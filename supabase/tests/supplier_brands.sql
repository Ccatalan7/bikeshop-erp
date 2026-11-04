begin;

select plan(24);

-- Las marcas de cada proveedor (20261103090000, 100000, 110000, 120000): una marca la traen varios
-- proveedores, cada fila dice de dónde salió, lo que se compró se vuelve
-- regla y lo que una persona quitó no vuelve solo.
--
-- Corre contra la forma de producción (scripts/db/test_production_shape.sh).

insert into public.tenants (id, shop_name, currency, timezone) values
  ('c0db0000-0000-4000-8000-000000000001', 'Taller marcas', 'CLP', 'America/Santiago'),
  ('c0db0000-0000-4000-8000-000000000002', 'Otro taller marcas', 'CLP', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c0db0000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
   'compras-marcas@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c0db0000-0000-4000-8000-000000000001"}'::jsonb, now(), now()),
  ('c0db0000-0000-4000-8000-000000000092', 'authenticated', 'authenticated',
   'vecino-marcas@example.invalid', '', now(), '{}'::jsonb,
   '{"tenant_id":"c0db0000-0000-4000-8000-000000000002"}'::jsonb, now(), now());
delete from public.user_profiles where user_id in (
  'c0db0000-0000-4000-8000-000000000091', 'c0db0000-0000-4000-8000-000000000092');
insert into public.user_profiles (user_id, tenant_id, role, permissions, is_active) values
  ('c0db0000-0000-4000-8000-000000000091', 'c0db0000-0000-4000-8000-000000000001', 'cashier', '{}'::jsonb, true),
  ('c0db0000-0000-4000-8000-000000000092', 'c0db0000-0000-4000-8000-000000000002', 'admin', '{}'::jsonb, true);

insert into public.suppliers (id, tenant_id, name) values
  ('c0db0000-0000-4000-8000-0000000000a1', 'c0db0000-0000-4000-8000-000000000001', 'Distribuidora Norte (prueba)'),
  ('c0db0000-0000-4000-8000-0000000000a2', 'c0db0000-0000-4000-8000-000000000001', 'Importadora Sur (prueba)'),
  ('c0db0000-0000-4000-8000-0000000000a3', 'c0db0000-0000-4000-8000-000000000002', 'Proveedor del vecino (prueba)');

-- Pedalia y Ruedex son del catálogo compartido; la ajena es del otro taller;
-- «SIN MARCA» no nombra a un fabricante; Descontinuada está inactiva y
-- Borradora sólo aparece en un borrador de factura.
insert into public.product_brands (id, tenant_id, name, is_active) values
  ('c0db0000-0000-4000-8000-0000000000b1', null, 'Pedalia Proveedores', true),
  ('c0db0000-0000-4000-8000-0000000000b2', null, 'Ruedex Proveedores', true),
  ('c0db0000-0000-4000-8000-0000000000b3', null, 'SIN MARCA', true),
  ('c0db0000-0000-4000-8000-0000000000b4', 'c0db0000-0000-4000-8000-000000000002', 'Ajena Proveedores', true),
  ('c0db0000-0000-4000-8000-0000000000b5', null, 'Descontinuada Proveedores', false),
  ('c0db0000-0000-4000-8000-0000000000b6', 'c0db0000-0000-4000-8000-000000000001', 'Borradora Proveedores', true);

select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website, brand_id, supplier_id
) values
  ('c0db0000-0000-4000-8000-000000000011', 'c0db0000-0000-4000-8000-000000000001',
   'Cassette Pedalia 11v', 'MP-1', 59000, 30000, 19, 'product', false, true, 1, 1, 0, 10, true, true, true,
   'c0db0000-0000-4000-8000-0000000000b1', 'c0db0000-0000-4000-8000-0000000000a1'),
  ('c0db0000-0000-4000-8000-000000000012', 'c0db0000-0000-4000-8000-000000000001',
   'Neumático Ruedex 29 x 2.25', 'MP-2', 29000, 15000, 19, 'product', false, true, 1, 1, 0, 10, true, true, true,
   'c0db0000-0000-4000-8000-0000000000b2', null),
  ('c0db0000-0000-4000-8000-000000000013', 'c0db0000-0000-4000-8000-000000000001',
   'Puños sin marca', 'MP-3', 3000, 1000, 19, 'product', false, true, 1, 1, 0, 10, true, true, true,
   'c0db0000-0000-4000-8000-0000000000b3', 'c0db0000-0000-4000-8000-0000000000a1'),
  ('c0db0000-0000-4000-8000-000000000014', 'c0db0000-0000-4000-8000-000000000001',
   'Cadena Borradora 9v', 'MP-4', 9000, 4000, 19, 'product', false, true, 1, 1, 0, 10, true, true, true,
   'c0db0000-0000-4000-8000-0000000000b6', null),
  ('c0db0000-0000-4000-8000-000000000015', 'c0db0000-0000-4000-8000-000000000001',
   'Pedal Descontinuada', 'MP-5', 9000, 4000, 19, 'product', false, true, 1, 1, 0, 10, true, true, true,
   'c0db0000-0000-4000-8000-0000000000b5', 'c0db0000-0000-4000-8000-0000000000a2');

