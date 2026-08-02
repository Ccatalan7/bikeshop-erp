-- Audited, append-only correction of Payroll payments and advance allocations.
--
-- Deployment status: NOT DEPLOYED. Expand-first: existing clients continue to
-- read v1 settlement evidence and cannot forge reversal command contexts.
-- Existing payment/allocation rows are not rewritten or backfilled.
--
-- Forward behaviour:
--   * the original settlement remains immutable and visible;
--   * one exact compensating movement links to that original;
--   * the compensation posts a balanced journal linked through
--     journal_entries.reversal_of_id;
--   * payroll/expense/advance balances and voucher state are recalculated;
--   * a stable operation key makes retries deterministic;
--   * statement/OCR evidence remains immutable and the v2 read model reports
--     that its resulting settlement was reversed.
--
-- Recovery: hide the UI action and revoke the two reversal RPCs. Preserve all
-- reversal rows, operation receipts and journals permanently. Never roll back
-- by deleting committed correction evidence.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $$
begin
  if to_regprocedure(
    'public.pay_payroll_voucher_v2(uuid,text,bigint,jsonb)'
  ) is null
     or to_regprocedure(
       'public.get_payroll_voucher_settlement_evidence(uuid[])'
     ) is null
     or to_regprocedure(
       'public.begin_expense_accounting_operation(uuid,text,uuid,uuid,text,text,jsonb,jsonb,jsonb,text)'
     ) is null then
    raise exception 'Missing versioned Payroll/accounting prerequisites'
      using errcode = '55000';
  end if;
end
$$;

-- A compensating row preserves both the original settlement and the exact
-- inverse used by every existing SUM-based balance projection.
alter table public.expense_payments
  add column if not exists reversal_of_id uuid,
  add column if not exists reversal_reason text;

alter table public.employee_advance_allocations
  add column if not exists reversal_of_id uuid,
  add column if not exists reversal_reason text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.expense_payments'::regclass
      and constraint_row.conname =
        'expense_payments_tenant_reversal_of_fkey'
  ) then
    alter table public.expense_payments
      add constraint expense_payments_tenant_reversal_of_fkey
      foreign key (tenant_id, reversal_of_id)
      references public.expense_payments(tenant_id, id)
      on delete restrict;
  end if;

  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid =
        'public.employee_advance_allocations'::regclass
      and constraint_row.conname =
        'employee_advance_allocations_tenant_reversal_of_fkey'
  ) then
    alter table public.employee_advance_allocations
      add constraint employee_advance_allocations_tenant_reversal_of_fkey
      foreign key (tenant_id, reversal_of_id)
      references public.employee_advance_allocations(tenant_id, id)
      on delete restrict;
  end if;
end
$$;

create unique index if not exists ux_expense_payments_one_reversal
  on public.expense_payments(tenant_id, reversal_of_id)
  where reversal_of_id is not null;

create unique index if not exists ux_employee_advance_allocations_one_reversal
  on public.employee_advance_allocations(tenant_id, reversal_of_id)
  where reversal_of_id is not null;

alter table public.expense_payments
  drop constraint if exists expense_payments_reversal_shape_check;
alter table public.expense_payments
  add constraint expense_payments_reversal_shape_check
  check (
    (
      reversal_of_id is null
      and reversal_reason is null
      and amount >= 0
    )
    or (
      reversal_of_id is not null
      and amount < 0
      and char_length(btrim(reversal_reason)) between 3 and 1000
    )
  );

alter table public.employee_advance_allocations
  drop constraint if exists employee_advance_allocations_amount_check;
alter table public.employee_advance_allocations
  drop constraint if exists employee_advance_allocations_reversal_shape_check;
alter table public.employee_advance_allocations
  add constraint employee_advance_allocations_reversal_shape_check
  check (
    (
      reversal_of_id is null
      and reversal_reason is null
      and amount > 0
    )
    or (
      reversal_of_id is not null
      and amount < 0
      and char_length(btrim(reversal_reason)) between 3 and 1000
    )
  );

-- Reversal commands use the existing immutable Payroll money receipt and
-- movement link. The original operation is optional because legacy and
-- statement-created settlements predate payroll_money_operations.
alter table public.payroll_money_operations
  add column if not exists reversal_of_operation_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid =
        'public.payroll_money_operations'::regclass
      and constraint_row.conname =
        'payroll_money_operations_tenant_reversal_operation_fkey'
  ) then
    alter table public.payroll_money_operations
      add constraint payroll_money_operations_tenant_reversal_operation_fkey
      foreign key (tenant_id, reversal_of_operation_id)
      references public.payroll_money_operations(tenant_id, id)
      on delete restrict;
  end if;
end
$$;

alter table public.payroll_money_operations
  drop constraint if exists payroll_money_operations_operation_type_check;
alter table public.payroll_money_operations
  add constraint payroll_money_operations_operation_type_check
  check (
    operation_type in (
      'manual_payroll_payment',
      'employee_advance',
      'payroll_settlement_reversal'
    )
  );

alter table public.payroll_money_operations
  drop constraint if exists payroll_money_operations_check;
alter table public.payroll_money_operations
  add constraint payroll_money_operations_check
  check (
    (
      operation_type = 'manual_payroll_payment'
      and voucher_id is not null
      and employee_advance_id is null
      and reversal_of_operation_id is null
    )
    or (
      operation_type = 'employee_advance'
      and voucher_id is null
      and employee_advance_id is not null
      and reversal_of_operation_id is null
    )
    or (
      operation_type = 'payroll_settlement_reversal'
      and voucher_id is not null
      and employee_advance_id is null
    )
  );

alter table public.payroll_money_command_contexts
  drop constraint if exists payroll_money_command_contexts_command_check;
alter table public.payroll_money_command_contexts
  add constraint payroll_money_command_contexts_command_check
  check (
    command in (
      'manual_payment',
      'advance_registration',
      'legacy_reversal',
      'audited_reversal'
    )
  );

alter table public.payroll_statement_command_contexts
  drop constraint if exists payroll_statement_command_contexts_command_check;
alter table public.payroll_statement_command_contexts
  add constraint payroll_statement_command_contexts_command_check
  check (
    command in (
      'import_revision',
      'apply',
      'manual_settlement',
      'audited_reversal'
    )
  );

create or replace function public.guard_reconciled_payroll_voucher_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  voucher_id_value uuid := case
    when tg_table_name = 'payroll_vouchers' then
      case
        when tg_op = 'DELETE' then (to_jsonb(old)->>'id')::uuid
        else (to_jsonb(new)->>'id')::uuid
      end
    when tg_op = 'DELETE'
      then (to_jsonb(old)->>'voucher_id')::uuid
    else (to_jsonb(new)->>'voucher_id')::uuid
  end;
  tenant_id_value uuid := case
    when tg_op = 'DELETE' then (to_jsonb(old)->>'tenant_id')::uuid
    else (to_jsonb(new)->>'tenant_id')::uuid
  end;
  prior_voucher_id_value uuid := case
    when tg_table_name = 'payroll_voucher_lines' and tg_op = 'UPDATE'
      then (to_jsonb(old)->>'voucher_id')::uuid
    else null
  end;
