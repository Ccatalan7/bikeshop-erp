-- Enforce whole-peso CLP amounts for sales/purchase invoices and payments.
-- These operational documents are paid and displayed in pesos, so storing
-- fractional residues creates fake balances and bad workflow transitions.

create or replace function public.clp_round(p_amount numeric)
returns numeric
language sql
immutable
as $$
  select round(coalesce(p_amount, 0), 0)
$$;

alter table public.purchase_invoices
  add column if not exists iva_amount numeric(12,2) not null default 0;

create or replace function public.normalize_sales_invoice_clp_amounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total numeric;
  v_net numeric;
  v_paid numeric;
begin
  v_total := public.clp_round(NEW.total);
  v_paid := public.clp_round(NEW.paid_amount);

  NEW.total := v_total;
  NEW.paid_amount := v_paid;
  NEW.discount_amount := public.clp_round(NEW.discount_amount);

  if NEW.tax_treatment = 'tax_included' and v_total <> 0 then
    v_net := public.clp_round(v_total / 1.19);
    NEW.net_amount := v_net;
    NEW.iva_amount := v_total - v_net;
    NEW.subtotal := v_total;
  else
    NEW.net_amount := v_total;
    NEW.iva_amount := 0;
    NEW.subtotal := v_total;
  end if;

  NEW.balance := greatest(v_total - v_paid, 0);
  return NEW;
end;
$$;

drop trigger if exists trg_sales_invoices_normalize_clp_amounts on public.sales_invoices;
create trigger trg_sales_invoices_normalize_clp_amounts
  before insert or update of subtotal, iva_amount, total, paid_amount, balance, net_amount, discount_amount, tax_treatment
  on public.sales_invoices
  for each row execute function public.normalize_sales_invoice_clp_amounts();

create or replace function public.normalize_purchase_invoice_clp_amounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total numeric;
  v_net numeric;
  v_paid numeric;
begin
  v_total := public.clp_round(NEW.total);
  v_paid := public.clp_round(NEW.paid_amount);

  NEW.total := v_total;
  NEW.paid_amount := v_paid;
  NEW.discount_amount := public.clp_round(NEW.discount_amount);

  if NEW.tax_treatment = 'tax_included' and v_total <> 0 then
    v_net := public.clp_round(v_total / 1.19);
    NEW.net_amount := v_net;
    NEW.subtotal := v_net;
    NEW.tax := v_total - v_net;
    NEW.iva_amount := NEW.tax;
  else
    NEW.net_amount := v_total;
    NEW.subtotal := v_total;
    NEW.tax := 0;
    NEW.iva_amount := 0;
  end if;

  NEW.balance := greatest(v_total - v_paid, 0);
  return NEW;
end;
$$;

drop trigger if exists trg_purchase_invoices_normalize_clp_amounts on public.purchase_invoices;
create trigger trg_purchase_invoices_normalize_clp_amounts
  before insert or update of subtotal, tax, iva_amount, total, paid_amount, balance, net_amount, discount_amount, tax_treatment
  on public.purchase_invoices
  for each row execute function public.normalize_purchase_invoice_clp_amounts();

create or replace function public.validate_sales_payment_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice record;
  v_existing_paid numeric(12,2);
  v_remaining numeric(12,2);
  v_amount numeric(12,2);
  v_net numeric(12,2);
begin
  if TG_OP = 'DELETE' then
    return OLD;
  end if;

  v_amount := public.clp_round(NEW.amount);
  if v_amount <= 0 then
    raise exception 'El monto del pago debe ser mayor a cero.';
  end if;

  NEW.amount := v_amount;

  if NEW.tax_treatment = 'tax_included' then
    v_net := public.clp_round(v_amount / 1.19);
    NEW.net_amount := v_net;
    NEW.iva_amount := v_amount - v_net;
  else
    NEW.tax_treatment := coalesce(NEW.tax_treatment, 'no_tax');
    NEW.net_amount := v_amount;
    NEW.iva_amount := 0;
  end if;

  if NEW.deleted_at is not null then
    return NEW;
  end if;

  if NEW.invoice_id is null then
    raise exception 'El pago debe pertenecer a una factura de venta.';
  end if;

  select id, tenant_id, total
    into v_invoice
    from public.sales_invoices
   where id = NEW.invoice_id
   for update;

  if not found then
    raise exception 'La factura de venta asociada al pago no existe.';
  end if;

  if NEW.tenant_id is null then
    NEW.tenant_id := v_invoice.tenant_id;
  end if;

  if NEW.tenant_id is distinct from v_invoice.tenant_id then
    raise exception 'El pago no pertenece al mismo tenant que la factura de venta.';
  end if;

  select public.clp_round(coalesce(sum(amount), 0))
    into v_existing_paid
    from public.sales_payments
   where invoice_id = NEW.invoice_id
     and deleted_at is null
     and id is distinct from NEW.id;

  v_remaining := public.clp_round(greatest(coalesce(v_invoice.total, 0) - v_existing_paid, 0));

  if v_amount > v_remaining then
    raise exception 'El pago excede el saldo pendiente de la factura de venta. Saldo pendiente: %, monto enviado: %.',
      v_remaining, v_amount;
  end if;

  return NEW;
