-- Manual test: verify that full inventory restore is blocked when there is
-- post-conversion activity, while config-only restore still succeeds.
--
-- Safe to run in Supabase SQL Editor. Ends with ROLLBACK.

begin;

create temp table _blocking_restore_ctx (
  product_id uuid not null,
  conversion_reference text not null
) on commit drop;

create temp table _blocking_restore_results (
  check_name text not null,
  outcome text not null,
  details text
) on commit drop;

do $$
declare
  v_tenant_id uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_actor_user_id uuid;
  v_product_id uuid;
  v_convert_result jsonb;
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
    v_tenant_id,
    'TEST PRODUCT RESTORE BLOCKING CASE',
    'TEST-RESTORE-BLOCK-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS'),
    20000,
    12000,
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
  returning id into v_product_id;

  v_convert_result := public.convert_product_inventory_to_non_stock(
    v_product_id,
    'workshop_consumable',
    'product',
    'TEST blocking case conversion'
  );

  insert into _blocking_restore_ctx (product_id, conversion_reference)
  values (v_product_id, v_convert_result->>'reference');

  insert into public.stock_adjustments (
    tenant_id,
    product_id,
    adjustment_type,
    quantity,
    stock_before,
    stock_after,
    reason,
    reference,
    created_by,
    created_at
  ) values (
    v_tenant_id,
    v_product_id,
    'manual',
    1,
    0,
    1,
    'TEST blocking activity after conversion',
    'manual-blocking-activity',
    auth.uid(),
    now()
  );
end;
$$;

do $$
declare
  v_product_id uuid;
  v_conversion_reference text;
begin
  select product_id, conversion_reference
    into v_product_id, v_conversion_reference
    from _blocking_restore_ctx
   limit 1;

  begin
    perform public.restore_product_conversion_state(
      v_product_id,
      'TEST full restore should be blocked',
      true,
      v_conversion_reference
    );

    insert into _blocking_restore_results (check_name, outcome, details)
    values (
      'full_restore_with_post_conversion_activity',
      'UNEXPECTED_SUCCESS',
      'The restore with inventory=true was expected to fail but succeeded.'
    );
  exception
    when others then
      insert into _blocking_restore_results (check_name, outcome, details)
      values (
        'full_restore_with_post_conversion_activity',
        'EXPECTED_FAILURE',
        SQLERRM
      );
  end;
end;
$$;

select public.restore_product_conversion_state(
  (select product_id from _blocking_restore_ctx limit 1),
  'TEST config-only restore after blocking activity',
  false,
  (select conversion_reference from _blocking_restore_ctx limit 1)
) as config_only_restore_result;

select *
from _blocking_restore_results;

select
  p.id,
  p.sku,
  p.purchase_treatment,
  p.product_type,
  p.track_stock,
  p.inventory_qty,
  p.stock_quantity
from public.products p
where p.id = (select product_id from _blocking_restore_ctx limit 1);

select
  ual.action,
  ual.created_at,
  ual.details->>'conversion_reference' as conversion_reference,
  ual.details->>'source_conversion_reference' as source_conversion_reference,
  ual.details->>'restore_reference' as restore_reference,
  ual.details->>'restored' as restored_flag,
  ual.details->>'restored_inventory' as restored_inventory
from public.user_activity_log ual
where ual.details->>'product_id' = (
  select product_id::text from _blocking_restore_ctx limit 1
)
  and ual.action in ('product_conversion', 'product_conversion_restore')
order by ual.created_at asc;

rollback;