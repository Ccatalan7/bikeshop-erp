begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(18);

insert into public.tenants(id, shop_name)
values ('99500000-0000-4000-8000-000000000001', 'Workshop Archive Test');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99500000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'job-archive@example.invalid', '', now(),
  '{}', '{}', now(), now()
);

delete from public.user_profiles
where user_id = '99500000-0000-4000-8000-000000000099';

insert into public.user_profiles(
  user_id, tenant_id, role, permissions, is_active
) values (
  '99500000-0000-4000-8000-000000000099',
  '99500000-0000-4000-8000-000000000001',
  'admin', '{}'::jsonb, true
);

insert into public.customers(id, tenant_id, name)
values (
  '99500000-0000-4000-8000-000000000010',
  '99500000-0000-4000-8000-000000000001',
  'Archive Customer'
);

insert into public.bikes(id, tenant_id, customer_id, brand, model)
values (
  '99500000-0000-4000-8000-000000000020',
  '99500000-0000-4000-8000-000000000001',
  '99500000-0000-4000-8000-000000000010',
  'Test', 'Archive Bike'
);

insert into public.mechanic_jobs(
  id, tenant_id, job_number, customer_id, bike_id,
  status, job_type, workflow_kind, intake_kind, quotation_status
) values (
  '99500000-0000-4000-8000-000000000030',
  '99500000-0000-4000-8000-000000000001',
  'PG-ARCHIVE-001',
  '99500000-0000-4000-8000-000000000010',
  '99500000-0000-4000-8000-000000000020',
  'PENDIENTE', 'quotation', 'quotation', 'bike', 'pending'
);

insert into public.mechanic_job_bikes(
  id, tenant_id, job_id, bike_id, order_index
) values (
  '99500000-0000-4000-8000-000000000040',
  '99500000-0000-4000-8000-000000000001',
  '99500000-0000-4000-8000-000000000030',
  '99500000-0000-4000-8000-000000000020', 0
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, item_type, quantity, unit_price,
  total_price
) values (
  '99500000-0000-4000-8000-000000000050',
  '99500000-0000-4000-8000-000000000001',
  '99500000-0000-4000-8000-000000000030',
  'Archive service', 'service', 1, 10000, 10000
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99500000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99500000-0000-4000-8000-000000000099',
  true
);

select throws_ok($$
  update public.mechanic_jobs
  set deleted_at = clock_timestamp(),
      deleted_by = '99500000-0000-4000-8000-000000000099',
      archive_reason = 'Bypass',
      archive_operation_id = gen_random_uuid()
  where id = '99500000-0000-4000-8000-000000000030'
$$, '42501',
  'Esta versión del ERP no puede eliminar trabajos de forma auditada. Actualiza la aplicación e inténtalo nuevamente.',
  'direct or old-client archive updates cannot bypass the audited command'
);

create temporary table archive_result as
select public.set_mechanic_job_archived(
  '99500000-0000-4000-8000-000000000030',
  true,
  'Trabajo creado para una prueba',
  'archive-test-001'
) as payload;

select ok(
  (select deleted_at is not null from public.mechanic_jobs
   where id = '99500000-0000-4000-8000-000000000030'),
  'archive removes the job from active operation'
);
select is(
  (select deleted_by from public.mechanic_jobs
   where id = '99500000-0000-4000-8000-000000000030'),
  '99500000-0000-4000-8000-000000000099'::uuid,
  'archive records the authenticated actor'
);
select is(
  (select archive_reason from public.mechanic_jobs
   where id = '99500000-0000-4000-8000-000000000030'),
  'Trabajo creado para una prueba',
  'archive records the mandatory reason'
);
select is(
  (select count(*)::integer from public.mechanic_job_archive_events
   where job_id = '99500000-0000-4000-8000-000000000030'),
  1,
  'archive appends one immutable event'
);
select is(
  (select count(*)::integer from public.mechanic_job_items
   where job_id = '99500000-0000-4000-8000-000000000030'),
  1,
  'archive preserves every job item'
);
select is(
  (select count(*)::integer from public.mechanic_job_bikes
   where job_id = '99500000-0000-4000-8000-000000000030'),
  1,
  'archive preserves every bicycle link'
);
select is(
  (select count(*)::integer from public.stock_movements
   where source_document_type = 'mechanic_job'
     and source_document_id = '99500000-0000-4000-8000-000000000030'),
  0,
  'archive does not invent inventory movement'
);
select is(
  (select count(*)::integer from public.journal_entries
   where source_document_type = 'mechanic_job'
     and source_document_id = '99500000-0000-4000-8000-000000000030'),
  0,
  'archive does not invent an accounting journal'
);
select is(
  (select operation.outcome
   from public.inventory_accounting_operations operation
   join public.mechanic_jobs job
     on job.archive_operation_id = operation.id
   where job.id = '99500000-0000-4000-8000-000000000030'),
  'completed',
  'archive central operation completes'
);
select is(
  (select count(*)::integer
   from public.inventory_accounting_checkpoints checkpoint
   where checkpoint.operation_id = (
     select archive_operation_id from public.mechanic_jobs
     where id = '99500000-0000-4000-8000-000000000030'
   )),
  6,
  'archive records all central checkpoints'
);
select is(
  (select (payload->>'archived')::boolean from archive_result),
  true,
  'archive returns a confirmed result'
);
select is(
  (public.set_mechanic_job_archived(
    '99500000-0000-4000-8000-000000000030',
    true,
    'Trabajo creado para una prueba',
    'archive-test-001'
  )->>'replayed')::boolean,
  true,
  'same idempotency key replays the committed archive'
);
select is(
  (select count(*)::integer from public.mechanic_job_archive_events
   where job_id = '99500000-0000-4000-8000-000000000030'),
  1,
  'archive replay creates no duplicate event'
);

create temporary table restore_result as
select public.set_mechanic_job_archived(
  '99500000-0000-4000-8000-000000000030',
  false,
  'El trabajo se eliminó por error',
  'restore-test-001'
) as payload;

select ok(
  (select deleted_at is null and deleted_by is null
   from public.mechanic_jobs
   where id = '99500000-0000-4000-8000-000000000030'),
  'restore returns the job to active operation'
);
select ok(
  (select archive_reason is null and archive_operation_id is null
   from public.mechanic_jobs
   where id = '99500000-0000-4000-8000-000000000030'),
  'restore clears the current archive projection'
);
select is(
  (select count(*)::integer from public.mechanic_job_archive_events
   where job_id = '99500000-0000-4000-8000-000000000030'),
  2,
  'restore appends a second event without rewriting the first'
);
select is(
  (select (payload->>'archived')::boolean from restore_result),
  false,
  'restore returns a confirmed result'
);

select * from finish();
rollback;
