-- End-to-end manual test for workshop consumable conversion + restore.
--
-- What this does:
-- 1. Picks a real authenticated user from the Viñabike tenant.
-- 2. Sets SQL Editor session auth context to that user.
-- 3. Creates a disposable stock-tracked product.
-- 4. Converts it to workshop_consumable.
-- 5. Restores it with inventory = true.
-- 6. Shows product, stock adjustment, journal, and activity-log evidence.
-- 7. Rolls everything back so the DB stays clean.
--
-- Safe to run in Supabase SQL Editor as-is.

begin;

create temp table _product_restore_test_ctx (
  tenant_id uuid not null,
  actor_user_id uuid not null,
  product_id uuid not null,
  product_sku text not null,
  convert_reference text,
  convert_journal_entry_id uuid,
  restore_reference text,
  restore_journal_entry_id uuid
) on commit drop;

do $$
declare
  v_tenant_id uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_actor_user_id uuid;
  v_product_id uuid;
  v_product_sku text;
  v_convert_result jsonb;
  v_restore_result jsonb;
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

  v_product_sku := 'TEST-RESTORE-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISS');

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
    'TEST PRODUCT CONVERSION RESTORE',
    v_product_sku,
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
  returning id into v_product_id;

  v_convert_result := public.convert_product_inventory_to_non_stock(
    v_product_id,
    'workshop_consumable',
    'product',
    'TEST SQL roundtrip conversion'
  );

  v_restore_result := public.restore_product_conversion_state(
    v_product_id,
    'TEST SQL roundtrip restore',
    true,
    v_convert_result->>'reference'
  );

  insert into _product_restore_test_ctx (
    tenant_id,
    actor_user_id,
    product_id,
    product_sku,
    convert_reference,
    convert_journal_entry_id,
    restore_reference,
    restore_journal_entry_id
  ) values (
    v_tenant_id,
    v_actor_user_id,
    v_product_id,
    v_product_sku,
    v_convert_result->>'reference',
    nullif(v_convert_result->>'journal_entry_id', '')::uuid,
    v_restore_result->>'restore_reference',
    nullif(v_restore_result->>'journal_entry_id', '')::uuid
  );
end
$$;

-- Final product state: should be back to inventory/product with stock restored to 5.
select
  'final_product_state' as section,
  p.id,
  p.sku,
  p.name,
  p.purchase_treatment,
  p.product_type,
  p.track_stock,
  p.inventory_qty,
  p.stock_quantity,
  p.min_stock_level,
  p.max_stock_level
from public.products p
join _product_restore_test_ctx ctx
  on ctx.product_id = p.id;

-- Validation summary.
select
  'validation' as section,
  p.id as product_id,
  p.sku,
  case
    when p.purchase_treatment = 'inventory'
     and p.product_type = 'product'
     and coalesce(p.track_stock, true) = true
     and p.inventory_qty = 5
     and p.stock_quantity = 5
    then 'PASS'
    else 'FAIL'
  end as final_product_check,
  case
    when (
      select count(*)
        from public.stock_adjustments sa
       where sa.product_id = p.id
         and sa.reference like 'product_conversion:%'
    ) = 1
    then 'PASS'
    else 'FAIL'
  end as conversion_adjustment_check,
  case
    when (
      select count(*)
        from public.stock_adjustments sa
       where sa.product_id = p.id
         and sa.reference like 'product_restore:%'
    ) = 1
    then 'PASS'
    else 'FAIL'
  end as restore_adjustment_check,
  case
    when (
      select count(*)
        from public.journal_entries je
       where je.source_reference = p.id::text
         and je.source_module = 'product_conversion'
    ) = 1
    then 'PASS'
    else 'FAIL'
  end as conversion_journal_check,
  case
    when (
      select count(*)
        from public.journal_entries je
       where je.source_reference = p.id::text
         and je.source_module = 'product_restore'
    ) = 1
    then 'PASS'
    else 'FAIL'
  end as restore_journal_check
from public.products p
join _product_restore_test_ctx ctx
  on ctx.product_id = p.id;

-- Stock adjustments created by the round-trip.
select
  'stock_adjustments' as section,
  sa.id,
  sa.product_id,
  sa.adjustment_type,
  sa.quantity,
  sa.stock_before,
  sa.stock_after,
  sa.reason,
  sa.reference,
  sa.created_at
from public.stock_adjustments sa
join _product_restore_test_ctx ctx
  on ctx.product_id = sa.product_id
where sa.reference like 'product_conversion:%'
   or sa.reference like 'product_restore:%'
order by sa.created_at asc;

-- Journal entries created by the round-trip.
select
  'journal_entries' as section,
  je.id,
  je.entry_number,
  je.source_module,
  je.source_reference,
  je.description,
  je.total_debit,
  je.total_credit,
  je.status,
  je.created_at
from public.journal_entries je
join _product_restore_test_ctx ctx
  on je.source_reference = ctx.product_id::text
where je.source_module in ('product_conversion', 'product_restore')
order by je.created_at asc;

-- Journal lines: should show 5101/1105 on conversion and 1105/5101 on restore.
select
  'journal_lines' as section,
  je.source_module,
  je.entry_number,
  jl.account_code,
  jl.account_name,
  jl.debit_amount,
  jl.credit_amount,
  jl.description
from public.journal_entries je
join public.journal_lines jl
  on jl.entry_id = je.id
join _product_restore_test_ctx ctx
  on je.source_reference = ctx.product_id::text
where je.source_module in ('product_conversion', 'product_restore')
order by je.created_at asc, jl.created_at asc;

-- Activity log evidence for snapshot + restore.
select
  'activity_log' as section,
  ual.action,
  ual.created_at,
  ual.details->>'product_name' as product_name,
  ual.details->>'conversion_reference' as conversion_reference,
  ual.details->>'source_conversion_reference' as source_conversion_reference,
  ual.details->>'restore_reference' as restore_reference,
  ual.details->>'restored' as restored_flag,
  ual.details->>'restored_inventory' as restored_inventory,
  ual.details->>'journal_entry_id' as journal_entry_id
from public.user_activity_log ual
join _product_restore_test_ctx ctx
  on ual.details->>'product_id' = ctx.product_id::text
where ual.action in ('product_conversion', 'product_conversion_restore')
order by ual.created_at asc;

-- Context summary.
select
  'test_context' as section,
  tenant_id,
  actor_user_id,
  product_id,
  product_sku,
  convert_reference,
  convert_journal_entry_id,
  restore_reference,
  restore_journal_entry_id
from _product_restore_test_ctx;

rollback;