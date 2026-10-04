begin;

select plan(15);

-- Borrar un cliente con actividad lo rechaza la base: sus llaves borran en
-- cascada bicis y trabajos (20261003220000_guard_customer_delete_activity).

insert into public.tenants (id, shop_name) values
  ('d3c70000-0000-4000-8000-000000000001', 'Taller borrado A'),
  ('d3c70000-0000-4000-8000-000000000002', 'Taller borrado B');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.customers (id, tenant_id, name) values
  ('d3c70000-0000-4000-8000-000000000010', 'd3c70000-0000-4000-8000-000000000001', 'Sin nada'),
  ('d3c70000-0000-4000-8000-000000000011', 'd3c70000-0000-4000-8000-000000000001', 'Con bici'),
  ('d3c70000-0000-4000-8000-000000000012', 'd3c70000-0000-4000-8000-000000000001', 'Con trabajo'),
  ('d3c70000-0000-4000-8000-000000000013', 'd3c70000-0000-4000-8000-000000000001', 'Con trabajo borrado'),
  ('d3c70000-0000-4000-8000-000000000014', 'd3c70000-0000-4000-8000-000000000001', 'Con factura'),
  ('d3c70000-0000-4000-8000-000000000015', 'd3c70000-0000-4000-8000-000000000001', 'Bici en otro taller'),
  ('d3c70000-0000-4000-8000-000000000020', 'd3c70000-0000-4000-8000-000000000002', 'Cliente del taller B');

insert into public.bikes (id, tenant_id, customer_id, brand, model) values
  ('d3c70000-0000-4000-8000-000000000031', 'd3c70000-0000-4000-8000-000000000001',
   'd3c70000-0000-4000-8000-000000000011', 'Trek', 'Marlin 5'),
  -- Una bici de otra empresa que apunta a este cliente: la cascada no mira
  -- la empresa, la guardia tampoco.
  ('d3c70000-0000-4000-8000-000000000032', 'd3c70000-0000-4000-8000-000000000002',
   'd3c70000-0000-4000-8000-000000000015', 'Oxford', 'Jade'),
  ('d3c70000-0000-4000-8000-000000000033', 'd3c70000-0000-4000-8000-000000000002',
   'd3c70000-0000-4000-8000-000000000020', 'Giant', 'Talon');

insert into public.mechanic_jobs (id, tenant_id, customer_id, job_number, deleted_at) values
  ('d3c70000-0000-4000-8000-000000000041', 'd3c70000-0000-4000-8000-000000000001',
   'd3c70000-0000-4000-8000-000000000012', 'PG-BORRADO-1', null),
  ('d3c70000-0000-4000-8000-000000000042', 'd3c70000-0000-4000-8000-000000000001',
   'd3c70000-0000-4000-8000-000000000013', 'PG-BORRADO-2', now());

insert into public.sales_invoices (id, tenant_id, customer_id, invoice_number) values
  ('d3c70000-0000-4000-8000-000000000051', 'd3c70000-0000-4000-8000-000000000001',
   'd3c70000-0000-4000-8000-000000000014', 'FV-BORRADO-1');

select has_trigger('public', 'customers', 'trg_guard_customer_delete_activity',
  'customers has the delete guard');
select ok(
  (select p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']
     from pg_proc p where p.oid = 'public.guard_customer_delete_activity()'::regprocedure),
  'the guard sees every row (security definer, fixed search_path)');

select lives_ok(
  $$delete from public.customers where id = 'd3c70000-0000-4000-8000-000000000010'$$,
  'a customer with nothing is deleted');
select ok(
  not exists (select 1 from public.customers where id = 'd3c70000-0000-4000-8000-000000000010'),
  'and is gone');

select throws_ok(
  $$delete from public.customers where id = 'd3c70000-0000-4000-8000-000000000011'$$,
  '23503', 'customer_has_activity',
  'a customer with a bike is refused');
select ok(
  exists (select 1 from public.bikes where id = 'd3c70000-0000-4000-8000-000000000031'),
  'and the bike stays');

select throws_ok(
  $$delete from public.customers where id = 'd3c70000-0000-4000-8000-000000000012'$$,
  '23503', 'customer_has_activity',
  'a customer with a job is refused');
select throws_ok(
  $$delete from public.customers where id = 'd3c70000-0000-4000-8000-000000000013'$$,
  '23503', 'customer_has_activity',
  'a soft-deleted job still counts: the cascade would delete it');
select throws_ok(
  $$delete from public.customers where id = 'd3c70000-0000-4000-8000-000000000014'$$,
  '23503', 'customer_has_activity',
  'a customer with an invoice is refused');
select is(
  (select customer_id::text from public.sales_invoices where id = 'd3c70000-0000-4000-8000-000000000051'),
  'd3c70000-0000-4000-8000-000000000014',
  'and the invoice keeps its customer');
select throws_ok(
  $$delete from public.customers where id = 'd3c70000-0000-4000-8000-000000000015'$$,
  '23503', 'customer_has_activity',
  'a bike in another company also counts');

-- El detalle dice qué tiene.
create temporary table guard_detail(detail text) on commit drop;
do $$
begin
  delete from public.customers where id = 'd3c70000-0000-4000-8000-000000000011';
exception when foreign_key_violation then
  declare v_detail text;
  begin
    get stacked diagnostics v_detail = pg_exception_detail;
    insert into guard_detail values (v_detail);
  end;
end;
$$;
select is((select detail from guard_detail), 'El cliente tiene bicis.',
  'the detail names what the customer has');

-- Borrar una empresa se lleva a sus clientes y sus bicis en cascada.
select lives_ok(
  $$delete from public.tenants where id = 'd3c70000-0000-4000-8000-000000000002'$$,
  'deleting a company still cascades through its customers');
select ok(
  not exists (select 1 from public.customers where id = 'd3c70000-0000-4000-8000-000000000020')
  and not exists (select 1 from public.bikes where id = 'd3c70000-0000-4000-8000-000000000033'),
  'its customers and bikes are gone');
select ok(
  exists (select 1 from public.customers where id = 'd3c70000-0000-4000-8000-000000000011'),
  'the refused customers are untouched');

select * from finish();
rollback;