end;
$$;

create or replace function public.validate_purchase_payment_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice record;
  v_existing_paid numeric(12,2);
  v_remaining numeric(12,2);
  v_amount numeric(12,2);
begin
  if TG_OP = 'DELETE' then
    return OLD;
  end if;

  v_amount := public.clp_round(NEW.amount);
  if v_amount <= 0 then
    raise exception 'El monto del pago debe ser mayor a cero.';
  end if;
  NEW.amount := v_amount;

  if NEW.deleted_at is not null then
    return NEW;
  end if;

  if NEW.invoice_id is null then
    raise exception 'El pago debe pertenecer a una factura de compra.';
  end if;

  select id, tenant_id, total
    into v_invoice
    from public.purchase_invoices
   where id = NEW.invoice_id
   for update;

  if not found then
    raise exception 'La factura de compra asociada al pago no existe.';
  end if;

  if NEW.tenant_id is null then
    NEW.tenant_id := v_invoice.tenant_id;
  end if;

  if NEW.tenant_id is distinct from v_invoice.tenant_id then
    raise exception 'El pago no pertenece al mismo tenant que la factura de compra.';
  end if;

  select public.clp_round(coalesce(sum(amount), 0))
    into v_existing_paid
    from public.purchase_payments
   where invoice_id = NEW.invoice_id
     and deleted_at is null
     and id is distinct from NEW.id;

  v_remaining := public.clp_round(greatest(coalesce(v_invoice.total, 0) - v_existing_paid, 0));

  if v_amount > v_remaining then
    raise exception 'El pago excede el saldo pendiente de la factura de compra. Saldo pendiente: %, monto enviado: %.',
      v_remaining, v_amount;
  end if;

  return NEW;
end;
$$;

create or replace function public.recalculate_sales_invoice_payments(p_invoice_id uuid)
returns void as $$
declare
  v_invoice record;
  v_total numeric(12,2);
  v_new_status text;
  v_balance numeric(12,2);
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

  select public.clp_round(coalesce(sum(amount), 0))
    into v_total
    from public.sales_payments
   where invoice_id = p_invoice_id
     and deleted_at is null;

  v_balance := greatest(public.clp_round(coalesce(v_invoice.total, 0)) - v_total, 0);

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

  select public.clp_round(coalesce(sum(amount), 0))
    into v_total
    from public.purchase_payments
   where invoice_id = p_invoice_id
     and deleted_at is null;

  v_balance := greatest(public.clp_round(coalesce(v_invoice.total, 0)) - v_total, 0);

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

