-- La tienda habla con las palabras del cliente (2026-10-01).
--
-- El dueño: «todo lo que esté publicado en la página web tiene que ser
-- mostrado de una forma ultra user friendly y orientada al cliente, con
-- vocabulario entendible en Chile». La ficha pública salía de los mismos
-- hechos que la del ERP, pero con las palabras del operador: «Talón (alambre
-- o plegable)», «TPI (densidad de la carcasa)», «Velocidades declaradas del
-- modelo», «Variante (rango publicado)», y sin decir qué datos importan.
-- La tienda los compensaba con un mapa propio de claves de 2026-05 que ya no
-- calzaba con ninguna ficha.
--
-- Desde aquí la base es dueña de esas palabras:
--   * `spec_definitions.store_label`: cómo se llama el dato en la tienda.
--   * `spec_definitions.store_hint`: una línea que explica un término técnico
--     (TPI, ETRTO, OLD, BCD…), sin afirmar nada del producto.
--   * `spec_template_fields.store_label`: el mismo dato leído distinto en una
--     ficha («Velocidades de la cadena» en un eslabón rápido).
--   * `spec_template_fields.store_highlight`: lo que decide la compra, en
--     orden, para mostrarlo junto al precio.
-- El rótulo del operador, sus reglas y las lecturas del nombre no cambian:
-- el recibo de una lectura no mira estas columnas.
--
-- 227 datos de productos publicados reciben nombre (226 se ven hoy; el borde
-- del aro espera un valor conocido); 3 dejan de mostrarse
-- porque son texto de proveedor o notas de conciliación («12-32T (br)»,
-- «Riveted adapter (ROAD type)», «Sleeve»); 19 opciones en inglés reciben su
-- nombre visible. Los filtros del catálogo usan el mismo nombre y el nombre
-- visible de cada opción.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

alter table public.spec_definitions
  add column if not exists store_label text,
  add column if not exists store_hint text;
alter table public.spec_template_fields
  add column if not exists store_label text,
  add column if not exists store_highlight smallint;
alter table public.spec_template_fields
  drop constraint if exists spec_template_fields_store_highlight_check;
alter table public.spec_template_fields
  add constraint spec_template_fields_store_highlight_check
  check (store_highlight between 1 and 9);

comment on column public.spec_definitions.store_label is
  'Cómo se llama el dato en la tienda, en palabras de cliente chileno. Nulo: el rótulo de la ficha.';
comment on column public.spec_definitions.store_hint is
  'Una línea que explica el término técnico al cliente; nunca afirma nada del producto.';
comment on column public.spec_template_fields.store_label is
  'Nombre del dato en la tienda para esta ficha, cuando difiere del de la definición.';
comment on column public.spec_template_fields.store_highlight is
  'Orden del dato entre lo esencial que la tienda muestra junto al precio (1 primero). Nulo: no es esencial.';

