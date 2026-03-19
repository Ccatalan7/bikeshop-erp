-- ============================================================================
-- SPEC ENGINE: Technical Templates + Service Profiles
-- Migration: 20260318_spec_engine.sql
--
-- Creates 11 tables covering:
--   - Product technical spec schema (spec_definitions, spec_templates, spec_template_fields)
--   - Category-to-template mapping (category_tech_mappings)
--   - Per-product spec values (product_spec_values)
--   - Service profile engine (service_profiles, service_product_profile_mappings,
--     service_profile_targets, service_profile_questions,
--     service_profile_part_rules, service_profile_task_templates)
--
-- Then seeds the BRAKE DOMAIN as the first full-cycle domain:
--   - 22 system spec definitions
--   - 7 spec templates + their field assignments
--   - 7 service profiles + targets + questions + part rules + task templates
--   - Category-to-template mappings for Viñabike (tenant 5443b130-...)
--   - Service product-to-profile mappings for Viñabike
--
-- Architecture decisions baked in:
--   - tenant_id = NULL   → system-level (readable by all tenants, not modifiable)
--   - tenant_id = UUID   → tenant-level custom (full CRUD for that tenant)
--   - visibility_rules   → [{field, operator, value}] flat AND conditions
--   - Line item evolution → deferred to Milestone 5 (ALTER TABLE, not here)
-- ============================================================================


-- ============================================================================
-- 1. SPEC DEFINITIONS
-- Reusable field definitions. tenant_id NULL = system, UUID = tenant custom.
-- ============================================================================

