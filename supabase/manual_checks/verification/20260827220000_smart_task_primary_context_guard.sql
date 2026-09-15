-- Production read-back for 20260827220000.

select
  to_regprocedure('public.smart_tasks_guard_primary_context()') is not null
    as guard_function_installed,
  md5(pg_get_functiondef(
    'public.smart_tasks_guard_primary_context()'::regprocedure
  )) as definition_md5;

select
  trigger.tgname,
  trigger.tgenabled,
  pg_get_triggerdef(trigger.oid) as definition
from pg_trigger trigger
where trigger.tgrelid = 'public.smart_tasks'::regclass
  and trigger.tgname = 'trg_smart_tasks_guard_primary_context'
  and not trigger.tgisinternal;

select
  count(*) filter (
    where num_nonnulls(
      task.linked_job_id,
      task.linked_customer_id,
      task.linked_supplier_id,
      task.linked_sales_invoice_id,
      task.linked_purchase_invoice_id
    ) > 1
  ) as tasks_with_multiple_contexts,
  count(*) filter (
    where task.linked_customer_id is not null
      and not exists (
        select 1 from public.customers customer
        where customer.id = task.linked_customer_id
          and customer.tenant_id = task.tenant_id
      )
  ) as cross_tenant_customers,
  count(*) filter (
    where task.linked_supplier_id is not null
      and not exists (
        select 1 from public.suppliers supplier
        where supplier.id = task.linked_supplier_id
          and supplier.tenant_id = task.tenant_id
      )
  ) as cross_tenant_suppliers,
  count(*) filter (
    where task.linked_sales_invoice_id is not null
      and not exists (
        select 1 from public.sales_invoices invoice
        where invoice.id = task.linked_sales_invoice_id
          and invoice.tenant_id = task.tenant_id
      )
  ) as cross_tenant_sales,
  count(*) filter (
    where task.linked_purchase_invoice_id is not null
      and not exists (
        select 1 from public.purchase_invoices invoice
        where invoice.id = task.linked_purchase_invoice_id
          and invoice.tenant_id = task.tenant_id
      )
  ) as cross_tenant_purchases
from public.smart_tasks task;

select 1 / (case when exists (
  select 1
  from pg_trigger trigger
  where trigger.tgrelid = 'public.smart_tasks'::regclass
    and trigger.tgname = 'trg_smart_tasks_guard_primary_context'
    and trigger.tgenabled <> 'D'
    and not trigger.tgisinternal
) then 1 else 0 end) as primary_context_trigger_is_active;

select 1 / (case when not exists (
  select 1
  from public.smart_tasks task
  where num_nonnulls(
    task.linked_job_id,
    task.linked_customer_id,
    task.linked_supplier_id,
    task.linked_sales_invoice_id,
    task.linked_purchase_invoice_id
  ) > 1
) then 1 else 0 end) as every_task_has_at_most_one_primary_context;

