-- Compartir destinos entre los equipos de una misma cuenta (fase 3 de
-- docs/compartir.md en el repositorio de la app).
--
-- Se comparte el lugar (las credenciales de un bucket o de un rest-server),
-- nunca un repositorio ni su contraseña. La web solo transporta sobres
-- sellados de libsodium (base64) cifrados en el equipo que comparte para la
-- clave pública X25519 del que lo pide: nunca ve credenciales.
--
-- - Las tablas tienen RLS y ningún permiso directo: solo las tocan las RPC.
-- - RPC de los equipos: con su secreto (como device_report) y no revocados.
-- - RPC de las personas: con sesión aal2.
-- - Cada petición avisa al momento (push) y no se entrega hasta pasados
--   5 minutos (not_before): da tiempo a cancelarla si no fuiste tú.
-- - Las peticiones caducan a las 24 h (pg_cron cada 15 min y al consultar).

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------

-- Clave pública X25519 de cada equipo (32 bytes en base64: 44 caracteres).
create table public.device_keys (
  device_id uuid primary key references public.devices on delete cascade,
  public_key text not null check (public_key ~ '^[A-Za-z0-9+/]{43}=$'),
  updated_at timestamptz not null default now()
);

-- Destinos compartidos: solo metadatos (nunca credenciales).
create table public.place_shares (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references auth.users on delete cascade,
  device_id uuid not null references public.devices on delete cascade,
  place_id text not null check (char_length(place_id) between 1 and 64),
  kind text not null check (kind in ('s3', 'b2', 'azure', 'gs', 'rest')),
  -- Servidor, sin usuario ni contraseña.
  host text check (host is null or (char_length(host) <= 200 and position('@' in host) = 0)),
  -- Bucket o ruta base, para mostrar (tampoco con credenciales).
  base text not null check (char_length(base) between 1 and 300 and position('@' in base) = 0),
  name text not null check (char_length(name) between 1 and 80),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (device_id, place_id)
);
create index place_shares_owner_idx on public.place_shares (owner);

-- Peticiones y entregas.
create table public.share_requests (
  id uuid primary key default gen_random_uuid(),
  share_id uuid not null references public.place_shares on delete cascade,
  requester_device uuid not null references public.devices on delete cascade,
  requested_by uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  -- Ventana para cancelar si no fuiste tú: no se entrega antes.
  not_before timestamptz not null default now() + interval '5 minutes',
  expires_at timestamptz not null default now() + interval '24 hours',
  status text not null default 'pending'
    check (status in ('pending', 'delivered', 'received', 'rejected', 'expired', 'cancelled')),
  -- Sobre sellado (base64); se borra al confirmar, rechazar, cancelar o caducar.
  ciphertext text check (ciphertext is null or (char_length(ciphertext) <= 8192 and ciphertext ~ '^[A-Za-z0-9+/]+={0,2}$')),
  reason text check (reason is null or char_length(reason) <= 300),
  delivered_at timestamptz,
  received_at timestamptz
);
create unique index share_requests_una_pendiente on public.share_requests (share_id, requester_device) where status = 'pending';
create index share_requests_share_idx on public.share_requests (share_id, status);
create index share_requests_requester_idx on public.share_requests (requester_device, status);
create index share_requests_user_idx on public.share_requests (requested_by, created_at desc);

alter table public.device_keys enable row level security;
alter table public.place_shares enable row level security;
alter table public.share_requests enable row level security;
-- Sin políticas ni permisos: solo las RPC (SECURITY DEFINER) las tocan.
revoke all on public.device_keys, public.place_shares, public.share_requests from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Utilidades internas
-- ---------------------------------------------------------------------------

-- El equipo, si su secreto es correcto y no está desvinculado (como device_report).
create or replace function public.device_auth(p_device uuid, p_secret text)
returns public.devices
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_sec public.device_secrets;
  v_dev public.devices;
