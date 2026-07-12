begin;

create or replace function public.require_eligible_sales_invoice_for_correction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_status text;
  v_invoice_tenant uuid;
begin
  select lower(status), tenant_id
    into v_invoice_status, v_invoice_tenant
    from public.sales_invoices
   where id = new.sales_invoice_id;

  if not found then
    raise exception 'Sales invoice not found';
  end if;

  if v_invoice_tenant is distinct from new.tenant_id then
    raise exception 'Sales correction tenant does not match the invoice tenant';
  end if;

  if tg_table_name = 'sales_returns' and v_invoice_status not in (
    'paid', 'pagado', 'pagada'
  ) then
    raise exception 'Sales invoice must be paid before a physical return';
  end if;

  if tg_table_name = 'sales_credit_notes' and v_invoice_status not in (
    'confirmed', 'confirmado', 'confirmada',
    'paid', 'pagado', 'pagada',
    'overdue', 'vencido', 'vencida'
  ) then
    raise exception 'Sales invoice must be confirmed before a credit note';
  end if;

  return new;
end;
$$;

revoke all on function public.require_eligible_sales_invoice_for_correction()
  from public, anon, authenticated;

drop trigger if exists trg_require_posted_invoice_sales_return
  on public.sales_returns;
drop trigger if exists trg_require_eligible_invoice_sales_return
  on public.sales_returns;
create trigger trg_require_eligible_invoice_sales_return
before insert or update of sales_invoice_id, tenant_id
on public.sales_returns
for each row execute function public.require_eligible_sales_invoice_for_correction();

drop trigger if exists trg_require_posted_invoice_sales_credit_note
  on public.sales_credit_notes;
drop trigger if exists trg_require_eligible_invoice_sales_credit_note
  on public.sales_credit_notes;
create trigger trg_require_eligible_invoice_sales_credit_note
before insert or update of sales_invoice_id, tenant_id
on public.sales_credit_notes
for each row execute function public.require_eligible_sales_invoice_for_correction();

commit;
