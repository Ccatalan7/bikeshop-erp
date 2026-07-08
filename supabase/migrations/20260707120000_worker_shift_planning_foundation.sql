-- Worker portal login and shift planning foundation.
--
-- This migration is intentionally idempotent so it can be run through
-- `supabase db query --linked --file ...` and mirrored in core_schema.sql.

create or replace function public.normalize_worker_username(p_username text)
returns text
language sql
immutable
as $$
  select lower(trim(coalesce(p_username, '')));
$$;

grant execute on function public.normalize_worker_username(text) to anon, authenticated;

create unique index if not exists idx_employees_id_tenant_unique
  on public.employees(id, tenant_id);

create table if not exists public.employee_portal_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  auth_user_id uuid unique references auth.users(id) on delete set null,
  username text not null,
  login_email text not null unique,
  is_active boolean not null default true,
  must_reset_password boolean not null default false,
  last_login_at timestamp with time zone,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint employee_portal_accounts_employee_tenant_fk
    foreign key (employee_id, tenant_id) references public.employees(id, tenant_id)
    on delete cascade,
  constraint employee_portal_accounts_username_normalized
    check (username = public.normalize_worker_username(username)),
  constraint employee_portal_accounts_username_format
    check (username ~ '^[a-z0-9][a-z0-9._-]{2,31}$'),
  unique (tenant_id, employee_id),
  unique (tenant_id, username)
);

create index if not exists idx_employee_portal_accounts_tenant
  on public.employee_portal_accounts(tenant_id);
create index if not exists idx_employee_portal_accounts_employee
  on public.employee_portal_accounts(employee_id);
create index if not exists idx_employee_portal_accounts_auth_user
  on public.employee_portal_accounts(auth_user_id);
create index if not exists idx_employee_portal_accounts_username
  on public.employee_portal_accounts(tenant_id, username);

drop trigger if exists trg_employee_portal_accounts_updated_at
  on public.employee_portal_accounts cascade;
create trigger trg_employee_portal_accounts_updated_at
  before update on public.employee_portal_accounts
  for each row execute procedure public.set_updated_at();

create or replace function public.worker_portal_tenant_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  select epa.tenant_id
    into v_tenant_id
  from public.employee_portal_accounts epa
  join public.employees e on e.id = epa.employee_id
  where epa.auth_user_id = auth.uid()
    and epa.is_active = true
    and e.status = 'active'
  limit 1;

  return v_tenant_id;
end;
$$;

grant execute on function public.worker_portal_tenant_id() to authenticated;

create or replace function public.worker_portal_employee_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_employee_id uuid;
begin
  select epa.employee_id
    into v_employee_id
  from public.employee_portal_accounts epa
  join public.employees e on e.id = epa.employee_id
  where epa.auth_user_id = auth.uid()
    and epa.is_active = true
    and e.status = 'active'
  limit 1;

  return v_employee_id;
end;
$$;

grant execute on function public.worker_portal_employee_id() to authenticated;

create table if not exists public.planning_roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  color text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint planning_roles_code_normalized check (code = lower(trim(code))),
  constraint planning_roles_code_format check (code ~ '^[a-z0-9][a-z0-9_-]{1,31}$'),
  unique (tenant_id, code)
);

create unique index if not exists idx_planning_roles_id_tenant_unique
  on public.planning_roles(id, tenant_id);
create index if not exists idx_planning_roles_tenant
  on public.planning_roles(tenant_id);

drop trigger if exists trg_planning_roles_updated_at on public.planning_roles cascade;
create trigger trg_planning_roles_updated_at
  before update on public.planning_roles
  for each row execute procedure public.set_updated_at();

insert into public.planning_roles (tenant_id, code, name, color, sort_order, is_active)
select t.id, seed.code, seed.name, seed.color, seed.sort_order, true
from public.tenants t
cross join (values
  ('ventas', 'Ventas', '#2563EB', 10),
  ('taller', 'Taller', '#16A34A', 20),
  ('caja', 'Caja', '#F59E0B', 30),
  ('soporte', 'Soporte', '#7C3AED', 40)
) as seed(code, name, color, sort_order)
where t.is_active = true
on conflict (tenant_id, code) do update
set name = excluded.name,
    color = excluded.color,
    sort_order = excluded.sort_order,
    is_active = true;

