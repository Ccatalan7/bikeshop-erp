begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(156);

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
select has_trigger(
  'public',
  'sales_invoices',
  'trg_sales_invoice_00_workshop_payment_snapshot_guard',
  'atomic payment command validates the workshop snapshot before invoice update'
);
select has_trigger(
  'public',
  'sales_payments',
  'trg_sales_payments_00_workshop_snapshot_guard',
  'legacy and direct payment inserts validate the workshop snapshot'
);
select has_trigger(
  'public',
  'mechanic_job_items',
  'trg_mechanic_job_items_guard_paid_snapshot',
  'paid workshop item rows are server-protected'
);
select has_trigger(
  'public',
  'mechanic_job_bikes',
  'trg_mechanic_job_bikes_guard_paid_snapshot',
  'paid workshop physical bicycle rows are server-protected'
);
select has_trigger(
  'public',
  'mechanic_jobs',
  'trg_mechanic_jobs_guard_invoice_link_identity',
  'database-owned invoice linkage ignores stale full-row mirrors'
);
select ok(
  position(
    'old.status is not distinct from new.status'
    in pg_get_functiondef(
      'public.sync_covered_warranty_invoice_lifecycle()'::regprocedure
    )
  ) > 0
  and position(
    'old.status is not distinct from new.status'
    in pg_get_functiondef(
      'public.sync_covered_warranty_invoice_lifecycle()'::regprocedure
    )
  ) < position(
    'if new.job_type'
    in pg_get_functiondef(
      'public.sync_covered_warranty_invoice_lifecycle()'::regprocedure
    )
  ),
  'covered-warranty lifecycle exits before finance when status values did not change'
);
select ok(
  exists (
    select 1
    from pg_proc procedure
    cross join lateral unnest(procedure.proconfig) setting
    where procedure.oid =
      'public.sync_covered_warranty_invoice_lifecycle()'::regprocedure
      and setting = 'lock_timeout=750ms'
  )
  and position(
    'from public.sales_payments payment'
    in pg_get_functiondef(
      'public.sync_covered_warranty_invoice_lifecycle()'::regprocedure
    )
  ) < position(
    'update public.sales_invoices invoice'
    in pg_get_functiondef(
      'public.sync_covered_warranty_invoice_lifecycle()'::regprocedure
    )
  )
  and position(
    'v_invoice_id := coalesce(old.invoice_id, new.invoice_id)'
    in pg_get_functiondef(
      'public.sync_covered_warranty_invoice_lifecycle()'::regprocedure
    )
  ) > 0,
  'covered-warranty status finance is payment-guarded with a bounded lock wait'
);
select ok(
  position(
    $$set_config('app.syncing_job_to_invoice', 'true', true)$$
    in pg_get_functiondef('public.sync_job_to_invoice(uuid)'::regprocedure)
  ) > 0
  and position(
    $$set_config('app.syncing_job_to_invoice', '', true)$$
    in pg_get_functiondef('public.sync_job_to_invoice(uuid)'::regprocedure)
  ) > position(
    $$set_config('app.syncing_job_to_invoice', 'true', true)$$
    in pg_get_functiondef('public.sync_job_to_invoice(uuid)'::regprocedure)
  ),
  'job-to-invoice projection owns and clears its circular-sync flag explicitly'
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
  exists (
    select 1
    from pg_proc procedure
    cross join lateral unnest(procedure.proconfig) setting
    where procedure.oid =
      'public.register_mechanic_job_warranty_claim(uuid,uuid,text)'::regprocedure
      and setting = 'lock_timeout=750ms'
  ),
  'warranty registration retains the bounded 750ms business-traffic lock timeout'
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
select ok(
  exists (
    select 1
    from pg_proc procedure
    cross join lateral unnest(procedure.proconfig) setting
    where procedure.oid =
      'public.decide_mechanic_job_warranty_claim(uuid,text,text,text)'::regprocedure
      and setting = 'lock_timeout=750ms'
  ),
  'warranty decisions retain the bounded 750ms business-traffic lock timeout'
);
select ok(
  position(
    'from public.sales_invoices invoice'
    in pg_get_functiondef(
      'public.decide_mechanic_job_warranty_claim(uuid,text,text,text)'::regprocedure
    )
  ) > 0
  and position(
    'for update;'
    in pg_get_functiondef(
      'public.decide_mechanic_job_warranty_claim(uuid,text,text,text)'::regprocedure
    )
  ) > position(
    'from public.sales_invoices invoice'
    in pg_get_functiondef(
      'public.decide_mechanic_job_warranty_claim(uuid,text,text,text)'::regprocedure
    )
  )
  and position(
    'for update;'
    in pg_get_functiondef(
      'public.decide_mechanic_job_warranty_claim(uuid,text,text,text)'::regprocedure
    )
  ) < position(
    'select job.* into v_job'
    in pg_get_functiondef(
      'public.decide_mechanic_job_warranty_claim(uuid,text,text,text)'::regprocedure
    )
  ),
  'warranty decisions lock the invoice before locking the linked job'
);
select ok(
  position(
    'from public.sales_payments payment'
    in pg_get_functiondef(
      'public.decide_mechanic_job_warranty_claim(uuid,text,text,text)'::regprocedure
    )
  ) > position(
    'select job.* into v_job'
    in pg_get_functiondef(
      'public.decide_mechanic_job_warranty_claim(uuid,text,text,text)'::regprocedure
    )
  )
  and position(
    'v_job.invoice_id is distinct from v_preflight_invoice_id'
    in pg_get_functiondef(
      'public.decide_mechanic_job_warranty_claim(uuid,text,text,text)'::regprocedure
    )
  ) > position(
    'select job.* into v_job'
    in pg_get_functiondef(
      'public.decide_mechanic_job_warranty_claim(uuid,text,text,text)'::regprocedure
    )
  ),
  'payment inspection follows invoice/job locks and financial-link revalidation'
);
select ok(
  exists (
    select 1
    from pg_proc procedure
    cross join lateral unnest(procedure.proconfig) setting
    where procedure.oid = 'public.sync_job_to_invoice(uuid)'::regprocedure
      and setting = 'lock_timeout=750ms'
  )
  and position(
    'from public.sales_invoices invoice'
    in pg_get_functiondef('public.sync_job_to_invoice(uuid)'::regprocedure)
  ) > 0
  and position(
    'from public.sales_invoices invoice'
    in pg_get_functiondef('public.sync_job_to_invoice(uuid)'::regprocedure)
  ) < position(
    'select job.* into v_job'
    in pg_get_functiondef('public.sync_job_to_invoice(uuid)'::regprocedure)
  )
  and position(
    'v_job.invoice_id is distinct from v_preflight_invoice_id'
    in pg_get_functiondef('public.sync_job_to_invoice(uuid)'::regprocedure)
  ) > position(
    'select job.* into v_job'
    in pg_get_functiondef('public.sync_job_to_invoice(uuid)'::regprocedure)
  )
  and position(
    'from public.sales_payments payment'
    in pg_get_functiondef('public.sync_job_to_invoice(uuid)'::regprocedure)
  ) > position(
    'select job.* into v_job'
    in pg_get_functiondef('public.sync_job_to_invoice(uuid)'::regprocedure)
  ),
  'direct job sync locks invoice before job and protects financial history'
);
select ok(
  exists (
    select 1
    from pg_proc procedure
    cross join lateral unnest(procedure.proconfig) setting
    where procedure.oid =
      'public.create_billable_invoice_from_mechanic_job(uuid)'::regprocedure
      and setting = 'lock_timeout=750ms'
  )
  and position(
    'from public.sales_invoices invoice'
    in pg_get_functiondef(
      'public.create_billable_invoice_from_mechanic_job(uuid)'::regprocedure
    )
  ) > 0
  and position(
    'from public.sales_invoices invoice'
    in pg_get_functiondef(
      'public.create_billable_invoice_from_mechanic_job(uuid)'::regprocedure
    )
  ) < position(
    'select job.* into v_job'
    in pg_get_functiondef(
      'public.create_billable_invoice_from_mechanic_job(uuid)'::regprocedure
    )
  )
  and position(
    'v_job.invoice_id is distinct from v_preflight_invoice_id'
    in pg_get_functiondef(
      'public.create_billable_invoice_from_mechanic_job(uuid)'::regprocedure
    )
  ) > position(
    'select job.* into v_job'
    in pg_get_functiondef(
      'public.create_billable_invoice_from_mechanic_job(uuid)'::regprocedure
    )
  ),
  'existing-invoice retry locks invoice before job and revalidates the link'
);

insert into public.tenants(id, shop_name) values
  (
    '99773000-0000-4000-8000-000000000001',
    'Service Warranty Ledger Tenant'
  ),
  (
    '99773100-0000-4000-8000-000000000001',
    'Service Warranty Tenant Scope Decoy'
  );

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Invoice numbers are tenant-local. Keep a second FV-00001 in the fixture so
-- every journal/invoice correlation below proves tenant scoping even though
-- pgTAP runs as postgres and bypasses RLS.
insert into public.customers(id, tenant_id, name) values (
  '99773100-0000-4000-8000-000000000010',
  '99773100-0000-4000-8000-000000000001',
  'Tenant Scope Decoy Customer'
);

insert into public.sales_invoices (
  id,
  tenant_id,
  invoice_number,
  customer_id,
  customer_name,
  source,
  status,
  subtotal,
  net_amount,
  iva_amount,
  total,
  paid_amount,
  balance,
  tax_treatment,
  items
) values (
  '99773100-0000-4000-8000-000000000020',
  '99773100-0000-4000-8000-000000000001',
  'FV-00001',
  '99773100-0000-4000-8000-000000000010',
  'Tenant Scope Decoy Customer',
  'manual_sale',
  'draft',
  0, 0, 0, 0, 0, 0,
  'no_tax',
  '[]'::jsonb
);

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

create temporary table warranty_registration_financial_snapshot as
select
  coalesce((
    select jsonb_agg(to_jsonb(invoice) order by invoice.id)
    from public.sales_invoices invoice
    where invoice.tenant_id = '99773000-0000-4000-8000-000000000001'
  ), '[]'::jsonb) as invoice_rows,
  coalesce((
    select jsonb_agg(to_jsonb(payment) order by payment.id)
    from public.sales_payments payment
    where payment.tenant_id = '99773000-0000-4000-8000-000000000001'
  ), '[]'::jsonb) as payment_rows,
  jsonb_build_object(
    'products', coalesce((
      select jsonb_agg(to_jsonb(product) order by product.id)
      from public.products product
      where product.tenant_id = '99773000-0000-4000-8000-000000000001'
    ), '[]'::jsonb),
    'movements', coalesce((
      select jsonb_agg(to_jsonb(movement) order by movement.id)
      from public.stock_movements movement
      where movement.tenant_id = '99773000-0000-4000-8000-000000000001'
    ), '[]'::jsonb)
  ) as inventory_rows,
  jsonb_build_object(
    'entries', coalesce((
      select jsonb_agg(to_jsonb(entry) order by entry.id)
      from public.journal_entries entry
      where entry.tenant_id = '99773000-0000-4000-8000-000000000001'
    ), '[]'::jsonb),
    'lines', coalesce((
      select jsonb_agg(to_jsonb(line) order by line.id)
      from public.journal_lines line
      join public.journal_entries entry on entry.id = line.entry_id
      where entry.tenant_id = '99773000-0000-4000-8000-000000000001'
    ), '[]'::jsonb)
  ) as accounting_rows;

select lives_ok(
  $$select public.register_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000050',
    '99773000-0000-4000-8000-000000000040',
    'test-register-warranty-claim'
  )$$,
  'a warranty claim links to its original delivered work'
);
select is(
  coalesce((select jsonb_agg(to_jsonb(invoice) order by invoice.id)
            from public.sales_invoices invoice
            where invoice.tenant_id = '99773000-0000-4000-8000-000000000001'),
           '[]'::jsonb),
  (select invoice_rows from warranty_registration_financial_snapshot),
  'claim registration preserves the exact invoice rows before a coverage decision'
);
select is(
  coalesce((select jsonb_agg(to_jsonb(payment) order by payment.id)
            from public.sales_payments payment
            where payment.tenant_id = '99773000-0000-4000-8000-000000000001'),
           '[]'::jsonb),
  (select payment_rows from warranty_registration_financial_snapshot),
  'claim registration preserves the exact payment rows'
);
select is(
  jsonb_build_object(
    'products', coalesce((select jsonb_agg(to_jsonb(product) order by product.id)
                          from public.products product
                          where product.tenant_id = '99773000-0000-4000-8000-000000000001'),
                         '[]'::jsonb),
    'movements', coalesce((select jsonb_agg(to_jsonb(movement) order by movement.id)
                           from public.stock_movements movement
                           where movement.tenant_id = '99773000-0000-4000-8000-000000000001'),
                          '[]'::jsonb)
  ),
  (select inventory_rows from warranty_registration_financial_snapshot),
  'claim registration preserves exact product and stock-movement rows'
);
select is(
  jsonb_build_object(
    'entries', coalesce((select jsonb_agg(to_jsonb(entry) order by entry.id)
                         from public.journal_entries entry
                         where entry.tenant_id = '99773000-0000-4000-8000-000000000001'),
                        '[]'::jsonb),
    'lines', coalesce((select jsonb_agg(to_jsonb(line) order by line.id)
                       from public.journal_lines line
                       join public.journal_entries entry on entry.id = line.entry_id
                       where entry.tenant_id = '99773000-0000-4000-8000-000000000001'),
                      '[]'::jsonb)
  ),
  (select accounting_rows from warranty_registration_financial_snapshot),
  'claim registration preserves exact journal entry and line rows'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_bikes
   where job_id = '99773000-0000-4000-8000-000000000050'
     and bike_id = '99773000-0000-4000-8000-000000000020'),
  1,
  'bike claim registration owns exactly one canonical job-bike row'
);
select is(
  (public.register_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000050',
    '99773000-0000-4000-8000-000000000040',
    'test-register-warranty-claim'
  )->>'replay')::boolean,
  true,
  'the exact registration operation key replays its immutable receipt'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_warranty_claim_events
   where warranty_job_id = '99773000-0000-4000-8000-000000000050'
     and event_type = 'registration'),
  1,
  'an exact registration replay appends no duplicate event'
);

