begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_column(
  'public', 'job_statuses', 'prompts_supply_need_capture',
  'job statuses expose an explicit supply-capture capability'
);
select has_table(
  'public', 'supply_needs',
  'supply needs are durable source-neutral demand'
);
select has_table(
  'public', 'supply_need_interpretation_revisions',
  'typed interpretations have an append-only revision ledger'
);
select has_table(
  'public', 'supply_need_events',
  'need commands emit durable receipts'
);
select has_view(
  'public', 'mechanic_job_supply_attention_v1',
  'workshop missing-parts attention is derived rather than persisted'
);
select has_function(
  'public', 'create_supply_need_v1',
  array['text', 'uuid', 'uuid', 'text', 'uuid', 'numeric', 'text', 'uuid', 'text'],
  'free-text and formal products share one create command'
);
select has_function(
  'public', 'update_supply_need_v1',
  array['uuid', 'bigint', 'text', 'uuid', 'numeric', 'text', 'text'],
  'need editing is versioned through one command'
);
select has_function(
  'public', 'cancel_supply_need_v1',
  array['uuid', 'bigint', 'text', 'text'],
  'need cancellation is an audited command'
);
select has_function(
  'public', 'set_job_status_supply_need_capability_v1',
  array['uuid', 'boolean', 'text'],
  'status capability changes are explicit and audited'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.create_supply_need_v1(text,uuid,uuid,text,uuid,numeric,text,uuid,text)',
    'execute'
  ) and not has_function_privilege(
    'anon',
    'public.create_supply_need_v1(text,uuid,uuid,text,uuid,numeric,text,uuid,text)',
    'execute'
  ),
  'only authenticated users can invoke the create command'
);
select ok(
  has_table_privilege('authenticated', 'public.supply_needs', 'select')
  and not has_table_privilege('authenticated', 'public.supply_needs', 'insert')
  and not has_table_privilege('authenticated', 'public.supply_needs', 'update')
  and not has_table_privilege('authenticated', 'public.supply_needs', 'delete'),
  'clients can read their needs but cannot bypass commands'
);

insert into public.tenants(id, shop_name) values
  ('99b10000-0000-4000-8000-000000000001', 'Supply Tenant A'),
  ('99b10000-0000-4000-8000-000000000002', 'Supply Tenant B');

-- Tenant bootstrap functions may impersonate a tenant while seeding defaults.
-- Clear that transient claim before creating neutral cross-tenant fixtures.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99b10000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'supply-command@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(user_id, tenant_id, role) values (
  '99b10000-0000-4000-8000-000000000099',
  '99b10000-0000-4000-8000-000000000001',
  'admin'
);

insert into public.customers(id, tenant_id, name) values
  ('99b10000-0000-4000-8000-000000000011', '99b10000-0000-4000-8000-000000000001', 'Supply Customer A'),
  ('99b10000-0000-4000-8000-000000000021', '99b10000-0000-4000-8000-000000000002', 'Supply Customer B');

insert into public.bikes(id, tenant_id, customer_id, brand, model) values
  ('99b10000-0000-4000-8000-000000000012', '99b10000-0000-4000-8000-000000000001', '99b10000-0000-4000-8000-000000000011', 'QA', 'Bike A'),
  ('99b10000-0000-4000-8000-000000000022', '99b10000-0000-4000-8000-000000000002', '99b10000-0000-4000-8000-000000000021', 'QA', 'Bike B');

insert into public.job_statuses(
  id, tenant_id, name, code, color, phase, sort_order
) values
  ('99b10000-0000-4000-8000-000000000031', '99b10000-0000-4000-8000-000000000001', 'QA Pendiente', 'QA_PENDING', '#64748B', 'todo', 90),
  ('99b10000-0000-4000-8000-000000000032', '99b10000-0000-4000-8000-000000000001', 'QA Repuestos', 'QA_PARTS', '#F97316', 'in_progress', 91),
  ('99b10000-0000-4000-8000-000000000034', '99b10000-0000-4000-8000-000000000002', 'QA Foreign', 'QA_FOREIGN', '#DC2626', 'todo', 90);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, workflow_kind,
  intake_kind, status, status_id
) values
  ('99b10000-0000-4000-8000-000000000041', '99b10000-0000-4000-8000-000000000001', '99b10000-0000-4000-8000-000000000011', 'SUPPLY-JOB-A', 'item_service', 'service', 'bike', 'QA_PENDING', '99b10000-0000-4000-8000-000000000031'),
  ('99b10000-0000-4000-8000-000000000042', '99b10000-0000-4000-8000-000000000002', '99b10000-0000-4000-8000-000000000021', 'SUPPLY-JOB-B', 'item_service', 'service', 'bike', 'QA_FOREIGN', '99b10000-0000-4000-8000-000000000034');

insert into public.mechanic_job_bikes(
  id, tenant_id, job_id, bike_id, order_index
) values
  ('99b10000-0000-4000-8000-000000000051', '99b10000-0000-4000-8000-000000000001', '99b10000-0000-4000-8000-000000000041', '99b10000-0000-4000-8000-000000000012', 0),
  ('99b10000-0000-4000-8000-000000000052', '99b10000-0000-4000-8000-000000000002', '99b10000-0000-4000-8000-000000000042', '99b10000-0000-4000-8000-000000000022', 0);

