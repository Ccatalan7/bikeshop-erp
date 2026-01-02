-- Migration: Add attendance summary function for payroll preview
-- This function returns total worked hours per employee for a given date range

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
security definer
set search_path = public
as $$
begin
  return query
  select 
    e.id as employee_id,
    e.name as employee_name,
    coalesce(sum(a.worked_hours), 0)::numeric as total_hours,
    count(distinct date(a.check_in))::integer as total_days
  from employees e
  left join attendances a on a.employee_id = e.id
    and a.status in ('completed', 'approved')
    and date(a.check_in) between p_start_date and p_end_date
  where e.status = 'active'
  group by e.id, e.name
  order by e.name;
end;
$$;

-- Grant execute permission
grant execute on function public.get_attendance_summary_for_period(date, date) to authenticated;
