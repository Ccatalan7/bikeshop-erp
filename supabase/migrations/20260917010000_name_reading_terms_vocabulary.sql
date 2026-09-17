-- Términos de lectura: segunda tanda de vocabulario de tienda.
--
-- Al escribir las reglas por familia para la segunda pasada de nombres
-- (2026-09-17) aparecieron palabras que las etiquetas no pueden reconocer y
-- que el catálogo usa todo el tiempo: «DER.» e «IZQ.» en las manillas,
-- «d/pared» en las llantas, «1-1/8» en las horquillas, «apernar» y «directo»
-- en los cambios, «6 vel / 8v / 10s» en las cadenas, las fracciones de las
-- bolitas («1/4», «3/16») que se normalizan a números sueltos de un carácter y
-- no cuentan para la etiqueta, «prostático» en los sillines. Son datos de las
-- definiciones globales, igual que la primera tanda; se suman a lo que ya hay
-- sin borrar nada.

-- opciones: se agregan términos (sin duplicar) a la opción exacta.
with terms(def_key, option_label, phrases) as (
  values
  ('hub_package_position', 'Juego (delantera y trasera)', array['jgo','juego','par','set','mazas jgo','mazas']),
  ('hub_package_position', 'Delantera', array['front','del']),
  ('hub_package_position', 'Trasera', array['rear','tras']),
  ('hub_axle_mount_kind', 'Eje con tuercas', array['eje 3 8','3 8']),
  ('hub_drive_receiver_kind', 'Driver BMX', array['driver','9t','driver bmx']),
  ('rim_pad_stud_type', 'Espárrago roscado', array['con tuerca','con tuercas','c tuerca','tuerca','tuerca allen']),
  ('rim_pad_stud_type', 'Poste liso', array['vastago','con vastago','c vastago']),
  ('ball_diameter_in', '1/8', array['1 8']),
  ('ball_diameter_in', '5/32', array['5 32']),
  ('ball_diameter_in', '3/16', array['3 16']),
  ('ball_diameter_in', '7/32', array['7 32']),
  ('ball_diameter_in', '1/4', array['1 4']),
  ('bb_ball_size_in', '1/8', array['1 8']),
  ('bb_ball_size_in', '5/32', array['5 32']),
  ('bb_ball_size_in', '3/16', array['3 16']),
  ('bb_ball_size_in', '1/4', array['1 4']),
  ('grip_attachment', 'Lock-on (una abrazadera)', array['un solo lado','en un solo lado']),
  ('rim_wall_type', 'Doble pared', array['d pared','doble']),
  ('rim_wall_type', 'Pared simple', array['simple','pared simple']),
  ('steerer_fit', '1 1/8" (28.6 mm)', array['1 1 8','28 6']),
  ('steerer_fit', '1" (25.4 mm)', array['25 4']),
  ('steerer_fit', '1 1/4" (31.8 mm)', array['1 1 4','31 8']),
  ('steerer_fit', '1.5" (38.1 mm)', array['1 5','38 1']),
  ('steerer_fit', 'Tapered 1 1/8" – 1.5"', array['tapered','conica','conico','taper']),
  ('drivetrain_mode', 'Derailleur', array['6 speed','7 speed','8 speed','9 speed','10 speed','11 speed','12 speed','6vel','7vel','8vel','9vel','10vel','11vel','12vel','6v','7v','8v','9v','10v','11v','12v','6s','7s','8s','9s','10s','11s','12s','6speed','7speed','8speed','9speed','10speed','11speed','12speed']),
  ('drivetrain_mode', 'Single speed / BMX / IGH', array['1 velocidad','single','fixed']),
  ('chain_width_family', '1/8', array['1 8']),
  ('chain_width_family', '3/32', array['3 32']),
  ('chain_width_family', '11/128', array['11 128']),
  ('rotor_mount_type', '6 pernos', array['con tornillos','6 tornillos']),
  ('rear_derailleur_mount_type', 'Con uña / claw', array['apernar','apernado','con pata','c pata','riveted adapter','w riveted adapter','con garra']),
  ('rear_derailleur_mount_type', 'Pata/postiza estándar', array['direct attachment','directo','s pata','sin pata']),
  ('shifter_control_style', 'Gatillo (trigger)', array['rapidfire','rapid fire']),
  ('shifter_control_style', 'Integrado con la maneta de freno', array['integrado','integrada','sti']),
  ('shifter_position', 'Derecho (trasero)', array['der','right','rear','tras']),
  ('shifter_position', 'Izquierdo (delantero)', array['izq','left','front']),
  ('shifter_actuation_mode', 'Fricción', array['friction']),
  ('shifter_actuation_mode', 'Indexado', array['sincronizado','sincronizada','index','sis']),
  ('crankset_construction', 'Tres piezas (motor aparte)', array['pta cuad','pta cuadrada','punta cuadrada','p eje','para eje']),
  ('chainring_mounting', 'Platos desmontables por pernos', array['desmontable','desmontables']),
  ('tool_kind', 'Multiherramienta', array['en 1','x 1','multifuncional','multi herramienta']),
  ('tool_kind', 'Extractor de biela', array['extractor de volante','extractor volante']),
  ('tool_kind', 'Desmontador de neumático', array['desmontador','desmontadores']),
  ('tool_kind', 'Corta cadena', array['cortacadenas','corta cadenas']),
  ('tool_kind', 'Juego de llaves Allen', array['llavero allen','llaves allen','llave allen set','allen']),
  ('tool_kind', 'Extractor de cono de dirección', array['extractor cono']),
  ('tool_kind', 'EPP (guantes de taller)', array['guante','guantes','nitrilo']),
  ('tool_kind', 'Guía de cableado interno', array['guia cableado interno','cableado interno']),
  ('saddle_intended_use', 'Niño', array['kids','nina','ninos','ninas','junior','infantil']),
  ('bar_style', 'Urbano / paseo', array['playera','beach','beach cruiser','paseo','city','urbano']),
  ('bar_style', 'Recto (plano)', array['recto','plano','flat']),
  ('lock_kind', 'U-lock', array['ulock','u lock']),
  ('bag_kind', 'Cubre-mochila', array['protector de mochila','protector impermeable de mochila','cubre mochila']),
  ('bag_kind', 'Mochila de hidratación', array['camelbak','hidratacion','hydration']),
  ('accessory_mount_kind', 'Soporte de teléfono', array['celular','telefono','phone']),
  ('front_derailleur_swing', 'Tradicional (top swing)', array['top swing','topswing']),
  ('front_derailleur_swing', 'Down swing', array['down swing','downswing']),
  ('front_derailleur_swing', 'Side swing', array['side swing','sideswing']),
  ('cassette_spline_standard', 'Shimano MICRO SPLINE (MTB 12v)', array['microspline','micro spline']),
  ('pump_kind', 'De mano / mini', array['mano','mini','hand']),
  ('material', 'Acero inoxidable', array['inox','acero inox','inoxidable','stainless']),
  ('rotor_material', 'Acero Inoxidable', array['inox','acero inox','stainless']),
  ('brake_presentation', 'Par delantero y trasero', array['delantero y trasero','del y tras','juego de frenos']),
  ('light_position', 'Juego (delantera y trasera)', array['juego','set','kit','par']),
  ('lever_side', 'Izquierda', array['izq','left']),
  ('lever_side', 'Derecha', array['der','right']),
  ('wheel_position', 'Delantera', array['front','del']),
  ('wheel_position', 'Trasera', array['rear','tras']),
  ('brake_position', 'Delantero', array['front','del']),
  ('brake_position', 'Trasero', array['rear','tras']),
  ('fender_position', 'Juego', array['set','par','delantero y trasero']),
  ('bearing_supply_form', 'Cartucho', array['sellado','sellada','2rs']),
  ('consumable_kind', 'Sellante', array['sellador','liquido antipinchazos','seal','liquido tubular']),
  ('control_part_kind', 'Terminal de piola (crimp)', array['terminal de piola','terminal cable','terminal punta piola','terminal piola']),
  ('control_part_kind', 'Fuelle / goma protectora', array['goma','gomita']),
  ('control_part_kind', 'Guía de cable', array['guia','hebilla']),
  ('control_part_kind', 'Regulador de tensión (barril)', array['regulador']),
  ('peg_axle_fit', 'Eje 3/8" (10 mm)', array['3 8']),
  ('peg_axle_fit', 'Eje 14 mm', array['14 mm','14mm']),
  ('carrier_kind', 'Correa / pulpo de carga', array['cuerda bungee','bungee','pulpo']),
  ('covering_kind', 'Funda / espuma tubular', array['cubre manubrio','cubre manillar']),
  ('souvenir_kind', 'Modelo a escala', array['a escala','escala']),
  ('spring_kind', 'Aire', array['air','triair']),
  ('device_kind', 'Tarjeta de memoria', array['memoria sd','memoria','sd']),
  ('speed_source', 'Sensor de rueda (imán / cable)', array['con cable']),
  ('headset_part_kind', 'Araña (star nut)', array['arana']),
  ('signal_kind', 'Bocina electrónica', array['bocina']),
  ('bag_position', 'Triángulo del cuadro', array['triangular','triangulo','marco'])
)
update public.spec_definition_values v
set reading_terms = coalesce((
  select array_agg(distinct x order by x)
  from unnest(v.reading_terms || t.phrases) as u(x)), '{}'::text[])
