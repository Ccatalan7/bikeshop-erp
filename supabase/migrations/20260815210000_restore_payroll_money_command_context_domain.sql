-- Restore the complete command domain used by every payroll money writer.
--
-- 20260802120000 added audited reversals by replacing this CHECK, but omitted
-- advance_audit_attach, which register_employee_advance_v3 needs inside the
-- same transaction after registering the advance. The omission made every
-- structured advance fail with SQLSTATE 23514 and roll back completely.

set lock_timeout = '5s';
set statement_timeout = '30s';

alter table public.payroll_money_command_contexts
  drop constraint if exists payroll_money_command_contexts_command_check;

alter table public.payroll_money_command_contexts
  add constraint payroll_money_command_contexts_command_check
  check (
    command in (
      'manual_payment',
      'advance_registration',
      'advance_audit_attach',
      'legacy_reversal',
      'audited_reversal'
    )
  );

comment on constraint payroll_money_command_contexts_command_check
  on public.payroll_money_command_contexts is
  'Complete command domain shared by payroll payments, advances, audit attachment, and reversals.';
