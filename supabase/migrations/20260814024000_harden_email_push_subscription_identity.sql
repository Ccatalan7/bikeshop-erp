-- Deployment status: reviewed production-bound forward migration; guarded
-- production apply, exact read-back, and history registration are part of
-- this task.
-- Verification status: 12/12 focused pgTAP assertions pass on the local
-- candidate.
-- Compatibility-safe cutover for released clients that still renew Gmail
-- watches by upserting their own subscription row. The authenticated client
-- may manage transport hints for its row, but mailbox identity and webhook
-- evidence remain server-owned.

create or replace function public.enforce_email_push_subscription_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_tenant_id uuid;
  v_email_address text;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then
    return new;
  end if;

  if v_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authenticated mail subscription requires a user identity';
  end if;

  select account.tenant_id, account.account_email
    into v_tenant_id, v_email_address
    from public.email_accounts account
   where account.user_id = v_user_id
     and account.provider = new.provider
     and account.is_active is true
   limit 1;

  if not found then
    raise exception using
      errcode = '42501',
      message = 'Authenticated mail account is not connected';
  end if;

  new.user_id := v_user_id;
  new.tenant_id := v_tenant_id;
  new.email_address := v_email_address;

  if tg_op = 'INSERT' then
    new.new_mail_notification := false;
    new.notification_data := null;
    new.last_notification_at := null;
    new.error_message := null;
  else
    -- Authenticated clients may acknowledge true -> false for compatibility,
    -- but only a service-role webhook may create notification evidence.
    if coalesce(new.new_mail_notification, false)
       and not coalesce(old.new_mail_notification, false) then
      new.new_mail_notification := old.new_mail_notification;
    end if;
    new.notification_data := old.notification_data;
    new.last_notification_at := old.last_notification_at;
    new.error_message := old.error_message;
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_email_push_subscription_identity()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_email_push_subscription_identity
  on public.email_push_subscriptions;
create trigger trg_email_push_subscription_identity
before insert or update on public.email_push_subscriptions
for each row execute function public.enforce_email_push_subscription_identity();

comment on function public.enforce_email_push_subscription_identity() is
  'Derives authenticated push mailbox identity from server-owned email_accounts and protects webhook evidence while released clients migrate to provider Edge actions.';
