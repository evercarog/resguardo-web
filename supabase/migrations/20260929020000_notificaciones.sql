-- Notificaciones push: suscripciones de cada dispositivo y avisos cuando el
-- estado de un repositorio o de un equipo empeora (o se recupera).

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Suscripciones Web Push (una por navegador/dispositivo donde se activen).
create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  endpoint text not null unique check (endpoint ~ '^https://'),
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now()
);

alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from anon;

create policy "suscripciones propias" on public.push_subscriptions
  for all to authenticated
  using (owner = auth.uid() and public.is_mfa())
  with check (owner = auth.uid() and public.is_mfa());

-- Último nivel notificado de cada aviso, para avisar solo cuando cambia.
create table public.alert_state (
  owner uuid not null references auth.users on delete cascade,
  alert_key text not null,
  level text not null,
  notified_at timestamptz not null default now(),
  primary key (owner, alert_key)
);
alter table public.alert_state enable row level security;
revoke all on public.alert_state from anon, authenticated;

-- Avisos actuales (misma lógica que la web: con retraso a 1,25× el intervalo
-- esperado + 1 h, atrasada a 2× + 1 h; equipo sin conexión tras 60 min).
-- Solo la usa la función de notificaciones (con la clave de servicio).
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
      coalesce(
        r.expected_hours,
        case r.schedule ->> 'kind'
          when 'hours' then (r.schedule ->> 'every')::int
          when 'monitor' then (r.schedule ->> 'every')::int
          when 'weekly' then 168
          else 24
        end
      ) as expected,
      coalesce(r.last_snapshot_at, (r.last_run ->> 'finished')::timestamptz) as last_at,
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
      when 'ok' then device_name || ': última copia ' || to_char(last_at at time zone 'America/Bogota', 'DD/MM HH24:MI')
      else device_name || ': sin copias desde ' || to_char(last_at at time zone 'America/Bogota', 'DD/MM HH24:MI')
    end,
    '/repo/' || device_id || '/' || repo_id
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

-- Cada 10 minutos, la función "notify" revisa los avisos y envía los nuevos.
-- (La función es idempotente: llamarla de más no repite avisos.)
select cron.schedule(
  'resguardo-avisos',
  '*/10 * * * *',
  $$ select net.http_post(
       url := 'https://ltuqkovbkmhlyjhsbuff.supabase.co/functions/v1/notify',
       headers := '{"Content-Type": "application/json"}'::jsonb,
       body := '{}'::jsonb
     ) $$
);
