-- ============================================================================
-- WHEEL BUILDING SYSTEM MIGRATION
-- Run this in Supabase SQL Editor to create wheel building tables
-- ============================================================================

-- Table: wheel_hubs
create table if not exists wheel_hubs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid references products(id) on delete cascade,
  
  -- Basic Info
  name text not null,
  manufacturer text,
  model text,
  hub_type text check (hub_type in ('front', 'rear')) not null,
  
  -- Critical Measurements (in mm)
  old_mm numeric(5,1) not null,
  spoke_holes integer not null check (spoke_holes in (24, 28, 32, 36, 40)),
  
  -- Flange Measurements (for spoke length calculation)
  left_flange_diameter_mm numeric(5,2) not null,
  right_flange_diameter_mm numeric(5,2) not null,
  center_to_left_flange_mm numeric(5,2) not null,
  center_to_right_flange_mm numeric(5,2) not null,
  
  -- Compatibility
  brake_type text check (brake_type in ('rim', 'disc_6bolt', 'disc_centerlock')) not null,
  driver_type text check (driver_type in ('freewheel', 'cassette', 'fixed', 'none')) not null,
  axle_type text check (axle_type in ('quick_release', 'thru_axle_12mm', 'thru_axle_15mm', 'thru_axle_20mm', 'bolt_on')) not null,
  
  -- Additional Specs
  weight_grams integer,
  material text,
  bearing_type text,
  
  -- Metadata
  notes text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_wheel_hubs_tenant on wheel_hubs(tenant_id);
create index if not exists idx_wheel_hubs_product on wheel_hubs(product_id);
create index if not exists idx_wheel_hubs_old on wheel_hubs(old_mm);
create index if not exists idx_wheel_hubs_spoke_holes on wheel_hubs(spoke_holes);

alter table wheel_hubs enable row level security;

create policy "wheel_hubs_select" on wheel_hubs for select to authenticated using (tenant_id = public.user_tenant_id());
create policy "wheel_hubs_insert" on wheel_hubs for insert to authenticated with check (tenant_id = public.user_tenant_id());
create policy "wheel_hubs_update" on wheel_hubs for update to authenticated using (tenant_id = public.user_tenant_id());
create policy "wheel_hubs_delete" on wheel_hubs for delete to authenticated using (tenant_id = public.user_tenant_id());