create table if not exists spec_definitions (
  id                       uuid        primary key default gen_random_uuid(),
  tenant_id                uuid        references tenants(id) on delete cascade,
  key                      text        not null,
  label                    text        not null,
  description              text,
  data_type                text        not null default 'text'
                             check (data_type in ('text','number','boolean','single_select','multi_select','range','json')),
  unit                     text,
  allowed_values           jsonb       not null default '[]',
  validation_rules         jsonb       not null default '{}',
  is_filterable            boolean     not null default false,
  is_required_by_default   boolean     not null default false,
  is_compatibility_relevant boolean    not null default false,
  is_customer_visible      boolean     not null default true,
  is_mechanic_visible      boolean     not null default true,
  group_name               text,
  sort_order               integer     not null default 0,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

-- system keys globally unique; tenant keys unique within tenant
create unique index if not exists idx_spec_definitions_system_key
  on spec_definitions (key) where tenant_id is null;
create unique index if not exists idx_spec_definitions_tenant_key
  on spec_definitions (tenant_id, key) where tenant_id is not null;
create index if not exists idx_spec_definitions_tenant
  on spec_definitions (tenant_id);

alter table spec_definitions enable row level security;
drop policy if exists "spec_definitions_select" on spec_definitions;
drop policy if exists "spec_definitions_insert" on spec_definitions;
drop policy if exists "spec_definitions_update" on spec_definitions;
drop policy if exists "spec_definitions_delete" on spec_definitions;

create policy "spec_definitions_select" on spec_definitions for select to authenticated
  using (tenant_id is null or tenant_id = public.user_tenant_id());
create policy "spec_definitions_insert" on spec_definitions for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "spec_definitions_update" on spec_definitions for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "spec_definitions_delete" on spec_definitions for delete to authenticated
  using (tenant_id = public.user_tenant_id());


-- ============================================================================
-- 2. SPEC TEMPLATES
-- Ficha técnica schemas. tenant_id NULL = system template.
-- ============================================================================

create table if not exists spec_templates (
  id               uuid        primary key default gen_random_uuid(),
  tenant_id        uuid        references tenants(id) on delete cascade,
  key              text        not null,
  name             text        not null,
  technical_family text        not null,
  description      text,
  default_tags     jsonb       not null default '[]',
  is_active        boolean     not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create unique index if not exists idx_spec_templates_system_key
  on spec_templates (key) where tenant_id is null;
create unique index if not exists idx_spec_templates_tenant_key
  on spec_templates (tenant_id, key) where tenant_id is not null;
create index if not exists idx_spec_templates_tenant
  on spec_templates (tenant_id);
create index if not exists idx_spec_templates_family
  on spec_templates (technical_family) where tenant_id is null;

alter table spec_templates enable row level security;
drop policy if exists "spec_templates_select" on spec_templates;
drop policy if exists "spec_templates_insert" on spec_templates;
drop policy if exists "spec_templates_update" on spec_templates;
drop policy if exists "spec_templates_delete" on spec_templates;

create policy "spec_templates_select" on spec_templates for select to authenticated
  using (tenant_id is null or tenant_id = public.user_tenant_id());
create policy "spec_templates_insert" on spec_templates for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "spec_templates_update" on spec_templates for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "spec_templates_delete" on spec_templates for delete to authenticated
  using (tenant_id = public.user_tenant_id());


-- ============================================================================
-- 3. SPEC TEMPLATE FIELDS
-- Which spec definitions belong to which template, with ordering, sections,
-- visibility rules, and defaults.
--
-- visibility_rules format: [{field, operator, value}] — ALL must be true to show.
-- field = spec_definition.key; operators: eq, neq, in, not_in.
-- ============================================================================

create table if not exists spec_template_fields (
  id                  uuid        primary key default gen_random_uuid(),
  tenant_id           uuid        references tenants(id) on delete cascade,
  template_id         uuid        not null references spec_templates(id) on delete cascade,
  spec_definition_id  uuid        not null references spec_definitions(id) on delete cascade,
  is_required         boolean     not null default false,
  section_key         text        not null default 'general',
  sort_order          integer     not null default 0,
  default_value_json  jsonb,
  visibility_rules    jsonb       not null default '[]',
  helper_text         text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (template_id, spec_definition_id)
);

create index if not exists idx_spec_template_fields_template
  on spec_template_fields (template_id);
create index if not exists idx_spec_template_fields_definition
  on spec_template_fields (spec_definition_id);

alter table spec_template_fields enable row level security;
drop policy if exists "spec_template_fields_select" on spec_template_fields;
drop policy if exists "spec_template_fields_insert" on spec_template_fields;
drop policy if exists "spec_template_fields_update" on spec_template_fields;
drop policy if exists "spec_template_fields_delete" on spec_template_fields;

create policy "spec_template_fields_select" on spec_template_fields for select to authenticated
  using (tenant_id is null or tenant_id = public.user_tenant_id());
create policy "spec_template_fields_insert" on spec_template_fields for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "spec_template_fields_update" on spec_template_fields for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "spec_template_fields_delete" on spec_template_fields for delete to authenticated
  using (tenant_id = public.user_tenant_id());


-- ============================================================================
-- 4. CATEGORY TECH MAPPINGS
-- Connects business categories to technical families and templates.
-- Always tenant-scoped (each tenant maps their own category tree).
-- ============================================================================

create table if not exists category_tech_mappings (
  id               uuid        primary key default gen_random_uuid(),
  tenant_id        uuid        not null references tenants(id) on delete cascade,
  category_id      uuid        not null references product_categories(id) on delete cascade,
  technical_family text        not null,
  template_id      uuid        references spec_templates(id) on delete set null,
  default_tags     jsonb       not null default '[]',
  status           text        not null default 'active'
                     check (status in ('active', 'pending')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (tenant_id, category_id)
);

create index if not exists idx_category_tech_mappings_tenant
  on category_tech_mappings (tenant_id);
create index if not exists idx_category_tech_mappings_category
  on category_tech_mappings (category_id);
create index if not exists idx_category_tech_mappings_template
  on category_tech_mappings (template_id);

alter table category_tech_mappings enable row level security;
drop policy if exists "category_tech_mappings_select" on category_tech_mappings;
drop policy if exists "category_tech_mappings_insert" on category_tech_mappings;
drop policy if exists "category_tech_mappings_update" on category_tech_mappings;
drop policy if exists "category_tech_mappings_delete" on category_tech_mappings;

create policy "category_tech_mappings_select" on category_tech_mappings for select to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "category_tech_mappings_insert" on category_tech_mappings for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "category_tech_mappings_update" on category_tech_mappings for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "category_tech_mappings_delete" on category_tech_mappings for delete to authenticated
  using (tenant_id = public.user_tenant_id());


-- ============================================================================
-- 5. PRODUCT SPEC VALUES
-- Actual technical values per product.
-- display_value = human-readable string; populated on write by Flutter or trigger.
-- ============================================================================

create table if not exists product_spec_values (
  id                  uuid        primary key default gen_random_uuid(),
  tenant_id           uuid        not null references tenants(id) on delete cascade,
  product_id          uuid        not null references products(id) on delete cascade,
  spec_definition_id  uuid        not null references spec_definitions(id) on delete cascade,
  value_text          text,
  value_number        numeric,
  value_boolean       boolean,
  value_option        text,
  value_json          jsonb,
  display_value       text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (tenant_id, product_id, spec_definition_id)
);

create index if not exists idx_product_spec_values_tenant
  on product_spec_values (tenant_id);
create index if not exists idx_product_spec_values_product
  on product_spec_values (product_id);
create index if not exists idx_product_spec_values_product_def
  on product_spec_values (product_id, spec_definition_id);
create index if not exists idx_product_spec_values_filterable
  on product_spec_values (spec_definition_id, value_option)
  where value_option is not null;

alter table product_spec_values enable row level security;
drop policy if exists "product_spec_values_select" on product_spec_values;
drop policy if exists "product_spec_values_insert" on product_spec_values;
drop policy if exists "product_spec_values_update" on product_spec_values;
drop policy if exists "product_spec_values_delete" on product_spec_values;

create policy "product_spec_values_select" on product_spec_values for select to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "product_spec_values_insert" on product_spec_values for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "product_spec_values_update" on product_spec_values for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "product_spec_values_delete" on product_spec_values for delete to authenticated
  using (tenant_id = public.user_tenant_id());


-- ============================================================================
-- 6. SERVICE PROFILES
-- Defines operational behavior for a billable service product.
-- tenant_id NULL = system profile.
-- summary templates use {{question_key}} placeholder tokens.
-- ============================================================================

create table if not exists service_profiles (
  id                        uuid        primary key default gen_random_uuid(),
  tenant_id                 uuid        references tenants(id) on delete cascade,
  key                       text        not null,
  name                      text        not null,
  service_family            text        not null,
  description               text,
  customer_summary_template text,
  mechanic_summary_template text,
  is_active                 boolean     not null default true,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create unique index if not exists idx_service_profiles_system_key
  on service_profiles (key) where tenant_id is null;
create unique index if not exists idx_service_profiles_tenant_key
  on service_profiles (tenant_id, key) where tenant_id is not null;
create index if not exists idx_service_profiles_tenant
  on service_profiles (tenant_id);
create index if not exists idx_service_profiles_family
  on service_profiles (service_family) where tenant_id is null;

alter table service_profiles enable row level security;
drop policy if exists "service_profiles_select" on service_profiles;
drop policy if exists "service_profiles_insert" on service_profiles;
drop policy if exists "service_profiles_update" on service_profiles;
drop policy if exists "service_profiles_delete" on service_profiles;

create policy "service_profiles_select" on service_profiles for select to authenticated
  using (tenant_id is null or tenant_id = public.user_tenant_id());
create policy "service_profiles_insert" on service_profiles for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "service_profiles_update" on service_profiles for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "service_profiles_delete" on service_profiles for delete to authenticated
  using (tenant_id = public.user_tenant_id());


-- ============================================================================
-- 7. SERVICE PRODUCT PROFILE MAPPINGS
-- Links billable service products to their service profiles.
-- Always tenant-scoped.
-- ============================================================================

create table if not exists service_product_profile_mappings (
  id                 uuid        primary key default gen_random_uuid(),
  tenant_id          uuid        not null references tenants(id) on delete cascade,
  product_id         uuid        not null references products(id) on delete cascade,
  service_profile_id uuid        not null references service_profiles(id) on delete cascade,
  status             text        not null default 'active'
                       check (status in ('active', 'pending')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (tenant_id, product_id)
);

create index if not exists idx_svc_product_map_tenant
  on service_product_profile_mappings (tenant_id);
create index if not exists idx_svc_product_map_product
  on service_product_profile_mappings (product_id);
create index if not exists idx_svc_product_map_profile
  on service_product_profile_mappings (service_profile_id);

alter table service_product_profile_mappings enable row level security;
drop policy if exists "svc_product_map_select" on service_product_profile_mappings;
drop policy if exists "svc_product_map_insert" on service_product_profile_mappings;
drop policy if exists "svc_product_map_update" on service_product_profile_mappings;
drop policy if exists "svc_product_map_delete" on service_product_profile_mappings;

create policy "svc_product_map_select" on service_product_profile_mappings for select to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "svc_product_map_insert" on service_product_profile_mappings for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "svc_product_map_update" on service_product_profile_mappings for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "svc_product_map_delete" on service_product_profile_mappings for delete to authenticated
  using (tenant_id = public.user_tenant_id());


-- ============================================================================
-- 8. SERVICE PROFILE TARGETS
-- Defines what a service can target (brake, wheel, hub, etc.)
-- and whether position (front/rear) is applicable.
-- ============================================================================

create table if not exists service_profile_targets (
  id                    uuid        primary key default gen_random_uuid(),
  tenant_id             uuid        references tenants(id) on delete cascade,
  service_profile_id    uuid        not null references service_profiles(id) on delete cascade,
  target_family         text        not null,
  target_position_mode  text        not null default 'none'
                          check (target_position_mode in ('none','front_rear','left_right','both_allowed')),
  target_rules          jsonb       not null default '{}',
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index if not exists idx_svc_profile_targets_profile
  on service_profile_targets (service_profile_id);

alter table service_profile_targets enable row level security;
drop policy if exists "svc_profile_targets_select" on service_profile_targets;
drop policy if exists "svc_profile_targets_insert" on service_profile_targets;
drop policy if exists "svc_profile_targets_update" on service_profile_targets;
drop policy if exists "svc_profile_targets_delete" on service_profile_targets;

create policy "svc_profile_targets_select" on service_profile_targets for select to authenticated
  using (tenant_id is null or tenant_id = public.user_tenant_id());
create policy "svc_profile_targets_insert" on service_profile_targets for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "svc_profile_targets_update" on service_profile_targets for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "svc_profile_targets_delete" on service_profile_targets for delete to authenticated
  using (tenant_id = public.user_tenant_id());


-- ============================================================================
-- 9. SERVICE PROFILE QUESTIONS
-- The guided wizard questions.
-- is_advanced = true → shown in collapsible "advanced" section.
-- visibility_rules: [{question_key, operator, value}] — show only if all conditions met.
-- ============================================================================

create table if not exists service_profile_questions (
  id                 uuid        primary key default gen_random_uuid(),
  tenant_id          uuid        references tenants(id) on delete cascade,
  service_profile_id uuid        not null references service_profiles(id) on delete cascade,
  key                text        not null,
  label              text        not null,
  question_type      text        not null
                       check (question_type in ('single_select','multi_select','text','number','boolean','product_picker')),
  is_required        boolean     not null default false,
  is_advanced        boolean     not null default false,
  sort_order         integer     not null default 0,
  options_json       jsonb       not null default '[]',
  visibility_rules   jsonb       not null default '[]',
  default_answer_json jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (service_profile_id, key)
);

create index if not exists idx_svc_profile_questions_profile
  on service_profile_questions (service_profile_id);

alter table service_profile_questions enable row level security;
drop policy if exists "svc_profile_questions_select" on service_profile_questions;
drop policy if exists "svc_profile_questions_insert" on service_profile_questions;
drop policy if exists "svc_profile_questions_update" on service_profile_questions;
drop policy if exists "svc_profile_questions_delete" on service_profile_questions;

create policy "svc_profile_questions_select" on service_profile_questions for select to authenticated
  using (tenant_id is null or tenant_id = public.user_tenant_id());
create policy "svc_profile_questions_insert" on service_profile_questions for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "svc_profile_questions_update" on service_profile_questions for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "svc_profile_questions_delete" on service_profile_questions for delete to authenticated
  using (tenant_id = public.user_tenant_id());


-- ============================================================================
-- 10. SERVICE PROFILE PART RULES
-- Defines what parts to suggest or require based on question answers.
-- conditions_json: [{question_key, operator, value}] — all must be true to apply.
-- suggested_category_ids: system rules leave this empty; tenants fill their own UUIDs.
-- ============================================================================

create table if not exists service_profile_part_rules (
  id                       uuid        primary key default gen_random_uuid(),
  tenant_id                uuid        references tenants(id) on delete cascade,
  service_profile_id       uuid        not null references service_profiles(id) on delete cascade,
  rule_name                text        not null,
  conditions_json          jsonb       not null default '[]',
  suggested_category_ids   jsonb       not null default '[]',
  suggested_product_ids    jsonb       not null default '[]',
  default_quantity         integer     not null default 1,
  is_required              boolean     not null default false,
  sort_order               integer     not null default 0,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create index if not exists idx_svc_profile_part_rules_profile
  on service_profile_part_rules (service_profile_id);

alter table service_profile_part_rules enable row level security;
drop policy if exists "svc_profile_part_rules_select" on service_profile_part_rules;
drop policy if exists "svc_profile_part_rules_insert" on service_profile_part_rules;
drop policy if exists "svc_profile_part_rules_update" on service_profile_part_rules;
drop policy if exists "svc_profile_part_rules_delete" on service_profile_part_rules;

create policy "svc_profile_part_rules_select" on service_profile_part_rules for select to authenticated
  using (tenant_id is null or tenant_id = public.user_tenant_id());
create policy "svc_profile_part_rules_insert" on service_profile_part_rules for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "svc_profile_part_rules_update" on service_profile_part_rules for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "svc_profile_part_rules_delete" on service_profile_part_rules for delete to authenticated
  using (tenant_id = public.user_tenant_id());


-- ============================================================================
-- 11. SERVICE PROFILE TASK TEMPLATES
-- Mechanic task checklist generated per service line.
-- conditions_json: only show task when conditions are met.
-- ============================================================================

create table if not exists service_profile_task_templates (
  id                 uuid        primary key default gen_random_uuid(),
  tenant_id          uuid        references tenants(id) on delete cascade,
  service_profile_id uuid        not null references service_profiles(id) on delete cascade,
  task_name          text        not null,
  task_description   text,
  sort_order         integer     not null default 0,
  conditions_json    jsonb       not null default '[]',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index if not exists idx_svc_profile_task_templates_profile
  on service_profile_task_templates (service_profile_id);

alter table service_profile_task_templates enable row level security;
drop policy if exists "svc_profile_task_templates_select" on service_profile_task_templates;
drop policy if exists "svc_profile_task_templates_insert" on service_profile_task_templates;
drop policy if exists "svc_profile_task_templates_update" on service_profile_task_templates;
drop policy if exists "svc_profile_task_templates_delete" on service_profile_task_templates;

create policy "svc_profile_task_templates_select" on service_profile_task_templates for select to authenticated
  using (tenant_id is null or tenant_id = public.user_tenant_id());
create policy "svc_profile_task_templates_insert" on service_profile_task_templates for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
create policy "svc_profile_task_templates_update" on service_profile_task_templates for update to authenticated
  using (tenant_id = public.user_tenant_id());
create policy "svc_profile_task_templates_delete" on service_profile_task_templates for delete to authenticated
  using (tenant_id = public.user_tenant_id());


-- ============================================================================
-- SEEDING — BRAKE DOMAIN (FIRST WAVE)
-- All seed data uses tenant_id = NULL (system-level).
-- Safe to re-run: every INSERT uses ON CONFLICT DO NOTHING.
-- ============================================================================


-- ============================================================================
-- S1. SYSTEM SPEC DEFINITIONS — BRAKE FIELDS
-- ============================================================================

insert into spec_definitions
  (tenant_id, key, label, data_type, allowed_values, is_filterable,
   is_compatibility_relevant, group_name, sort_order)
values
  -- Identification
  (null, 'brake_system',            'Sistema de Freno',                   'single_select',
   '["Shimano","SRAM","Magura","Tektro","Hayes","Bengal","TRP","Hope","Promax","Genérico"]',
   true, true, 'Identificación', 10),

  (null, 'brake_type',              'Tipo de Freno',                      'single_select',
   '["Disco Hidráulico","Disco Mecánico","V-Brake","Cantilever"]',
   true, true, 'Identificación', 20),

  (null, 'brake_position',          'Posición',                           'single_select',
   '["Delantero","Trasero","Universal"]',
   true, false, 'Identificación', 30),

  -- Brake pad fields
  (null, 'pad_shape_code',          'Código de Forma (Pastilla)',         'text',
   '[]', true, true, 'Compatibilidad', 10),

  (null, 'compound_type',           'Compuesto',                          'single_select',
   '["Metálico","Orgánico","Semi-Metálico","Cerámico"]',
   true, true, 'Material', 10),

  (null, 'pad_spring_included',     'Incluye Resorte',                    'boolean',
   '[]', false, false, 'Contenido', 10),

  (null, 'pad_finned',              'Con Aletas de Calor',                'boolean',
   '[]', true, false, 'Características', 10),

  -- Rotor fields
  (null, 'rotor_diameter_mm',       'Diámetro del Rotor (mm)',            'single_select',
   '["140","160","180","203","220","160/140","180/160","203/180"]',
   true, true, 'Dimensiones', 10),

  (null, 'rotor_mount_type',        'Montaje del Rotor',                  'single_select',
   '["6 pernos","Centerlock"]',
   true, true, 'Montaje', 10),

  (null, 'rotor_thickness_mm',      'Espesor del Rotor (mm)',             'number',
   '[]', false, false, 'Dimensiones', 20),

  (null, 'rotor_floating',          'Rotor Flotante',                     'boolean',
   '[]', false, false, 'Características', 10),

  (null, 'rotor_material',          'Material del Rotor',                 'single_select',
   '["Acero Inoxidable","Acero","Aluminio (Pista Acerada)"]',
   true, false, 'Material', 10),

  -- Caliper / mounting
  (null, 'mount_standard',          'Estándar de Montaje',                'single_select',
   '["Post Mount","Flat Mount","International Standard","Adaptor Requerido"]',
   true, true, 'Montaje', 10),

  (null, 'piston_count',            'Número de Pistones',                 'single_select',
   '["2","4","6"]',
   true, true, 'Especificaciones', 10),

  (null, 'caliper_hydraulic',       'Hidráulico',                         'boolean',
   '[]', true, true, 'Especificaciones', 20),

  -- Hydraulic system
  (null, 'fluid_type',              'Tipo de Fluido',                     'single_select',
   '["Aceite Mineral","DOT 4","DOT 5.1"]',
   true, true, 'Sistema Hidráulico', 10),

  (null, 'hose_length_mm',          'Largo de Manguera (mm)',             'number',
   '[]', false, false, 'Sistema Hidráulico', 20),

  (null, 'hose_fitting_type',       'Tipo de Fitting',                    'single_select',
   '["Oliva + Barb","Compresión","Push-fit"]',
   false, false, 'Sistema Hidráulico', 30),

  (null, 'bleed_port',              'Puerto de Purga',                    'single_select',
   '["Tornillo","Jeringa de Empuje","Llave 7mm","Llave T25"]',
   false, false, 'Sistema Hidráulico', 40),

  -- General compatibility
  (null, 'pad_compatibility_note',  'Compatibilidad de Pastilla (nota)',  'text',
   '[]', false, true, 'Compatibilidad', 20),

  (null, 'reach_adjust',            'Regulación de Alcance',              'boolean',
   '[]', false, false, 'Características', 20),

  (null, 'tool_size_mm',            'Tamaño de Herramienta (mm)',         'text',
   '[]', false, false, 'Instalación', 10)

on conflict do nothing;


-- ============================================================================
-- S2. SYSTEM SPEC TEMPLATES — BRAKE DOMAIN
-- ============================================================================

insert into spec_templates
  (tenant_id, key, name, technical_family, description, is_active)
values
  (null, 'brake_pad',            'Pastilla de Freno',          'brake_pad',      'Pastillas para frenos de disco o de llanta',                true),
  (null, 'rotor',                'Rotor de Freno',             'rotor',          'Rotores o discos de freno',                                 true),
  (null, 'brake_caliper',        'Caliper de Freno',           'brake_caliper',  'Calipers completos hidráulicos o mecánicos',                true),
  (null, 'hydraulic_disc_brake', 'Freno Disco Hidráulico',     'complete_brake', 'Kit o freno completo hidráulico',                           true),
  (null, 'mechanical_disc_brake','Freno Disco Mecánico',       'complete_brake', 'Freno de disco mecánico completo',                          true),
  (null, 'rim_brake',            'Freno de Llanta / V-Brake',  'rim_brake',      'Frenos tipo V-Brake o cantilever',                          true),
  (null, 'brake_lever',          'Manilla de Freno',           'brake_lever',    'Manillas o palancas de freno independientes del sistema',   true)
on conflict do nothing;


-- ============================================================================
-- S3. TEMPLATE FIELDS — assign spec definitions to each brake template
-- Uses key-based lookup to avoid hardcoded UUIDs.
-- ============================================================================

do $$
declare
  t_brake_pad           uuid;
  t_rotor               uuid;
  t_brake_caliper       uuid;
  t_hydraulic_brake     uuid;
  t_mechanical_brake    uuid;
  t_rim_brake           uuid;
  t_brake_lever         uuid;

  d_brake_system        uuid;
  d_brake_type          uuid;
  d_brake_position      uuid;
  d_pad_shape_code      uuid;
  d_compound_type       uuid;
  d_pad_spring_included uuid;
  d_pad_finned          uuid;
  d_rotor_diameter_mm   uuid;
  d_rotor_mount_type    uuid;
  d_rotor_thickness_mm  uuid;
  d_rotor_floating      uuid;
  d_rotor_material      uuid;
  d_mount_standard      uuid;
  d_piston_count        uuid;
  d_caliper_hydraulic   uuid;
  d_fluid_type          uuid;
  d_hose_length_mm      uuid;
  d_hose_fitting_type   uuid;
  d_bleed_port          uuid;
  d_pad_compat_note     uuid;
  d_reach_adjust        uuid;
  d_tool_size_mm        uuid;
begin
  -- load template IDs
  select id into t_brake_pad           from spec_templates where key = 'brake_pad'            and tenant_id is null;
  select id into t_rotor               from spec_templates where key = 'rotor'                and tenant_id is null;
  select id into t_brake_caliper       from spec_templates where key = 'brake_caliper'        and tenant_id is null;
  select id into t_hydraulic_brake     from spec_templates where key = 'hydraulic_disc_brake' and tenant_id is null;
  select id into t_mechanical_brake    from spec_templates where key = 'mechanical_disc_brake' and tenant_id is null;
  select id into t_rim_brake           from spec_templates where key = 'rim_brake'            and tenant_id is null;
  select id into t_brake_lever         from spec_templates where key = 'brake_lever'          and tenant_id is null;

  -- load definition IDs
  select id into d_brake_system        from spec_definitions where key = 'brake_system'           and tenant_id is null;
  select id into d_brake_type          from spec_definitions where key = 'brake_type'             and tenant_id is null;
  select id into d_brake_position      from spec_definitions where key = 'brake_position'         and tenant_id is null;
  select id into d_pad_shape_code      from spec_definitions where key = 'pad_shape_code'         and tenant_id is null;
  select id into d_compound_type       from spec_definitions where key = 'compound_type'          and tenant_id is null;
  select id into d_pad_spring_included from spec_definitions where key = 'pad_spring_included'    and tenant_id is null;
  select id into d_pad_finned          from spec_definitions where key = 'pad_finned'             and tenant_id is null;
  select id into d_rotor_diameter_mm   from spec_definitions where key = 'rotor_diameter_mm'     and tenant_id is null;
  select id into d_rotor_mount_type    from spec_definitions where key = 'rotor_mount_type'       and tenant_id is null;
  select id into d_rotor_thickness_mm  from spec_definitions where key = 'rotor_thickness_mm'    and tenant_id is null;
  select id into d_rotor_floating      from spec_definitions where key = 'rotor_floating'         and tenant_id is null;
  select id into d_rotor_material      from spec_definitions where key = 'rotor_material'         and tenant_id is null;
  select id into d_mount_standard      from spec_definitions where key = 'mount_standard'         and tenant_id is null;
  select id into d_piston_count        from spec_definitions where key = 'piston_count'           and tenant_id is null;
  select id into d_caliper_hydraulic   from spec_definitions where key = 'caliper_hydraulic'      and tenant_id is null;
  select id into d_fluid_type          from spec_definitions where key = 'fluid_type'             and tenant_id is null;
  select id into d_hose_length_mm      from spec_definitions where key = 'hose_length_mm'         and tenant_id is null;
  select id into d_hose_fitting_type   from spec_definitions where key = 'hose_fitting_type'      and tenant_id is null;
  select id into d_bleed_port          from spec_definitions where key = 'bleed_port'             and tenant_id is null;
  select id into d_pad_compat_note     from spec_definitions where key = 'pad_compatibility_note' and tenant_id is null;
  select id into d_reach_adjust        from spec_definitions where key = 'reach_adjust'           and tenant_id is null;
  select id into d_tool_size_mm        from spec_definitions where key = 'tool_size_mm'           and tenant_id is null;

  -- brake_pad fields
  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_brake_pad, d_brake_system,        false, 'identification', 10),
    (null, t_brake_pad, d_brake_type,          true,  'identification', 20),
    (null, t_brake_pad, d_brake_position,      false, 'identification', 30),
    (null, t_brake_pad, d_pad_shape_code,      true,  'compatibility',  10),
    (null, t_brake_pad, d_compound_type,       true,  'material',       10),
    (null, t_brake_pad, d_pad_spring_included, false, 'contents',       10),
    (null, t_brake_pad, d_pad_finned,          false, 'features',       10),
    (null, t_brake_pad, d_pad_compat_note,     false, 'compatibility',  20)
  on conflict do nothing;

  -- rotor fields
  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_rotor, d_brake_system,       false, 'identification', 10),
    (null, t_rotor, d_brake_position,     false, 'identification', 20),
    (null, t_rotor, d_rotor_diameter_mm,  true,  'dimensions',     10),
    (null, t_rotor, d_rotor_mount_type,   true,  'mounting',       10),
    (null, t_rotor, d_rotor_thickness_mm, false, 'dimensions',     20),
    (null, t_rotor, d_rotor_floating,     false, 'features',       10),
    (null, t_rotor, d_rotor_material,     false, 'material',       10),
    (null, t_rotor, d_tool_size_mm,       false, 'installation',   10)
  on conflict do nothing;

  -- brake_caliper fields
  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_brake_caliper, d_brake_system,       false, 'identification', 10),
    (null, t_brake_caliper, d_brake_type,         true,  'identification', 20),
    (null, t_brake_caliper, d_brake_position,     false, 'identification', 30),
    (null, t_brake_caliper, d_mount_standard,     true,  'mounting',       10),
    (null, t_brake_caliper, d_piston_count,       true,  'specs',          10),
    (null, t_brake_caliper, d_caliper_hydraulic,  true,  'specs',          20),
    (null, t_brake_caliper, d_pad_shape_code,     true,  'compatibility',  10),
    (null, t_brake_caliper, d_rotor_diameter_mm,  false, 'compatibility',  20),
    (null, t_brake_caliper, d_fluid_type,         false, 'hydraulic',      10),
    (null, t_brake_caliper, d_hose_fitting_type,  false, 'hydraulic',      20),
    (null, t_brake_caliper, d_bleed_port,         false, 'hydraulic',      30),
    (null, t_brake_caliper, d_reach_adjust,       false, 'features',       10)
  on conflict do nothing;

  -- hydraulic_disc_brake fields (complete brake system)
  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_hydraulic_brake, d_brake_system,      true,  'identification', 10),
    (null, t_hydraulic_brake, d_brake_position,    true,  'identification', 20),
    (null, t_hydraulic_brake, d_fluid_type,        true,  'hydraulic',      10),
    (null, t_hydraulic_brake, d_hose_length_mm,    false, 'hydraulic',      20),
    (null, t_hydraulic_brake, d_hose_fitting_type, false, 'hydraulic',      30),
    (null, t_hydraulic_brake, d_bleed_port,        false, 'hydraulic',      40),
    (null, t_hydraulic_brake, d_mount_standard,    true,  'mounting',       10),
    (null, t_hydraulic_brake, d_piston_count,      false, 'specs',          10),
    (null, t_hydraulic_brake, d_rotor_diameter_mm, false, 'compatibility',  10),
    (null, t_hydraulic_brake, d_pad_shape_code,    false, 'compatibility',  20),
    (null, t_hydraulic_brake, d_reach_adjust,      false, 'features',       10)
  on conflict do nothing;

  -- mechanical_disc_brake fields
  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_mechanical_brake, d_brake_system,      false, 'identification', 10),
    (null, t_mechanical_brake, d_brake_position,    false, 'identification', 20),
    (null, t_mechanical_brake, d_mount_standard,    true,  'mounting',       10),
    (null, t_mechanical_brake, d_rotor_diameter_mm, true,  'compatibility',  10),
    (null, t_mechanical_brake, d_pad_shape_code,    false, 'compatibility',  20),
    (null, t_mechanical_brake, d_reach_adjust,      false, 'features',       10),
    (null, t_mechanical_brake, d_tool_size_mm,      false, 'installation',   10)
  on conflict do nothing;

  -- rim_brake (V-Brake) fields
  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_rim_brake, d_brake_system,   false, 'identification', 10),
    (null, t_rim_brake, d_brake_position, false, 'identification', 20),
    (null, t_rim_brake, d_reach_adjust,   false, 'features',       10),
    (null, t_rim_brake, d_tool_size_mm,   false, 'installation',   10)
  on conflict do nothing;

  -- brake_lever fields
  insert into spec_template_fields
    (tenant_id, template_id, spec_definition_id, is_required, section_key, sort_order)
  values
    (null, t_brake_lever, d_brake_system,      false, 'identification', 10),
    (null, t_brake_lever, d_brake_type,        true,  'identification', 20),
    (null, t_brake_lever, d_brake_position,    true,  'identification', 30),
    (null, t_brake_lever, d_caliper_hydraulic, false, 'specs',          10),
    (null, t_brake_lever, d_reach_adjust,      false, 'features',       10)
  on conflict do nothing;
end $$;


-- ============================================================================
-- S4. SYSTEM SERVICE PROFILES — BRAKE DOMAIN
-- summary templates: {{question_key}} tokens replaced by Flutter at render time.
-- ============================================================================

insert into service_profiles
  (tenant_id, key, name, service_family, description,
   customer_summary_template, mechanic_summary_template, is_active)
values
  (null, 'brake_adjustment',
   'Regulación de Freno', 'brake',
   'Ajuste y regulación de frenos mecánicos o hidráulicos',
   'Regulación de freno {{brake_type}} {{position}}',
   'Freno {{brake_type}} {{position}} — síntoma: {{symptom}}. Revisar centrado cáliper y estado pastillas.',
   true),

  (null, 'hydraulic_brake_bleed',
   'Purgado de Freno Hidráulico', 'brake',
   'Purga completa del sistema hidráulico de freno',
   'Purgado de freno hidráulico {{position}} ({{fluid_type}})',
   'Purgar sistema {{position}} con {{fluid_type}}. Severity: {{symptom_severity}}. Revisar pistones y presencia de aire.',
   true),

  (null, 'brake_service_general',
   'Mantención de Freno', 'brake',
   'Mantención general: revisión, limpieza y ajuste',
   'Mantención general de freno {{position}}',
   'Mantención freno {{position}} — Revisar pastillas, rotor, cable/manguera y cáliper.',
   true),

  (null, 'caliper_service',
   'Servicio de Caliper', 'brake',
   'Desmontaje, limpieza y ajuste del cáliper',
   'Servicio de cáliper {{position}}',
   'Servicio cáliper {{position}} — limpiar pistones, revisar sellos.',
   true),

  (null, 'piston_clean_and_reset',
   'Limpieza y Elongación de Pistones', 'brake',
   'Reset de pistones de cáliper hidráulico',
   'Limpieza y elongación de pistones {{position}}',
   'Elongar y limpiar pistones {{position}}. Identificar pistón pegado o contaminado.',
   true),

  (null, 'rotor_truing',
   'Centrado de Rotor', 'brake',
   'Centrado o enderezado de rotor de freno',
   'Centrado de rotor {{position}}',
   'Centrar rotor {{position}} — medir desvío lateral, ajustar con llave de rotor.',
   true),

  (null, 'brake_cable_replace_adjust',
   'Reemplazo Fundas/Piolas + Regulación', 'brake',
   'Cambio de cable y funda de freno más regulación',
   'Reemplazo cable y funda de freno {{position}}',
   'Reemplazar cable/funda freno {{position}}, regular ajuste final.',
   true)

on conflict do nothing;


-- ============================================================================
-- S5. SERVICE PROFILE TARGETS — BRAKE DOMAIN
-- ============================================================================

do $$
declare
  p_brake_adj       uuid;
  p_bleed           uuid;
  p_service_gen     uuid;
  p_caliper_svc     uuid;
  p_piston_clean    uuid;
  p_rotor_tru       uuid;
  p_cable_replace   uuid;
begin
  select id into p_brake_adj     from service_profiles where key = 'brake_adjustment'         and tenant_id is null;
  select id into p_bleed         from service_profiles where key = 'hydraulic_brake_bleed'    and tenant_id is null;
  select id into p_service_gen   from service_profiles where key = 'brake_service_general'    and tenant_id is null;
  select id into p_caliper_svc   from service_profiles where key = 'caliper_service'          and tenant_id is null;
  select id into p_piston_clean  from service_profiles where key = 'piston_clean_and_reset'   and tenant_id is null;
  select id into p_rotor_tru     from service_profiles where key = 'rotor_truing'             and tenant_id is null;
  select id into p_cable_replace from service_profiles where key = 'brake_cable_replace_adjust' and tenant_id is null;

  insert into service_profile_targets
    (tenant_id, service_profile_id, target_family, target_position_mode)
  values
    (null, p_brake_adj,     'brake', 'front_rear'),
    (null, p_bleed,         'brake', 'front_rear'),
    (null, p_service_gen,   'brake', 'front_rear'),
    (null, p_caliper_svc,   'brake', 'front_rear'),
    (null, p_piston_clean,  'brake', 'front_rear'),
    (null, p_rotor_tru,     'brake', 'front_rear'),
    (null, p_cable_replace, 'brake', 'front_rear')
  on conflict do nothing;
end $$;


-- ============================================================================
-- S6. SERVICE PROFILE QUESTIONS — BRAKE DOMAIN
-- ============================================================================

do $$
declare
  p_brake_adj    uuid;
  p_bleed        uuid;
  p_service_gen  uuid;
  p_caliper_svc  uuid;
  p_piston_clean uuid;
  p_rotor_tru    uuid;
  p_cable_repl   uuid;
begin
  select id into p_brake_adj    from service_profiles where key = 'brake_adjustment'          and tenant_id is null;
  select id into p_bleed        from service_profiles where key = 'hydraulic_brake_bleed'     and tenant_id is null;
  select id into p_service_gen  from service_profiles where key = 'brake_service_general'     and tenant_id is null;
  select id into p_caliper_svc  from service_profiles where key = 'caliper_service'           and tenant_id is null;
  select id into p_piston_clean from service_profiles where key = 'piston_clean_and_reset'    and tenant_id is null;
  select id into p_rotor_tru    from service_profiles where key = 'rotor_truing'              and tenant_id is null;
  select id into p_cable_repl   from service_profiles where key = 'brake_cable_replace_adjust' and tenant_id is null;

  -- brake_adjustment (3 primary + 3 advanced)
  insert into service_profile_questions
    (tenant_id, service_profile_id, key, label, question_type, is_required, is_advanced, sort_order, options_json)
  values
    (null, p_brake_adj, 'brake_type', 'Tipo de freno', 'single_select', true, false, 10,
     '[{"value":"hidraulico","label":"Hidráulico"},{"value":"mecanico","label":"Mecánico"}]'),
    (null, p_brake_adj, 'position', 'Posición', 'single_select', true, false, 20,
     '[{"value":"delantero","label":"Delantero"},{"value":"trasero","label":"Trasero"},{"value":"ambos","label":"Ambos"}]'),
    (null, p_brake_adj, 'symptom', 'Síntoma principal', 'multi_select', true, false, 30,
     '[{"value":"roza","label":"Roza / frota"},{"value":"frena_poco","label":"Frena poco"},{"value":"maneta_blanda","label":"Maneta esponjosa"},{"value":"desalineado","label":"Desalineado"},{"value":"suena","label":"Hace ruido"}]'),
    (null, p_brake_adj, 'pad_condition', 'Condición de pastillas', 'single_select', false, true, 40,
     '[{"value":"bien","label":"Bien"},{"value":"desgastadas","label":"Desgastadas"},{"value":"contaminadas","label":"Contaminadas"}]'),
    (null, p_brake_adj, 'rotor_condition', 'Condición del rotor', 'single_select', false, true, 50,
     '[{"value":"bien","label":"Bien"},{"value":"torcido","label":"Torcido"},{"value":"contaminado","label":"Contaminado"},{"value":"desgastado","label":"Muy desgastado"}]'),
    (null, p_brake_adj, 'replace_parts', 'Incluir cambio de piezas', 'boolean', false, true, 60, '[]')
  on conflict do nothing;

  -- hydraulic_brake_bleed (3 primary + 2 advanced)
  insert into service_profile_questions
    (tenant_id, service_profile_id, key, label, question_type, is_required, is_advanced, sort_order, options_json)
  values
    (null, p_bleed, 'position', 'Posición del freno', 'single_select', true, false, 10,
     '[{"value":"delantero","label":"Delantero"},{"value":"trasero","label":"Trasero"},{"value":"ambos","label":"Ambos"}]'),
    (null, p_bleed, 'fluid_type', 'Tipo de fluido', 'single_select', true, false, 20,
     '[{"value":"mineral","label":"Aceite Mineral (Shimano / Magura / Tektro)"},{"value":"dot","label":"DOT 4 / 5.1 (SRAM / Hayes / Hope)"}]'),
    (null, p_bleed, 'symptom_severity', 'Severidad del problema', 'single_select', false, false, 30,
     '[{"value":"leve","label":"Leve (poca firmeza)"},{"value":"moderado","label":"Moderado (burbujas visibles)"},{"value":"severo","label":"Severo (maneta al fondo / fluido perdido)"}]'),
    (null, p_bleed, 'hose_condition', 'Condición de manguera', 'single_select', false, true, 40,
     '[{"value":"bien","label":"Bien"},{"value":"danada","label":"Dañada / doblada"},{"value":"reemplazar","label":"Requiere reemplazo"}]'),
    (null, p_bleed, 'pad_contaminated', '¿Pastillas contaminadas con fluido?', 'boolean', false, true, 50, '[]')
  on conflict do nothing;

  -- brake_service_general (3 primary)
  insert into service_profile_questions
    (tenant_id, service_profile_id, key, label, question_type, is_required, is_advanced, sort_order, options_json)
  values
    (null, p_service_gen, 'position', 'Posición', 'single_select', true, false, 10,
     '[{"value":"delantero","label":"Delantero"},{"value":"trasero","label":"Trasero"},{"value":"ambos","label":"Ambos"}]'),
    (null, p_service_gen, 'brake_type', 'Tipo de freno', 'single_select', true, false, 20,
     '[{"value":"hidraulico","label":"Hidráulico"},{"value":"mecanico","label":"Mecánico"},{"value":"v-brake","label":"V-Brake"}]'),
    (null, p_service_gen, 'include_pads', '¿Incluir cambio de pastillas?', 'boolean', false, false, 30, '[]')
  on conflict do nothing;

  -- caliper_service (4 primary)
  insert into service_profile_questions
    (tenant_id, service_profile_id, key, label, question_type, is_required, is_advanced, sort_order, options_json)
  values
    (null, p_caliper_svc, 'position', 'Posición', 'single_select', true, false, 10,
     '[{"value":"delantero","label":"Delantero"},{"value":"trasero","label":"Trasero"}]'),
    (null, p_caliper_svc, 'brake_system', 'Sistema de freno', 'single_select', false, false, 20,
     '[{"value":"shimano","label":"Shimano"},{"value":"sram","label":"SRAM"},{"value":"magura","label":"Magura"},{"value":"tektro","label":"Tektro"},{"value":"otro","label":"Otro"}]'),
    (null, p_caliper_svc, 'piston_stuck', '¿Pistón pegado o atascado?', 'boolean', false, false, 30, '[]'),
    (null, p_caliper_svc, 'seal_leak', '¿Pérdida de fluido visible?', 'boolean', false, false, 40, '[]')
  on conflict do nothing;

  -- piston_clean_and_reset (3 primary)
  insert into service_profile_questions
    (tenant_id, service_profile_id, key, label, question_type, is_required, is_advanced, sort_order, options_json)
  values
    (null, p_piston_clean, 'position', 'Posición', 'single_select', true, false, 10,
     '[{"value":"delantero","label":"Delantero"},{"value":"trasero","label":"Trasero"}]'),
    (null, p_piston_clean, 'fluid_type', 'Tipo de fluido', 'single_select', true, false, 20,
     '[{"value":"mineral","label":"Aceite Mineral"},{"value":"dot","label":"DOT"}]'),
    (null, p_piston_clean, 'num_pistons', 'Número de pistones', 'single_select', false, false, 30,
     '[{"value":"2","label":"2 pistones"},{"value":"4","label":"4 pistones"}]')
  on conflict do nothing;

  -- rotor_truing (3 primary)
  insert into service_profile_questions
    (tenant_id, service_profile_id, key, label, question_type, is_required, is_advanced, sort_order, options_json)
  values
    (null, p_rotor_tru, 'position', 'Posición', 'single_select', true, false, 10,
     '[{"value":"delantero","label":"Delantero"},{"value":"trasero","label":"Trasero"}]'),
    (null, p_rotor_tru, 'rotor_diameter', 'Diámetro del rotor', 'single_select', false, false, 20,
     '[{"value":"140","label":"140 mm"},{"value":"160","label":"160 mm"},{"value":"180","label":"180 mm"},{"value":"203","label":"203 mm"}]'),
    (null, p_rotor_tru, 'deviation_severity', 'Severidad del desvío', 'single_select', false, false, 30,
     '[{"value":"leve","label":"Leve (< 1 mm)"},{"value":"moderado","label":"Moderado (1–3 mm)"},{"value":"severo","label":"Severo (> 3 mm, visible a ojo)"}]')
  on conflict do nothing;

  -- brake_cable_replace_adjust (3 primary)
  insert into service_profile_questions
    (tenant_id, service_profile_id, key, label, question_type, is_required, is_advanced, sort_order, options_json)
  values
    (null, p_cable_repl, 'position', 'Posición', 'single_select', true, false, 10,
     '[{"value":"delantero","label":"Delantero"},{"value":"trasero","label":"Trasero"},{"value":"ambos","label":"Ambos"}]'),
    (null, p_cable_repl, 'include_housing', '¿Incluir reemplazo de funda?', 'boolean', true, false, 20, '[]'),
    (null, p_cable_repl, 'brake_type_mech', 'Tipo de freno mecánico', 'single_select', false, false, 30,
     '[{"value":"v-brake","label":"V-Brake"},{"value":"disco_mec","label":"Disco Mecánico"},{"value":"cantilever","label":"Cantilever"}]')
  on conflict do nothing;
end $$;


-- ============================================================================
-- S7. SERVICE PROFILE PART RULES — BRAKE DOMAIN
-- suggested_category_ids left as [] at system level.
-- Tenants can add tenant-scoped rows pointing to their real category UUIDs.
-- Flutter falls back to showing all brake categories when [] is empty.
-- ============================================================================

do $$
declare
  p_brake_adj    uuid;
  p_bleed        uuid;
  p_service_gen  uuid;
  p_cable_repl   uuid;
begin
  select id into p_brake_adj   from service_profiles where key = 'brake_adjustment'          and tenant_id is null;
  select id into p_bleed       from service_profiles where key = 'hydraulic_brake_bleed'     and tenant_id is null;
  select id into p_service_gen from service_profiles where key = 'brake_service_general'     and tenant_id is null;
  select id into p_cable_repl  from service_profiles where key = 'brake_cable_replace_adjust' and tenant_id is null;

  -- brake_adjustment
  insert into service_profile_part_rules
    (tenant_id, service_profile_id, rule_name, conditions_json, suggested_category_ids, default_quantity, is_required, sort_order)
  values
    (null, p_brake_adj, 'Pastillas (si hay cambio de piezas)',
     '[{"question_key":"replace_parts","operator":"eq","value":true}]',
     '[]', 1, false, 10),
    (null, p_brake_adj, 'Aceite mineral (si hidráulico y cambio de piezas)',
     '[{"question_key":"brake_type","operator":"eq","value":"hidraulico"},{"question_key":"replace_parts","operator":"eq","value":true}]',
     '[]', 1, false, 20)
  on conflict do nothing;

  -- hydraulic_brake_bleed
  insert into service_profile_part_rules
    (tenant_id, service_profile_id, rule_name, conditions_json, suggested_category_ids, default_quantity, is_required, sort_order)
  values
    (null, p_bleed, 'Aceite mineral (sistema mineral)',
     '[{"question_key":"fluid_type","operator":"eq","value":"mineral"}]',
     '[]', 1, true, 10),
    (null, p_bleed, 'Fluido DOT (sistema DOT)',
     '[{"question_key":"fluid_type","operator":"eq","value":"dot"}]',
     '[]', 1, true, 20),
    (null, p_bleed, 'Pastillas (si contaminadas)',
     '[{"question_key":"pad_contaminated","operator":"eq","value":true}]',
     '[]', 1, false, 30)
  on conflict do nothing;

  -- brake_service_general
  insert into service_profile_part_rules
    (tenant_id, service_profile_id, rule_name, conditions_json, suggested_category_ids, default_quantity, is_required, sort_order)
  values
    (null, p_service_gen, 'Pastillas (si incluido el cambio)',
     '[{"question_key":"include_pads","operator":"eq","value":true}]',
     '[]', 1, false, 10)
  on conflict do nothing;

  -- brake_cable_replace_adjust
  insert into service_profile_part_rules
    (tenant_id, service_profile_id, rule_name, conditions_json, suggested_category_ids, default_quantity, is_required, sort_order)
  values
    (null, p_cable_repl, 'Piola de freno', '[]', '[]', 1, true, 10),
    (null, p_cable_repl, 'Funda de freno (si se reemplaza)',
     '[{"question_key":"include_housing","operator":"eq","value":true}]',
     '[]', 1, false, 20)
  on conflict do nothing;
end $$;


-- ============================================================================
-- S8. SERVICE PROFILE TASK TEMPLATES — BRAKE DOMAIN
-- ============================================================================

do $$
declare
  p_brake_adj    uuid;
  p_bleed        uuid;
  p_service_gen  uuid;
  p_caliper_svc  uuid;
  p_piston_clean uuid;
  p_rotor_tru    uuid;
  p_cable_repl   uuid;
begin
  select id into p_brake_adj    from service_profiles where key = 'brake_adjustment'          and tenant_id is null;
  select id into p_bleed        from service_profiles where key = 'hydraulic_brake_bleed'     and tenant_id is null;
  select id into p_service_gen  from service_profiles where key = 'brake_service_general'     and tenant_id is null;
  select id into p_caliper_svc  from service_profiles where key = 'caliper_service'           and tenant_id is null;
  select id into p_piston_clean from service_profiles where key = 'piston_clean_and_reset'    and tenant_id is null;
  select id into p_rotor_tru    from service_profiles where key = 'rotor_truing'              and tenant_id is null;
  select id into p_cable_repl   from service_profiles where key = 'brake_cable_replace_adjust' and tenant_id is null;

  -- brake_adjustment tasks
  insert into service_profile_task_templates
    (tenant_id, service_profile_id, task_name, task_description, sort_order, conditions_json)
  values
    (null, p_brake_adj, 'Revisar centrado del cáliper',
     'Aflojar tornillos, centrar cáliper sobre el rotor y volver a apretar',              10, '[]'),
    (null, p_brake_adj, 'Ajustar alcance de maneta',
     'Regular la distancia de la maneta al manillar',                                     20, '[]'),
    (null, p_brake_adj, 'Revisar estado de pastillas',
     'Verificar desgaste y presencia de contaminación',                                   30, '[]'),
    (null, p_brake_adj, 'Lubricar pivot y reguladores (mecánico)',
     'Lubricar partes móviles del freno mecánico',
     40, '[{"question_key":"brake_type","operator":"eq","value":"mecanico"}]'),
    (null, p_brake_adj, 'Revisar estado del rotor',
     'Verificar desvío lateral, desgaste y contaminación de la pista de freno',           50, '[]'),
    (null, p_brake_adj, 'Cambiar pastillas (si desgastadas / contaminadas)',
     'Instalar pastillas nuevas del código correcto',
     60, '[{"question_key":"pad_condition","operator":"in","value":["desgastadas","contaminadas"]}]')
  on conflict do nothing;

  -- hydraulic_brake_bleed tasks
  insert into service_profile_task_templates
    (tenant_id, service_profile_id, task_name, task_description, sort_order, conditions_json)
  values
    (null, p_bleed, 'Preparar equipo de purga',
     'Ensamblar jeringa, manguera y fluido correcto según sistema',                       10, '[]'),
    (null, p_bleed, 'Purgar sistema hidráulico',
     'Eliminar todo el aire desde reservorio hasta cáliper',                              20, '[]'),
    (null, p_bleed, 'Revisar y elongar pistones',
     'Elongar pistones con palanca de freno y verificar desplazamiento parejo',           30, '[]'),
    (null, p_bleed, 'Verificar nivel en reservorio',
     'Ajustar nivel de fluido en reservorio o depósito',                                  40, '[]'),
    (null, p_bleed, 'Instalar pastillas nuevas (si contaminadas)',
     'Reemplazar si hay contaminación con fluido',
     50, '[{"question_key":"pad_contaminated","operator":"eq","value":true}]'),
    (null, p_bleed, 'Revisar manguera',
     'Verificar daño, dobleces agudos o necesidad de corte',                              60, '[]')
  on conflict do nothing;

  -- brake_service_general tasks
  insert into service_profile_task_templates
    (tenant_id, service_profile_id, task_name, task_description, sort_order, conditions_json)
  values
    (null, p_service_gen, 'Revisar y ajustar freno',
     'Inspección completa y ajuste de tensión o presión',                                 10, '[]'),
    (null, p_service_gen, 'Limpiar cáliper y pista de rotor',
     'Aplicar desengrasante en pista de freno y pistones',                                20, '[]'),
    (null, p_service_gen, 'Revisar pastillas',
     'Inspeccionar desgaste y compuesto',                                                 30, '[]'),
    (null, p_service_gen, 'Centrar freno en rotor',
     'Centrar cáliper y verificar roce cero',                                             40, '[]'),
    (null, p_service_gen, 'Cambiar pastillas (si incluido)',
     'Instalar pastillas si desgastadas o si se incluyó cambio',
     50, '[{"question_key":"include_pads","operator":"eq","value":true}]')
  on conflict do nothing;

  -- caliper_service tasks
  insert into service_profile_task_templates
    (tenant_id, service_profile_id, task_name, task_description, sort_order, conditions_json)
  values
    (null, p_caliper_svc, 'Desmontar cáliper',
     'Retirar del adaptador y desconectar manguera si es necesario',                      10, '[]'),
    (null, p_caliper_svc, 'Limpiar cuerpo del cáliper',
     'Limpiar exterior e interior con desengrasante',                                     20, '[]'),
    (null, p_caliper_svc, 'Elongar y limpiar pistones',
     'Empujar pistones y limpiar pista de sellos',                                        30, '[]'),
    (null, p_caliper_svc, 'Revisar sellos',
     'Verificar integridad, reemplazar si hay pérdida de fluido',                         40, '[]'),
    (null, p_caliper_svc, 'Reinstalar y centrar',
     'Montar, purgar si fue abierto y centrar sobre rotor',                               50, '[]')
  on conflict do nothing;

  -- piston_clean_and_reset tasks
  insert into service_profile_task_templates
    (tenant_id, service_profile_id, task_name, task_description, sort_order, conditions_json)
  values
    (null, p_piston_clean, 'Elongar pistones con palanca de freno',
     'Presionar maneta suavemente con pastillas retiradas para exponer pistones',         10, '[]'),
    (null, p_piston_clean, 'Limpiar pista de pistones',
     'Usar alcohol isopropílico en los pistones y ranuras de sellos',                     20, '[]'),
    (null, p_piston_clean, 'Verificar desplazamiento parejo',
     'Ambos pistones deben avanzar y retroceder uniformemente',                           30, '[]'),
    (null, p_piston_clean, 'Retractar, re-espaciar y ajustar',
     'Retractar pistones, instalar pastillas y ajustar distancia al rotor',               40, '[]')
  on conflict do nothing;

  -- rotor_truing tasks
  insert into service_profile_task_templates
    (tenant_id, service_profile_id, task_name, task_description, sort_order, conditions_json)
  values
    (null, p_rotor_tru, 'Medir desvío lateral',
     'Girar rueda lentamente y localizar el punto de máximo desvío',                      10, '[]'),
    (null, p_rotor_tru, 'Ajustar con llave de rotor',
     'Doblar con precisión en punto opuesto al desvío, verificar con galga',              20, '[]'),
    (null, p_rotor_tru, 'Verificar centrado con cáliper',
     'Confirmar que el rotor centra correctamente en el cáliper sin roce',                30, '[]'),
    (null, p_rotor_tru, 'Recomendar reemplazo (desvío severo)',
     'Si desvío > 3 mm o rotor doblado en V, recomendar reemplazo',
     40, '[{"question_key":"deviation_severity","operator":"eq","value":"severo"}]')
  on conflict do nothing;

  -- brake_cable_replace_adjust tasks
  insert into service_profile_task_templates
    (tenant_id, service_profile_id, task_name, task_description, sort_order, conditions_json)
  values
    (null, p_cable_repl, 'Retirar cable y funda anterior',
     'Cortar, retirar y desechar cable y funda vieja',                                    10, '[]'),
    (null, p_cable_repl, 'Instalar funda nueva',
     'Cortar a medida, instalar tapas y férulas en extremos',
     20, '[{"question_key":"include_housing","operator":"eq","value":true}]'),
    (null, p_cable_repl, 'Pasar piola nueva',
     'Insertar por maneta, guiar por funda hasta el freno',                               30, '[]'),
    (null, p_cable_repl, 'Regular tensión y alcance',
     'Ajustar tensor, verificar agarre firme y alcance correcto de maneta',               40, '[]'),
    (null, p_cable_repl, 'Verificar funcionamiento completo',
     'Probar frenada con fuerza, verificar retorno y roce cero',                          50, '[]')
  on conflict do nothing;
end $$;


-- ============================================================================
-- T1. VINABIKE CATEGORY-TO-TEMPLATE MAPPINGS
-- Tenant: 5443b130-cc28-45af-a420-cd500b288890
-- Uses full_path lookup — no hardcoded category UUIDs.
-- ============================================================================

do $$
declare
  v_tenant           uuid := '5443b130-cc28-45af-a420-cd500b288890';
  t_brake_pad        uuid;
  t_rotor            uuid;
  t_brake_caliper    uuid;
  t_hydraulic_brake  uuid;
  t_mechanical_brake uuid;
  t_rim_brake        uuid;
  t_brake_lever      uuid;
begin
  select id into t_brake_pad        from spec_templates where key = 'brake_pad'            and tenant_id is null;
  select id into t_rotor            from spec_templates where key = 'rotor'                and tenant_id is null;
  select id into t_brake_caliper    from spec_templates where key = 'brake_caliper'        and tenant_id is null;
  select id into t_hydraulic_brake  from spec_templates where key = 'hydraulic_disc_brake' and tenant_id is null;
  select id into t_mechanical_brake from spec_templates where key = 'mechanical_disc_brake' and tenant_id is null;
  select id into t_rim_brake        from spec_templates where key = 'rim_brake'            and tenant_id is null;
  select id into t_brake_lever      from spec_templates where key = 'brake_lever'          and tenant_id is null;

  -- Pastillas
  insert into category_tech_mappings
    (tenant_id, category_id, technical_family, template_id, status)
  select v_tenant, pc.id, 'brake_pad', t_brake_pad, 'active'
  from product_categories pc
  where pc.tenant_id = v_tenant and pc.full_path = 'Componentes / Frenos / Pastillas'
  on conflict (tenant_id, category_id) do update
    set technical_family = excluded.technical_family,
        template_id = excluded.template_id,
        status = excluded.status;

  -- Rotores (including BMX gyro rotor)
  insert into category_tech_mappings
    (tenant_id, category_id, technical_family, template_id, status)
  select v_tenant, pc.id, 'rotor', t_rotor, 'active'
  from product_categories pc
  where pc.tenant_id = v_tenant
    and pc.full_path in ('Componentes / Frenos / Rotores', 'Componentes / Frenos / Rotor BMX')
  on conflict (tenant_id, category_id) do update
    set technical_family = excluded.technical_family,
        template_id = excluded.template_id,
        status = excluded.status;

  -- Calipers
  insert into category_tech_mappings
    (tenant_id, category_id, technical_family, template_id, status)
  select v_tenant, pc.id, 'brake_caliper', t_brake_caliper, 'active'
  from product_categories pc
  where pc.tenant_id = v_tenant and pc.full_path = 'Componentes / Frenos / Calipers'
  on conflict (tenant_id, category_id) do update
    set technical_family = excluded.technical_family,
        template_id = excluded.template_id,
        status = excluded.status;

  -- Frenos hidráulicos completos
  insert into category_tech_mappings
    (tenant_id, category_id, technical_family, template_id, status)
  select v_tenant, pc.id, 'complete_brake', t_hydraulic_brake, 'active'
  from product_categories pc
  where pc.tenant_id = v_tenant
    and pc.full_path = 'Componentes / Frenos / Frenos Hidráulicos / Frenos hidráulicos completos'
  on conflict (tenant_id, category_id) do update
    set technical_family = excluded.technical_family,
        template_id = excluded.template_id,
        status = excluded.status;

  -- V-Brake (arm-level and parent category)
  insert into category_tech_mappings
    (tenant_id, category_id, technical_family, template_id, status)
  select v_tenant, pc.id, 'rim_brake', t_rim_brake, 'active'
  from product_categories pc
  where pc.tenant_id = v_tenant
    and pc.full_path in (
      'Componentes / Frenos / V-Brake',
      'Componentes / Frenos / V-Brake / Herraduras'
    )
  on conflict (tenant_id, category_id) do update
    set technical_family = excluded.technical_family,
        template_id = excluded.template_id,
        status = excluded.status;

  -- Manillas
  insert into category_tech_mappings
    (tenant_id, category_id, technical_family, template_id, status)
  select v_tenant, pc.id, 'brake_lever', t_brake_lever, 'active'
  from product_categories pc
  where pc.tenant_id = v_tenant and pc.full_path = 'Componentes / Frenos / Manillas'
  on conflict (tenant_id, category_id) do update
    set technical_family = excluded.technical_family,
        template_id = excluded.template_id,
        status = excluded.status;
end $$;


-- ============================================================================
-- T2. VINABIKE SERVICE PRODUCT → PROFILE MAPPINGS
-- Uses ilike pattern matching on service product names.
-- _ wildcard in ilike matches any single character (handles accent chars like ó, é).
-- ============================================================================

do $$
declare
  v_tenant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  p_id     uuid;
begin
  -- brake_adjustment ← Regulación de frenos
  select id into p_id from service_profiles where key = 'brake_adjustment' and tenant_id is null;
  insert into service_product_profile_mappings
    (tenant_id, product_id, service_profile_id, status)
  select v_tenant, p.id, p_id, 'active'
  from products p
  where p.tenant_id = v_tenant
    and p.product_type = 'service'
    and p.name ilike '%Regulaci_n de frenos%'
  on conflict (tenant_id, product_id) do nothing;

  -- hydraulic_brake_bleed ← Purgado / Sangrado de Freno Hidráulico
  select id into p_id from service_profiles where key = 'hydraulic_brake_bleed' and tenant_id is null;
  insert into service_product_profile_mappings
    (tenant_id, product_id, service_profile_id, status)
  select v_tenant, p.id, p_id, 'active'
  from products p
  where p.tenant_id = v_tenant
    and p.product_type = 'service'
    and (p.name ilike '%Purgado%Freno%' or p.name ilike '%Sangrado%Freno%')
  on conflict (tenant_id, product_id) do nothing;

  -- brake_service_general ← Mantención de Freno
  select id into p_id from service_profiles where key = 'brake_service_general' and tenant_id is null;
  insert into service_product_profile_mappings
    (tenant_id, product_id, service_profile_id, status)
  select v_tenant, p.id, p_id, 'active'
  from products p
  where p.tenant_id = v_tenant
    and p.product_type = 'service'
    and p.name ilike '%Mantenci_n%Freno%'
  on conflict (tenant_id, product_id) do nothing;

  -- caliper_service ← Mantención Caliper
  select id into p_id from service_profiles where key = 'caliper_service' and tenant_id is null;
  insert into service_product_profile_mappings
    (tenant_id, product_id, service_profile_id, status)
  select v_tenant, p.id, p_id, 'active'
  from products p
  where p.tenant_id = v_tenant
    and p.product_type = 'service'
    and p.name ilike '%Caliper%'
  on conflict (tenant_id, product_id) do nothing;

  -- piston_clean_and_reset ← Limpieza y Elongación de Pistones
  select id into p_id from service_profiles where key = 'piston_clean_and_reset' and tenant_id is null;
  insert into service_product_profile_mappings
    (tenant_id, product_id, service_profile_id, status)
  select v_tenant, p.id, p_id, 'active'
  from products p
  where p.tenant_id = v_tenant
    and p.product_type = 'service'
    and p.name ilike '%Pist_n%'
  on conflict (tenant_id, product_id) do nothing;

  -- rotor_truing ← Centrado Rotor de Freno
  select id into p_id from service_profiles where key = 'rotor_truing' and tenant_id is null;
  insert into service_product_profile_mappings
    (tenant_id, product_id, service_profile_id, status)
  select v_tenant, p.id, p_id, 'active'
  from products p
  where p.tenant_id = v_tenant
    and p.product_type = 'service'
    and p.name ilike '%Centrado%Rotor%'
  on conflict (tenant_id, product_id) do nothing;

  -- brake_cable_replace_adjust ← Reemplazo de fundas y piolas + Regulación de frenos
  select id into p_id from service_profiles where key = 'brake_cable_replace_adjust' and tenant_id is null;
  insert into service_product_profile_mappings
    (tenant_id, product_id, service_profile_id, status)
  select v_tenant, p.id, p_id, 'active'
  from products p
  where p.tenant_id = v_tenant
    and p.product_type = 'service'
    and p.name ilike '%fundas%piolas%frenos%'
  on conflict (tenant_id, product_id) do nothing;
end $$;
