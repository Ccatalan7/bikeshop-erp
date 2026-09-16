#!/usr/bin/env python3
"""Prepare the headset owner against a fresh preimage, never publish.

Adjudicates H-2 of the 2026-09-08 review: the crown race belongs to the lower
end, so a headset declared upper-only cannot claim to include one.

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

PREFIX = 'headset-2026-09-16'
FAMILIES = ('headset',)
CATALOG_SHA = '02968a0066cc3c51f401de205bc6dab933923b8cfe3ea4e9d2c42561f166db57'
CASES_SHA = '1eda457a90cf3e17c17a8c52ba420db1d755a2da47d1acc6fde342d1ad33fa75'
FROZEN_PREIMAGE_SHA = '4112b2b4b7bbc970617aafcd0c5cca54903d7f3f82cdb1a0897959358a469131'
# New scalar definitions with operator/customer meaning. Free-text OEM
# designations, row tables and the retired legacy readings stay outside filters.
SURFACE_FIELDS = {
    'crown_race_included', 'headset_part_scope', 'headset_lower_stack_height_mm',
    'headset_upper_stack_height_mm',
}
LOWER_SCOPES = ['Inferior', 'Completa']
PARK = 'https://www.parktool.com/en-us/blog/repair-help/headset-standards'
SHELDON = 'https://www.sheldonbrown.com/headsets.html'


def lower_gate():
    return {'kind': 'when', 'rows': [[{'field': 'headset_part_scope', 'operator': 'in',
                                       'value_type': 'token', 'value': list(LOWER_SCOPES)}]]}


def crown_race_cases(old_cases):
    """Pin the crown race to the lower end on every scope."""
    upper = next(c for c in old_cases['cases'] if c['id'] == 'hs_loose_balls_record_diameter_and_count')
    complete = next(c for c in old_cases['cases'] if c['id'] == 'hs_complete_does_not_force_a_separate_crown_race')
    cases = []

    def add(base, name, values, *, blocking=(), forbidden=(), sources=()):
        case = deepcopy(base)
        case.update(id='headset_' + name, kind='synthetic_boundary',
                    facts_verified_for_product=False, automatic_fill_authorized=False)
        case['values'].update(values)
        for key, value in list(values.items()):
            if value is None:
                case['values'].pop(key, None)
        case['expected_blocking'] = [{'code': c, 'field': f} for c, f in blocking]
        case['expected_sql_blocking'] = deepcopy(case['expected_blocking'])
        case['forbidden_issue_fields'] = list(forbidden)
        case['source_urls'] = list(sources)
        cases.append(case)
    add(upper, 'an_upper_only_headset_cannot_include_a_crown_race',
        {'crown_race_included': True}, blocking=(('field_applicability', 'crown_race_included'),),
        sources=(PARK, SHELDON))
    add(upper, 'an_upper_only_headset_owes_no_crown_race_answer',
        {'crown_race_included': None}, forbidden=('crown_race_included', 'headset_supplied_crown_race_reference'))
    add(complete, 'a_complete_headset_may_include_a_crown_race_with_its_reference',
        {'crown_race_included': True, 'headset_supplied_crown_race_reference': 'Synthetic crown race ref',
         'spec_evidence_source': 'Ficha sintética'},
        forbidden=('crown_race_included', 'headset_supplied_crown_race_reference'))
    return cases


def stripped(records):
    return {json.dumps(r, sort_keys=True) for r in records}


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_headset_successors.py <fresh-preimage.json>')
    path = Path(sys.argv[1])
    before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    frozen = load_pinned(RESEARCH / 'existing-headset-publication-preimage-2026-09-08.json', FROZEN_PREIMAGE_SHA)
    for section in ('templates', 'fields', 'existing_definitions'):
        if stripped(before[section]) != stripped(frozen[section]):
            raise ValueError('Live metadata drifted from the reviewed preimage: ' + section)
    original = load_pinned(RESEARCH / 'existing-headset-catalog-2026-09-08.json', CATALOG_SHA)
    old_cases = load_pinned(RESEARCH / 'existing-headset-cases-2026-09-08.json', CASES_SHA)
    templates = deepcopy([t for t in original['templates'] if t['key'] in FAMILIES])
    if len(templates) != 1:
        raise ValueError('The reviewed catalogue must carry exactly the spoke family')
    contract = templates[0]['form_contract']
    if {k for k, r in contract['roles'].items() if r == 'legacy'} != {'bearing_system', 'headset_standard', 'steerer_type'}:
        raise ValueError('The legacy boundary changed; re-adjudicate it')
    if contract['allowed_when'].get('crown_race_included') != {'kind': 'always'}:
        raise ValueError('The crown race gate changed; re-adjudicate it')
    contract['allowed_when']['crown_race_included'] = lower_gate()
    contract['required_when']['crown_race_included'] = lower_gate()
    contract['helpers']['crown_race_included'] = (
        'La pista de corona va prensada en la base del tubo de horquilla y pertenece al '
        'extremo inferior. Sólo un juego inferior o completo puede declarar que la incluye; '
        'un extremo superior no la responde.')
    used = {f['key'] for t in templates for f in t['fields']}
    definitions = {k: deepcopy(original['definitions'][k]) for k in sorted(used)}
    catalog = {**deepcopy(original), 'templates': templates, 'definitions': definitions,
               'source_catalog_sha256': CATALOG_SHA, 'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False, 'publication_authorized': False}
    cp = RESEARCH / (PREFIX + '-catalog.json'); write_json(cp, catalog)
    sha = hashlib.sha256(cp.read_bytes()).hexdigest()
    cases = {'schema_version': 1, 'catalogue_sha256': sha,
             'cases': deepcopy(old_cases['cases']) + crown_race_cases(old_cases),
             'pending_cases': deepcopy(old_cases.get('pending_cases', []))}
    absent = next(c for c in cases['cases'] if c['id'] == 'hs_crown_race_absent_disallows_its_reference')
    if absent['values'].get('headset_part_scope') is not None:
        raise ValueError('The reviewed crown race case changed; re-adjudicate it')
    absent['values']['headset_part_scope'] = 'Inferior'
    case_path = RESEARCH / (PREFIX + '-cases.json'); write_json(case_path, cases)
    packet = compile_packet(catalog=catalog, cases=cases, before=before, families=list(FAMILIES),
        hashes={'catalog_sha256': sha, 'cases_sha256': hashlib.sha256(case_path.read_bytes()).hexdigest(),
                'preimage_sha256': hashlib.sha256(path.read_bytes()).hexdigest()},
        adjudication={
            'status': 'candidate_under_sole_owner_review',
            'scope': 'The headset owner only; frames, forks and fill stay outside.',
            'preimage': 'Fresh 2026-09-16 production capture equals the 2026-09-08 publication preimage in '
                        'template, fields and shared definitions; effective bindings 15 -> 16.',
            'ends': 'Upper and lower ends own their SHIS code, bearing table and installed height; SHIS is a nominal code.',
            'crown_race': 'H-2 adjudicated: crown_race_included is allowed and required only for lower or complete scope; '
                          'Park and Sheldon place the crown race in the lower stack, pressed on the fork base. '
                          'An upper-only kit that ships a crown race has no scope token today and stays undeclared.',
            'crown_race_sources': [PARK, SHELDON],
            'geometry': 'H-1 covered: inner larger than outer and non-positive wall thickness block as row_shape (strict row order deployed 2026-09-08).',
            'legacy': 'Published standard, steerer and bearing-system readings are retained without becoming active compatibility.',
            'reviews': 'Independent review dictamen sustained the per-end split; the final delta review confirmed the strict geometry.',
            'released_client': 'f51f3777 decodes row_conditions; no scalar pairs and no strict order construct here.',
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