create table if not exists public.employee_planning_roles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  planning_role_id uuid not null references public.planning_roles(id) on delete cascade,
  is_default boolean not null default false,
  created_at timestamp with time zone not null default now(),
  constraint employee_planning_roles_employee_tenant_fk
    foreign key (employee_id, tenant_id) references public.employees(id, tenant_id)
    on delete cascade,
  constraint employee_planning_roles_role_tenant_fk
    foreign key (planning_role_id, tenant_id) references public.planning_roles(id, tenant_id)
    on delete cascade,
  unique (tenant_id, employee_id, planning_role_id)
);

create index if not exists idx_employee_planning_roles_employee
  on public.employee_planning_roles(employee_id);
create index if not exists idx_employee_planning_roles_role
  on public.employee_planning_roles(planning_role_id);
create unique index if not exists idx_employee_planning_roles_one_default
  on public.employee_planning_roles(tenant_id, employee_id)
  where is_default = true;

create table if not exists public.employee_default_shift_blocks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  planning_role_id uuid references public.planning_roles(id) on delete set null,
  day_of_week integer not null check (day_of_week between 1 and 7),
  start_time time without time zone not null,
  end_time time without time zone not null,
  timezone text not null default 'America/Santiago',
  source text not null default 'profile'
    check (source in ('profile', 'worker', 'manager', 'generated')),
  is_active boolean not null default true,
  store_hours_validated boolean not null default false,
  outside_store_hours_reason text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint employee_default_shift_blocks_time_order
    check (start_time < end_time),
  constraint employee_default_shift_blocks_employee_tenant_fk
    foreign key (employee_id, tenant_id) references public.employees(id, tenant_id)
    on delete cascade
);

create index if not exists idx_employee_default_shift_blocks_employee
  on public.employee_default_shift_blocks(employee_id, day_of_week);
create index if not exists idx_employee_default_shift_blocks_tenant_day
  on public.employee_default_shift_blocks(tenant_id, day_of_week, start_time);

drop trigger if exists trg_employee_default_shift_blocks_updated_at
  on public.employee_default_shift_blocks cascade;
create trigger trg_employee_default_shift_blocks_updated_at
  before update on public.employee_default_shift_blocks
  for each row execute procedure public.set_updated_at();

create table if not exists public.planned_shifts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid references public.employees(id) on delete set null,
  planning_role_id uuid references public.planning_roles(id) on delete set null,
  title text,
  start_at timestamp with time zone not null,
  end_at timestamp with time zone not null,
  timezone text not null default 'America/Santiago',
  status text not null default 'draft'
    check (status in ('draft', 'published', 'cancelled', 'completed')),
  source text not null default 'manual'
    check (source in ('manual', 'default_schedule', 'worker_request', 'generated', 'service_order', 'project')),
  notes text,
  store_hours_snapshot jsonb,
  store_hours_validated boolean not null default false,
  outside_store_hours_reason text,
  published_at timestamp with time zone,
  published_by uuid references auth.users(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint planned_shifts_time_order check (start_at < end_at)
);

create unique index if not exists idx_planned_shifts_id_tenant_unique
  on public.planned_shifts(id, tenant_id);
create index if not exists idx_planned_shifts_tenant_time
  on public.planned_shifts(tenant_id, start_at, end_at);
create index if not exists idx_planned_shifts_employee_time
  on public.planned_shifts(employee_id, start_at, end_at);
create index if not exists idx_planned_shifts_status
  on public.planned_shifts(tenant_id, status);

drop trigger if exists trg_planned_shifts_updated_at on public.planned_shifts cascade;
create trigger trg_planned_shifts_updated_at
  before update on public.planned_shifts
  for each row execute procedure public.set_updated_at();