create temporary table _store_words(key text primary key, label text not null, hint text) on commit drop;
insert into _store_words(key, label, hint) values
    ('accessory_mount_kind', 'Tipo de soporte', null),
    ('adjustable_fit', 'Ajuste regulable', null),
    ('adjustable_length', 'Largo regulable', null),
    ('axle_hollow', 'Eje hueco', null),
    ('axle_length_mm', 'Largo del eje', null),
    ('axle_to_crown_mm', 'Altura eje a corona', 'Distancia del eje de la rueda a la corona; cambiarla altera la geometría de la bicicleta.'),
    ('axle_type', 'Eje', null),
    ('bag_kind', 'Tipo de bolso', null),
    ('bag_position', 'Ubicación', null),
    ('ball_diameter_in', 'Tamaño de la bolita', null),
    ('bar_clamp_diameter_mm', 'Diámetro de abrazadera', 'El manubrio y el tee deben tener el mismo diámetro.'),
    ('bar_rise_mm', 'Altura (rise)', null),
    ('bar_style', 'Tipo de manubrio', null),
    ('bar_width_mm', 'Ancho', null),
    ('barrel_material', 'Material del cuerpo', null),
    ('bb_ball_count_per_side', 'Bolitas por lado', null),
    ('bb_ball_size_in', 'Tamaño de la bolita', null),
    ('bead_seat_diameter_mm', 'Aro', null),
    ('bearing_application', 'Para', null),
    ('bearing_size_code', 'Código del rodamiento', null),
    ('bearing_supply_form', 'Presentación', null),
    ('bearing_system', 'Rodamientos', null),
    ('biodegradable_claim', 'Biodegradable', null),
    ('body_material', 'Material', null),
    ('bottom_bracket_included', 'Incluye motor (eje de centro)', null),
    ('brake_actuation', 'Sistema', 'Mecánico funciona con piola; hidráulico, con líquido y frena con menos fuerza en la manilla.'),
    ('brake_mount', 'Montaje de freno', 'Debe coincidir con el montaje del cáliper.'),
    ('brake_position', 'Freno', null),
    ('brake_presentation', 'Qué incluye', null),
    ('brake_track', 'Pista para V-brake', null),
    ('braking_surface', 'Para freno de', null),
    ('cable_diameter_mm', 'Grosor del cable', null),
    ('caliper_mount_interface', 'Montaje del cáliper', 'Debe coincidir con el montaje de freno del cuadro u horquilla.'),
    ('carrier_kind', 'Tipo', null),
    ('cassette_spline_standard', 'Núcleo', 'El tipo de núcleo de la maza trasera donde se monta.'),
    ('chain_connector_directional', 'Tiene sentido de montaje', null),
    ('chain_connector_type', 'Tipo de unión', null),
    ('chain_ebike_rated', 'Apta para e-bike', null),
    ('chain_link_pack_qty', 'Cantidad', null),
    ('chain_link_reusable', 'Reutilizable', null),
    ('chain_outer_width_mm', 'Ancho exterior', null),
    ('chain_pitch_mm', 'Paso', 'El paso de toda cadena de bicicleta es 12,7 mm (1/2").'),
    ('chain_speeds', 'Velocidades', null),
    ('chain_tool_speeds', 'Velocidades de cadena', null),
    ('chain_width_family', 'Ancho de cadena', '1/8": una velocidad y BMX. 3/32": con cambios de 5 a 8 velocidades. 11/128": de 9 a 12.'),
    ('chainring_bcd_mm', 'BCD (círculo de pernos)', 'Diámetro del círculo que forman los pernos del plato; debe coincidir con la biela.'),
    ('chainring_mounting', 'Fijación de los platos', null),
    ('chainring_package_kind', 'Presentación', null),
    ('chainring_position', 'Posición del plato', null),
    ('chemical_kind', 'Tipo de producto', null),
    ('clamp_kind', 'Tipo de cierre', null),
    ('compound_type', 'Compuesto', 'Orgánico: más silencioso. Metálico: dura más y rinde mejor con barro.'),
    ('cones_and_locknuts_included', 'Incluye conos y contratuercas', null),
    ('consumable_kind', 'Tipo', null),
    ('container', 'Envase', null),
    ('control_part_kind', 'Tipo de pieza', null),
    ('covering_kind', 'Tipo', null),
    ('crank_arm_carries_chainring_mount', 'Lleva los platos', null),
    ('crank_arm_length_mm', 'Largo de biela', null),
    ('crank_arm_system_construction', 'Tipo de volante', null),
    ('crank_fixing_bolt_included', 'Incluye perno de biela', null),
    ('crank_side', 'Lado', null),
    ('crankset_chain_guard_included', 'Incluye cubrecadena', null),
    ('crankset_construction', 'Tipo de volante', null),
    ('declared_applications', 'Usos', null),
    ('declared_purpose', 'Uso', null),
    ('derailleur_cage_length', 'Largo de la pata', 'Una pata más larga admite piñones más grandes.'),
    ('derailleur_clutch', 'Estabilizador de cadena (clutch)', 'Evita que la cadena golpee el cuadro o se salga en terreno irregular.'),
    ('device_kind', 'Tipo', null),
    ('device_width_max_mm', 'Ancho máximo del equipo', null),
    ('device_width_min_mm', 'Ancho mínimo del equipo', null),
    ('drivetrain_mode', 'Transmisión', null),
    ('dust_cap_included', 'Incluye tapa guardapolvo', null),
    ('fastener_kind', 'Tipo', null),
    ('fender_position', 'Ubicación', null),
    ('finger_length', 'Dedos', null),
    ('fits_volume_max_l', 'Para mochilas de hasta', null),
    ('fits_volume_min_l', 'Para mochilas desde', null),
    ('fork_kind', 'Tipo de horquilla', null),
    ('front_derailleur_cable_pull', 'Tiro del cable', 'Por dónde llega la piola al desviador; debe coincidir con el cuadro.'),
    ('front_derailleur_mount_type', 'Montaje', null),
    ('front_derailleur_swing', 'Movimiento', null),
    ('functions_count', 'Funciones', null),
    ('garment_kind', 'Tipo de prenda', null),
    ('gauge', 'Con manómetro', null),
    ('glove_intended_use', 'Uso', null),
    ('glue_volume_ml', 'Pegamento', null),
    ('grip_attachment', 'Fijación', 'Lock-on: se aprieta con pernos y no gira ni se suelta.'),
    ('grip_length_mm', 'Largo', null),
    ('head_drive', 'Tipo de cabeza', null),
    ('headset_part_kind', 'Tipo de pieza', null),
    ('headset_part_scope', 'Qué incluye', null),
    ('helmet_kind', 'Uso', null),
    ('hub_axle_diameter_mm', 'Diámetro del eje', null),
    ('hub_axle_mount_kind', 'Tipo de eje', null),
    ('hub_drive_receiver_kind', 'Montaje de piñones', null),
    ('hub_drive_receiver_present', 'Con montaje para piñones', null),
    ('hub_old_mm', 'Ancho de montaje (OLD)', 'Lo que mide la maza entre los apoyos del cuadro o la horquilla.'),
    ('hub_package_position', 'Ubicación', null),
    ('hub_part_kind', 'Tipo de pieza', null),
    ('hub_rotor_mount_present', 'Para freno de disco', null),
    ('included_chainring_count', 'Platos', null),
    ('includes_spindle', 'Incluye eje', null),
    ('intended_audience', 'Para', null),
    ('intended_rider', 'Para', null),
    ('kickstand_mount_kind', 'Fijación', null),
    ('largest_cog_teeth', 'Piñón más grande', null),
    ('length_mm', 'Largo', null),
    ('lever_cable_pull', 'Tipo de tiro', 'Tiro largo: V-brake y disco mecánico de tiro largo. Tiro corto: cantilever y frenos de ruta.'),
    ('lever_side', 'Lado', null),
    ('light_position', 'Posición', null),
    ('link_count', 'Largo', null),
    ('lock_kind', 'Tipo de candado', null),
    ('locking_mechanism', 'Cierre', null),
    ('lockout', 'Bloqueo', 'Bloquea la suspensión para subir o andar en pavimento.'),
    ('lockring_included', 'Incluye tuerca de cierre', null),
    ('loudness_db_claim', 'Volumen', null),
    ('lumens_claimed', 'Potencia de luz', null),
    ('material', 'Material', null),
    ('max_rotor_mm', 'Disco máximo', null),
    ('narrow_wide', 'Dientes narrow-wide', 'Dientes anchos y angostos alternados que sujetan mejor la cadena.'),
    ('nipples_included', 'Incluye niples', null),
    ('pack_quantity', 'Cantidad', null),
    ('pad_spring_included', 'Incluye resorte', null),
    ('padding', 'Acolchado', null),
    ('patch_count', 'Parches', null),
    ('pedal_thread_standard', 'Rosca', '9/16": bielas de bicicleta adulta. 1/2": bielas de una pieza (niños y BMX).'),
    ('pedal_type', 'Tipo de pedal', null),
    ('peg_axle_fit', 'Para eje de', null),
    ('peg_length_mm', 'Largo', null),
    ('power_source', 'Alimentación', null),
    ('pulley_package_kind', 'Presentación', null),
    ('pulley_teeth', 'Dientes', null),
    ('pump_kind', 'Tipo de bombín', null),
    ('quick_link_included', 'Incluye eslabón rápido', null),
    ('quill_adapter_output_diameter_mm', 'Diámetro de salida', null),
    ('quill_diameter_mm', 'Diámetro de la espiga', null),
    ('rated_power_w', 'Potencia', null),
    ('reach_adjust', 'Ajuste de distancia', null),
    ('rear_derailleur_mount_type', 'Montaje', 'Con uña: para cuadros sin postiza; se fija en el eje de la rueda.'),
    ('rear_derailleur_supplied_mount_adapter', 'Incluye uña', null),
    ('reflectors_included', 'Incluye reflectantes', null),
    ('repair_kind', 'Tipo', null),
    ('replaceable_pins', 'Pines reemplazables', null),
    ('rim_asymmetric_offset_mm', 'Desplazamiento lateral', null),
    ('rim_bead_profile', 'Borde del aro', 'Sin gancho (hookless) sólo admite neumáticos aprobados para ese borde.'),
    ('rim_erd_mm', 'ERD', 'Diámetro efectivo del aro: con él se calcula el largo de los rayos.'),
    ('rim_etrto', 'Medida ETRTO', 'Medida exacta en milímetros: diámetro × ancho interno.'),
    ('rim_external_width_mm', 'Ancho externo', null),
    ('rim_eyelet_type', 'Ojetillos', 'Refuerzan los hoyos de los rayos.'),
    ('rim_internal_width_mm', 'Ancho interno', 'Define qué anchos de neumático le quedan bien.'),
    ('rim_material', 'Material', null),
    ('rim_pad_length_mm', 'Largo de la zapata', null),
    ('rim_pad_stud_type', 'Fijación de la zapata', null),
    ('rim_profile_height_mm', 'Alto del perfil', null),
    ('rim_symmetry', 'Simetría', null),
    ('rim_tubeless_ready', 'Tubeless Ready', 'Se puede usar sin cámara, con líquido sellante.'),
    ('rim_valve_bore_mm', 'Agujero de válvula', null),
    ('rim_wall_type', 'Pared', 'Doble pared: más rígida y resistente.'),
    ('roll_length_m', 'Largo del rollo', null),
    ('rotation_360', 'Gira 360°', null),
    ('rotor_diameter_mm_value', 'Diámetro del disco', null),
    ('rotor_floating', 'Disco flotante', 'Disipa mejor el calor y se deforma menos.'),
    ('rotor_material', 'Material', null),
    ('rotor_mount_type', 'Montaje del disco', 'Debe coincidir con la maza: 6 pernos o Centerlock.'),
    ('rotor_nominal_thickness_mm', 'Espesor', null),
    ('saddle_cutout', 'Canal central', 'Alivia la presión al pedalear.'),
    ('saddle_intended_use', 'Uso', null),
    ('saddle_length_mm', 'Largo', null),
    ('saddle_width_mm', 'Ancho', null),
    ('sealant_volume_ml', 'Sellante', null),
    ('seat_tube_outer_diameter_mm', 'Para tubo de asiento de', null),
    ('seatpost_diameter_mm', 'Diámetro', 'Debe coincidir exactamente con el tubo de asiento del cuadro.'),
    ('seatpost_kind', 'Tipo', null),
    ('seatpost_length_mm', 'Largo', null),
    ('shift_technology', 'Tecnología', null),
    ('shifter_actuation_mode', 'Tipo de cambio', 'Indexado: cada clic es un cambio. Fricción: se ajusta a mano.'),
    ('shifter_control_style', 'Tipo de mando', null),
    ('shifter_indexed_positions', 'Velocidades', null),
    ('shifter_position', 'Lado', null),
    ('shifter_unit_count', 'Mandos incluidos', null),
    ('shim_inner_diameter_mm', 'Para poste de', null),
    ('signal_kind', 'Tipo', null),
    ('smallest_cog_teeth', 'Piñón más chico', null),
    ('sold_as', 'Se vende por', null),
    ('souvenir_kind', 'Tipo', null),
    ('speed_source', 'Mide la velocidad con', null),
    ('spindle_included', 'Incluye eje', null),
    ('spindle_interface', 'Tipo de eje', 'Debe coincidir con las bielas.'),
    ('spindle_length_mm', 'Largo del eje', null),
    ('spoke_gauge_designation', 'Calibre', '14G es el estándar (2 mm); 13G es más grueso y resistente.'),
    ('spoke_head_interface', 'Tipo de rayo', null),
    ('spoke_hole_count', 'Número de rayos', null),
    ('spoke_length_mm', 'Largo del rayo', null),
    ('sprocket_count', 'Velocidades', null),
    ('stanchion_diameter_mm', 'Diámetro de barras', null),
    ('steerer_fit', 'Tubo de dirección', 'Debe coincidir con la dirección del cuadro.'),
    ('steerer_threaded', 'Con hilo', null),
    ('stem_angle_deg', 'Ángulo', null),
    ('stem_kind', 'Tipo', null),
    ('stem_length_mm', 'Largo', null),
    ('storage_capacity_gb', 'Capacidad', null),
    ('strip_material', 'Material', null),
    ('tape_width_mm', 'Ancho', 'Conviene que sea un poco más ancha que el ancho interno del aro.'),
    ('teeth_count', 'Dientes', null),
    ('thread', 'Rosca', null),
    ('tire_bead_type', 'Talón', 'Plegable (kevlar): más liviano y se guarda doblado. Alambre: más económico.'),
    ('tire_etrto', 'Medida ETRTO', 'Medida exacta impresa en el costado: ancho-diámetro en milímetros.'),
    ('tire_tpi', 'TPI', 'Hilos por pulgada de la carcasa: más TPI, más flexible y liviano.'),
    ('tire_tubeless_ready', 'Tubeless Ready', 'Se puede usar sin cámara, con líquido sellante.'),
    ('tire_use', 'Uso', null),
    ('tire_weight_g', 'Peso', null),
    ('tire_width_mm', 'Ancho', null),
    ('tool_kind', 'Tipo de herramienta', null),
    ('travel_mm', 'Recorrido', null),
    ('tube_fit_rows', 'Para neumáticos', 'Revisa la medida impresa en el costado de tu neumático.'),
    ('tube_has_sealant', 'Con líquido antipinchazos', null),
    ('tube_material', 'Material', null),
    ('valve_heads_supported', 'Válvulas', null),
    ('valve_length_mm_value', 'Largo de la válvula', 'En aros de perfil alto conviene una válvula más larga.'),
    ('valve_standard', 'Válvula', 'Presta es la delgada (francesa); Schrader, la de auto.'),
    ('volume_l', 'Capacidad', null),
    ('volume_ml', 'Contenido', null),
    ('washer_thickness_mm', 'Espesor', null),
    ('waterproof_claim', 'Impermeable', null),
    ('weight_g', 'Peso', null),
    ('wheel_position', 'Para rueda', null);

