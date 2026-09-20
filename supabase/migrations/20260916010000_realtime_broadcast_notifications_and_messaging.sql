-- 20260916010000: move ERP notifications and messaging change signals from
-- postgres_changes subscriptions to tenant-private Broadcast topics emitted
-- by triggers, the pattern 20260726164000 already uses for the financial
-- projection.
--
-- Why
--   Every postgres_changes subscriber makes Realtime run realtime.apply_rls
--   for each WAL change on the subscribed table: on 2026-09-15 messages and
--   erp_notifications carried 4 live subscriptions each (desktop toasts, the
--   workspace badge, the chat inbox on conversations + participants +
--   messages with no tenant filter) and realtime.list_changes was 66% of all
--   database time. A Broadcast row is authorized once at channel join
--   (realtime.messages RLS) and never re-evaluated per change.
--
-- Forward behaviour
--   * erp_notifications: AFTER INSERT OR UPDATE sends the full row (the same
--     payload postgres_changes delivered) to
--     'erp-notifications:<tenant_id>:<recipient_user_id>' or, when the row has
--     no recipient, to 'erp-notifications:<tenant_id>:all'. A member can
--     only join the ':all' topic of their tenant and their own user topic,
--     which preserves the erp_notifications_select semantics.
--   * messages (AFTER INSERT OR UPDATE), conversations and
--     conversation_participants (AFTER INSERT OR UPDATE OR DELETE) send a
--     payload-minimal signal to 'messaging:<tenant_id>': table, operation,
--     ids and, for a message update, external_status (delivery receipts).
--     No content, sender or participant identity travels; the client
--     re-reads through PostgREST under RLS before presenting anything.
--   * Store customers have no user_profiles row, so user_tenant_id() is null
--     for them and they cannot join these topics; the storefront chat keeps
--     its RLS-scoped postgres_changes path.
-- Recovery
--   Idempotent (create or replace / drop-create). Dropping the four triggers
--   and two policies restores the previous behaviour; the client falls back
--   to postgres_changes on channel errors.
-- Locks
--   CREATE TRIGGER takes SHARE ROW EXCLUSIVE on its table briefly; all four
--   tables are small.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = public, pg_temp;

create or replace function public.broadcast_erp_notification_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_record jsonb;
  v_topic text;
begin
  -- jsonb access keeps the function valid on fixtures that predate the
  -- recipient_user_id column (the local baseline does).
  v_record := to_jsonb(new);
  if nullif(v_record ->> 'tenant_id', '') is null then
    return new;
  end if;
  v_topic := 'erp-notifications:' || (v_record ->> 'tenant_id') || ':'
    || coalesce(nullif(v_record ->> 'recipient_user_id', ''), 'all');
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then
    -- Public-only validation clones omit the managed realtime schema.
    return new;
  end if;
  perform realtime.send(
    jsonb_build_object(
      'event_id', gen_random_uuid()::text,
      'operation', lower(tg_op),
      'record', v_record
    ),
    'changed',
    v_topic,
    true
  );
  return new;
end;
$$;

revoke all on function public.broadcast_erp_notification_change()
  from public, anon, authenticated, service_role;
comment on function public.broadcast_erp_notification_change() is
  'Broadcasts each ERP notification row to its recipient''s private topic (or the tenant ''all'' topic) so clients do not need a postgres_changes subscription.';

create or replace function public.broadcast_messaging_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_record jsonb;
  v_tenant_id uuid;
  v_payload jsonb;
begin
  v_record := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_tenant_id := nullif(v_record ->> 'tenant_id', '')::uuid;
  if v_tenant_id is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  v_payload := jsonb_build_object(
    'event_id', gen_random_uuid()::text,
    'table', tg_table_name,
    'operation', lower(tg_op)
  );
  if tg_table_name = 'messages' then
    v_payload := v_payload || jsonb_build_object(
      'message_id', v_record ->> 'id',
      'conversation_id', v_record ->> 'conversation_id',
      'external_status', v_record ->> 'external_status'
    );
  elsif tg_table_name = 'conversations' then
    v_payload := v_payload || jsonb_build_object(
      'conversation_id', v_record ->> 'id'
    );
  else
    v_payload := v_payload || jsonb_build_object(
      'conversation_id', v_record ->> 'conversation_id'
    );
  end if;
  if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is not null then
    perform realtime.send(
      v_payload,
      'changed',
      'messaging:' || v_tenant_id::text,
      true
    );
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.broadcast_messaging_change()
  from public, anon, authenticated, service_role;
comment on function public.broadcast_messaging_change() is
  'Broadcasts a payload-minimal change signal (table, operation, ids, delivery status) to the tenant''s private messaging topic; content never travels through Realtime.';

drop trigger if exists trg_erp_notifications_broadcast on public.erp_notifications;
create trigger trg_erp_notifications_broadcast
  after insert or update on public.erp_notifications
  for each row execute function public.broadcast_erp_notification_change();

drop trigger if exists trg_messages_broadcast on public.messages;
create trigger trg_messages_broadcast
  after insert or update on public.messages
  for each row execute function public.broadcast_messaging_change();

drop trigger if exists trg_conversations_broadcast on public.conversations;
create trigger trg_conversations_broadcast
  after insert or update or delete on public.conversations
  for each row execute function public.broadcast_messaging_change();

drop trigger if exists trg_conversation_participants_broadcast on public.conversation_participants;
create trigger trg_conversation_participants_broadcast
  after insert or update or delete on public.conversation_participants
  for each row execute function public.broadcast_messaging_change();

do $$
begin
  -- Realtime authorizes a private channel by inserting and reading a
  -- synthetic realtime.messages row inside a rolled-back transaction, so the
  -- policy must not filter on the durable `private` column (see
  -- 20260726170500). Only the topic and the extension are checked.
  if to_regclass('realtime.messages') is not null then
    execute 'drop policy if exists "Tenant members receive ERP notification broadcasts" on realtime.messages';
    execute $policy$
      create policy "Tenant members receive ERP notification broadcasts"
        on realtime.messages
        for select
        to authenticated
        using (
          extension = 'broadcast'
          and (select realtime.topic()) in (
            'erp-notifications:' || (select public.user_tenant_id())::text || ':all',
            'erp-notifications:' || (select public.user_tenant_id())::text || ':'
              || (select auth.uid())::text
          )
        )
    $policy$;
    execute 'drop policy if exists "Tenant members receive messaging broadcasts" on realtime.messages';
    execute $policy$
      create policy "Tenant members receive messaging broadcasts"
        on realtime.messages
        for select
        to authenticated
        using (
          extension = 'broadcast'
          and (select realtime.topic()) =
            'messaging:' || (select public.user_tenant_id())::text
        )
    $policy$;
  end if;
end
$$;

commit;
