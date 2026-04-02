-- STEP 1: Create a disposable stock-tracked test product.
-- Run this in Supabase SQL Editor first.
-- Copy the returned product_id and sku for the next steps.

do $$
declare
  v_tenant_id uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_actor_user_id uuid;
begin
  select up.user_id
    into v_actor_user_id
    from public.user_profiles up
   where up.tenant_id = v_tenant_id
     and up.user_id is not null
     and up.role in ('owner', 'admin', 'manager')
   order by case up.role
              when 'owner' then 1
              when 'admin' then 2
              when 'manager' then 3
              else 99
            end,
            up.created_at asc nulls last
   limit 1;

  if v_actor_user_id is null then
    raise exception 'No owner/admin/manager user found for tenant %', v_tenant_id;
  end if;

  perform set_config('request.jwt.claim.sub', v_actor_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end
$$;

insert into public.products (
  tenant_id,
  name,
  sku,
  price,
  cost,
  inventory_qty,
  stock_quantity,
  track_stock,
  purchase_treatment,
  product_type,
  min_stock_level,
  max_stock_level,
  is_active,
  is_published,
  show_on_website
) values (
  '5443b130-cc28-45af-a420-cd500b288890',
  'TEST PRODUCT CONVERSION RESTORE',
  'TEST-RESTORE-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS'),
  15000,
  10000,
  5,
  5,
  true,
  'inventory',
  'product',
  0,
  10,
  true,
  false,
  false
)
returning id as product_id, sku, purchase_treatment, product_type, inventory_qty, stock_quantity;