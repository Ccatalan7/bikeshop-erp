-- Verifier: fails (division by zero) until the second label pass is fully in place.
select 1/(case when (select count(*) from public.spec_definitions where tenant_id is null and key='bar_fit_representation' and label='Ajuste al manubrio (medidas o rango)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='max_load_kg' and label='Carga máxima')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='device_system' and label='Sistema de unión')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='loudness_db_claim' and label='Nivel sonoro')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='signal_kind' and label='Tipo (campanilla o bocina)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='volume_basis' and label='La capacidad incluye')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='volume_l' and label='Capacidad')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='volume_scope' and label='La capacidad corresponde a')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='waterproof_claim' and label='Impermeable')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fits_bike_size' and label='Para bicicletas de')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='detangler_kind' and label='Tipo (gyro)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='steerer_fit' and label='Medida de dirección')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='ball_count_per_pack' and label='Bolitas por pack')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='ball_diameter_in' and label='Tamaño de bolita')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_application' and label='Para (maza, dirección o motor)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_element_retention' and label='Con jaula o sueltas')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_inner_contact_angle_deg' and label='Ángulo del bisel interior')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_outer_contact_angle_deg' and label='Ángulo del bisel exterior')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_inner_diameter_mm' and label='Diámetro interior')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_outer_diameter_mm' and label='Diámetro exterior')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_race_contact_angle_deg' and label='Ángulo de contacto')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_race_type' and label='Tipo (ranura profunda o contacto angular)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_regreasable' and label='Se puede reengrasar')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_row_count' and label='Hileras de bolitas')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_seal_designation' and label='Código del sello (2RS, ZZ…)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_seal_type' and label='Sellado')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_seat_geometry' and label='Biseles de apoyo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_size_code' and label='Código (6902, 6001…)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_supply_form' and label='Presentación')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_width_mm' and label='Ancho')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bb_bearing_width_mm' and label='Ancho del rodamiento')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bb_cup_inner_seat_angle_deg' and label='Ángulo interior del asiento')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bb_cup_outer_seat_angle_deg' and label='Ángulo exterior del asiento')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bb_cup_seat_bevel' and label='Biseles del asiento')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bottle_diameter_mm' and label='Diámetro (para portabotella)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bottle_retention_system' and label='Sujeción (portabotella o Fidlock)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bpa_free_claim' and label='Libre de BPA')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='insulated' and label='Térmica')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='boss_count' and label='Tornillos al cuadro')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='boss_spacing_mm' and label='Separación de tornillos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='cage_mount' and label='Fijación')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='cage_retention_system' and label='Sujeción de la botella')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='frame_tube_width_max_mm' and label='Tubo máximo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='frame_tube_width_min_mm' and label='Tubo mínimo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='side_entry_side' and label='Lado de salida')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spindle_diameter_datum' and label='Dónde se mide el diámetro del eje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spindle_interface' and label='Tipo de eje (cuadrado, Hollowtech…)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='brake_conversion_location' and label='Dónde convierte cable a hidráulico')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='brake_external_hose_connection' and label='Con conexión de manguera externa')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='brake_pad_retainer_model' and label='Pasador de pastilla (modelo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='cable_pull_required' and label='Tiro de cable (largo o corto)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='caliper_mount_interface' and label='Montaje (Post Mount, IS, Flat Mount)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pad_shape_code' and label='Forma de pastilla (código)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_pad_stud_type' and label='Fijación del patín')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tool_size_mm' and label='Medida de llave')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='handlebar_clamp_mm' and label='Diámetro del manubrio (abrazadera)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lever_bar_bore_max_mm' and label='Diámetro interior máximo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lever_bar_bore_min_mm' and label='Diámetro interior mínimo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lever_cable_interface' and label='Anclaje del cable')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lever_cable_pull' and label='Tiro de cable (largo o corto)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lever_control_mount_oem_code' and label='Código de anclaje del mando')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lever_hydraulic_role' and label='Función (principal o auxiliar)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lever_mount_clearance_mm' and label='Espacio recto de manubrio necesario')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lever_mount_method' and label='Fijación al manubrio')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lever_mount_oem_interface' and label='Montaje específico (modelo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='reach_adjust' and label='Alcance regulable')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='shifter_mount_interface' and label='Anclaje para manilla de cambio (I-Spec, MatchMaker)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='brake_pad_oem_compound' and label='Compuesto (nombre del fabricante)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pad_compatibility_note' and label='Compatibilidad (nota)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pad_finned' and label='Con aletas (disipador)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pad_retention' and label='Sujeción (pin, clip o imán)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pad_spring_included' and label='Incluye resorte')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_material_intended' and label='Para llanta de')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_pad_interface_model' and label='Soporte del patín (modelo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='brake_presentation' and label='Presentación (qué incluye)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pad_compound_restriction' and label='Pastillas que admite (resina o metálica)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='published_variant_label' and label='Variante (rango publicado)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spacer_thickness_mm' and label='Espesor')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='target_rear_drive_interface' and label='Para núcleo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chain_other_width_designation' and label='Otra medida de ancho')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='drivetrain_mode' and label='Tipo de transmisión (con cambios o single speed)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chain_guide_chainline_adjustment_mm' and label='Ajuste de línea de cadena')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chain_guide_chainline_datum' and label='Cómo se mide la línea de cadena')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_teeth_max' and label='Plato máximo (dientes)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_teeth_min' and label='Plato mínimo (dientes)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chain_link_pack_qty' and label='Conectores por pack')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='connector_reuse_limit' and label='Usos máximos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_direct_mount_generation' and label='Direct mount (generación)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_mount_type' and label='Montaje (BCD o direct mount)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crank_arm_carries_chainring_mount' and label='Lleva los platos (lado derecho)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crank_arm_spindle_designation' and label='Eje (designación)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crank_arm_system_construction' and label='Tipo de volante (una, dos o tres piezas)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crank_side' and label='Lado')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pedal_thread' and label='Rosca de pedal')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hanger_derailleur_interface' and label='Lado del cambio (rosca o direct mount)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hanger_frame_interface' and label='Lado del cuadro (UDH, puntera…)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hanger_model_code' and label='Código de la pata (postiza)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='extender_declaration_form' and label='Qué declara el extensor')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hanger_interface' and label='Tipo de pata (postiza)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pulley_bearing_construction' and label='Apoyo (buje o rodamiento)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pulley_bearing_element_material' and label='Material de las bolitas')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pulley_bore_diameter_mm' and label='Diámetro del agujero')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pulley_declared_position' and label='Posición (guía o tensión)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pulley_declared_speeds' and label='Velocidades')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pulley_teeth' and label='Dientes')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pulley_tooth_profile' and label='Dentado')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pulley_unit_count' and label='Roldanas incluidas')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pulley_width_mm' and label='Ancho')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='cog_thread_standard' and label='Rosca del piñón')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='single_cog_teeth' and label='Dientes')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='freewheel_thread_standard' and label='Rosca')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='front_derailleur_cable_anchor' and label='Anclaje del cable en el perno')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rear_derailleur_actuation_ratio_declaration' and label='Relación de accionamiento')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rear_derailleur_mount_type' and label='Montaje (pata, direct mount o uña)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rear_derailleur_spring_return' and label='Retorno del resorte (normal o inverso)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rear_derailleur_supplied_adapter_reference' and label='Uña o adaptador incluido (modelo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='shifter_control_style' and label='Tipo de manilla (gatillo, giro…)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='cable_data_capability' and label='Datos del cable (norma y velocidad)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='cable_power_capacity_w' and label='Potencia de carga del cable')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='charging_protocol_claim' and label='Protocolo de carga')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='speed_class_claim' and label='Clase de velocidad')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='storage_capacity_label' and label='Capacidad impresa')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='wireless' and label='Inalámbrico')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='connector_a' and label='Conector (lado 1)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='connector_b' and label='Conector (lado 2)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='control_part_kind' and label='Tipo de pieza')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fits_cable_diameter_mm' and label='Para cable de')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fits_housing_diameter_mm' and label='Para funda de')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='noodle_angle_deg' and label='Ángulo de la guía')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='positioning_source' and label='GPS')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='head_drive_size_mm' and label='Medida de llave (hex)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='length_datum' and label='Cómo se mide el largo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='thread_pitch_system' and label='Paso expresado en')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='thread_tpi' and label='Hilos por pulgada')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='torx_size' and label='Torx (T25…)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='caffeine_basis' and label='Cafeína por')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='ingredients_text' and label='Ingredientes')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='milk_substitution_offered' and label='Se puede cambiar la leche')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='net_mass_g' and label='Peso neto')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='unit_mass_g' and label='Peso por unidad')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='serving_size' and label='Tamaño')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='temperature' and label='Se sirve')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='axle_to_crown_mm' and label='Largo eje a corona')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='brake_mount' and label='Montaje de freno')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crown_race_diameter_mm' and label='Diámetro de pista de corona')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crown_stack_max_mm' and label='Altura máxima entre coronas')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crown_stack_min_mm' and label='Altura mínima entre coronas')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fork_offset_mm' and label='Offset (avance)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='stanchion_diameter_mm' and label='Diámetro de barras')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='steerer_length_mm' and label='Largo del tubo de dirección')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='steerer_threaded' and label='Con hilo (rosca)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='headset_lower_shis' and label='Medida SHIS inferior')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='headset_upper_shis' and label='Medida SHIS superior')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='headset_lower_stack_height_mm' and label='Altura inferior instalada')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='headset_upper_stack_height_mm' and label='Altura superior instalada')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='headset_part_scope' and label='Qué incluye (superior, inferior o completa)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='headset_supplied_crown_race_reference' and label='Pista de corona incluida (modelo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='grip_attachment' and label='Fijación (deslizante o lock-on)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='grip_bar_nominal_diameter_mm' and label='Para manubrio de')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='grip_inner_diameter_mm' and label='Diámetro interior')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='grip_length_mm' and label='Largo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='grip_length_left_mm' and label='Largo (izquierdo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='grip_length_right_mm' and label='Largo (derecho)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='grip_measurement_reference' and label='Cómo se midió')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='grip_straight_length_required_mm' and label='Zona recta de manubrio necesaria')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='grip_straight_length_required_left_mm' and label='Zona recta necesaria (izquierdo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='grip_straight_length_required_right_mm' and label='Zona recta necesaria (derecho)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='intended_rider' and label='Para (adulto o niño)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='accessory_mount_ports_text' and label='Soportes para accesorios')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_backsweep_deg' and label='Backsweep (ángulo hacia atrás)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_drop_mm' and label='Drop')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_reach_mm' and label='Reach')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_rise_mm' and label='Rise (elevación)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_upsweep_deg' and label='Upsweep (ángulo hacia arriba)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_width_drops_mm' and label='Ancho en drops')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_width_hoods_mm' and label='Ancho en manetas')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_width_reference' and label='Cómo se mide el ancho')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='cable_routing' and label='Cableado (interno o externo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='grip_area_diameter_mm' and label='Diámetro en los puños')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='integrated_steerer_clamp_mm' and label='Diámetro de dirección (integrado)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='integrated_stem_angle_deg' and label='Ángulo de la tee integrada')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='integrated_stem_length_mm' and label='Largo de la tee integrada')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='covering_kind' and label='Tipo (cinta o funda)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='quill_adapter_output_diameter_mm' and label='Diámetro de salida (ahead)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='quill_diameter_mm' and label='Diámetro de la espiga')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='quill_min_insertion_mm' and label='Inserción mínima')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='stem_angle_deg' and label='Ángulo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='stem_steerer_clamp_diameter_mm' and label='Diámetro de dirección (abrazadera)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='clamp_kind' and label='Tipo (perno o cierre rápido)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='clamp_thread' and label='Rosca')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='clamp_thread_pitch_mm' and label='Paso de la rosca')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seat_tube_outer_diameter_mm' and label='Para tubo de asiento de')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='dropper_cable_routing' and label='Cableado de la telescópica (interno o externo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='dropper_control_kind' and label='Accionamiento (cable, hidráulico o inalámbrico)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='dropper_remote_model' and label='Mando incluido (modelo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='dropper_travel_mm' and label='Recorrido')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_bottom_clearance_mm' and label='Proyección bajo el largo declarado')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_min_exposed_mm' and label='Mínimo expuesto')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_min_insertion_mm' and label='Inserción mínima')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_offset_mm' and label='Retroceso (offset)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_shim_length_mm' and label='Largo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_shim_mount_instructions' and label='Instrucciones de montaje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_shim_oem_interface' and label='Perfil específico (fabricante)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_shim_shape' and label='Forma')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_shim_support_length_mm' and label='Largo de apoyo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='shim_inner_diameter_mm' and label='Diámetro interior')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='shim_outer_diameter_mm' and label='Diámetro exterior')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='cover_material' and label='Material del forro')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='saddle_cutout' and label='Con canal central')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='saddle_length_mm' and label='Largo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='saddle_mount_model' and label='Anclaje (detalle)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='saddle_rail_geometry' and label='Rieles (redondo 7 mm, oval…)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='saddle_width_mm' and label='Ancho')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fits_saddle_length_max_mm' and label='Para sillín de largo hasta')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fits_saddle_length_min_mm' and label='Para sillín de largo desde')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fits_saddle_width_max_mm' and label='Para sillín de ancho hasta')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='center_to_flange_left_mm' and label='Centro a brida izquierda')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='center_to_flange_right_mm' and label='Centro a brida derecha')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='flange_pcd_left_mm' and label='PCD brida izquierda')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='flange_pcd_right_mm' and label='PCD brida derecha')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_axle_diameter_datum' and label='Dónde se mide el diámetro del eje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_drive_receiver_reference' and label='Núcleo (referencia exacta)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_package_piece_count' and label='Mazas en el juego')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_supplied_thru_axle_reference' and label='Eje pasante incluido (modelo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_hole_diameter_mm' and label='Diámetro del hoyo de rayo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_axle_length_datum' and label='Cómo se mide el largo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_finish_declared' and label='Acabado')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_gauge_designation' and label='Calibre (14G, 15G…)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_head_elbow_angle_deg' and label='Ángulo del codo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_head_oem_designation' and label='Cabeza (referencia del fabricante)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_hub_hole_class_declared' and label='Para hoyo de maza de')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_nipple_thread_present' and label='Con rosca para niple')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_thread_length_mm' and label='Largo de la rosca')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_thread_major_diameter_mm' and label='Diámetro de la rosca')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_thread_nominal_mm' and label='Rosca nominal')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_thread_standard' and label='Rosca (FG 2.3…)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='nipple_thread' and label='Para rayo calibre')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='nipple_thread_standard' and label='Rosca (FG 2.3…)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='brake_track' and label='Con pista de freno (para V-brake)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_asymmetric_offset_mm' and label='Offset asimétrico')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_bead_profile' and label='Gancho (hooked o hookless)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_brake_wear_indicator' and label='Indicador de desgaste')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_erd_datum' and label='Cómo se mide el ERD')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_external_width_mm' and label='Ancho externo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_internal_width_mm' and label='Ancho interno')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_eyelet_type' and label='Ojetillos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_profile_height_mm' and label='Alto del perfil')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_spoke_hole_diameter_mm' and label='Diámetro del hoyo de niple')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_symmetry' and label='Simetría')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_tire_bed_access_hole_mm' and label='Agujero de acceso del fondo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_tubeless_ready' and label='Tubeless ready')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='strip_fit_internal_width_max_mm' and label='Para llanta de ancho interno hasta')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='strip_fit_internal_width_min_mm' and label='Para llanta de ancho interno desde')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='strip_material' and label='Material')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='strip_width_mm' and label='Ancho')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tire_tubeless_ready' and label='Tubeless ready')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tire_weight_g' and label='Peso')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tube_material' and label='Material')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='glue_volume_ml' and label='Pegamento (volumen)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='consumable_kind' and label='Tipo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='sealant_base' and label='Sellante (con o sin látex)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tubeless_tape_application' and label='Instrucciones de aplicación')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='valve_base_shape' and label='Forma de la base')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='axle_nut_thread' and label='Rosca del eje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='included_cleat_model' and label='Calas incluidas (modelo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pedal_intended_rider' and label='Para (adulto o niño)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pedal_thread_other_declaration' and label='Otra rosca (medida completa)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='pedal_wrench_interface' and label='Se monta con (llave o hexágono)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='peg_axle_fit' and label='Para eje de')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='frame_requirement_text' and label='Requisito del cuadro')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='installed_height_max_mm' and label='Altura instalada máxima')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='installed_height_min_mm' and label='Altura instalada mínima')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='kickstand_length_reference' and label='Cómo se mide el largo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='kickstand_mount_kind' and label='Fijación')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='barrel_material' and label='Material del cuerpo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='co2_inflation_capable' and label='También infla con CO₂')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='inflation_target_note' and label='Presión máxima (nota)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='valve_heads_supported' and label='Válvulas que infla')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='carrier_kind' and label='Tipo (parrilla o canasto)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='carrier_mount_kind' and label='Fijación')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='load_reference' and label='La carga máxima se refiere a')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rack_eyelets_required' and label='Necesita ojales en el cuadro')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lock_chain_length_mm' and label='Largo de la cadena')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='shackle_diameter_mm' and label='Grosor del arco')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='inner_height_mm' and label='Alto interior')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='gender_fit' and label='Corte (hombre, mujer, unisex)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='sleeve' and label='Manga')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fits_volume_max_l' and label='Para mochila de hasta')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fits_volume_min_l' and label='Para mochila desde')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='reservoir_l' and label='Capacidad de la bolsa de hidratación')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='finger_length' and label='Dedos (corto o largo)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='padding' and label='Acolchado')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rider_protection_kind' and label='Protege')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='mounting_hardware_included' and label='Incluye bujes de montaje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spring_kind' and label='Tipo (aire o muelle)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='theme' and label='Diseño')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chemical_kind' and label='Tipo de producto')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='not_for' and label='No usar en')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chain_tool_speeds' and label='Velocidades de cadena que admite')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='size_label' and label='Talla')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tool_interface' and label='Encaje (cassette, biela…)')=1
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='rim_eyelet_type' and v.label='Sin ojillos')=0
 and (select count(*) from public.spec_definitions d where d.tenant_id is null and d.key='rim_eyelet_type' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Sin ojillos'::text]))=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='rim_eyelet_type' and v.label='Ojillo simple')=0
 and (select count(*) from public.spec_definitions d where d.tenant_id is null and d.key='rim_eyelet_type' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Ojillo simple'::text]))=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='rim_eyelet_type' and v.label='Doble ojillo')=0
 and (select count(*) from public.spec_definitions d where d.tenant_id is null and d.key='rim_eyelet_type' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Doble ojillo'::text]))=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='tire_bead_type' and v.label='Talón de alambre')=0
 and (select count(*) from public.spec_definitions d where d.tenant_id is null and d.key='tire_bead_type' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Talón de alambre'::text]))=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='tire_bead_type' and v.label='Talón plegable')=0
 and (select count(*) from public.spec_definitions d where d.tenant_id is null and d.key='tire_bead_type' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Talón plegable'::text]))=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='hub_package_position' and v.label='Juego delantera + trasera')=0
 and (select count(*) from public.spec_definitions d where d.tenant_id is null and d.key='hub_package_position' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Juego delantera + trasera'::text]))=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='light_position' and v.label='Juego delantera + trasera')=0
 and (select count(*) from public.spec_definitions d where d.tenant_id is null and d.key='light_position' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Juego delantera + trasera'::text]))=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='chainring_package_kind' and v.label='Plato individual')=0
 and (select count(*) from public.spec_definitions d where d.tenant_id is null and d.key='chainring_package_kind' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Plato individual'::text]))=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='chainring_package_kind' and v.label='Juego de platos en el mismo envase')=0
 and (select count(*) from public.spec_definitions d where d.tenant_id is null and d.key='chainring_package_kind' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Juego de platos en el mismo envase'::text]))=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='stem_kind' and v.label='Tee sin rosca (ahead)')=0
 and (select count(*) from public.spec_definitions d where d.tenant_id is null and d.key='stem_kind' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Tee sin rosca (ahead)'::text]))=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='stem_kind' and v.label='Tee de espiga (quill)')=0
 and (select count(*) from public.spec_definitions d where d.tenant_id is null and d.key='stem_kind' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Tee de espiga (quill)'::text]))=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id where d.tenant_id is null and d.key='stem_kind' and v.label='Adaptador quill → ahead')=0
 and (select count(*) from public.spec_definitions d where d.tenant_id is null and d.key='stem_kind' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Adaptador quill → ahead'::text]))=0
 and (select count(*) from public.spec_templates t where t.tenant_id is null and t.is_active and position('"Talón de alambre"' in t.form_contract::text)>0)=0
 and (select count(*) from public.spec_templates t where t.tenant_id is null and t.is_active and position('"Talón plegable"' in t.form_contract::text)>0)=0
 and (select count(*) from public.spec_templates t where t.tenant_id is null and t.is_active and position('"Juego delantera + trasera"' in t.form_contract::text)>0)=0
 and (select count(*) from public.spec_templates t where t.tenant_id is null and t.is_active and position('"Juego delantera + trasera"' in t.form_contract::text)>0)=0
 and (select count(*) from public.spec_templates t where t.tenant_id is null and t.is_active and position('"Plato individual"' in t.form_contract::text)>0)=0
 and (select count(*) from public.spec_templates t where t.tenant_id is null and t.is_active and position('"Juego de platos en el mismo envase"' in t.form_contract::text)>0)=0
 and (select count(*) from public.spec_templates t where t.tenant_id is null and t.is_active and position('"Tee sin rosca (ahead)"' in t.form_contract::text)>0)=0
 and (select count(*) from public.spec_templates t where t.tenant_id is null and t.is_active and position('"Tee de espiga (quill)"' in t.form_contract::text)>0)=0
 and (select count(*) from public.spec_templates t where t.tenant_id is null and t.is_active and position('"Adaptador quill → ahead"' in t.form_contract::text)>0)=0 then 1 else 0 end) as customer_labels_2_ok;
