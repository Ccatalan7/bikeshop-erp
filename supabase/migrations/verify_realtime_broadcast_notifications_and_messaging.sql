-- Read-back for 20260916010000. Run it before the deploy and require a failure.
select 1 / (count(*) = 2)::integer as broadcast_functions_present
from pg_proc where oid in (
  to_regprocedure('public.broadcast_erp_notification_change()'),
  to_regprocedure('public.broadcast_messaging_change()'))
  and prosecdef
  and not has_function_privilege('authenticated', oid, 'execute')
  and not has_function_privilege('anon', oid, 'execute');
select 1 / (count(*) = 4)::integer as broadcast_triggers_enabled
from pg_trigger where not tgisinternal and tgenabled = 'O'
  and (tgrelid, tgname) in (
    ('public.erp_notifications'::regclass, 'trg_erp_notifications_broadcast'),
    ('public.messages'::regclass, 'trg_messages_broadcast'),
    ('public.conversations'::regclass, 'trg_conversations_broadcast'),
    ('public.conversation_participants'::regclass, 'trg_conversation_participants_broadcast'));
select 1 / (count(*) = 1)::integer as erp_notification_topic_policy
from pg_policies where schemaname = 'realtime' and tablename = 'messages'
  and policyname = 'Tenant members receive ERP notification broadcasts'
  and cmd = 'SELECT' and roles::text = '{authenticated}'
  and qual like '%erp-notifications:%' and qual like '%:all%' and qual like '%auth.uid()%';
select 1 / (count(*) = 1)::integer as messaging_topic_policy
from pg_policies where schemaname = 'realtime' and tablename = 'messages'
  and policyname = 'Tenant members receive messaging broadcasts'
  and cmd = 'SELECT' and roles::text = '{authenticated}'
  and qual like '%messaging:%' and qual like '%user_tenant_id()%';
select 1 / (count(*) = 0)::integer as messaging_payload_carries_no_content
from pg_proc where oid = to_regprocedure('public.broadcast_messaging_change()')
  and (pg_get_functiondef(oid) like '%''content''%' or pg_get_functiondef(oid) like '%''sender_id''%');
