-- Deployment status: pending guarded production deployment and read-back.
--
-- Forward behavior:
--   The first successful apply receipt explicitly reports `replayed = false`.
--   An exact operation-key retry overlays `replayed = true` on the immutable
--   stored receipt without changing the stored financial result.
--
-- Recovery behavior:
--   Replacing the function with the immediately preceding definition restores
--   the old response shape. No table rows or accounting effects are rewritten.
--
-- Lock/timeout risk:
--   CREATE OR REPLACE takes the ordinary function-definition lock only. This
--   migration performs no backfill and touches no business rows.

do $migration$
declare
  function_identity constant regprocedure :=
    'public.apply_payroll_statement_reconciliation(uuid,text,jsonb,jsonb,jsonb)'::regprocedure;
  definition text;
  replay_old constant text :=
    'return import_row.apply_receipt;';
  replay_new constant text :=
    'return import_row.apply_receipt || jsonb_build_object(''replayed'', true);';
  replay_new_formatted constant text :=
    E'return import_row.apply_receipt\n          || jsonb_build_object(''replayed'', true);';
  receipt_old constant text := E'receipt_value := jsonb_build_object(\n    ''import_id'',';
  receipt_new constant text := E'receipt_value := jsonb_build_object(\n    ''replayed'',\n    false,\n    ''import_id'',';
begin
  select pg_get_functiondef(function_identity)
  into definition;

  if definition is null then
    raise exception
      'apply_payroll_statement_reconciliation definition is unavailable'
      using errcode = '55000';
  end if;

  if (
       position(replay_new in definition) > 0
       or position(replay_new_formatted in definition) > 0
     )
     and position(receipt_new in definition) > 0 then
    return;
  end if;

  if position(replay_new in definition) > 0
     or position(replay_new_formatted in definition) > 0
     or position(receipt_new in definition) > 0 then
    raise exception
      'apply_payroll_statement_reconciliation has a partial replay-marker patch'
      using errcode = '55000';
  end if;

  if (
    length(definition) - length(replace(definition, replay_old, ''))
  ) / length(replay_old) <> 1
     or (
       length(definition) - length(replace(definition, receipt_old, ''))
     ) / length(receipt_old) <> 1 then
    raise exception
      'apply_payroll_statement_reconciliation baseline does not match the reviewed definition'
      using errcode = '55000';
  end if;

  definition := replace(definition, replay_old, replay_new);
  definition := replace(definition, receipt_old, receipt_new);
  execute definition;

  select pg_get_functiondef(function_identity)
  into definition;

  if (
       position(replay_new in definition) = 0
       and position(replay_new_formatted in definition) = 0
     )
     or position(receipt_new in definition) = 0 then
    raise exception
      'apply_payroll_statement_reconciliation replay markers were not installed'
      using errcode = '55000';
  end if;
end
$migration$;

comment on function public.apply_payroll_statement_reconciliation(
  uuid,
  text,
  jsonb,
  jsonb,
  jsonb
) is
  'Atomically applies explicit reviewed payroll decisions with stable account-scoped row dedupe, live balances, tenant locks, voucher-version checks, and an exact allow-list for draft vouchers the operator authorized to commit. The receipt returns committed_voucher_ids and declares replayed=false on the first application or replayed=true on an exact retry. A manually confirmed partial debit posts exactly the bank amount and leaves the residual obligation open; bounded overpayment variance remains unresolved and is not a full bank-ledger reconciliation.';
