#!/usr/bin/env python3
"""Compile the Chilean-Spanish vocabulary pass for technical sheets.

Operator-facing labels lead with the words used by Chilean bike shops. Exact
manufacturer standards remain available in parentheses or helper text, so the
wording change does not alter stored values, compatibility tokens, or rules.

Usage: compile_chilean_bicycle_language.py [--version 20260919250000]
"""
import argparse
import json
from pathlib import Path

from compile_hub_plain_language import (
    DEFINITION_LABELS as HUB_DEFINITION_LABELS,
    HUB_HELPERS,
    HUB_TEMPLATE_DESCRIPTION,
    HUB_TEMPLATE_NAME,
)

ROOT = Path(__file__).resolve().parents[2]


DEFINITION_LABELS = {
    **HUB_DEFINITION_LABELS,
    # Manubrio, horquilla y puesto de conducción.
    'bar_backsweep_deg': 'Ángulo del manubrio hacia atrás',
    'bar_drop_mm': 'Caída del manubrio',
    'bar_reach_mm': 'Alcance del manubrio',
    'bar_rise_mm': 'Elevación del manubrio',
    'bar_upsweep_deg': 'Ángulo del manubrio hacia arriba',
    'bar_width_drops_mm': 'Ancho del manubrio en la parte baja',
    'bar_width_hoods_mm': 'Ancho del manubrio en las manillas',
    'fork_offset_mm': 'Avance de la horquilla',
    'reach_adjust': 'Ajuste de distancia de la manilla',
    'stem_kind': 'Tipo de tee / potencia',
    # Asiento y tubo de asiento.
    'dropper_actuation': 'Accionamiento del tubo telescópico',
    'fits_saddle_length_max_mm': 'Para asiento de largo hasta',
    'fits_saddle_length_min_mm': 'Para asiento de largo desde',
    'fits_saddle_width_max_mm': 'Para asiento de ancho hasta',
    'seatpost_kind': 'Tipo de tubo de asiento',
    'seatpost_offset_mm': 'Retroceso del tubo de asiento',
    'seatpost_saddle_configurations': 'Anclajes de asiento documentados',
    # Volante, platos y cambios.
    'chainring_bcd_mm': 'Diámetro del círculo de pernos (BCD)',
    'chainring_bolt_count': 'Cantidad de pernos del plato',
    'chainring_direct_mount_generation': 'Sistema de montaje directo',
    'chainring_mount_type': 'Fijación del plato',
    'chainring_mounting': 'Fijación de los platos',
    'chainring_offset_mm': 'Desplazamiento lateral del plato',
    'derailleur_cage_length': 'Largo de la pata del cambio',
    'derailleur_clutch': 'Con estabilizador de cadena (clutch)',
    'drivetrain_mode': 'Tipo de transmisión',
    'drivetrain_platform': 'Familia de transmisión',
    'drivetrain_primary_ecosystem': 'Sistema principal de transmisión',
    'freehub_type': 'Tipo de núcleo',
    'front_derailleur_swing': 'Movimiento del desviador delantero',
    'hanger_derailleur_interface': 'Unión con el cambio trasero',
    'hanger_frame_interface': 'Unión con el cuadro',
    'hanger_interface': 'Tipo de pata / postiza',
    'quick_link_included': 'Incluye conector rápido',
    'rear_derailleur_hanger_interface': 'Unión con la pata de cambio',
    'rear_derailleur_mount_type': 'Fijación del cambio trasero',
    # Aros, neumáticos y rayos.
    'rim_asymmetric_offset_mm': 'Desplazamiento lateral del aro',
    'rim_bead_profile': 'Borde del aro (con o sin gancho)',
    'rim_erd_datum': 'Cómo se midió el diámetro efectivo del aro (ERD)',
    'rim_erd_mm': 'Diámetro efectivo del aro (ERD)',
    'rim_etrto': 'Medida normalizada del aro (ETRTO)',
    'rim_tubeless_ready': 'Apto para usar sin cámara (Tubeless Ready)',
    'spoke_bend_type': 'Tipo de rayo (con codo o recto)',
    'spoke_head_interface': 'Tipo de rayo (con codo o recto)',
    'spoke_holes': 'Cantidad de hoyos para rayos',
    'tire_etrto': 'Medida normalizada del neumático (ETRTO)',
    'tire_tubeless_ready': 'Apto para usar sin cámara (Tubeless Ready)',
    # Frenos y fijaciones: el nombre exacto del estándar sigue en la ayuda.
    'cable_pull_required': 'Recorrido de cable que necesita',
    'caliper_mount_interface': 'Fijación del cáliper',
    'front_derailleur_cable_pull': 'Entrada del cable al desviador',
    'lever_cable_pull': 'Recorrido de cable de la manilla',
    'lockout': 'Con bloqueo',
    'mount_standard': 'Sistema de fijación',
    # Motor o caja de motor, como se nombra en talleres chilenos.
    'bb_declared_systems': 'Sistemas de motor declarados',
    'bb_shell_interface': 'Fijación en la caja de motor',
    'bb_thread_standard': 'Rosca de la caja de motor',
    'bottom_bracket_family': 'Familia de motor / caja de motor',
    'bottom_bracket_included': 'Incluye motor / caja de motor',
    'bottom_bracket_required': 'Motor / caja de motor requerido',
    'crankset_bottom_bracket_supplied': 'Motor / caja de motor incluido',
}


