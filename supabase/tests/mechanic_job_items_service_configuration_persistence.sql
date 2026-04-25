begin;

select plan(4);

insert into public.tenants (id, shop_name)
values ('11111111-1111-4111-8111-111111111111', 'Codex Test Tenant');

insert into public.customers (id, tenant_id, name)
values (
  '22222222-2222-4222-8222-222222222222',
  '11111111-1111-4111-8111-111111111111',
  'Codex Test Customer'
);

insert into public.products (
  id,
  tenant_id,
  name,
  sku,
  price,
  cost,
  is_service,
  product_type,
  track_stock
)
values (
  '33333333-3333-4333-8333-333333333333',
  '11111111-1111-4111-8111-111111111111',
  'Brake Bleed',
  'SRV-JSON-TEST',
  15000,
  0,
  true,
  'service',
  false
);

insert into public.mechanic_jobs (id, tenant_id, customer_id, job_number)
values (
  '44444444-4444-4444-8444-444444444444',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'JOB-JSON-TEST'
);

insert into public.mechanic_job_items (
  id,
  tenant_id,
  job_id,
  service_product_id,
  product_name,
  item_type,
  quantity,
  unit_price,
  location_key,
  service_configuration_data
)
values (
  '55555555-5555-4555-8555-555555555555',
  '11111111-1111-4111-8111-111111111111',
  '44444444-4444-4444-8444-444444444444',
  '33333333-3333-4333-8333-333333333333',
  'Brake Bleed',
  'service',
  1,
  15000,
  'front',
  '{"which_wheel":"front","fluid_type":"mineral"}'::jsonb
);

select ok(
  exists(
    select 1
    from public.mechanic_job_items
    where id = '55555555-5555-4555-8555-555555555555'
      and total_price = 15000
      and item_type = 'service'
      and service_configuration_data =
        '{"which_wheel":"front","fluid_type":"mineral"}'::jsonb
  ),
  'service item insert preserves service_configuration_data and derived total'
);

select ok(
  exists(
    select 1
    from public.mechanic_jobs
    where id = '44444444-4444-4444-8444-444444444444'
      and labor_cost = 15000
      and parts_cost = 0
      and total_cost = 15000
  ),
  'service items roll up into labor totals'
);

update public.mechanic_job_items
set service_configuration_data =
  '{"which_wheel":"rear","fluid_type":"dot"}'::jsonb
where id = '55555555-5555-4555-8555-555555555555';

select ok(
  exists(
    select 1
    from public.mechanic_job_items
    where id = '55555555-5555-4555-8555-555555555555'
      and service_configuration_data =
        '{"which_wheel":"rear","fluid_type":"dot"}'::jsonb
  ),
  'service_configuration_data survives update triggers'
);

select ok(
  exists(
    select 1
    from public.mechanic_job_items
    where id = '55555555-5555-4555-8555-555555555555'
      and location_key = 'front'
  ),
  'updating configuration data does not clobber stored location metadata'
);

select * from finish();

rollback;