begin
  -- The audited command changes only settlement-derived voucher state. Its
  -- transaction capability is tied to the exact statement import and actor;
  -- authenticated callers cannot create this row directly.
  if exists (
    select 1
    from public.payroll_statement_command_contexts command_context
    join public.payroll_statement_decisions decision
      on decision.import_id = command_context.import_id
     and decision.tenant_id = command_context.tenant_id
     and decision.voucher_id in (
       voucher_id_value,
       prior_voucher_id_value
     )
    where command_context.transaction_id = txid_current()
      and command_context.command = 'audited_reversal'
      and command_context.tenant_id = tenant_id_value
      and command_context.actor_id = auth.uid()
  ) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if (
    exists (
      select 1
      from public.payroll_statement_decisions decision
      where decision.voucher_id in (
        voucher_id_value,
        prior_voucher_id_value
      )
    )
    or exists (
      select 1
      from public.payroll_statement_allocations allocation
      where allocation.voucher_id in (
        voucher_id_value,
        prior_voucher_id_value
      )
    )
  )
  and not exists (
    select 1
    from public.payroll_statement_command_contexts command_context
    join public.payroll_statement_decisions decision
      on decision.import_id = command_context.import_id
     and decision.tenant_id = command_context.tenant_id
     and decision.voucher_id in (
       voucher_id_value,
       prior_voucher_id_value
     )
    where command_context.transaction_id = txid_current()
      and command_context.command = 'apply'
      and command_context.tenant_id = tenant_id_value
  )
  and not (
    tg_table_name = 'payroll_vouchers'
    and tg_op = 'UPDATE'
    and (
      to_jsonb(new) - array[
        'status',
        'paid_at',
        'paid_by',
        'updated_at',
        'reconciliation_version'
      ]::text[]
    ) = (
      to_jsonb(old) - array[
        'status',
        'paid_at',
        'paid_by',
        'updated_at',
        'reconciliation_version'
      ]::text[]
    )
    and exists (
      select 1
      from public.payroll_statement_command_contexts command_context
      join public.payroll_statement_decisions decision
        on decision.import_id = command_context.import_id
       and decision.tenant_id = command_context.tenant_id
       and decision.voucher_id = voucher_id_value
      where command_context.transaction_id = txid_current()
        and command_context.command = 'manual_settlement'
        and command_context.tenant_id = tenant_id_value
    )
  ) then
    raise exception 'payroll_reconciled_voucher_is_immutable'
      using
        errcode = '55000',
        detail = 'Use the audited reconciliation reversal command';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.guard_reconciled_payroll_voucher_mutation()
  from public, anon, authenticated, service_role;

create or replace function public.guard_payroll_expense_payment_balance()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  expense_id_value uuid := case
    when tg_op = 'DELETE' then old.expense_id
    else new.expense_id
  end;
  payment_id_value uuid := case
    when tg_op = 'INSERT' then null
    else old.id
  end;
  tenant_id_value uuid := case
    when tg_op = 'DELETE' then old.tenant_id
    else new.tenant_id
  end;
  line_row record;
  original_row public.expense_payments%rowtype;
  settled_value numeric(14,2);
  audited_reversal boolean := false;
begin
  select
    voucher_line.id,
    voucher_line.tenant_id,
    voucher_line.voucher_id,
    voucher_line.total_amount
  into line_row
  from public.payroll_voucher_lines voucher_line
  where voucher_line.expense_id = expense_id_value;

  if not found then
    if tg_op <> 'DELETE'
       and (
         new.reversal_of_id is not null
         or new.reversal_reason is not null
         or new.amount < 0
       ) then
      raise exception 'payroll_reversal_requires_payroll_expense'
        using errcode = '23514';
    end if;
    if tg_op = 'UPDATE'
       and old.expense_id is distinct from new.expense_id
       and exists (
         select 1
         from public.payroll_voucher_lines voucher_line
         where voucher_line.expense_id = old.expense_id
       ) then
      raise exception 'payroll_payment_expense_link_is_immutable'
        using errcode = '55000';
    end if;
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if line_row.tenant_id <> tenant_id_value then
    raise exception 'payroll_payment_tenant_mismatch'
      using errcode = '23514';
  end if;

  audited_reversal := exists (
    select 1
    from public.payroll_money_command_contexts command_context
    where command_context.transaction_id = txid_current()
      and command_context.tenant_id = tenant_id_value
      and command_context.command = 'audited_reversal'
      and command_context.actor_id = auth.uid()
  );

  if tg_op = 'INSERT'
     and not exists (
       select 1
       from public.payroll_statement_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command = 'apply'
     )
     and not exists (
       select 1
       from public.payroll_money_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command in (
           'manual_payment',
           'audited_reversal'
         )
     ) then
    raise exception 'payroll_money_command_required'
      using errcode = '42501';
  end if;

  if tg_op in ('UPDATE', 'DELETE')
     and exists (
       select 1
       from public.payroll_money_operation_movements movement
       where movement.expense_payment_id = old.id
     ) then
    raise exception 'payroll_money_receipt_movement_is_immutable'
      using
        errcode = '55000',
        detail = 'Use the audited idempotent reversal command';
  end if;

  if tg_op in ('UPDATE', 'DELETE')
     and exists (
       select 1
       from public.payroll_statement_allocations allocation
       where allocation.expense_payment_id = old.id
     ) then
    raise exception 'payroll_reconciled_payment_is_immutable'
      using
        errcode = '55000',
        detail = 'Use the audited reconciliation reversal command';
  end if;

  if tg_op = 'UPDATE'
     and (
       old.reversal_of_id is distinct from new.reversal_of_id
       or old.reversal_reason is distinct from new.reversal_reason
     ) then
    raise exception 'payroll_payment_reversal_identity_is_immutable'
      using errcode = '55000';
  end if;

  if tg_op in ('UPDATE', 'DELETE')
     and not exists (
       select 1
       from public.payroll_money_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command = 'legacy_reversal'
     ) then
    raise exception 'payroll_money_command_required'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  perform voucher.id
  from public.payroll_vouchers voucher
  where voucher.id = line_row.voucher_id
    and voucher.tenant_id = tenant_id_value
  for update;

  perform voucher_line.id
  from public.payroll_voucher_lines voucher_line
  where voucher_line.id = line_row.id
    and voucher_line.tenant_id = tenant_id_value
  for update;

  if tg_op = 'UPDATE'
     and old.expense_id is distinct from new.expense_id then
    raise exception 'payroll_payment_expense_link_is_immutable'
      using errcode = '55000';
  end if;

  if tg_op = 'INSERT' and new.reversal_of_id is not null then
    if not audited_reversal then
      raise exception 'payroll_money_command_required'
        using errcode = '42501';
    end if;

    select payment.*
    into original_row
    from public.expense_payments payment
    where payment.id = new.reversal_of_id
      and payment.tenant_id = tenant_id_value
    for update;

    if not found
       or original_row.expense_id <> new.expense_id
       or original_row.reversal_of_id is not null
       or original_row.amount <= 0
       or new.amount <> -original_row.amount
       or new.payment_method_id is distinct from
          original_row.payment_method_id
       or new.payment_account_id is distinct from
          original_row.payment_account_id
       or exists (
         select 1
         from public.expense_payments reversal
         where reversal.tenant_id = tenant_id_value
           and reversal.reversal_of_id = original_row.id
       ) then
      raise exception 'payroll_payment_reversal_invalid_original'
        using errcode = '23514';
    end if;
  elsif tg_op <> 'DELETE' then
    select
      coalesce(
        (
          select sum(payment.amount)
          from public.expense_payments payment
          where payment.expense_id = expense_id_value
            and payment.id is distinct from payment_id_value
        ),
        0
      )
      + coalesce(
        (
          select sum(allocation.amount)
          from public.employee_advance_allocations allocation
          where allocation.voucher_line_id = line_row.id
        ),
        0
      )
    into settled_value;

    if new.amount <= 0
       or new.reversal_reason is not null
       or settled_value + new.amount
            > line_row.total_amount + 0.01 then
      raise exception 'payroll_expense_payment_exceeds_line_balance'
        using errcode = '23514';
    end if;
  end if;

  update public.payroll_vouchers voucher
  set updated_at = statement_timestamp()
  where voucher.id = line_row.voucher_id
    and voucher.tenant_id = tenant_id_value;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.guard_payroll_expense_payment_balance()
  from public, anon, authenticated, service_role;

create or replace function public.guard_payroll_advance_allocation_evidence()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := case
    when tg_op = 'DELETE' then old.tenant_id
    else new.tenant_id
  end;
  voucher_line_id_value uuid := case
    when tg_op = 'DELETE' then old.voucher_line_id
    else new.voucher_line_id
  end;
  advance_id_value uuid := case
    when tg_op = 'DELETE' then old.advance_id
    else new.advance_id
  end;
  line_row record;
