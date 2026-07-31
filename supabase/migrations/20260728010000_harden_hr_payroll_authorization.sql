-- Harden HR, attendance, planning, payroll, and employee PII authorization.
-- Deployment status: NOT DEPLOYED. Production deployment only through the
-- owner-authorized checkpoint in docs/development/PAYROLL_COMPLETION_PLAN.md.
-- Recovery: restore the prior table policies/function definitions from the
-- immediately preceding schema snapshot. No data rewrite or backfill occurs.
-- Lock risk: brief catalog locks while RLS policies and function ACLs change.
-- Atomicity: this file runs as one explicit transaction; a mid-file failure
-- rolls back every change (no CONCURRENTLY/VACUUM/enum-value statements).

begin;

-- Resolve the signed-in ERP tenant only from authoritative DB/Auth state.
-- Worker Portal identities deliberately resolve to NULL.
create or replace function public.erp_member_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
  select case
    when count(*) = 1 then (array_agg(profile.tenant_id))[1]
    else null
  end
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  join auth.users auth_user
    on auth_user.id = profile.user_id
  where profile.user_id = auth.uid()
    and profile.is_active is true
    and (
      auth_user.banned_until is null
      or auth_user.banned_until <= statement_timestamp()
    )
    and coalesce(
      auth_user.raw_app_meta_data->>'account_type',
      ''
    ) in ('erp_owner', 'erp_staff')
    and not exists (
      select 1
      from public.employee_portal_accounts portal
      where portal.auth_user_id = profile.user_id
        and portal.is_active is true
    )
$$;

revoke all on function public.erp_member_tenant_id()
  from public, anon, authenticated, service_role;
grant execute on function public.erp_member_tenant_id()
  to authenticated, service_role;

-- A self-service employee is accepted only when both sides of the ERP link,
-- the tenant, the employee lifecycle, and the Auth account type agree.
create or replace function public.current_erp_employee_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
  select case
    when count(*) = 1 then (array_agg(employee.id))[1]
    else null
  end
  from public.user_profiles profile
  join public.employees employee
    on employee.id = profile.employee_id
   and employee.tenant_id = profile.tenant_id
   and employee.user_id = profile.user_id
   and employee.status = 'active'
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  join auth.users auth_user
    on auth_user.id = profile.user_id
  where profile.user_id = auth.uid()
    and profile.is_active is true
    and profile.tenant_id = public.erp_member_tenant_id()
    and (
      auth_user.banned_until is null
      or auth_user.banned_until <= statement_timestamp()
    )
    and coalesce(
      auth_user.raw_app_meta_data->>'account_type',
      ''
    ) in ('erp_owner', 'erp_staff')
    and (
      select count(*)
      from public.employees employee_side
      where employee_side.user_id = profile.user_id
    ) = 1
    and not exists (
      select 1
      from public.employee_portal_accounts portal
      where portal.employee_id = employee.id
        and portal.tenant_id = employee.tenant_id
        and portal.is_active is true
    )
$$;

revoke all on function public.current_erp_employee_id()
  from public, anon, authenticated, service_role;
grant execute on function public.current_erp_employee_id()
  to authenticated, service_role;

