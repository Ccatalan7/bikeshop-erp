-- Payroll settlement ledger:
-- - recognize salary obligations when a voucher is confirmed
-- - support dated partial payments
-- - support employee advances and later allocation to payroll
-- - keep cash-flow timing based on the real money-movement date
-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-06-07
-- Deployment verification: live schema checks passed and Braulio pgTAP scenario passed 9/9 in a rollback transaction

create table if not exists public.payroll_vouchers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  voucher_number text not null,
  period_start date not null,
  period_end date not null,
  period_label text,
  total_hours numeric(10,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  employee_count integer not null default 0,
  status text not null default 'draft',
  paid_at timestamp with time zone,
  paid_by uuid references auth.users(id),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.payroll_voucher_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  voucher_id uuid references public.payroll_vouchers(id) on delete cascade not null,
  employee_id uuid references public.employees(id) on delete restrict not null,
  employee_name text not null,
  worked_hours numeric(10,2) not null default 0,
  overtime_hours numeric(10,2) not null default 0,
  hourly_rate numeric(10,2) not null default 0,
  overtime_rate numeric(10,2) not null default 0,
  regular_amount numeric(12,2) not null default 0,
  overtime_amount numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  payment_method text default 'transfer',
  payment_method_id uuid references public.payment_methods(id),
  payment_account_id uuid references public.accounts(id),
  is_included boolean not null default true,
  expense_id uuid references public.expenses(id),
  salary_account_id uuid references public.accounts(id),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$
begin
  alter table public.payroll_vouchers
    drop constraint if exists payroll_vouchers_status_check;
  alter table public.payroll_vouchers
    add constraint payroll_vouchers_status_check
    check (status in ('draft', 'confirmed', 'partial', 'paid', 'voided'));
exception
  when undefined_table then null;
end $$;

create index if not exists idx_payroll_vouchers_tenant
  on public.payroll_vouchers(tenant_id);
create index if not exists idx_payroll_vouchers_status
  on public.payroll_vouchers(status);
create index if not exists idx_payroll_vouchers_period
  on public.payroll_vouchers(period_start, period_end);
create index if not exists idx_payroll_voucher_lines_voucher
  on public.payroll_voucher_lines(voucher_id);
create index if not exists idx_payroll_voucher_lines_employee
  on public.payroll_voucher_lines(employee_id);

create table if not exists public.employee_advances (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  employee_id uuid references public.employees(id) on delete restrict not null,
  amount numeric(14,2) not null check (amount > 0),
  amount_applied numeric(14,2) not null default 0 check (amount_applied >= 0),
  payment_method_id uuid references public.payment_methods(id),
  payment_account_id uuid references public.accounts(id),
  paid_at timestamp with time zone not null,
  reference text,
  notes text,
  status text not null default 'open'
    check (status in ('open', 'partially_applied', 'applied', 'voided')),
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  check (amount_applied <= amount + 0.01)
);

create table if not exists public.employee_advance_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  advance_id uuid references public.employee_advances(id) on delete cascade not null,
  voucher_line_id uuid references public.payroll_voucher_lines(id) on delete cascade not null,
  amount numeric(14,2) not null check (amount > 0),
  applied_at timestamp with time zone not null default now(),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_employee_advances_employee_status
  on public.employee_advances(tenant_id, employee_id, status);
create index if not exists idx_employee_advances_paid_at
  on public.employee_advances(tenant_id, paid_at);
create index if not exists idx_employee_advance_allocations_advance
  on public.employee_advance_allocations(advance_id);
create index if not exists idx_employee_advance_allocations_line
  on public.employee_advance_allocations(voucher_line_id);

alter table public.payroll_vouchers enable row level security;
alter table public.payroll_voucher_lines enable row level security;
alter table public.employee_advances enable row level security;
alter table public.employee_advance_allocations enable row level security;

drop policy if exists payroll_vouchers_select on public.payroll_vouchers;
drop policy if exists payroll_vouchers_insert on public.payroll_vouchers;
drop policy if exists payroll_vouchers_update on public.payroll_vouchers;
drop policy if exists payroll_vouchers_delete on public.payroll_vouchers;
create policy payroll_vouchers_select on public.payroll_vouchers
  for select to authenticated using (tenant_id = public.user_tenant_id());
create policy payroll_vouchers_insert on public.payroll_vouchers
  for insert to authenticated with check (tenant_id = public.user_tenant_id());
create policy payroll_vouchers_update on public.payroll_vouchers
  for update to authenticated using (tenant_id = public.user_tenant_id());
create policy payroll_vouchers_delete on public.payroll_vouchers
  for delete to authenticated using (tenant_id = public.user_tenant_id());

drop policy if exists payroll_voucher_lines_select on public.payroll_voucher_lines;
drop policy if exists payroll_voucher_lines_insert on public.payroll_voucher_lines;
drop policy if exists payroll_voucher_lines_update on public.payroll_voucher_lines;
drop policy if exists payroll_voucher_lines_delete on public.payroll_voucher_lines;
create policy payroll_voucher_lines_select on public.payroll_voucher_lines
  for select to authenticated using (tenant_id = public.user_tenant_id());
create policy payroll_voucher_lines_insert on public.payroll_voucher_lines
  for insert to authenticated with check (tenant_id = public.user_tenant_id());
create policy payroll_voucher_lines_update on public.payroll_voucher_lines
  for update to authenticated using (tenant_id = public.user_tenant_id());
create policy payroll_voucher_lines_delete on public.payroll_voucher_lines
  for delete to authenticated using (tenant_id = public.user_tenant_id());

drop policy if exists employee_advances_select on public.employee_advances;
drop policy if exists employee_advances_insert on public.employee_advances;
drop policy if exists employee_advances_update on public.employee_advances;
drop policy if exists employee_advances_delete on public.employee_advances;
create policy employee_advances_select on public.employee_advances
  for select to authenticated using (tenant_id = public.user_tenant_id());
create policy employee_advances_insert on public.employee_advances
  for insert to authenticated with check (tenant_id = public.user_tenant_id());
create policy employee_advances_update on public.employee_advances
  for update to authenticated using (tenant_id = public.user_tenant_id());
create policy employee_advances_delete on public.employee_advances
  for delete to authenticated using (tenant_id = public.user_tenant_id());

drop policy if exists employee_advance_allocations_select on public.employee_advance_allocations;
drop policy if exists employee_advance_allocations_insert on public.employee_advance_allocations;
drop policy if exists employee_advance_allocations_update on public.employee_advance_allocations;
drop policy if exists employee_advance_allocations_delete on public.employee_advance_allocations;
create policy employee_advance_allocations_select on public.employee_advance_allocations
  for select to authenticated using (tenant_id = public.user_tenant_id());
create policy employee_advance_allocations_insert on public.employee_advance_allocations
  for insert to authenticated with check (tenant_id = public.user_tenant_id());
create policy employee_advance_allocations_update on public.employee_advance_allocations
  for update to authenticated using (tenant_id = public.user_tenant_id());
create policy employee_advance_allocations_delete on public.employee_advance_allocations
  for delete to authenticated using (tenant_id = public.user_tenant_id());

create or replace function public.validate_employee_advance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expected_applied numeric(14,2);
  v_expected_status text;
begin
  if tg_op = 'UPDATE'
     and (new.tenant_id is distinct from old.tenant_id
       or new.employee_id is distinct from old.employee_id) then
    raise exception 'No se puede cambiar el trabajador de un anticipo existente';
  end if;
  if tg_op = 'UPDATE' and old.status = 'voided' and new.status <> 'voided' then
    raise exception 'No se puede reactivar un anticipo anulado';
  end if;
  if tg_op = 'UPDATE' and new.status = 'voided'
     and exists (
       select 1 from public.employee_advance_allocations aa
        where aa.advance_id = new.id
     ) then
    raise exception 'Primero revierte las imputaciones del anticipo';
  end if;
  if new.paid_at > now() + interval '5 minutes' then
    raise exception 'La fecha del anticipo no puede estar en el futuro';
  end if;
  if not exists (
    select 1 from public.employees e
     where e.id = new.employee_id and e.tenant_id = new.tenant_id
  ) then raise exception 'El trabajador no pertenece al tenant del anticipo'; end if;
  if new.payment_method_id is null or not exists (
    select 1 from public.payment_methods pm
     where pm.id = new.payment_method_id and pm.tenant_id = new.tenant_id
  ) then raise exception 'El método de pago no pertenece al tenant del anticipo'; end if;
  if new.payment_account_id is not null and not exists (
    select 1 from public.accounts a
     where a.id = new.payment_account_id and a.tenant_id = new.tenant_id
  ) then raise exception 'La cuenta de pago no pertenece al tenant del anticipo'; end if;

  select coalesce(sum(amount), 0)
    into v_expected_applied
    from public.employee_advance_allocations
   where advance_id = new.id;
  v_expected_status := case
    when new.status = 'voided' then 'voided'
    when v_expected_applied <= 0 then 'open'
    when v_expected_applied + 0.01 >= new.amount then 'applied'
    else 'partially_applied'
  end;
  if abs(new.amount_applied - v_expected_applied) > 0.01
     or new.status <> v_expected_status then
    raise exception 'El saldo y estado del anticipo se calculan desde sus imputaciones';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_employee_advances_validate on public.employee_advances;
create trigger trg_employee_advances_validate
  before insert or update on public.employee_advances
  for each row execute procedure public.validate_employee_advance();

create or replace function public.validate_employee_advance_allocation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_advance record;
  v_line record;
  v_other_allocations numeric(14,2);
  v_other_line_allocations numeric(14,2);
  v_cash_paid numeric(14,2);
begin
  if tg_op = 'UPDATE'
     and (new.tenant_id is distinct from old.tenant_id
       or new.advance_id is distinct from old.advance_id
       or new.voucher_line_id is distinct from old.voucher_line_id) then
    raise exception 'No se pueden cambiar los vínculos de una imputación existente';
  end if;

  select tenant_id, employee_id, amount, status
    into v_advance
    from public.employee_advances
   where id = new.advance_id
   for update;
  select l.tenant_id, l.employee_id, l.total_amount, l.expense_id,
         v.status as voucher_status, v.period_end
    into v_line
    from public.payroll_voucher_lines l
    join public.payroll_vouchers v on v.id = l.voucher_id
   where l.id = new.voucher_line_id
   for update of l;

  if v_advance.tenant_id is null or v_line.tenant_id is null
     or v_advance.tenant_id <> new.tenant_id
     or v_line.tenant_id <> new.tenant_id then
    raise exception 'La imputación debe permanecer dentro del mismo tenant';
  end if;
  if v_advance.employee_id <> v_line.employee_id then
    raise exception 'El anticipo y la línea de nómina deben pertenecer al mismo trabajador';
  end if;
  if v_advance.status = 'voided' then
    raise exception 'No se puede imputar un anticipo anulado';
  end if;
  if v_line.voucher_status not in ('confirmed', 'partial') or v_line.expense_id is null then
    raise exception 'La nómina debe estar confirmada antes de imputar anticipos';
  end if;
  if new.applied_at < v_line.period_end::timestamp with time zone then
    raise exception 'La imputación no puede ser anterior al cierre del período';
  end if;
  if new.applied_at > now() + interval '5 minutes' then
    raise exception 'La fecha de imputación no puede estar en el futuro';
  end if;

  select coalesce(sum(amount), 0)
    into v_other_allocations
    from public.employee_advance_allocations
   where advance_id = new.advance_id
     and id is distinct from new.id;
  if v_other_allocations + new.amount > v_advance.amount + 0.01 then
    raise exception 'Las imputaciones exceden el saldo disponible del anticipo';
  end if;

  select coalesce(sum(amount), 0)
    into v_other_line_allocations
    from public.employee_advance_allocations
   where voucher_line_id = new.voucher_line_id
     and id is distinct from new.id;
  select coalesce(sum(amount), 0)
    into v_cash_paid
    from public.expense_payments
   where expense_id = v_line.expense_id;
  if v_cash_paid + v_other_line_allocations + new.amount > v_line.total_amount + 0.01 then
    raise exception 'La imputación excede el saldo pendiente de la línea de nómina';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_employee_advance_allocations_validate
  on public.employee_advance_allocations;
create trigger trg_employee_advance_allocations_validate
  before insert or update on public.employee_advance_allocations
  for each row execute procedure public.validate_employee_advance_allocation();

create or replace function public.create_employee_advance_journal_entry(p_advance_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_advance record;
  v_advance_account_id uuid;
  v_cash_account record;
  v_entry_id uuid := gen_random_uuid();
  v_description text;
begin
  select ea.*, concat_ws(' ', e.first_name, e.last_name) as employee_name
    into v_advance
    from public.employee_advances ea
    join public.employees e on e.id = ea.employee_id
   where ea.id = p_advance_id;

  if not found or v_advance.status = 'voided' then
    return;
  end if;

  delete from public.journal_entries
   where source_module = 'employee_advances'
     and source_reference = p_advance_id::text;

  v_advance_account_id := public.ensure_account(
    v_advance.tenant_id,
    '1135',
    'Anticipos al Personal',
    'asset',
    'currentAsset',
    'Anticipos de remuneraciones pendientes de imputar',
    null
  );

  if v_advance.payment_account_id is not null then
    select id, code, name into v_cash_account
      from public.accounts
     where id = v_advance.payment_account_id
       and tenant_id = v_advance.tenant_id;
  elsif v_advance.payment_method_id is not null then
    select a.id, a.code, a.name into v_cash_account
      from public.payment_methods pm
      join public.accounts a on a.id = pm.account_id
     where pm.id = v_advance.payment_method_id
       and pm.tenant_id = v_advance.tenant_id;
  end if;

  if v_cash_account.id is null then
    raise exception 'El anticipo requiere una cuenta de pago válida';
  end if;

  v_description := format('Anticipo de sueldo - %s', v_advance.employee_name);

  insert into public.journal_entries (
    id, tenant_id, entry_number, entry_date, description, type,
    source_module, source_reference, status, total_debit, total_credit
  ) values (
    v_entry_id, v_advance.tenant_id,
    public.get_next_document_number(v_advance.tenant_id, 'journal_entry'),
    v_advance.paid_at, v_description, 'payment',
    'employee_advances', v_advance.id::text, 'posted',
    v_advance.amount, v_advance.amount
  );

  insert into public.journal_lines (
    tenant_id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount
  )
  select v_advance.tenant_id, v_entry_id, a.id, a.code, a.name,
         v_description, v_advance.amount, 0
    from public.accounts a
   where a.id = v_advance_account_id;

  insert into public.journal_lines (
    tenant_id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount
  ) values (
    v_advance.tenant_id, v_entry_id, v_cash_account.id, v_cash_account.code,
    v_cash_account.name, v_description, 0, v_advance.amount
  );
end;
$$;

create or replace function public.create_employee_advance_allocation_journal_entry(p_allocation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allocation record;
  v_advance_account_id uuid;
  v_salary_payable_account_id uuid;
  v_entry_id uuid := gen_random_uuid();
  v_description text;
begin
  select aa.*, ea.employee_id, l.employee_name
    into v_allocation
    from public.employee_advance_allocations aa
    join public.employee_advances ea on ea.id = aa.advance_id
    join public.payroll_voucher_lines l on l.id = aa.voucher_line_id
   where aa.id = p_allocation_id;

  if not found then
    return;
  end if;

  delete from public.journal_entries
   where source_module = 'employee_advance_allocations'
     and source_reference = p_allocation_id::text;

  v_advance_account_id := public.ensure_account(
    v_allocation.tenant_id, '1135', 'Anticipos al Personal', 'asset',
    'currentAsset', 'Anticipos de remuneraciones pendientes de imputar', null
  );
  v_salary_payable_account_id := public.ensure_account(
    v_allocation.tenant_id, '2106', 'Sueldos por Pagar', 'liability',
    'currentLiability', 'Obligaciones pendientes de pago por remuneraciones', null
  );
  v_description := format('Aplicación de anticipo - %s', v_allocation.employee_name);

  insert into public.journal_entries (
    id, tenant_id, entry_number, entry_date, description, type,
    source_module, source_reference, status, total_debit, total_credit
  ) values (
    v_entry_id, v_allocation.tenant_id,
    public.get_next_document_number(v_allocation.tenant_id, 'journal_entry'),
    v_allocation.applied_at, v_description, 'payroll',
    'employee_advance_allocations', v_allocation.id::text, 'posted',
    v_allocation.amount, v_allocation.amount
  );

  insert into public.journal_lines (
    tenant_id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount
  )
  select v_allocation.tenant_id, v_entry_id, a.id, a.code, a.name,
         v_description, v_allocation.amount, 0
    from public.accounts a
   where a.id = v_salary_payable_account_id;

  insert into public.journal_lines (
    tenant_id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount
  )
  select v_allocation.tenant_id, v_entry_id, a.id, a.code, a.name,
         v_description, 0, v_allocation.amount
    from public.accounts a
   where a.id = v_advance_account_id;
end;
$$;

create or replace function public.recalculate_employee_advance(p_advance_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount numeric(14,2);
  v_applied numeric(14,2);
  v_status text;
begin
  select amount, status into v_amount, v_status
    from public.employee_advances
   where id = p_advance_id
   for update;

  if not found or v_status = 'voided' then
    return;
  end if;

  select coalesce(sum(amount), 0) into v_applied
    from public.employee_advance_allocations
   where advance_id = p_advance_id;

  if v_applied > v_amount + 0.01 then
    raise exception 'Las imputaciones exceden el monto del anticipo';
  end if;

  update public.employee_advances
     set amount_applied = v_applied,
         status = case
           when v_applied <= 0 then 'open'
           when v_applied + 0.01 >= v_amount then 'applied'
           else 'partially_applied'
         end,
         updated_at = now()
   where id = p_advance_id;
end;
$$;

create or replace function public.handle_employee_advance_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.journal_entries
     where source_module = 'employee_advances'
       and source_reference = old.id::text;
    return old;
  end if;

  if tg_op = 'INSERT'
     or new.amount is distinct from old.amount
     or new.paid_at is distinct from old.paid_at
     or new.payment_method_id is distinct from old.payment_method_id
     or new.payment_account_id is distinct from old.payment_account_id
     or (new.status = 'voided') is distinct from (old.status = 'voided') then
    perform public.create_employee_advance_journal_entry(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_employee_advances_change on public.employee_advances;
create trigger trg_employee_advances_change
  after insert or update or delete on public.employee_advances
  for each row execute procedure public.handle_employee_advance_change();

create or replace function public.handle_employee_advance_allocation_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense_id uuid;
begin
  if tg_op = 'DELETE' then
    delete from public.journal_entries
     where source_module = 'employee_advance_allocations'
       and source_reference = old.id::text;
    select expense_id into v_expense_id
      from public.payroll_voucher_lines where id = old.voucher_line_id;
    perform public.recalculate_employee_advance(old.advance_id);
    perform public.recalculate_expense_totals(v_expense_id);
    return old;
  end if;

  if tg_op = 'UPDATE' then
    delete from public.journal_entries
     where source_module = 'employee_advance_allocations'
       and source_reference = old.id::text;
    perform public.recalculate_employee_advance(old.advance_id);
  end if;

  perform public.create_employee_advance_allocation_journal_entry(new.id);
  perform public.recalculate_employee_advance(new.advance_id);
  select expense_id into v_expense_id
    from public.payroll_voucher_lines where id = new.voucher_line_id;
  perform public.recalculate_expense_totals(v_expense_id);
  return new;
end;
$$;

drop trigger if exists trg_employee_advance_allocations_change
  on public.employee_advance_allocations;
create trigger trg_employee_advance_allocations_change
  after insert or update or delete on public.employee_advance_allocations
  for each row execute procedure public.handle_employee_advance_allocation_change();

create or replace function public.recalculate_expense_totals(p_expense_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expense record;
  v_subtotal numeric(14,2) := 0;
  v_tax numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_cash_paid numeric(14,2) := 0;
  v_allocated numeric(14,2) := 0;
  v_paid numeric(14,2) := 0;
  v_latest_payment_date timestamp with time zone;
  v_payment_method_count integer := 0;
  v_payment_account_count integer := 0;
  v_single_payment_method_id uuid;
  v_single_payment_account_id uuid;
  v_category_id uuid;
  v_line_account_id uuid;
  v_line_account_code text;
  v_line_account_name text;
  v_category_name text;
  v_category_desc text;
  v_prev_payment text;
  v_new_payment text;
  v_is_payroll boolean := false;
begin
  if p_expense_id is null then return; end if;

  select e.id, e.tenant_id, e.category_id, e.issue_date,
         lower(coalesce(e.payment_status, 'pending')) as payment_status,
         lower(coalesce(e.posting_status, 'draft')) as posting_status,
         e.paid_at, e.payment_method_id, e.payment_account_id,
         (
           e.notes like 'Pago de salario%'
           or e.notes like 'Salario:%'
           or e.reference like 'Semana %'
         ) as is_payroll
    into v_expense
    from public.expenses e
   where e.id = p_expense_id
   for update;
  if not found then return; end if;
  v_is_payroll := coalesce(v_expense.is_payroll, false);

  select coalesce(sum(subtotal), 0), coalesce(sum(tax_amount), 0),
         coalesce(sum(total), 0)
    into v_subtotal, v_tax, v_total
    from public.expense_lines
   where expense_id = p_expense_id;

  select coalesce(sum(amount), 0), max(payment_date)
    into v_cash_paid, v_latest_payment_date
    from public.expense_payments
   where expense_id = p_expense_id;

  select coalesce(sum(aa.amount), 0),
         greatest(v_latest_payment_date, max(aa.applied_at))
    into v_allocated, v_latest_payment_date
    from public.employee_advance_allocations aa
    join public.payroll_voucher_lines l on l.id = aa.voucher_line_id
   where l.expense_id = p_expense_id;

  v_paid := v_cash_paid + v_allocated;

  if v_cash_paid > 0 then
    select count(distinct ep.payment_method_id),
           (array_agg(distinct ep.payment_method_id))[1]
      into v_payment_method_count, v_single_payment_method_id
      from public.expense_payments ep
     where ep.expense_id = p_expense_id and ep.amount > 0
       and ep.payment_method_id is not null;
    select count(distinct ep.payment_account_id),
           (array_agg(distinct ep.payment_account_id))[1]
      into v_payment_account_count, v_single_payment_account_id
      from public.expense_payments ep
     where ep.expense_id = p_expense_id and ep.amount > 0
       and ep.payment_account_id is not null;
  end if;

  v_prev_payment := v_expense.payment_status;
  v_category_id := v_expense.category_id;
  if v_category_id is null then
    select el.account_id, el.account_code, el.account_name
      into v_line_account_id, v_line_account_code, v_line_account_name
      from public.expense_lines el
     where el.expense_id = p_expense_id
     order by el.line_index, el.created_at
     limit 1;
    if v_line_account_id is not null then
      v_category_name := public.get_expense_category_name_for_account(
        v_line_account_code, v_line_account_name
      );
      v_category_desc := coalesce(v_line_account_name, v_category_name);
      v_category_id := public.ensure_expense_category(
        v_expense.tenant_id, v_category_name, v_category_desc, v_line_account_id
      );
    end if;
  end if;

  if not v_is_payroll
     and v_prev_payment = 'paid' and v_expense.payment_method_id is not null
     and v_paid = 0 and v_total > 0 then
    v_new_payment := 'paid';
    v_paid := v_total;
  elsif v_total = 0 then
    v_new_payment := v_prev_payment;
  elsif v_paid <= 0 then
    v_new_payment := case when v_prev_payment = 'scheduled'
      then 'scheduled' else 'pending' end;
  elsif v_paid + 0.01 < v_total then
    v_new_payment := 'partial';
  else
    v_new_payment := 'paid';
  end if;

  update public.expenses
     set subtotal = v_subtotal,
         tax_amount = v_tax,
         total_amount = v_total,
         amount_paid = v_paid,
         balance = greatest(v_total - v_paid, 0),
         category_id = coalesce(category_id, v_category_id),
         payment_method_id = case
           when v_payment_method_count = 1 and payment_method_id is null
             then v_single_payment_method_id else payment_method_id end,
         payment_account_id = case
           when v_payment_account_count = 1 and payment_account_id is null
             then v_single_payment_account_id else payment_account_id end,
         payment_status = case
           when v_expense.posting_status = 'void' then payment_status
           when v_prev_payment = 'void' then 'void'
           else v_new_payment end,
         paid_at = case
           when v_expense.posting_status <> 'void' and v_total > 0
             and v_paid + 0.01 >= v_total
             then coalesce(v_latest_payment_date, paid_at, issue_date, now())
           when v_new_payment <> 'paid' then null
           else paid_at end,
         updated_at = now()
   where id = p_expense_id;
end;
$$;

create or replace function public.ensure_payroll_line_expense(p_line_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line record;
  v_expense_id uuid;
  v_expense_number text;
  v_salary_account_id uuid;
  v_reference text;
begin
  select l.*, v.period_end, v.period_label, v.voucher_number
    into v_line
    from public.payroll_voucher_lines l
    join public.payroll_vouchers v on v.id = l.voucher_id
   where l.id = p_line_id
     and l.tenant_id = public.user_tenant_id();
  if not found then raise exception 'Línea de nómina no encontrada'; end if;
  if v_line.expense_id is not null then return v_line.expense_id; end if;

  select coalesce(v_line.salary_account_id, e.salary_account_id)
    into v_salary_account_id
    from public.employees e
   where e.id = v_line.employee_id
     and e.tenant_id = v_line.tenant_id;
  if v_salary_account_id is null then
    raise exception 'El trabajador % no tiene cuenta contable de sueldo', v_line.employee_name;
  end if;

  update public.payroll_voucher_lines
     set salary_account_id = v_salary_account_id, updated_at = now()
   where id = p_line_id;

  v_expense_number := public.generate_expense_number();
  v_reference := format('Semana %s - %s',
    coalesce(v_line.period_label, ''), v_line.voucher_number);

  insert into public.expenses (
    tenant_id, expense_number, document_type, subtotal, tax_amount,
    total_amount, issue_date, reference, notes, posting_status,
    payment_status, created_by
  ) values (
    v_line.tenant_id, v_expense_number, 'ticket', v_line.total_amount, 0,
    v_line.total_amount, v_line.period_end::timestamp with time zone,
    v_reference, format('Pago de salario: %s', v_line.employee_name),
    'posted', 'pending', auth.uid()
  ) returning id into v_expense_id;

  update public.payroll_voucher_lines
     set expense_id = v_expense_id, updated_at = now()
   where id = p_line_id;

  insert into public.expense_lines (
    tenant_id, expense_id, line_index, account_id, description,
    quantity, unit_price, tax_amount, total
  ) values (
    v_line.tenant_id, v_expense_id, 0, v_salary_account_id,
    format('Salario: %s', v_line.employee_name), 1, v_line.total_amount, 0,
    v_line.total_amount
  );

  -- The shared expense-line trigger creates journals before recalculating the
  -- new line total. Recreate once the payroll obligation has its final amount.
  perform public.create_expense_journal_entry(v_expense_id);

  return v_expense_id;
end;
$$;

create or replace function public.refresh_payroll_voucher_status(p_voucher_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_due numeric(14,2);
  v_settled numeric(14,2);
  v_latest timestamp with time zone;
  v_status text;
begin
  select coalesce(sum(l.total_amount), 0),
         coalesce(sum(
           coalesce((select sum(ep.amount) from public.expense_payments ep
                     where ep.expense_id = l.expense_id), 0)
           + coalesce((select sum(aa.amount) from public.employee_advance_allocations aa
                       where aa.voucher_line_id = l.id), 0)
         ), 0),
         max(greatest(
           (select max(ep.payment_date) from public.expense_payments ep
             where ep.expense_id = l.expense_id),
           (select max(aa.applied_at) from public.employee_advance_allocations aa
             where aa.voucher_line_id = l.id)
         ))
    into v_due, v_settled, v_latest
    from public.payroll_voucher_lines l
   where l.voucher_id = p_voucher_id and l.is_included = true;

  v_status := case
    when v_due > 0 and v_settled + 0.01 >= v_due then 'paid'
    when v_settled > 0 then 'partial'
    else 'confirmed'
  end;

  update public.payroll_vouchers
     set status = v_status,
         paid_at = case when v_status = 'paid' then coalesce(v_latest, now()) else null end,
         paid_by = case when v_settled > 0 then coalesce(auth.uid(), paid_by) else null end,
         updated_at = now()
   where id = p_voucher_id
     and tenant_id = public.user_tenant_id();
  return v_status;
end;
$$;

create or replace function public.confirm_payroll_voucher(p_voucher_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_voucher record;
  v_line record;
begin
  select * into v_voucher
    from public.payroll_vouchers
   where id = p_voucher_id and tenant_id = public.user_tenant_id()
   for update;
  if not found then raise exception 'Nómina no encontrada'; end if;
  if v_voucher.status <> 'draft' then
    raise exception 'Solo una nómina en borrador puede confirmarse';
  end if;

  for v_line in
    select id from public.payroll_voucher_lines
     where voucher_id = p_voucher_id and is_included = true and total_amount > 0
  loop
    perform public.ensure_payroll_line_expense(v_line.id);
  end loop;

  update public.payroll_vouchers
     set status = 'confirmed', updated_at = now()
   where id = p_voucher_id;
  return true;
end;
$$;

create or replace function public.register_employee_advance(
  p_employee_id uuid,
  p_amount numeric,
  p_payment_method_id uuid,
  p_payment_account_id uuid default null,
  p_paid_at timestamp with time zone default now(),
  p_reference text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_id uuid;
begin
  if p_amount <= 0 then raise exception 'El monto debe ser mayor a cero'; end if;
  if p_paid_at > now() + interval '5 minutes' then
    raise exception 'La fecha del anticipo no puede estar en el futuro';
  end if;
  if not exists (
    select 1 from public.employees
     where id = p_employee_id and tenant_id = v_tenant_id
  ) then raise exception 'Trabajador no encontrado'; end if;
  if not exists (
    select 1 from public.payment_methods
     where id = p_payment_method_id and tenant_id = v_tenant_id
  ) then raise exception 'Método de pago no válido'; end if;

  insert into public.employee_advances (
    tenant_id, employee_id, amount, payment_method_id, payment_account_id,
    paid_at, reference, notes, created_by
  ) values (
    v_tenant_id, p_employee_id, p_amount, p_payment_method_id,
    p_payment_account_id, p_paid_at, p_reference, p_notes, auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;

drop function if exists public.pay_payroll_voucher(uuid, jsonb);

create or replace function public.pay_payroll_voucher(
  p_voucher_id uuid,
  p_payment_splits jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_voucher record;
  v_line record;
  v_splits jsonb;
  v_split jsonb;
  v_kind text;
  v_amount numeric(14,2);
  v_remaining numeric(14,2);
  v_batch_total numeric(14,2);
  v_method_id uuid;
  v_account_id uuid;
  v_advance record;
  v_payment_date timestamp with time zone;
  v_reference text;
  v_notes text;
begin
  select * into v_voucher
    from public.payroll_vouchers
   where id = p_voucher_id and tenant_id = public.user_tenant_id()
   for update;
  if not found then raise exception 'Nómina no encontrada'; end if;
  if v_voucher.status not in ('confirmed', 'partial') then
    raise exception 'La nómina debe estar confirmada o parcialmente pagada';
  end if;

  for v_line in
    select * from public.payroll_voucher_lines
     where voucher_id = p_voucher_id and is_included = true and total_amount > 0
  loop
    perform public.ensure_payroll_line_expense(v_line.id);
    select * into v_line from public.payroll_voucher_lines where id = v_line.id;

    select greatest(v_line.total_amount
      - coalesce((select sum(amount) from public.expense_payments
                  where expense_id = v_line.expense_id), 0)
      - coalesce((select sum(amount) from public.employee_advance_allocations
                  where voucher_line_id = v_line.id), 0), 0)
      into v_remaining;

    if p_payment_splits is null then
      v_splits := jsonb_build_array(jsonb_build_object(
        'kind', 'payment',
        'payment_method_id', v_line.payment_method_id,
        'payment_account_id', v_line.payment_account_id,
        'amount', v_remaining,
        'payment_date', now()
      ));
    else
      v_splits := p_payment_splits -> v_line.id::text;
    end if;

    if v_splits is null then continue; end if;
    if jsonb_typeof(v_splits) <> 'array' then
      raise exception 'Movimientos inválidos para %', v_line.employee_name;
    end if;

    v_batch_total := 0;
    for v_split in select * from jsonb_array_elements(v_splits)
    loop
      v_amount := coalesce(nullif(v_split->>'amount', '')::numeric, 0);
      if v_amount <= 0 then continue; end if;
      v_batch_total := v_batch_total + v_amount;
      if v_batch_total > v_remaining + 0.01 then
        raise exception 'Los movimientos exceden el saldo de %', v_line.employee_name;
      end if;

      v_kind := coalesce(nullif(v_split->>'kind', ''), 'payment');
      v_reference := nullif(v_split->>'reference', '');
      v_notes := nullif(v_split->>'notes', '');

      if v_kind = 'advance' then
        select * into v_advance
          from public.employee_advances
         where id = nullif(v_split->>'advance_id', '')::uuid
           and tenant_id = v_line.tenant_id
           and employee_id = v_line.employee_id
           and status in ('open', 'partially_applied')
         for update;
        if not found then raise exception 'Anticipo no válido para %', v_line.employee_name; end if;
        if v_amount > v_advance.amount - v_advance.amount_applied + 0.01 then
          raise exception 'La imputación excede el saldo disponible del anticipo';
        end if;
        insert into public.employee_advance_allocations (
          tenant_id, advance_id, voucher_line_id, amount, applied_at, notes, created_by
        ) values (
          v_line.tenant_id, v_advance.id, v_line.id, v_amount,
          v_voucher.period_end::timestamp with time zone, v_notes, auth.uid()
        );
      elsif v_kind = 'payment' then
        v_method_id := coalesce(
          nullif(v_split->>'payment_method_id', '')::uuid,
          v_line.payment_method_id
        );
        v_account_id := coalesce(
          nullif(v_split->>'payment_account_id', '')::uuid,
          v_line.payment_account_id
        );
        if v_method_id is null then
          raise exception 'Falta método de pago para %', v_line.employee_name;
        end if;
        v_payment_date := coalesce(
          nullif(v_split->>'payment_date', '')::timestamp with time zone, now()
        );
        if v_payment_date > now() + interval '5 minutes' then
          raise exception 'La fecha de pago no puede estar en el futuro';
        end if;
        if v_payment_date < v_voucher.period_end::timestamp with time zone then
          raise exception 'Un movimiento anterior al cierre del período debe registrarse como anticipo';
        end if;
        insert into public.expense_payments (
          tenant_id, expense_id, payment_method_id, payment_account_id,
          amount, payment_date, reference, notes
        ) values (
          v_line.tenant_id, v_line.expense_id, v_method_id, v_account_id,
          v_amount, v_payment_date,
          coalesce(v_reference, format('Nómina %s', v_voucher.voucher_number)),
          coalesce(v_notes, format('Pago de salario: %s', v_line.employee_name))
        );
      else
        raise exception 'Tipo de movimiento de nómina no válido: %', v_kind;
      end if;
    end loop;
    perform public.recalculate_expense_totals(v_line.expense_id);
  end loop;

  perform public.refresh_payroll_voucher_status(p_voucher_id);
  return true;
end;
$$;

create or replace function public.pay_payroll_voucher(p_voucher_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.pay_payroll_voucher(p_voucher_id, null);
  return true;
end;
$$;

create or replace function public.revert_payroll_payment(p_voucher_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line record;
begin
  if not exists (
    select 1 from public.payroll_vouchers
     where id = p_voucher_id and tenant_id = public.user_tenant_id()
       and status in ('partial', 'paid')
  ) then raise exception 'La nómina no tiene movimientos para revertir'; end if;

  for v_line in
    select id, expense_id from public.payroll_voucher_lines
     where voucher_id = p_voucher_id
  loop
    delete from public.employee_advance_allocations where voucher_line_id = v_line.id;
    delete from public.expense_payments where expense_id = v_line.expense_id;
    perform public.recalculate_expense_totals(v_line.expense_id);
  end loop;
  perform public.refresh_payroll_voucher_status(p_voucher_id);
  return true;
end;
$$;

create or replace function public.revert_payroll_to_draft(p_voucher_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line record;
begin
  if not exists (
    select 1 from public.payroll_vouchers
     where id = p_voucher_id and tenant_id = public.user_tenant_id()
       and status = 'confirmed'
  ) then raise exception 'Solo una nómina confirmada sin pagos puede volver a borrador'; end if;

  for v_line in
    select id, expense_id from public.payroll_voucher_lines
     where voucher_id = p_voucher_id and expense_id is not null
  loop
    if exists (select 1 from public.expense_payments where expense_id = v_line.expense_id)
       or exists (select 1 from public.employee_advance_allocations where voucher_line_id = v_line.id) then
      raise exception 'La nómina tiene movimientos registrados';
    end if;
    update public.payroll_voucher_lines set expense_id = null where id = v_line.id;
    delete from public.expenses where id = v_line.expense_id;
  end loop;

  update public.payroll_vouchers
     set status = 'draft', paid_at = null, paid_by = null, updated_at = now()
   where id = p_voucher_id;
  return true;
end;
$$;

create or replace function public.get_payroll_voucher_line_settlements(p_voucher_id uuid)
returns table (
  line_id uuid,
  cash_paid numeric(14,2),
  advances_applied numeric(14,2),
  settled_amount numeric(14,2),
  balance numeric(14,2)
)
language sql
security definer
set search_path = public
as $$
  select l.id,
         coalesce((select sum(ep.amount) from public.expense_payments ep
                   where ep.expense_id = l.expense_id), 0)::numeric(14,2),
         coalesce((select sum(aa.amount) from public.employee_advance_allocations aa
                   where aa.voucher_line_id = l.id), 0)::numeric(14,2),
         least(l.total_amount,
           coalesce((select sum(ep.amount) from public.expense_payments ep
                     where ep.expense_id = l.expense_id), 0)
           + coalesce((select sum(aa.amount) from public.employee_advance_allocations aa
                       where aa.voucher_line_id = l.id), 0)
         )::numeric(14,2),
         greatest(l.total_amount
           - coalesce((select sum(ep.amount) from public.expense_payments ep
                       where ep.expense_id = l.expense_id), 0)
           - coalesce((select sum(aa.amount) from public.employee_advance_allocations aa
                       where aa.voucher_line_id = l.id), 0), 0)::numeric(14,2)
    from public.payroll_voucher_lines l
   where l.voucher_id = p_voucher_id
     and l.tenant_id = public.user_tenant_id();
$$;

grant execute on function public.confirm_payroll_voucher(uuid) to authenticated;
grant execute on function public.register_employee_advance(uuid, numeric, uuid, uuid, timestamp with time zone, text, text) to authenticated;
grant execute on function public.pay_payroll_voucher(uuid) to authenticated;
grant execute on function public.pay_payroll_voucher(uuid, jsonb) to authenticated;
grant execute on function public.revert_payroll_payment(uuid) to authenticated;
grant execute on function public.revert_payroll_to_draft(uuid) to authenticated;
grant execute on function public.get_payroll_voucher_line_settlements(uuid) to authenticated;

revoke execute on function public.create_employee_advance_journal_entry(uuid)
  from public, authenticated;
revoke execute on function public.create_employee_advance_allocation_journal_entry(uuid)
  from public, authenticated;
revoke execute on function public.recalculate_employee_advance(uuid)
  from public, authenticated;
revoke execute on function public.ensure_payroll_line_expense(uuid)
  from public, authenticated;
revoke execute on function public.refresh_payroll_voucher_status(uuid)
  from public, authenticated;

create or replace function public.get_income_statement_data(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_is_cash_flow boolean default false
)
returns table (
  category text,
  category_label text,
  account_code text,
  account_name text,
  amount numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_is_cash_flow then
    return query
    select 'operatingIncome'::text, 'Ingresos de Efectivo'::text,
           '4000'::text, 'Cobros de Clientes'::text,
           coalesce(sum(sp.amount), 0)::numeric(14,2)
      from public.sales_payments sp
     where sp.date >= p_start_date and sp.date <= p_end_date
       and sp.tenant_id = public.user_tenant_id()
    union all
    select 'costOfGoodsSold'::text, 'Egresos de Efectivo - Proveedores'::text,
           '5000'::text, 'Pagos a Proveedores'::text,
           coalesce(sum(pp.amount), 0)::numeric(14,2)
      from public.purchase_payments pp
     where pp.date >= p_start_date and pp.date <= p_end_date
       and pp.tenant_id = public.user_tenant_id()
    union all
    select a.category, 'Egresos de Efectivo - Gastos'::text, a.code, a.name,
           coalesce(sum(ep.amount * el.total / nullif(e.total_amount, 0)), 0)::numeric(14,2)
      from public.expense_payments ep
      join public.expenses e on e.id = ep.expense_id
      join public.expense_lines el on el.expense_id = e.id
      join public.accounts a on a.id = el.account_id
     where ep.payment_date >= p_start_date and ep.payment_date <= p_end_date
       and ep.tenant_id = public.user_tenant_id()
       and e.posting_status <> 'void' and a.type = 'expense'
     group by a.category, a.code, a.name
    union all
    select a.category, 'Egresos de Efectivo - Gastos'::text, a.code, a.name,
           coalesce(sum(el.total), 0)::numeric(14,2)
      from public.expenses e
      join public.expense_lines el on el.expense_id = e.id
      join public.accounts a on a.id = el.account_id
     where e.payment_status = 'paid'
       and e.paid_at >= p_start_date and e.paid_at <= p_end_date
       and e.tenant_id = public.user_tenant_id() and a.type = 'expense'
       and not exists (select 1 from public.expense_payments ep where ep.expense_id = e.id)
       and not exists (
         select 1
           from public.employee_advance_allocations aa
           join public.payroll_voucher_lines l on l.id = aa.voucher_line_id
          where l.expense_id = e.id
       )
     group by a.category, a.code, a.name
    union all
    select 'operatingExpense'::text, 'Egresos de Efectivo - Gastos'::text,
           '1135'::text, 'Anticipos al Personal'::text,
           coalesce(sum(ea.amount), 0)::numeric(14,2)
      from public.employee_advances ea
     where ea.paid_at >= p_start_date and ea.paid_at <= p_end_date
       and ea.tenant_id = public.user_tenant_id() and ea.status <> 'voided';
  else
    return query
    select a.category,
           case a.category
             when 'operatingIncome' then 'Ingresos Operacionales'
             when 'nonOperatingIncome' then 'Ingresos No Operacionales'
             when 'costOfGoodsSold' then 'Costo de Ventas'
             when 'operatingExpense' then 'Gastos Operacionales'
             when 'financialExpense' then 'Gastos Financieros'
             when 'taxExpense' then 'Impuestos'
             else a.category end,
           a.code, a.name,
           case when a.type = 'income'
             then coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
             when a.type = 'expense'
             then coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
             else 0 end::numeric(14,2)
      from public.accounts a
      join public.journal_lines jl on jl.account_id = a.id
       and jl.tenant_id = public.user_tenant_id()
      join public.journal_entries je on je.id = jl.entry_id
       and je.entry_date >= p_start_date and je.entry_date <= p_end_date
       and je.status = 'posted' and je.tenant_id = public.user_tenant_id()
     where a.type in ('income', 'expense') and a.is_active = true
       and a.tenant_id = public.user_tenant_id()
     group by a.id, a.code, a.name, a.type, a.category
    having coalesce(sum(jl.debit_amount), 0) <> 0
        or coalesce(sum(jl.credit_amount), 0) <> 0
     order by a.code;
  end if;
end;
$$;

create or replace function public.get_income_expense_timeseries(
  p_months integer default 12,
  p_is_cash_flow boolean default false
)
returns table (
  period_start date, period_end date, income numeric(14,2), expense numeric(14,2)
)
language sql
security definer
set search_path = public
as $$
  with month_windows as (
    select date_trunc('month', current_timestamp)
      - make_interval(months => m.month_index) as period_start
      from generate_series(0, greatest(p_months, 1) - 1) as m(month_index)
  )
  select mw.period_start::date,
         (mw.period_start + interval '1 month' - interval '1 day')::date,
         coalesce(case when p_is_cash_flow then (
           select sum(amount) from public.sales_payments sp
            where sp.date >= mw.period_start and sp.date < mw.period_start + interval '1 month'
              and sp.tenant_id = public.user_tenant_id()
         ) else (
           select sum(coalesce(jl.credit_amount,0)-coalesce(jl.debit_amount,0))
             from public.journal_lines jl
             join public.journal_entries je on je.id=jl.entry_id
             join public.accounts a on a.id=jl.account_id
            where je.status='posted' and a.type='income'
              and je.entry_date >= mw.period_start and je.entry_date < mw.period_start + interval '1 month'
              and je.tenant_id=public.user_tenant_id()
              and jl.tenant_id=public.user_tenant_id()
              and a.tenant_id=public.user_tenant_id()
         ) end, 0)::numeric(14,2),
         coalesce(case when p_is_cash_flow then (
           coalesce((select sum(amount) from public.purchase_payments pp
             where pp.date >= mw.period_start and pp.date < mw.period_start + interval '1 month'
               and pp.tenant_id=public.user_tenant_id()),0)
           + coalesce((select sum(amount) from public.expense_payments ep
             where ep.payment_date >= mw.period_start and ep.payment_date < mw.period_start + interval '1 month'
               and ep.tenant_id=public.user_tenant_id()),0)
           + coalesce((select sum(e.total_amount) from public.expenses e
             where e.payment_status='paid'
               and e.paid_at >= mw.period_start and e.paid_at < mw.period_start + interval '1 month'
               and e.tenant_id=public.user_tenant_id()
               and not exists (select 1 from public.expense_payments ep where ep.expense_id=e.id)
               and not exists (
                 select 1
                   from public.employee_advance_allocations aa
                   join public.payroll_voucher_lines l on l.id=aa.voucher_line_id
                  where l.expense_id=e.id
               )),0)
           + coalesce((select sum(amount) from public.employee_advances ea
             where ea.paid_at >= mw.period_start and ea.paid_at < mw.period_start + interval '1 month'
               and ea.tenant_id=public.user_tenant_id() and ea.status <> 'voided'),0)
         ) else (
           select sum(coalesce(jl.debit_amount,0)-coalesce(jl.credit_amount,0))
             from public.journal_lines jl
             join public.journal_entries je on je.id=jl.entry_id
             join public.accounts a on a.id=jl.account_id
            where je.status='posted' and a.type='expense'
              and je.entry_date >= mw.period_start and je.entry_date < mw.period_start + interval '1 month'
              and je.tenant_id=public.user_tenant_id()
              and jl.tenant_id=public.user_tenant_id()
              and a.tenant_id=public.user_tenant_id()
         ) end,0)::numeric(14,2)
    from month_windows mw order by mw.period_start;
$$;

create or replace function public.get_income_expense_daily_timeseries(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_is_cash_flow boolean default false
)
returns table (
  period_start date, period_end date, income numeric(14,2), expense numeric(14,2)
)
language sql
security definer
set search_path = public
as $$
  with day_windows as (
    select (date_trunc('day', p_start_date)
      + make_interval(days => d.day_index))::date as period_start
      from generate_series(0, extract(days from (p_end_date-p_start_date))::integer) d(day_index)
  )
  select dw.period_start, dw.period_start,
         coalesce(case when p_is_cash_flow then (
           select sum(amount) from public.sales_payments sp
            where sp.date >= dw.period_start and sp.date < dw.period_start + interval '1 day'
              and sp.tenant_id=public.user_tenant_id()
         ) else (
           select sum(coalesce(jl.credit_amount,0)-coalesce(jl.debit_amount,0))
             from public.journal_lines jl join public.journal_entries je on je.id=jl.entry_id
             join public.accounts a on a.id=jl.account_id
            where je.status='posted' and a.type='income'
              and je.entry_date >= dw.period_start and je.entry_date < dw.period_start + interval '1 day'
              and je.tenant_id=public.user_tenant_id() and jl.tenant_id=public.user_tenant_id()
              and a.tenant_id=public.user_tenant_id()
         ) end,0)::numeric(14,2),
         coalesce(case when p_is_cash_flow then (
           coalesce((select sum(amount) from public.purchase_payments pp
             where pp.date >= dw.period_start and pp.date < dw.period_start + interval '1 day'
               and pp.tenant_id=public.user_tenant_id()),0)
           + coalesce((select sum(amount) from public.expense_payments ep
             where ep.payment_date >= dw.period_start and ep.payment_date < dw.period_start + interval '1 day'
               and ep.tenant_id=public.user_tenant_id()),0)
           + coalesce((select sum(e.total_amount) from public.expenses e
             where e.payment_status='paid'
               and e.paid_at >= dw.period_start and e.paid_at < dw.period_start + interval '1 day'
               and e.tenant_id=public.user_tenant_id()
               and not exists (select 1 from public.expense_payments ep where ep.expense_id=e.id)
               and not exists (
                 select 1
                   from public.employee_advance_allocations aa
                   join public.payroll_voucher_lines l on l.id=aa.voucher_line_id
                  where l.expense_id=e.id
               )),0)
           + coalesce((select sum(amount) from public.employee_advances ea
             where ea.paid_at >= dw.period_start and ea.paid_at < dw.period_start + interval '1 day'
               and ea.tenant_id=public.user_tenant_id() and ea.status <> 'voided'),0)
         ) else (
           select sum(coalesce(jl.debit_amount,0)-coalesce(jl.credit_amount,0))
             from public.journal_lines jl join public.journal_entries je on je.id=jl.entry_id
             join public.accounts a on a.id=jl.account_id
            where je.status='posted' and a.type='expense'
              and je.entry_date >= dw.period_start and je.entry_date < dw.period_start + interval '1 day'
              and je.tenant_id=public.user_tenant_id() and jl.tenant_id=public.user_tenant_id()
              and a.tenant_id=public.user_tenant_id()
         ) end,0)::numeric(14,2)
    from day_windows dw order by dw.period_start;
$$;

grant execute on function public.get_income_statement_data(timestamp with time zone, timestamp with time zone, boolean) to authenticated;
grant execute on function public.get_income_expense_timeseries(integer, boolean) to authenticated;
grant execute on function public.get_income_expense_daily_timeseries(timestamp with time zone, timestamp with time zone, boolean) to authenticated;
