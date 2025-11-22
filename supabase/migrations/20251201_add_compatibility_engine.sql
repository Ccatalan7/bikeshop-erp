-- SMART CATALOG & COMPATIBILITY ENGINE (Metadata + Telemetry)
-- ============================================================================

-- Core table: component types (e.g., rear_hub, rim, spoke, tire)
create table if not exists compat_component_types (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  code text not null,
  display_name text not null,
  parent_id uuid references compat_component_types(id) on delete cascade,
  discipline_scope text[] default array[]::text[],
  description text,
  icon_name text,
  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, code)
);

create index if not exists idx_compat_component_types_tenant on compat_component_types(tenant_id);
create index if not exists idx_compat_component_types_parent on compat_component_types(parent_id);
create index if not exists idx_compat_component_types_active on compat_component_types(tenant_id, is_active);

alter table compat_component_types enable row level security;

drop policy if exists "compat_component_types_select" on compat_component_types;
drop policy if exists "compat_component_types_insert" on compat_component_types;
drop policy if exists "compat_component_types_update" on compat_component_types;
drop policy if exists "compat_component_types_delete" on compat_component_types;

create policy "compat_component_types_select" on compat_component_types
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_component_types_insert" on compat_component_types
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_component_types_update" on compat_component_types
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_component_types_delete" on compat_component_types
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Alternate names/slugs per component type (e.g., "rear wheel hub", "eje trasero")
create table if not exists compat_component_aliases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  component_type_id uuid references compat_component_types(id) on delete cascade not null,
  alias text not null,
  locale text,
  notes text,
  created_at timestamp with time zone not null default now(),
  unique(tenant_id, component_type_id, lower(alias))
);

create index if not exists idx_compat_component_aliases_tenant on compat_component_aliases(tenant_id);
create index if not exists idx_compat_component_aliases_component on compat_component_aliases(component_type_id);

alter table compat_component_aliases enable row level security;

drop policy if exists "compat_component_aliases_select" on compat_component_aliases;
drop policy if exists "compat_component_aliases_insert" on compat_component_aliases;
drop policy if exists "compat_component_aliases_update" on compat_component_aliases;
drop policy if exists "compat_component_aliases_delete" on compat_component_aliases;

create policy "compat_component_aliases_select" on compat_component_aliases
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_component_aliases_insert" on compat_component_aliases
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_component_aliases_update" on compat_component_aliases
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_component_aliases_delete" on compat_component_aliases
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Master list of compatibility attributes (e.g., hub_spacing_mm, axle_type)
create table if not exists compat_attributes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  key text not null,
  label text not null,
  attribute_type text not null check (attribute_type in ('enum','numeric','boolean','text','json','range')),
  unit_code text,
  description text,
  min_value numeric,
  max_value numeric,
  precision_scale integer,
  enum_values text[] default array[]::text[],
  metadata jsonb not null default '{}'::jsonb,
  is_global boolean not null default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, key)
);

create index if not exists idx_compat_attributes_tenant on compat_attributes(tenant_id);
create index if not exists idx_compat_attributes_key on compat_attributes(lower(key));

alter table compat_attributes enable row level security;

drop policy if exists "compat_attributes_select" on compat_attributes;
drop policy if exists "compat_attributes_insert" on compat_attributes;
drop policy if exists "compat_attributes_update" on compat_attributes;
drop policy if exists "compat_attributes_delete" on compat_attributes;

create policy "compat_attributes_select" on compat_attributes
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_attributes_insert" on compat_attributes
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_attributes_update" on compat_attributes
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_attributes_delete" on compat_attributes
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Additional option rows for enum attributes (e.g., QR, thru_12)
create table if not exists compat_attribute_options (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  attribute_id uuid references compat_attributes(id) on delete cascade not null,
  value_key text not null,
  display_name text not null,
  description text,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now(),
  unique(tenant_id, attribute_id, lower(value_key))
);