create table if not exists public.shift_change_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  planned_shift_id uuid references public.planned_shifts(id) on delete set null,
  request_type text not null
    check (request_type in ('create', 'update', 'delete', 'availability')),
  requested_start_at timestamp with time zone,
  requested_end_at timestamp with time zone,
  requested_role_id uuid references public.planning_roles(id) on delete set null,
  request_payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  worker_note text,
  manager_note text,
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  constraint shift_change_requests_requested_time_order
    check (requested_start_at is null or requested_end_at is null or requested_start_at < requested_end_at),
  constraint shift_change_requests_employee_tenant_fk
    foreign key (employee_id, tenant_id) references public.employees(id, tenant_id)
    on delete cascade
);

create index if not exists idx_shift_change_requests_employee
  on public.shift_change_requests(employee_id, status, created_at desc);
create index if not exists idx_shift_change_requests_tenant_status
  on public.shift_change_requests(tenant_id, status, created_at desc);

drop trigger if exists trg_shift_change_requests_updated_at
  on public.shift_change_requests cascade;
create trigger trg_shift_change_requests_updated_at
  before update on public.shift_change_requests
  for each row execute procedure public.set_updated_at();

create or replace function public.validate_shift_planning_tenant_consistency()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_TABLE_NAME = 'employee_default_shift_blocks' then
    if NEW.planning_role_id is not null and not exists (
      select 1 from public.planning_roles pr
      where pr.id = NEW.planning_role_id
        and pr.tenant_id = NEW.tenant_id
    ) then
      raise exception 'Planning role does not belong to this tenant';
    end if;
  elsif TG_TABLE_NAME = 'planned_shifts' then
    if NEW.employee_id is not null and not exists (
      select 1 from public.employees e
      where e.id = NEW.employee_id
        and e.tenant_id = NEW.tenant_id
    ) then
      raise exception 'Worker does not belong to this tenant';
    end if;

    if NEW.planning_role_id is not null and not exists (
      select 1 from public.planning_roles pr
      where pr.id = NEW.planning_role_id
        and pr.tenant_id = NEW.tenant_id
    ) then
      raise exception 'Planning role does not belong to this tenant';
    end if;
  elsif TG_TABLE_NAME = 'shift_change_requests' then
    if NEW.requested_role_id is not null and not exists (
      select 1 from public.planning_roles pr
      where pr.id = NEW.requested_role_id
        and pr.tenant_id = NEW.tenant_id
    ) then
      raise exception 'Requested planning role does not belong to this tenant';
    end if;

    if NEW.planned_shift_id is not null and not exists (
      select 1 from public.planned_shifts ps
      where ps.id = NEW.planned_shift_id
        and ps.tenant_id = NEW.tenant_id
    ) then
      raise exception 'Planned shift does not belong to this tenant';
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_employee_default_shift_blocks_tenant_consistency
  on public.employee_default_shift_blocks cascade;
create trigger trg_employee_default_shift_blocks_tenant_consistency
  before insert or update on public.employee_default_shift_blocks
  for each row execute procedure public.validate_shift_planning_tenant_consistency();

drop trigger if exists trg_planned_shifts_tenant_consistency on public.planned_shifts cascade;
create trigger trg_planned_shifts_tenant_consistency
  before insert or update on public.planned_shifts
  for each row execute procedure public.validate_shift_planning_tenant_consistency();

drop trigger if exists trg_shift_change_requests_tenant_consistency
  on public.shift_change_requests cascade;
create trigger trg_shift_change_requests_tenant_consistency
  before insert or update on public.shift_change_requests
  for each row execute procedure public.validate_shift_planning_tenant_consistency();

create or replace view public.shift_attendance_variances
with (security_invoker = true)
as
select
  ps.id as planned_shift_id,
  ps.tenant_id,
  ps.employee_id,
  ps.planning_role_id,
  ps.start_at,
  ps.end_at,
  ps.status as shift_status,
  round(extract(epoch from (ps.end_at - ps.start_at)) / 60.0, 2) as planned_minutes,
  att.first_check_in,
  att.last_check_out,
  att.actual_minutes,
  case
    when att.first_check_in is null then null
    else round(extract(epoch from (att.first_check_in - ps.start_at)) / 60.0, 2)
  end as start_delta_minutes,
  case
    when att.last_check_out is null then null
    else round(extract(epoch from (att.last_check_out - ps.end_at)) / 60.0, 2)
  end as end_delta_minutes,
  case
    when att.actual_minutes is null then null
    else round(att.actual_minutes - (extract(epoch from (ps.end_at - ps.start_at)) / 60.0), 2)
  end as variance_minutes