create temporary table _store_field_words(template_key text, key text, label text not null,
  primary key (template_key, key)) on commit drop;
insert into _store_field_words(template_key, key, label) values
    ('chain_link', 'chain_speeds', 'Velocidades de la cadena'),
    ('handlebar', 'bar_clamp_diameter_mm', 'Diámetro central'),
    ('stem', 'bar_clamp_diameter_mm', 'Para manubrio de'),
    ('bottle', 'volume_ml', 'Capacidad');

create temporary table _store_highlights(template_key text, key text, rank smallint not null,
  primary key (template_key, key)) on commit drop;
insert into _store_highlights(template_key, key, rank) values
    ('tube', 'tube_fit_rows', 1),
    ('tube', 'valve_standard', 2),
    ('tube', 'valve_length_mm_value', 3),
    ('tube', 'tube_has_sealant', 4),
    ('tire', 'bead_seat_diameter_mm', 1),
    ('tire', 'tire_width_mm', 2),
    ('tire', 'tire_use', 3),
    ('tire', 'tire_bead_type', 4),
    ('tire', 'tire_tubeless_ready', 5),
    ('tire', 'tire_tpi', 6),
    ('spoke', 'spoke_length_mm', 1),
    ('spoke', 'spoke_gauge_designation', 2),
    ('spoke', 'spoke_head_interface', 3),
    ('spoke', 'pack_quantity', 4),
    ('spoke', 'nipples_included', 5),
    ('hub', 'hub_package_position', 1),
    ('hub', 'spoke_hole_count', 2),
    ('hub', 'hub_axle_mount_kind', 3),
    ('hub', 'hub_rotor_mount_present', 4),
    ('hub', 'hub_drive_receiver_kind', 5),
    ('hub', 'hub_old_mm', 6),
    ('brake_pad', 'braking_surface', 1),
    ('brake_pad', 'compound_type', 2),
    ('brake_pad', 'rim_pad_length_mm', 3),
    ('brake_pad', 'rim_pad_stud_type', 4),
    ('workshop_tool', 'tool_kind', 1),
    ('workshop_tool', 'chain_tool_speeds', 2),
    ('rim', 'bead_seat_diameter_mm', 1),
    ('rim', 'spoke_hole_count', 2),
    ('rim', 'rim_internal_width_mm', 3),
    ('rim', 'rim_wall_type', 4),
    ('rim', 'rim_tubeless_ready', 5),
    ('rim', 'rim_material', 6),
    ('rear_derailleur', 'derailleur_cage_length', 1),
    ('rear_derailleur', 'rear_derailleur_mount_type', 2),
    ('rear_derailleur', 'derailleur_clutch', 3),
    ('bottom_bracket', 'spindle_length_mm', 1),
    ('bottom_bracket', 'spindle_interface', 2),
    ('bottom_bracket', 'includes_spindle', 3),
    ('shifter', 'shifter_indexed_positions', 1),
    ('shifter', 'shifter_position', 2),
    ('shifter', 'shifter_control_style', 3),
    ('shifter', 'shifter_actuation_mode', 4),
    ('chain', 'chain_speeds', 1),
    ('chain', 'link_count', 2),
    ('chain', 'chain_width_family', 3),
    ('chain', 'quick_link_included', 4),
    ('rider_glove', 'finger_length', 1),
    ('rider_glove', 'padding', 2),
    ('rider_glove', 'glove_intended_use', 3),
    ('cassette', 'sprocket_count', 1),
    ('cassette', 'smallest_cog_teeth', 2),
    ('cassette', 'largest_cog_teeth', 3),
    ('cassette', 'cassette_spline_standard', 4),
    ('pedal', 'pedal_type', 1),
    ('pedal', 'body_material', 2),
    ('pedal', 'pedal_thread_standard', 3),
    ('pedal', 'replaceable_pins', 4),
    ('crankset', 'crank_arm_length_mm', 1),
    ('crankset', 'included_chainring_count', 2),
    ('crankset', 'crankset_construction', 3),
    ('crankset', 'chainring_mounting', 4),
    ('lock', 'lock_kind', 1),
    ('lock', 'locking_mechanism', 2),
    ('lock', 'cable_diameter_mm', 3),
    ('freewheel', 'sprocket_count', 1),
    ('freewheel', 'smallest_cog_teeth', 2),
    ('freewheel', 'largest_cog_teeth', 3),
    ('workshop_chemical', 'chemical_kind', 1),
    ('workshop_chemical', 'volume_ml', 2),
    ('workshop_chemical', 'container', 3),
    ('workshop_chemical', 'biodegradable_claim', 4),
    ('grip', 'grip_attachment', 1),
    ('grip', 'grip_length_mm', 2),
    ('grip', 'intended_rider', 3),
    ('fastener', 'fastener_kind', 1),
    ('fastener', 'thread', 2),
    ('fastener', 'length_mm', 3),
    ('fastener', 'declared_purpose', 4),
    ('saddle', 'saddle_intended_use', 1),
    ('saddle', 'saddle_cutout', 2),
    ('saddle', 'saddle_width_mm', 3),
    ('saddle', 'saddle_length_mm', 4),
    ('hub_axle', 'wheel_position', 1),
    ('hub_axle', 'axle_length_mm', 2),
    ('hub_axle', 'axle_hollow', 3),
    ('hub_axle', 'cones_and_locknuts_included', 4),
    ('front_derailleur', 'front_derailleur_cable_pull', 1),
    ('front_derailleur', 'front_derailleur_swing', 2),
    ('front_derailleur', 'front_derailleur_mount_type', 3),
    ('light', 'light_position', 1),
    ('light', 'lumens_claimed', 2),
    ('rotor', 'rotor_diameter_mm_value', 1),
    ('rotor', 'rotor_mount_type', 2),
    ('rotor', 'rotor_floating', 3),
    ('rotor', 'rotor_material', 4),
    ('chainring', 'teeth_count', 1),
    ('chainring', 'chainring_bcd_mm', 2),
    ('chainring', 'narrow_wide', 3),
    ('chainring', 'chainring_position', 4),
    ('stem', 'stem_length_mm', 1),
    ('stem', 'bar_clamp_diameter_mm', 2),
    ('stem', 'stem_angle_deg', 3),
    ('stem', 'material', 4),
    ('handlebar', 'bar_width_mm', 1),
    ('handlebar', 'bar_clamp_diameter_mm', 2),
    ('handlebar', 'bar_rise_mm', 3),
    ('handlebar', 'bar_style', 4),
    ('seatpost', 'seatpost_diameter_mm', 1),
    ('seatpost', 'seatpost_length_mm', 2),
    ('seatpost', 'material', 3),
    ('seat_clamp', 'seat_tube_outer_diameter_mm', 1),
    ('seat_clamp', 'clamp_kind', 2),
    ('seat_clamp', 'material', 3),
    ('helmet', 'helmet_kind', 1),
    ('helmet', 'intended_audience', 2),
    ('helmet', 'adjustable_fit', 3),
    ('brake_caliper', 'brake_actuation', 1),
    ('brake_caliper', 'brake_position', 2),
    ('brake_caliper', 'caliper_mount_interface', 3),
    ('brake_lever', 'brake_actuation', 1),
    ('brake_lever', 'lever_cable_pull', 2),
    ('brake_lever', 'lever_side', 3),
    ('brake_lever', 'reach_adjust', 4),
    ('pump', 'pump_kind', 1),
    ('pump', 'gauge', 2),
    ('pump', 'valve_heads_supported', 3),
    ('fork', 'fork_kind', 1),
    ('fork', 'travel_mm', 2),
    ('fork', 'axle_type', 3),
    ('fork', 'steerer_fit', 4),
    ('fork', 'lockout', 5),
    ('chain_link', 'chain_speeds', 1),
    ('chain_link', 'chain_connector_type', 2),
    ('chain_link', 'chain_link_pack_qty', 3),
    ('chain_link', 'chain_link_reusable', 4),
    ('tubeless_tape', 'tape_width_mm', 1),
    ('tubeless_tape', 'roll_length_m', 2),
    ('tubeless_valve', 'valve_standard', 1),
    ('tubeless_valve', 'valve_length_mm_value', 2),
    ('tubeless_valve', 'pack_quantity', 3),
    ('crank_arm', 'crank_side', 1),
    ('crank_arm', 'crank_arm_length_mm', 2),
    ('rider_bag', 'bag_kind', 1),
    ('rider_bag', 'volume_l', 2),
    ('rider_bag', 'waterproof_claim', 3),
    ('accessory_mount', 'accessory_mount_kind', 1),
    ('accessory_mount', 'rotation_360', 2),
    ('tube_repair', 'repair_kind', 1),
    ('tube_repair', 'patch_count', 2),
    ('hub_small_part', 'hub_part_kind', 1),
    ('hub_small_part', 'wheel_position', 2),
    ('audible_signal', 'signal_kind', 1),
    ('audible_signal', 'loudness_db_claim', 2),
    ('bearing', 'bearing_application', 1),
    ('bearing', 'bearing_supply_form', 2),
    ('bearing', 'ball_diameter_in', 3);

