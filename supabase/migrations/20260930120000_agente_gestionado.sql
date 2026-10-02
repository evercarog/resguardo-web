-- Resguardo Agente: equipos gestionados (fase 5, docs/agente-gestionado.md en
-- el repositorio de la app).
--
-- La web solo hace de relevo: guarda la clave pública Ed25519 de la consola,
-- empareja con un código de un solo uso (solo su hash) y transporta sobres
-- sellados y firmados por la consola. No puede inventar órdenes: el agente
-- fija la clave de la consola al emparejar y se comprueba con un SAS de 6
-- cifras a ojo en los dos lados.
--
-- Decisiones sobre el contrato del documento:
-- - managed_pairing_join crea el equipo del agente (como device_pair: un
--   agente nuevo aún no tiene identidad) en la cuenta y el cliente de la
--   consola, y devuelve su device_id y su secreto una sola vez. Toma además
--   p_name, p_os y p_app_version. Es anónima. Un código fallido NO lanza
--   error (se desharía el registro del intento): devuelve
--   {"error": "codigo", "message": ...}. Pasado el límite, sí lanza error.
-- - Límite de intentos fallidos cada 10 minutos: 10 por IP (solo su huella)
--   y 100 en total; y 5 con el mismo hash invalidan esa vinculación. Los
--   códigos son de un solo uso y caducan a los 15 min.
-- - El equipo unido no queda gestionado hasta que la consola confirma el SAS
--   (devices.managed_by). Si no confirma a tiempo (15 min desde que se une),
--   o lo cancela con managed_pairing_cancel (extra), el equipo se borra.
-- - endpoint_device es «on delete set null» para poder quitar el equipo
--   desde la web.
-- - Solo la consola de una vinculación confirmada manda al agente con
--   managed_by = esa consola. seq siempre crece (la limpieza guarda el
--   último mensaje de cada agente).
-- - La web no da órdenes a un agente: device_report no permite copias a
--   distancia en un equipo gestionado.

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------

alter table public.devices
  -- La consola que gestiona este equipo (tras confirmar el SAS). Solo lo pone la web.
  add column managed_by uuid references public.devices on delete set null,
  -- Lo que informa el agente: { console_device, seq, service }.
  add column managed jsonb;
create index devices_managed_by_idx on public.devices (managed_by) where managed_by is not null;

create table public.managed_consoles (
  device_id uuid primary key references public.devices on delete cascade,
  -- Ed25519, 32 bytes en base64.
  sign_public_key text not null check (sign_public_key ~ '^[A-Za-z0-9+/]{43}=$'),
  updated_at timestamptz not null default now()
);

