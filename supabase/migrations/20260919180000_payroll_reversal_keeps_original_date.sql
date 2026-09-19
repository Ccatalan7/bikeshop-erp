-- Una reversa se fecha el día del movimiento que anula.
--
-- `reverse_payroll_settlement_v1` escribía el contra-pago y la reversa de
-- un anticipo con `statement_timestamp()`, y el asiento hereda esa fecha
-- (`reversal_payment.payment_date`). Así, anular un pago del 27 de agosto
-- dejaba agosto con $30.000 de sueldo que nunca se pagaron y septiembre con
-- un «Gasto · Salario» de -$30.000: los dos meses mal, y en el panorama del
-- dueño un sueldo negativo. Lo vio él en «Panorama financiero» el
-- 2026-09-19, sobre mi propia corrección del anticipo de Braulio.
--
-- El contra-movimiento toma ahora la fecha del original —`payment_date` del
-- pago, `applied_at` de la asignación—, que es lo que hace que el mes diga
-- la verdad. `created_at` sigue siendo el día en que se corrigió, que es la
-- pista de auditoría, y la razón queda escrita como antes.
--
-- Firma y privilegios sin cambios.

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
      -- A reversal is not money moving today: it takes the date of the
      -- movement it cancels, so neither month is left holding half of it.
      original_payment.payment_date,
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
      original_allocation.applied_at,
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

-- Lo ya escrito con la fecha del día se corrige en su lugar: mover el
-- contra-movimiento a la fecha de su original deja los dos en el mismo mes,
-- donde se anulan. Los montos no se tocan, así que ningún gasto cambia de
-- estado; las guardias de evidencia se apagan sólo para esta reparación
-- versionada y se vuelven a encender antes de revalidar.
do $$
declare
  v_pagos integer := 0;
  v_asientos integer := 0;
  v_anticipos integer := 0;
  v_pendientes integer := 0;
begin
  alter table public.expense_payments
    disable trigger trg_aaa_payroll_expense_payment_balance;
  alter table public.expense_payments
    disable trigger trg_guard_payroll_workspace_expense_payment;
  alter table public.employee_advance_allocations
    disable trigger trg_aaa_payroll_advance_allocation_evidence;

  with corregidos as (
    update public.expense_payments reversal
       set payment_date = original.payment_date,
           updated_at = now()
      from public.expense_payments original
     where reversal.reversal_of_id = original.id
       and reversal.tenant_id = original.tenant_id
       and reversal.payment_date <> original.payment_date
    returning reversal.id, reversal.tenant_id, reversal.payment_date
  ), asientos as (
    update public.journal_entries entry
       set entry_date = corregidos.payment_date,
           updated_at = now()
      from corregidos
     where entry.tenant_id = corregidos.tenant_id
       and entry.source_module = 'expense_payments'
       and entry.source_document_id = corregidos.id
       and entry.entry_date <> corregidos.payment_date
    returning entry.id
  )
  select (select count(*) from corregidos), (select count(*) from asientos)
    into v_pagos, v_asientos;

  with corregidas as (
    update public.employee_advance_allocations reversal
       set applied_at = original.applied_at,
           updated_at = now()
      from public.employee_advance_allocations original
     where reversal.reversal_of_id = original.id
       and reversal.tenant_id = original.tenant_id
       and reversal.applied_at <> original.applied_at
    returning reversal.id
  )
  select count(*) into v_anticipos from corregidas;

  alter table public.expense_payments
    enable trigger trg_aaa_payroll_expense_payment_balance;
  alter table public.expense_payments
    enable trigger trg_guard_payroll_workspace_expense_payment;
  alter table public.employee_advance_allocations
    enable trigger trg_aaa_payroll_advance_allocation_evidence;

  select count(*) into v_pendientes
    from public.expense_payments reversal
    join public.expense_payments original
      on original.id = reversal.reversal_of_id
     and original.tenant_id = reversal.tenant_id
   where reversal.payment_date <> original.payment_date;
  if v_pendientes > 0 then
    raise exception 'payroll_reversal_date_repair_incomplete: % pagos',
      v_pendientes;
  end if;

  raise notice 'reversas corregidas: % pagos, % asientos, % anticipos',
    v_pagos, v_asientos, v_anticipos;
end;
$$;
