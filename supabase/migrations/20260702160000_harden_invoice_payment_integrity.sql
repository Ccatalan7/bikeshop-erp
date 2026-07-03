-- Harden invoice payment writes against double submits, overpayments, and
-- stale payment ledger state. Mirrors the app-side idempotency key now sent by
-- purchase and sales payment forms.

alter table public.sales_payments
  add column if not exists idempotency_key text,
  add column if not exists notes text,
  add column if not exists deleted_at timestamp with time zone,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null,
  add column if not exists tax_treatment text not null default 'no_tax',
  add column if not exists net_amount numeric(12,2) not null default 0,
  add column if not exists iva_amount numeric(12,2) not null default 0,
  add column if not exists updated_at timestamp with time zone not null default now();

alter table public.purchase_payments
  add column if not exists idempotency_key text,
  add column if not exists deleted_at timestamp with time zone,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null;

create unique index if not exists idx_sales_payments_tenant_idempotency_key
  on public.sales_payments(tenant_id, idempotency_key)
  where idempotency_key is not null;

create unique index if not exists idx_purchase_payments_tenant_idempotency_key
  on public.purchase_payments(tenant_id, idempotency_key)
  where idempotency_key is not null;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.sales_payments'::regclass
       and conname = 'sales_payments_amount_positive'
  ) then
    alter table public.sales_payments
      add constraint sales_payments_amount_positive check (amount > 0) not valid;
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.purchase_payments'::regclass
       and conname = 'purchase_payments_amount_positive'
  ) then
    alter table public.purchase_payments
      add constraint purchase_payments_amount_positive check (amount > 0) not valid;
  end if;
end $$;

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
begin
  if TG_OP = 'DELETE' then
    return OLD;
  end if;

  if NEW.deleted_at is not null then
    NEW.amount := round(coalesce(NEW.amount, 0), 2);
    return NEW;
  end if;

  if NEW.invoice_id is null then
    raise exception 'El pago debe pertenecer a una factura de venta.';
  end if;

  v_amount := round(coalesce(NEW.amount, 0), 2);
  if v_amount <= 0 then
    raise exception 'El monto del pago debe ser mayor a cero.';
  end if;
  NEW.amount := v_amount;

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

  select coalesce(sum(amount), 0)
    into v_existing_paid
    from public.sales_payments
   where invoice_id = NEW.invoice_id
     and deleted_at is null
     and id is distinct from NEW.id;

  v_remaining := round(greatest(coalesce(v_invoice.total, 0) - v_existing_paid, 0), 2);

  if v_amount > v_remaining then
    raise exception 'El pago excede el saldo pendiente de la factura de venta. Saldo pendiente: %, monto enviado: %.',
      v_remaining, v_amount;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_sales_payments_validate_integrity on public.sales_payments;
create trigger trg_sales_payments_validate_integrity
  before insert or update on public.sales_payments
  for each row execute function public.validate_sales_payment_integrity();

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

  if NEW.deleted_at is not null then
    NEW.amount := round(coalesce(NEW.amount, 0), 2);
    return NEW;
  end if;

  if NEW.invoice_id is null then
    raise exception 'El pago debe pertenecer a una factura de compra.';
  end if;

  v_amount := round(coalesce(NEW.amount, 0), 2);
  if v_amount <= 0 then
    raise exception 'El monto del pago debe ser mayor a cero.';
  end if;
  NEW.amount := v_amount;

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

  select coalesce(sum(amount), 0)
    into v_existing_paid
    from public.purchase_payments
   where invoice_id = NEW.invoice_id
     and deleted_at is null
     and id is distinct from NEW.id;

  v_remaining := round(greatest(coalesce(v_invoice.total, 0) - v_existing_paid, 0), 2);

  if v_amount > v_remaining then
    raise exception 'El pago excede el saldo pendiente de la factura de compra. Saldo pendiente: %, monto enviado: %.',
      v_remaining, v_amount;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_purchase_payments_validate_integrity on public.purchase_payments;
create trigger trg_purchase_payments_validate_integrity
  before insert or update on public.purchase_payments
  for each row execute function public.validate_purchase_payment_integrity();

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
      if v_invoice.status IN ('paid', 'received') then
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

