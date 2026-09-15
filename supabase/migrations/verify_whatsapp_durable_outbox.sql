-- Each denominator is catalog-derived: an absent/incorrect gate fails SQL.
select 1 / count(*)::integer as queue_private
from pg_class where oid = 'public.whatsapp_outbox'::regclass and relrowsecurity
  and not has_table_privilege('authenticated', oid, 'select')
  and not has_table_privilege('anon', oid, 'insert');
select 1 / count(*)::integer as queued_status_allowed
from pg_constraint where conrelid = 'public.messages'::regclass
  and conname = 'messages_external_status_check'
  and pg_get_constraintdef(oid) like '%queued%'
  and pg_get_constraintdef(oid) like '%delivered%';
select 1 / count(*)::integer as acceptance_authorized
from pg_proc where oid = 'public.enqueue_whatsapp_message_v1(jsonb)'::regprocedure
  and prosecdef
  and has_function_privilege('authenticated', oid, 'execute')
  and not has_function_privilege('anon', oid, 'execute')
  and pg_get_functiondef(oid) like '%messaging_can_write_conversation%'
  and pg_get_functiondef(oid) like '%request_hash <> v_hash%';
select 1 / (count(*) = 5)::integer as worker_rpcs_private
from pg_proc where oid in (
  'public.recover_whatsapp_outbox_v1()'::regprocedure,
  'public.dispatch_whatsapp_outbox_v1()'::regprocedure,
  'public.claim_whatsapp_outbox_v1(uuid,text)'::regprocedure,
  'public.start_whatsapp_outbox_send_v1(uuid,text)'::regprocedure,
  'public.finish_whatsapp_outbox_v1(uuid,text,text,jsonb)'::regprocedure)
  and prosecdef
  and has_function_privilege('service_role', oid, 'execute')
  and not has_function_privilege('authenticated', oid, 'execute')
  and not has_function_privilege('anon', oid, 'execute');
select 1 / count(*)::integer as fenced_sender
from pg_proc where oid = 'public.start_whatsapp_outbox_send_v1(uuid,text)'::regprocedure
  and pg_get_functiondef(oid) like '%state = ''processing''%'
  and pg_get_functiondef(oid) like '%lease_until > now()%'
  and pg_get_functiondef(oid) like '%token_hash =%';
select 1 / count(*)::integer as scheduler_active
from cron.job where jobname = 'vinabike_whatsapp_outbox' and active
  and schedule = '* * * * *'
  and command = 'select public.recover_whatsapp_outbox_v1(); select public.dispatch_whatsapp_outbox_v1();';
select 1 / count(*)::integer as worker_runtime
from public.whatsapp_outbox_runtime where singleton and enabled
  and endpoint = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/whatsapp-deliver';
