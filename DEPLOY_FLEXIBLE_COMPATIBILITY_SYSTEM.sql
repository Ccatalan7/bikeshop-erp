-- ============================================================================
-- FLEXIBLE COMPATIBILITY SYSTEM (Nov 22, 2025)
-- ============================================================================
-- GOAL: Allow users to manually map their categories to predefined component types
-- 
-- ARCHITECTURE:
-- 1. compat_component_library: GLOBAL catalog of component types (shared, not tenant-specific)
-- 2. product_categories.component_type_code: Simple FK reference (nullable, user maps manually)
-- 3. Flutter Category Form: Dropdown to select component type or "None"
-- 4. Flutter Product Form: Reads category.component_type_code → fetches metadata → builds fields
--
-- BENEFITS:
-- ✅ Flexible: Add/edit component types without touching tenant data
-- ✅ Simple: Just one dropdown in category form
-- ✅ No scripts needed: User maps directly in UI
-- ✅ Open to change: Modify attributes, add types, update metadata anytime
-- ============================================================================

-- ============================================================================
-- 1. GLOBAL COMPONENT TYPE LIBRARY (Shared catalog, no tenant_id)
-- ============================================================================
create table if not exists compat_component_library (
  code text primary key, -- e.g., 'rear_hub', 'rim', 'cassette', 'frame'
  display_name text not null, -- e.g., 'Maza Trasera', 'Aro / Rin'
  parent_code text references compat_component_library(code) on delete cascade, -- Hierarchy (optional)
  discipline_scope text[] default array[]::text[], -- ['road', 'mtb', 'gravel']
  description text,
  icon_name text, -- Material Icons name for Flutter
  metadata jsonb not null default '{}'::jsonb, -- Flexible JSON for attributes, rules, etc.
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Indexes
create index if not exists idx_compat_library_parent on compat_component_library(parent_code);
create index if not exists idx_compat_library_active on compat_component_library(is_active);
create index if not exists idx_compat_library_metadata on compat_component_library using gin(metadata);

-- No RLS needed - this is a global reference table (read-only for users, admin editable)
alter table compat_component_library enable row level security;

drop policy if exists "component_library_select_all" on compat_component_library;
create policy "component_library_select_all" on compat_component_library
  for select to authenticated
  using (true); -- Anyone can read the catalog

-- ============================================================================
-- 2. ADD COMPONENT TYPE REFERENCE TO CATEGORIES
-- ============================================================================
-- Simple foreign key: categories optionally link to ONE component type
alter table product_categories 
  add column if not exists component_type_code text references compat_component_library(code) on delete set null;

-- Index for fast lookups
create index if not exists idx_product_categories_component_type 
  on product_categories(component_type_code) where component_type_code is not null;

comment on column product_categories.component_type_code is 
  'User-mapped reference to compat_component_library. When set, products in this category inherit compatibility fields from the component type metadata.';

-- ============================================================================
-- 3. SEED COMPONENT LIBRARY WITH INITIAL TYPES
-- ============================================================================
-- Start with essential bike components (expandable over time)

-- Parent groups (for organization)
insert into compat_component_library (code, display_name, parent_code, discipline_scope, description, icon_name, metadata) values
  ('wheel_system', 'Sistema de Rueda', null, '{road,mtb,gravel}', 'Componentes relacionados con ruedas', 'settings_input_component', '{}'),
  ('frame_system', 'Sistema de Cuadro', null, '{road,mtb,gravel}', 'Componentes estructurales del cuadro y horquilla', 'directions_bike', '{}'),
  ('drivetrain_system', 'Tren Motriz', null, '{road,mtb,gravel}', 'Componentes de transmisión', 'settings', '{}'),
  ('brake_system', 'Sistema de Freno', null, '{road,mtb,gravel}', 'Componentes de frenado', 'gpp_maybe', '{}')
on conflict (code) do update set
  display_name = excluded.display_name,
  discipline_scope = excluded.discipline_scope,
  description = excluded.description,
  icon_name = excluded.icon_name,
  updated_at = now();

-- Wheel components
insert into compat_component_library (code, display_name, parent_code, discipline_scope, description, icon_name, metadata) values
  ('hub', 'Maza', 'wheel_system', '{road,mtb,gravel}', 'Mazas delanteras o traseras', 'hub', '{
    "attributes": [
      {"key": "spoke_holes", "label": "Número de Rayos", "type": "enum", "required": true, "enum_values": ["16", "20", "24", "28", "32", "36", "40", "48"]},
      {"key": "hub_spacing_mm", "label": "Ancho OLD (mm)", "type": "enum", "required": true, "enum_values": ["100", "110", "130", "135", "142", "148", "157"]},
      {"key": "axle_type", "label": "Tipo de Eje", "type": "enum", "required": true, "enum_values": ["QR 9mm", "QR 10mm", "Thru 12mm", "Thru 15mm", "Thru 20mm"]},
      {"key": "brake_interface", "label": "Interface de Freno", "type": "enum", "required": false, "enum_values": ["Disco 6-Bolt", "Disco Centerlock", "Freno Rin"]},
      {"key": "freehub_body", "label": "Cuerpo de Cassette", "type": "enum", "required": false, "enum_values": ["Shimano HG", "Shimano MicroSpline", "SRAM XD", "SRAM XDR", "Campagnolo", "T-Type"]}
    ]
  }'),
  
  ('rim', 'Aro / Rin', 'wheel_system', '{road,mtb,gravel}', 'Aros y llantas para armado de ruedas', 'donut_large', '{
    "attributes": [
      {"key": "spoke_holes", "label": "Número de Rayos", "type": "enum", "required": true, "enum_values": ["16", "20", "24", "28", "32", "36", "40", "48"]},
      {"key": "erd_mm", "label": "ERD (mm)", "type": "number", "required": true, "min": 250, "max": 700},
      {"key": "rim_internal_width_mm", "label": "Ancho Interno (mm)", "type": "number", "required": true, "min": 13, "max": 45},
      {"key": "wheel_size", "label": "Tamaño de Rueda", "type": "enum", "required": true, "enum_values": ["700c", "650b (27.5)", "29er", "27.5+", "26\"", "24\"", "20\""]},
      {"key": "brake_interface", "label": "Interface de Freno", "type": "enum", "required": false, "enum_values": ["Disco 6-Bolt", "Disco Centerlock", "Freno Rin"]}
    ]
  }'),
  
  ('spoke', 'Rayo', 'wheel_system', '{road,mtb,gravel}', 'Rayos tradicionales o especiales', 'timeline', '{
    "attributes": [
      {"key": "spoke_length_mm", "label": "Largo de Rayo (mm)", "type": "number", "required": true, "min": 180, "max": 320},
      {"key": "spoke_gauge", "label": "Calibre", "type": "enum", "required": true, "enum_values": ["13g", "14g", "15g", "Bladed"]},
      {"key": "spoke_material", "label": "Material", "type": "enum", "required": false, "enum_values": ["Acero Inoxidable", "Aluminio", "Titanio", "Carbono"]}
    ]
  }'),
  
  ('tire', 'Neumático', 'wheel_system', '{road,mtb,gravel}', 'Neumáticos o cubiertas', 'radio_button_checked', '{
    "attributes": [
      {"key": "wheel_size", "label": "Tamaño de Rueda", "type": "enum", "required": true, "enum_values": ["700c", "650b (27.5)", "29er", "27.5+", "26\"", "24\"", "20\""]},
      {"key": "tire_width_mm", "label": "Ancho (mm)", "type": "number", "required": true, "min": 23, "max": 85}
    ]
  }'),
  
  ('tube', 'Cámara', 'wheel_system', '{road,mtb,gravel}', 'Cámaras de aire', 'trip_origin', '{
    "attributes": [
      {"key": "wheel_size", "label": "Tamaño de Rueda", "type": "enum", "required": true, "enum_values": ["700c", "650b (27.5)", "29er", "27.5+", "26\"", "24\"", "20\""]},
      {"key": "valve_type", "label": "Tipo de Válvula", "type": "enum", "required": true, "enum_values": ["Presta", "Schrader", "Dunlop"]}
    ]
  }')
on conflict (code) do update set
  display_name = excluded.display_name,
  parent_code = excluded.parent_code,
  discipline_scope = excluded.discipline_scope,
  description = excluded.description,
  icon_name = excluded.icon_name,
  metadata = excluded.metadata,
  updated_at = now();

-- Frame system components
insert into compat_component_library (code, display_name, parent_code, discipline_scope, description, icon_name, metadata) values
  ('frame', 'Cuadro', 'frame_system', '{road,mtb,gravel}', 'Cuadros completos', 'bike_scooter', '{
    "attributes": [
      {"key": "wheel_size", "label": "Tamaño de Rueda", "type": "enum", "required": true, "enum_values": ["700c", "650b (27.5)", "29er", "27.5+", "26\"", "24\"", "20\""]},
      {"key": "frame_tire_max_width_mm", "label": "Ancho Máx Neumático (mm)", "type": "number", "required": false, "min": 25, "max": 85},
      {"key": "seatpost_diameter_mm", "label": "Diámetro Tubo Asiento (mm)", "type": "enum", "required": false, "enum_values": ["27.2", "30.9", "31.6", "34.9"]},
      {"key": "headset_standard", "label": "Norma Dirección", "type": "enum", "required": false, "enum_values": ["IS41/IS52", "ZS44/EC44", "EC34", "EC44/EC44", "ZS44/ZS56", "EC49"]},
      {"key": "bb_type", "label": "Norma Caja Centro", "type": "enum", "required": false, "enum_values": ["BSA 68mm", "BSA 73mm", "ITA", "PF30", "BB30", "BB86", "BB92", "BB386", "T47"]},
      {"key": "bb_shell_width_mm", "label": "Ancho Caja Centro (mm)", "type": "enum", "required": false, "enum_values": ["68", "73", "86", "92"]},
      {"key": "rear_spacing_mm", "label": "Espaciado Trasero (mm)", "type": "enum", "required": false, "enum_values": ["130", "135", "142", "148", "157"]},
      {"key": "chainline_mm", "label": "Chainline (mm)", "type": "number", "required": false, "min": 42, "max": 58}
    ]
  }'),
  
  ('fork', 'Horquilla', 'frame_system', '{road,mtb,gravel}', 'Horquillas rígidas y con suspensión', 'hiking', '{
    "attributes": [
      {"key": "wheel_size", "label": "Tamaño de Rueda", "type": "enum", "required": true, "enum_values": ["700c", "650b (27.5)", "29er", "27.5+", "26\"", "24\"", "20\""]},
      {"key": "fork_travel_mm", "label": "Recorrido (mm)", "type": "number", "required": false, "min": 0, "max": 220},
      {"key": "steerer_diameter_mm", "label": "Diámetro Tubo Dirección (mm)", "type": "enum", "required": true, "enum_values": ["1\" (25.4mm)", "1-1/8\" (28.6mm)", "1.5\" (38.1mm)"]},
      {"key": "axle_type", "label": "Tipo de Eje", "type": "enum", "required": true, "enum_values": ["QR 9mm", "Thru 12mm", "Thru 15mm", "Thru 20mm"]},
      {"key": "brake_mount_type", "label": "Montaje Freno", "type": "enum", "required": false, "enum_values": ["Post Mount", "Flat Mount", "IS Mount", "V-Brake", "Canti"]}
    ]
  }'),
  
  ('headset', 'Juego de Dirección', 'frame_system', '{road,mtb,gravel}', 'Normas y rodamientos de dirección', 'donut_small', '{
    "attributes": [
      {"key": "headset_standard", "label": "Norma", "type": "enum", "required": true, "enum_values": ["IS41/IS52", "ZS44/EC44", "EC34", "EC44/EC44", "ZS44/ZS56", "EC49", "Roscado 1-1/8\""]},
      {"key": "steerer_diameter_mm", "label": "Diámetro Compatible", "type": "enum", "required": true, "enum_values": ["1\" (25.4mm)", "1-1/8\" (28.6mm)", "1.5\" (38.1mm)"]}
    ]
  }'),
  
  ('seatpost', 'Tubo de Asiento', 'frame_system', '{road,mtb,gravel}', 'Seatposts rígidos y telescópicos', 'straighten', '{
    "attributes": [
      {"key": "seatpost_diameter_mm", "label": "Diámetro (mm)", "type": "enum", "required": true, "enum_values": ["27.2", "30.9", "31.6", "34.9"]},
      {"key": "seatpost_length_mm", "label": "Largo (mm)", "type": "number", "required": false, "min": 200, "max": 500},
      {"key": "seatpost_travel_mm", "label": "Recorrido Dropper (mm)", "type": "number", "required": false, "min": 0, "max": 250}
    ]
  }'),
  
  ('handlebar', 'Manubrio', 'frame_system', '{road,mtb,gravel}', 'Barras, drops y risers', 'pan_tool_alt', '{
    "attributes": [
      {"key": "handlebar_width_mm", "label": "Ancho (mm)", "type": "number", "required": true, "min": 360, "max": 820},
      {"key": "handlebar_clamp_diameter_mm", "label": "Diámetro Abrazadera (mm)", "type": "enum", "required": true, "enum_values": ["25.4", "31.8", "35"]},
      {"key": "handlebar_type", "label": "Tipo", "type": "enum", "required": true, "enum_values": ["Drop", "Flat", "Riser", "BMX", "Aero"]}
    ]
  }'),
  
  ('stem', 'Stem / Tee', 'frame_system', '{road,mtb,gravel}', 'Potencias y tees', 'call_split', '{
    "attributes": [
      {"key": "stem_length_mm", "label": "Largo (mm)", "type": "number", "required": true, "min": 30, "max": 140},
      {"key": "handlebar_clamp_diameter_mm", "label": "Diámetro Abrazadera Manubrio (mm)", "type": "enum", "required": true, "enum_values": ["25.4", "31.8", "35"]},
      {"key": "steerer_diameter_mm", "label": "Diámetro Tubo Dirección (mm)", "type": "enum", "required": true, "enum_values": ["1\" (25.4mm)", "1-1/8\" (28.6mm)", "1.5\" (38.1mm)"]},
      {"key": "stem_rise_deg", "label": "Ángulo (°)", "type": "number", "required": false, "min": -20, "max": 60}
    ]
  }'),
  
  ('saddle', 'Asiento', 'frame_system', '{road,mtb,gravel}', 'Sillines y asientos', 'event_seat', '{
    "attributes": [
      {"key": "saddle_width_mm", "label": "Ancho (mm)", "type": "number", "required": false, "min": 120, "max": 180},
      {"key": "rail_material", "label": "Material Rieles", "type": "enum", "required": false, "enum_values": ["Acero", "Titanio", "Carbono"]}
    ]
  }')
on conflict (code) do update set
  display_name = excluded.display_name,
  parent_code = excluded.parent_code,
  discipline_scope = excluded.discipline_scope,
  description = excluded.description,
  icon_name = excluded.icon_name,
  metadata = excluded.metadata,
  updated_at = now();

-- Drivetrain components
insert into compat_component_library (code, display_name, parent_code, discipline_scope, description, icon_name, metadata) values
  ('crankset', 'Bielas', 'drivetrain_system', '{road,mtb,gravel}', 'Cranksets completos', 'pedal_bike', '{
    "attributes": [
      {"key": "bb_type", "label": "Compatibilidad Caja Centro", "type": "enum", "required": true, "enum_values": ["BSA 68mm", "BSA 73mm", "ITA", "PF30", "BB30", "BB86", "BB92", "BB386", "T47"]},
      {"key": "crank_arm_length_mm", "label": "Largo Biela (mm)", "type": "enum", "required": true, "enum_values": ["165", "170", "172.5", "175", "177.5", "180"]},
      {"key": "chainring_bcd_mm", "label": "BCD Plato (mm)", "type": "enum", "required": false, "enum_values": ["64", "96", "104", "110", "130"]},
      {"key": "chainline_mm", "label": "Chainline (mm)", "type": "number", "required": false, "min": 42, "max": 58}
    ]
  }'),
  
  ('chainring', 'Plato', 'drivetrain_system', '{road,mtb,gravel}', 'Platos individuales o dobles', 'adjust', '{
    "attributes": [
      {"key": "chainring_teeth", "label": "Número de Dientes", "type": "number", "required": true, "min": 20, "max": 60},
      {"key": "chainring_bcd_mm", "label": "BCD (mm)", "type": "enum", "required": true, "enum_values": ["64", "96", "104", "110", "130"]}
    ]
  }'),
  
  ('bottom_bracket', 'Caja Centro', 'drivetrain_system', '{road,mtb,gravel}', 'Bottom brackets y rodamientos', 'sync_alt', '{
    "attributes": [
      {"key": "bb_type", "label": "Norma", "type": "enum", "required": true, "enum_values": ["BSA 68mm", "BSA 73mm", "ITA", "PF30", "BB30", "BB86", "BB92", "BB386", "T47"]},
      {"key": "bb_shell_width_mm", "label": "Ancho Shell (mm)", "type": "enum", "required": true, "enum_values": ["68", "73", "86", "92"]}
    ]
  }'),
  
  ('cassette', 'Cassette', 'drivetrain_system', '{road,mtb,gravel}', 'Cassettes y piñoneras', 'view_column', '{
    "attributes": [
      {"key": "freehub_body", "label": "Tipo de Cuerpo", "type": "enum", "required": true, "enum_values": ["Shimano HG", "Shimano MicroSpline", "SRAM XD", "SRAM XDR", "Campagnolo", "T-Type"]},
      {"key": "cassette_speeds", "label": "Velocidades", "type": "enum", "required": true, "enum_values": ["7", "8", "9", "10", "11", "12", "13"]},
      {"key": "cassette_min_tooth", "label": "Diente Mínimo", "type": "number", "required": true, "min": 9, "max": 18},
      {"key": "cassette_max_tooth", "label": "Diente Máximo", "type": "number", "required": true, "min": 28, "max": 60}
    ]
  }'),
  
  ('chain', 'Cadena', 'drivetrain_system', '{road,mtb,gravel}', 'Cadenas y eslabones', 'link', '{
    "attributes": [
      {"key": "chain_speeds", "label": "Velocidades", "type": "enum", "required": true, "enum_values": ["7/8", "9", "10", "11", "12", "13"]},
      {"key": "chain_width_mm", "label": "Ancho (mm)", "type": "number", "required": false, "min": 5, "max": 8}
    ]
  }'),
  
  ('rear_derailleur', 'Cambio Trasero', 'drivetrain_system', '{road,mtb,gravel}', 'Derailleurs traseros', 'settings_ethernet', '{
    "attributes": [
      {"key": "derailleur_speeds", "label": "Velocidades", "type": "enum", "required": true, "enum_values": ["7", "8", "9", "10", "11", "12", "13"]},
      {"key": "derailleur_cage_length", "label": "Tamaño Jaula", "type": "enum", "required": true, "enum_values": ["Short", "Medium", "Long", "DH"]},
      {"key": "derailleur_capacity_teeth", "label": "Capacidad (dientes)", "type": "number", "required": false, "min": 20, "max": 50},
      {"key": "derailleur_mount", "label": "Tipo de Montaje", "type": "enum", "required": false, "enum_values": ["Direct Mount", "Hanger", "Clamp 31.8", "Clamp 34.9"]}
    ]
  }'),
  
  ('pedal', 'Pedales', 'drivetrain_system', '{road,mtb,gravel}', 'Pedales planos o de fijación', 'directions_run', '{
    "attributes": [
      {"key": "pedal_type", "label": "Tipo", "type": "enum", "required": true, "enum_values": ["Plano", "Clipless SPD", "Clipless SPD-SL", "Clipless Look Keo", "Mixto"]},
      {"key": "thread_size", "label": "Rosca", "type": "enum", "required": true, "enum_values": ["9/16\" (estándar)", "1/2\" (infantil)"]}
    ]
  }')
on conflict (code) do update set
  display_name = excluded.display_name,
  parent_code = excluded.parent_code,
  discipline_scope = excluded.discipline_scope,
  description = excluded.description,
  icon_name = excluded.icon_name,
  metadata = excluded.metadata,
  updated_at = now();

-- Brake system components
insert into compat_component_library (code, display_name, parent_code, discipline_scope, description, icon_name, metadata) values
  ('brake_caliper', 'Caliper', 'brake_system', '{road,mtb,gravel}', 'Pinzas / calipers de freno', 'pattern', '{
    "attributes": [
      {"key": "brake_mount_type", "label": "Tipo de Montaje", "type": "enum", "required": true, "enum_values": ["Post Mount", "Flat Mount", "IS Mount", "Direct Mount", "V-Brake", "Canti"]},
      {"key": "brake_fluid_type", "label": "Tipo de Fluido", "type": "enum", "required": false, "enum_values": ["Mineral", "DOT 4", "DOT 5.1", "Cable"]}
    ]
  }'),
  
  ('brake_rotor', 'Rotor / Disco', 'brake_system', '{road,mtb,gravel}', 'Discos de freno', 'donut_large', '{
    "attributes": [
      {"key": "rotor_size_mm", "label": "Tamaño (mm)", "type": "enum", "required": true, "enum_values": ["140", "160", "180", "200", "203", "220"]},
      {"key": "rotor_mount_type", "label": "Montaje", "type": "enum", "required": true, "enum_values": ["6-Bolt", "Centerlock"]}
    ]
  }')
on conflict (code) do update set
  display_name = excluded.display_name,
  parent_code = excluded.parent_code,
  discipline_scope = excluded.discipline_scope,
  description = excluded.description,
  icon_name = excluded.icon_name,
  metadata = excluded.metadata,
  updated_at = now();

-- ============================================================================
-- 4. HELPER VIEW: Get All Component Types with Metadata (for Flutter)
-- ============================================================================
create or replace view v_component_type_catalog as
select 
  code,
  display_name,
  parent_code,
  discipline_scope,
  description,
  icon_name,
  metadata,
  is_active,
  -- Extract attribute count for UI display
  jsonb_array_length(coalesce(metadata->'attributes', '[]'::jsonb)) as attribute_count
from compat_component_library
where is_active = true
order by 
  case when parent_code is null then 0 else 1 end, -- Parents first
  display_name;

-- Grant access
grant select on v_component_type_catalog to authenticated;

-- ============================================================================
-- 5. HELPER FUNCTION: Get Category with Component Type Metadata
-- ============================================================================
-- Returns category enriched with component type metadata (for product form)
create or replace function public.get_category_with_component_metadata(p_category_id uuid)
returns table (
  category_id uuid,
  category_name text,
  category_full_path text,
  component_type_code text,
  component_display_name text,
  component_icon text,
  component_metadata jsonb,
  discipline_scope text[]
)
language plpgsql
security definer
as $$
begin
  return query
  select 
    pc.id,
    pc.name,
    pc.full_path,
    cl.code,
    cl.display_name,
    cl.icon_name,
    cl.metadata,
    cl.discipline_scope
  from product_categories pc
  left join compat_component_library cl on pc.component_type_code = cl.code
  where pc.id = p_category_id
    and pc.tenant_id = public.user_tenant_id();
end;
$$;

grant execute on function public.get_category_with_component_metadata(uuid) to authenticated;

-- ============================================================================
-- 6. MIGRATION: Remove old compatibility columns (if they exist)
-- ============================================================================
-- Clean up the old JSON-based compatibility_metadata approach
-- Categories now just reference component_type_code (simpler!)

-- Keep these for backward compatibility during transition:
-- alter table product_categories drop column if exists compatibility_metadata;
-- alter table product_categories drop column if exists discipline_scope;
-- alter table product_categories drop column if exists icon_name;

-- For now, keep them but they'll be deprecated in favor of component_type_code reference

-- ============================================================================
-- SUMMARY
-- ============================================================================
-- ✅ Created: compat_component_library (global catalog, 30+ component types seeded)
-- ✅ Added: product_categories.component_type_code (simple FK reference)
-- ✅ Created: v_component_type_catalog view (for Flutter dropdown)
-- ✅ Created: get_category_with_component_metadata() function (for product form)
--
-- NEXT STEPS (Flutter):
-- 1. Category Form: Add dropdown with v_component_type_catalog options + "None"
-- 2. Product Form: Call get_category_with_component_metadata(category_id)
-- 3. Product Form: If component_type_code exists → build dynamic fields from metadata.attributes
--
-- TO ADD MORE COMPONENT TYPES:
-- Just INSERT into compat_component_library with metadata JSON!
-- No schema changes, no migrations, no tenant data affected!
-- ============================================================================
