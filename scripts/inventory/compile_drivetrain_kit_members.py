#!/usr/bin/env python3
"""Prepare the kit's member ownership from live metadata; never execute SQL.

The frozen original-successor catalogue remains historical evidence. Only the
eleven fields actually attached to the live kit become legacy. Their field IDs,
defaults, help and observations remain intact. Member observations belong to
their own family templates, whose successor publication is a separate step.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

from compile_existing_spec_publication import (
    compile_packet, generate_migration as base_migration,
    generate_verifier as base_verifier, preimage_query)
from compile_member_profile_enablement import COLLECTIONS
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

FAMILY = 'drivetrain_kit'
PREFIX = 'drivetrain-kit-members-2026-09-15'
LEGACY = frozenset((
    'kit_contents', 'front_chainring_count', 'chainring_teeth',
    'bottom_bracket_family', 'spindle_interface', 'crank_arm_length_mm',
    'chain_ebike_rated', 'drivetrain_primary_ecosystem',
    'drivetrain_declared_compatible_ecosystems', 'drivetrain_platform',
    'chain_profile_family'))
PROTOTYPES = (
    'drivetrain_kit_member_evidence', 'drivetrain_kit_member_interfaces',
    'drivetrain_kit_member_fitments')
PROTOTYPE_IDS = ('1b828eee-89d5-52ae-9d3c-30768f6c9c3d',
                 '16568903-784a-5bde-bf3c-9c680d7f0230',
                 '98492b05-1e1a-5a60-b462-45b0fe9c2939')


def build_catalog(before):
    if len(before['templates']) != 1 or before['templates'][0]['key'] != FAMILY:
        raise ValueError('Only the live drivetrain kit belongs to this delta')
    definitions = {d['key']: {**deepcopy(d), 'origin': 'existing'}
                   for d in before['existing_definitions']}
    if set(definitions) != LEGACY | {'spec_evidence_source', 'kit_members'}:
        raise ValueError('Unexpected field definitions; do not create absent legacy')
    by_id = {d['id']: d['key'] for d in definitions.values()}
    template = deepcopy(before['templates'][0])
    fields = [{**deepcopy(f), 'key': by_id[f['spec_definition_id']]}
              for f in before['fields']]
    if (len(fields) != 12 or {f['key'] for f in fields} !=
            LEGACY | {'spec_evidence_source'}):
        raise ValueError('The reviewed preimage has twelve existing kit fields')
    old = template['form_contract']
    if (set(old) != {'roles', 'labels', 'helpers', 'version', 'coverage',
                     'prerequisites'} or old['version'] != 1 or
            old['coverage'] != 'template' or old['labels'] or old['helpers'] or
            old['prerequisites'] or set(old['roles']) != LEGACY | {'spec_evidence_source'} or
            old['roles']['kit_contents'] != 'contents' or
            old['roles']['spec_evidence_source'] != 'declaration'):
        raise ValueError('Existing contract changed; review it before replacing rules')
    for field in fields:
        if field['key'] in LEGACY:
            field['section_key'] = 'legacy'
            field['is_required'] = False
    fields.append({'key': 'kit_members', 'section_key': 'contents',
                   'sort_order': 0, 'is_required': False, 'visibility_rules': [],
                   'option_rules': [], 'constraint_rules': [],
                   'helper_text': None, 'default_value_json': None})
    roles = {k: 'legacy' for k in sorted(LEGACY)}
    roles.update(kit_members='contents', spec_evidence_source='declaration')
    contract = {
        'rules_version': 2, 'roles': roles,
        'semantic_roles': {**roles, 'spec_evidence_source': 'evidence'},
        'labels': {}, 'allowed_options': {},
        'allowed_when': {k: {'kind': 'never' if k in LEGACY else 'always'} for k in roles},
        'required_when': {k: {'kind': 'always' if k == 'kit_members' else 'never'} for k in roles},
        'prerequisites': {'kit_members': ['spec_evidence_source']},
        'helpers': {'kit_members':
            'Registra las piezas incluidas en esta presentación y sus fuentes. '
            'Cada pieza conserva su propia identificación y ficha técnica. '
            'El contenido del envase no acredita que las piezas sean compatibles entre sí.'},
        'evidence_requirements': {'kit_members': 'package_or_label',
                                  'spec_evidence_source': 'oem_or_package'},
        'member_profiles': deepcopy(COLLECTIONS),
    }
    template.update(origin='existing', fields=fields, form_contract=contract)
    return {'schema_version': 2, 'templates': [template], 'definitions': definitions,
            'publication_authorized': False, 'mechanical_coverage_complete': False,
            'automatic_fill_authorized': False}


def build_cases(catalog_sha):
    def row(row_id='piece-a', family='chain', **values):
        return {'id': row_id, 'values': {'member_role': 'otro', 'family': family,
                'quantity': '1', 'position': 'Sin posición', **values},
                'sources': ['https://example.com/synthetic-kit-source']}
    def rows(*items):
        return {'schema_version': 1, 'rows': list(items)}
    evidence = {'spec_evidence_source': 'Synthetic package evidence; not a product claim.'}
    cases = []
    def add(name, values, blocking=(), pending=(), forbidden=()):
        case = {'id': 'kit_members_' + name, 'template': FAMILY,
            'values': values, 'expected_blocking': [
                {'code': code, 'field': 'kit_members'} for code in blocking],
            'expected_issue_subset': [
                {'code': code, 'field': 'kit_members', 'blocking': False} for code in pending],
            'forbidden_issue_fields': list(forbidden),
            'facts_verified_for_product': False, 'automatic_fill_authorized': False}
        # Existing client/server issue codes differ; the severity and actual
        # domain outcome must agree. These cases exercise both implementations.
        case['expected_sql_blocking'] = [
            {'code': 'field_constraint' if code == 'row_shape' else code,
             'field': 'kit_members'} for code in blocking]
        case['expected_sql_issue_subset'] = [
            {'code': 'prerequisite_missing' if code == 'prerequisite' else code,
             'field': 'kit_members', 'blocking': False} for code in pending]
        if 'kit_members' in values and not blocking:
            case['expected_row_counts'] = {'kit_members': len(values['kit_members']['rows'])}
        cases.append(case)
    add('empty_is_pending', {}, pending=('required_missing',))
    add('source_required', {'kit_members': rows(row())}, pending=('prerequisite',))
    add('single_piece', {**evidence, 'kit_members': rows(row())})
    add('separate_families', {**evidence, 'kit_members': rows(row(), row('piece-b', 'cassette'))})
    add('same_model_two_physical_rows', {**evidence, 'kit_members': rows(
        row(identity_model='Synthetic model'), row('piece-b', identity_model='Synthetic model'))})
    unknown = row(); unknown['values'].pop('family')
    add('unknown_family_is_pending', {**evidence, 'kit_members': rows(unknown)}, pending=('row_incomplete',))
    add('blank_family_is_invalid', {**evidence, 'kit_members': rows(row(family=''))}, blocking=('row_shape',))
    add('invalid_family', {**evidence, 'kit_members': rows(row(family='made-up-family'))}, blocking=('row_shape',))
    add('zero_quantity', {**evidence, 'kit_members': rows(row(quantity='0'))}, blocking=('row_shape',))
    add('duplicate_row_id', {**evidence, 'kit_members': rows(row(), row())}, blocking=('row_shape',))
    add('legacy_not_global_constraints', {**evidence, 'kit_members': rows(row()),
        'front_chainring_count': ['impossible'], 'crank_arm_length_mm': '-2',
        'drivetrain_primary_ecosystem': 'invalid legacy',
        'chain_profile_family': ['invalid legacy']}, forbidden=sorted(LEGACY))
    return {'schema_version': 1, 'catalogue_sha256': catalog_sha, 'cases': cases}


def prototype_absence():
    keys = ','.join("'" + key + "'" for key in PROTOTYPES)
    ids = ','.join("'" + value + "'" for value in PROTOTYPE_IDS)
    return ("not exists(select 1 from public.spec_definitions where key=any(array[" +
            keys + "]::text[]) or id=any(array[" + ids +
            "]::uuid[]))")


def generate_migration(packet, *, source_sha):
    sql = base_migration(packet, source_sha=source_sha)
    anchor = 'select d.doc into doc from nd_publication_document d;'
    if sql.count(anchor) != 1:
        raise ValueError('Publisher framing changed')
    return sql.replace(anchor, anchor + '\n if not (' + prototype_absence() +
        ") then raise exception 'Unreviewed kit prototype definition'; end if;")


def generate_verifier(packet, cases):
    return ('select 1/(case when ' + prototype_absence() +
            ' then 1 else 0 end) as no_unpublished_kit_prototypes;\n' +
            base_verifier(packet, cases))


def main():
    if len(sys.argv) == 2 and sys.argv[1] == '--preimage-query':
        print(preimage_query({'templates': [{'key': FAMILY, 'fields': [
            {'key': 'kit_members'}]}]}, [FAMILY]))
        return
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_drivetrain_kit_members.py PREIMAGE.json | --preimage-query')
    path = Path(sys.argv[1]); before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    catalog = build_catalog(before)
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    catalog_path = RESEARCH / (PREFIX + '-catalog.json')
    write_json(catalog_path, catalog)
    cases = build_cases(digest(catalog_path))
    cases_path = RESEARCH / (PREFIX + '-cases.json'); write_json(cases_path, cases)
    packet = compile_packet(catalog=catalog, cases=cases, before=before,
        families=[FAMILY], hashes={'catalog_sha256': digest(catalog_path),
            'cases_sha256': digest(cases_path), 'preimage_sha256': digest(path)},
        adjudication={'owner_review': 'Root; Claude rounds 217/218 corrected against live preimage.',
            'scope': 'One shared contents field, eleven existing fields retained as legacy, independent member profiles.',
            'limits': 'No automatic connection or compatibility verdict across pieces; family successors remain separate.'})
    if packet['records']['spec_definitions'] or packet['records']['spec_definition_values']:
        raise ValueError('This delta must not create definitions or options')
    write_json(RESEARCH / (PREFIX + '-packet.json'), packet)
    (ROOT / '.tmp/db' / (PREFIX + '-candidate.sql')).write_text(
        generate_migration(packet, source_sha=digest(catalog_path)))
    (ROOT / '.tmp/db' / (PREFIX + '-verification.sql')).write_text(generate_verifier(packet, cases))
    print(json.dumps({'fields_before': len(before['fields']), 'fields_after': len(catalog['templates'][0]['fields']),
        'patches': len(packet['patches']), 'contract_version': packet['records']['spec_templates'][0]['contract_version'],
        'cases': len(cases['cases']), 'applied': False, 'product_writes': False}))


if __name__ == '__main__':
    main()
