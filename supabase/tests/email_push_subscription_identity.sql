begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(12);

select has_function(
  'public',
  'enforce_email_push_subscription_identity',
  array[]::text[],
  'push subscription identity has one trigger owner'
);
select has_trigger(
  'public',
  'email_push_subscriptions',
  'trg_email_push_subscription_identity',
  'push subscription writes pass through the identity guard'
);
select is(
  (
    select routine.prosecdef
      from pg_proc routine
     where routine.oid =
       'public.enforce_email_push_subscription_identity()'::regprocedure
  ),
  true,
  'identity guard is security definer so email_accounts remains server-only'
);
select is(
  (
    select array_to_string(routine.proconfig, ',')
      from pg_proc routine
     where routine.oid =
       'public.enforce_email_push_subscription_identity()'::regprocedure
  ),
  'search_path=""',
  'identity guard uses an empty trusted search path'
);

insert into public.tenants (id, shop_name)
values ('98e10000-0000-4000-8000-000000000001', 'Mail Push Guard Test');
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '98e10000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'mail-push@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  '{}'::jsonb,
  now(),
  now()
);
insert into public.user_profiles (user_id, tenant_id, role)
values (
  '98e10000-0000-4000-8000-000000000099',
  '98e10000-0000-4000-8000-000000000001',
  'admin'
);
insert into public.email_accounts (
  tenant_id, user_id, provider, account_email, refresh_token
)
values (
  '98e10000-0000-4000-8000-000000000001',
  '98e10000-0000-4000-8000-000000000099',
  'gmail',
  'canonical@gmail.example',
  'test-refresh-token'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '98e10000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98e10000-0000-4000-8000-000000000099',
  true
);

insert into public.email_push_subscriptions (
  user_id, tenant_id, provider, email_address,
  new_mail_notification, notification_data, last_notification_at
)
values (
  '98e10000-0000-4000-8000-000000000099',
  '98e10000-0000-4000-8000-000000000001',
  'gmail',
  'spoofed@gmail.example',
  true,
  '{"spoofed":true}'::jsonb,
  now()
);

select is(
  (select email_address from public.email_push_subscriptions
    where user_id = '98e10000-0000-4000-8000-000000000099'
      and provider = 'gmail'),
  'canonical@gmail.example',
  'authenticated insert derives the provider mailbox server-side'
);
select is(
  (select tenant_id from public.email_push_subscriptions
    where user_id = '98e10000-0000-4000-8000-000000000099'
      and provider = 'gmail'),
  '98e10000-0000-4000-8000-000000000001'::uuid,
  'authenticated insert derives the tenant server-side'
);
select is(
  (select new_mail_notification from public.email_push_subscriptions
    where user_id = '98e10000-0000-4000-8000-000000000099'
      and provider = 'gmail'),
  false,
  'authenticated insert cannot fabricate webhook evidence'
);
select is(
  (select notification_data from public.email_push_subscriptions
    where user_id = '98e10000-0000-4000-8000-000000000099'
      and provider = 'gmail'),
  null,
  'authenticated insert cannot fabricate notification payload'
);

select throws_ok(
  $$
    insert into public.email_push_subscriptions (
      user_id, tenant_id, provider, email_address
    ) values (
      '98e10000-0000-4000-8000-000000000099',
      '98e10000-0000-4000-8000-000000000001',
      'zoho',
      'unconnected@zoho.example'
    )
  $$,
  '42501',
  'Authenticated mail account is not connected',
  'an unconnected provider cannot create a subscription row'
);

select set_config(
  'request.jwt.claims',
  '{"role":"service_role"}',
  true
);
select set_config('request.jwt.claim.sub', '', true);
update public.email_push_subscriptions
   set new_mail_notification = true,
       notification_data = '{"historyId":"42"}'::jsonb,
       last_notification_at = '2026-08-14 02:00:00+00'
 where user_id = '98e10000-0000-4000-8000-000000000099'
   and provider = 'gmail';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '98e10000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '98e10000-0000-4000-8000-000000000099',
  true
);
update public.email_push_subscriptions
   set new_mail_notification = false,
       notification_data = '{"forged":true}'::jsonb,
       last_notification_at = '2099-01-01 00:00:00+00'
 where user_id = '98e10000-0000-4000-8000-000000000099'
   and provider = 'gmail';

select is(
  (select new_mail_notification from public.email_push_subscriptions
    where user_id = '98e10000-0000-4000-8000-000000000099'
      and provider = 'gmail'),
  false,
  'authenticated client may acknowledge a real notification'
);
select is(
  (select notification_data from public.email_push_subscriptions
    where user_id = '98e10000-0000-4000-8000-000000000099'
      and provider = 'gmail'),
  '{"historyId":"42"}'::jsonb,
  'authenticated acknowledgement cannot rewrite provider evidence'
);
select is(
  (select last_notification_at from public.email_push_subscriptions
    where user_id = '98e10000-0000-4000-8000-000000000099'
      and provider = 'gmail'),
  '2026-08-14 02:00:00+00'::timestamptz,
  'authenticated acknowledgement cannot rewrite provider time'
);

select * from finish();
rollback;
