#!/usr/bin/env python3
"""Prepare the bearing and bottom bracket owners against a fresh preimage, never publish.

Shared definitions the catalogue labels new but that already live in production
with the same id and attributes are adopted as existing (crank_bolt_thread was
created by the crank publication of 2026-09-16).

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

PREFIX = 'bearing-bb-2026-09-16'
FAMILIES = ('bearing', 'bottom_bracket', 'bottom_bracket_axle', 'bottom_bracket_bearing', 'bottom_bracket_cup')
CATALOG_SHA = '62bd5a7e860000bbc3e36ce2b2a10e9640052b8e501ffca8b6690640a29bc2b6'
CASES_SHA = '5f61afff3507aaca14679858a7904fe9a97c2eed16267d997d108c826b65c4ff'
FROZEN_PREIMAGE_SHA = '385f6924ded3e54254bd4f974792c444f651d0b92e89527648b77a5b2b3868f8'
# New scalar definitions with operator/customer meaning. Free-text OEM
# designations, row tables and the retired legacy readings stay outside filters.
SURFACE_FIELDS = {
    'ball_count_per_pack', 'bb_cup_inner_seat_angle_deg', 'bb_cup_outer_seat_angle_deg',
    'bb_cup_seat_bevel', 'bearing_element_retention', 'bearing_included',
    'bearing_inner_contact_angle_deg', 'bearing_outer_contact_angle_deg',
    'bearing_race_contact_angle_deg', 'bearing_race_type', 'bearing_regreasable',
    'bearing_row_count', 'bearing_seal_type', 'bearing_seat_geometry', 'bearing_supply_form',
    'bearing_width_mm',
}
DEAD_ON_ARRIVAL = {}
ADOPT_LIVE = {'crank_bolt_thread'}


def stripped(records):
    return {json.dumps(r, sort_keys=True) for r in records}


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_bearing_bb_successors.py <fresh-preimage.json>')
    path = Path(sys.argv[1])
    before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    frozen = load_pinned(RESEARCH / 'existing-bearing-bb-publication-preimage-2026-09-07.json', FROZEN_PREIMAGE_SHA)
    for section in ('templates', 'fields', 'existing_definitions'):
        live = [r for r in before[section] if section != 'existing_definitions' or r['key'] not in ADOPT_LIVE]
        if stripped(live) != stripped(frozen[section]):
            raise ValueError('Live metadata drifted from the reviewed preimage: ' + section)
    original = load_pinned(RESEARCH / 'existing-bearing-bb-catalog-2026-09-07.json', CATALOG_SHA)
    old_cases = load_pinned(RESEARCH / 'existing-bearing-bb-cases-2026-09-07.json', CASES_SHA)
    templates = deepcopy([t for t in original['templates'] if t['key'] in FAMILIES])
    if len(templates) != 5:
        raise ValueError('The reviewed catalogue must carry exactly the five bearing families')
    legacy = {t['key']: {k for k, r in t['form_contract']['roles'].items() if r == 'legacy'} for t in templates}
    if legacy != {'bearing': set(),
                  'bottom_bracket': {'bb_ball_count_per_side', 'bb_ball_size_in', 'bb_construction',
                                     'bb_cup_outer_diameter_mm', 'bb_cup_thread_pair', 'bb_shell_diameter_mm',
                                     'bb_shell_standard', 'bb_shell_width_mm', 'bb_spacer_stack_mm',
                                     'bearing_size_code', 'spindle_interface_accepted'},
                  'bottom_bracket_axle': {'bb_construction'},
                  'bottom_bracket_bearing': {'bb_construction', 'spindle_diameter_mm'},
                  'bottom_bracket_cup': {'bb_construction', 'bb_cup_outer_diameter_mm', 'bb_cup_thread_pair',
                                         'bb_shell_standard', 'bb_shell_width_mm', 'spindle_interface_accepted'}}:
        raise ValueError('The legacy boundary changed; re-adjudicate it')
    used = {f['key'] for t in templates for f in t['fields']}
    definitions = {k: deepcopy(original['definitions'][k]) for k in sorted(used)}
    live_defs = {d['key']: d for d in before['existing_definitions']}
    for key in ADOPT_LIVE:
        wanted, live = definitions[key], live_defs.get(key)
        if live is None or wanted['origin'] != 'new':
            raise ValueError('Adoption expects a live definition the catalogue still labels new: ' + key)
        options = [o.get('value') or o.get('label') or o.get('key') for o in live.get('options', [])]
        if (wanted['id'], wanted['label'], wanted['data_type'], wanted['unit'], wanted['validation_rules']) != (
                live['id'], live['label'], live['data_type'], live['unit'], live['validation_rules']) or \
                sorted(wanted['allowed_values']) != sorted(live['allowed_values']):
            raise ValueError('Live definition differs from the reviewed one; re-adjudicate it: ' + key)
        wanted['origin'] = 'existing'
    if any(d['origin'] == 'new' and d['key'] in live_defs for d in definitions.values()):
        raise ValueError('A definition labelled new already exists live; re-adjudicate it')
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
            'scope': 'Bearing, bottom bracket, axle, motor bearing and cup owners; cranks, identity and fill stay outside.',
            'preimage': 'Fresh 2026-09-16 production capture equals the 2026-09-07 publication preimage in '
                        'templates, fields and shared definitions, plus one live definition adopted; '
                        'effective bindings 9+34+3+3+8 -> 16+38+4+5+9.',
            'adopted_live_definitions': sorted(ADOPT_LIVE),
            'adopted_reason': 'crank_bolt_thread was created by 20260916070000 with the same deterministic id, '
                              'label, type and options this catalogue proposed; it is reused, not recreated.',
            'ownership': 'One fact, one owner: shell, cup, axle and bearing facts each live with their piece.',
            'legacy': 'Published shell, cup, construction and spindle readings are retained without becoming active compatibility.',
            'reviews': 'Root decisions and the final independent review (2026-09-07) closed with one non-blocking note on bb_accepted_spindles.',
            'released_client': 'f51f3777 decodes row_conditions; no scalar pairs and no strict order here.',
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
    print(json.dumps({'templates': 5, 'new_definitions': len(packet['records']['spec_definitions']),
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'pending_cases': len(cases['pending_cases']),
                      'patches': len(packet['patches']),
                      'contract_versions': {t['key']: t['contract_version'] for t in packet['records']['spec_templates']},
                      'bindings': before['effective_bindings'], 'published': False, 'facts_changed': 0}))


if __name__ == '__main__':
    main()
