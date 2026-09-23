begin;

select no_plan();

-- Una ficha agotada sigue existiendo aunque el sitio oculte los agotados de
-- los listados (20260923210000).

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Fixtures sin disparadores de alta ni de stock.
set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values ('a17c0000-0000-4000-8000-000000000001', 'Tienda con agotados',
  'agotados@example.invalid', 'America/Santiago', true);

insert into public.website_settings (tenant_id, key, value)
values ('a17c0000-0000-4000-8000-000000000001',
  'product_visibility_stock_policy', 'available_only');

insert into public.products (
  id, tenant_id, name, sku, price, product_type, is_service,
  purchase_treatment, track_stock, inventory_qty, stock_quantity, is_active,
  is_published, show_on_website
) values
  ('a17c0000-0000-4000-8000-000000000101',
   'a17c0000-0000-4000-8000-000000000001', 'Cadena con stock', 'AGO-SI',
   15000, 'product', false, 'inventory', true, 3, 3, true, true, true),
  ('a17c0000-0000-4000-8000-000000000102',
   'a17c0000-0000-4000-8000-000000000001', 'Cadena agotada', 'AGO-NO',
   15000, 'product', false, 'inventory', true, 0, 0, true, true, true),
  ('a17c0000-0000-4000-8000-000000000103',
   'a17c0000-0000-4000-8000-000000000001', 'Cadena en borrador', 'AGO-BORR',
   15000, 'product', false, 'inventory', true, 0, 0, true, false, false);

set local session_replication_role = origin;
set local role anon;

select results_eq($$
  select sku, stock_quantity
    from public.get_public_products(
      p_tenant_id := 'a17c0000-0000-4000-8000-000000000001',
      p_product_ids := array['a17c0000-0000-4000-8000-000000000102']::uuid[],
      p_only_in_stock := false)
$$, $$ values ('AGO-NO'::text, 0) $$,
  'la ficha de un agotado se encuentra, con stock 0');

select results_eq($$
  select sku
    from public.get_public_products(
      p_tenant_id := 'a17c0000-0000-4000-8000-000000000001',
      p_sku := 'AGO-NO',
      p_only_in_stock := false)
$$, $$ values ('AGO-NO'::text) $$,
  'también por SKU, como llegan los enlaces antiguos');

select is_empty($$
  select sku
    from public.get_public_products(
      p_tenant_id := 'a17c0000-0000-4000-8000-000000000001',
      p_product_ids := array['a17c0000-0000-4000-8000-000000000102']::uuid[],
      p_only_in_stock := true)
$$, 'con p_only_in_stock (destacados, carrito) el agotado sigue oculto');

select results_eq($$
  select sku
    from public.get_public_products(
      p_tenant_id := 'a17c0000-0000-4000-8000-000000000001',
      p_only_in_stock := false)
   order by sku
$$, $$ values ('AGO-SI'::text) $$,
  'un listado sigue el ajuste del sitio y oculta el agotado');

select is_empty($$
  select sku
    from public.get_public_products(
      p_tenant_id := 'a17c0000-0000-4000-8000-000000000001',
      p_product_ids := array['a17c0000-0000-4000-8000-000000000103']::uuid[],
      p_only_in_stock := false)
$$, 'un producto no publicado sigue sin ficha pública');

reset role;

select * from finish();
rollback;