begin
  if tg_op in ('UPDATE', 'DELETE')
     and exists (
       select 1
       from public.payroll_money_operation_movements movement
       where movement.advance_allocation_id = old.id
     ) then
    raise exception 'payroll_money_receipt_movement_is_immutable'
      using
        errcode = '55000',
        detail = 'Use the audited idempotent reversal command';
  end if;

  if tg_op in ('UPDATE', 'DELETE')
     and exists (
       select 1
       from public.payroll_statement_allocations allocation
       where allocation.employee_advance_allocation_id = old.id
     ) then
    raise exception 'payroll_reconciled_advance_allocation_is_immutable'
      using
        errcode = '55000',
        detail = 'Use the audited reconciliation reversal command';
  end if;

  if tg_op = 'UPDATE'
     and (
       old.reversal_of_id is distinct from new.reversal_of_id
       or old.reversal_reason is distinct from new.reversal_reason
     ) then
    raise exception 'payroll_advance_reversal_identity_is_immutable'
      using errcode = '55000';
  end if;

  select
    voucher_line.id,
    voucher_line.tenant_id,
    voucher_line.voucher_id
  into line_row
  from public.payroll_voucher_lines voucher_line
  where voucher_line.id = voucher_line_id_value;

  if not found then
    if tg_op <> 'DELETE'
       and (
         new.reversal_of_id is not null
         or new.reversal_reason is not null
         or new.amount < 0
       ) then
      raise exception 'payroll_reversal_requires_payroll_line'
        using errcode = '23514';
    end if;
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if line_row.tenant_id <> tenant_id_value then
    raise exception 'payroll_advance_allocation_tenant_mismatch'
      using errcode = '23514';
  end if;

  if tg_op = 'INSERT'
     and not exists (
       select 1
       from public.payroll_statement_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command = 'apply'
     )
     and not exists (
       select 1
       from public.payroll_money_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command in (
           'manual_payment',
           'audited_reversal'
         )
     ) then
    raise exception 'payroll_money_command_required'
      using errcode = '42501';
  end if;

  if tg_op in ('UPDATE', 'DELETE')
     and not exists (
       select 1
       from public.payroll_money_command_contexts command_context
       where command_context.transaction_id = txid_current()
         and command_context.tenant_id = tenant_id_value
         and command_context.command = 'legacy_reversal'
     ) then
    raise exception 'payroll_money_command_required'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  perform voucher.id
  from public.payroll_vouchers voucher
  where voucher.id = line_row.voucher_id
    and voucher.tenant_id = tenant_id_value
  for update;

  perform advance.id
  from public.employee_advances advance
  where advance.id = advance_id_value
    and advance.tenant_id = tenant_id_value
  for update;

  perform voucher_line.id
  from public.payroll_voucher_lines voucher_line
  where voucher_line.id = voucher_line_id_value
    and voucher_line.tenant_id = tenant_id_value
  for update;

  update public.payroll_vouchers voucher
  set updated_at = statement_timestamp()
  where voucher.id = line_row.voucher_id
    and voucher.tenant_id = tenant_id_value;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.guard_payroll_advance_allocation_evidence()
  from public, anon, authenticated, service_role;

create or replace function public.validate_employee_advance_allocation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  advance_row record;
  line_row record;
  original_row public.employee_advance_allocations%rowtype;
  other_allocations numeric(14,2);
  other_line_allocations numeric(14,2);
  cash_paid numeric(14,2);
  audited_reversal boolean := false;
begin
  if tg_op = 'UPDATE'
     and (
       new.tenant_id is distinct from old.tenant_id
       or new.advance_id is distinct from old.advance_id
       or new.voucher_line_id is distinct from old.voucher_line_id
     ) then
    raise exception
      'No se pueden cambiar los vínculos de una imputación existente';
  end if;

  select tenant_id, employee_id, amount, status
  into advance_row
  from public.employee_advances
  where id = new.advance_id
  for update;

  select
    voucher_line.tenant_id,
    voucher_line.employee_id,
    voucher_line.total_amount,
    voucher_line.expense_id,
    voucher.status as voucher_status,
    voucher.period_end
  into line_row
  from public.payroll_voucher_lines voucher_line
  join public.payroll_vouchers voucher
    on voucher.id = voucher_line.voucher_id
  where voucher_line.id = new.voucher_line_id
  for update of voucher_line;

  if advance_row.tenant_id is null
     or line_row.tenant_id is null
     or advance_row.tenant_id <> new.tenant_id
     or line_row.tenant_id <> new.tenant_id then
    raise exception 'La imputación debe permanecer dentro del mismo tenant';
  end if;

  if advance_row.employee_id <> line_row.employee_id then
    raise exception
      'El anticipo y la línea de nómina deben pertenecer al mismo trabajador';
  end if;

  if line_row.expense_id is null then
    raise exception 'La nómina debe estar comprometida antes de imputar';
  end if;

  if new.applied_at > now() + interval '5 minutes' then
    raise exception 'La fecha de imputación no puede estar en el futuro';
  end if;

  audited_reversal := exists (
    select 1
    from public.payroll_money_command_contexts command_context
    where command_context.transaction_id = txid_current()
      and command_context.tenant_id = new.tenant_id
      and command_context.command = 'audited_reversal'
      and command_context.actor_id = auth.uid()
  );

  if new.reversal_of_id is not null then
    if not audited_reversal
       or line_row.voucher_status not in ('confirmed', 'partial', 'paid') then
      raise exception 'payroll_advance_reversal_command_required'
        using errcode = '42501';
    end if;

    select allocation.*
    into original_row
    from public.employee_advance_allocations allocation
    where allocation.id = new.reversal_of_id
      and allocation.tenant_id = new.tenant_id
    for update;

    if not found
       or original_row.advance_id <> new.advance_id
       or original_row.voucher_line_id <> new.voucher_line_id
       or original_row.reversal_of_id is not null
       or original_row.amount <= 0
       or new.amount <> -original_row.amount
       or exists (
         select 1
         from public.employee_advance_allocations reversal
         where reversal.tenant_id = new.tenant_id
           and reversal.reversal_of_id = original_row.id
       ) then
      raise exception 'payroll_advance_reversal_invalid_original'
        using errcode = '23514';
    end if;

    return new;
  end if;

  if advance_row.status = 'voided' then
    raise exception 'No se puede imputar un anticipo anulado';
  end if;

  if line_row.voucher_status not in ('confirmed', 'partial') then
    raise exception 'La nómina debe estar confirmada antes de imputar anticipos';
  end if;

  if new.applied_at < line_row.period_end::timestamp with time zone then
    raise exception 'La imputación no puede ser anterior al cierre del período';
  end if;

  select coalesce(sum(allocation.amount), 0)
  into other_allocations
  from public.employee_advance_allocations allocation
  where allocation.advance_id = new.advance_id
    and allocation.id is distinct from new.id;

  if other_allocations + new.amount > advance_row.amount + 0.01 then
    raise exception 'Las imputaciones exceden el saldo disponible del anticipo';
  end if;

  select coalesce(sum(allocation.amount), 0)
  into other_line_allocations
  from public.employee_advance_allocations allocation
  where allocation.voucher_line_id = new.voucher_line_id
    and allocation.id is distinct from new.id;

  select coalesce(sum(payment.amount), 0)
  into cash_paid
  from public.expense_payments payment
  where payment.expense_id = line_row.expense_id;

  if cash_paid + other_line_allocations + new.amount
       > line_row.total_amount + 0.01 then
    raise exception 'La imputación excede el saldo pendiente de la línea de nómina';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_employee_advance_allocation()
  from public, anon, authenticated, service_role;