create temporary table warranty_existing_registration_receipt as
select public.register_mechanic_job_warranty_claim(
  '99773000-0000-4000-8000-000000000050',
  '99773000-0000-4000-8000-000000000040',
  'test-register-warranty-claim-new-key'
) as receipt;

select is(
  (select (receipt->>'invariant_already_satisfied')::boolean
   from warranty_existing_registration_receipt),
  true,
  'a new key recognizes an already-satisfied registration invariant'
);
select is(
  (select receipt->>'request_operation_key'
   from warranty_existing_registration_receipt),
  'test-register-warranty-claim-new-key',
  'the reconstructed receipt identifies the new request key'
);
select is(
  (select receipt->>'canonical_operation_key'
   from warranty_existing_registration_receipt),
  'test-register-warranty-claim',
  'the reconstructed receipt preserves the canonical immutable event key'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_warranty_claim_events
   where warranty_job_id = '99773000-0000-4000-8000-000000000050'
     and event_type = 'registration'),
  1,
  'a new key for an existing registration appends no duplicate event'
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
select is(
  (public.decide_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000050',
    'covered',
    null,
    'test-cover-warranty-claim'
  )->>'replay')::boolean,
  true,
  'the exact decision operation key replays its immutable receipt'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_warranty_claim_events
   where warranty_job_id = '99773000-0000-4000-8000-000000000050'
     and event_type = 'decision'),
  1,
  'an exact decision replay appends no duplicate event'
);
select throws_ok(
  $$select public.decide_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000050',
    'not_covered',
    'Payload distinto para la misma clave',
    'test-cover-warranty-claim'
  )$$,
  '23505',
  'La clave de operación ya pertenece a otra decisión de garantía',
  'a decision key cannot be reused for another outcome'
);
select throws_ok(
  $$select public.decide_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000050',
    'covered',
    'Motivo distinto para la misma clave',
    'test-cover-warranty-claim'
  )$$,
  '23505',
  'La clave de operación ya pertenece a otra decisión de garantía',
  'a decision key cannot be reused with another normalized reason'
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
                          where invoice.invoice_number = entry.source_reference
                            and invoice.tenant_id = entry.tenant_id)
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
    and invoice.tenant_id = entry.tenant_id
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
    and invoice.tenant_id = entry.tenant_id
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
select is(
  nullif(
    current_setting(
      'app.covered_warranty_nested_invoice_trace_marker',
      true
    ),
    ''
  ),
  null::text,
  'covered warranty lifecycle clears its exact nested-trace marker'
);

