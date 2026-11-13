-- The daily briefing shows the shop's weather (owner, 2026-11-12).
--
-- The forecast comes from MET Norway, whose terms ask that an app reads it
-- through a backend, that nobody repeats a request before its `Expires`, and
-- that a repeat carries `If-Modified-Since`. So the last answer of each shop
-- is kept here, and the `weather-forecast` Edge Function is the only reader
-- and writer: the ERP never reads this table.
--
-- Additive: nothing published reads or writes it.

create table if not exists public.weather_forecast_cache (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  provider text not null,
  latitude numeric(7, 4) not null,
  longitude numeric(8, 4) not null,
  payload jsonb not null,
  source_last_modified text,
  fetched_at timestamptz not null,
  checked_at timestamptz not null,
  expires_at timestamptz not null,
  refresh_claimed_at timestamptz,
  constraint weather_forecast_cache_latitude_is_real
    check (latitude between -90 and 90),
  constraint weather_forecast_cache_longitude_is_real
    check (longitude between -180 and 180)
);

comment on table public.weather_forecast_cache is
  'Last weather forecast of each shop, as its provider answered it. Read and written only by the weather-forecast Edge Function.';
comment on column public.weather_forecast_cache.source_last_modified is
  'The provider''s Last-Modified header, sent back as If-Modified-Since.';
comment on column public.weather_forecast_cache.fetched_at is
  'When this payload was downloaded.';
comment on column public.weather_forecast_cache.checked_at is
  'Last time the provider confirmed the payload, by sending it or by answering that it had not changed.';
comment on column public.weather_forecast_cache.expires_at is
  'The provider must not be asked again before this instant.';
comment on column public.weather_forecast_cache.refresh_claimed_at is
  'Set by the one caller that is refreshing an expired row, cleared when it finishes.';

alter table public.weather_forecast_cache enable row level security;
revoke all on public.weather_forecast_cache from public, anon, authenticated;
grant all on public.weather_forecast_cache to service_role;
