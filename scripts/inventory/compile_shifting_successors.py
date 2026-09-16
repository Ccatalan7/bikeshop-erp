#!/usr/bin/env python3
"""Prepare the shifter and derailleur owners against a fresh preimage, never publish.

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

PREFIX = 'shifting-2026-09-16'
FAMILIES = ('shifter', 'rear_derailleur', 'front_derailleur')
CATALOG_SHA = '924a77009aff0db778c3e909c8e286edf9d80037c94f0739a0d800d89d145c39'
CASES_SHA = 'ca7feac7c5b72fb41b4fe495368e611aec1d40ad1a96ed05436186440bd3630a'
FROZEN_PREIMAGE_SHA = '7cee2317b653acf176d48e4bbed3f3afdca54dafae6535de52262a415c40f655'
# New scalar definitions with operator/customer meaning. Free-text OEM
# designations, row tables and the retired legacy readings stay outside filters.
SURFACE_FIELDS = {
    'shifter_actuation_mode', 'shifter_control_style', 'shifter_unit_count',
    'rear_derailleur_spring_return', 'rear_derailleur_supplied_mount_adapter',
    'front_derailleur_cable_anchor', 'front_derailleur_cable_pull', 'front_derailleur_swing',
}
DEAD_ON_ARRIVAL = {'front_derailleur': ['max_chainring_teeth']}


def stripped(records):
    return {json.dumps(r, sort_keys=True) for r in records}


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_shifting_successors.py <fresh-preimage.json>')
    path = Path(sys.argv[1])
    before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    frozen = load_pinned(RESEARCH / 'existing-shifting-final-preimage-2026-09-08.json', FROZEN_PREIMAGE_SHA)
    for section in ('templates', 'fields', 'existing_definitions'):
        if stripped(before[section]) != stripped(frozen[section]):
            raise ValueError('Live metadata drifted from the reviewed preimage: ' + section)
    original = load_pinned(RESEARCH / 'existing-shifting-adjudicated-catalog-2026-09-08.json', CATALOG_SHA)
    old_cases = load_pinned(RESEARCH / 'existing-shifting-adjudicated-cases-2026-09-08.json', CASES_SHA)
    templates = deepcopy([t for t in original['templates'] if t['key'] in FAMILIES])
    if len(templates) != 3:
        raise ValueError('The reviewed catalogue must carry exactly the three shifting families')
    # A definition that never held an observation has nothing to preserve: a
    # new key born with the legacy role is a dead field, not retained history.
    for template in templates:
        for key in DEAD_ON_ARRIVAL.get(template['key'], []):
            contract = template['form_contract']
            if contract['roles'].get(key) != 'legacy' or original['definitions'][key]['origin'] != 'new':
                raise ValueError('Only a new key with legacy role may be dropped: ' + key)
            template['fields'] = [f for f in template['fields'] if f['key'] != key]
            for section in ('roles', 'semantic_roles', 'labels', 'helpers', 'allowed_when',
                            'required_when', 'prerequisites', 'allowed_options', 'evidence_requirements'):
                contract.get(section, {}).pop(key, None)
    legacy = {t['key']: {k for k, r in t['form_contract']['roles'].items() if r == 'legacy'} for t in templates}
    shared = {'drivetrain_declared_compatible_ecosystems', 'drivetrain_platform',
              'drivetrain_primary_ecosystem', 'drivetrain_speeds', 'shift_actuation_family'}
    if legacy != {'shifter': shared | {'derailleur_models_compatible', 'front_chainring_count', 'kit_members'},
                  'rear_derailleur': shared | {'rear_derailleur_max_teeth', 'rear_derailleur_min_teeth',
                                               'rear_derailleur_total_capacity_teeth'},
                  'front_derailleur': shared | {'front_chainring_count', 'front_derailleur_clamp_mm',
                                                'front_derailleur_pull_direction'}}:
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
            'scope': 'Shifter, rear and front derailleur owners; combined controls, identity and fill stay outside.',
            'preimage': 'Fresh 2026-09-16 production capture equals the 2026-09-08 final preimage in '
                        'templates, fields and shared definitions; effective bindings 32+35+15 -> 36+40+18.',
            'dead_on_arrival_dropped': DEAD_ON_ARRIVAL,
            'dead_on_arrival_reason': 'max_chainring_teeth was a new definition placed in the legacy section '
                                      'after the maximum moved into documented configurations; no case, helper '
                                      'or observation depends on it, so it is not created.',
            'actuation': 'Index or friction is a property of the control, filled from package or manual, never from a title.',
            'speeds': 'Each documented configuration carries its own speed count; one row cannot hold two counts.',
            'combined_controls': 'Combined shift/brake units belong to brake_shift_combined_control through the assignment queue.',
            'legacy': 'Published platform, ecosystem, speed and teeth readings are retained without becoming active compatibility.',
            'reviews': 'Claude review H1-H5 adjudicated by Root (2026-09-08); no open blocker on the metadata.',
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
