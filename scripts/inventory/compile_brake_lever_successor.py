#!/usr/bin/env python3
"""Prepare a source-adjudicated lever owner; never publish or fill products."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import uuid

from compile_existing_spec_publication import (
    compile_packet, generate_migration, generate_verifier, load_pinned,
    preimage_query,
)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json
from compile_brake_piece_successors import CATALOG_SHA

PREFIX = 'brake-lever-2026-09-15'
UNKNOWN = 'Desconocido / sin confirmar'
MECHANICAL = 'Mecánico (cable)'
HYDRAULIC = 'Hidráulico'
LONG = 'Tiro largo (V-brake / disco mecánico tiro largo)'
SHORT = 'Tiro corto (ruta / cantilever / caliper)'
CLAMP = 'Abrazadera externa'
EXPANDER = 'Expansor interno'
SPECIFIC = 'Montaje específico del modelo'
ANCHORED = 'Cabeza de cable anclada'
INLINE = 'Cable pasante en línea'
DUAL = 'Ambos usos documentados por el OEM'
PRIMARY = 'Principal'
SUB = 'Auxiliar en línea'


def condition(*predicates):
    return {'kind': 'when', 'rows': [[{'field': key, 'operator': 'in' if isinstance(value, list) else 'eq',
        'value_type': 'token', 'value': value} for key, value in predicates]]}


def definition(key, label, kind='single_select', options=(), rules=None, unit=None):
    return {'id': str(uuid.uuid5(uuid.NAMESPACE_URL, 'vinabike:spec-definition:' + key)),
        'key': key, 'origin': 'new', 'label': label, 'data_type': kind, 'unit': unit,
        'allowed_values': list(options), 'validation_rules': rules or {}, 'used_by': ['brake_lever']}


def column(key, label, kind='text', *, required=False, options=()):
    return {'key': key, 'label': label, 'type': kind,
            **({'required': True} if required else {}),
            **({'allowed_values': list(options)} if options else {})}


def row_definition(key, label, columns, unique):
    return definition(key, label, 'json', rules={'rows_schema': {
        'version': 1, 'columns': columns, 'unique_by': unique}})


def build_catalog(before):
    original = load_pinned(RESEARCH / 'original-successors-integrated-catalog-2026-09-08.json', CATALOG_SHA)
    template = deepcopy(next(t for t in original['templates'] if t['key'] == 'brake_lever'))
    live = next(t for t in before['templates'] if t['id'] == template['id'])
    actual = {d['key']: d for d in before['existing_definitions']}
    keys_by_id = {d['id']: d['key'] for d in actual.values()}
    live_fields = {keys_by_id[f['spec_definition_id']]: f for f in before['fields']}
    expected_live = {'spec_evidence_source', 'brake_position', 'brake_type',
                     'reach_adjust', 'caliper_hydraulic', 'brake_system'}
    if set(live_fields) != expected_live:
        raise ValueError('Review changed legacy lever field ownership before compiling')
    removed = {'fluid_type', 'hose_system_code', 'kit_members', 'integrated_shifter',
               'brake_external_hose_connection', 'brake_conversion_location',
               'brake_external_converter_model'}
    contract = template['form_contract']
    template['fields'] = [f for f in template['fields'] if f['key'] not in removed]
    for bucket in ('roles', 'semantic_roles', 'labels', 'helpers', 'allowed_when',
                   'required_when', 'prerequisites', 'allowed_options', 'evidence_requirements'):
        for key in removed:
            contract[bucket].pop(key, None)
    for field in template['fields']:
        key = field['key']
        if contract['roles'][key] == 'legacy':
            field.update(deepcopy(live_fields[key]))
            field.update(section_key='legacy', is_required=False)
            contract['semantic_roles'][key] = 'legacy'
            contract['allowed_when'][key] = {'kind': 'never'}
            for bucket in ('labels', 'helpers'):
                if key in live['form_contract'].get(bucket, {}):
                    contract[bucket][key] = live['form_contract'][bucket][key]
                else:
                    contract[bucket].pop(key, None)

    defs = {}
    def add(d, *, role='measurement', semantic='compatibility', allowed=None,
            required=False, helper=None, prerequisites=()):
        key = d['key']; defs[key] = d
        template['fields'].append({'key': key, 'section_key': role,
            'sort_order': 300 + len(template['fields']), 'is_required': False,
            'visibility_rules': [], 'option_rules': [], 'constraint_rules': []})
        contract['roles'][key] = role
        contract['semantic_roles'][key] = semantic
        contract['allowed_when'][key] = deepcopy(allowed or {'kind': 'always'})
        contract['required_when'][key] = deepcopy(allowed or {'kind': 'always'}) if required else {'kind': 'never'}
        contract['evidence_requirements'][key] = 'oem_or_package'
        if helper: contract['helpers'][key] = helper
        if prerequisites: contract['prerequisites'][key] = list(prerequisites)

    mech = condition(('brake_actuation', MECHANICAL))
    hydraulic = condition(('brake_actuation', HYDRAULIC))
    clamped = condition(('lever_mount_method', CLAMP))
    expanded = condition(('lever_mount_method', EXPANDER))
    anchor = condition(('brake_actuation', MECHANICAL), ('lever_cable_interface', [ANCHORED, DUAL]))
    add(definition('lever_side', 'Lado de la maneta', options=['Izquierda', 'Derecha', 'Ambidiestra', UNKNOWN]),
        role='primary', semantic='intrinsic', required=True,
        helper='Lado físico de esta pieza. No determina qué rueda frena; no se deduce por país o marca.')
    add(definition('lever_mount_method', 'Fijación de la maneta al manubrio', options=[CLAMP, EXPANDER, SPECIFIC, UNKNOWN]),
        role='primary', semantic='intrinsic', required=True,
        helper='Distingue el diámetro exterior de una abrazadera del diámetro interior que recibe un expansor.')
    for key, label in [('lever_bar_bore_min_mm', 'Diámetro interior mínimo admitido'),
                       ('lever_bar_bore_max_mm', 'Diámetro interior máximo admitido')]:
        add(definition(key, label, 'number', rules={'positive': True}, unit='mm'),
            allowed=expanded, required=True,
            helper='Rango de montaje de este expansor publicado por el OEM; no es diámetro exterior del manubrio.')
    add(definition('lever_mount_oem_interface', 'Interfaz específica de montaje', 'text'),
        allowed=condition(('lever_mount_method', SPECIFIC)), required=True,
        helper='Modelo o código de la interfaz receptora; una marca sin modelo no identifica el montaje.')
    add(definition('lever_mount_clearance_mm', 'Espacio recto de montaje requerido', 'number',
        rules={'positive': True}, unit='mm'), allowed=clamped,
        helper='Longitud libre de manubrio exigida por el OEM. No se deduce del diámetro ni del ancho visual de la abrazadera.')
    add(definition('lever_cable_interface', 'Interfaz de cable de la maneta', options=[ANCHORED, INLINE, DUAL, UNKNOWN]),
        role='primary', semantic='intrinsic', allowed=mech, required=True,
        helper='Una maneta en línea puede actuar sobre la funda con el cable pasante. Ambos usos requiere documentación del mismo modelo.')
    add(row_definition('lever_cable_head_profiles', 'Cabezas de cable admitidas', [
        column('profile', 'Perfil', 'token', required=True, options=['Barril', 'Pera', 'Específico OEM']),
        column('oem_spec', 'Código o dimensiones OEM', required=True),
        column('source_url', 'Fuente del perfil admitido', 'url', required=True),
    ], [['profile', 'oem_spec']]), allowed=anchor,
        helper='Describe el alojamiento de esta maneta. Doble cabeza describe un cable sin cortar, no un alojamiento universal.')
    adjustable = condition(('brake_actuation', MECHANICAL), ('lever_cable_pull', 'Ajustable'))
    add(row_definition('lever_cable_pull_positions', 'Posiciones documentadas del tiro ajustable', [
        column('position_id', 'Posición de ajuste', required=True),
        column('pull', 'Tiro entregado', 'token', required=True, options=[SHORT, LONG]),
        column('setup_note', 'Condición de montaje'),
        column('source_url', 'Fuente del ajuste', 'url', required=True),
    ], [['position_id']]), allowed=adjustable, required=True,
        helper='Ajustable no significa compatible en cualquier posición. Cada fila identifica la posición y el tiro que entrega.')
    add(definition('lever_hydraulic_role', 'Función hidráulica de la maneta', options=[PRIMARY, SUB, UNKNOWN]),
        role='primary', semantic='intrinsic', allowed=hydraulic, required=True,
        helper='La maneta auxiliar en línea conecta con un mando principal y con el resto del circuito. No es un par de manetas.')
    add(row_definition('lever_inline_hydraulic_ports', 'Conexiones de la maneta hidráulica en línea', [
        column('port_id', 'Identificador del puerto físico', required=True),
        column('connection_side', 'Extremo de conexión', 'token', required=True,
               options=['Hacia el mando principal', 'Hacia la pinza']),
        column('fitting_model', 'Conector del modelo'),
        column('connection_spec', 'Especificación de la conexión'),
        column('source_url', 'Fuente OEM', 'url', required=True),
    ], [['port_id']]), allowed=condition(('brake_actuation', HYDRAULIC), ('lever_hydraulic_role', SUB)),
        helper='Un puerto de esta pieza por fila. Los nombres indican extremos de conexión, no una dirección permanente del flujo. No valida el circuito completo.')
    add(deepcopy(original['definitions']['brake_bleed_ports']), role='declaration', allowed=hydraulic,
        helper='Sólo puertos que el procedimiento OEM identifica para purgar esta maneta. No convierte un tornillo de sellado en purgador.')
    add(definition('shifter_mount_interface', 'Anclaje para mando separado', options=[
        'Sin anclaje para mando separado', 'I-SPEC EV', 'I-SPEC II', 'MatchMaker X', 'Otro sistema OEM', UNKNOWN]),
        helper='Interfaz propia, sin sumar compatibilidades de adaptadores ni afirmar que un mando viene incluido.')
    add(definition('lever_control_mount_oem_code', 'Código del anclaje para mando', 'text'),
        allowed=condition(('shifter_mount_interface', 'Otro sistema OEM')), required=True)

    contract['allowed_when']['handlebar_clamp_mm'] = clamped
    contract['required_when']['handlebar_clamp_mm'] = deepcopy(clamped)
    contract['helpers']['handlebar_clamp_mm'] = 'Diámetro exterior de la sección donde se fija esta maneta. No se restringe a 22,2 o 23,8 ni se deduce del tiro.'
    contract['required_when']['brake_position'] = {'kind': 'never'}
    contract['roles']['brake_position'] = 'declaration'
    contract['semantic_roles']['brake_position'] = 'compatibility'
    for field in template['fields']:
        if field['key'] == 'brake_position': field['section_key'] = 'declaration'
    contract['helpers']['brake_position'] = 'Destino declarado por la presentación. Izquierda y derecha no determinan delantero o trasero.'
    contract['helpers']['brake_actuation'] = 'Cómo acciona esta maneta. Una maneta de cable que mueve un convertidor sigue siendo mecánica.'
    contract['allowed_when']['brake_model_fluid_approvals'] = hydraulic
    contract['required_when']['brake_model_fluid_approvals'] = deepcopy(hydraulic)
    contract['allowed_when']['brake_piece_hydraulic_ports'] = condition(('brake_actuation', HYDRAULIC), ('lever_hydraulic_role', PRIMARY))
    contract['helpers']['brake_piece_hydraulic_ports'] = 'Salidas hidráulicas de la maneta principal. La auxiliar en línea tiene su propia tabla de conexiones.'
    contract['scalar_ordered_pairs'] = [['lever_bar_bore_min_mm', 'lever_bar_bore_max_mm']]
    rows = contract['row_conditions']['fields']
    rows['brake_piece_hydraulic_ports'] = {'allowed_options': {'end_role': ['Salida']}}
    rows['brake_bleed_ports'] = {'allowed_options': {'component_role': ['Maneta']}}
    used = {f['key'] for f in template['fields']}
    for key in used:
        if key not in defs: defs[key] = deepcopy(original['definitions'][key])
        if key in actual:
            # Current global definitions, including flags/options, are inputs.
            defs[key].update({k: deepcopy(actual[key][k]) for k in (
                'id', 'key', 'label', 'data_type', 'unit', 'allowed_values', 'validation_rules')})
            defs[key]['origin'] = 'existing'
    return {'schema_version': 2, 'templates': [template], 'definitions': defs,
            'source_catalog_sha256': CATALOG_SHA, 'mechanical_coverage_complete': False,
            'automatic_fill_authorized': False, 'publication_authorized': False}


def build_cases(catalog_sha):
    cases = []
    def add(name, values, *, blocking=(), pending=(), absent=()):
        issues = [{'code': c, 'field': f} for c, f in blocking]
        sql_codes = {'constraint': 'field_constraint', 'row_shape': 'field_constraint'}
        item = {'id': 'lever_' + name, 'template': 'brake_lever', 'values': values,
            'kind': 'synthetic_boundary', 'facts_verified_for_product': False,
            'automatic_fill_authorized': False, 'expected_blocking': issues,
            'expected_sql_blocking': sorted(
                [{**i, 'code': sql_codes.get(i['code'], i['code'])} for i in issues],
                key=lambda i: (i['code'], i['field'])),
            'expected_issue_subset': [{'code': 'required_missing', 'field': k, 'blocking': False} for k in pending],
            'forbidden_issue_fields': list(absent)}
        item['expected_sql_issue_subset'] = deepcopy(item['expected_issue_subset'])
        cases.append(item)
    def row(values):
        return {'schema_version': 1, 'rows': [{'id': 'r1', 'sources': [], 'values': {
            **values, 'source_url': 'https://example.invalid/lever'}}]}
    base = {'brake_actuation': MECHANICAL, 'lever_side': 'Izquierda',
            'lever_mount_method': CLAMP, 'handlebar_clamp_mm': '22.2',
            'lever_cable_interface': ANCHORED, 'lever_cable_pull': SHORT}
    hydro = {**base, 'brake_actuation': HYDRAULIC, 'lever_hydraulic_role': PRIMARY}
    for key in ('lever_cable_pull', 'lever_cable_interface'): hydro.pop(key)
    add('unanswered_identity_pending', {}, pending=('brake_actuation', 'lever_side', 'lever_mount_method'))
    add('mechanical_without_pull', {k: v for k, v in base.items() if k != 'lever_cable_pull'}, pending=('lever_cable_pull',))
    add('flat_bar_short_pull_is_valid', base)
    add('drop_bar_long_pull_is_valid', {**base, 'handlebar_clamp_mm': '23.8', 'lever_cable_pull': LONG})
    add('inline_clamp_is_not_limited_to_drop_diameter', {**base, 'handlebar_clamp_mm': '31.8', 'lever_cable_interface': INLINE})
    add('inline_cable_has_no_anchored_head', {**base, 'lever_cable_interface': INLINE,
        'lever_cable_head_profiles': row({'profile': 'Barril', 'oem_spec': 'Synthetic barrel interface'})}, blocking=(('field_applicability', 'lever_cable_head_profiles'),))
    add('dual_use_has_documented_head', {**base, 'lever_cable_interface': DUAL,
        'lever_cable_head_profiles': row({'profile': 'Barril', 'oem_spec': 'Synthetic barrel interface'})})
    add('universal_uncut_cable_is_not_a_socket', {**base,
        'lever_cable_head_profiles': row({'profile': 'Doble cabeza (universal)', 'oem_spec': 'Synthetic barrel interface'})}, blocking=(('row_shape', 'lever_cable_head_profiles'),))
    duplicate = row({'profile': 'Barril', 'oem_spec': 'Synthetic barrel interface'})
    duplicate['rows'].append({**deepcopy(duplicate['rows'][0]), 'id': 'r2'})
    add('duplicate_head_interface_rejected', {**base, 'lever_cable_head_profiles': duplicate},
        blocking=(('row_shape', 'lever_cable_head_profiles'),))
    expanded = {**base, 'lever_mount_method': EXPANDER,
                'lever_bar_bore_min_mm': '19', 'lever_bar_bore_max_mm': '22'}
    expanded.pop('handlebar_clamp_mm')
    add('bar_end_uses_bore_range', expanded)
    add('bar_end_cannot_claim_external_clamp', {**expanded, 'handlebar_clamp_mm': '22.2'}, blocking=(('field_applicability', 'handlebar_clamp_mm'),))
    add('clamp_cannot_claim_bore', {**base, 'lever_bar_bore_min_mm': '19'}, blocking=(('field_applicability', 'lever_bar_bore_min_mm'),))
    add('bore_max_pending', {k: v for k, v in expanded.items() if k != 'lever_bar_bore_max_mm'}, pending=('lever_bar_bore_max_mm',))
    add('bore_range_cannot_be_reversed', {**expanded, 'lever_bar_bore_min_mm': '22', 'lever_bar_bore_max_mm': '19'},
        blocking=(('range_order', 'lever_bar_bore_min_mm'), ('range_order', 'lever_bar_bore_max_mm')))
    add('adjustable_requires_positions', {**base, 'lever_cable_pull': 'Ajustable'}, pending=('lever_cable_pull_positions',))
    add('adjustable_position_names_actual_pull', {**base, 'lever_cable_pull': 'Ajustable',
        'lever_cable_pull_positions': row({'position_id': 'inner pivot', 'pull': SHORT})})
    add('fixed_pull_does_not_claim_adjustable_positions', {**base,
        'lever_cable_pull_positions': row({'position_id': 'inner pivot', 'pull': SHORT})}, blocking=(('field_applicability', 'lever_cable_pull_positions'),))
    add('hydraulic_pull_is_foreign', {**hydro, 'lever_cable_pull': LONG}, blocking=(('field_applicability', 'lever_cable_pull'),))
    add('hydraulic_role_pending', {k: v for k, v in hydro.items() if k != 'lever_hydraulic_role'}, pending=('lever_hydraulic_role',))
    add('hydraulic_fluid_approval_pending', hydro, pending=('brake_model_fluid_approvals',))
    for role in ('Salida', 'Entrada', 'Purgador'):
        add('principal_port_' + role, {**hydro, 'brake_piece_hydraulic_ports': row({
            'port_id': 'p1', 'end_role': role, 'source_scope': 'Synthetic port'})},
            blocking=() if role == 'Salida' else (('row_option', 'brake_piece_hydraulic_ports'),))
    inline_ports = row({'port_id': 'p1', 'connection_side': 'Hacia el mando principal'})
    add('hydraulic_inline_has_upstream_port', {**hydro, 'lever_hydraulic_role': SUB,
        'lever_inline_hydraulic_ports': inline_ports})
    add('principal_cannot_claim_inline_ports', {**hydro, 'lever_inline_hydraulic_ports': inline_ports},
        blocking=(('field_applicability', 'lever_inline_hydraulic_ports'),))
    add('inline_cannot_claim_principal_ports', {**hydro, 'lever_hydraulic_role': SUB,
        'brake_piece_hydraulic_ports': row({'port_id': 'p1', 'end_role': 'Salida', 'source_scope': 'fixture'})},
        blocking=(('field_applicability', 'brake_piece_hydraulic_ports'),))
    for role in ('Maneta', 'Cáliper', 'Convertidor'):
        add('bleed_port_' + role, {**hydro, 'brake_bleed_ports': row({'port_id': 'bleed1', 'component_role': role})},
            blocking=() if role == 'Maneta' else (('row_option', 'brake_bleed_ports'),))
    add('mechanical_has_no_bleed_port', {**base, 'brake_bleed_ports': row({'port_id': 'bleed1', 'component_role': 'Maneta'})},
        blocking=(('field_applicability', 'brake_bleed_ports'),))
    for actuation in ('Híbrido (cable a hidráulico)', 'Contrapedal'):
        add('actuation_' + actuation, {'brake_actuation': actuation}, blocking=(('constraint', 'brake_actuation'),))
    for side in ('Izquierda', 'Derecha', 'Ambidiestra'):
        add('side_does_not_imply_wheel_' + side, {**base, 'lever_side': side, 'brake_position': 'Delantero'})
    add('other_control_interface_requires_code', {**base, 'shifter_mount_interface': 'Otro sistema OEM'}, pending=('lever_control_mount_oem_code',))
    add('no_mount_cannot_claim_other_interface', {**base, 'shifter_mount_interface': 'Sin anclaje para mando separado',
        'lever_control_mount_oem_code': 'something'}, blocking=(('field_applicability', 'lever_control_mount_oem_code'),))
    add('legacy_not_promoted', {'brake_system': 'Shimano', 'caliper_hydraulic': True},
        pending=('brake_actuation',), absent=('brake_system', 'caliper_hydraulic'))
    return {'schema_version': 1, 'catalogue_sha256': catalog_sha, 'cases': cases, 'pending_cases': []}


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit('Usage: compile_brake_lever_successor.py preimage.json [--query]')
    path = Path(sys.argv[1]); before = json.loads(path.read_text())[0]['metadata']
    catalog = build_catalog(before)
    if len(sys.argv) == 3:
        assert sys.argv[2] == '--query'
        print(preimage_query(catalog, ['brake_lever']))
        return
    cp = RESEARCH / (PREFIX + '-catalog.json'); write_json(cp, catalog)
    sha = hashlib.sha256(cp.read_bytes()).hexdigest()
    cases = build_cases(sha); case_path = RESEARCH / (PREFIX + '-cases.json'); write_json(case_path, cases)
    before['existing_definitions'] = [d for d in before['existing_definitions'] if d['key'] in catalog['definitions']]
    packet = compile_packet(catalog=catalog, cases=cases, before=before, families=['brake_lever'],
        hashes={'catalog_sha256': sha, 'cases_sha256': hashlib.sha256(case_path.read_bytes()).hexdigest(),
                'preimage_sha256': hashlib.sha256(path.read_bytes()).hexdigest()},
        adjudication={'status': 'root_candidate_pending_review',
            'scope': 'One complete physical brake lever, primary or inline, external clamp or internal expander. No assemblies or replacement blades.',
            'root_corrections_to_228': ['inline hydraulic topology', 'external versus internal mounting',
                'anchored versus passing cable', 'adjustable pull positions', 'head socket versus uncut cable'],
            'absent_legacy_not_created': ['fluid_type', 'hose_system_code'],
            'shared_definitions_unchanged': True, 'compatibility_and_fill_not_approved': True})
    for d in packet['records']['spec_definitions']:
        if d['data_type'] != 'json':
            d.update(is_customer_visible=True, is_filterable=True)
    write_json(RESEARCH / (PREFIX + '-packet.json'), packet)
    (ROOT / '.tmp/db' / (PREFIX + '-candidate.sql')).write_text(generate_migration(packet, source_sha=sha))
    (ROOT / '.tmp/db' / (PREFIX + '-verification.sql')).write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': 1, 'new_definitions': len(packet['records']['spec_definitions']),
        'cases': len(cases['cases']), 'version': packet['records']['spec_templates'][0]['contract_version'],
        'published': False, 'facts_changed': 0}))


if __name__ == '__main__':
    main()
