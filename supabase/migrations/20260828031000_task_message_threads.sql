-- True message threads for task conversations.
--
-- A task conversation used to be a flat list whose task card was only drawn
-- by Flutter.  That made every comment an ordinary top-level message.  This
-- migration gives messages a durable root/reply relation, binds the canonical
-- task context to one root message, and preserves the two existing task chats
-- by attaching their current messages as replies to a generated task root.

set lock_timeout = '750ms';
set statement_timeout = '30s';

alter table public.messages
  add column if not exists thread_root_message_id uuid;

alter table public.conversation_contexts
  add column if not exists thread_root_message_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.messages'::regclass
      and conname = 'messages_thread_root_message_id_fkey'
  ) then
    alter table public.messages
      add constraint messages_thread_root_message_id_fkey
      foreign key (thread_root_message_id)
      references public.messages(id)
      on delete cascade;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.messages'::regclass
      and conname = 'messages_thread_root_not_self_check'
  ) then
    alter table public.messages
      add constraint messages_thread_root_not_self_check
      check (thread_root_message_id is distinct from id);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.conversation_contexts'::regclass
      and conname = 'conversation_contexts_thread_root_message_id_fkey'
  ) then
    alter table public.conversation_contexts
      add constraint conversation_contexts_thread_root_message_id_fkey
      foreign key (thread_root_message_id)
      references public.messages(id)
      on delete set null;
  end if;
end;
$$;

create index if not exists idx_messages_thread_replies
  on public.messages (conversation_id, thread_root_message_id, message_sequence)
  where thread_root_message_id is not null;

create unique index if not exists uq_conversation_contexts_thread_root_message
  on public.conversation_contexts (thread_root_message_id)
  where thread_root_message_id is not null;

comment on column public.messages.thread_root_message_id is
  'Null for a top-level message; otherwise the immutable top-level message whose reply thread contains this row.';
comment on column public.conversation_contexts.thread_root_message_id is
  'Optional root message that represents this business context inside its conversation.';

create or replace function public.messaging_thread_relation_guard_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_metadata_root text;
  v_root public.messages%rowtype;
begin
  new.metadata := coalesce(new.metadata, '{}'::jsonb);
  v_metadata_root := nullif(btrim(new.metadata->>'thread_root_message_id'), '');

  if new.thread_root_message_id is null and v_metadata_root is not null then
    begin
      new.thread_root_message_id := v_metadata_root::uuid;
    exception when invalid_text_representation then
      raise exception 'Thread root metadata is not a UUID'
        using errcode = '22023';
    end;
  end if;

  if new.thread_root_message_id is null then
    new.metadata := new.metadata - 'thread_root_message_id';
    return new;
  end if;

  if new.thread_root_message_id = new.id then
    raise exception 'A message cannot reply to itself'
      using errcode = '23514';
  end if;

  select root.* into v_root
  from public.messages root
  where root.id = new.thread_root_message_id;

  if not found then
    raise exception 'Thread root message does not exist'
      using errcode = '23503';
  end if;
  if v_root.thread_root_message_id is not null then
    raise exception 'A reply cannot be used as another thread root'
      using errcode = '23514';
  end if;
  if v_root.conversation_id is distinct from new.conversation_id
     or v_root.tenant_id is distinct from new.tenant_id then
    raise exception 'Thread root must belong to the same conversation and tenant'
      using errcode = '23514';
  end if;

  new.metadata := jsonb_set(
    new.metadata,
    '{thread_root_message_id}',
    to_jsonb(new.thread_root_message_id::text),
    true
  );
  return new;
end;
$$;

revoke all on function public.messaging_thread_relation_guard_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_messages_thread_relation_guard on public.messages;
create trigger trg_messages_thread_relation_guard
before insert or update of thread_root_message_id, metadata,
  conversation_id, tenant_id
on public.messages
for each row execute function public.messaging_thread_relation_guard_v1();

create or replace function public.messaging_context_thread_root_guard_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_root public.messages%rowtype;
begin
  if new.thread_root_message_id is null then
    return new;
  end if;

  select root.* into v_root
  from public.messages root
  where root.id = new.thread_root_message_id;

  if not found then
    raise exception 'Context thread root message does not exist'
      using errcode = '23503';
  end if;
  if v_root.thread_root_message_id is not null
     or v_root.conversation_id is distinct from new.conversation_id
     or v_root.tenant_id is distinct from new.tenant_id then
    raise exception 'Context thread root must be a top-level message in the same conversation and tenant'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.messaging_context_thread_root_guard_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_conversation_contexts_thread_root_guard
  on public.conversation_contexts;
