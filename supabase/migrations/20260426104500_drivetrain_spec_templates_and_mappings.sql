-- ============================================================================
-- DRIVETRAIN SPEC TEMPLATES + CATEGORY MAPPINGS
-- Migration: 20260426104500_drivetrain_spec_templates_and_mappings.sql
--
-- Adds the structured ficha-tecnica layer needed for drivetrain compatibility.
-- This follows the existing mature pattern:
--   category_tech_mappings -> spec_templates -> product_spec_values
--   -> BikeProductCompatibilityService
--
-- Important: this does not infer product specs from names/SKUs. It creates the
-- fields and maps the right commercial categories so real product ficha data can
-- be entered, audited, and consumed by the compatibility engine.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. System spec definitions
-- ---------------------------------------------------------------------------

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
  (null, 'drivetrain_speeds', 'Velocidades transmisión',
   'Velocidades traseras compatibles: cassette, piñón, cambio, shifter, volante o corona.',
   'multi_select', null, '["1","5","6","7","8","9","10","11","12","13"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Compatibilidad', 10),

  (null, 'chain_speeds', 'Velocidades cadena',
   'Velocidades traseras compatibles para cadenas y conectores de cadena.',
   'multi_select', null, '["1","5","6","7","8","9","10","11","12","13"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Compatibilidad', 11),

  (null, 'chain_width_family', 'Familia ancho cadena',
   'Familia de ancho de cadena; especialmente importante para single speed, BMX y transmisiones modernas.',
   'single_select', null, '["1/8","3/32","11/128","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Compatibilidad', 12),

  (null, 'link_count', 'Cantidad de eslabones',
   'Cantidad de eslabones incluidos en una cadena.',
   'number', 'eslabones', '[]'::jsonb, '{"min":1,"max":180}'::jsonb,
   false, false, false, true, true, 'Contenido', 20),

  (null, 'quick_link_included', 'Incluye missing link',
   'Indica si la cadena incluye conector rapido.',
   'boolean', null, '[]'::jsonb, '{}'::jsonb,
   true, false, false, true, true, 'Contenido', 21),

  (null, 'chain_connector_type', 'Tipo conector cadena',
   'Tipo de conector o cierre de cadena.',
   'single_select', null, '["Missing link","Pin","Half link","Otro"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Compatibilidad', 22),

  (null, 'freehub_type', 'Driver / Freehub',
   'Familia de driver trasero: núcleo de cassette, rueda libre roscada, driver BMX, fijo o contrapedal.',
   'single_select', null, '["Shimano HG","Micro Spline","SRAM XD","Campagnolo","Rueda libre roscada","Driver BMX","Rosca fija / contratuerca","Maza contrapedal","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Compatibilidad', 23),

  (null, 'smallest_cog_teeth', 'Piñón menor',
   'Cantidad de dientes del piñón más pequeño del cassette o rueda libre.',
   'number', 'T', '[]'::jsonb, '{"min":8,"max":24}'::jsonb,
   true, false, true, true, true, 'Rango', 30),

  (null, 'largest_cog_teeth', 'Piñón mayor',
   'Cantidad de dientes del piñón más grande del cassette o rueda libre.',
   'number', 'T', '[]'::jsonb, '{"min":14,"max":60}'::jsonb,
   true, false, true, true, true, 'Rango', 31),

  (null, 'single_cog_teeth', 'Dientes piñón simple',
   'Cantidad de dientes cuando el producto es piñón simple, fixie o single speed.',
   'number', 'T', '[]'::jsonb, '{"min":9,"max":24}'::jsonb,
   true, false, true, true, true, 'Rango', 32),

  (null, 'front_chainring_count', 'Cantidad de platos',
   'Cantidad de platos delanteros que el componente soporta o incluye.',
   'multi_select', null, '["1","2","3"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Compatibilidad', 40),

  (null, 'chainring_teeth', 'Dientes plato/corona',
   'Dientes del plato o corona; puede ser un valor simple o una combinación como 42/34/24.',
   'text', 'T', '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Transmisión delantera', 41),

  (null, 'chainring_bcd_mm', 'BCD corona',
   'Diámetro BCD de la corona/plato.',
   'number', 'mm', '[]'::jsonb, '{"min":64,"max":144}'::jsonb,
   true, false, true, true, true, 'Montaje', 42),

  (null, 'chainring_bolt_count', 'Pernos corona',
   'Cantidad de pernos de montaje de la corona/plato.',
   'single_select', null, '["3","4","5","Direct mount","Otro"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Montaje', 43),

  (null, 'chainring_mount_type', 'Montaje corona',
   'Interfaz de montaje de corona/plato.',
   'single_select', null, '["BCD 4 pernos","BCD 5 pernos","Direct mount Shimano","Direct mount SRAM","Direct mount Cinch","Rosca BMX","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Montaje', 44),

  (null, 'chainring_offset_mm', 'Offset corona',
   'Offset de corona/plato para línea de cadena.',
   'number', 'mm', '[]'::jsonb, '{"min":-10,"max":10}'::jsonb,
   false, false, true, true, true, 'Montaje', 45),

  (null, 'narrow_wide', 'Narrow-wide',
   'Indica si la corona usa perfil narrow-wide.',
   'boolean', null, '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Transmisión delantera', 46),

  (null, 'crank_arm_length_mm', 'Largo biela',
   'Largo de biela/pedivela.',
   'number', 'mm', '[]'::jsonb, '{"min":130,"max":190}'::jsonb,
   true, false, true, true, true, 'Bielas', 50),

  (null, 'crank_side', 'Lado biela',
   'Lado de la biela o pedivela cuando se vende por separado.',
   'single_select', null, '["Izquierda","Derecha","Par"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Bielas', 51),

  (null, 'pedal_thread', 'Rosca pedal',
   'Rosca de pedal compatible.',
   'single_select', null, '["9/16","1/2","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Bielas', 52),

  (null, 'chainline_mm', 'Línea de cadena',
   'Línea de cadena nominal del volante/corona.',
   'number', 'mm', '[]'::jsonb, '{"min":35,"max":60}'::jsonb,
   false, false, true, true, true, 'Compatibilidad', 53),

  (null, 'bottom_bracket_family', 'Familia pedalier / motor',
   'Familia o estándar principal del eje de motor / bottom bracket.',
   'single_select', null, '["BSA roscado","Pressfit","BB30 / PF30","Mid / BMX","Americano / one-piece","Cuadrado cartucho","Hollowtech / 24mm externo","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Pedalier', 60),

  (null, 'bb_thread_standard', 'Rosca pedalier',
   'Estándar de rosca o caja del pedalier.',
   'single_select', null, '["BSA / Inglés 1.37x24","Italiano","Americano BMX","Mid BMX","Pressfit","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Pedalier', 61),

  (null, 'bb_shell_width_mm', 'Ancho caja motor',
   'Ancho de caja del cuadro para motor / bottom bracket.',
   'number', 'mm', '[]'::jsonb, '{"min":50,"max":125}'::jsonb,
   true, false, true, true, true, 'Pedalier', 62),

  (null, 'spindle_interface', 'Interfaz eje',
   'Interfaz del eje con biela: cuadrado, Hollowtech, ISIS, BMX, etc.',
   'single_select', null, '["Cuadrado JIS","Cuadrado ISO","Hollowtech / 24mm","SRAM DUB","ISIS","Octalink","BMX 19mm","BMX 22mm","BMX 24mm","One-piece / americano","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Pedalier', 63),

  (null, 'spindle_length_mm', 'Largo eje',
   'Largo del eje de motor / spindle.',
   'number', 'mm', '[]'::jsonb, '{"min":80,"max":150}'::jsonb,
   true, false, true, true, true, 'Pedalier', 64),

  (null, 'spindle_diameter_mm', 'Diámetro eje',
   'Diámetro de eje/spindle, común en BMX y motores externos.',
   'number', 'mm', '[]'::jsonb, '{"min":15,"max":32}'::jsonb,
   true, false, true, true, true, 'Pedalier', 65),

  (null, 'bearing_size_code', 'Código rodamiento',
   'Código comercial del rodamiento, por ejemplo 6805, 6902 o 163110.',
   'text', null, '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Rodamientos', 66),

  (null, 'bearing_inner_diameter_mm', 'Diámetro interno rodamiento',
   'Diámetro interno del rodamiento.',
   'number', 'mm', '[]'::jsonb, '{"min":5,"max":40}'::jsonb,
   true, false, true, true, true, 'Rodamientos', 67),

  (null, 'bearing_outer_diameter_mm', 'Diámetro externo rodamiento',
   'Diámetro externo del rodamiento.',
   'number', 'mm', '[]'::jsonb, '{"min":10,"max":60}'::jsonb,
   true, false, true, true, true, 'Rodamientos', 68),

  (null, 'shifter_position', 'Posición shifter',
   'Indica si el mando controla cambio delantero, trasero o viene como par.',
   'single_select', null, '["Izquierdo / delantero","Derecho / trasero","Par","Universal"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Cambios', 70),

  (null, 'shift_actuation_family', 'Familia indexado / tiro',
   'Familia de tiro/indexado para shifter y desviadores.',
   'single_select', null, '["Shimano MTB 6-9v","Shimano MTB 10-12v","Shimano ruta","Shimano CUES / Linkglide","SRAM Exact Actuation","SRAM X-Actuation","Campagnolo","Fricción","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Cambios', 71),

  (null, 'rear_derailleur_mount_type', 'Montaje cambio trasero',
   'Tipo de montaje del cambio trasero.',
   'single_select', null, '["Pata/postiza estándar","Direct mount","Con uña / claw","Extensor de pata","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Cambios', 72),

  (null, 'rear_derailleur_max_teeth', 'Máximo piñón cambio trasero',
   'Máximo piñón que soporta el cambio trasero.',
   'number', 'T', '[]'::jsonb, '{"min":24,"max":60}'::jsonb,
   true, false, true, true, true, 'Cambios', 73),

  (null, 'derailleur_cage_length', 'Largo caja cambio',
   'Largo de caja/pata del cambio trasero.',
   'single_select', null, '["SS / corta","GS / media","SGS / larga","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Cambios', 74),

  (null, 'front_derailleur_mount_type', 'Montaje desviador delantero',
   'Tipo de montaje del desviador delantero.',
   'single_select', null, '["Abrazadera","Braze-on","E-type","Direct mount","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Cambios', 75),

  (null, 'front_derailleur_clamp_mm', 'Abrazadera desviador delantero',
   'Diámetro de abrazadera del desviador delantero.',
   'single_select', 'mm', '["28.6","31.8","34.9","Otro","No aplica"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Cambios', 76),

  (null, 'front_derailleur_pull_direction', 'Tiro desviador delantero',
   'Dirección de tiro del cable del desviador delantero.',
   'single_select', null, '["Top pull","Down pull","Dual pull","Side swing","Electrónico","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Cambios', 77),

  (null, 'pulley_teeth', 'Dientes roldana',
   'Cantidad de dientes de la roldana/polea de cambio.',
   'number', 'T', '[]'::jsonb, '{"min":8,"max":18}'::jsonb,
   true, false, true, true, true, 'Roldanas', 80),

  (null, 'hanger_model_code', 'Código postiza / pata',
   'Código de modelo de la postiza o fusible de cambio.',
   'text', null, '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Postiza', 81),

  (null, 'compatible_frame_hint', 'Compatibilidad cuadro',
   'Marca/modelo de cuadro compatible cuando aplica.',
   'text', null, '[]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Postiza', 82),

  (null, 'chain_guide_mount_type', 'Montaje guía cadena',
   'Tipo de montaje de guía de cadena.',
   'single_select', null, '["ISCG 05","BB mount","Seat tube","Direct mount","Otro","Desconocido / sin confirmar"]'::jsonb, '{}'::jsonb,
   true, false, true, true, true, 'Guía cadena', 83),

  (null, 'spacer_thickness_mm', 'Espesor espaciador',
   'Espesor del espaciador de cassette/freehub.',
   'number', 'mm', '[]'::jsonb, '{"min":0.5,"max":10}'::jsonb,
   true, false, true, true, true, 'Espaciadores', 84),

  (null, 'kit_contents', 'Contenido kit',
   'Resumen estructurado/manual del contenido del kit.',
   'text', null, '[]'::jsonb, '{}'::jsonb,
   false, false, false, true, true, 'Kit', 85)
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

