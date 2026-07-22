-- Restore exact read receipts after the Meta transport migration replaced the
-- shared tenant-consistency trigger with message-only NEW column references.
--
-- The generic function is also attached to conversation_participants and
-- conversation_contexts. PostgreSQL may evaluate SQL boolean operands in any
-- order, so guarding NEW.type with `tg_table_name = 'messages' AND ...` is not
-- sufficient for a participant row that has no `type` column. Use row-shaped
-- trigger functions for both non-message child tables and retain the existing
-- message transport validation unchanged.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $$
begin
  if to_regclass('public.conversations') is null
     or to_regclass('public.conversation_participants') is null
     or to_regclass('public.conversation_contexts') is null then
    raise exception 'Messaging conversation child tables are required';
  end if;
end;
$$;

create or replace function
  public.enforce_conversation_participant_tenant_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_parent_tenant_id uuid;
begin
  if new.conversation_id is null then
    raise exception 'conversation_participants conversation_id is required'
      using errcode = '23502';
  end if;

  select conversation.tenant_id
  into v_parent_tenant_id
  from public.conversations conversation
  where conversation.id = new.conversation_id;

  if v_parent_tenant_id is null then
    raise exception 'Parent conversation not found' using errcode = '23503';
  end if;

  if new.tenant_id is null then
    new.tenant_id := v_parent_tenant_id;
  elsif new.tenant_id is distinct from v_parent_tenant_id then
    raise exception 'conversation_participants tenant_id must match its conversation'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function
  public.enforce_conversation_context_tenant_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_parent_tenant_id uuid;
begin
  if new.conversation_id is null then
    raise exception 'conversation_contexts conversation_id is required'
      using errcode = '23502';
  end if;

  select conversation.tenant_id
  into v_parent_tenant_id
  from public.conversations conversation
  where conversation.id = new.conversation_id;

  if v_parent_tenant_id is null then
    raise exception 'Parent conversation not found' using errcode = '23503';
  end if;

  if new.tenant_id is null then
    new.tenant_id := v_parent_tenant_id;
  elsif new.tenant_id is distinct from v_parent_tenant_id then
    raise exception 'conversation_contexts tenant_id must match its conversation'
      using errcode = '23514';
  end if;

  if not public.messaging_context_belongs_to_tenant(
    new.context_type,
    new.context_id,
    v_parent_tenant_id
  ) then
    raise exception 'Messaging context does not belong to the conversation tenant'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_conversation_participants_tenant_consistency
  on public.conversation_participants;
create trigger trg_conversation_participants_tenant_consistency
before insert or update on public.conversation_participants
for each row execute function
  public.enforce_conversation_participant_tenant_consistency();

drop trigger if exists trg_conversation_contexts_tenant_consistency
  on public.conversation_contexts;
create trigger trg_conversation_contexts_tenant_consistency
before insert or update on public.conversation_contexts
for each row execute function
  public.enforce_conversation_context_tenant_consistency();

revoke all on function
  public.enforce_conversation_participant_tenant_consistency()
  from public, anon, authenticated, service_role;
revoke all on function
  public.enforce_conversation_context_tenant_consistency()
  from public, anon, authenticated, service_role;

comment on function
  public.enforce_conversation_participant_tenant_consistency()
is 'Canonicalizes participant tenant identity without inspecting message-only columns.';
comment on function
  public.enforce_conversation_context_tenant_consistency()
is 'Canonicalizes context tenant identity and validates retained context ownership without inspecting message-only columns.';

commit;