-- Creates the exact opposite of the original posted payment journal. The
-- original journal and its lines are never updated or deleted.
create or replace function
  public.create_payroll_expense_payment_reversal_journal(
    p_reversal_payment_id uuid
  )
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  reversal_payment public.expense_payments%rowtype;
  original_payment public.expense_payments%rowtype;
  original_journal public.journal_entries%rowtype;
  original_journal_count integer;
  journal_id_value uuid := gen_random_uuid();
  amount_value numeric(14,2);
  debit_value numeric(14,2);
  credit_value numeric(14,2);
  description_value text;
begin
  select payment.*
  into reversal_payment
  from public.expense_payments payment
  where payment.id = p_reversal_payment_id;

  if not found or reversal_payment.reversal_of_id is null then
    raise exception 'payroll_payment_reversal_not_found'
      using errcode = 'P0002';
  end if;

  select payment.*
  into original_payment
  from public.expense_payments payment
  where payment.id = reversal_payment.reversal_of_id
    and payment.tenant_id = reversal_payment.tenant_id;

  if not found
     or original_payment.expense_id <> reversal_payment.expense_id
     or reversal_payment.amount <> -original_payment.amount then
    raise exception 'payroll_payment_reversal_invalid_original'
      using errcode = '23514';
  end if;

  select count(*)::integer
  into original_journal_count
  from public.journal_entries journal_entry
  where journal_entry.tenant_id = reversal_payment.tenant_id
    and journal_entry.source_module = 'expense_payments'
    and (
      journal_entry.source_reference = original_payment.id::text
      or journal_entry.source_document_id = original_payment.id
    );

  if original_journal_count <> 1 then
    raise exception 'payroll_payment_original_journal_is_ambiguous'
      using errcode = '55000';
  end if;

  select journal_entry.*
  into original_journal
  from public.journal_entries journal_entry
  where journal_entry.tenant_id = reversal_payment.tenant_id
    and journal_entry.source_module = 'expense_payments'
    and (
      journal_entry.source_reference = original_payment.id::text
      or journal_entry.source_document_id = original_payment.id
    )
  for update;

  select
    round(coalesce(sum(line.debit_amount), 0), 2),
    round(coalesce(sum(line.credit_amount), 0), 2)
  into debit_value, credit_value
  from public.journal_lines line
  where line.tenant_id = reversal_payment.tenant_id
    and line.entry_id = original_journal.id;

  amount_value := round(abs(reversal_payment.amount), 2);
  if original_journal.status <> 'posted'
     or debit_value <> credit_value
     or debit_value <> amount_value
     or round(original_journal.total_debit, 2) <> amount_value
     or round(original_journal.total_credit, 2) <> amount_value then
    raise exception 'payroll_payment_original_journal_is_invalid'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.journal_entries journal_entry
    where journal_entry.tenant_id = reversal_payment.tenant_id
      and journal_entry.source_module = 'expense_payments'
      and (
        journal_entry.source_reference = reversal_payment.id::text
        or journal_entry.source_document_id = reversal_payment.id
      )
  ) then
    raise exception 'payroll_payment_reversal_journal_already_exists'
      using errcode = '23505';
  end if;

  description_value := format(
    'Reversa de pago de nómina · %s · %s',
    original_journal.entry_number,
    reversal_payment.reversal_reason
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
    operation_id,
    source_document_type,
    source_document_id,
    created_by,
    reversal_of_id,
    created_at,
    updated_at
  ) values (
    journal_id_value,
    reversal_payment.tenant_id,
    public.get_next_document_number(
      reversal_payment.tenant_id,
      'journal_entry'
    ),
    reversal_payment.payment_date,
    description_value,
    'payment_reversal',
    'expense_payments',
    reversal_payment.id::text,
    'posted',
    amount_value,
    amount_value,
    nullif(current_setting('app.inventory_operation_id', true), '')::uuid,
    'expense_payment',
    reversal_payment.id,
    auth.uid(),
    original_journal.id,
    statement_timestamp(),
    statement_timestamp()
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
  )
  select
    gen_random_uuid(),
    line.tenant_id,
    journal_id_value,
    line.account_id,
    line.account_code,
    line.account_name,
    description_value,
    line.credit_amount,
    line.debit_amount,
    statement_timestamp(),
    statement_timestamp()
  from public.journal_lines line
  where line.tenant_id = reversal_payment.tenant_id
    and line.entry_id = original_journal.id
  order by line.id;

  return journal_id_value;
end;
$$;

revoke all on function
  public.create_payroll_expense_payment_reversal_journal(uuid)
  from public, anon, authenticated, service_role;

-- Keep the traced wrapper as the single owner. Only its untraced posting
-- branch changes for a row explicitly shaped as an audited reversal.
create or replace function public.create_expense_payment_journal_entry(
  p_payment_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  payment_row public.expense_payments%rowtype;
  expense_row public.expenses%rowtype;
  operation_text text := nullif(
    current_setting('app.inventory_operation_id', true),
    ''
  );
  operation_id_value uuid;
  owns_trace boolean := false;
begin
  select payment.*
  into payment_row
  from public.expense_payments payment
  where payment.id = p_payment_id;

  if not found then
    perform public.create_expense_payment_journal_entry_untraced(p_payment_id);
    return;
  end if;

  select expense.*
  into expense_row
  from public.expenses expense
  where expense.id = payment_row.expense_id
    and expense.tenant_id = payment_row.tenant_id;

  if not found then
    raise exception 'Expense payment parent is missing'
      using errcode = '23503';
  end if;

  if operation_text is null then
    operation_id_value := public.begin_expense_accounting_operation(
      payment_row.tenant_id,
      'expense_payment',
      payment_row.id,
      expense_row.id,
      'expense_payment',
      case
        when payment_row.reversal_of_id is null then 'journal_rebuild'
        else 'reversal_journal_rebuild'
      end,
      to_jsonb(payment_row),
      to_jsonb(payment_row),
      jsonb_build_object(
        'trace_owner', 'rpc',
        'rpc', 'create_expense_payment_journal_entry',
        'reversal_of_id', payment_row.reversal_of_id
      ),
      'database_rpc'
    );
    owns_trace := true;
  else
    operation_id_value := operation_text::uuid;
  end if;

  if payment_row.reversal_of_id is null then
    perform public.create_expense_payment_journal_entry_untraced(p_payment_id);
  else
    perform public.create_payroll_expense_payment_reversal_journal(
      p_payment_id
    );
  end if;

  if owns_trace then
    perform public.complete_expense_accounting_operation(
      operation_id_value,
      payment_row.tenant_id,
      expense_row.id,
      payment_row.id,
      null,
      null,
      false,
      true,
      false,
      expense_row.expense_number
    );
  end if;
exception
  when others then
    if owns_trace then
      perform set_config('app.inventory_operation_id', '', true);
      perform set_config('app.inventory_source_document_type', '', true);
      perform set_config('app.inventory_source_document_id', '', true);
      perform set_config('app.inventory_source_channel', '', true);
    end if;
    raise;
end;
$$;

revoke all on function public.create_expense_payment_journal_entry(uuid)
  from public, anon;
grant execute on function public.create_expense_payment_journal_entry(uuid)
  to authenticated, service_role;

create or replace function
  public.create_payroll_advance_allocation_reversal_journal(
    p_reversal_allocation_id uuid
  )
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  reversal_allocation public.employee_advance_allocations%rowtype;
  original_allocation public.employee_advance_allocations%rowtype;
  original_journal public.journal_entries%rowtype;
  original_journal_count integer;
  journal_id_value uuid := gen_random_uuid();
  amount_value numeric(14,2);
  debit_value numeric(14,2);
  credit_value numeric(14,2);
  description_value text;
begin
  select allocation.*
  into reversal_allocation
  from public.employee_advance_allocations allocation
  where allocation.id = p_reversal_allocation_id;

  if not found or reversal_allocation.reversal_of_id is null then
    raise exception 'payroll_advance_reversal_not_found'
      using errcode = 'P0002';
  end if;

  select allocation.*
  into original_allocation
  from public.employee_advance_allocations allocation
  where allocation.id = reversal_allocation.reversal_of_id
    and allocation.tenant_id = reversal_allocation.tenant_id;

  if not found
     or original_allocation.advance_id <> reversal_allocation.advance_id
     or original_allocation.voucher_line_id <>
        reversal_allocation.voucher_line_id
     or reversal_allocation.amount <> -original_allocation.amount then
    raise exception 'payroll_advance_reversal_invalid_original'
      using errcode = '23514';
  end if;

  select count(*)::integer
  into original_journal_count
  from public.journal_entries journal_entry
  where journal_entry.tenant_id = reversal_allocation.tenant_id
    and journal_entry.source_module = 'employee_advance_allocations'
    and (
      journal_entry.source_reference = original_allocation.id::text
      or journal_entry.source_document_id = original_allocation.id
    );

  if original_journal_count <> 1 then
    raise exception 'payroll_advance_original_journal_is_ambiguous'
      using errcode = '55000';
  end if;

  select journal_entry.*
  into original_journal
  from public.journal_entries journal_entry
  where journal_entry.tenant_id = reversal_allocation.tenant_id
    and journal_entry.source_module = 'employee_advance_allocations'
    and (
      journal_entry.source_reference = original_allocation.id::text
      or journal_entry.source_document_id = original_allocation.id
    )
  for update;

  select
    round(coalesce(sum(line.debit_amount), 0), 2),
    round(coalesce(sum(line.credit_amount), 0), 2)
  into debit_value, credit_value
  from public.journal_lines line
  where line.tenant_id = reversal_allocation.tenant_id
    and line.entry_id = original_journal.id;

  amount_value := round(abs(reversal_allocation.amount), 2);
  if original_journal.status <> 'posted'
     or debit_value <> credit_value
     or debit_value <> amount_value
     or round(original_journal.total_debit, 2) <> amount_value
     or round(original_journal.total_credit, 2) <> amount_value then
    raise exception 'payroll_advance_original_journal_is_invalid'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.journal_entries journal_entry
    where journal_entry.tenant_id = reversal_allocation.tenant_id
      and journal_entry.source_module = 'employee_advance_allocations'
      and (
        journal_entry.source_reference = reversal_allocation.id::text
        or journal_entry.source_document_id = reversal_allocation.id
      )
  ) then
    raise exception 'payroll_advance_reversal_journal_already_exists'
      using errcode = '23505';
  end if;

  description_value := format(
    'Reversa de aplicación de anticipo · %s · %s',
    original_journal.entry_number,
    reversal_allocation.reversal_reason
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
    operation_id,
    source_document_type,
    source_document_id,
    created_by,
    reversal_of_id,
    created_at,
    updated_at
  ) values (
    journal_id_value,
    reversal_allocation.tenant_id,
    public.get_next_document_number(
      reversal_allocation.tenant_id,
      'journal_entry'
    ),
    reversal_allocation.applied_at,
    description_value,
    'payroll_reversal',
    'employee_advance_allocations',
    reversal_allocation.id::text,
    'posted',
    amount_value,
    amount_value,
    nullif(current_setting('app.inventory_operation_id', true), '')::uuid,
    'payroll_advance_allocation',
    reversal_allocation.id,
    auth.uid(),
    original_journal.id,
    statement_timestamp(),
    statement_timestamp()
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
  )
  select
    gen_random_uuid(),
    line.tenant_id,
    journal_id_value,
    line.account_id,
    line.account_code,
    line.account_name,
    description_value,
    line.credit_amount,
    line.debit_amount,
    statement_timestamp(),
    statement_timestamp()
  from public.journal_lines line
  where line.tenant_id = reversal_allocation.tenant_id
    and line.entry_id = original_journal.id
  order by line.id;

  return journal_id_value;
