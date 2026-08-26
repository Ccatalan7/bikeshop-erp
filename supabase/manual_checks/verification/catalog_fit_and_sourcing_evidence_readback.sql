-- Executable production read-back for 20260825230000.
-- Read-only: proves the catalog/history split, exact-only basket semantics,
-- closed ACLs and the live 60 mm camera case without creating a plan line.

select 1 / (case when to_regprocedure(
  'public.get_product_sourcing_evidence_v1(uuid[])'
) is not null then 1 else 0 end) as sourcing_read_is_installed;

select 1 / (case when to_regprocedure(
  'public.get_supply_need_stock_resolution_v2(uuid,integer,integer)'
) is not null then 1 else 0 end) as stock_resolution_v2_is_installed;

select 1 / (case when to_regprocedure(
  'public.prepare_purchase_plan_product_v1(uuid,bigint,uuid,uuid,numeric,text,text)'
) is not null then 1 else 0 end) as quote_line_command_is_installed;

select 1 / (case when
  not (
    select attribute.attnotnull
    from pg_attribute attribute
    where attribute.attrelid = 'public.purchase_plan_lines'::regclass
      and attribute.attname = 'candidate_id'
      and not attribute.attisdropped
  )
  and not (
    select attribute.attnotnull
    from pg_attribute attribute
    where attribute.attrelid = 'public.purchase_plan_lines'::regclass
      and attribute.attname = 'supplier_name'
      and not attribute.attisdropped
  )
  and (
    select attribute.attnotnull
    from pg_attribute attribute
    where attribute.attrelid = 'public.purchase_plan_lines'::regclass
      and attribute.attname = 'evidence_state'
      and not attribute.attisdropped
  )
then 1 else 0 end) as quote_line_columns_have_the_expected_nullability;

select 1 / (case when pg_get_constraintdef(oid) like
  '%erp_purchase_history%fresh_supplier_check%catalog_assignment%no_erp_history%'
then 1 else 0 end) as evidence_state_is_closed
from pg_constraint
where conrelid = 'public.purchase_plan_lines'::regclass
  and conname = 'purchase_plan_lines_evidence_state_check';

select 1 / (case when
  has_function_privilege(
    'authenticated',
    'public.get_product_sourcing_evidence_v1(uuid[])',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_supply_need_stock_resolution_v2(uuid,integer,integer)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.prepare_purchase_plan_product_v1(uuid,bigint,uuid,uuid,numeric,text,text)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.get_product_sourcing_evidence_v1(uuid[])',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.get_supply_need_stock_resolution_v2(uuid,integer,integer)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.prepare_purchase_plan_product_v1(uuid,bigint,uuid,uuid,numeric,text,text)',
    'execute'
  )
then 1 else 0 end) as sourcing_functions_are_caller_scoped;

select 1 / (case when
  pg_get_functiondef(
    'public.purchase_basket_supplier_coverage_internal_v1(uuid,jsonb,integer)'::regprocedure
  ) like '%filter (where not relaxed)%'
  and pg_get_functiondef(
    'public.purchase_basket_supplier_coverage_internal_v1(uuid,jsonb,integer)'::regprocedure
  ) like '%''coverageSemantics'', ''exact_only''%'
  and pg_get_functiondef(
    'public.purchase_basket_supplier_coverage_internal_v1(uuid,jsonb,integer)'::regprocedure
  ) like '%and not relaxed%'
then 1 else 0 end) as basket_coverage_is_exact_only;

select 1 / (case when pg_get_functiondef(
  'public.prepare_purchase_plan_line_v1(uuid,bigint,uuid,uuid,numeric,text,text)'::regprocedure
) like '%v_existing.candidate_id is distinct from v_candidate.candidate_id%'
then 1 else 0 end) as quote_line_promotion_is_null_safe;

select set_config(
  'request.jwt.claim.sub',
  (
    select profile.user_id::text
    from public.user_profiles profile
    join public.products product
      on product.tenant_id = profile.tenant_id
     and product.sku = '160-4'
     and product.is_active is true
    join public.supply_needs need
      on need.tenant_id = product.tenant_id
     and need.product_id = product.id
     and need.identity_state = 'confirmed'
     and need.supply_state = 'open'
    where profile.is_active is true
    order by profile.user_id
    limit 1
  ),
  true
) as exact_camera_tenant_context_ready;

with target as (
  select need.id as need_id, product.id as product_id
  from public.products product
  join public.supply_needs need
    on need.tenant_id = product.tenant_id
   and need.product_id = product.id
  where product.tenant_id = public.user_tenant_id()
    and product.sku = '160-4'
    and product.is_active is true
    and need.identity_state = 'confirmed'
    and need.supply_state = 'open'
  order by need.created_at desc
  limit 1
), resolution as (
  select target.product_id,
    public.get_supply_need_stock_resolution_v2(
      target.need_id, 12, 0
    ) as payload
  from target
), exact_item as (
  select resolution.product_id, resolution.payload->>'lane' as lane,
    item.value
  from resolution
  cross join lateral jsonb_array_elements(
    coalesce(resolution.payload->'items', '[]'::jsonb)
  ) item
  where item.value->>'productId' = resolution.product_id::text
)
select 1 / (case when exists (
  select 1
  from exact_item
  where lane = 'exact'
    and (
      (
        value->>'evidenceState' = 'catalog_assignment'
        and value->>'supplierName' = 'Derman'
        and (value->>'purchaseCount')::integer = 0
        and value->>'candidateId' is null
      )
      or (
        value->>'evidenceState' = 'erp_purchase_history'
        and (value->>'purchaseCount')::integer > 0
        and value->>'candidateId' is not null
      )
    )
) then 1 else 0 end) as exact_60mm_product_stays_visible_and_can_promote;

with product_row as (
  select product.id
  from public.products product
  where product.tenant_id = public.user_tenant_id()
    and product.sku = '160-4'
    and product.is_active is true
  limit 1
), evidence as (
  select public.get_product_sourcing_evidence_v1(
    array[product_row.id]
  ) as payload
  from product_row
)
select
  payload->'items'->0->>'evidenceState' as evidence_state,
  payload->'items'->0->>'supplierName' as supplier_name,
  payload->'items'->0->>'purchaseCount' as erp_purchase_count
from evidence;