insert into public.purchase_invoices (
  id, tenant_id, supplier_id, supplier_name, invoice_number, date, status, tax_treatment
) values
  ('c0db0000-0000-4000-8000-000000000051', 'c0db0000-0000-4000-8000-000000000001',
   'c0db0000-0000-4000-8000-0000000000a1', 'Distribuidora Norte (prueba)', 'MP-F1',
   date '2026-10-12', 'received', 'no_tax'),
  ('c0db0000-0000-4000-8000-000000000052', 'c0db0000-0000-4000-8000-000000000001',
   'c0db0000-0000-4000-8000-0000000000a2', 'Importadora Sur (prueba)', 'MP-F2',
   date '2026-10-20', 'draft', 'no_tax');
insert into public.purchase_invoice_lines (
  id, tenant_id, purchase_invoice_id, line_number, product_id, description,
  quantity, net_amount, line_kind, line_nature, classification_status, currency_code
) values
  ('c0db0000-0000-4000-8000-000000000061', 'c0db0000-0000-4000-8000-000000000001',
   'c0db0000-0000-4000-8000-000000000051', 1, 'c0db0000-0000-4000-8000-000000000012',
   'Neumático Ruedex 29 x 2.25', 2, 30000, 'item', 'inventory', 'classified', 'CLP'),
  ('c0db0000-0000-4000-8000-000000000062', 'c0db0000-0000-4000-8000-000000000001',
   'c0db0000-0000-4000-8000-000000000051', 2, 'c0db0000-0000-4000-8000-000000000012',
   'Neumático Ruedex 29 x 2.25', 1, 15000, 'item', 'inventory', 'classified', 'CLP'),
  ('c0db0000-0000-4000-8000-000000000063', 'c0db0000-0000-4000-8000-000000000001',
   'c0db0000-0000-4000-8000-000000000052', 1, 'c0db0000-0000-4000-8000-000000000014',
   'Cadena Borradora 9v', 1, 4000, 'item', 'inventory', 'classified', 'CLP');
select set_config('request.jwt.claim.role', '', true);

select ok(
  has_function_privilege('authenticated', 'public.supplier_brands_v1(uuid, uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.brand_suppliers_v1(uuid, uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.supplier_brand_index_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.save_supplier_brand_v1(uuid, uuid, uuid, boolean)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.remove_supplier_brand_v1(uuid, uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.supplier_brands_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.save_supplier_brand_v1(uuid, uuid, uuid, boolean)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.refresh_supplier_brands_from_records_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.refresh_supplier_brands_from_records_all_internal()', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.supplier_brands', 'INSERT')
  and not has_table_privilege('authenticated', 'public.supplier_brands', 'UPDATE')
  and not has_table_privilege('anon', 'public.supplier_brands', 'SELECT'),
  'the team reads and changes supplier brands only through their commands');

-- Lo que compramos se vuelve regla: Norte trae Pedalia (es su proveedor en
-- el catálogo) y Ruedex (factura recibida). Ni «SIN MARCA», ni la marca
-- inactiva, ni lo que sólo está en un borrador.
select is(
  public.refresh_supplier_brands_from_records_internal('c0db0000-0000-4000-8000-000000000001'),
  2,
  'the nightly rule assigns the brands of what was bought and of the products that list the supplier');

select is(
  (select jsonb_agg(jsonb_build_object('brand', b.name, 'source', sb.source, 'evidence', sb.evidence)
                    order by b.name)
     from public.supplier_brands sb join public.product_brands b on b.id = sb.brand_id
    where sb.tenant_id = 'c0db0000-0000-4000-8000-000000000001'),
  '[{"brand": "Pedalia Proveedores", "source": "records", "evidence": {"records": {"products": 1, "purchase_lines": 0}}},
    {"brand": "Ruedex Proveedores", "source": "records", "evidence": {"records": {"products": 0, "purchase_lines": 2, "last_purchase": "2026-10-12"}}}]'::jsonb,
  'each assignment says what in our records it came from');

select is(
  public.refresh_supplier_brands_from_records_internal('c0db0000-0000-4000-8000-000000000001'),
  0,
  'running the rule again adds nothing');

-- El equipo agrega marcas desde la ficha.
select set_config('request.jwt.claims', '{"sub":"c0db0000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0db0000-0000-4000-8000-000000000091', true);

