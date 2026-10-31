-- 20261030190000: a product saved without tax carries 19 % IVA, so the
-- online-sale rule no longer hides it for 'missing_tax'; an exempt product and
-- a service keep theirs.
begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(5);

insert into public.tenants(id, shop_name, timezone) values
  ('9d320000-0000-4000-8000-000000000001', 'Tax Default Tenant', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.products (id, tenant_id, name, sku, price, tax_rate, product_type) values
  ('9d320000-0000-4000-8000-000000000011',
   '9d320000-0000-4000-8000-000000000001', 'Cámara 24 x 1.95', 'TAX-24', 4000, null, 'product'),
  ('9d320000-0000-4000-8000-000000000012',
   '9d320000-0000-4000-8000-000000000001', 'Libro de mecánica', 'TAX-EX', 9000, 0, 'product'),
  ('9d320000-0000-4000-8000-000000000013',
   '9d320000-0000-4000-8000-000000000001', 'Mantención', 'TAX-SV', 15000, null, 'service');

select is(
  (select tax_rate from public.products where id = '9d320000-0000-4000-8000-000000000011'),
  19.00::numeric,
  'a product saved without tax carries 19'
);

select is(
  (select tax_rate from public.products where id = '9d320000-0000-4000-8000-000000000012'),
  0.00::numeric,
  'an exempt product keeps 0'
);

select is(
  (select tax_rate from public.products where id = '9d320000-0000-4000-8000-000000000013'),
  null::numeric,
  'a service keeps no tax'
);

update public.products
   set tax_rate = null
 where id = '9d320000-0000-4000-8000-000000000012';

select is(
  (select tax_rate from public.products where id = '9d320000-0000-4000-8000-000000000012'),
  19.00::numeric,
  'clearing the tax of a product brings back 19'
);

update public.products
   set product_type = 'product'
 where id = '9d320000-0000-4000-8000-000000000013';

select is(
  (select tax_rate from public.products where id = '9d320000-0000-4000-8000-000000000013'),
  19.00::numeric,
  'a service turned into a product carries 19'
);

select * from finish();
rollback;
