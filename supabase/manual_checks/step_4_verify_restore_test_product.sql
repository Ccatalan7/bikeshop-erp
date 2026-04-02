-- STEP 4: Verify final product state, stock adjustments, journals, and activity logs.
-- Replace PRODUCT_ID_HERE with the product_id from step 1.

select
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
where p.id = 'PRODUCT_ID_HERE'::uuid;

select
  sa.id,
  sa.adjustment_type,
  sa.quantity,
  sa.stock_before,
  sa.stock_after,
  sa.reason,
  sa.reference,
  sa.created_at
from public.stock_adjustments sa
where sa.product_id = 'PRODUCT_ID_HERE'::uuid
  and (
    sa.reference like 'product_conversion:%'
    or sa.reference like 'product_restore:%'
  )
order by sa.created_at asc;

select
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
where je.source_reference = 'PRODUCT_ID_HERE'
  and je.source_module in ('product_conversion', 'product_restore')
order by je.created_at asc;

select
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
where je.source_reference = 'PRODUCT_ID_HERE'
  and je.source_module in ('product_conversion', 'product_restore')
order by je.created_at asc, jl.created_at asc;

select
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
where ual.details->>'product_id' = 'PRODUCT_ID_HERE'
  and ual.action in ('product_conversion', 'product_conversion_restore')
order by ual.created_at asc;