create temporary table completed_covered_warranty_snapshot as
select
  (select to_jsonb(invoice)
   from public.sales_invoices invoice
   where invoice.id = job.invoice_id) as invoice_row,
  jsonb_build_object(
    'products', coalesce((
      select jsonb_agg(to_jsonb(product) order by product.id)
      from public.products product
      where product.tenant_id = job.tenant_id
    ), '[]'::jsonb),
    'movements', coalesce((
      select jsonb_agg(to_jsonb(movement) order by movement.id)
      from public.stock_movements movement
      where movement.tenant_id = job.tenant_id
    ), '[]'::jsonb)
  ) as inventory_rows,
  jsonb_build_object(
    'entries', coalesce((
      select jsonb_agg(to_jsonb(entry) order by entry.id)
      from public.journal_entries entry
      where entry.tenant_id = job.tenant_id
    ), '[]'::jsonb),
    'lines', coalesce((
      select jsonb_agg(to_jsonb(line) order by line.id)
      from public.journal_lines line
      join public.journal_entries entry on entry.id = line.entry_id
      where entry.tenant_id = job.tenant_id
    ), '[]'::jsonb)
  ) as accounting_rows
from public.mechanic_jobs job
where job.id = '99773000-0000-4000-8000-000000000050';

update public.mechanic_jobs
set diagnosis = 'Diagnóstico actualizado sin transición',
    status = status,
    status_id = status_id
where id = '99773000-0000-4000-8000-000000000050';

select is(
  (select diagnosis
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000050'),
  'Diagnóstico actualizado sin transición',
  'diagnosis-only save persists while explicitly retaining lifecycle columns'
);
select is(
  (select to_jsonb(invoice)
   from public.sales_invoices invoice
   where invoice.id = (
     select invoice_id
     from public.mechanic_jobs
     where id = '99773000-0000-4000-8000-000000000050'
   )),
  (select invoice_row from completed_covered_warranty_snapshot),
  'diagnosis-only save preserves the exact completed warranty invoice row'
);
select is(
  jsonb_build_object(
    'products', coalesce((select jsonb_agg(to_jsonb(product) order by product.id)
                          from public.products product
                          where product.tenant_id = '99773000-0000-4000-8000-000000000001'),
                         '[]'::jsonb),
    'movements', coalesce((select jsonb_agg(to_jsonb(movement) order by movement.id)
                           from public.stock_movements movement
                           where movement.tenant_id = '99773000-0000-4000-8000-000000000001'),
                          '[]'::jsonb)
  ),
  (select inventory_rows from completed_covered_warranty_snapshot),
  'diagnosis-only save preserves exact completed warranty stock rows'
);
select is(
  jsonb_build_object(
    'entries', coalesce((select jsonb_agg(to_jsonb(entry) order by entry.id)
                         from public.journal_entries entry
                         where entry.tenant_id = '99773000-0000-4000-8000-000000000001'),
                        '[]'::jsonb),
    'lines', coalesce((select jsonb_agg(to_jsonb(line) order by line.id)
                       from public.journal_lines line
                       join public.journal_entries entry on entry.id = line.entry_id
                       where entry.tenant_id = '99773000-0000-4000-8000-000000000001'),
                      '[]'::jsonb)
  ),
  (select accounting_rows from completed_covered_warranty_snapshot),
  'diagnosis-only save preserves exact completed warranty journal rows'
);

update public.mechanic_jobs
set status = 'EN_CURSO',
    invoice_id = null,
    is_invoiced = false,
    is_paid = false
where id = '99773000-0000-4000-8000-000000000050';

select is(
  (select status
   from public.sales_invoices
   where id = (select invoice_id from public.mechanic_jobs
               where id = '99773000-0000-4000-8000-000000000050')),
  'draft',
  'an unpaid stale full-row status payload preserves the link and reverses the internal posting'
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
    and invoice.tenant_id = entry.tenant_id
   where invoice.id = (select invoice_id from public.mechanic_jobs
                       where id = '99773000-0000-4000-8000-000000000050')
     and entry.source_module = 'sales_invoices'),
  0,
  'reopening removes the current warranty-cost posting'
);

update public.mechanic_jobs
set status = 'FINALIZADO',
    invoice_id = null,
    is_invoiced = false,
    is_paid = false
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

