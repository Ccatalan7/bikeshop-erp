begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(47);

select has_function(
  'public',
  'classify_mechanic_job_intake',
  array['uuid', 'text', 'uuid', 'uuid', 'text', 'text', 'uuid'],
  'reviewed workshop intake has one canonical classification command'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.classify_mechanic_job_intake(uuid,text,uuid,uuid,text,text,uuid)',
    'execute'
  ),
  'authenticated employees can complete intake review'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.classify_mechanic_job_intake(uuid,text,uuid,uuid,text,text,uuid)',
    'execute'
  ),
  'anonymous callers cannot classify workshop intake'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.classify_mechanic_job_intake(uuid,text,uuid,uuid,text,text,uuid)',
    'execute'
  ),
  'service role is not granted an employee-audited classification command'
);

insert into public.tenants(id, shop_name) values
  ('99616400-0000-4000-8000-000000000001', 'Intake Classifier Tenant A'),
  ('99616400-0000-4000-8000-000000000002', 'Intake Classifier Tenant B');

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99616400-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'intake-classifier@example.invalid', '',
  now(), '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '99616400-0000-4000-8000-000000000001'
  ),
  now(), now()
);

insert into public.user_profiles(user_id, tenant_id, role) values (
  '99616400-0000-4000-8000-000000000099',
  '99616400-0000-4000-8000-000000000001',
  'admin'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99616400-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99616400-0000-4000-8000-000000000099',
  true
);

insert into public.customers(id, tenant_id, name) values
  (
    '99616400-0000-4000-8000-000000000011',
    '99616400-0000-4000-8000-000000000001',
    'Intake Customer A'
  ),
  (
    '99616400-0000-4000-8000-000000000012',
    '99616400-0000-4000-8000-000000000001',
    'Other Customer A'
  ),
  (
    '99616400-0000-4000-8000-000000000021',
    '99616400-0000-4000-8000-000000000002',
    'Intake Customer B'
  );

insert into public.bikes(
  id, tenant_id, customer_id, brand, model, is_active
) values
  (
    '99616400-0000-4000-8000-000000000031',
    '99616400-0000-4000-8000-000000000001',
    '99616400-0000-4000-8000-000000000011',
    'Codex', 'Bike A', true
  ),
  (
    '99616400-0000-4000-8000-000000000032',
    '99616400-0000-4000-8000-000000000001',
    '99616400-0000-4000-8000-000000000012',
    'Codex', 'Other Customer Bike', true
  ),
  (
    '99616400-0000-4000-8000-000000000033',
    '99616400-0000-4000-8000-000000000001',
    '99616400-0000-4000-8000-000000000011',
    'Codex', 'Inactive Bike', false
  ),
  (
    '99616400-0000-4000-8000-000000000041',
    '99616400-0000-4000-8000-000000000002',
    '99616400-0000-4000-8000-000000000021',
    'Codex', 'Tenant B Bike', true
  );

insert into public.job_subjects(
  id, tenant_id, name, category, is_active
) values
  (
    '99616400-0000-4000-8000-000000000051',
    '99616400-0000-4000-8000-000000000001',
    'Rueda QA trasera', 'Ruedas', true
  ),
  (
    '99616400-0000-4000-8000-000000000052',
    '99616400-0000-4000-8000-000000000001',
    'Rueda QA inactiva', 'Ruedas', false
  ),
  (
    '99616400-0000-4000-8000-000000000053',
    '99616400-0000-4000-8000-000000000002',
    'Rueda QA tenant B', 'Ruedas', true
  );

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, status
) values (
  '99616400-0000-4000-8000-000000000061',
  '99616400-0000-4000-8000-000000000001',
  '99616400-0000-4000-8000-000000000011',
  'INTAKE-BIKE-REVIEW', 'service', 'PENDIENTE'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, product_sku,
  item_type, quantity, unit_price
) values (
  '99616400-0000-4000-8000-000000000071',
  '99616400-0000-4000-8000-000000000001',
  '99616400-0000-4000-8000-000000000061',
  'Diagnóstico inicial', 'INTAKE-DIAG', 'service', 1, 5000
);

