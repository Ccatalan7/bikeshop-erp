-- READ-ONLY audit of surviving real manual adjustments.
--
-- This query excludes the two phantom classes already identified and cleaned:
-- 1) sales-invoice-linked phantom manual adjustments
-- 2) standalone product-form sync-noise phantom adjustments
--
-- What remains should be the current real manual adjustments.

with manual_adjustments as (
  select
    sa.id as adjustment_id,
    sa.tenant_id,
    sa.product_id,
    sa.adjustment_type,
    sa.quantity,
    sa.stock_before,
    sa.stock_after,
    sa.reason,
    sa.reference,
    sa.created_at,
    sa.created_by
  from public.stock_adjustments sa
  where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and sa.adjustment_type = 'manual'
), sales_linked_phantom as (
  select distinct ma.adjustment_id
  from manual_adjustments ma
  join public.stock_movements sm_sale
    on sm_sale.tenant_id = ma.tenant_id
   and sm_sale.product_id = ma.product_id
   and sm_sale.reference like 'sales_invoice:%'
   and sm_sale.type = 'OUT'
   and abs(extract(epoch from (sm_sale.created_at - ma.created_at))) <= 30
), standalone_manual_rows as (
  select ma.*
  from manual_adjustments ma
  where coalesce(ma.reason, '') in (
      'Manual adjustment via product form',
      'Ajuste Manual'
    )
    and ma.reference is null
), standalone_without_business_context as (
  select smr.*
  from standalone_manual_rows smr
  where not exists (
    select 1
    from public.stock_movements sm
    where sm.tenant_id = smr.tenant_id
      and sm.product_id = smr.product_id
      and abs(extract(epoch from (sm.created_at - smr.created_at))) <= 60
      and (
        coalesce(sm.reference, '') <> ''
        or coalesce(sm.movement_type, '') <> 'manual'
      )
  )
), seed_rows as (
  select *
  from standalone_without_business_context
  where quantity > 0
    and (stock_before < 0 or stock_after <= 0)
), seeded_batches as (
  select distinct tenant_id, created_by, created_at
  from seed_rows
), standalone_product_form_sync_noise as (
  select distinct swbc.adjustment_id
  from standalone_without_business_context swbc
  join seeded_batches sb
    on sb.tenant_id = swbc.tenant_id
   and sb.created_by is not distinct from swbc.created_by
   and sb.created_at = swbc.created_at
), real_manual_adjustments as (
  select ma.*
  from manual_adjustments ma
  left join sales_linked_phantom slp
    on slp.adjustment_id = ma.adjustment_id
  left join standalone_product_form_sync_noise spsn
    on spsn.adjustment_id = ma.adjustment_id
  where slp.adjustment_id is null
    and spsn.adjustment_id is null
)
select
  rma.created_at,
  rma.adjustment_id,
  p.name as product_name,
  p.sku,
  rma.quantity,
  rma.stock_before,
  rma.stock_after,
  rma.reason,
  rma.reference,
  au.email as created_by_email,
  up.role as created_by_role,
  sm.id as movement_id,
  sm.type as movement_type_sign,
  sm.movement_type,
  sm.quantity as movement_qty,
  sm.reference as movement_reference,
  sm.notes as movement_notes
from real_manual_adjustments rma
left join public.products p
  on p.id = rma.product_id
 and p.tenant_id = rma.tenant_id
left join auth.users au
  on au.id = rma.created_by
left join public.user_profiles up
  on up.user_id = rma.created_by
 and up.tenant_id = rma.tenant_id
left join public.stock_movements sm
  on sm.tenant_id = rma.tenant_id
 and sm.product_id = rma.product_id
 and sm.created_at = rma.created_at
 and coalesce(sm.movement_type, '') = 'manual'
order by rma.created_at desc, p.name;

with manual_adjustments as (
  select
    sa.id as adjustment_id,
    sa.tenant_id,
    sa.product_id,
    sa.adjustment_type,
    sa.quantity,
    sa.stock_before,
    sa.stock_after,
    sa.reason,
    sa.reference,
    sa.created_at,
    sa.created_by
  from public.stock_adjustments sa
  where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and sa.adjustment_type = 'manual'
), sales_linked_phantom as (
  select distinct ma.adjustment_id
  from manual_adjustments ma
  join public.stock_movements sm_sale
    on sm_sale.tenant_id = ma.tenant_id
   and sm_sale.product_id = ma.product_id
   and sm_sale.reference like 'sales_invoice:%'
   and sm_sale.type = 'OUT'
   and abs(extract(epoch from (sm_sale.created_at - ma.created_at))) <= 30
), standalone_manual_rows as (
  select ma.*
  from manual_adjustments ma
  where coalesce(ma.reason, '') in (
      'Manual adjustment via product form',
      'Ajuste Manual'
    )
    and ma.reference is null
), standalone_without_business_context as (
  select smr.*
  from standalone_manual_rows smr
  where not exists (
    select 1
    from public.stock_movements sm
    where sm.tenant_id = smr.tenant_id
      and sm.product_id = smr.product_id
      and abs(extract(epoch from (sm.created_at - smr.created_at))) <= 60
      and (
        coalesce(sm.reference, '') <> ''
        or coalesce(sm.movement_type, '') <> 'manual'
      )
  )
), seed_rows as (
  select *
  from standalone_without_business_context
  where quantity > 0
    and (stock_before < 0 or stock_after <= 0)
), seeded_batches as (
  select distinct tenant_id, created_by, created_at
  from seed_rows
), standalone_product_form_sync_noise as (
  select distinct swbc.adjustment_id
  from standalone_without_business_context swbc
  join seeded_batches sb
    on sb.tenant_id = swbc.tenant_id
   and sb.created_by is not distinct from swbc.created_by
   and sb.created_at = swbc.created_at
), real_manual_adjustments as (
  select ma.*
  from manual_adjustments ma
  left join sales_linked_phantom slp
    on slp.adjustment_id = ma.adjustment_id
  left join standalone_product_form_sync_noise spsn
    on spsn.adjustment_id = ma.adjustment_id
  where slp.adjustment_id is null
    and spsn.adjustment_id is null
)
select
  coalesce(reason, '(sin motivo)') as reason,
  count(*) as adjustment_rows,
  sum(quantity) as total_quantity_delta,
  min(created_at) as first_seen_at,
  max(created_at) as last_seen_at
from real_manual_adjustments
group by coalesce(reason, '(sin motivo)')
order by last_seen_at desc, adjustment_rows desc;