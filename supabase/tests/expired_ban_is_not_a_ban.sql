begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

insert into public.tenants (id, shop_name, timezone) values
  ('eb000000-0000-4000-8000-000000000001', 'Bloqueo vencido',
   'America/Santiago');

insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, job_title, status
) values (
  'eb000000-0000-4000-8000-000000000030',
  'eb000000-0000-4000-8000-000000000001',
  'E-1', 'Braulio', 'Muñoz', 'Mecánico', 'active'
);

set local session_replication_role = replica;
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, banned_until
) values (
  'eb000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'expired-ban@example.invalid',
  '', now(),
  jsonb_build_object(
    'account_type', 'worker_portal',
    'tenant_id', 'eb000000-0000-4000-8000-000000000001',
    'employee_id', 'eb000000-0000-4000-8000-000000000030',
    'role', 'worker'
  ),
  '{}'::jsonb, now(), now(),
  -- Suspended for a day, a week ago.
  now() - interval '7 days'
);
-- The shop's own user, who is the one keeping the account.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'eb000000-0000-4000-8000-000000000003',
  'authenticated', 'authenticated', 'jefe@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'eb000000-0000-4000-8000-000000000004',
  'eb000000-0000-4000-8000-000000000003',
  'eb000000-0000-4000-8000-000000000001',
  'admin', '{"access_hr":true}'::jsonb, true
);
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"eb000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', 'eb000000-0000-4000-8000-000000000003', true
);

-- The portal account is what the workshop keeps for a worker; its trigger
-- demands an authoritative Worker identity on every write.
select lives_ok(
  $$insert into public.employee_portal_accounts (
      id, tenant_id, employee_id, auth_user_id, username, login_email,
      is_active, must_reset_password, created_by
    ) values (
      'eb000000-0000-4000-8000-000000000040',
      'eb000000-0000-4000-8000-000000000001',
      'eb000000-0000-4000-8000-000000000030',
      'eb000000-0000-4000-8000-000000000002',
      'braulio', 'braulio@example.invalid', true, false,
      'eb000000-0000-4000-8000-000000000003'
    )$$,
  'a ban that already expired does not close the worker portal account'
);

-- The guard watches the identity columns, so reactivating the account is
-- what asks it the question again.
select lives_ok(
  $$update public.employee_portal_accounts
       set is_active = false
     where id = 'eb000000-0000-4000-8000-000000000040'$$,
  'the account can be closed'
);

select lives_ok(
  $$update public.employee_portal_accounts
       set is_active = true
     where id = 'eb000000-0000-4000-8000-000000000040'$$,
  'and reopened while the ban stays expired'
);

-- A ban that has not expired still closes it, which is the point.
update auth.users
   set banned_until = now() + interval '1 day'
 where id = 'eb000000-0000-4000-8000-000000000002';

update public.employee_portal_accounts
   set is_active = false
 where id = 'eb000000-0000-4000-8000-000000000040';

select throws_like(
  $$update public.employee_portal_accounts
       set is_active = true
     where id = 'eb000000-0000-4000-8000-000000000040'$$,
  '%Authoritative worker portal identity is required%',
  'a ban still running closes it'
);

-- What the worker is allowed to see follows the same rule.
select is(
  public.is_authoritative_worker_portal_identity(
    'eb000000-0000-4000-8000-000000000002',
    'eb000000-0000-4000-8000-000000000001',
    'eb000000-0000-4000-8000-000000000030'
  ),
  false,
  'while the ban runs the identity is not authoritative'
);

-- Once it expires, the shop can reopen the account and the worker is
-- himself again.
update auth.users
   set banned_until = now() - interval '1 hour'
 where id = 'eb000000-0000-4000-8000-000000000002';

select lives_ok(
  $$update public.employee_portal_accounts
       set is_active = true
     where id = 'eb000000-0000-4000-8000-000000000040'$$,
  'the suspension lifts on its own and the account reopens'
);

select is(
  public.is_authoritative_worker_portal_identity(
    'eb000000-0000-4000-8000-000000000002',
    'eb000000-0000-4000-8000-000000000001',
    'eb000000-0000-4000-8000-000000000030'
  ),
  true,
  'once it expires the worker is authoritative again'
);

select * from finish();
rollback;
