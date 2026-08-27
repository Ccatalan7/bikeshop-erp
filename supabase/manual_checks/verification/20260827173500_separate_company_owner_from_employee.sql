-- Production read-back for 20260827173500.
-- Diagnostics precede SQL-level assertions so a failure explains the drift.

select
  auth_user.id as user_id,
  auth_user.raw_app_meta_data->>'account_type' as account_type,
  auth_user.raw_user_meta_data->>'display_name' as account_display_name,
  profile.employee_id,
  profile.role,
  profile.is_active
from auth.users auth_user
join public.user_profiles profile on profile.user_id = auth_user.id
where auth_user.id in (
  '7bb76d88-5455-462e-a838-5f78af922914'::uuid,
  'f0d091c5-85cc-4c7b-8688-fc352b0e8136'::uuid
)
order by auth_user.id;

select id, first_name, last_name, user_id, status
from public.employees
where id = 'e558e411-6ac0-415f-8ac0-0653c2ac0bfa'::uuid;

select 1 / (case when exists (
  select 1
  from auth.users auth_user
  join public.user_profiles profile on profile.user_id = auth_user.id
  join public.tenants tenant on tenant.id = profile.tenant_id
  where auth_user.id = '7bb76d88-5455-462e-a838-5f78af922914'::uuid
    and auth_user.raw_app_meta_data->>'account_type' = 'erp_owner'
    and auth_user.raw_user_meta_data->>'display_name' = tenant.shop_name
    and tenant.shop_name = 'Viñabike'
    and profile.employee_id is null
    and profile.is_active is true
    and not exists (
      select 1 from public.employees employee
      where employee.user_id = auth_user.id
    )
) then 1 else 0 end) as company_owner_is_not_an_employee;

select 1 / (case when exists (
  select 1
  from auth.users auth_user
  join public.user_profiles profile on profile.user_id = auth_user.id
  join public.employees employee
    on employee.id = profile.employee_id
   and employee.tenant_id = profile.tenant_id
   and employee.user_id = profile.user_id
  where auth_user.id = 'f0d091c5-85cc-4c7b-8688-fc352b0e8136'::uuid
    and auth_user.raw_app_meta_data->>'account_type' = 'erp_staff'
    and profile.employee_id = 'e558e411-6ac0-415f-8ac0-0653c2ac0bfa'::uuid
    and profile.is_active is true
    and btrim(employee.first_name) = 'Claudio'
    and btrim(employee.last_name) = 'Catalán'
    and employee.status = 'active'
) then 1 else 0 end) as personal_user_owns_claudio_employee_identity;

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

select user_id, employee_id, display_name, role, access
from public.get_smart_task_assignment_directory_v1()
where user_id in (
  '7bb76d88-5455-462e-a838-5f78af922914'::uuid,
  'f0d091c5-85cc-4c7b-8688-fc352b0e8136'::uuid
)
order by user_id;

select 1 / (case when (
  select count(*)
  from public.get_smart_task_assignment_directory_v1() directory
  where (
    directory.user_id = '7bb76d88-5455-462e-a838-5f78af922914'::uuid
    and directory.employee_id is null
    and directory.display_name = 'Viñabike'
    and directory.access = 'erp'
  ) or (
    directory.user_id = 'f0d091c5-85cc-4c7b-8688-fc352b0e8136'::uuid
    and directory.employee_id = 'e558e411-6ac0-415f-8ac0-0653c2ac0bfa'::uuid
    and directory.display_name = 'Claudio Catalán'
    and directory.access = 'erp'
  )
) = 2 then 1 else 0 end) as assignment_directory_separates_company_and_person;

select 1 / (case when exists (
  select 1
  from public.user_activity_log activity
  where activity.user_id = '7bb76d88-5455-462e-a838-5f78af922914'::uuid
    and activity.action = 'employee_erp_identity_unlinked'
    and activity.details->>'employee_id' =
      'e558e411-6ac0-415f-8ac0-0653c2ac0bfa'
) and exists (
  select 1
  from public.user_activity_log activity
  where activity.user_id = 'f0d091c5-85cc-4c7b-8688-fc352b0e8136'::uuid
    and activity.action = 'employee_erp_identity_linked'
    and activity.details->>'employee_id' =
      'e558e411-6ac0-415f-8ac0-0653c2ac0bfa'
) then 1 else 0 end) as identity_transfer_is_audited;
