-- Cleanup historical bogus stock adjustment artifacts caused by editing posted
-- sales invoices before 20260407134000_fix_sales_invoice_inventory_edit_side_effects.sql.
--
-- Scope:
-- - Tenant: Viñabike production
-- - Invoice set: derived from the read-only preview query run on 2026-04-07
-- - Deletes ONLY:
--     1) bogus manual stock_adjustments rows created by the restore trigger leak
--     2) the synced manual stock_movements rows created from those adjustments
-- - Does NOT update products or recalculate stock quantities.
--
-- Safety:
-- - Candidate adjustment must be a manual adjustment with one of the known bogus reasons.
-- - It must match a sales-invoice OUT movement for the same product within 30 seconds.
-- - It must belong to one of the preview-confirmed invoices below.
-- - The manual stock_movement deleted must match the adjustment exactly on
--   product, timestamp, type sign, quantity, reference, and notes.

begin;

create temp table tmp_historical_sales_edit_bug_adjustments on commit drop as
with confirmed_invoices as (
  select id, invoice_number, tenant_id
  from public.sales_invoices
  where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and invoice_number in (
      'FV-00307',
      'FV-00123',
      'FV-00300',
      'FV-00338',
      'FV-00048',
      'FV-00074',
      'FV-00269',
      'FV-00471',
      'FV-00503',
      'FV-00011',
      'FV-00135',
      'FV-00170',
      'FV-00179',
      'FV-00201',
      'FV-00212',
      'FV-00283',
      'FV-00289',
      'FV-00490',
      'FV-00502',
      'FV-00504'
    )
), candidate_adjustments as (
  select distinct
    sa.id as adjustment_id,
    sa.tenant_id,
    sa.product_id,
    sa.quantity as adjustment_quantity,
    sa.stock_before,
    sa.stock_after,
    sa.reason,
    sa.reference,
    sa.created_at as adjustment_created_at,
    ci.id as invoice_id,
    ci.invoice_number,
    sm_sale.id as sale_movement_id,
    sm_sale.created_at as sale_movement_created_at
  from confirmed_invoices ci
  join public.stock_movements sm_sale
    on sm_sale.tenant_id = ci.tenant_id
   and sm_sale.reference = 'sales_invoice:' || ci.id::text
   and sm_sale.type = 'OUT'
   and sm_sale.product_id is not null
  join public.stock_adjustments sa
    on sa.tenant_id = sm_sale.tenant_id
   and sa.product_id = sm_sale.product_id
   and sa.adjustment_type = 'manual'
   and coalesce(sa.reason, '') in (
     'Manual adjustment via product form',
     'Ajuste Manual'
   )
   and abs(extract(epoch from (sa.created_at - sm_sale.created_at))) <= 30
)
select *
from candidate_adjustments;

create temp table tmp_historical_sales_edit_bug_movements on commit drop as
select distinct
  sm.id as movement_id,
  sm.tenant_id,
  sm.product_id,
  sm.created_at,
  sm.type,
  sm.movement_type,
  sm.quantity,
  sm.reference,
  sm.notes,
  adj.adjustment_id,
  adj.invoice_number
from tmp_historical_sales_edit_bug_adjustments adj
join public.stock_movements sm
  on sm.tenant_id = adj.tenant_id
 and sm.product_id = adj.product_id
 and sm.created_at = adj.adjustment_created_at
 and sm.type = case
                 when adj.adjustment_quantity >= 0 then 'IN'
                 else 'OUT'
               end
 and coalesce(sm.movement_type, '') = 'manual'
 and sm.quantity = abs(adj.adjustment_quantity)
 and coalesce(sm.reference, '') = coalesce(adj.reference, '')
 and coalesce(sm.notes, '') = coalesce(adj.reason, '');

-- Preview what will be deleted.
select
  adj.invoice_number,
  count(distinct adj.adjustment_id) as adjustment_rows,
  count(distinct adj.sale_movement_id) as nearby_sale_movements,
  count(distinct mov.movement_id) as synced_manual_movement_rows
from tmp_historical_sales_edit_bug_adjustments adj
left join tmp_historical_sales_edit_bug_movements mov
  on mov.adjustment_id = adj.adjustment_id
group by adj.invoice_number
order by adj.invoice_number;

delete from public.stock_movements sm
using tmp_historical_sales_edit_bug_movements doomed
where sm.id = doomed.movement_id;

delete from public.stock_adjustments sa
using tmp_historical_sales_edit_bug_adjustments doomed
where sa.id = doomed.adjustment_id;

commit;