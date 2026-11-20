begin;

select no_plan();

-- La lista de compras sugiere reposición, no lo que nunca se tiene en la
-- repisa: lo que se vende a pedido y nunca se compró para tener
-- (20261120140000).

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, timezone, is_active)
values
  ('a6090000-0000-4000-8000-000000000001', 'Tienda lista',
   'lista@example.invalid', 'America/Santiago', true),
  ('a6090000-0000-4000-8000-000000000002', 'Otra tienda',
   'otra-lista@example.invalid', 'America/Santiago', true);

insert into public.suppliers (id, tenant_id, name, is_active)
values ('a6090000-0000-4000-8000-000000000301',
        'a6090000-0000-4000-8000-000000000001', 'Proveedor lista', true);

-- Compras: una para tener (202), una sólo para el pedido de una cotización
-- (203) y una anulada (205).
insert into public.purchase_invoices
  (id, tenant_id, invoice_number, supplier_id, date, status, items)
values
  ('a6090000-0000-4000-8000-000000000402', 'a6090000-0000-4000-8000-000000000001',
   'F-202', 'a6090000-0000-4000-8000-000000000301', now() - interval '40 days', 'received',
   '[{"product_id": "a6090000-0000-4000-8000-000000000202", "quantity": 2}]'),
  ('a6090000-0000-4000-8000-000000000403', 'a6090000-0000-4000-8000-000000000001',
   'PED-203', 'a6090000-0000-4000-8000-000000000301', now() - interval '5 days', 'draft',
   '[{"product_id": "a6090000-0000-4000-8000-000000000203", "quantity": 1}]'),
  ('a6090000-0000-4000-8000-000000000405', 'a6090000-0000-4000-8000-000000000001',
   'F-205', 'a6090000-0000-4000-8000-000000000301', now() - interval '9 days', 'cancelled',
   '[{"product_id": "a6090000-0000-4000-8000-000000000205", "quantity": 1}]');

insert into public.customer_quote_purchase_orders
  (tenant_id, quote_id, online_order_id, supplier_id, purchase_invoice_id)
values
  ('a6090000-0000-4000-8000-000000000001', 'a6090000-0000-4000-8000-000000000501',
   'a6090000-0000-4000-8000-000000000601', 'a6090000-0000-4000-8000-000000000301',
   'a6090000-0000-4000-8000-000000000403');

-- Desde aquí corre sólo el disparador de stock de la lista, de verdad.
set local session_replication_role = origin;
alter table public.products disable trigger user;
alter table public.products enable trigger trg_auto_add_low_stock;

create function pg_temp.product(p_id text, p_sku text, p_type text default 'product',
  p_track boolean default true, p_tenant text default 'a6090000-0000-4000-8000-000000000001')
returns void
language sql
as $$
  insert into public.products (
    id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service,
    purchase_treatment, track_stock, inventory_qty, stock_quantity,
    min_stock_level, max_stock_level, is_active
  ) values (
    p_id::uuid, p_tenant::uuid, 'Producto ' || p_sku, p_sku, 10000, 5000, 19, p_type,
    p_type = 'service', case when p_type = 'service' then 'expense' else 'inventory' end,
    p_track, 0, 0, 1, 10, true
  );
$$;

create function pg_temp.pending(p_id text, p_tenant text default 'a6090000-0000-4000-8000-000000000001')
returns bigint
language sql
as $$
  select count(*) from public.smart_purchase_list
   where tenant_id = p_tenant::uuid and product_id = p_id::uuid and status = 'pending'
$$;

create function pg_temp.on_order(p_id text, p_active boolean default true,
  p_tenant text default 'a6090000-0000-4000-8000-000000000001')
returns void
language sql
as $$
  insert into public.product_on_order_terms (product_id, tenant_id, supplier_id, is_active)
  values (p_id::uuid, p_tenant::uuid, null, p_active)
  on conflict (product_id) do update set is_active = excluded.is_active
$$;

