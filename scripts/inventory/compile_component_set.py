#!/usr/bin/env python3
"""Prepare a component-set catalogue from two reused live definitions.

This owns the commercial collection, not the intrinsic facts of its pieces.
No transport, product writes, or compatibility approval. The first supported
families correspond to the mixed retention/fastener/bearing and brake sets.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import uuid

from compile_member_profile_enablement import COLLECTIONS
from compile_non_drivetrain_publication import (
    RESEARCH, ROOT, TENANT, generate_migration, generate_verifier,
    metadata_records, write_json)
from compile_product_spec_catalog import validate_contract

KEY = 'component_set'
ID = str(uuid.uuid5(uuid.NAMESPACE_URL, 'vinabike:spec-template:' + KEY))
FAMILIES = ('bearing', 'brake_caliper', 'brake_lever', 'brake_pad', 'fastener',
            'hub_small_part', 'seat_clamp', 'wheel_retention')
PREFIX = 'component-set-2026-09-15'


def build_catalog(before):
    if before['tenant_id'] != TENANT or before['template_collisions']:
        raise ValueError('New collection identity or tenant scope changed')
    defs = {d['key']: {**deepcopy(d), 'origin': 'existing'}
            for d in before['existing_definitions']}
    if (set(defs) != {'kit_members', 'spec_evidence_source'} or
            len(before['existing_definitions']) != 2 or
            any(d['tenant_id'] is not None for d in defs.values())):
        raise ValueError('Exactly two reviewed global definitions are required')
    children = before['child_templates']
    if (len(children) != len(FAMILIES) or
            {t['key'] for t in children} != set(FAMILIES) or
            any(not t['is_active'] or t['member_profiles'] is not None for t in children)):
        raise ValueError('Review the current component owners before enabling the collection')
    contract = {
        'rules_version': 2,
        'roles': {'kit_members': 'contents', 'spec_evidence_source': 'declaration'},
        'semantic_roles': {'kit_members': 'contents', 'spec_evidence_source': 'evidence'},
        'labels': {}, 'allowed_options': {},
        'allowed_when': {k: {'kind': 'always'} for k in defs},
        'required_when': {k: {'kind': 'always'} for k in defs},
        'prerequisites': {'kit_members': ['spec_evidence_source']},
        'helpers': {'kit_members':
            'Identifica las piezas que realmente incluye esta presentación. '
            'Separa piezas con medidas, posición o modelo diferentes; agrupa '
            'cantidades sólo cuando sean piezas idénticas. Cada fila tiene su '
            'propia ficha. Compartir envase no acredita compatibilidad.'},
        'evidence_requirements': {'kit_members': 'package_or_label',
                                  'spec_evidence_source': 'oem_or_package'},
        'row_conditions': {'version': 1, 'fields': {'kit_members': {
            'allowed_options': {'family': list(FAMILIES)}}}},
        'member_profiles': deepcopy(COLLECTIONS),
    }
    template = {'id': ID, 'key': KEY, 'name': 'Conjunto de piezas',
                'technical_family': KEY, 'origin': 'new', 'form_contract': contract,
                'fields': [{'key': key, 'section_key': section, 'sort_order': order,
                            'is_required': False, 'visibility_rules': [],
                            'option_rules': [], 'constraint_rules': [],
                            'helper_text': None, 'default_value_json': None}
                           for key, section, order in (
                               ('spec_evidence_source', 'declaration', 0),
                               ('kit_members', 'contents', 10))]}
    validate_contract(KEY, contract, defs, set(defs))
    return {'schema_version': 2, 'templates': [template], 'definitions': defs,
            'publication_authorized': False, 'automatic_fill_authorized': False,
            'mechanical_coverage_complete': False}


def build_cases(sha):
    def row(identity, family, **values):
        return {'id': identity, 'values': {'member_role': 'otro', 'family': family,
                'quantity': '1', 'position': 'Sin posición', **values},
                'sources': ['https://example.invalid/synthetic-package']}

    cases = []
    def add(name, rows=None, *, source=True, blocking=(), pending=()):
        vals = {'spec_evidence_source': 'Synthetic package, no inventory claim.'} if source else {}
        if rows is not None:
            vals['kit_members'] = {'schema_version': 1, 'rows': rows}
        case = {'id': 'component_set_' + name, 'template': KEY, 'values': vals,
                'expected_blocking': [{'code': c, 'field': 'kit_members'} for c in blocking],
                'expected_issue_subset': [{'code': c, 'field': f, 'blocking': False}
                                          for c, f in pending],
                'facts_verified_for_product': False, 'automatic_fill_authorized': False}
        case['expected_sql_blocking'] = deepcopy(case['expected_blocking'])
        case['expected_sql_issue_subset'] = [
            {**e, 'code': 'prerequisite_missing' if e['code'] == 'prerequisite' else e['code']}
            for e in case['expected_issue_subset']]
        if rows is not None and not blocking:
            case['expected_row_counts'] = {'kit_members': len(rows)}
        cases.append(case)

    add('empty_pending', source=False, pending=(('required_missing', 'kit_members'),
                                               ('required_missing', 'spec_evidence_source')))
    add('members_pending', pending=(('required_missing', 'kit_members'),))
    add('source_pending', [row('a', 'bearing')], source=False,
        pending=(('prerequisite', 'kit_members'), ('required_missing', 'spec_evidence_source')))
    add('wheel_and_seat_retention', [row('a', 'wheel_retention'), row('b', 'seat_clamp')])
    add('fastener_and_bearing', [row('a', 'fastener'), row('b', 'bearing')])
    add('same_model_distinct_units', [row('a', 'brake_lever', identity_model='Synthetic lever', position='Izquierdo'),
                                    row('b', 'brake_lever', identity_model='Synthetic lever', position='Derecho')])
    unknown = row('a', 'bearing'); unknown['values'].pop('family')
    add('unknown_family_pending', [unknown], pending=(('row_incomplete', 'kit_members'),))
    add('unreviewed_family', [row('a', 'chain')], blocking=('row_option',))
    add('assembly_cannot_be_member', [row('a', 'drivetrain_kit')], blocking=('row_option',))
    add('unresolved_rim_brake_presentation', [row('a', 'rim_brake')], blocking=('row_option',))
    add('cannot_contain_itself', [row('a', KEY)], blocking=('row_shape',))
    add('blank_family', [row('a', '')], blocking=('row_shape',))
    add('zero_quantity', [row('a', 'bearing', quantity='0')], blocking=('row_shape',))
    add('duplicate_row_id', [row('a', 'bearing'), row('a', 'fastener')], blocking=('row_shape',))
    return {'schema_version': 1, 'catalogue_sha256': sha, 'cases': cases}


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_component_set.py <live-preimage.json>')
    path = Path(sys.argv[1]); before = json.loads(path.read_text())[0]['metadata']
    catalog = build_catalog(before)
    cp = RESEARCH / (PREFIX + '-catalog.json'); write_json(cp, catalog)
    sha = hashlib.sha256(cp.read_bytes()).hexdigest(); cases = build_cases(sha)
    write_json(RESEARCH / (PREFIX + '-cases.json'), cases)
    records = metadata_records(catalog['templates'], catalog['definitions'], set(catalog['definitions']))
    # A new template starts at 1 and gains one revision per inserted field.
    records['spec_templates'][0]['contract_version'] = 3
    packet = {'schema_version': 1, 'scope': 'new_global_metadata_only',
              'audited_tenant_id': TENANT, 'catalog_sha256': sha,
              'preimage_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'families': [KEY], 'reused_definitions': before['existing_definitions'],
              'records': records, 'product_writes': False, 'fill_allowed': False,
              'mechanical_approval': False,
              'adjudication': {'scope': 'Commercial collection of explicitly identified physical pieces; first eight supported piece families. Rim-brake presentation remains excluded pending ownership review.',
                               'no_recursive_member_family': True,
                               'no_intrinsic_root_facts': True}}
    write_json(RESEARCH / (PREFIX + '-packet.json'), packet)
    (ROOT / '.tmp/db' / (PREFIX + '-candidate.sql')).write_text(generate_migration(packet, source_sha=sha))
    (ROOT / '.tmp/db' / (PREFIX + '-verification.sql')).write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': 1, 'definitions': 0, 'fields': 2,
                      'cases': len(cases['cases']), 'applied': False, 'fills': 0}))


if __name__ == '__main__':
    main()
