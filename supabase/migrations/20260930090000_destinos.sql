-- Destinos y repositorios: la app de escritorio pasa al modelo «Destino
-- (el lugar: un bucket, un servidor REST, un disco) → Repositorios (cada
-- repositorio de restic, cifrado con su propia contraseña)». Lo que la web
-- llamaba «destino» es un repositorio.
--
-- Cada repositorio del informe puede traer "place": {"id": uuid, "name",
-- "kind"}. El id es de ese equipo (no global). Sin el dato (versiones
-- antiguas), cada repositorio es su propio destino.

alter table public.repos add column place jsonb;

-- Destino de un repositorio: id uuid, nombre de hasta 80 caracteres y tipo
-- conocido; si no, nada.
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
  end;
$$;

revoke all on function public.clean_place(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Pedir una copia a distancia: la de 20260930080000_copias_a_distancia.sql,
-- con «repositorio» en el mensaje.
-- ---------------------------------------------------------------------------

create or replace function public.request_remote_backup(p_device uuid, p_repo text, p_plan text, p_from text default 'web')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := auth.uid();
  v_dev public.devices;
  v_plans jsonb;
  v_name text;
  v_id uuid;
begin
  if v_owner is null or not public.is_mfa() then
    raise exception 'Para pedir una copia necesitas haber entrado con la verificación en dos pasos.' using errcode = '42501';
  end if;

  select * into v_dev from public.devices where id = p_device and owner = v_owner;
  if not found then
    raise exception 'Equipo no encontrado.';
  end if;
  if v_dev.revoked_at is not null then
    raise exception 'Este equipo está desvinculado.';
  end if;
  if not v_dev.remote_backup_enabled then
    raise exception 'Este equipo no permite copias a distancia. Actívalo en Resguardo, en ese equipo.';
  end if;

  select r.plans into v_plans from public.repos r where r.device_id = p_device and r.repo_id = p_repo;
  if not found then
    raise exception 'Ese repositorio ya no existe en el equipo.';
  end if;
  select x ->> 'name' into v_name
  from jsonb_array_elements(case when jsonb_typeof(v_plans) = 'array' then v_plans else '[]'::jsonb end) as e(x)
  where jsonb_typeof(x) = 'object' and x ->> 'id' = p_plan
  limit 1;
  if not found then
    raise exception 'Esa copia ya no existe en el equipo.';
  end if;

  -- Límite por cuenta: una petición a la vez por cuenta para contar bien.
  perform pg_advisory_xact_lock(hashtextextended('request_remote_backup:' || v_owner::text, 0));
  if (select count(*) from public.device_commands c
      where c.owner = v_owner and c.requested_at > now() - interval '1 hour') >= 20 then
    raise exception 'Has pedido demasiadas copias en la última hora. Espera un poco y vuelve a intentarlo.';
  end if;

  begin
    insert into public.device_commands (owner, device_id, repo_id, plan_id, kind, requested_from)
    values (v_owner, p_device, p_repo, p_plan, 'backup', left(coalesce(nullif(trim(p_from), ''), 'web'), 60))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Ya hay una copia de «%» pedida; espera a que termine.', coalesce(v_name, 'esa copia');
  end;

  return v_id;
end;
$$;

revoke all on function public.request_remote_backup(uuid, text, text, text) from public, anon;
grant execute on function public.request_remote_backup(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Informe del equipo: la de 20260930080000_copias_a_distancia.sql, con place.
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
      remote_backup_enabled = coalesce(p_report ->> 'remote_backup' = 'true', false)
  where id = p_device;

  -- Peticiones a distancia: si el equipo no las permite, se rechazan las
  -- pendientes; las recogidas sin respuesta en 6 h se dan por fallidas; las
  -- de hace más de 30 días se borran.
  if not coalesce(p_report ->> 'remote_backup' = 'true', false) then
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
