-- Executable production read-back for 20260825180000.
-- This runs read-only: it proves the exact command, receipt ledger and ACL are
-- installed without creating a purchasing need.

select 1 / (case when to_regclass(
  'public.purchase_priority_batch_receipts'
) is not null then 1 else 0 end) as priority_batch_receipt_ledger_is_installed;

select 1 / (case when to_regprocedure(
  'public.take_purchase_priority_batch_v1(jsonb,integer,text)'
) is not null then 1 else 0 end) as priority_batch_command_is_installed;

select 1 / (case when
  pg_get_functiondef(
    'public.take_purchase_priority_batch_v1(jsonb,integer,text)'::regprocedure
  ) like '%purchase_priority_feed_v1(%'
  and pg_get_functiondef(
    'public.take_purchase_priority_batch_v1(jsonb,integer,text)'::regprocedure
  ) like '%create_supply_need_v1(%'
  and pg_get_functiondef(
    'public.take_purchase_priority_batch_v1(jsonb,integer,text)'::regprocedure
  ) like '%purchase_priority_product:%'
then 1 else 0 end) as authoritative_replay_safe_batch_body_is_installed;

select 1 / (case when has_function_privilege(
  'authenticated',
  'public.take_purchase_priority_batch_v1(jsonb,integer,text)',
  'execute'
) and not has_function_privilege(
  'anon',
  'public.take_purchase_priority_batch_v1(jsonb,integer,text)',
  'execute'
) then 1 else 0 end) as priority_batch_acl_is_closed;

select 1 / (case when relrowsecurity
  and not has_table_privilege(
    'authenticated', 'public.purchase_priority_batch_receipts', 'select'
  )
  and not has_table_privilege(
    'anon', 'public.purchase_priority_batch_receipts', 'select'
  )
then 1 else 0 end) as priority_batch_receipts_are_private
from pg_class
where oid = 'public.purchase_priority_batch_receipts'::regclass;