select lives_ok(
  $$update public.mechanic_jobs
    set invoice_id = null,
        is_invoiced = false,
        is_paid = false
    where id = '99773000-0000-4000-8000-000000000050'$$,
  'a stale full-row client payload is normalized without unlinking finance'
);
select ok(
  (select invoice_id is not null and is_invoiced and not is_paid
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000050'),
  'invoice identity remains database-owned before settlement'
);

update public.sales_invoices
set status = 'confirmed'
where id = (
  select invoice_id
  from public.mechanic_jobs
  where id = '99773000-0000-4000-8000-000000000050'
);

update public.mechanic_job_items
set unit_price = 4000,
    total_price = 4000
where id = '99773000-0000-4000-8000-000000000060';

select throws_ok(
  $$insert into public.sales_payments(
      id, tenant_id, invoice_id, payment_method_id, amount,
      idempotency_key, reference, date
    )
    select
      '99773000-0000-4000-8000-000000000090',
      job.tenant_id,
      job.invoice_id,
      payment_method.id,
      4000,
      'stale-workshop-payment-rejected',
      'stale-workshop-payment-rejected',
      now()
    from public.mechanic_jobs job
    cross join lateral (
      select method.id
      from public.payment_methods method
      where method.tenant_id = job.tenant_id
      order by method.created_at, method.id
      limit 1
    ) payment_method
    where job.id = '99773000-0000-4000-8000-000000000050'$$,
  '40001',
  'El trabajo cambió mientras se preparaba el pago. Guarda o recarga el trabajo y vuelve a cobrar; no se registró ningún pago.',
  'payment rejects a stale workshop line projection before settlement'
);
select is(
  (select count(*)::integer
   from public.sales_payments
   where id = '99773000-0000-4000-8000-000000000090'),
  0,
  'stale workshop rejection leaves no payment row'
);

update public.mechanic_job_items
set unit_price = 5000,
    total_price = 5000
where id = '99773000-0000-4000-8000-000000000060';

select is(
  public.workshop_job_commercial_snapshot(
    '99773000-0000-4000-8000-000000000050'
  ),
  public.workshop_invoice_commercial_snapshot((
    select invoice_id
    from public.mechanic_jobs
    where id = '99773000-0000-4000-8000-000000000050'
  )),
  'restoring the draft line restores exact payment-ready workshop projection'
);

select throws_ok(
  $statement$
  do $block$
  declare
    v_job public.mechanic_jobs%rowtype;
    v_method_id uuid;
  begin
    update public.mechanic_job_items
    set job_bike_id = (
      select job_bike.id
      from public.mechanic_job_bikes job_bike
      where job_bike.job_id = '99773000-0000-4000-8000-000000000050'
      order by job_bike.id
      limit 1
    )
    where id = '99773000-0000-4000-8000-000000000060';
    perform public.sync_job_to_invoice(
      '99773000-0000-4000-8000-000000000050'
    );

    delete from public.mechanic_job_bikes
    where job_id = '99773000-0000-4000-8000-000000000050';

    select job.* into v_job
    from public.mechanic_jobs job
    where job.id = '99773000-0000-4000-8000-000000000050';
    select method.id into v_method_id
    from public.payment_methods method
    where method.tenant_id = v_job.tenant_id
    order by method.created_at, method.id
    limit 1;

    insert into public.sales_payments(
      id, tenant_id, invoice_id, payment_method_id, amount,
      idempotency_key, reference, date
    ) values (
      '99773000-0000-4000-8000-000000000090',
      v_job.tenant_id,
      v_job.invoice_id,
      v_method_id,
      5000,
      'stale-workshop-bike-payment-rejected',
      'stale-workshop-bike-payment-rejected',
      now()
    );
  end;
  $block$;
  $statement$,
  '40001',
  'El trabajo cambió mientras se preparaba el pago. Guarda o recarga el trabajo y vuelve a cobrar; no se registró ningún pago.',
  'payment rejects a raced physical-bike deletion and rolls the statement back'
);
select ok(
  (select count(*) = 1
   from public.mechanic_job_bikes
   where job_id = '99773000-0000-4000-8000-000000000050')
  and
  (select count(*) = 1
   from public.mechanic_job_items
   where job_id = '99773000-0000-4000-8000-000000000050'),
  'rejected raced payment preserves the exact physical job aggregate'
);

insert into public.sales_payments(
  id, tenant_id, invoice_id, payment_method_id, amount,
  tax_treatment, net_amount, iva_amount, idempotency_key, reference, date
)
select
  '99773000-0000-4000-8000-000000000091',
  '99773000-0000-4000-8000-000000000001',
  job.invoice_id,
  payment_method.id,
  5000,
  'no_tax',
  5000,
  0,
  'warranty-paid-financial-review',
  'warranty-paid-financial-review',
  now()
from public.mechanic_jobs job
cross join lateral (
  select id
  from public.payment_methods
  where tenant_id = job.tenant_id
  order by created_at, id
  limit 1
) payment_method
where job.id = '99773000-0000-4000-8000-000000000050';

select lives_ok(
  $$update public.mechanic_jobs
    set invoice_id = null,
        is_invoiced = false,
        is_paid = false
    where id = '99773000-0000-4000-8000-000000000050'$$,
  'a stale post-payment full-row payload is normalized without unlinking finance'
);
select ok(
  (select invoice_id is not null and is_invoiced and is_paid
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000050'),
  'paid and invoice identity mirrors remain invoice-owned after settlement'
);

create temporary table paid_warranty_financial_snapshot as
select
  (select to_jsonb(invoice)
   from public.sales_invoices invoice
   where invoice.id = job.invoice_id) as invoice_row,
  coalesce((
    select jsonb_agg(to_jsonb(payment) order by payment.id)
    from public.sales_payments payment
    where payment.tenant_id = job.tenant_id
  ), '[]'::jsonb) as payment_rows,
  jsonb_build_object(
    'products', coalesce((
      select jsonb_agg(to_jsonb(product) order by product.id)
      from public.products product
      where product.tenant_id = job.tenant_id
    ), '[]'::jsonb),
    'movements', coalesce((
      select jsonb_agg(to_jsonb(movement) order by movement.id)
      from public.stock_movements movement
      where movement.tenant_id = job.tenant_id
    ), '[]'::jsonb)
  ) as inventory_rows,
  jsonb_build_object(
    'entries', coalesce((
      select jsonb_agg(to_jsonb(entry) order by entry.id)
      from public.journal_entries entry
      where entry.tenant_id = job.tenant_id
    ), '[]'::jsonb),
    'lines', coalesce((
      select jsonb_agg(to_jsonb(line) order by line.id)
      from public.journal_lines line
      join public.journal_entries entry on entry.id = line.entry_id
      where entry.tenant_id = job.tenant_id
    ), '[]'::jsonb)
  ) as accounting_rows
from public.mechanic_jobs job
where job.id = '99773000-0000-4000-8000-000000000050';

select throws_ok(
  $$update public.mechanic_job_items
    set unit_price = 4000,
        total_price = 4000
    where id = '99773000-0000-4000-8000-000000000060'$$,
  '55000',
  'La factura del trabajo ya tiene pagos. Productos, precios y bicicleta recibida quedan protegidos; el diagnóstico sí puede seguir editándose.',
  'paid workshop item prices reject external mutation atomically'
);
select throws_ok(
  $$update public.mechanic_jobs
    set discount_amount = 1000
    where id = '99773000-0000-4000-8000-000000000050'$$,
  '55000',
  'La factura del trabajo ya tiene pagos. Cliente, modalidad, objeto recibido y descuento quedan protegidos.',
  'paid workshop discount rejects external mutation atomically'
);
select throws_ok(
  $$delete from public.mechanic_job_bikes
    where job_id = '99773000-0000-4000-8000-000000000050'$$,
  '55000',
  'La factura del trabajo ya tiene pagos. Productos, precios y bicicleta recibida quedan protegidos; el diagnóstico sí puede seguir editándose.',
  'paid workshop physical bicycle rejects deletion atomically'
);

-- Simulate drift written before this guard existed. Only the internal
-- invoice-owned reconciliation context may bypass the paid mutation guard.
select set_config('app.syncing_invoice_to_job', 'true', true);
update public.mechanic_job_items
set unit_price = 4000,
    total_price = 4000
where id = '99773000-0000-4000-8000-000000000060';
update public.mechanic_jobs
set discount_amount = 1000
where id = '99773000-0000-4000-8000-000000000050';
select set_config('app.syncing_invoice_to_job', '', true);

select lives_ok(
  $$select public.sync_job_to_invoice(
    '99773000-0000-4000-8000-000000000050'
  )$$,
  'settled workshop sync is a commercial no-op without rewriting legacy mirrors or finance'
);
select is(
  current_setting('app.syncing_invoice_to_job', true),
  '',
  'settled workshop reconciliation always clears its invoice-to-job sync flag'
);
select is(
  (select to_jsonb(invoice)
   from public.sales_invoices invoice
   where invoice.id = (
     select invoice_id
     from public.mechanic_jobs
     where id = '99773000-0000-4000-8000-000000000050'
   )),
  (select invoice_row from paid_warranty_financial_snapshot),
  'generic workshop sync preserves the exact paid invoice row'
);
select is(
  coalesce((select jsonb_agg(to_jsonb(payment) order by payment.id)
            from public.sales_payments payment
            where payment.tenant_id = '99773000-0000-4000-8000-000000000001'),
           '[]'::jsonb),
  (select payment_rows from paid_warranty_financial_snapshot),
  'generic workshop sync preserves the exact payment rows'
);
select is(
  jsonb_build_object(
    'products', coalesce((select jsonb_agg(to_jsonb(product) order by product.id)
                          from public.products product
                          where product.tenant_id = '99773000-0000-4000-8000-000000000001'),
                         '[]'::jsonb),
    'movements', coalesce((select jsonb_agg(to_jsonb(movement) order by movement.id)
                           from public.stock_movements movement
                           where movement.tenant_id = '99773000-0000-4000-8000-000000000001'),
                          '[]'::jsonb)
  ),
  (select inventory_rows from paid_warranty_financial_snapshot),
  'generic workshop sync preserves exact paid product and movement rows'
);
select is(
  jsonb_build_object(
    'entries', coalesce((select jsonb_agg(to_jsonb(entry) order by entry.id)
                         from public.journal_entries entry
                         where entry.tenant_id = '99773000-0000-4000-8000-000000000001'),
                        '[]'::jsonb),
    'lines', coalesce((select jsonb_agg(to_jsonb(line) order by line.id)
                       from public.journal_lines line
                       join public.journal_entries entry on entry.id = line.entry_id
                       where entry.tenant_id = '99773000-0000-4000-8000-000000000001'),
                      '[]'::jsonb)
  ),
  (select accounting_rows from paid_warranty_financial_snapshot),
  'generic workshop sync preserves exact paid journal entry and line rows'
);
select ok(
  (select unit_price = 4000 and total_price = 4000
   from public.mechanic_job_items
   where id = '99773000-0000-4000-8000-000000000060'),
  'settled workshop sync preserves legacy job line differences byte-for-byte'
);
select is(
  (select discount_amount
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000050'),
  1000::numeric,
  'settled workshop sync preserves the legacy job discount without backfill'
);

create temporary table paid_covered_status_snapshot as
select status
from public.mechanic_jobs
where id = '99773000-0000-4000-8000-000000000050';

select set_config('app.warranty_claim_rpc', 'true', true);
update public.mechanic_jobs
set warranty_outcome = 'covered'
where id = '99773000-0000-4000-8000-000000000050';
select set_config('app.warranty_claim_rpc', '', true);

select throws_ok(
  $$update public.mechanic_jobs
    set status = 'EN_CURSO',
        invoice_id = null,
        is_invoiced = false,
        is_paid = false
    where id = '99773000-0000-4000-8000-000000000050'$$,
  '55000',
  'La garantía cubierta tiene evidencia de pago. Su estado y efectos contables no pueden cambiar sin una corrección financiera auditada.',
  'paid stale full-row covered-warranty transition fails closed before finance'
);
select is(
  (select status
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000050'),
  (select status from paid_covered_status_snapshot),
  'failed paid covered-warranty transition preserves the job status'
);
select is(
  (select to_jsonb(invoice)
   from public.sales_invoices invoice
   where invoice.id = (
     select invoice_id
     from public.mechanic_jobs
     where id = '99773000-0000-4000-8000-000000000050'
   )),
  (select invoice_row from paid_warranty_financial_snapshot),
  'failed paid covered-warranty transition preserves the exact invoice row'
);
select is(
  coalesce((select jsonb_agg(to_jsonb(payment) order by payment.id)
            from public.sales_payments payment
            where payment.tenant_id = '99773000-0000-4000-8000-000000000001'),
           '[]'::jsonb),
  (select payment_rows from paid_warranty_financial_snapshot),
  'failed paid covered-warranty transition preserves exact payment rows'
);
select is(
  jsonb_build_object(
    'products', coalesce((select jsonb_agg(to_jsonb(product) order by product.id)
                          from public.products product
                          where product.tenant_id = '99773000-0000-4000-8000-000000000001'),
                         '[]'::jsonb),
    'movements', coalesce((select jsonb_agg(to_jsonb(movement) order by movement.id)
                           from public.stock_movements movement
                           where movement.tenant_id = '99773000-0000-4000-8000-000000000001'),
                          '[]'::jsonb)
  ),
  (select inventory_rows from paid_warranty_financial_snapshot),
  'failed paid covered-warranty transition preserves exact stock rows'
);
select is(
  jsonb_build_object(
    'entries', coalesce((select jsonb_agg(to_jsonb(entry) order by entry.id)
                         from public.journal_entries entry
                         where entry.tenant_id = '99773000-0000-4000-8000-000000000001'),
                        '[]'::jsonb),
    'lines', coalesce((select jsonb_agg(to_jsonb(line) order by line.id)
                       from public.journal_lines line
                       join public.journal_entries entry on entry.id = line.entry_id
                       where entry.tenant_id = '99773000-0000-4000-8000-000000000001'),
                      '[]'::jsonb)
  ),
  (select accounting_rows from paid_warranty_financial_snapshot),
  'failed paid covered-warranty transition preserves exact journal rows'
);

select set_config('app.warranty_claim_rpc', 'true', true);
update public.mechanic_jobs
set warranty_outcome = 'not_covered'
where id = '99773000-0000-4000-8000-000000000050';
select set_config('app.warranty_claim_rpc', '', true);

select throws_ok(
  $$select public.decide_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000050',
    'covered',
    'Reintento cubierto después de un pago',
    'test-reject-covered-with-payment'
  )$$,
  'P0001',
  'No se puede marcar como cubierta una garantía con pagos vigentes; primero revierte o reembolsa el pago desde la factura',
  'a paid billable warranty cannot silently become covered'
);
select is(
  (select warranty_outcome
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000050'),
  'not_covered',
  'a rejected paid transition preserves the confirmed warranty outcome'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_warranty_claim_events
   where warranty_job_id = '99773000-0000-4000-8000-000000000050'
     and event_type = 'decision'),
  2,
  'a rejected paid transition appends no decision receipt'
);

create temporary table legacy_financial_history_guard_snapshot as
select jsonb_build_object(
  'job_outcome', job.warranty_outcome,
  'invoice', to_jsonb(invoice),
  'payments', coalesce((
    select jsonb_agg(to_jsonb(payment) order by payment.id)
    from public.sales_payments payment
    where payment.invoice_id = invoice.id
  ), '[]'::jsonb),
  'events', coalesce((
    select jsonb_agg(to_jsonb(event) order by event.id)
    from public.mechanic_job_warranty_claim_events event
    where event.warranty_job_id = job.id
  ), '[]'::jsonb),
  'products', coalesce((
    select jsonb_agg(to_jsonb(product) order by product.id)
    from public.products product
    where product.tenant_id = job.tenant_id
  ), '[]'::jsonb),
  'movements', coalesce((
    select jsonb_agg(to_jsonb(movement) order by movement.id)
    from public.stock_movements movement
    where movement.tenant_id = job.tenant_id
  ), '[]'::jsonb),
  'entries', coalesce((
    select jsonb_agg(to_jsonb(entry) order by entry.id)
    from public.journal_entries entry
    where entry.tenant_id = job.tenant_id
  ), '[]'::jsonb),
  'lines', coalesce((
    select jsonb_agg(to_jsonb(line) order by line.id)
    from public.journal_lines line
    join public.journal_entries entry on entry.id = line.entry_id
    where entry.tenant_id = job.tenant_id
  ), '[]'::jsonb)
) as exact_rows
from public.mechanic_jobs job
join public.sales_invoices invoice on invoice.id = job.invoice_id
where job.id = '99773000-0000-4000-8000-000000000050';

select throws_ok(
  $statement$
  do $block$
  declare v_invoice_id uuid;
  begin
    select invoice_id into v_invoice_id from public.mechanic_jobs
    where id = '99773000-0000-4000-8000-000000000050';
    update public.sales_payments set deleted_at = clock_timestamp()
    where invoice_id = v_invoice_id and deleted_at is null;
    perform set_config('app.syncing_job_to_invoice', 'true', true);
    update public.sales_invoices set status = 'paid', paid_amount = 0
    where id = v_invoice_id;
    perform set_config('app.syncing_job_to_invoice', '', true);
    perform public.decide_mechanic_job_warranty_claim(
      '99773000-0000-4000-8000-000000000050',
      'covered', 'Legacy status mirror', 'legacy-paid-status-cover-reject'
    );
  end;
  $block$;
  $statement$,
  'P0001',
  'No se puede marcar como cubierta una garantía con pagos vigentes; primero revierte o reembolsa el pago desde la factura',
  'invoice paid status alone blocks entering covered warranty'
);

select throws_ok(
  $statement$
  do $block$
  declare v_invoice_id uuid;
  begin
    select invoice_id into v_invoice_id from public.mechanic_jobs
    where id = '99773000-0000-4000-8000-000000000050';
    update public.sales_payments set deleted_at = clock_timestamp()
    where invoice_id = v_invoice_id and deleted_at is null;
    perform set_config('app.syncing_job_to_invoice', 'true', true);
    update public.sales_invoices set status = 'confirmed', paid_amount = 1
    where id = v_invoice_id;
    perform set_config('app.syncing_job_to_invoice', '', true);
    perform public.decide_mechanic_job_warranty_claim(
      '99773000-0000-4000-8000-000000000050',
      'covered', 'Legacy paid amount mirror', 'legacy-paid-amount-cover-reject'
    );
  end;
  $block$;
  $statement$,
  'P0001',
  'No se puede marcar como cubierta una garantía con pagos vigentes; primero revierte o reembolsa el pago desde la factura',
  'invoice paid_amount alone blocks entering covered warranty'
);

select throws_ok(
  $statement$
  do $block$
  declare v_invoice_id uuid;
  begin
    select invoice_id into v_invoice_id from public.mechanic_jobs
    where id = '99773000-0000-4000-8000-000000000050';
    update public.sales_payments set deleted_at = clock_timestamp()
    where invoice_id = v_invoice_id and deleted_at is null;
    perform set_config('app.syncing_job_to_invoice', 'true', true);
    update public.sales_invoices set status = 'paid', paid_amount = 0
    where id = v_invoice_id;
    perform set_config('app.syncing_job_to_invoice', '', true);
    perform set_config('app.warranty_claim_rpc', 'true', true);
    update public.mechanic_jobs set warranty_outcome = 'covered'
    where id = '99773000-0000-4000-8000-000000000050';
    perform set_config('app.warranty_claim_rpc', '', true);
    perform public.decide_mechanic_job_warranty_claim(
      '99773000-0000-4000-8000-000000000050',
      'not_covered', 'Legacy paid coverage correction',
      'legacy-paid-status-uncover-reject'
    );
  end;
  $block$;
  $statement$,
  'P0001',
  'No se puede retirar la cobertura de una garantía con historial financiero; primero corrige el documento desde la factura',
  'invoice paid status alone blocks leaving covered warranty'
);

select is(
  (select jsonb_build_object(
    'job_outcome', job.warranty_outcome,
    'invoice', to_jsonb(invoice),
    'payments', coalesce((select jsonb_agg(to_jsonb(payment) order by payment.id)
                          from public.sales_payments payment
                          where payment.invoice_id = invoice.id), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(to_jsonb(event) order by event.id)
                        from public.mechanic_job_warranty_claim_events event
                        where event.warranty_job_id = job.id), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(to_jsonb(product) order by product.id)
                          from public.products product
                          where product.tenant_id = job.tenant_id), '[]'::jsonb),
    'movements', coalesce((select jsonb_agg(to_jsonb(movement) order by movement.id)
                           from public.stock_movements movement
                           where movement.tenant_id = job.tenant_id), '[]'::jsonb),
    'entries', coalesce((select jsonb_agg(to_jsonb(entry) order by entry.id)
                         from public.journal_entries entry
                         where entry.tenant_id = job.tenant_id), '[]'::jsonb),
    'lines', coalesce((select jsonb_agg(to_jsonb(line) order by line.id)
                       from public.journal_lines line
                       join public.journal_entries entry on entry.id = line.entry_id
                       where entry.tenant_id = job.tenant_id), '[]'::jsonb)
  )
  from public.mechanic_jobs job
  join public.sales_invoices invoice on invoice.id = job.invoice_id
  where job.id = '99773000-0000-4000-8000-000000000050'),
  (select exact_rows from legacy_financial_history_guard_snapshot),
  'legacy financial-history rejections preserve exact job, invoice, payment, inventory, journal and event rows'
);
select lives_ok(
  $$select public.decide_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000050',
    'not_covered',
    'Factura ya pagada; se conserva el documento financiero',
    'test-confirm-paid-not-covered'
  )$$,
  'a paid historical warranty can record not-covered without rewriting finance'
);
select is(
  (select to_jsonb(invoice)
   from public.sales_invoices invoice
   where invoice.id = (
     select invoice_id
     from public.mechanic_jobs
     where id = '99773000-0000-4000-8000-000000000050'
   )),
  (select invoice_row from paid_warranty_financial_snapshot),
  'paid not-covered decision preserves the exact invoice row'
);
select is(
  coalesce((select jsonb_agg(to_jsonb(payment) order by payment.id)
            from public.sales_payments payment
            where payment.tenant_id = '99773000-0000-4000-8000-000000000001'),
           '[]'::jsonb),
  (select payment_rows from paid_warranty_financial_snapshot),
  'paid not-covered decision preserves the exact payment rows'
);
select is(
  jsonb_build_object(
    'products', coalesce((select jsonb_agg(to_jsonb(product) order by product.id)
                          from public.products product
                          where product.tenant_id = '99773000-0000-4000-8000-000000000001'),
                         '[]'::jsonb),
    'movements', coalesce((select jsonb_agg(to_jsonb(movement) order by movement.id)
                           from public.stock_movements movement
                           where movement.tenant_id = '99773000-0000-4000-8000-000000000001'),
                          '[]'::jsonb)
  ),
  (select inventory_rows from paid_warranty_financial_snapshot),
  'paid not-covered decision preserves exact product and stock-movement rows'
);
select is(
  jsonb_build_object(
    'entries', coalesce((select jsonb_agg(to_jsonb(entry) order by entry.id)
                         from public.journal_entries entry
                         where entry.tenant_id = '99773000-0000-4000-8000-000000000001'),
                        '[]'::jsonb),
    'lines', coalesce((select jsonb_agg(to_jsonb(line) order by line.id)
                       from public.journal_lines line
                       join public.journal_entries entry on entry.id = line.entry_id
                       where entry.tenant_id = '99773000-0000-4000-8000-000000000001'),
                      '[]'::jsonb)
  ),
  (select accounting_rows from paid_warranty_financial_snapshot),
  'paid not-covered decision preserves exact journal entry and line rows'
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

select is(
  (select intake_kind
   from public.mechanic_job_service_warranty_view
   where job_id = '99773000-0000-4000-8000-000000000040'),
  'bike',
  'the warranty source view exposes the canonical bicycle intake'
);
select is(
  (select mode_needs_review
   from public.mechanic_job_service_warranty_view
   where job_id = '99773000-0000-4000-8000-000000000040'),
  false,
  'the warranty source view exposes classification review state'
);

insert into public.job_subjects(
  id, tenant_id, name, category
) values (
  '99773000-0000-4000-8000-000000000071',
  '99773000-0000-4000-8000-000000000001',
  'Warranty loose wheel',
  'Ruedas'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, subject_id, subject_notes,
  job_number, job_type, workflow_kind, intake_kind, status
) values (
  '99773000-0000-4000-8000-000000000070',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  '99773000-0000-4000-8000-000000000020',
  '99773000-0000-4000-8000-000000000071',
  'Rueda trasera dejada sin la bicicleta completa',
  'WARRANTY-COMPONENT-SOURCE',
  'item_service',
  'service',
  'component',
  'PENDIENTE'
);

update public.mechanic_jobs
set status = 'ENTREGADO'
where id = '99773000-0000-4000-8000-000000000070';

select is(
  (select intake_kind
   from public.mechanic_job_service_warranty_view
   where job_id = '99773000-0000-4000-8000-000000000070'),
  'component',
  'component intake wins over a related bicycle provenance id'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, subject_id, subject_notes, job_number,
  job_type, workflow_kind, intake_kind, status
) values (
  '99773000-0000-4000-8000-000000000072',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  '99773000-0000-4000-8000-000000000071',
  'Rueda trasera dejada sin la bicicleta completa',
  'WARRANTY-COMPONENT-CLAIM',
  'warranty',
  'warranty',
  'component',
  'PENDIENTE'
);

select lives_ok(
  $$select public.register_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000072',
    '99773000-0000-4000-8000-000000000070',
    'test-register-component-warranty'
  )$$,
  'a component warranty inherits the source through the canonical intake axis'
);
select is(
  (select intake_kind
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000072'),
  'component',
  'the warranty claim keeps component custody'
);
select is(
  (select bike_id
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000072'),
  null::uuid,
  'component provenance never becomes bicycle custody on the claim'
);
select is(
  (select subject_id
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000072'),
  '99773000-0000-4000-8000-000000000071'::uuid,
  'the claim inherits the exact component subject'
);
select throws_ok(
  $$select public.decide_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000072',
    'covered',
    null,
    'test-cover-warranty-claim'
  )$$,
  '23505',
  'La clave de operación ya pertenece a otra decisión de garantía',
  'a decision key cannot be reused for another warranty job'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, subject_notes, job_number,
  job_type, workflow_kind, intake_kind, status
) values (
  '99773000-0000-4000-8000-000000000075',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  'Rueda delantera tubular dejada sin bicicleta',
  'WARRANTY-NOTES-ONLY-SOURCE',
  'item_service',
  'service',
  'component',
  'PENDIENTE'
);

update public.mechanic_jobs
set status = 'ENTREGADO'
where id = '99773000-0000-4000-8000-000000000075';

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, subject_notes, job_number,
  job_type, workflow_kind, intake_kind, status
) values (
  '99773000-0000-4000-8000-000000000076',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  'Rueda delantera tubular dejada sin bicicleta',
  'WARRANTY-NOTES-ONLY-CLAIM',
  'warranty',
  'warranty',
  'component',
  'PENDIENTE'
);

select lives_ok(
  $$select public.register_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000076',
    '99773000-0000-4000-8000-000000000075',
    'test-register-notes-only-component'
  )$$,
  'a notes-only loose component can be registered without inventing a catalog subject'
);
select is(
  (select intake_kind
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000076'),
  'component',
  'notes-only component claim keeps component custody'
);
select is(
  (select bike_id
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000076'),
  null::uuid,
  'notes-only component claim has no bicycle custody'
);
select is(
  (select subject_id
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000076'),
  null::uuid,
  'notes-only component claim does not invent a catalog subject'
);
select is(
  (select subject_notes
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000076'),
  'Rueda delantera tubular dejada sin bicicleta',
  'notes-only component claim inherits the exact description'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_bikes
   where job_id = '99773000-0000-4000-8000-000000000076'),
  0,
  'notes-only component registration creates no fictitious job-bike row'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, workflow_kind,
  intake_kind, mode_needs_review, mode_review_reason, status
) values (
  '99773000-0000-4000-8000-000000000077',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  'WARRANTY-REVIEW-SOURCE',
  'service',
  'service',
  'unspecified',
  true,
  'test: recepción no resuelta',
  'PENDIENTE'
);

update public.mechanic_jobs
set status = 'ENTREGADO'
where id = '99773000-0000-4000-8000-000000000077';

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, subject_notes, job_number,
  job_type, workflow_kind, intake_kind, status
) values (
  '99773000-0000-4000-8000-000000000078',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  'Componente temporal para validar rechazo',
  'WARRANTY-REVIEW-CLAIM',
  'warranty',
  'warranty',
  'component',
  'PENDIENTE'
);

select throws_ok(
  $$select public.register_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000078',
    '99773000-0000-4000-8000-000000000077',
    'test-reject-review-source'
  )$$,
  'P0001',
  'Clasifica primero el trabajo original como bicicleta o componente',
  'a source pending intake review cannot become a warranty anchor'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_warranty_claim_events
   where operation_key = 'test-reject-review-source'),
  0,
  'review-source rejection leaves no registration event'
);

