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

-- The other door the same migration fixed: turning an ERP user back into a
-- worker reads the ban of the Worker identity it is switching to.
set local session_replication_role = replica;
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  -- The person as an ERP user today.
  'eb000000-0000-4000-8000-000000000005',
  'authenticated', 'authenticated', 'vicente.erp@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
), (
  -- And the Worker credential already prepared for him, suspended a week ago.
  'eb000000-0000-4000-8000-000000000006',
  'authenticated', 'authenticated', 'vicente.worker@example.invalid',
  '', now(),
  jsonb_build_object(
    'account_type', 'worker_portal',
    'tenant_id', 'eb000000-0000-4000-8000-000000000001',
    'employee_id', 'eb000000-0000-4000-8000-000000000031',
    'role', 'worker'
  ),
  '{}'::jsonb, now(), now()
);
update auth.users
   set banned_until = now() - interval '7 days'
 where id = 'eb000000-0000-4000-8000-000000000006';
set local session_replication_role = origin;

insert into public.employees (
  id, tenant_id, employee_number, first_name, last_name, job_title, status,
  user_id
) values (
  'eb000000-0000-4000-8000-000000000031',
  'eb000000-0000-4000-8000-000000000001',
  'E-2', 'Vicente', 'Díaz', 'Mecánico', 'active',
  'eb000000-0000-4000-8000-000000000005'
);
insert into public.user_profiles (
  id, user_id, tenant_id, employee_id, role, permissions, is_active
) values (
  'eb000000-0000-4000-8000-000000000006',
  'eb000000-0000-4000-8000-000000000005',
  'eb000000-0000-4000-8000-000000000001',
  'eb000000-0000-4000-8000-000000000031',
  'mechanic', '{}'::jsonb, true
);
-- Prepared, not yet in use: that is what the switch expects to find.
insert into public.employee_portal_accounts (
  id, tenant_id, employee_id, auth_user_id, username, login_email,
  is_active, must_reset_password, password_credential_issued_at, created_by
) values (
  'eb000000-0000-4000-8000-000000000041',
  'eb000000-0000-4000-8000-000000000001',
  'eb000000-0000-4000-8000-000000000031',
  'eb000000-0000-4000-8000-000000000006',
  'vicente', 'vicente@example.invalid', false, true, now(),
  'eb000000-0000-4000-8000-000000000003'
);

update auth.users
   set banned_until = now() + interval '1 day'
 where id = 'eb000000-0000-4000-8000-000000000006';

select throws_like(
  $$select public.switch_erp_user_to_worker(
      'eb000000-0000-4000-8000-000000000005',
      'eb000000-0000-4000-8000-000000000031',
      'eb000000-0000-4000-8000-000000000041'
    )$$,
  '%worker_identity_conflict%',
  'a running ban stops the switch to Worker'
);

update auth.users
   set banned_until = now() - interval '7 days'
 where id = 'eb000000-0000-4000-8000-000000000006';

select lives_ok(
  $$select public.switch_erp_user_to_worker(
      'eb000000-0000-4000-8000-000000000005',
      'eb000000-0000-4000-8000-000000000031',
      'eb000000-0000-4000-8000-000000000041'
    )$$,
  'an expired ban does not stop it'
);

select results_eq(
  $$select portal.is_active, employee.user_id is null, profile.is_active
      from public.employee_portal_accounts portal
      join public.employees employee on employee.id = portal.employee_id
      join public.user_profiles profile
        on profile.id = 'eb000000-0000-4000-8000-000000000006'
     where portal.id = 'eb000000-0000-4000-8000-000000000041'$$,
  $$values (true, true, false)$$,
  'and the person ends up as a worker, with the ERP profile closed'
);

select * from finish();
rollback;
