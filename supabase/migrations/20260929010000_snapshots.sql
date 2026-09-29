-- Lista de snapshots de cada repositorio (solo metadatos: sin rutas ni
-- nombres de archivos). La envía el agente como mucho una vez por hora.

create table public.snapshots (
  device_id uuid not null,
  repo_id text not null,
  owner uuid not null references auth.users on delete cascade,
  snapshot_id text not null check (char_length(snapshot_id) between 1 and 16),
  time timestamptz not null,
  hostname text,
  tags text[] not null default '{}',
  duration_s real,
  data_added bigint,
  total_bytes bigint,
  total_files bigint,
  files_new bigint,
  files_changed bigint,
  files_unmodified bigint,
  primary key (device_id, repo_id, snapshot_id),
  foreign key (device_id, repo_id) references public.repos (device_id, repo_id) on delete cascade
);

create index snapshots_time_idx on public.snapshots (device_id, repo_id, time desc);

alter table public.snapshots enable row level security;
revoke all on public.snapshots from anon;

create policy "ver snapshots propios" on public.snapshots
  for select to authenticated
  using (owner = auth.uid() and public.is_mfa());

-- Informe del equipo: igual que antes y, si el repositorio trae "snapshots",
-- se guardan (máx. 500) y se quitan los que ya no existen en ese periodo
-- (p. ej. borrados por la retención).
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
  v_repo_id text;
  v_snap_ids text[];
  v_oldest timestamptz;
begin
  select * into v_dev from public.devices where id = p_device;
  if not found or v_dev.secret_hash <> encode(extensions.digest(coalesce(p_secret, ''), 'sha256'), 'hex') then
    raise exception 'Equipo no autorizado' using errcode = '42501';
  end if;
  if v_dev.revoked_at is not null then
    return jsonb_build_object('revoked', true);
  end if;
  if pg_column_size(p_report) > 2097152 then
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
    v_repo_id := left(v_repo ->> 'id', 64);
    v_ids := v_ids || v_repo_id;

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
        v_repo_id,
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
        (x ->> 'time')::timestamptz,
        left(x ->> 'hostname', 120),
        coalesce(
          (select array_agg(left(t, 60)) from jsonb_array_elements_text(
            case when jsonb_typeof(x -> 'tags') = 'array' then x -> 'tags' else '[]'::jsonb end
          ) as t),
          '{}'
        ),
        (x ->> 'duration_s')::real,
        (x ->> 'data_added')::bigint,
        (x ->> 'total_bytes')::bigint,
        (x ->> 'total_files')::bigint,
        (x ->> 'files_new')::bigint,
        (x ->> 'files_changed')::bigint,
        (x ->> 'files_unmodified')::bigint
      from (select value as x from jsonb_array_elements(v_repo -> 'snapshots') limit 500) as items
      where (x ->> 'id') is not null and (x ->> 'time') is not null
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
      select array_agg(left(x ->> 'id', 16)), min((x ->> 'time')::timestamptz)
      into v_snap_ids, v_oldest
      from (select value as x from jsonb_array_elements(v_repo -> 'snapshots') limit 500) as items;

      if v_oldest is not null then
        delete from public.snapshots
        where device_id = p_device and repo_id = v_repo_id
          and time >= v_oldest and not (snapshot_id = any (v_snap_ids));
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
  end loop;

  delete from public.repos where device_id = p_device and not (repo_id = any (v_ids));
  delete from public.runs where device_id = p_device and started_at < now() - interval '400 days';

  return jsonb_build_object('ok', true, 'repos', v_count);
end;
$$;

revoke all on function public.device_report(uuid, text, jsonb) from public;
grant execute on function public.device_report(uuid, text, jsonb) to anon, authenticated;
