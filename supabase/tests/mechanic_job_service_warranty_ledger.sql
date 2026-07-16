begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(54);

select has_table(
  'public',
  'mechanic_job_delivery_events',
  'delivery events have a dedicated immutable ledger'
);
select has_trigger(
  'public',
  'mechanic_job_delivery_events',
  'trg_mechanic_job_delivery_events_immutable',
  'delivery events are append-only'
);
select has_table(
  'public',
  'mechanic_job_warranty_claim_events',
  'warranty decisions have a dedicated immutable ledger'
);
select has_view(
  'public',
  'mechanic_job_service_warranty_view',
  'service-warranty state is a derived read model'
);
select has_view(
  'public',
  'mechanic_job_warranty_claims_view',
  'warranty claim state is a derived read model'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.register_mechanic_job_warranty_claim(uuid,uuid,text)',
    'execute'
  ),
  'authenticated employees can register a warranty claim'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.register_mechanic_job_warranty_claim(uuid,uuid,text)',
    'execute'
  ),
  'anonymous callers cannot register a warranty claim'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.decide_mechanic_job_warranty_claim(uuid,text,text,text)',
    'execute'
  ),
  'authenticated employees can record a warranty decision'
);

insert into public.tenants(id, shop_name) values (
  '99773000-0000-4000-8000-000000000001',
  'Service Warranty Ledger Tenant'
);

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99773000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'service-warranty@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '99773000-0000-4000-8000-000000000001'
  ),
  now(),
  now()
);

insert into public.user_profiles(user_id, tenant_id, role) values (
  '99773000-0000-4000-8000-000000000099',
  '99773000-0000-4000-8000-000000000001',
  'admin'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99773000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99773000-0000-4000-8000-000000000099',
  true
);

insert into public.customers(id, tenant_id, name) values (
  '99773000-0000-4000-8000-000000000010',
  '99773000-0000-4000-8000-000000000001',
  'Service Warranty Customer'
);

insert into public.bikes(id, tenant_id, customer_id, brand, model) values (
  '99773000-0000-4000-8000-000000000020',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  'Codex',
  'Warranty Bike'
);

insert into public.products(
  id, tenant_id, name, sku, price, cost, inventory_qty, stock_quantity,
  is_service, product_type, track_stock
) values (
  '99773000-0000-4000-8000-000000000030',
  '99773000-0000-4000-8000-000000000001',
  'Warranty Replacement Part',
  'WARRANTY-PART',
  5000,
  1500,
  10,
  10,
  false,
  'product',
  true
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, job_number, job_type, status
) values (
  '99773000-0000-4000-8000-000000000040',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  '99773000-0000-4000-8000-000000000020',
  'WARRANTY-SOURCE',
  'service',
  'PENDIENTE'
);

update public.mechanic_jobs
set status = 'ENTREGADO'
where id = '99773000-0000-4000-8000-000000000040';

