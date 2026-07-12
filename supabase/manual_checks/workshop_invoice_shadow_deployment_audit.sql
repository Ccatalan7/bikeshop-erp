-- READ-ONLY: tenant-scoped before/after metrics for workshop shadow deployment.

with tenant as (
  select '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id
), metrics as (
  select 'product_inventory_sum' metric, coalesce(sum(inventory_qty), 0)::text value
  from public.products, tenant where products.tenant_id = tenant.tenant_id
  union all
  select 'product_stock_sum', coalesce(sum(stock_quantity), 0)::text
  from public.products, tenant where products.tenant_id = tenant.tenant_id
  union all
  select 'stock_movements', count(*)::text
  from public.stock_movements, tenant where stock_movements.tenant_id = tenant.tenant_id
  union all
  select 'stock_adjustments', count(*)::text
  from public.stock_adjustments, tenant where stock_adjustments.tenant_id = tenant.tenant_id
  union all
  select 'journal_entries', count(*)::text
  from public.journal_entries, tenant where journal_entries.tenant_id = tenant.tenant_id
  union all
  select 'sales_invoices', count(*)::text
  from public.sales_invoices, tenant where sales_invoices.tenant_id = tenant.tenant_id
  union all
  select 'sales_payments_active', count(*)::text
  from public.sales_payments, tenant
  where sales_payments.tenant_id = tenant.tenant_id and deleted_at is null
  union all
  select 'mechanic_jobs', count(*)::text
  from public.mechanic_jobs, tenant where mechanic_jobs.tenant_id = tenant.tenant_id
  union all
  select 'mechanic_jobs_linked', count(*)::text
  from public.mechanic_jobs, tenant
  where mechanic_jobs.tenant_id = tenant.tenant_id and invoice_id is not null
  union all
  select 'job_owned_stock_movements', count(*)::text
  from public.stock_movements, tenant
  where stock_movements.tenant_id = tenant.tenant_id
    and reference like 'mechanic_job:%'
  union all
  select 'job_owned_revenue_journals', count(*)::text
  from public.journal_entries, tenant
  where journal_entries.tenant_id = tenant.tenant_id
    and source_module = 'mechanic_jobs'
  union all
  select 'stock_column_drift', count(*)::text
  from public.products, tenant
  where products.tenant_id = tenant.tenant_id
    and coalesce(inventory_qty, 0) <> coalesce(stock_quantity, 0)
  union all
  select 'unbalanced_journals', count(*)::text
  from (
    select entry.id
    from public.journal_entries entry
    join tenant on entry.tenant_id = tenant.tenant_id
    left join public.journal_lines line
      on line.entry_id = entry.id and line.tenant_id = entry.tenant_id
    group by entry.id
    having round(coalesce(sum(line.debit_amount), 0), 2)
        <> round(coalesce(sum(line.credit_amount), 0), 2)
  ) broken
  union all
  select 'trace_inconsistencies', count(*)::text
  from public.inventory_accounting_inconsistencies_view, tenant
  where inventory_accounting_inconsistencies_view.tenant_id = tenant.tenant_id
  union all
  select 'control_settings_table_exists',
    (to_regclass('public.workshop_invoice_control_settings') is not null)::text
  union all
  select 'control_events_table_exists',
    (to_regclass('public.workshop_invoice_control_events') is not null)::text
  union all
  select 'control_view_exists',
    (to_regclass('public.workshop_invoice_ownership_control_view') is not null)::text
  union all
  select 'anon_can_consume_job_inventory',
    has_function_privilege(
      'anon', 'public.consume_mechanic_job_inventory(uuid)', 'EXECUTE'
    )::text
  union all
  select 'authenticated_can_restore_job_inventory',
    has_function_privilege(
      'authenticated', 'public.restore_mechanic_job_inventory(uuid)', 'EXECUTE'
    )::text
  union all
  select 'service_role_can_consume_job_inventory',
    has_function_privilege(
      'service_role', 'public.consume_mechanic_job_inventory(uuid)', 'EXECUTE'
    )::text
)
select metric, value from metrics order by metric;
