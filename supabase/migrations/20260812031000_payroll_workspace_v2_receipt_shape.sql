-- Deployment status: local candidate; not deployed.
--
-- PayrollPaymentWorkspace V2 stores one disposition row for every separate
-- concept.  The row ID is reclassification evidence only when the disposition
-- is `included_in_payroll_total`; an `additional` concept has no payroll link
-- and no reclassification.  The original receipt builder nevertheless exposed
-- that row ID as `reclassification_id` for every disposition.  A client that
-- correctly validates receipt lineage could therefore reject an already
-- committed additional expense and report the whole batch as failed.
--
-- Forward behavior: only newly stored V2 receipts change shape.  Additional
-- concepts expose `disposition` and their ordinary expense/payment evidence;
-- included concepts retain their complete payroll and reclassification
-- lineage.  There is no data backfill or accounting mutation.  Exact replays
-- of receipts stored before this migration retain their immutable historical
-- shape.  Recovery is another forward CREATE OR REPLACE patch.  Lock risk is
-- limited to the brief catalog lock for replacing one function.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $migration$
declare
  v_signature regprocedure := to_regprocedure(
    'public.apply_payroll_payment_workspace_v2(uuid,text,bigint,jsonb)'
  );
  v_definition text;
  v_old_fragment constant text := $old$
        concept_receipt.value || jsonb_strip_nulls(jsonb_build_object(
          'disposition', disposition.disposition,
          'target_id', disposition.target_id,
          'voucher_id', disposition.voucher_id,
          'voucher_line_id', disposition.voucher_line_id,
          'reclassification_id', disposition.id,
          'reclassification_journal_entry_id',
            disposition.reclassification_journal_entry_id
        ))
$old$;
  v_new_fragment constant text := $new$
        concept_receipt.value || case disposition.disposition
          when 'included_in_payroll_total' then
            jsonb_strip_nulls(jsonb_build_object(
              'disposition', disposition.disposition,
              'target_id', disposition.target_id,
              'voucher_id', disposition.voucher_id,
              'voucher_line_id', disposition.voucher_line_id,
              'reclassification_id', disposition.id,
              'reclassification_journal_entry_id',
                disposition.reclassification_journal_entry_id
            ))
          else jsonb_build_object(
            'disposition', disposition.disposition
          )
        end
$new$;
begin
  if v_signature is null then
    raise exception
      'apply_payroll_payment_workspace_v2(uuid,text,bigint,jsonb) is missing'
      using errcode = '42883';
  end if;

  select pg_get_functiondef(v_signature)
  into v_definition;

  if position(v_new_fragment in v_definition) > 0 then
    return;
  end if;

  if position(v_old_fragment in v_definition) = 0 then
    raise exception
      'Unexpected V2 concept receipt builder; refusing partial patch'
      using errcode = '55000';
  end if;

  v_definition := replace(v_definition, v_old_fragment, v_new_fragment);
  execute v_definition;
end;
$migration$;

comment on function public.apply_payroll_payment_workspace_v2(
  uuid,
  text,
  bigint,
  jsonb
) is
  'Atomically posts payroll payments plus separate concepts. Additional concept receipts contain no payroll or reclassification lineage; included_in_payroll_total receipts retain their exact voucher-line and reclassification evidence.';

commit;