TEMPLATE_METADATA = {
    'bottom_bracket': (
        'Motor / caja de motor',
        'Conjunto que permite girar el volante dentro del cuadro; se confirma '
        'por caja, rosca, eje y sistema de biela.',
    ),
    'brake_caliper': (
        'Cáliper de freno',
        'Cálipers completos, hidráulicos o mecánicos.',
    ),
    'cassette': (
        'Cassette',
        'Conjunto de piñones que se instala sobre un núcleo; se confirma por '
        'sistema de núcleo, velocidades y rango.',
    ),
    'cassette_spacer': (
        'Espaciador de cassette',
        'Anillo espaciador para instalar un cassette sobre un núcleo.',
    ),
    'chainring': (
        'Plato / corona',
        'Plato del volante; se confirma por dientes, fijación, velocidades y '
        'desplazamiento lateral.',
    ),
    'crank_arm': (
        'Biela suelta',
        'Una biela individual; se confirma por lado, largo, unión al eje y '
        'rosca del pedal.',
    ),
    'crankset': (
        'Volante / juego de bielas',
        'Conjunto de bielas y platos; se confirma por platos, eje, motor y '
        'velocidades.',
    ),
    'derailleur_hanger': (
        'Pata / postiza de cambio',
        'Pieza reemplazable que une el cambio trasero al cuadro; se confirma '
        'por cuadro, modelo y fijación.',
    ),
    'derailleur_hanger_extender': (
        'Extensor de pata de cambio',
        'Extensor que cambia la posición del cambio trasero.',
    ),
    'freewheel': (
        'Piñón roscado / rueda libre',
        'Conjunto de piñones que se enrosca directamente en la maza; se '
        'confirma por rosca y velocidades.',
    ),
    'hub': (HUB_TEMPLATE_NAME, HUB_TEMPLATE_DESCRIPTION),
    'rim': (
        'Aro / llanta',
        'Aro de rueda; se confirma por diámetro, ancho, hoyos para rayos y '
        'agujero de válvula.',
    ),
    'rim_strip': (
        'Fondo de aro / cubre cámara',
        'Cinta o banda que cubre los hoyos interiores del aro.',
    ),
    'saddle': ('Asiento', 'Asiento de bicicleta.'),
    'saddle_cover': ('Funda para asiento', 'Funda que cubre el asiento.'),
    'seatpost': (
        'Tubo de asiento',
        'Tubo que une el asiento al cuadro, fijo o telescópico.',
    ),
    'spoke': (
        'Rayo',
        'Rayo de rueda; se confirma por largo, calibre, rosca y tipo de '
        'entrada a la maza.',
    ),
    'tire': (
        'Neumático',
        'Neumático de bicicleta; se confirma por aro, ancho, construcción y '
        'uso con o sin cámara.',
    ),
}


