begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

do $$
begin
  if exists (
    select 1
    from public.sales_invoices invoice
    left join public.customers customer
      on customer.id = invoice.customer_id
    where invoice.tenant_id is null
      and customer.tenant_id is null
  ) then
    raise exception
      'Cannot infer tenant_id for every legacy sales invoice';
  end if;

  update public.sales_invoices invoice
     set tenant_id = customer.tenant_id
    from public.customers customer
   where invoice.tenant_id is null
     and customer.id = invoice.customer_id
     and customer.tenant_id is not null;

  if exists (
    select 1
    from public.sales_invoices
    where tenant_id is null
  ) then
    raise exception
      'sales_invoices still contains rows without tenant_id';
  end if;
end
$$;

alter table public.sales_invoices
  alter column tenant_id set not null;

commit;