begin
  select * into v_sec from public.device_secrets where device_id = p_device;
  if not found or v_sec.secret_hash <> encode(extensions.digest(coalesce(p_secret, ''), 'sha256'), 'hex') then
    raise exception 'Equipo no autorizado' using errcode = '42501';
  end if;
  select * into v_dev from public.devices where id = p_device;
  if v_dev.revoked_at is not null then
    raise exception 'Equipo desvinculado' using errcode = '42501';
  end if;
  return v_dev;
end;
$$;

-- Sesión de una persona con verificación en dos pasos.
create or replace function public.require_aal2()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_mfa() then
    raise exception 'Inicia sesión con la verificación en dos pasos para continuar.' using errcode = '42501';
  end if;
  return auth.uid();
end;
$$;

-- Lanza ya la revisión de avisos (push inmediato), sin esperar a pg_cron.
-- Si falla, el aviso llega igual en la siguiente vuelta (como mucho 10 min).
create or replace function public.notify_now()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://ltuqkovbkmhlyjhsbuff.supabase.co/functions/v1/notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'notify_cron')
    ),
    body := '{}'::jsonb
  );
exception when others then
  raise warning 'notify_now: %', sqlerrm;
end;
$$;

-- Caducan las peticiones pasadas de plazo (y se borra su sobre).
create or replace function public.share_expire()
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update public.share_requests
  set status = 'expired', ciphertext = null
  where status in ('pending', 'delivered') and expires_at < now();
$$;

revoke all on function public.device_auth(uuid, text) from public, anon, authenticated;
revoke all on function public.require_aal2() from public, anon, authenticated;
revoke all on function public.notify_now() from public, anon, authenticated;
revoke all on function public.share_expire() from public, anon, authenticated;

select cron.schedule('resguardo-compartir-caducar', '*/15 * * * *', $$ select public.share_expire() $$);

