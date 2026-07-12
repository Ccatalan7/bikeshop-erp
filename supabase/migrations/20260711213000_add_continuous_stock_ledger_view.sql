-- Continuous posting ledger. Effective dates and source balances remain audit
-- evidence, while the primary Initial/Cambio/Final chain is ordered by posting.

begin;

drop view if exists public.stock_movements_ledger_view;
create view public.stock_movements_ledger_view
with (security_invoker = on)
as
with evidence as (
  select
    audit.*,
    audit.stock_before as evidence_stock_before,
    audit.stock_after as evidence_stock_after,
    audit.balance_provenance as evidence_balance_provenance,
    audit.integrity_status as evidence_integrity_status,
    greatest(coalesce(product.inventory_qty, 0), coalesce(product.stock_quantity, 0))::integer
      as current_stock
  from public.stock_movements_audit_view audit
  join public.products product
    on product.id = audit.product_id
   and product.tenant_id = audit.tenant_id
), ordered as (
  select
    evidence.*,
    (
      evidence.current_stock - coalesce(
        sum(evidence.reconciled_quantity) over (
          partition by evidence.tenant_id, evidence.product_id
          order by evidence.created_at desc, evidence.id desc
          rows between unbounded preceding and 1 preceding
        ),
        0
      )
    )::integer as ledger_stock_after
  from evidence
)
select
  ordered.id,
  ordered.product_id,
  ordered.product_name,
  ordered.product_sku,
  ordered.transaction_date,
  ordered.movement_type,
  ordered.source,
  ordered.reference_id,
  ordered.reference_number,
  ordered.quantity,
  (ordered.ledger_stock_after - ordered.reconciled_quantity)::integer as stock_before,
  ordered.ledger_stock_after::integer as stock_after,
  ordered.notes,
  ordered.adjustment_origin,
  ordered.created_by,
  ordered.created_at,
  ordered.tenant_id,
  ordered.raw_quantity,
  ordered.actual_stock_delta,
  ordered.reconciled_quantity,
  'current_stock_reconciled_ledger'::text as balance_provenance,
  case
    when ordered.is_summary_excluded then ordered.evidence_integrity_status
    when ordered.evidence_integrity_status in (
      'verified',
      'verified_adjustment',
      'legacy_purchase_reversal_collision'
    ) and (
      ordered.evidence_stock_before
        <> ordered.ledger_stock_after - ordered.reconciled_quantity
      or ordered.evidence_stock_after <> ordered.ledger_stock_after
    ) then 'ledger_source_balance_mismatch'
    else ordered.evidence_integrity_status
  end as integrity_status,
  ordered.is_summary_excluded,
  ordered.linked_adjustment_id,
  ordered.canonical_movement_id,
  ordered.operation_id,
  ordered.source_document_type,
  ordered.source_document_id,
  ordered.evidence_stock_before,
  ordered.evidence_stock_after,
  ordered.evidence_balance_provenance,
  ordered.evidence_integrity_status
from ordered;

grant select on public.stock_movements_ledger_view to authenticated;

commit;