insert into public.bikes(id, tenant_id, customer_id, brand, model) values (
  '99773000-0000-4000-8000-000000000021',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  'Codex',
  'Different Warranty Bike'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, job_number,
  job_type, workflow_kind, intake_kind, status
) values (
  '99773000-0000-4000-8000-000000000079',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  '99773000-0000-4000-8000-000000000020',
  'WARRANTY-MISMATCH-JOB-BIKE',
  'warranty',
  'warranty',
  'bike',
  'PENDIENTE'
);

insert into public.mechanic_job_bikes(
  tenant_id, job_id, bike_id, order_index, is_warranty_work
) values (
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000079',
  '99773000-0000-4000-8000-000000000021',
  0,
  true
);

select throws_ok(
  $$select public.register_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000079',
    '99773000-0000-4000-8000-000000000040',
    'test-reject-mismatched-job-bike'
  )$$,
  'P0001',
  'La ficha de garantía contiene una bicicleta distinta al trabajo original',
  'registration rejects a different aggregate job-bike row'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_bikes
   where job_id = '99773000-0000-4000-8000-000000000079'
     and bike_id = '99773000-0000-4000-8000-000000000021'),
  1,
  'mismatch rejection does not touch the pre-existing different row'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_bikes
   where job_id = '99773000-0000-4000-8000-000000000079'
     and bike_id = '99773000-0000-4000-8000-000000000020'),
  0,
  'mismatch rejection does not append the canonical row beside stale state'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_warranty_claim_events
   where operation_key = 'test-reject-mismatched-job-bike'),
  0,
  'mismatch rejection leaves no registration event'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, job_number, job_type, workflow_kind,
  intake_kind, is_warranty_job, warranty_outcome, status
) values (
  '99773000-0000-4000-8000-000000000080',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  '99773000-0000-4000-8000-000000000020',
  'WARRANTY-ROLLBACK-CLAIM',
  'warranty',
  'warranty',
  'bike',
  false,
  'pending',
  'PENDIENTE'
);