select is(
  (select jsonb_agg(jsonb_build_object('name', x->>'name', 'official', x->'official', 'source', x->>'source'))
     from jsonb_array_elements(public.save_supplier_brand_v1(
       'c0db0000-0000-4000-8000-000000000001', 'c0db0000-0000-4000-8000-0000000000a2',
       'c0db0000-0000-4000-8000-0000000000b6')) x),
  '[{"name": "Borradora Proveedores", "official": false, "source": "manual"}]'::jsonb,
  'a member adds a brand to a supplier by hand');

select is(
  (select jsonb_agg(x->>'name')
     from jsonb_array_elements(public.save_supplier_brand_v1(
       'c0db0000-0000-4000-8000-000000000001', 'c0db0000-0000-4000-8000-0000000000a2',
       'c0db0000-0000-4000-8000-0000000000b1', true)) x),
  '["Pedalia Proveedores", "Borradora Proveedores"]'::jsonb,
  'the official representative of a brand comes first');

select is(
  (select jsonb_agg(jsonb_build_object('supplier', x->>'name', 'official', x->'official'))
     from jsonb_array_elements(public.brand_suppliers_v1(
       'c0db0000-0000-4000-8000-000000000001', 'c0db0000-0000-4000-8000-0000000000b1')) x),
  '[{"supplier": "Importadora Sur (prueba)", "official": true},
    {"supplier": "Distribuidora Norte (prueba)", "official": false}]'::jsonb,
  'one brand, several suppliers: who brings Pedalia, the official one first');

-- Dos líneas en un mismo documento son una compra (20261103110000).
select is(
  (select jsonb_build_object('products', x->'products', 'purchases', x->'purchases',
                             'purchase_lines', x->'purchase_lines',
                             'last_purchase', x->>'last_purchase')
     from jsonb_array_elements(public.supplier_brands_v1(
       'c0db0000-0000-4000-8000-000000000001', 'c0db0000-0000-4000-8000-0000000000a1')) x
    where x->>'name' = 'Ruedex Proveedores'),
  '{"products": 1, "purchases": 1, "purchase_lines": 2, "last_purchase": "2026-10-12"}'::jsonb,
  'a supplier brand says how many products of it the catalog has and how many purchases were made from that supplier');

select is(
  public.supplier_brand_index_v1('c0db0000-0000-4000-8000-000000000001')
    -> 'c0db0000-0000-4000-8000-0000000000a2',
  '{"brands": ["Borradora Proveedores", "Pedalia Proveedores"], "official": ["Pedalia Proveedores"]}'::jsonb,
  'the directory reads every supplier''s brands at once');

select is(
  (select x->'official'
     from jsonb_array_elements(public.save_supplier_brand_v1(
       'c0db0000-0000-4000-8000-000000000001', 'c0db0000-0000-4000-8000-0000000000a2',
       'c0db0000-0000-4000-8000-0000000000b1')) x
    where x->>'name' = 'Pedalia Proveedores'),
  'true'::jsonb,
  'adding a brand again leaves «official» as it was');

-- El logo de la marca viaja con ella (20261103120000), y sólo por https.
select set_config('request.jwt.claims', '{}', true);
update public.product_brands set logo_url = 'https://example.invalid/marcas/ruedex.png'
 where id = 'c0db0000-0000-4000-8000-0000000000b2';
select set_config('request.jwt.claims', '{"sub":"c0db0000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select is(
  (select x->>'logo_url'
     from jsonb_array_elements(public.supplier_brands_v1(
       'c0db0000-0000-4000-8000-000000000001', 'c0db0000-0000-4000-8000-0000000000a1')) x
    where x->>'name' = 'Ruedex Proveedores'),
  'https://example.invalid/marcas/ruedex.png',
  'a supplier brand carries the brand logo');

select throws_ok(
  $$update public.product_brands set logo_url = 'http://example.invalid/x.png'
     where id = 'c0db0000-0000-4000-8000-0000000000b2'$$,
  '23514', null,
  'a brand logo is only served over https');

-- Lo que no es una marca del taller, o no es una marca, no entra.
select throws_ok(
  $$select public.save_supplier_brand_v1('c0db0000-0000-4000-8000-000000000001',
      'c0db0000-0000-4000-8000-0000000000a1', 'c0db0000-0000-4000-8000-0000000000b4')$$,
  '23503', 'Brand not found for this tenant',
  'another shop''s brand cannot be assigned');

select throws_ok(
  $$select public.save_supplier_brand_v1('c0db0000-0000-4000-8000-000000000001',
      'c0db0000-0000-4000-8000-0000000000a1', 'c0db0000-0000-4000-8000-0000000000b3')$$,
  '23514', 'SIN MARCA is not a manufacturer',
  'a placeholder brand is not a supplier brand');

