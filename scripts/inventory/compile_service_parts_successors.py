#!/usr/bin/env python3
"""Prepare the hanger, pulley and chain guide owners against a fresh preimage, never publish.

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

PREFIX = 'service-parts-2026-09-16'
FAMILIES = ('derailleur_hanger', 'derailleur_pulley', 'chain_guide')
CATALOG_SHA = '1c10d400a1bea3f26c33c67c5a81dece3cdae9c7a4f954eea74be695b0c2216f'
CASES_SHA = '5084eeb7d917e294ed21caaea4c7b266a7989cc6b963410f184c543a871fbb9b'
FROZEN_PREIMAGE_SHA = '09a0e6b26958535000cda8e234992b904c4371387dc47e0b702dbd8ba076e1c9'
# New scalar definitions with operator/customer meaning. Free-text OEM
# designations, row tables and the retired legacy readings stay outside filters.
SURFACE_FIELDS = {
    'hanger_derailleur_interface', 'hanger_frame_interface',
    'pulley_bearing_construction', 'pulley_bearing_element_material', 'pulley_bore_diameter_mm',
    'pulley_declared_position', 'pulley_declared_speeds', 'pulley_outer_diameter_mm',
    'pulley_package_kind', 'pulley_tooth_profile', 'pulley_unit_count', 'pulley_width_mm',
    'chain_guide_chainline_adjustment_mm', 'chainring_teeth_min', 'chainring_teeth_max',
}
DEAD_ON_ARRIVAL = {}


def stripped(records):
    return {json.dumps(r, sort_keys=True) for r in records}


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_service_parts_successors.py <fresh-preimage.json>')
    path = Path(sys.argv[1])
    before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    frozen = load_pinned(RESEARCH / 'existing-drivetrain-service-parts-final-preimage-2026-09-08.json', FROZEN_PREIMAGE_SHA)
    for section in ('templates', 'fields', 'existing_definitions'):
        if stripped(before[section]) != stripped(frozen[section]):
            raise ValueError('Live metadata drifted from the reviewed preimage: ' + section)
    original = load_pinned(RESEARCH / 'existing-drivetrain-service-parts-catalog-2026-09-08.json', CATALOG_SHA)
    old_cases = load_pinned(RESEARCH / 'existing-drivetrain-service-parts-cases-2026-09-08.json', CASES_SHA)
    templates = deepcopy([t for t in original['templates'] if t['key'] in FAMILIES])
    if len(templates) != 3:
        raise ValueError('The reviewed catalogue must carry exactly the three service-part families')
    legacy = {t['key']: {k for k, r in t['form_contract']['roles'].items() if r == 'legacy'} for t in templates}
    if legacy != {'derailleur_hanger': {'compatible_frame_hint', 'hanger_interface', 'rear_derailleur_mount_type'},
                  'derailleur_pulley': set(),
                  'chain_guide': {'chain_guide_mount_type', 'chainring_teeth'}}:
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
            'scope': 'Hanger, pulley and chain guide owners; extenders, full-mount derailleurs, identity and fill stay outside.',
            'preimage': 'Fresh 2026-09-16 production capture equals the 2026-09-08 final preimage in '
                        'templates, fields and shared definitions; effective bindings 23+7+3 -> 28+7+3.',
            'hanger': 'Frame and derailleur interfaces are declarations of this hanger; a title never resolves them.',
            'pulley': 'Position, speeds, profile and dimensions are per declared unit; rotation and torque need the exact manual.',
            'chain_guide': 'Line-wide interchange is a cross-product claim, not a fact of one SKU.',
            'legacy': 'Published frame hint, hanger interface, mount type and teeth readings are retained without becoming active compatibility.',
            'reviews': 'Root decisions and the row-order delta review (2026-09-08) left no open blocker; adoption then 33/0, now repeated on 38.',
            'released_client': 'f51f3777 decodes row_conditions, row_coherence and two-element scalar pairs; one two-element pair here, no strict order.',
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
    print(json.dumps({'templates': 3, 'new_definitions': len(packet['records']['spec_definitions']),
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'pending_cases': len(cases['pending_cases']),
                      'patches': len(packet['patches']),
                      'contract_versions': {t['key']: t['contract_version'] for t in packet['records']['spec_templates']},
                      'bindings': before['effective_bindings'], 'published': False, 'facts_changed': 0}))


if __name__ == '__main__':
    main()