end;
$$;

revoke all on function
  public.create_payroll_advance_allocation_reversal_journal(uuid)
  from public, anon, authenticated, service_role;

create or replace function
  public.create_employee_advance_allocation_journal_entry(
    p_allocation_id uuid
  )
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  allocation_row record;
  advance_account_id uuid;
  salary_payable_account_id uuid;
  journal_id_value uuid := gen_random_uuid();
  description_value text;
begin
  select allocation.*, advance.employee_id, voucher_line.employee_name
  into allocation_row
  from public.employee_advance_allocations allocation
  join public.employee_advances advance
    on advance.id = allocation.advance_id
  join public.payroll_voucher_lines voucher_line
    on voucher_line.id = allocation.voucher_line_id
  where allocation.id = p_allocation_id;

  if not found then
    return;
  end if;

  if allocation_row.reversal_of_id is not null then
    perform public.create_payroll_advance_allocation_reversal_journal(
      p_allocation_id
    );
    return;
  end if;

  delete from public.journal_entries journal_entry
  where journal_entry.source_module = 'employee_advance_allocations'
    and journal_entry.source_reference = p_allocation_id::text;

  advance_account_id := public.ensure_account(
    allocation_row.tenant_id,
    '1135',
    'Anticipos al Personal',
    'asset',
    'currentAsset',
    'Anticipos de remuneraciones pendientes de imputar',
    null
  );
  salary_payable_account_id := public.ensure_account(
    allocation_row.tenant_id,
    '2106',
    'Sueldos por Pagar',
    'liability',
    'currentLiability',
    'Obligaciones pendientes de pago por remuneraciones',
    null
  );
  description_value := format(
    'Aplicación de anticipo - %s',
    allocation_row.employee_name
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
    total_credit
  ) values (
    journal_id_value,
    allocation_row.tenant_id,
    public.get_next_document_number(
      allocation_row.tenant_id,
      'journal_entry'
    ),
    allocation_row.applied_at,
    description_value,
    'payroll',
    'employee_advance_allocations',
    allocation_row.id::text,
    'posted',
    allocation_row.amount,
    allocation_row.amount
  );

  insert into public.journal_lines (
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount
  )
  select
    allocation_row.tenant_id,
    journal_id_value,
    account.id,
    account.code,
    account.name,
    description_value,
    allocation_row.amount,
    0
  from public.accounts account
  where account.id = salary_payable_account_id;

  insert into public.journal_lines (
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount
  )
  select
    allocation_row.tenant_id,
    journal_id_value,
    account.id,
    account.code,
    account.name,
    description_value,
    0,
    allocation_row.amount
  from public.accounts account
  where account.id = advance_account_id;
end;
$$;

