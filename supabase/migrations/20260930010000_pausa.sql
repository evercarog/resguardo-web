-- Copias automáticas en pausa.
--
-- El equipo informa en cada repositorio "paused": null | {"since", "until"}
-- ("until" null = hasta que se reanude a mano; las versiones antiguas no lo
-- envían = sin pausa). Mientras dura la pausa no se avisa de retrasos, y al
-- terminar el plazo vuelve a contar desde el fin de la pausa.

alter table public.repos
  add column paused boolean not null default false,
  add column paused_since timestamptz,
  add column paused_until timestamptz,
  add column resumed_at timestamptz;

-- Fin de una pausa: como try_ts, pero admite fechas futuras (hasta un año y
-- pico). Lo que no sea una fecha válida devuelve null.
create or replace function public.try_pause_until(p text)
returns timestamptz language plpgsql stable set search_path = '' as $$
declare
  v timestamptz;
begin
  if p is null then return null; end if;
  v := p::timestamptz;
  if not isfinite(v) or v > now() + interval '400 days' or v < '2000-01-01'::timestamptz then
    return null;
  end if;
  return v;
exception when others then
  return null;
end;
$$;

revoke all on function public.try_pause_until(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Informe del equipo: la de 20260929090000_historial.sql, con la pausa.
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
        last_run, running_since, maintenance, verify_run, offsite_run, task_running, plans,
        paused, paused_since, paused_until, resumed_at, updated_at
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
        v_paused,
        v_paused_since,
        v_paused_until,
        v_pause_ended,
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

-- ---------------------------------------------------------------------------
-- Avisos: la de 20260929060000_mantenimiento.sql, sin retrasos en pausa y con
-- margen al reanudar (el plazo cuenta desde el fin de la pausa).
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
      r.offsite_run ->> 'message' as message,
      public.try_ts(r.offsite_run ->> 'finished') as last_at,
      case
        when r.offsite_run ->> 'result' = 'error' then 'failed'
        when r.task_running ->> 'kind' = 'offsite' then 'ok'
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
  -- En pausa, igual que arriba: solo se avisa de un fallo.
  where not (paused_now and lvl <> 'failed');
$$;

revoke all on function public.current_alerts() from public, anon, authenticated;
