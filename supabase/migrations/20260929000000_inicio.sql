-- Resguardo web: estado de las copias de los equipos vinculados.
--
-- Principios de seguridad:
-- * La web nunca guarda contraseñas de repositorios ni nombres de archivos:
--   solo metadatos (fechas, duraciones, tamaños, resultado).
-- * Las personas (auth.users) solo ven y modifican lo suyo, y solo con la
--   verificación en dos pasos completada (aal2), comprobado aquí en la base
--   de datos, no en la web.
-- * Los equipos no son usuarios ni leen tablas: solo llaman a device_pair
--   (con un código de un solo uso) y device_report (con su secreto, del que
--   aquí solo se guarda la huella SHA-256).

-- ---------------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------------

create or replace function public.is_mfa()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
$$;

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  created_at timestamptz not null default now()
);

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references auth.users on delete cascade,
  client_id uuid references public.clients on delete set null,
  name text not null check (char_length(name) between 1 and 120),
  -- Huella SHA-256 (hex) del secreto del equipo. El secreto solo lo tiene el equipo.
  secret_hash text not null,
  os text,
  app_version text,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  revoked_at timestamptz
);

create table public.pairing_codes (
  code text primary key check (code ~ '^[A-Z2-9]{8}$'),
  owner uuid not null references auth.users on delete cascade,
  client_id uuid references public.clients on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '15 minutes',
  used_at timestamptz,
  device_id uuid references public.devices on delete set null
);

-- Estado actual de cada repositorio de cada equipo.
create table public.repos (
  device_id uuid not null references public.devices on delete cascade,
  repo_id text not null check (char_length(repo_id) between 1 and 64),
  owner uuid not null references auth.users on delete cascade,
  name text not null,
  -- local | rest | sftp | s3 | b2 | azure | gs | rclone | other
  kind text not null default 'other',
  -- Servidor sin credenciales (p. ej. "backups.ejemplo.com:8000"); nunca rutas locales.
  host text,
  schedule jsonb,
  expected_hours integer,
  snapshots_count integer,
  last_snapshot_at timestamptz,
  last_duration_s real,
  last_data_added bigint,
  last_total_bytes bigint,
  last_run jsonb,
  updated_at timestamptz not null default now(),
  primary key (device_id, repo_id)
);

-- Historial de copias automáticas (para gráficas y avisos).
create table public.runs (
  id bigint generated always as identity primary key,
  device_id uuid not null references public.devices on delete cascade,
  repo_id text not null,
  owner uuid not null references auth.users on delete cascade,
  started_at timestamptz not null,
  finished_at timestamptz,
  result text not null check (result in ('ok', 'warning', 'error')),
  message text,
  data_added bigint,
  files_new bigint,
  files_changed bigint,
  unique (device_id, repo_id, started_at)
);

create index devices_owner_idx on public.devices (owner);
create index repos_owner_idx on public.repos (owner);
create index runs_lookup_idx on public.runs (device_id, repo_id, started_at desc);
create index pairing_codes_owner_idx on public.pairing_codes (owner);

-- ---------------------------------------------------------------------------
-- Permisos: nada para anon; lo propio (con 2FA) para authenticated
-- ---------------------------------------------------------------------------

alter table public.clients enable row level security;
alter table public.devices enable row level security;
alter table public.pairing_codes enable row level security;
alter table public.repos enable row level security;
alter table public.runs enable row level security;

revoke all on public.clients, public.devices, public.pairing_codes, public.repos, public.runs from anon;

create policy "clientes propios" on public.clients
  for all to authenticated
  using (owner = auth.uid() and public.is_mfa())
  with check (owner = auth.uid() and public.is_mfa());

create policy "ver equipos propios" on public.devices
  for select to authenticated
  using (owner = auth.uid() and public.is_mfa());

create policy "quitar equipos propios" on public.devices
  for delete to authenticated
  using (owner = auth.uid() and public.is_mfa());

-- Solo se pueden cambiar el nombre y el cliente de un equipo (ver grant de abajo).
create policy "editar equipos propios" on public.devices
  for update to authenticated
  using (owner = auth.uid() and public.is_mfa())
  with check (
    owner = auth.uid() and public.is_mfa()
    and (client_id is null or exists (
      select 1 from public.clients c where c.id = client_id and c.owner = auth.uid()
    ))
  );
revoke update on public.devices from authenticated;
grant update (name, client_id, revoked_at) on public.devices to authenticated;

create policy "ver códigos propios" on public.pairing_codes
  for select to authenticated
  using (owner = auth.uid() and public.is_mfa());

create policy "ver repositorios propios" on public.repos
  for select to authenticated
  using (owner = auth.uid() and public.is_mfa());

create policy "ver historial propio" on public.runs
  for select to authenticated
  using (owner = auth.uid() and public.is_mfa());

-- ---------------------------------------------------------------------------
-- Funciones
-- ---------------------------------------------------------------------------

-- Crea un código de vinculación (8 caracteres, 15 minutos, un solo uso).
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

  for i in 0..7 loop
    v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;

  -- Limpieza de códigos caducados sin usar.
  delete from public.pairing_codes pc
  where pc.owner = auth.uid() and pc.used_at is null and pc.expires_at < now();

  insert into public.pairing_codes (code, owner, client_id)
  values (v_code, auth.uid(), p_client)
  returning expires_at into v_expires;

  return jsonb_build_object('code', v_code, 'expires_at', v_expires);
end;
$$;