create temporary table _store_options(key text, label text, display_label text not null,
  primary key (key, label)) on commit drop;
insert into _store_options(key, label, display_label) values
    ('spoke_head_interface', 'J-Bend', 'Con codo (J-bend)'),
    ('spoke_head_interface', 'Straight Pull', 'Recto (straight pull)'),
    ('hub_spoke_head_interface', 'J-Bend', 'Con codo (J-bend)'),
    ('hub_spoke_head_interface', 'Straight Pull', 'Recto (straight pull)'),
    ('spoke_bend_type', 'J-Bend', 'Con codo (J-bend)'),
    ('spoke_bend_type', 'Straight Pull', 'Recto (straight pull)'),
    ('front_derailleur_pull_direction', 'Top pull', 'Tiro arriba (top pull)'),
    ('front_derailleur_pull_direction', 'Down pull', 'Tiro abajo (down pull)'),
    ('front_derailleur_pull_direction', 'Dual pull', 'Doble tiro (dual pull)'),
    ('rear_derailleur_mount_type', 'Pata/postiza estándar', 'En la postiza (estándar)'),
    ('rear_derailleur_mount_type', 'Con uña / claw', 'Con uña (claw)'),
    ('chain_width_family', '1/8', '1/8"'),
    ('chain_width_family', '3/32', '3/32"'),
    ('chain_width_family', '11/128', '11/128"'),
    ('shift_technology', 'HYPERGLIDE', 'Hyperglide'),
    ('shift_technology', 'HYPERGLIDE+', 'Hyperglide+'),
    ('shift_technology', 'LINKGLIDE', 'Linkglide'),
    ('cassette_spline_standard', 'Shimano MICRO SPLINE (MTB 12v)', 'Shimano Micro Spline (MTB 12v)'),
    ('target_rear_drive_interface', 'Shimano MICRO SPLINE (MTB 12v)', 'Shimano Micro Spline (MTB 12v)');

