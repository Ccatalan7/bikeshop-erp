-- Production read-back for 20260827210000.
-- Diagnostics precede SQL-level assertions so any failure exposes its cause.

with expected(signature) as (
  values
    ('public.is_current_worker_to_erp_invitation(uuid,uuid,jsonb)'),
    ('public.guard_erp_invitation_employee_access()'),
    ('public.is_authoritative_worker_portal_identity(uuid,uuid,uuid)'),
    ('public.guard_worker_portal_identity()'),
    ('public.prepare_worker_transition_credential(uuid,uuid)'),
    ('public.finish_worker_transition_credential(uuid,uuid,timestamp with time zone)'),
    ('public.guard_company_principal_employee_link()'),
    ('public.transfer_open_employee_tasks_v1(uuid,uuid,uuid,uuid,uuid,text)'),
    ('public.switch_worker_to_erp_user(uuid,uuid)'),
    ('public.switch_erp_user_to_worker(uuid,uuid,uuid)'),
    ('public.accept_user_invitation(text)')
)
select
  expected.signature,
  to_regprocedure(expected.signature) is not null as installed,
  md5(pg_get_functiondef(to_regprocedure(expected.signature))) as definition_md5
from expected
order by expected.signature;

select
  trigger.tgname,
  trigger.tgenabled,
  pg_get_triggerdef(trigger.oid) as definition
from pg_trigger trigger
where trigger.tgrelid = 'public.employees'::regclass
  and trigger.tgname = 'trg_guard_company_principal_employee_link'
  and not trigger.tgisinternal;

select
  count(*) filter (
    where activity.action = 'employee_access_switched_worker_to_erp'
  ) as worker_to_erp_transitions,
  count(*) filter (
    where activity.action = 'employee_access_switched_erp_to_worker'
  ) as erp_to_worker_transitions
from public.user_activity_log activity;

select 1 / (case when (
  select count(*)
  from (values
    ('public.is_current_worker_to_erp_invitation(uuid,uuid,jsonb)'),
    ('public.guard_erp_invitation_employee_access()'),
    ('public.is_authoritative_worker_portal_identity(uuid,uuid,uuid)'),
    ('public.guard_worker_portal_identity()'),
    ('public.prepare_worker_transition_credential(uuid,uuid)'),
    ('public.finish_worker_transition_credential(uuid,uuid,timestamp with time zone)'),
    ('public.guard_company_principal_employee_link()'),
    ('public.transfer_open_employee_tasks_v1(uuid,uuid,uuid,uuid,uuid,text)'),
    ('public.switch_worker_to_erp_user(uuid,uuid)'),
    ('public.switch_erp_user_to_worker(uuid,uuid,uuid)'),
    ('public.accept_user_invitation(text)')
  ) expected(signature)
  where to_regprocedure(expected.signature) is not null
) = 11 then 1 else 0 end) as all_transition_functions_are_installed;

select 1 / (case when
  has_function_privilege(
    'authenticated',
    'public.switch_worker_to_erp_user(uuid,uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.switch_erp_user_to_worker(uuid,uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.switch_worker_to_erp_user(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.switch_erp_user_to_worker(uuid,uuid,uuid)',
    'EXECUTE'
  )
then 1 else 0 end) as transition_commands_are_authenticated_only;

select 1 / (case when
  has_function_privilege(
    'service_role',
    'public.prepare_worker_transition_credential(uuid,uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.finish_worker_transition_credential(uuid,uuid,timestamp with time zone)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.prepare_worker_transition_credential(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.finish_worker_transition_credential(uuid,uuid,timestamp with time zone)',
    'EXECUTE'
  )
then 1 else 0 end) as credential_preparation_is_service_only;

select 1 / (case when exists (
  select 1
  from pg_trigger trigger
  where trigger.tgrelid = 'public.employees'::regclass
    and trigger.tgname = 'trg_guard_company_principal_employee_link'
    and trigger.tgenabled <> 'D'
    and pg_get_triggerdef(trigger.oid) like '%BEFORE INSERT OR UPDATE%'
    and not trigger.tgisinternal
) then 1 else 0 end) as company_owner_guard_covers_insert_and_update;

select 1 / (case when not exists (
  select 1
  from public.employees employee
  join public.employee_portal_accounts portal
    on portal.tenant_id = employee.tenant_id
   and portal.employee_id = employee.id
   and portal.is_active is true
  where employee.user_id is not null
     or exists (
       select 1
       from public.user_profiles profile
       where profile.tenant_id = employee.tenant_id
         and profile.employee_id = employee.id
     )
) then 1 else 0 end) as no_worker_has_simultaneous_erp_and_worker_authority;

select 1 / (case when not exists (
  select 1
  from public.user_invitations invitation
  where invitation.status = 'pending'
    and invitation.employee_id is not null
    and exists (
      select 1
      from public.employee_portal_accounts portal
      where portal.tenant_id = invitation.tenant_id
        and portal.employee_id = invitation.employee_id
        and portal.is_active is true
    )
    and not public.is_current_worker_to_erp_invitation(
      invitation.tenant_id,
      invitation.employee_id,
      invitation.metadata
    )
) then 1 else 0 end) as every_pending_worker_overlap_is_an_exact_transition;

select 1 / (case when not exists (
  select 1
  from public.employees employee
  where employee.user_id is not null
    and public.is_auth_user_db_backed_tenant_owner(
      employee.user_id,
      employee.tenant_id
    )
) and not exists (
  select 1
  from public.user_profiles profile
  where profile.employee_id is not null
    and public.is_auth_user_db_backed_tenant_owner(
      profile.user_id,
      profile.tenant_id
    )
) then 1 else 0 end) as company_principals_are_not_workers;
