begin;

select plan(2);

insert into public.tenants (id, shop_name)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Codex Test Tenant');

-- A service (or any non-stock item) must never be auto-added to purchase list.
insert into public.products (
  id,
  tenant_id,
  name,
  sku,
  price,
  cost,
  is_service,
  product_type,
  track_stock,
  stock_quantity,
  inventory_qty,
  min_stock_level,
  max_stock_level
)
values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'Brake Bleed',
  'SRV-PURCHASE-LIST-TEST',
  15000,
  0,
  true,
  'service',
  false,
  0,
  0,
  0,
  0
);

select ok(
  not exists(
    select 1
    from public.smart_purchase_list
    where tenant_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and product_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
      and status in ('pending', 'ordered')
  ),
  'services are never auto-added to smart_purchase_list'
);

-- A stock-tracked product below min stock SHOULD be auto-added.
insert into public.products (
  id,
  tenant_id,
  name,
  sku,
  price,
  cost,
  is_service,
  product_type,
  track_stock,
  stock_quantity,
  inventory_qty,
  min_stock_level,
  max_stock_level
)
values (
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'Inner Tube 29',
  'PRD-PURCHASE-LIST-TEST',
  3000,
  1000,
  false,
  'product',
  true,
  0,
  0,
  1,
  10
);

select ok(
  exists(
    select 1
    from public.smart_purchase_list
    where tenant_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
      and product_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
      and status in ('pending', 'ordered')
  ),
  'stock-tracked products below min stock are auto-added to smart_purchase_list'
);

select * from finish();

rollback;

