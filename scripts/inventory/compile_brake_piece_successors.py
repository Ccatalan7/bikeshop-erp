#!/usr/bin/env python3
"""Prepare three original piece owners against fresh metadata, never publish.

The frozen 37-family proposal stays untouched. Complete brakes and paired
presentations are outside this slice. Current field observations are preserved.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import uuid

from compile_existing_spec_publication import (
    compile_packet, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

PREFIX = 'brake-pieces-2026-09-15'
FAMILIES = ('brake_caliper', 'brake_pad', 'rotor')
CATALOG_SHA = 'e0cccea8cdea5835e47301d11060bc735454334a9bdf6e0666b9bb5b5d87b28d'
CASES_SHA = '3d8f9a4dd6c79af3ebeeacb730506d72479a057a3ef13b29bc06e6e9175e5af8'
# These are new scalar definitions with operator/customer meaning. Source URLs,
# OEM recipe rows and free-text approval lists stay outside automatic filters.
SURFACE_FIELDS = {
    'rotor_diameter_mm_value', 'rotor_nominal_thickness_mm', 'rotor_wear_limit_mm',
    'piston_count_value', 'braking_surface', 'cable_pull_required', 'pad_retention',
    'rim_pad_stud_type', 'rim_pad_construction', 'rim_pad_length_mm',
    'caliper_mount_interface',
}


def when(field, value):
    return {'kind': 'when', 'rows': [[{'field': field, 'operator': 'eq',
            'value_type': 'token', 'value': value}]]}


def attach(template, key, condition, *, role, semantic, label=None):
    template['fields'].append({'key': key, 'section_key': role,
        'sort_order': 300 + len(template['fields']), 'is_required': False,
        'visibility_rules': [], 'option_rules': [], 'constraint_rules': []})
    contract = template['form_contract']
    for section, value in [('roles', role), ('semantic_roles', semantic),
            ('allowed_when', condition), ('required_when', condition),
            ('evidence_requirements', 'oem_or_package')]:
        contract[section][key] = deepcopy(value)
    if label:
        contract['labels'][key] = label


def correct_piece_ownership(templates):
    """Adjudicated 225: interfaces belong to one piece, never its fitment rows."""
    caliper = next(t for t in templates if t['key'] == 'brake_caliper')
    contract = caliper['form_contract']
    removed = 'brake_external_converter_model'
    caliper['fields'] = [f for f in caliper['fields'] if f['key'] != removed]
    for section in ('roles', 'semantic_roles', 'labels', 'helpers', 'allowed_when',
                    'required_when', 'prerequisites', 'allowed_options', 'evidence_requirements'):
        contract.get(section, {}).pop(removed, None)
    contract['allowed_options'].update(
        braking_surface=['Disco', 'Llanta'],
        brake_conversion_location=['En esta pieza'])
    contract['helpers']['brake_actuation'] = (
        'Accionamiento de esta pieza. Si la mueve un convertidor externo, la '
        'pinza sigue siendo hidráulica; el convertidor se documenta en la '
        'presentación que lo incluye, no en esta pieza.')
    contract['helpers']['brake_conversion_location'] = (
        'Una pinza híbrida convierte el tiro de cable en presión dentro de sí '
        'misma. Un convertidor externo es otra pieza; no cambia el accionamiento '
        'hidráulico de la pinza que alimenta.')
    attach(caliper, 'caliper_mount_interface', when('braking_surface', 'Disco'),
           role='primary', semantic='intrinsic')
    attach(caliper, 'rim_pad_stud_type', when('braking_surface', 'Llanta'),
           role='measurement', semantic='compatibility',
           label='Fijación de zapata admitida por esta pinza')
    contract['helpers']['caliper_mount_interface'] = (
        'Interfaz física de esta pinza. El anclaje del cuadro u horquilla y el '
        'adaptador se declaran en cada montaje documentado; no sustituyen esta interfaz.')
    contract['required_when']['rotor_size_recipe'] = {'kind': 'never'}
    contract['helpers']['rotor_size_recipe'] = (
        'Montajes OEM documentados para esta pinza: posición, cuadro u horquilla, '
        'adaptador y rotor admitido. La interfaz propia se declara una vez arriba. '
        'No conocer una tabla de adaptadores deja su compatibilidad sin confirmar.')
    rows = contract['row_conditions']['fields']
    # Keep the shared schema available for assembly owners. This piece cannot
    # repeat or override its root model/mount inside a compatibility recipe.
    rows['rotor_size_recipe']['allowed_when'].update(
        caliper_mount={'kind': 'never'}, caliper_model={'kind': 'never'})
    rows['brake_piece_hydraulic_ports'] = {'allowed_options': {'end_role': ['Entrada']}}
    contract['helpers']['brake_piece_hydraulic_ports'] = (
        'Una entrada hidráulica de esta pinza por fila. El puerto de purga se '
        'documenta únicamente en Puertos de purga; no duplicarlo aquí.')
    contract['prerequisites'].pop('bleed_port', None)

    pad = next(t for t in templates if t['key'] == 'brake_pad')['form_contract']
    rim = when('braking_surface', 'Llanta')
    with_holder = deepcopy(rim)
    with_holder['rows'][0].append({'field': 'rim_pad_construction', 'operator': 'in',
        'value_type': 'token', 'value': ['Una pieza', 'Cartucho (porta-goma)']})
    pad['required_when']['rim_pad_construction'] = rim
    pad['allowed_when']['rim_pad_stud_type'] = deepcopy(with_holder)
    pad['required_when']['rim_pad_stud_type'] = deepcopy(with_holder)
    pad['helpers']['rim_pad_stud_type'] = (
        'Fijación del cuerpo completo o porta-goma. El recambio de goma no '
        'posee ese espárrago: declara la interfaz de cartucho compatible.')
    pad['helpers']['rim_pad_construction'] = (
        'Distingue la unidad completa, el porta-goma y el recambio de goma. '
        'Esta elección determina qué fijaciones pertenecen a la pieza.')


def ownership_cases():
    cases = []
    def add(name, family, values, *, blocking=(), pending=(), absent=()):
        item = {'id': 'brake_piece_' + name, 'template': family, 'values': values,
            'kind': 'synthetic_boundary', 'facts_verified_for_product': False,
            'automatic_fill_authorized': False,
            'expected_blocking': [{'code': c, 'field': f} for c, f in blocking],
            'expected_issue_subset': [{'code': 'required_missing', 'field': f,
                                       'blocking': False} for f in pending],
            'forbidden_issue_fields': list(absent)}
        sql_codes = {'cardinality': 'field_constraint', 'constraint': 'field_constraint'}
        item['expected_sql_blocking'] = [
            {**i, 'code': sql_codes.get(i['code'], i['code'])}
            for i in item['expected_blocking']]
        item['expected_sql_issue_subset'] = deepcopy(item['expected_issue_subset'])
        cases.append(item)
    disc = {'braking_surface': 'Disco', 'brake_actuation': 'Mecánico (cable)'}
    add('disc_mount_is_pending', 'brake_caliper', disc, pending=('caliper_mount_interface',),
        absent=('rotor_size_recipe',))
    add('disc_mount_without_adapter_table', 'brake_caliper',
        {**disc, 'caliper_mount_interface': 'Flat Mount'},
        absent=('caliper_mount_interface', 'rotor_size_recipe'))
    add('disc_mount_cannot_be_multivalued', 'brake_caliper',
        {**disc, 'caliper_mount_interface': ['Flat Mount', 'Post Mount']},
        blocking=(('cardinality', 'caliper_mount_interface'),))
    recipe = {'schema_version': 1, 'rows': [{'id': 'r1', 'sources': [], 'values': {
        'configuration': 'Synthetic fitment', 'position': 'Delantero',
        'rotor_diameter_mm': '160', 'frame_mount': 'Post Mount',
        'adapter_required': False, 'source_url': 'https://example.invalid/fitment'}}]}
    for column, value in [('caliper_mount', 'Post Mount'), ('caliper_model', 'Another model')]:
        contradictory = deepcopy(recipe)
        contradictory['rows'][0]['values'][column] = value
        add('recipe_cannot_override_' + column, 'brake_caliper',
            {**disc, 'caliper_mount_interface': 'Flat Mount', 'rotor_size_recipe': contradictory},
            blocking=(('row_field_applicability', 'rotor_size_recipe'),))
    add('hybrid_conversion_is_inside', 'brake_caliper',
        {'braking_surface': 'Disco', 'brake_actuation': 'Híbrido (cable a hidráulico)',
         'brake_conversion_location': 'En un dispositivo externo'},
        blocking=(('constraint', 'brake_conversion_location'),))
    add('hub_brake_is_not_a_caliper', 'brake_caliper',
        {'braking_surface': 'Maza (banda / tambor / rodillo)'},
        blocking=(('constraint', 'braking_surface'),))
    port = {'schema_version': 1, 'rows': [{'id': 'p1', 'sources': [], 'values': {
        'port_id': 'p1', 'end_role': 'Entrada', 'source_scope': 'Synthetic inlet',
        'source_url': 'https://example.invalid/port'}}]}
    for role in ['Entrada', 'Salida', 'Purgador']:
        value = deepcopy(port); value['rows'][0]['values']['end_role'] = role
        add('caliper_port_' + role, 'brake_caliper',
            {'braking_surface': 'Disco', 'brake_actuation': 'Hidráulico',
             'brake_external_hose_connection': True, 'brake_piece_hydraulic_ports': value},
            blocking=() if role == 'Entrada' else (('row_option', 'brake_piece_hydraulic_ports'),))
    rim = {'braking_surface': 'Llanta'}
    add('rim_construction_pending', 'brake_pad', rim, pending=('rim_pad_construction',))
    for construction in ['Una pieza', 'Cartucho (porta-goma)']:
        add('holder_stud_pending_' + construction, 'brake_pad',
            {**rim, 'rim_pad_construction': construction}, pending=('rim_pad_stud_type',))
    insert = {**rim, 'rim_pad_construction': 'Recambio de cartucho'}
    add('cartridge_insert_has_no_stud', 'brake_pad', insert, absent=('rim_pad_stud_type',))
    add('cartridge_insert_cannot_claim_holder_stud', 'brake_pad',
        {**insert, 'rim_pad_stud_type': 'Espárrago roscado'},
        blocking=(('field_applicability', 'rim_pad_stud_type'),))
    add('rim_caliper_pad_attachment_pending', 'brake_caliper',
        {**rim, 'brake_actuation': 'Mecánico (cable)'}, pending=('rim_pad_stud_type',))
    add('rim_caliper_pad_attachment_declared', 'brake_caliper',
        {**rim, 'brake_actuation': 'Mecánico (cable)', 'rim_pad_stud_type': 'Poste liso'},
        absent=('rim_pad_stud_type',))
    return cases


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_brake_piece_successors.py <live-preimage.json>')
    path = Path(sys.argv[1]); before = json.loads(path.read_text())[0]['metadata']
    original = load_pinned(RESEARCH / 'original-successors-integrated-catalog-2026-09-08.json', CATALOG_SHA)
    old_cases = load_pinned(RESEARCH / 'original-successors-integrated-cases-2026-09-08.json', CASES_SHA)
    templates = deepcopy([t for t in original['templates'] if t['key'] in FAMILIES])
    actual_definitions = {d['id']: d['key'] for d in before['existing_definitions']}
    dropped = {}
    for template in templates:
        live = next(t for t in before['templates'] if t['id'] == template['id'])
        current = {actual_definitions[f['spec_definition_id']]: f for f in before['fields']
                   if f['template_id'] == template['id']}
        contract = template['form_contract']
        absent = {f['key'] for f in template['fields']
                  if contract['roles'].get(f['key']) == 'legacy' and f['key'] not in current}
        dropped[template['key']] = sorted(absent)
        template['fields'] = [f for f in template['fields'] if f['key'] not in absent]
        for section in ('roles', 'semantic_roles', 'labels', 'helpers', 'allowed_when',
                        'required_when', 'prerequisites', 'allowed_options', 'evidence_requirements'):
            for key in absent:
                contract.get(section, {}).pop(key, None)
        for field in template['fields']:
            key = field['key']
            if contract['roles'].get(key) == 'legacy':
                # Preserve real old helpers/defaults/options; do not relabel an
                # ambiguous measurement as a new intrinsic observation.
                field.update(deepcopy(current[key]))
                field.update(section_key='legacy', is_required=False)
                contract['semantic_roles'][key] = 'legacy'
                if key in live['form_contract'].get('labels', {}):
                    contract['labels'][key] = live['form_contract']['labels'][key]
                else:
                    contract['labels'].pop(key, None)
        if template['key'] == 'brake_pad':
            contract['helpers']['compound_type'] = (
                'Clase técnica del compuesto según su fuente. El nombre comercial '
                'se conserva por separado y puede conocerse antes que esta clasificación; '
                'no deducir una clase únicamente de ese nombre.')
    if dropped != {'brake_caliper': ['hose_system_code'], 'brake_pad': [], 'rotor': []}:
        raise ValueError('The observed legacy attachment boundary needs another review')
    correct_piece_ownership(templates)
    used = {f['key'] for t in templates for f in t['fields']}
    definitions = {k: deepcopy(original['definitions'][k]) for k in sorted(used)
                   if k in original['definitions']}
    definitions['caliper_mount_interface'] = {
        'id': str(uuid.uuid5(uuid.NAMESPACE_URL, 'vinabike:spec-definition:caliper_mount_interface')),
        'key': 'caliper_mount_interface', 'origin': 'new',
        'label': 'Montaje propio de la pinza', 'data_type': 'single_select', 'unit': None,
        'allowed_values': ['International Standard', 'Post Mount', 'Flat Mount',
                           'Desconocido / sin confirmar'], 'validation_rules': {},
        'used_by': ['brake_caliper']}
    catalog = {'schema_version': 2, 'templates': templates, 'definitions': definitions,
               'source_catalog_sha256': CATALOG_SHA, 'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False, 'publication_authorized': False}
    cp = RESEARCH / (PREFIX + '-catalog.json'); write_json(cp, catalog)
    sha = hashlib.sha256(cp.read_bytes()).hexdigest()
    cases = {'schema_version': 1, 'catalogue_sha256': sha,
             'cases': deepcopy([c for c in old_cases['cases'] if c['template'] in FAMILIES
                 and 'brake_external_converter_model' not in c['values']]),
             'pending_cases': deepcopy([c for c in old_cases['pending_cases']
                 if c.get('template') in FAMILIES or
                 ('template' not in c and c.get('source_package') == 'existing-brakes-catalog-2026-09-07.json')])}
    # Removed foreign-field fixtures are archived in reviewed-v1. The aggregate
    # writer (not the draft validator) owns rejection of unattached definitions.
    for case in cases['cases']:
        if case['id'] == 'bkx_the_same_port_twice_blocks':
            # The scoped port rules validate the row shape before options.
            # The same duplicate remains blocking in both engines.
            case['expected_sql_blocking'] = [
                {'code': 'row_shape', 'field': 'brake_piece_hydraulic_ports'}]
        if case['id'] == 'bkx_a_caliper_owns_its_ports':
            case['id'] = 'bkx_a_caliper_keeps_inlet_and_bleed_port_separate'
            ports = case['values']['brake_piece_hydraulic_ports']['rows']
            purge = next(row for row in ports if row['values']['end_role'] == 'Purgador')
            case['values']['brake_piece_hydraulic_ports']['rows'] = [
                row for row in ports if row is not purge]
            case['values']['brake_bleed_ports'] = {'schema_version': 1, 'rows': [{
                'id': purge['id'], 'sources': purge['sources'], 'values': {
                    'component_role': 'Cáliper', 'port_id': purge['values']['port_id'],
                    'source_url': purge['values']['source_url']}}]}
    cases['cases'].extend(ownership_cases())
    case_path = RESEARCH / (PREFIX + '-cases.json'); write_json(case_path, cases)
    # The captured unattached shared definition is evidence only. This publisher
    # neither attaches nor mutates it after retiring its prototype use.
    before['existing_definitions'] = [d for d in before['existing_definitions'] if d['key'] in used]
    packet = compile_packet(catalog=catalog, cases=cases, before=before, families=list(FAMILIES),
        hashes={'catalog_sha256': sha, 'cases_sha256': hashlib.sha256(case_path.read_bytes()).hexdigest(),
                'preimage_sha256': hashlib.sha256(path.read_bytes()).hexdigest()},
        adjudication={'status': 'candidate_under_independent_review',
                      'scope': 'Only physical brake caliper, brake pad and rotor owners. No complete assemblies.',
                      'absent_legacy_not_created': dropped,
                      'preserve_legacy_labels_helpers_defaults': True,
                      'compound_name_can_precede_technical_class': True,
                      'round_225_ownership_corrections': ['H1', 'H2', 'H3', 'H4'],
                      'shared_recipe_columns_disabled_only_for_piece_owner': True,
                      'compatibility_and_fill_not_approved': True})
    new_definitions = {d['key']: d for d in packet['records']['spec_definitions']}
    if not SURFACE_FIELDS <= new_definitions.keys():
        raise ValueError('Surface flags may only be assigned to reviewed new definitions')
    for key in SURFACE_FIELDS:
        new_definitions[key].update(is_customer_visible=True, is_filterable=True)
    packet['adjudication']['new_scalar_surfaces'] = sorted(SURFACE_FIELDS)
    write_json(RESEARCH / (PREFIX + '-packet.json'), packet)
    (ROOT / '.tmp/db' / (PREFIX + '-candidate.sql')).write_text(generate_migration(packet, source_sha=sha))
    (ROOT / '.tmp/db' / (PREFIX + '-verification.sql')).write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': len(templates), 'new_definitions': len(packet['records']['spec_definitions']),
                      'cases': len(cases['cases']), 'pending_cases': len(cases['pending_cases']),
                      'contract_versions': {t['key']: t['contract_version'] for t in packet['records']['spec_templates']},
                      'published': False, 'facts_changed': 0}))


if __name__ == '__main__':
    main()
