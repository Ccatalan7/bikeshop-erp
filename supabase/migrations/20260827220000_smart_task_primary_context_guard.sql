-- Una tarea es neutral y puede tener, como máximo, un contexto principal.
-- La UI ofrece Taller, cliente, proveedor, venta o compra de forma progresiva;
-- este guard hace que el contrato también sea verdad para RPCs, clientes
-- antiguos y mantenimiento directo.

create or replace function public.smart_tasks_guard_primary_context()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
begin
  if num_nonnulls(
    new.linked_job_id,
    new.linked_customer_id,
    new.linked_supplier_id,
    new.linked_sales_invoice_id,
    new.linked_purchase_invoice_id
  ) > 1 then
    raise exception 'smart_tasks: choose only one primary context'
      using errcode = '23514', hint = 'primary_context_only';
  end if;

  if new.linked_job_id is not null and not exists (
    select 1
    from public.mechanic_jobs job
    where job.id = new.linked_job_id
      and job.tenant_id = new.tenant_id
      and job.deleted_at is null
  ) then
    raise exception 'smart_tasks: linked job does not belong to the task tenant'
      using errcode = '23503', hint = 'context_not_in_tenant';
  end if;

  if new.linked_customer_id is not null and not exists (
    select 1
    from public.customers customer
    where customer.id = new.linked_customer_id
      and customer.tenant_id = new.tenant_id
  ) then
    raise exception 'smart_tasks: linked customer does not belong to the task tenant'
      using errcode = '23503', hint = 'context_not_in_tenant';
  end if;

  if new.linked_supplier_id is not null and not exists (
    select 1
    from public.suppliers supplier
    where supplier.id = new.linked_supplier_id
      and supplier.tenant_id = new.tenant_id
  ) then
    raise exception 'smart_tasks: linked supplier does not belong to the task tenant'
      using errcode = '23503', hint = 'context_not_in_tenant';
  end if;

  if new.linked_sales_invoice_id is not null and not exists (
    select 1
    from public.sales_invoices invoice
    where invoice.id = new.linked_sales_invoice_id
      and invoice.tenant_id = new.tenant_id
  ) then
    raise exception 'smart_tasks: linked sale does not belong to the task tenant'
      using errcode = '23503', hint = 'context_not_in_tenant';
  end if;

  if new.linked_purchase_invoice_id is not null and not exists (
    select 1
    from public.purchase_invoices invoice
    where invoice.id = new.linked_purchase_invoice_id
      and invoice.tenant_id = new.tenant_id
  ) then
    raise exception 'smart_tasks: linked purchase does not belong to the task tenant'
      using errcode = '23503', hint = 'context_not_in_tenant';
  end if;

  return new;
end;
$$;

revoke all on function public.smart_tasks_guard_primary_context()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_smart_tasks_guard_primary_context
  on public.smart_tasks;
create trigger trg_smart_tasks_guard_primary_context
before insert or update of
  tenant_id,
  linked_job_id,
  linked_customer_id,
  linked_supplier_id,
  linked_sales_invoice_id,
  linked_purchase_invoice_id
on public.smart_tasks
for each row execute function public.smart_tasks_guard_primary_context();