create function pg_temp.fail_test_warranty_trace()
returns trigger
language plpgsql
as $$
begin
  raise exception 'forced warranty trace failure';
end;
$$;

create trigger trg_test_fail_warranty_trace
before insert on public.inventory_accounting_operations
for each row
when (new.operation_key = 'service_warranty:test-register-rollback')
execute function pg_temp.fail_test_warranty_trace();

select throws_ok(
  $$select public.register_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000080',
    '99773000-0000-4000-8000-000000000040',
    'test-register-rollback'
  )$$,
  'P0001',
  'forced warranty trace failure',
  'a late trace failure aborts the complete registration transaction'
);

drop trigger trg_test_fail_warranty_trace
  on public.inventory_accounting_operations;

select is(
  (select count(*)::integer
   from public.mechanic_job_warranty_claim_events
   where operation_key = 'test-register-rollback'),
  0,
  'late failure rolls back the immutable registration event'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_bikes
   where job_id = '99773000-0000-4000-8000-000000000080'),
  0,
  'late failure rolls back the canonical job-bike upsert'
);
select is(
  (select count(*)::integer
   from public.inventory_accounting_operations
   where operation_key = 'service_warranty:test-register-rollback'),
  0,
  'late failure leaves no trace root'
);
select is(
  (select is_warranty_job
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000080'),
  false,
  'late failure rolls back the job mirror update'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, subject_id, subject_notes, job_number,
  job_type, workflow_kind, intake_kind, status
) values (
  '99773000-0000-4000-8000-000000000073',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  '99773000-0000-4000-8000-000000000020',
  '99773000-0000-4000-8000-000000000071',
  'Rueda trasera dejada sin la bicicleta completa',
  'WARRANTY-STALE-BIKE',
  'warranty',
  'warranty',
  'component',
  'PENDIENTE'
);

select throws_ok(
  $$select public.register_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000073',
    '99773000-0000-4000-8000-000000000070',
    'test-reject-stale-warranty-bike'
  )$$,
  'P0001',
  'Una garantía de componente no puede recibir una bicicleta completa',
  'the server rejects stale bicycle state on a component warranty'
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, subject_id, subject_notes, job_number,
  job_type, workflow_kind, intake_kind, status
) values (
  '99773000-0000-4000-8000-000000000074',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000010',
  '99773000-0000-4000-8000-000000000071',
  'Rueda trasera dejada sin la bicicleta completa',
  'WARRANTY-KEY-COLLISION',
  'warranty',
  'warranty',
  'component',
  'PENDIENTE'
);