create trigger trg_conversation_contexts_thread_root_guard
before insert or update of thread_root_message_id, conversation_id, tenant_id
on public.conversation_contexts
for each row execute function public.messaging_context_thread_root_guard_v1();

-- Preserve existing task conversations.  System roots are intentionally
-- silent in the push recipient policy; all prior human messages become replies
-- without changing their author, timestamp, content or message sequence.
do $$
declare
  v_context record;
  v_root_message_id uuid;
begin
  for v_context in
    select
      context.id as context_row_id,
      context.conversation_id,
      context.tenant_id,
      context.context_id as task_id,
      context.thread_root_message_id,
      task.title,
      task.created_by,
      task.created_at
    from public.conversation_contexts context
    join public.smart_tasks task
      on task.id = context.context_id
     and task.tenant_id = context.tenant_id
    where context.context_type = 'task'
    order by context.id
    for update of context
  loop
    v_root_message_id := v_context.thread_root_message_id;

    if v_root_message_id is null then
      select message.id into v_root_message_id
      from public.messages message
      where message.conversation_id = v_context.conversation_id
        and message.tenant_id = v_context.tenant_id
        and message.thread_root_message_id is null
        and message.type = 'system'
        and message.metadata->>'task_thread_root' = 'true'
        and message.metadata->>'task_id' = v_context.task_id::text
      order by message.message_sequence
      limit 1;
    end if;

    if v_root_message_id is null then
      v_root_message_id := gen_random_uuid();
      insert into public.messages (
        id, conversation_id, sender_id, tenant_id, content, type, metadata,
        created_at
      ) values (
        v_root_message_id,
        v_context.conversation_id,
        v_context.created_by,
        v_context.tenant_id,
        v_context.title,
        'system',
        jsonb_build_object(
          'task_thread_root', true,
          'task_id', v_context.task_id,
          'source', 'smart_task'
        ),
        v_context.created_at
      );
    end if;

    update public.conversation_contexts context
    set thread_root_message_id = v_root_message_id
    where context.id = v_context.context_row_id
      and context.thread_root_message_id is distinct from v_root_message_id;

    update public.messages message
    set thread_root_message_id = v_root_message_id
    where message.conversation_id = v_context.conversation_id
      and message.tenant_id = v_context.tenant_id
      and message.id <> v_root_message_id
      and message.thread_root_message_id is null;

    update public.conversations conversation
    set last_message_at = latest.created_at,
        updated_at = greatest(conversation.updated_at, latest.created_at)
    from (
      select max(message.created_at) as created_at
      from public.messages message
      where message.conversation_id = v_context.conversation_id
    ) latest
    where conversation.id = v_context.conversation_id
      and latest.created_at is not null;
  end loop;
end;
$$;

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
        'source', 'smart_task'
      ),
      p_task.created_at
    );

    update public.conversation_contexts context
    set thread_root_message_id = v_root_message_id
    where context.id = v_context_id;
  end if;

  update public.messages message
  set thread_root_message_id = v_root_message_id
  where message.conversation_id = p_conversation_id
    and message.tenant_id = p_task.tenant_id
    and message.id <> v_root_message_id
    and message.thread_root_message_id is null;

  return v_root_message_id;
end;
$$;

revoke all on function public.smart_task_ensure_thread_root_v1(
  public.smart_tasks, uuid
) from public, anon, authenticated, service_role;

-- Same authorization and participant contract as v1, now returning the
-- canonical root message as part of the durable descriptor.
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
  v_is_manager boolean;
  v_existing uuid;
  v_conversation uuid;
  v_root_message_id uuid;
