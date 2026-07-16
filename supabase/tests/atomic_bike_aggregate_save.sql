begin;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(56);

insert into public.tenants(id, shop_name) values
  ('99941000-0000-4000-8000-000000000001', 'Atomic Bike Tenant'),
  ('99941000-0000-4000-8000-000000000002', 'Other Bike Tenant');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99941000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'atomic-bike@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '99941000-0000-4000-8000-000000000001'
  ),
  now(),
  now()
);

insert into public.user_profiles(user_id, tenant_id, role) values (
  '99941000-0000-4000-8000-000000000099',
  '99941000-0000-4000-8000-000000000001',
  'admin'
);

insert into public.customers(id, tenant_id, name) values
  ('99941000-0000-4000-8000-000000000010', '99941000-0000-4000-8000-000000000001', 'Atomic Bike Customer'),
  ('99941000-0000-4000-8000-000000000012', '99941000-0000-4000-8000-000000000001', 'Same Tenant Other Customer'),
  ('99941000-0000-4000-8000-000000000020', '99941000-0000-4000-8000-000000000002', 'Other Tenant Customer');

insert into public.bike_brands(id, tenant_id, name) values
  ('99941000-0000-4000-8000-000000000041', '99941000-0000-4000-8000-000000000001', 'Atomic Brand A'),
  ('99941000-0000-4000-8000-000000000042', '99941000-0000-4000-8000-000000000001', 'Atomic Brand B');

insert into public.bike_models(id, tenant_id, brand_id, name) values (
  '99941000-0000-4000-8000-000000000051',
  '99941000-0000-4000-8000-000000000001',
  '99941000-0000-4000-8000-000000000041',
  'Atomic Model A'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99941000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99941000-0000-4000-8000-000000000099',
  true
);

select ok(
  not has_function_privilege(
    'anon',
    'public.save_bike_aggregate(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)',
    'execute'
  ),
  'anonymous callers cannot execute the aggregate writer'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.save_bike_aggregate(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)',
    'execute'
  ),
  'authenticated employees can execute the aggregate writer'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.save_bike_aggregate(text,uuid,uuid,timestamptz,timestamptz,jsonb,jsonb)',
    'execute'
  ),
  'service role is not granted a command whose authorization requires an employee JWT'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.bike_aggregate_save_operations',
    'insert'
  ),
  'clients cannot forge aggregate save receipts'
);
select ok(
  (
    select relrowsecurity
      from pg_class
     where oid = 'public.bike_aggregate_save_operations'::regclass
  ),
  'aggregate save receipts are protected by RLS'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.bike_aggregate_save_operations',
    'select'
  ),
  'clients can reconcile receipts only through the tenant-checked function'
);

update public.user_profiles
   set is_active = false
 where user_id = '99941000-0000-4000-8000-000000000099';
select throws_ok(
  $$
    select public.get_bike_aggregate(
      '99941000-0000-4000-8000-000000000011'
    )
  $$,
  '42501',
  'Exactly one active employee tenant is required',
  'an inactive employee profile cannot authorize an aggregate read'
);
update public.user_profiles
   set is_active = true
 where user_id = '99941000-0000-4000-8000-000000000099';

insert into public.user_profiles(user_id, tenant_id, role) values (
  '99941000-0000-4000-8000-000000000099',
  '99941000-0000-4000-8000-000000000002',
  'admin'
);
select throws_ok(
  $$
    select public.get_bike_aggregate(
      '99941000-0000-4000-8000-000000000011'
    )
  $$,
  '42501',
  'Exactly one active employee tenant is required',
  'ambiguous multi-tenant membership cannot pick a tenant nondeterministically'
);
delete from public.user_profiles
 where user_id = '99941000-0000-4000-8000-000000000099'
   and tenant_id = '99941000-0000-4000-8000-000000000002';

select throws_ok(
  $$
    select public.save_bike_aggregate(
      'bike-invalid-profile-map',
      '99941000-0000-4000-8000-000000000012',
      '99941000-0000-4000-8000-000000000010',
      null,
      null,
      '{"brand":"Invalid","model":"Profile"}'::jsonb,
      '{"technical_profile":null}'::jsonb
    )
  $$,
  'P0001',
  'Bicycle profile maps must be JSON objects',
  'JSON null cannot silently replace a profile map'
);