select throws_ok(
  $$select public.register_mechanic_job_warranty_claim(
    '99773000-0000-4000-8000-000000000074',
    '99773000-0000-4000-8000-000000000070',
    'test-register-component-warranty'
  )$$,
  '23505',
  'La clave de operación ya pertenece a otra acción de garantía',
  'a registration replay key cannot be reused for another claim'
);

update public.mechanic_jobs
set workflow_kind = 'service',
    intake_kind = 'bike',
    mode_needs_review = false
where id = '99773000-0000-4000-8000-000000000040';

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_id, product_name, item_type,
  quantity, unit_price
) values (
  '99773000-0000-4000-8000-000000000093',
  '99773000-0000-4000-8000-000000000001',
  '99773000-0000-4000-8000-000000000040',
  '99773000-0000-4000-8000-000000000030',
  'Paid Service Status Regression Part',
  'product',
  1,
  1000
);

select public.create_billable_invoice_from_mechanic_job(
  '99773000-0000-4000-8000-000000000040'
);
update public.sales_invoices
set status = 'confirmed'
where id = (
  select invoice_id
  from public.mechanic_jobs
  where id = '99773000-0000-4000-8000-000000000040'
);
insert into public.sales_payments(
  id, tenant_id, invoice_id, payment_method_id, amount,
  idempotency_key, reference, date
)
select
  '99773000-0000-4000-8000-000000000094',
  job.tenant_id,
  job.invoice_id,
  payment_method.id,
  1000,
  'paid-service-status-regression',
  'paid-service-status-regression',
  now()
