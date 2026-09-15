-- Each denominator is catalog-derived: an absent gate fails SQL.
select 1 / count(*)::integer as unread_function_private_and_definer
from pg_proc where oid = 'public.inbox_unread_counts_v1()'::regprocedure
  and prosecdef and provolatile = 's'
  and has_function_privilege('authenticated', oid, 'execute')
  and not has_function_privilege('anon', oid, 'execute')
  and pg_get_functiondef(oid) like '%messaging_can_access_conversation(conversation.id)%'
  and pg_get_functiondef(oid) like '%messaging_can_read_conversation_messages(conversation.id)%';
select 1 / count(*)::integer as view_delegates_to_function
from pg_views where schemaname = 'public' and viewname = 'conversation_unread_counts'
  and definition like '%inbox_unread_counts_v1()%';
select 1 / count(*)::integer as latest_function_private_and_definer
from pg_proc where oid = 'public.inbox_latest_messages_v1(uuid[])'::regprocedure
  and prosecdef and provolatile = 's'
  and has_function_privilege('authenticated', oid, 'execute')
  and not has_function_privilege('anon', oid, 'execute')
  and pg_get_functiondef(oid) like '%messaging_can_read_conversation_messages(c.id)%'
  and pg_get_functiondef(oid) like '%limit 3%';
