#!/usr/bin/env python3
"""Prepare the crankset, crank arm and chainring owners against a fresh preimage, never publish.

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

PREFIX = 'crank-drive-2026-09-16'
FAMILIES = ('crankset', 'crank_arm', 'chainring')
CATALOG_SHA = 'b477332c223b3d667a0a2542701fca8697802d5bee5c98f703e05588448b5458'
CASES_SHA = 'f5dbf16cd23ccab9283b8f42778b4a2ded82ed4752e60c091e94216a376f8da4'
FROZEN_PREIMAGE_SHA = 'e74791e3bd5809d37902b5b920b4c03d67c0df53e2b24275fee1b8728e325afe'
# New scalar definitions with operator/customer meaning. Free-text OEM
# designations, row tables and the retired legacy readings stay outside filters.
SURFACE_FIELDS = {
    'bottom_bracket_included', 'chainring_bolt_pattern_symmetric', 'chainring_mounting',
    'chainring_package_kind', 'chainring_position', 'chainring_set_member_count',
    'crank_arm_carries_chainring_mount', 'crank_arm_system_construction', 'crank_arm_unit_count',
    'crank_bolt_thread', 'crank_fixing_bolt_included', 'crankset_chain_guard_included',
    'crankset_construction', 'included_chainring_count', 'spindle_included', 'teeth_count',
}
# Root retired spindle_taper_standard and compatible_rear_speeds to legacy with
# helpers and 19 reviewed cases pinning that they no longer answer; they are
# created as retired selectors, not dropped.
DEAD_ON_ARRIVAL = {}


def stripped(records):
    return {json.dumps(r, sort_keys=True) for r in records}


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_crank_drive_successors.py <fresh-preimage.json>')
    path = Path(sys.argv[1])
    before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    frozen = load_pinned(RESEARCH / 'existing-crank-drive-final-preimage-2026-09-08.json', FROZEN_PREIMAGE_SHA)
    for section in ('templates', 'fields', 'existing_definitions'):
        if stripped(before[section]) != stripped(frozen[section]):
            raise ValueError('Live metadata drifted from the reviewed preimage: ' + section)
    original = load_pinned(RESEARCH / 'existing-crank-drive-adjudicated-catalog-2026-09-08.json', CATALOG_SHA)
    old_cases = load_pinned(RESEARCH / 'existing-crank-drive-adjudicated-cases-2026-09-08.json', CASES_SHA)
    templates = deepcopy([t for t in original['templates'] if t['key'] in FAMILIES])
    if len(templates) != 3:
        raise ValueError('The reviewed catalogue must carry exactly the three crank families')
    # A definition that never held an observation has nothing to preserve: a
    # new key born with the legacy role is a dead field, not retained history.
    dropped = set()
    for template in templates:
        for key in DEAD_ON_ARRIVAL.get(template['key'], []):
            contract = template['form_contract']
            if contract['roles'].get(key) != 'legacy' or original['definitions'][key]['origin'] != 'new':
                raise ValueError('Only a new key with legacy role may be dropped: ' + key)
            template['fields'] = [f for f in template['fields'] if f['key'] != key]
            for section in ('roles', 'semantic_roles', 'labels', 'helpers', 'allowed_when',
                            'required_when', 'prerequisites', 'allowed_options', 'evidence_requirements'):
                contract.get(section, {}).pop(key, None)
            dropped.add(key)
    if any(k in json.dumps(c['values']) for c in old_cases['cases'] for k in dropped):
        raise ValueError('A reviewed case exercises a dropped key; re-adjudicate it')
    legacy = {t['key']: {k for k, r in t['form_contract']['roles'].items() if r == 'legacy'} for t in templates}
    if legacy != {'crankset': {'bottom_bracket_family', 'chain_profile_family', 'chainring_bcd_mm',
                               'chainring_count', 'chainring_teeth', 'compatible_rear_speeds',
                               'drivetrain_platform', 'drivetrain_speeds', 'front_chainring_count',
                               'kit_members', 'spindle_interface', 'spindle_taper_standard'},
                  'crank_arm': {'spindle_interface', 'spindle_taper_standard'},
                  'chainring': {'chain_profile_family', 'chainring_bolt_count', 'chainring_offset_mm',
                                'chainring_teeth', 'compatible_rear_speeds', 'drivetrain_platform',
                                'drivetrain_speeds'}}:
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
            'scope': 'Crankset, crank arm and chainring owners; bottom brackets, identity and fill stay outside.',
            'preimage': 'Fresh 2026-09-16 production capture equals the 2026-09-08 final preimage in '
                        'templates, fields and shared definitions; effective bindings 28+7+16 -> 32+8+17.',
            'retired_selectors_created_as_legacy': ['spindle_taper_standard', 'compatible_rear_speeds'],
            'retired_selectors_reason': 'Root retired both selectors to legacy with helpers; nineteen reviewed cases '
                                        'carry them as inert values and four assert they no longer answer. Unlike '
                                        'max_chainring_teeth in shifting, the retirement is adjudicated evidence, so '
                                        'the definitions are created retired rather than dropped.',
            'integrated_motor_axle': 'The published axle interface domain has no token for an integrated motor spindle; '
                                     'the manufacturer designation lives in crank_arm_spindle_designation and no token is invented.',
            'identity': 'Manufacturer codes in titles are resolved in the product identity, never in a second store.',
            'legacy': 'Published platform, speed, teeth, BCD and spindle readings are retained without becoming active compatibility.',
            'reviews': 'Claude review H1-H4 adjudicated by Root with five closures (2026-09-08); no open blocker on the metadata.',
            'released_client': 'f51f3777 decodes row_conditions and row_coherence; no scalar pairs and no strict order here.',
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