-- Lo que falta en una base local con el catálogo de antes sólo avisa; una
-- opción repetida detiene todo. El read-back exige todo en producción.
do $guard$
declare r record; v_count integer;
begin
  for r in select w.key from _store_words w
    where not exists (select 1 from public.spec_definitions d where d.tenant_id is null and d.key = w.key) loop
    raise notice 'La definición % no existe aquí', r.key;
  end loop;
  for r in select x.template_key, x.key from (
      select template_key, key from _store_field_words
      union select template_key, key from _store_highlights) x
    where not exists (
      select 1 from public.spec_template_fields f
      join public.spec_templates t on t.id = f.template_id and t.tenant_id is null
      join public.spec_definitions d on d.id = f.spec_definition_id and d.tenant_id is null
      where t.key = x.template_key and d.key = x.key) loop
    raise notice 'La ficha % no tiene el campo % aquí', r.template_key, r.key;
  end loop;
  for r in select * from _store_options loop
    select count(*) into v_count
      from public.spec_definition_values v
      join public.spec_definitions d on d.id = v.spec_definition_id
     where d.tenant_id is null and d.key = r.key and v.tenant_id is null and v.label = r.label;
    if v_count > 1 then
      raise exception 'La opción % de % está % veces', r.label, r.key, v_count;
    elsif v_count = 0 then
      raise notice 'La opción % de % no existe aquí', r.label, r.key;
    end if;
  end loop;
