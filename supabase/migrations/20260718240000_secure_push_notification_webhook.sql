-- Replace the legacy Database Webhook trigger that embedded a long-lived
-- service-role JWT in pg_trigger.tgargs. Push delivery now uses a dedicated,
-- least-privilege shared secret kept in Supabase Vault and mirrored into the
-- Edge Function secret PUSH_NOTIFICATION_WEBHOOK_SECRET.
--
-- Deployment is intentionally fail-closed: if the Vault secret is absent,
-- message inserts still commit but no outbound request is queued. The Edge
-- Function independently rejects every request without the matching header.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

do $$
begin
  if to_regclass('public.messages') is null then
    raise exception 'Messaging foundation must exist before securing push delivery';
  end if;

  if not exists (
    select 1 from pg_extension where extname = 'pg_net'
  ) then
    raise exception 'pg_net extension is required for push delivery';
  end if;

  if not exists (
    select 1 from pg_extension where extname = 'supabase_vault'
  ) then
    raise exception 'Supabase Vault is required for push delivery';
  end if;
end;
$$;

create or replace function public.invoke_push_notification_for_message()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net, pg_catalog
as $$
declare
  v_webhook_secret text;
begin
  select secret.decrypted_secret
    into v_webhook_secret
    from vault.decrypted_secrets secret
   where secret.name = 'push_notification_webhook_secret'
     and nullif(secret.decrypted_secret, '') is not null
   order by secret.created_at desc
   limit 1;

  -- Missing configuration must never turn a chat write into a phantom failure.
  -- The notification is skipped and can be diagnosed from secret presence;
  -- the message itself remains the authoritative committed record.
  if nullif(v_webhook_secret, '') is null then
    return new;
  end if;

  perform net.http_post(
    url := 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-webhook-secret', v_webhook_secret
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'table', 'messages',
      'schema', 'public',
      'record', to_jsonb(new)
    ),
    timeout_milliseconds := 5000
  );

  return new;
exception
  when others then
    -- The request queue is ancillary to the durable message. Never surface a
    -- credential or make a successful insert look failed because push is down.
    raise warning 'Push notification request could not be queued';
    return new;
end;
$$;

revoke all on function public.invoke_push_notification_for_message()
  from public, anon, authenticated, service_role;

comment on function public.invoke_push_notification_for_message() is
  'Queues an authenticated push-notification Edge request using a dedicated Vault secret; message writes fail open while dispatch fails closed.';

-- Remove the legacy Supabase Dashboard webhook first. Its trigger arguments
-- contained a bearer credential. Replays are safe regardless of which trigger
-- name is currently installed.
drop trigger if exists "push-on-message" on public.messages;
drop trigger if exists trg_messages_push_notification on public.messages;

create trigger trg_messages_push_notification
  after insert on public.messages
  for each row execute function public.invoke_push_notification_for_message();

comment on trigger trg_messages_push_notification on public.messages is
  'Push dispatch trigger with no embedded credential; authentication material is read from Vault at execution time.';

commit;
