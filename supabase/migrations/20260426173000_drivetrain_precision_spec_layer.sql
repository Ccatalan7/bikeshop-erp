-- ============================================================================
-- DRIVETRAIN PRECISION SPEC LAYER
-- Migration: 20260426173000_drivetrain_precision_spec_layer.sql
--
-- Extends the first drivetrain ficha layer with platform/profile fields that
-- matter for real compatibility decisions. This stays additive and idempotent:
-- no product specs are guessed from names/SKUs, and existing product rows keep
-- working while mechanics fill richer ficha data over time.
-- ============================================================================

insert into spec_definitions (
  tenant_id,
  key,
  label,
  description,
  data_type,
  unit,
  allowed_values,
  validation_rules,
  is_filterable,
  is_required_by_default,
  is_compatibility_relevant,
  is_customer_visible,
  is_mechanic_visible,
  group_name,
  sort_order
)
values
  (null, 'freehub_type', 'Driver / Freehub',
   'Familia de driver trasero: nucleo de cassette, XDR/XD, Micro Spline, rueda libre roscada, driver BMX, fijo o contrapedal.',
   'single_select', null, '["Shimano HG","Shimano HG Road 11","Micro Spline","SRAM XD","SRAM XDR","Campagnolo","Campagnolo N3W","Rueda libre roscada","Driver BMX","Rosca fija / contratuerca","Maza contrapedal","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Compatibilidad', 23),

  (null, 'shift_actuation_family', 'Familia indexado / tiro',
   'Familia de tiro/indexado para shifter y desviadores; no confundir con marca comercial simple.',
   'single_select', null, '["Shimano SIS 6-9v","Shimano Dynasys 10v","Shimano Dynasys 11/12v","Shimano CUES / Linkglide","Shimano ruta","SRAM Exact Actuation","SRAM X-Actuation / Eagle","SRAM AXS road / FlatTop","SRAM T-Type Transmission","Campagnolo","Microshift Advent / Acolyte","Friccion / universal","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Cambios', 71),

  (null, 'drivetrain_platform', 'Plataforma transmision',
   'Ecosistema de compatibilidad declarado por el fabricante cuando afecta cadena, cassette, cambio, shifter o plato.',
   'single_select', null, '["Shimano HG / SIS","Shimano Hyperglide+","Shimano Linkglide / CUES","SRAM Eagle","SRAM FlatTop / AXS road","SRAM T-Type Transmission","Campagnolo","Microshift Advent / Acolyte","Friccion / universal","Single speed / BMX","Generico compatible","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Compatibilidad', 13),

  (null, 'chain_profile_family', 'Perfil cadena',
   'Perfil o familia de cadena compatible: universal, HG+, Linkglide, Eagle, FlatTop, BMX/single speed, etc.',
   'multi_select', null, '["Universal 5-8v","Universal 9-11v","Shimano HG+","Shimano Linkglide / CUES","SRAM Eagle","SRAM FlatTop","SRAM T-Type","Campagnolo","KMC compatible","Single speed / BMX","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Compatibilidad', 14),

  (null, 'chain_directional', 'Cadena direccional',
   'Indica si la cadena tiene sentido de instalacion declarado por fabricante.',
   'boolean', null, '[]'::jsonb, '{}'::jsonb,
   true, false, false, true, true, 'Caracteristicas', 24),

  (null, 'chain_ebike_rated', 'Apta e-bike',
   'Indica si la cadena o kit declara refuerzo para e-bike o alto torque.',
   'boolean', null, '[]'::jsonb, '{}'::jsonb,
   true, false, false, true, true, 'Caracteristicas', 25),

  (null, 'chain_link_reusable', 'Missing link reutilizable',
   'Indica si el conector de cadena declara reutilizacion.',
   'boolean', null, '[]'::jsonb, '{}'::jsonb,
   true, false, false, true, true, 'Contenido', 26),

  (null, 'chain_link_pack_qty', 'Cantidad conectores',
   'Cantidad de conectores incluidos en el pack.',
   'number', 'unidades', '[]'::jsonb, '{"min":1,"max":100}'::jsonb,
   false, false, false, true, true, 'Contenido', 27),

  (null, 'cassette_cog_sequence', 'Secuencia pinones',
   'Secuencia de dientes del cassette o rueda libre, por ejemplo 11-13-15-18-21-24-28-32.',
   'text', 'T', '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Rango', 33),

  (null, 'rear_derailleur_min_teeth', 'Minimo pinon cambio trasero',
   'Piñon menor minimo recomendado por el cambio trasero.',
   'number', 'T', '[]'::jsonb, '{"min":8,"max":24}'::jsonb,
   true, false, true, true, true, 'Rango', 75),

  (null, 'rear_derailleur_total_capacity_teeth', 'Capacidad total cambio trasero',
   'Capacidad total del cambio trasero en dientes.',
   'number', 'T', '[]'::jsonb, '{"min":10,"max":60}'::jsonb,
   true, false, true, true, true, 'Rango', 76),

  (null, 'derailleur_clutch', 'Cambio con clutch',
   'Indica si el cambio trasero tiene embrague/clutch de estabilizacion de cadena.',
   'boolean', null, '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Cambios', 77),

  (null, 'bb_shell_diameter_mm', 'Diametro caja motor',
   'Diametro interno o nominal de la caja de motor cuando el estandar lo requiere.',
   'number', 'mm', '[]'::jsonb, '{"min":30,"max":55}'::jsonb,
   true, false, true, true, true, 'Pedalier', 69),

  (null, 'bb_bearing_width_mm', 'Ancho rodamiento motor',
   'Ancho del rodamiento de motor/pedalier.',
   'number', 'mm', '[]'::jsonb, '{"min":5,"max":20}'::jsonb,
   true, false, true, true, true, 'Rodamientos', 70)
