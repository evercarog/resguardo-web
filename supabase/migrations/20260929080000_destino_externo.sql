-- Copia externa hacia otro destino de la app: se guarda también su nombre
-- para mostrarlo en el panel (en lugar de «Otra ubicación»).

create or replace function public.clean_maintenance(p jsonb)
returns jsonb language sql stable set search_path = '' as $$
  select case when jsonb_typeof(p) <> 'object' then null
  else jsonb_build_object(
    'verify', case when jsonb_typeof(p -> 'verify') = 'object' then jsonb_build_object(
      'schedule', public.clean_schedule(p -> 'verify' -> 'schedule'),
      'subset_percent', coalesce(public.try_int(p -> 'verify' ->> 'subset_percent', 0, 100), 0)) end,
    'offsite', case when jsonb_typeof(p -> 'offsite') = 'object' then jsonb_build_object(
      'schedule', public.clean_schedule(p -> 'offsite' -> 'schedule'),
      'provider', left(coalesce(p -> 'offsite' ->> 'provider', ''), 20),
      'target_name', left(p -> 'offsite' ->> 'target_name', 80),
      'retention', coalesce((p -> 'offsite' ->> 'retention') = 'true', false)) end
  ) end;
$$;

revoke all on function public.clean_maintenance(jsonb) from public, anon, authenticated;