from public.planned_shifts ps
left join lateral (
  select
    min(a.check_in) as first_check_in,
    max(a.check_out) as last_check_out,
    round(sum(extract(epoch from (coalesce(a.check_out, now()) - a.check_in)) / 60.0), 2) as actual_minutes
  from public.attendances a
  where a.tenant_id = ps.tenant_id
    and a.employee_id = ps.employee_id
    and a.check_in >= ps.start_at - interval '12 hours'
    and a.check_in <= ps.end_at + interval '12 hours'
    and a.status in ('ongoing', 'completed', 'approved')
) att on true;

create or replace function public.resolve_worker_login(
  p_tenant text,
  p_username text
)
returns table (login_email text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tenant_key text := lower(trim(coalesce(p_tenant, '')));
  v_username text := public.normalize_worker_username(p_username);
  v_tenant_uuid uuid;
begin
  begin
    v_tenant_uuid := v_tenant_key::uuid;
  exception
    when invalid_text_representation then
      v_tenant_uuid := null;
  end;

  return query
  select epa.login_email
  from public.employee_portal_accounts epa
  join public.tenants t on t.id = epa.tenant_id
  join public.employees e on e.id = epa.employee_id
  where epa.username = v_username
    and epa.is_active = true
    and e.status = 'active'
    and t.is_active = true
    and (
      t.id = v_tenant_uuid
      or lower(coalesce(t.subdomain, '')) = v_tenant_key
      or lower(coalesce(t.custom_domain, '')) = v_tenant_key
      or lower(replace(coalesce(t.shop_name, ''), ' ', '')) = replace(v_tenant_key, ' ', '')
    )
  limit 1;
end;
$$;

grant execute on function public.resolve_worker_login(text, text) to anon, authenticated;

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
      'isActive', epa.is_active
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
      'photoUrl', e.photo_url,
      'email', e.email,
      'phone', e.phone,
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
        'source', dsb.source,
        'storeHoursValidated', dsb.store_hours_validated,
        'outsideStoreHoursReason', dsb.outside_store_hours_reason
      ) order by dsb.day_of_week, dsb.start_time)
      from public.employee_default_shift_blocks dsb
      where dsb.tenant_id = epa.tenant_id
        and dsb.employee_id = epa.employee_id
        and dsb.is_active = true
    ), '[]'::jsonb)
  )
  into v_context
  from public.employee_portal_accounts epa
  join public.employees e on e.id = epa.employee_id
  join public.tenants t on t.id = epa.tenant_id
  where epa.auth_user_id = auth.uid()
    and epa.is_active = true
    and e.status = 'active'
    and t.is_active = true
  limit 1;

  return v_context;
end;
$$;

grant execute on function public.get_my_worker_portal_context() to authenticated;

