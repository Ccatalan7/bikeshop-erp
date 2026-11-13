-- The places a person adds to the weather tab belong to the server: only the
-- `weather-forecast` Edge Function reads and writes them, with the service
-- key, and each place has its own kept forecast (2026-11-13).
begin;

select plan(7);

insert into public.tenants (id, shop_name) values
  ('c11b0000-0000-4000-8000-000000000001', 'Weather Places Tenant');
insert into auth.users (id, email) values
  ('c11b0000-0000-4000-8000-0000000000a1', 'weather-places@example.test');

select ok(
  (select relrowsecurity from pg_class
    where oid = 'public.weather_places'::regclass),
  'the places have row level security on'
);

select is(
  (select count(*)::int from pg_policies
    where schemaname = 'public' and tablename = 'weather_places'),
  0,
  'and no policy opens them to a session'
);

select is(
  (select count(*)::int
     from unnest(array['anon', 'authenticated']) as role_name,
          unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
                       'REFERENCES', 'TRIGGER']) as privilege
    where has_table_privilege(role_name, 'public.weather_places', privilege)),
  0,
  'no session role holds a privilege on them'
);

set local role service_role;

select lives_ok(
  $$insert into public.weather_places (
      tenant_id, user_id, name, region, latitude, longitude, time_zone
    ) values (
      'c11b0000-0000-4000-8000-000000000001',
      'c11b0000-0000-4000-8000-0000000000a1',
      'Seattle', 'Washington, Estados Unidos', 47.6038, -122.3301,
      'America/Los_Angeles'
    )$$,
  'the function keeps a place for a person'
);

select throws_ok(
  $$insert into public.weather_places (
      tenant_id, user_id, name, latitude, longitude, time_zone
    ) values (
      'c11b0000-0000-4000-8000-000000000001',
      'c11b0000-0000-4000-8000-0000000000a1',
      'Seattle otra vez', 47.6038, -122.3301, 'America/Los_Angeles'
    )$$,
  '23505',
  null,
  'the same place once per person'
);

select lives_ok(
  $$insert into public.weather_forecast_cache (
      tenant_id, place_key, provider, latitude, longitude, payload,
      fetched_at, checked_at, expires_at
    ) values
      ('c11b0000-0000-4000-8000-000000000001', 'shop', 'met.no', -33.0252,
       -71.5623, '{}', now(), now(), now()),
      ('c11b0000-0000-4000-8000-000000000001', '47.6038,-122.3301', 'met.no',
       47.6038, -122.3301, '{}', now(), now(), now())$$,
  'a shop keeps one forecast per place'
);

reset role;

select is(
  (select confdeltype::text from pg_constraint
    where conrelid = 'public.weather_places'::regclass
      and contype = 'f'
      and pg_get_constraintdef(oid) like 'FOREIGN KEY (user_id)%'),
  'c',
  'a person who leaves takes their places along'
);

select * from finish();
rollback;