on conflict (key) where tenant_id is null do update
set label = excluded.label,
    description = excluded.description,
    data_type = excluded.data_type,
    unit = excluded.unit,
    allowed_values = excluded.allowed_values,
    validation_rules = excluded.validation_rules,
    is_filterable = excluded.is_filterable,
    is_required_by_default = excluded.is_required_by_default,
    is_compatibility_relevant = excluded.is_compatibility_relevant,
    is_customer_visible = excluded.is_customer_visible,
    is_mechanic_visible = excluded.is_mechanic_visible,
    group_name = excluded.group_name,
    sort_order = excluded.sort_order,
    updated_at = now();

with field_rows(template_key, spec_key, is_required, section_key, sort_order, helper_text) as (
  values
    ('chain', 'chain_profile_family', false, 'compatibility', 30, 'Perfil de compatibilidad declarado por fabricante.'),
    ('chain', 'drivetrain_platform', false, 'compatibility', 40, 'Solo llenar si el fabricante declara una plataforma especifica.'),
    ('chain', 'chain_directional', false, 'features', 10, null),
    ('chain', 'chain_ebike_rated', false, 'features', 20, null),

    ('chain_link', 'chain_profile_family', false, 'compatibility', 30, 'Debe coincidir con cadena y plataforma cuando aplica.'),
    ('chain_link', 'chain_link_reusable', false, 'features', 10, null),
    ('chain_link', 'chain_link_pack_qty', false, 'contents', 20, null),

    ('cassette', 'drivetrain_platform', false, 'compatibility', 30, 'Plataforma declarada si afecta cadena/cambio/shifter.'),
    ('cassette', 'cassette_cog_sequence', false, 'range', 30, null),

    ('freewheel', 'drivetrain_platform', false, 'compatibility', 30, null),
    ('freewheel', 'cassette_cog_sequence', false, 'range', 30, null),

    ('fixed_cog', 'drivetrain_platform', false, 'compatibility', 30, null),

    ('rear_derailleur', 'drivetrain_platform', false, 'compatibility', 30, null),
    ('rear_derailleur', 'rear_derailleur_min_teeth', false, 'range', 15, null),
    ('rear_derailleur', 'rear_derailleur_total_capacity_teeth', false, 'range', 30, null),
    ('rear_derailleur', 'derailleur_clutch', false, 'features', 10, null),

    ('front_derailleur', 'drivetrain_platform', false, 'compatibility', 40, null),

    ('shifter', 'drivetrain_platform', false, 'compatibility', 50, null),

    ('bottom_bracket', 'bb_shell_diameter_mm', false, 'dimensions', 40, null),
    ('bottom_bracket_bearing', 'bb_bearing_width_mm', false, 'dimensions', 40, null),

    ('crankset', 'drivetrain_platform', false, 'compatibility', 60, null),
    ('crankset', 'chain_profile_family', false, 'compatibility', 70, 'Perfil de cadena/plato declarado si aplica.'),

    ('chainring', 'chain_profile_family', false, 'compatibility', 40, null),
    ('chainring', 'drivetrain_platform', false, 'compatibility', 50, null),

    ('chain_guide', 'drivetrain_platform', false, 'compatibility', 30, null),

    ('drivetrain_kit', 'drivetrain_platform', false, 'compatibility', 50, null),
    ('drivetrain_kit', 'chain_profile_family', false, 'compatibility', 60, null),
    ('drivetrain_kit', 'chain_ebike_rated', false, 'features', 10, null)
)
insert into spec_template_fields (
  tenant_id,
  template_id,
  spec_definition_id,
  is_required,
  section_key,
  sort_order,
  helper_text
)
select
  null,
  st.id,
  sd.id,
  fr.is_required,
  fr.section_key,
  fr.sort_order,
  fr.helper_text
from field_rows fr
join spec_templates st
  on st.tenant_id is null
 and st.key = fr.template_key
join spec_definitions sd
  on sd.tenant_id is null
 and sd.key = fr.spec_key
on conflict (template_id, spec_definition_id) do update
set is_required = excluded.is_required,
    section_key = excluded.section_key,
    sort_order = excluded.sort_order,
    helper_text = excluded.helper_text,
    updated_at = now();
