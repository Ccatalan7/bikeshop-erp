begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(162);

select is(
  (
    select constraint_definition.delete_rule
    from information_schema.referential_constraints constraint_definition
    where constraint_definition.constraint_schema = 'public'
      and constraint_definition.constraint_name = 'mechanic_jobs_invoice_id_fkey'
  ),
  'RESTRICT',
  'a linked workshop invoice cannot erase its authoritative job'
);
select has_trigger(
  'public', 'mechanic_jobs', 'trg_delete_pega_cascade_invoice',
  'job-originated draft cleanup keeps its guarded compatibility path'
);
select hasnt_trigger(
  'public', 'sales_invoices', 'trg_delete_invoice_cascade_pega',
  'Sales no longer has an invoice-to-job destructive cascade trigger'
);
select has_trigger(
  'public', 'mechanic_job_bikes',
  'trg_mechanic_job_bikes_guard_final_service_budget',
  'a decided service budget freezes its received-bike aggregate'
);

select has_column(
  'public', 'mechanic_jobs', 'workflow_kind',
  'jobs expose the canonical workflow axis'
);
select has_column(
  'public', 'mechanic_jobs', 'intake_kind',
  'jobs expose the canonical physical-intake axis'
);
select has_column(
  'public', 'mechanic_jobs', 'mode_needs_review',
  'ambiguous legacy modes stay explicitly reviewable'
);
select has_table(
  'public', 'mechanic_job_mode_events',
  'mode changes have an immutable event ledger'
);
select has_trigger(
  'public', 'mechanic_job_mode_events',
  'trg_mechanic_job_mode_events_immutable',
  'mode events are append-only'
);
select has_view(
  'public', 'mechanic_job_mode_view',
  'mode and quotation expiry have a canonical read model'
);
select has_trigger(
  'public', 'mechanic_jobs',
  'trg_mechanic_jobs_guard_quotation_invoice',
  'quotation invoice ownership is guarded at the row boundary'
);
select has_function(
  'public',
  'mechanic_job_quotation_content_snapshot',
  array['uuid'],
  'quotation approval has a canonical commercial snapshot builder'
);
select has_trigger(
  'public', 'mechanic_job_mode_events',
  'trg_mechanic_job_mode_event_snapshot',
  'approval and conversion events preserve the commercial snapshot'
);
select has_trigger(
  'public', 'mechanic_jobs',
  'zzzz_mechanic_jobs_guard_canonical_mode_transition',
  'cross-workflow and approved-quotation writes use canonical commands'
);
select has_trigger(
  'public', 'mechanic_job_items',
  'trg_mechanic_job_items_guard_final_quotation',
  'final quotation lines are immutable at the row boundary'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.transition_mechanic_job_quotation(uuid,text,text,uuid)',
    'execute'
  ),
  'authenticated employees can transition quotations'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.convert_mechanic_job_to_billable(uuid,text,text,boolean,uuid,uuid,uuid)',
    'execute'
  ),
  'authenticated employees can convert an approved quotation'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.convert_mechanic_job_to_billable(uuid,text,text,boolean,uuid,uuid,uuid)',
    'execute'
  ),
  'anonymous callers cannot convert quotations'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_invoice_from_mechanic_job_internal(uuid)',
    'execute'
  ),
  'the unchecked invoice builder is private even from employees'
);
select ok(
  public.mechanic_job_mode_backfill_eligible(
    timestamptz '2026-07-16 05:14:59+00'
  ),
  'rows before the frozen deployment cutoff are historical-backfill eligible'
);
select ok(
  not public.mechanic_job_mode_backfill_eligible(
    timestamptz '2026-07-16 05:15:00+00'
  ),
  'rows at or after the frozen cutoff can never enter a future backfill replay'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'public.mechanic_job_mode_backfill_eligible(timestamp with time zone)',
    'execute'
  ),
  'the migration cutoff predicate is private to schema maintenance'
);

insert into public.tenants(id, shop_name) values
  ('99616000-0000-4000-8000-000000000001', 'Job Mode Tenant A'),
  ('99616000-0000-4000-8000-000000000002', 'Job Mode Tenant B');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99616000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'job-modes@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '99616000-0000-4000-8000-000000000001'
  ),
  now(),
  now()
);

insert into public.user_profiles(user_id, tenant_id, role) values (
  '99616000-0000-4000-8000-000000000099',
  '99616000-0000-4000-8000-000000000001',
  'admin'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99616000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99616000-0000-4000-8000-000000000099',
  true
);

insert into public.customers(id, tenant_id, name) values
  ('99616000-0000-4000-8000-000000000011', '99616000-0000-4000-8000-000000000001', 'Mode Customer A'),
  ('99616000-0000-4000-8000-000000000021', '99616000-0000-4000-8000-000000000002', 'Mode Customer B');

insert into public.bikes(id, tenant_id, customer_id, brand, model) values
  ('99616000-0000-4000-8000-000000000031', '99616000-0000-4000-8000-000000000001', '99616000-0000-4000-8000-000000000011', 'Codex', 'Bike A'),
  ('99616000-0000-4000-8000-000000000032', '99616000-0000-4000-8000-000000000001', '99616000-0000-4000-8000-000000000011', 'Codex', 'Bike A2'),
  ('99616000-0000-4000-8000-000000000041', '99616000-0000-4000-8000-000000000002', '99616000-0000-4000-8000-000000000021', 'Codex', 'Bike B');

-- The deployed tenant trigger does not currently seed workshop subjects.
-- Keep this contract fixture self-contained instead of relying on tenant
-- initialization or a bootstrap snapshot.
insert into public.job_subjects(
  id, tenant_id, name, category, is_active
) values (
  '99616000-0000-4000-8000-000000000044',
  '99616000-0000-4000-8000-000000000001',
  'Rueda trasera', 'Ruedas', true
);

insert into public.products(
  id, tenant_id, name, sku, price, cost, inventory_qty, stock_quantity,
  is_service, product_type, track_stock
) values (
  '99616000-0000-4000-8000-000000000051',
  '99616000-0000-4000-8000-000000000001',
  'Quoted Part',
  'MODE-PART',
  9000,
  4000,
  12,
  12,
  false,
  'product',
  true
);

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_id, status,
  subtotal, net_amount, total, paid_amount, balance, items
) values (
  '99616000-0000-4000-8000-000000000061',
  '99616000-0000-4000-8000-000000000001',
  'MODE-DUMMY-INVOICE',
  '99616000-0000-4000-8000-000000000011',
  'draft', 0, 0, 0, 0, 0, '[]'::jsonb
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type,
  quotation_status, quotation_valid_until, status
) values (
  '99616000-0000-4000-8000-000000000071',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  'MODE-QUOTE-BIKE',
  'quotation',
  'pending',
  clock_timestamp() + interval '7 days',
  'PRESUPUESTO'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, bike_id, status
) values (
  '99616000-0000-4000-8000-000000000077',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  'MODE-REPARARENT-TARGET',
  'service',
  '99616000-0000-4000-8000-000000000031',
  'PENDIENTE'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type,
  quotation_status, parts_cost, final_cost, discount_amount, tax_amount, total_cost,
  tax_treatment, status
) values (
  '99616000-0000-4000-8000-000000000078',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  'MODE-QUOTE-CLIENT-MIRRORS',
  'quotation',
  'pending',
  1000, 1000, 500, 190, 1190,
  'taxable',
  'PRESUPUESTO'
);

