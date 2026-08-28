-- Production read-back for shared task channels and Slack-style root threads.
-- Diagnostics come first; the division assertions make any broken invariant
-- fail the deployment wrapper instead of reporting a misleading success.

select
  channel.tenant_id,
  channel.audience,
  channel.owner_user_id,
  channel.conversation_id,
  conversation.title,
  count(distinct context.id) filter (
    where context.context_type = 'task'
  ) as task_roots,
  count(distinct participant.user_id) as participants
from public.smart_task_message_channels channel
join public.conversations conversation
  on conversation.id = channel.conversation_id
left join public.conversation_contexts context
  on context.conversation_id = channel.conversation_id
left join public.conversation_participants participant
  on participant.conversation_id = channel.conversation_id
group by
  channel.tenant_id,
  channel.audience,
  channel.owner_user_id,
  channel.conversation_id,
  conversation.title
order by channel.tenant_id, channel.audience, channel.owner_user_id;

select
  count(distinct context.id) filter (
    where context.context_type = 'task'
  ) as task_contexts,
  count(distinct context.conversation_id) filter (
    where context.context_type = 'task'
  ) as task_channel_conversations,
  count(distinct context.id) filter (
    where context.context_type = 'task'
      and context.thread_root_message_id is not null
  ) as task_roots,
  count(reply.id) as task_replies
from public.conversation_contexts context
left join public.messages reply
  on reply.thread_root_message_id = context.thread_root_message_id;

select
  function.proname,
  md5(pg_get_functiondef(function.oid)) as definition_md5
from pg_proc function
join pg_namespace namespace on namespace.oid = function.pronamespace
where namespace.nspname = 'public'
  and function.proname in (
    'smart_task_sync_channel_participants_v1',
    'smart_task_channel_for_v1',
    'smart_task_move_thread_v1',
    'smart_task_thread_get_or_create_v1',
    'smart_task_rehome_existing_thread_v1',
    'smart_task_profile_channel_membership_v1'
  )
order by function.proname;

select
  trigger.tgname,
  trigger.tgenabled,
  pg_get_triggerdef(trigger.oid) as definition
from pg_trigger trigger
where trigger.tgname in (
    'trg_smart_tasks_rehome_message_thread',
    'trg_user_profiles_smart_task_channel_membership'
  )
  and not trigger.tgisinternal
order by trigger.tgname;

select 1 / (case when to_regclass(
  'public.smart_task_message_channels'
) is not null then 1 else 0 end) as channel_registry_exists;

select 1 / (case when to_regclass(
  'public.uq_smart_task_message_channels_team'
) is not null then 1 else 0 end) as team_channel_unique_index_exists;

select 1 / (case when to_regclass(
  'public.uq_smart_task_message_channels_private'
) is not null then 1 else 0 end) as private_channel_unique_index_exists;

select 1 / (case when
  to_regprocedure(
    'public.smart_task_sync_channel_participants_v1(uuid)'
  ) is not null
  and to_regprocedure(
    'public.smart_task_channel_for_v1(public.smart_tasks,uuid)'
  ) is not null
  and to_regprocedure(
    'public.smart_task_move_thread_v1(public.smart_tasks,uuid,uuid)'
  ) is not null
  and to_regprocedure(
    'public.smart_task_thread_get_or_create_v1(uuid)'
  ) is not null
  and to_regprocedure(
    'public.smart_task_rehome_existing_thread_v1()'
  ) is not null
  and to_regprocedure(
    'public.smart_task_profile_channel_membership_v1()'
  ) is not null
then 1 else 0 end) as shared_channel_functions_exist;

select 1 / (case when
  exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid = 'public.smart_tasks'::regclass
      and trigger.tgname = 'trg_smart_tasks_rehome_message_thread'
      and trigger.tgenabled <> 'D'
      and not trigger.tgisinternal
  )
  and exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid = 'public.user_profiles'::regclass
      and trigger.tgname =
        'trg_user_profiles_smart_task_channel_membership'
      and trigger.tgenabled <> 'D'
      and not trigger.tgisinternal
  )
then 1 else 0 end) as channel_sync_triggers_are_enabled;