-- Destino de un repositorio (la de 20260930090000_destinos.sql) con "shared"
-- (solo si es booleano).
create or replace function public.clean_place(p jsonb)
returns jsonb language sql stable set search_path = '' as $$
  select case
    when jsonb_typeof(p) <> 'object'
      or coalesce(p ->> 'id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then null
    else jsonb_build_object(
      'id', lower(p ->> 'id'),
      'name', left(coalesce(nullif(trim(p ->> 'name'), ''), 'Destino'), 80),
      'kind', case when p ->> 'kind' in ('s3', 'b2', 'azure', 'gs', 'rest', 'sftp', 'local', 'rclone', 'other')
        then p ->> 'kind' else 'other' end)
      || case when jsonb_typeof(p -> 'shared') = 'boolean' then jsonb_build_object('shared', p -> 'shared') else '{}'::jsonb end
  end;
$$;

revoke all on function public.clean_place(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPC de los equipos (con su secreto)
-- ---------------------------------------------------------------------------

-- Publica (o cambia) la clave pública X25519 del equipo.
create or replace function public.device_set_key(p_device uuid, p_secret text, p_public_key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
begin
  if coalesce(p_public_key, '') !~ '^[A-Za-z0-9+/]{43}=$' then
    raise exception 'Clave pública no válida (32 bytes en base64)';
  end if;
  if length(decode(p_public_key, 'base64')) <> 32 then
    raise exception 'Clave pública no válida (32 bytes en base64)';
  end if;
  insert into public.device_keys (device_id, public_key, updated_at)
  values (v_dev.id, p_public_key, now())
  on conflict (device_id) do update set public_key = excluded.public_key, updated_at = now();
end;
$$;

-- Empieza a compartir un destino (con sus metadatos) o deja de hacerlo (null).
create or replace function public.place_share_set(p_device uuid, p_secret text, p_place_id text, p_meta jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
  v_id uuid;
  v_host text;
  v_base text;
begin
  if coalesce(p_place_id, '') = '' or char_length(p_place_id) > 64 then
    raise exception 'Destino no válido';
  end if;

  if p_meta is null or jsonb_typeof(p_meta) = 'null' then
    -- Dejar de compartir: lo pendiente o entregado sin confirmar se rechaza y se borra.
    update public.place_shares set revoked_at = now()
    where device_id = v_dev.id and place_id = p_place_id and revoked_at is null
    returning id into v_id;
    if v_id is not null then
      update public.share_requests
      set status = 'rejected', reason = 'Ya no se comparte', ciphertext = null
      where share_id = v_id and status in ('pending', 'delivered');
    end if;
    return null;
  end if;

  if jsonb_typeof(p_meta) <> 'object' or coalesce(p_meta ->> 'kind', '') not in ('s3', 'b2', 'azure', 'gs', 'rest') then
    raise exception 'Tipo de destino no válido';
  end if;
  v_host := nullif(trim(p_meta ->> 'host'), '');
  v_base := nullif(trim(p_meta ->> 'base'), '');
  if v_base is null then
    raise exception 'Falta la ruta base del destino';
  end if;
  -- Nunca credenciales en los metadatos («usuario:clave@servidor»).
  if position('@' in coalesce(v_host, '')) > 0 or position('@' in v_base) > 0 then
    raise exception 'El servidor o la ruta llevan credenciales: no se comparten';
  end if;

  insert into public.place_shares (owner, device_id, place_id, kind, host, base, name)
  values (
    v_dev.owner, v_dev.id, p_place_id, p_meta ->> 'kind', left(v_host, 200), left(v_base, 300),
    left(coalesce(nullif(trim(p_meta ->> 'name'), ''), 'Destino'), 80)
  )
  on conflict (device_id, place_id) do update set
    owner = excluded.owner,
    kind = excluded.kind,
    host = excluded.host,
    base = excluded.base,
    name = excluded.name,
    revoked_at = null
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end;
$$;

-- Peticiones maduras de mis destinos compartidos (para entregar o rechazar).
create or replace function public.share_pending(p_device uuid, p_secret text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
begin
  perform public.share_expire();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'request_id', q.id,
      'share_id', s.id,
      'place_id', s.place_id,
      'requester_device', rd.id,
      'requester_name', rd.name,
      'requester_public_key', k.public_key,
      'requester_linked_at', rd.created_at,
      'created_at', q.created_at
    ) order by q.created_at)
    from public.share_requests q
    join public.place_shares s on s.id = q.share_id
    join public.devices rd on rd.id = q.requester_device
    left join public.device_keys k on k.device_id = rd.id
    where s.device_id = v_dev.id
      and s.revoked_at is null
      and q.status = 'pending'
      and now() between q.not_before and q.expires_at
      and rd.revoked_at is null
      and rd.owner = s.owner
  ), '[]'::jsonb);
end;
$$;

-- Entrega el sobre sellado de una petición madura de mi destino compartido.
create or replace function public.share_deliver(p_device uuid, p_secret text, p_request uuid, p_ciphertext text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
  v_n integer;
begin
  if coalesce(p_ciphertext, '') !~ '^[A-Za-z0-9+/]+={0,2}$' or char_length(p_ciphertext) > 8192 then
    raise exception 'Sobre no válido';
  end if;
  update public.share_requests q
  set status = 'delivered', ciphertext = p_ciphertext, delivered_at = now()
  from public.place_shares s, public.devices rd
  where q.id = p_request
    and s.id = q.share_id and s.device_id = v_dev.id and s.revoked_at is null
    and rd.id = q.requester_device and rd.revoked_at is null and rd.owner = s.owner
    and q.status = 'pending'
    and now() between q.not_before and q.expires_at;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Esa petición no se puede entregar (no es tuya, no está pendiente o aún no ha madurado)';
  end if;
  -- Aviso: «"<equipo>" recibió el destino "<nombre>"».
  perform public.notify_now();
end;
$$;

-- Rechaza una petición de mi destino compartido.
create or replace function public.share_reject(p_device uuid, p_secret text, p_request uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
  v_n integer;
begin
  update public.share_requests q
  set status = 'rejected',
      ciphertext = null,
      reason = nullif(left(trim(regexp_replace(coalesce(p_reason, ''), '[[:cntrl:]]+', ' ', 'g')), 300), '')
  from public.place_shares s
  where q.id = p_request and s.id = q.share_id and s.device_id = v_dev.id and q.status = 'pending';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Esa petición no se puede rechazar (no es tuya o ya no está pendiente)';
  end if;
end;
$$;

-- Sobres entregados a este equipo, pendientes de abrir y confirmar.
create or replace function public.share_inbox(p_device uuid, p_secret text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
begin
  perform public.share_expire();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'request_id', q.id,
      'share_id', s.id,
      'ciphertext', q.ciphertext,
      'from_device_name', sd.name,
      'meta', jsonb_build_object('kind', s.kind, 'host', s.host, 'base', s.base, 'name', s.name)
    ) order by q.delivered_at)
    from public.share_requests q
    join public.place_shares s on s.id = q.share_id
    join public.devices sd on sd.id = s.device_id
    where q.requester_device = v_dev.id and q.status = 'delivered' and q.ciphertext is not null
  ), '[]'::jsonb);
