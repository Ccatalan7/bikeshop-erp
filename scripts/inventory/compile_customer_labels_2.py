#!/usr/bin/env python3
"""Second, global pass of customer-facing labels (2026-09-16).

The first pass (compile_customer_labels.py) covered the fields that already
held facts. This one covers the rest of the customer-visible definitions with
engine wording («declarado por el fabricante», «datum OEM», «interfaz»,
«geometría del casquillo») and the option labels the first pass left alone
because a template contract names them: those are renamed together with the
contract text, the option row and the definition's allowed_values in one
transaction, so the rules guard sees a consistent contract at commit.

Same references as the first pass (Bike Factory, Viaja en Bici, Faucon,
Trek Chile, Imperio Bikers, Rideshop, Oxford Store); Weinmann's own Chilean
product names say «Ojetillos», and the trade says «Alambre» / «Plegable
(kevlar)» for tire beads.

Usage: compile_customer_labels_2.py [--version 20260916190000]
"""
import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/inventory'))
from compile_customer_labels import q  # noqa: E402

DEFINITION_LABELS = {
    # soportes, timbres, bolsos, protecciones
    'bar_fit_representation': 'Ajuste al manubrio (medidas o rango)',
    'max_load_kg': 'Carga máxima',
    'device_system': 'Sistema de unión',
    'loudness_db_claim': 'Nivel sonoro',
    'signal_kind': 'Tipo (campanilla o bocina)',
    'volume_basis': 'La capacidad incluye',
    'volume_l': 'Capacidad',
    'volume_scope': 'La capacidad corresponde a',
    'waterproof_claim': 'Impermeable',
    'fits_bike_size': 'Para bicicletas de',
    'detangler_kind': 'Tipo (gyro)',
    'steerer_fit': 'Medida de dirección',
    # rodamientos
    'ball_count_per_pack': 'Bolitas por pack',
    'ball_diameter_in': 'Tamaño de bolita',
    'bearing_application': 'Para (maza, dirección o motor)',
    'bearing_element_retention': 'Con jaula o sueltas',
    'bearing_inner_contact_angle_deg': 'Ángulo del bisel interior',
    'bearing_outer_contact_angle_deg': 'Ángulo del bisel exterior',
    'bearing_inner_diameter_mm': 'Diámetro interior',
    'bearing_outer_diameter_mm': 'Diámetro exterior',
    'bearing_race_contact_angle_deg': 'Ángulo de contacto',
    'bearing_race_type': 'Tipo (ranura profunda o contacto angular)',
    'bearing_regreasable': 'Se puede reengrasar',
    'bearing_row_count': 'Hileras de bolitas',
    'bearing_seal_designation': 'Código del sello (2RS, ZZ…)',
    'bearing_seal_type': 'Sellado',
    'bearing_seat_geometry': 'Biseles de apoyo',
    'bearing_size_code': 'Código (6902, 6001…)',
    'bearing_supply_form': 'Presentación',
    'bearing_width_mm': 'Ancho',
    'bb_bearing_width_mm': 'Ancho del rodamiento',
    'bb_cup_inner_seat_angle_deg': 'Ángulo interior del asiento',
    'bb_cup_outer_seat_angle_deg': 'Ángulo exterior del asiento',
    'bb_cup_seat_bevel': 'Biseles del asiento',
    # botellas y portabotellas
    'bottle_diameter_mm': 'Diámetro (para portabotella)',
    'bottle_retention_system': 'Sujeción (portabotella o Fidlock)',
    'bpa_free_claim': 'Libre de BPA',
    'insulated': 'Térmica',
    'boss_count': 'Tornillos al cuadro',
    'boss_spacing_mm': 'Separación de tornillos',
    'cage_mount': 'Fijación',
    'cage_retention_system': 'Sujeción de la botella',
    'frame_tube_width_max_mm': 'Tubo máximo',
    'frame_tube_width_min_mm': 'Tubo mínimo',
    'side_entry_side': 'Lado de salida',
    # pedalier
    'spindle_diameter_datum': 'Dónde se mide el diámetro del eje',
    'spindle_interface': 'Tipo de eje (cuadrado, Hollowtech…)',
    # frenos
    'brake_conversion_location': 'Dónde convierte cable a hidráulico',
    'brake_external_hose_connection': 'Con conexión de manguera externa',
    'brake_pad_retainer_model': 'Pasador de pastilla (modelo)',
    'cable_pull_required': 'Tiro de cable (largo o corto)',
    'caliper_mount_interface': 'Montaje (Post Mount, IS, Flat Mount)',
    'pad_shape_code': 'Forma de pastilla (código)',
    'rim_pad_stud_type': 'Fijación del patín',
    'tool_size_mm': 'Medida de llave',
    'handlebar_clamp_mm': 'Diámetro del manubrio (abrazadera)',
    'lever_bar_bore_max_mm': 'Diámetro interior máximo',
    'lever_bar_bore_min_mm': 'Diámetro interior mínimo',
    'lever_cable_interface': 'Anclaje del cable',
    'lever_cable_pull': 'Tiro de cable (largo o corto)',
    'lever_control_mount_oem_code': 'Código de anclaje del mando',
    'lever_hydraulic_role': 'Función (principal o auxiliar)',
    'lever_mount_clearance_mm': 'Espacio recto de manubrio necesario',
    'lever_mount_method': 'Fijación al manubrio',
    'lever_mount_oem_interface': 'Montaje específico (modelo)',
    'reach_adjust': 'Alcance regulable',
    'shifter_mount_interface': 'Anclaje para manilla de cambio (I-Spec, MatchMaker)',
    'brake_pad_oem_compound': 'Compuesto (nombre del fabricante)',
    'pad_compatibility_note': 'Compatibilidad (nota)',
    'pad_finned': 'Con aletas (disipador)',
    'pad_retention': 'Sujeción (pin, clip o imán)',
    'pad_spring_included': 'Incluye resorte',
    'rim_material_intended': 'Para llanta de',
    'rim_pad_interface_model': 'Soporte del patín (modelo)',
    'brake_presentation': 'Presentación (qué incluye)',
    'pad_compound_restriction': 'Pastillas que admite (resina o metálica)',
    # transmisión
    'published_variant_label': 'Variante (rango publicado)',
    'spacer_thickness_mm': 'Espesor',
    'target_rear_drive_interface': 'Para núcleo',
    'chain_other_width_designation': 'Otra medida de ancho',
    'drivetrain_mode': 'Tipo de transmisión (con cambios o single speed)',
    'chain_guide_chainline_adjustment_mm': 'Ajuste de línea de cadena',
    'chain_guide_chainline_datum': 'Cómo se mide la línea de cadena',
    'chainring_teeth_max': 'Plato máximo (dientes)',
    'chainring_teeth_min': 'Plato mínimo (dientes)',
    'chain_link_pack_qty': 'Conectores por pack',
    'connector_reuse_limit': 'Usos máximos',
    'chainring_direct_mount_generation': 'Direct mount (generación)',
    'chainring_mount_type': 'Montaje (BCD o direct mount)',
    'crank_arm_carries_chainring_mount': 'Lleva los platos (lado derecho)',
    'crank_arm_spindle_designation': 'Eje (designación)',
    'crank_arm_system_construction': 'Tipo de volante (una, dos o tres piezas)',
    'crank_side': 'Lado',
    'pedal_thread': 'Rosca de pedal',
    'hanger_derailleur_interface': 'Lado del cambio (rosca o direct mount)',
    'hanger_frame_interface': 'Lado del cuadro (UDH, puntera…)',
    'hanger_model_code': 'Código de la pata (postiza)',
    'extender_declaration_form': 'Qué declara el extensor',
    'hanger_interface': 'Tipo de pata (postiza)',
    'pulley_bearing_construction': 'Apoyo (buje o rodamiento)',
    'pulley_bearing_element_material': 'Material de las bolitas',
    'pulley_bore_diameter_mm': 'Diámetro del agujero',
    'pulley_declared_position': 'Posición (guía o tensión)',
    'pulley_declared_speeds': 'Velocidades',
    'pulley_teeth': 'Dientes',
    'pulley_tooth_profile': 'Dentado',
    'pulley_unit_count': 'Roldanas incluidas',
    'pulley_width_mm': 'Ancho',
    'cog_thread_standard': 'Rosca del piñón',
    'single_cog_teeth': 'Dientes',
    'freewheel_thread_standard': 'Rosca',
    'front_derailleur_cable_anchor': 'Anclaje del cable en el perno',
    'rear_derailleur_actuation_ratio_declaration': 'Relación de accionamiento',
    'rear_derailleur_mount_type': 'Montaje (pata, direct mount o uña)',
    'rear_derailleur_spring_return': 'Retorno del resorte (normal o inverso)',
    'rear_derailleur_supplied_adapter_reference': 'Uña o adaptador incluido (modelo)',
    'shifter_control_style': 'Tipo de manilla (gatillo, giro…)',
    # electrónica y accesorios
    'cable_data_capability': 'Datos del cable (norma y velocidad)',
    'cable_power_capacity_w': 'Potencia de carga del cable',
    'charging_protocol_claim': 'Protocolo de carga',
    'speed_class_claim': 'Clase de velocidad',
    'storage_capacity_label': 'Capacidad impresa',
    'wireless': 'Inalámbrico',
    'connector_a': 'Conector (lado 1)',
    'connector_b': 'Conector (lado 2)',
    'control_part_kind': 'Tipo de pieza',
    'fits_cable_diameter_mm': 'Para cable de',
    'fits_housing_diameter_mm': 'Para funda de',
    'noodle_angle_deg': 'Ángulo de la guía',
    'positioning_source': 'GPS',
    # fijaciones
    'head_drive_size_mm': 'Medida de llave (hex)',
    'length_datum': 'Cómo se mide el largo',
    'thread_pitch_system': 'Paso expresado en',
    'thread_tpi': 'Hilos por pulgada',
    'torx_size': 'Torx (T25…)',
    # comida
    'caffeine_basis': 'Cafeína por',
    'ingredients_text': 'Ingredientes',
    'milk_substitution_offered': 'Se puede cambiar la leche',
    'net_mass_g': 'Peso neto',
    'unit_mass_g': 'Peso por unidad',
    'serving_size': 'Tamaño',
    'temperature': 'Se sirve',
    # horquilla y dirección
    'axle_to_crown_mm': 'Largo eje a corona',
    'brake_mount': 'Montaje de freno',
    'crown_race_diameter_mm': 'Diámetro de pista de corona',
    'crown_stack_max_mm': 'Altura máxima entre coronas',
    'crown_stack_min_mm': 'Altura mínima entre coronas',
    'fork_offset_mm': 'Offset (avance)',
    'stanchion_diameter_mm': 'Diámetro de barras',
    'steerer_length_mm': 'Largo del tubo de dirección',
    'steerer_threaded': 'Con hilo (rosca)',
    'headset_lower_shis': 'Medida SHIS inferior',
    'headset_upper_shis': 'Medida SHIS superior',
    'headset_lower_stack_height_mm': 'Altura inferior instalada',
    'headset_upper_stack_height_mm': 'Altura superior instalada',
    'headset_part_scope': 'Qué incluye (superior, inferior o completa)',
    'headset_supplied_crown_race_reference': 'Pista de corona incluida (modelo)',
    # puños, manubrio, tee, tija, sillín
    'grip_attachment': 'Fijación (deslizante o lock-on)',
    'grip_bar_nominal_diameter_mm': 'Para manubrio de',
    'grip_inner_diameter_mm': 'Diámetro interior',
    'grip_length_mm': 'Largo',
    'grip_length_left_mm': 'Largo (izquierdo)',
    'grip_length_right_mm': 'Largo (derecho)',
    'grip_measurement_reference': 'Cómo se midió',
    'grip_straight_length_required_mm': 'Zona recta de manubrio necesaria',
    'grip_straight_length_required_left_mm': 'Zona recta necesaria (izquierdo)',
    'grip_straight_length_required_right_mm': 'Zona recta necesaria (derecho)',
    'intended_rider': 'Para (adulto o niño)',
    'accessory_mount_ports_text': 'Soportes para accesorios',
    'bar_backsweep_deg': 'Backsweep (ángulo hacia atrás)',
    'bar_drop_mm': 'Drop',
    'bar_reach_mm': 'Reach',
    'bar_rise_mm': 'Rise (elevación)',
    'bar_upsweep_deg': 'Upsweep (ángulo hacia arriba)',
    'bar_width_drops_mm': 'Ancho en drops',
    'bar_width_hoods_mm': 'Ancho en manetas',
    'bar_width_reference': 'Cómo se mide el ancho',
    'cable_routing': 'Cableado (interno o externo)',
    'grip_area_diameter_mm': 'Diámetro en los puños',
    'integrated_steerer_clamp_mm': 'Diámetro de dirección (integrado)',
    'integrated_stem_angle_deg': 'Ángulo de la tee integrada',
    'integrated_stem_length_mm': 'Largo de la tee integrada',
    'covering_kind': 'Tipo (cinta o funda)',
    'quill_adapter_output_diameter_mm': 'Diámetro de salida (ahead)',
    'quill_diameter_mm': 'Diámetro de la espiga',
    'quill_min_insertion_mm': 'Inserción mínima',
    'stem_angle_deg': 'Ángulo',
    'stem_steerer_clamp_diameter_mm': 'Diámetro de dirección (abrazadera)',
    'clamp_kind': 'Tipo (perno o cierre rápido)',
    'clamp_thread': 'Rosca',
    'clamp_thread_pitch_mm': 'Paso de la rosca',
    'seat_tube_outer_diameter_mm': 'Para tubo de asiento de',
    'dropper_cable_routing': 'Cableado de la telescópica (interno o externo)',
    'dropper_control_kind': 'Accionamiento (cable, hidráulico o inalámbrico)',
    'dropper_remote_model': 'Mando incluido (modelo)',
    'dropper_travel_mm': 'Recorrido',
    'seatpost_bottom_clearance_mm': 'Proyección bajo el largo declarado',
    'seatpost_min_exposed_mm': 'Mínimo expuesto',
    'seatpost_min_insertion_mm': 'Inserción mínima',
    'seatpost_offset_mm': 'Retroceso (offset)',
    'seatpost_shim_length_mm': 'Largo',
    'seatpost_shim_mount_instructions': 'Instrucciones de montaje',
    'seatpost_shim_oem_interface': 'Perfil específico (fabricante)',
    'seatpost_shim_shape': 'Forma',
    'seatpost_shim_support_length_mm': 'Largo de apoyo',
    'shim_inner_diameter_mm': 'Diámetro interior',
    'shim_outer_diameter_mm': 'Diámetro exterior',
    'cover_material': 'Material del forro',
    'saddle_cutout': 'Con canal central',
    'saddle_length_mm': 'Largo',
    'saddle_mount_model': 'Anclaje (detalle)',
    'saddle_rail_geometry': 'Rieles (redondo 7 mm, oval…)',
    'saddle_width_mm': 'Ancho',
    'fits_saddle_length_max_mm': 'Para sillín de largo hasta',
    'fits_saddle_length_min_mm': 'Para sillín de largo desde',
    'fits_saddle_width_max_mm': 'Para sillín de ancho hasta',
    # mazas, rayos, llantas, cámaras
    'center_to_flange_left_mm': 'Centro a brida izquierda',
    'center_to_flange_right_mm': 'Centro a brida derecha',
    'flange_pcd_left_mm': 'PCD brida izquierda',
    'flange_pcd_right_mm': 'PCD brida derecha',
    'hub_axle_diameter_datum': 'Dónde se mide el diámetro del eje',
    'hub_drive_receiver_reference': 'Núcleo (referencia exacta)',
    'hub_package_piece_count': 'Mazas en el juego',
    'hub_supplied_thru_axle_reference': 'Eje pasante incluido (modelo)',
    'spoke_hole_diameter_mm': 'Diámetro del hoyo de rayo',
    'hub_axle_length_datum': 'Cómo se mide el largo',
    'spoke_finish_declared': 'Acabado',
    'spoke_gauge_designation': 'Calibre (14G, 15G…)',
    'spoke_head_elbow_angle_deg': 'Ángulo del codo',
    'spoke_head_oem_designation': 'Cabeza (referencia del fabricante)',
    'spoke_hub_hole_class_declared': 'Para hoyo de maza de',
    'spoke_nipple_thread_present': 'Con rosca para niple',
    'spoke_thread_length_mm': 'Largo de la rosca',
    'spoke_thread_major_diameter_mm': 'Diámetro de la rosca',
    'spoke_thread_nominal_mm': 'Rosca nominal',
    'spoke_thread_standard': 'Rosca (FG 2.3…)',
    'nipple_thread': 'Para rayo calibre',
    'nipple_thread_standard': 'Rosca (FG 2.3…)',
    'brake_track': 'Con pista de freno (para V-brake)',
    'rim_asymmetric_offset_mm': 'Offset asimétrico',
    'rim_bead_profile': 'Gancho (hooked o hookless)',
    'rim_brake_wear_indicator': 'Indicador de desgaste',
    'rim_erd_datum': 'Cómo se mide el ERD',
    'rim_external_width_mm': 'Ancho externo',
    'rim_internal_width_mm': 'Ancho interno',
    'rim_eyelet_type': 'Ojetillos',
    'rim_profile_height_mm': 'Alto del perfil',
    'rim_spoke_hole_diameter_mm': 'Diámetro del hoyo de niple',
    'rim_symmetry': 'Simetría',
    'rim_tire_bed_access_hole_mm': 'Agujero de acceso del fondo',
    'rim_tubeless_ready': 'Tubeless ready',
    'strip_fit_internal_width_max_mm': 'Para llanta de ancho interno hasta',
    'strip_fit_internal_width_min_mm': 'Para llanta de ancho interno desde',
    'strip_material': 'Material',
    'strip_width_mm': 'Ancho',
    'tire_tubeless_ready': 'Tubeless ready',
    'tire_weight_g': 'Peso',
    'tube_material': 'Material',
    'glue_volume_ml': 'Pegamento (volumen)',
    'consumable_kind': 'Tipo',
    'sealant_base': 'Sellante (con o sin látex)',
    'tubeless_tape_application': 'Instrucciones de aplicación',
    'valve_base_shape': 'Forma de la base',
    'axle_nut_thread': 'Rosca del eje',
    # pedales, pata de apoyo, bombín, parrilla, candado
    'included_cleat_model': 'Calas incluidas (modelo)',
    'pedal_intended_rider': 'Para (adulto o niño)',
    'pedal_thread_other_declaration': 'Otra rosca (medida completa)',
    'pedal_wrench_interface': 'Se monta con (llave o hexágono)',
    'peg_axle_fit': 'Para eje de',
    'frame_requirement_text': 'Requisito del cuadro',
    'installed_height_max_mm': 'Altura instalada máxima',
    'installed_height_min_mm': 'Altura instalada mínima',
    'kickstand_length_reference': 'Cómo se mide el largo',
    'kickstand_mount_kind': 'Fijación',
    'barrel_material': 'Material del cuerpo',
    'co2_inflation_capable': 'También infla con CO₂',
    'inflation_target_note': 'Presión máxima (nota)',
    'valve_heads_supported': 'Válvulas que infla',
    'carrier_kind': 'Tipo (parrilla o canasto)',
    'carrier_mount_kind': 'Fijación',
    'load_reference': 'La carga máxima se refiere a',
    'rack_eyelets_required': 'Necesita ojales en el cuadro',
    'lock_chain_length_mm': 'Largo de la cadena',
    'shackle_diameter_mm': 'Grosor del arco',
    'inner_height_mm': 'Alto interior',
    # ropa y bolsos del ciclista, amortiguador, taller
    'gender_fit': 'Corte (hombre, mujer, unisex)',
    'sleeve': 'Manga',
    'fits_volume_max_l': 'Para mochila de hasta',
    'fits_volume_min_l': 'Para mochila desde',
    'reservoir_l': 'Capacidad de la bolsa de hidratación',
    'finger_length': 'Dedos (corto o largo)',
    'padding': 'Acolchado',
    'rider_protection_kind': 'Protege',
    'mounting_hardware_included': 'Incluye bujes de montaje',
    'spring_kind': 'Tipo (aire o muelle)',
    'theme': 'Diseño',
    'chemical_kind': 'Tipo de producto',
    'not_for': 'No usar en',
    'chain_tool_speeds': 'Velocidades de cadena que admite',
    'size_label': 'Talla',
    'tool_interface': 'Encaje (cassette, biela…)',
}

