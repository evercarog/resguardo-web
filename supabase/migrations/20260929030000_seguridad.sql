-- Endurecimiento tras la revisión de seguridad.
--
-- 1. Conversiones seguras: un informe con datos raros de un equipo nunca
--    rompe las consultas que recorren a todos los usuarios (avisos).
-- 2. La huella del secreto de cada equipo sale de "devices" (que se lee desde
--    la web y viaja por tiempo real) a una tabla sin acceso.
-- 3. Límites: códigos de vinculación pendientes, equipos por cuenta,
--    frecuencia de informes, fechas de las copias.
-- 4. Suscripciones push: solo servicios de push conocidos y como mucho 10.
-- 5. La función de avisos solo hace la revisión periódica si la llama
--    pg_cron (con un secreto guardado en Vault) y nunca dos veces a la vez.

-- ---------------------------------------------------------------------------
-- 1. Conversiones seguras (null si el texto no es válido)
-- ---------------------------------------------------------------------------

create or replace function public.try_int(p text, p_min integer, p_max integer)
returns integer language plpgsql immutable set search_path = '' as $$
begin
  if p is null then return null; end if;
  return least(greatest(p::numeric, p_min), p_max)::integer;
exception when others then
  return null;
end;
$$;

create or replace function public.try_bigint(p text)
returns bigint language plpgsql immutable set search_path = '' as $$
begin
  if p is null then return null; end if;
  return greatest(p::numeric, 0)::bigint;
exception when others then
  return null;
end;
$$;

create or replace function public.try_real(p text)
returns real language plpgsql immutable set search_path = '' as $$
begin
  if p is null then return null; end if;
  return greatest(p::real, 0);
exception when others then
  return null;
end;
$$;

create or replace function public.try_ts(p text)
returns timestamptz language plpgsql stable set search_path = '' as $$
begin
  return p::timestamptz;
exception when others then
  return null;
end;
$$;

revoke all on function public.try_int(text, integer, integer) from public, anon, authenticated;
revoke all on function public.try_bigint(text) from public, anon, authenticated;
revoke all on function public.try_real(text) from public, anon, authenticated;
revoke all on function public.try_ts(text) from public, anon, authenticated;

-- Horario normalizado: solo tipos conocidos y números en rango.
create or replace function public.clean_schedule(p jsonb)
returns jsonb language sql immutable set search_path = '' as $$
  select case
    when jsonb_typeof(p) <> 'object' then null
    when p ->> 'kind' in ('hours', 'monitor') then jsonb_build_object(
      'kind', p ->> 'kind', 'every', coalesce(public.try_int(p ->> 'every', 1, 8760), 24))
    when p ->> 'kind' = 'daily' then jsonb_build_object(
      'kind', 'daily', 'time', left(coalesce(p ->> 'time', ''), 5))
    when p ->> 'kind' = 'weekly' then jsonb_build_object(
      'kind', 'weekly', 'weekday', coalesce(public.try_int(p ->> 'weekday', 0, 6), 0),
      'time', left(coalesce(p ->> 'time', ''), 5))
    else null
  end;
$$;
revoke all on function public.clean_schedule(jsonb) from public, anon, authenticated;

-- Datos existentes: se limpian con las mismas reglas.
update public.repos set
  schedule = public.clean_schedule(schedule),
  expected_hours = case when expected_hours is null then null else least(greatest(expected_hours, 1), 8760) end;

-- ---------------------------------------------------------------------------
-- 2. Secretos de los equipos, aparte
-- ---------------------------------------------------------------------------

create table public.device_secrets (
  device_id uuid primary key references public.devices on delete cascade,
  -- Huella SHA-256 (hex) del secreto del equipo. El secreto solo lo tiene el equipo.
  secret_hash text not null,
  -- Último informe aceptado (para limitar la frecuencia).
  last_report_at timestamptz
);
alter table public.device_secrets enable row level security;
revoke all on public.device_secrets from anon, authenticated;

insert into public.device_secrets (device_id, secret_hash)
select id, secret_hash from public.devices;