revoke all on function
  public.create_employee_advance_allocation_journal_entry(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.reverse_payroll_settlement_v1(
  p_voucher_id uuid,
  p_settlement_kind text,
  p_settlement_id uuid,
  p_reason text,
  p_operation_key text,
  p_expected_reconciliation_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  actor_id_value uuid := auth.uid();
  tenant_id_value uuid := public.erp_member_tenant_id();
  kind_value text := lower(btrim(coalesce(p_settlement_kind, '')));
  reason_value text := nullif(btrim(coalesce(p_reason, '')), '');
  operation_key_value text := btrim(coalesce(p_operation_key, ''));
  payload_hash_value text;
  money_operation_id_value uuid := gen_random_uuid();
  original_money_operation_id_value uuid;
  existing_operation public.payroll_money_operations%rowtype;
  voucher_row public.payroll_vouchers%rowtype;
  line_row public.payroll_voucher_lines%rowtype;
  original_payment public.expense_payments%rowtype;
  reversal_payment public.expense_payments%rowtype;
  original_allocation public.employee_advance_allocations%rowtype;
  reversal_allocation public.employee_advance_allocations%rowtype;
  reversal_id_value uuid := gen_random_uuid();
  trace_operation_id_value uuid;
  original_journal public.journal_entries%rowtype;
  reversal_journal public.journal_entries%rowtype;
  original_journal_count integer;
  reversal_journal_count integer;
  journal_debit_value numeric(14,2);
  journal_credit_value numeric(14,2);
  statement_import_ids uuid[];
  statement_import_id_value uuid;
  receipt_value jsonb;
begin
  if actor_id_value is null
     or tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if p_voucher_id is null
     or p_settlement_id is null
     or kind_value not in ('payment', 'advance_allocation')
     or reason_value is null
     or char_length(reason_value) not between 3 and 1000
     or operation_key_value !~ '^[A-Za-z0-9:_-]{8,200}$'
     or p_expected_reconciliation_version is null
     or p_expected_reconciliation_version < 0 then
    raise exception 'payroll_settlement_reversal_invalid_payload'
      using errcode = '22023';
  end if;

  payload_hash_value := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'operation_type', 'payroll_settlement_reversal',
          'voucher_id', p_voucher_id,
          'settlement_kind', kind_value,
          'settlement_id', p_settlement_id,
          'reason', reason_value,
          'expected_reconciliation_version',
          p_expected_reconciliation_version
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      tenant_id_value::text || ':payroll-settlement',
      0
    )
  );

  select money_operation.*
  into existing_operation
  from public.payroll_money_operations money_operation
  where money_operation.tenant_id = tenant_id_value
    and money_operation.operation_key = operation_key_value
  for update;

  if found then
    if existing_operation.operation_type = 'payroll_settlement_reversal'
       and existing_operation.payload_hash = payload_hash_value then
      return existing_operation.receipt ||
        jsonb_build_object('replayed', true);
    end if;
    raise exception 'payroll_money_idempotency_conflict'
      using
        errcode = 'P0001',
        detail = 'operation_key already has a different money payload';
  end if;

  select voucher.*
  into voucher_row
  from public.payroll_vouchers voucher
  where voucher.id = p_voucher_id
    and voucher.tenant_id = tenant_id_value
  for update;

  if not found then
    raise exception 'Payroll voucher not found'
      using errcode = '42501';
  end if;

  if voucher_row.status not in ('confirmed', 'partial', 'paid')
     or voucher_row.reconciliation_version <>
        p_expected_reconciliation_version then
    raise exception 'payroll_settlement_reversal_version_conflict'
      using
        errcode = '40001',
        detail = 'reload payroll balances before correcting a settlement';
  end if;

  if kind_value = 'payment' then
    select payment.*
    into original_payment
    from public.expense_payments payment
    where payment.id = p_settlement_id
      and payment.tenant_id = tenant_id_value
    for update;

    if not found
       or original_payment.amount <= 0
       or original_payment.reversal_of_id is not null then
      raise exception 'payroll_payment_reversal_invalid_original'
        using errcode = '23514';
    end if;

    select voucher_line.*
    into line_row
    from public.payroll_voucher_lines voucher_line
    where voucher_line.voucher_id = p_voucher_id
      and voucher_line.tenant_id = tenant_id_value
      and voucher_line.expense_id = original_payment.expense_id
    for update;

    if not found then
      raise exception 'payroll_payment_reversal_invalid_original'
        using errcode = '23514';
    end if;

    if exists (
      select 1
      from public.expense_payments reversal
      where reversal.tenant_id = tenant_id_value
        and reversal.reversal_of_id = original_payment.id
    ) then
      raise exception 'payroll_settlement_already_reversed'
        using errcode = '55000';
    end if;

    select count(*)::integer
    into original_journal_count
    from public.journal_entries journal_entry
    where journal_entry.tenant_id = tenant_id_value
      and journal_entry.source_module = 'expense_payments'
      and (
        journal_entry.source_reference = original_payment.id::text
        or journal_entry.source_document_id = original_payment.id
      );

    if original_journal_count <> 1 then
      raise exception 'payroll_payment_original_journal_is_ambiguous'
        using errcode = '55000';
    end if;

    select journal_entry.*
    into original_journal
    from public.journal_entries journal_entry
    where journal_entry.tenant_id = tenant_id_value
      and journal_entry.source_module = 'expense_payments'
      and (
        journal_entry.source_reference = original_payment.id::text
        or journal_entry.source_document_id = original_payment.id
      )
    for update;

    select movement.operation_id
    into original_money_operation_id_value
    from public.payroll_money_operation_movements movement
    where movement.tenant_id = tenant_id_value
      and movement.expense_payment_id = original_payment.id;

    select array_agg(distinct allocation.import_id order by allocation.import_id)
    into statement_import_ids
    from public.payroll_statement_allocations allocation
    where allocation.tenant_id = tenant_id_value
      and allocation.expense_payment_id = original_payment.id;
  else
    select allocation.*
    into original_allocation
    from public.employee_advance_allocations allocation
    where allocation.id = p_settlement_id
      and allocation.tenant_id = tenant_id_value
    for update;

    if not found
       or original_allocation.amount <= 0
       or original_allocation.reversal_of_id is not null then
      raise exception 'payroll_advance_reversal_invalid_original'
        using errcode = '23514';
    end if;

    select voucher_line.*
    into line_row
    from public.payroll_voucher_lines voucher_line
    where voucher_line.id = original_allocation.voucher_line_id
      and voucher_line.voucher_id = p_voucher_id
      and voucher_line.tenant_id = tenant_id_value
    for update;

    if not found then
      raise exception 'payroll_advance_reversal_invalid_original'
        using errcode = '23514';
    end if;

    perform advance.id
    from public.employee_advances advance
    where advance.id = original_allocation.advance_id
      and advance.tenant_id = tenant_id_value
    for update;

    if not found or exists (
      select 1
      from public.employee_advance_allocations reversal
      where reversal.tenant_id = tenant_id_value
        and reversal.reversal_of_id = original_allocation.id
    ) then
      raise exception 'payroll_settlement_already_reversed'
        using errcode = '55000';
    end if;

    select count(*)::integer
    into original_journal_count
    from public.journal_entries journal_entry
    where journal_entry.tenant_id = tenant_id_value
      and journal_entry.source_module = 'employee_advance_allocations'
      and (
        journal_entry.source_reference = original_allocation.id::text
        or journal_entry.source_document_id = original_allocation.id
      );

    if original_journal_count <> 1 then
      raise exception 'payroll_advance_original_journal_is_ambiguous'
        using errcode = '55000';
    end if;

    select journal_entry.*
    into original_journal
    from public.journal_entries journal_entry
    where journal_entry.tenant_id = tenant_id_value
      and journal_entry.source_module = 'employee_advance_allocations'
      and (
        journal_entry.source_reference = original_allocation.id::text
        or journal_entry.source_document_id = original_allocation.id
      )
    for update;

    select movement.operation_id
    into original_money_operation_id_value
    from public.payroll_money_operation_movements movement
    where movement.tenant_id = tenant_id_value
      and movement.advance_allocation_id = original_allocation.id;

    select array_agg(distinct allocation.import_id order by allocation.import_id)
    into statement_import_ids
    from public.payroll_statement_allocations allocation
    where allocation.tenant_id = tenant_id_value
      and allocation.employee_advance_allocation_id = original_allocation.id;
  end if;

  if coalesce(cardinality(statement_import_ids), 0) > 1 then
    raise exception 'payroll_settlement_statement_evidence_is_ambiguous'
      using errcode = '55000';
  end if;
  statement_import_id_value := statement_import_ids[1];

  insert into public.payroll_money_command_contexts (
    transaction_id,
    tenant_id,
    command,
    operation_key,
    actor_id
  ) values (
    txid_current(),
    tenant_id_value,
    'audited_reversal',
    operation_key_value,
    actor_id_value
  );

  if statement_import_id_value is not null then
    insert into public.payroll_statement_command_contexts (
      transaction_id,
      tenant_id,
      import_id,
      command,
      actor_id
    ) values (
      txid_current(),
      tenant_id_value,
      statement_import_id_value,
      'audited_reversal',
      actor_id_value
    );
  end if;

  perform set_config(
    'app.inventory_idempotency_key',
    operation_key_value,
    true
  );

  trace_operation_id_value := public.begin_expense_accounting_operation(
    tenant_id_value,
    case
      when kind_value = 'payment' then 'expense_payment'
      else 'payroll_advance_allocation'
    end,
    reversal_id_value,
    line_row.expense_id,
    'payroll',
    'reversal',
    case
      when kind_value = 'payment' then to_jsonb(original_payment)
      else to_jsonb(original_allocation)
    end,
    jsonb_build_object(
      'id', reversal_id_value,
      'tenant_id', tenant_id_value,
      'reversal_of_id', p_settlement_id,
      'amount', case
        when kind_value = 'payment' then -original_payment.amount
        else -original_allocation.amount
      end,
      'reason', reason_value
    ),
    jsonb_build_object(
      'trace_owner', 'rpc',
      'rpc', 'reverse_payroll_settlement_v1',
      'voucher_id', p_voucher_id,
      'settlement_kind', kind_value,
      'reversal_of_id', p_settlement_id,
      'reason', reason_value
    ),
    'database_rpc'
  );

  if kind_value = 'payment' then
    insert into public.expense_payments (
      id,
      tenant_id,
      expense_id,
      payment_method_id,
      payment_account_id,
      amount,
      payment_date,
      reference,
      notes,
      reversal_of_id,
      reversal_reason,
      created_at,
      updated_at
    ) values (
      reversal_id_value,
      tenant_id_value,
      original_payment.expense_id,
      original_payment.payment_method_id,
      original_payment.payment_account_id,
      -original_payment.amount,
      statement_timestamp(),
      coalesce(
        nullif(btrim(original_payment.reference), ''),
        original_payment.id::text
      ) || ' · REVERSA',
      reason_value,
      original_payment.id,
      reason_value,
      statement_timestamp(),
      statement_timestamp()
    )
    returning * into reversal_payment;

    perform public.complete_expense_accounting_operation(
      trace_operation_id_value,
      tenant_id_value,
      line_row.expense_id,
      reversal_payment.id,
      null,
      1,
      false,
      true,
      false,
      null
    );
  else
    insert into public.employee_advance_allocations (
      id,
      tenant_id,
      advance_id,
      voucher_line_id,
      amount,
      applied_at,
      notes,
      created_by,
      reversal_of_id,
      reversal_reason,
      created_at,
      updated_at
    ) values (
      reversal_id_value,
      tenant_id_value,
      original_allocation.advance_id,
      original_allocation.voucher_line_id,
      -original_allocation.amount,
      statement_timestamp(),
      reason_value,
      actor_id_value,
      original_allocation.id,
      reason_value,
      statement_timestamp(),
      statement_timestamp()
    )
    returning * into reversal_allocation;

    select count(*)::integer
    into reversal_journal_count
    from public.journal_entries journal_entry
    where journal_entry.tenant_id = tenant_id_value
      and journal_entry.source_module = 'employee_advance_allocations'
      and journal_entry.source_document_id = reversal_allocation.id
      and journal_entry.operation_id = trace_operation_id_value
      and journal_entry.reversal_of_id = original_journal.id;

    if reversal_journal_count <> 1 then
      raise exception 'payroll_advance_reversal_journal_missing'
        using errcode = '23514';
    end if;

    select journal_entry.*
    into reversal_journal
    from public.journal_entries journal_entry
    where journal_entry.tenant_id = tenant_id_value
      and journal_entry.source_module = 'employee_advance_allocations'
      and journal_entry.source_document_id = reversal_allocation.id
      and journal_entry.operation_id = trace_operation_id_value
      and journal_entry.reversal_of_id = original_journal.id;

    select
      round(coalesce(sum(line.debit_amount), 0), 2),
      round(coalesce(sum(line.credit_amount), 0), 2)
    into journal_debit_value, journal_credit_value
    from public.journal_lines line
    where line.tenant_id = tenant_id_value
      and line.entry_id = reversal_journal.id;

    if journal_debit_value <> journal_credit_value
       or journal_debit_value <> abs(reversal_allocation.amount)
       or exists (
         select 1
         from public.stock_movements movement
         where movement.tenant_id = tenant_id_value
           and movement.operation_id = trace_operation_id_value
       ) then
      raise exception 'payroll_advance_reversal_accounting_invariant_failed'
        using errcode = '23514';
    end if;

    perform public.complete_expense_accounting_operation(
      trace_operation_id_value,
      tenant_id_value,
      line_row.expense_id,
      null,
      null,
      null,
      false,
      false,
      false,
      null
    );
  end if;

  perform set_config('app.inventory_idempotency_key', '', true);

  perform public.refresh_payroll_voucher_status(p_voucher_id);

  select voucher.*
  into voucher_row
  from public.payroll_vouchers voucher
  where voucher.id = p_voucher_id
    and voucher.tenant_id = tenant_id_value;

  select count(*)::integer
  into reversal_journal_count
  from public.journal_entries journal_entry
  where journal_entry.tenant_id = tenant_id_value
    and journal_entry.source_document_id = reversal_id_value
    and journal_entry.operation_id = trace_operation_id_value
    and journal_entry.reversal_of_id = original_journal.id;

  if reversal_journal_count <> 1 then
    raise exception 'payroll_settlement_reversal_journal_missing'
      using errcode = '23514';
  end if;

  select journal_entry.*
  into reversal_journal
  from public.journal_entries journal_entry
  where journal_entry.tenant_id = tenant_id_value
    and journal_entry.source_document_id = reversal_id_value
    and journal_entry.operation_id = trace_operation_id_value
    and journal_entry.reversal_of_id = original_journal.id;

  receipt_value := jsonb_build_object(
    'contract_version', 1,
    'operation_id', money_operation_id_value,
    'operation_key', operation_key_value,
    'payload_hash', payload_hash_value,
    'voucher_id', p_voucher_id,
    'voucher_line_id', line_row.id,
    'settlement_kind', kind_value,
    'original_settlement_id', p_settlement_id,
    'reversal_settlement_id', reversal_id_value,
    'amount', case
      when kind_value = 'payment' then original_payment.amount
      else original_allocation.amount
    end,
    'reason', reason_value,
    'status', voucher_row.status,
    'reconciliation_version', voucher_row.reconciliation_version,
    'trace_operation_id', trace_operation_id_value,
    'original_journal_entry_id', original_journal.id,
    'reversal_journal_entry_id', reversal_journal.id,
    'statement_import_id', statement_import_id_value,
    'replayed', false
  );

  insert into public.payroll_money_operations (
    id,
    tenant_id,
    operation_type,
    operation_key,
    payload_hash,
    voucher_id,
    employee_advance_id,
    reversal_of_operation_id,
    receipt,
    created_by
  ) values (
    money_operation_id_value,
    tenant_id_value,
    'payroll_settlement_reversal',
    operation_key_value,
    payload_hash_value,
    p_voucher_id,
    null,
    original_money_operation_id_value,
    receipt_value,
    actor_id_value
  );

  insert into public.payroll_money_operation_movements (
    tenant_id,
    operation_id,
    movement_type,
    expense_payment_id,
    advance_allocation_id
  ) values (
    tenant_id_value,
    money_operation_id_value,
    case
      when kind_value = 'payment' then 'expense_payment'
      else 'advance_allocation'
    end,
    case
      when kind_value = 'payment' then reversal_id_value
      else null
    end,
    case
      when kind_value = 'advance_allocation' then reversal_id_value
      else null
    end
  );

  if statement_import_id_value is not null then
    delete from public.payroll_statement_command_contexts command_context
    where command_context.transaction_id = txid_current()
      and command_context.tenant_id = tenant_id_value
      and command_context.import_id = statement_import_id_value
      and command_context.command = 'audited_reversal';
  end if;

  delete from public.payroll_money_command_contexts command_context
  where command_context.transaction_id = txid_current()
    and command_context.tenant_id = tenant_id_value
    and command_context.command = 'audited_reversal';

  return receipt_value;