# Options no contract names: (definition key, current label, new label).
OPTION_LABELS = [
    ('rim_eyelet_type', 'Sin ojillos', 'Sin ojetillos'),
    ('rim_eyelet_type', 'Ojillo simple', 'Ojetillo simple'),
    ('rim_eyelet_type', 'Doble ojillo', 'Doble ojetillo'),
]

# Options a template contract names: renamed in the option row, in
# allowed_values and inside every active global contract, in one transaction.
CONTRACT_OPTION_LABELS = [
    ('tire_bead_type', 'Talón de alambre', 'Alambre'),
    ('tire_bead_type', 'Talón plegable', 'Plegable (kevlar)'),
    ('hub_package_position', 'Juego delantera + trasera', 'Juego (delantera y trasera)'),
    ('light_position', 'Juego delantera + trasera', 'Juego (delantera y trasera)'),
    # shifter_position («Izquierdo / delantero», «Derecho / trasero») stays: the
    # distributed Dart client compares those exact texts
    # (drivetrain_canonical_data.dart); renaming them needs a client release.
    ('chainring_package_kind', 'Plato individual', 'Un plato'),
    ('chainring_package_kind', 'Juego de platos en el mismo envase', 'Juego de platos'),
    ('stem_kind', 'Tee sin rosca (ahead)', 'Ahead (sin rosca)'),
    ('stem_kind', 'Tee de espiga (quill)', 'De espiga (quill)'),
    ('stem_kind', 'Adaptador quill → ahead', 'Adaptador (quill a ahead)'),
]


