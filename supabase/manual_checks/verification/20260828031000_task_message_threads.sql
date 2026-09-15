select
  count(*) filter (
    where context.context_type = 'task'
  ) as task_contexts,
  count(*) filter (
    where context.context_type = 'task'
      and context.thread_root_message_id is not null
  ) as task_contexts_with_root,
  count(*) filter (
    where context.context_type = 'task'
      and message.id is not null
      and message.thread_root_message_id is null
  ) as valid_task_roots,
  count(reply.id) as task_replies
from public.conversation_contexts context
left join public.messages message
  on message.id = context.thread_root_message_id
left join public.messages reply
  on reply.thread_root_message_id = context.thread_root_message_id;

select 1 / count(*)::integer as messages_thread_column_exists
from information_schema.columns
where table_schema = 'public'
  and table_name = 'messages'
  and column_name = 'thread_root_message_id';

select 1 / count(*)::integer as contexts_thread_column_exists
from information_schema.columns
where table_schema = 'public'
  and table_name = 'conversation_contexts'
  and column_name = 'thread_root_message_id';

select 1 / count(*)::integer as thread_relation_guard_exists
from pg_trigger trigger
where trigger.tgrelid = 'public.messages'::regclass
  and trigger.tgname = 'trg_messages_thread_relation_guard'
  and not trigger.tgisinternal;

select 1 / count(*)::integer as context_root_guard_exists
from pg_trigger trigger
where trigger.tgrelid = 'public.conversation_contexts'::regclass
  and trigger.tgname = 'trg_conversation_contexts_thread_root_guard'
  and not trigger.tgisinternal;

select 1 / count(*)::integer as task_thread_rpc_returns_root
from pg_proc function
where function.oid =
  to_regprocedure('public.smart_task_thread_get_or_create_v1(uuid)')
  and pg_get_functiondef(function.oid) like '%root_message_id%';

select 1 / count(*)::integer as threaded_attachment_rpc_exists
where to_regprocedure(
  'public.publish_messaging_attachment_in_thread_v1(uuid,text,uuid)'
) is not null;

select 1 / count(*)::integer as task_contexts_have_roots
from public.conversation_contexts context
where context.context_type = 'task'
  and context.thread_root_message_id is not null;

select 1 / (
  1 - least(count(*)::integer, 1)
) as no_invalid_task_roots
from public.conversation_contexts context
left join public.messages root
  on root.id = context.thread_root_message_id
where context.context_type = 'task'
  and (
    context.thread_root_message_id is null
    or root.id is null
    or root.conversation_id is distinct from context.conversation_id
    or root.tenant_id is distinct from context.tenant_id
    or root.thread_root_message_id is not null
    or root.type is distinct from 'system'
    or root.metadata->>'task_thread_root' is distinct from 'true'
    or root.metadata->>'task_id' is distinct from context.context_id::text
  );

select 1 / (
  1 - least(count(*)::integer, 1)
) as no_task_messages_float_outside_the_root
from public.conversation_contexts context
join public.messages message
  on message.conversation_id = context.conversation_id
where context.context_type = 'task'
  and message.id is distinct from context.thread_root_message_id
  and message.thread_root_message_id is distinct from
    context.thread_root_message_id;

select 1 / count(*)::integer as authenticated_can_open_task_thread
where has_function_privilege(
  'authenticated',
  'public.smart_task_thread_get_or_create_v1(uuid)',
  'EXECUTE'
);

select 1 / count(*)::integer as anonymous_cannot_open_task_thread
where not has_function_privilege(
  'anon',
  'public.smart_task_thread_get_or_create_v1(uuid)',
  'EXECUTE'
);

