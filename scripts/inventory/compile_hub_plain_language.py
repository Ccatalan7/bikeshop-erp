#!/usr/bin/env python3
"""Hub sheet in the words of a Chilean bike mechanic (2026-09-17).

The owner opened the hub sheet and could not follow it: «PCD brida
izquierda», «Centro a brida izquierda», «Dónde se mide el diámetro del eje»,
«Completa primero Fuente de la declaración, Posición de la maza». The labels
are global definitions (`spec_definitions.label`, tenant_id null) and the
helper texts live in the hub template contract (`form_contract->'helpers'`),
where the engine-era wording came from the 2026-09-16 successor packet.

This compiler emits one rerunnable migration and its verifier:
  * relabels the hub definitions by key (a few are shared: `spec_evidence_source`
    is in every template, `rotor_mount_type` in rotor and wheel,
    `bearing_system` in headset, `hub_old_mm` in fork and wheel,
    `spoke_hole_count` in rim — the new wording reads correctly there too);
  * replaces the hub contract helpers with one short explanation per field,
    the way the mechanic would say it, with the usual values as examples.
Option labels are untouched: the contract references them by token.

Usage: compile_hub_plain_language.py [--version 20260917210000]
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

DEFINITION_LABELS = {
    'spec_evidence_source': 'Fuente del dato',
    'hub_old_mm': 'Ancho entre tuercas (OLD)',
    'spoke_hole_count': 'Cantidad de hoyos (rayos)',
    'hub_spoke_head_interface': 'Tipo de rayo (con codo o recto)',
    'bearing_system': 'Tipo de rodamiento',
    'rotor_mount_type': 'Anclaje del disco (6 pernos o Centerlock)',
    'hub_drive_receiver_present': 'Lleva núcleo o rosca para piñón',
    'hub_drive_receiver_kind': 'Tipo de núcleo',
    'hub_drive_receiver_reference': 'Modelo del núcleo',
    'flange_pcd_left_mm': 'Círculo de hoyos, brida izquierda (PCD)',
    'flange_pcd_right_mm': 'Círculo de hoyos, brida derecha (PCD)',
    'center_to_flange_left_mm': 'Del centro a la brida izquierda',
    'center_to_flange_right_mm': 'Del centro a la brida derecha',
    'hub_flange_to_flange_mm': 'Entre bridas (centro a centro)',
    'spoke_hole_diameter_mm': 'Diámetro del hoyo del rayo',
    'hub_axle_diameter_datum': 'Dónde se mide el eje',
    'hub_supplied_thru_axle_reference': 'Modelo del eje pasante incluido',
    'hub_package_pieces': 'Mazas de este juego',
}

HUB_HELPERS = {
    'hub_package_position': 'Qué viene en la caja: una maza delantera, una trasera, o el juego de las dos. Si es el juego, cada maza va en su propia fila más abajo y no se llena un solo ancho ni una sola perforación.',
    'spec_evidence_source': 'Pega el link de la página del fabricante, o escribe «manual» o «caja» si lo leíste ahí. Sin fuente, los demás datos quedan como no confirmados.',
    'hub_old_mm': 'De tuerca a tuerca del eje, donde la maza apoya en el cuadro o la horquilla. Lo normal: 100 delante; 135 atrás con cierre rápido; 142 o 148 con eje pasante. Un juego de dos mazas no tiene un solo ancho.',
    'spoke_hole_count': 'Cuántos rayos lleva la rueda. Lo común es 32 o 36; cuenta los hoyos de una brida.',
    'hub_axle_mount_kind': 'Cierre rápido: eje hueco con palanca (9 o 10 mm). Eje pasante: eje grueso de 12 o 15 mm que se enrosca al cuadro. Con tuercas: eje macizo con una tuerca a cada lado.',
    'hub_spoke_head_interface': 'Con codo (J-bend) es el rayo de siempre, con la cabeza doblada que entra por el hoyo de la brida. Recto (straight pull) entra derecho. Si el fabricante no lo dice, déjalo sin confirmar.',
    'hub_rotor_mount_present': 'Sí si la maza trae dónde afirmar el disco de freno. No si es para freno de llanta (V-brake o caliper).',
    'rotor_mount_type': '6 pernos: el disco va apernado con seis pernos Torx. Centerlock: el disco entra estriado y se afirma con un anillo.',
    'bearing_system': 'Sellados: rodamientos de cartucho, se cambian enteros. Bolas sueltas: bolitas con conos y tazas, se ajustan y se engrasan.',
    'hub_drive_receiver_present': 'Sólo para mazas traseras. Sí si trae el núcleo para cassette o el hilo para piñón de rosca.',
    'hub_drive_receiver_kind': 'Núcleo de cassette (HG de Shimano, Micro Spline, XD) o rosca para piñón de rueda libre. Contrapedal es un freno: no dice por sí solo qué piñón acepta.',
    'hub_drive_receiver_reference': 'El nombre exacto del núcleo según el fabricante (por ejemplo «HG 8-11v» o «Micro Spline»), si lo publica.',
    'flange_pcd_left_mm': 'Diámetro del círculo que forman los hoyos de los rayos en la brida izquierda (lado del disco). Se mide de centro de hoyo a centro del hoyo de enfrente.',
    'flange_pcd_right_mm': 'Diámetro del círculo que forman los hoyos de los rayos en la brida derecha (lado del piñón). Se mide de centro de hoyo a centro del hoyo de enfrente.',
    'center_to_flange_left_mm': 'Desde el centro de la maza (la mitad del ancho entre tuercas) hasta el centro de la brida izquierda. Si el fabricante mide desde la tuerca, convierte antes de escribir; no lo copies tal cual.',
    'center_to_flange_right_mm': 'Desde el centro de la maza hasta el centro de la brida derecha, medido igual que el lado izquierdo.',
    'hub_flange_to_flange_mm': 'De centro de una brida al centro de la otra. Es la suma de las dos distancias al centro, no una de ellas.',
    'spoke_hole_diameter_mm': 'Lo que mide el agujero de la brida por donde entra el rayo. Lo normal es 2,5 o 2,6 mm.',
    'hub_axle_diameter_datum': 'Escribe dónde se mide: por fuera del eje (lo que se ve en la puntera), en el paso por dentro de la maza, u otro punto que indique el fabricante. Ojo: el perno del cierre rápido no es el eje.',
    'hub_axle_diameter_mm': 'Grosor del eje en el punto que indicaste arriba. Cierre rápido: 9 o 10 mm. Pasante: 12 o 15 mm.',
    'hub_thru_axle_supplied': 'Sí sólo si el eje pasante viene en la caja.',
    'hub_supplied_thru_axle_reference': 'El código del eje que viene. Su rosca y su largo son del eje y del cuadro, no de la maza.',
    'hub_package_pieces': 'Sólo lo que viene en la caja: una fila por maza. No es la lista de variantes del fabricante ni una rueda armada.',
    'hub_package_piece_count': 'Cuántas mazas trae el juego (normalmente dos: delantera y trasera). Confírmalo con la fuente, no por el título.',
}


def q(text: str) -> str:
    return "'" + text.replace("'", "''") + "'"


def compile_sql(version: str) -> tuple[str, str]:
    keys = list(DEFINITION_LABELS)
    key_list = ','.join(q(k) for k in keys)
    helpers_json = json.dumps(HUB_HELPERS, ensure_ascii=False, sort_keys=True)
    lines = [
        '-- Hub sheet in the words of a Chilean bike mechanic (2026-09-17).',
        '-- Relabels the hub definitions by key and replaces the hub contract helpers',
        '-- with one plain explanation per field. Facts, values, option labels, rules',
        '-- and flags are untouched; the revision trigger bumps the contract_version.',
        '-- Rerunnable: every update is conditional on the old wording.',
        f'-- Generated by scripts/inventory/compile_hub_plain_language.py --version {version}.',
        'begin;',
        "set local lock_timeout='5s';",
        "set local statement_timeout='120s';",
        'do $guard$ begin',
        f' if (select count(*) from public.spec_definitions where tenant_id is null and key in ({key_list})) <> {len(keys)} then',
        "  raise exception 'A relabeled definition is missing among the global definitions';",
        ' end if;',
        " if (select count(*) from public.spec_templates where tenant_id is null and key='hub') <> 1 then",
        "  raise exception 'The global hub template is missing';",
        ' end if;',
        'end $guard$;',
    ]
    for key, label in DEFINITION_LABELS.items():
        lines.append(
            f'update public.spec_definitions set label={q(label)}, updated_at=now() '
            f'where tenant_id is null and key={q(key)} and label is distinct from {q(label)};')
    lines.append(
        'update public.spec_templates set form_contract = jsonb_set(form_contract, \'{helpers}\', '
        f"coalesce(form_contract->'helpers','{{}}'::jsonb) || {q(helpers_json)}::jsonb), updated_at=now() "
        "where tenant_id is null and key='hub' and "
        f"(form_contract->'helpers') is distinct from (coalesce(form_contract->'helpers','{{}}'::jsonb) || {q(helpers_json)}::jsonb);")
    lines.append('commit;')
    migration = '\n'.join(lines) + '\n'

    checks = [
        f"(select count(*) from public.spec_definitions where tenant_id is null and key={q(k)} and label={q(v)})=1"
        for k, v in DEFINITION_LABELS.items()
    ]
    checks += [
        f"(select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>{q(k)}={q(v)})=1"
        for k, v in HUB_HELPERS.items()
    ]
    verifier = (
        '-- Verifier: fails (division by zero) until every hub label and helper is in place.\n'
        'select 1/(case when ' + '\n and '.join(checks) + ' then 1 else 0 end);\n'
    )
    return migration, verifier


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--version', default='20260917210000')
    args = parser.parse_args()
    migration, verifier = compile_sql(args.version)
    slug = f'{args.version}_hub_plain_language.sql'
    (ROOT / 'supabase' / 'migrations' / slug).write_text(migration, encoding='utf-8')
    (ROOT / 'supabase' / 'manual_checks' / 'verification' / slug).write_text(verifier, encoding='utf-8')
    print(f'wrote supabase/migrations/{slug} and its verifier: {len(DEFINITION_LABELS)} labels, {len(HUB_HELPERS)} helpers')


if __name__ == '__main__':
    main()