create index if not exists idx_compat_attribute_options_tenant on compat_attribute_options(tenant_id);
create index if not exists idx_compat_attribute_options_attribute on compat_attribute_options(attribute_id);

alter table compat_attribute_options enable row level security;

drop policy if exists "compat_attribute_options_select" on compat_attribute_options;
drop policy if exists "compat_attribute_options_insert" on compat_attribute_options;
drop policy if exists "compat_attribute_options_update" on compat_attribute_options;
drop policy if exists "compat_attribute_options_delete" on compat_attribute_options;

create policy "compat_attribute_options_select" on compat_attribute_options
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_attribute_options_insert" on compat_attribute_options
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_attribute_options_update" on compat_attribute_options
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_attribute_options_delete" on compat_attribute_options
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Mapping table: which attributes belong to which component types and how they are used
create table if not exists compat_component_attribute_schema (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  component_type_id uuid references compat_component_types(id) on delete cascade not null,
  attribute_id uuid references compat_attributes(id) on delete cascade not null,
  is_required boolean not null default false,
  is_primary boolean not null default false,
  match_weight numeric not null default 1,
  ui_group text,
  ui_order integer not null default 0,
  validation jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, component_type_id, attribute_id)
);

create index if not exists idx_compat_component_attribute_schema_tenant on compat_component_attribute_schema(tenant_id);
create index if not exists idx_compat_component_attribute_schema_component on compat_component_attribute_schema(component_type_id);

alter table compat_component_attribute_schema enable row level security;

drop policy if exists "compat_component_attribute_schema_select" on compat_component_attribute_schema;
drop policy if exists "compat_component_attribute_schema_insert" on compat_component_attribute_schema;
drop policy if exists "compat_component_attribute_schema_update" on compat_component_attribute_schema;
drop policy if exists "compat_component_attribute_schema_delete" on compat_component_attribute_schema;

create policy "compat_component_attribute_schema_select" on compat_component_attribute_schema
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_component_attribute_schema_insert" on compat_component_attribute_schema
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_component_attribute_schema_update" on compat_component_attribute_schema
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_component_attribute_schema_delete" on compat_component_attribute_schema
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Discipline + component rules (JSON rule graph per discipline/component pairing)
create table if not exists compat_discipline_component_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  discipline_token text not null,
  component_type_id uuid references compat_component_types(id) on delete cascade not null,
  rule_payload jsonb not null default '{}'::jsonb,
  priority integer not null default 100,
  is_active boolean not null default true,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, discipline_token, component_type_id, priority)
);

create index if not exists idx_compat_discipline_rules_tenant on compat_discipline_component_rules(tenant_id);
create index if not exists idx_compat_discipline_rules_component on compat_discipline_component_rules(component_type_id);
create index if not exists idx_compat_discipline_rules_active on compat_discipline_component_rules(tenant_id, is_active);

alter table compat_discipline_component_rules enable row level security;

drop policy if exists "compat_discipline_rules_select" on compat_discipline_component_rules;
drop policy if exists "compat_discipline_rules_insert" on compat_discipline_component_rules;
drop policy if exists "compat_discipline_rules_update" on compat_discipline_component_rules;
drop policy if exists "compat_discipline_rules_delete" on compat_discipline_component_rules;

create policy "compat_discipline_rules_select" on compat_discipline_component_rules
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_discipline_rules_insert" on compat_discipline_component_rules
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_discipline_rules_update" on compat_discipline_component_rules
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_discipline_rules_delete" on compat_discipline_component_rules
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Conversion / adapter rules (HG -> Microspline, QR -> Thru, etc.)
create table if not exists compat_conversion_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  from_component_type_id uuid references compat_component_types(id) on delete cascade,
  to_component_type_id uuid references compat_component_types(id) on delete cascade,
  discipline_scope text[] default array[]::text[],
  requirements jsonb not null default '{}'::jsonb,
  adapter_notes text,
  labor_minutes integer,
  cost_estimate numeric,
  is_active boolean not null default true,
  priority integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, name)
);

