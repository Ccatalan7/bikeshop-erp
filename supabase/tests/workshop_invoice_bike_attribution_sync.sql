begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(27);

select ok(
  to_regprocedure('public.sync_invoice_items_to_job(uuid)') is not null,
  'canonical invoice-to-job synchronization is installed'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.sync_invoice_items_to_job(uuid)',
    'execute'
  ),
  'authenticated workers can run the canonical synchronization'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.sync_invoice_items_to_job(uuid)',
    'execute'
  ),
  'anonymous callers cannot synchronize workshop invoices'
);
select ok(
  not has_function_privilege(
    'service_role',
    'public.sync_invoice_items_to_job(uuid)',
    'execute'
  ),
  'service role cannot bypass the employee tenant assertion'
);

insert into public.tenants(id, shop_name) values (
  '99616600-0000-4000-8000-000000000001',
  'Workshop Bike Attribution Tenant'
);

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99616600-0000-4000-8000-000000000099',
  'authenticated', 'authenticated',
  'workshop-bike-attribution@example.invalid', '', now(), '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', '99616600-0000-4000-8000-000000000001'
  ),
  now(), now()
);

insert into public.user_profiles(user_id, tenant_id, role) values (
  '99616600-0000-4000-8000-000000000099',
  '99616600-0000-4000-8000-000000000001',
  'admin'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99616600-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99616600-0000-4000-8000-000000000099',
  true
);

insert into public.customers(id, tenant_id, name) values (
  '99616600-0000-4000-8000-000000000011',
  '99616600-0000-4000-8000-000000000001',
  'Workshop Bike Attribution Customer'
);

insert into public.bikes(
  id, tenant_id, customer_id, brand, model, is_active
) values
  (
    '99616600-0000-4000-8000-000000000031',
    '99616600-0000-4000-8000-000000000001',
    '99616600-0000-4000-8000-000000000011',
    'Codex', 'Classification Bike', true
  ),
  (
    '99616600-0000-4000-8000-000000000032',
    '99616600-0000-4000-8000-000000000001',
    '99616600-0000-4000-8000-000000000011',
    'Codex', 'Other Job Bike', true
  );

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, status
) values (
  '99616600-0000-4000-8000-000000000061',
  '99616600-0000-4000-8000-000000000001',
  '99616600-0000-4000-8000-000000000011',
  'PG-ATTRIBUTION-MAIN', 'service', 'PENDIENTE'
);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, product_sku,
  item_type, quantity, unit_price, total_price, notes, description,
  location_key, creates_lifecycle
) values
  (
    '99616600-0000-4000-8000-000000000071',
    '99616600-0000-4000-8000-000000000001',
    '99616600-0000-4000-8000-000000000061',
    'Servicio estable A', 'ATTR-A', 'service', 1, 30000, 30000,
    'Diagnóstico A', 'Diagnóstico A', 'none', false
  ),
  (
    '99616600-0000-4000-8000-000000000072',
    '99616600-0000-4000-8000-000000000001',
    '99616600-0000-4000-8000-000000000061',
    'Servicio estable B', 'ATTR-B', 'service', 1, 20000, 20000,
    'Diagnóstico B', 'Diagnóstico B', 'none', false
  );

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_id, customer_name, source,
  status, subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
) values (
  '99616600-0000-4000-8000-000000000081',
  '99616600-0000-4000-8000-000000000001',
  'FV-ATTRIBUTION-MAIN',
  '99616600-0000-4000-8000-000000000011',
  'Workshop Bike Attribution Customer', 'mechanic_job', 'draft',
  50000, 50000, 0, 50000, 0, 50000, 'no_tax',
  jsonb_build_array(
    jsonb_build_object(
      'id', '99616600-0000-4000-8000-000000000071',
      'product_name', 'Servicio estable A',
      'product_sku', 'ATTR-A',
      'item_type', 'service',
      'is_service', true,
      'quantity', 1,
      'unit_price', 30000,
      'line_total', 30000,
      'description', 'Diagnóstico A'
    ),
    jsonb_build_object(
      'id', '99616600-0000-4000-8000-000000000072',
      'job_bike_id', null,
      'product_name', 'Servicio estable B',
      'product_sku', 'ATTR-B',
      'item_type', 'service',
      'is_service', true,
      'quantity', 1,
      'unit_price', 20000,
      'line_total', 20000,
      'description', 'Diagnóstico B'
    )
  )
);

