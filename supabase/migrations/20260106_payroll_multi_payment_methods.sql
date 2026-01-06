-- Enable paying a payroll voucher with multiple payment methods per employee.
-- Implementation strategy:
-- - Create the salary expense (posted) and credit the expense liability (2105) via create_expense_journal_entry()
-- - Record one or more expense_payments rows per employee to represent the cash/bank splits
--   (each payment generates its own journal entry)

-- -----------------------------------------------------------------------------
-- SAFETY FIXES (Jan 2026)
-- - Ensure expenses are tenant-scoped unique by (tenant_id, expense_number)
-- - Sync expense_number_seq to existing expense numbers to avoid duplicates
-- -----------------------------------------------------------------------------

do $$
begin
  -- Drop accidental global unique constraint if present
  if exists (
    select 1
      from information_schema.table_constraints
     where constraint_schema = 'public'
       and table_name = 'expenses'
       and constraint_name = 'expenses_expense_number_key'
  ) then
    alter table public.expenses drop constraint expenses_expense_number_key;
  end if;

  -- Ensure tenant-scoped uniqueness exists
  if not exists (
    select 1
      from pg_constraint c
     where c.conrelid = 'public.expenses'::regclass
       and c.contype = 'u'
       and pg_get_constraintdef(c.oid) like '%(tenant_id, expense_number)%'
  ) then
    alter table public.expenses
      add constraint expenses_expense_number_tenant_key unique (tenant_id, expense_number);
  end if;
exception
  when undefined_table then null;
  when others then
    raise notice '⚠️ expenses unique constraint fix: %', sqlerrm;
end $$;

create sequence if not exists expense_number_seq;

do $$
declare
  v_max bigint;
begin
  select coalesce(
    max((regexp_replace(expense_number, '^GTO-', ''))::bigint),
    0
  )
  into v_max
  from public.expenses
  where expense_number ~ '^GTO-[0-9]+$';

  perform setval('expense_number_seq', v_max, true);
exception
  when undefined_table then null;
  when others then
    raise notice '⚠️ expense_number_seq sync failed: %', sqlerrm;
end $$;

-- Repair any expenses that were zeroed-out because expense_lines.total defaulted to 0.
-- This targets payroll-created expenses (reference starts with 'Semana ') only.
do $$
declare
  r record;
begin
  -- Fix line totals where unit_price implies a value but total stayed 0
  update public.expense_lines
     set subtotal = round(quantity * unit_price, 2),
         total = round(quantity * unit_price, 2) + coalesce(tax_amount, 0)
   where total = 0
     and unit_price <> 0
     and expense_id in (
       select id from public.expenses
        where reference ilike 'Semana %'
     );

  -- Recalculate headers
  for r in
    select id
      from public.expenses
     where reference ilike 'Semana %'
       and total_amount = 0
  loop
    perform public.recalculate_expense_totals(r.id);
  end loop;

  -- Fill header payment method/account when payments are unambiguous
  update public.expenses e
     set payment_method_id = ep.payment_method_id
    from (
      select expense_id,
             (array_agg(distinct payment_method_id))[1] as payment_method_id
        from public.expense_payments
       where payment_method_id is not null
         and amount > 0
       group by expense_id
      having count(distinct payment_method_id) = 1
    ) ep
   where e.id = ep.expense_id
     and e.reference ilike 'Semana %'
     and e.payment_method_id is null;

  update public.expenses e
     set payment_account_id = ep.payment_account_id
    from (
      select expense_id,
             (array_agg(distinct payment_account_id))[1] as payment_account_id
        from public.expense_payments
       where payment_account_id is not null
         and amount > 0
       group by expense_id
      having count(distinct payment_account_id) = 1
    ) ep
   where e.id = ep.expense_id
     and e.reference ilike 'Semana %'
     and e.payment_account_id is null;
exception
  when undefined_table then null;
  when others then
    raise notice '⚠️ payroll expense repair failed: %', sqlerrm;
end $$;

create or replace function public.pay_payroll_voucher(
  p_voucher_id uuid
)
returns boolean
security definer
language plpgsql
set search_path = public
as $$
begin
  -- Delegate to the 2-arg version (default: no explicit splits)
  perform public.pay_payroll_voucher(p_voucher_id, null);
  return true;
end;
$$;

grant execute on function public.pay_payroll_voucher(uuid) to authenticated;

create or replace function public.pay_payroll_voucher(
  p_voucher_id uuid,
  p_payment_splits jsonb default null
)
returns boolean
security definer
language plpgsql
set search_path = public
as $$
declare
  v_voucher record;
  line record;
  v_expense_id uuid;
  v_expense_number text;
  v_splits jsonb;
  v_split jsonb;
  v_split_amount numeric(14,2);
  v_total_split numeric(14,2);
  v_method_id uuid;
  v_account_id uuid;
  v_notes text;
  v_reference text;
  v_default_method_id uuid;
  v_default_account_id uuid;