select throws_ok(
  $$
    select public.save_bike_aggregate(
      'bike-invalid-technical-values',
      '99941000-0000-4000-8000-000000000012',
      '99941000-0000-4000-8000-000000000010',
      null,
      null,
      '{"brand":"Invalid","model":"Technical"}'::jsonb,
      '{"technical_profile":{"values":[]}}'::jsonb
    )
  $$,
  'P0001',
  'Bicycle technical profile values, sources and confirmed maps must be JSON objects',
  'nested technical maps cannot silently change JSON type'
);

select throws_ok(
  $$
    select public.save_bike_aggregate(
      'bike-oversized-payload',
      '99941000-0000-4000-8000-000000000013',
      '99941000-0000-4000-8000-000000000010',
      null,
      null,
      jsonb_build_object('notes', repeat('x', 65537)),
      null
    )
  $$,
  'P0001',
  'Bicycle payload exceeds the 64 KiB command limit',
  'aggregate commands reject unexpectedly large identity payloads'
);

create temp table first_save on commit drop as
select public.save_bike_aggregate(
  'bike-attempt-1',
  '99941000-0000-4000-8000-000000000011',
  '99941000-0000-4000-8000-000000000010',
  null,
  null,
  jsonb_build_object(
    'brand_id', '99941000-0000-4000-8000-000000000041',
    'model_id', '99941000-0000-4000-8000-000000000051',
    'brand', 'Atomic',
    'model', 'Trail',
    'bike_type', 'mountain_hardtail',
    'color', 'Azul',
    'wheel_size', '29',
    'image_urls', jsonb_build_array()
  ),
  jsonb_build_object(
    'intake_profile', jsonb_build_object('primaryUse', 'trail'),
    'technical_profile', jsonb_build_object(
      'values', jsonb_build_object(
        'brakeType', 'hydraulic_disc',
        'drivetrainConfig', '1x12',
        'drivetrainSpeeds', 12
      ),
      'sources', jsonb_build_object(
        'brakeType', 'mechanic',
        'drivetrainConfig', 'mechanic',
        'drivetrainSpeeds', 'mechanic'
      ),
      'confirmed', jsonb_build_object(
        'brakeType', true,
        'drivetrainConfig', true,
        'drivetrainSpeeds', true
      )
    ),
    'summary_snapshot', jsonb_build_object('identityLine', 'Atomic Trail'),
    'last_confirmed_at', '2026-07-14T12:00:00Z'
  )
) payload;

select ok(
  not (select (payload->>'replayed')::boolean from first_save),
  'the first aggregate command is newly applied'
);
select is(
  (select count(*)::integer from public.bikes where id = '99941000-0000-4000-8000-000000000011'),
  1,
  'create writes exactly one bicycle identity row'
);
select is(
  (select count(*)::integer from public.bike_profiles where bike_id = '99941000-0000-4000-8000-000000000011'),
  1,
  'create writes exactly one technical profile row'
);
select is(
  (
    select technical_profile->'values'->>'drivetrainConfig'
      from public.bike_profiles
     where bike_id = '99941000-0000-4000-8000-000000000011'
  ),
  '1x12',
  'representative technical truth round-trips'
);
select ok(
  (
    select (technical_profile->'confirmed'->>'brakeType')::boolean
      from public.bike_profiles
     where bike_id = '99941000-0000-4000-8000-000000000011'
  ),
  'technical confirmation metadata round-trips'
);
select is(
  (
    select count(*)::integer
      from public.bike_aggregate_save_operations
     where operation_key = 'bike-attempt-1'
  ),
  1,
  'create stores one durable retry receipt'
);
select is(
  (
    select count(*)::integer
      from public.bike_events
     where bike_id = '99941000-0000-4000-8000-000000000011'
       and source = 'atomic_bike_save'
  ),
  2,
  'identity and profile audit events commit with the aggregate'
);
select is(
  (
    public.get_bike_aggregate('99941000-0000-4000-8000-000000000011')
      ->'profile'->'technical_profile'->'values'->>'brakeType'
  ),
  'hydraulic_disc',
  'the aggregate reader returns identity and profile together'
);

