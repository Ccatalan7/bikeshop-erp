begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(18);

select has_table(
  'public',
  'workshop_tenant_graph_backfill_audit',
  'tenant graph repair keeps immutable row evidence'
);
select has_trigger(
  'public',
  'workshop_tenant_graph_backfill_audit',
  'trg_workshop_tenant_graph_backfill_audit_immutable',
  'tenant graph repair evidence is immutable'
);
select has_function(
  'public',
  'validate_workshop_tenant_graph',
  array[]::text[],
  'workshop tenant graph validator exists'
);
select has_trigger(
  'public',
  'mechanic_jobs',
  'trg_mechanic_jobs_tenant_graph',
  'mechanic jobs enforce the tenant graph'
);
select has_trigger(
  'public',
  'mechanic_job_bikes',
  'trg_mechanic_job_bikes_tenant_graph',
  'job bicycles enforce the tenant graph'
);
select has_trigger(
  'public',
  'mechanic_job_items',
  'trg_mechanic_job_items_tenant_graph',
  'job items enforce the tenant graph'
);

insert into public.tenants(id, shop_name) values
  ('99822000-0000-4000-8000-000000000001', 'Workshop Graph Tenant A'),
  ('99822000-0000-4000-8000-000000000002', 'Workshop Graph Tenant B');

-- Tenant bootstrap helpers temporarily set the request actor while seeding
-- tenant defaults. Clear it before creating business fixtures so unrelated
-- accounting trace triggers do not attribute them to a synthetic tenant UUID.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.customers(id, tenant_id, name) values
  ('99822000-0000-4000-8000-000000000011', '99822000-0000-4000-8000-000000000001', 'Customer A'),
  ('99822000-0000-4000-8000-000000000012', '99822000-0000-4000-8000-000000000001', 'Customer A2'),
  ('99822000-0000-4000-8000-000000000021', '99822000-0000-4000-8000-000000000002', 'Customer B');

