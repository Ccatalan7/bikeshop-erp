#!/usr/bin/env python3
"""Prepare the hub and rim owners against a fresh preimage, never publish.

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

PREFIX = 'hub-rim-2026-09-16'
FAMILIES = ('hub', 'rim')
CATALOG_SHA = '7585bdb1f1b5365e7474324b37e6d20a287d92cbce74319ed53af3ffb663b1a3'
CASES_SHA = 'bab19fbb361c1823c01c373704298013ba6ff3c56027bb44f01eb972552f774c'
FROZEN_PREIMAGE_SHA = '247c106d4aab8d342931739dc4acb964ddbe6184fd18f0c9a4d8357e653f5b78'
# New scalar definitions with operator/customer meaning. Free-text OEM
# designations, row tables and the retired legacy readings stay outside filters.
SURFACE_FIELDS = {
    'center_to_flange_left_mm', 'center_to_flange_right_mm', 'flange_pcd_left_mm',
    'flange_pcd_right_mm', 'hub_axle_diameter_mm', 'hub_axle_mount_kind',
    'hub_drive_receiver_kind', 'hub_drive_receiver_present', 'hub_flange_to_flange_mm',
    'hub_package_piece_count', 'hub_package_position', 'hub_rotor_mount_present',
    'hub_spoke_head_interface', 'hub_thru_axle_supplied', 'rim_profile_height_mm',
    'rim_spoke_hole_diameter_mm', 'rim_tire_bed_access_hole_mm', 'rim_valve_bore_mm',
    'spoke_hole_count', 'spoke_hole_diameter_mm',
}


def stripped(records):
    return {json.dumps(r, sort_keys=True) for r in records}


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_hub_rim_successors.py <fresh-preimage.json>')
    path = Path(sys.argv[1])
    before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    frozen = load_pinned(RESEARCH / 'existing-hub-rim-final-preimage-2026-09-08.json', FROZEN_PREIMAGE_SHA)
    for section in ('templates', 'fields', 'existing_definitions'):
        if stripped(before[section]) != stripped(frozen[section]):
            raise ValueError('Live metadata drifted from the reviewed preimage: ' + section)
    original = load_pinned(RESEARCH / 'existing-hub-rim-catalog-2026-09-08.json', CATALOG_SHA)
    old_cases = load_pinned(RESEARCH / 'existing-hub-rim-cases-2026-09-08.json', CASES_SHA)
    templates = deepcopy([t for t in original['templates'] if t['key'] in FAMILIES])
    if len(templates) != 2:
        raise ValueError('The reviewed catalogue must carry exactly hub and rim')
    legacy = {t['key']: {k for k, r in t['form_contract']['roles'].items() if r == 'legacy'} for t in templates}
    if legacy != {'hub': {'wheel_position', 'hub_spacing_mm', 'axle_type', 'thru_axle_thread',
                          'spoke_holes', 'rear_drive_interface', 'freehub_type'},
                  'rim': {'wheel_size', 'spoke_holes', 'valve_hole', 'valve_type'}}:
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
            'scope': 'The hub and rim owners only; no built wheel, no fill, no assignment.',
            'preimage': 'Fresh 2026-09-16 production capture equals the 2026-09-08 final preimage in '
                        'templates, fields and shared definitions; effective bindings 48+41 -> 52+44.',
            'hub_ownership': 'A front/rear package preserves separate axles, bearings, spoke anchors, rotors and flange geometry.',
            'axle': 'An axle dimension needs its datum; frame thru-axle threads are not hub bore facts.',
            'rim': 'Clincher bead measurements require a clincher profile; a component tension limit is not an assembled-wheel observation.',
            'legacy': 'All published definitions and existing observation IDs remain unchanged; retired usage is explicit.',
            'reviews': 'Root adjudication and the independent delta review (2026-09-08) left two non-blocking findings and no open blocker.',
            'released_client': 'f51f3777 decodes row_conditions and row_coherence (product_spec_coherence.dart); no scalar pairs and no strict order here.',
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
    print(json.dumps({'templates': 2, 'new_definitions': len(packet['records']['spec_definitions']),
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'pending_cases': len(cases['pending_cases']),
                      'patches': len(packet['patches']),
                      'contract_versions': {t['key']: t['contract_version'] for t in packet['records']['spec_templates']},
                      'bindings': before['effective_bindings'], 'published': False, 'facts_changed': 0}))


if __name__ == '__main__':
    main()