select is(
  (select tax_amount from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000078'),
  0::numeric,
  'a new quotation discards client-supplied IVA mirrors'
);
select is(
  (select tax_treatment from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000078'),
  'no_tax',
  'a new quotation cannot claim an invoice tax treatment'
);
select is(
  (select total_cost from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000078'),
  0::numeric,
  'a new quotation derives its total from persisted lines, not client mirrors'
);
select is(
  (select discount_amount from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000078'),
  500::numeric,
  'a legacy client can stage its requested discount before writing lines'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_id, product_name, product_sku,
  item_type, quantity, unit_price
) values (
  '99616000-0000-4000-8000-000000000088',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000078',
  '99616000-0000-4000-8000-000000000051',
  'Quoted Part', 'MODE-PART', 'product', 1, 9000
);

select is(
  (select total_cost from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000078'),
  8500::numeric,
  'the staged legacy discount applies after its quotation line exists'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, product_sku,
  item_type, quantity, unit_price
) values (
  '99616000-0000-4000-8000-000000000087',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000078',
  'Repuesto manual', 'MODE-ADHOC', 'adhoc', 1, 2000
);

select is(
  (select parts_cost from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000078'),
  11000::numeric,
  'ad-hoc part lines remain parts instead of inflating labor KPIs'
);
select is(
  (select labor_cost from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000078'),
  0::numeric,
  'ad-hoc part lines do not become workshop labor'
);
select is(
  (select total_cost from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000078'),
  10500::numeric,
  'the staged discount remains exact after an ad-hoc part is added'
);

select throws_ok(
  $$insert into public.mechanic_jobs(
      id, tenant_id, customer_id, job_number, job_type,
      quotation_status, status
    ) values (
      '99616000-0000-4000-8000-000000000079',
      '99616000-0000-4000-8000-000000000001',
      '99616000-0000-4000-8000-000000000011',
      'MODE-QUOTE-DIRECT-APPROVED',
      'quotation',
      'approved',
      'PRESUPUESTO'
    )$$,
  '23514',
  'Una cotización nueva siempre comienza pendiente; registra su decisión después de guardarla.',
  'new quotations cannot bypass pending and their first approval snapshot'
);

select is(
  (select workflow_kind from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000071'),
  'quotation',
  'legacy quotation job_type normalizes to quotation workflow'
);
select is(
  (select intake_kind from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000071'),
  'unspecified',
  'walk-in quotations can remain without a received intake object'
);
select is(
  (select mode_needs_review from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000071'),
  false,
  'an unspecified quotation is not treated as a broken service intake'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_id, product_name, product_sku,
  item_type, quantity, unit_price
) values (
  '99616000-0000-4000-8000-000000000081',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000071',
  '99616000-0000-4000-8000-000000000051',
  'Quoted Part',
  'MODE-PART',
  'product',
  1,
  9000
);

select is(
  (select tax_amount from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000071'),
  0::numeric,
  'a quotation item recalc never invents IVA before an invoice exists'
);
select is(
  (select total_cost from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000071'),
  9000::numeric,
  'quotation total equals its customer-facing gross line total'
);
select is(
  (select tax_treatment from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000071'),
  'no_tax',
  'an unconverted quotation remains non-posting and non-tax classified'
);

update public.mechanic_jobs
set tax_amount = 999,
    total_cost = 999999,
    tax_treatment = 'taxable'
where id = '99616000-0000-4000-8000-000000000071';

select is(
  (select tax_amount from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000071'),
  0::numeric,
  'a pending quotation normalizes direct IVA mirror drift'
);
select is(
  (select total_cost from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000071'),
  9000::numeric,
  'a pending quotation re-derives total from its authoritative lines'
);

select throws_ok(
  $$select public.create_billable_invoice_from_mechanic_job('99616000-0000-4000-8000-000000000071')$$,
  '23514',
  'Una cotización no genera factura; primero debe aprobarse y convertirse.',
  'a quotation cannot use the billable invoice entrypoint'
);
select throws_ok(
  $$select public.create_invoice_from_mechanic_job('99616000-0000-4000-8000-000000000071')$$,
  '23514',
  'Una cotización no genera factura; primero debe aprobarse y convertirse.',
  'the historical invoice RPC is now the same guarded quotation path'
);
select throws_ok(
  $$update public.mechanic_jobs
    set invoice_id = '99616000-0000-4000-8000-000000000061', is_invoiced = true
    where id = '99616000-0000-4000-8000-000000000071'$$,
  '23514',
  'Una cotización no puede tener factura. Apruébala y conviértela primero.',
  'a quotation cannot be linked to an invoice directly'
);
select throws_ok(
  $$update public.mechanic_jobs
    set is_invoiced = true
    where id = '99616000-0000-4000-8000-000000000071'$$,
  '23514',
  'Una cotización no puede tener factura ni pago. Apruébala y conviértela primero.',
  'a quotation cannot fake an invoiced flag without an invoice link'
);

update public.sales_invoices
set status = 'cancelled'
where id = '99616000-0000-4000-8000-000000000061';

select is(
  (select status from public.sales_invoices where id = '99616000-0000-4000-8000-000000000061'),
  'cancelled',
  'a zero-effect detached draft can be preserved as cancelled evidence'
);
select is(
  (select count(*)::integer
   from public.stock_movements
   where source_document_type = 'sales_invoice'
     and source_document_id = '99616000-0000-4000-8000-000000000061'),
  0,
  'cancelling the preserved draft creates no stock movement'
);
select is(
  (select count(*)::integer
   from public.journal_entries
   where source_document_type = 'sales_invoice'
     and source_document_id = '99616000-0000-4000-8000-000000000061'),
  0,
  'cancelling the preserved draft creates no journal'
);
select throws_ok(
  $$select public.convert_mechanic_job_to_billable(
    '99616000-0000-4000-8000-000000000071', 'service', null, true,
    '99616000-0000-4000-8000-000000000031', null,
    '99616000-0000-4000-8000-000000000201'
  )$$,
  '23514',
  'La cotización debe estar aprobada antes de convertirse.',
  'pending quotations cannot be converted'
);

select is(
  public.transition_mechanic_job_quotation(
    '99616000-0000-4000-8000-000000000071',
    'approved',
    null,
    '99616000-0000-4000-8000-000000000202'
  )->>'quotation_status',
  'approved',
  'quotation approval uses the audited command'
);
select is(
  (select actor_id
   from public.mechanic_job_mode_events
   where operation_key = '99616000-0000-4000-8000-000000000202'),
  '99616000-0000-4000-8000-000000000099'::uuid,
  'quotation approval records the authenticated employee'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_mode_events
   where job_id = '99616000-0000-4000-8000-000000000071'
     and event_type = 'quotation_status_changed'),
  1,
  'quotation approval appends one status event'
);
select ok(
  (select metadata->'quotation_snapshot' is not null
   from public.mechanic_job_mode_events
   where operation_key = '99616000-0000-4000-8000-000000000202'),
  'quotation approval stores an immutable commercial snapshot'
);
select is(
  (select metadata->'quotation_snapshot'->'items'->0->>'id'
   from public.mechanic_job_mode_events
   where operation_key = '99616000-0000-4000-8000-000000000202'),
  '99616000-0000-4000-8000-000000000081',
  'the approval snapshot preserves the exact accepted line identity'
);
select is(
  (select metadata->>'quotation_snapshot_hash'
   from public.mechanic_job_mode_events
   where operation_key = '99616000-0000-4000-8000-000000000202'),
  (select encode(
      extensions.digest((metadata->'quotation_snapshot')::text, 'sha256'),
      'hex'
    )
   from public.mechanic_job_mode_events
   where operation_key = '99616000-0000-4000-8000-000000000202'),
  'the approval event stores a reproducible snapshot hash'
);
select throws_ok(
  $$update public.mechanic_job_items
    set unit_price = 9500, total_price = 9500
    where id = '99616000-0000-4000-8000-000000000081'$$,
  '23514',
  'Los ítems de una cotización decidida son inmutables; reábrela antes de editarlos.',
  'approved quotation lines cannot drift before conversion'
);
select throws_ok(
  $$update public.mechanic_job_items
    set job_id = '99616000-0000-4000-8000-000000000077'
    where id = '99616000-0000-4000-8000-000000000081'$$,
  '23514',
  'Los ítems de una cotización decidida son inmutables; reábrela antes de editarlos.',
  'an approved line cannot escape immutability by being reparented'
);
select throws_ok(
  $$update public.mechanic_jobs
    set discount_amount = 500
    where id = '99616000-0000-4000-8000-000000000071'$$,
  '23514',
  'La cotización decidida es inmutable; reábrela antes de editarla.',
  'approved quotation commercial fields cannot drift before conversion'
);
select throws_ok(
  $$update public.mechanic_jobs
    set job_type = 'service'
    where id = '99616000-0000-4000-8000-000000000071'$$,
  '23514',
  'Selecciona la bicicleta o componente recibido desde la versión actual antes de convertir el presupuesto.',
  'a legacy approved conversion cannot bypass resolved intake'
);

select throws_ok(
  $$select public.convert_mechanic_job_to_billable(
    '99616000-0000-4000-8000-000000000071', 'service', null, true,
    '99616000-0000-4000-8000-000000000041', null,
    '99616000-0000-4000-8000-000000000203'
  )$$,
  '23514',
  'Selecciona una bicicleta activa del mismo cliente antes de convertir la cotización.',
  'conversion rejects a bicycle from another tenant/customer'
);

create temporary table mode_bike_conversion as
select public.convert_mechanic_job_to_billable(
  '99616000-0000-4000-8000-000000000071',
  'service',
  'Cliente aprobó el presupuesto por WhatsApp.',
  true,
  '99616000-0000-4000-8000-000000000031',
  null,
  '99616000-0000-4000-8000-000000000204'
) as result;

select is(
  (select job_type from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000071'),
  'service',
  'approved bicycle quote becomes a normal service in place'
);
select is(
  (select intake_kind from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000071'),
  'bike',
  'converted bicycle quote has bicycle intake semantics'
);
select is(
  (select bike_id from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000071'),
  '99616000-0000-4000-8000-000000000031'::uuid,
  'conversion attaches the selected customer bicycle'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_bikes
   where job_id = '99616000-0000-4000-8000-000000000071'
     and bike_id = '99616000-0000-4000-8000-000000000031'),
  1,
  'conversion creates exactly one job-bicycle aggregate row'
);
select ok(
  (select job_bike_id is not null
   from public.mechanic_job_items
   where id = '99616000-0000-4000-8000-000000000081'),
  'unassigned quotation items become attributed to the selected bicycle'
);
select ok(
  (select invoice_id is not null and is_invoiced
   from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000071'),
  'conversion creates and links the draft invoice atomically'
);
select is(
  (select invoice.status
   from public.sales_invoices invoice
   join public.mechanic_jobs job on job.invoice_id = invoice.id
   where job.id = '99616000-0000-4000-8000-000000000071'),
  'draft',
  'the converted invoice starts as a non-posted draft'
);
select is(
  (select count(*)::integer
   from public.stock_movements movement
   join public.mechanic_jobs job on job.invoice_id = movement.source_document_id
   where job.id = '99616000-0000-4000-8000-000000000071'
     and movement.source_document_type = 'sales_invoice'),
  0,
  'draft conversion creates no inventory movement'
);
select is(
  (select count(*)::integer
   from public.journal_entries journal
   join public.mechanic_jobs job on job.invoice_id = journal.source_document_id
   where job.id = '99616000-0000-4000-8000-000000000071'
     and journal.source_document_type = 'sales_invoice'),
  0,
  'draft conversion creates no accounting journal'
);
select is(
  (select event_type
   from public.mechanic_job_mode_events
   where operation_key = '99616000-0000-4000-8000-000000000204'),
  'converted_to_billable',
  'conversion has one immutable audit event'
);
select is(
  (select metadata->>'quotation_snapshot_hash'
   from public.mechanic_job_mode_events
   where operation_key = '99616000-0000-4000-8000-000000000204'),
  (select metadata->>'quotation_snapshot_hash'
   from public.mechanic_job_mode_events
   where operation_key = '99616000-0000-4000-8000-000000000202'),
  'conversion points to the exact snapshot that the customer approved'
);
select is(
  (select (metadata->>'snapshot_verified_at_conversion')::boolean
   from public.mechanic_job_mode_events
   where operation_key = '99616000-0000-4000-8000-000000000204'),
  true,
  'conversion certifies that approved content did not drift'
);

update public.mechanic_jobs
set notes = 'Diagnóstico operativo posterior a la recepción.'
where id = '99616000-0000-4000-8000-000000000071';

update public.mechanic_job_items
set unit_price = 9500,
    total_price = 9500
where id = '99616000-0000-4000-8000-000000000081';

select is(
  (select notes from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000071'),
  'Diagnóstico operativo posterior a la recepción.',
  'the converted service remains editable for normal workshop operations'
);
select is(
  (select unit_price from public.mechanic_job_items
   where id = '99616000-0000-4000-8000-000000000081'),
  9500::numeric,
  'the converted service can add or revise current billable work'
);
select is(
  (select (metadata->'quotation_snapshot'->'items'->0->>'unit_price')::numeric
   from public.mechanic_job_mode_events
   where operation_key = '99616000-0000-4000-8000-000000000204'),
  9000::numeric,
  'post-conversion edits never rewrite the customer-approved quotation snapshot'
);

select is(
  public.convert_mechanic_job_to_billable(
    '99616000-0000-4000-8000-000000000071',
    'service',
    'Cliente aprobó el presupuesto por WhatsApp.',
    true,
    '99616000-0000-4000-8000-000000000031',
    null,
    '99616000-0000-4000-8000-000000000204'
  )->>'invoice_id',
  (select result->>'invoice_id' from mode_bike_conversion),
  'replaying the operation key returns the original invoice'
);
select throws_ok(
  $$select public.convert_mechanic_job_to_billable(
    '99616000-0000-4000-8000-000000000071',
    'service',
    'payload diferente con la misma clave',
    true,
    '99616000-0000-4000-8000-000000000031',
    null,
    '99616000-0000-4000-8000-000000000204'
  )$$,
  '23505',
  'La clave de operación ya pertenece a otra transición de trabajo.',
  'a conversion receipt cannot be replayed with a different request payload'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_mode_events
   where operation_key = '99616000-0000-4000-8000-000000000204'),
  1,
  'conversion operation replay does not duplicate audit events'
);
select is(
  public.convert_mechanic_job_to_billable(
    '99616000-0000-4000-8000-000000000071',
    'service',
    'retry after lost response with a fresh key',
    true,
    '99616000-0000-4000-8000-000000000031',
    null,
    '99616000-0000-4000-8000-000000000208'
  )->>'invoice_id',
  (select result->>'invoice_id' from mode_bike_conversion),
  'a fresh-key retry after conversion returns the committed invoice'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_mode_events
   where job_id = '99616000-0000-4000-8000-000000000071'
     and event_type = 'converted_to_billable'),
  1,
  'fresh-key retry does not append a second conversion event'
);

-- A normal workshop reception can begin as a non-posting service budget. The
-- conversion must reuse its already-persisted bike aggregate when the client
-- sends no replacement p_bike_id, preserving ficha, diagnosis and attribution.
create temporary table mode_service_budget_finance_baseline as
select
  (select count(*)::integer from public.sales_invoices) as invoice_count,
  (select count(*)::integer from public.stock_movements) as stock_count,
  (select count(*)::integer from public.journal_entries) as journal_count;

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, job_number, job_type, workflow_kind,
  intake_kind, quotation_status, quotation_valid_until, discount_amount,
  client_request, diagnosis, status
) values (
  '99616000-0000-4000-8000-000000000090',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  '99616000-0000-4000-8000-000000000031',
  'MODE-SERVICE-BUDGET',
  'quotation',
  'quotation',
  'bike',
  'pending',
  clock_timestamp() + interval '7 days',
  500,
  'Mantención completa solicitada',
  'Transmisión requiere limpieza',
  'PRESUPUESTO'
);

insert into public.mechanic_job_bikes(
  id, tenant_id, job_id, bike_id, order_index, diagnosis, work_requested,
  technician_notes, diagnosis_sheet_key, diagnosis_sheet_data
) values
  (
    '99616000-0000-4000-8000-000000000091',
    '99616000-0000-4000-8000-000000000001',
    '99616000-0000-4000-8000-000000000090',
    '99616000-0000-4000-8000-000000000031',
    0,
    'Diagnóstico por bicicleta conservado',
    'Limpieza y ajuste',
    'No reemplazar cadena sin confirmar',
    'workshop-v1',
    jsonb_build_object('drivetrain', jsonb_build_object('status', 'dirty'))
  ),
  (
    '99616000-0000-4000-8000-000000000095',
    '99616000-0000-4000-8000-000000000001',
    '99616000-0000-4000-8000-000000000090',
    '99616000-0000-4000-8000-000000000032',
    1,
    'Segunda bicicleta conservada',
    'Regulación secundaria',
    null,
    'workshop-v1',
    jsonb_build_object('brakes', jsonb_build_object('status', 'review'))
  );

insert into public.mechanic_job_items(
  id, tenant_id, job_id, job_bike_id, product_id, product_name, product_sku,
  item_type, quantity, unit_price
) values
  (
    '99616000-0000-4000-8000-000000000092',
    '99616000-0000-4000-8000-000000000001',
    '99616000-0000-4000-8000-000000000090',
    '99616000-0000-4000-8000-000000000091',
    '99616000-0000-4000-8000-000000000051',
    'Quoted Part',
    'MODE-PART',
    'product',
    1,
    9000
  ),
  (
    '99616000-0000-4000-8000-000000000093',
    '99616000-0000-4000-8000-000000000001',
    '99616000-0000-4000-8000-000000000090',
    '99616000-0000-4000-8000-000000000095',
    null,
    'Second Bike Labor',
    null,
    'service',
    1,
    2000
  ),
  (
    '99616000-0000-4000-8000-000000000094',
    '99616000-0000-4000-8000-000000000001',
    '99616000-0000-4000-8000-000000000090',
    null,
    null,
    'General inspection',
    null,
    'service',
    1,
    1000
  );

select is(
  (select job_type from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000090'),
  'quotation',
  'a service budget keeps the rolling-compatible quotation facade'
);
select is(
  (select workflow_kind || '/' || intake_kind from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000090'),
  'quotation/bike',
  'a service budget independently records proposal workflow and bike custody'
);
select is(
  (select total_cost from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000090'),
  11500::numeric,
  'a multi-bike service budget total includes linked and General lines plus its staged discount'
);
select is(
  (select count(*)::integer from public.sales_invoices),
  (select invoice_count from mode_service_budget_finance_baseline),
  'saving a service budget does not create an invoice'
);
select is(
  (select count(*)::integer from public.stock_movements),
  (select stock_count from mode_service_budget_finance_baseline),
  'saving service-budget product lines creates no stock movement'
);
select is(
  (select count(*)::integer from public.journal_entries),
  (select journal_count from mode_service_budget_finance_baseline),
  'saving service-budget product lines creates no accounting journal'
);

select is(
  public.transition_mechanic_job_quotation(
    '99616000-0000-4000-8000-000000000090',
    'approved',
    null,
    '99616000-0000-4000-8000-000000000220'
  )->>'quotation_status',
  'approved',
  'the service budget uses the same audited approval command'
);

select throws_ok(
  $$update public.mechanic_job_bikes
      set diagnosis = 'Mutación posterior a la aprobación'
    where id = '99616000-0000-4000-8000-000000000091'$$,
  '23514',
  'Las bicicletas y fichas de un presupuesto decidido son inmutables; reabre la propuesta mediante el comando auditado.',
  'an approved service budget protects its bicycle ficha and diagnosis'
);

select throws_ok(
  $$update public.mechanic_job_items
      set job_bike_id = '99616000-0000-4000-8000-000000000091'
    where id = '99616000-0000-4000-8000-000000000094'$$,
  '23514',
  'Los ítems de una cotización decidida son inmutables; reábrela antes de editarlos.',
  'approved service-budget attribution cannot be changed outside the audited conversion command'
);

create temporary table mode_service_budget_conversion as
select public.convert_mechanic_job_to_billable(
  '99616000-0000-4000-8000-000000000090',
  'service',
  null,
  true,
  null,
  null,
  '99616000-0000-4000-8000-000000000221'
) as result;

select is(
  (select result->>'job_id' from mode_service_budget_conversion),
  '99616000-0000-4000-8000-000000000090',
  'service-budget conversion keeps the same workshop job identity'
);
select is(
  (select workflow_kind || '/' || intake_kind from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000090'),
  'service/bike',
  'approved service budget becomes a billable bike service in place'
);
select is(
  (select count(*)::integer from public.sales_invoices invoice
   join public.mechanic_jobs job on job.invoice_id = invoice.id
   where job.id = '99616000-0000-4000-8000-000000000090'),
  1,
  'service-budget conversion creates exactly one linked invoice'
);
select is(
  (select count(*)::integer from public.mechanic_job_bikes
   where job_id = '99616000-0000-4000-8000-000000000090'),
  2,
  'service-budget conversion preserves the complete received multi-bike graph'
);
select is(
  (select diagnosis from public.mechanic_job_bikes
   where id = '99616000-0000-4000-8000-000000000091'),
  'Diagnóstico por bicicleta conservado',
  'service-budget conversion preserves the persisted bike diagnosis row'
);
select is(
  (select diagnosis_sheet_data->'drivetrain'->>'status'
   from public.mechanic_job_bikes
   where id = '99616000-0000-4000-8000-000000000091'),
  'dirty',
  'service-budget conversion preserves structured ficha data'
);
select is(
  (select job_bike_id from public.mechanic_job_items
   where id = '99616000-0000-4000-8000-000000000092'),
  '99616000-0000-4000-8000-000000000091'::uuid,
  'service-budget conversion preserves existing line-to-bike attribution'
);
select is(
  (select job_bike_id from public.mechanic_job_items
   where id = '99616000-0000-4000-8000-000000000094'),
  null::uuid,
  'service-budget conversion preserves an intentional General line as unscoped'
);
select is(
  (select job_bike_id from public.mechanic_job_items
   where id = '99616000-0000-4000-8000-000000000093'),
  '99616000-0000-4000-8000-000000000095'::uuid,
  'service-budget conversion does not collapse the second bicycle into the primary bicycle'
);
select is(
  (select subtotal from public.mechanic_job_bikes
   where id = '99616000-0000-4000-8000-000000000091'),
  9000::numeric,
  'conversion does not fold General work into the primary bicycle rollup'
);
select is(
  (select subtotal from public.mechanic_job_bikes
   where id = '99616000-0000-4000-8000-000000000095'),
  2000::numeric,
  'conversion preserves the second bicycle rollup'
);
select is(
  (select invoice.total
   from public.sales_invoices invoice
   join public.mechanic_jobs job on job.invoice_id = invoice.id
   where job.id = '99616000-0000-4000-8000-000000000090'),
  11500::numeric,
  'the linked invoice still includes bike-linked and General commercial lines'
);
select is(
  (select job.id::text from public.mechanic_jobs job
   where job.invoice_id = (
     select result->>'invoice_id' from mode_service_budget_conversion
   )::uuid),
  '99616000-0000-4000-8000-000000000090',
  'invoice-to-job navigation resolves the same enforced foreign key in reverse'
);
select is(
  (select count(*)::integer from public.sales_invoices),
  (select invoice_count + 1 from mode_service_budget_finance_baseline),
  'conversion adds only its one draft invoice'
);
select is(
  (select count(*)::integer from public.stock_movements),
  (select stock_count from mode_service_budget_finance_baseline),
  'the converted draft invoice still posts no stock movement'
);
select is(
  (select count(*)::integer from public.journal_entries),
  (select journal_count from mode_service_budget_finance_baseline),
  'the converted draft invoice still posts no accounting journal'
);
select is(
  public.convert_mechanic_job_to_billable(
    '99616000-0000-4000-8000-000000000090',
    'service',
    null,
    true,
    null,
    null,
    '99616000-0000-4000-8000-000000000221'
  )->>'invoice_id',
  (select result->>'invoice_id' from mode_service_budget_conversion),
  'service-budget conversion replays without creating another invoice'
);
select is(
  (select count(*)::integer from public.mechanic_job_mode_events
   where job_id = '99616000-0000-4000-8000-000000000090'
     and event_type = 'converted_to_billable'),
  1,
  'service-budget conversion appends exactly one immutable conversion event'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type,
  quotation_status, quotation_valid_until, subject_notes, status
) values (
  '99616000-0000-4000-8000-000000000072',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  'MODE-QUOTE-COMPONENT',
  'quotation',
  'pending',
  clock_timestamp() + interval '7 days',
  'Rueda trasera para enrayar',
  'PRESUPUESTO'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, item_type, quantity, unit_price
) values (
  '99616000-0000-4000-8000-000000000073',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000072',
  'Component labor',
  'service',
  1,
  3000
);

select is(
  public.transition_mechanic_job_quotation(
    '99616000-0000-4000-8000-000000000072',
    'approved',
    null,
    '99616000-0000-4000-8000-000000000211'
  )->>'quotation_status',
  'approved',
  'component quotation also receives an immutable approval snapshot'
);

select throws_ok(
  $$select public.convert_mechanic_job_to_billable(
    '99616000-0000-4000-8000-000000000072',
    'item_service',
    'Cliente dejó solamente la rueda.',
    true,
    null,
    '99616000-0000-4000-8000-000000000044',
    '99616000-0000-4000-8000-000000000202'
  )$$,
  '23505',
  'La clave de operación ya pertenece a otra transición de trabajo.',
  'a quotation transition receipt cannot be reused as a conversion receipt'
);

create temporary table mode_component_subject as
select id
from public.job_subjects
where id = '99616000-0000-4000-8000-000000000044';

create temporary table mode_component_conversion as
select public.convert_mechanic_job_to_billable(
  '99616000-0000-4000-8000-000000000072',
  'item_service',
  'Cliente dejó solamente la rueda.',
  true,
  null,
  (select id from mode_component_subject),
  '99616000-0000-4000-8000-000000000205'
) as result;

select is(
  (select job_type from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000072'),
  'item_service',
  'component quote keeps the familiar component compatibility type'
);
select is(
  (select intake_kind from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000072'),
  'component',
  'component conversion records that no complete bicycle was received'
);
select is(
  (select bike_id from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000072'),
  null::uuid,
  'component conversion does not inflate the bicycle count'
);
select is(
  (select subject_id from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000072'),
  (select id from mode_component_subject),
  'component conversion attaches the selected tenant subject'
);
select ok(
  (select result->>'invoice_id' is not null from mode_component_conversion),
  'billable component service receives its own draft invoice'
);

select throws_ok(
  $$update public.mechanic_jobs
    set job_type = 'service', quotation_status = 'approved'
    where id = '99616000-0000-4000-8000-000000000078'$$,
  '23514',
  'La versión anterior solo puede convertir un presupuesto previamente aprobado; actualiza la aplicación para completar este flujo.',
  'a legacy client cannot combine pending approval and conversion'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, bike_id,
  quotation_status, quotation_valid_until, status
) values (
  '99616000-0000-4000-8000-000000000080',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  'MODE-QUOTE-LEGACY-BRIDGE',
  'quotation',
  '99616000-0000-4000-8000-000000000031',
  'pending',
  clock_timestamp() + interval '7 days',
  'PRESUPUESTO'
);
insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_id, product_name, product_sku,
  item_type, quantity, unit_price
) values (
  '99616000-0000-4000-8000-000000000089',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000080',
  '99616000-0000-4000-8000-000000000051',
  'Quoted Part', 'MODE-PART', 'product', 1, 9000
);

select throws_ok(
  $$update public.mechanic_jobs
    set quotation_status = 'approved',
        client_request = 'Contenido inyectado al aprobar'
    where id = '99616000-0000-4000-8000-000000000080'$$,
  '23514',
  'La versión anterior solo puede cambiar el estado del presupuesto; edita su contenido desde la versión actual.',
  'legacy status approval cannot smuggle a commercial edit'
);
select is(
  (select quotation_status from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000080'),
  'pending',
  'a rejected combined approval leaves the quotation pending'
);

update public.mechanic_jobs
set quotation_status = 'approved'
where id = '99616000-0000-4000-8000-000000000080';

select is(
  (select quotation_status from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000080'),
  'approved',
  'legacy status-only approval remains available during client rollout'
);
select ok(
  (select approved_by_customer
      and approved_at is not null
   from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000080'),
  'legacy approval normalizes the customer approval fields server-side'
);
select ok(
  (select metadata->>'compatibility_path' = 'true'
      and metadata->'quotation_snapshot' is not null
      and nullif(metadata->>'quotation_snapshot_hash', '') is not null
   from public.mechanic_job_mode_events
   where job_id = '99616000-0000-4000-8000-000000000080'
     and event_type = 'quotation_status_changed'
   order by occurred_at desc, id desc
   limit 1),
  'legacy status approval receives the same immutable snapshot evidence'
);

select throws_ok(
  $$update public.mechanic_jobs
    set job_type = 'service',
        workflow_kind = 'service',
        quotation_status = null,
        invoice_id = '99616000-0000-4000-8000-000000000061',
        is_invoiced = true,
        converted_at = '2000-01-01T00:00:00Z'::timestamptz
    where id = '99616000-0000-4000-8000-000000000080'$$,
  '23514',
  'La conversión anterior no puede vincular facturas ni pagos; la factura se crea en la acción atómica posterior.',
  'legacy conversion cannot inject an arbitrary same-tenant invoice'
);
select is(
  (select invoice_id from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000080'),
  null::uuid,
  'a rejected invoice injection leaves the approved quotation unlinked'
);

update public.mechanic_jobs
set job_type = 'service',
    quotation_status = null,
    quotation_valid_until = null,
    is_warranty_job = false,
    converted_at = '2000-01-01T00:00:00Z'::timestamptz
where id = '99616000-0000-4000-8000-000000000080';

select is(
  (select workflow_kind from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000080'),
  'service',
  'legacy conversion is bridged only after a verified approval'
);
select is(
  (select quotation_status from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000080'),
  null::text,
  'legacy conversion normalizes the quotation status on the service'
);
select ok(
  (select quotation_valid_until is not null
   from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000080'),
  'legacy conversion preserves the approved validity evidence'
);
select ok(
  (select converted_at > clock_timestamp() - interval '1 minute'
   from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000080'),
  'legacy conversion replaces a client timestamp with server time'
);
select ok(
  (select metadata->>'compatibility_path' = 'true'
      and metadata->>'legacy_bridge' = 'approved-quotation-conversion-v1'
      and (metadata->>'snapshot_verified_at_conversion')::boolean
   from public.mechanic_job_mode_events
   where job_id = '99616000-0000-4000-8000-000000000080'
     and event_type = 'converted_to_billable'
   order by occurred_at desc, id desc
   limit 1),
  'legacy conversion records a verified compatibility receipt'
);
select is(
  (select invoice_id from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000080'),
  null::uuid,
  'legacy bridge does not invent an invoice outside its original second action'
);
select is(
  (select count(*)::integer from public.stock_movements
   where source_document_id = '99616000-0000-4000-8000-000000000080'),
  0,
  'legacy bridge conversion has no direct inventory effect'
);
select is(
  (select count(*)::integer from public.journal_entries
   where source_document_id = '99616000-0000-4000-8000-000000000080'),
  0,
  'legacy bridge conversion has no direct accounting effect'
);

insert into public.job_subjects(
  id, tenant_id, name, category, is_active
) values
  (
    '99616000-0000-4000-8000-000000000042',
    '99616000-0000-4000-8000-000000000002',
    'Cross-tenant wheel', 'Ruedas', true
  ),
  (
    '99616000-0000-4000-8000-000000000043',
    '99616000-0000-4000-8000-000000000001',
    'Inactive local wheel', 'Ruedas', false
  );

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, intake_kind,
  subject_id, subject_notes, quotation_status, quotation_valid_until, status
) values (
  '99616000-0000-4000-8000-000000000084',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  'MODE-QUOTE-INACTIVE-SUBJECT',
  'quotation', 'component',
  '99616000-0000-4000-8000-000000000043',
  'Rueda inactiva descrita', 'pending',
  clock_timestamp() + interval '7 days', 'PRESUPUESTO'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, item_type, quantity, unit_price
) values (
  '99616000-0000-4000-8000-000000000096',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000084',
  'Component inspection', 'service', 1, 0
);

select public.transition_mechanic_job_quotation(
  '99616000-0000-4000-8000-000000000084',
  'approved', null,
  '99616000-0000-4000-8000-000000000215'
);

select throws_ok(
  $$select public.convert_mechanic_job_to_billable(
    '99616000-0000-4000-8000-000000000084',
    'item_service', 'Cliente dejó la rueda descrita.', false,
    null, null,
    '99616000-0000-4000-8000-000000000216'
  )$$,
  '23514',
  'El componente recibido debe estar activo y pertenecer al negocio del trabajo.',
  'canonical conversion rejects a persisted inactive component subject even when notes exist'
);

select ok(
  (select workflow_kind = 'quotation'
      and subject_id = '99616000-0000-4000-8000-000000000043'::uuid
      and invoice_id is null
      and not exists (
        select 1
        from public.mechanic_job_mode_events event
        where event.job_id = mechanic_jobs.id
          and event.event_type = 'converted_to_billable'
      )
   from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000084'),
  'failed inactive-subject conversion leaves the quote, invoice, and event ledger unchanged'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, intake_kind,
  subject_notes, quotation_status, quotation_valid_until, status
) values (
  '99616000-0000-4000-8000-000000000085',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  'MODE-QUOTE-EXPLICIT-CROSS-TENANT-SUBJECT',
  'quotation', 'component', 'Rueda por seleccionar', 'pending',
  clock_timestamp() + interval '7 days', 'PRESUPUESTO'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, item_type, quantity, unit_price
) values (
  '99616000-0000-4000-8000-000000000097',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000085',
  'Component inspection', 'service', 1, 0
);

select public.transition_mechanic_job_quotation(
  '99616000-0000-4000-8000-000000000085',
  'approved', null,
  '99616000-0000-4000-8000-000000000217'
);

select throws_ok(
  $$select public.convert_mechanic_job_to_billable(
    '99616000-0000-4000-8000-000000000085',
    'item_service', 'Cliente dejó una rueda.', false,
    null, '99616000-0000-4000-8000-000000000042',
    '99616000-0000-4000-8000-000000000218'
  )$$,
  '23514',
  'El componente recibido debe estar activo y pertenecer al negocio del trabajo.',
  'canonical conversion rejects an explicitly requested cross-tenant component subject'
);

select ok(
  (select workflow_kind = 'quotation'
      and subject_id is null
      and invoice_id is null
      and not exists (
        select 1
        from public.mechanic_job_mode_events event
        where event.job_id = mechanic_jobs.id
          and event.event_type = 'converted_to_billable'
      )
   from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000085'),
  'failed cross-tenant conversion leaves the quote, invoice, and event ledger unchanged'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, intake_kind,
  subject_id, subject_notes, quotation_status, quotation_valid_until, status
) values (
  '99616000-0000-4000-8000-000000000082',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  'MODE-QUOTE-CROSS-TENANT-SUBJECT',
  'quotation', 'component',
  '99616000-0000-4000-8000-000000000042',
  'Rueda suelta', 'pending', clock_timestamp() + interval '7 days',
  'PRESUPUESTO'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, item_type, quantity, unit_price
) values (
  '99616000-0000-4000-8000-000000000098',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000082',
  'Component inspection', 'service', 1, 0
);

select public.transition_mechanic_job_quotation(
  '99616000-0000-4000-8000-000000000082',
  'approved', null,
  '99616000-0000-4000-8000-000000000214'
);

select throws_ok(
  $$update public.mechanic_jobs
    set job_type = 'item_service',
        quotation_status = null,
        quotation_valid_until = null,
        is_warranty_job = false,
        converted_at = '2000-01-01T00:00:00Z'::timestamptz
    where id = '99616000-0000-4000-8000-000000000082'$$,
  '23514',
  'El componente recibido debe estar activo y pertenecer al negocio del trabajo.',
  'legacy component conversion rejects a cross-tenant subject'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type,
  quotation_status, quotation_valid_until, status
) values (
  '99616000-0000-4000-8000-000000000073',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  'MODE-QUOTE-EXPIRED',
  'quotation',
  'pending',
  clock_timestamp() - interval '1 day',
  'PRESUPUESTO'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, item_type, quantity, unit_price
) values (
  '99616000-0000-4000-8000-000000000100',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000073',
  'Quotation review', 'service', 1, 0
);

select throws_ok(
  $$select public.transition_mechanic_job_quotation(
    '99616000-0000-4000-8000-000000000073',
    'approved',
    'Intento de reutilizar una clave de otra cotización.',
    '99616000-0000-4000-8000-000000000202'
  )$$,
  '23505',
  'La clave de operación ya pertenece a otra transición de trabajo.',
  'a quotation status receipt cannot be replayed against another job'
);

select is(
  (select effective_quotation_status
   from public.mechanic_job_mode_view
   where job_id = '99616000-0000-4000-8000-000000000073'),
  'expired',
  'quotation expiry is derived without mutating the stored pending status'
);
select throws_ok(
  $$update public.mechanic_jobs
    set quotation_status = 'approved'
    where id = '99616000-0000-4000-8000-000000000073'$$,
  '23514',
  'La cotización venció; apruébala desde la versión actual para registrar el motivo.',
  'legacy status writes cannot approve an expired quotation without a reason'
);
select throws_ok(
  $$select public.transition_mechanic_job_quotation(
    '99616000-0000-4000-8000-000000000073', 'approved', null,
    '99616000-0000-4000-8000-000000000206'
  )$$,
  '23514',
  'La cotización venció; registra el motivo para aprobarla fuera de plazo.',
  'expired quotation approval requires an explicit reason'
);
select is(
  public.transition_mechanic_job_quotation(
    '99616000-0000-4000-8000-000000000073',
    'approved',
    'Cliente confirmó mantener el precio anterior.',
    '99616000-0000-4000-8000-000000000207'
  )->>'quotation_status',
  'approved',
  'expired quotation approval is possible with an audited reason'
);

select is(
  public.transition_mechanic_job_quotation(
    '99616000-0000-4000-8000-000000000073',
    'rejected',
    'Cliente rechazó expresamente la primera versión.',
    '99616000-0000-4000-8000-000000000212'
  )->>'quotation_status',
  'rejected',
  'the canonical command still supports an audited rejection'
);

select throws_ok(
  $$insert into public.mechanic_job_items(
      id, tenant_id, job_id, product_id, product_name, product_sku,
      item_type, quantity, unit_price
    ) values (
      '99616000-0000-4000-8000-000000000083',
      '99616000-0000-4000-8000-000000000001',
      '99616000-0000-4000-8000-000000000073',
      '99616000-0000-4000-8000-000000000051',
      'Quoted Part', 'MODE-PART', 'product', 1, 9000
    )$$,
  '23514',
  'Los ítems de una cotización decidida son inmutables; reábrela antes de editarlos.',
  'a rejected quotation cannot gain lines without reopening'
);
select throws_ok(
  $$update public.mechanic_jobs
    set client_request = 'Cambio posterior al rechazo'
    where id = '99616000-0000-4000-8000-000000000073'$$,
  '23514',
  'La cotización decidida es inmutable; reábrela antes de editarla.',
  'a rejected quotation cannot drift through job fields either'
);
select is(
  public.transition_mechanic_job_quotation(
    '99616000-0000-4000-8000-000000000073',
    'pending',
    'Se reabre para preparar una nueva versión.',
    '99616000-0000-4000-8000-000000000213'
  )->>'quotation_status',
  'pending',
  'a reasoned reopen restores the editable pending state'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_id, product_name, product_sku,
  item_type, quantity, unit_price
) values (
  '99616000-0000-4000-8000-000000000083',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000073',
  '99616000-0000-4000-8000-000000000051',
  'Quoted Part', 'MODE-PART', 'product', 1, 9000
);

select is(
  (select total_cost from public.mechanic_jobs
   where id = '99616000-0000-4000-8000-000000000073'),
  9000::numeric,
  'reopened quotation lines are editable and recalculate without tax'
);

select is(
  (select count(*)::integer
   from public.mechanic_job_mode_events
   where job_id = '99616000-0000-4000-8000-000000000073'
     and metadata->>'compatibility_path' = 'true'),
  0,
  'rejected direct status writes leave no misleading compatibility event'
);
select throws_ok(
  $$update public.mechanic_job_mode_events
    set reason = 'tamper'
    where operation_key = '99616000-0000-4000-8000-000000000207'$$,
  '55000',
  'Mechanic job mode events are append-only',
  'mode history cannot be rewritten'
);

select is(
  public.transition_mechanic_job_quotation(
    '99616000-0000-4000-8000-000000000073',
    'approved',
    'Cliente volvió a aprobar expresamente la cotización vencida.',
    '99616000-0000-4000-8000-000000000209'
  )->>'quotation_status',
  'approved',
  'a rejected expired quote can receive a new explicit late approval'
);

create temporary table mode_expired_conversion as
select public.convert_mechanic_job_to_billable(
  '99616000-0000-4000-8000-000000000073',
  'item_service',
  'Aprobación tardía registrada antes de recibir la rueda.',
  false,
  null,
  (select id from mode_component_subject),
  '99616000-0000-4000-8000-000000000210'
) as result;

select is(
  (select job_type from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000073'),
  'item_service',
  'an expired quote with audited late approval can convert coherently'
);
select is(
  (select invoice_id from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000073'),
  null::uuid,
  'late-approved conversion honors the explicit no-invoice option'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, status
) values (
  '99616000-0000-4000-8000-000000000074',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  'MODE-INCOMPLETE-SERVICE',
  'service',
  'PENDIENTE'
);

select is(
  (select mode_needs_review from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000074'),
  true,
  'a service without bicycle/component is flagged instead of guessed'
);
select throws_ok(
  $$select public.create_billable_invoice_from_mechanic_job('99616000-0000-4000-8000-000000000074')$$,
  '23514',
  'Confirma si se recibió una bicicleta o solo un componente antes de facturar.',
  'an unresolved intake cannot create a billable invoice'
);
select throws_ok(
  $$select public.create_invoice_from_mechanic_job('99616000-0000-4000-8000-000000000074')$$,
  '23514',
  'Confirma si se recibió una bicicleta o solo un componente antes de facturar.',
  'legacy clients cannot bypass unresolved intake validation'
);

update public.mechanic_jobs
set mode_needs_review = true,
    mode_review_reason = 'backfill: servicio sin bicicleta verificable'
where id = '99616000-0000-4000-8000-000000000074';

update public.mechanic_jobs
set bike_id = '99616000-0000-4000-8000-000000000031'
where id = '99616000-0000-4000-8000-000000000074';

select is(
  (select intake_kind from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000074'),
  'bike',
  'a legacy bike_id-only update derives bicycle intake without resending mode axes'
);
select is(
  (select mode_needs_review from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000074'),
  false,
  'the concrete legacy bike update clears a historical backfill review flag'
);
select is(
  (select mode_review_reason from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000074'),
  null::text,
  'the resolved legacy graph removes the stale historical review reason'
);
select ok(
  public.create_invoice_from_mechanic_job(
    '99616000-0000-4000-8000-000000000074'
  ) is not null,
  'the normalized legacy update can use the guarded invoice compatibility RPC'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, bike_id, status
) values (
  '99616000-0000-4000-8000-000000000075',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  'MODE-LEGACY-SERVICE-BIKE',
  'service',
  '99616000-0000-4000-8000-000000000031',
  'PENDIENTE'
);

select is(
  (select intake_kind from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000075'),
  'bike',
  'a legacy service insert derives bike intake despite the new column default'
);
select is(
  (select mode_needs_review from public.mechanic_jobs where id = '99616000-0000-4000-8000-000000000075'),
  false,
  'a legacy service insert with a concrete bike is not falsely review-flagged'
);
select ok(
  public.create_invoice_from_mechanic_job(
    '99616000-0000-4000-8000-000000000075'
  ) is not null,
  'the guarded historical RPC remains compatible with a valid legacy bike service'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, bike_id,
  warranty_outcome, status
) values (
  '99616000-0000-4000-8000-000000000076',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000011',
  'MODE-COVERED-WARRANTY',
  'warranty',
  '99616000-0000-4000-8000-000000000031',
  'covered',
  'TERMINADO'
);
insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, item_type,
  quantity, unit_price, total_price
) values (
  '99616000-0000-4000-8000-000000000086',
  '99616000-0000-4000-8000-000000000001',
  '99616000-0000-4000-8000-000000000076',
  'Servicio cubierto',
  'service',
  1,
  15000,
  15000
);

select ok(
  public.create_invoice_from_mechanic_job(
    '99616000-0000-4000-8000-000000000076'
  ) is not null,
  'the compatibility wrapper can create the internal covered-warranty document'
);
select is(
  (select invoice.total
   from public.sales_invoices invoice
   join public.mechanic_jobs job on job.invoice_id = invoice.id
   where job.id = '99616000-0000-4000-8000-000000000076'),
  0::numeric,
  'a newly created covered-warranty invoice has zero customer total'
);
select is(
  (select invoice.balance
   from public.sales_invoices invoice
   join public.mechanic_jobs job on job.invoice_id = invoice.id
   where job.id = '99616000-0000-4000-8000-000000000076'),
  0::numeric,
  'a newly created covered-warranty invoice has zero customer balance'
);
select is(
  (select (invoice.items->0->>'line_total')::numeric
   from public.sales_invoices invoice
   join public.mechanic_jobs job on job.invoice_id = invoice.id
   where job.id = '99616000-0000-4000-8000-000000000076'),
  0::numeric,
  'covered-warranty invoice lines retain reference prices without customer obligation'
);

select * from finish();
rollback;