from public.mechanic_jobs job
cross join lateral (
  select method.id
  from public.payment_methods method
  where method.tenant_id = job.tenant_id
  order by method.created_at, method.id
  limit 1
) payment_method
where job.id = '99773000-0000-4000-8000-000000000040';

create temporary table paid_service_status_snapshot as
select jsonb_build_object(
  'invoice', to_jsonb(invoice),
  'payments', coalesce((
    select jsonb_agg(to_jsonb(payment) order by payment.id)
    from public.sales_payments payment
    where payment.invoice_id = invoice.id
      and payment.deleted_at is null
  ), '[]'::jsonb)
) as finance_rows
from public.sales_invoices invoice
where invoice.id = (
  select invoice_id
  from public.mechanic_jobs
  where id = '99773000-0000-4000-8000-000000000040'
);

select lives_ok(
  $$update public.mechanic_jobs
    set status = 'EN_CURSO'
    where id = '99773000-0000-4000-8000-000000000040'$$,
  'normal paid service keeps its operational status editable'
);
select is(
  (select status
   from public.mechanic_jobs
   where id = '99773000-0000-4000-8000-000000000040'),
  'EN_CURSO',
  'normal paid service status transition persists'
);
select is(
  (select jsonb_build_object(
    'invoice', to_jsonb(invoice),
    'payments', coalesce((
      select jsonb_agg(to_jsonb(payment) order by payment.id)
      from public.sales_payments payment
      where payment.invoice_id = invoice.id
        and payment.deleted_at is null
    ), '[]'::jsonb)
  )
  from public.sales_invoices invoice
  where invoice.id = (
    select invoice_id
    from public.mechanic_jobs
    where id = '99773000-0000-4000-8000-000000000040'
  )),
  (select finance_rows from paid_service_status_snapshot),
  'normal paid service status transition leaves invoice and payment exact'
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