end $guard$;

update public.spec_definitions d
   set store_label = w.label, store_hint = w.hint, updated_at = now()
  from _store_words w
 where d.tenant_id is null and d.key = w.key
   and (d.store_label is distinct from w.label or d.store_hint is distinct from w.hint);

update public.spec_template_fields f
   set store_label = w.label, updated_at = now()
  from _store_field_words w, public.spec_templates t, public.spec_definitions d
 where t.id = f.template_id and t.tenant_id is null and t.key = w.template_key
   and d.id = f.spec_definition_id and d.tenant_id is null and d.key = w.key
   and f.store_label is distinct from w.label;

update public.spec_template_fields f
   set store_highlight = h.rank, updated_at = now()
  from _store_highlights h, public.spec_templates t, public.spec_definitions d
 where t.id = f.template_id and t.tenant_id is null and t.key = h.template_key
   and d.id = f.spec_definition_id and d.tenant_id is null and d.key = h.key
   and f.store_highlight is distinct from h.rank;

update public.spec_definitions
   set is_customer_visible = false, updated_at = now()
 where tenant_id is null and is_customer_visible
   and key in ('published_variant_label', 'rear_derailleur_supplied_adapter_reference', 'rim_joint_designation');

update public.spec_definition_values v
   set display_label = o.display_label, updated_at = now()
  from _store_options o, public.spec_definitions d
 where d.id = v.spec_definition_id and d.tenant_id is null and d.key = o.key
   and v.tenant_id is null and v.label = o.label
   and v.display_label is distinct from o.display_label;