select 1 / (case when
  not has_table_privilege(
    'anon', 'public.smart_task_message_channels',
    'SELECT,INSERT,UPDATE,DELETE'
  )
  and not has_table_privilege(
    'authenticated', 'public.smart_task_message_channels',
    'SELECT,INSERT,UPDATE,DELETE'
  )
then 1 else 0 end) as channel_registry_is_server_owned;

select 1 / (case when
  has_function_privilege(
    'authenticated',
    'public.smart_task_thread_get_or_create_v1(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.smart_task_thread_get_or_create_v1(uuid)',
    'EXECUTE'
  )
then 1 else 0 end) as thread_entrypoint_remains_authenticated_only;

select 1 / (
  1 - least(count(*)::integer, 1)
) as no_duplicate_audience_channels
from (
  select
    channel.tenant_id,
    channel.audience,
    channel.owner_user_id,
    count(*)
  from public.smart_task_message_channels channel
  group by channel.tenant_id, channel.audience, channel.owner_user_id
  having count(*) > 1
) duplicate;

select 1 / (
  1 - least(count(*)::integer, 1)
) as every_task_context_uses_its_audience_channel
from public.conversation_contexts context
left join public.smart_tasks task
  on task.id = context.context_id
 and task.tenant_id = context.tenant_id
left join public.smart_task_message_channels channel
  on channel.conversation_id = context.conversation_id
 and channel.tenant_id = context.tenant_id
where context.context_type = 'task'
  and (
    task.id is null
    or channel.id is null
    or context.is_primary is distinct from false
    or channel.audience is distinct from case
      when task.visibility = 'private' then 'private'
      else 'team'
    end
    or channel.owner_user_id is distinct from case
      when task.visibility = 'private' then task.created_by
      else null
    end
  );

select 1 / (
  1 - least(count(*)::integer, 1)
) as every_task_root_is_top_level_in_the_same_channel
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
) as every_reply_stays_with_its_root
from public.messages reply
left join public.messages root
  on root.id = reply.thread_root_message_id
where reply.thread_root_message_id is not null
  and (
    root.id is null
    or root.thread_root_message_id is not null
    or root.conversation_id is distinct from reply.conversation_id
    or root.tenant_id is distinct from reply.tenant_id
  );

select 1 / (
  1 - least(count(*)::integer, 1)
) as team_channel_participants_equal_active_erp_profiles
from public.smart_task_message_channels channel
where channel.audience = 'team'
  and (
    exists (
      select 1
      from public.conversation_participants participant
      where participant.conversation_id = channel.conversation_id
        and not exists (
          select 1
          from public.user_profiles profile
          where profile.tenant_id = channel.tenant_id
            and profile.user_id = participant.user_id
            and profile.is_active is true
        )
    )
    or exists (
      select 1
      from public.user_profiles profile
      where profile.tenant_id = channel.tenant_id
        and profile.is_active is true
        and not exists (
          select 1
          from public.conversation_participants participant
          where participant.conversation_id = channel.conversation_id
            and participant.user_id = profile.user_id
        )
    )
  );

select 1 / (
  1 - least(count(*)::integer, 1)
) as private_channel_participants_equal_active_owner
from public.smart_task_message_channels channel
where channel.audience = 'private'
  and (
    exists (
      select 1
      from public.conversation_participants participant
      where participant.conversation_id = channel.conversation_id
        and participant.user_id is distinct from channel.owner_user_id
    )
    or exists (
      select 1
      from public.user_profiles profile
      where profile.tenant_id = channel.tenant_id
        and profile.user_id = channel.owner_user_id
        and profile.is_active is true
        and not exists (
          select 1
          from public.conversation_participants participant
          where participant.conversation_id = channel.conversation_id
            and participant.user_id = channel.owner_user_id
        )
    )
    or exists (
      select 1
      from public.conversation_participants participant
      where participant.conversation_id = channel.conversation_id
        and not exists (
          select 1
          from public.user_profiles profile
          where profile.tenant_id = channel.tenant_id
            and profile.user_id = participant.user_id
            and profile.is_active is true
        )
    )
  );
