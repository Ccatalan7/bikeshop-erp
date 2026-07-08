-- Let a worker replace only their own default shift blocks from the worker PWA.

create or replace function public.set_my_default_shift_blocks(
  p_blocks jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid := public.worker_portal_employee_id();
  v_tenant_id uuid := public.worker_portal_tenant_id();
  v_count integer := 0;
begin
  if v_employee_id is null or v_tenant_id is null then
    raise exception 'Worker portal account not found';
  end if;

  if p_blocks is null then
    p_blocks := '[]'::jsonb;
  end if;

  if jsonb_typeof(p_blocks) <> 'array' then
    raise exception 'Default shift blocks must be a JSON array';
  end if;

  if jsonb_array_length(p_blocks) > 21 then
    raise exception 'Default shift blocks limit exceeded';
  end if;

  create temporary table if not exists worker_shift_blocks_input (
    idx integer,
    day_of_week integer,
    start_time time without time zone,
    end_time time without time zone,
    timezone text,
    planning_role_id uuid
  ) on commit drop;

  truncate table worker_shift_blocks_input;

  insert into worker_shift_blocks_input (
    idx,
    day_of_week,
    start_time,
    end_time,
    timezone,
    planning_role_id
  )
  select
    row_number() over (),
    (item->>'dayOfWeek')::integer,
    (item->>'startTime')::time,
    (item->>'endTime')::time,
    coalesce(nullif(item->>'timezone', ''), 'America/Santiago'),
    nullif(item->>'planningRoleId', '')::uuid
  from jsonb_array_elements(p_blocks) as item;

  select count(*) into v_count from worker_shift_blocks_input;

  if exists (
    select 1
    from worker_shift_blocks_input
    where day_of_week not between 1 and 7
       or start_time >= end_time
  ) then
    raise exception 'Default shift block contains invalid day or time';
  end if;

  if exists (
    select 1
    from worker_shift_blocks_input input
    where input.planning_role_id is not null
      and not exists (
        select 1
        from public.employee_planning_roles epr
        join public.planning_roles pr on pr.id = epr.planning_role_id
        where epr.tenant_id = v_tenant_id
          and epr.employee_id = v_employee_id
          and epr.planning_role_id = input.planning_role_id
          and pr.is_active = true
      )
  ) then
    raise exception 'Planning role is not assigned to current worker';
  end if;

  if exists (
    select 1
    from worker_shift_blocks_input a
    join worker_shift_blocks_input b
      on a.day_of_week = b.day_of_week
     and a.idx < b.idx
     and a.start_time < b.end_time
     and a.end_time > b.start_time
  ) then
    raise exception 'Default shift blocks cannot overlap';
  end if;

  update public.employee_default_shift_blocks
  set is_active = false,
      updated_by = auth.uid()
  where tenant_id = v_tenant_id
    and employee_id = v_employee_id
    and is_active = true;

  insert into public.employee_default_shift_blocks (
    tenant_id,
    employee_id,
    planning_role_id,
    day_of_week,
    start_time,
    end_time,
    timezone,
    source,
    is_active,
    store_hours_validated,
    outside_store_hours_reason,
    created_by,
    updated_by
  )
  select
    v_tenant_id,
    v_employee_id,
    planning_role_id,
    day_of_week,
    start_time,
    end_time,
    timezone,
    'worker',
    true,
    true,
    null,
    auth.uid(),
    auth.uid()
  from worker_shift_blocks_input;

  return jsonb_build_object('saved', v_count);
end;
$$;

grant execute on function public.set_my_default_shift_blocks(jsonb) to authenticated;
