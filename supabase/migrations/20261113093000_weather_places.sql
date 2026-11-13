-- The weather tab of the daily briefing shows more places than the shop
-- (owner, 2026-11-13: «haz que se puedan agregar más localidades, para poder
-- agregar Seattle también»).
--
-- Each person keeps a short list of places, and the last forecast of every
-- place is kept as the shop's already was: one row per shop and place. The
-- `weather-forecast` Edge Function is still the only reader and writer of
-- both tables.
--
-- Additive for what is published: the shop's own row keeps its place under
-- the key `shop`.

alter table public.weather_forecast_cache
  add column if not exists place_key text not null default 'shop';

comment on column public.weather_forecast_cache.place_key is
  '`shop` for the shop''s own place; `latitude,longitude` with four decimals for a place a person added.';

do $$
begin
  if exists (
    select 1 from pg_constraint
     where conrelid = 'public.weather_forecast_cache'::regclass
       and contype = 'p'
       and pg_get_constraintdef(oid) = 'PRIMARY KEY (tenant_id)'
  ) then
    alter table public.weather_forecast_cache
      drop constraint weather_forecast_cache_pkey;
    alter table public.weather_forecast_cache
      add constraint weather_forecast_cache_pkey primary key (tenant_id, place_key);
  end if;
end
$$;

create table if not exists public.weather_places (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  region text,
  latitude numeric(7, 4) not null,
  longitude numeric(8, 4) not null,
  time_zone text not null,
  created_at timestamptz not null default now(),
  constraint weather_places_name_is_short
    check (char_length(btrim(name)) between 1 and 80),
  constraint weather_places_region_is_short
    check (region is null or char_length(region) <= 120),
  constraint weather_places_latitude_is_real
    check (latitude between -90 and 90),
  constraint weather_places_longitude_is_real
    check (longitude between -180 and 180),
  constraint weather_places_time_zone_is_named
    check (char_length(time_zone) between 1 and 64),
  constraint weather_places_once_per_person
    unique (tenant_id, user_id, latitude, longitude)
);

comment on table public.weather_places is
  'Places a person added to the weather tab of the daily briefing, besides the shop. Read and written only by the weather-forecast Edge Function.';
comment on column public.weather_places.time_zone is
  'IANA zone of the place, resolved when it was added; its hours are shown on that clock.';

create index if not exists weather_places_of_person
  on public.weather_places (tenant_id, user_id, created_at);

alter table public.weather_places enable row level security;
revoke all on public.weather_places from public, anon, authenticated;
grant all on public.weather_places to service_role;
