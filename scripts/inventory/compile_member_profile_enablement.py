#!/usr/bin/env python3
"""Prepare opt-in metadata from an exact live preimage; never execute SQL.

This first slice keeps all existing fields, definitions and family rules.
Assemblies whose component ownership is still being reconciled are excluded.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

from compile_existing_spec_publication import (
    compile_packet, generate_migration, generate_verifier, preimage_query)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

FAMILIES = ('fender', 'handlebar_covering', 'headset_small_part', 'light',
            'lock', 'rider_protection', 'training_wheel', 'tube_repair',
            'tubeless_repair')
COLLECTIONS = {'version': 1, 'collections': [{
    'field': 'kit_members', 'family_column': 'family',
    'identity_columns': ['member_role', 'position', 'identity_brand',
                         'identity_model']}]}
PREFIX = 'member-profile-enablement-2026-09-14'


def build_catalog(before):
    """Only opt in the reviewed collection; keep every other value verbatim."""
    definitions = {d['key']: {**deepcopy(d), 'origin': 'existing'}
                   for d in before['existing_definitions']}
    by_id = {d['id']: d for d in definitions.values()}
    templates = []
    for current in before['templates']:
        if current['key'] not in FAMILIES:
            raise ValueError('Out-of-scope template')
        template = deepcopy(current)
        template['origin'] = 'existing'
        template['fields'] = [{**deepcopy(f), 'key': by_id[f['spec_definition_id']]['key']}
                              for f in before['fields']
                              if f['template_id'] == current['id']]
        contract = template['form_contract']
        if contract['roles'].get('kit_members') != 'contents':
            raise ValueError('Collection is not active contents')
        if contract.get('member_profiles') not in (None, COLLECTIONS):
            raise ValueError('A different collection contract already exists')
        contract['member_profiles'] = deepcopy(COLLECTIONS)
        templates.append(template)
    if {t['key'] for t in templates} != set(FAMILIES):
        raise ValueError('Exact nine-family preimage required')
    return {'schema_version': 2, 'templates': templates,
            'definitions': definitions, 'publication_authorized': False,
            'mechanical_coverage_complete': False,
            'automatic_fill_authorized': False}


def build_cases(catalog_sha):
    cases = []
    for family in FAMILIES:
        for child in ('accessory_mount', 'light'):
            blocked = family == 'light' and child == 'light'
            cases.append({
                'id': f'member_optin_{family}_{child}', 'template': family,
                'values': {'kit_members': {'schema_version': 1, 'rows': [{
                    'id': 'included-piece', 'values': {'member_role': 'otro',
                        'family': child, 'quantity': '1',
                        'position': 'Sin posición'}, 'sources': []}]}},
                'expected_blocking': ([{'code': 'row_option', 'field': 'kit_members'}]
                                      if blocked else []),
                'facts_verified_for_product': False,
                'automatic_fill_authorized': False})
    return {'schema_version': 1, 'catalogue_sha256': catalog_sha, 'cases': cases}


def main():
    if len(sys.argv) == 2 and sys.argv[1] == '--preimage-query':
        # The query includes every current definition through the field IDs.
        print(preimage_query({'templates': [{'key': k, 'fields': []}
                                           for k in FAMILIES]}, FAMILIES))
        return
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_member_profile_enablement.py PREIMAGE.json | --preimage-query')
    path = Path(sys.argv[1])
    before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    catalog = build_catalog(before)
    catalog_path = RESEARCH / (PREFIX + '-catalog.json')
    write_json(catalog_path, catalog)
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    cases = build_cases(digest(catalog_path))
    case_path = RESEARCH / (PREFIX + '-cases.json')
    write_json(case_path, cases)
    packet = compile_packet(catalog=catalog, cases=cases, before=before,
        families=FAMILIES,
        hashes={'catalog_sha256': digest(catalog_path),
                'cases_sha256': digest(case_path), 'preimage_sha256': digest(path)},
        adjudication={
            'owner_review': 'Claude rounds 213/214; Root excludes bicycle, wheel and detangler pending declaration-owner review.',
            'light': 'Existing effective family restriction excludes light; production draft probe confirms it remains blocking.',
            'scope': 'Only member_profiles opt-in; no field/definition/assignment/fact changes or compatibility certification.'})
    if any(packet['records'][table] for table in
           ('spec_definitions', 'spec_definition_values')) or any(
            patch['table'] != 'spec_templates' for patch in packet['patches']):
        raise ValueError('Opt-in unexpectedly changes definitions or fields')
    write_json(RESEARCH / (PREFIX + '-packet.json'), packet)
    target = ROOT / '.tmp/db'
    (target / (PREFIX + '-candidate.sql')).write_text(
        generate_migration(packet, source_sha=digest(catalog_path)))
    (target / (PREFIX + '-verification.sql')).write_text(generate_verifier(packet, cases))
    print(json.dumps({'families': len(FAMILIES), 'patches': len(packet['patches']),
                      'cases': len(cases['cases']), 'applied': False,
                      'product_writes': False}))


if __name__ == '__main__':
    main()