update public.mechanic_jobs
set invoice_id = '99616600-0000-4000-8000-000000000081',
    is_invoiced = true
where id = '99616600-0000-4000-8000-000000000061';

create temporary table workshop_bike_attribution_baseline
on commit drop
as
select
  invoice.items,
  invoice.subtotal,
  invoice.net_amount,
  invoice.iva_amount,
  invoice.total,
  invoice.paid_amount,
  invoice.balance,
  (select count(*)::integer
     from public.sales_payments payment
    where payment.tenant_id = invoice.tenant_id) as payment_count,
  (select coalesce(sum(payment.amount), 0)::numeric
     from public.sales_payments payment
    where payment.tenant_id = invoice.tenant_id) as payment_total,
  (select count(*)::integer
     from public.stock_movements movement
    where movement.tenant_id = invoice.tenant_id) as stock_count,
  (select coalesce(sum(movement.quantity), 0)::numeric
     from public.stock_movements movement
    where movement.tenant_id = invoice.tenant_id) as stock_quantity,
  (select count(*)::integer
     from public.journal_entries entry
    where entry.tenant_id = invoice.tenant_id) as journal_count,
  (select coalesce(sum(entry.total_debit), 0)::numeric
     from public.journal_entries entry
    where entry.tenant_id = invoice.tenant_id) as journal_debit,
  (select coalesce(sum(entry.total_credit), 0)::numeric
     from public.journal_entries entry
    where entry.tenant_id = invoice.tenant_id) as journal_credit
from public.sales_invoices invoice
where invoice.id = '99616600-0000-4000-8000-000000000081';

select ok(
  (select mode_needs_review and intake_kind = 'unspecified'
     from public.mechanic_jobs
    where id = '99616600-0000-4000-8000-000000000061'),
  'linked historical job starts conservatively flagged for intake review'
);

select is(
  public.classify_mechanic_job_intake(
    '99616600-0000-4000-8000-000000000061', 'bike',
    '99616600-0000-4000-8000-000000000031', null, null,
    'Cliente confirmó la bicicleta completa.',
    '99616600-0000-4000-8000-000000000101'
  )->>'intake_kind',
  'bike',
  'facturado job can be classified as a complete bicycle without reposting'
);

select ok(
  (select intake_kind = 'bike'
      and job_type = 'service'
      and bike_id = '99616600-0000-4000-8000-000000000031'
      and not mode_needs_review
   from public.mechanic_jobs
   where id = '99616600-0000-4000-8000-000000000061'),
  'classification persists the reviewed job axes and primary bicycle'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_bikes
   where job_id = '99616600-0000-4000-8000-000000000061'),
  1,
  'classification creates exactly one canonical job-bike link'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_items item
   join public.mechanic_job_bikes job_bike on job_bike.id = item.job_bike_id
   where item.job_id = '99616600-0000-4000-8000-000000000061'
     and job_bike.job_id = item.job_id),
  2,
  'classification attributes both stable items to the received bicycle'
);
select ok(
  (select invoice.items = baseline.items
      and not (invoice.items->0 ? 'job_bike_id')
      and invoice.items->1->'job_bike_id' = 'null'::jsonb
   from public.sales_invoices invoice
   cross join workshop_bike_attribution_baseline baseline
   where invoice.id = '99616600-0000-4000-8000-000000000081'),
  'classification does not rewrite omitted or JSON-null invoice mirrors'
);
select is(
  (select count(*)::integer from public.sales_payments
   where tenant_id = '99616600-0000-4000-8000-000000000001'),
  (select payment_count from workshop_bike_attribution_baseline),
  'classification does not create or remove payments'
);
select is(
  (select count(*)::integer from public.stock_movements
   where tenant_id = '99616600-0000-4000-8000-000000000001'),
  (select stock_count from workshop_bike_attribution_baseline),
  'classification does not post inventory'
);
select is(
  (select count(*)::integer from public.journal_entries
   where tenant_id = '99616600-0000-4000-8000-000000000001'),
  (select journal_count from workshop_bike_attribution_baseline),
  'classification does not post accounting'
);

