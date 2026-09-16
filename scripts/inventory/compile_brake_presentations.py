#!/usr/bin/env python3
"""Prepare the three brake presentations and the caliper tool owner (D2, revision 223).

Adjudication 2026-09-15 accepted: an explicit presentation selector, the
circuit separated from its pieces, connections directed at row ids, and every
ambiguous live field retained as legacy. It rejected two ownership errors of
revision 222, both closed here:

* the caliper tool size does not stay in the presentation root; the owner is
  completed by attaching the existing ``tool_size_mm`` definition to
  ``brake_caliper``, and every presentation keeps its historical datum as
  legacy, unedited;
* the two mechanisms of a rim brake pair share nothing automatically: the
  root of ``rim_brake`` keeps no active mechanism field, each mechanism is a
  ``kit_members`` row with its own ``brake_caliper`` profile (braking surface
  «Llanta»), exactly like a disc caliper.

The presentation root declares only the presentation, its evidence, its
member rows and its circuits. No profile is compared with another; no
compatibility verdict exists. Never executes SQL.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import uuid

from compile_existing_spec_publication import (
    compile_packet, generate_migration as base_migration,
    generate_verifier as base_verifier, preimage_query)
from compile_member_profile_enablement import COLLECTIONS
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

PREFIX = 'brake-presentations-2026-09-16'
PRESENTATIONS = ('hydraulic_disc_brake', 'mechanical_disc_brake', 'rim_brake')
CALIPER = 'brake_caliper'
FAMILIES = PRESENTATIONS + (CALIPER,)
LIVE_FIELDS = {
    'hydraulic_disc_brake': ['spec_evidence_source', 'fluid_type', 'brake_system', 'mount_standard',
                             'piston_count', 'rotor_diameter_mm', 'reach_adjust', 'brake_position',
                             'hose_length_mm', 'pad_shape_code', 'hose_fitting_type', 'bleed_port'],
    'mechanical_disc_brake': ['spec_evidence_source', 'brake_system', 'mount_standard', 'rotor_diameter_mm',
                              'reach_adjust', 'tool_size_mm', 'brake_position', 'pad_shape_code'],
    'rim_brake': ['spec_evidence_source', 'tool_size_mm', 'brake_system', 'reach_adjust', 'brake_position'],
}
OPTIONS = {
    'hydraulic_disc_brake': ['Un freno completo (maneta, manguera, cáliper)', 'Par delantero y trasero',
                             'Cáliper con manguera, sin maneta'],
    'mechanical_disc_brake': ['Un freno completo (maneta, cable y funda, cáliper)', 'Par delantero y trasero',
                              'Cáliper sin maneta'],
    'rim_brake': ['Un mecanismo (un extremo)', 'Par de mecanismos', 'Set con manetas y cables'],
}
# Presentations whose circuits include a lever; a bare caliper or mechanism has no circuit.
WITH_CIRCUITS = {
    'hydraulic_disc_brake': OPTIONS['hydraulic_disc_brake'][:2],
    'mechanical_disc_brake': OPTIONS['mechanical_disc_brake'][:2],
    'rim_brake': OPTIONS['rim_brake'][2:],
}
MEMBER_FAMILIES = {
    'hydraulic_disc_brake': ['brake_lever', 'brake_caliper', 'hydraulic_hose', 'rotor',
                             'brake_mount_adapter', 'brake_pad', 'brake_fluid'],
    'mechanical_disc_brake': ['brake_lever', 'brake_caliper', 'control_cable', 'control_housing',
                              'rotor', 'brake_mount_adapter', 'brake_pad'],
    'rim_brake': ['brake_caliper', 'brake_lever', 'brake_pad', 'control_cable', 'control_housing'],
}
ACTUATION = {'hydraulic_disc_brake': ['Hidráulico'], 'mechanical_disc_brake': ['Cable'], 'rim_brake': ['Cable']}
FLUIDS = ['Aceite Mineral', 'DOT 4', 'DOT 5.1', 'Desconocido / sin confirmar']
# Successor prototypes that must not exist before or after (keys of the frozen 37 catalogue).
PROTOTYPES = ('brake_assembly_configurations', 'brake_circuit_connections', 'rotor_included_diameter_mm',
              'levers_included', 'rim_brake_style', 'lever_pull_required', 'brake_presentation_kind')
CIRCUIT_HELPER = (
    'Un circuito por freno accionado: qué maneta mueve qué cáliper o mecanismo y por qué '
    'línea, apuntando a las filas de piezas. El líquido con que se entrega es del circuito; '
    'el que cada pieza admite es de esa pieza. Declararlo no verifica que las piezas calcen.')


def definition_id(key):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'vinabike:spec-definition:' + key))


def when(field, operator, value):
    return {'kind': 'when', 'rows': [[{'field': field, 'operator': operator,
                                       'value_type': 'token', 'value': value}]]}


def new_definitions():
    presentation = {
        'id': definition_id('brake_presentation'), 'key': 'brake_presentation', 'origin': 'new',
        'label': 'Presentación de este freno', 'data_type': 'single_select', 'unit': None,
        'allowed_values': sorted({o for values in OPTIONS.values() for o in values}),
        'validation_rules': {}, 'used_by': list(PRESENTATIONS)}
    circuits = {
        'id': definition_id('brake_circuits'), 'key': 'brake_circuits', 'origin': 'new',
        'label': 'Circuitos de freno de esta presentación', 'data_type': 'json', 'unit': None,
        'allowed_values': [], 'used_by': list(PRESENTATIONS),
        'validation_rules': {'rows_schema': {'version': 1, 'unique_by': [['circuit_id']], 'columns': [
            {'key': 'circuit_id', 'type': 'text', 'label': 'Identificador del circuito', 'required': True},
            {'key': 'position', 'type': 'token', 'label': 'Rueda que frena', 'required': True,
             'allowed_values': ['Delantero', 'Trasero', 'Único']},
            {'key': 'actuation', 'type': 'token', 'label': 'Accionamiento del circuito', 'required': True,
             'allowed_values': ['Hidráulico', 'Cable']},
            {'key': 'lever_row_id', 'type': 'text', 'label': 'Fila de la maneta'},
            {'key': 'caliper_row_id', 'type': 'text', 'label': 'Fila del cáliper o mecanismo'},
            {'key': 'line_row_id', 'type': 'text', 'label': 'Fila de la manguera o cable'},
            {'key': 'fluid_as_shipped', 'type': 'token', 'label': 'Líquido con que se entrega',
             'allowed_values': FLUIDS},
            {'key': 'source_url', 'type': 'url', 'label': 'Fuente'}]}}}
    return presentation, circuits


def presentation_contract(key):
    legacy = [k for k in LIVE_FIELDS[key] if k != 'spec_evidence_source']
    roles = {k: 'legacy' for k in legacy}
    roles.update(spec_evidence_source='declaration', brake_presentation='primary',
                 kit_members='contents', brake_circuits='declaration')
    semantic = {**roles, 'spec_evidence_source': 'evidence', 'brake_presentation': 'intrinsic',
                'brake_circuits': 'compatibility'}
    circuits_when = when('brake_presentation', 'in', list(WITH_CIRCUITS[key]))
    allowed_when = {k: {'kind': 'never'} for k in legacy}
    allowed_when.update(spec_evidence_source={'kind': 'always'}, brake_presentation={'kind': 'always'},
                        kit_members={'kind': 'always'}, brake_circuits=circuits_when)
    required_when = {k: {'kind': 'never'} for k in legacy}
    required_when.update(spec_evidence_source={'kind': 'never'}, brake_presentation={'kind': 'always'},
                         kit_members={'kind': 'always'}, brake_circuits=deepcopy(circuits_when))
    piece = 'mecanismo' if key == 'rim_brake' else 'cáliper'
    return {
        'rules_version': 2, 'roles': roles, 'semantic_roles': semantic, 'labels': {},
        'allowed_options': {'brake_presentation': list(OPTIONS[key])},
        'allowed_when': allowed_when, 'required_when': required_when,
        'prerequisites': {'kit_members': ['brake_presentation', 'spec_evidence_source'],
                          'brake_circuits': ['brake_presentation', 'spec_evidence_source']},
        'helpers': {
            'brake_presentation': (
                'Qué se vende armado: un freno completo, un par o una pieza con su línea. Todo lo '
                'demás depende de esta elección; la ausencia de filas nunca significa pieza única.'),
            'kit_members': (
                f'Una fila por pieza física incluida, con su perfil propio: cada maneta, cada {piece}, '
                'cada línea, rotor, adaptador o pastilla. Dos piezas del mismo modelo son dos filas. '
                'Las medidas e interfaces viven en el perfil de cada pieza, nunca en esta raíz.'),
            'brake_circuits': CIRCUIT_HELPER,
            'spec_evidence_source': 'Documento o envase que respalda el contenido y los circuitos declarados.'},
        'evidence_requirements': {'kit_members': 'package_or_label', 'brake_circuits': 'package_or_label',
                                  'spec_evidence_source': 'oem_or_package'},
        'row_conditions': {'version': 1, 'fields': {
            'kit_members': {'allowed_options': {'family': list(MEMBER_FAMILIES[key])}},
            'brake_circuits': {
                'allowed_options': {'actuation': list(ACTUATION[key])},
                'allowed_when': {'fluid_as_shipped': when('actuation', 'eq', 'Hidráulico')}}}},
        'member_profiles': deepcopy(COLLECTIONS),
        'row_coherence': {'version': 2, 'cardinalities': [], 'links': [
            {'id': 'brake_circuit_lever', 'field': 'brake_circuits', 'column': 'lever_row_id',
             'target_field': 'kit_members', 'label_columns': ['member_role', 'position', 'identity_model']},
            {'id': 'brake_circuit_caliper', 'field': 'brake_circuits', 'column': 'caliper_row_id',
             'target_field': 'kit_members', 'label_columns': ['member_role', 'position', 'identity_model']},
            {'id': 'brake_circuit_line', 'field': 'brake_circuits', 'column': 'line_row_id',
             'target_field': 'kit_members', 'label_columns': ['member_role', 'position', 'identity_model']}]},
    }


def new_field(key, section, sort_order):
    return {'key': key, 'section_key': section, 'sort_order': sort_order, 'is_required': False,
            'visibility_rules': [], 'option_rules': [], 'constraint_rules': [],
            'helper_text': None, 'default_value_json': None}


def build_catalog(before):
    live = {t['key']: t for t in before['templates']}
    if set(live) != set(FAMILIES):
        raise ValueError('The preimage must carry the three presentations and the caliper')
    definitions = {d['key']: {**deepcopy(d), 'origin': 'existing'} for d in before['existing_definitions']}
    by_id = {d['id']: d['key'] for d in definitions.values()}
    for key in ('kit_members', 'tool_size_mm', 'spec_evidence_source'):
        if key not in definitions:
            raise ValueError('The live preimage must include the shared definition ' + key)
    if any(k in definitions for k in ('brake_presentation', 'brake_circuits')):
        raise ValueError('A presentation definition already exists; re-adjudicate it')
    templates = []
    for key in PRESENTATIONS:
        template = deepcopy(live[key])
        fields = [{**deepcopy(f), 'key': by_id[f['spec_definition_id']]}
                  for f in before['fields'] if f['template_id'] == template['id']]
        if {f['key'] for f in fields} != set(LIVE_FIELDS[key]):
            raise ValueError('Live fields of ' + key + ' changed; review the matrix before replacing rules')
        old = template['form_contract']
        if (old.get('version') != 1 or set(old) - {'roles', 'version', 'coverage', 'labels', 'helpers', 'prerequisites'}
                or any(old.get(k) for k in ('labels', 'helpers', 'prerequisites'))
                or set(old['roles']) != set(LIVE_FIELDS[key])):
            raise ValueError('Existing contract of ' + key + ' changed; review it before replacing rules')
        for field in fields:
            if field['key'] != 'spec_evidence_source':
                field['section_key'] = 'legacy'
                field['is_required'] = False
        fields.append(new_field('brake_presentation', 'primary', 0))
        fields.append(new_field('kit_members', 'contents', 1))
        fields.append(new_field('brake_circuits', 'declaration', 2))
        template.update(origin='existing', fields=fields, form_contract=presentation_contract(key))
        templates.append(template)
    caliper = deepcopy(live[CALIPER])
    fields = [{**deepcopy(f), 'key': by_id[f['spec_definition_id']]}
              for f in before['fields'] if f['template_id'] == caliper['id']]
    if 'tool_size_mm' in {f['key'] for f in fields} or caliper['form_contract'].get('rules_version') != 2:
        raise ValueError('The caliper already owns tool_size_mm or its contract shape changed')
    fields.append(new_field('tool_size_mm', 'measurement', 300 + len(fields)))
    contract = deepcopy(caliper['form_contract'])
    contract['roles']['tool_size_mm'] = 'measurement'
    contract['semantic_roles']['tool_size_mm'] = 'intrinsic'
    contract['allowed_when']['tool_size_mm'] = {'kind': 'always'}
    contract['required_when']['tool_size_mm'] = {'kind': 'never'}
    contract['helpers']['tool_size_mm'] = (
        'Medida de la herramienta que piden los pernos de fijación y ajuste de esta pinza, tal '
        'como la publica su fuente. Es un dato de la pieza; una presentación completa lo lee '
        'en el perfil de cada pinza incluida.')
    contract['evidence_requirements']['tool_size_mm'] = 'oem_or_package'
    caliper.update(origin='existing', fields=fields, form_contract=contract)
    templates.append(caliper)
    presentation, circuits = new_definitions()
    definitions['brake_presentation'] = presentation
    definitions['brake_circuits'] = circuits
    used = {f['key'] for t in templates for f in t['fields']}
    definitions = {k: v for k, v in definitions.items() if k in used}
    if set(definitions) != used:
        raise ValueError('Every field needs its definition: ' + str(sorted(used - set(definitions))))
    return {'schema_version': 2, 'templates': templates, 'definitions': definitions,
            'publication_authorized': False, 'mechanical_coverage_complete': False,
            'automatic_fill_authorized': False}


def build_cases(catalog_sha):
    source = 'https://example.invalid/synthetic-package'
    evidence = {'spec_evidence_source': 'Synthetic package, no inventory claim.'}
    cases = []

    def member(row_id, family, role, position='Sin posición', model=None, quantity='1'):
        values = {'member_role': role, 'family': family, 'quantity': quantity, 'position': position}
        if model:
            values['identity_model'] = model
        return {'id': row_id, 'values': values, 'sources': [source]}

    def circuit(row_id, position, actuation, lever=None, caliper=None, line=None, fluid=None):
        values = {'circuit_id': row_id, 'position': position, 'actuation': actuation, 'source_url': source}
        for column, value in (('lever_row_id', lever), ('caliper_row_id', caliper),
                              ('line_row_id', line), ('fluid_as_shipped', fluid)):
            if value is not None:
                values[column] = value
        return {'id': row_id, 'values': values, 'sources': [source]}

    def rows(*items):
        return {'schema_version': 1, 'rows': list(items)}

    def add(name, template, values, *, blocking=(), pending=(), sql_pending=None,
            forbidden=(), row_counts=None):
        case = {'id': 'brake_presentation_' + name, 'template': template, 'values': values,
                'kind': 'synthetic_boundary', 'source_urls': [],
                'facts_verified_for_product': False, 'automatic_fill_authorized': False,
                'expected_blocking': [{'code': c, 'field': f} for c, f in blocking],
                'expected_issue_subset': [{'code': c, 'field': f, 'blocking': False} for c, f in pending],
                'forbidden_issue_fields': list(forbidden)}
        case['expected_sql_blocking'] = sorted(deepcopy(case['expected_blocking']),
                                               key=lambda i: (i['code'], i['field']))
        case['expected_sql_issue_subset'] = [{'code': c, 'field': f, 'blocking': False}
                                             for c, f in (sql_pending if sql_pending is not None else pending)]
        if row_counts:
            case['expected_row_counts'] = row_counts
        cases.append(case)

    hyd = 'hydraulic_disc_brake'
    complete = {**evidence, 'brake_presentation': OPTIONS[hyd][0]}
    lever = member('lever', 'brake_lever', 'maneta', 'Derecho', 'Synthetic lever')
    caliper = member('caliper', 'brake_caliper', 'cáliper', 'Delantero', 'Synthetic caliper')
    hose = member('hose', 'hydraulic_hose', 'manguera', 'Delantero')
    # Both engines report a required field that is absent as required_missing even
    # when its prerequisite is also absent; the circuits declaration stays silent
    # because its applicability gate (a presentation with circuits) is unresolved.
    add('without_a_presentation_everything_is_pending', hyd, {},
        pending=(('required_missing', 'brake_presentation'), ('required_missing', 'kit_members')),
        forbidden=('brake_circuits',))
    add('a_presentation_without_pieces_is_pending_never_single', hyd, complete,
        pending=(('required_missing', 'kit_members'), ('required_missing', 'brake_circuits')))
    add('a_complete_hydraulic_brake_with_its_circuit', hyd,
        {**complete, 'kit_members': rows(lever, caliper, hose),
         'brake_circuits': rows(circuit('front', 'Delantero', 'Hidráulico', 'lever', 'caliper', 'hose',
                                        'Aceite Mineral'))},
        row_counts={'kit_members': 3, 'brake_circuits': 1})
    add('a_bare_caliper_with_hose_owes_no_circuit', hyd,
        {**evidence, 'brake_presentation': OPTIONS[hyd][2], 'kit_members': rows(caliper, hose)},
        forbidden=('brake_circuits',), row_counts={'kit_members': 2})
    add('a_bare_caliper_cannot_declare_a_circuit', hyd,
        {**evidence, 'brake_presentation': OPTIONS[hyd][2], 'kit_members': rows(caliper, hose),
         'brake_circuits': rows(circuit('front', 'Delantero', 'Hidráulico', caliper='caliper'))},
        blocking=(('field_applicability', 'brake_circuits'),))
    add('a_pair_keeps_two_levers_of_the_same_model_apart', hyd,
        {**evidence, 'brake_presentation': OPTIONS[hyd][1],
         'kit_members': rows(member('lever-r', 'brake_lever', 'maneta', 'Derecho', 'Synthetic lever'),
                             member('lever-l', 'brake_lever', 'maneta', 'Izquierdo', 'Synthetic lever'),
                             member('caliper-f', 'brake_caliper', 'cáliper', 'Delantero', 'Synthetic caliper'),
                             member('caliper-r', 'brake_caliper', 'cáliper', 'Trasero', 'Synthetic caliper')),
         'brake_circuits': rows(circuit('front', 'Delantero', 'Hidráulico', 'lever-r', 'caliper-f'),
                                circuit('rear', 'Trasero', 'Hidráulico', 'lever-l', 'caliper-r'))},
        row_counts={'kit_members': 4, 'brake_circuits': 2})
    add('a_complete_brake_cannot_contain_a_complete_brake', hyd,
        {**complete, 'kit_members': rows(member('nested', 'hydraulic_disc_brake', 'otro'))},
        blocking=(('row_option', 'kit_members'),))
    add('a_hydraulic_presentation_admits_no_cable_circuit', hyd,
        {**complete, 'kit_members': rows(lever, caliper),
         'brake_circuits': rows(circuit('front', 'Delantero', 'Cable', 'lever', 'caliper'))},
        blocking=(('row_option', 'brake_circuits'),))
    add('a_circuit_pointing_at_a_missing_piece_blocks', hyd,
        {**complete, 'kit_members': rows(lever, caliper),
         'brake_circuits': rows(circuit('front', 'Delantero', 'Hidráulico', 'lever', 'ghost'))},
        blocking=(('row_reference_unresolved', 'brake_circuits'),))
    add('two_circuits_cannot_share_an_identifier', hyd,
        {**complete, 'kit_members': rows(lever, caliper),
         'brake_circuits': rows(circuit('front', 'Delantero', 'Hidráulico', 'lever', 'caliper'),
                                circuit('front', 'Trasero', 'Hidráulico', 'lever', 'caliper'))},
        blocking=(('row_shape', 'brake_circuits'),))
    add('legacy_readings_stay_inert', hyd,
        {**complete, 'kit_members': rows(lever, caliper),
         'brake_circuits': rows(circuit('front', 'Delantero', 'Hidráulico', 'lever', 'caliper')),
         'brake_system': 'invalid legacy', 'fluid_type': 'invalid legacy', 'piston_count': 'invalid legacy',
         'rotor_diameter_mm': 'invalid legacy', 'hose_length_mm': 'not a number'},
        forbidden=('brake_system', 'fluid_type', 'piston_count', 'rotor_diameter_mm', 'hose_length_mm',
                   'bleed_port', 'hose_fitting_type', 'mount_standard', 'pad_shape_code', 'reach_adjust',
                   'brake_position'))

    mech = 'mechanical_disc_brake'
    mcomplete = {**evidence, 'brake_presentation': OPTIONS[mech][0]}
    cable = member('cable', 'control_cable', 'cable', 'Delantero')
    add('a_cable_circuit_carries_no_shipped_fluid', mech,
        {**mcomplete, 'kit_members': rows(lever, caliper, cable),
         'brake_circuits': rows(circuit('front', 'Delantero', 'Cable', 'lever', 'caliper', 'cable', 'DOT 4'))},
        blocking=(('row_field_applicability', 'brake_circuits'),))
    add('a_complete_mechanical_brake_with_its_circuit', mech,
        {**mcomplete, 'kit_members': rows(lever, caliper, cable),
         'brake_circuits': rows(circuit('front', 'Delantero', 'Cable', 'lever', 'caliper', 'cable'))},
        forbidden=('tool_size_mm', 'rotor_diameter_mm'), row_counts={'kit_members': 3, 'brake_circuits': 1})
    add('the_retired_root_tool_size_no_longer_answers', mech,
        {**mcomplete, 'kit_members': rows(lever, caliper, cable),
         'brake_circuits': rows(circuit('front', 'Delantero', 'Cable', 'lever', 'caliper', 'cable')),
         'tool_size_mm': '5 mm', 'rotor_diameter_mm': '160'},
        forbidden=('tool_size_mm', 'rotor_diameter_mm'))
    add('a_mechanical_presentation_admits_no_hydraulic_line', mech,
        {**mcomplete, 'kit_members': rows(lever, caliper, member('hose', 'hydraulic_hose', 'manguera'))},
        blocking=(('row_option', 'kit_members'),))

    rim = 'rim_brake'
    mechanism = member('arm', 'brake_caliper', 'cáliper', 'Delantero', 'Synthetic rim mechanism')
    add('one_rim_mechanism_is_one_piece_row', rim,
        {**evidence, 'brake_presentation': OPTIONS[rim][0], 'kit_members': rows(mechanism)},
        forbidden=('brake_circuits', 'brake_system', 'brake_position', 'tool_size_mm'),
        row_counts={'kit_members': 1})
    add('a_single_mechanism_owes_no_circuit', rim,
        {**evidence, 'brake_presentation': OPTIONS[rim][0], 'kit_members': rows(mechanism),
         'brake_circuits': rows(circuit('front', 'Delantero', 'Cable', caliper='arm'))},
        blocking=(('field_applicability', 'brake_circuits'),))
    add('a_pair_of_rim_mechanisms_is_two_rows_with_their_own_profiles', rim,
        {**evidence, 'brake_presentation': OPTIONS[rim][1],
         'kit_members': rows(member('arm-f', 'brake_caliper', 'cáliper', 'Delantero', 'Synthetic V-brake'),
                             member('arm-r', 'brake_caliper', 'cáliper', 'Trasero', 'Synthetic V-brake'))},
        forbidden=('brake_system', 'brake_position', 'tool_size_mm'), row_counts={'kit_members': 2})
    add('a_rim_set_with_levers_declares_its_cable_circuits', rim,
        {**evidence, 'brake_presentation': OPTIONS[rim][2],
         'kit_members': rows(member('arm-f', 'brake_caliper', 'cáliper', 'Delantero'),
                             member('arm-r', 'brake_caliper', 'cáliper', 'Trasero'),
                             member('lever-r', 'brake_lever', 'maneta', 'Derecho'),
                             member('lever-l', 'brake_lever', 'maneta', 'Izquierdo'),
                             member('cables', 'control_cable', 'cable', 'Sin posición', quantity='2')),
         'brake_circuits': rows(circuit('front', 'Delantero', 'Cable', 'lever-r', 'arm-f', 'cables'),
                                circuit('rear', 'Trasero', 'Cable', 'lever-l', 'arm-r', 'cables'))},
        row_counts={'kit_members': 5, 'brake_circuits': 2})
    add('a_rim_presentation_cannot_contain_a_rim_presentation', rim,
        {**evidence, 'brake_presentation': OPTIONS[rim][1],
         'kit_members': rows(member('nested', 'rim_brake', 'otro'))},
        blocking=(('row_option', 'kit_members'),))
    add('the_retired_rim_root_readings_stay_inert', rim,
        {**evidence, 'brake_presentation': OPTIONS[rim][0], 'kit_members': rows(mechanism),
         'brake_system': 'invalid legacy', 'brake_position': 'invalid legacy', 'tool_size_mm': 'M6'},
        forbidden=('brake_system', 'brake_position', 'tool_size_mm', 'reach_adjust'))

    add('a_caliper_declares_the_tool_size_of_its_bolts', CALIPER,
        {'braking_surface': 'Disco', 'brake_actuation': 'Mecánico (cable)', 'caliper_mount_interface': 'Post Mount',
         'tool_size_mm': '5 mm hex', 'spec_evidence_source': 'Synthetic sheet'},
        forbidden=('tool_size_mm',))
    return {'schema_version': 1, 'catalogue_sha256': catalog_sha, 'cases': cases, 'pending_cases': [
        {'id': 'oem_relation_and_editor_validation_pending', 'template': None,
         'reason': 'No engine compares an included rotor with the diameters a caliper profile admits, a lever pull '
                   'with a mechanism, or a shipped fluid with the approvals of each piece (E2). Declared, not verified.'},
        {'id': 'circuit_target_family_is_not_checked', 'template': None,
         'reason': 'A link proves that the target row exists; it does not check that lever_row_id points at a lever. '
                   'The row labels show role, position and model so the operator sees what was chosen.'},
        {'id': 'a_pair_does_not_count_its_circuits', 'template': None,
         'reason': 'No total field exists for circuits; a pair with one circuit stays incomplete by inspection, not by rule.'},
        {'id': 'lever_pairs_sold_alone_wait_for_their_presentation', 'template': None,
         'reason': 'A pair of levers is not a brake_lever; it needs a lever presentation or member scoping (E1).'}]}


def prototype_absence():
    keys = ','.join("'" + key + "'" for key in PROTOTYPES)
    return 'not exists(select 1 from public.spec_definitions where key=any(array[' + keys + ']::text[]))'


def generate_migration(packet, *, source_sha):
    sql = base_migration(packet, source_sha=source_sha)
    anchor = 'select d.doc into doc from nd_publication_document d;'
    if sql.count(anchor) != 1:
        raise ValueError('Publisher framing changed')
    return sql.replace(anchor, anchor + '\n if not (' + prototype_absence() +
                       ") then raise exception 'Unreviewed brake successor prototype definition'; end if;")


def generate_verifier(packet, cases):
    return ('select 1/(case when ' + prototype_absence() +
            ' then 1 else 0 end) as no_unpublished_brake_prototypes;\n' + base_verifier(packet, cases))


def main():
    if len(sys.argv) == 2 and sys.argv[1] == '--preimage-query':
        templates = [{'key': key, 'fields': [{'key': k} for k in keys]} for key, keys in LIVE_FIELDS.items()]
        templates.append({'key': CALIPER, 'fields': [{'key': 'kit_members'}, {'key': 'tool_size_mm'}]})
        print(preimage_query({'templates': templates}, list(FAMILIES)))
        return
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_brake_presentations.py PREIMAGE.json | --preimage-query')
    path = Path(sys.argv[1]); before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    catalog = build_catalog(before)
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    catalog_path = RESEARCH / (PREFIX + '-catalog.json'); write_json(catalog_path, catalog)
    cases = build_cases(digest(catalog_path))
    cases_path = RESEARCH / (PREFIX + '-cases.json'); write_json(cases_path, cases)
    packet = compile_packet(catalog=catalog, cases=cases, before=before, families=list(FAMILIES),
        hashes={'catalog_sha256': digest(catalog_path), 'cases_sha256': digest(cases_path),
                'preimage_sha256': digest(path)},
        adjudication={
            'status': 'candidate_under_sole_owner_review',
            'revision': '223 over the 2026-09-15 adjudication of proposal 222',
            'scope': 'Three brake presentations become explicit presentations; brake_caliper gains the tool-size owner.',
            'presentation': 'brake_presentation is required always; kit_members and brake_circuits depend on it and on the evidence source; absence of rows is pending, never a single piece.',
            'ownership': 'tool_size_mm now belongs to brake_caliper; every presentation keeps its historical root datum as legacy, unedited.',
            'rim_pairs': 'Each rim mechanism is a brake_caliper member row (braking surface Llanta) with its own profile; the rim_brake root holds no active mechanism field.',
            'circuits': 'brake_circuits links lever, caliper/mechanism and line rows by id; fluid_as_shipped exists only on hydraulic circuits; nothing is compared across profiles.',
            'recursion': 'No presentation admits hydraulic_disc_brake, mechanical_disc_brake, rim_brake or brake_shift_combined_control as a member.',
            'lever_pairs': 'Pairs of levers sold alone stay as they are until a lever presentation or member scoping exists.',
            'compatibility_and_fill_not_approved': True})
    new_keys = sorted(d['key'] for d in packet['records']['spec_definitions'])
    if new_keys != ['brake_circuits', 'brake_presentation']:
        raise ValueError('Only the two presentation definitions may be created: ' + str(new_keys))
    presentation = next(d for d in packet['records']['spec_definitions'] if d['key'] == 'brake_presentation')
    presentation.update(is_customer_visible=True, is_filterable=True)
    packet['adjudication']['new_scalar_surfaces'] = ['brake_presentation']
    write_json(RESEARCH / (PREFIX + '-packet.json'), packet)
    (ROOT / '.tmp/db' / (PREFIX + '-candidate.sql')).write_text(generate_migration(packet, source_sha=digest(catalog_path)))
    (ROOT / '.tmp/db' / (PREFIX + '-verification.sql')).write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': len(catalog['templates']), 'new_definitions': len(packet['records']['spec_definitions']),
                      'reused_definitions': len(packet['reused_definitions']), 'patches': len(packet['patches']),
                      'contract_versions': {t['key']: t['contract_version'] for t in packet['records']['spec_templates']},
                      'cases': len(cases['cases']), 'pending_cases': len(cases['pending_cases']),
                      'bindings': before['effective_bindings'], 'published': False, 'facts_changed': 0}))


if __name__ == '__main__':
    main()
