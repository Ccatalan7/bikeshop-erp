create or replace function public.get_worker_portal_planning_calendar(
  p_start_at timestamp with time zone,
  p_end_at timestamp with time zone
)
returns table (
  id uuid,
  employee_id uuid,
  employee_full_name text,
  employee_job_title text,
  employee_photo_url text,
  title text,
  start_at timestamp with time zone,
  end_at timestamp with time zone,
  timezone text,
  status text,
  source text,
  planning_role_id uuid,
  planning_role_name text,
  planning_role_color text,
  store_hours_validated boolean,
  outside_store_hours_reason text,
  is_my_shift boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_employee_id uuid := public.worker_portal_employee_id();
  v_tenant_id uuid := public.worker_portal_tenant_id();
begin
  if v_employee_id is null or v_tenant_id is null then
    raise exception 'Worker portal account not found';
  end if;

  return query
  select
    ps.id,
    ps.employee_id,
    trim(concat_ws(' ', e.first_name, e.last_name)) as employee_full_name,
    e.job_title as employee_job_title,
    e.photo_url as employee_photo_url,
    ps.title,
    ps.start_at,
    ps.end_at,
    ps.timezone,
    ps.status,
    ps.source,
    ps.planning_role_id,
    pr.name as planning_role_name,
    pr.color as planning_role_color,
    ps.store_hours_validated,
    ps.outside_store_hours_reason,
    ps.employee_id = v_employee_id as is_my_shift
  from public.planned_shifts ps
  left join public.employees e on e.id = ps.employee_id
  left join public.planning_roles pr on pr.id = ps.planning_role_id
  where ps.tenant_id = v_tenant_id
    and ps.status <> 'cancelled'
    and ps.start_at < p_end_at
    and ps.end_at > p_start_at
    and (
      ps.employee_id = v_employee_id
      or ps.status in ('published', 'completed')
    )
  order by ps.start_at, trim(concat_ws(' ', e.first_name, e.last_name));
end;
$$;

grant execute on function public.get_worker_portal_planning_calendar(
  timestamp with time zone,
  timestamp with time zone
) to authenticated;

create or replace function public.update_my_worker_shift(
  p_shift_id uuid,
  p_start_at timestamp with time zone,
  p_end_at timestamp with time zone
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_employee_id uuid := public.worker_portal_employee_id();
  v_tenant_id uuid := public.worker_portal_tenant_id();
  v_shift_id uuid;
begin
  if v_employee_id is null or v_tenant_id is null then
    raise exception 'Worker portal account not found';
  end if;

  if p_end_at <= p_start_at then
    raise exception 'Shift end must be after start';
  end if;

  update public.planned_shifts ps
     set start_at = p_start_at,
         end_at = p_end_at,
         timezone = coalesce(nullif(ps.timezone, ''), 'America/Santiago'),
         updated_by = auth.uid(),
         store_hours_validated = true,
         outside_store_hours_reason = null,
         updated_at = now()
   where ps.id = p_shift_id
     and ps.tenant_id = v_tenant_id
     and ps.employee_id = v_employee_id
     and ps.status in ('draft', 'published')
   returning ps.id into v_shift_id;

  if v_shift_id is null then
    raise exception 'Shift not found or not editable';
  end if;

  return v_shift_id;
end;
$$;

grant execute on function public.update_my_worker_shift(
  uuid,
  timestamp with time zone,
  timestamp with time zone
) to authenticated;
