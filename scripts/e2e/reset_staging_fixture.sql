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

commit;
