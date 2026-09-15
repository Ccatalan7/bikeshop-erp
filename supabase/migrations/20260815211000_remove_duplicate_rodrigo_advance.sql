-- Remove one isolated legacy duplicate advance for Rodrigo Guillermo Nieto.
--
-- The valid CLP 36,000 advance from 2026-06-26 is fully allocated to
-- NOM-00028. A second legacy row was created on 2026-07-13 with the note
-- "PAGO DE SEMANA 27 29-JUN / 05-JUL". It has no allocation, command receipt,
-- evidence, statement decision, or payment-workspace leg, but it posted a
-- second cash/advance journal. The owner confirmed that only the original,
-- applied advance exists economically.

set lock_timeout = '5s';
set statement_timeout = '30s';

do $$
declare
  tenant_id_value constant uuid :=
    '5443b130-cc28-45af-a420-cd500b288890'::uuid;
  employee_id_value constant uuid :=
    'ff48247b-5eea-4adc-bdd3-59b4e7a7fd1e'::uuid;
  original_advance_id constant uuid :=
    '7ac0f6a5-f88f-4cf4-bb48-8d4c8b14642e'::uuid;
  duplicate_advance_id constant uuid :=
    '56c36dd9-f4cd-43a8-a92e-c3557d2d8e1b'::uuid;
  original_allocation_id constant uuid :=
    '2929ca81-f6a7-4943-9696-b4033185c6f2'::uuid;
  duplicate_row public.employee_advances%rowtype;
begin
  select advance.*
  into duplicate_row
  from public.employee_advances advance
  where advance.id = duplicate_advance_id
  for update;

  if not found then
    if exists (
      select 1
      from public.journal_entries journal_entry
      where journal_entry.tenant_id = tenant_id_value
        and journal_entry.source_module = 'employee_advances'
        and journal_entry.source_reference = duplicate_advance_id::text
    ) then
      raise exception 'duplicate_payroll_advance_missing_but_journal_remains';
    end if;
    return;
  end if;

  if duplicate_row.tenant_id <> tenant_id_value
     or duplicate_row.employee_id <> employee_id_value
     or duplicate_row.amount <> 36000.00
     or duplicate_row.amount_applied <> 0.00
     or duplicate_row.status <> 'open'
     or duplicate_row.paid_at < timestamptz '2026-07-11 17:29:59+00'
     or duplicate_row.paid_at > timestamptz '2026-07-11 17:30:01+00'
     or duplicate_row.notes <>
       'PAGO DE SEMANA 27 29-JUN / 05-JUL' then
    raise exception 'duplicate_payroll_advance_fingerprint_changed';
  end if;

  if not exists (
    select 1
    from public.employee_advances original
    join public.employee_advance_allocations allocation
      on allocation.advance_id = original.id
    join public.payroll_voucher_lines voucher_line
      on voucher_line.id = allocation.voucher_line_id
    join public.payroll_vouchers voucher
      on voucher.id = voucher_line.voucher_id
    where original.id = original_advance_id
      and original.tenant_id = tenant_id_value
      and original.employee_id = employee_id_value
      and original.amount = 36000.00
      and original.amount_applied = 36000.00
      and original.status = 'applied'
      and allocation.id = original_allocation_id
      and allocation.amount = 36000.00
      and voucher.voucher_number = 'NOM-00028'
  ) then
    raise exception 'original_payroll_advance_invariant_changed';
  end if;

  if exists (
    select 1
    from public.employee_advance_allocations allocation
    where allocation.advance_id = duplicate_advance_id
  ) or exists (
    select 1
    from public.employee_advance_evidence evidence
    where evidence.advance_id = duplicate_advance_id
  ) or exists (
    select 1
    from public.payroll_money_operations operation
    where operation.employee_advance_id = duplicate_advance_id
  ) or exists (
    select 1
    from public.payroll_statement_decisions decision
    where decision.advance_id = duplicate_advance_id
  ) or exists (
    select 1
    from public.payroll_payment_workspace_legs leg
    where leg.advance_id = duplicate_advance_id
  ) then
    raise exception 'duplicate_payroll_advance_gained_business_evidence';
  end if;

  if (
    select count(*)
    from public.journal_entries journal_entry
    where journal_entry.tenant_id = tenant_id_value
      and journal_entry.source_module = 'employee_advances'
      and journal_entry.source_reference = duplicate_advance_id::text
      and journal_entry.status = 'posted'
      and journal_entry.total_debit = 36000.00
      and journal_entry.total_credit = 36000.00
  ) <> 1 then
    raise exception 'duplicate_payroll_advance_journal_fingerprint_changed';
  end if;

  delete from public.employee_advances advance
  where advance.id = duplicate_advance_id;

  if exists (
    select 1
    from public.employee_advances advance
    where advance.id = duplicate_advance_id
  ) or exists (
    select 1
    from public.journal_entries journal_entry
    where journal_entry.tenant_id = tenant_id_value
      and journal_entry.source_module = 'employee_advances'
      and journal_entry.source_reference = duplicate_advance_id::text
  ) then
    raise exception 'duplicate_payroll_advance_correction_incomplete';
  end if;
end
$$;
