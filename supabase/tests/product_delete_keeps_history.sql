begin;

select plan(21);

-- Borrar un producto con historia lo rechaza la base, y «Eliminar» en la app
-- lo archiva (20261030210000_guard_product_delete_history): la cascada se
-- llevaba su kardex y dejaba sin producto sus trabajos, compras y bicis.

insert into public.tenants (id, shop_name) values
  ('d4e10000-0000-4000-8000-000000000001', 'Taller productos A'),
  ('d4e10000-0000-4000-8000-000000000002', 'Taller productos B');

-- Tenant seed helpers touch transaction-local auth configuration. Product
-- fixture creation must remain an actorless synthetic setup.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'd4e10000-0000-4000-8000-000000000091', 'authenticated', 'authenticated',
  'productos-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);

insert into public.user_profiles (user_id, tenant_id, role, permissions) values
  ('d4e10000-0000-4000-8000-000000000091',
   'd4e10000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb);

insert into public.products (id, tenant_id, name, sku, price, tax_rate, product_type, is_service) values
  ('d4e10000-0000-4000-8000-000000000010', 'd4e10000-0000-4000-8000-000000000001',
   'Servicio sin nada', 'HIST-SV-0', 5000, null, 'service', true),
  ('d4e10000-0000-4000-8000-000000000011', 'd4e10000-0000-4000-8000-000000000001',
   'Servicio con trabajo', 'HIST-SV-JOB', 9000, null, 'service', true),
  ('d4e10000-0000-4000-8000-000000000012', 'd4e10000-0000-4000-8000-000000000001',
   'Cadena con movimiento', 'HIST-MOV', 12000, 19, 'product', false),
  ('d4e10000-0000-4000-8000-000000000013', 'd4e10000-0000-4000-8000-000000000001',
   'Servicio vendido', 'HIST-SOLD', 4000, null, 'service', true),
  ('d4e10000-0000-4000-8000-000000000014', 'd4e10000-0000-4000-8000-000000000001',
   'Producto recién creado', 'HIST-IVA', 3000, 19, 'product', false),
  ('d4e10000-0000-4000-8000-000000000015', 'd4e10000-0000-4000-8000-000000000001',
   'Servicio por error', 'HIST-SV-1', 1000, null, 'service', true),
  ('d4e10000-0000-4000-8000-000000000020', 'd4e10000-0000-4000-8000-000000000002',
   'Servicio del taller B', 'HIST-B', 1000, null, 'service', true);

insert into public.customers (id, tenant_id, name) values
  ('d4e10000-0000-4000-8000-000000000071', 'd4e10000-0000-4000-8000-000000000001', 'Cliente A');
insert into public.mechanic_jobs (id, tenant_id, customer_id, job_number) values
  ('d4e10000-0000-4000-8000-000000000081', 'd4e10000-0000-4000-8000-000000000001',
   'd4e10000-0000-4000-8000-000000000071', 'PG-HIST-1');
insert into public.mechanic_job_items (id, tenant_id, job_id, product_name, service_product_id) values
  ('d4e10000-0000-4000-8000-000000000082', 'd4e10000-0000-4000-8000-000000000001',
   'd4e10000-0000-4000-8000-000000000081', 'Servicio con trabajo',
   'd4e10000-0000-4000-8000-000000000011');

insert into public.stock_movements (tenant_id, product_id, type, quantity) values
  ('d4e10000-0000-4000-8000-000000000001', 'd4e10000-0000-4000-8000-000000000012', 'IN', 1),
  ('d4e10000-0000-4000-8000-000000000002', 'd4e10000-0000-4000-8000-000000000020', 'IN', 1);

-- A sale keeps its lines as JSON, with no key that could stop the delete.
insert into public.sales_invoices (id, tenant_id, invoice_number, items) values
  ('d4e10000-0000-4000-8000-000000000061', 'd4e10000-0000-4000-8000-000000000001',
   'FV-HIST-1', jsonb_build_array(jsonb_build_object(
     'product_id', 'd4e10000-0000-4000-8000-000000000013',
     'product_name', 'Servicio vendido', 'quantity', 1)));

select has_trigger('public', 'products', 'trg_guard_product_delete_history',
  'products has the delete guard');
select ok(
  (select bool_and(p.prosecdef and p.proconfig @> array['search_path=public, pg_temp'])
     from pg_proc p
    where p.oid in ('public.guard_product_delete_history()'::regprocedure,
                    'public.product_history_reasons_internal(uuid,uuid)'::regprocedure)),
  'the guard sees every row (security definer, fixed search_path)');

select lives_ok(
  $$delete from public.products where id = 'd4e10000-0000-4000-8000-000000000010'$$,
  'a product with nothing is deleted');
select ok(
  not exists (select 1 from public.products where id = 'd4e10000-0000-4000-8000-000000000010'),
  'and is gone');

select throws_ok(
  $$delete from public.products where id = 'd4e10000-0000-4000-8000-000000000011'$$,
  '23503', 'product_has_history',
  'a service used in a job is refused: its job lines would lose it');
select is(
  (select service_product_id::text from public.mechanic_job_items
    where id = 'd4e10000-0000-4000-8000-000000000082'),
  'd4e10000-0000-4000-8000-000000000011',
  'and the job line keeps its service');

select throws_ok(
  $$delete from public.products where id = 'd4e10000-0000-4000-8000-000000000012'$$,
  '23503', 'product_has_history',
  'a product with a stock movement is refused: the cascade would delete it');
select is(
  (select count(*)::int from public.stock_movements
    where product_id = 'd4e10000-0000-4000-8000-000000000012'),
  1,
  'and its movement stays');

select throws_ok(
  $$delete from public.products where id = 'd4e10000-0000-4000-8000-000000000013'$$,
  '23503', 'product_has_history',
  'a sold product is refused even though the sale has no key');

-- El detalle dice qué tiene.
create temporary table guard_detail(detail text) on commit drop;
do $$
begin
  delete from public.products where id = 'd4e10000-0000-4000-8000-000000000011';
exception when foreign_key_violation then
  declare v_detail text;
  begin
    get stacked diagnostics v_detail = pg_exception_detail;
    insert into guard_detail values (v_detail);
  end;
end;
$$;
select is((select detail from guard_detail), 'El producto tiene trabajos.',
  'the detail names what the product has');

select ok(
  has_function_privilege('authenticated',
    'public.delete_or_archive_product_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.delete_or_archive_product_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.product_history_reasons_internal(uuid,uuid)', 'EXECUTE'),
  'staff call the command; the history read stays private');

-- «Eliminar» desde la app, como el administrador del taller A.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'd4e10000-0000-4000-8000-000000000091',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub', 'd4e10000-0000-4000-8000-000000000091', true);
set local role authenticated;

select is(
  public.delete_or_archive_product_v1(
    'd4e10000-0000-4000-8000-000000000001', 'd4e10000-0000-4000-8000-000000000015'),
  '{"outcome": "deleted", "reasons": []}'::jsonb,
  'the app deletes a product with nothing');

select is(
  public.delete_or_archive_product_v1(
    'd4e10000-0000-4000-8000-000000000001', 'd4e10000-0000-4000-8000-000000000014'),
  '{"outcome": "archived", "reasons": ["registro de IVA"]}'::jsonb,
  'its IVA record keeps a product just created: it is archived');

select is(
  public.delete_or_archive_product_v1(
    'd4e10000-0000-4000-8000-000000000001', 'd4e10000-0000-4000-8000-000000000012'),
  '{"outcome": "archived", "reasons": ["movimientos de stock", "registro de IVA"]}'::jsonb,
  'a product with movements is archived and says why');

select is(
  public.delete_or_archive_product_v1(
    'd4e10000-0000-4000-8000-000000000001', 'd4e10000-0000-4000-8000-000000000013'),
  '{"outcome": "archived", "reasons": ["ventas"]}'::jsonb,
  'a sold product is archived');

select throws_ok(
  $$select public.delete_or_archive_product_v1(
      'd4e10000-0000-4000-8000-000000000002', 'd4e10000-0000-4000-8000-000000000020')$$,
  '42501', 'Product not found or not accessible',
  'another company is refused');

select throws_ok(
  $$select public.delete_or_archive_product_v1(
      'd4e10000-0000-4000-8000-000000000001', 'd4e10000-0000-4000-8000-000000000020')$$,
  'P0002', 'Product not found or not accessible',
  'a product of another company is not found in this one');

reset role;

select is(
  (select string_agg(id::text || ':' || is_active::text, ',' order by id)
     from public.products
    where id in ('d4e10000-0000-4000-8000-000000000012',
                 'd4e10000-0000-4000-8000-000000000013',
                 'd4e10000-0000-4000-8000-000000000014',
                 'd4e10000-0000-4000-8000-000000000015')),
  'd4e10000-0000-4000-8000-000000000012:false,d4e10000-0000-4000-8000-000000000013:false,d4e10000-0000-4000-8000-000000000014:false',
  'the archived products stay inactive and the deleted one is gone');

select is(
  (select count(*)::int from public.stock_movements
    where product_id = 'd4e10000-0000-4000-8000-000000000012'),
  1,
  'an archived product keeps its movements');

-- Borrar una empresa se lleva sus productos en cascada.
select lives_ok(
  $$delete from public.tenants where id = 'd4e10000-0000-4000-8000-000000000002'$$,
  'deleting a company still cascades through its products');
select ok(
  not exists (select 1 from public.products where id = 'd4e10000-0000-4000-8000-000000000020'),
  'its products are gone');

select * from finish();
rollback;
