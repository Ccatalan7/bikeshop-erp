-- Preserve received purchase invoices when payment ledgers are recalculated.
-- Payment state can change paid_amount/balance, but receiving inventory is the
-- terminal purchase workflow state and must not be downgraded to paid.

create or replace function public.recalculate_sales_invoice_payments(p_invoice_id uuid)
returns void as $$
declare
  v_invoice record;
  v_total numeric(12,2);
  v_new_status text;
  v_balance numeric(12,2);
  v_balance_raw numeric(12,2);
begin
  if p_invoice_id is null then
    return;
  end if;

  select id,
         total,
         status
    into v_invoice
    from public.sales_invoices
   where id = p_invoice_id
   for update;

  if not found then
    return;
  end if;

  select coalesce(sum(amount), 0)
    into v_total
    from public.sales_payments
   where invoice_id = p_invoice_id
     and deleted_at is null;

  v_balance_raw := round(coalesce(v_invoice.total, 0) - v_total, 2);
  v_balance := case
    when abs(v_balance_raw) < 1 then 0
    else greatest(v_balance_raw, 0)
  end;

  if v_invoice.status = 'cancelled' then
    v_new_status := v_invoice.status;
  elsif v_invoice.status = 'draft' then
    if v_balance = 0 and v_total > 0 then
      v_new_status := 'paid';
    else
      v_new_status := 'draft';
    end if;
  elsif v_balance = 0 and v_total > 0 then
    v_new_status := 'paid';
  elsif v_total > 0 and v_balance > 0 then
    if v_invoice.status = 'overdue' then
      v_new_status := 'overdue';
    else
      v_new_status := 'confirmed';
    end if;
  elsif v_total = 0 then
    if v_invoice.status = 'paid' then
      v_new_status := 'confirmed';
    else
      v_new_status := v_invoice.status;
    end if;
  else
    v_new_status := v_invoice.status;
  end if;

  update public.sales_invoices
     set paid_amount = v_total,
         balance = v_balance,
         status = v_new_status,
         updated_at = now()
   where id = p_invoice_id;

  perform public.sync_invoice_status_to_job(p_invoice_id);
end;
$$ language plpgsql;

create or replace function public.recalculate_purchase_invoice_payments(p_invoice_id uuid)
returns void as $$
declare
  v_invoice record;
  v_total numeric(12,2);
  v_new_status text;
  v_balance numeric(12,2);
  v_balance_raw numeric(12,2);
begin
  if p_invoice_id is null then
    return;
  end if;

  select id,
         total,
         status,
         prepayment_model,
         received_date
    into v_invoice
    from public.purchase_invoices
   where id = p_invoice_id
   for update;

  if not found then
    return;
  end if;

  select coalesce(sum(amount), 0)
    into v_total
    from public.purchase_payments
   where invoice_id = p_invoice_id
     and deleted_at is null;

  v_balance_raw := round(coalesce(v_invoice.total, 0) - v_total, 2);
  v_balance := case
    when abs(v_balance_raw) < 1 then 0
    else greatest(v_balance_raw, 0)
  end;

  if v_invoice.status = 'cancelled' then
    v_new_status := 'cancelled';
  elsif v_invoice.status = 'received' or v_invoice.received_date is not null then
    v_new_status := 'received';
  elsif v_invoice.status IN ('draft', 'sent') then
    v_new_status := v_invoice.status;
  elsif v_balance = 0 and v_total > 0 then
    v_new_status := 'paid';
  elsif v_total > 0 and v_balance > 0 then
    if v_invoice.prepayment_model then
      if v_invoice.status IN ('paid', 'received') then
        v_new_status := 'paid';
      else
        v_new_status := 'confirmed';
      end if;
    else
      if v_invoice.status IN ('received', 'paid') then
        v_new_status := 'received';
      else
        v_new_status := 'confirmed';
      end if;
    end if;
  else
    if v_invoice.prepayment_model then
      if v_invoice.status = 'paid' then
        v_new_status := 'confirmed';
      else
        v_new_status := v_invoice.status;
      end if;
    else
      if v_invoice.status = 'paid' then
        v_new_status := 'received';
      else
        v_new_status := v_invoice.status;
      end if;
    end if;
  end if;

  update public.purchase_invoices
     set paid_amount = v_total,
         balance = v_balance,
         status = v_new_status,
         updated_at = now()
   where id = p_invoice_id;
end;
$$ language plpgsql;

do $$
declare
  v_invoice record;
begin
  for v_invoice in
    select id
      from public.purchase_invoices
     where status = 'paid'
       and received_date is not null
       and coalesce(status, '') <> 'cancelled'
  loop
    perform public.recalculate_purchase_invoice_payments(v_invoice.id);
  end loop;
end $$;
