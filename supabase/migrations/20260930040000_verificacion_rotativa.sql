-- Verificación rotativa: el equipo informa en maintenance.verify
-- "rotate_parts" (0 = no; 2–52: todo el repositorio en N verificaciones),
-- "next_part" y "last_full_at". clean_maintenance (la de
-- 20260930020000_subida_frenada.sql) los descartaba: se conservan, con
-- conversiones seguras. device_report la llama por su nombre y no cambia.

create or replace function public.clean_maintenance(p jsonb)
returns jsonb language sql stable set search_path = '' as $$
  select case when jsonb_typeof(p) <> 'object' then null
  else jsonb_build_object(
    'verify', case when jsonb_typeof(p -> 'verify') = 'object' then jsonb_build_object(
      'schedule', public.clean_schedule(p -> 'verify' -> 'schedule'),
      'subset_percent', coalesce(public.try_int(p -> 'verify' ->> 'subset_percent', 0, 100), 0),
      -- Verificación rotativa: todo el repositorio en N partes (0 = no; 2–52).
      'rotate_parts', case when public.try_int(p -> 'verify' ->> 'rotate_parts', 0, 52) >= 2
        then public.try_int(p -> 'verify' ->> 'rotate_parts', 0, 52) else 0 end,
      'next_part', public.try_int(p -> 'verify' ->> 'next_part', 0, 52),
      'last_full_at', public.try_ts(p -> 'verify' ->> 'last_full_at')) end,
    'offsite', case when jsonb_typeof(p -> 'offsite') = 'object' then jsonb_build_object(
      'schedule', public.clean_offsite_schedule(p -> 'offsite' -> 'schedule'),
      'provider', left(coalesce(p -> 'offsite' ->> 'provider', ''), 20),
      'target_name', left(p -> 'offsite' ->> 'target_name', 80),
      'retention', coalesce((p -> 'offsite' ->> 'retention') = 'true', false)) end
  ) end;
$$;

revoke all on function public.clean_maintenance(jsonb) from public, anon, authenticated;