insert into public.products(
  id, tenant_id, name, sku, price, cost, inventory_qty,
  stock_quantity, is_active, is_service, product_type
) values
  ('99b10000-0000-4000-8000-000000000061', '99b10000-0000-4000-8000-000000000001', 'Piñón QA', 'SUPPLY-PRODUCT-A', 22000, 8990, 2, 2, true, false, 'product'),
  ('99b10000-0000-4000-8000-000000000062', '99b10000-0000-4000-8000-000000000002', 'Producto ajeno', 'SUPPLY-PRODUCT-B', 100, 50, 1, 1, true, false, 'product');

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99b10000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99b10000-0000-4000-8000-000000000099',
  true
);

select is(
  (public.set_job_status_supply_need_capability_v1(
    '99b10000-0000-4000-8000-000000000032', true,
    'supply-capability-enable'
  )->>'changed')::boolean,
  true,
  'an explicit command enables capture for the selected status'
);
select is(
  (public.set_job_status_supply_need_capability_v1(
    '99b10000-0000-4000-8000-000000000032', true,
    'supply-capability-enable'
  )->>'replay')::boolean,
  true,
  'the same status-capability request replays exactly'
);
select is(
  (
    select count(*)::integer
    from public.job_status_supply_capability_events
    where operation_key = 'supply-capability-enable'
  ),
  1,
  'status capability replay appends no duplicate receipt'
);
select throws_ok(
  $$select public.set_job_status_supply_need_capability_v1(
    '99b10000-0000-4000-8000-000000000034', true,
    'supply-capability-foreign'
  )$$,
  'P0002',
  'Estado no encontrado.',
  'a tenant cannot configure another tenant status'
);

select lives_ok(
  $$select public.transition_mechanic_job_status(
    '99b10000-0000-4000-8000-000000000041',
    '99b10000-0000-4000-8000-000000000032',
    'supply-transition-parts'
  )$$,
  'the canonical transition can enter a status that prompts capture'
);
select is(
  (
    select count(*)::integer from public.supply_needs
    where mechanic_job_id = '99b10000-0000-4000-8000-000000000041'
  ),
  0,
  'selecting the status never creates an empty need'
);
select is(
  (
    select requires_supply_definition
    from public.mechanic_job_supply_attention_v1
    where mechanic_job_id = '99b10000-0000-4000-8000-000000000041'
  ),
  true,
  'the derived read model exposes Repuestos sin definir attention'
);

update public.job_statuses
set name = 'QA Esperando piezas'
where id = '99b10000-0000-4000-8000-000000000032';
select is(
  (
    select requires_supply_definition
    from public.mechanic_job_supply_attention_v1
    where mechanic_job_id = '99b10000-0000-4000-8000-000000000041'
  ),
  true,
  'renaming a status does not break its semantic capability'
);

create temporary table supply_free_text_result as
select public.create_supply_need_v1(
  'mechanic_job',
  '99b10000-0000-4000-8000-000000000041',
  '99b10000-0000-4000-8000-000000000051',
  '  rayos 27.5  ',
  null,
  32,
  'unit',
  null,
  'supply-create-free-text'
) as receipt;

select is(
  (select receipt->'need'->>'original_description' from supply_free_text_result),
  '  rayos 27.5  ',
  'the command preserves the operator text verbatim'
);
select is(
  (select receipt->'need'->>'identity_state' from supply_free_text_result),
  'unresolved',
  'free text remains explicitly unresolved until interpretation'
);
select is(
  (
    select revision.raw_description
    from public.supply_need_interpretation_revisions revision
    where revision.supply_need_id = (
      select (receipt->>'need_id')::uuid from supply_free_text_result
    )
  ),
  '  rayos 27.5  ',
  'the initial interpretation revision also preserves raw text'
);
select is(
  (
    select requires_supply_definition
    from public.mechanic_job_supply_attention_v1
    where mechanic_job_id = '99b10000-0000-4000-8000-000000000041'
  ),
  false,
  'capturing one real need clears the derived undefined-parts attention'
);
select is(
  (public.create_supply_need_v1(
    'mechanic_job',
    '99b10000-0000-4000-8000-000000000041',
    '99b10000-0000-4000-8000-000000000051',
    '  rayos 27.5  ',
    null,
    32,
    'unit',
    null,
    'supply-create-free-text'
  )->>'replay')::boolean,
  true,
  'an exact create replay returns its original receipt'
);
select is(
  (
    select count(*)::integer from public.supply_need_events
    where operation_key = 'supply-create-free-text'
  ),
  1,
  'an exact create replay appends no duplicate event'
);