create index if not exists idx_compat_conversion_rules_tenant on compat_conversion_rules(tenant_id);
create index if not exists idx_compat_conversion_rules_active on compat_conversion_rules(tenant_id, is_active);

alter table compat_conversion_rules enable row level security;

drop policy if exists "compat_conversion_rules_select" on compat_conversion_rules;
drop policy if exists "compat_conversion_rules_insert" on compat_conversion_rules;
drop policy if exists "compat_conversion_rules_update" on compat_conversion_rules;
drop policy if exists "compat_conversion_rules_delete" on compat_conversion_rules;

create policy "compat_conversion_rules_select" on compat_conversion_rules
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_conversion_rules_insert" on compat_conversion_rules
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_conversion_rules_update" on compat_conversion_rules
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_conversion_rules_delete" on compat_conversion_rules
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Adapter catalog (spacers, dropout kits, freehub swaps, etc.)
create table if not exists compat_adapter_catalog (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  name text not null,
  manufacturer text,
  product_id uuid references products(id) on delete set null,
  from_interface text[],
  to_interface text[],
  specs jsonb not null default '{}'::jsonb,
  notes text,
  weight_grams numeric,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, name)
);

create index if not exists idx_compat_adapter_catalog_tenant on compat_adapter_catalog(tenant_id);
create index if not exists idx_compat_adapter_catalog_product on compat_adapter_catalog(product_id);

alter table compat_adapter_catalog enable row level security;

drop policy if exists "compat_adapter_catalog_select" on compat_adapter_catalog;
drop policy if exists "compat_adapter_catalog_insert" on compat_adapter_catalog;
drop policy if exists "compat_adapter_catalog_update" on compat_adapter_catalog;
drop policy if exists "compat_adapter_catalog_delete" on compat_adapter_catalog;

create policy "compat_adapter_catalog_select" on compat_adapter_catalog
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_adapter_catalog_insert" on compat_adapter_catalog
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_adapter_catalog_update" on compat_adapter_catalog
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_adapter_catalog_delete" on compat_adapter_catalog
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Adapter components table: connect adapters to component requirements
create table if not exists compat_adapter_components (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  adapter_id uuid references compat_adapter_catalog(id) on delete cascade not null,
  component_type_id uuid references compat_component_types(id) on delete cascade not null,
  attribute_overrides jsonb not null default '{}'::jsonb,
  notes text,
  created_at timestamp with time zone not null default now(),
  unique(tenant_id, adapter_id, component_type_id)
);

create index if not exists idx_compat_adapter_components_tenant on compat_adapter_components(tenant_id);
create index if not exists idx_compat_adapter_components_adapter on compat_adapter_components(adapter_id);

alter table compat_adapter_components enable row level security;

drop policy if exists "compat_adapter_components_select" on compat_adapter_components;
drop policy if exists "compat_adapter_components_insert" on compat_adapter_components;
drop policy if exists "compat_adapter_components_update" on compat_adapter_components;
drop policy if exists "compat_adapter_components_delete" on compat_adapter_components;

create policy "compat_adapter_components_select" on compat_adapter_components
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_adapter_components_insert" on compat_adapter_components
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_adapter_components_update" on compat_adapter_components
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_adapter_components_delete" on compat_adapter_components
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Scoring weights per discipline/component (influences Mode 1/2/3)
create table if not exists compat_scoring_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  discipline_token text not null,
  component_type_id uuid references compat_component_types(id) on delete cascade not null,
  weight_payload jsonb not null default '{}'::jsonb,
  is_default boolean not null default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  unique(tenant_id, discipline_token, component_type_id)
);

create index if not exists idx_compat_scoring_profiles_tenant on compat_scoring_profiles(tenant_id);

alter table compat_scoring_profiles enable row level security;

drop policy if exists "compat_scoring_profiles_select" on compat_scoring_profiles;
drop policy if exists "compat_scoring_profiles_insert" on compat_scoring_profiles;
drop policy if exists "compat_scoring_profiles_update" on compat_scoring_profiles;
drop policy if exists "compat_scoring_profiles_delete" on compat_scoring_profiles;

