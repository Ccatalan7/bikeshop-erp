#!/usr/bin/env python3
"""Customer-facing labels in the language of Chilean bike shops.

The definition labels of the 2026-09 templates were written for the engine
("Posición de las mazas de este envase", "Norma de válvula", "Construcción del
receptor de transmisión"). The public store, the workshop and the purchasing
assistant print them as they are. This compiler emits one rerunnable migration
that relabels the global definitions (by key) and a handful of option labels
(by definition key + current label) with the wording Chilean shops use on
their own spec sheets, plus its verifier, which fails before the deploy.

Reference wording (2026-09-16): Bike Factory filters «Rayos: 32H», «Núcleo:
HG / Micro Spline / XD», «Medida eje: 12x148»; Viaja en Bici «Ancho de buje:
135mm», «Anclaje disco tipo Centerlock», «32 Hoyos»; Faucon Bikes «Válvula
Auto Schrader», «Válvula Francesa», «Aro 29», «Diámetro manillar 31.8mm»;
Trek Chile «Válvula: Presta», «Largo: 48 mm», «Diámetro: 27.5"», «Ancho:
2.2-2.5"»; Imperio Bikers «Velocidades», «Rango», «Núcleo», «Caja larga»,
«Piñón máximo»; Rideshop / Derman «32 hoyos», «doble pared», «ancho interno /
externo»; Oxford Store «Tipo de candado», «Incluye 2 llaves».

Option labels that a template contract references (`Talón de alambre`,
`Juego delantera + trasera`, `Tee sin rosca (ahead)`, `Plato individual`,
`Izquierdo / delantero`…) are left alone: renaming them means migrating the
contract in the same step, which is a separate block.

Follow-up 20260916181000: «Llave y clave» became «Llave y combinación» because
it tied with «Clave (combinación)» in the name-reading label score; the map
below is the applied 20260916180000 state and is not regenerated.

Usage: compile_customer_labels.py [--version 20260916180000]
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# key -> new label (global definitions, tenant_id is null)
DEFINITION_LABELS = {
    # ruedas y mazas
    'spoke_hole_count': 'Hoyos para rayos',
    'hub_package_position': 'Posición de la maza',
    'hub_old_mm': 'Ancho de la maza (OLD)',
    'hub_axle_diameter_mm': 'Diámetro del eje',
    'hub_drive_receiver_kind': 'Núcleo (tipo de piñón)',
    'hub_axle_mount_kind': 'Tipo de eje (cierre rápido o pasante)',
    'hub_rotor_mount_present': 'Para freno de disco',
    'hub_drive_receiver_present': 'Lleva núcleo o piñón (maza trasera)',
    'hub_spoke_head_interface': 'Tipo de rayo (J-bend o straight pull)',
    'bearing_system': 'Rodamientos',
    'spoke_length_mm': 'Largo del rayo',
    'spoke_head_interface': 'Tipo de cabeza (J-bend o straight pull)',
    'spoke_material_declared': 'Material',
    'rim_material': 'Material',
    'rim_wall_type': 'Pared (simple o doble)',
    'rim_joint_designation': 'Unión de la llanta',
    'bead_seat_diameter_mm': 'Diámetro ISO (BSD)',
    'wheel_position': 'Posición',
    'axle_length_mm': 'Largo del eje',
    # cámaras, válvulas y neumáticos
    'valve_standard': 'Tipo de válvula',
    'tube_has_sealant': 'Con líquido antipinchazos (sellante)',
    'tire_bead_type': 'Talón (alambre o plegable)',
    'tire_width_mm': 'Ancho',
    'tire_use': 'Uso',
    'tire_tpi': 'TPI (densidad de la carcasa)',
    'sealant_volume_ml': 'Volumen de sellante',
    # transmisión
    'sprocket_count': 'Velocidades',
    'chain_speeds': 'Velocidades',
    'shifter_indexed_positions': 'Velocidades',
    'chain_width_family': 'Ancho de cadena (1/8, 3/32)',
    'chain_outer_width_mm': 'Ancho externo',
    'chain_pitch_mm': 'Paso',
    'link_count': 'Eslabones',
    'chain_connector_type': 'Tipo de conector',
    'chain_link_reusable': 'Reutilizable',
    'chain_directional': 'Con sentido de montaje (direccional)',
    'derailleur_clutch': 'Con clutch (embrague)',
    'derailleur_cage_length': 'Largo de pata (caja)',
    'rear_derailleur_supplied_mount_adapter': 'Incluye uña (adaptador de montaje)',
    'front_derailleur_cable_pull': 'Tiro del cable',
    'front_derailleur_mount_type': 'Montaje',
    'front_derailleur_swing': 'Tipo (top swing o down swing)',
    'shifter_position': 'Lado (izquierdo o derecho)',
    'shifter_actuation_mode': 'Accionamiento (indexado o fricción)',
    'shifter_unit_count': 'Manillas incluidas',
    'teeth_count': 'Dientes',
    'chainring_bcd_mm': 'BCD (patrón de pernos)',
    'chainring_package_kind': 'Presentación',
    'chainring_set_member_count': 'Platos en el juego',
    'crank_arm_length_mm': 'Largo de biela',
    'crankset_construction': 'Tipo (una, dos o tres piezas)',
    'chainring_mounting': 'Montaje de los platos',
    'included_chainring_count': 'Platos incluidos',
    'bottom_bracket_included': 'Incluye motor (pedalier)',
    'crank_fixing_bolt_included': 'Incluye perno de biela',
    'crankset_chain_guard_included': 'Incluye cubrecadena',
    'crank_arm_unit_count': 'Bielas incluidas',
    'spindle_length_mm': 'Largo del eje',
    'spindle_diameter_mm': 'Diámetro del eje',
    'cassette_spline_standard': 'Núcleo (estriado)',
    'shift_technology': 'Tecnología (HG, Linkglide, Eagle…)',
    'remover_tool_standard': 'Extractor compatible',
    'pulley_package_kind': 'Presentación',
    # frenos
    'braking_surface': 'Freno (disco o llanta)',
    'brake_actuation': 'Accionamiento (mecánico o hidráulico)',
    'rotor_diameter_mm_value': 'Diámetro del disco',
    'rotor_material': 'Material',
    'rotor_floating': 'Disco flotante',
    'rotor_nominal_thickness_mm': 'Espesor (disco nuevo)',
    'rotor_mount_type': 'Montaje (6 pernos o Centerlock)',
    'rotor_wear_limit_mm': 'Límite de desgaste',
    'rim_pad_length_mm': 'Largo del patín',
    'rim_pad_construction': 'Tipo de patín',
    'lever_side': 'Lado',
    'piston_count_value': 'Pistones',
    'max_rotor_mm': 'Disco máximo',
    # cockpit, sillín, horquilla
    'bar_clamp_diameter_mm': 'Diámetro del manubrio (abrazadera)',
    'bar_width_mm': 'Ancho',
    'bar_style': 'Tipo',
    'bar_construction': 'Tipo (separado o integrado)',
    'stem_length_mm': 'Largo',
    'seatpost_length_mm': 'Largo',
    'seatpost_diameter_mm': 'Diámetro',
    'saddle_intended_use': 'Uso',
    'saddle_rail_material': 'Material de los rieles',
    'lockout': 'Con bloqueo (lockout)',
    'fork_crown_layout': 'Coronas (simple o doble)',
    # pedales
    'pedal_thread_standard': 'Rosca',
    'body_material': 'Material',
    'sold_as': 'Se vende por',
    # accesorios y ropa
    'light_position': 'Posición',
    'lumens_claimed': 'Lúmenes',
    'modes_count': 'Modos de luz',
    'locking_mechanism': 'Cierre (llave o clave)',
    'keys_included': 'Llaves incluidas',
    'helmet_kind': 'Uso',
    'oem_size_label': 'Talla',
    'rotational_protection_claimed': 'Con protección rotacional (MIPS u otro)',
    'intended_audience': 'Para (adulto o niño)',
    'glove_intended_use': 'Uso',
    'touchscreen': 'Compatible con pantalla táctil',
    'fabric_composition_text': 'Composición',
    'fit_cut': 'Corte',
    'certification_claim_text': 'Certificación',
    'pack_quantity': 'Unidades por pack',
    'units_per_pack': 'Unidades por pack',
    'patch_count': 'Parches',
    'plug_count': 'Mechas',
    'toluene_free': 'Sin tolueno',
    'biodegradable_claim': 'Biodegradable',
    'declared_applications': 'Usos',
    'declared_purpose': 'Uso',
    'head_drive': 'Tipo de cabeza (allen, torx…)',
    'thread': 'Rosca',
    'strength_class_claim': 'Grado',
    'max_tire_width_mm': 'Ancho máximo de neumático',
    'max_bike_weight_kg': 'Peso máximo de la bici',
    'mount_bolt_count': 'Pernos de montaje',
    'kickstand_mount_standard': 'Montaje',
    'functions_count': 'Funciones',
    'caffeine_mg': 'Cafeína',
    'interchangeable_lenses': 'Lentes adicionales',
    'uv_protection_claim': 'Protección UV',
    'rated_power_w': 'Potencia',
    'ports_count': 'Puertos',
    'combined_control_declared_units': 'Mandos incluidos',
}

# (definition key, current option label) -> new option label. Only options no
# template contract references.
OPTION_LABELS = [
    ('hub_drive_receiver_kind', 'Núcleo estriado de cassette', 'Núcleo de cassette'),
    ('hub_drive_receiver_kind', 'Rosca para rueda libre', 'Rosca para piñón (rueda libre)'),
    ('hub_drive_receiver_kind', 'Rosca para piñón fijo y contratuerca', 'Rosca para piñón fijo'),
    ('hub_drive_receiver_kind', 'Otra interfaz OEM', 'Otro'),
    ('bearing_system', 'Rodamientos sellados', 'Sellados'),
    ('derailleur_cage_length', 'SS / corta', 'Corta (SS)'),
    ('derailleur_cage_length', 'GS / media', 'Media (GS)'),
    ('derailleur_cage_length', 'SGS / larga', 'Larga (SGS)'),
    ('locking_mechanism', 'Combinación', 'Clave (combinación)'),
    ('locking_mechanism', 'Llave + combinación', 'Llave y clave'),
    ('front_derailleur_cable_pull', 'Top pull', 'Tiro arriba (top pull)'),
    ('front_derailleur_cable_pull', 'Down pull', 'Tiro abajo (down pull)'),
    ('front_derailleur_cable_pull', 'Dual pull', 'Doble tiro (dual pull)'),
    ('crankset_construction', 'Una pieza (americana / Ashtabula)', 'Una pieza (americana)'),
    ('crankset_construction', 'Dos piezas (eje solidario al brazo derecho)', 'Dos piezas (integrado)'),
    ('crankset_construction', 'Tres piezas (eje independiente)', 'Tres piezas (motor aparte)'),
    ('compound_type', 'Orgánico', 'Orgánico (resina)'),
    ('bar_style', 'Recto', 'Recto (plano)'),
    ('valve_standard', 'Presta (francesa)', 'Francesa (Presta)'),
    ('valve_standard', 'Schrader (americana / auto)', 'Auto (Schrader / americana)'),
]


def q(value):
    return "'" + value.replace("'", "''") + "'"


def migration(version):
    lines = [
        '-- Customer-facing labels in the wording of Chilean bike shops (2026-09-16).',
        '-- Relabels global definitions by key and a few option labels by (key, label).',
        '-- Facts, values, contracts and flags are untouched; the revision trigger bumps',
        '-- the contract_version of every template that uses a relabeled definition.',
        '-- Rerunnable: every update is conditional on the old wording.',
        f'-- Generated by scripts/inventory/compile_customer_labels.py --version {version}.',
        'begin;',
        "set local lock_timeout='5s';",
        "set local statement_timeout='120s';",
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
    for key, old, new in OPTION_LABELS:
        lines.append('update public.spec_definition_values v set label=' + q(new) + ', updated_at=now()'
                     ' from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null'
                     ' and d.key=' + q(key) + ' and v.label=' + q(old) + ';')
    lines.append('commit;')
    return '\n'.join(lines) + '\n'


def verifier():
    checks = ['(select count(*) from public.spec_definitions where tenant_id is null and key=' + q(k)
              + ' and label=' + q(v) + ')=1' for k, v in DEFINITION_LABELS.items()]
    checks += ['(select count(*) from public.spec_definition_values v join public.spec_definitions d'
               ' on d.id=v.spec_definition_id where d.tenant_id is null and d.key=' + q(k)
               + ' and v.label=' + q(old) + ')=0' for k, old, _ in OPTION_LABELS]
    checks += ['(select count(*) from public.spec_definition_values v join public.spec_definitions d'
               ' on d.id=v.spec_definition_id where d.tenant_id is null and d.key=' + q(k)
               + ' and v.label=' + q(new) + ')=1' for k, _, new in OPTION_LABELS]
    return ('-- Verifier: fails (division by zero) until every customer-facing label is in place.\n'
            'select 1/(case when ' + '\n and '.join(checks) + ' then 1 else 0 end) as customer_labels_ok;\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--version', default='20260916180000')
    args = parser.parse_args()
    mig = ROOT / f'supabase/migrations/{args.version}_customer_facing_labels.sql'
    ver = ROOT / f'supabase/manual_checks/verification/{args.version}_customer_facing_labels.sql'
    mig.write_text(migration(args.version))
    ver.write_text(verifier())
    print(mig, len(DEFINITION_LABELS), 'definition labels;', len(OPTION_LABELS), 'option labels')
    print(ver)


if __name__ == '__main__':
    main()
