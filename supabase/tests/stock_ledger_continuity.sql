begin;

select plan(6);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name)
values ('99000000-0000-4000-8000-000000000010', 'Stock Ledger Continuity Test');

select set_config('request.jwt.claim.sub', '', true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
)
values (
  '99000000-0000-4000-8000-000000000011',
  '99000000-0000-4000-8000-000000000010',
  'Continuity Product', 'CONTINUITY-001', 5000, 2500,
  'product', false, true, 0, 0, 0, 20
);

insert into public.stock_movements (
  id, tenant_id, product_id, date, type, movement_type, quantity, created_at
) values
(
  '99000000-0000-4000-8000-000000000012',
  '99000000-0000-4000-8000-000000000010',
  '99000000-0000-4000-8000-000000000011',
  '2026-07-10 10:00:00+00', 'IN', 'manual', 10,
  '2026-07-01 10:00:00+00'
),
(
  '99000000-0000-4000-8000-000000000013',
  '99000000-0000-4000-8000-000000000010',
  '99000000-0000-4000-8000-000000000011',
  '2026-06-30 10:00:00+00', 'OUT', 'sale', 3,
  '2026-07-02 10:00:00+00'
);

select set_config('app.skip_stock_adjustment_trigger', 'true', true);
update public.products
set inventory_qty = 7,
    stock_quantity = 7
where id = '99000000-0000-4000-8000-000000000011';
select set_config('app.skip_stock_adjustment_trigger', '', true);

select is(
  (select count(*)::integer from public.stock_movements_ledger_view
    where product_id = '99000000-0000-4000-8000-000000000011'),
  2,
  'ledger keeps one row per movement'
);

select is(
  (select stock_after from public.stock_movements_ledger_view
    where product_id = '99000000-0000-4000-8000-000000000011'
    order by created_at desc, id desc limit 1),
  7,
  'newest posting ends at current product stock'
);

select is(
  (select id from public.stock_movements_ledger_view
    where product_id = '99000000-0000-4000-8000-000000000011'
    order by created_at desc, id desc limit 1),
  '99000000-0000-4000-8000-000000000013'::uuid,
  'posting order wins over conflicting effective-date order'
);

select is(
  (
    select count(*)::integer
    from (
      select
        stock_after,
        lag(stock_before) over (order by created_at desc, id desc) as newer_initial
      from public.stock_movements_ledger_view
      where product_id = '99000000-0000-4000-8000-000000000011'
    ) chain
    where newer_initial is not null
      and stock_after <> newer_initial
  ),
  0,
  'every older final equals the newer initial above it'
);

select is(
  (select count(*)::integer from public.stock_movements_ledger_view
    where product_id = '99000000-0000-4000-8000-000000000011'
      and stock_before + reconciled_quantity <> stock_after),
  0,
  'every row satisfies Initial + Cambio = Final'
);

select is(
  (select sum(reconciled_quantity)::integer
   from public.stock_movements_ledger_view
   where product_id = '99000000-0000-4000-8000-000000000011'),
  7,
  'ledger reconciled quantities preserve the net movement'
);

select * from finish();
rollback;