HELPER_PATCHES = {
    'bottom_bracket': {
        'spindle_interface': 'Sistema de eje que trae este motor. Si no trae eje, la unión que acepta se declara por separado.',
    },
    'brake_caliper': {
        'cable_pull_required': 'Recorrido de cable que este cáliper necesita de la manilla. No se deduce de la marca.',
        'caliper_mount_interface': 'Fijación física de este cáliper. Conserva el nombre exacto del estándar: Post Mount, Flat Mount o IS.',
        'brake_conversion_location': 'En un cáliper híbrido, la conversión de cable a presión ocurre dentro de la misma pieza. Un convertidor externo es otra pieza.',
    },
    'chainring': {
        'chainring_direct_mount_generation': 'Sistema exacto de montaje directo que publica el fabricante. La frase direct mount por sí sola no identifica piezas intercambiables.',
        'chainring_offset_declarations': 'Desplazamiento lateral medido desde la referencia que indica el fabricante. No es la línea de cadena del conjunto armado.',
    },
    'crankset': {
        'chainring_mounting': 'Indica si los platos se sacan con pernos, van remachados o usan montaje directo al brazo.',
        'bottom_bracket_included': 'Que el volante necesite un motor determinado y que ese motor venga en la caja son dos respuestas distintas.',
        'bottom_bracket_required': 'Una fila por combinación documentada de caja, motor, largo de eje y línea de cadena.',
        'crankset_bottom_bracket_supplied': 'Identifica el motor o caja de motor que viene en el envase. Si no viene incluido, déjalo vacío.',
    },
    'front_derailleur': {
        'front_derailleur_swing': 'Indica dónde pivota la jaula. No es la ruta del cable: top swing y top pull describen cosas distintas.',
        'front_derailleur_cable_pull': 'Indica desde dónde entra el cable: por arriba, por abajo o por ambos lados. No describe el pivote de la jaula.',
    },
    'rear_derailleur': {
        'rear_derailleur_mount_type': 'Cómo se fija este cambio al cuadro: a la pata, por montaje directo o mediante una uña sujeta al eje.',
        'rear_derailleur_supplied_mount_adapter': 'Una uña es una pieza incluida que se sostiene con la tuerca del eje o el cierre rápido. No cambia la fijación que ofrece el cuadro.',
    },
    'rim': {
        'rim_erd_datum': 'Indica desde qué punto midió el fabricante el diámetro efectivo del aro (ERD), incluyendo niple o arandela cuando corresponda. No es el diámetro de apoyo del neumático.',
    },
    'seatpost': {
        'seatpost_kind': 'Tubo de asiento completo. Un adaptador reductor tiene su propia ficha.',
    },
    'spoke': {
        'spoke_head_elbow_angle_deg': 'Ángulo del codo según el dibujo del fabricante. No se supone que todos los rayos con codo midan 90°.',
    },
    'tire': {
        'tire_tubeless_ready': 'Apto para usar sin cámara sólo con un aro, válvula y sellante compatibles. En la caja suele aparecer como Tubeless Ready.',
    },
    'hub': HUB_HELPERS,
}


def q(text: str) -> str:
    return "'" + text.replace("'", "''") + "'"


