with checks(name, passed, details) as (
  values
    (
      'products_with_sets_final_shape',
      (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'products_with_sets')
        = (select count(*) + 4 from information_schema.columns where table_schema = 'public' and table_name = 'products'),
      'view exposes all product columns plus four computed set columns'
    ),
    (
      'inventory_operation_trace',
      to_regclass('public.inventory_accounting_operation_trace_view') is not null,
      'operation/checkpoint/stock/journal trace view exists'
    ),
    (
      'inventory_inconsistency_view',
      to_regclass('public.inventory_accounting_inconsistencies_view') is not null,
      'inventory and accounting inconsistency view exists'
    ),
    (
      'stock_audit_view',
      to_regclass('public.stock_movements_audit_view') is not null,
      'stock movement evidence read model exists'
    ),
    (
      'stock_ledger_view',
      to_regclass('public.stock_movements_ledger_view') is not null,
      'continuous stock ledger read model exists'
    ),
    (
      'payment_integrity_function',
      to_regprocedure('public.recalculate_sales_invoice_payments(uuid)') is not null,
      'sales payment reconciliation function exists'
    )
)
select name, passed, details
from checks
order by name;