create policy "compat_scoring_profiles_select" on compat_scoring_profiles
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_scoring_profiles_insert" on compat_scoring_profiles
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_scoring_profiles_update" on compat_scoring_profiles
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_scoring_profiles_delete" on compat_scoring_profiles
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Compatibility sessions (context for a wheel build or bike evaluation)
create table if not exists compat_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  bike_id uuid references bikes(id) on delete set null,
  wheel_build_id uuid references wheel_builds(id) on delete set null,
  initiated_by uuid references auth.users(id),
  context jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft','running','completed','failed')),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_compat_sessions_tenant on compat_sessions(tenant_id);
create index if not exists idx_compat_sessions_bike on compat_sessions(bike_id);
create index if not exists idx_compat_sessions_status on compat_sessions(status);

alter table compat_sessions enable row level security;

drop policy if exists "compat_sessions_select" on compat_sessions;
drop policy if exists "compat_sessions_insert" on compat_sessions;
drop policy if exists "compat_sessions_update" on compat_sessions;
drop policy if exists "compat_sessions_delete" on compat_sessions;

create policy "compat_sessions_select" on compat_sessions
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_sessions_insert" on compat_sessions
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_sessions_update" on compat_sessions
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_sessions_delete" on compat_sessions
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Compatibility evaluations (individual runs per component type)
create table if not exists compat_evaluations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  session_id uuid references compat_sessions(id) on delete cascade not null,
  component_type_id uuid references compat_component_types(id) on delete cascade not null,
  discipline_token text,
  evaluation_mode text not null default 'mode2',
  status text not null default 'pending' check (status in ('pending','running','completed','failed')),
  evaluator text not null default 'engine',
  warnings jsonb not null default '[]'::jsonb,
  errors jsonb not null default '[]'::jsonb,
  result_summary jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now(),
  completed_at timestamp with time zone,
  unique(tenant_id, session_id, component_type_id, evaluation_mode)
);

create index if not exists idx_compat_evaluations_tenant on compat_evaluations(tenant_id);
create index if not exists idx_compat_evaluations_session on compat_evaluations(session_id);

alter table compat_evaluations enable row level security;

drop policy if exists "compat_evaluations_select" on compat_evaluations;
drop policy if exists "compat_evaluations_insert" on compat_evaluations;
drop policy if exists "compat_evaluations_update" on compat_evaluations;
drop policy if exists "compat_evaluations_delete" on compat_evaluations;

create policy "compat_evaluations_select" on compat_evaluations
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_evaluations_insert" on compat_evaluations
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_evaluations_update" on compat_evaluations
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_evaluations_delete" on compat_evaluations
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Evaluation items: individual product recommendations with scoring + adapters
create table if not exists compat_evaluation_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  evaluation_id uuid references compat_evaluations(id) on delete cascade not null,
  product_id uuid references products(id) on delete set null,
  score numeric not null default 0,
  classification text not null default 'mode2' check (classification in ('mode1','mode2','mode3','blocked')),
  adapter_plan jsonb not null default '[]'::jsonb,
  warnings jsonb not null default '[]'::jsonb,
  reasoning jsonb not null default '{}'::jsonb,
  stock_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now(),
  unique(tenant_id, evaluation_id, product_id)
);

create index if not exists idx_compat_evaluation_items_tenant on compat_evaluation_items(tenant_id);
create index if not exists idx_compat_evaluation_items_eval on compat_evaluation_items(evaluation_id);
create index if not exists idx_compat_evaluation_items_product on compat_evaluation_items(product_id);

alter table compat_evaluation_items enable row level security;

drop policy if exists "compat_evaluation_items_select" on compat_evaluation_items;
drop policy if exists "compat_evaluation_items_insert" on compat_evaluation_items;
drop policy if exists "compat_evaluation_items_update" on compat_evaluation_items;
drop policy if exists "compat_evaluation_items_delete" on compat_evaluation_items;