create or replace function public.get_my_worker_shifts(
  p_start_at timestamp with time zone,
  p_end_at timestamp with time zone
)
returns table (
  id uuid,
  title text,
  start_at timestamp with time zone,
  end_at timestamp with time zone,
  timezone text,
  status text,
  source text,
  planning_role_id uuid,
  planning_role_name text,
  store_hours_validated boolean,
  outside_store_hours_reason text,
  first_check_in timestamp with time zone,
  last_check_out timestamp with time zone,
  planned_minutes numeric,
  actual_minutes numeric,
  variance_minutes numeric
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
    ps.title,
    ps.start_at,
    ps.end_at,
    ps.timezone,
    ps.status,
    ps.source,
    ps.planning_role_id,
    pr.name as planning_role_name,
    ps.store_hours_validated,
    ps.outside_store_hours_reason,
    sav.first_check_in,
    sav.last_check_out,
    sav.planned_minutes,
    sav.actual_minutes,
    sav.variance_minutes
  from public.planned_shifts ps
  left join public.planning_roles pr on pr.id = ps.planning_role_id
  left join public.shift_attendance_variances sav on sav.planned_shift_id = ps.id
  where ps.tenant_id = v_tenant_id
    and ps.employee_id = v_employee_id
    and ps.status in ('draft', 'published', 'completed')
    and ps.start_at < p_end_at
    and ps.end_at > p_start_at
  order by ps.start_at;
end;
$$;

grant execute on function public.get_my_worker_shifts(timestamp with time zone, timestamp with time zone)
  to authenticated;

create or replace function public.request_my_shift_change(
  p_request_type text,
  p_planned_shift_id uuid default null,
  p_requested_start_at timestamp with time zone default null,
  p_requested_end_at timestamp with time zone default null,
  p_requested_role_id uuid default null,
  p_worker_note text default null,
  p_request_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_id uuid := public.worker_portal_employee_id();
  v_tenant_id uuid := public.worker_portal_tenant_id();
  v_request_id uuid;
begin
  if v_employee_id is null or v_tenant_id is null then
    raise exception 'Worker portal account not found';
  end if;

  if p_request_type not in ('create', 'update', 'delete', 'availability') then
    raise exception 'Unsupported shift request type: %', p_request_type;
  end if;

  if p_requested_start_at is not null
     and p_requested_end_at is not null
     and p_requested_start_at >= p_requested_end_at then
    raise exception 'Requested shift start must be before end';
  end if;

  if p_planned_shift_id is not null and not exists (
    select 1
    from public.planned_shifts ps
    where ps.id = p_planned_shift_id
      and ps.tenant_id = v_tenant_id
      and ps.employee_id = v_employee_id
  ) then
    raise exception 'Shift not found for current worker';
  end if;

  if p_requested_role_id is not null and not exists (
    select 1
    from public.planning_roles pr
    where pr.id = p_requested_role_id
      and pr.tenant_id = v_tenant_id
      and pr.is_active = true
  ) then
    raise exception 'Planning role not found';
  end if;

  insert into public.shift_change_requests (
    tenant_id,
    employee_id,
    planned_shift_id,
    request_type,
    requested_start_at,
    requested_end_at,
    requested_role_id,
    worker_note,
    request_payload
  )
  values (
    v_tenant_id,
    v_employee_id,
    p_planned_shift_id,
    p_request_type,
    p_requested_start_at,
    p_requested_end_at,
    p_requested_role_id,
    p_worker_note,
    coalesce(p_request_payload, '{}'::jsonb)
  )
  returning id into v_request_id;

  return v_request_id;
end;
$$;

grant execute on function public.request_my_shift_change(
  text,
  uuid,
  timestamp with time zone,
  timestamp with time zone,
  uuid,
  text,
  jsonb
) to authenticated;

alter table public.employee_portal_accounts enable row level security;
alter table public.planning_roles enable row level security;
alter table public.employee_planning_roles enable row level security;
alter table public.employee_default_shift_blocks enable row level security;
alter table public.planned_shifts enable row level security;
alter table public.shift_change_requests enable row level security;

drop policy if exists employee_portal_accounts_select on public.employee_portal_accounts;
drop policy if exists employee_portal_accounts_insert on public.employee_portal_accounts;
drop policy if exists employee_portal_accounts_update on public.employee_portal_accounts;
drop policy if exists employee_portal_accounts_delete on public.employee_portal_accounts;

create policy employee_portal_accounts_select on public.employee_portal_accounts
  for select to authenticated
  using (tenant_id = public.user_tenant_id() or auth_user_id = auth.uid());
create policy employee_portal_accounts_insert on public.employee_portal_accounts
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy employee_portal_accounts_update on public.employee_portal_accounts
  for update to authenticated
  using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());
create policy employee_portal_accounts_delete on public.employee_portal_accounts
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists planning_roles_select on public.planning_roles;
drop policy if exists planning_roles_insert on public.planning_roles;
drop policy if exists planning_roles_update on public.planning_roles;
drop policy if exists planning_roles_delete on public.planning_roles;

create policy planning_roles_select on public.planning_roles
  for select to authenticated
  using (tenant_id = public.user_tenant_id() or tenant_id = public.worker_portal_tenant_id());
create policy planning_roles_insert on public.planning_roles
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy planning_roles_update on public.planning_roles
  for update to authenticated
  using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());
