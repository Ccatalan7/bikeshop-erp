-- Truthful stock-movement read model. Historical evidence is classified, not
-- deleted or rewritten. Future adjustment movements persist their exact balance.

begin;

create or replace function public.sync_stock_adjustment_to_movement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.stock_movements (
    tenant_id,
    product_id,
    date,
    type,
    movement_type,
    reference,
    quantity,
    notes,
    created_at,
    operation_id,
    source_document_type,
    source_document_id,
    created_by,
    stock_before,
    stock_after
  ) values (
    NEW.tenant_id,
    NEW.product_id,
    coalesce(NEW.adjustment_date, NEW.created_at),
    case when NEW.quantity >= 0 then 'IN' else 'OUT' end,
    NEW.adjustment_type,
    NEW.reference,
    abs(NEW.quantity),
    NEW.reason,
    NEW.created_at,
    NEW.operation_id,
    'stock_adjustment',
    NEW.id,
    NEW.created_by,
    NEW.stock_before,
    NEW.stock_after
  );
  return NEW;
end;
$$;

drop view if exists public.stock_movements_audit_view;
create view public.stock_movements_audit_view
with (security_invoker = on)
as
with movement_candidates as (
  select
    candidate.*,
    count(*) over (partition by candidate.id) as source_match_count,
    row_number() over (
      partition by candidate.id
      order by candidate.reference_id nulls last
    ) as source_match_order
  from public.stock_movements_view candidate
),
movement_base as (
  select *
  from movement_candidates
  where source_match_order = 1
)
select
  movement.id,
  movement.product_id,
  movement.product_name,
  movement.product_sku,
  movement.transaction_date,
  movement.movement_type,
  movement.source,
  case
    when movement.movement_type = 'adjustment'
     and movement.source_match_count = 1
      then coalesce(movement.reference_id, adjustment.id)
    else movement.reference_id
  end as reference_id,
  movement.reference_number,
  movement.quantity,
  coalesce(
    raw_movement.stock_before,
    case when movement.source_match_count = 1 then adjustment.stock_before end,
    collision_adjustment.stock_before,
    movement.stock_before
  )::integer as stock_before,
  coalesce(
    raw_movement.stock_after,
    case when movement.source_match_count = 1 then adjustment.stock_after end,
    collision_adjustment.stock_after,
    movement.stock_after
  )::integer as stock_after,
  movement.notes,
  movement.adjustment_origin,
  movement.created_by,
  movement.created_at,
  movement.tenant_id,
  movement.quantity::integer as raw_quantity,
  (
    coalesce(
      raw_movement.stock_after,
      case when movement.source_match_count = 1 then adjustment.stock_after end,
      collision_adjustment.stock_after,
      movement.stock_after
    ) -
    coalesce(
      raw_movement.stock_before,
      case when movement.source_match_count = 1 then adjustment.stock_before end,
      collision_adjustment.stock_before,
      movement.stock_before
    )
  )::integer as actual_stock_delta,
  case
    when collision_purchase.id is not null then 0
    when collision_adjustment.id is not null then
      (collision_adjustment.stock_after - collision_adjustment.stock_before)::integer
    when adjustment.id is not null and movement.source_match_count = 1 then
      (adjustment.stock_after - adjustment.stock_before)::integer
    else movement.quantity::integer
  end as reconciled_quantity,
  case
    when raw_movement.stock_before is not null and raw_movement.stock_after is not null
      then 'persisted_movement'
    when movement.source_match_count > 1 then 'legacy_ambiguous_reconstruction'
    when adjustment.id is not null then 'stock_adjustment'
    when collision_adjustment.id is not null then 'legacy_collision_adjustment'
    else 'reconstructed'
  end as balance_provenance,
  case
    when movement.source_match_count > 1 then 'legacy_ambiguous_adjustment_match'
    when collision_purchase.id is not null then 'legacy_duplicate_footprint'
    when collision_adjustment.id is not null then 'legacy_purchase_reversal_collision'
    when raw_movement.stock_before is not null
     and raw_movement.stock_after is not null
     and raw_movement.stock_after - raw_movement.stock_before <> movement.quantity
      then 'arithmetic_mismatch'
    when raw_movement.stock_before is not null and raw_movement.stock_after is not null
      then 'verified'
    when adjustment.id is not null then 'verified_adjustment'
    else 'legacy_reconstructed'
  end as integrity_status,
  (collision_purchase.id is not null) as is_summary_excluded,
  case
    when movement.source_match_count = 1
      then coalesce(adjustment.id, collision_adjustment.id)
    else collision_adjustment.id
  end as linked_adjustment_id,
  collision_purchase.id as canonical_movement_id,
  raw_movement.operation_id,
  raw_movement.source_document_type,
  raw_movement.source_document_id
from movement_base movement
join public.stock_movements raw_movement
  on raw_movement.id = movement.id
 and raw_movement.tenant_id = movement.tenant_id
left join public.stock_adjustments adjustment
  on adjustment.tenant_id = movement.tenant_id
 and adjustment.product_id = movement.product_id
 and (
   adjustment.id = movement.reference_id
   or (
     raw_movement.source_document_type = 'stock_adjustment'
     and raw_movement.source_document_id = adjustment.id
   )
 )
left join lateral (
  select candidate.*
  from public.stock_adjustments candidate
  where movement.source = 'purchase_invoice_reversal'
    and movement.created_at < timestamp with time zone '2026-07-10 12:30:00+00'
    and candidate.tenant_id = movement.tenant_id
    and candidate.product_id = movement.product_id
    and candidate.created_at = movement.created_at
    and candidate.quantity < 0
  order by candidate.id
  limit 1
) collision_adjustment on true
left join lateral (
  select candidate.id
  from public.stock_movements candidate
  where movement.movement_type = 'adjustment'
    and movement.created_at < timestamp with time zone '2026-07-10 12:30:00+00'
    and candidate.tenant_id = movement.tenant_id
    and candidate.product_id = movement.product_id
    and candidate.created_at = movement.created_at
    and candidate.movement_type = 'purchase_invoice_reversal'
  order by candidate.id
  limit 1
) collision_purchase on true;

grant select on public.stock_movements_audit_view to authenticated;

commit;
