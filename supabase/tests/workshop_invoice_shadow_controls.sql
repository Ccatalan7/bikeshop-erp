begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(22);

select hasnt_trigger(
  'public',
  'mechanic_jobs',
  'trg_mechanic_jobs_sync_invoice_update',
  'obsolete statement-level job-to-invoice synchronization remains retired'
);

insert into public.tenants (id, shop_name)
values ('95000000-0000-4000-8000-000000000001', 'Workshop Ownership Shadow Test');

select set_config('request.jwt.claim.sub', '', true);

insert into public.customers (id, tenant_id, name)
values (
  '95000000-0000-4000-8000-000000000002',
  '95000000-0000-4000-8000-000000000001',
  'Workshop Ownership Customer'
);

insert into public.bikes (id, tenant_id, customer_id, brand, model, serial_number)
values (
  '95000000-0000-4000-8000-000000000003',
  '95000000-0000-4000-8000-000000000001',
  '95000000-0000-4000-8000-000000000002',
  'Control', 'Bike', 'CONTROL-BIKE-001'
);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
)
values (
  '95000000-0000-4000-8000-000000000004',
  '95000000-0000-4000-8000-000000000001',
  'Workshop Controlled Part', 'WORKSHOP-CONTROL-PART', 2000, 1000,
  'product', false, true, 5, 5, 0, 100
);

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_id, customer_name, source,
  status, subtotal, net_amount, iva_amount, total, paid_amount, balance, items
)
values (
  '95000000-0000-4000-8000-000000000005',
  '95000000-0000-4000-8000-000000000001',
  'FV-WORKSHOP-CONTROL-001',
  '95000000-0000-4000-8000-000000000002',
  'Workshop Ownership Customer',
  'mechanic_job',
  'draft',
  2000, 2000, 0, 2000, 0, 2000,
  jsonb_build_array(jsonb_build_object(
    'product_id', '95000000-0000-4000-8000-000000000004',
    'product_name', 'Workshop Controlled Part',
    'product_sku', 'WORKSHOP-CONTROL-PART',
    'quantity', 1,
    'unit_price', 2000,
    'line_total', 2000,
    'cost', 1000,
    'item_type', 'product',
    'is_service', false,
    'purchase_treatment', 'inventory'
  ))
);

insert into public.mechanic_jobs (
  id, tenant_id, job_number, customer_id, bike_id, status,
  invoice_id, is_invoiced, is_paid, tax_treatment
)
values (
  '95000000-0000-4000-8000-000000000006',
  '95000000-0000-4000-8000-000000000001',
  'PG-WORKSHOP-CONTROL-001',
  '95000000-0000-4000-8000-000000000002',
  '95000000-0000-4000-8000-000000000003',
  'PENDIENTE',
  '95000000-0000-4000-8000-000000000005',
  true,
  false,
  'no_tax'
);

select is(
  (
    select control_mode
    from public.workshop_invoice_ownership_control_view
    where job_id = '95000000-0000-4000-8000-000000000006'
  ),
  'shadow',
  'no tenant setting defaults the ownership control to shadow mode'
);

select is(
  (
    select control_status
    from public.workshop_invoice_ownership_control_view
    where job_id = '95000000-0000-4000-8000-000000000006'
  ),
  'compliant',
  'new linked job starts with no job-owned stock or revenue posting'
);

update public.sales_invoices
set customer_name = 'Workshop Ownership Customer Updated'
where id = '95000000-0000-4000-8000-000000000005';

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations
    where document_type = 'sales_invoice'
      and document_id = '95000000-0000-4000-8000-000000000005'
      and outcome = 'started'
  ),
  0,
  'ordinary linked invoice updates leave no incomplete trace root'
);

select ok(
  exists (
    select 1
    from public.inventory_accounting_checkpoints checkpoint
    join public.inventory_accounting_operations operation
      on operation.id = checkpoint.operation_id
    where operation.document_type = 'sales_invoice'
      and operation.document_id = '95000000-0000-4000-8000-000000000005'
      and checkpoint.phase = 'invariants_verified'
      and checkpoint.outcome = 'completed'
      and checkpoint.payload->>'control_name' = 'workshop_invoice_owner'
      and checkpoint.payload->>'expected_inventory_owner' = 'sales_invoice'
  ),
  'linked invoice operation receives a compliant ownership checkpoint'
);

update public.mechanic_jobs
set status = 'EN_CURSO'
where id = '95000000-0000-4000-8000-000000000006';

select is(
  (
    select count(*)::integer
    from public.stock_movements
    where reference like 'mechanic_job:95000000-0000-4000-8000-000000000006%'
  ),
  0,
  'job lifecycle status does not create a job-owned stock movement'
);

select is(
  (
    select count(*)::integer
    from public.journal_entries
    where source_module = 'mechanic_jobs'
      and source_reference in (
        '95000000-0000-4000-8000-000000000006',
        'PG-WORKSHOP-CONTROL-001'
      )
  ),
  0,
  'job lifecycle status does not create a job-owned revenue journal'
);

insert into public.stock_movements (
  id, tenant_id, product_id, type, movement_type, quantity, reference, notes
)
values (
  '95000000-0000-4000-8000-000000000007',
  '95000000-0000-4000-8000-000000000001',
  '95000000-0000-4000-8000-000000000004',
  'OUT', 'mechanic_job_shadow_test', -1,
  'mechanic_job:95000000-0000-4000-8000-000000000006',
  'Shadow-only attempted job writer'
);