def compile_sql(version: str) -> tuple[str, str]:
    definition_keys = list(DEFINITION_LABELS)
    template_keys = list(TEMPLATE_METADATA)
    helper_template_keys = list(HELPER_PATCHES)
    definition_key_list = ','.join(q(key) for key in definition_keys)
    template_key_list = ','.join(q(key) for key in template_keys)
    helper_template_key_list = ','.join(q(key) for key in helper_template_keys)

    lines = [
        '-- Chilean-Spanish vocabulary for bicycle technical sheets (2026-09-19).',
        '-- Changes labels, template names/descriptions and explanatory helpers only.',
        '-- Stored values, option tokens, compatibility rules and product facts are untouched.',
        '-- Rerunnable: every update is conditional on the desired wording.',
        f'-- Generated by scripts/inventory/compile_chilean_bicycle_language.py --version {version}.',
        'begin;',
        "set local lock_timeout='5s';",
        "set local statement_timeout='120s';",
        'do $guard$ begin',
        f' if (select count(*) from public.spec_definitions where tenant_id is null and key in ({definition_key_list})) <> {len(definition_keys)} then',
        "  raise exception 'A relabeled global definition is missing';",
        ' end if;',
        f' if (select count(*) from public.spec_templates where tenant_id is null and key in ({template_key_list})) <> {len(template_keys)} then',
        "  raise exception 'A relabeled global template is missing';",
        ' end if;',
        f' if (select count(*) from public.spec_templates where tenant_id is null and key in ({helper_template_key_list})) <> {len(helper_template_keys)} then',
        "  raise exception 'A helper-patched global template is missing';",
        ' end if;',
        'end $guard$;',
    ]

    for key, label in DEFINITION_LABELS.items():
        lines.append(
            f'update public.spec_definitions set label={q(label)}, updated_at=now() '
            f'where tenant_id is null and key={q(key)} and label is distinct from {q(label)};'
        )

    for key, (name, description) in TEMPLATE_METADATA.items():
        lines.append(
            f'update public.spec_templates set name={q(name)}, description={q(description)}, updated_at=now() '
            f'where tenant_id is null and key={q(key)} and '
            f'(name,description) is distinct from ({q(name)},{q(description)});'
        )

    for key, helpers in HELPER_PATCHES.items():
        helpers_json = json.dumps(helpers, ensure_ascii=False, sort_keys=True)
        lines.append(
            "update public.spec_templates set form_contract=jsonb_set(form_contract,'{helpers}', "
            f"coalesce(form_contract->'helpers','{{}}'::jsonb) || {q(helpers_json)}::jsonb), updated_at=now() "
            f"where tenant_id is null and key={q(key)} and (form_contract->'helpers') is distinct from "
            f"(coalesce(form_contract->'helpers','{{}}'::jsonb) || {q(helpers_json)}::jsonb);"
        )

    lines.append('commit;')
    migration = '\n'.join(lines) + '\n'

    checks = [
        f'(select count(*) from public.spec_definitions where tenant_id is null and key={q(key)} and label={q(label)})=1'
        for key, label in DEFINITION_LABELS.items()
    ]
    checks.extend(
        f'(select count(*) from public.spec_templates where tenant_id is null and key={q(key)} and name={q(name)} and description={q(description)})=1'
        for key, (name, description) in TEMPLATE_METADATA.items()
    )
    checks.extend(
        f"(select count(*) from public.spec_templates where tenant_id is null and key={q(template_key)} and form_contract->'helpers'->>{q(helper_key)}={q(helper)})=1"
        for template_key, helpers in HELPER_PATCHES.items()
        for helper_key, helper in helpers.items()
    )
    verifier = (
        '-- Verifier: fails until every Chilean-Spanish label and helper is live.\n'
        'select 1/(case when ' + '\n and '.join(checks) + ' then 1 else 0 end);\n'
    )
    return migration, verifier


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--version', default='20260919250000')
    args = parser.parse_args()
    migration, verifier = compile_sql(args.version)
    slug = f'{args.version}_chilean_bicycle_language.sql'
    migration_path = ROOT / 'supabase' / 'migrations' / slug
    verifier_path = ROOT / 'supabase' / 'manual_checks' / 'verification' / slug
    migration_path.write_text(migration, encoding='utf-8')
    verifier_path.write_text(verifier, encoding='utf-8')
    print(
        f'wrote {migration_path.relative_to(ROOT)} and its verifier: '
        f'{len(DEFINITION_LABELS)} labels, {len(TEMPLATE_METADATA)} templates, '
        f'{sum(map(len, HELPER_PATCHES.values()))} helpers'
    )


if __name__ == '__main__':
    main()