end;
$$;

-- Confirma que el sobre llegó: se borra de la web.
create or replace function public.share_ack(p_device uuid, p_secret text, p_request uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
  v_n integer;
begin
  update public.share_requests
  set status = 'received', received_at = now(), ciphertext = null
  where id = p_request and requester_device = v_dev.id and status = 'delivered';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Esa entrega no es de este equipo o ya se confirmó';
  end if;
end;
$$;

revoke all on function public.device_set_key(uuid, text, text) from public;
revoke all on function public.place_share_set(uuid, text, text, jsonb) from public;
revoke all on function public.share_pending(uuid, text) from public;
revoke all on function public.share_deliver(uuid, text, uuid, text) from public;
revoke all on function public.share_reject(uuid, text, uuid, text) from public;
revoke all on function public.share_inbox(uuid, text) from public;
revoke all on function public.share_ack(uuid, text, uuid) from public;
grant execute on function public.device_set_key(uuid, text, text) to anon, authenticated;
grant execute on function public.place_share_set(uuid, text, text, jsonb) to anon, authenticated;
grant execute on function public.share_pending(uuid, text) to anon, authenticated;
grant execute on function public.share_deliver(uuid, text, uuid, text) to anon, authenticated;
grant execute on function public.share_reject(uuid, text, uuid, text) to anon, authenticated;
grant execute on function public.share_inbox(uuid, text) to anon, authenticated;
grant execute on function public.share_ack(uuid, text, uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPC de las personas (sesión aal2)
-- ---------------------------------------------------------------------------

-- Destinos que comparten mis equipos.
create or replace function public.shares_list()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.require_aal2();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', s.id,
      'device_id', s.device_id,
      'device_name', d.name,
      'kind', s.kind,
      'host', s.host,
      'base', s.base,
      'name', s.name,
      'created_at', s.created_at
    ) order by s.name, d.name)
    from public.place_shares s
    join public.devices d on d.id = s.device_id and d.revoked_at is null
    where s.owner = v_owner and s.revoked_at is null
  ), '[]'::jsonb);
end;
$$;