create temp table replay_save on commit drop as
select public.save_bike_aggregate(
  'bike-attempt-1',
  '99941000-0000-4000-8000-000000000011',
  '99941000-0000-4000-8000-000000000010',
  null,
  null,
  jsonb_build_object(
    'brand_id', '99941000-0000-4000-8000-000000000041',
    'model_id', '99941000-0000-4000-8000-000000000051',
    'brand', 'Atomic',
    'model', 'Trail',
    'bike_type', 'mountain_hardtail',
    'color', 'Azul',
    'wheel_size', '29',
    'image_urls', jsonb_build_array()
  ),
  jsonb_build_object(
    'intake_profile', jsonb_build_object('primaryUse', 'trail'),
    'technical_profile', jsonb_build_object(
      'values', jsonb_build_object(
        'brakeType', 'hydraulic_disc',
        'drivetrainConfig', '1x12',
        'drivetrainSpeeds', 12
      ),
      'sources', jsonb_build_object(
        'brakeType', 'mechanic',
        'drivetrainConfig', 'mechanic',
        'drivetrainSpeeds', 'mechanic'
      ),
      'confirmed', jsonb_build_object(
        'brakeType', true,
        'drivetrainConfig', true,
        'drivetrainSpeeds', true
      )
    ),
    'summary_snapshot', jsonb_build_object('identityLine', 'Atomic Trail'),
    'last_confirmed_at', '2026-07-14T12:00:00Z'
  )
) payload;

select ok(
  (select (payload->>'replayed')::boolean from replay_save),
  'same-key retry returns the committed aggregate after a lost response'
);
select is(
  (select payload->'bike'->>'id' from replay_save),
  '99941000-0000-4000-8000-000000000011',
  'replay returns the original bicycle identity'
);
select is(
  (select count(*)::integer from public.bikes where id = '99941000-0000-4000-8000-000000000011'),
  1,
  'replay creates no duplicate bicycle'
);
select is(
  (
    select count(*)::integer
      from public.bike_events
     where bike_id = '99941000-0000-4000-8000-000000000011'
       and source = 'atomic_bike_save'
  ),
  2,
  'replay creates no duplicate audit events'
);
select throws_ok(
  $$
    select public.save_bike_aggregate(
      'bike-attempt-1',
      '99941000-0000-4000-8000-000000000011',
      '99941000-0000-4000-8000-000000000010',
      null,
      null,
      '{"brand_id":"99941000-0000-4000-8000-000000000041","model_id":"99941000-0000-4000-8000-000000000051","brand":"Atomic","model":"Trail","bike_type":"mountain_hardtail","color":"Azul","wheel_size":"29","image_urls":[]}'::jsonb,
      '{"intake_profile":{"primaryUse":"trail"},"technical_profile":{"values":{"brakeType":"hydraulic_disc","drivetrainConfig":"1x12","drivetrainSpeeds":12},"sources":{"brakeType":"mechanic","drivetrainConfig":"mechanic","drivetrainSpeeds":"mechanic"},"confirmed":{"brakeType":true,"drivetrainConfig":true,"drivetrainSpeeds":true}},"summary_snapshot":{"identityLine":"Changed summary"},"last_confirmed_at":"2026-07-14T12:00:00Z"}'::jsonb
    )
  $$,
  '23000',
  'Bicycle save key was already used with different content',
  'the retry fingerprint includes the persisted summary snapshot'
);
select throws_ok(
  $$
    select public.save_bike_aggregate(
      'bike-attempt-1',
      '99941000-0000-4000-8000-000000000011',
      '99941000-0000-4000-8000-000000000010',
      null,
      null,
      '{"brand_id":"99941000-0000-4000-8000-000000000041","model_id":"99941000-0000-4000-8000-000000000051","brand":"Atomic","model":"Trail","bike_type":"mountain_hardtail","color":"Azul","wheel_size":"29","image_urls":[]}'::jsonb,
      '{"intake_profile":{"primaryUse":"trail"},"technical_profile":{"values":{"brakeType":"hydraulic_disc","drivetrainConfig":"1x12","drivetrainSpeeds":12},"sources":{"brakeType":"mechanic","drivetrainConfig":"mechanic","drivetrainSpeeds":"mechanic"},"confirmed":{"brakeType":true,"drivetrainConfig":true,"drivetrainSpeeds":true}},"summary_snapshot":{"identityLine":"Atomic Trail"},"last_confirmed_at":"2026-07-14T12:05:00Z"}'::jsonb
    )
  $$,
  '23000',
  'Bicycle save key was already used with different content',
  'the retry fingerprint includes the persisted confirmation timestamp'
);
select throws_ok(
  $$
    select public.save_bike_aggregate(
      'bike-attempt-1',
      '99941000-0000-4000-8000-000000000011',
      '99941000-0000-4000-8000-000000000010',
      null,
      null,
      '{"brand":"Atomic","model":"Changed"}'::jsonb,
      null
    )
  $$,
  '23000',
  'Bicycle save key was already used with different content',
  'one operation key cannot be reused for different content'
);