select throws_ok(
  $$select public.save_supplier_brand_v1('c0db0000-0000-4000-8000-000000000001',
      'c0db0000-0000-4000-8000-0000000000a1', 'c0db0000-0000-4000-8000-0000000000b5')$$,
  '23514', 'Brand is inactive',
  'an inactive brand cannot be added');

select throws_ok(
  $$select public.save_supplier_brand_v1('c0db0000-0000-4000-8000-000000000001',
      'c0db0000-0000-4000-8000-0000000000a3', 'c0db0000-0000-4000-8000-0000000000b1')$$,
  'P0002', 'Supplier not found in tenant',
  'another shop''s supplier cannot get brands');

set local role authenticated;
select throws_ok(
  $$insert into public.supplier_brands (tenant_id, supplier_id, brand_id)
    values ('c0db0000-0000-4000-8000-000000000001', 'c0db0000-0000-4000-8000-0000000000a1',
            'c0db0000-0000-4000-8000-0000000000b6')$$,
  '42501', null,
  'the table is not written directly');
reset role;

-- Quitar: deja de verse, el otro proveedor sigue, la noche no la repone.
select is(
  (select jsonb_agg(x->>'name')
     from jsonb_array_elements(public.remove_supplier_brand_v1(
       'c0db0000-0000-4000-8000-000000000001', 'c0db0000-0000-4000-8000-0000000000a1',
       'c0db0000-0000-4000-8000-0000000000b1')) x),
  '["Ruedex Proveedores"]'::jsonb,
  'a removed brand leaves the supplier''s list');

select is(
  (select jsonb_agg(x->>'name')
     from jsonb_array_elements(public.brand_suppliers_v1(
       'c0db0000-0000-4000-8000-000000000001', 'c0db0000-0000-4000-8000-0000000000b1')) x),
  '["Importadora Sur (prueba)"]'::jsonb,
  'and the brand page no longer lists that supplier');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select is(
  public.refresh_supplier_brands_from_records_internal('c0db0000-0000-4000-8000-000000000001'),
  0,
  'what a person removed the nightly rule does not put back');

select is(
  (select jsonb_build_object('removed', sb.removed_at is not null, 'by', sb.removed_by, 'official', sb.official)
     from public.supplier_brands sb
    where sb.tenant_id = 'c0db0000-0000-4000-8000-000000000001'
      and sb.supplier_id = 'c0db0000-0000-4000-8000-0000000000a1'
      and sb.brand_id = 'c0db0000-0000-4000-8000-0000000000b1'),
  '{"removed": true, "by": "c0db0000-0000-4000-8000-000000000091", "official": false}'::jsonb,
  'the removal is kept with who did it');

select set_config('request.jwt.claims', '{"sub":"c0db0000-0000-4000-8000-000000000091","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0db0000-0000-4000-8000-000000000091', true);
-- «Deshacer» (20261103100000): reponerla la deja como estaba.
select is(
  (select jsonb_build_object('source', x->>'source', 'official', x->'official', 'evidence', x->'evidence')
     from jsonb_array_elements(public.save_supplier_brand_v1(
       'c0db0000-0000-4000-8000-000000000001', 'c0db0000-0000-4000-8000-0000000000a1',
       'c0db0000-0000-4000-8000-0000000000b1')) x
    where x->>'name' = 'Pedalia Proveedores'),
  '{"source": "records", "official": false, "evidence": {"records": {"products": 1, "purchase_lines": 0}}}'::jsonb,
  'a brand put back keeps where it came from and its evidence');

select is(
  (select x->'official'
     from jsonb_array_elements(public.remove_supplier_brand_v1(
       'c0db0000-0000-4000-8000-000000000001', 'c0db0000-0000-4000-8000-0000000000a2',
       'c0db0000-0000-4000-8000-0000000000b1')) x
    where x->>'name' = 'Pedalia Proveedores')
  is null
  and (select x->'official'
     from jsonb_array_elements(public.save_supplier_brand_v1(
       'c0db0000-0000-4000-8000-000000000001', 'c0db0000-0000-4000-8000-0000000000a2',
       'c0db0000-0000-4000-8000-0000000000b1', true)) x
    where x->>'name' = 'Pedalia Proveedores') = 'true'::jsonb,
  true,
  'undoing the removal of the official representative puts it back as official');

-- Otro taller no lee ni cambia las marcas de éste.
select set_config('request.jwt.claims', '{"sub":"c0db0000-0000-4000-8000-000000000092","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'c0db0000-0000-4000-8000-000000000092', true);
select throws_ok(
  $$select public.supplier_brands_v1('c0db0000-0000-4000-8000-000000000001',
      'c0db0000-0000-4000-8000-0000000000a1')$$,
  '42501', 'Active tenant membership required',
  'another shop cannot read this shop''s supplier brands');

select * from finish();
rollback;
