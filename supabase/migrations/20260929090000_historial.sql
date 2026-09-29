-- Más historial de versiones por destino (1500) para los informes mensuales.

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
        last_run, running_since, maintenance, verify_run, offsite_run, task_running, plans, updated_at
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
        public.clean_task_running(v_repo -> 'task_running'),
        public.clean_plans(v_repo -> 'plans'),
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
        task_running = excluded.task_running,
        plans = excluded.plans,
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