create temp table update_versions on commit drop as
select b.updated_at bike_updated_at, p.updated_at profile_updated_at
  from public.bikes b
  join public.bike_profiles p on p.bike_id = b.id
 where b.id = '99941000-0000-4000-8000-000000000011';

create temp table update_save on commit drop as
select public.save_bike_aggregate(
  'bike-attempt-2',
  '99941000-0000-4000-8000-000000000011',
  '99941000-0000-4000-8000-000000000010',
  (select bike_updated_at from update_versions),
  (select profile_updated_at from update_versions),
  '{"color":"Rojo"}'::jsonb,
  jsonb_build_object(
    'technical_profile', jsonb_build_object(
      'values', jsonb_build_object('brakeType', 'rim'),
      'sources', jsonb_build_object('brakeType', 'mechanic'),
      'confirmed', jsonb_build_object('brakeType', true)
    ),
    'last_confirmed_at', '2026-07-14T13:00:00Z'
  )
) payload;

select is(
  (select color from public.bikes where id = '99941000-0000-4000-8000-000000000011'),
  'Rojo',
  'update changes the existing identity row'
);
select is(
  (
    select technical_profile->'values'->>'brakeType'
      from public.bike_profiles
     where bike_id = '99941000-0000-4000-8000-000000000011'
  ),
  'rim',
  'update changes the existing profile row in the same command'
);
select is(
  (select count(*)::integer from public.bike_profiles where bike_id = '99941000-0000-4000-8000-000000000011'),
  1,
  'aggregate update never creates a replacement profile row'
);
select is(
  (
    public.get_bike_aggregate_save_operation('bike-attempt-1')
      ->'bike'->>'color'
  ),
  'Azul',
  'receipt reconciliation returns the immutable committed command snapshot'
);
select is(
  (
    public.get_bike_aggregate_save_operation('bike-attempt-1')
      ->'profile'->'technical_profile'->'values'->>'brakeType'
  ),
  'hydraulic_disc',
  'receipt reconciliation cannot absorb a later profile edit'
);
select is(
  (
    select intake_profile->>'primaryUse'
      from public.bike_profiles
     where bike_id = '99941000-0000-4000-8000-000000000011'
  ),
  'trail',
  'a partial profile update preserves omitted intake truth'
);
select is(
  (
    select summary_snapshot->>'identityLine'
      from public.bike_profiles
     where bike_id = '99941000-0000-4000-8000-000000000011'
  ),
  'Atomic Trail',
  'a partial profile update preserves an omitted derived summary'
);

create temp table pair_version on commit drop as
select updated_at
  from public.bikes
 where id = '99941000-0000-4000-8000-000000000011';
select throws_ok(
  format(
    'select public.save_bike_aggregate(%L,%L::uuid,%L::uuid,%L::timestamptz,null,%L::jsonb,null)',
    'bike-invalid-brand-model-pair',
    '99941000-0000-4000-8000-000000000011',
    '99941000-0000-4000-8000-000000000010',
    (select updated_at from pair_version),
    '{"brand_id":"99941000-0000-4000-8000-000000000042"}'
  ),
  '23000',
  'Bicycle model not found for current tenant or effective brand',
  'a partial brand change cannot retain a model owned by another brand'
);
select is(
  (
    select brand_id::text
      from public.bikes
     where id = '99941000-0000-4000-8000-000000000011'
  ),
  '99941000-0000-4000-8000-000000000041',
  'rejected brand-model mismatch leaves the original identity pair intact'
);

create temp table ownership_version on commit drop as
select updated_at
  from public.bikes
 where id = '99941000-0000-4000-8000-000000000011';
select throws_ok(
  format(
    'select public.save_bike_aggregate(%L,%L::uuid,%L::uuid,%L::timestamptz,null,%L::jsonb,null)',
    'bike-owner-reassignment',
    '99941000-0000-4000-8000-000000000011',
    '99941000-0000-4000-8000-000000000012',
    (select updated_at from ownership_version),
    '{"notes":"Ownership reassignment attempt"}'
  ),
  '23000',
  'Bicycle customer cannot be reassigned through the aggregate save command',
  'normal aggregate editing cannot rewrite durable bicycle ownership'
);
select is(
  (
    select customer_id::text
      from public.bikes
     where id = '99941000-0000-4000-8000-000000000011'
  ),
  '99941000-0000-4000-8000-000000000010',
  'rejected ownership reassignment preserves the original customer'
);