from terms t, public.spec_definitions d
where d.id = v.spec_definition_id and d.tenant_id is null and d.key = t.def_key
  and v.label = t.option_label and v.is_active is true;

-- booleanos: se agregan términos afirmativos y negativos (sin duplicar).
with terms(def_key, yes, no) as (
  values
  ('nipples_included', array['nipple','niple'], array[]::text[]),
  ('rim_tubeless_ready', array['tl'], array[]::text[]),
  ('rear_derailleur_supplied_mount_adapter', array['riveted adapter','w riveted adapter','con pata','c pata'], array['sin pata','s pata']),
  ('crankset_chain_guard_included', array['c cub','chain case','chaincase'], array['s cubre','s cg']),
  ('saddle_cutout', array['prostatico','prostatica','perforado','perforada'], array[]::text[]),
  ('includes_spindle', array['eje de motor','eje motor','eje sellado','con eje','c eje'], array['hollowtech','integrado','press fit','sin eje']),
  ('adjustable_fit', array['regulador','con regulador','ajustable','regulable'], array[]::text[]),
  ('rotation_360', array['360','giro 360'], array[]::text[]),
  ('dust_cap_included', array['cubrepolvo','cubre polvo','con cubrepolvo','guardapolvo'], array[]::text[]),
  ('waterproof_claim', array['waterproof'], array[]::text[]),
  ('wireless', array['inalambrico','inalambrica','wireless','bluetooth'], array['con cable']),
  ('hub_rotor_mount_present', array['discbul','disc brake'], array[]::text[]),
  ('adjustable_length', array['ajustable'], array[]::text[])
)
update public.spec_definitions d
set reading_terms = coalesce((select array_agg(distinct x order by x) from unnest(d.reading_terms || t.yes) as u(x)), '{}'::text[]),
    reading_terms_false = coalesce((select array_agg(distinct x order by x) from unnest(d.reading_terms_false || t.no) as u(x)), '{}'::text[])
from terms t
where d.tenant_id is null and d.key = t.def_key and d.data_type = 'boolean';