alter table public.devices drop column secret_hash;

-- ---------------------------------------------------------------------------
-- 3. Vinculación con límites
-- ---------------------------------------------------------------------------

create or replace function public.create_pairing_code(p_client uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- sin 0/O ni 1/I
  v_bytes bytea := extensions.gen_random_bytes(8);
  v_code text := '';
  v_expires timestamptz;
begin
  if auth.uid() is null or not public.is_mfa() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_client is not null and not exists (
    select 1 from public.clients c where c.id = p_client and c.owner = auth.uid()
  ) then
    raise exception 'Cliente no encontrado';
  end if;

  -- Limpieza de códigos caducados sin usar.
  delete from public.pairing_codes pc
  where pc.owner = auth.uid() and pc.used_at is null and pc.expires_at < now();

  if (select count(*) from public.pairing_codes pc
      where pc.owner = auth.uid() and pc.used_at is null) >= 5 then
    raise exception 'Ya tienes 5 códigos sin usar. Espera a que caduquen (15 minutos).';
  end if;

  for i in 0..7 loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;

  insert into public.pairing_codes (code, owner, client_id)
  values (v_code, auth.uid(), p_client)
  returning expires_at into v_expires;

  return jsonb_build_object('code', v_code, 'expires_at', v_expires);
end;
$$;

create or replace function public.device_pair(
  p_code text,
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
  v_pc public.pairing_codes;
  v_secret text := encode(extensions.gen_random_bytes(32), 'hex');
  v_device uuid;
begin
  select * into v_pc
  from public.pairing_codes
  where code = upper(replace(replace(trim(coalesce(p_code, '')), '-', ''), ' ', ''))
  for update;

  if not found or v_pc.used_at is not null or v_pc.expires_at < now() then
    raise exception 'Código no válido o caducado' using errcode = 'P0001';
  end if;

  if (select count(*) from public.devices d where d.owner = v_pc.owner) >= 200 then
    raise exception 'Esta cuenta ya tiene el máximo de equipos (200).';
  end if;

  insert into public.devices (owner, client_id, name, os, app_version, last_seen_at)
  values (
    v_pc.owner,
    v_pc.client_id,
    left(coalesce(nullif(trim(p_name), ''), 'Equipo'), 120),
    left(p_os, 60),
    left(p_app_version, 40),
    now()
  )
  returning id into v_device;

  insert into public.device_secrets (device_id, secret_hash)
  values (v_device, encode(extensions.digest(v_secret, 'sha256'), 'hex'));

  update public.pairing_codes set used_at = now(), device_id = v_device where code = v_pc.code;

  return jsonb_build_object('device_id', v_device, 'secret', v_secret);
end;
$$;

-- Informe del equipo, con conversiones seguras y límites. Un repositorio con
-- datos inválidos se salta sin estropear el resto del informe.
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
      os = coalesce(left(p_report ->> 'os', 60), os)
  where id = p_device;

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
        );
      end if;

      insert into public.repos as r (
        device_id, repo_id, owner, name, kind, host, schedule, expected_hours,
        snapshots_count, last_snapshot_at, last_duration_s, last_data_added, last_total_bytes,
        last_run, updated_at
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
        updated_at = now();

      -- Historial: solo copias con fecha razonable (últimos 30 días).
      v_started := public.try_ts(v_run ->> 'started');
      if v_started is not null and v_started between now() - interval '30 days' and now() + interval '1 day' then
        insert into public.runs (
          device_id, repo_id, owner, started_at, finished_at, result, message,
          data_added, files_new, files_changed
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
          public.try_bigint(v_run ->> 'files_changed')
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
        -- Se conservan como mucho los 500 más recientes.
        delete from public.snapshots
        where device_id = p_device and repo_id = v_repo_id and snapshot_id in (
          select snapshot_id from public.snapshots
          where device_id = p_device and repo_id = v_repo_id
          order by time desc offset 500
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

revoke all on function public.create_pairing_code(uuid) from public, anon;
revoke all on function public.device_pair(text, text, text, text) from public;
revoke all on function public.device_report(uuid, text, jsonb) from public;
grant execute on function public.create_pairing_code(uuid) to authenticated;
grant execute on function public.device_pair(text, text, text, text) to anon, authenticated;
grant execute on function public.device_report(uuid, text, jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Avisos: consulta a prueba de datos raros
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
      coalesce(r.last_snapshot_at, public.try_ts(r.last_run ->> 'finished')) as last_at,
      r.last_run ->> 'result' as last_result,
      r.last_run ->> 'message' as last_message
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
        when now() - last_at > make_interval(hours => expected * 2 + 1) then 'overdue'
        when now() - last_at > make_interval(hours => ceil(expected * 1.25)::int + 1) then 'late'
        else 'ok'
      end as lvl
    from repo_status
  ) s
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
  where d.revoked_at is null and d.last_seen_at is not null;
$$;

revoke all on function public.current_alerts() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Suscripciones push
-- ---------------------------------------------------------------------------

alter table public.push_subscriptions
  add constraint push_endpoint_conocido check (
    endpoint ~ '^https://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|web\.push\.apple\.com|[a-z0-9-]+\.notify\.windows\.com|[a-z0-9.-]+\.push\.apple\.com)/'
    and char_length(endpoint) <= 1000
  ) not valid,
  add constraint push_claves_acotadas check (
    char_length(p256dh) <= 200 and char_length(auth) <= 100 and coalesce(char_length(user_agent), 0) <= 300
  ) not valid;

create or replace function public.push_subscriptions_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.push_subscriptions where owner = new.owner) >= 10 then
    raise exception 'Como mucho 10 dispositivos con avisos por cuenta. Desactiva alguno antes.';
  end if;
  return new;
end;
$$;
revoke all on function public.push_subscriptions_limit() from public, anon, authenticated;

create trigger push_subscriptions_limit
  before insert on public.push_subscriptions
  for each row execute function public.push_subscriptions_limit();

-- ---------------------------------------------------------------------------
-- 5. Función de avisos: solo pg_cron, y una ejecución a la vez
-- ---------------------------------------------------------------------------

-- Secreto compartido entre pg_cron y la función (se genera aquí; no está en
-- ningún archivo del proyecto).
select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'notify_cron',
  'Resguardo: pg_cron lo envía a la función notify');

create or replace function public.notify_cron_ok(p_secret text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from vault.decrypted_secrets
    where name = 'notify_cron' and decrypted_secret = coalesce(p_secret, '')
  );
$$;

-- Turno: evita que dos revisiones a la vez envíen el mismo aviso.
create table public.notify_lease (
  id integer primary key default 1 check (id = 1),
  locked_until timestamptz
);
alter table public.notify_lease enable row level security;
revoke all on public.notify_lease from anon, authenticated;
insert into public.notify_lease (id) values (1);

create or replace function public.notify_claim()
returns boolean language sql volatile security definer set search_path = '' as $$
  update public.notify_lease set locked_until = now() + interval '4 minutes'
  where id = 1 and (locked_until is null or locked_until < now())
  returning true;
$$;

create or replace function public.notify_release()
returns void language sql volatile security definer set search_path = '' as $$
  update public.notify_lease set locked_until = null where id = 1;
$$;

revoke all on function public.notify_cron_ok(text) from public, anon, authenticated;
revoke all on function public.notify_claim() from public, anon, authenticated;
revoke all on function public.notify_release() from public, anon, authenticated;
grant execute on function public.notify_cron_ok(text) to service_role;
grant execute on function public.notify_claim() to service_role;
grant execute on function public.notify_release() to service_role;

-- pg_cron envía el secreto (leído de Vault en cada ejecución).
select cron.schedule(
  'resguardo-avisos',
  '*/10 * * * *',
  $$ select net.http_post(
       url := 'https://ltuqkovbkmhlyjhsbuff.supabase.co/functions/v1/notify',
       headers := jsonb_build_object(
         'Content-Type', 'application/json',
         'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'notify_cron')
       ),
       body := '{}'::jsonb
     ) $$
);