-- Scope the existing broad tenant capabilities to an authoritative ERP Auth
-- identity. This prevents a still-valid JWT for a currently banned account
-- from retaining HR or payroll authority.
create or replace function public.can_manage_tenant_hr(
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select coalesce(
    p_tenant_id = public.erp_member_tenant_id()
    and public.can_manage_tenant_users(p_tenant_id),
    false
  )
$$;

revoke all on function public.can_manage_tenant_hr(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.can_manage_tenant_hr(uuid)
  to authenticated, service_role;

create or replace function public.can_manage_tenant_payroll(
  p_tenant_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select coalesce(
    p_tenant_id = public.erp_member_tenant_id()
    and public.can_manage_tenant_accounting(p_tenant_id),
    false
  )
$$;

revoke all on function public.can_manage_tenant_payroll(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.can_manage_tenant_payroll(uuid)
  to authenticated, service_role;

-- Match Supabase ban semantics for Worker identities: a future ban is denied,
-- while an expired temporary ban no longer blocks the authoritative account.
create or replace function public.is_authoritative_worker_portal_identity(
  p_user_id uuid,
  p_tenant_id uuid,
  p_employee_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
  select exists (
    select 1
    from auth.users auth_user
    join public.employee_portal_accounts portal
      on portal.auth_user_id = auth_user.id
     and portal.tenant_id = p_tenant_id
     and portal.employee_id = p_employee_id
     and portal.is_active is true
    join public.employees employee
      on employee.id = portal.employee_id
     and employee.tenant_id = portal.tenant_id
     and employee.status = 'active'
     and employee.user_id is null
    join public.tenants tenant
      on tenant.id = portal.tenant_id
     and tenant.is_active is true
    where auth_user.id = p_user_id
      and (
        auth_user.banned_until is null
        or auth_user.banned_until <= statement_timestamp()
      )
      and coalesce(
        auth_user.raw_app_meta_data->>'account_type',
        ''
      ) = 'worker_portal'
      and coalesce(
        auth_user.raw_app_meta_data->>'tenant_id',
        ''
      ) = p_tenant_id::text
      and coalesce(
        auth_user.raw_app_meta_data->>'employee_id',
        ''
      ) = p_employee_id::text
      and coalesce(
        auth_user.raw_app_meta_data->>'role',
        ''
      ) = 'worker'
      and not exists (
        select 1
        from public.user_profiles profile
        where profile.employee_id = p_employee_id
          and profile.tenant_id = p_tenant_id
      )
      and not exists (
        select 1
        from public.user_invitations invitation
        where invitation.employee_id = p_employee_id
          and invitation.tenant_id = p_tenant_id
          and invitation.status = 'pending'
      )
      and not exists (
        select 1
        from public.user_profiles profile
        join public.tenants profile_tenant
          on profile_tenant.id = profile.tenant_id
         and profile_tenant.is_active is true
        where profile.user_id = p_user_id
          and profile.is_active is true
      )
      and not exists (
        select 1
        from public.employees staff_employee
        join public.tenants staff_tenant
          on staff_tenant.id = staff_employee.tenant_id
         and staff_tenant.is_active is true
        where staff_employee.user_id = p_user_id
          and staff_employee.status = 'active'
      )
  )
$$;

revoke all on function public.is_authoritative_worker_portal_identity(
  uuid,
  uuid,
  uuid
) from public, anon, authenticated, service_role;

create or replace function public.guard_worker_portal_identity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  auth_metadata jsonb;
  employee_row public.employees%rowtype;
begin
  perform public.lock_auth_membership_identities(
    case
      when tg_op = 'INSERT' then null
      else old.auth_user_id
    end,
    new.auth_user_id
  );
  perform public.lock_employee_access_identity(new.employee_id);

  if new.is_active is not true or new.auth_user_id is null then
    return new;
  end if;

  select employee.*
  into employee_row
  from public.employees employee
  where employee.id = new.employee_id
    and employee.tenant_id = new.tenant_id
  for update;

  if not found or employee_row.status <> 'active' then
    raise exception 'employee_not_found'
      using errcode = 'P0001';
  end if;

  if employee_row.user_id is not null
     or exists (
       select 1
       from public.user_profiles profile
       where profile.employee_id = new.employee_id
         and profile.tenant_id = new.tenant_id
     )
     or exists (
       select 1
       from public.user_invitations invitation
       where invitation.employee_id = new.employee_id
         and invitation.tenant_id = new.tenant_id
         and invitation.status = 'pending'
     ) then
    raise exception 'worker_access_conflict'
      using errcode = 'P0001';
  end if;

  select coalesce(auth_user.raw_app_meta_data, '{}'::jsonb)
  into auth_metadata
  from auth.users auth_user
  where auth_user.id = new.auth_user_id
    and (
      auth_user.banned_until is null
      or auth_user.banned_until <= statement_timestamp()
    );

  if not found
     or coalesce(auth_metadata->>'account_type', '') <> 'worker_portal'
     or coalesce(auth_metadata->>'tenant_id', '') <> new.tenant_id::text
     or coalesce(auth_metadata->>'employee_id', '')
          <> new.employee_id::text
     or coalesce(auth_metadata->>'role', '') <> 'worker' then
    raise exception 'Authoritative worker portal identity is required'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.user_profiles profile
    join public.tenants tenant
      on tenant.id = profile.tenant_id
     and tenant.is_active is true
    where profile.user_id = new.auth_user_id
      and profile.is_active is true
  ) then
    raise exception
      'Worker portal identity cannot be linked to an active ERP profile'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.employees employee
    join public.tenants tenant
      on tenant.id = employee.tenant_id
     and tenant.is_active is true
    where employee.user_id = new.auth_user_id
      and employee.status = 'active'
  ) then
    raise exception
      'Worker portal identity cannot be linked as ERP staff'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_worker_portal_identity()
  from public, anon, authenticated, service_role;

-- Existing ERP profile/self-service functions predate the explicit Auth ban
-- check. Keep their mature business bodies internal and place the same
-- authoritative ERP gate in front of every API entrypoint.
do $$
begin
  if to_regprocedure(
    'public.get_my_erp_profile_internal()'
  ) is null then
    if to_regprocedure('public.get_my_erp_profile()') is null then
      raise exception 'Missing ERP profile projection';
    end if;
    alter function public.get_my_erp_profile()
      rename to get_my_erp_profile_internal;
  end if;

  if to_regprocedure(
    'public.update_my_employee_contact_internal(jsonb)'
  ) is null then
    if to_regprocedure(
      'public.update_my_employee_contact(jsonb)'
    ) is null then
      raise exception 'Missing ERP employee contact command';
    end if;
    alter function public.update_my_employee_contact(jsonb)
      rename to update_my_employee_contact_internal;
  end if;

end
$$;

create or replace function public.get_my_erp_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if exists (
    select 1
    from auth.users auth_user
    where auth_user.id = auth.uid()
      and auth_user.banned_until > statement_timestamp()
  ) then
    raise exception 'ERP profile access denied'
      using errcode = '42501';
  end if;

  return public.get_my_erp_profile_internal();
end;
$$;

create or replace function public.update_my_employee_contact(
  p_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if exists (
    select 1
    from auth.users auth_user
    where auth_user.id = auth.uid()
      and auth_user.banned_until > statement_timestamp()
  ) then
    raise exception 'ERP employee self-service access denied'
      using errcode = '42501';
  end if;

  return public.update_my_employee_contact_internal(p_patch);
end;
$$;

revoke all on function public.get_my_erp_profile_internal()
  from public, anon, authenticated, service_role;
revoke all on function public.update_my_employee_contact_internal(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.get_my_erp_profile()
  from public, anon, authenticated, service_role;
revoke all on function public.update_my_employee_contact(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_erp_profile()
  to authenticated;
grant execute on function public.update_my_employee_contact(jsonb)
  to authenticated;

-- Keep the operational coworker directory useful without exposing the full
-- employees row (RUT, contacts, health, bank, contract, and remuneration).
create or replace function public.get_erp_employee_directory()
returns table (
  employee_id uuid,
  user_id uuid,
  first_name text,
  last_name text,
  job_title text,
  system_role text,
  status text,
  photo_url text,
  department_id uuid
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null then
    raise exception 'Employee directory access denied'
      using errcode = '42501';
  end if;

  return query
  select
    employee.id,
    case
      when employee.user_id is not null
       and exists (
         select 1
         from public.user_profiles directory_profile
         join auth.users directory_auth_user
           on directory_auth_user.id = directory_profile.user_id
         where directory_profile.user_id = employee.user_id
           and directory_profile.tenant_id = employee.tenant_id
           and directory_profile.employee_id = employee.id
           and directory_profile.is_active is true
           and (
             directory_auth_user.banned_until is null
             or directory_auth_user.banned_until
                  <= statement_timestamp()
           )
           and coalesce(
             directory_auth_user.raw_app_meta_data->>'account_type',
             ''
           ) in ('erp_owner', 'erp_staff')
       )
       and not exists (
         select 1
         from public.employee_portal_accounts directory_portal
         where directory_portal.auth_user_id = employee.user_id
           and directory_portal.is_active is true
       )
      then employee.user_id
      else null
    end,
    employee.first_name,
    employee.last_name,
    employee.job_title,
    employee.system_role,
    employee.status,
    employee.photo_url,
    employee.department_id
  from public.employees employee
  where employee.tenant_id = tenant_id_value
    and employee.status <> 'terminated'
  order by employee.first_name, employee.last_name, employee.id;
end;
$$;

revoke all on function public.get_erp_employee_directory()
  from public, anon, authenticated, service_role;
grant execute on function public.get_erp_employee_directory()
  to authenticated;

-- Chat addresses ERP principals, not only employee records. Keep this
-- projection separate so owner/admin accounts without an employee link remain
-- reachable without widening the operational employee directory.
create or replace function public.get_erp_chat_principal_directory()
returns table (
  tenant_id uuid,
  user_id uuid,
  employee_id uuid,
  display_name text,
  role text,
  photo_url text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null then
    raise exception 'ERP chat directory access denied'
      using errcode = '42501';
  end if;

  return query
  select
    profile.tenant_id,
    profile.user_id,
    employee.id,
    coalesce(
      nullif(
        trim(employee.first_name || ' ' || employee.last_name),
        ''
      ),
      nullif(trim(auth_user.raw_user_meta_data->>'display_name'), ''),
      nullif(trim(auth_user.raw_user_meta_data->>'full_name'), ''),
      nullif(trim(auth_user.raw_user_meta_data->>'name'), ''),
      'Usuario ERP'
    ),
    profile.role,
    employee.photo_url
  from public.user_profiles profile
  join auth.users auth_user
    on auth_user.id = profile.user_id
  left join public.employees employee
    on employee.id = profile.employee_id
   and employee.tenant_id = profile.tenant_id
   and employee.user_id = profile.user_id
   and employee.status = 'active'
  where profile.tenant_id = tenant_id_value
    and profile.is_active is true
    and (
      auth_user.banned_until is null
      or auth_user.banned_until <= statement_timestamp()
    )
    and coalesce(
      auth_user.raw_app_meta_data->>'account_type',
      ''
    ) in ('erp_owner', 'erp_staff')
    and (
      profile.employee_id is null
      or employee.id is not null
    )
    and not exists (
      select 1
      from public.employees conflicting_employee
      where conflicting_employee.user_id = profile.user_id
        and conflicting_employee.id is distinct from profile.employee_id
    )
    and not exists (
      select 1
      from public.employee_portal_accounts portal
      where portal.auth_user_id = profile.user_id
        and portal.is_active is true
    )
  order by 4, profile.user_id;
end;
$$;

revoke all on function public.get_erp_chat_principal_directory()
  from public, anon, authenticated, service_role;
grant execute on function public.get_erp_chat_principal_directory()
  to authenticated;

-- RLS constrains the row tenant but cannot prove that referenced employee,
-- contract, attendance, and payroll UUIDs belong to that same tenant. This
-- trigger closes those cross-tenant graph edges for historical tables that do
-- not yet have composite foreign keys.
create or replace function
  public.validate_hr_payroll_tenant_consistency()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if tg_table_name = 'departments' then
    if new.manager_id is not null
       and not exists (
         select 1
         from public.employees employee
         where employee.id = new.manager_id
           and employee.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
  elsif tg_table_name = 'employees' then
    if new.department_id is not null
       and not exists (
         select 1
         from public.departments department
         where department.id = new.department_id
           and department.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
    if new.preferred_payment_method_id is not null
       and not exists (
         select 1
         from public.payment_methods payment_method
         where payment_method.id = new.preferred_payment_method_id
           and payment_method.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
    if new.salary_account_id is not null
       and not exists (
         select 1
         from public.accounts account_row
         where account_row.id = new.salary_account_id
           and account_row.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
  elsif tg_table_name = 'employee_contracts' then
    if not exists (
      select 1
      from public.employees employee
      where employee.id = new.employee_id
        and employee.tenant_id = new.tenant_id
    ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
    if new.work_schedule_id is not null
       and not exists (
         select 1
         from public.work_schedules work_schedule
         where work_schedule.id = new.work_schedule_id
           and work_schedule.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
    if new.department_id is not null
       and not exists (
         select 1
         from public.departments department
         where department.id = new.department_id
           and department.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
  elsif tg_table_name in (
    'attendances',
    'attendance_records',
    'leave_requests',
    'medical_leaves',
    'employment_contracts',
    'payroll_records',
    'shifts'
  ) then
    if new.employee_id is not null
       and not exists (
         select 1
         from public.employees employee
         where employee.id = new.employee_id
           and employee.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
    if tg_table_name = 'attendances'
       and new.approved_by is not null
       and not exists (
         select 1
         from public.employees approver
         where approver.id = new.approved_by
           and approver.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
  elsif tg_table_name = 'payroll_entries' then
    if new.payroll_run_id is not null
       and not exists (
         select 1
         from public.payroll_runs payroll_run
         where payroll_run.id = new.payroll_run_id
           and payroll_run.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
    if new.employee_id is not null
       and not exists (
         select 1
         from public.employees employee
         where employee.id = new.employee_id
           and employee.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
  elsif tg_table_name = 'payroll_voucher_lines' then
    if not exists (
      select 1
      from public.payroll_vouchers voucher
      where voucher.id = new.voucher_id
        and voucher.tenant_id = new.tenant_id
    ) or not exists (
      select 1
      from public.employees employee
      where employee.id = new.employee_id
        and employee.tenant_id = new.tenant_id
    ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
    if new.payment_method_id is not null
       and not exists (
         select 1
         from public.payment_methods payment_method
         where payment_method.id = new.payment_method_id
           and payment_method.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
    if new.payment_account_id is not null
       and not exists (
         select 1
         from public.accounts payment_account
         where payment_account.id = new.payment_account_id
           and payment_account.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
    if new.salary_account_id is not null
       and not exists (
         select 1
         from public.accounts salary_account
         where salary_account.id = new.salary_account_id
           and salary_account.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
    if new.expense_id is not null
       and not exists (
         select 1
         from public.expenses expense
         where expense.id = new.expense_id
           and expense.tenant_id = new.tenant_id
       ) then
      raise exception 'HR/payroll tenant mismatch'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function
  public.validate_hr_payroll_tenant_consistency()
  from public, anon, authenticated, service_role;

do $$
declare
  table_name_value text;
begin
  foreach table_name_value in array array[
    'departments',
    'employees',
    'employee_contracts',
    'attendances',
    'attendance_records',
    'leave_requests',
    'medical_leaves',
    'employment_contracts',
    'payroll_entries',
    'payroll_records',
    'shifts',
    'payroll_voucher_lines'
  ]
  loop
    execute format(
      'drop trigger if exists trg_validate_hr_payroll_tenant_consistency on public.%I',
      table_name_value
    );
    execute format(
      'create trigger trg_validate_hr_payroll_tenant_consistency '
      || 'before insert or update on public.%I '
      || 'for each row execute function '
      || 'public.validate_hr_payroll_tenant_consistency()',
      table_name_value
    );
  end loop;
end
$$;

-- Every HR/payroll table is an explicit RLS surface. Drop historical generic
-- tenant policies so they cannot combine permissively with the policies below.
do $$
declare
  table_name_value text;
  policy_row record;
begin
  foreach table_name_value in array array[
    'departments',
    'job_roles',
    'employees',
    'work_schedules',
    'employee_contracts',
    'attendances',
    'attendance_records',
    'leave_requests',
    'medical_leaves',
    'employment_contracts',
    'payroll_runs',
    'payroll_entries',
    'payroll_records',
    'shifts',
    'planning_roles',
    'employee_planning_roles',
    'employee_default_shift_blocks',
    'planned_shifts',
    'shift_change_requests',
    'payroll_vouchers',
    'payroll_voucher_lines',
    'employee_advances',
    'employee_advance_allocations'
  ]
  loop
    if to_regclass('public.' || table_name_value) is null then
      raise exception 'Missing required HR/payroll table: %', table_name_value;
    end if;

    execute format(
      'alter table public.%I enable row level security',
      table_name_value
    );

    for policy_row in
      select policyname
      from pg_policies
      where schemaname = 'public'
        and tablename = table_name_value
    loop
      execute format(
        'drop policy if exists %I on public.%I',
        policy_row.policyname,
        table_name_value
      );
    end loop;
  end loop;
end
$$;

-- Attendance aggregates are definer-rights reads and therefore enforce their
-- own row authority instead of relying on the caller's table RLS.
create or replace function public.get_checked_in_employees()
returns table (
  attendance_id uuid,
  employee_id uuid,
  employee_name text,
  check_in timestamp with time zone,
  hours_worked numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not (
       public.can_manage_tenant_hr(tenant_id_value)
       or public.can_manage_tenant_payroll(tenant_id_value)
     ) then
    raise exception 'Attendance access denied'
      using errcode = '42501';
  end if;

  return query
  select
    attendance.id,
    employee.id,
    trim(employee.first_name || ' ' || employee.last_name),
    attendance.check_in,
    round(
      extract(epoch from (statement_timestamp() - attendance.check_in))
        / 3600.0,
      2
    )
  from public.attendances attendance
  join public.employees employee
    on employee.id = attendance.employee_id
   and employee.tenant_id = attendance.tenant_id
  where attendance.tenant_id = tenant_id_value
    and attendance.status = 'ongoing'
    and attendance.check_out is null
  order by attendance.check_in;
end;
$$;

create or replace function public.get_attendance_summary(
  p_employee_id uuid,
  p_start_date date,
  p_end_date date
)
returns table (
  total_days integer,
  total_hours numeric,
  total_overtime numeric,
  average_hours numeric,
  late_arrivals integer,
  early_departures integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := coalesce(
    public.erp_member_tenant_id(),
    public.worker_portal_tenant_id()
  );
  store_timezone text;
  period_start_at timestamp with time zone;
  period_end_at timestamp with time zone;
begin
  if p_start_date is null
     or p_end_date is null
     or p_start_date > p_end_date then
    raise exception 'Invalid attendance date range'
      using errcode = '22023';
  end if;

  if tenant_id_value is null
     or not exists (
       select 1
       from public.employees employee
       where employee.id = p_employee_id
         and employee.tenant_id = tenant_id_value
     )
     or not (
       public.can_manage_tenant_hr(tenant_id_value)
       or public.can_manage_tenant_payroll(tenant_id_value)
       or (
         tenant_id_value = public.erp_member_tenant_id()
         and p_employee_id = public.current_erp_employee_id()
       )
       or (
         tenant_id_value = public.worker_portal_tenant_id()
         and p_employee_id = public.worker_portal_employee_id()
       )
     ) then
    raise exception 'Attendance access denied'
      using errcode = '42501';
  end if;

  select tenant.timezone
  into store_timezone
  from public.tenants tenant
  where tenant.id = tenant_id_value
    and tenant.is_active is true;

  if store_timezone is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names timezone_row
       where timezone_row.name = store_timezone
     ) then
    raise exception 'Attendance timezone invalid'
      using errcode = '22023';
  end if;

  period_start_at :=
    p_start_date::timestamp without time zone
      at time zone store_timezone;
  period_end_at :=
    (p_end_date + 1)::timestamp without time zone
      at time zone store_timezone;

  return query
  select
    count(
      distinct (
        attendance.check_in at time zone store_timezone
      )::date
    )::integer,
    coalesce(sum(attendance.worked_hours), 0),
    coalesce(sum(attendance.overtime_hours), 0),
    coalesce(avg(attendance.worked_hours), 0),
    count(*) filter (
      where (
        attendance.check_in at time zone store_timezone
      )::time > time '09:00:00'
    )::integer,
    count(*) filter (
      where attendance.check_out is not null
        and (
          attendance.check_out at time zone store_timezone
        )::time < time '18:00:00'
    )::integer
  from public.attendances attendance
  where attendance.tenant_id = tenant_id_value
    and attendance.employee_id = p_employee_id
    and attendance.status in ('completed', 'approved')
    and attendance.check_in >= period_start_at
    and attendance.check_in < period_end_at;
end;
$$;

create or replace function public.get_employee_hours_summary(
  p_employee_id uuid,
  p_start_date date,
  p_end_date date
)
returns json
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := coalesce(
    public.erp_member_tenant_id(),
    public.worker_portal_tenant_id()
  );
  result_value json;
  expected_start constant time := '09:00:00';
  expected_end constant time := '18:00:00';
  store_timezone text;
  period_start_at timestamp with time zone;
  period_end_at timestamp with time zone;
begin
  if p_start_date is null
     or p_end_date is null
     or p_start_date > p_end_date then
    raise exception 'Invalid attendance date range'
      using errcode = '22023';
  end if;

  if tenant_id_value is null
     or not exists (
       select 1
       from public.employees employee
       where employee.id = p_employee_id
         and employee.tenant_id = tenant_id_value
     )
     or not (
       public.can_manage_tenant_hr(tenant_id_value)
       or public.can_manage_tenant_payroll(tenant_id_value)
       or (
         tenant_id_value = public.erp_member_tenant_id()
         and p_employee_id = public.current_erp_employee_id()
       )
       or (
         tenant_id_value = public.worker_portal_tenant_id()
         and p_employee_id = public.worker_portal_employee_id()
       )
     ) then
    raise exception 'Attendance access denied'
      using errcode = '42501';
  end if;

  select tenant.timezone
  into store_timezone
  from public.tenants tenant
  where tenant.id = tenant_id_value
    and tenant.is_active is true;

  if store_timezone is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names timezone_row
       where timezone_row.name = store_timezone
     ) then
    raise exception 'Attendance timezone invalid'
      using errcode = '22023';
  end if;

  period_start_at :=
    p_start_date::timestamp without time zone
      at time zone store_timezone;
  period_end_at :=
    (p_end_date + 1)::timestamp without time zone
      at time zone store_timezone;

  select json_build_object(
    'total_days_worked', count(*),
    'total_hours', coalesce(sum(attendance.worked_hours), 0),
    'total_overtime', coalesce(sum(attendance.overtime_hours), 0),
    'total_break_minutes', coalesce(sum(attendance.break_minutes), 0),
    'average_hours_per_day',
      round(coalesce(avg(attendance.worked_hours), 0)::numeric, 2),
    'earliest_check_in',
      min((attendance.check_in at time zone store_timezone)::time),
    'latest_check_out',
      max((attendance.check_out at time zone store_timezone)::time),
    'days_with_overtime', count(*) filter (
      where coalesce(attendance.overtime_hours, 0) > 0
    ),
    'late_arrivals', count(*) filter (
      where (
        attendance.check_in at time zone store_timezone
      )::time >
        expected_start + interval '30 minutes'
    ),
    'early_departures', count(*) filter (
      where attendance.check_out is not null
        and (
          attendance.check_out at time zone store_timezone
        )::time <
          expected_end - interval '30 minutes'
    ),
    'perfect_attendance_days', count(*) filter (
      where coalesce(attendance.worked_hours, 0) >= 8
    ),
    'short_days', count(*) filter (
      where coalesce(attendance.worked_hours, 0) < 8
        and coalesce(attendance.worked_hours, 0) > 0
    )
  )
  into result_value
  from public.attendances attendance
  where attendance.tenant_id = tenant_id_value
    and attendance.employee_id = p_employee_id
    and attendance.check_in >= period_start_at
    and attendance.check_in < period_end_at
    and attendance.status in ('completed', 'approved');

  return coalesce(result_value, '{}'::json);
end;
$$;

create or replace function public.get_attendance_summary_for_period(
  p_start_date date,
  p_end_date date
)
returns table (
  employee_id uuid,
  employee_name text,
  total_hours numeric,
  total_days integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  store_timezone text;
  period_start_at timestamp with time zone;
  period_end_at timestamp with time zone;
begin
  if p_start_date is null
     or p_end_date is null
     or p_start_date > p_end_date then
    raise exception 'Invalid attendance date range'
      using errcode = '22023';
  end if;

  if tenant_id_value is null
     or not (
       public.can_manage_tenant_hr(tenant_id_value)
       or public.can_manage_tenant_payroll(tenant_id_value)
     ) then
    raise exception 'Attendance access denied'
      using errcode = '42501';
  end if;

  select tenant.timezone
  into store_timezone
  from public.tenants tenant
  where tenant.id = tenant_id_value
    and tenant.is_active is true;

  if store_timezone is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names timezone_row
       where timezone_row.name = store_timezone
     ) then
    raise exception 'Attendance timezone invalid'
      using errcode = '22023';
  end if;

  period_start_at :=
    p_start_date::timestamp without time zone
      at time zone store_timezone;
  period_end_at :=
    (p_end_date + 1)::timestamp without time zone
      at time zone store_timezone;

  return query
  select
    employee.id,
    trim(employee.first_name || ' ' || employee.last_name),
    coalesce(sum(attendance.worked_hours), 0)::numeric,
    count(
      distinct (
        attendance.check_in at time zone store_timezone
      )::date
    )::integer
  from public.employees employee
  left join public.attendances attendance
    on attendance.employee_id = employee.id
   and attendance.tenant_id = employee.tenant_id
   and attendance.status in ('completed', 'approved')
   and attendance.check_in >= period_start_at
   and attendance.check_in < period_end_at
  where employee.tenant_id = tenant_id_value
    and employee.status = 'active'
  group by employee.id, employee.first_name, employee.last_name
  order by trim(employee.first_name || ' ' || employee.last_name);
end;
$$;

revoke all on function public.get_checked_in_employees()
  from public, anon, authenticated, service_role;
revoke all on function public.get_attendance_summary(uuid, date, date)
  from public, anon, authenticated, service_role;
revoke all on function public.get_employee_hours_summary(uuid, date, date)
  from public, anon, authenticated, service_role;
revoke all on function public.get_attendance_summary_for_period(date, date)
  from public, anon, authenticated, service_role;
grant execute on function public.get_checked_in_employees()
  to authenticated;
grant execute on function public.get_attendance_summary(uuid, date, date)
  to authenticated;
grant execute on function public.get_employee_hours_summary(uuid, date, date)
  to authenticated;
grant execute on function public.get_attendance_summary_for_period(date, date)
  to authenticated;

-- Fresh canonical snapshots did not carry the legacy voucher sequence even
-- though the draft generator below depends on it. Client roles never need
-- direct sequence access because the command executes as SECURITY DEFINER.
create sequence if not exists public.payroll_voucher_number_seq start with 1;
revoke all on sequence public.payroll_voucher_number_seq
  from public, anon, authenticated, service_role;

-- Canonical draft generation was historically present in hosted databases but
-- absent from some bootstrap snapshots. Define the implementation explicitly
-- so this hardening migration behaves the same in both states.
create or replace function
  public.generate_payroll_voucher_draft_internal(
    p_start_date date,
    p_end_date date,
    p_period_label text default null
  )
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.user_tenant_id();
  voucher_id_value uuid;
  voucher_number_value text;
  total_hours_value numeric := 0;
  total_amount_value numeric := 0;
  employee_count_value integer := 0;
  employee_row record;
  worked_hours_value numeric;
  overtime_hours_value numeric;
  hourly_rate_value numeric;
  overtime_rate_value numeric;
  regular_amount_value numeric;
  overtime_amount_value numeric;
  store_timezone text;
  period_start_at timestamp with time zone;
  period_end_at timestamp with time zone;
begin
  select tenant.timezone
  into store_timezone
  from public.tenants tenant
  where tenant.id = tenant_id_value
    and tenant.is_active is true;

  if store_timezone is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names timezone_row
       where timezone_row.name = store_timezone
     ) then
    raise exception 'Payroll timezone invalid'
      using errcode = '22023';
  end if;

  period_start_at :=
    p_start_date::timestamp without time zone
      at time zone store_timezone;
  period_end_at :=
    (p_end_date + 1)::timestamp without time zone
      at time zone store_timezone;

  voucher_number_value :=
    'PV-'
    || lpad(
      nextval('public.payroll_voucher_number_seq')::text,
      5,
      '0'
    );

  insert into public.payroll_vouchers (
    tenant_id,
    voucher_number,
    period_start,
    period_end,
    period_label,
    status,
    created_by
  )
  values (
    tenant_id_value,
    voucher_number_value,
    p_start_date,
    p_end_date,
    coalesce(
      p_period_label,
      'Periodo: ' || p_start_date || ' - ' || p_end_date
    ),
    'draft',
    auth.uid()
  )
  returning id into voucher_id_value;

  for employee_row in
    select
      employee.*,
      coalesce(employee.hourly_rate, 0) as rate
    from public.employees employee
    where employee.tenant_id = tenant_id_value
      and employee.status = 'active'
  loop
    select
      coalesce(sum(attendance.worked_hours), 0),
      coalesce(sum(attendance.overtime_hours), 0)
    into worked_hours_value, overtime_hours_value
    from public.attendances attendance
    where attendance.tenant_id = tenant_id_value
      and attendance.employee_id = employee_row.id
      and attendance.status in ('completed', 'approved')
      and attendance.check_in >= period_start_at
      and attendance.check_in < period_end_at;

    hourly_rate_value := employee_row.rate;
    overtime_rate_value := hourly_rate_value * 1.5;
    regular_amount_value :=
      worked_hours_value * hourly_rate_value;
    overtime_amount_value :=
      overtime_hours_value * overtime_rate_value;

    insert into public.payroll_voucher_lines (
      tenant_id,
      voucher_id,
      employee_id,
      employee_name,
      worked_hours,
      overtime_hours,
      hourly_rate,
      overtime_rate,
      regular_amount,
      overtime_amount,
      total_amount,
      payment_method,
      payment_method_id,
      salary_account_id,
      is_included
    )
    values (
      tenant_id_value,
      voucher_id_value,
      employee_row.id,
      trim(
        employee_row.first_name || ' ' || employee_row.last_name
      ),
      worked_hours_value,
      overtime_hours_value,
      hourly_rate_value,
      overtime_rate_value,
      regular_amount_value,
      overtime_amount_value,
      regular_amount_value + overtime_amount_value,
      coalesce(
        employee_row.preferred_payment_method::text,
        'transfer'
      ),
      employee_row.preferred_payment_method_id,
      employee_row.salary_account_id,
      worked_hours_value + overtime_hours_value > 0
    );

    if worked_hours_value + overtime_hours_value > 0 then
      total_hours_value :=
        total_hours_value
        + worked_hours_value
        + overtime_hours_value;
      total_amount_value :=
        total_amount_value
        + regular_amount_value
        + overtime_amount_value;
      employee_count_value := employee_count_value + 1;
    end if;
  end loop;

  update public.payroll_vouchers voucher
  set total_hours = total_hours_value,
      total_amount = total_amount_value,
      employee_count = employee_count_value,
      updated_at = now()
  where voucher.id = voucher_id_value
    and voucher.tenant_id = tenant_id_value;

  return voucher_id_value;
end;
$$;

-- Preserve the other established payroll implementations behind service-only
-- names. Public wrappers below enforce accounting authority before entering
-- them.
do $$
begin
  if to_regprocedure(
    'public.confirm_payroll_voucher_internal(uuid)'
  ) is null then
    if to_regprocedure('public.confirm_payroll_voucher(uuid)') is null then
      raise exception 'Missing payroll confirmation command';
    end if;
    alter function public.confirm_payroll_voucher(uuid)
      rename to confirm_payroll_voucher_internal;
  end if;

  if to_regprocedure(
    'public.register_employee_advance_internal(uuid,numeric,uuid,uuid,timestamptz,text,text)'
  ) is null then
    if to_regprocedure(
      'public.register_employee_advance(uuid,numeric,uuid,uuid,timestamptz,text,text)'
    ) is null then
      raise exception 'Missing employee advance command';
    end if;
    alter function public.register_employee_advance(
      uuid,
      numeric,
      uuid,
      uuid,
      timestamp with time zone,
      text,
      text
    ) rename to register_employee_advance_internal;
  end if;

  if to_regprocedure(
    'public.pay_payroll_voucher_internal(uuid,jsonb)'
  ) is null then
    if to_regprocedure('public.pay_payroll_voucher(uuid,jsonb)') is null then
      raise exception 'Missing split payroll payment command';
    end if;
    alter function public.pay_payroll_voucher(uuid, jsonb)
      rename to pay_payroll_voucher_internal;
  end if;

  if to_regprocedure(
    'public.pay_payroll_voucher_internal(uuid)'
  ) is null then
    if to_regprocedure('public.pay_payroll_voucher(uuid)') is null then
      raise exception 'Missing payroll payment command';
    end if;
    alter function public.pay_payroll_voucher(uuid)
      rename to pay_payroll_voucher_internal;
  end if;

  if to_regprocedure(
    'public.revert_payroll_payment_internal(uuid)'
  ) is null then
    if to_regprocedure('public.revert_payroll_payment(uuid)') is null then
      raise exception 'Missing payroll payment reversal';
    end if;
    alter function public.revert_payroll_payment(uuid)
      rename to revert_payroll_payment_internal;
  end if;

  if to_regprocedure(
    'public.revert_payroll_to_draft_internal(uuid)'
  ) is null then
    if to_regprocedure('public.revert_payroll_to_draft(uuid)') is null then
      raise exception 'Missing payroll draft reversal';
    end if;
    alter function public.revert_payroll_to_draft(uuid)
      rename to revert_payroll_to_draft_internal;
  end if;

  if to_regprocedure(
    'public.get_payroll_voucher_line_settlements_internal(uuid)'
  ) is null then
    if to_regprocedure(
      'public.get_payroll_voucher_line_settlements(uuid)'
    ) is null then
      raise exception 'Missing payroll settlement projection';
    end if;
    alter function public.get_payroll_voucher_line_settlements(uuid)
      rename to get_payroll_voucher_line_settlements_internal;
  end if;

  if to_regprocedure(
    'public.calculate_payroll_internal(uuid,uuid,integer,integer)'
  ) is null then
    if to_regprocedure(
      'public.calculate_payroll(uuid,uuid,integer,integer)'
    ) is null then
      raise exception 'Missing legacy payroll calculator';
    end if;
    alter function public.calculate_payroll(uuid, uuid, integer, integer)
      rename to calculate_payroll_internal;
  end if;

  if to_regprocedure(
    'public.get_income_statement_data_internal(timestamptz,timestamptz,boolean)'
  ) is null then
    if to_regprocedure(
      'public.get_income_statement_data(timestamptz,timestamptz,boolean)'
    ) is null then
      raise exception 'Missing income statement projection';
    end if;
    alter function public.get_income_statement_data(
      timestamp with time zone,
      timestamp with time zone,
      boolean
    ) rename to get_income_statement_data_internal;
  end if;

  if to_regprocedure(
    'public.get_income_expense_timeseries_internal(integer,boolean)'
  ) is null then
    if to_regprocedure(
      'public.get_income_expense_timeseries(integer,boolean)'
    ) is null then
      raise exception 'Missing income/expense timeseries';
    end if;
    alter function public.get_income_expense_timeseries(integer, boolean)
      rename to get_income_expense_timeseries_internal;
  end if;

  if to_regprocedure(
    'public.get_income_expense_daily_timeseries_internal(timestamptz,timestamptz,boolean)'
  ) is null then
    if to_regprocedure(
      'public.get_income_expense_daily_timeseries(timestamptz,timestamptz,boolean)'
    ) is null then
      raise exception 'Missing daily income/expense timeseries';
    end if;
    alter function public.get_income_expense_daily_timeseries(
      timestamp with time zone,
      timestamp with time zone,
      boolean
    ) rename to get_income_expense_daily_timeseries_internal;
  end if;
end
$$;

create or replace function public.generate_payroll_voucher_draft(
  p_start_date date,
  p_end_date date,
  p_period_label text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if p_start_date is null
     or p_end_date is null
     or p_start_date > p_end_date then
    raise exception 'Invalid payroll date range'
      using errcode = '22023';
  end if;

  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  return public.generate_payroll_voucher_draft_internal(
    p_start_date,
    p_end_date,
    p_period_label
  );
end;
$$;

create or replace function public.confirm_payroll_voucher(
  p_voucher_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  return public.confirm_payroll_voucher_internal(p_voucher_id);
end;
$$;

create or replace function public.register_employee_advance(
  p_employee_id uuid,
  p_amount numeric,
  p_payment_method_id uuid,
  p_payment_account_id uuid default null,
  p_paid_at timestamp with time zone default statement_timestamp(),
  p_reference text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  return public.register_employee_advance_internal(
    p_employee_id,
    p_amount,
    p_payment_method_id,
    p_payment_account_id,
    p_paid_at,
    p_reference,
    p_notes
  );
end;
$$;

create or replace function public.pay_payroll_voucher(
  p_voucher_id uuid,
  p_payment_splits jsonb
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  return public.pay_payroll_voucher_internal(
    p_voucher_id,
    p_payment_splits
  );
end;
$$;

create or replace function public.pay_payroll_voucher(
  p_voucher_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  return public.pay_payroll_voucher_internal(p_voucher_id, null);
end;
$$;

create or replace function public.revert_payroll_payment(
  p_voucher_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  return public.revert_payroll_payment_internal(p_voucher_id);
end;
$$;

create or replace function public.revert_payroll_to_draft(
  p_voucher_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  return public.revert_payroll_to_draft_internal(p_voucher_id);
end;
$$;

create or replace function public.get_payroll_voucher_line_settlements(
  p_voucher_id uuid
)
returns table (
  line_id uuid,
  cash_paid numeric(14,2),
  advances_applied numeric(14,2),
  settled_amount numeric(14,2),
  balance numeric(14,2)
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  return query
  select *
  from public.get_payroll_voucher_line_settlements_internal(p_voucher_id);
end;
$$;

create or replace function public.calculate_payroll(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if p_tenant_id is null
     or p_tenant_id is distinct from public.erp_member_tenant_id()
     or not public.can_manage_tenant_payroll(p_tenant_id) then
    raise exception 'Payroll access denied'
      using errcode = '42501';
  end if;

  if p_year not between 2000 and 2100
     or p_month not between 1 and 12 then
    raise exception 'Invalid payroll period'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.employees employee
    where employee.id = p_employee_id
      and employee.tenant_id = p_tenant_id
  ) then
    raise exception 'Payroll employee not found'
      using errcode = 'P0002';
  end if;

  return public.calculate_payroll_internal(
    p_tenant_id,
    p_employee_id,
    p_year,
    p_month
  );
end;
$$;

create or replace function public.get_income_statement_data(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_is_cash_flow boolean default false
)
returns table (
  category text,
  category_label text,
  account_code text,
  account_name text,
  amount numeric(14,2)
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if p_start_date is null
     or p_end_date is null
     or p_start_date > p_end_date then
    raise exception 'Invalid accounting date range'
      using errcode = '22023';
  end if;

  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Accounting access denied'
      using errcode = '42501';
  end if;

  return query
  select *
  from public.get_income_statement_data_internal(
    p_start_date,
    p_end_date,
    p_is_cash_flow
  );
end;
$$;

create or replace function public.get_income_expense_timeseries(
  p_months integer default 12,
  p_is_cash_flow boolean default false
)
returns table (
  period_start date,
  period_end date,
  income numeric(14,2),
  expense numeric(14,2)
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if p_months is null or p_months not between 1 and 120 then
    raise exception 'Invalid accounting timeseries range'
      using errcode = '22023';
  end if;

  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Accounting access denied'
      using errcode = '42501';
  end if;

  return query
  select *
  from public.get_income_expense_timeseries_internal(
    p_months,
    p_is_cash_flow
  );
end;
$$;

create or replace function public.get_income_expense_daily_timeseries(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_is_cash_flow boolean default false
)
returns table (
  period_start date,
  period_end date,
  income numeric(14,2),
  expense numeric(14,2)
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
begin
  if p_start_date is null
     or p_end_date is null
     or p_start_date > p_end_date
     or p_end_date - p_start_date > interval '3660 days' then
    raise exception 'Invalid accounting date range'
      using errcode = '22023';
  end if;

  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'Accounting access denied'
      using errcode = '42501';
  end if;

  return query
  select *
  from public.get_income_expense_daily_timeseries_internal(
    p_start_date,
    p_end_date,
    p_is_cash_flow
  );
end;
$$;

-- Internal payroll implementations are never public API entrypoints.
revoke all on function
  public.generate_payroll_voucher_draft_internal(date, date, text)
  from public, anon, authenticated, service_role;
revoke all on function public.confirm_payroll_voucher_internal(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.register_employee_advance_internal(
  uuid,
  numeric,
  uuid,
  uuid,
  timestamp with time zone,
  text,
  text
) from public, anon, authenticated, service_role;
revoke all on function public.pay_payroll_voucher_internal(uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.pay_payroll_voucher_internal(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.revert_payroll_payment_internal(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.revert_payroll_to_draft_internal(uuid)
  from public, anon, authenticated, service_role;
revoke all on function
  public.get_payroll_voucher_line_settlements_internal(uuid)
  from public, anon, authenticated, service_role;
revoke all on function
  public.calculate_payroll_internal(uuid, uuid, integer, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.get_income_statement_data_internal(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) from public, anon, authenticated, service_role;
revoke all on function
  public.get_income_expense_timeseries_internal(integer, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.get_income_expense_daily_timeseries_internal(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) from public, anon, authenticated, service_role;

grant execute on function
  public.generate_payroll_voucher_draft_internal(date, date, text)
  to service_role;
grant execute on function public.confirm_payroll_voucher_internal(uuid)
  to service_role;
grant execute on function public.register_employee_advance_internal(
  uuid,
  numeric,
  uuid,
  uuid,
  timestamp with time zone,
  text,
  text
) to service_role;
grant execute on function public.pay_payroll_voucher_internal(uuid, jsonb)
  to service_role;
grant execute on function public.pay_payroll_voucher_internal(uuid)
  to service_role;
grant execute on function public.revert_payroll_payment_internal(uuid)
  to service_role;
grant execute on function public.revert_payroll_to_draft_internal(uuid)
  to service_role;
grant execute on function
  public.get_payroll_voucher_line_settlements_internal(uuid)
  to service_role;
grant execute on function
  public.calculate_payroll_internal(uuid, uuid, integer, integer)
  to service_role;
grant execute on function public.get_income_statement_data_internal(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) to service_role;
grant execute on function
  public.get_income_expense_timeseries_internal(integer, boolean)
  to service_role;
grant execute on function public.get_income_expense_daily_timeseries_internal(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) to service_role;

revoke all on function public.generate_payroll_voucher_draft(
  date,
  date,
  text
) from public, anon, authenticated, service_role;
revoke all on function public.confirm_payroll_voucher(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.register_employee_advance(
  uuid,
  numeric,
  uuid,
  uuid,
  timestamp with time zone,
  text,
  text
) from public, anon, authenticated, service_role;
revoke all on function public.pay_payroll_voucher(uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.pay_payroll_voucher(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.revert_payroll_payment(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.revert_payroll_to_draft(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_payroll_voucher_line_settlements(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.calculate_payroll(
  uuid,
  uuid,
  integer,
  integer
) from public, anon, authenticated, service_role;
revoke all on function public.get_income_statement_data(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) from public, anon, authenticated, service_role;
revoke all on function public.get_income_expense_timeseries(integer, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.get_income_expense_daily_timeseries(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) from public, anon, authenticated, service_role;

grant execute on function public.generate_payroll_voucher_draft(
  date,
  date,
  text
) to authenticated;
grant execute on function public.confirm_payroll_voucher(uuid)
  to authenticated;
grant execute on function public.register_employee_advance(
  uuid,
  numeric,
  uuid,
  uuid,
  timestamp with time zone,
  text,
  text
) to authenticated;
grant execute on function public.pay_payroll_voucher(uuid, jsonb)
  to authenticated;
grant execute on function public.pay_payroll_voucher(uuid)
  to authenticated;
grant execute on function public.revert_payroll_payment(uuid)
  to authenticated;
grant execute on function public.revert_payroll_to_draft(uuid)
  to authenticated;
grant execute on function public.get_payroll_voucher_line_settlements(uuid)
  to authenticated;
grant execute on function public.calculate_payroll(
  uuid,
  uuid,
  integer,
  integer
) to authenticated;
grant execute on function public.get_income_statement_data(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) to authenticated;
grant execute on function public.get_income_expense_timeseries(integer, boolean)
  to authenticated;
grant execute on function public.get_income_expense_daily_timeseries(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) to authenticated;

-- Trigger/helper functions execute through their owning triggers or the
-- service-only implementations above, never as direct API commands.
revoke all on function public.calculate_attendance_hours()
  from public, anon, authenticated, service_role;
revoke all on function public.prevent_duplicate_checkin()
  from public, anon, authenticated, service_role;
revoke all on function public.validate_employee_advance()
  from public, anon, authenticated, service_role;
revoke all on function public.validate_employee_advance_allocation()
  from public, anon, authenticated, service_role;
revoke all on function public.handle_employee_advance_change()
  from public, anon, authenticated, service_role;
revoke all on function public.handle_employee_advance_allocation_change()
  from public, anon, authenticated, service_role;
revoke all on function public.validate_shift_planning_tenant_consistency()
  from public, anon, authenticated, service_role;

revoke all on function
  public.create_employee_advance_journal_entry(uuid)
  from public, anon, authenticated, service_role;
revoke all on function
  public.create_employee_advance_allocation_journal_entry(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.recalculate_employee_advance(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.recalculate_expense_totals(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.ensure_payroll_line_expense(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.refresh_payroll_voucher_status(uuid)
  from public, anon, authenticated, service_role;

grant execute on function
  public.create_employee_advance_journal_entry(uuid)
  to service_role;
grant execute on function
  public.create_employee_advance_allocation_journal_entry(uuid)
  to service_role;
grant execute on function public.recalculate_employee_advance(uuid)
  to service_role;
grant execute on function public.recalculate_expense_totals(uuid)
  to service_role;
grant execute on function public.ensure_payroll_line_expense(uuid)
  to service_role;
grant execute on function public.refresh_payroll_voucher_status(uuid)
  to service_role;

comment on function public.get_erp_employee_directory() is
  'Minimal same-tenant ERP employee directory; excludes HR, contact, health, bank, and remuneration fields.';
comment on function public.current_erp_employee_id() is
  'Returns the exact active bilaterally linked ERP employee for auth.uid(), otherwise NULL.';

-- Non-sensitive HR catalogs remain readable to active ERP members. Their
-- lifecycle is still a user-management responsibility.
create policy departments_read_erp
  on public.departments
  for select
  to authenticated
  using (tenant_id = public.erp_member_tenant_id());
create policy departments_insert_managers
  on public.departments
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy departments_update_managers
  on public.departments
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy departments_delete_managers
  on public.departments
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

create policy job_roles_read_erp
  on public.job_roles
  for select
  to authenticated
  using (tenant_id = public.erp_member_tenant_id());
create policy job_roles_insert_managers
  on public.job_roles
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy job_roles_update_managers
  on public.job_roles
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy job_roles_delete_managers
  on public.job_roles
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

create policy work_schedules_read_erp
  on public.work_schedules
  for select
  to authenticated
  using (tenant_id = public.erp_member_tenant_id());
create policy work_schedules_insert_managers
  on public.work_schedules
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy work_schedules_update_managers
  on public.work_schedules
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy work_schedules_delete_managers
  on public.work_schedules
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

-- The full employee row is restricted to HR managers, accounting staff, or
-- the exact linked ERP employee. Physical employee deletion remains service
-- only; the canonical retire_employee command owns application retirement.
create policy employees_read_authorized
  on public.employees
  for select
  to authenticated
  using (
    public.can_manage_tenant_hr(tenant_id)
    or public.can_manage_tenant_payroll(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and id = public.current_erp_employee_id()
    )
  );
create policy employees_insert_managers
  on public.employees
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy employees_update_managers
  on public.employees
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));

-- Salary contracts and attendance are readable by HR/accounting or the exact
-- employee. Private leave/medical rows are HR-or-own only. Direct mutation is
-- manager-only throughout this family.
create policy employee_contracts_read_authorized
  on public.employee_contracts
  for select
  to authenticated
  using (
    public.can_manage_tenant_hr(tenant_id)
    or public.can_manage_tenant_payroll(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
  );
create policy employee_contracts_insert_managers
  on public.employee_contracts
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy employee_contracts_update_managers
  on public.employee_contracts
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy employee_contracts_delete_managers
  on public.employee_contracts
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

create policy employment_contracts_read_authorized
  on public.employment_contracts
  for select
  to authenticated
  using (
    public.can_manage_tenant_hr(tenant_id)
    or public.can_manage_tenant_payroll(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
  );
create policy employment_contracts_insert_managers
  on public.employment_contracts
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy employment_contracts_update_managers
  on public.employment_contracts
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy employment_contracts_delete_managers
  on public.employment_contracts
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

create policy attendances_read_authorized
  on public.attendances
  for select
  to authenticated
  using (
    public.can_manage_tenant_hr(tenant_id)
    or public.can_manage_tenant_payroll(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
  );
create policy attendances_insert_managers
  on public.attendances
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy attendances_update_managers
  on public.attendances
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy attendances_delete_managers
  on public.attendances
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

create policy attendance_records_read_authorized
  on public.attendance_records
  for select
  to authenticated
  using (
    public.can_manage_tenant_hr(tenant_id)
    or public.can_manage_tenant_payroll(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
  );
create policy attendance_records_insert_managers
  on public.attendance_records
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy attendance_records_update_managers
  on public.attendance_records
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy attendance_records_delete_managers
  on public.attendance_records
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

create policy leave_requests_read_authorized
  on public.leave_requests
  for select
  to authenticated
  using (
    public.can_manage_tenant_hr(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
  );
create policy leave_requests_insert_managers
  on public.leave_requests
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy leave_requests_update_managers
  on public.leave_requests
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy leave_requests_delete_managers
  on public.leave_requests
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

create policy medical_leaves_read_authorized
  on public.medical_leaves
  for select
  to authenticated
  using (
    public.can_manage_tenant_hr(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
  );
create policy medical_leaves_insert_managers
  on public.medical_leaves
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy medical_leaves_update_managers
  on public.medical_leaves
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy medical_leaves_delete_managers
  on public.medical_leaves
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

-- Legacy and current payroll surfaces share one accounting authority. An
-- employee may read only rows that are explicitly keyed to that employee.
create policy payroll_runs_read_accounting
  on public.payroll_runs
  for select
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));
create policy payroll_runs_insert_accounting
  on public.payroll_runs
  for insert
  to authenticated
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy payroll_runs_update_accounting
  on public.payroll_runs
  for update
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id))
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy payroll_runs_delete_accounting
  on public.payroll_runs
  for delete
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

create policy payroll_entries_read_authorized
  on public.payroll_entries
  for select
  to authenticated
  using (
    public.can_manage_tenant_payroll(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
  );
create policy payroll_entries_insert_accounting
  on public.payroll_entries
  for insert
  to authenticated
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy payroll_entries_update_accounting
  on public.payroll_entries
  for update
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id))
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy payroll_entries_delete_accounting
  on public.payroll_entries
  for delete
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

create policy payroll_records_read_authorized
  on public.payroll_records
  for select
  to authenticated
  using (
    public.can_manage_tenant_payroll(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
  );
create policy payroll_records_insert_accounting
  on public.payroll_records
  for insert
  to authenticated
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy payroll_records_update_accounting
  on public.payroll_records
  for update
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id))
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy payroll_records_delete_accounting
  on public.payroll_records
  for delete
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

-- Legacy shifts have no current Flutter owner. Keep historical rows readable
-- only to HR managers or the exact ERP employee, and manager-only for writes.
create policy shifts_read_authorized
  on public.shifts
  for select
  to authenticated
  using (
    public.can_manage_tenant_hr(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
  );
create policy shifts_insert_managers
  on public.shifts
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy shifts_update_managers
  on public.shifts
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy shifts_delete_managers
  on public.shifts
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

create policy payroll_vouchers_read_accounting
  on public.payroll_vouchers
  for select
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));
create policy payroll_vouchers_insert_accounting
  on public.payroll_vouchers
  for insert
  to authenticated
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy payroll_vouchers_update_accounting
  on public.payroll_vouchers
  for update
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id))
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy payroll_vouchers_delete_accounting
  on public.payroll_vouchers
  for delete
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

create policy payroll_voucher_lines_read_authorized
  on public.payroll_voucher_lines
  for select
  to authenticated
  using (
    public.can_manage_tenant_payroll(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
  );
create policy payroll_voucher_lines_insert_accounting
  on public.payroll_voucher_lines
  for insert
  to authenticated
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy payroll_voucher_lines_update_accounting
  on public.payroll_voucher_lines
  for update
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id))
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy payroll_voucher_lines_delete_accounting
  on public.payroll_voucher_lines
  for delete
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

create policy employee_advances_read_authorized
  on public.employee_advances
  for select
  to authenticated
  using (
    public.can_manage_tenant_payroll(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
  );
create policy employee_advances_insert_accounting
  on public.employee_advances
  for insert
  to authenticated
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy employee_advances_update_accounting
  on public.employee_advances
  for update
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id))
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy employee_advances_delete_accounting
  on public.employee_advances
  for delete
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

create policy employee_advance_allocations_read_authorized
  on public.employee_advance_allocations
  for select
  to authenticated
  using (
    public.can_manage_tenant_payroll(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and (
        exists (
          select 1
          from public.employee_advances advance
          where advance.id =
              employee_advance_allocations.advance_id
            and advance.tenant_id =
              employee_advance_allocations.tenant_id
            and advance.employee_id =
              public.current_erp_employee_id()
        )
        or exists (
          select 1
          from public.payroll_voucher_lines voucher_line
          where voucher_line.id =
              employee_advance_allocations.voucher_line_id
            and voucher_line.tenant_id =
              employee_advance_allocations.tenant_id
            and voucher_line.employee_id =
              public.current_erp_employee_id()
        )
      )
    )
  );
create policy employee_advance_allocations_insert_accounting
  on public.employee_advance_allocations
  for insert
  to authenticated
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy employee_advance_allocations_update_accounting
  on public.employee_advance_allocations
  for update
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id))
  with check (public.can_manage_tenant_payroll(tenant_id));
create policy employee_advance_allocations_delete_accounting
  on public.employee_advance_allocations
  for delete
  to authenticated
  using (public.can_manage_tenant_payroll(tenant_id));

-- Planning managers retain tenant-wide control. ERP and Worker identities may
-- read only their own employee rows; team coverage remains in curated RPCs.
create policy planning_roles_read_authorized
  on public.planning_roles
  for select
  to authenticated
  using (
    tenant_id = public.erp_member_tenant_id()
    or tenant_id = public.worker_portal_tenant_id()
  );
create policy planning_roles_insert_managers
  on public.planning_roles
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy planning_roles_update_managers
  on public.planning_roles
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy planning_roles_delete_managers
  on public.planning_roles
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

create policy employee_planning_roles_read_authorized
  on public.employee_planning_roles
  for select
  to authenticated
  using (
    public.can_manage_tenant_hr(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
    or (
      tenant_id = public.worker_portal_tenant_id()
      and employee_id = public.worker_portal_employee_id()
    )
  );
create policy employee_planning_roles_insert_managers
  on public.employee_planning_roles
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy employee_planning_roles_update_managers
  on public.employee_planning_roles
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy employee_planning_roles_delete_managers
  on public.employee_planning_roles
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

create policy employee_default_shift_blocks_read_authorized
  on public.employee_default_shift_blocks
  for select
  to authenticated
  using (
    public.can_manage_tenant_hr(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
    or (
      tenant_id = public.worker_portal_tenant_id()
      and employee_id = public.worker_portal_employee_id()
    )
  );
create policy employee_default_shift_blocks_insert_managers
  on public.employee_default_shift_blocks
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy employee_default_shift_blocks_update_managers
  on public.employee_default_shift_blocks
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy employee_default_shift_blocks_delete_managers
  on public.employee_default_shift_blocks
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

create policy planned_shifts_read_authorized
  on public.planned_shifts
  for select
  to authenticated
  using (
    public.can_manage_tenant_hr(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
    or (
      tenant_id = public.worker_portal_tenant_id()
      and employee_id = public.worker_portal_employee_id()
    )
  );
create policy planned_shifts_insert_managers
  on public.planned_shifts
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy planned_shifts_update_managers
  on public.planned_shifts
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy planned_shifts_delete_managers
  on public.planned_shifts
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

create policy shift_change_requests_read_authorized
  on public.shift_change_requests
  for select
  to authenticated
  using (
    public.can_manage_tenant_hr(tenant_id)
    or (
      tenant_id = public.erp_member_tenant_id()
      and employee_id = public.current_erp_employee_id()
    )
    or (
      tenant_id = public.worker_portal_tenant_id()
      and employee_id = public.worker_portal_employee_id()
    )
  );
create policy shift_change_requests_insert_managers
  on public.shift_change_requests
  for insert
  to authenticated
  with check (public.can_manage_tenant_hr(tenant_id));
create policy shift_change_requests_update_managers
  on public.shift_change_requests
  for update
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id))
  with check (public.can_manage_tenant_hr(tenant_id));
create policy shift_change_requests_delete_managers
  on public.shift_change_requests
  for delete
  to authenticated
  using (public.can_manage_tenant_hr(tenant_id));

-- Remove Supabase's broad default table ACLs. RLS then applies only to the
-- intended authenticated operations; service-role maintenance stays explicit.
do $$
declare
  table_name_value text;
begin
  foreach table_name_value in array array[
    'departments',
    'job_roles',
    'work_schedules',
    'employee_contracts',
    'attendances',
    'attendance_records',
    'leave_requests',
    'medical_leaves',
    'employment_contracts',
    'payroll_runs',
    'payroll_entries',
    'payroll_records',
    'shifts',
    'planning_roles',
    'employee_planning_roles',
    'employee_default_shift_blocks',
    'planned_shifts',
    'shift_change_requests',
    'payroll_vouchers',
    'payroll_voucher_lines',
    'employee_advances',
    'employee_advance_allocations'
  ]
  loop
    execute format(
      'revoke all on table public.%I from public, anon, authenticated, service_role',
      table_name_value
    );
    execute format(
      'grant select, insert, update, delete on table public.%I to authenticated',
      table_name_value
    );
    execute format(
      'grant all on table public.%I to service_role',
      table_name_value
    );
  end loop;

  revoke all on table public.employees
    from public, anon, authenticated, service_role;
  grant select, insert, update on table public.employees
    to authenticated;
  grant all on table public.employees
    to service_role;
end
$$;

commit;