def json_string(value):
    """The label as it appears inside a JSON text (only quotes need escaping here)."""
    return '"' + value.replace('"', '\\"') + '"'


def migration(version):
    every_option = OPTION_LABELS + CONTRACT_OPTION_LABELS
    lines = [
        '-- Customer-facing labels, second (global) pass, 2026-09-16.',
        '-- Definitions relabeled by key; options relabeled in the option row, in',
        '-- allowed_values and, for the ones a contract names, inside the contract text',
        '-- of every active global template. Facts and values ids are untouched.',
        '-- Rerunnable: every update is conditional on the old wording.',
        f'-- Generated by scripts/inventory/compile_customer_labels_2.py --version {version}.',
        'begin;',
        "set local lock_timeout='5s';",
        "set local statement_timeout='180s';",
        'do $guard$ begin',
        " if (select count(*) from public.spec_definitions where tenant_id is null and key in ("
        + ','.join(q(k) for k in DEFINITION_LABELS) + f')) <> {len(DEFINITION_LABELS)} then',
        "  raise exception 'A relabeled definition is missing among the global definitions';",
        ' end if;',
        'end $guard$;',
    ]
    for key, label in DEFINITION_LABELS.items():
        lines.append('update public.spec_definitions set label=' + q(label) + ', updated_at=now()'
                     ' where tenant_id is null and key=' + q(key) + ' and label is distinct from ' + q(label) + ';')
    for key, old, new in every_option:
        lines.append('update public.spec_definition_values v set label=' + q(new) + ', updated_at=now()'
                     ' from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null'
                     ' and d.key=' + q(key) + ' and v.label=' + q(old) + ';')
        lines.append(
            'update public.spec_definitions d set allowed_values=(select jsonb_agg(case when e=to_jsonb('
            + q(old) + '::text) then to_jsonb(' + q(new) + '::text) else e end order by ord)'
            ' from jsonb_array_elements(d.allowed_values) with ordinality as t(e, ord)), updated_at=now()'
            ' where d.tenant_id is null and d.key=' + q(key)
            + " and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array[" + q(old) + '::text]);')
    for key, old, new in CONTRACT_OPTION_LABELS:
        lines.append('update public.spec_templates t set form_contract=replace(t.form_contract::text, '
                     + q(json_string(old)) + ', ' + q(json_string(new)) + ')::jsonb, updated_at=now()'
                     ' where t.tenant_id is null and t.is_active and position(' + q(json_string(old))
                     + ' in t.form_contract::text)>0;')
    lines.append('commit;')
    return '\n'.join(lines) + '\n'