create temporary table supply_formal_result as
select public.create_supply_need_v1(
  'mechanic_job',
  '99b10000-0000-4000-8000-000000000041',
  null,
  'Piñón Shimano para el trabajo',
  '99b10000-0000-4000-8000-000000000061',
  1,
  'unit',
  null,
  'supply-create-formal-general'
) as receipt;
select is(
  (select receipt->'need'->>'identity_state' from supply_formal_result),
  'confirmed',
  'a formal product starts with confirmed identity'
);
select is(
  (select receipt->'need'->>'job_bike_id' from supply_formal_result),
  null,
  'General attribution is represented by a durable null bike link'
);

select throws_ok(
  $$select public.create_supply_need_v1(
    'mechanic_job',
    '99b10000-0000-4000-8000-000000000041',
    '99b10000-0000-4000-8000-000000000052',
    'foreign bike', null, 1, 'unit', null,
    'supply-create-foreign-bike'
  )$$,
  '23514',
  'La bicicleta no pertenece a este trabajo.',
  'a need cannot use another tenant or job bike'
);
select throws_ok(
  $$select public.create_supply_need_v1(
    'mechanic_job',
    '99b10000-0000-4000-8000-000000000041',
    null,
    'foreign product',
    '99b10000-0000-4000-8000-000000000062',
    1, 'unit', null,
    'supply-create-foreign-product'
  )$$,
  '23514',
  'El producto no existe, está inactivo o no es un repuesto.',
  'a need cannot link another tenant product'
);
select throws_ok(
  $$select public.create_supply_need_v1(
    'ad_hoc',
    '99b10000-0000-4000-8000-000000000041',
    null, 'invalid ad hoc', null, 1, 'unit', null,
    'supply-create-invalid-origin'
  )$$,
  '23514',
  'La procedencia de la necesidad no coincide con su contexto.',
  'ad-hoc demand cannot masquerade as workshop demand'
);

create temporary table supply_update_result as
select public.update_supply_need_v1(
  (select (receipt->>'need_id')::uuid from supply_free_text_result),
  1,
  'Rayos negros 27.5 confirmados por el operador',
  null,
  36,
  'unit',
  'supply-update-free-text'
) as receipt;
select is(
  (select (receipt->>'version')::bigint from supply_update_result),
  2::bigint,
  'a material edit increments the optimistic version'
);
select is(
  (
    select count(*)::integer
    from public.supply_need_interpretation_revisions
    where supply_need_id = (
      select (receipt->>'need_id')::uuid from supply_free_text_result
    )
  ),
  2,
  'a material edit appends one interpretation revision'
);
select throws_ok(
  format(
    'select public.update_supply_need_v1(%L::uuid, 1, %L, null, 36, %L, %L)',
    (select receipt->>'need_id' from supply_free_text_result),
    'stale edit', 'unit', 'supply-update-stale'
  ),
  '40001',
  'La necesidad cambió; vuelve a cargarla antes de guardar.',
  'stale edits cannot overwrite a newer operator decision'
);
select is(
  (public.update_supply_need_v1(
    (select (receipt->>'need_id')::uuid from supply_free_text_result),
    2,
    'Rayos negros 27.5 confirmados por el operador',
    null,
    36,
    'unit',
    'supply-update-noop'
  )->>'changed')::boolean,
  false,
  'a new identical update is a durable no-op'
);

create temporary table supply_cancel_result as
select public.cancel_supply_need_v1(
  (select (receipt->>'need_id')::uuid from supply_free_text_result),
  2,
  'El cliente canceló el trabajo',
  'supply-cancel-free-text'
) as receipt;
select is(
  (select receipt->'need'->>'supply_state' from supply_cancel_result),
  'cancelled',
  'cancellation closes the need without deleting its evidence'
);
select is(
  (public.cancel_supply_need_v1(
    (select (receipt->>'need_id')::uuid from supply_free_text_result),
    2,
    'El cliente canceló el trabajo',
    'supply-cancel-free-text'
  )->>'replay')::boolean,
  true,
  'cancellation replays before optimistic-version evaluation'
);
select throws_ok(
  format(
    'update public.supply_need_events set changed = false where supply_need_id = %L::uuid',
    (select receipt->>'need_id' from supply_free_text_result)
  ),
  '55000',
  'Supply kernel evidence is append-only',
  'event receipts cannot be rewritten even by a privileged session'
);
select throws_ok(
  format(
    'delete from public.supply_need_interpretation_revisions where supply_need_id = %L::uuid',
    (select receipt->>'need_id' from supply_free_text_result)
  ),
  '55000',
  'Supply kernel evidence is append-only',
  'interpretation history cannot be deleted even by a privileged session'
);

set local role authenticated;
select throws_ok(
  $$insert into public.supply_needs(
      tenant_id, origin_kind, mechanic_job_id, original_description,
      quantity, unit, identity_state, supply_state, usage_state
    ) values (
      '99b10000-0000-4000-8000-000000000001', 'mechanic_job',
      '99b10000-0000-4000-8000-000000000041', 'bypass attempt',
      1, 'unit', 'unresolved', 'open', 'pending'
    )$$,
  '42501',
  'permission denied for table supply_needs',
  'authenticated clients cannot bypass the command boundary'
);
reset role;

select * from finish();
rollback;
