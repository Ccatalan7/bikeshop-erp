-- Worker portal attendance and payroll self-service.
-- Exposes only the logged-in trabajador's own attendance and payroll rows.

create or replace function public.get_my_worker_attendances(
  p_start_at timestamp with time zone,
  p_end_at timestamp with time zone
)
returns table (
  id uuid,
  employee_id uuid,
  check_in timestamp with time zone,
  check_out timestamp with time zone,
  worked_hours numeric,
  overtime_hours numeric,
  break_minutes integer,
  status text,
  notes text
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

  if p_start_at is null or p_end_at is null or p_start_at >= p_end_at then
    raise exception 'Invalid attendance period';
  end if;

  return query
  select
    a.id,
    a.employee_id,
    a.check_in,
    a.check_out,
    a.worked_hours,
    a.overtime_hours,
    a.break_minutes,
    a.status::text,
    a.notes
  from public.attendances a
  where a.tenant_id = v_tenant_id
    and a.employee_id = v_employee_id
    and a.check_in < p_end_at
    and coalesce(a.check_out, now()) >= p_start_at
  order by a.check_in;
end;
$$;

grant execute on function public.get_my_worker_attendances(
  timestamp with time zone,
  timestamp with time zone
) to authenticated;

create or replace function public.get_my_worker_payroll_for_period(
  p_start_date date,
  p_end_date date
)
returns table (
  voucher_id uuid,
  voucher_number text,
  period_start date,
  period_end date,
  period_label text,
  status text,
  paid_at timestamp with time zone,
  line_id uuid,
  worked_hours numeric,
  overtime_hours numeric,
  hourly_rate numeric,
  overtime_rate numeric,
  regular_amount numeric,
  overtime_amount numeric,
  total_amount numeric,
  payment_method text,
  payment_method_name text
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

  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'Invalid payroll period';
  end if;

  return query
  select
    pv.id as voucher_id,
    pv.voucher_number,
    pv.period_start,
    pv.period_end,
    pv.period_label,
    pv.status::text,
    pv.paid_at,
    pvl.id as line_id,
    pvl.worked_hours,
    pvl.overtime_hours,
    pvl.hourly_rate,
    pvl.overtime_rate,
    pvl.regular_amount,
    pvl.overtime_amount,
    pvl.total_amount,
    pvl.payment_method,
    pm.name as payment_method_name
  from public.payroll_voucher_lines pvl
  join public.payroll_vouchers pv
    on pv.id = pvl.voucher_id
   and pv.tenant_id = pvl.tenant_id
  left join public.payment_methods pm
    on pm.id = pvl.payment_method_id
   and pm.tenant_id = pvl.tenant_id
  where pvl.tenant_id = v_tenant_id
    and pvl.employee_id = v_employee_id
    and pvl.is_included = true
    and pv.period_start <= p_end_date
    and pv.period_end >= p_start_date
    and pv.status <> 'voided'
  order by pv.period_end desc, pv.created_at desc;
end;
$$;

grant execute on function public.get_my_worker_payroll_for_period(date, date)
  to authenticated;