-- Lo de siempre: un producto en cero entra a la lista.
select pg_temp.product('a6090000-0000-4000-8000-000000000201', 'L-201');
select is(pg_temp.pending('a6090000-0000-4000-8000-000000000201'), 1::bigint,
  'a stocked product created at zero still enters the purchase list');

-- Se vende a pedido y nunca se compró para tener: sale al marcarlo y no vuelve.
select pg_temp.on_order('a6090000-0000-4000-8000-000000000201');
select is(pg_temp.pending('a6090000-0000-4000-8000-000000000201'), 0::bigint,
  'marking it on order removes the untouched automatic suggestion');
update public.products set stock_quantity = 0, inventory_qty = 0
 where id = 'a6090000-0000-4000-8000-000000000201';
select is(pg_temp.pending('a6090000-0000-4000-8000-000000000201'), 0::bigint,
  'a later stock update does not bring it back');

-- Comprado alguna vez para tener: lo a pedido es el respaldo, sigue en la lista.
select pg_temp.product('a6090000-0000-4000-8000-000000000202', 'L-202');
select pg_temp.on_order('a6090000-0000-4000-8000-000000000202');
select is(pg_temp.pending('a6090000-0000-4000-8000-000000000202'), 1::bigint,
  'a product bought for stock keeps its suggestion when marked on order');

-- Comprado sólo para el pedido de una cotización: cuenta como nunca comprado.
select pg_temp.product('a6090000-0000-4000-8000-000000000203', 'L-203');
select pg_temp.on_order('a6090000-0000-4000-8000-000000000203');
select is(pg_temp.pending('a6090000-0000-4000-8000-000000000203'), 0::bigint,
  'a purchase made only for a quote order does not count as stocking it');

-- Una sugerencia que alguien puso a mano se queda.
select pg_temp.product('a6090000-0000-4000-8000-000000000204', 'L-204');
update public.smart_purchase_list
   set notes = 'Pedido por el mesón'
 where tenant_id = 'a6090000-0000-4000-8000-000000000001'
   and product_id = 'a6090000-0000-4000-8000-000000000204';
select pg_temp.on_order('a6090000-0000-4000-8000-000000000204');
select is(pg_temp.pending('a6090000-0000-4000-8000-000000000204'), 1::bigint,
  'a suggestion someone wrote by hand is never removed');

-- Una compra anulada no cuenta; condiciones apagadas no sacan nada.
select pg_temp.product('a6090000-0000-4000-8000-000000000205', 'L-205');
select pg_temp.on_order('a6090000-0000-4000-8000-000000000205', false);
select is(pg_temp.pending('a6090000-0000-4000-8000-000000000205'), 1::bigint,
  'inactive on-order terms leave the suggestion alone');
select pg_temp.on_order('a6090000-0000-4000-8000-000000000205', true);
select is(pg_temp.pending('a6090000-0000-4000-8000-000000000205'), 0::bigint,
  'turning the terms on removes it, a cancelled purchase does not count');

-- Nunca cruza de tienda.
select pg_temp.product('a6090000-0000-4000-8000-000000000221', 'L-221', 'product', true,
  'a6090000-0000-4000-8000-000000000002');
select pg_temp.on_order('a6090000-0000-4000-8000-000000000201');
select is(pg_temp.pending('a6090000-0000-4000-8000-000000000221',
  'a6090000-0000-4000-8000-000000000002'), 1::bigint,
  'another shop keeps its own suggestion');
select is(
  public.purchase_list_on_order_only_internal_v1(
    'a6090000-0000-4000-8000-000000000002', 'a6090000-0000-4000-8000-000000000201'),
  false,
  'terms of one shop never answer for another');

select ok(
  not has_function_privilege('authenticated',
    'public.purchase_list_on_order_only_internal_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.purchase_list_on_order_only_internal_v1(uuid, uuid)', 'EXECUTE'),
  'the rule is private to the triggers'
);

select * from finish();
rollback;
