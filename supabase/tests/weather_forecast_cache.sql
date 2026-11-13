-- The last weather forecast of each shop belongs to the server: the
-- `weather-forecast` Edge Function keeps it with the service key, and no
-- session of the ERP or of the store reads or writes it (2026-11-12).
begin;

select plan(9);

insert into public.tenants (id, shop_name) values
  ('c11a0000-0000-4000-8000-000000000001', 'Weather Cache Tenant'),
  ('c11a0000-0000-4000-8000-000000000002', 'Weather Cache Other Tenant');

select ok(
  (select relrowsecurity from pg_class
    where oid = 'public.weather_forecast_cache'::regclass),
  'the cache has row level security on'
);

select is(
  (select count(*)::int from pg_policies
    where schemaname = 'public' and tablename = 'weather_forecast_cache'),
  0,
  'and no policy opens it to a session'
);

select is(
  (select count(*)::int
     from unnest(array['anon', 'authenticated']) as role_name,
          unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
                       'REFERENCES', 'TRIGGER']) as privilege
    where has_table_privilege(role_name, 'public.weather_forecast_cache', privilege)),
  0,
  'neither the store nor an employee holds any of the seven privileges'
);

set local role service_role;

select lives_ok(
  $$insert into public.weather_forecast_cache (
      tenant_id, provider, latitude, longitude, payload,
      source_last_modified, fetched_at, checked_at, expires_at
    ) values (
      'c11a0000-0000-4000-8000-000000000001',
      'met.no/locationforecast/2.0/complete', -33.0252, -71.5623,
      '{"properties": {"timeseries": [{"time": "2026-11-12T22:00:00Z"}]}}',
      'Thu, 12 Nov 2026 22:40:12 GMT', now(), now(), now() + interval '30 minutes'
    )$$,
  'the function keeps a forecast with the service key'
);

select throws_ok(
  $$insert into public.weather_forecast_cache (
      tenant_id, provider, latitude, longitude, payload,
      fetched_at, checked_at, expires_at
    ) values (
      'c11a0000-0000-4000-8000-000000000001', 'met.no', -33.5, -70.6, '{}',
      now(), now(), now()
    )$$,
  '23505',
  null,
  'one forecast per shop'
);

select throws_ok(
  $$insert into public.weather_forecast_cache (
      tenant_id, provider, latitude, longitude, payload,
      fetched_at, checked_at, expires_at
    ) values (
      'c11a0000-0000-4000-8000-000000000002', 'met.no', 91, -70.6, '{}',
      now(), now(), now()
    )$$,
  '23514',
  null,
  'a latitude outside the globe is refused'
);

reset role;
set local role authenticated;

select throws_ok(
  $$select tenant_id from public.weather_forecast_cache$$,
  '42501',
  null,
  'an employee session cannot read the cache'
);

reset role;
set local role anon;

select throws_ok(
  $$select tenant_id from public.weather_forecast_cache$$,
  '42501',
  null,
  'a visitor cannot read the cache'
);

reset role;

select is(
  (select confdeltype::text from pg_constraint
    where conrelid = 'public.weather_forecast_cache'::regclass
      and contype = 'f'
      and confrelid = 'public.tenants'::regclass),
  'c',
  'a shop that is deleted takes its forecast with it'
);

select * from finish();
rollback;