insert into public.bikes(id, tenant_id, customer_id, brand, model) values
  ('99822000-0000-4000-8000-000000000031', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000011', 'Codex', 'Bike A'),
  ('99822000-0000-4000-8000-000000000032', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000012', 'Codex', 'Bike A2'),
  ('99822000-0000-4000-8000-000000000041', '99822000-0000-4000-8000-000000000002', '99822000-0000-4000-8000-000000000021', 'Codex', 'Bike B');

insert into public.products(
  id, tenant_id, name, sku, price, cost, is_service, product_type, track_stock
) values
  ('99822000-0000-4000-8000-000000000051', '99822000-0000-4000-8000-000000000001', 'Product A', 'GRAPH-A', 1000, 500, false, 'product', true),
  ('99822000-0000-4000-8000-000000000061', '99822000-0000-4000-8000-000000000002', 'Product B', 'GRAPH-B', 1000, 500, false, 'product', true),
  ('99822000-0000-4000-8000-000000000062', '99822000-0000-4000-8000-000000000002', 'Service B', 'GRAPH-SRV-B', 1000, 0, true, 'service', false);

insert into public.sales_invoices(
  id, tenant_id, invoice_number, status, subtotal, net_amount,
  total, paid_amount, balance, items
) values (
  '99822000-0000-4000-8000-000000000071',
  '99822000-0000-4000-8000-000000000002',
  'GRAPH-INV-B',
  'draft',
  0,
  0,
  0,
  0,
  0,
  '[]'::jsonb
);

insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, job_number
) values
  ('99822000-0000-4000-8000-000000000081', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000011', '99822000-0000-4000-8000-000000000031', 'GRAPH-JOB-A1'),
  ('99822000-0000-4000-8000-000000000082', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000011', '99822000-0000-4000-8000-000000000031', 'GRAPH-JOB-A2'),
  ('99822000-0000-4000-8000-000000000091', '99822000-0000-4000-8000-000000000002', '99822000-0000-4000-8000-000000000021', '99822000-0000-4000-8000-000000000041', 'GRAPH-JOB-B1');

insert into public.mechanic_job_bikes(
  id, tenant_id, job_id, bike_id, order_index
) values
  ('99822000-0000-4000-8000-000000000101', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000081', '99822000-0000-4000-8000-000000000031', 0),
  ('99822000-0000-4000-8000-000000000102', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000082', '99822000-0000-4000-8000-000000000031', 0),
  ('99822000-0000-4000-8000-000000000111', '99822000-0000-4000-8000-000000000002', '99822000-0000-4000-8000-000000000091', '99822000-0000-4000-8000-000000000041', 0);

insert into public.mechanic_job_items(
  id, tenant_id, job_id, job_bike_id, product_id,
  product_name, item_type, quantity, unit_price
) values (
  '99822000-0000-4000-8000-000000000121',
  '99822000-0000-4000-8000-000000000001',
  '99822000-0000-4000-8000-000000000081',
  '99822000-0000-4000-8000-000000000101',
  '99822000-0000-4000-8000-000000000051',
  'Product A',
  'product',
  1,
  1000
);

select ok(
  exists(
    select 1 from public.mechanic_job_items
    where id = '99822000-0000-4000-8000-000000000121'
      and tenant_id = '99822000-0000-4000-8000-000000000001'
  ),
  'a valid same-tenant workshop graph persists normally'
);

select throws_ok(
  $$insert into public.mechanic_jobs(id, tenant_id, customer_id, job_number)
    values ('99822000-0000-4000-8000-000000000131', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000021', 'GRAPH-BAD-CUSTOMER')$$,
  'P0001',
  'Workshop customer must belong to the job tenant',
  'a job cannot use another tenant customer'
);
select throws_ok(
  $$insert into public.mechanic_jobs(id, tenant_id, customer_id, bike_id, job_number)
    values ('99822000-0000-4000-8000-000000000132', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000011', '99822000-0000-4000-8000-000000000032', 'GRAPH-BAD-BIKE')$$,
  'P0001',
  'Workshop bicycle must belong to the job customer and tenant',
  'a job cannot use a different customer bicycle'
);
select throws_ok(
  $$insert into public.mechanic_jobs(id, tenant_id, customer_id, invoice_id, job_number)
    values ('99822000-0000-4000-8000-000000000133', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000011', '99822000-0000-4000-8000-000000000071', 'GRAPH-BAD-INVOICE')$$,
  'P0001',
  'Workshop invoice must belong to the job tenant',
  'a job cannot link another tenant invoice'
);
select throws_ok(
  $$update public.mechanic_jobs set discount_amount = -1
    where id = '99822000-0000-4000-8000-000000000081'$$,
  'P0001',
  'Workshop discount cannot be negative',
  'a workshop discount cannot become negative'
);
select throws_ok(
  $$insert into public.mechanic_job_bikes(id, tenant_id, job_id, bike_id, order_index)
    values ('99822000-0000-4000-8000-000000000141', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000091', '99822000-0000-4000-8000-000000000031', 1)$$,
  'P0001',
  'Job bicycle must belong to the parent job tenant',
  'a job bicycle cannot cross the parent tenant'
);
select throws_ok(
  $$insert into public.mechanic_job_bikes(id, tenant_id, job_id, bike_id, order_index)
    values ('99822000-0000-4000-8000-000000000142', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000081', '99822000-0000-4000-8000-000000000032', 1)$$,
  'P0001',
  'Job bicycle must belong to the job customer and tenant',
  'a job bicycle cannot use another customer bicycle'
);
select throws_ok(
  $$insert into public.mechanic_job_items(id, tenant_id, job_id, product_name, item_type, quantity, unit_price)
    values ('99822000-0000-4000-8000-000000000151', null, '99822000-0000-4000-8000-000000000081', 'Null tenant', 'adhoc', 1, 0)$$,
  '42501',
  'Workshop entity tenant is required',
  'new workshop items cannot omit tenant ownership'
);
select throws_ok(
  $$insert into public.mechanic_job_items(id, tenant_id, job_id, product_name, item_type, quantity, unit_price)
    values ('99822000-0000-4000-8000-000000000152', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000091', 'Wrong parent', 'adhoc', 1, 0)$$,
  'P0001',
  'Workshop item must belong to the parent job tenant',
  'a workshop item cannot cross the parent tenant'
);
select throws_ok(
  $$insert into public.mechanic_job_items(id, tenant_id, job_id, job_bike_id, product_name, item_type, quantity, unit_price)
    values ('99822000-0000-4000-8000-000000000153', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000081', '99822000-0000-4000-8000-000000000102', 'Wrong job bike', 'adhoc', 1, 0)$$,
  'P0001',
  'Workshop item bicycle must belong to the same job and tenant',
  'an item cannot use a bicycle assignment from another job'
);
select throws_ok(
  $$insert into public.mechanic_job_items(id, tenant_id, job_id, product_id, product_name, item_type, quantity, unit_price)
    values ('99822000-0000-4000-8000-000000000154', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000081', '99822000-0000-4000-8000-000000000061', 'Wrong product', 'product', 1, 1000)$$,
  'P0001',
  'Workshop product must belong to the item tenant',
  'an item cannot use another tenant product'
);
select throws_ok(
  $$insert into public.mechanic_job_items(id, tenant_id, job_id, service_product_id, product_name, item_type, quantity, unit_price)
    values ('99822000-0000-4000-8000-000000000155', '99822000-0000-4000-8000-000000000001', '99822000-0000-4000-8000-000000000081', '99822000-0000-4000-8000-000000000062', 'Wrong service', 'service', 1, 1000)$$,
  'P0001',
  'Workshop service must belong to the item tenant',
  'an item cannot use another tenant service'
);

select * from finish();
rollback;