create or replace function public.create_purchase_payment_journal_entry(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment record;
  v_invoice record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_payment_method record;
  v_cash_account_id uuid;
  v_cash_account_code text;
  v_cash_account_name text;
  v_payable_account_id uuid;
  v_payable_account_code text := '2101';
  v_payable_account_name text := 'Cuentas por Pagar Proveedores';
  v_description text;
  v_tenant_id uuid;
begin
  select id, invoice_id, amount, date, payment_method_id, tenant_id, deleted_at
    into v_payment
    from public.purchase_payments
   where id = p_payment_id;

  if not found or v_payment.invoice_id is null or v_payment.deleted_at is not null then
    return;
  end if;

  v_tenant_id := v_payment.tenant_id;

  if v_tenant_id is null then
    raise warning 'create_purchase_payment_journal_entry: No tenant_id on payment %, skipping', v_payment.id;
    return;
  end if;

  select exists (
           select 1
             from public.journal_entries
            where tenant_id = v_tenant_id
              and source_module = 'purchase_payments'
              and source_reference = v_payment.id::text
        )
    into v_exists;

  if v_exists then
    return;
  end if;

  select id,
         invoice_number,
         supplier_name,
         total
    into v_invoice
    from public.purchase_invoices
   where id = v_payment.invoice_id;

  if not found then
    return;
  end if;

  select pm.id, pm.code, pm.name, a.id as account_id, a.code as account_code, a.name as account_name
    into v_payment_method
    from public.payment_methods pm
    join public.accounts a on a.id = pm.account_id
   where pm.id = v_payment.payment_method_id;

  if not found then
    raise exception 'Payment method not found for payment %', v_payment.id;
  end if;

  v_cash_account_id := v_payment_method.account_id;
  v_cash_account_code := v_payment_method.account_code;
  v_cash_account_name := v_payment_method.account_name;

  v_payable_account_id := public.ensure_account(
    v_tenant_id,
    v_payable_account_code,
    v_payable_account_name,
    'liability',
    'currentLiability',
    'Cuentas por pagar a proveedores',
    null
  );

  v_description := format('Pago factura compra %s - %s',
    coalesce(v_invoice.invoice_number, v_invoice.id::text),
    v_payment_method.name
  );

  insert into public.journal_entries (
    id,
    tenant_id,
    entry_number,
    entry_date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    v_tenant_id,
    public.get_next_document_number(v_tenant_id, 'journal_entry'),
    coalesce(v_payment.date, now()),
    v_description,
    'payment',
    'purchase_payments',
    v_payment.id::text,
    'posted',
    v_payment.amount,
    v_payment.amount,
    now(),
    now()
  );

  insert into public.journal_lines (
    id,
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_tenant_id,
    v_entry_id,
    v_payable_account_id,
    v_payable_account_code,
    v_payable_account_name,
    v_description,
    v_payment.amount,
    0,
    now(),
    now()
  );

  insert into public.journal_lines (
    id,
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_tenant_id,
    v_entry_id,
    v_cash_account_id,
    v_cash_account_code,
    v_cash_account_name,
    v_description,
    0,
    v_payment.amount,
    now(),
    now()
  );
end;
$$;

create or replace function public.handle_purchase_payment_change()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    perform public.create_purchase_payment_journal_entry(NEW.id);
    perform public.recalculate_purchase_invoice_payments(NEW.invoice_id);
  elsif TG_OP = 'UPDATE' then
    if NEW.invoice_id is distinct from OLD.invoice_id then
      perform public.recalculate_purchase_invoice_payments(OLD.invoice_id);
    end if;
    perform public.delete_purchase_payment_journal_entry(OLD.id);
    perform public.create_purchase_payment_journal_entry(NEW.id);
    perform public.recalculate_purchase_invoice_payments(NEW.invoice_id);
  elsif TG_OP = 'DELETE' then
    perform public.delete_purchase_payment_journal_entry(OLD.id);
    perform public.recalculate_purchase_invoice_payments(OLD.invoice_id);
  end if;
  return NULL;
end;
$$ language plpgsql;

drop trigger if exists trg_purchase_payments_change on public.purchase_payments;
create trigger trg_purchase_payments_change
  after insert or update or delete on public.purchase_payments
  for each row execute function public.handle_purchase_payment_change();
