-- Auth-bound ERP employee self-service projection.
-- Deployment status: NOT DEPLOYED.
-- Recovery: revoke EXECUTE and drop public.get_my_employee_self_service(date).
-- Lock/backfill risk: function/ACL replacement only; no table rewrite or data
-- backfill. The function performs bounded, indexed reads for one employee/week.

create or replace function public.get_my_employee_self_service(
  p_week_anchor date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $function$
declare
  caller_user_id uuid := auth.uid();
  profile_count integer;
  profile_row public.user_profiles%rowtype;
  account_type_value text;
  employee_row public.employees%rowtype;
  employee_side_count integer;
  store_timezone text;
  shop_today date;
  current_week_start date;
  week_start_date date;
  week_end_date date;
  week_start_at timestamp with time zone;
  week_end_at timestamp with time zone;
begin
  if caller_user_id is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  select count(*)::integer
  into profile_count
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = caller_user_id
    and profile.is_active is true;

  if profile_count <> 1 then
    raise exception 'erp_employee_self_service_context_invalid'
      using errcode = 'P0001';
  end if;

  select profile.*
  into profile_row
  from public.user_profiles profile
  join public.tenants tenant
    on tenant.id = profile.tenant_id
   and tenant.is_active is true
  where profile.user_id = caller_user_id
    and profile.is_active is true;

  select coalesce(auth_user.raw_app_meta_data->>'account_type', '')
  into account_type_value
  from auth.users auth_user
  where auth_user.id = caller_user_id
    and (
      auth_user.banned_until is null
      or auth_user.banned_until <= statement_timestamp()
    );

  if not found or account_type_value not in ('erp_owner', 'erp_staff') then
    raise exception 'erp_employee_self_service_context_invalid'
      using errcode = 'P0001';
  end if;

  select count(*)::integer
  into employee_side_count
  from public.employees employee
  where employee.user_id = caller_user_id;

  if profile_row.employee_id is null or employee_side_count <> 1 then
    raise exception 'erp_employee_self_service_context_invalid'
      using errcode = 'P0001';
  end if;

  select employee.*
  into employee_row
  from public.employees employee
  where employee.id = profile_row.employee_id
    and employee.tenant_id = profile_row.tenant_id
    and employee.user_id = caller_user_id
    and employee.status = 'active';

  if not found
     or exists (
       select 1
       from public.employee_portal_accounts portal
       where portal.employee_id = profile_row.employee_id
         and portal.tenant_id = profile_row.tenant_id
         and portal.is_active is true
     ) then
    raise exception 'erp_employee_self_service_context_invalid'
      using errcode = 'P0001';
  end if;

  select tenant.timezone
  into store_timezone
  from public.tenants tenant
  where tenant.id = profile_row.tenant_id
    and tenant.is_active is true;

  if store_timezone is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names timezone_row
       where timezone_row.name = store_timezone
     ) then
    raise exception 'erp_employee_self_service_timezone_invalid'
      using errcode = 'P0001';
  end if;

  shop_today := (statement_timestamp() at time zone store_timezone)::date;
  current_week_start :=
    shop_today - (extract(isodow from shop_today)::integer - 1);
  week_start_date :=
    coalesce(p_week_anchor, shop_today)
      - (
        extract(isodow from coalesce(p_week_anchor, shop_today))::integer
        - 1
      );
  week_end_date := week_start_date + 7;
  week_start_at :=
    week_start_date::timestamp without time zone at time zone store_timezone;
  week_end_at :=
    week_end_date::timestamp without time zone at time zone store_timezone;

  return jsonb_build_object(
    'user_id', caller_user_id,
    'tenant_id', profile_row.tenant_id,
    'employee_id', employee_row.id,
    'timezone', store_timezone,
    'week_start', week_start_date,
    'week_end', week_end_date,
    'week_start_at', week_start_at,
    'week_end_at', week_end_at,
    'is_current_week', week_start_date = current_week_start,
    'my_shifts', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', shift.id,
          'employee_id', shift.employee_id,
          'title', shift.title,
          'start_at', shift.start_at,
          'end_at', shift.end_at,
          'status', shift.status,
          'source', shift.source,
          'store_hours_validated', shift.store_hours_validated,
          'outside_store_hours_reason', shift.outside_store_hours_reason,
          'role_name', planning_role.name,
          'employee_name',
            trim(concat_ws(' ', employee.first_name, employee.last_name)),
          'employee_job_title', employee.job_title,
          'planned_minutes_in_week',
            round(
              (
                extract(
                  epoch from (
                    least(shift.end_at, week_end_at)
                    - greatest(shift.start_at, week_start_at)
                  )
                ) / 60.0
              )::numeric,
              2
            )
        )
        order by shift.start_at, shift.id
      )
      from public.planned_shifts shift
      join public.employees employee
        on employee.id = shift.employee_id
       and employee.tenant_id = shift.tenant_id
       and employee.status = 'active'
      left join public.planning_roles planning_role
        on planning_role.id = shift.planning_role_id
       and planning_role.tenant_id = shift.tenant_id
      where shift.tenant_id = profile_row.tenant_id
        and shift.employee_id = employee_row.id
        and shift.start_at < week_end_at
        and shift.end_at > week_start_at
    ), '[]'::jsonb),
    'team_shifts', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', shift.id,
          'employee_id', shift.employee_id,
          'title', shift.title,
          'start_at', shift.start_at,
          'end_at', shift.end_at,
          'status', shift.status,
          'source', shift.source,
          'store_hours_validated', shift.store_hours_validated,
          'outside_store_hours_reason', shift.outside_store_hours_reason,
          'role_name', planning_role.name,
          'employee_name',
            trim(concat_ws(' ', employee.first_name, employee.last_name)),
          'employee_job_title', employee.job_title,
          'planned_minutes_in_week',
            round(
              (
                extract(
                  epoch from (
                    least(shift.end_at, week_end_at)
                    - greatest(shift.start_at, week_start_at)
                  )
                ) / 60.0
              )::numeric,
              2
            )
        )
        order by shift.start_at, shift.id
      )
      from public.planned_shifts shift
      join public.employees employee
        on employee.id = shift.employee_id
       and employee.tenant_id = shift.tenant_id
       and employee.status = 'active'
      left join public.planning_roles planning_role
        on planning_role.id = shift.planning_role_id
       and planning_role.tenant_id = shift.tenant_id
      where shift.tenant_id = profile_row.tenant_id
        and shift.employee_id <> employee_row.id
        and shift.status in ('published', 'completed')
        and shift.start_at < week_end_at
        and shift.end_at > week_start_at
    ), '[]'::jsonb),
    'attendances', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', attendance.id,
          'employee_id', attendance.employee_id,
          'check_in', attendance.check_in,
          'check_out', attendance.check_out,
          'worked_hours', attendance.worked_hours,
          'overtime_hours', attendance.overtime_hours,
          'break_minutes', attendance.break_minutes,
          'status', attendance.status,
          'notes', attendance.notes,
          'worked_minutes_in_week',
            case
              when attendance.status in ('completed', 'approved')
                   and attendance.check_out is not null
                   and attendance.check_out > attendance.check_in then
                round(
                  (
                    greatest(
                      coalesce(
                        attendance.worked_hours * 60.0,
                        extract(
                          epoch from (
                            attendance.check_out - attendance.check_in
                          )
                        ) / 60.0
                          - coalesce(attendance.break_minutes, 0)
                      ),
                      0
                    )
                    * extract(
                        epoch from (
                          least(attendance.check_out, week_end_at)
                          - greatest(attendance.check_in, week_start_at)
                        )
                      )
                    / extract(
                        epoch from (
                          attendance.check_out - attendance.check_in
                        )
                      )
                  )::numeric,
                  2
                )
              else 0
            end
        )
        order by attendance.check_in, attendance.id
      )
      from public.attendances attendance
      where attendance.tenant_id = profile_row.tenant_id
        and attendance.employee_id = employee_row.id
        and attendance.check_in < week_end_at
        and coalesce(attendance.check_out, statement_timestamp())
              > week_start_at
    ), '[]'::jsonb),
    'payroll_lines', coalesce((
      select jsonb_agg(
        payroll_row.payload
        order by payroll_row.period_end desc, payroll_row.line_id
      )
      from (
        select
          voucher.period_end,
          line.id as line_id,
          jsonb_build_object(
            'id', line.id,
            'employee_id', line.employee_id,
            'voucher_id', line.voucher_id,
            'worked_hours', line.worked_hours,
            'overtime_hours', line.overtime_hours,
            'regular_amount', line.regular_amount,
            'overtime_amount', line.overtime_amount,
            'total_amount', line.total_amount,
            'payment_method',
              coalesce(payment_method.name, line.payment_method),
            'voucher', jsonb_build_object(
              'id', voucher.id,
              'voucher_number', voucher.voucher_number,
              'period_start', voucher.period_start,
              'period_end', voucher.period_end,
              'period_label', voucher.period_label,
              'status', voucher.status,
              'paid_at', voucher.paid_at
            )
          ) as payload
        from public.payroll_voucher_lines line
        join public.payroll_vouchers voucher
          on voucher.id = line.voucher_id
         and voucher.tenant_id = line.tenant_id
        left join public.payment_methods payment_method
          on payment_method.id = line.payment_method_id
         and payment_method.tenant_id = line.tenant_id
        where line.tenant_id = profile_row.tenant_id
          and line.employee_id = employee_row.id
          and line.is_included is true
          and voucher.status <> 'voided'
          and voucher.period_start <= shop_today + 31
          and voucher.period_end >= shop_today - 365
        order by voucher.period_end desc, line.id
        limit 24
      ) payroll_row
    ), '[]'::jsonb),
    'change_requests', coalesce((
      select jsonb_agg(
        request_row.payload
        order by request_row.created_at desc, request_row.request_id
      )
      from (
        select
          request.created_at,
          request.id as request_id,
          jsonb_build_object(
            'id', request.id,
            'employee_id', request.employee_id,
            'request_type', request.request_type,
            'status', request.status,
            'requested_start_at', request.requested_start_at,
            'requested_end_at', request.requested_end_at,
            'worker_note', request.worker_note,
            'manager_note', request.manager_note,
            'created_at', request.created_at,
            'decided_at', request.decided_at
          ) as payload
        from public.shift_change_requests request
        where request.tenant_id = profile_row.tenant_id
          and request.employee_id = employee_row.id
        order by request.created_at desc, request.id
        limit 20
      ) request_row
    ), '[]'::jsonb),
    'default_shift_blocks', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', shift_block.id,
          'employee_id', shift_block.employee_id,
          'day_of_week', shift_block.day_of_week,
          'start_time', shift_block.start_time,
          'end_time', shift_block.end_time,
          'role_name', planning_role.name
        )
        order by shift_block.day_of_week, shift_block.start_time, shift_block.id
      )
      from public.employee_default_shift_blocks shift_block
      left join public.planning_roles planning_role
        on planning_role.id = shift_block.planning_role_id
       and planning_role.tenant_id = shift_block.tenant_id
      where shift_block.tenant_id = profile_row.tenant_id
        and shift_block.employee_id = employee_row.id
        and shift_block.is_active is true
    ), '[]'::jsonb)
  );
end;
$function$;

revoke all on function public.get_my_employee_self_service(date)
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_employee_self_service(date)
  to authenticated;

comment on function public.get_my_employee_self_service(date) is
  'Returns the signed-in active ERP employee own labor projection plus published/completed team coverage in the tenant store timezone.';
