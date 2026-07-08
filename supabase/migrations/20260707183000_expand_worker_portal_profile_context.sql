-- Expand worker portal profile data so the worker PWA can show the full
-- self-service profile summary without exposing ERP access.

create or replace function public.get_my_worker_portal_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_context jsonb;
begin
  select jsonb_build_object(
    'account', jsonb_build_object(
      'id', epa.id,
      'username', epa.username,
      'mustResetPassword', epa.must_reset_password,
      'isActive', epa.is_active,
      'createdAt', epa.created_at,
      'lastLoginAt', epa.last_login_at
    ),
    'tenant', jsonb_build_object(
      'id', t.id,
      'shopName', t.shop_name,
      'subdomain', t.subdomain,
      'timezone', t.timezone
    ),
    'storeSchedule', (
      select jsonb_build_object(
        'source', coalesce(max(ws.value) filter (where ws.key = 'business_hours_source'), 'erp_settings'),
        'businessHoursJson', coalesce(max(ws.value) filter (where ws.key = 'business_hours_json'), ''),
        'googleBusinessHoursJson', coalesce(max(ws.value) filter (where ws.key = 'google_business_regular_hours'), ''),
        'updatedAt', max(ws.value) filter (where ws.key = 'business_hours_updated_at')
      )
      from public.website_settings ws
      where ws.tenant_id = epa.tenant_id
        and ws.key in (
          'business_hours_source',
          'business_hours_json',
          'google_business_regular_hours',
          'business_hours_updated_at'
        )
    ),
    'employee', jsonb_build_object(
      'id', e.id,
      'employeeNumber', e.employee_number,
      'firstName', e.first_name,
      'lastName', e.last_name,
      'fullName', trim(e.first_name || ' ' || e.last_name),
      'jobTitle', e.job_title,
      'departmentName', d.name,
      'employmentType', e.employment_type,
      'systemRole', e.system_role,
      'photoUrl', e.photo_url,
      'email', e.email,
      'phone', e.phone,
      'rut', e.rut,
      'birthDate', e.birth_date,
      'hireDate', e.hire_date,
      'address', e.address,
      'city', e.city,
      'emergencyContactName', e.emergency_contact_name,
      'emergencyContactPhone', e.emergency_contact_phone,
      'status', e.status
    ),
    'planningRoles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pr.id,
        'code', pr.code,
        'name', pr.name,
        'color', pr.color,
        'isDefault', epr.is_default
      ) order by epr.is_default desc, pr.sort_order, pr.name)
      from public.employee_planning_roles epr
      join public.planning_roles pr on pr.id = epr.planning_role_id
      where epr.tenant_id = epa.tenant_id
        and epr.employee_id = epa.employee_id
        and pr.is_active = true
    ), '[]'::jsonb),
    'defaultShiftBlocks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', dsb.id,
        'dayOfWeek', dsb.day_of_week,
        'startTime', dsb.start_time,
        'endTime', dsb.end_time,
        'timezone', dsb.timezone,
        'planningRoleId', dsb.planning_role_id,
        'planningRoleName', pr.name,
        'planningRoleColor', pr.color,
        'source', dsb.source,
        'storeHoursValidated', dsb.store_hours_validated,
        'outsideStoreHoursReason', dsb.outside_store_hours_reason
      ) order by dsb.day_of_week, dsb.start_time)
      from public.employee_default_shift_blocks dsb
      left join public.planning_roles pr on pr.id = dsb.planning_role_id
      where dsb.tenant_id = epa.tenant_id
        and dsb.employee_id = epa.employee_id
        and dsb.is_active = true
    ), '[]'::jsonb)
  )
  into v_context
  from public.employee_portal_accounts epa
  join public.employees e on e.id = epa.employee_id
  join public.tenants t on t.id = epa.tenant_id
  left join public.departments d on d.id = e.department_id
  where epa.auth_user_id = auth.uid()
    and epa.is_active = true
    and e.status = 'active'
    and t.is_active = true
  limit 1;

  return v_context;
end;
$$;

grant execute on function public.get_my_worker_portal_context() to authenticated;
