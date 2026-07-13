with fixture_product as (
  select product.*
  from public.products product
  where product.id = 'e2e00000-0000-4000-8000-000000000101'
    and product.tenant_id = 'e2e00000-0000-4000-8000-000000000001'
),
latest_forward as (
  select adjustment.*
  from public.stock_adjustments adjustment
  where adjustment.product_id = 'e2e00000-0000-4000-8000-000000000101'
    and adjustment.reason like '%[E2E] Forward stock adjustment%'
    and adjustment.created_at >= now() - interval '20 minutes'
  order by adjustment.created_at desc
  limit 1
),
latest_reverse as (
  select adjustment.*
  from public.stock_adjustments adjustment
  where adjustment.product_id = 'e2e00000-0000-4000-8000-000000000101'
    and adjustment.reason like '%[E2E] Reverse stock adjustment%'
    and adjustment.created_at >= now() - interval '20 minutes'
  order by adjustment.created_at desc
  limit 1
),
evidence as (
  select
    product.sku,
    product.inventory_qty as final_inventory_qty,
    product.stock_quantity as final_stock_quantity,
    forward_adjustment.operation_id as forward_operation_id,
    reverse_adjustment.operation_id as reverse_operation_id,
    forward_adjustment.created_at <= reverse_adjustment.created_at as ordered_pair,
    forward_adjustment.stock_before = 10
      and forward_adjustment.stock_after = 9
      and forward_movement.stock_before = 10
      and forward_movement.stock_after = 9 as forward_continuous,
    reverse_adjustment.stock_before = 9
      and reverse_adjustment.stock_after = 10
      and reverse_movement.stock_before = 9
      and reverse_movement.stock_after = 10 as reverse_continuous,
    forward_entry.total_debit = forward_entry.total_credit
      and reverse_entry.total_debit = reverse_entry.total_credit as journals_balanced,
    forward_operation.outcome = 'completed'
      and reverse_operation.outcome = 'completed'
      and exists (
        select 1 from public.inventory_accounting_checkpoints checkpoint
        where checkpoint.operation_id = forward_operation.id
          and checkpoint.phase = 'completed'
      )
      and exists (
        select 1 from public.inventory_accounting_checkpoints checkpoint
        where checkpoint.operation_id = reverse_operation.id
          and checkpoint.phase = 'completed'
      ) as traces_completed,
    not exists (
      select 1
      from public.inventory_accounting_inconsistencies_view inconsistency
      where inconsistency.operation_id in (
        forward_adjustment.operation_id,
        reverse_adjustment.operation_id
      )
    ) as no_inconsistencies
  from fixture_product product
  cross join latest_forward forward_adjustment
  cross join latest_reverse reverse_adjustment
  join public.stock_movements forward_movement
    on forward_movement.operation_id = forward_adjustment.operation_id
  join public.stock_movements reverse_movement
    on reverse_movement.operation_id = reverse_adjustment.operation_id
  join public.journal_entries forward_entry
    on forward_entry.operation_id = forward_adjustment.operation_id
  join public.journal_entries reverse_entry
    on reverse_entry.operation_id = reverse_adjustment.operation_id
  join public.inventory_accounting_operations forward_operation
    on forward_operation.id = forward_adjustment.operation_id
  join public.inventory_accounting_operations reverse_operation
    on reverse_operation.id = reverse_adjustment.operation_id
)
select
  count(*) = 1
    and bool_and(final_inventory_qty = 10)
    and bool_and(final_stock_quantity = 10)
    and bool_and(ordered_pair)
    and bool_and(forward_continuous)
    and bool_and(reverse_continuous)
    and bool_and(journals_balanced)
    and bool_and(traces_completed)
    and bool_and(no_inconsistencies) as passed,
  coalesce(max(sku), 'missing') as sku,
  coalesce(max(final_inventory_qty), -1) as final_stock
from evidence
\gset e2e_

\if :e2e_passed
\echo 'Verified E2E stock 10 -> 9 -> 10 with balanced journals and complete traces.'
\else
\echo 'E2E inventory/accounting verification failed.'
\quit 1
\endif