create table public.managed_pairings (
  id uuid primary key default gen_random_uuid(),
  console_device uuid not null references public.devices on delete cascade,
  -- sha256(código) en hexadecimal, nunca el código.
  code_hash text not null check (code_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '15 minutes',
  endpoint_device uuid references public.devices on delete set null,
  -- X25519 del agente, 32 bytes en base64.
  endpoint_box_key text check (endpoint_box_key is null or endpoint_box_key ~ '^[A-Za-z0-9+/]{43}=$'),
  -- Intentos fallidos con este mismo hash (a los 5 deja de valer).
  failures integer not null default 0,
  status text not null default 'open' check (status in ('open', 'joined', 'confirmed', 'expired'))
);
create unique index managed_pairings_codigo_abierto on public.managed_pairings (code_hash) where status = 'open';
create index managed_pairings_console_idx on public.managed_pairings (console_device, status);
create index managed_pairings_endpoint_idx on public.managed_pairings (endpoint_device) where endpoint_device is not null;

create table public.managed_messages (
  id uuid primary key default gen_random_uuid(),
  console_device uuid not null references public.devices on delete cascade,
  endpoint_device uuid not null references public.devices on delete cascade,
  seq bigint not null check (seq > 0),
  -- Sobre sellado (base64) de {payload, firma}.
  ciphertext text not null check (length(ciphertext) <= 65536 and ciphertext ~ '^[A-Za-z0-9+/]+={0,2}$'),
  created_at timestamptz not null default now(),
  taken_at timestamptz,
  unique (endpoint_device, seq)
);
create index managed_messages_pendientes on public.managed_messages (endpoint_device, seq) where taken_at is null;

-- Intentos fallidos de unirse (huella de la IP, nunca la IP).
create table public.managed_join_failures (
  ip_hash text not null,
  at timestamptz not null default now()
);
create index managed_join_failures_idx on public.managed_join_failures (at, ip_hash);

alter table public.managed_consoles enable row level security;
alter table public.managed_pairings enable row level security;
alter table public.managed_messages enable row level security;
alter table public.managed_join_failures enable row level security;
-- Sin políticas ni permisos: solo las RPC (SECURITY DEFINER) las tocan.
revoke all on public.managed_consoles, public.managed_pairings, public.managed_messages,
  public.managed_join_failures from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Utilidades internas
-- ---------------------------------------------------------------------------

-- 32 bytes en base64 (Ed25519 o X25519).
create or replace function public.is_key32(p text)
returns boolean language plpgsql immutable set search_path = '' as $$
begin
  return coalesce(p, '') ~ '^[A-Za-z0-9+/]{43}=$' and length(decode(p, 'base64')) = 32;
exception when others then
  return false;
end;
$$;

-- Informe del agente: solo campos conocidos.
create or replace function public.clean_managed(p jsonb)
returns jsonb language sql stable set search_path = '' as $$
  select case
    when jsonb_typeof(p) is distinct from 'object' then null
    else jsonb_build_object(
      'console_device', case when coalesce(p ->> 'console_device', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then lower(p ->> 'console_device') end,
      'seq', public.try_bigint(p ->> 'seq'),
      'service', case when p ->> 'service' in ('running', 'stopped_by_admin') then p ->> 'service' end
    )
  end;
$$;

-- Caducan las vinculaciones pasadas de plazo; los equipos unidos sin
-- confirmar se borran. Se limpian los mensajes tomados (o viejos) salvo el
-- último de cada agente, y los intentos fallidos de hace más de un día.
create or replace function public.managed_expire()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_gone uuid[];
begin
  with x as (
    update public.managed_pairings
    set status = 'expired'
    where status in ('open', 'joined') and expires_at < now()
    returning endpoint_device
  )
  select array_agg(endpoint_device) into v_gone from x where endpoint_device is not null;
  -- Unidos sin confirmar: el equipo creado al unirse sobra (nunca uno gestionado).
  if v_gone is not null then
    delete from public.devices d where d.id = any (v_gone) and d.managed_by is null;
  end if;

  delete from public.managed_pairings where status = 'expired' and expires_at < now() - interval '7 days';

  delete from public.managed_messages m
  where (m.taken_at < now() - interval '7 days' or m.created_at < now() - interval '30 days')
    and m.seq < (select max(m2.seq) from public.managed_messages m2 where m2.endpoint_device = m.endpoint_device);

  delete from public.managed_join_failures where at < now() - interval '1 day';
end;
$$;

-- Huella de la IP de la petición (para limitar intentos sin guardar la IP).
create or replace function public.request_ip_hash()
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_h jsonb;
  v_ip text;
begin
  begin
    v_h := current_setting('request.headers', true)::jsonb;
  exception when others then
    v_h := null;
  end;
  v_ip := coalesce(
    nullif(trim(v_h ->> 'cf-connecting-ip'), ''),
    nullif(trim(split_part(v_h ->> 'x-forwarded-for', ',', 1)), ''),
    nullif(trim(v_h ->> 'x-real-ip'), ''),
    'desconocida'
  );
  return encode(extensions.digest('resguardo-ip:' || left(v_ip, 64), 'sha256'), 'hex');
end;
$$;

revoke all on function public.is_key32(text) from public, anon, authenticated;
revoke all on function public.clean_managed(jsonb) from public, anon, authenticated;
revoke all on function public.managed_expire() from public, anon, authenticated;
revoke all on function public.request_ip_hash() from public, anon, authenticated;

select cron.schedule('resguardo-gestionados-limpiar', '*/15 * * * *', $$ select public.managed_expire() $$);

-- ---------------------------------------------------------------------------
-- RPC de la consola
-- ---------------------------------------------------------------------------

-- Publica (o cambia) la clave Ed25519 de la consola.
create or replace function public.managed_console_set_key(p_device uuid, p_secret text, p_public_key text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
begin
  if v_dev.managed_by is not null then
    raise exception 'Un equipo gestionado no puede ser consola';
  end if;
  if not public.is_key32(p_public_key) then
    raise exception 'Clave pública no válida (32 bytes en base64)';
  end if;
  insert into public.managed_consoles (device_id, sign_public_key, updated_at)
  values (v_dev.id, p_public_key, now())
  on conflict (device_id) do update set sign_public_key = excluded.sign_public_key, updated_at = now();
end;
$$;

-- Abre una vinculación con el hash del código que muestra la consola.
create or replace function public.managed_pairing_open(p_device uuid, p_secret text, p_code_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
  v_hash text := lower(coalesce(p_code_hash, ''));
  v_id uuid;
  v_expires timestamptz;
begin
  if v_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Código no válido (sha256 en hexadecimal)';
  end if;
  if not exists (select 1 from public.managed_consoles c where c.device_id = v_dev.id) then
    raise exception 'Publica antes la clave de la consola (managed_console_set_key)';
  end if;
  perform public.managed_expire();
  perform pg_advisory_xact_lock(hashtextextended('managed_pairing_open:' || v_dev.id::text, 0));
  if (select count(*) from public.managed_pairings p
      where p.console_device = v_dev.id and p.status in ('open', 'joined')) >= 5 then
    raise exception 'Ya hay 5 vinculaciones abiertas. Espera a que caduquen (15 minutos).';
  end if;
  if (select count(*) from public.managed_pairings p
      where p.console_device = v_dev.id and p.created_at > now() - interval '1 hour') >= 20 then
    raise exception 'Demasiadas vinculaciones en la última hora. Espera un poco.';
  end if;
  begin
    insert into public.managed_pairings (console_device, code_hash)
    values (v_dev.id, v_hash)
    returning id, expires_at into v_id, v_expires;
  exception when unique_violation then
    raise exception 'Ese código ya está en uso. Genera otro.';
  end;
  return jsonb_build_object('id', v_id, 'expires_at', v_expires);
end;
$$;

-- Estado de una vinculación de esta consola.
create or replace function public.managed_pairing_status(p_device uuid, p_secret text, p_pairing uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
  v_r jsonb;
begin
  perform public.managed_expire();
  select jsonb_build_object(
    'status', p.status,
    'endpoint_device', p.endpoint_device,
    'endpoint_name', e.name,
    'endpoint_box_key', p.endpoint_box_key,
    'expires_at', p.expires_at
  ) into v_r
  from public.managed_pairings p
  left join public.devices e on e.id = p.endpoint_device
  where p.id = p_pairing and p.console_device = v_dev.id;
  if v_r is null then
    raise exception 'Vinculación no encontrada';
  end if;
  return v_r;
end;
$$;

-- La consola confirma, tras comprobar el SAS a ojo, que el agente es el suyo.
create or replace function public.managed_pairing_confirm(p_device uuid, p_secret text, p_pairing uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
  v_p public.managed_pairings;
begin
  perform public.managed_expire();
  select * into v_p from public.managed_pairings
  where id = p_pairing and console_device = v_dev.id
  for update;
  if not found or v_p.status <> 'joined' or v_p.endpoint_device is null or v_p.expires_at < now() then
    raise exception 'Esa vinculación no se puede confirmar (no es de esta consola, nadie se ha unido o caducó)';
  end if;
  update public.devices
  set managed_by = v_dev.id
  where id = v_p.endpoint_device and owner = v_dev.owner and revoked_at is null;
  if not found then
    raise exception 'El equipo que se unió ya no existe';
  end if;
  update public.managed_pairings set status = 'confirmed' where id = v_p.id;
end;
$$;

-- La consola descarta una vinculación (el SAS no coincide o se arrepiente):
-- si alguien se unió y no estaba confirmado, su equipo se borra.
create or replace function public.managed_pairing_cancel(p_device uuid, p_secret text, p_pairing uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
  v_p public.managed_pairings;
begin
  select * into v_p from public.managed_pairings
  where id = p_pairing and console_device = v_dev.id
  for update;
  if not found or v_p.status not in ('open', 'joined') then
    raise exception 'Esa vinculación no se puede cancelar (no es de esta consola o ya terminó)';
  end if;
  update public.managed_pairings set status = 'expired', expires_at = least(expires_at, now()) where id = v_p.id;
  if v_p.endpoint_device is not null then
    delete from public.devices where id = v_p.endpoint_device and managed_by is null;
  end if;
end;
$$;

-- Manda un sobre (firmado y cifrado en la consola) a uno de sus agentes.
create or replace function public.managed_send(p_device uuid, p_secret text, p_endpoint uuid, p_seq bigint, p_ciphertext text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
  v_id uuid;
begin
  if coalesce(p_ciphertext, '') !~ '^[A-Za-z0-9+/]+={0,2}$' or length(p_ciphertext) > 65536 then
    raise exception 'Sobre no válido (base64, 64 KB como mucho)';
  end if;
  if p_seq is null or p_seq <= 0 then
    raise exception 'seq no válido';
  end if;
  if not exists (
    select 1
    from public.managed_pairings p
    join public.devices e on e.id = p.endpoint_device
    where p.console_device = v_dev.id and p.endpoint_device = p_endpoint and p.status = 'confirmed'
      and e.managed_by = v_dev.id and e.owner = v_dev.owner and e.revoked_at is null
  ) then
    raise exception 'Ese equipo no lo gestiona esta consola';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('managed_send:' || p_endpoint::text, 0));
  if p_seq <= coalesce((select max(m.seq) from public.managed_messages m where m.endpoint_device = p_endpoint), 0) then
    raise exception 'seq tiene que ser mayor que el último enviado';
  end if;
  if (select count(*) from public.managed_messages m where m.endpoint_device = p_endpoint and m.taken_at is null) >= 100 then
    raise exception 'Ese equipo tiene 100 mensajes sin recoger. Espera a que se conecte.';
  end if;

  insert into public.managed_messages (console_device, endpoint_device, seq, ciphertext)
  values (v_dev.id, p_endpoint, p_seq, p_ciphertext)
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC del agente
-- ---------------------------------------------------------------------------

-- Se une a una vinculación abierta con el hash del código. Crea el equipo del
-- agente (en la cuenta y el cliente de la consola) y devuelve su secreto una
-- sola vez. Un código fallido devuelve {"error": "codigo", "message": ...}
-- (sin lanzar error, para que el intento quede contado).
create or replace function public.managed_pairing_join(
  p_code_hash text,
  p_box_key text,
  p_name text,
  p_os text default null,
  p_app_version text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text := lower(coalesce(p_code_hash, ''));
  v_ip text := public.request_ip_hash();
  v_p public.managed_pairings;
  v_found boolean;
  v_console public.devices;
  v_key text;
  v_secret text := encode(extensions.gen_random_bytes(32), 'hex');
  v_device uuid;
begin
  if v_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Código no válido';
  end if;
  if not public.is_key32(p_box_key) then
    raise exception 'Clave pública no válida (32 bytes en base64)';
  end if;

  if (select count(*) from public.managed_join_failures f
      where f.at > now() - interval '10 minutes' and f.ip_hash = v_ip) >= 10
     or (select count(*) from public.managed_join_failures f
         where f.at > now() - interval '10 minutes') >= 100 then
    raise exception 'Demasiados intentos. Espera unos minutos y vuelve a intentarlo.';
  end if;

  select * into v_p from public.managed_pairings
  where code_hash = v_hash and status = 'open'
  for update;
  v_found := found;

  if not v_found or v_p.expires_at < now() or v_p.failures >= 5 then
    insert into public.managed_join_failures (ip_hash) values (v_ip);
    if v_found then
      update public.managed_pairings set failures = failures + 1 where id = v_p.id;
    end if;
    return jsonb_build_object('error', 'codigo', 'message', 'Código no válido o caducado');
  end if;

  select * into v_console from public.devices where id = v_p.console_device;
  select c.sign_public_key into v_key from public.managed_consoles c where c.device_id = v_p.console_device;
  if v_console.revoked_at is not null or v_console.managed_by is not null or v_key is null then
    update public.managed_pairings set status = 'expired' where id = v_p.id;
    return jsonb_build_object('error', 'codigo', 'message', 'Código no válido o caducado');
  end if;

  if (select count(*) from public.devices d where d.owner = v_console.owner) >= 200 then
    raise exception 'Esta cuenta ya tiene el máximo de equipos (200).';
  end if;

  insert into public.devices (owner, client_id, name, os, app_version, last_seen_at)
  values (
    v_console.owner,
    v_console.client_id,
    left(coalesce(nullif(trim(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]]+', ' ', 'g')), ''), 'Equipo'), 120),
    left(p_os, 60),
    left(p_app_version, 40),
    now()
  )
  returning id into v_device;

  insert into public.device_secrets (device_id, secret_hash)
  values (v_device, encode(extensions.digest(v_secret, 'sha256'), 'hex'));
  insert into public.device_keys (device_id, public_key, updated_at)
  values (v_device, p_box_key, now());

  -- Un solo uso; la consola tiene 15 minutos más para confirmar el SAS.
  update public.managed_pairings
  set status = 'joined', endpoint_device = v_device, endpoint_box_key = p_box_key,
      expires_at = now() + interval '15 minutes'
  where id = v_p.id;

  return jsonb_build_object(
    'pairing_id', v_p.id,
    'console_device', v_console.id,
    'console_name', v_console.name,
    'console_sign_key', v_key,
    'device_id', v_device,
    'secret', v_secret
  );
end;
$$;

-- Los sobres pendientes de este agente (de su consola), por seq. Quedan tomados.
create or replace function public.managed_take(p_device uuid, p_secret text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices := public.device_auth(p_device, p_secret);
  v_r jsonb;
begin
  if v_dev.managed_by is null then
    return '[]'::jsonb;
  end if;
  with t as (
    update public.managed_messages m
    set taken_at = now()
    where m.endpoint_device = v_dev.id and m.console_device = v_dev.managed_by and m.taken_at is null
    returning m.id, m.seq, m.console_device, m.ciphertext, m.created_at
  )
  select jsonb_agg(jsonb_build_object(
    'id', t.id, 'seq', t.seq, 'console_device', t.console_device,
    'ciphertext', t.ciphertext, 'created_at', t.created_at
  ) order by t.seq) into v_r
  from t;
  return coalesce(v_r, '[]'::jsonb);
end;
$$;

revoke all on function public.managed_console_set_key(uuid, text, text) from public;
revoke all on function public.managed_pairing_open(uuid, text, text) from public;
revoke all on function public.managed_pairing_status(uuid, text, uuid) from public;
revoke all on function public.managed_pairing_confirm(uuid, text, uuid) from public;
revoke all on function public.managed_pairing_cancel(uuid, text, uuid) from public;
revoke all on function public.managed_send(uuid, text, uuid, bigint, text) from public;
revoke all on function public.managed_pairing_join(text, text, text, text, text) from public;
revoke all on function public.managed_take(uuid, text) from public;
grant execute on function public.managed_console_set_key(uuid, text, text) to anon, authenticated;
grant execute on function public.managed_pairing_open(uuid, text, text) to anon, authenticated;
grant execute on function public.managed_pairing_status(uuid, text, uuid) to anon, authenticated;
grant execute on function public.managed_pairing_confirm(uuid, text, uuid) to anon, authenticated;
grant execute on function public.managed_pairing_cancel(uuid, text, uuid) to anon, authenticated;
grant execute on function public.managed_send(uuid, text, uuid, bigint, text) to anon, authenticated;
grant execute on function public.managed_pairing_join(text, text, text, text, text) to anon, authenticated;
grant execute on function public.managed_take(uuid, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Informe del equipo: la de 20260930110000_servidor_copias.sql, con managed
-- y sin copias a distancia en los agentes gestionados.
-- ---------------------------------------------------------------------------

create or replace function public.device_report(p_device uuid, p_secret text, p_report jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices;
  v_sec public.device_secrets;
  v_repo jsonb;
  v_run jsonb;
  v_ids text[] := '{}';
  v_count integer := 0;
  v_repo_id text;
  v_snap_ids text[];
  v_oldest timestamptz;
  v_started timestamptz;
  v_pause jsonb;
  v_paused boolean;
  v_paused_since timestamptz;
  v_paused_until timestamptz;
  v_pause_ended timestamptz;
begin
  select * into v_sec from public.device_secrets where device_id = p_device for update;
  if not found or v_sec.secret_hash <> encode(extensions.digest(coalesce(p_secret, ''), 'sha256'), 'hex') then
    raise exception 'Equipo no autorizado' using errcode = '42501';
  end if;
  select * into v_dev from public.devices where id = p_device;
  if v_dev.revoked_at is not null then
    return jsonb_build_object('revoked', true);
  end if;
  if v_sec.last_report_at > now() - interval '5 seconds' then
    raise exception 'Demasiados informes seguidos; se enviará en la próxima vuelta.';
  end if;
  if pg_column_size(p_report) > 2097152 then
    raise exception 'Informe demasiado grande';
  end if;

  update public.device_secrets set last_report_at = now() where device_id = p_device;
  update public.devices
  set last_seen_at = now(),
      app_version = coalesce(left(p_report ->> 'app_version', 40), app_version),
      os = coalesce(left(p_report ->> 'os', 60), os),
      -- Copias a distancia: solo las activa el propio equipo (sin el dato = no).
      -- Nunca en un agente gestionado: sus órdenes las firma la consola.
      remote_backup_enabled = (coalesce(p_report ->> 'remote_backup' = 'true', false) and v_dev.managed_by is null and not (p_report ? 'managed')),
      -- Servidor de copias: solo mientras está activo (sin el dato = desactivado).
      server = public.clean_server(p_report -> 'server'),
      -- Agente gestionado: estado de su servicio (quién lo gestiona lo dice managed_by).
      managed = public.clean_managed(p_report -> 'managed')
  where id = p_device;

  -- Peticiones a distancia: si el equipo no las permite, se rechazan las
  -- pendientes; las recogidas sin respuesta en 6 h se dan por fallidas; las
  -- de hace más de 30 días se borran.
  if not (coalesce(p_report ->> 'remote_backup' = 'true', false) and v_dev.managed_by is null and not (p_report ? 'managed')) then
    update public.device_commands
    set status = 'rejected', finished_at = now(), message = 'Este equipo no permite copias a distancia.'
    where device_id = p_device and status = 'pending';
  end if;
  update public.device_commands
  set status = 'failed', finished_at = now(), message = 'El equipo no informó del resultado.'
  where device_id = p_device and status = 'claimed' and claimed_at < now() - interval '6 hours';
  delete from public.device_commands where device_id = p_device and requested_at < now() - interval '30 days';

  for v_repo in
    select value from jsonb_array_elements(
      case when jsonb_typeof(p_report -> 'repos') = 'array' then p_report -> 'repos' else '[]'::jsonb end
    ) limit 100
  loop
    v_repo_id := left(v_repo ->> 'id', 64);
    if v_repo_id is null or v_repo_id = '' then
      continue;
    end if;
    v_ids := v_ids || v_repo_id;

    begin
      v_run := case when jsonb_typeof(v_repo -> 'last_run') = 'object' then v_repo -> 'last_run' end;
      -- Solo campos conocidos y convertidos.
      if v_run is not null then
        v_run := jsonb_build_object(
          'started', public.try_ts(v_run ->> 'started'),
          'finished', public.try_ts(v_run ->> 'finished'),
          'result', case when v_run ->> 'result' in ('ok', 'warning', 'error') then v_run ->> 'result' else 'error' end,
          'message', left(v_run ->> 'message', 500),
          'snapshot_id', left(v_run ->> 'snapshot_id', 64),
          'data_added', public.try_bigint(v_run ->> 'data_added'),
          'files_new', public.try_bigint(v_run ->> 'files_new'),
          'files_changed', public.try_bigint(v_run ->> 'files_changed')
        ) || case when jsonb_typeof(v_run -> 'unchanged') = 'boolean'
          then jsonb_build_object('unchanged', v_run -> 'unchanged') else '{}'::jsonb end;
      end if;

      -- Pausa de las copias automáticas: {"since": fecha, "until": fecha | null}.
      -- Cualquier dato raro cuenta como "sin pausa" y nunca estropea el informe.
      -- Una pausa cuya fecha de fin ya pasó tampoco cuenta: se anota cuándo
      -- terminó, para dar margen antes de avisar de retraso.
      v_paused := false;
      v_paused_since := null;
      v_paused_until := null;
      v_pause_ended := null;
      v_pause := case when jsonb_typeof(v_repo -> 'paused') = 'object' then v_repo -> 'paused' end;
      if v_pause is not null then
        v_paused_since := public.try_ts(v_pause ->> 'since');
        v_paused_until := public.try_pause_until(v_pause ->> 'until');
        if v_paused_since is null then
          v_paused_until := null;
        elsif v_pause ->> 'until' is null then
          v_paused := true;
        elsif v_paused_until is null then
          v_paused_since := null;
        elsif v_paused_until > now() then
          v_paused := true;
        else
          v_pause_ended := greatest(v_paused_until, v_paused_since);
          v_paused_since := null;
          v_paused_until := null;
        end if;
      end if;

      insert into public.repos as r (
        device_id, repo_id, owner, name, kind, host, schedule, expected_hours,
        snapshots_count, last_snapshot_at, last_duration_s, last_data_added, last_total_bytes,
        last_run, running_since, maintenance, verify_run, offsite_run, offsite_verify_run, restore_test_run,
        kit_saved_at, protection, task_running, plans,
        paused, paused_since, paused_until, resumed_at, offsite_hold, place, updated_at
      )
      values (
        p_device,
        v_repo_id,
        v_dev.owner,
        left(coalesce(v_repo ->> 'name', 'Repositorio'), 120),
        left(coalesce(v_repo ->> 'kind', 'other'), 20),
        left(v_repo ->> 'host', 200),
        public.clean_schedule(v_repo -> 'schedule'),
        public.try_int(v_repo ->> 'expected_hours', 1, 8760),
        public.try_int(v_repo ->> 'snapshots_count', 0, 100000000),
        public.try_ts(v_repo ->> 'last_snapshot_at'),
        public.try_real(v_repo ->> 'last_duration_s'),
        public.try_bigint(v_repo ->> 'last_data_added'),
        public.try_bigint(v_repo ->> 'last_total_bytes'),
        v_run,
        -- Copia automática en marcha (solo si la fecha es razonable).
        case when public.try_ts(v_repo ->> 'running_since') between now() - interval '2 days' and now() + interval '1 hour'
          then public.try_ts(v_repo ->> 'running_since') end,
        public.clean_maintenance(v_repo -> 'maintenance'),
        public.clean_task_run(v_repo -> 'verify_run'),
        public.clean_task_run(v_repo -> 'offsite_run'),
        public.clean_task_run(v_repo -> 'offsite_verify_run'),
        public.clean_task_run(v_repo -> 'restore_test_run'),
        public.try_ts(v_repo ->> 'kit_saved_at'),
        public.clean_protection(v_repo -> 'protection'),
        public.clean_task_running(v_repo -> 'task_running'),
        public.clean_plans(v_repo -> 'plans'),
        v_paused,
        v_paused_since,
        v_paused_until,
        v_pause_ended,
        public.clean_offsite_hold(v_repo -> 'offsite_hold'),
        public.clean_place(v_repo -> 'place'),
        now()
      )
      on conflict (device_id, repo_id) do update set
        name = excluded.name,
        kind = excluded.kind,
        host = excluded.host,
        schedule = excluded.schedule,
        expected_hours = excluded.expected_hours,
        snapshots_count = coalesce(excluded.snapshots_count, r.snapshots_count),
        last_snapshot_at = coalesce(excluded.last_snapshot_at, r.last_snapshot_at),
        last_duration_s = coalesce(excluded.last_duration_s, r.last_duration_s),
        last_data_added = coalesce(excluded.last_data_added, r.last_data_added),
        last_total_bytes = coalesce(excluded.last_total_bytes, r.last_total_bytes),
        last_run = coalesce(excluded.last_run, r.last_run),
        running_since = excluded.running_since,
        maintenance = excluded.maintenance,
        verify_run = coalesce(excluded.verify_run, r.verify_run),
        offsite_run = coalesce(excluded.offsite_run, r.offsite_run),
        offsite_verify_run = coalesce(excluded.offsite_verify_run, r.offsite_verify_run),
        restore_test_run = coalesce(excluded.restore_test_run, r.restore_test_run),
        -- Sin dato = sin kit (o caducado) y sin resumen: se sustituyen siempre.
        kit_saved_at = excluded.kit_saved_at,
        protection = excluded.protection,
        task_running = excluded.task_running,
        plans = excluded.plans,
        paused = excluded.paused,
        paused_since = excluded.paused_since,
        paused_until = excluded.paused_until,
        -- Fin de la última pausa: al reanudar a mano, ahora; si llegó su fecha
        -- de fin, esa fecha. Mientras dura la pausa no hace falta.
        resumed_at = case
          when excluded.paused then null
          when r.paused then least(coalesce(r.paused_until, now()), now())
          else coalesce(excluded.resumed_at, r.resumed_at)
        end,
        -- Sin el campo (versiones antiguas) = sin subida frenada.
        offsite_hold = excluded.offsite_hold,
        -- Sin el dato (versiones antiguas), cada repositorio es su propio destino.
        place = excluded.place,
        updated_at = now();

      -- Historial: solo copias con fecha razonable (últimos 30 días).
      v_started := public.try_ts(v_run ->> 'started');
      if v_started is not null and v_started between now() - interval '30 days' and now() + interval '1 day' then
        insert into public.runs (
          device_id, repo_id, owner, started_at, finished_at, result, message,
          data_added, files_new, files_changed, unchanged
        )
        values (
          p_device,
          v_repo_id,
          v_dev.owner,
          v_started,
          public.try_ts(v_run ->> 'finished'),
          v_run ->> 'result',
          v_run ->> 'message',
          public.try_bigint(v_run ->> 'data_added'),
          public.try_bigint(v_run ->> 'files_new'),
          public.try_bigint(v_run ->> 'files_changed'),
          coalesce(v_run ->> 'unchanged' = 'true', false)
        )
        on conflict (device_id, repo_id, started_at) do nothing;
      end if;

      -- Lista de snapshots (solo cuando el agente la envía).
      if jsonb_typeof(v_repo -> 'snapshots') = 'array' then
        insert into public.snapshots as s (
          device_id, repo_id, owner, snapshot_id, time, hostname, tags, duration_s,
          data_added, total_bytes, total_files, files_new, files_changed, files_unmodified
        )
        select
          p_device,
          v_repo_id,
          v_dev.owner,
          left(x ->> 'id', 16),
          public.try_ts(x ->> 'time'),
          left(x ->> 'hostname', 120),
          coalesce(
            (select array_agg(left(t, 60)) from (
              select t from jsonb_array_elements_text(
                case when jsonb_typeof(x -> 'tags') = 'array' then x -> 'tags' else '[]'::jsonb end
              ) as t limit 20
            ) as tt),
            '{}'
          ),
          public.try_real(x ->> 'duration_s'),
          public.try_bigint(x ->> 'data_added'),
          public.try_bigint(x ->> 'total_bytes'),
          public.try_bigint(x ->> 'total_files'),
          public.try_bigint(x ->> 'files_new'),
          public.try_bigint(x ->> 'files_changed'),
          public.try_bigint(x ->> 'files_unmodified')
        from (select value as x from jsonb_array_elements(v_repo -> 'snapshots') limit 500) as items
        where coalesce(x ->> 'id', '') <> '' and public.try_ts(x ->> 'time') is not null
        on conflict (device_id, repo_id, snapshot_id) do update set
          time = excluded.time,
          hostname = excluded.hostname,
          tags = excluded.tags,
          duration_s = excluded.duration_s,
          data_added = excluded.data_added,
          total_bytes = excluded.total_bytes,
          total_files = excluded.total_files,
          files_new = excluded.files_new,
          files_changed = excluded.files_changed,
          files_unmodified = excluded.files_unmodified;

        -- Los que ya no están en el repositorio (dentro del periodo enviado) se quitan.
        select array_agg(left(x ->> 'id', 16)), min(public.try_ts(x ->> 'time'))
        into v_snap_ids, v_oldest
        from (select value as x from jsonb_array_elements(v_repo -> 'snapshots') limit 500) as items;

        if v_oldest is not null then
          delete from public.snapshots
          where device_id = p_device and repo_id = v_repo_id
            and time >= v_oldest and not (snapshot_id = any (coalesce(v_snap_ids, '{}')));
        end if;
        -- Historial: como mucho las 1500 más recientes (para los informes
        -- mensuales, también con copias cada hora).
        delete from public.snapshots
        where device_id = p_device and repo_id = v_repo_id and snapshot_id in (
          select snapshot_id from public.snapshots
          where device_id = p_device and repo_id = v_repo_id
          order by time desc offset 1500
        );
      end if;

      v_count := v_count + 1;
    exception when others then
      -- Un repositorio con datos inválidos no estropea el resto del informe.
      raise warning 'device_report: repositorio % omitido: %', v_repo_id, sqlerrm;
    end;
  end loop;

  delete from public.repos where device_id = p_device and not (repo_id = any (v_ids));
  delete from public.runs where device_id = p_device and started_at < now() - interval '400 days';

  return jsonb_build_object('ok', true, 'repos', v_count);
end;
$$;

revoke all on function public.device_report(uuid, text, jsonb) from public;
grant execute on function public.device_report(uuid, text, jsonb) to anon, authenticated;
