begin;

do $$
declare
  v_tenant_name text;
  v_user_count integer;
begin
  select shop_name
    into v_tenant_name
    from public.tenants
   where id = 'e2e00000-0000-4000-8000-000000000001';

  if v_tenant_name is distinct from 'STAGING E2E - SYNTHETIC ONLY' then
    raise exception 'Refusing E2E reset: synthetic staging tenant is missing';
  end if;

  select count(*)::integer
    into v_user_count
    from auth.users user_account
    join public.user_profiles profile on profile.user_id = user_account.id
   where lower(user_account.email) = lower('e2e-agent@staging.vinabike.invalid')
     and profile.tenant_id = 'e2e00000-0000-4000-8000-000000000001';

  if v_user_count <> 1 then
    raise exception 'Refusing E2E reset: expected exactly one synthetic E2E actor';
  end if;
end
$$;

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
)
values (
  'e2e00000-0000-4000-8000-000000000101',
  'e2e00000-0000-4000-8000-000000000001',
  'Producto E2E - Ajuste reversible',
  'E2E-STOCK-REVERSAL',
  2500,
  1000,
  'product',
  false,
  true,
  10,
  10,
  0,
  100
)
on conflict (id) do update
set name = excluded.name,
    sku = excluded.sku,
    price = excluded.price,
    cost = excluded.cost,
    product_type = excluded.product_type,
    is_service = excluded.is_service,
    track_stock = excluded.track_stock,
    min_stock_level = excluded.min_stock_level,
    max_stock_level = excluded.max_stock_level
where products.tenant_id = excluded.tenant_id;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', user_account.id,
    'role', 'authenticated'
  )::text,
  true
)
from auth.users user_account
where lower(user_account.email) = lower('e2e-agent@staging.vinabike.invalid');

select set_config(
  'request.jwt.claim.sub',
  user_account.id::text,
  true
)
from auth.users user_account
where lower(user_account.email) = lower('e2e-agent@staging.vinabike.invalid');

with fixture as (
  select
    product.id,
    10 - product.inventory_qty as delta
  from public.products product
  where product.id = 'e2e00000-0000-4000-8000-000000000101'
    and product.tenant_id = 'e2e00000-0000-4000-8000-000000000001'
)
select public.apply_inventory_stock_adjustment(
  fixture.id,
  abs(fixture.delta)::integer,
  case when fixture.delta > 0 then 'IN' else 'OUT' end,
  'count',
  '[E2E reset] Restore deterministic stock baseline',
  now(),
  'manual_service'
)
from fixture
where fixture.delta <> 0;

do $$
begin
  if not exists (
    select 1
    from public.products product
    where product.id = 'e2e00000-0000-4000-8000-000000000101'
      and product.tenant_id = 'e2e00000-0000-4000-8000-000000000001'
      and product.inventory_qty = 10
      and product.stock_quantity = 10
  ) then
    raise exception 'E2E fixture reset did not restore stock baseline';
  end if;
end
$$;

delete from public.sales_payments
where invoice_id = 'e2e00000-0000-4000-8000-000000000201'
  and tenant_id = 'e2e00000-0000-4000-8000-000000000001';

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, date, due_date, reference,
  status, subtotal, iva_amount, total, paid_amount, balance, items,
  tax_treatment, net_amount, source, created_by
)
select
  'e2e00000-0000-4000-8000-000000000201',
  'e2e00000-0000-4000-8000-000000000001',
  'E2E-PAY-ROUNDING',
  'Cliente E2E - Pago reversible',
  now(),
  now() + interval '30 days',
  '[E2E] Partial whole-peso payment reversal',
  'confirmed',
  9000,
  0,
  9000,
  0,
  9000,
  jsonb_build_array(jsonb_build_object(
    'product_name', 'Servicio E2E sin movimiento de stock',
    'description', 'Fixture sintético para pagos parciales',
    'is_catalog_product', false,
    'quantity', 1,
    'unit_price', 9000,
    'discount', 0,
    'line_total', 9000,
    'cost', 0,
    'purchase_treatment', 'expense',
    'is_service', true
  )),
  'no_tax',
  9000,
  'manual_sale',
  user_account.id
from auth.users user_account
where lower(user_account.email) = lower('e2e-agent@staging.vinabike.invalid')
on conflict (id) do update
set invoice_number = excluded.invoice_number,
    customer_name = excluded.customer_name,
    date = excluded.date,
    due_date = excluded.due_date,
    reference = excluded.reference,
    status = excluded.status,
    subtotal = excluded.subtotal,
    iva_amount = excluded.iva_amount,
    total = excluded.total,
    paid_amount = excluded.paid_amount,
    balance = excluded.balance,
    items = excluded.items,
    tax_treatment = excluded.tax_treatment,
    net_amount = excluded.net_amount,
    source = excluded.source,
    created_by = excluded.created_by
where sales_invoices.tenant_id = excluded.tenant_id;

do $$
begin
  if not exists (
    select 1
    from public.sales_invoices invoice
    where invoice.id = 'e2e00000-0000-4000-8000-000000000201'
      and invoice.tenant_id = 'e2e00000-0000-4000-8000-000000000001'
      and invoice.status = 'confirmed'
      and invoice.total = 9000
      and invoice.paid_amount = 0
      and invoice.balance = 9000
      and not exists (
        select 1
        from public.sales_payments payment
        where payment.invoice_id = invoice.id
          and payment.deleted_at is null
      )
  ) then
    raise exception 'E2E payment fixture reset did not restore the unpaid baseline';
  end if;
end
$$;

commit;