create policy planning_roles_delete on public.planning_roles
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists employee_planning_roles_select on public.employee_planning_roles;
drop policy if exists employee_planning_roles_insert on public.employee_planning_roles;
drop policy if exists employee_planning_roles_update on public.employee_planning_roles;
drop policy if exists employee_planning_roles_delete on public.employee_planning_roles;

create policy employee_planning_roles_select on public.employee_planning_roles
  for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    or (
      tenant_id = public.worker_portal_tenant_id()
      and employee_id = public.worker_portal_employee_id()
    )
  );
create policy employee_planning_roles_insert on public.employee_planning_roles
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy employee_planning_roles_update on public.employee_planning_roles
  for update to authenticated
  using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());
create policy employee_planning_roles_delete on public.employee_planning_roles
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists employee_default_shift_blocks_select on public.employee_default_shift_blocks;
drop policy if exists employee_default_shift_blocks_insert on public.employee_default_shift_blocks;
drop policy if exists employee_default_shift_blocks_update on public.employee_default_shift_blocks;
drop policy if exists employee_default_shift_blocks_delete on public.employee_default_shift_blocks;

create policy employee_default_shift_blocks_select on public.employee_default_shift_blocks
  for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    or (
      tenant_id = public.worker_portal_tenant_id()
      and employee_id = public.worker_portal_employee_id()
    )
  );
create policy employee_default_shift_blocks_insert on public.employee_default_shift_blocks
  for insert to authenticated
  with check (
    tenant_id = public.user_tenant_id()
    or (
      tenant_id = public.worker_portal_tenant_id()
      and employee_id = public.worker_portal_employee_id()
    )
  );
create policy employee_default_shift_blocks_update on public.employee_default_shift_blocks
  for update to authenticated
  using (
    tenant_id = public.user_tenant_id()
    or (
      tenant_id = public.worker_portal_tenant_id()
      and employee_id = public.worker_portal_employee_id()
    )
  )
  with check (
    tenant_id = public.user_tenant_id()
    or (
      tenant_id = public.worker_portal_tenant_id()
      and employee_id = public.worker_portal_employee_id()
    )
  );
create policy employee_default_shift_blocks_delete on public.employee_default_shift_blocks
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists planned_shifts_select on public.planned_shifts;
drop policy if exists planned_shifts_insert on public.planned_shifts;
drop policy if exists planned_shifts_update on public.planned_shifts;
drop policy if exists planned_shifts_delete on public.planned_shifts;

create policy planned_shifts_select on public.planned_shifts
  for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    or (
      tenant_id = public.worker_portal_tenant_id()
      and employee_id = public.worker_portal_employee_id()
    )
  );
create policy planned_shifts_insert on public.planned_shifts
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy planned_shifts_update on public.planned_shifts
  for update to authenticated
  using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());
create policy planned_shifts_delete on public.planned_shifts
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists shift_change_requests_select on public.shift_change_requests;
drop policy if exists shift_change_requests_insert on public.shift_change_requests;
drop policy if exists shift_change_requests_update on public.shift_change_requests;
drop policy if exists shift_change_requests_delete on public.shift_change_requests;

create policy shift_change_requests_select on public.shift_change_requests
  for select to authenticated
  using (
    tenant_id = public.user_tenant_id()
    or (
      tenant_id = public.worker_portal_tenant_id()
      and employee_id = public.worker_portal_employee_id()
    )
  );
create policy shift_change_requests_insert on public.shift_change_requests
  for insert to authenticated
  with check (
    tenant_id = public.user_tenant_id()
    or (
      tenant_id = public.worker_portal_tenant_id()
      and employee_id = public.worker_portal_employee_id()
    )
  );
create policy shift_change_requests_update on public.shift_change_requests
  for update to authenticated
  using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());
create policy shift_change_requests_delete on public.shift_change_requests
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());