select lives_ok(
  $$select public.sync_invoice_items_to_job(
    '99616600-0000-4000-8000-000000000081'
  )$$,
  'invoice-to-job synchronization accepts omitted bicycle mirrors'
);
select is(
  (select count(*)::integer
   from public.mechanic_job_items item
   join public.mechanic_job_bikes job_bike on job_bike.id = item.job_bike_id
   where item.job_id = '99616600-0000-4000-8000-000000000061'
     and job_bike.job_id = item.job_id),
  2,
  'subsequent invoice synchronization preserves both item attributions'
);
select ok(
  (select (invoice.subtotal, invoice.net_amount, invoice.iva_amount,
           invoice.total, invoice.paid_amount, invoice.balance)
       is not distinct from
      (baseline.subtotal, baseline.net_amount, baseline.iva_amount,
       baseline.total, baseline.paid_amount, baseline.balance)
   from public.sales_invoices invoice
   cross join workshop_bike_attribution_baseline baseline
   where invoice.id = '99616600-0000-4000-8000-000000000081'),
  'synchronization leaves every invoice financial total unchanged'
);
select ok(
  (select invoice.items = baseline.items
   from public.sales_invoices invoice
   cross join workshop_bike_attribution_baseline baseline
   where invoice.id = '99616600-0000-4000-8000-000000000081'),
  'synchronization leaves invoice line JSON unchanged'
);
select ok(
  (select count(payment.id) = baseline.payment_count
      and coalesce(sum(payment.amount), 0) = baseline.payment_total
   from workshop_bike_attribution_baseline baseline
   left join public.sales_payments payment
     on payment.tenant_id = '99616600-0000-4000-8000-000000000001'
   group by baseline.payment_count, baseline.payment_total),
  'synchronization leaves payment count and amount unchanged'
);
select ok(
  (select count(movement.id) = baseline.stock_count
      and coalesce(sum(movement.quantity), 0) = baseline.stock_quantity
   from workshop_bike_attribution_baseline baseline
   left join public.stock_movements movement
     on movement.tenant_id = '99616600-0000-4000-8000-000000000001'
   group by baseline.stock_count, baseline.stock_quantity),
  'synchronization leaves stock count and quantity unchanged'
);
select ok(
  (select count(entry.id) = baseline.journal_count
      and coalesce(sum(entry.total_debit), 0) = baseline.journal_debit
      and coalesce(sum(entry.total_credit), 0) = baseline.journal_credit
   from workshop_bike_attribution_baseline baseline
   left join public.journal_entries entry
     on entry.tenant_id = '99616600-0000-4000-8000-000000000001'
   group by baseline.journal_count, baseline.journal_debit,
            baseline.journal_credit),
  'synchronization leaves journal count and balance unchanged'
);
select ok(
  (select parts_cost = 0 and labor_cost = 50000 and subtotal = 50000
   from public.mechanic_job_bikes
   where job_id = '99616600-0000-4000-8000-000000000061'),
  'preserved attribution also reconciles the bicycle operational rollup'
);

-- A different job provides a real same-tenant job-bike UUID. It must never be
-- accepted by an invoice linked to another workshop job.
insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, bike_id, status
) values (
  '99616600-0000-4000-8000-000000000062',
  '99616600-0000-4000-8000-000000000001',
  '99616600-0000-4000-8000-000000000011',
  'PG-ATTRIBUTION-OTHER', 'service',
  '99616600-0000-4000-8000-000000000032', 'PENDIENTE'
);
insert into public.mechanic_job_bikes(
  id, tenant_id, job_id, bike_id, order_index
) values (
  '99616600-0000-4000-8000-000000000091',
  '99616600-0000-4000-8000-000000000001',
  '99616600-0000-4000-8000-000000000062',
  '99616600-0000-4000-8000-000000000032', 0
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, job_number, job_type, status
) values
  (
    '99616600-0000-4000-8000-000000000063',
    '99616600-0000-4000-8000-000000000001',
    '99616600-0000-4000-8000-000000000011',
    'PG-ATTRIBUTION-INVALID', 'service', 'PENDIENTE'
  ),
  (
    '99616600-0000-4000-8000-000000000064',
    '99616600-0000-4000-8000-000000000001',
    '99616600-0000-4000-8000-000000000011',
    'PG-ATTRIBUTION-CROSS', 'service', 'PENDIENTE'
  );

