-- Progreso de la verificación y de la subida a la copia externa en curso.
--
-- El equipo añade a "task_running": total, percent, eta_s, bytes_done,
-- bytes_total y current_snapshot_time (cualquiera puede faltar o ser null; las
-- versiones antiguas solo envían kind, started, stage y done). device_report
-- ya limpia "task_running" con esta función, así que basta con redefinirla
-- (la de 20260929060000_mantenimiento.sql, con los campos nuevos).

create or replace function public.clean_task_running(p jsonb)
returns jsonb language sql stable set search_path = '' as $$
  select case when jsonb_typeof(p) <> 'object'
    or coalesce(p ->> 'kind', '') not in ('verify', 'offsite')
    or public.try_ts(p ->> 'started') is null
    or public.try_ts(p ->> 'started') < now() - interval '3 days' then null
  else jsonb_build_object(
    'kind', p ->> 'kind',
    'started', public.try_ts(p ->> 'started'),
    'stage', left(coalesce(p ->> 'stage', ''), 160),
    'done', coalesce(public.try_bigint(p ->> 'done'), 0),
    'total', public.try_bigint(p ->> 'total'),
    -- 0–100; sin dato, null (ojo: least(null, 100) daría 100).
    'percent', case when public.try_real(p ->> 'percent') is not null
      then least(public.try_real(p ->> 'percent'), 100) end,
    'eta_s', public.try_bigint(p ->> 'eta_s'),
    'bytes_done', public.try_bigint(p ->> 'bytes_done'),
    'bytes_total', public.try_bigint(p ->> 'bytes_total'),
    'current_snapshot_time', public.try_ts(p ->> 'current_snapshot_time')
  ) end;
$$;

revoke all on function public.clean_task_running(jsonb) from public, anon, authenticated;