create or replace function public.normalize_journal_entry_to_clp(p_entry_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_debit numeric;
  v_credit numeric;
  v_diff numeric;
  v_line_id uuid;
begin
  if p_entry_id is null then
    return;
  end if;

  update public.journal_lines
     set debit_amount = public.clp_round(debit_amount),
         credit_amount = public.clp_round(credit_amount),
         updated_at = now()
   where entry_id = p_entry_id;

  select coalesce(sum(debit_amount), 0), coalesce(sum(credit_amount), 0)
    into v_debit, v_credit
    from public.journal_lines
   where entry_id = p_entry_id;

  v_diff := v_debit - v_credit;

  if v_diff > 0 then
    select id
      into v_line_id
      from public.journal_lines
     where entry_id = p_entry_id
       and credit_amount > 0
     order by credit_amount desc, created_at asc
     limit 1;

    if v_line_id is not null then
      update public.journal_lines
         set credit_amount = credit_amount + v_diff,
             updated_at = now()
       where id = v_line_id;
    end if;
  elsif v_diff < 0 then
    select id
      into v_line_id
      from public.journal_lines
     where entry_id = p_entry_id
       and debit_amount > 0
     order by debit_amount desc, created_at asc
     limit 1;

    if v_line_id is not null then
      update public.journal_lines
         set debit_amount = debit_amount + abs(v_diff),
             updated_at = now()
       where id = v_line_id;
    end if;
  end if;

  select coalesce(sum(debit_amount), 0), coalesce(sum(credit_amount), 0)
    into v_debit, v_credit
    from public.journal_lines
   where entry_id = p_entry_id;

  update public.journal_entries
     set total_debit = v_debit,
         total_credit = v_credit,
         updated_at = now()
   where id = p_entry_id;
end;
$$;

do $$
declare
  v_entry_id uuid;
begin
  if exists (select 1 from pg_trigger where tgrelid = 'public.sales_payments'::regclass and tgname = 'trg_sales_payments_validate_integrity') then
    alter table public.sales_payments disable trigger trg_sales_payments_validate_integrity;
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.sales_payments'::regclass and tgname = 'trg_sales_payments_change') then
    alter table public.sales_payments disable trigger trg_sales_payments_change;
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.purchase_payments'::regclass and tgname = 'trg_purchase_payments_validate_integrity') then
    alter table public.purchase_payments disable trigger trg_purchase_payments_validate_integrity;
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.purchase_payments'::regclass and tgname = 'trg_purchase_payments_change') then
    alter table public.purchase_payments disable trigger trg_purchase_payments_change;
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.sales_invoices'::regclass and tgname = 'trg_sales_invoices_change') then
    alter table public.sales_invoices disable trigger trg_sales_invoices_change;
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.purchase_invoices'::regclass and tgname = 'trg_purchase_invoices_change') then
    alter table public.purchase_invoices disable trigger trg_purchase_invoices_change;
  end if;

  update public.sales_payments
     set amount = public.clp_round(amount),
         net_amount = case
           when tax_treatment = 'tax_included' then public.clp_round(public.clp_round(amount) / 1.19)
           else public.clp_round(amount)
         end,
         iva_amount = case
           when tax_treatment = 'tax_included' then public.clp_round(amount) - public.clp_round(public.clp_round(amount) / 1.19)
           else 0
         end,
         updated_at = now()
   where amount <> public.clp_round(amount)
      or net_amount <> public.clp_round(net_amount)
      or iva_amount <> public.clp_round(iva_amount);

  update public.purchase_payments
     set amount = public.clp_round(amount),
         updated_at = now()
   where amount <> public.clp_round(amount);

  with payment_totals as (
    select invoice_id, public.clp_round(sum(amount)) as paid_amount
      from public.sales_payments
     where deleted_at is null
     group by invoice_id
  ), normalized as (
    select si.id,
           public.clp_round(si.total) as total,
           coalesce(pt.paid_amount, 0) as paid_amount,
           si.tax_treatment
      from public.sales_invoices si
      left join payment_totals pt on pt.invoice_id = si.id
  )
  update public.sales_invoices si
     set total = n.total,
         subtotal = n.total,
         net_amount = case
           when n.tax_treatment = 'tax_included' and n.total <> 0 then public.clp_round(n.total / 1.19)
           else n.total
         end,
         iva_amount = case
           when n.tax_treatment = 'tax_included' and n.total <> 0 then n.total - public.clp_round(n.total / 1.19)
           else 0
         end,
         paid_amount = n.paid_amount,
         balance = greatest(n.total - n.paid_amount, 0),
         discount_amount = public.clp_round(si.discount_amount),
         updated_at = now()
    from normalized n
   where n.id = si.id;

  with payment_totals as (
    select invoice_id, public.clp_round(sum(amount)) as paid_amount
      from public.purchase_payments
     where deleted_at is null
     group by invoice_id
  ), normalized as (
    select pi.id,
           public.clp_round(pi.total) as total,
           coalesce(pt.paid_amount, 0) as paid_amount,
           pi.tax_treatment
      from public.purchase_invoices pi
      left join payment_totals pt on pt.invoice_id = pi.id
  )
  update public.purchase_invoices pi
     set total = n.total,
         subtotal = case
           when n.tax_treatment = 'tax_included' and n.total <> 0 then public.clp_round(n.total / 1.19)
           else n.total
         end,
         net_amount = case
           when n.tax_treatment = 'tax_included' and n.total <> 0 then public.clp_round(n.total / 1.19)
           else n.total
         end,
         tax = case
           when n.tax_treatment = 'tax_included' and n.total <> 0 then n.total - public.clp_round(n.total / 1.19)
           else 0
         end,
         iva_amount = case
           when n.tax_treatment = 'tax_included' and n.total <> 0 then n.total - public.clp_round(n.total / 1.19)
           else 0
         end,
         paid_amount = n.paid_amount,
         balance = greatest(n.total - n.paid_amount, 0),
         discount_amount = public.clp_round(pi.discount_amount),
         updated_at = now()
    from normalized n
   where n.id = pi.id;

  for v_entry_id in
    select id
      from public.journal_entries
     where source_module in ('sales_invoices', 'purchase_invoices', 'sales_payments', 'purchase_payments')
       and (
         total_debit <> public.clp_round(total_debit)
         or total_credit <> public.clp_round(total_credit)
         or exists (
           select 1
             from public.journal_lines jl
            where jl.entry_id = journal_entries.id
              and (
                jl.debit_amount <> public.clp_round(jl.debit_amount)
                or jl.credit_amount <> public.clp_round(jl.credit_amount)
              )
         )
       )
  loop
    perform public.normalize_journal_entry_to_clp(v_entry_id);
  end loop;

  if exists (select 1 from pg_trigger where tgrelid = 'public.sales_payments'::regclass and tgname = 'trg_sales_payments_validate_integrity') then
    alter table public.sales_payments enable trigger trg_sales_payments_validate_integrity;
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.sales_payments'::regclass and tgname = 'trg_sales_payments_change') then
    alter table public.sales_payments enable trigger trg_sales_payments_change;
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.purchase_payments'::regclass and tgname = 'trg_purchase_payments_validate_integrity') then
    alter table public.purchase_payments enable trigger trg_purchase_payments_validate_integrity;
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.purchase_payments'::regclass and tgname = 'trg_purchase_payments_change') then
    alter table public.purchase_payments enable trigger trg_purchase_payments_change;
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.sales_invoices'::regclass and tgname = 'trg_sales_invoices_change') then
    alter table public.sales_invoices enable trigger trg_sales_invoices_change;
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.purchase_invoices'::regclass and tgname = 'trg_purchase_invoices_change') then
    alter table public.purchase_invoices enable trigger trg_purchase_invoices_change;
  end if;
exception
  when others then
    if exists (select 1 from pg_trigger where tgrelid = 'public.sales_payments'::regclass and tgname = 'trg_sales_payments_validate_integrity') then
      alter table public.sales_payments enable trigger trg_sales_payments_validate_integrity;
    end if;
    if exists (select 1 from pg_trigger where tgrelid = 'public.sales_payments'::regclass and tgname = 'trg_sales_payments_change') then
      alter table public.sales_payments enable trigger trg_sales_payments_change;
    end if;
    if exists (select 1 from pg_trigger where tgrelid = 'public.purchase_payments'::regclass and tgname = 'trg_purchase_payments_validate_integrity') then
      alter table public.purchase_payments enable trigger trg_purchase_payments_validate_integrity;
    end if;
    if exists (select 1 from pg_trigger where tgrelid = 'public.purchase_payments'::regclass and tgname = 'trg_purchase_payments_change') then
      alter table public.purchase_payments enable trigger trg_purchase_payments_change;
    end if;
    if exists (select 1 from pg_trigger where tgrelid = 'public.sales_invoices'::regclass and tgname = 'trg_sales_invoices_change') then
      alter table public.sales_invoices enable trigger trg_sales_invoices_change;
    end if;
    if exists (select 1 from pg_trigger where tgrelid = 'public.purchase_invoices'::regclass and tgname = 'trg_purchase_invoices_change') then
      alter table public.purchase_invoices enable trigger trg_purchase_invoices_change;
    end if;
    raise;
end $$;

alter table public.sales_invoices
  drop constraint if exists sales_invoices_clp_whole_amounts,
  add constraint sales_invoices_clp_whole_amounts check (
    subtotal = public.clp_round(subtotal)
    and iva_amount = public.clp_round(iva_amount)
    and total = public.clp_round(total)
    and paid_amount = public.clp_round(paid_amount)
    and balance = public.clp_round(balance)
    and net_amount = public.clp_round(net_amount)
    and discount_amount = public.clp_round(discount_amount)
  );

alter table public.purchase_invoices
  drop constraint if exists purchase_invoices_clp_whole_amounts,
  add constraint purchase_invoices_clp_whole_amounts check (
    subtotal = public.clp_round(subtotal)
    and tax = public.clp_round(tax)
    and iva_amount = public.clp_round(iva_amount)
    and total = public.clp_round(total)
    and paid_amount = public.clp_round(paid_amount)
    and balance = public.clp_round(balance)
    and net_amount = public.clp_round(net_amount)
    and discount_amount = public.clp_round(discount_amount)
  );

alter table public.sales_payments
  drop constraint if exists sales_payments_clp_whole_amounts,
  add constraint sales_payments_clp_whole_amounts check (
    amount = public.clp_round(amount)
    and net_amount = public.clp_round(net_amount)
    and iva_amount = public.clp_round(iva_amount)
  );

alter table public.purchase_payments
  drop constraint if exists purchase_payments_clp_whole_amounts,
  add constraint purchase_payments_clp_whole_amounts check (
    amount = public.clp_round(amount)
  );
