begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(11);

select has_column(
  'public',
  'mechanic_jobs',
  'created_by',
  'workshop jobs retain their registration actor'
);

select col_type_is(
  'public',
  'mechanic_jobs',
  'created_by',
  'uuid',
  'the job actor uses the canonical Auth user identity'
);

select is(
  (
    select pg_get_expr(default_row.adbin, default_row.adrelid)
    from pg_attrdef default_row
    join pg_attribute attribute
      on attribute.attrelid = default_row.adrelid
     and attribute.attnum = default_row.adnum
    where default_row.adrelid = 'public.mechanic_jobs'::regclass
      and attribute.attname = 'created_by'
  ),
  'auth.uid()',
  'new jobs default to the authenticated request identity'
);

select is(
  (
    select constraint_definition.delete_rule
    from information_schema.referential_constraints constraint_definition
    where constraint_definition.constraint_schema = 'public'
      and constraint_definition.constraint_name =
        'mechanic_jobs_created_by_fkey'
  ),
  'SET NULL',
  'removing an Auth identity preserves the historical job'
);

select has_trigger(
  'public',
  'mechanic_jobs',
  'trg_mechanic_jobs_created_by',
  'a server trigger owns job registration identity'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.set_mechanic_job_created_by()',
    'EXECUTE'
  ),
  'authenticated clients cannot invoke the actor trigger directly'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_mechanic_job_erp_notification()',
    'EXECUTE'
  ),
  'authenticated clients cannot invoke the job notification trigger directly'
);

insert into public.tenants (id, shop_name)
values (
  '98741000-0000-4000-8000-000000000001',
  'Mechanic Job Notification Actor Test'
);

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values
  (
    '98741000-0000-4000-8000-000000000098',
    'authenticated',
    'authenticated',
    'spoofed-job-actor@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object('name', 'Identidad no autorizada'),
    now(),
    now()
  ),
  (
    '98741000-0000-4000-8000-000000000099',
    'authenticated',
    'authenticated',
    'job-actor@example.invalid',
    '',
    now(),
    '{}'::jsonb,
    jsonb_build_object('name', 'Tania Registradora'),
    now(),
    now()
  );

insert into public.user_profiles (user_id, tenant_id, role)
values (
  '98741000-0000-4000-8000-000000000099',
  '98741000-0000-4000-8000-000000000001',
  'admin'
);

insert into public.customers (id, tenant_id, name)
values (
  '98741000-0000-4000-8000-000000000010',
  '98741000-0000-4000-8000-000000000001',
  'Cliente de notificación'
);

insert into public.bikes (
  id,
  tenant_id,
  customer_id,
  brand,
  model,
  color
) values (
  '98741000-0000-4000-8000-000000000020',
  '98741000-0000-4000-8000-000000000001',
  '98741000-0000-4000-8000-000000000010',
  'Oxford',
  'Orion 4',
  'Negro'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '98741000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98741000-0000-4000-8000-000000000099',
  true
);

insert into public.mechanic_jobs (
  id,
  tenant_id,
  customer_id,
  bike_id,
  job_number,
  job_type,
  workflow_kind,
  intake_kind,
  client_request,
  created_by
) values (
  '98741000-0000-4000-8000-000000000030',
  '98741000-0000-4000-8000-000000000001',
  '98741000-0000-4000-8000-000000000010',
  '98741000-0000-4000-8000-000000000020',
  'PG-NOTIFY-ACTOR-001',
  'service',
  'service',
  'bike',
  'Revisión de frenos',
  '98741000-0000-4000-8000-000000000098'
);

select is(
  (
    select created_by
    from public.mechanic_jobs
    where id = '98741000-0000-4000-8000-000000000030'
  ),
  '98741000-0000-4000-8000-000000000099'::uuid,
  'the server replaces a spoofed actor with the authenticated user'
);

select is(
  (
    select data->>'recorded_by_name'
    from public.erp_notifications
    where entity_type = 'mechanic_job'
      and entity_id = '98741000-0000-4000-8000-000000000030'
  ),
  'Tania Registradora',
  'the durable job notification carries the tenant-safe actor name'
);

select is(
  (
    select data->>'client_request'
    from public.erp_notifications
    where entity_type = 'mechanic_job'
      and entity_id = '98741000-0000-4000-8000-000000000030'
  ),
  'Revisión de frenos',
  'actor enrichment preserves the existing job disclosure payload'
);

select is(
  (
    select count(*)::integer
    from public.erp_notifications
    where tenant_id = '98741000-0000-4000-8000-000000000001'
      and entity_type = 'mechanic_job'
      and entity_id = '98741000-0000-4000-8000-000000000030'
  ),
  1,
  'one job creates exactly one durable notification'
);

select * from finish();
rollback;
