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
    'hub_old_mm': 'Ancho de la maza entre apoyos (OLD)',
    'spoke_hole_count': 'Cantidad de rayos / hoyos',
    'hub_spoke_head_interface': 'Tipo de rayo (con codo o recto)',
    'bearing_system': 'Tipo de rodamiento',
    'rotor_mount_type': 'Fijación del disco',
    'hub_drive_receiver_present': 'Tiene montaje para piñón',
    'hub_drive_receiver_kind': 'Sistema de montaje del piñón',
    'hub_drive_receiver_reference': 'Modelo exacto del núcleo o la rosca',
    'flange_pcd_left_mm': 'Diámetro del círculo de hoyos izquierdo',
    'flange_pcd_right_mm': 'Diámetro del círculo de hoyos derecho',
    'center_to_flange_left_mm': 'Del centro al círculo de hoyos izquierdo',
    'center_to_flange_right_mm': 'Del centro al círculo de hoyos derecho',
    'hub_flange_to_flange_mm': 'Distancia entre los círculos de hoyos',
    'spoke_hole_diameter_mm': 'Diámetro de cada hoyo para rayo',
    'hub_axle_diameter_datum': 'Punto donde se mide el diámetro del eje',
    'hub_supplied_thru_axle_reference': 'Modelo del eje pasante incluido',
    'hub_package_pieces': 'Mazas de este juego',
}

HUB_HELPERS = {
    'hub_package_position': 'Qué viene en la caja: una maza delantera, una trasera, o el juego de las dos. Si es el juego, cada maza va en su propia fila más abajo y no se llena un solo ancho ni una sola perforación.',
    'spec_evidence_source': 'Pega el link de la página del fabricante, o escribe «manual» o «caja» si lo leíste ahí. Sin fuente, los demás datos quedan como no confirmados.',
    'hub_old_mm': 'Ancho exterior de la maza, medido entre las dos caras que apoyan en el cuadro o la horquilla. En catálogos aparece como OLD. Valores comunes: 100 mm delante; 135 mm atrás con cierre rápido; 142 o 148 mm con eje pasante.',
    'spoke_hole_count': 'Cantidad total de rayos que lleva la maza. Cuenta los hoyos de ambos lados: una maza de 32H tiene 32 en total, normalmente 16 por lado.',
    'hub_axle_mount_kind': 'Cierre rápido: eje hueco con palanca (9 o 10 mm). Eje pasante: eje grueso de 12 o 15 mm que se enrosca al cuadro. Con tuercas: eje macizo con una tuerca a cada lado.',
    'hub_spoke_head_interface': 'Con codo es el rayo tradicional: la cabeza doblada entra por un hoyo lateral de la maza. Recto entra sin codo. En fichas del fabricante pueden aparecer como J-bend y straight pull.',
    'hub_rotor_mount_present': 'Sí si la maza trae una fijación para disco de freno. No si sólo sirve para freno de llanta.',
    'rotor_mount_type': '6 pernos: el disco se atornilla con seis pernos. Center Lock: el disco entra en una estría y se asegura con un anillo.',
    'bearing_system': 'Sellados: rodamientos de cartucho, se cambian enteros. Bolas sueltas: bolitas con conos y tazas, se ajustan y se engrasan.',
    'hub_drive_receiver_present': 'Sólo para mazas traseras. Sí si trae núcleo para cassette, hilo para piñón roscado u otro montaje documentado para el piñón.',
    'hub_drive_receiver_kind': 'Cómo se instala el piñón en esta maza trasera: sobre un núcleo estriado, en una rosca o mediante el sistema específico del fabricante.',
    'hub_drive_receiver_reference': 'Nombre exacto publicado por el fabricante, por ejemplo HG 8-11v, Micro Spline, XD o la medida de la rosca.',
    'flange_pcd_left_mm': 'Diámetro del círculo que forman los hoyos del lado izquierdo. Se mide desde el centro de un hoyo hasta el centro del hoyo opuesto. En catálogos puede aparecer como PCD.',
    'flange_pcd_right_mm': 'Diámetro del círculo que forman los hoyos del lado derecho. Se mide desde el centro de un hoyo hasta el centro del hoyo opuesto. En catálogos puede aparecer como PCD.',
    'center_to_flange_left_mm': 'Desde el centro de la maza hasta el plano donde están los hoyos del lado izquierdo. Si el fabricante mide desde el apoyo exterior, convierte la medida antes de escribirla.',
    'center_to_flange_right_mm': 'Desde el centro de la maza hasta el plano donde están los hoyos del lado derecho, medido igual que el lado izquierdo.',
    'hub_flange_to_flange_mm': 'Distancia entre los dos planos donde están los hoyos de los rayos. Debe coincidir con la suma de las dos distancias medidas desde el centro.',
    'spoke_hole_diameter_mm': 'Diámetro de un hoyo lateral por donde entra el rayo. Valores comunes: 2,5 o 2,6 mm.',
    'hub_axle_diameter_datum': 'Indica en qué parte se midió: en la zona que entra al cuadro o la horquilla, dentro de la maza u otro punto publicado por el fabricante. El perno fino del cierre rápido no es el diámetro del eje.',
    'hub_axle_diameter_mm': 'Grosor del eje en el punto que indicaste arriba. Cierre rápido: 9 o 10 mm. Pasante: 12 o 15 mm.',
    'hub_thru_axle_supplied': 'Sí sólo si el eje pasante viene en la caja.',
    'hub_supplied_thru_axle_reference': 'El código del eje que viene. Su rosca y su largo son del eje y del cuadro, no de la maza.',
    'hub_package_pieces': 'Sólo lo que viene en la caja: una fila por maza. No es la lista de variantes del fabricante ni una rueda armada.',
    'hub_package_piece_count': 'Cuántas mazas trae el juego (normalmente dos: delantera y trasera). Confírmalo con la fuente, no por el título.',
}

HUB_TEMPLATE_NAME = 'Maza'
HUB_TEMPLATE_DESCRIPTION = (
    'Mazas delanteras, traseras o juegos, con ancho, eje, rayos, freno y '
    'montaje del piñón.'
)


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
        'update public.spec_templates set '
        f'name={q(HUB_TEMPLATE_NAME)}, description={q(HUB_TEMPLATE_DESCRIPTION)}, updated_at=now() '
        "where tenant_id is null and key='hub' and "
        f'(name,description) is distinct from ({q(HUB_TEMPLATE_NAME)},{q(HUB_TEMPLATE_DESCRIPTION)});')
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
        f"(select count(*) from public.spec_templates where tenant_id is null and key='hub' and name={q(HUB_TEMPLATE_NAME)} and description={q(HUB_TEMPLATE_DESCRIPTION)})=1",
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
