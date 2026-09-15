-- Executable production read-back for 20260825233000.
-- Read-only: proves fit-first transport, labelled catalog cost, frozen plan
-- evidence, closed ACLs and the live exact 60 mm camera case.

select 1 / (case when to_regprocedure(
  'public.get_supply_need_stock_resolution_v3(uuid,integer,integer)'
) is not null then 1 else 0 end) as stock_resolution_v3_is_installed;

select 1 / (case when to_regprocedure(
  'public.purchase_plan_line_catalog_reference_v1()'
) is not null then 1 else 0 end) as plan_catalog_snapshot_trigger_is_installed;

select 1 / (case when
  has_function_privilege(
    'authenticated',
    'public.get_supply_need_stock_resolution_v3(uuid,integer,integer)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.get_supply_need_stock_resolution_v3(uuid,integer,integer)',
    'execute'
  )
then 1 else 0 end) as stock_resolution_v3_is_staff_only;

select 1 / (case when
  pg_get_functiondef(
    'public.get_supply_need_stock_resolution_v3(uuid,integer,integer)'::regprocedure
  ) like '%get_supply_need_stock_resolution_v2%'
  and pg_get_functiondef(
    'public.get_supply_need_stock_resolution_v3(uuid,integer,integer)'::regprocedure
  ) like '%catalogCostNet%'
  and pg_get_functiondef(
    'public.get_supply_need_stock_resolution_v3(uuid,integer,integer)'::regprocedure
  ) like '%automaticAvailabilityEnabled%'
then 1 else 0 end) as v3_adds_metadata_without_replacing_stock_resolution;

select 1 / (case when exists (
  select 1
  from pg_trigger trigger_row
  where trigger_row.tgrelid = 'public.purchase_plan_lines'::regclass
    and trigger_row.tgname = 'trg_purchase_plan_line_catalog_reference'
    and not trigger_row.tgisinternal
    and pg_get_triggerdef(trigger_row.oid) like '%BEFORE INSERT OR UPDATE%'
) then 1 else 0 end) as plan_snapshot_trigger_is_live;

select 1 / (case when
  pg_get_functiondef(
    'public.purchase_plan_line_catalog_reference_v1()'::regprocedure
  ) like '%catalog_cost_net%'
  and pg_get_functiondef(
    'public.purchase_plan_line_catalog_reference_v1()'::regprocedure
  ) not like '%new.landed_unit_cost_net%'
then 1 else 0 end) as catalog_reference_never_becomes_landed_cost;

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
  select need.id as need_id, product.id as product_id, product.cost,
    nullif(btrim(product.supplier_code), '') as supplier_code
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
), exact_item as (
  select target.need_id, target.product_id, target.cost,
    target.supplier_code, item.value
  from target
  cross join lateral jsonb_array_elements(
    public.get_supply_need_stock_resolution_v3(
      target.need_id, 12, 0
    ) -> 'items'
  ) item
  where item.value ->> 'productId' = target.product_id::text
)
select 1 / (case when exists (
  select 1
  from exact_item
  where value ->> 'supplierName' = 'Derman'
    and (value ->> 'catalogCostNet')::numeric = cost
    and value ->> 'supplierCode' is not distinct from supplier_code
    and value ->> 'evidenceState' = 'catalog_assignment'
) then 1 else 0 end) as exact_camera_keeps_derman_and_catalog_reference;

select 1 / (case when not exists (
  select 1
  from public.purchase_plan_lines line
  join public.products product
    on product.tenant_id = line.tenant_id
   and product.id = line.product_id
  where line.candidate_id is null
    and line.evidence_state in (
      'fresh_supplier_check', 'catalog_assignment', 'no_erp_history'
    )
    and product.cost > 0
    and (
      line.landed_unit_cost_net is not null
      or (line.evidence_snapshot ->> 'catalog_cost_net')::numeric
        is distinct from product.cost
      or line.evidence_snapshot ->> 'catalog_cost_currency'
        is distinct from coalesce(
          nullif(upper(product.cost_currency), ''), 'CLP'
        )
    )
) then 1 else 0 end) as no_history_plan_lines_freeze_reference_only;

select
  product.name,
  product.sku,
  product.cost as catalog_cost_net,
  supplier.name as catalog_supplier
from public.products product
left join public.suppliers supplier on supplier.id = product.supplier_id
where product.tenant_id = public.user_tenant_id()
  and product.sku = '160-4'
  and product.is_active is true;
