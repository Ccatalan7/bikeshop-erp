-- READ-ONLY: compact production summary for historical repair gating.

with phantom as (
  select distinct on (adjustment.id)
    adjustment.id,
    adjustment.quantity,
    adjustment.reason,
    adjustment.reference,
    adjustment.created_at,
    invoice.invoice_number,
    movement.id as movement_id,
    movement.quantity as movement_quantity,
    movement.type as movement_type,
    product.sku,
    product.inventory_qty,
    product.stock_quantity
  from public.purchase_invoices invoice
  join public.stock_movements movement
    on movement.tenant_id = invoice.tenant_id
   and movement.reference = 'purchase_invoice:' || invoice.id::text
   and movement.movement_type = 'purchase_invoice_reversal'
  join public.stock_adjustments adjustment
    on adjustment.tenant_id = movement.tenant_id
   and adjustment.product_id = movement.product_id
   and adjustment.created_at = movement.created_at
   and adjustment.adjustment_type = 'manual'
  join public.products product on product.id = adjustment.product_id
  where invoice.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  order by adjustment.id, movement.id
), distribution as (
  select
    case when quantity < 0 then 'negative' when quantity > 0 then 'positive' else 'zero' end as sign,
    count(*) as rows,
    sum(quantity) as net
  from phantom
  group by 1
), linked_adjustment_journals as (
  select count(*) as rows
  from phantom
  join public.journal_entries entry
    on entry.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and entry.source_module = 'stock_adjustment'
   and entry.source_reference = phantom.id::text
)
select jsonb_build_object(
  'quantity_distribution',
    (select jsonb_agg(to_jsonb(x) order by x.sign) from distribution x),
  'non_negative_rows',
    (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at), '[]'::jsonb)
       from phantom x where quantity >= 0),
  'linked_adjustment_journals',
    (select rows from linked_adjustment_journals)
) as repair_summary;