-- Table: wheel_rims
create table if not exists wheel_rims (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid references products(id) on delete cascade,
  
  -- Basic Info
  name text not null,
  manufacturer text,
  model text,
  
  -- Critical Measurements (in mm)
  erd_mm numeric(5,2) not null,
  spoke_holes integer not null check (spoke_holes in (24, 28, 32, 36, 40)),
  internal_width_mm numeric(4,1) not null,
  external_width_mm numeric(4,1),
  rim_depth_mm numeric(4,1),
  
  -- Specifications
  wheel_size text not null,
  brake_type text check (brake_type in ('rim', 'disc')) not null,
  rim_type text check (rim_type in ('clincher', 'tubular', 'tubeless_ready', 'hookless')) not null,
  material text,
  
  -- Technical Details
  max_pressure_psi integer,
  weight_grams integer,
  spoke_hole_drilling text,
  
  -- Metadata
  notes text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_wheel_rims_tenant on wheel_rims(tenant_id);
create index if not exists idx_wheel_rims_product on wheel_rims(product_id);
create index if not exists idx_wheel_rims_erd on wheel_rims(erd_mm);
create index if not exists idx_wheel_rims_spoke_holes on wheel_rims(spoke_holes);

alter table wheel_rims enable row level security;

create policy "wheel_rims_select" on wheel_rims for select to authenticated using (tenant_id = public.user_tenant_id());
create policy "wheel_rims_insert" on wheel_rims for insert to authenticated with check (tenant_id = public.user_tenant_id());
create policy "wheel_rims_update" on wheel_rims for update to authenticated using (tenant_id = public.user_tenant_id());
create policy "wheel_rims_delete" on wheel_rims for delete to authenticated using (tenant_id = public.user_tenant_id());

-- Table: wheel_spokes
create table if not exists wheel_spokes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid references products(id) on delete cascade,
  
  -- Basic Info
  name text not null,
  manufacturer text,
  model text,
  
  -- Critical Specs
  length_mm integer not null,
  gauge numeric(3,2) not null,
  is_butted boolean not null default false,
  
  -- Specifications
  material text not null default 'stainless_steel',
  finish text,
  head_type text check (head_type in ('j_bend', 'straight_pull')) not null default 'j_bend',
  thread_type text,
  
  -- Technical Details
  tensile_strength_n integer,
  weight_grams numeric(4,2),
  
  -- Metadata
  notes text,
  image_url text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_wheel_spokes_tenant on wheel_spokes(tenant_id);
create index if not exists idx_wheel_spokes_product on wheel_spokes(product_id);
create index if not exists idx_wheel_spokes_length on wheel_spokes(length_mm);

alter table wheel_spokes enable row level security;

create policy "wheel_spokes_select" on wheel_spokes for select to authenticated using (tenant_id = public.user_tenant_id());
create policy "wheel_spokes_insert" on wheel_spokes for insert to authenticated with check (tenant_id = public.user_tenant_id());
create policy "wheel_spokes_update" on wheel_spokes for update to authenticated using (tenant_id = public.user_tenant_id());
create policy "wheel_spokes_delete" on wheel_spokes for delete to authenticated using (tenant_id = public.user_tenant_id());

-- Table: wheel_builds
create table if not exists wheel_builds (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  
  -- References
  bike_id uuid references bikes(id) on delete set null,
  mechanic_job_id uuid references mechanic_jobs(id) on delete set null,
  
  -- Build Info
  build_name text not null,
  wheel_position text check (wheel_position in ('front', 'rear')) not null,
  build_date date default current_date,
  
  -- Components
  hub_id uuid references wheel_hubs(id) on delete set null,
  rim_id uuid references wheel_rims(id) on delete set null,
  spoke_id uuid references wheel_spokes(id) on delete set null,
  
  -- Build Specifications
  spoke_count integer not null,
  lacing_pattern text not null,
  
  -- Calculated Spoke Lengths (in mm)
  left_spoke_length_mm numeric(5,2),
  right_spoke_length_mm numeric(5,2),
  
  -- Actual Spoke Products Used (for inventory)
  left_spoke_product_id uuid references products(id) on delete set null,
  right_spoke_product_id uuid references products(id) on delete set null,
  
  -- Additional Components
  nipple_type text,
  rim_tape_width_mm integer,
  
  -- Metadata
  notes text,
  mechanic_notes text,
  is_template boolean not null default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_wheel_builds_tenant on wheel_builds(tenant_id);
create index if not exists idx_wheel_builds_bike on wheel_builds(bike_id);

alter table wheel_builds enable row level security;

create policy "wheel_builds_select" on wheel_builds for select to authenticated using (tenant_id = public.user_tenant_id());
create policy "wheel_builds_insert" on wheel_builds for insert to authenticated with check (tenant_id = public.user_tenant_id());
create policy "wheel_builds_update" on wheel_builds for update to authenticated using (tenant_id = public.user_tenant_id());
create policy "wheel_builds_delete" on wheel_builds for delete to authenticated using (tenant_id = public.user_tenant_id());

-- SPOKE LENGTH CALCULATOR FUNCTION
create or replace function public.calculate_spoke_length(
  p_erd_mm numeric,
  p_flange_diameter_mm numeric,
  p_center_to_flange_mm numeric,
  p_spoke_holes integer,
  p_cross_pattern integer default 3
) returns numeric
language plpgsql
as $$
declare
  v_rim_radius numeric;
  v_flange_radius numeric;
  v_spoke_angle_rad numeric;
  v_spoke_length numeric;
  v_pi numeric := 3.14159265359;
begin
  if p_erd_mm is null or p_erd_mm <= 0 then
    raise exception 'Invalid ERD: %', p_erd_mm;
  end if;
  
  if p_spoke_holes not in (24, 28, 32, 36, 40) then
    raise exception 'Invalid spoke hole count: %', p_spoke_holes;
  end if;
  
  v_rim_radius := p_erd_mm / 2.0;
  v_flange_radius := p_flange_diameter_mm / 2.0;
  
  if p_cross_pattern = 0 then
    v_spoke_angle_rad := 0;
  else
    v_spoke_angle_rad := (2 * v_pi * p_cross_pattern) / p_spoke_holes;
  end if;
  
  v_spoke_length := sqrt(
    power(v_rim_radius, 2) +
    power(v_flange_radius, 2) +
    power(p_center_to_flange_mm, 2) -
    (2 * v_rim_radius * v_flange_radius * cos(v_spoke_angle_rad))
  );
  
  return round(v_spoke_length, 1);
end;
$$;

-- FIND COMPATIBLE HUBS FUNCTION
create or replace function public.find_compatible_hubs(
  p_tenant_id uuid,
  p_rim_id uuid,
  p_bike_old_mm numeric default null,
  p_hub_type text default 'rear'
) returns table (
  hub_id uuid,
  hub_name text,
  manufacturer text,
  old_mm numeric,
  spoke_holes integer,
  compatibility_score integer,
  notes text
)
language plpgsql
as $$
declare
  v_rim_spoke_holes integer;
  v_rim_brake_type text;
begin
  select r.spoke_holes, r.brake_type
  into v_rim_spoke_holes, v_rim_brake_type
  from wheel_rims r
  where r.id = p_rim_id and r.tenant_id = p_tenant_id;
  
  if not found then
    raise exception 'Rim not found: %', p_rim_id;
  end if;
  
  return query
  select
    h.id as hub_id,
    h.name as hub_name,
    h.manufacturer,
    h.old_mm,
    h.spoke_holes,
    case
      when h.spoke_holes = v_rim_spoke_holes then 100
      when h.brake_type = v_rim_brake_type then 80
      when p_bike_old_mm is not null and h.old_mm = p_bike_old_mm then 90
      else 50
    end as compatibility_score,
    case
      when h.spoke_holes <> v_rim_spoke_holes then '⚠️ Spoke hole mismatch'
      when h.brake_type <> v_rim_brake_type then '⚠️ Brake type mismatch'
      else '✅ Compatible'
    end as notes
  from wheel_hubs h
  where h.tenant_id = p_tenant_id
    and h.is_active = true
    and h.hub_type = p_hub_type
    and h.spoke_holes = v_rim_spoke_holes
  order by compatibility_score desc, h.name;
end;
$$;

-- FIND COMPATIBLE SPOKES FUNCTION
create or replace function public.find_compatible_spokes(
  p_tenant_id uuid,
  p_required_length_mm numeric,
  p_tolerance_mm numeric default 2.0
) returns table (
  spoke_id uuid,
  spoke_name text,
  length_mm integer,
  gauge numeric,
  manufacturer text,
  stock_quantity integer,
  length_difference_mm numeric
)
language plpgsql
as $$
begin
  return query
  select
    ws.id as spoke_id,
    ws.name as spoke_name,
    ws.length_mm,
    ws.gauge,
    ws.manufacturer,
    coalesce(p.inventory_qty, 0) as stock_quantity,
    abs(ws.length_mm - p_required_length_mm) as length_difference_mm
  from wheel_spokes ws
  left join products p on p.id = ws.product_id
  where ws.tenant_id = p_tenant_id
    and ws.is_active = true
    and ws.length_mm between (p_required_length_mm - p_tolerance_mm) and (p_required_length_mm + p_tolerance_mm)
  order by length_difference_mm, stock_quantity desc, ws.manufacturer;
end;
$$;