-- La ficha pública: el nombre de tienda, su explicación y el orden entre lo
-- esencial. Cambia la forma de la tabla, así que se recrea con sus permisos.
drop function if exists public.get_public_product_technical_specs(uuid, uuid);
CREATE FUNCTION public.get_public_product_technical_specs(p_tenant_id uuid, p_product_id uuid)
 RETURNS TABLE(section_key text, section_sort_order integer, field_sort_order integer, spec_key text, spec_label text, display_value text, unit text, data_type text, spec_hint text, highlight_rank integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
  with visible as (
    select p.id,p.brand,p.model,p.manufacturer_sku,p.spec_reference_id,t.id template_id,t.form_contract
    from public.products p
    join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
    join public.spec_templates t on t.id=b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id=p.tenant_id)
    where p.id=p_product_id and p.tenant_id=p_tenant_id and coalesce(p.is_active,true)
      and coalesce(p.is_published,false) and coalesce(p.show_on_website,false)
  ), facts as (
    select p.*,public.spec_active_product_values_internal_v1(p.id,p.template_id) vals from visible p
  ), assessed as (select p.*,public.spec_validate_draft_internal_v1(p.template_id,p.vals,p.spec_reference_id,p.brand,p.model,p.manufacturer_sku) issues from facts p
  ), fields as (
    select f.section_key,f.sort_order,d.id definition_id,d.key,
      coalesce(nullif(btrim(f.store_label),''),nullif(btrim(d.store_label),''),p.form_contract->'labels'->>d.key,d.label) label,
      nullif(btrim(d.store_hint),'') hint,f.store_highlight,
      d.unit,d.data_type,d.validation_rules,p.form_contract,p.vals,p.vals->d.key val,min(f.sort_order) over(partition by f.section_key) section_order
    from assessed p join public.spec_template_fields f on f.template_id=p.template_id
    join public.spec_definitions d on d.id=f.spec_definition_id and d.is_customer_visible
    where coalesce(p.form_contract->'roles'->>d.key,'primary') <> 'legacy'
      and public.spec_rule_known_internal_v1(p.vals->d.key)
      -- Pending inference is retained in the editor, not asserted by the storefront.
      -- Confirmation and source are distinct: other origins keep their existing policy.
      and not exists (
        select 1 from public.spec_facts observed
        where observed.tenant_id=p_tenant_id and observed.subject_type='product'
          and observed.subject_id=p.id and observed.subject_scope is null
          and observed.spec_definition_id=d.id
          and observed.source='inferred' and not coalesce(observed.confirmed,false)
      )
      and not exists(select 1 from jsonb_array_elements(p.issues) i where coalesce((i->>'blocking')::boolean,true) and i->>'field' in ('',d.key))
  )
  select f.section_key,dense_rank() over(order by f.section_order,f.section_key)::integer,
    f.sort_order,f.key,f.label,case
      when f.data_type='json' and f.validation_rules ? 'rows_schema' then public.spec_rows_display_internal_v1(f.validation_rules->'rows_schema',public.spec_coherence_display_rows_internal_v1(f.val,public.spec_coherence_labels_internal_v1(f.key,f.form_contract,f.vals)))
      when jsonb_typeof(f.val)='array' then (select string_agg(public.spec_option_display_internal_v1(f.definition_id,e,p_tenant_id),', ' order by n) from jsonb_array_elements_text(f.val) with ordinality a(e,n))
      when jsonb_typeof(f.val)='boolean' then case when f.val='true'::jsonb then 'Sí' else 'No' end
      when f.data_type='single_select' then public.spec_option_display_internal_v1(f.definition_id,f.val#>>'{}',p_tenant_id)
      else f.val#>>'{}' end,f.unit,f.data_type,f.hint,f.store_highlight::integer
  from fields f order by f.section_order,f.sort_order,f.label
$function$;
revoke all on function public.get_public_product_technical_specs(uuid, uuid) from public;
grant execute on function public.get_public_product_technical_specs(uuid, uuid) to anon, authenticated, service_role;

-- Los filtros del catálogo nombran el dato como la ficha pública. Sólo el
-- nombre de la definición: uno por ficha partiría un mismo filtro en dos.
create or replace function public.spec_public_facet_values_internal_v1(p_tenant_id uuid)
returns table(product_id uuid, spec_key text, spec_label text, data_type text, unit text, value_text text)
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  with bound as (
    -- Facts of the product's resolved active template, field not retired,
    -- customer-visible, never an unconfirmed inference.
    select f.id as fact_id, f.subject_id, f.value_number, f.value_boolean, f.value_json,
      d.key, d.label, d.store_label, d.data_type, d.unit, d.is_filterable, d.validation_rules,
      t.form_contract
    from public.spec_facts f
    join public.product_spec_bindings_internal_v1 b on b.product_id = f.subject_id and b.tenant_id = f.tenant_id
    join public.spec_templates t on t.id = b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id = p_tenant_id)
    join public.spec_template_fields tf on tf.template_id = t.id and tf.spec_definition_id = f.spec_definition_id
    join public.spec_definitions d on d.id = f.spec_definition_id and d.is_customer_visible
    where f.tenant_id = p_tenant_id and f.subject_type = 'product' and f.subject_scope is null
      and coalesce(t.form_contract->'roles'->>d.key, 'primary') <> 'legacy'
      and not (f.source = 'inferred' and not coalesce(f.confirmed, false))
  ), scalar as (
    -- Options by label, numbers without trailing zeros, booleans as «Sí»/«No».
    select b.subject_id, b.key,
      coalesce(nullif(btrim(b.store_label), ''), b.form_contract->'labels'->>b.key, b.label) as spec_label,
      b.data_type, b.unit,
      case b.data_type
        when 'number' then trim_scale(b.value_number)::text
        when 'boolean' then case when b.value_boolean then 'Sí' else 'No' end
        else v.label end as value_text
    from bound b
    left join public.spec_fact_values fv on fv.fact_id = b.fact_id
    left join public.spec_definition_values v on v.id = fv.value_id and v.is_active
    where b.is_filterable and b.data_type in ('single_select','number','boolean')
      and (b.data_type <> 'single_select' or v.label is not null)
      and (b.data_type <> 'number' or b.value_number is not null)
      and (b.data_type <> 'boolean' or b.value_boolean is not null)
  ), projected as (
    -- A numeric cell of a rows field named after a global filterable number
    -- field is that field for the visitor (a tube's ISO diameter is «Aro»).
    select b.subject_id, target.key,
      coalesce(nullif(btrim(target.store_label), ''), b.form_contract->'labels'->>target.key, target.label) as spec_label,
      target.data_type, target.unit,
      case when (fit.r->'values'->>(cols.col->>'key')) ~ '^[0-9]+(\.[0-9]+)?$'
        then trim_scale((fit.r->'values'->>(cols.col->>'key'))::numeric)::text end as value_text
    from bound b
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(b.validation_rules->'rows_schema'->'columns') = 'array'
        then b.validation_rules->'rows_schema'->'columns' else '[]'::jsonb end
    ) as cols(col)
    join public.spec_definitions target
      on target.tenant_id is null and target.key = cols.col->>'key'
     and target.data_type = 'number' and target.is_filterable and target.is_customer_visible
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(b.value_json->'rows') = 'array' then b.value_json->'rows' else '[]'::jsonb end
    ) as fit(r)
    where b.data_type = 'json' and cols.col->>'type' in ('integer','decimal','number')
  )
  select subject_id, key, spec_label, data_type, unit, value_text from scalar
  union
  select subject_id, key, spec_label, data_type, unit, value_text from projected where value_text is not null
$$;
revoke all on function public.spec_public_facet_values_internal_v1(uuid) from public, anon, authenticated, service_role;

-- Un filtro guarda la etiqueta de la opción (identidad: enlaces y búsquedas
-- compartidas la citan); el cliente lee su nombre visible.
create or replace function public.get_public_spec_option_labels_v1(p_tenant_id uuid)
returns table(spec_key text, value_label text, display_label text)
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select d.key, v.label, btrim(v.display_label)
  from public.spec_definition_values v
  join public.spec_definitions d on d.id = v.spec_definition_id
  where d.is_customer_visible and v.is_active
    and nullif(btrim(v.display_label), '') is not null
    and (d.tenant_id is null or d.tenant_id = p_tenant_id)
    and (v.tenant_id is null or v.tenant_id = p_tenant_id)
  order by d.key, v.label
$$;
revoke all on function public.get_public_spec_option_labels_v1(uuid) from public;
grant execute on function public.get_public_spec_option_labels_v1(uuid) to anon, authenticated, service_role;

commit;