exception
  when others then
    perform set_config('app.inventory_operation_id', '', true);
    perform set_config('app.inventory_source_document_type', '', true);
    perform set_config('app.inventory_source_document_id', '', true);
    perform set_config('app.inventory_source_channel', '', true);
    perform set_config('app.inventory_idempotency_key', '', true);
    raise;
end;
$$;

revoke all on function public.reverse_payroll_settlement_v1(
  uuid,
  text,
  uuid,
  text,
  text,
  bigint
) from public, anon, authenticated, service_role;
grant execute on function public.reverse_payroll_settlement_v1(
  uuid,
  text,
  uuid,
  text,
  text,
  bigint
) to authenticated;

create or replace function public.get_payroll_settlement_reversal_operation_v1(
  p_operation_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  operation_key_value text := btrim(coalesce(p_operation_key, ''));
  operation_row public.payroll_money_operations%rowtype;
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if operation_key_value !~ '^[A-Za-z0-9:_-]{8,200}$' then
    raise exception 'payroll_settlement_reversal_invalid_operation_key'
      using errcode = '22023';
  end if;

  select money_operation.*
  into operation_row
  from public.payroll_money_operations money_operation
  where money_operation.tenant_id = tenant_id_value
    and money_operation.operation_key = operation_key_value
    and money_operation.operation_type = 'payroll_settlement_reversal';

  if not found then
    return null;
  end if;

  return operation_row.receipt;
end;
$$;

revoke all on function
  public.get_payroll_settlement_reversal_operation_v1(text)
  from public, anon, authenticated, service_role;
grant execute on function
  public.get_payroll_settlement_reversal_operation_v1(text)
  to authenticated;

-- Backward compatible read: v1 keeps its exact signature while v2 enriches
-- each row with both sides of the correction relationship.
create or replace function
  public.get_payroll_voucher_settlement_evidence_v2(
    p_voucher_ids uuid[]
  )
returns table (
  voucher_id uuid,
  line_id uuid,
  evidence_id uuid,
  evidence_kind text,
  source text,
  origin_action text,
  amount numeric,
  effective_date timestamp with time zone,
  cash_movement_date timestamp with time zone,
  recorded_at timestamp with time zone,
  payment_method_id uuid,
  payment_method_label text,
  payment_account_id uuid,
  payment_account_label text,
  reference text,
  notes text,
  actor_id uuid,
  actor_name text,
  funding_actor_id uuid,
  funding_actor_name text,
  operation_id uuid,
  operation_key text,
  funding_operation_id uuid,
  funding_operation_key text,
  statement_import_id uuid,
  statement_decision_id uuid,
  statement_row_id uuid,
  advance_id uuid,
  bank_amount numeric,
  variance numeric,
  variance_disposition text,
  manual_confirmation boolean,
  review_reason text,
  statement_transaction_date date,
  statement_description_observed text,
  statement_document_observed text,
  statement_page_number integer,
  statement_source_line_start integer,
  statement_source_line_end integer,
  statement_row_ordinal integer,
  is_reversal boolean,
  reversal_of_evidence_id uuid,
  reversal_evidence_id uuid,
  reversal_reason text,
  reversal_operation_id uuid,
  reversal_operation_key text,
  reversed_at timestamp with time zone,
  reversed_by_id uuid,
  reversed_by_name text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  return query
  select
    evidence.*,
    (
      payment.reversal_of_id is not null
      or advance_allocation.reversal_of_id is not null
    ) as is_reversal,
    coalesce(
      payment.reversal_of_id,
      advance_allocation.reversal_of_id
    ) as reversal_of_evidence_id,
    coalesce(
      payment_reversal.id,
      advance_allocation_reversal.id
    ) as reversal_evidence_id,
    coalesce(
      payment.reversal_reason,
      advance_allocation.reversal_reason,
      payment_reversal.reversal_reason,
      advance_allocation_reversal.reversal_reason
    )::text as reversal_reason,
    coalesce(
      reversal_operation.id,
      case
        when payment.reversal_of_id is not null
          or advance_allocation.reversal_of_id is not null
          then evidence.operation_id
        else null
      end
    ) as reversal_operation_id,
    coalesce(
      reversal_operation.operation_key,
      case
        when payment.reversal_of_id is not null
          or advance_allocation.reversal_of_id is not null
          then evidence.operation_key
        else null
      end
    )::text as reversal_operation_key,
    coalesce(
      reversal_operation.created_at,
      case
        when payment.reversal_of_id is not null
          or advance_allocation.reversal_of_id is not null
          then evidence.recorded_at
        else null
      end
    ) as reversed_at,
    coalesce(
      reversal_operation.created_by,
      case
        when payment.reversal_of_id is not null
          or advance_allocation.reversal_of_id is not null
          then evidence.actor_id
        else null
      end
    ) as reversed_by_id,
    public.erp_actor_display_name(
      coalesce(
        reversal_operation.created_by,
        case
          when payment.reversal_of_id is not null
            or advance_allocation.reversal_of_id is not null
            then evidence.actor_id
          else null
        end
      ),
      tenant_id_value
    ) as reversed_by_name
  from public.get_payroll_voucher_settlement_evidence(
    p_voucher_ids
  ) evidence
  left join public.expense_payments payment
    on evidence.evidence_kind = 'payment'
   and payment.id = evidence.evidence_id
   and payment.tenant_id = tenant_id_value
  left join public.employee_advance_allocations advance_allocation
    on evidence.evidence_kind = 'advance'
   and advance_allocation.id = evidence.evidence_id
   and advance_allocation.tenant_id = tenant_id_value
  left join public.expense_payments payment_reversal
    on payment_reversal.tenant_id = tenant_id_value
   and payment_reversal.reversal_of_id = payment.id
  left join public.employee_advance_allocations
    advance_allocation_reversal
    on advance_allocation_reversal.tenant_id = tenant_id_value
   and advance_allocation_reversal.reversal_of_id = advance_allocation.id
  left join public.payroll_money_operation_movements reversal_movement
    on reversal_movement.tenant_id = tenant_id_value
   and (
     reversal_movement.expense_payment_id = payment_reversal.id
     or reversal_movement.advance_allocation_id =
        advance_allocation_reversal.id
   )
  left join public.payroll_money_operations reversal_operation
    on reversal_operation.tenant_id = reversal_movement.tenant_id
   and reversal_operation.id = reversal_movement.operation_id
   and reversal_operation.operation_type = 'payroll_settlement_reversal'
  order by
    evidence.voucher_id,
    evidence.line_id,
    evidence.effective_date,
    evidence.evidence_id;
end;
$$;

revoke all on function
  public.get_payroll_voucher_settlement_evidence_v2(uuid[])
  from public, anon, authenticated, service_role;
grant execute on function
  public.get_payroll_voucher_settlement_evidence_v2(uuid[])
  to authenticated;

create or replace function public.get_payroll_refinement_capabilities_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  return jsonb_build_object(
    'contract_version', 1,
    'employee_payment_method_command',
      to_regprocedure(
        'public.set_employee_payroll_payment_method(uuid,timestamp with time zone,uuid,text,text,text)'
      ) is not null,
    'structured_advance_audit',
      to_regprocedure(
        'public.register_employee_advance_v3(text,uuid,numeric,uuid,uuid,timestamp with time zone,text,text,text,text,date,uuid,text)'
      ) is not null,
    'audited_settlement_reversal', true,
    'settlement_evidence_contract_version', 2
  );
end;
$$;

revoke all on function public.get_payroll_refinement_capabilities_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_payroll_refinement_capabilities_v1()
  to authenticated;

comment on column public.expense_payments.reversal_of_id is
  'Original immutable Payroll payment compensated by this negative row; null for ordinary payments.';
comment on column public.employee_advance_allocations.reversal_of_id is
  'Original immutable Payroll advance allocation compensated by this negative row; null for ordinary allocations.';
comment on function public.reverse_payroll_settlement_v1(
  uuid,
  text,
  uuid,
  text,
  text,
  bigint
) is
  'Idempotently appends one exact Payroll settlement compensation, a balanced journal linked to the original, and recalculated voucher/expense/advance state without deleting evidence.';
comment on function
  public.get_payroll_voucher_settlement_evidence_v2(uuid[]) is
  'Extends the bounded v1 Payroll settlement evidence with append-only reversal lineage, reason, actor and operation metadata.';

commit;
