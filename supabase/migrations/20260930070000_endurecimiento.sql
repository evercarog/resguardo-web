-- Repaso de seguridad (defensa en profundidad; nada de esto cambia lo que
-- la web o los equipos pueden hacer hoy).
--
-- 1. Permisos de tabla mínimos. Supabase concede por defecto todo a anon y
--    authenticated en las tablas nuevas; la RLS ya bloquea lo que no tiene
--    política, pero TRUNCATE no pasa por la RLS y sobra igualmente. Las
--    personas solo leen repos, runs, snapshots y pairing_codes (los escriben
--    las funciones de los equipos) y no crean equipos (solo device_pair).
-- 2. notify_cron_ok compara huellas SHA-256 en lugar del secreto en claro
--    (el tiempo de la comparación ya no depende del secreto).
-- 3. Se validan las restricciones de push_subscriptions que se añadieron
--    como NOT VALID (servicio de push conocido y tamaños acotados); hoy no
--    hay filas que las incumplan.

-- 1. Permisos de tabla
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;

revoke all on public.clients, public.devices, public.pairing_codes, public.repos, public.runs,
  public.snapshots, public.push_subscriptions, public.alert_state, public.notify_lease,
  public.device_secrets from anon;

revoke insert, update, delete on public.repos, public.runs, public.snapshots, public.pairing_codes from authenticated;
revoke insert on public.devices from authenticated;

-- 2. Secreto de pg_cron (la de 20260929030000_seguridad.sql, comparando huellas)
create or replace function public.notify_cron_ok(p_secret text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from vault.decrypted_secrets
    where name = 'notify_cron'
      and extensions.digest(decrypted_secret, 'sha256') = extensions.digest(coalesce(p_secret, ''), 'sha256')
  );
$$;

revoke all on function public.notify_cron_ok(text) from public, anon, authenticated;
grant execute on function public.notify_cron_ok(text) to service_role;

-- 3. Suscripciones push
alter table public.push_subscriptions validate constraint push_endpoint_conocido;
alter table public.push_subscriptions validate constraint push_claves_acotadas;