select is(
  (select count(*)::integer
   from public.mechanic_job_delivery_events
   where job_id = '99773000-0000-4000-8000-000000000040'),
  1,
  'the first delivered transition records exactly one server event'
);
select is(
  (select warranty_state
   from public.mechanic_job_service_warranty_view
   where job_id = '99773000-0000-4000-8000-000000000040'),
  'active',
  'the first delivery opens an active service-warranty window'
);
select ok(
  (select warranty_days_remaining between 13 and 14
   from public.mechanic_job_service_warranty_view
   where job_id = '99773000-0000-4000-8000-000000000040'),
  'the default service-warranty window is fourteen days'
);
select is(
  (select actor_id
   from public.mechanic_job_delivery_events
   where job_id = '99773000-0000-4000-8000-000000000040'),
  '99773000-0000-4000-8000-000000000099'::uuid,
  'delivery records the authenticated employee'
);
select ok(
  (select abs(extract(epoch from (recorded_at - occurred_at))) < 1
   from public.mechanic_job_delivery_events
   where job_id = '99773000-0000-4000-8000-000000000040'),
  'delivery occurrence and recording use the database clock'
);
select ok(
  (select status_updated_at is not null
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000040'),
  'status_updated_at is maintained for legacy status changes too'
);

create temporary table warranty_test_snapshot as
select warranty_event_id, warranty_expires_at
from public.mechanic_job_service_warranty_view
where job_id = '99773000-0000-4000-8000-000000000040';

update public.mechanic_jobs
set status = 'EN_CURSO'
where id = '99773000-0000-4000-8000-000000000040';

select is(
  (select delivered_at
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000040'),
  null::timestamptz,
  'reopening still clears the current-state delivered_at mirror'
);
select ok(
  (select first_delivered_at is not null
   from public.mechanic_job_service_warranty_view
   where job_id = '99773000-0000-4000-8000-000000000040'),
  'reopening does not erase the contractual delivery event'
);

update public.mechanic_jobs
set status = 'ENTREGADO'
where id = '99773000-0000-4000-8000-000000000040';

select is(
  (select delivery_count
   from public.mechanic_job_service_warranty_view
   where job_id = '99773000-0000-4000-8000-000000000040'),
  2,
  're-delivery appends a second delivery event'
);
select is(
  (select warranty_event_id
   from public.mechanic_job_service_warranty_view
   where job_id = '99773000-0000-4000-8000-000000000040'),
  (select warranty_event_id from warranty_test_snapshot),
  're-delivery does not silently reset the warranty window'
);
select is(
  (select warranty_expires_at
   from public.mechanic_job_service_warranty_view
   where job_id = '99773000-0000-4000-8000-000000000040'),
  (select warranty_expires_at from warranty_test_snapshot),
  're-delivery preserves the original expiry timestamp'
);
select throws_ok(
  $$update public.mechanic_job_delivery_events
    set reason = 'tamper'
    where job_id = '99773000-0000-4000-8000-000000000040'$$,
  '55000',
  'Delivery and service-warranty events are append-only',
  'delivery history cannot be edited'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, job_number, job_type,
  warranty_outcome, is_warranty_job, status
) values (
  '99773000-0000-4000-8000-000000000050',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  '99773000-0000-4000-8000-000000000020',
  'WARRANTY-CLAIM',
  'warranty',
  'pending',
  true,
  'PENDIENTE'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_id, product_name, item_type,
  quantity, unit_price
) values (
  '99773000-0000-4000-8000-000000000060',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000050',
  '99773000-0000-4000-8000-000000000030',
  'Warranty Replacement Part',
  'product',
  1,
  5000
);

select lives_ok(
  $$select public.register_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000050',
    '99773000-0000-4000-8000-000000000040',
    'test-register-warranty-claim'
  )$$,
  'a warranty claim links to its original delivered work'
);
select is(
  (select eligibility
   from public.mechanic_job_warranty_claims_view
   where warranty_job_id = '99773000-0000-4000-8000-000000000050'),
  'within_window',
  'claim eligibility is frozen when the claim is registered'
);
select is(
  (select source_job_id
   from public.mechanic_job_warranty_claims_view
   where warranty_job_id = '99773000-0000-4000-8000-000000000050'),
  '99773000-0000-4000-8000-000000000040'::uuid,
  'the claim projection keeps the original job link'
);
select lives_ok(
  $$select public.decide_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000050',
    'covered',
    null,
    'test-cover-warranty-claim'
  )$$,
  'an in-window warranty can be covered without an exception reason'
);
select ok(
  (select invoice_id is not null
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000050'),
  'covered warranty gets an internal linked invoice owner'
);
select is(
  (select total
   from public.sales_invoices
   where id = (select invoice_id from public.mechanic_jobs
               where id = '99773000-0000-4000-8000-000000000050')),
  0::numeric,
  'covered warranty creates no customer receivable'
);
select is(
  (select (items->0->>'warranty_reference_unit_price')::numeric
   from public.sales_invoices
   where id = (select invoice_id from public.mechanic_jobs
               where id = '99773000-0000-4000-8000-000000000050')),
  5000::numeric,
  'the internal invoice preserves the billable reference price'
);
select is(
  (select unit_price
   from public.mechanic_job_items
   where id = '99773000-0000-4000-8000-000000000060'),
  5000::numeric,
  'zeroing the internal document does not destroy the job reference price'
);
select is(
  (select iva_amount
   from public.sales_invoices
   where id = (select invoice_id from public.mechanic_jobs
               where id = '99773000-0000-4000-8000-000000000050')),
  0::numeric,
  'covered warranty produces no IVA'
);

update public.mechanic_jobs
set status = 'FINALIZADO'
where id = '99773000-0000-4000-8000-000000000050';

select is(
  (select status
   from public.sales_invoices
   where id = (select invoice_id from public.mechanic_jobs
               where id = '99773000-0000-4000-8000-000000000050')),
  'confirmed',
  'completing covered warranty posts its internal invoice owner'
);
select is(
  (select inventory_qty
   from public.products
   where id = '99773000-0000-4000-8000-000000000030'),
  9,
  'posting the internal warranty invoice consumes the replacement part once'
);
select is(
  (select stock_quantity
   from public.products
   where id = '99773000-0000-4000-8000-000000000030'),
  9,
  'both canonical stock mirrors remain equal'
);
select is(
  (select count(*)::integer
   from public.journal_entries entry
   join public.mechanic_jobs job
     on job.invoice_id = (select id from public.sales_invoices invoice
                          where invoice.invoice_number = entry.source_reference)
   where job.id = '99773000-0000-4000-8000-000000000050'
     and entry.source_module = 'sales_invoices'),
  1,
  'covered warranty creates one balanced cost journal'
);
select is(
  (select coalesce(sum(line.debit_amount), 0)
   from public.journal_lines line
   join public.journal_entries entry on entry.id = line.entry_id
   join public.sales_invoices invoice
     on invoice.invoice_number = entry.source_reference
   where invoice.id = (select invoice_id from public.mechanic_jobs
                       where id = '99773000-0000-4000-8000-000000000050')
     and line.account_code = '5115'),
  1500::numeric,
  'warranty expense is debited at catalog cost'
);
select is(
  (select count(*)::integer
   from public.journal_lines line
   join public.journal_entries entry on entry.id = line.entry_id
   join public.sales_invoices invoice
     on invoice.invoice_number = entry.source_reference
   where invoice.id = (select invoice_id from public.mechanic_jobs
                       where id = '99773000-0000-4000-8000-000000000050')
     and line.account_code in ('1130', '2150', '4100')),
  0,
  'covered warranty posts no receivable, IVA, or revenue lines'
);
select ok(
  (select movement.operation_id is not null
     and operation.outcome = 'completed'
   from public.stock_movements movement
   join public.inventory_accounting_operations operation
     on operation.id = movement.operation_id
    and operation.tenant_id = movement.tenant_id
   where movement.reference = 'sales_invoice:' || (
     select invoice_id::text
     from public.mechanic_jobs
     where id = '99773000-0000-4000-8000-000000000050'
   )
   order by movement.created_at desc
   limit 1),
  'covered warranty stock consumption belongs to a completed invoice trace'
);
select ok(
  (select entry.operation_id is not null
     and operation.outcome = 'completed'
   from public.journal_entries entry
   join public.inventory_accounting_operations operation
     on operation.id = entry.operation_id
    and operation.tenant_id = entry.tenant_id
   join public.sales_invoices invoice
     on invoice.invoice_number = entry.source_reference
    and invoice.tenant_id = entry.tenant_id
   where invoice.id = (select invoice_id from public.mechanic_jobs
                       where id = '99773000-0000-4000-8000-000000000050')
     and entry.source_module = 'sales_invoices'
   limit 1),
  'covered warranty cost journal belongs to the same completed trace kernel'
);
select is(
  (select count(*)::integer
   from public.inventory_accounting_operations operation
   where operation.tenant_id = '99773000-0000-4000-8000-000000000001'
     and operation.document_type = 'sales_invoice'
     and operation.document_id = (select invoice_id from public.mechanic_jobs
                                  where id = '99773000-0000-4000-8000-000000000050')
     and operation.outcome = 'started'),
  0,
  'nested warranty invoice lifecycle leaves no trace operation open'
);

update public.mechanic_jobs
set status = 'EN_CURSO'
where id = '99773000-0000-4000-8000-000000000050';

select is(
  (select status
   from public.sales_invoices
   where id = (select invoice_id from public.mechanic_jobs
               where id = '99773000-0000-4000-8000-000000000050')),
  'draft',
  'reopening covered work reverses the internal posting'
);
select is(
  (select inventory_qty
   from public.products
   where id = '99773000-0000-4000-8000-000000000030'),
  10,
  'reopening restores inventory through the invoice reversal path'
);
select is(
  (select count(*)::integer
   from public.journal_entries entry
   join public.sales_invoices invoice
     on invoice.invoice_number = entry.source_reference
   where invoice.id = (select invoice_id from public.mechanic_jobs
                       where id = '99773000-0000-4000-8000-000000000050')
     and entry.source_module = 'sales_invoices'),
  0,
  'reopening removes the current warranty-cost posting'
);

update public.mechanic_jobs
set status = 'FINALIZADO'
where id = '99773000-0000-4000-8000-000000000050';

select is(
  (select inventory_qty
   from public.products
   where id = '99773000-0000-4000-8000-000000000030'),
  9,
  'finalizing again reapplies exactly one inventory effect'
);
select throws_ok(
  $$select public.decide_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000050',
    'not_covered',
    null,
    'test-reject-without-reason'
  )$$,
  'P0001',
  'Rechazar una garantía requiere una justificación',
  'rejecting a warranty requires an auditable reason'
);
select lives_ok(
  $$select public.decide_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000050',
    'not_covered',
    'Daño externo no relacionado con la reparación original',
    'test-reject-warranty-claim'
  )$$,
  'a reasoned rejection reverses the internal coverage classification'
);
select is(
  (select warranty_outcome
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000050'),
  'not_covered',
  'the job mirror follows the audited claim decision'
);
select is(
  (select status
   from public.sales_invoices
   where id = (select invoice_id from public.mechanic_jobs
               where id = '99773000-0000-4000-8000-000000000050')),
  'draft',
  'a rejected warranty returns to the normal billable draft flow'
);
select is(
  (select total
   from public.sales_invoices
   where id = (select invoice_id from public.mechanic_jobs
               where id = '99773000-0000-4000-8000-000000000050')),
  5000::numeric,
  'a rejected warranty restores the customer price'
);
select is(
  (select inventory_qty
   from public.products
   where id = '99773000-0000-4000-8000-000000000030'),
  10,
  'changing to not covered reverses covered inventory before billing'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_warranty_claim_events
   where warranty_job_id = '99773000-0000-4000-8000-000000000050'
     and event_type = 'decision'),
  2,
  'coverage and rejection remain as separate immutable decisions'
);
select ok(
  (select count(*) >= 3
   from public.inventory_accounting_operations
   where document_id = '99773000-0000-4000-8000-000000000050'
     and outcome = 'completed'),
  'claim registration and both decisions have completed trace roots'
);
select throws_ok(
  $$select public.extend_mechanic_job_service_warranty(
    '99773000-0000-4000-8000-000000000040',
    clock_timestamp() + interval '30 days',
    null,
    'test-extension-without-reason'
  )$$,
  'P0001',
  'La extensión de garantía requiere una justificación',
  'manual warranty extensions require a reason'
);
select lives_ok(
  $$select public.extend_mechanic_job_service_warranty(
    '99773000-0000-4000-8000-000000000040',
    clock_timestamp() + interval '30 days',
    'Excepción comercial autorizada',
    'test-extension-with-reason'
  )$$,
  'a reasoned extension appends a new warranty window event'
);
select ok(
  (select warranty_expires_at > (select warranty_expires_at
                                 from warranty_test_snapshot)
   from public.mechanic_job_service_warranty_view
   where job_id = '99773000-0000-4000-8000-000000000040'),
  'the derived view uses the latest explicit extension'
);
select throws_ok(
  $$update public.mechanic_job_warranty_claim_events
    set reason = 'tamper'
    where warranty_job_id = '99773000-0000-4000-8000-000000000050'$$,
  '55000',
  'Delivery and service-warranty events are append-only',
  'claim decisions cannot be edited'
);

select * from finish();
rollback;