-- Pide un destino compartido para uno de mis equipos.
create or replace function public.share_request(p_share uuid, p_device uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.require_aal2();
  v_share public.place_shares;
  v_id uuid;
  v_nb timestamptz;
begin
  select * into v_share from public.place_shares s
  where s.id = p_share and s.owner = v_owner and s.revoked_at is null
    and exists (select 1 from public.devices d where d.id = s.device_id and d.revoked_at is null);
  if not found then
    raise exception 'Ese destino ya no se comparte.';
  end if;
  if not exists (select 1 from public.devices d where d.id = p_device and d.owner = v_owner and d.revoked_at is null) then
    raise exception 'Equipo no encontrado.';
  end if;
  if p_device = v_share.device_id then
    raise exception 'Ese equipo ya tiene este destino: es el que lo comparte.';
  end if;

  -- 10 por persona y hora (una petición a la vez por cuenta, para contar bien).
  perform pg_advisory_xact_lock(hashtextextended('share_request:' || v_owner::text, 0));
  if (select count(*) from public.share_requests q
      where q.requested_by = v_owner and q.created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Demasiadas peticiones; espera un rato.';
  end if;

  begin
    insert into public.share_requests (share_id, requester_device, requested_by)
    values (p_share, p_device, v_owner)
    returning id, not_before into v_id, v_nb;
  exception when unique_violation then
    raise exception 'Ya lo has pedido; llegará en unos minutos.';
  end;

  -- Aviso inmediato: «"<equipo>" pidió el destino "<nombre>"…».
  perform public.notify_now();
  return jsonb_build_object('id', v_id, 'not_before', v_nb);
end;
$$;

-- Mis peticiones, las más recientes primero.
create or replace function public.share_requests_mine()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.require_aal2();
begin
  return coalesce((
    select jsonb_agg(x order by (x ->> 'created_at') desc)
    from (
      select jsonb_build_object(
        'id', q.id,
        'share_id', q.share_id,
        'status', case when q.status in ('pending', 'delivered') and q.expires_at < now() then 'expired' else q.status end,
        'reason', q.reason,
        'not_before', q.not_before,
        'created_at', q.created_at,
        'expires_at', q.expires_at,
        'delivered_at', q.delivered_at,
        'received_at', q.received_at,
        'share_name', s.name,
        'from_device_name', sd.name,
        'requester_device', q.requester_device,
        'requester_name', rd.name
      ) as x
      from public.share_requests q
      join public.place_shares s on s.id = q.share_id
      join public.devices sd on sd.id = s.device_id
      join public.devices rd on rd.id = q.requester_device
      where q.requested_by = v_owner
      order by q.created_at desc
      limit 200
    ) t
  ), '[]'::jsonb);
end;
$$;

-- Cancela una petición mía que aún no se ha entregado.
create or replace function public.share_cancel(p_request uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := public.require_aal2();
  v_n integer;
begin
  update public.share_requests
  set status = 'cancelled', ciphertext = null
  where id = p_request and requested_by = v_owner and status = 'pending';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Esa petición ya no se puede cancelar (se entregó, caducó o no es tuya).';
  end if;
end;
$$;

revoke all on function public.shares_list() from public, anon;
revoke all on function public.share_request(uuid, uuid) from public, anon;
revoke all on function public.share_requests_mine() from public, anon;
revoke all on function public.share_cancel(uuid) from public, anon;
grant execute on function public.shares_list() to authenticated;
grant execute on function public.share_request(uuid, uuid) to authenticated;
grant execute on function public.share_requests_mine() to authenticated;
grant execute on function public.share_cancel(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Avisos: la de 20260930060000_proteccion.sql, con los de los destinos
-- compartidos (petición al momento; entrega, durante 24 h).
-- ---------------------------------------------------------------------------

create or replace function public.current_alerts()
returns table (owner uuid, alert_key text, level text, title text, body text, url text)
language sql
stable
security definer
set search_path = ''
as $$
  with repo_status as (
    select
      r.owner, r.device_id, r.repo_id, r.name as repo_name, d.name as device_name,
      least(greatest(coalesce(
        r.expected_hours,
        case r.schedule ->> 'kind'
          when 'hours' then public.try_int(r.schedule ->> 'every', 1, 8760)
          when 'monitor' then public.try_int(r.schedule ->> 'every', 1, 8760)
          when 'weekly' then 168
          else 24
        end,
        24
      ), 1), 8760) as expected,
      -- Última revisión correcta (versión o copia sin cambios), no solo la última versión.
      public.last_ok_at(r.last_snapshot_at, r.last_run, r.plans) as last_at,
      r.last_run ->> 'result' as last_result,
      r.last_run ->> 'message' as last_message,
      -- En pausa ahora: sin fecha de fin o con la fecha aún por llegar.
      (r.paused and (r.paused_until is null or r.paused_until > now())) as paused_now,
      -- Fin de la última pausa: el retraso se cuenta desde aquí.
      case when r.paused then r.paused_until else r.resumed_at end as pause_ended
    from public.repos r
    join public.devices d on d.id = r.device_id and d.revoked_at is null
  )
  select
    owner,
    'repo:' || device_id || ':' || repo_id,
    lvl,
    case lvl
      when 'failed' then 'Falló la copia de ' || repo_name
      when 'overdue' then repo_name || ' está atrasada'
      when 'late' then repo_name || ' va con retraso'
      else repo_name || ' vuelve a estar al día'
    end,
    case lvl
      when 'failed' then device_name || ': ' || left(coalesce(last_message, 'error en la última copia'), 140)
      when 'ok' then device_name || ': última copia ' || coalesce(to_char(last_at at time zone 'America/Bogota', 'DD/MM HH24:MI'), '—')
      else device_name || ': sin copias desde ' || to_char(last_at at time zone 'America/Bogota', 'DD/MM HH24:MI')
    end,
    -- Solo identificadores con caracteres seguros en la dirección; si no, al inicio.
    case when repo_id ~ '^[A-Za-z0-9_.-]+$' then '/repo/' || device_id || '/' || repo_id else '/' end
  from (
    select *,
      case
        when last_result = 'error' then 'failed'
        when last_at is null then 'ok'
        when now() - greatest(last_at, pause_ended) > make_interval(hours => expected * 2 + 1) then 'overdue'
        when now() - greatest(last_at, pause_ended) > make_interval(hours => ceil(expected * 1.25)::int + 1) then 'late'
        else 'ok'
      end as lvl
    from repo_status
  ) s
  -- En pausa no hay aviso de retraso (ni de "vuelve a estar al día"): la fila
  -- desaparece y el estado anterior se olvida sin notificar. Un fallo sí sigue.
  where not (paused_now and lvl <> 'failed')
  union all
  select
    d.owner,
    'device:' || d.id,
    case when d.last_seen_at < now() - interval '60 minutes' then 'offline' else 'ok' end,
    case when d.last_seen_at < now() - interval '60 minutes'
      then d.name || ' no se ha conectado'
      else d.name || ' vuelve a estar conectado' end,
    case when d.last_seen_at < now() - interval '60 minutes'
      then 'Último contacto: ' || to_char(d.last_seen_at at time zone 'America/Bogota', 'DD/MM HH24:MI')
      else 'El equipo vuelve a enviar su estado.' end,
    '/'
  from public.devices d
  where d.revoked_at is null and d.last_seen_at is not null
  union all
  -- Verificación: aviso si falla y cuando vuelve a salir bien.
  select
    r.owner,
    'verify:' || r.device_id || ':' || r.repo_id,
    case when r.verify_run ->> 'result' = 'error' then 'failed' else 'ok' end,
    case when r.verify_run ->> 'result' = 'error'
      then 'Falló la verificación de ' || r.name
      else r.name || ': la verificación vuelve a estar bien' end,
    d.name || ': ' || left(coalesce(r.verify_run ->> 'message', ''), 140),
    case when r.repo_id ~ '^[A-Za-z0-9_.-]+$' then '/repo/' || r.device_id || '/' || r.repo_id else '/' end
  from public.repos r
  join public.devices d on d.id = r.device_id and d.revoked_at is null
  where r.maintenance -> 'verify' is not null and r.verify_run is not null
  union all
  -- Verificación de la copia en la nube: igual que la local.
  select
    r.owner,
    'verify_offsite:' || r.device_id || ':' || r.repo_id,
    case when r.offsite_verify_run ->> 'result' = 'error' then 'failed' else 'ok' end,
    case when r.offsite_verify_run ->> 'result' = 'error'
      then 'La verificación de la copia en la nube de «' || r.name || '» falló'
      else r.name || ': la verificación de la nube vuelve a estar bien' end,
    d.name || ': ' || left(coalesce(r.offsite_verify_run ->> 'message', ''), 140),
    case when r.repo_id ~ '^[A-Za-z0-9_.-]+$' then '/repo/' || r.device_id || '/' || r.repo_id else '/' end
  from public.repos r
  join public.devices d on d.id = r.device_id and d.revoked_at is null
  where jsonb_typeof(r.maintenance -> 'offsite' -> 'verify') = 'object' and r.offsite_verify_run is not null
  union all
  -- Prueba de restauración: igual que la verificación.
  select
    r.owner,
    'restore_test:' || r.device_id || ':' || r.repo_id,
    case when r.restore_test_run ->> 'result' = 'error' then 'failed' else 'ok' end,
    case when r.restore_test_run ->> 'result' = 'error'
      then 'La prueba de restauración de «' || r.name || '» falló'
      else r.name || ': la prueba de restauración vuelve a salir bien' end,
    d.name || ': ' || left(coalesce(r.restore_test_run ->> 'message', ''), 140),
    case when r.repo_id ~ '^[A-Za-z0-9_.-]+$' then '/repo/' || r.device_id || '/' || r.repo_id else '/' end
  from public.repos r
  join public.devices d on d.id = r.device_id and d.revoked_at is null
  where jsonb_typeof(r.maintenance -> 'restore_test') = 'object' and r.restore_test_run is not null
  union all
  -- Copia externa: aviso si falla o si lleva más del doble de lo previsto sin subir.
  select owner, 'offsite:' || device_id || ':' || repo_id, lvl,
    case lvl
      when 'failed' then 'Falló la copia externa de ' || repo_name
      when 'overdue' then 'La copia externa de ' || repo_name || ' está atrasada'
      else repo_name || ': la copia externa vuelve a estar al día' end,
    case lvl
      when 'failed' then device_name || ': ' || left(coalesce(message, ''), 140)
      else device_name || ': última subida ' || coalesce(to_char(last_at at time zone 'America/Bogota', 'DD/MM HH24:MI'), 'nunca') end,
    case when repo_id ~ '^[A-Za-z0-9_.-]+$' then '/repo/' || device_id || '/' || repo_id else '/' end
  from (
    select r.owner, r.device_id, r.repo_id, r.name as repo_name, d.name as device_name,
      (r.paused and (r.paused_until is null or r.paused_until > now())) as paused_now,
      r.offsite_hold is not null as held,
      r.offsite_run ->> 'message' as message,
      public.try_ts(r.offsite_run ->> 'finished') as last_at,
      case
        when r.offsite_run ->> 'result' = 'error' then 'failed'
        when r.task_running ->> 'kind' = 'offsite' then 'ok'
        -- «Después de cada copia con cambios»: atrasada solo si hay una versión
        -- más nueva que la última subida que lleva más de 6 h (más la espera
        -- configurada) sin subir. Sin versiones nuevas no hay nada que subir.
        when r.maintenance -> 'offsite' -> 'schedule' ->> 'kind' = 'after_backup' then
          case when public.try_ts(r.offsite_run ->> 'finished') is not null
            and exists (
              select 1 from public.snapshots s
              where s.device_id = r.device_id and s.repo_id = r.repo_id
                and s.time > public.try_ts(r.offsite_run ->> 'finished')
                and s.time < now() - make_interval(hours => 6,
                  mins => coalesce(public.try_int(r.maintenance -> 'offsite' -> 'schedule' ->> 'min_minutes', 0, 1440), 0))
            )
            -- Tras una pausa, el mismo margen desde que terminó.
            and coalesce(case when r.paused then r.paused_until else r.resumed_at end, '-infinity'::timestamptz)
              < now() - make_interval(hours => 6,
                mins => coalesce(public.try_int(r.maintenance -> 'offsite' -> 'schedule' ->> 'min_minutes', 0, 1440), 0))
          then 'overdue' else 'ok' end
        when public.try_ts(r.offsite_run ->> 'finished') is not null
          and now() - greatest(public.try_ts(r.offsite_run ->> 'finished'),
            case when r.paused then r.paused_until else r.resumed_at end) > make_interval(hours => least(greatest(coalesce(
            case r.maintenance -> 'offsite' -> 'schedule' ->> 'kind'
              when 'hours' then public.try_int(r.maintenance -> 'offsite' -> 'schedule' ->> 'every', 1, 8760)
              when 'weekly' then 168 else 24 end, 24), 1), 8760) * 2 + 1)
          then 'overdue'
        else 'ok'
      end as lvl
    from public.repos r
    join public.devices d on d.id = r.device_id and d.revoked_at is null
    where r.maintenance -> 'offsite' is not null and r.offsite_run is not null
  ) o
  -- En pausa, igual que arriba: solo se avisa de un fallo. Con la subida
  -- frenada por un cambio inusual, tampoco (ya hay un aviso más grave).
  where not ((paused_now or held) and lvl <> 'failed')
  union all
  -- Cambio inusual: el equipo frena la subida a la nube hasta que se revise.
  -- Aviso de seguridad (no de retraso): la pausa no lo oculta.
  select r.owner, 'hold:' || r.device_id || ':' || r.repo_id,
    case when r.offsite_hold is not null then 'critical' else 'ok' end,
    case when r.offsite_hold is not null
      then 'Cambio inusual en «' || r.name || '» (' || d.name || ')'
      else 'Subida a la nube reanudada: ' || r.name end,
    case when r.offsite_hold is not null then
      'La copia'
      || coalesce(' «' || nullif(r.offsite_hold ->> 'plan_name', '') || '»', '')
      || coalesce(' del ' || to_char(public.try_ts(r.offsite_hold ->> 'since') at time zone 'America/Bogota', 'DD/MM "a las" HH24:MI'), '')
      || ' añadió '
      || coalesce(nullif(concat_ws(' y ',
           public.fmt_bytes_es(public.try_bigint(r.offsite_hold ->> 'data_added')),
           public.fmt_int_es(public.try_bigint(r.offsite_hold ->> 'files')) || ' archivos'), ''),
         'mucho más de lo normal')
      || coalesce(' (lo normal: ' || nullif(concat_ws(' y ',
           '~' || public.fmt_bytes_es(public.try_bigint(r.offsite_hold ->> 'typical_bytes')),
           '~' || public.fmt_int_es(public.try_bigint(r.offsite_hold ->> 'typical_files'))), '') || ')', '')
      || '. La subida a la nube está frenada. Revisa en Resguardo.'
    else d.name || ': ya no hay un cambio inusual pendiente de revisar.' end,
    case when r.repo_id ~ '^[A-Za-z0-9_.-]+$' then '/repo/' || r.device_id || '/' || r.repo_id else '/' end
  from public.repos r
  join public.devices d on d.id = r.device_id and d.revoked_at is null
  where r.offsite_hold is not null or r.maintenance -> 'offsite' is not null
  union all
  -- Destinos compartidos: alguien pidió un destino. Aviso al momento (la
  -- entrega espera 5 min: da tiempo a cancelarla si no fuiste tú).
  select s.owner, 'sharereq:' || q.id, 'notice',
    '«' || rd.name || '» pidió el destino «' || s.name || '»',
    'Se entregará en unos minutos. Si no fuiste tú, cancélalo en Cuenta › Destinos compartidos y cambia tu contraseña.',
    '/cuenta/compartidos'
  from public.share_requests q
  join public.place_shares s on s.id = q.share_id
  join public.devices rd on rd.id = q.requester_device
  where q.status = 'pending' and q.expires_at > now()
  union all
  -- …y cuando se entrega (durante 24 h).
  select s.owner, 'sharedel:' || q.id, 'notice',
    '«' || rd.name || '» recibió el destino «' || s.name || '»',
    'Lo entregó «' || sd.name || '». Si no lo esperabas, deja de compartirlo y rota la clave en el proveedor.',
    '/cuenta/compartidos'
  from public.share_requests q
  join public.place_shares s on s.id = q.share_id
  join public.devices rd on rd.id = q.requester_device
  join public.devices sd on sd.id = s.device_id
  where q.status in ('delivered', 'received') and q.delivered_at > now() - interval '24 hours';
$$;

revoke all on function public.current_alerts() from public, anon, authenticated;
