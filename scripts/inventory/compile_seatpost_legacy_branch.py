#!/usr/bin/env python3
"""Retire the inherited shim branch of `seatpost` now that `seatpost_shim` owns it.

Metadata only: the three inherited shim fields become legacy (`allowed_when never`),
the option «Suplemento (shim)» leaves this template's allowed options, and every
ID, fact, label, helper and default is preserved. No product or fact is written.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

from compile_non_drivetrain_publication import ROOT, RESEARCH, TENANT, generate_verifier, write_json
from compile_existing_spec_publication import compile_packet, generate_migration, preimage_query
from compile_product_spec_catalog import validate_contract

KEY = 'seatpost'
PREFIX = 'seatpost-legacy-branch-2026-09-15'
SUCCESSOR = 'seatpost_shim'
SUCCESSOR_MIGRATION = '20260915203000'
RETIRED = ('shim_inner_diameter_mm', 'shim_outer_diameter_mm', 'seatpost_shim_length_mm')
SHIM_OPTION = 'Suplemento (shim)'
FIELD_COLUMNS = ('section_key', 'sort_order', 'is_required', 'visibility_rules',
                 'option_rules', 'constraint_rules', 'helper_text', 'default_value_json')
PUBLISHED_CATALOG = RESEARCH / 'contact-points-catalog-2026-09-07.json'


def build_catalog(before):
    if before['tenant_id'] != TENANT or len(before['templates']) != 1:
        raise ValueError('Exactly one live seatpost template preimage is required')
    live = before['templates'][0]
    if live['key'] != KEY or live['tenant_id'] is not None or not live['is_active']:
        raise ValueError('The live seatpost template is not the expected global owner')
    defs_by_id = {d['id']: d for d in before['existing_definitions']}
    definitions, fields = {}, []
    for f in sorted(before['fields'], key=lambda f: f['sort_order']):
        if f['template_id'] != live['id'] or f['tenant_id'] is not None:
            raise ValueError('Unexpected field scope')
        d = defs_by_id[f['spec_definition_id']]
        if d['tenant_id'] is not None:
            raise ValueError('Tenant-scoped definition on a global template: ' + d['key'])
        definitions[d['key']] = {**deepcopy(d), 'origin': 'existing', 'used_by': [KEY]}
        fields.append({'key': d['key'], **{c: deepcopy(f[c]) for c in FIELD_COLUMNS}})
    if len(fields) != 22 or len(definitions) != 22:
        raise ValueError('The seatpost preimage changed shape; review before retiring anything')
    contract = deepcopy(live['form_contract'])
    for key in RETIRED:
        if contract['roles'].get(key) != 'measurement':
            raise ValueError('Unexpected live role for ' + key)
        contract['roles'][key] = 'legacy'
        contract['semantic_roles'][key] = 'legacy'
        contract['allowed_when'][key] = {'kind': 'never'}
        contract['required_when'][key] = {'kind': 'never'}
        contract['prerequisites'][key] = []
        field = next(x for x in fields if x['key'] == key)
        field.update(section_key='legacy', is_required=False)
    if any(key in deps for deps in contract['prerequisites'].values() for key in RETIRED):
        raise ValueError('A live prerequisite still points at a retired field')
    kinds = definitions['seatpost_kind']['allowed_values']
    if SHIM_OPTION not in kinds or 'seatpost_kind' in contract['allowed_options']:
        raise ValueError('The shim option or an existing kind restriction was not where expected')
    contract['allowed_options']['seatpost_kind'] = [k for k in kinds if k != SHIM_OPTION]
    contract['helpers']['seatpost_kind'] = (
        'Tija completa. Un casquillo reductor tiene su propia ficha (Casquillo reductor de tija); '
        'las medidas de suplemento heredadas se conservan sólo como historial y no se editan aquí.')
    validate_contract(KEY, contract, definitions, {f['key'] for f in fields})
    template = {'id': live['id'], 'key': KEY, 'name': live['name'],
                'technical_family': live['technical_family'], 'form_contract': contract, 'fields': fields}
    return {'schema_version': 2, 'templates': [template], 'definitions': definitions,
            'publication_authorized': False, 'automatic_fill_authorized': False,
            'mechanical_coverage_complete': False}


def build_cases(sha, definitions):
    source = {'spec_evidence_source': 'Synthetic fixture; no inventory claim.'}
    legacy = {'shim_inner_diameter_mm': '27.2', 'shim_outer_diameter_mm': '30.9', 'seatpost_shim_length_mm': '80'}
    dropper_control = definitions['dropper_control_kind']['allowed_values'][0]
    cases = []

    def add(name, values, blocking=(), pending=(), forbidden=()):
        blocked = [{'code': c, 'field': k} for c, k in blocking]
        hints = [{'code': c, 'field': k, 'blocking': False} for c, k in pending]
        case = {'id': KEY + '_' + name, 'template': KEY, 'values': values,
                'expected_blocking': blocked, 'expected_issue_subset': hints,
                'expected_sql_blocking': sorted(deepcopy(blocked), key=lambda x: (x['code'], x['field'])),
                'expected_sql_issue_subset': [{**p, 'code': 'prerequisite_missing' if p['code'] == 'prerequisite' else p['code']} for p in hints],
                'facts_verified_for_product': False, 'automatic_fill_authorized': False}
        for issue in case['expected_sql_blocking']:
            if issue['code'] in {'constraint', 'range', 'type'}:
                issue['code'] = 'field_constraint'
        if forbidden:
            case['forbidden_issue_fields'] = list(forbidden)
        cases.append(case)
    add('empty', {}, pending=(('required_missing', 'seatpost_kind'),))
    add('shim_kind_is_no_longer_a_seatpost', {**source, 'seatpost_kind': SHIM_OPTION},
        blocking=(('constraint', 'seatpost_kind'),))
    add('shim_kind_with_inherited_values_blocks_only_the_kind', {**source, 'seatpost_kind': SHIM_OPTION, **legacy},
        blocking=(('constraint', 'seatpost_kind'),), forbidden=RETIRED)
    add('rigid_post_keeps_inherited_values_silent', {**source, 'seatpost_kind': 'Rígida', 'seatpost_diameter_mm': '27.2', **legacy},
        pending=(('required_missing', 'seatpost_saddle_configurations'),), forbidden=RETIRED)
    add('rigid_post_pending_saddle_configurations', {**source, 'seatpost_kind': 'Rígida', 'seatpost_diameter_mm': '27.2'},
        pending=(('required_missing', 'seatpost_saddle_configurations'),))
    add('dropper_kind_still_valid', {**source, 'seatpost_kind': 'Telescópica (dropper)', 'seatpost_diameter_mm': '30.9',
                                     'dropper_control_kind': dropper_control},
        pending=(('required_missing', 'seatpost_saddle_configurations'),))
    add('other_kind_still_valid', {**source, 'seatpost_kind': 'Otro', 'seatpost_diameter_mm': '31.6'},
        pending=(('required_missing', 'seatpost_saddle_configurations'),))
    return {'schema_version': 1, 'catalogue_sha256': sha, 'cases': cases}


def main():
    if sys.argv[1:] == ['--query']:
        print(preimage_query(json.loads(PUBLISHED_CATALOG.read_text()), [KEY])); return
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_seatpost_legacy_branch.py preimage.json | --query')
    path = Path(sys.argv[1]); before = json.loads(path.read_text())[0]['metadata']
    catalog = build_catalog(before); cp = RESEARCH / (PREFIX + '-catalog.json'); write_json(cp, catalog)
    sha = hashlib.sha256(cp.read_bytes()).hexdigest()
    cases = build_cases(sha, catalog['definitions']); case_path = RESEARCH / (PREFIX + '-cases.json'); write_json(case_path, cases)
    packet = compile_packet(
        catalog=catalog, cases=cases, before=before, families=[KEY],
        hashes={'catalog_sha256': sha, 'cases_sha256': hashlib.sha256(case_path.read_bytes()).hexdigest(),
                'preimage_sha256': hashlib.sha256(path.read_bytes()).hexdigest()},
        adjudication={'status': 'inherited_shim_branch_retired_after_successor_publication',
                      'successor_template': SUCCESSOR, 'successor_migration': SUCCESSOR_MIGRATION,
                      'retired_fields': list(RETIRED), 'retired_option_in_this_template_only': SHIM_OPTION,
                      'definitions_and_option_vocabulary_unchanged': True,
                      'production_usage_read_2026_09_15': {'facts': 0, 'references': 0, 'option_uses': 0, 'explicit_products': before['explicit_bindings']},
                      'facts_moved': 0, 'products_reassigned': 0, 'fill_allowed': False})
    write_json(RESEARCH / (PREFIX + '-packet.json'), packet)
    (ROOT / '.tmp/db' / (PREFIX + '-candidate.sql')).write_text(generate_migration(packet, source_sha=sha))
    (ROOT / '.tmp/db' / (PREFIX + '-verification.sql')).write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': 1, 'retired_fields': len(RETIRED), 'cases': len(cases['cases']),
                      'patches': len(packet['patches']),
                      'contract_version': packet['records']['spec_templates'][0]['contract_version'],
                      'applied': False, 'fills': 0}))


if __name__ == '__main__':
    main()