create temp table profile_stale_baseline on commit drop as
select
  b.updated_at as bike_updated_at,
  p.updated_at as profile_updated_at,
  (
    select count(*)::integer
      from public.bike_events e
     where e.bike_id = b.id
       and e.source = 'atomic_bike_save'
  ) as event_count
from public.bikes b
join public.bike_profiles p on p.bike_id = b.id
where b.id = '99941000-0000-4000-8000-000000000011';

alter table public.bike_profiles disable trigger trg_bike_profiles_updated_at;
update public.bike_profiles
   set updated_at = updated_at + interval '1 second'
 where bike_id = '99941000-0000-4000-8000-000000000011';
alter table public.bike_profiles enable trigger trg_bike_profiles_updated_at;

select throws_ok(
  format(
    'select public.save_bike_aggregate(%L,%L::uuid,%L::uuid,%L::timestamptz,%L::timestamptz,%L::jsonb,%L::jsonb)',
    'bike-profile-only-stale',
    '99941000-0000-4000-8000-000000000011',
    '99941000-0000-4000-8000-000000000010',
    (select bike_updated_at from profile_stale_baseline),
    (select profile_updated_at from profile_stale_baseline),
    '{"color":"Morado"}',
    '{"technical_profile":{"values":{"brakeType":"mechanical_disc"}}}'
  ),
  '40001',
  'Bicycle profile changed since it was loaded; reload before saving',
  'a current bike version cannot bypass a stale profile version'
);
select is(
  (select color from public.bikes where id = '99941000-0000-4000-8000-000000000011'),
  'Rojo',
  'profile-only stale rejection rolls the preceding bicycle update back'
);
select is(
  (
    select technical_profile->'values'->>'brakeType'
      from public.bike_profiles
     where bike_id = '99941000-0000-4000-8000-000000000011'
  ),
  'rim',
  'profile-only stale rejection preserves the newer technical truth'
);
select is(
  (
    select count(*)::integer
      from public.bike_aggregate_save_operations
     where operation_key = 'bike-profile-only-stale'
  ),
  0,
  'profile-only stale rejection creates no success receipt'
);
select is(
  (
    select count(*)::integer
      from public.bike_events
     where bike_id = '99941000-0000-4000-8000-000000000011'
       and source = 'atomic_bike_save'
  ),
  (select event_count from profile_stale_baseline),
  'profile-only stale rejection creates no audit event'
);

-- pgTAP keeps the whole file in one transaction, while the production RPC is
-- called in separate request transactions. Move the stored versions forward
-- explicitly so the next assertion represents a genuinely stale editor.
alter table public.bikes disable trigger trg_bikes_updated_at;
alter table public.bike_profiles disable trigger trg_bike_profiles_updated_at;
update public.bikes
   set updated_at = updated_at + interval '1 second'
 where id = '99941000-0000-4000-8000-000000000011';
update public.bike_profiles
   set updated_at = updated_at + interval '1 second'
 where bike_id = '99941000-0000-4000-8000-000000000011';
alter table public.bikes enable trigger trg_bikes_updated_at;
alter table public.bike_profiles enable trigger trg_bike_profiles_updated_at;

select throws_ok(
  format(
    'select public.save_bike_aggregate(%L,%L::uuid,%L::uuid,%L::timestamptz,%L::timestamptz,%L::jsonb,%L::jsonb)',
    'bike-attempt-stale',
    '99941000-0000-4000-8000-000000000011',
    '99941000-0000-4000-8000-000000000010',
    (select bike_updated_at from update_versions),
    (select profile_updated_at from update_versions),
    '{"color":"Verde"}',
    '{"technical_profile":{"values":{"brakeType":"mechanical_disc"}}}'
  ),
  '40001',
  'Bicycle changed since it was loaded; reload before saving',
  'a stale editor cannot overwrite newer bicycle/profile truth'
);
select is(
  (select color from public.bikes where id = '99941000-0000-4000-8000-000000000011'),
  'Rojo',
  'stale save leaves the newer identity unchanged'
);

create temp table preserve_version on commit drop as
select updated_at from public.bikes
 where id = '99941000-0000-4000-8000-000000000011';
