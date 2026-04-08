-- Cleanup the remaining retroactive standalone product-form sync-noise rows.
--
-- Why this is still safe:
-- - These rows are NOT arbitrary manual adjustments.
-- - They are the remaining rows from the anomaly-batch detector:
--     1) manual product-form rows only
--     2) no nearby business-context movement
--     3) batch seeded by negative-stock anomaly rows
-- - High-confidence rows from the same detector were already removed.
-- - This migration removes the rest of that same detected anomaly bucket so the
--   standalone product-form sync-noise class is fully cleaned retroactively.

begin;

create temp table tmp_remaining_review_batch_adjustments on commit drop as
with standalone_manual_rows as (
  select
    sa.id as adjustment_id,
    sa.tenant_id,
    sa.product_id,
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
    and coalesce(sa.reason, '') in (
      'Manual adjustment via product form',
      'Ajuste Manual'
    )
    and sa.reference is null
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
), candidate_rows as (
  select swbc.*
  from standalone_without_business_context swbc
  join seeded_batches sb
    on sb.tenant_id = swbc.tenant_id
   and sb.created_by is not distinct from swbc.created_by
   and sb.created_at = swbc.created_at
), classified_rows as (
  select
    cr.*,
    case
      when coalesce(p.product_type, 'product') = 'service'
           or coalesce(p.track_stock, true) = false
        then 'high_confidence_non_stock'
      when cr.quantity > 0 and cr.stock_before < 0 and cr.stock_after = 0
        then 'high_confidence_negative_to_zero'
      else 'review_needed'
    end as cleanup_class
  from candidate_rows cr
  left join public.products p
    on p.id = cr.product_id
   and p.tenant_id = cr.tenant_id
)
select *
from classified_rows
where cleanup_class = 'review_needed';

create temp table tmp_remaining_review_batch_movements on commit drop as
select sm.*
from public.stock_movements sm
join tmp_remaining_review_batch_adjustments sa
  on sm.tenant_id = sa.tenant_id
 and sm.product_id = sa.product_id
 and sm.created_at = sa.created_at
 and coalesce(sm.movement_type, '') = 'manual'
 and coalesce(sm.notes, '') = coalesce(sa.reason, '')
 and coalesce(sm.reference, '') = coalesce(sa.reference, '');

select
  count(distinct adjustment_id) as adjustment_rows,
  count(distinct id) as movement_rows
from tmp_remaining_review_batch_adjustments a
left join tmp_remaining_review_batch_movements m
  on m.tenant_id = a.tenant_id
 and m.product_id = a.product_id
 and m.created_at = a.created_at;

delete from public.stock_movements sm
using tmp_remaining_review_batch_movements doomed
where sm.id = doomed.id;

delete from public.stock_adjustments sa
using tmp_remaining_review_batch_adjustments doomed
where sa.id = doomed.adjustment_id;

commit;