create policy "compat_evaluation_items_select" on compat_evaluation_items
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_evaluation_items_insert" on compat_evaluation_items
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_evaluation_items_update" on compat_evaluation_items
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_evaluation_items_delete" on compat_evaluation_items
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Recommendation snapshots (cached payloads for sharing budgets/quotes)
create table if not exists compat_recommendations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  evaluation_id uuid references compat_evaluations(id) on delete cascade not null,
  quote_id uuid references sales_invoices(id) on delete set null,
  payload jsonb not null,
  status text not null default 'draft' check (status in ('draft','sent','accepted','rejected')),
  expires_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_compat_recommendations_tenant on compat_recommendations(tenant_id);
create index if not exists idx_compat_recommendations_quote on compat_recommendations(quote_id);

alter table compat_recommendations enable row level security;

drop policy if exists "compat_recommendations_select" on compat_recommendations;
drop policy if exists "compat_recommendations_insert" on compat_recommendations;
drop policy if exists "compat_recommendations_update" on compat_recommendations;
drop policy if exists "compat_recommendations_delete" on compat_recommendations;

create policy "compat_recommendations_select" on compat_recommendations
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_recommendations_insert" on compat_recommendations
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_recommendations_update" on compat_recommendations
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_recommendations_delete" on compat_recommendations
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Telemetry table for rule hits, adapters used, etc.
create table if not exists compat_rule_audit_log (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  evaluation_item_id uuid references compat_evaluation_items(id) on delete cascade,
  rule_source text not null,
  result text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now()
);

create index if not exists idx_compat_rule_audit_log_tenant on compat_rule_audit_log(tenant_id);

alter table compat_rule_audit_log enable row level security;

drop policy if exists "compat_rule_audit_log_select" on compat_rule_audit_log;
drop policy if exists "compat_rule_audit_log_insert" on compat_rule_audit_log;
drop policy if exists "compat_rule_audit_log_delete" on compat_rule_audit_log;

create policy "compat_rule_audit_log_select" on compat_rule_audit_log
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "compat_rule_audit_log_insert" on compat_rule_audit_log
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "compat_rule_audit_log_delete" on compat_rule_audit_log
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());

-- Wheel build linkage: store compatibility session reference + recommendation snapshot
alter table wheel_builds
  add column if not exists compatibility_session_id uuid references compat_sessions(id) on delete set null,
  add column if not exists compatibility_summary jsonb;

create index if not exists idx_wheel_builds_compat_session on wheel_builds(compatibility_session_id);

-- ============================================================================
-- COMPATIBILITY ENGINE HELPERS & RPC FUNCTIONS
-- ============================================================================