select throws_ok(
  $$select public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000061', 'bike',
    '99616400-0000-4000-8000-000000000033', null, null,
    'Intento con bicicleta inactiva.',
    '99616400-0000-4000-8000-000000000100'
  )$$,
  '23514',
  'La bicicleta debe estar activa y pertenecer al cliente y negocio del trabajo.',
  'bike classification rejects an inactive customer bicycle'
);
select throws_ok(
  $$select public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000061', 'bike',
    '99616400-0000-4000-8000-000000000032', null, null,
    'Intento con bicicleta ajena.',
    '99616400-0000-4000-8000-000000000101'
  )$$,
  '23514',
  'La bicicleta debe estar activa y pertenecer al cliente y negocio del trabajo.',
  'bike classification rejects another customer bicycle'
);
select ok(
  (select mode_needs_review and intake_kind = 'unspecified'
   from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000061'),
  'rejected bicycle classification leaves the review state unchanged'
);

create temporary table bike_classification as
select public.classify_mechanic_job_intake(
  '99616400-0000-4000-8000-000000000061', 'bike',
  '99616400-0000-4000-8000-000000000031', null, null,
  'Cliente confirmó que dejó la bicicleta completa.',
  '99616400-0000-4000-8000-000000000102'
) as result;

select is(
  (select result->>'intake_kind' from bike_classification),
  'bike',
  'classification response reports complete bicycle intake'
);
select is(
  (select intake_kind from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000061'),
  'bike',
  'reviewed job persists bicycle intake'
);
select is(
  (select job_type from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000061'),
  'service',
  'bicycle intake retains the service compatibility type'
);
select is(
  (select mode_needs_review from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000061'),
  false,
  'successful bicycle classification clears the review flag'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_bikes
   where job_id = '99616400-0000-4000-8000-000000000061'
     and bike_id = '99616400-0000-4000-8000-000000000031'),
  1,
  'bicycle classification creates one canonical job-bike link'
);
select ok(
  (select job_bike_id is not null
   from public.mechanic_job_items
   where id = '99616400-0000-4000-8000-000000000071'),
  'unassigned workshop lines become attributed to the classified bicycle'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_mode_events
   where job_id = '99616400-0000-4000-8000-000000000061'
     and event_type = 'classified'),
  1,
  'bicycle classification appends one immutable event'
);
select is(
  (select actor_id
   from public.mechanic_job_mode_events
   where operation_key = '99616400-0000-4000-8000-000000000102'),
  '99616400-0000-4000-8000-000000000099'::uuid,
  'classification records the authenticated employee'
);
select is(
  (select (metadata->>'financial_effects_created')::boolean
   from public.mechanic_job_mode_events
   where operation_key = '99616400-0000-4000-8000-000000000102'),
  false,
  'classification receipt explicitly records that it did not post financially'
);
select is(
  (select reason
   from public.mechanic_job_mode_events
   where operation_key = '99616400-0000-4000-8000-000000000102'),
  'Cliente confirmó que dejó la bicicleta completa.',
  'classification preserves the employee justification'
);
select is(
  public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000061', 'bike',
    '99616400-0000-4000-8000-000000000031', null, null,
    'Cliente confirmó que dejó la bicicleta completa.',
    '99616400-0000-4000-8000-000000000102'
  )->>'replayed',
  'true',
  'same-key retry replays the committed classification receipt'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_mode_events
   where job_id = '99616400-0000-4000-8000-000000000061'
     and event_type = 'classified'),
  1,
  'classification replay never duplicates the event'
);
select throws_ok(
  $$select public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000061', 'component',
    null, '99616400-0000-4000-8000-000000000051', null, null,
    '99616400-0000-4000-8000-000000000102'
  )$$,
  '23505',
  'La clave de operación ya pertenece a otra clasificación de trabajo.',
  'one operation key cannot be reused for another classification payload'
);
select is(
  (select count(*)::integer from public.stock_movements
   where source_document_id = '99616400-0000-4000-8000-000000000061'),
  0,
  'intake classification creates no direct inventory movement'
);
select is(
  (select count(*)::integer from public.journal_entries
   where source_document_id = '99616400-0000-4000-8000-000000000061'),
  0,
  'intake classification creates no direct accounting entry'
);
select is(
  (select invoice_id from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000061'),
  null::uuid,
  'intake classification does not invent an invoice'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, status
) values (
  '99616400-0000-4000-8000-000000000062',
  '99616400-0000-4000-8000-000000000001',
  '99616400-0000-4000-8000-000000000011',
  'INTAKE-COMPONENT-REVIEW', 'service', 'PENDIENTE'
);

select throws_ok(
  $$select public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000062', 'component',
    null, '99616400-0000-4000-8000-000000000052',
    'Rueda descrita', null,
    '99616400-0000-4000-8000-000000000103'
  )$$,
  '23514',
  'El componente debe estar activo y pertenecer al negocio del trabajo.',
  'component classification rejects an inactive catalog subject'
);
select throws_ok(
  $$select public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000062', 'component',
    null, '99616400-0000-4000-8000-000000000053',
    'Rueda descrita', null,
    '99616400-0000-4000-8000-000000000104'
  )$$,
  '23514',
  'El componente debe estar activo y pertenecer al negocio del trabajo.',
  'component classification rejects a cross-tenant catalog subject'
);
select ok(
  (select mode_needs_review
      and intake_kind = 'unspecified'
      and not exists (
        select 1 from public.mechanic_job_mode_events event
        where event.job_id = mechanic_jobs.id
          and event.event_type = 'classified'
      )
   from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000062'),
  'rejected component classifications leave row and event ledger unchanged'
);

select is(
  public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000062', 'component',
    null, '99616400-0000-4000-8000-000000000051',
    'Rueda trasera entregada sin bicicleta.', null,
    '99616400-0000-4000-8000-000000000105'
  )->>'intake_kind',
  'component',
  'active tenant component can complete intake review'
);
select is(
  (select job_type from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000062'),
  'item_service',
  'component classification uses the component compatibility type'
);
select is(
  (select mode_needs_review from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000062'),
  false,
  'component classification clears review'
);
select is(
  (select subject_id from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000062'),
  '99616400-0000-4000-8000-000000000051'::uuid,
  'component classification stores the active tenant subject'
);
select is(
  (select bike_id from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000062'),
  null::uuid,
  'component classification does not inflate the bicycle count'
);
select is(
  (select reason from public.mechanic_job_mode_events
   where operation_key = '99616400-0000-4000-8000-000000000105'),
  'Clasificación manual de recepción confirmada por un trabajador.',
  'an omitted justification receives a clear server-owned audit reason'
);
select ok(
  (select invoice_id is null
      and not exists (
        select 1 from public.stock_movements movement
        where movement.source_document_id = mechanic_jobs.id
      )
      and not exists (
        select 1 from public.journal_entries entry
        where entry.source_document_id = mechanic_jobs.id
      )
   from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000062'),
  'component classification has no invoice, stock, or accounting side effect'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, subject_notes, status
) values (
  '99616400-0000-4000-8000-000000000063',
  '99616400-0000-4000-8000-000000000001',
  '99616400-0000-4000-8000-000000000011',
  'INTAKE-NOTES-ONLY', 'service', 'Horquilla suelta', 'PENDIENTE'
);

select is(
  public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000063', 'component',
    null, null, 'Horquilla suelta', null,
    '99616400-0000-4000-8000-000000000106'
  )->>'intake_kind',
  'component',
  'notes-only component intake remains a supported explicit classification'
);
select ok(
  (select subject_id is null and subject_notes = 'Horquilla suelta'
   from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000063'),
  'notes-only classification keeps explicit free-text component identity'
);
select is(
  (select count(*)::integer from public.mechanic_job_mode_events
   where job_id = '99616400-0000-4000-8000-000000000063'
     and event_type = 'classified'),
  1,
  'notes-only classification is audited like catalog classification'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, status
) values (
  '99616400-0000-4000-8000-000000000064',
  '99616400-0000-4000-8000-000000000001',
  '99616400-0000-4000-8000-000000000011',
  'INTAKE-NO-COMPONENT', 'service', 'PENDIENTE'
);
select throws_ok(
  $$select public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000064', 'component',
    null, null, null, null,
    '99616400-0000-4000-8000-000000000107'
  )$$,
  '23514',
  'Selecciona o describe el componente que quedó en el taller.',
  'component classification requires catalog identity or description'
);
select is(
  (select mode_needs_review from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000064'),
  true,
  'missing component identity keeps the review visible'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, bike_id, status
) values (
  '99616400-0000-4000-8000-000000000065',
  '99616400-0000-4000-8000-000000000001',
  '99616400-0000-4000-8000-000000000011',
  'INTAKE-ALREADY-BIKE', 'service',
  '99616400-0000-4000-8000-000000000031', 'PENDIENTE'
);
update public.mechanic_jobs
set mode_needs_review = true,
    mode_review_reason = 'manual: revisar asociación existente'
where id = '99616400-0000-4000-8000-000000000065';
select throws_ok(
  $$select public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000065', 'component',
    null, '99616400-0000-4000-8000-000000000051', null, null,
    '99616400-0000-4000-8000-000000000108'
  )$$,
  '23514',
  'El trabajo ya tiene una bicicleta asociada; revísala antes de clasificarlo como componente suelto.',
  'component classification never detaches an existing bicycle implicitly'
);
select is(
  (select bike_id from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000065'),
  '99616400-0000-4000-8000-000000000031'::uuid,
  'rejected component classification preserves the existing bicycle link'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type,
  quotation_status, status
) values (
  '99616400-0000-4000-8000-000000000066',
  '99616400-0000-4000-8000-000000000001',
  '99616400-0000-4000-8000-000000000011',
  'INTAKE-QUOTE', 'quotation', 'pending', 'PRESUPUESTO'
);
select throws_ok(
  $$select public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000066', 'bike',
    '99616400-0000-4000-8000-000000000031', null, null, null,
    '99616400-0000-4000-8000-000000000109'
  )$$,
  '23514',
  'Los presupuestos se clasifican al convertirlos, no mediante esta revisión.',
  'quotation intake cannot bypass the conversion workflow'
);
select throws_ok(
  $$select public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000061', 'bike',
    '99616400-0000-4000-8000-000000000031', null, null, null,
    '99616400-0000-4000-8000-000000000110'
  )$$,
  '23514',
  'Este trabajo ya tiene una recepción clasificada.',
  'resolved intake cannot be changed through the review-only command'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, status
) values (
  '99616400-0000-4000-8000-000000000067',
  '99616400-0000-4000-8000-000000000001',
  '99616400-0000-4000-8000-000000000011',
  'INTAKE-WARRANTY', 'warranty', 'PENDIENTE'
);
select is(
  public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000067', 'bike',
    '99616400-0000-4000-8000-000000000031', null, null,
    'Garantía recibida con bicicleta completa.',
    '99616400-0000-4000-8000-000000000111'
  )->>'workflow_kind',
  'warranty',
  'warranty review preserves the warranty workflow'
);
select ok(
  (select job_type = 'warranty'
      and workflow_kind = 'warranty'
      and intake_kind = 'bike'
      and not mode_needs_review
   from public.mechanic_jobs
   where id = '99616400-0000-4000-8000-000000000067'),
  'warranty classification changes only the physical intake axis'
);
select is(
  (select count(*)::integer from public.mechanic_job_mode_events
   where job_id = '99616400-0000-4000-8000-000000000067'
     and event_type = 'classified'),
  1,
  'warranty intake review has the same immutable classification receipt'
);

select throws_ok(
  $$select public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000064', 'unknown',
    null, null, null, null,
    '99616400-0000-4000-8000-000000000112'
  )$$,
  '23514',
  'La recepción debe clasificarse como bicicleta completa o componente suelto.',
  'unknown intake classifications are rejected'
);

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, status
) values (
  '99616400-0000-4000-8000-000000000068',
  '99616400-0000-4000-8000-000000000002',
  '99616400-0000-4000-8000-000000000021',
  'INTAKE-TENANT-B', 'service', 'PENDIENTE'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99616400-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99616400-0000-4000-8000-000000000099',
  true
);

select throws_ok(
  $$select public.classify_mechanic_job_intake(
    '99616400-0000-4000-8000-000000000068', 'bike',
    '99616400-0000-4000-8000-000000000041', null, null, null,
    '99616400-0000-4000-8000-000000000113'
  )$$,
  '42501',
  'Workshop record does not belong to the active tenant',
  'employee cannot classify a job from another tenant'
);

select * from finish();
rollback;