insert into public.mechanic_job_items(
  id, tenant_id, job_id, product_name, product_sku,
  item_type, quantity, unit_price, total_price, location_key
) values
  (
    '99616600-0000-4000-8000-000000000073',
    '99616600-0000-4000-8000-000000000001',
    '99616600-0000-4000-8000-000000000063',
    'Servicio inválido', 'ATTR-INVALID', 'service', 1, 10000, 10000, 'none'
  ),
  (
    '99616600-0000-4000-8000-000000000074',
    '99616600-0000-4000-8000-000000000001',
    '99616600-0000-4000-8000-000000000064',
    'Servicio cruzado', 'ATTR-CROSS', 'service', 1, 10000, 10000, 'none'
  );

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_id, customer_name, source,
  status, subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
) values
  (
    '99616600-0000-4000-8000-000000000083',
    '99616600-0000-4000-8000-000000000001', 'FV-ATTRIBUTION-INVALID',
    '99616600-0000-4000-8000-000000000011',
    'Workshop Bike Attribution Customer', 'mechanic_job', 'draft',
    10000, 10000, 0, 10000, 0, 10000, 'no_tax',
    jsonb_build_array(jsonb_build_object(
      'id', '99616600-0000-4000-8000-000000000073',
      'job_bike_id', 'not-a-uuid',
      'product_name', 'Servicio inválido',
      'product_sku', 'ATTR-INVALID',
      'item_type', 'service',
      'quantity', 1, 'unit_price', 10000, 'line_total', 10000
    ))
  ),
  (
    '99616600-0000-4000-8000-000000000084',
    '99616600-0000-4000-8000-000000000001', 'FV-ATTRIBUTION-CROSS',
    '99616600-0000-4000-8000-000000000011',
    'Workshop Bike Attribution Customer', 'mechanic_job', 'draft',
    10000, 10000, 0, 10000, 0, 10000, 'no_tax',
    jsonb_build_array(jsonb_build_object(
      'id', '99616600-0000-4000-8000-000000000074',
      'job_bike_id', '99616600-0000-4000-8000-000000000091',
      'product_name', 'Servicio cruzado',
      'product_sku', 'ATTR-CROSS',
      'item_type', 'service',
      'quantity', 1, 'unit_price', 10000, 'line_total', 10000
    ))
  );

update public.mechanic_jobs
set invoice_id = case id
      when '99616600-0000-4000-8000-000000000063'::uuid
        then '99616600-0000-4000-8000-000000000083'::uuid
      else '99616600-0000-4000-8000-000000000084'::uuid
    end,
    is_invoiced = true
where id in (
  '99616600-0000-4000-8000-000000000063',
  '99616600-0000-4000-8000-000000000064'
);

select throws_ok(
  $$select public.sync_invoice_items_to_job(
    '99616600-0000-4000-8000-000000000083'
  )$$,
  '23514',
  'Invoice line job_bike_id must reference a bicycle linked to this workshop job.',
  'malformed explicit job_bike_id aborts synchronization'
);
select ok(
  (select job_bike_id is null and total_price = 10000
   from public.mechanic_job_items
   where id = '99616600-0000-4000-8000-000000000073'),
  'malformed attribution leaves the stable workshop item unchanged'
);
select is(
  (select items->0->>'job_bike_id' from public.sales_invoices
   where id = '99616600-0000-4000-8000-000000000083'),
  'not-a-uuid',
  'malformed attribution failure leaves the invoice evidence untouched'
);

select throws_ok(
  $$select public.sync_invoice_items_to_job(
    '99616600-0000-4000-8000-000000000084'
  )$$,
  '23514',
  'Invoice line job_bike_id must reference a bicycle linked to this workshop job.',
  'same-tenant job_bike_id from another job aborts synchronization'
);
select ok(
  (select job_bike_id is null and total_price = 10000
   from public.mechanic_job_items
   where id = '99616600-0000-4000-8000-000000000074'),
  'cross-job attribution leaves the stable workshop item unchanged'
);
select is(
  (select items->0->>'job_bike_id' from public.sales_invoices
   where id = '99616600-0000-4000-8000-000000000084'),
  '99616600-0000-4000-8000-000000000091',
  'cross-job attribution failure leaves the invoice evidence untouched'
);

select * from finish();
rollback;