create or replace function public.compat_get_component_type_id(
  p_tenant_id uuid,
  p_code text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_component_type_id uuid;
begin
  select id into v_component_type_id
    from compat_component_types
   where tenant_id = p_tenant_id
     and code = p_code
     and is_active = true
   order by updated_at desc
   limit 1;

  if v_component_type_id is null then
    raise exception 'Component type % not found for tenant %', p_code, p_tenant_id;
  end if;

  return v_component_type_id;
end;
$$;

grant execute on function public.compat_get_component_type_id(uuid, text) to authenticated;

create or replace function public.compat_start_session(
  p_tenant_id uuid,
  p_bike_id uuid default null,
  p_wheel_build_id uuid default null,
  p_context jsonb default '{}'::jsonb,
  p_status text default 'draft'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id uuid;
  v_payload jsonb := coalesce(p_context, '{}'::jsonb);
begin
  if p_wheel_build_id is not null then
    select id
      into v_session_id
      from compat_sessions
     where tenant_id = p_tenant_id
       and wheel_build_id = p_wheel_build_id
     order by created_at desc
     limit 1;
  end if;

  if v_session_id is not null then
    update compat_sessions
       set context = coalesce(context, '{}'::jsonb) || v_payload,
           bike_id = coalesce(p_bike_id, bike_id),
           status = coalesce(nullif(p_status, ''), status),
           updated_at = now()
     where id = v_session_id;
  else
    insert into compat_sessions (tenant_id, bike_id, wheel_build_id, context, status)
    values (p_tenant_id, p_bike_id, p_wheel_build_id, v_payload, coalesce(nullif(p_status, ''), 'draft'))
    returning id into v_session_id;
  end if;

  return v_session_id;
end;
$$;

grant execute on function public.compat_start_session(uuid, uuid, uuid, jsonb, text) to authenticated;

create or replace function public.compat_fetch_component_candidates(
  p_tenant_id uuid,
  p_component_type_id uuid,
  p_filters jsonb default '{}'::jsonb,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  product_id uuid,
  product_name text,
  sku text,
  brand_name text,
  category_id uuid,
  price numeric,
  price_currency text,
  stock_quantity integer,
  specifications jsonb,
  match_score numeric,
  match_reasons jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_filters jsonb := coalesce(p_filters, '{}'::jsonb);
  v_component_code text;
begin
  select code
    into v_component_code
    from compat_component_types
   where tenant_id = p_tenant_id
     and id = p_component_type_id
     and is_active = true;

  if v_component_code is null then
    raise exception 'Component type % not found for tenant %', p_component_type_id, p_tenant_id;
  end if;

  return query
    with attr_schema as (
      select cas.attribute_id,
             attr.key,
             attr.attribute_type,
             cas.match_weight,
             (v_filters ? attr.key) as has_filter,
             (v_filters->>attr.key) as filter_value
        from compat_component_attribute_schema cas
        join compat_attributes attr on attr.id = cas.attribute_id
       where cas.tenant_id = p_tenant_id
         and cas.component_type_id = p_component_type_id
    ),
    product_candidates as (
      select p.id,
             p.name,
             p.sku,
             p.brand,
             p.category_id,
             p.price,
             p.price_currency,
             p.stock_quantity,
             coalesce(p.specifications, '{}'::jsonb) as specs
        from products p
       where p.tenant_id = p_tenant_id
         and (
           (p.specifications->>'component_type') = v_component_code
           or v_component_code is null
         )
    )
    select
      pc.id as product_id,
      pc.name as product_name,
      pc.sku,
      coalesce(pc.brand, '') as brand_name,
      pc.category_id,
      pc.price,
      pc.price_currency,
      pc.stock_quantity,
      pc.specs as specifications,
      coalesce(attr_eval.match_score, 0) as match_score,
      coalesce(attr_eval.match_reasons, '[]'::jsonb) as match_reasons
    from product_candidates pc
    left join lateral (
      select
        coalesce(sum(
          case
            when attr_schema.has_filter is false then 0
            when pc.specs ? attr_schema.key
                 and attr_schema.filter_value is not null
                 and lower(pc.specs->>attr_schema.key) = lower(attr_schema.filter_value)
              then coalesce(attr_schema.match_weight, 1)
            else 0
          end
        ), 0) as match_score,
        coalesce(jsonb_agg(
          jsonb_build_object(
            'key', attr_schema.key,
            'filter', attr_schema.filter_value,
            'product', pc.specs->>attr_schema.key,
            'matched', case
              when attr_schema.has_filter and pc.specs ? attr_schema.key and attr_schema.filter_value is not null
                   and lower(pc.specs->>attr_schema.key) = lower(attr_schema.filter_value)
                then true
              else false
            end
          )
        ) filter (where attr_schema.has_filter), '[]'::jsonb) as match_reasons
      from attr_schema
    ) attr_eval on true
    order by attr_eval.match_score desc, pc.stock_quantity desc, pc.name
    limit greatest(p_limit, 1)
    offset greatest(p_offset, 0);
end;
$$;

grant execute on function public.compat_fetch_component_candidates(uuid, uuid, jsonb, integer, integer) to authenticated;

create or replace function public.compat_record_evaluation(
  p_tenant_id uuid,
  p_session_id uuid,
  p_component_type_id uuid,
  p_evaluation_mode text default 'mode2',
  p_items jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eval_id uuid;
  v_item jsonb;
  v_total integer := 0;
begin
  insert into compat_evaluations (
    tenant_id,
    session_id,
    component_type_id,
    discipline_token,
    evaluation_mode,
    status,
    warnings,
    errors
  ) values (
    p_tenant_id,
    p_session_id,
    p_component_type_id,
    null,
    coalesce(nullif(p_evaluation_mode, ''), 'mode2'),
    'running',
    '[]'::jsonb,
    '[]'::jsonb
  ) returning id into v_eval_id;

  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) = 'array' then
    for v_item in select * from jsonb_array_elements(p_items)
    loop
      insert into compat_evaluation_items (
        tenant_id,
        evaluation_id,
        product_id,
        score,
        classification,
        adapter_plan,
        warnings,
        reasoning,
        stock_snapshot
      ) values (
        p_tenant_id,
        v_eval_id,
        nullif(v_item->>'product_id', '')::uuid,
        coalesce(nullif(v_item->>'score', '')::numeric, 0),
        coalesce(nullif(v_item->>'classification', ''), 'mode2'),
        coalesce(v_item->'adapter_plan', '[]'::jsonb),
        coalesce(v_item->'warnings', '[]'::jsonb),
        coalesce(v_item->'reasoning', '{}'::jsonb),
        coalesce(v_item->'stock_snapshot', '{}'::jsonb)
      );
      v_total := v_total + 1;
    end loop;
  end if;

  update compat_evaluations
     set status = 'completed',
         completed_at = now(),
         result_summary = jsonb_build_object('items', v_total)
   where id = v_eval_id;

  update compat_sessions
     set updated_at = now(),
         status = case when status = 'draft' then 'completed' else status end
   where id = p_session_id
     and tenant_id = p_tenant_id;

  return v_eval_id;
end;
$$;

grant execute on function public.compat_record_evaluation(uuid, uuid, uuid, text, jsonb) to authenticated;

create or replace function public.compat_recommend_spokes(
  p_tenant_id uuid,
  p_session_id uuid,
  p_component_type_code text default 'spoke',
  p_filters jsonb default '{}'::jsonb,
  p_limit integer default 20
)
returns table (
  product_id uuid,
  product_name text,
  sku text,
  brand_name text,
  category_id uuid,
  price numeric,
  price_currency text,
  stock_quantity integer,
  specifications jsonb,
  match_score numeric,
  match_reasons jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_component_type_id uuid;
begin
  v_component_type_id := public.compat_get_component_type_id(p_tenant_id, coalesce(nullif(p_component_type_code, ''), 'spoke'));

  return query
    select *
      from public.compat_fetch_component_candidates(
        p_tenant_id,
        v_component_type_id,
        p_filters,
        p_limit,
        0
      );
end;
$$;

grant execute on function public.compat_recommend_spokes(uuid, uuid, text, jsonb, integer) to authenticated;

create or replace function public.wheel_build_attach_compatibility(
  p_tenant_id uuid,
  p_wheel_build_id uuid,
  p_session_id uuid,
  p_summary jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated boolean := false;
begin
  update wheel_builds
     set compatibility_session_id = p_session_id,
         compatibility_summary = coalesce(compatibility_summary, '{}'::jsonb) || coalesce(p_summary, '{}'::jsonb),
         updated_at = now()
   where id = p_wheel_build_id
     and tenant_id = p_tenant_id;

  if found then
    v_updated := true;
  end if;

  update compat_sessions
     set wheel_build_id = coalesce(wheel_build_id, p_wheel_build_id),
         updated_at = now()
   where id = p_session_id
     and tenant_id = p_tenant_id;

  return v_updated;
end;
$$;

grant execute on function public.wheel_build_attach_compatibility(uuid, uuid, uuid, jsonb) to authenticated;




