-- Ajustes tras la revisión:
-- - Fechas y números "especiales" (infinity, NaN, fechas futuras) no cuentan
--   como datos: un informe con ellos no puede dejar un repositorio "al día"
--   para siempre ni mostrar "NaN".
-- - El límite de 10 suscripciones push no impide volver a guardar una que ya
--   existe, y deja sitio quitando la más antigua de la cuenta.

create or replace function public.try_ts(p text)
returns timestamptz language plpgsql stable set search_path = '' as $$
declare
  v timestamptz;
begin
  if p is null then return null; end if;
  v := p::timestamptz;
  if not isfinite(v) or v > now() + interval '1 day' or v < '2000-01-01'::timestamptz then
    return null;
  end if;
  return v;
exception when others then
  return null;
end;
$$;

create or replace function public.try_real(p text)
returns real language plpgsql immutable set search_path = '' as $$
declare
  v real;
begin
  if p is null then return null; end if;
  v := p::real;
  if v = 'NaN'::real or v = 'Infinity'::real or v = '-Infinity'::real then
    return null;
  end if;
  return greatest(v, 0);
exception when others then
  return null;
end;
$$;

revoke all on function public.try_ts(text) from public, anon, authenticated;
revoke all on function public.try_real(text) from public, anon, authenticated;

create or replace function public.push_subscriptions_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Volver a guardar la misma suscripción (upsert) no cuenta como nueva.
  if exists (select 1 from public.push_subscriptions where endpoint = new.endpoint) then
    return new;
  end if;
  -- Al llegar al límite se quita la más antigua de la cuenta (suele ser de un
  -- navegador reinstalado que ya no existe).
  delete from public.push_subscriptions
  where id in (
    select id from public.push_subscriptions
    where owner = new.owner
    order by created_at desc
    offset 9
  );
  return new;
end;
$$;
revoke all on function public.push_subscriptions_limit() from public, anon, authenticated;