select is(
  (
    select count(*)::integer
    from public.workshop_invoice_control_events
    where event_type = 'job_stock_writer_attempt'
      and job_id = '95000000-0000-4000-8000-000000000006'
  ),
  1,
  'shadow mode records a job stock writer attempt'
);

insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type,
  source_module, source_reference, status, total_debit, total_credit
)
values (
  '95000000-0000-4000-8000-000000000008',
  '95000000-0000-4000-8000-000000000001',
  'JE-WORKSHOP-SHADOW-001', now(), 'Shadow-only job journal attempt',
  'adjustment', 'mechanic_jobs', 'PG-WORKSHOP-CONTROL-001', 'posted', 0, 0
);

select is(
  (
    select count(*)::integer
    from public.workshop_invoice_control_events
    where event_type = 'job_journal_writer_attempt'
      and job_id = '95000000-0000-4000-8000-000000000006'
  ),
  1,
  'shadow mode records a job revenue journal writer attempt'
);

select is(
  (
    select control_status
    from public.workshop_invoice_ownership_control_view
    where job_id = '95000000-0000-4000-8000-000000000006'
  ),
  'job_stock_writer_detected',
  'ownership view surfaces the highest-priority job stock violation'
);

delete from public.stock_movements
where id = '95000000-0000-4000-8000-000000000007';
delete from public.journal_entries
where id = '95000000-0000-4000-8000-000000000008';

select is(
  (
    select count(*)::integer
    from public.workshop_invoice_control_events
    where job_id = '95000000-0000-4000-8000-000000000006'
  ),
  2,
  'append-only shadow evidence remains after attempted business rows are removed'
);

insert into public.workshop_invoice_control_settings (
  tenant_id, control_mode, expected_inventory_owner, activated_at
)
values (
  '95000000-0000-4000-8000-000000000001',
  'enforce',
  'sales_invoice',
  now()
);

select throws_ok(
  $$
    insert into public.stock_movements (
      tenant_id, product_id, type, movement_type, quantity, reference, notes
    ) values (
      '95000000-0000-4000-8000-000000000001',
      '95000000-0000-4000-8000-000000000004',
      'OUT', 'mechanic_job_enforce_test', -1,
      'mechanic_job:95000000-0000-4000-8000-000000000006',
      'Must be blocked'
    )
  $$,
  '23514',
  'Workshop jobs are operational documents; linked sales invoices exclusively own stock and revenue postings',
  'enforce mode blocks a job-owned stock movement atomically'
);

select throws_ok(
  $$
    insert into public.journal_entries (
      tenant_id, entry_number, entry_date, description, type,
      source_module, source_reference, status, total_debit, total_credit
    ) values (
      '95000000-0000-4000-8000-000000000001',
      'JE-WORKSHOP-ENFORCE-001', now(), 'Must be blocked',
      'adjustment', 'mechanic_jobs', 'PG-WORKSHOP-CONTROL-001', 'posted', 0, 0
    )
  $$,
  '23514',
  'Workshop jobs are operational documents; linked sales invoices exclusively own stock and revenue postings',
  'enforce mode blocks a job-owned revenue journal atomically'
);

select is(
  (
    select count(*)::integer
    from public.stock_movements
    where reference like 'mechanic_job:95000000-0000-4000-8000-000000000006%'
  ),
  0,
  'blocked job posting leaves no stock movement'
);

select is(
  (select stock_quantity from public.products where id = '95000000-0000-4000-8000-000000000004'),
  5,
  'shadow and blocked attempts do not alter product stock'
);

update public.sales_invoices
set status = 'confirmed'
where id = '95000000-0000-4000-8000-000000000005';

select is(
  (select stock_quantity from public.products where id = '95000000-0000-4000-8000-000000000004'),
  4,
  'enforce mode allows the linked invoice to deduct stock exactly once'
);

select is(
  (
    select count(*)::integer
    from public.stock_movements
    where reference = 'sales_invoice:95000000-0000-4000-8000-000000000005'
      and type = 'OUT'
  ),
  1,
  'invoice-owned stock deduction has one persisted movement'
);

select results_eq(
  $$
    select control_mode, expected_inventory_owner, control_status,
           job_stock_movement_count, job_journal_count,
           invoice_stock_movement_count, invoice_journal_count
    from public.workshop_invoice_ownership_control_view
    where job_id = '95000000-0000-4000-8000-000000000006'
  $$,
  $$values ('enforce'::text, 'sales_invoice'::text, 'compliant'::text,
            0::bigint, 0::bigint, 1::bigint, 1::bigint)$$,
  'control view certifies the invoice as the sole stock and revenue owner'
);

select is(
  has_function_privilege('anon', 'public.consume_mechanic_job_inventory(uuid)', 'EXECUTE'),
  false,
  'anonymous clients cannot invoke the legacy job inventory writer'
);

select is(
  has_function_privilege('authenticated', 'public.restore_mechanic_job_inventory(uuid)', 'EXECUTE'),
  false,
  'authenticated clients cannot invoke the legacy job inventory restore writer'
);

select is(
  has_function_privilege('authenticated', 'public.create_mechanic_job_journal_entry(uuid)', 'EXECUTE'),
  false,
  'authenticated clients cannot invoke the legacy job revenue writer'
);

select is(
  has_function_privilege('service_role', 'public.consume_mechanic_job_inventory(uuid)', 'EXECUTE'),
  false,
  'service API clients cannot bypass the invoice-owned stock boundary'
);

select * from finish();
rollback;