begin
  if v_actor is null or v_tenant is null then
    raise exception 'smart_tasks: active tenant membership required'
      using errcode = '42501';
  end if;

  select * into v_task
  from public.smart_tasks
  where id = p_task_id and tenant_id = v_tenant
  for update;
  if not found then
    raise exception 'smart_tasks: task not found'
      using errcode = '23503', hint = 'task_not_found';
  end if;

  v_is_manager := public.can_manage_tenant_users(v_tenant);
  if not (v_task.created_by = v_actor
          or v_task.assigned_to = v_actor
          or v_is_manager) then
    raise exception 'smart_tasks: only creator, assignee or a manager opens the thread'
      using errcode = '42501', hint = 'not_authorized';
  end if;

  select context.conversation_id into v_existing
  from public.conversation_contexts context
  where context.context_type = 'task' and context.context_id = p_task_id
  limit 1;
  if v_existing is not null then
    insert into public.conversation_participants (
      conversation_id, user_id, tenant_id
    )
    select v_existing, v_actor, v_tenant
    where exists (
        select 1 from public.user_profiles profile
        where profile.user_id = v_actor
          and profile.tenant_id = v_tenant
          and profile.is_active is true
      )
      and not exists (
        select 1 from public.conversation_participants participant
        where participant.conversation_id = v_existing
          and participant.user_id = v_actor
      );
    v_root_message_id := public.smart_task_ensure_thread_root_v1(
      v_task, v_existing
    );
    return jsonb_build_object(
      'conversation_id', v_existing,
      'root_message_id', v_root_message_id,
      'created', false
    );
  end if;

  v_conversation := gen_random_uuid();
  insert into public.conversations (
    id, tenant_id, type, channel, counterparty_type, is_group, status,
    title, created_by, created_at, updated_at
  ) values (
    v_conversation, v_tenant, 'internal', 'internal', 'internal', true,
    'active', left(v_task.title, 120), v_actor, now(), now()
  );

  insert into public.conversation_participants (
    conversation_id, user_id, tenant_id
  )
  select v_conversation, member.user_id, v_tenant
  from (
    select distinct candidate.user_id
    from (values (v_task.created_by), (v_task.assigned_to), (v_actor))
      as candidate(user_id)
    where candidate.user_id is not null
  ) member
  where exists (
    select 1 from public.user_profiles profile
    where profile.user_id = member.user_id
      and profile.tenant_id = v_tenant
      and profile.is_active is true
  );

  begin
    insert into public.conversation_contexts (
      conversation_id, context_type, context_id, is_primary, added_by,
      tenant_id
    ) values (
      v_conversation, 'task', p_task_id, true, v_actor, v_tenant
    );
  exception when unique_violation then
    select context.conversation_id into v_existing
    from public.conversation_contexts context
    where context.context_type = 'task' and context.context_id = p_task_id
    limit 1;
    delete from public.conversation_participants
      where conversation_id = v_conversation;
    delete from public.conversations where id = v_conversation;
    insert into public.conversation_participants (
      conversation_id, user_id, tenant_id
    )
    select v_existing, v_actor, v_tenant
    where exists (
        select 1 from public.user_profiles profile
        where profile.user_id = v_actor
          and profile.tenant_id = v_tenant
          and profile.is_active is true
      )
      and not exists (
        select 1 from public.conversation_participants participant
        where participant.conversation_id = v_existing
          and participant.user_id = v_actor
      );
    v_root_message_id := public.smart_task_ensure_thread_root_v1(
      v_task, v_existing
    );
    return jsonb_build_object(
      'conversation_id', v_existing,
      'root_message_id', v_root_message_id,
      'created', false
    );
  end;

  v_root_message_id := public.smart_task_ensure_thread_root_v1(
    v_task, v_conversation
  );

  update public.smart_tasks set updated_at = now()
   where id = p_task_id
   returning * into v_task;
  perform public.smart_task_append_event(
    v_task, v_actor, 'conversation_linked',
    jsonb_build_object(
      'conversation_id', v_conversation,
      'root_message_id', v_root_message_id
    )
  );

  return jsonb_build_object(
    'conversation_id', v_conversation,
    'root_message_id', v_root_message_id,
    'created', true
  );
end;
$$;

grant execute on function public.smart_task_thread_get_or_create_v1(uuid)
  to authenticated;
revoke execute on function public.smart_task_thread_get_or_create_v1(uuid)
  from anon, public;

-- Native attachment publishing keeps the same reservation and verification
-- flow; this wrapper only binds the resulting message to an already-validated
-- root in the same transaction.
create or replace function public.publish_messaging_attachment_in_thread_v1(
  p_attachment_id uuid,
  p_caption text,
  p_thread_root_message_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'storage', 'pg_temp'
as $$
declare
  v_result jsonb;
  v_message_id uuid;
begin
  if p_thread_root_message_id is null then
    raise exception 'Thread root message is required'
      using errcode = '22023';
  end if;

  v_result := public.publish_messaging_attachment(
    p_attachment_id, p_caption
  );
  v_message_id := nullif(v_result->>'message_id', '')::uuid;
  if v_message_id is null then
    raise exception 'Attachment publish did not return a message'
      using errcode = 'P0002';
  end if;

  update public.messages message
  set thread_root_message_id = p_thread_root_message_id
  where message.id = v_message_id
    and message.sender_id = auth.uid();
  if not found then
    raise exception 'Published attachment message is not owned by the caller'
      using errcode = '42501';
  end if;

  return v_result || jsonb_build_object(
    'thread_root_message_id', p_thread_root_message_id
  );
end;
$$;

revoke all on function public.publish_messaging_attachment_in_thread_v1(
  uuid, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.publish_messaging_attachment_in_thread_v1(
  uuid, text, uuid
) to authenticated;

