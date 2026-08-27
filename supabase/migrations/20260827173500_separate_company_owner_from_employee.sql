-- Separate the tenant-wide company owner identity from Claudio's employee
-- identity. The corporate account represents Viñabike as a whole; it must not
-- borrow one worker's HR/payroll identity. Claudio's personal ERP account is
-- the bilateral owner of his employee row after this repair.
--
-- Forward scope:
--   * exactly two active ERP profiles and one active employee row;
--   * no roles, permissions, Auth identities, tasks, payroll or history change;
--   * the existing canonical unlink/link commands write both activity events.
-- Recovery:
--   use the same canonical commands in the inverse direction only if the
--   business owner explicitly declares this identity mapping incorrect.
-- Lock risk:
--   bounded to the two Auth identities and one employee via the canonical
--   advisory/row locks; there is no scan or broad backfill.
-- Re-execution:
--   the final state is accepted as a no-op. Any partial or different mapping
--   fails closed instead of guessing.

begin;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '7bb76d88-5455-462e-a838-5f78af922914',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '7bb76d88-5455-462e-a838-5f78af922914',
  true
);

do $identity_repair$
declare
  company_owner_user_id constant uuid :=
    '7bb76d88-5455-462e-a838-5f78af922914';
  personal_user_id constant uuid :=
    'f0d091c5-85cc-4c7b-8688-fc352b0e8136';
  claudio_employee_id constant uuid :=
    'e558e411-6ac0-415f-8ac0-0653c2ac0bfa';
  company_profile public.user_profiles%rowtype;
  personal_profile public.user_profiles%rowtype;
  employee_row public.employees%rowtype;
  company_account_type text;
  personal_account_type text;
  company_display_name text;
  tenant_shop_name text;
  command_receipt jsonb;
begin
  -- Disposable/local databases do not carry this tenant-specific identity.
  -- A partially present identity set is drift and must not be ignored.
  if not exists (
    select 1 from auth.users where id = company_owner_user_id
  ) and not exists (
    select 1 from auth.users where id = personal_user_id
  ) and not exists (
    select 1 from public.employees where id = claudio_employee_id
  ) then
    raise notice 'Viñabike production identity set absent; migration is a no-op';
    return;
  end if;

  select profile.*
  into company_profile
  from public.user_profiles profile
  where profile.user_id = company_owner_user_id
    and profile.is_active is true
  for update;

  if not found then
    raise exception 'company_owner_profile_missing_or_inactive';
  end if;

  select profile.*
  into personal_profile
  from public.user_profiles profile
  where profile.user_id = personal_user_id
    and profile.is_active is true
  for update;

  if not found then
    raise exception 'personal_staff_profile_missing_or_inactive';
  end if;

  select employee.*
  into employee_row
  from public.employees employee
  where employee.id = claudio_employee_id
    and employee.status = 'active'
  for update;

  if not found then
    raise exception 'claudio_employee_missing_or_inactive';
  end if;

  if company_profile.tenant_id <> personal_profile.tenant_id
     or company_profile.tenant_id <> employee_row.tenant_id then
    raise exception 'company_personal_employee_tenant_mismatch';
  end if;

  select
    coalesce(company_user.raw_app_meta_data->>'account_type', ''),
    nullif(btrim(company_user.raw_user_meta_data->>'display_name'), ''),
    tenant.shop_name
  into company_account_type, company_display_name, tenant_shop_name
  from auth.users company_user
  join public.tenants tenant
    on tenant.id = company_profile.tenant_id
   and tenant.is_active is true
  where company_user.id = company_owner_user_id;

  select coalesce(personal_user.raw_app_meta_data->>'account_type', '')
  into personal_account_type
  from auth.users personal_user
  where personal_user.id = personal_user_id;

  if company_account_type <> 'erp_owner'
     or company_display_name is distinct from tenant_shop_name then
    raise exception 'company_owner_identity_drift';
  end if;

  if personal_account_type <> 'erp_staff' then
    raise exception 'personal_staff_identity_drift';
  end if;

  if exists (
    select 1
    from public.employee_portal_accounts portal
    where portal.employee_id = claudio_employee_id
      and portal.tenant_id = employee_row.tenant_id
      and portal.is_active is true
  ) then
    raise exception 'claudio_employee_has_active_worker_portal';
  end if;

  -- Exact final state: safe replay, no duplicate activity rows.
  if company_profile.employee_id is null
     and employee_row.user_id = personal_user_id
     and personal_profile.employee_id = claudio_employee_id then
    return;
  end if;

  -- Only the observed legacy mapping is accepted as a forward starting point.
  if company_profile.employee_id is distinct from claudio_employee_id
     or employee_row.user_id is distinct from company_owner_user_id
     or personal_profile.employee_id is not null then
    raise exception 'company_employee_identity_unexpected_starting_state';
  end if;

  command_receipt := public.unlink_erp_user_from_employee(
    company_owner_user_id,
    claudio_employee_id
  );

  if command_receipt->>'success' <> 'true'
     or command_receipt->>'linked' <> 'false' then
    raise exception 'company_owner_unlink_failed';
  end if;

  command_receipt := public.link_erp_user_to_employee(
    personal_user_id,
    claudio_employee_id
  );

  if command_receipt->>'success' <> 'true'
     or command_receipt->>'linked' <> 'true' then
    raise exception 'personal_employee_link_failed';
  end if;

  if not exists (
    select 1
    from public.user_profiles profile
    join public.employees employee
      on employee.id = profile.employee_id
     and employee.tenant_id = profile.tenant_id
     and employee.user_id = profile.user_id
    where profile.user_id = personal_user_id
      and profile.employee_id = claudio_employee_id
      and profile.is_active is true
      and employee.status = 'active'
  ) or exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = company_owner_user_id
      and profile.employee_id is not null
  ) then
    raise exception 'company_employee_identity_final_state_failed';
  end if;
end
$identity_repair$;

commit;