select lives_ok(
  format(
    'select public.save_bike_aggregate(%L,%L::uuid,%L::uuid,%L::timestamptz,null,%L::jsonb,null)',
    'bike-attempt-identity-only',
    '99941000-0000-4000-8000-000000000011',
    '99941000-0000-4000-8000-000000000010',
    (select updated_at from preserve_version),
    '{"notes":"Identity-only edit"}'
  ),
  'identity-only update can intentionally preserve an existing profile'
);
select is(
  (
    select technical_profile->'values'->>'brakeType'
      from public.bike_profiles
     where bike_id = '99941000-0000-4000-8000-000000000011'
  ),
  'rim',
  'null profile payload never erases the existing technical sheet'
);

select throws_ok(
  $$
    select public.save_bike_aggregate(
      'bike-other-tenant',
      '99941000-0000-4000-8000-000000000021',
      '99941000-0000-4000-8000-000000000020',
      null,
      null,
      '{"brand":"Forbidden","model":"Bike"}'::jsonb,
      null
    )
  $$,
  '42501',
  'Bicycle customer not found for current tenant',
  'the aggregate writer rejects a customer from another tenant'
);

create or replace function pg_temp.reject_test_bike_profile()
returns trigger
language plpgsql
as $$
begin
  if new.bike_id = '99941000-0000-4000-8000-000000000031'::uuid then
    raise exception 'Forced bicycle profile failure';
  end if;
  return new;
end;
$$;
create trigger test_reject_atomic_bike_profile
  before insert or update on public.bike_profiles
  for each row execute function pg_temp.reject_test_bike_profile();

select throws_ok(
  $$
    select public.save_bike_aggregate(
      'bike-forced-failure',
      '99941000-0000-4000-8000-000000000031',
      '99941000-0000-4000-8000-000000000010',
      null,
      null,
      '{"brand":"Rollback","model":"Bike"}'::jsonb,
      '{"technical_profile":{"values":{"brakeType":"rim"}}}'::jsonb
    )
  $$,
  'P0001',
  'Forced bicycle profile failure',
  'a profile failure aborts the complete aggregate command'
);
select is(
  (select count(*)::integer from public.bikes where id = '99941000-0000-4000-8000-000000000031'),
  0,
  'profile failure rolls the bicycle identity insert back'
);
select is(
  (
    select count(*)::integer
      from public.bike_aggregate_save_operations
     where operation_key = 'bike-forced-failure'
  ),
  0,
  'profile failure leaves no false success receipt'
);
select is(
  (
    select count(*)::integer
      from public.bike_events
     where bike_id = '99941000-0000-4000-8000-000000000031'
  ),
  0,
  'profile failure leaves no partial audit event'
);

create or replace function pg_temp.reject_test_bike_receipt()
returns trigger
language plpgsql
as $$
begin
  if new.operation_key = 'bike-late-receipt-failure' then
    raise exception 'Forced bicycle receipt failure';
  end if;
  return new;
end;
$$;
create trigger test_reject_atomic_bike_receipt
  before insert on public.bike_aggregate_save_operations
  for each row execute function pg_temp.reject_test_bike_receipt();

select throws_ok(
  $$
    select public.save_bike_aggregate(
      'bike-late-receipt-failure',
      '99941000-0000-4000-8000-000000000061',
      '99941000-0000-4000-8000-000000000010',
      null,
      null,
      '{"brand":"Late","model":"Rollback"}'::jsonb,
      '{"technical_profile":{"values":{"brakeType":"rim"}}}'::jsonb
    )
  $$,
  'P0001',
  'Forced bicycle receipt failure',
  'a final receipt failure aborts the complete aggregate command'
);
select is(
  (select count(*)::integer from public.bikes where id = '99941000-0000-4000-8000-000000000061'),
  0,
  'late receipt failure rolls the bicycle row back'
);
select is(
  (select count(*)::integer from public.bike_profiles where bike_id = '99941000-0000-4000-8000-000000000061'),
  0,
  'late receipt failure rolls the profile row back'
);
select is(
  (select count(*)::integer from public.bike_events where bike_id = '99941000-0000-4000-8000-000000000061'),
  0,
  'late receipt failure rolls already-inserted events back'
);
select is(
  (
    select count(*)::integer
      from public.bike_aggregate_save_operations
     where operation_key = 'bike-late-receipt-failure'
  ),
  0,
  'late receipt failure leaves no false success receipt'
);

select * from finish();
rollback;
