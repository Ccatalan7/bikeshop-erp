-- Shared Slack-style channels for task roots and their reply threads.
--
-- The first task-thread implementation correctly introduced a durable
-- root/reply relation, but still created one conversation per task.  This
-- migration makes the conversation the audience container instead:
--
--   * team/company tasks are roots in one tenant-wide task channel;
--   * private tasks are roots in the creator's personal task channel;
--   * each task keeps its own immutable root and replies;
--   * existing roots/replies are moved without changing author or timestamps;
--   * active ERP membership, not an incidental assignee list, owns access.

set lock_timeout = '750ms';
set statement_timeout = '30s';

create table if not exists public.smart_task_message_channels (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  audience text not null,
  owner_user_id uuid references auth.users(id) on delete cascade,
  conversation_id uuid not null unique
    references public.conversations(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint smart_task_message_channels_audience_check
    check (audience in ('team', 'private')),
  constraint smart_task_message_channels_owner_check
    check (
      (audience = 'team' and owner_user_id is null)
      or (audience = 'private' and owner_user_id is not null)
    )
);

create unique index if not exists uq_smart_task_message_channels_team
  on public.smart_task_message_channels (tenant_id)
  where audience = 'team';

create unique index if not exists uq_smart_task_message_channels_private
  on public.smart_task_message_channels (tenant_id, owner_user_id)
  where audience = 'private';

alter table public.smart_task_message_channels enable row level security;
revoke all on public.smart_task_message_channels
  from public, anon, authenticated, service_role;

comment on table public.smart_task_message_channels is
  'Server-owned audience registry: a conversation contains many task roots; a task never owns a conversation.';

create or replace function public.smart_task_sync_channel_participants_v1(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_channel public.smart_task_message_channels%rowtype;
begin
  select channel.* into v_channel
  from public.smart_task_message_channels channel
  where channel.conversation_id = p_conversation_id
  for update;

  if not found then
    return;
  end if;

  delete from public.conversation_participants participant
  where participant.conversation_id = v_channel.conversation_id
    and not exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = participant.user_id
        and profile.tenant_id = v_channel.tenant_id
        and profile.is_active is true
        and (
          v_channel.audience = 'team'
          or profile.user_id = v_channel.owner_user_id
        )
    );

  insert into public.conversation_participants (
    conversation_id, user_id, tenant_id, role
  )
  select
    v_channel.conversation_id,
    profile.user_id,
    v_channel.tenant_id,
    'member'
  from public.user_profiles profile
  where profile.tenant_id = v_channel.tenant_id
    and profile.is_active is true
    and (
      v_channel.audience = 'team'
      or profile.user_id = v_channel.owner_user_id
    )
  on conflict (conversation_id, user_id) do nothing;
end;
$$;

revoke all on function public.smart_task_sync_channel_participants_v1(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.smart_task_channel_for_v1(
  p_task public.smart_tasks,
  p_actor uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_audience text := case
    when p_task.visibility = 'private' then 'private'
    else 'team'
  end;
  v_owner uuid := case
    when p_task.visibility = 'private' then p_task.created_by
    else null
  end;
  v_conversation_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended(
    concat_ws(
      '|', 'smart_task_message_channel', p_task.tenant_id::text,
      v_audience, coalesce(v_owner::text, '-')
    ),
    91
  ));

  select channel.conversation_id into v_conversation_id
  from public.smart_task_message_channels channel
  where channel.tenant_id = p_task.tenant_id
    and channel.audience = v_audience
    and channel.owner_user_id is not distinct from v_owner
  limit 1
  for update;

  if v_conversation_id is null then
    v_conversation_id := gen_random_uuid();

    insert into public.conversations (
      id, tenant_id, type, channel, counterparty_type, is_group, status,
      title, created_by, context_type, context_id,
      created_at, updated_at, last_message_at
    ) values (
      v_conversation_id,
      p_task.tenant_id,
      'internal',
      'internal',
      'internal',
      true,
      'active',
      case when v_audience = 'private' then 'Mis tareas'
           else 'Tareas del equipo' end,
      coalesce(p_actor, p_task.created_by),
      null,
      null,
      now(),
      now(),
      now()
    );

    insert into public.smart_task_message_channels (
      tenant_id, audience, owner_user_id, conversation_id
    ) values (
      p_task.tenant_id, v_audience, v_owner, v_conversation_id
    );
  end if;

  perform public.smart_task_sync_channel_participants_v1(v_conversation_id);
  return v_conversation_id;
end;
$$;

revoke all on function public.smart_task_channel_for_v1(
  public.smart_tasks, uuid
) from public, anon, authenticated, service_role;

-- A shared channel may contain many top-level messages.  Ensuring one task
-- root must therefore never sweep unrelated top-level messages into that
-- task's thread.
create or replace function public.smart_task_ensure_thread_root_v1(
  p_task public.smart_tasks,
  p_conversation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_context_id uuid;
  v_root_message_id uuid;
begin
  select context.id, context.thread_root_message_id
    into v_context_id, v_root_message_id
  from public.conversation_contexts context
  where context.context_type = 'task'
    and context.context_id = p_task.id
    and context.conversation_id = p_conversation_id
    and context.tenant_id = p_task.tenant_id
  limit 1
  for update;

  if v_context_id is null then
    raise exception 'Task thread context is missing'
      using errcode = '23503';
  end if;

  if v_root_message_id is null then
    v_root_message_id := gen_random_uuid();
    insert into public.messages (
      id, conversation_id, sender_id, tenant_id, content, type, metadata,
      created_at
    ) values (
      v_root_message_id,
      p_conversation_id,
      p_task.created_by,
      p_task.tenant_id,
      p_task.title,
      'system',
      jsonb_build_object(
        'task_thread_root', true,
        'task_id', p_task.id,
        'task_visibility', p_task.visibility,
        'source', 'smart_task'
      ),
      p_task.created_at
    );

    update public.conversation_contexts context
    set thread_root_message_id = v_root_message_id
    where context.id = v_context_id;
  else
    update public.messages message
    set content = p_task.title,
        metadata = coalesce(message.metadata, '{}'::jsonb)
          || jsonb_build_object(
            'task_thread_root', true,
            'task_id', p_task.id,
            'task_visibility', p_task.visibility,
            'source', 'smart_task'
          )
    where message.id = v_root_message_id
      and message.conversation_id = p_conversation_id
      and message.tenant_id = p_task.tenant_id;
  end if;

  return v_root_message_id;
end;
$$;

revoke all on function public.smart_task_ensure_thread_root_v1(
  public.smart_tasks, uuid
) from public, anon, authenticated, service_role;

create or replace function public.smart_task_move_thread_v1(
  p_task public.smart_tasks,
  p_destination_conversation_id uuid,
  p_actor uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_context public.conversation_contexts%rowtype;
  v_root_message_id uuid;
  v_reply_ids uuid[] := '{}'::uuid[];
  v_message_ids uuid[] := '{}'::uuid[];
  v_old_context_count integer;
begin
  select context.* into v_context
  from public.conversation_contexts context
  where context.context_type = 'task'
    and context.context_id = p_task.id
    and context.tenant_id = p_task.tenant_id
  limit 1
  for update;

  if not found then
    insert into public.conversation_contexts (
      conversation_id, context_type, context_id, is_primary, added_by,
      tenant_id
    ) values (
      p_destination_conversation_id, 'task', p_task.id, false,
      coalesce(p_actor, p_task.created_by), p_task.tenant_id
    );
    return public.smart_task_ensure_thread_root_v1(
      p_task, p_destination_conversation_id
    );
  end if;

  if v_context.conversation_id = p_destination_conversation_id then
    update public.conversation_contexts context
    set is_primary = false
    where context.id = v_context.id
      and context.is_primary is distinct from false;
    return public.smart_task_ensure_thread_root_v1(
      p_task, p_destination_conversation_id
    );
  end if;

  v_root_message_id := v_context.thread_root_message_id;
  if v_root_message_id is null then
    v_root_message_id := public.smart_task_ensure_thread_root_v1(
      p_task, v_context.conversation_id
    );
  end if;

  select count(*)::integer into v_old_context_count
  from public.conversation_contexts context
  where context.conversation_id = v_context.conversation_id;

  select coalesce(array_agg(message.id order by message.message_sequence), '{}')
    into v_reply_ids
  from public.messages message
  where message.conversation_id = v_context.conversation_id
    and message.id <> v_root_message_id
    and (
      message.thread_root_message_id = v_root_message_id
      or v_old_context_count = 1
    );

  v_message_ids := array_prepend(v_root_message_id, v_reply_ids);

  -- Detach in this order so both guards remain truthful during the move.
  update public.conversation_contexts context
  set thread_root_message_id = null,
      is_primary = false
  where context.id = v_context.id;

  -- Context identity is immutable by contract.  A change of audience is a
  -- new placement of the same durable evidence, so preserve its id/author/time
  -- through delete+insert instead of weakening that guard with an UPDATE.
  delete from public.conversation_contexts context
  where context.id = v_context.id;

  update public.messages message
  set thread_root_message_id = null,
      metadata = coalesce(message.metadata, '{}'::jsonb)
        - 'thread_root_message_id'
  where message.id = any(v_reply_ids);

  update public.conversations conversation
  set context_type = null,
      context_id = null,
      updated_at = now()
  where conversation.id = v_context.conversation_id
    and conversation.context_type = 'task'
    and conversation.context_id = p_task.id;

  update public.messages message
  set conversation_id = p_destination_conversation_id
  where message.id = v_root_message_id;

  update public.messages message
  set conversation_id = p_destination_conversation_id,
      thread_root_message_id = v_root_message_id
  where message.id = any(v_reply_ids);

  update public.message_reactions reaction
  set conversation_id = p_destination_conversation_id
  where reaction.message_id = any(v_message_ids);

  update public.messaging_attachments attachment
  set conversation_id = p_destination_conversation_id
  where attachment.message_id = any(v_message_ids);

  insert into public.conversation_contexts (
    id, conversation_id, context_type, context_id, is_primary, added_by,
    added_at, tenant_id, thread_root_message_id
  ) values (
    v_context.id,
    p_destination_conversation_id,
    v_context.context_type,
    v_context.context_id,
    false,
    v_context.added_by,
    v_context.added_at,
    v_context.tenant_id,
    v_root_message_id
  );

  update public.conversations conversation
  set last_message_at = latest.created_at,
      updated_at = greatest(conversation.updated_at, latest.created_at)
  from (
    select max(message.created_at) as created_at
    from public.messages message
    where message.conversation_id = p_destination_conversation_id
  ) latest
  where conversation.id = p_destination_conversation_id
    and latest.created_at is not null;

  update public.conversations conversation
  set last_message_at = coalesce(latest.created_at, conversation.created_at),
      updated_at = now()
  from (
    select max(message.created_at) as created_at
    from public.messages message
    where message.conversation_id = v_context.conversation_id
  ) latest
  where conversation.id = v_context.conversation_id;

  delete from public.conversations conversation
  where conversation.id = v_context.conversation_id
    and not exists (
      select 1 from public.smart_task_message_channels channel
      where channel.conversation_id = conversation.id
    )
    and not exists (
      select 1 from public.conversation_contexts context
      where context.conversation_id = conversation.id
    )
    and not exists (
      select 1 from public.messages message
      where message.conversation_id = conversation.id
    )
    and not exists (
      select 1 from public.messaging_command_receipts receipt
      where receipt.conversation_id = conversation.id
         or receipt.related_conversation_id = conversation.id
    );

  return public.smart_task_ensure_thread_root_v1(
    p_task, p_destination_conversation_id
  );
end;
$$;

revoke all on function public.smart_task_move_thread_v1(
  public.smart_tasks, uuid, uuid
) from public, anon, authenticated, service_role;

-- Consolidate every existing dedicated task conversation.  This is bounded
-- by the number of task contexts (two in production before this migration)
-- and is idempotent: a context already in its audience channel is only
-- normalized and its root refreshed.
do $$
declare
  v_task public.smart_tasks%rowtype;
  v_destination uuid;
begin
  for v_task in
    select task.*
    from public.smart_tasks task
    where exists (
      select 1
      from public.conversation_contexts context
      where context.context_type = 'task'
        and context.context_id = task.id
        and context.tenant_id = task.tenant_id
    )
    order by task.tenant_id, task.created_at, task.id
  loop
    v_destination := public.smart_task_channel_for_v1(
      v_task, v_task.created_by
    );
    perform public.smart_task_move_thread_v1(
      v_task, v_destination, v_task.created_by
    );
  end loop;
end;
$$;

create or replace function public.smart_task_thread_get_or_create_v1(
  p_task_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid := public.user_tenant_id();
  v_task public.smart_tasks%rowtype;
  v_existing uuid;
  v_destination uuid;
  v_root_message_id uuid;
  v_created boolean := false;
begin
  if v_actor is null or v_tenant is null then
    raise exception 'smart_tasks: active tenant membership required'
      using errcode = '42501';
  end if;

  select task.* into v_task
  from public.smart_tasks task
  where task.id = p_task_id
    and task.tenant_id = v_tenant
  for update;
  if not found then
    raise exception 'smart_tasks: task not found'
      using errcode = '23503', hint = 'task_not_found';
  end if;

  if not public.smart_task_can_view_v1(p_task_id) then
    raise exception 'smart_tasks: task is outside your visibility'
      using errcode = '42501', hint = 'not_authorized';
  end if;

  select context.conversation_id into v_existing
  from public.conversation_contexts context
  where context.context_type = 'task'
    and context.context_id = p_task_id
    and context.tenant_id = v_tenant
  limit 1;

  v_destination := public.smart_task_channel_for_v1(v_task, v_actor);
  v_root_message_id := public.smart_task_move_thread_v1(
    v_task, v_destination, v_actor
  );
  v_created := v_existing is null;

  if v_created then
    perform public.smart_task_append_event(
      v_task, v_actor, 'conversation_linked',
      jsonb_build_object(
        'conversation_id', v_destination,
        'root_message_id', v_root_message_id,
        'channel_audience', case
          when v_task.visibility = 'private' then 'private'
          else 'team'
        end
      )
    );
  end if;

  return jsonb_build_object(
    'conversation_id', v_destination,
    'root_message_id', v_root_message_id,
    'created', v_created
  );
end;
$$;

grant execute on function public.smart_task_thread_get_or_create_v1(uuid)
  to authenticated;
revoke execute on function public.smart_task_thread_get_or_create_v1(uuid)
  from anon, public;

-- The audience channel, not creator/assignee churn, owns participants now.
create or replace function public.smart_task_thread_sync_participants(
  p_task public.smart_tasks,
  p_new_assignee uuid,
  p_previous_assignee uuid
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_conversation_id uuid;
begin
  select context.conversation_id into v_conversation_id
  from public.conversation_contexts context
  where context.context_type = 'task'
    and context.context_id = p_task.id
    and context.tenant_id = p_task.tenant_id
  limit 1;

  if v_conversation_id is not null then
    perform public.smart_task_sync_channel_participants_v1(v_conversation_id);
  end if;
end;
$$;

revoke all on function public.smart_task_thread_sync_participants(
  public.smart_tasks, uuid, uuid
) from public, anon, authenticated, service_role;

create or replace function public.smart_task_rehome_existing_thread_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_existing uuid;
  v_destination uuid;
  v_root uuid;
begin
  select context.conversation_id into v_existing
  from public.conversation_contexts context
  where context.context_type = 'task'
    and context.context_id = new.id
    and context.tenant_id = new.tenant_id
  limit 1;

  if v_existing is null then
    return new;
  end if;

  v_destination := public.smart_task_channel_for_v1(
    new, coalesce(auth.uid(), new.created_by)
  );
  v_root := public.smart_task_move_thread_v1(
    new, v_destination, coalesce(auth.uid(), new.created_by)
  );

  update public.messages message
  set content = new.title,
      metadata = coalesce(message.metadata, '{}'::jsonb)
        || jsonb_build_object(
          'task_thread_root', true,
          'task_id', new.id,
          'task_visibility', new.visibility,
          'source', 'smart_task'
        )
  where message.id = v_root;

  return new;
end;
$$;

revoke all on function public.smart_task_rehome_existing_thread_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_smart_tasks_rehome_message_thread
  on public.smart_tasks;
create trigger trg_smart_tasks_rehome_message_thread
after update of visibility, title on public.smart_tasks
for each row
when (
  old.visibility is distinct from new.visibility
  or old.title is distinct from new.title
)
execute function public.smart_task_rehome_existing_thread_v1();

create or replace function public.smart_task_profile_channel_membership_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_user_id uuid := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
begin
  delete from public.conversation_participants participant
  using public.smart_task_message_channels channel
  where participant.conversation_id = channel.conversation_id
    and participant.user_id = v_user_id
    and not exists (
      select 1
      from public.user_profiles profile
      where profile.user_id = v_user_id
        and profile.tenant_id = channel.tenant_id
        and profile.is_active is true
        and (
          channel.audience = 'team'
          or channel.owner_user_id = profile.user_id
        )
    );

  if tg_op <> 'DELETE' and new.is_active is true then
    insert into public.conversation_participants (
      conversation_id, user_id, tenant_id, role
    )
    select channel.conversation_id, new.user_id, new.tenant_id, 'member'
    from public.smart_task_message_channels channel
    where channel.tenant_id = new.tenant_id
      and (
        channel.audience = 'team'
        or channel.owner_user_id = new.user_id
      )
    on conflict (conversation_id, user_id) do nothing;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.smart_task_profile_channel_membership_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_user_profiles_smart_task_channel_membership
  on public.user_profiles;
create trigger trg_user_profiles_smart_task_channel_membership
after insert or delete or update of tenant_id, user_id, is_active
on public.user_profiles
for each row execute function public.smart_task_profile_channel_membership_v1();
