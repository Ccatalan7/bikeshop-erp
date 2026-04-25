begin;

select plan(4);

insert into public.tenants (id, shop_name)
values ('66666666-6666-4666-8666-666666666666', 'Codex Bike Service Tenant');

insert into public.customers (id, tenant_id, name)
values (
  '77777777-7777-4777-8777-777777777777',
  '66666666-6666-4666-8666-666666666666',
  'Codex Bike Service Customer'
);

insert into public.bikes (id, tenant_id, customer_id, brand, model)
values (
  '88888888-8888-4888-8888-888888888888',
  '66666666-6666-4666-8666-666666666666',
  '77777777-7777-4777-8777-777777777777',
  'Codex',
  'Service Bike'
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
  '99999999-9999-4999-8999-999999999999',
  '66666666-6666-4666-8666-666666666666',
  'Suspension Service',
  'SRV-BIKE-TEST',
  22500,
  0,
  true,
  'service',
  false
);

insert into public.mechanic_jobs (
  id,
  tenant_id,
  customer_id,
  bike_id,
  job_number
)
values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '66666666-6666-4666-8666-666666666666',
  '77777777-7777-4777-8777-777777777777',
  '88888888-8888-4888-8888-888888888888',
  'JOB-BIKE-SERVICE-TEST'
);

insert into public.mechanic_job_bikes (
  id,
  tenant_id,
  job_id,
  bike_id,
  order_index
)
values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '66666666-6666-4666-8666-666666666666',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '88888888-8888-4888-8888-888888888888',
  0
);

insert into public.mechanic_job_items (
  id,
  tenant_id,
  job_id,
  job_bike_id,
  service_product_id,
  product_name,
  item_type,
  quantity,
  unit_price,
  location_key,
  service_configuration_data
)
values (
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  '66666666-6666-4666-8666-666666666666',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '99999999-9999-4999-8999-999999999999',
  'Suspension Service',
  'service',
  1,
  22500,
  'front',
  '{"service_target":"front_suspension"}'::jsonb
);

select ok(
  exists(
    select 1
    from public.mechanic_job_items
    where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
      and job_bike_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
      and service_configuration_data =
        '{"service_target":"front_suspension"}'::jsonb
  ),
  'service item keeps its job_bike_id and configuration data'
);

select ok(
  exists(
    select 1
    from public.mechanic_job_bikes
    where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
      and parts_cost = 0
      and labor_cost = 22500
      and subtotal = 22500
  ),
  'bike-level cost rollup treats assigned service as labor'
);

select ok(
  exists(
    select 1
    from public.mechanic_jobs
    where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and parts_cost = 0
      and labor_cost = 22500
      and total_cost = 22500
  ),
  'job-level cost rollup includes bike-assigned service labor'
);

select ok(
  not exists(
    select 1
    from public.mechanic_job_items
    where id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
      and job_bike_id is null
  ),
  'bike-assigned service does not fall back to a job-level orphan row'
);

select * from finish();

rollback;