-- ---------------------------------------------------------------------------
-- 2. System templates
-- ---------------------------------------------------------------------------

insert into spec_templates (
  tenant_id,
  key,
  name,
  technical_family,
  description,
  default_tags,
  is_active
)
values
  (null, 'chain', 'Cadena', 'chain',
   'Cadena de transmisión; compatibilidad principal por velocidades y familia de ancho.',
   '["drivetrain","chain"]'::jsonb, true),
  (null, 'chain_link', 'Missing Link / Conector Cadena', 'chain_link',
   'Conector de cadena; compatibilidad principal por velocidades y ancho de cadena.',
   '["drivetrain","chain"]'::jsonb, true),
  (null, 'cassette', 'Cassette', 'cassette',
   'Cassette para núcleo/freehub; compatibilidad por velocidades, driver y rango.',
   '["drivetrain","rear_cogs"]'::jsonb, true),
  (null, 'freewheel', 'Piñón / Rueda Libre', 'freewheel',
   'Piñón atornillado o rueda libre; compatibilidad por rosca/driver y velocidades.',
   '["drivetrain","rear_cogs"]'::jsonb, true),
  (null, 'fixed_cog', 'Piñón Fixie', 'fixed_cog',
   'Piñón fijo o single speed roscado.',
   '["drivetrain","rear_cogs","fixie"]'::jsonb, true),
  (null, 'rear_derailleur', 'Cambio Trasero', 'rear_derailleur',
   'Cambio trasero; compatibilidad por velocidades, tiro/indexado, montaje y rango maximo.',
   '["drivetrain","derailleur"]'::jsonb, true),
  (null, 'front_derailleur', 'Desviador Delantero', 'front_derailleur',
   'Desviador delantero; compatibilidad por cantidad de platos, tiro y montaje.',
   '["drivetrain","derailleur"]'::jsonb, true),
  (null, 'shifter', 'Shifter / Mando Cambio', 'shifter',
   'Mando de cambio; compatibilidad por posicion, velocidades e indexado.',
   '["drivetrain","controls"]'::jsonb, true),
  (null, 'derailleur_hanger', 'Postiza / Pata Cambio', 'derailleur_hanger',
   'Postiza o fusible de cambio; compatibilidad por cuadro/modelo y montaje.',
   '["drivetrain","hanger"]'::jsonb, true),
  (null, 'derailleur_pulley', 'Roldana Cambio', 'derailleur_pulley',
   'Roldana/polea de cambio trasero.',
   '["drivetrain","derailleur"]'::jsonb, true),
  (null, 'bottom_bracket', 'Motor / Bottom Bracket', 'bottom_bracket',
   'Motor/pedalier completo; compatibilidad por familia, caja, rosca, eje e interfaz.',
   '["drivetrain","bottom_bracket"]'::jsonb, true),
  (null, 'bottom_bracket_axle', 'Eje de Motor', 'bottom_bracket_axle',
   'Eje/spindle de motor; compatibilidad por interfaz, largo y familia.',
   '["drivetrain","bottom_bracket"]'::jsonb, true),
  (null, 'bottom_bracket_cup', 'Cubeta de Motor', 'bottom_bracket_cup',
   'Cubeta/cazoleta de motor; compatibilidad por rosca, caja y familia.',
   '["drivetrain","bottom_bracket"]'::jsonb, true),
  (null, 'bottom_bracket_bearing', 'Rodamiento Motor', 'bottom_bracket_bearing',
   'Rodamiento de motor/pedalier; compatibilidad por codigo y medidas.',
   '["drivetrain","bottom_bracket","bearing"]'::jsonb, true),
  (null, 'crankset', 'Volante / Pedivela', 'crankset',
   'Volante/pedivela completo; compatibilidad por platos, eje, motor y velocidades.',
   '["drivetrain","crankset"]'::jsonb, true),
  (null, 'crank_arm', 'Biela / Pedivela Suelta', 'crank_arm',
   'Biela suelta; compatibilidad por lado, largo, interfaz de eje y rosca de pedal.',
   '["drivetrain","crankset"]'::jsonb, true),
  (null, 'chainring', 'Corona / Catalina / Plato', 'chainring',
   'Corona, catalina o plato; compatibilidad por dientes, BCD/montaje, velocidades y offset.',
   '["drivetrain","chainring"]'::jsonb, true),
  (null, 'chain_guide', 'Guía de Cadena', 'chain_guide',
   'Guía de cadena; compatibilidad por montaje, plato y línea de cadena.',
   '["drivetrain","chain_guide"]'::jsonb, true),
  (null, 'cassette_spacer', 'Espaciador Cassette', 'cassette_spacer',
   'Espaciador de cassette/freehub.',
   '["drivetrain","rear_cogs"]'::jsonb, true),
  (null, 'drivetrain_kit', 'Kit Transmisión', 'drivetrain_kit',
   'Kit mixto de transmisión; ficha resume contenido y compatibilidades principales.',
   '["drivetrain","kit"]'::jsonb, true)
