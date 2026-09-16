#!/usr/bin/env python3
"""Prepare the spoke owner against a fresh preimage, never publish.

The reviewed 2026-09-08 catalogue, cases and preimage stay pinned. The fresh
production preimage must match the reviewed one in template, fields and shared
definitions; only the binding counts may differ. Observations are preserved.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

from compile_existing_spec_publication import (
    compile_packet, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

PREFIX = 'spoke-2026-09-16'
FAMILIES = ('spoke',)
CATALOG_SHA = '4a604b432a05f598dc3d1233880c111e4714fed986a6823b71a3292142f2353f'
CASES_SHA = 'c3e3668e8d9124d72cb35a8c96c262238e9857ae9c78e4bf6b59649e565e5c4d'
FROZEN_PREIMAGE_SHA = '4d62f70e114ea85457a1f4d29e8120dbef86edd418374dffe7fb7ca25ddaab3c'
# New scalar definitions with operator/customer meaning. Free-text OEM
# designations, row tables and the retired legacy readings stay outside filters.
SURFACE_FIELDS = {
    'spoke_head_interface', 'spoke_thread_nominal_mm', 'spoke_thread_major_diameter_mm',
    'spoke_thread_length_mm', 'spoke_head_elbow_angle_deg', 'nipples_included',
    'spoke_nipple_thread_present',
}


def stripped(records):
    return {json.dumps(r, sort_keys=True) for r in records}


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_spoke_successors.py <fresh-preimage.json>')
    path = Path(sys.argv[1])
    before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    frozen = load_pinned(RESEARCH / 'existing-spoke-review-preimage-2026-09-08.json', FROZEN_PREIMAGE_SHA)
    for section in ('templates', 'fields', 'existing_definitions'):
        if stripped(before[section]) != stripped(frozen[section]):
            raise ValueError('Live metadata drifted from the reviewed preimage: ' + section)
    original = load_pinned(RESEARCH / 'existing-spoke-catalog-2026-09-08.json', CATALOG_SHA)
    old_cases = load_pinned(RESEARCH / 'existing-spoke-cases-2026-09-08.json', CASES_SHA)
    templates = deepcopy([t for t in original['templates'] if t['key'] in FAMILIES])
    if len(templates) != 1:
        raise ValueError('The reviewed catalogue must carry exactly the spoke family')
    contract = templates[0]['form_contract']
    if {k for k, r in contract['roles'].items() if r == 'legacy'} != {'spoke_gauge', 'spoke_bend_type'}:
        raise ValueError('The legacy boundary changed; re-adjudicate it')
    used = {f['key'] for t in templates for f in t['fields']}
    definitions = {k: deepcopy(original['definitions'][k]) for k in sorted(used)}
    catalog = {**deepcopy(original), 'templates': templates, 'definitions': definitions,
               'source_catalog_sha256': CATALOG_SHA, 'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False, 'publication_authorized': False}
    cp = RESEARCH / (PREFIX + '-catalog.json'); write_json(cp, catalog)
    sha = hashlib.sha256(cp.read_bytes()).hexdigest()
    cases = {'schema_version': 1, 'catalogue_sha256': sha,
             'cases': deepcopy(old_cases['cases']),
             'pending_cases': deepcopy(old_cases.get('pending_cases', []))}
    case_path = RESEARCH / (PREFIX + '-cases.json'); write_json(case_path, cases)
    packet = compile_packet(catalog=catalog, cases=cases, before=before, families=list(FAMILIES),
        hashes={'catalog_sha256': sha, 'cases_sha256': hashlib.sha256(case_path.read_bytes()).hexdigest(),
                'preimage_sha256': hashlib.sha256(path.read_bytes()).hexdigest()},
        adjudication={
            'status': 'candidate_under_sole_owner_review',
            'scope': 'The spoke owner only; nipples are contents with identity, wheels are not approved.',
            'preimage': 'Fresh 2026-09-16 production capture equals the 2026-09-08 review preimage in '
                        'template, fields and shared definitions; effective bindings 48 -> 58.',
            'sections': 'Physical positions within this SKU, never all OEM variants.',
            'thread': 'Wire diameter, major thread diameter and gauge are separate declarations.',
            'contents': 'Included nipples have component identity and quantity; no inferred tool or wheel approval.',
            'legacy': 'Published gauge and two-choice head readings are retained without becoming active compatibility.',
            'reviews': 'Independent review, delta review and final D1 review (2026-09-08) found no open blocker.',
            'released_client': 'f51f3777 decodes row_conditions; this catalogue declares no scalar pairs and no strict order.',
            'compatibility_and_fill_not_approved': True,
        })
    new_definitions = {d['key']: d for d in packet['records']['spec_definitions']}
    if not SURFACE_FIELDS <= new_definitions.keys():
        raise ValueError('Surface flags may only be assigned to reviewed new definitions')
    for key in SURFACE_FIELDS:
        new_definitions[key].update(is_customer_visible=True, is_filterable=True)
    packet['adjudication']['new_scalar_surfaces'] = sorted(SURFACE_FIELDS)
    write_json(RESEARCH / (PREFIX + '-packet.json'), packet)
    (ROOT / '.tmp/db' / (PREFIX + '-candidate.sql')).write_text(generate_migration(packet, source_sha=sha))
    (ROOT / '.tmp/db' / (PREFIX + '-verification.sql')).write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': 1, 'new_definitions': len(packet['records']['spec_definitions']),
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'pending_cases': len(cases['pending_cases']),
                      'patches': len(packet['patches']),
                      'contract_versions': {t['key']: t['contract_version'] for t in packet['records']['spec_templates']},
                      'bindings': before['effective_bindings'], 'published': False, 'facts_changed': 0}))


if __name__ == '__main__':
    main()