def verifier():
    every_option = OPTION_LABELS + CONTRACT_OPTION_LABELS
    checks = ['(select count(*) from public.spec_definitions where tenant_id is null and key=' + q(k)
              + ' and label=' + q(v) + ')=1' for k, v in DEFINITION_LABELS.items()]
    for k, old, new in every_option:
        checks.append('(select count(*) from public.spec_definition_values v join public.spec_definitions d'
                      ' on d.id=v.spec_definition_id where d.tenant_id is null and d.key=' + q(k)
                      + ' and v.label=' + q(old) + ')=0')
        checks.append('(select count(*) from public.spec_definitions d where d.tenant_id is null and d.key=' + q(k)
                      + " and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array[" + q(old) + '::text]))=0')
    for k, old, new in CONTRACT_OPTION_LABELS:
        checks.append('(select count(*) from public.spec_templates t where t.tenant_id is null and t.is_active and position('
                      + q(json_string(old)) + ' in t.form_contract::text)>0)=0')
    return ('-- Verifier: fails (division by zero) until the second label pass is fully in place.\n'
            'select 1/(case when ' + '\n and '.join(checks) + ' then 1 else 0 end) as customer_labels_2_ok;\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--version', default='20260916190000')
    args = parser.parse_args()
    mig = ROOT / f'supabase/migrations/{args.version}_customer_facing_labels_2.sql'
    ver = ROOT / f'supabase/manual_checks/verification/{args.version}_customer_facing_labels_2.sql'
    mig.write_text(migration(args.version))
    ver.write_text(verifier())
    print(mig, len(DEFINITION_LABELS), 'definition labels;', len(OPTION_LABELS), 'options;',
          len(CONTRACT_OPTION_LABELS), 'contract options')
    print(ver)


if __name__ == '__main__':
    main()