-- Vincula un equipo con un código. Devuelve su id y su secreto (la única vez
-- que el secreto sale de aquí; solo se guarda su huella).
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

  insert into public.devices (owner, client_id, name, secret_hash, os, app_version, last_seen_at)
  values (
    v_pc.owner,
    v_pc.client_id,
    left(coalesce(nullif(trim(p_name), ''), 'Equipo'), 120),
    encode(extensions.digest(v_secret, 'sha256'), 'hex'),
    left(p_os, 60),
    left(p_app_version, 40),
    now()
  )
  returning id into v_device;

  update public.pairing_codes set used_at = now(), device_id = v_device where code = v_pc.code;

  return jsonb_build_object('device_id', v_device, 'secret', v_secret);
end;
$$;

-- Informe periódico de un equipo: estado de sus repositorios y última copia.
create or replace function public.device_report(p_device uuid, p_secret text, p_report jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dev public.devices;
  v_repo jsonb;
  v_run jsonb;
  v_ids text[] := '{}';
  v_count integer := 0;
begin
  select * into v_dev from public.devices where id = p_device;
  if not found or v_dev.secret_hash <> encode(extensions.digest(coalesce(p_secret, ''), 'sha256'), 'hex') then
    raise exception 'Equipo no autorizado' using errcode = '42501';
  end if;
  if v_dev.revoked_at is not null then
    return jsonb_build_object('revoked', true);
  end if;
  if pg_column_size(p_report) > 262144 then
    raise exception 'Informe demasiado grande';
  end if;

  update public.devices
  set last_seen_at = now(),
      app_version = coalesce(left(p_report ->> 'app_version', 40), app_version),
      os = coalesce(left(p_report ->> 'os', 60), os)
  where id = p_device;

  for v_repo in
    select value from jsonb_array_elements(coalesce(p_report -> 'repos', '[]'::jsonb)) limit 100
  loop
    v_ids := v_ids || left(v_repo ->> 'id', 64);

    insert into public.repos as r (
      device_id, repo_id, owner, name, kind, host, schedule, expected_hours,
      snapshots_count, last_snapshot_at, last_duration_s, last_data_added, last_total_bytes,
      last_run, updated_at
    )
    values (
      p_device,
      left(v_repo ->> 'id', 64),
      v_dev.owner,
      left(coalesce(v_repo ->> 'name', 'Repositorio'), 120),
      left(coalesce(v_repo ->> 'kind', 'other'), 20),
      left(v_repo ->> 'host', 200),
      v_repo -> 'schedule',
      (v_repo ->> 'expected_hours')::integer,
      (v_repo ->> 'snapshots_count')::integer,
      (v_repo ->> 'last_snapshot_at')::timestamptz,
      (v_repo ->> 'last_duration_s')::real,
      (v_repo ->> 'last_data_added')::bigint,
      (v_repo ->> 'last_total_bytes')::bigint,
      v_repo -> 'last_run',
      now()
    )
    on conflict (device_id, repo_id) do update set
      name = excluded.name,
      kind = excluded.kind,
      host = excluded.host,
      schedule = excluded.schedule,
      expected_hours = excluded.expected_hours,
      -- Los datos de snapshots solo llegan cada cierto tiempo: se conservan los anteriores.
      snapshots_count = coalesce(excluded.snapshots_count, r.snapshots_count),
      last_snapshot_at = coalesce(excluded.last_snapshot_at, r.last_snapshot_at),
      last_duration_s = coalesce(excluded.last_duration_s, r.last_duration_s),
      last_data_added = coalesce(excluded.last_data_added, r.last_data_added),
      last_total_bytes = coalesce(excluded.last_total_bytes, r.last_total_bytes),
      last_run = coalesce(excluded.last_run, r.last_run),
      updated_at = now();

    v_run := v_repo -> 'last_run';
    if jsonb_typeof(v_run) = 'object' and (v_run ->> 'started') is not null then
      insert into public.runs (
        device_id, repo_id, owner, started_at, finished_at, result, message,
        data_added, files_new, files_changed
      )
      values (
        p_device,
        left(v_repo ->> 'id', 64),
        v_dev.owner,
        (v_run ->> 'started')::timestamptz,
        (v_run ->> 'finished')::timestamptz,
        case when v_run ->> 'result' in ('ok', 'warning', 'error') then v_run ->> 'result' else 'error' end,
        left(v_run ->> 'message', 500),
        (v_run ->> 'data_added')::bigint,
        (v_run ->> 'files_new')::bigint,
        (v_run ->> 'files_changed')::bigint
      )
      on conflict (device_id, repo_id, started_at) do nothing;
    end if;

    v_count := v_count + 1;
  end loop;

  -- El informe trae la lista completa: los repositorios que ya no están se quitan.
  delete from public.repos where device_id = p_device and not (repo_id = any (v_ids));
  -- Historial de un año aproximadamente.
  delete from public.runs where device_id = p_device and started_at < now() - interval '400 days';

  return jsonb_build_object('ok', true, 'repos', v_count);
end;
$$;

revoke all on function public.create_pairing_code(uuid) from public, anon;
revoke all on function public.device_pair(text, text, text, text) from public;
revoke all on function public.device_report(uuid, text, jsonb) from public;
revoke all on function public.is_mfa() from public;

grant execute on function public.is_mfa() to authenticated;
grant execute on function public.create_pairing_code(uuid) to authenticated;
grant execute on function public.device_pair(text, text, text, text) to anon, authenticated;
grant execute on function public.device_report(uuid, text, jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Tiempo real: la web se actualiza sola cuando un equipo informa.
-- (Supabase aplica las mismas reglas RLS a lo que envía en tiempo real.)
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.repos, public.devices;