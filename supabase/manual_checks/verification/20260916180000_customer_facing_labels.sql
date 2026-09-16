-- Verifier: fails (division by zero) until every customer-facing label is in place.
select 1/(case when (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_hole_count' and label='Hoyos para rayos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_package_position' and label='Posición de la maza')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_old_mm' and label='Ancho de la maza (OLD)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_axle_diameter_mm' and label='Diámetro del eje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_drive_receiver_kind' and label='Núcleo (tipo de piñón)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_axle_mount_kind' and label='Tipo de eje (cierre rápido o pasante)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_rotor_mount_present' and label='Para freno de disco')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_drive_receiver_present' and label='Lleva núcleo o piñón (maza trasera)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_spoke_head_interface' and label='Tipo de rayo (J-bend o straight pull)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_system' and label='Rodamientos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_length_mm' and label='Largo del rayo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_head_interface' and label='Tipo de cabeza (J-bend o straight pull)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_material_declared' and label='Material')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_material' and label='Material')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_wall_type' and label='Pared (simple o doble)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_joint_designation' and label='Unión de la llanta')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bead_seat_diameter_mm' and label='Diámetro ISO (BSD)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='wheel_position' and label='Posición')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='axle_length_mm' and label='Largo del eje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='valve_standard' and label='Tipo de válvula')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tube_has_sealant' and label='Con líquido antipinchazos (sellante)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tire_bead_type' and label='Talón (alambre o plegable)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tire_width_mm' and label='Ancho')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tire_use' and label='Uso')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tire_tpi' and label='TPI (densidad de la carcasa)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='sealant_volume_ml' and label='Volumen de sellante')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='sprocket_count' and label='Velocidades')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chain_speeds' and label='Velocidades')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='shifter_indexed_positions' and label='Velocidades')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chain_width_family' and label='Ancho de cadena (1/8, 3/32)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chain_outer_width_mm' and label='Ancho externo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chain_pitch_mm' and label='Paso')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='link_count' and label='Eslabones')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chain_connector_type' and label='Tipo de conector')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chain_link_reusable' and label='Reutilizable')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chain_directional' and label='Con sentido de montaje (direccional)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='derailleur_clutch' and label='Con clutch (embrague)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='derailleur_cage_length' and label='Largo de pata (caja)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rear_derailleur_supplied_mount_adapter' and label='Incluye uña (adaptador de montaje)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='front_derailleur_cable_pull' and label='Tiro del cable')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='front_derailleur_mount_type' and label='Montaje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='front_derailleur_swing' and label='Tipo (top swing o down swing)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='shifter_position' and label='Lado (izquierdo o derecho)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='shifter_actuation_mode' and label='Accionamiento (indexado o fricción)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='shifter_unit_count' and label='Manillas incluidas')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='teeth_count' and label='Dientes')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_bcd_mm' and label='BCD (patrón de pernos)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_package_kind' and label='Presentación')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_set_member_count' and label='Platos en el juego')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crank_arm_length_mm' and label='Largo de biela')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crankset_construction' and label='Tipo (una, dos o tres piezas)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_mounting' and label='Montaje de los platos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='included_chainring_count' and label='Platos incluidos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bottom_bracket_included' and label='Incluye motor (pedalier)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crank_fixing_bolt_included' and label='Incluye perno de biela')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crankset_chain_guard_included' and label='Incluye cubrecadena')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crank_arm_unit_count' and label='Bielas incluidas')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spindle_length_mm' and label='Largo del eje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spindle_diameter_mm' and label='Diámetro del eje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='cassette_spline_standard' and label='Núcleo (estriado)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='shift_technology' and label='Tecnología (HG, Linkglide, Eagle…)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='remover_tool_standard' and label='Extractor compatible')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pulley_package_kind' and label='Presentación')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='braking_surface' and label='Freno (disco o llanta)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='brake_actuation' and label='Accionamiento (mecánico o hidráulico)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rotor_diameter_mm_value' and label='Diámetro del disco')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rotor_material' and label='Material')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rotor_floating' and label='Disco flotante')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rotor_nominal_thickness_mm' and label='Espesor (disco nuevo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rotor_mount_type' and label='Montaje (6 pernos o Centerlock)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rotor_wear_limit_mm' and label='Límite de desgaste')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_pad_length_mm' and label='Largo del patín')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_pad_construction' and label='Tipo de patín')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lever_side' and label='Lado')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='piston_count_value' and label='Pistones')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='max_rotor_mm' and label='Disco máximo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_clamp_diameter_mm' and label='Diámetro del manubrio (abrazadera)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_width_mm' and label='Ancho')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_style' and label='Tipo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_construction' and label='Tipo (separado o integrado)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='stem_length_mm' and label='Largo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_length_mm' and label='Largo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_diameter_mm' and label='Diámetro')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='saddle_intended_use' and label='Uso')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='saddle_rail_material' and label='Material de los rieles')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lockout' and label='Con bloqueo (lockout)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fork_crown_layout' and label='Coronas (simple o doble)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pedal_thread_standard' and label='Rosca')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='body_material' and label='Material')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='sold_as' and label='Se vende por')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='light_position' and label='Posición')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lumens_claimed' and label='Lúmenes')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='modes_count' and label='Modos de luz')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='locking_mechanism' and label='Cierre (llave o clave)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='keys_included' and label='Llaves incluidas')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='helmet_kind' and label='Uso')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='oem_size_label' and label='Talla')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rotational_protection_claimed' and label='Con protección rotacional (MIPS u otro)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='intended_audience' and label='Para (adulto o niño)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='glove_intended_use' and label='Uso')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='touchscreen' and label='Compatible con pantalla táctil')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fabric_composition_text' and label='Composición')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fit_cut' and label='Corte')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='certification_claim_text' and label='Certificación')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pack_quantity' and label='Unidades por pack')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='units_per_pack' and label='Unidades por pack')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='patch_count' and label='Parches')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='plug_count' and label='Mechas')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='toluene_free' and label='Sin tolueno')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='biodegradable_claim' and label='Biodegradable')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='declared_applications' and label='Usos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='declared_purpose' and label='Uso')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='head_drive' and label='Tipo de cabeza (allen, torx…)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='thread' and label='Rosca')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='strength_class_claim' and label='Grado')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='max_tire_width_mm' and label='Ancho máximo de neumático')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='max_bike_weight_kg' and label='Peso máximo de la bici')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='mount_bolt_count' and label='Pernos de montaje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='kickstand_mount_standard' and label='Montaje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='functions_count' and label='Funciones')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='caffeine_mg' and label='Cafeína')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='interchangeable_lenses' and label='Lentes adicionales')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='uv_protection_claim' and label='Protección UV')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rated_power_w' and label='Potencia')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='ports_count' and label='Puertos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='combined_control_declared_units' and label='Mandos incluidos')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='hub_drive_receiver_kind' and v.label='Núcleo estriado de cassette')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='hub_drive_receiver_kind' and v.label='Rosca para rueda libre')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='hub_drive_receiver_kind' and v.label='Rosca para piñón fijo y contratuerca')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='hub_drive_receiver_kind' and v.label='Otra interfaz OEM')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='bearing_system' and v.label='Rodamientos sellados')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='derailleur_cage_length' and v.label='SS / corta')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='derailleur_cage_length' and v.label='GS / media')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='derailleur_cage_length' and v.label='SGS / larga')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='locking_mechanism' and v.label='Combinación')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='locking_mechanism' and v.label='Llave + combinación')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='front_derailleur_cable_pull' and v.label='Top pull')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='front_derailleur_cable_pull' and v.label='Down pull')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='front_derailleur_cable_pull' and v.label='Dual pull')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='crankset_construction' and v.label='Una pieza (americana / Ashtabula)')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='crankset_construction' and v.label='Dos piezas (eje solidario al brazo derecho)')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='crankset_construction' and v.label='Tres piezas (eje independiente)')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='compound_type' and v.label='Orgánico')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='bar_style' and v.label='Recto')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='valve_standard' and v.label='Presta (francesa)')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='valve_standard' and v.label='Schrader (americana / auto)')=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='hub_drive_receiver_kind' and v.label='Núcleo de cassette')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='hub_drive_receiver_kind' and v.label='Rosca para piñón (rueda libre)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='hub_drive_receiver_kind' and v.label='Rosca para piñón fijo')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='hub_drive_receiver_kind' and v.label='Otro')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='bearing_system' and v.label='Sellados')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='derailleur_cage_length' and v.label='Corta (SS)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='derailleur_cage_length' and v.label='Media (GS)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='derailleur_cage_length' and v.label='Larga (SGS)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='locking_mechanism' and v.label='Clave (combinación)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='locking_mechanism' and v.label='Llave y clave')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='front_derailleur_cable_pull' and v.label='Tiro arriba (top pull)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='front_derailleur_cable_pull' and v.label='Tiro abajo (down pull)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='front_derailleur_cable_pull' and v.label='Doble tiro (dual pull)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='crankset_construction' and v.label='Una pieza (americana)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='crankset_construction' and v.label='Dos piezas (integrado)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='crankset_construction' and v.label='Tres piezas (motor aparte)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='compound_type' and v.label='Orgánico (resina)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='bar_style' and v.label='Recto (plano)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='valve_standard' and v.label='Francesa (Presta)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='valve_standard' and v.label='Auto (Schrader / americana)')=1 then 1 else 0 end) as customer_labels_ok;