begin
  select *
    into v_voucher
    from public.payroll_vouchers
   where id = p_voucher_id;

  if not found then
    raise exception 'Voucher not found';
  end if;

  if v_voucher.status <> 'pending' then
    raise exception 'Voucher must be in pending status';
  end if;

  for line in
    select *
      from public.payroll_voucher_lines
     where voucher_id = p_voucher_id
       and is_included = true
  loop
    if coalesce(line.total_amount, 0) <= 0 then
      continue;
    end if;

    if line.salary_account_id is null then
      raise exception 'Employee % has missing Salary Account', line.employee_name;
    end if;

    v_reference := format('Semana %s - %s', coalesce(v_voucher.period_label, ''), v_voucher.voucher_number);
    v_notes := format('Pago de salario: %s', line.employee_name);

    -- Determine payment splits (JSON overrides defaults)
    v_splits := null;
    if p_payment_splits is not null and line.id is not null then
      v_splits := p_payment_splits -> (line.id::text);
    end if;

    if v_splits is null then
      v_splits := jsonb_build_array(
        jsonb_build_object(
          'payment_method_id', line.payment_method_id,
          'payment_account_id', line.payment_account_id,
          'amount', line.total_amount
        )
      );
    end if;

    if jsonb_typeof(v_splits) <> 'array' then
      raise exception 'Invalid payment splits for employee %', line.employee_name;
    end if;

    -- Create Expense Header
    v_expense_number := public.generate_expense_number();

    -- If there's only 1 payment method/account, store it in the header for UI convenience.
    select
      nullif((v_splits->0->>'payment_method_id'), '')::uuid,
      nullif((v_splits->0->>'payment_account_id'), '')::uuid
      into v_method_id, v_account_id;

    insert into public.expenses (
      tenant_id,
      expense_number,
      document_type,
      subtotal,
      tax_amount,
      total_amount,
      issue_date,
      reference,
      notes,
      posting_status,
      payment_status,
      payment_method_id,
      payment_account_id,
      created_by
    ) values (
      line.tenant_id,
      v_expense_number,
      'ticket',
      line.total_amount,
      0,
      line.total_amount,
      current_date,
      v_reference,
      v_notes,
      'posted',
      'pending',
      v_method_id,
      v_account_id,
      auth.uid()
    ) returning id into v_expense_id;

    -- Link back to the payroll voucher line (important for delete/revert workflows)
    update public.payroll_voucher_lines
       set expense_id = v_expense_id
     where id = line.id;

    -- Expense line (debit salary expense account)
    insert into public.expense_lines (
      tenant_id,
      expense_id,
      line_index,
      account_id,
      description,
      quantity,
      unit_price,
      tax_amount,
      total
    ) values (
      line.tenant_id,
      v_expense_id,
      0,
      line.salary_account_id,
      format('Salario: %s', line.employee_name),
      1,
      line.total_amount,
      0,
      line.total_amount
    );

    -- Fallback payment method IDs (legacy string support)
    v_default_method_id := line.payment_method_id;
    v_default_account_id := line.payment_account_id;

    if v_default_method_id is null then
      if line.payment_method = 'cash' then
        select pm.id
          into v_default_method_id
          from public.payment_methods pm
         where pm.tenant_id = line.tenant_id
           and (pm.name ilike '%efectivo%' or pm.name ilike '%cash%')
         limit 1;
      else
        select pm.id
          into v_default_method_id
          from public.payment_methods pm
         where pm.tenant_id = line.tenant_id
           and pm.name ilike '%transf%'
         limit 1;
      end if;
    end if;

    v_total_split := 0;

    for v_split in
      select * from jsonb_array_elements(v_splits)
    loop
      v_split_amount := coalesce(nullif(v_split->>'amount', '')::numeric, 0);
      if v_split_amount <= 0 then
        continue;
      end if;

      v_method_id := nullif(v_split->>'payment_method_id', '')::uuid;
      v_account_id := nullif(v_split->>'payment_account_id', '')::uuid;

      if v_method_id is null then
        v_method_id := v_default_method_id;
      end if;

      if v_account_id is null then
        v_account_id := v_default_account_id;
      end if;

      if v_method_id is null then
        raise exception 'Missing payment method for employee %', line.employee_name;
      end if;

      v_total_split := v_total_split + v_split_amount;

      insert into public.expense_payments (
        tenant_id,
        expense_id,
        payment_method_id,
        payment_account_id,
        amount,
        payment_date,
        reference,
        notes
      ) values (
        line.tenant_id,
        v_expense_id,
        v_method_id,
        v_account_id,
        v_split_amount,
        now(),
        v_reference,
        v_notes
      );
    end loop;

    -- Ensure header totals reflect the line totals (defensive)
    perform public.recalculate_expense_totals(v_expense_id);

    if abs(v_total_split - line.total_amount) > 0.01 then
      raise exception 'Payment splits must sum to the line total for employee %', line.employee_name;
    end if;
  end loop;

  update public.payroll_vouchers
     set status = 'paid',
         paid_at = now(),
         paid_by = auth.uid(),
         updated_at = now()
   where id = p_voucher_id;

  return true;
end;
$$;

grant execute on function public.pay_payroll_voucher(uuid, jsonb) to authenticated;
