-- Each denominator is catalog-derived: an absent gate fails SQL.
select 1 / count(*)::integer as inbox_list_definer_and_private
from pg_proc where oid = 'public.inbox_conversations_v1(text)'::regprocedure
  and prosecdef and provolatile = 's'
  and has_function_privilege('authenticated', oid, 'execute')
  and not has_function_privilege('anon', oid, 'execute')
  and pg_get_functiondef(oid) like '%messaging_can_access_conversation(c.id)%';
select 1 / count(*)::integer as hint_rows_staff_only
from pg_proc where oid = 'public.inbox_context_hint_rows_v1(uuid[],uuid[],uuid[],uuid[],uuid[],uuid[],uuid[])'::regprocedure
  and prosecdef and provolatile = 's'
  and has_function_privilege('authenticated', oid, 'execute')
  and not has_function_privilege('anon', oid, 'execute')
  and pg_get_functiondef(oid) like '%messaging_is_staff_in_tenant(me.tenant_id)%'
  and pg_get_functiondef(oid) like '%join staff on staff.tenant_id = cu.tenant_id%';