on conflict (key) where tenant_id is null do update
set name = excluded.name,
    technical_family = excluded.technical_family,
    description = excluded.description,
    default_tags = excluded.default_tags,
    is_active = excluded.is_active,
    updated_at = now();

-- ---------------------------------------------------------------------------
-- 3. Template fields
-- ---------------------------------------------------------------------------

with field_rows(template_key, spec_key, is_required, section_key, sort_order, helper_text) as (
  values
    ('chain', 'chain_speeds', true, 'compatibility', 10, 'Velocidades reales que soporta la cadena.'),
    ('chain', 'chain_width_family', false, 'compatibility', 20, 'Importante en single speed, BMX y cadenas angostas.'),
    ('chain', 'link_count', false, 'contents', 10, null),
    ('chain', 'quick_link_included', false, 'contents', 20, null),

    ('chain_link', 'chain_speeds', true, 'compatibility', 10, 'Debe coincidir con la cadena instalada.'),
    ('chain_link', 'chain_width_family', false, 'compatibility', 20, null),
    ('chain_link', 'chain_connector_type', false, 'identification', 10, null),

    ('cassette', 'drivetrain_speeds', true, 'compatibility', 10, 'Cantidad de velocidades traseras.'),
    ('cassette', 'freehub_type', true, 'compatibility', 20, 'Driver/nucleo requerido por el cassette.'),
    ('cassette', 'smallest_cog_teeth', false, 'range', 10, null),
    ('cassette', 'largest_cog_teeth', false, 'range', 20, 'Debe cruzarse con capacidad del cambio trasero.'),

    ('freewheel', 'drivetrain_speeds', true, 'compatibility', 10, '1v para piñón simple; 5-8v para ruedas libres comunes.'),
    ('freewheel', 'freehub_type', true, 'compatibility', 20, 'Normalmente rueda libre roscada.'),
    ('freewheel', 'smallest_cog_teeth', false, 'range', 10, null),
    ('freewheel', 'largest_cog_teeth', false, 'range', 20, null),

    ('fixed_cog', 'drivetrain_speeds', false, 'compatibility', 10, 'Normalmente 1v / single speed.'),
    ('fixed_cog', 'freehub_type', true, 'compatibility', 20, 'Normalmente rosca fija / contratuerca.'),
    ('fixed_cog', 'single_cog_teeth', true, 'range', 10, null),
    ('fixed_cog', 'chain_width_family', false, 'compatibility', 30, null),

    ('rear_derailleur', 'drivetrain_speeds', true, 'compatibility', 10, 'Velocidades traseras compatibles.'),
    ('rear_derailleur', 'shift_actuation_family', false, 'compatibility', 20, 'Familia de tiro/indexado.'),
    ('rear_derailleur', 'rear_derailleur_mount_type', false, 'mounting', 10, null),
    ('rear_derailleur', 'rear_derailleur_max_teeth', false, 'range', 10, 'Piñón mayor máximo soportado.'),
    ('rear_derailleur', 'derailleur_cage_length', false, 'range', 20, null),

    ('front_derailleur', 'front_chainring_count', true, 'compatibility', 10, '2x o 3x principalmente.'),
    ('front_derailleur', 'drivetrain_speeds', false, 'compatibility', 20, 'Velocidades traseras compatibles.'),
    ('front_derailleur', 'shift_actuation_family', false, 'compatibility', 30, null),
    ('front_derailleur', 'front_derailleur_mount_type', false, 'mounting', 10, null),
    ('front_derailleur', 'front_derailleur_clamp_mm', false, 'mounting', 20, null),
    ('front_derailleur', 'front_derailleur_pull_direction', false, 'mounting', 30, null),

    ('shifter', 'shifter_position', true, 'compatibility', 10, 'Izquierdo/delantero, derecho/trasero o par.'),
    ('shifter', 'drivetrain_speeds', false, 'compatibility', 20, 'Velocidades para shifter derecho/trasero.'),
    ('shifter', 'front_chainring_count', false, 'compatibility', 30, 'Platos para shifter izquierdo/delantero.'),
    ('shifter', 'shift_actuation_family', false, 'compatibility', 40, null),

    ('derailleur_hanger', 'hanger_model_code', false, 'identification', 10, 'Codigo A-HG, AE, marca/modelo, etc.'),
    ('derailleur_hanger', 'compatible_frame_hint', false, 'compatibility', 10, 'Marca/modelo de cuadro compatible.'),
    ('derailleur_hanger', 'rear_derailleur_mount_type', false, 'mounting', 10, null),

    ('derailleur_pulley', 'pulley_teeth', true, 'compatibility', 10, null),
    ('derailleur_pulley', 'derailleur_cage_length', false, 'compatibility', 20, null),

    ('bottom_bracket', 'bottom_bracket_family', true, 'compatibility', 10, 'Debe coincidir con el estándar confirmado de la bici.'),
    ('bottom_bracket', 'bb_thread_standard', false, 'compatibility', 20, null),
    ('bottom_bracket', 'bb_shell_width_mm', false, 'dimensions', 10, null),
    ('bottom_bracket', 'spindle_interface', false, 'compatibility', 30, null),
    ('bottom_bracket', 'spindle_length_mm', false, 'dimensions', 20, null),
    ('bottom_bracket', 'spindle_diameter_mm', false, 'dimensions', 30, null),

    ('bottom_bracket_axle', 'bottom_bracket_family', false, 'compatibility', 10, null),
    ('bottom_bracket_axle', 'spindle_interface', true, 'compatibility', 20, null),
    ('bottom_bracket_axle', 'spindle_length_mm', true, 'dimensions', 10, null),

    ('bottom_bracket_cup', 'bottom_bracket_family', true, 'compatibility', 10, null),
    ('bottom_bracket_cup', 'bb_thread_standard', false, 'compatibility', 20, null),
    ('bottom_bracket_cup', 'bb_shell_width_mm', false, 'dimensions', 10, null),

    ('bottom_bracket_bearing', 'bottom_bracket_family', false, 'compatibility', 10, null),
    ('bottom_bracket_bearing', 'bearing_size_code', false, 'identification', 10, null),
    ('bottom_bracket_bearing', 'bearing_inner_diameter_mm', false, 'dimensions', 10, null),
    ('bottom_bracket_bearing', 'bearing_outer_diameter_mm', false, 'dimensions', 20, null),
    ('bottom_bracket_bearing', 'spindle_diameter_mm', false, 'dimensions', 30, null),

    ('crankset', 'front_chainring_count', false, 'compatibility', 10, null),
    ('crankset', 'chainring_teeth', false, 'compatibility', 20, null),
    ('crankset', 'drivetrain_speeds', false, 'compatibility', 30, 'Velocidades traseras compatibles cuando el fabricante lo declara.'),
    ('crankset', 'bottom_bracket_family', false, 'compatibility', 40, null),
    ('crankset', 'spindle_interface', false, 'compatibility', 50, null),
    ('crankset', 'crank_arm_length_mm', false, 'dimensions', 10, null),
    ('crankset', 'chainline_mm', false, 'dimensions', 20, null),

    ('crank_arm', 'crank_side', true, 'identification', 10, null),
    ('crank_arm', 'crank_arm_length_mm', true, 'dimensions', 10, null),
    ('crank_arm', 'spindle_interface', true, 'compatibility', 10, null),
    ('crank_arm', 'pedal_thread', false, 'compatibility', 20, null),

    ('chainring', 'chainring_teeth', true, 'compatibility', 10, null),
    ('chainring', 'drivetrain_speeds', false, 'compatibility', 20, 'Velocidades traseras compatibles si la corona lo declara.'),
    ('chainring', 'chain_width_family', false, 'compatibility', 30, null),
    ('chainring', 'chainring_bcd_mm', false, 'mounting', 10, null),
    ('chainring', 'chainring_bolt_count', false, 'mounting', 20, null),
    ('chainring', 'chainring_mount_type', false, 'mounting', 30, null),
    ('chainring', 'chainring_offset_mm', false, 'mounting', 40, null),
    ('chainring', 'narrow_wide', false, 'features', 10, null),

    ('chain_guide', 'chain_guide_mount_type', false, 'mounting', 10, null),
    ('chain_guide', 'chainring_teeth', false, 'compatibility', 10, null),
    ('chain_guide', 'chainline_mm', false, 'compatibility', 20, null),

    ('cassette_spacer', 'freehub_type', false, 'compatibility', 10, null),
    ('cassette_spacer', 'spacer_thickness_mm', true, 'dimensions', 10, null),

    ('drivetrain_kit', 'kit_contents', false, 'contents', 10, null),
    ('drivetrain_kit', 'front_chainring_count', false, 'compatibility', 10, null),
    ('drivetrain_kit', 'chainring_teeth', false, 'compatibility', 20, null),
    ('drivetrain_kit', 'bottom_bracket_family', false, 'compatibility', 30, null),
    ('drivetrain_kit', 'spindle_interface', false, 'compatibility', 40, null),
    ('drivetrain_kit', 'crank_arm_length_mm', false, 'dimensions', 10, null)
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

-- ---------------------------------------------------------------------------
-- 4. Existing tenant category mappings
-- ---------------------------------------------------------------------------

with mapping_rows(full_path, technical_family, template_key, default_tags, status) as (
  values
    ('Componentes / Transmisión / Cadenas', 'chain', 'chain', '["drivetrain","chain"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Missinglink', 'chain_link', 'chain_link', '["drivetrain","chain"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Cadenas / Guias de cadena', 'chain_guide', 'chain_guide', '["drivetrain","chain_guide"]'::jsonb, 'active'),

    ('Componentes / Transmisión / Piñones', 'freewheel', 'freewheel', '["drivetrain","rear_cogs"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Piñones / Cassette', 'cassette', 'cassette', '["drivetrain","rear_cogs"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Piñones / Freewheel', 'freewheel', 'freewheel', '["drivetrain","rear_cogs"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Piñones / Fixie', 'fixed_cog', 'fixed_cog', '["drivetrain","rear_cogs","fixie"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Piñones / Espaciadores de Cassette', 'cassette_spacer', 'cassette_spacer', '["drivetrain","rear_cogs"]'::jsonb, 'active'),

    ('Componentes / Cambios / Desviadores / Desviador Trasero', 'rear_derailleur', 'rear_derailleur', '["drivetrain","derailleur"]'::jsonb, 'active'),
    ('Componentes / Cambios / Desviadores / Desviadores delanteros', 'front_derailleur', 'front_derailleur', '["drivetrain","derailleur"]'::jsonb, 'active'),
    ('Componentes / Cambios / Shifters', 'shifter', 'shifter', '["drivetrain","controls"]'::jsonb, 'active'),
    ('Componentes / Cambios / Postiza', 'derailleur_hanger', 'derailleur_hanger', '["drivetrain","hanger"]'::jsonb, 'active'),
    ('Componentes / Cambios / Roldanas', 'derailleur_pulley', 'derailleur_pulley', '["drivetrain","derailleur"]'::jsonb, 'active'),

    ('Componentes / Transmisión / Motores / Motor', 'bottom_bracket', 'bottom_bracket', '["drivetrain","bottom_bracket"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Motores / Ejes de motor', 'bottom_bracket_axle', 'bottom_bracket_axle', '["drivetrain","bottom_bracket"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Motores / Cubetas', 'bottom_bracket_cup', 'bottom_bracket_cup', '["drivetrain","bottom_bracket"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Motores / Rodamientos Motor', 'bottom_bracket_bearing', 'bottom_bracket_bearing', '["drivetrain","bottom_bracket","bearing"]'::jsonb, 'active'),

    ('Componentes / Transmisión / Volantes', 'crankset', 'crankset', '["drivetrain","crankset"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Volantes / Volante', 'crankset', 'crankset', '["drivetrain","crankset"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Volantes / Biela Americana', 'crankset', 'crankset', '["drivetrain","crankset","bmx"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Volantes / Biela Izquierda', 'crank_arm', 'crank_arm', '["drivetrain","crankset"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Volantes / Catalina', 'chainring', 'chainring', '["drivetrain","chainring"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Volantes / Coronas', 'chainring', 'chainring', '["drivetrain","chainring"]'::jsonb, 'active'),
    ('Componentes / Transmisión / Kits', 'drivetrain_kit', 'drivetrain_kit', '["drivetrain","kit"]'::jsonb, 'active')
)
insert into category_tech_mappings (
  tenant_id,
  category_id,
  technical_family,
  template_id,
  default_tags,
  status
)
select
  pc.tenant_id,
  pc.id,
  mr.technical_family,
  st.id,
  mr.default_tags,
  mr.status
from mapping_rows mr
join product_categories pc
  on pc.tenant_id is not null
 and pc.full_path = mr.full_path
join spec_templates st
  on st.tenant_id is null
 and st.key = mr.template_key
on conflict (tenant_id, category_id) do update
set technical_family = excluded.technical_family,
    template_id = excluded.template_id,
    default_tags = excluded.default_tags,
    status = excluded.status,
    updated_at = now();
