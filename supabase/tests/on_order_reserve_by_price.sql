begin;

select plan(4);

-- Lo que se le deja al proveedor depende del precio (20261124230000): 5 en lo
-- de hasta $200.000 y 1 en lo caro, que el distribuidor tiene de a pocas
-- unidades (horquillas RockShox de MKR: de 1 a 8). El tope por compra no
-- cambia (5/3/2 según precio).
--
-- Corre contra la forma de producción (scripts/db/test_production_shape.sh).

insert into public.tenants (id, shop_name, currency, timezone) values
  ('e2e20000-0000-4000-8000-000000000001', 'Taller reserva', 'CLP', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.suppliers (id, tenant_id, name, rut) values
  ('e2e20000-0000-4000-8000-000000000031', 'e2e20000-0000-4000-8000-000000000001',
   'Distribuidor con lector', '76.555.666-7');

insert into public.supplier_catalog_feeds (
  id, tenant_id, supplier_id, format, endpoint_template, last_ok_at, last_status
) values (
  'e2e20000-0000-4000-8000-0000000000f1', 'e2e20000-0000-4000-8000-000000000001',
  'e2e20000-0000-4000-8000-000000000031', 'mkr_csv_v1',
  'https://proveedor.example.cl/api/endpoint?token={token}',
  now() - interval '10 minutes', 'ok'
);
insert into public.supplier_catalog_feed_items (
  tenant_id, feed_id, supplier_id, supplier_sku, barcode, name, stock
) values
  ('e2e20000-0000-4000-8000-000000000001', 'e2e20000-0000-4000-8000-0000000000f1',
   'e2e20000-0000-4000-8000-000000000031', 'RS-2', null, 'Horquilla con 2', 2),
  ('e2e20000-0000-4000-8000-000000000001', 'e2e20000-0000-4000-8000-0000000000f1',
   'e2e20000-0000-4000-8000-000000000031', 'RS-1', null, 'Horquilla con 1', 1),
  ('e2e20000-0000-4000-8000-000000000001', 'e2e20000-0000-4000-8000-0000000000f1',
   'e2e20000-0000-4000-8000-000000000031', 'RS-8', null, 'Horquilla con 8', 8),
  ('e2e20000-0000-4000-8000-000000000001', 'e2e20000-0000-4000-8000-0000000000f1',
   'e2e20000-0000-4000-8000-000000000031', 'MID-5', null, 'Rueda con 5', 5),
  ('e2e20000-0000-4000-8000-000000000001', 'e2e20000-0000-4000-8000-0000000000f1',
   'e2e20000-0000-4000-8000-000000000031', 'MID-6', null, 'Rueda con 6', 6),
  ('e2e20000-0000-4000-8000-000000000001', 'e2e20000-0000-4000-8000-0000000000f1',
   'e2e20000-0000-4000-8000-000000000031', 'CHEAP-5', null, 'Cadena con 5', 5);

select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.products (
  id, tenant_id, name, sku, supplier_code, price, cost, tax_rate, product_type, is_service, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, supplier_id
) values
  ('e2e20000-0000-4000-8000-000000000011', 'e2e20000-0000-4000-8000-000000000001',
   'Horquilla con 2 en el proveedor', 'RS-2', 'RS-2', 685990, 461170, 19, 'product', false, true,
   0, 0, 0, 0, true, true, true, 'e2e20000-0000-4000-8000-000000000031'),
  ('e2e20000-0000-4000-8000-000000000012', 'e2e20000-0000-4000-8000-000000000001',
   'Horquilla con 1 en el proveedor', 'RS-1', 'RS-1', 436990, 293775, 19, 'product', false, true,
   0, 0, 0, 0, true, true, true, 'e2e20000-0000-4000-8000-000000000031'),
  ('e2e20000-0000-4000-8000-000000000013', 'e2e20000-0000-4000-8000-000000000001',
   'Horquilla con 8 en el proveedor', 'RS-8', 'RS-8', 685990, 461170, 19, 'product', false, true,
   0, 0, 0, 0, true, true, true, 'e2e20000-0000-4000-8000-000000000031'),
  ('e2e20000-0000-4000-8000-000000000014', 'e2e20000-0000-4000-8000-000000000001',
   'Rueda con 5 en el proveedor', 'MID-5', 'MID-5', 150000, 90000, 19, 'product', false, true,
   0, 0, 0, 0, true, true, true, 'e2e20000-0000-4000-8000-000000000031'),
  ('e2e20000-0000-4000-8000-000000000015', 'e2e20000-0000-4000-8000-000000000001',
   'Rueda con 6 en el proveedor', 'MID-6', 'MID-6', 200000, 120000, 19, 'product', false, true,
   0, 0, 0, 0, true, true, true, 'e2e20000-0000-4000-8000-000000000031'),
  ('e2e20000-0000-4000-8000-000000000016', 'e2e20000-0000-4000-8000-000000000001',
   'Cadena con 5 en el proveedor', 'CHEAP-5', 'CHEAP-5', 20000, 9000, 19, 'product', false, true,
   0, 0, 0, 0, true, true, true, 'e2e20000-0000-4000-8000-000000000031');
select set_config('request.jwt.claim.role', '', true);

insert into public.product_on_order_terms (product_id, tenant_id, supplier_id, lead_days_min, lead_days_max)
select p.id, p.tenant_id, 'e2e20000-0000-4000-8000-000000000031', 3, 5
  from public.products p
 where p.tenant_id = 'e2e20000-0000-4000-8000-000000000001';

select is(
  (select string_agg(p.sku || ':' || o.max_quantity, ',' order by p.sku)
     from public.product_on_order_offer_internal_v1('e2e20000-0000-4000-8000-000000000001', null) o
     join public.products p on p.id = o.product_id and p.tenant_id = 'e2e20000-0000-4000-8000-000000000001'),
  'MID-6:1,RS-2:1,RS-8:2',
  'over $200.000 the supplier keeps 1 and the cap of 2 holds; up to $200.000 it still keeps 5');

select ok(
  not exists (select 1 from public.product_on_order_offer_internal_v1(
    'e2e20000-0000-4000-8000-000000000001', array['e2e20000-0000-4000-8000-000000000012']::uuid[])),
  'an expensive item the supplier has only 1 of is not sold');

select ok(
  not exists (select 1 from public.product_on_order_offer_internal_v1(
    'e2e20000-0000-4000-8000-000000000001',
    array['e2e20000-0000-4000-8000-000000000014', 'e2e20000-0000-4000-8000-000000000016']::uuid[])),
  'up to $200.000, 5 with the supplier is still not enough');

update public.supplier_catalog_feeds set last_ok_at = now() - interval '4 hours'
 where id = 'e2e20000-0000-4000-8000-0000000000f1';
select ok(
  not exists (select 1 from public.product_on_order_offer_internal_v1(
    'e2e20000-0000-4000-8000-000000000001', null)),
  'a reading older than 3 hours sells nothing, expensive or not');

select * from finish();
rollback;
