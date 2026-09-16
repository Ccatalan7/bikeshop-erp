#!/usr/bin/env python3
"""Prepare the chain and connector owners against a fresh preimage, never publish.

The reviewed 2026-09-08 chain-drive catalogue also carried drivetrain_kit, which
was published separately on 2026-09-15 (20260915023000). Only chain and
chain_link are compiled here; the frozen preimage is compared restricted to them.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

from compile_existing_spec_publication import (
    compile_packet, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

PREFIX = 'chain-drive-2026-09-16'
FAMILIES = ('chain', 'chain_link')
CATALOG_SHA = 'ab1e52a97a73ea1530d48845b7b470871f35ec7898687bbbcda71e4d80dcd1f5'
CASES_SHA = '987ec6c10317ea76e1702cd660c18dcc347e4ed97a1faaafc7523801a09dd653'
FROZEN_PREIMAGE_SHA = '7a1fdb10197ec113d062d5dda761c60429cff1238d4db027d0985e91fb08cbab'
SURFACE_FIELDS = {'chain_pitch_mm', 'connector_reuse_limit'}


def stripped(records):
    return {json.dumps(r, sort_keys=True) for r in records}


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_chain_drive_successors.py <fresh-preimage.json>')
    path = Path(sys.argv[1])
    before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    if {t['key'] for t in before['templates']} != set(FAMILIES):
        raise ValueError('The fresh preimage must carry exactly chain and chain_link')
    frozen = load_pinned(RESEARCH / 'existing-chain-drive-final-preimage-2026-09-08.json', FROZEN_PREIMAGE_SHA)
    frozen_templates = [t for t in frozen['templates'] if t['key'] in FAMILIES]
    frozen_ids = {t['id'] for t in frozen_templates}
    frozen_fields = [f for f in frozen['fields'] if f['template_id'] in frozen_ids]
    live_keys = {d['key'] for d in before['existing_definitions']}
    frozen_defs = [d for d in frozen['existing_definitions'] if d['key'] in live_keys]
    for name, a, b in (('templates', frozen_templates, before['templates']),
                       ('fields', frozen_fields, before['fields']),
                       ('existing_definitions', frozen_defs, before['existing_definitions'])):
        if stripped(a) != stripped(b):
            raise ValueError('Live metadata drifted from the reviewed preimage: ' + name)
    original = load_pinned(RESEARCH / 'existing-chain-drive-catalog-2026-09-08.json', CATALOG_SHA)
    old_cases = load_pinned(RESEARCH / 'existing-chain-drive-cases-2026-09-08.json', CASES_SHA)
    templates = deepcopy([t for t in original['templates'] if t['key'] in FAMILIES])
    if len(templates) != 2:
        raise ValueError('The reviewed catalogue must carry chain and chain_link')
    used = {f['key'] for t in templates for f in t['fields']}
    definitions = {k: deepcopy(original['definitions'][k]) for k in sorted(used)}
    if any(d['origin'] == 'new' and d['key'] in live_keys for d in definitions.values()):
        raise ValueError('A definition labelled new already exists live; re-adjudicate it')
    legacy = {t['key']: {k for k, r in t['form_contract']['roles'].items() if r == 'legacy'} for t in templates}
    if legacy != {'chain': {'chain_profile_family', 'drivetrain_declared_compatible_ecosystems',
                            'drivetrain_platform', 'drivetrain_primary_ecosystem'},
                  'chain_link': {'chain_connector_target', 'chain_profile_family',
                                 'drivetrain_declared_compatible_ecosystems', 'drivetrain_mode',
                                 'drivetrain_primary_ecosystem'}}:
        raise ValueError('The legacy boundary changed; re-adjudicate it')
    catalog = {**deepcopy(original), 'templates': templates, 'definitions': definitions,
               'source_catalog_sha256': CATALOG_SHA, 'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False, 'publication_authorized': False}
    cp = RESEARCH / (PREFIX + '-catalog.json'); write_json(cp, catalog)
    sha = hashlib.sha256(cp.read_bytes()).hexdigest()
    cases = {'schema_version': 1, 'catalogue_sha256': sha,
             'cases': deepcopy([c for c in old_cases['cases'] if c['template'] in FAMILIES]),
             'pending_cases': deepcopy([c for c in old_cases.get('pending_cases', [])
                                        if c.get('template') in FAMILIES or c.get('template') is None])}
    case_path = RESEARCH / (PREFIX + '-cases.json'); write_json(case_path, cases)
    packet = compile_packet(catalog=catalog, cases=cases, before=before, families=list(FAMILIES),
        hashes={'catalog_sha256': sha, 'cases_sha256': hashlib.sha256(case_path.read_bytes()).hexdigest(),
                'preimage_sha256': hashlib.sha256(path.read_bytes()).hexdigest()},
        adjudication={
            'status': 'candidate_under_sole_owner_review',
            'scope': 'Chain and connector owners only; drivetrain_kit was published on 2026-09-15 and is not touched.',
            'preimage': 'Fresh 2026-09-16 production capture equals the 2026-09-08 final preimage restricted to '
                        'chain and chain_link; effective bindings 31+9 -> 35+9.',
            'width': 'Internal width and the manufacturer designation are separate declarations; no width is inferred from speeds.',
            'connector': 'A connector declares its documented targets and reuse limit; a matching pitch never approves a chain.',
            'legacy': 'Published profile, platform and ecosystem readings are retained without becoming active compatibility.',
            'reviews': 'Independent review F1, F3 and F4 corrected; F2 concerned the kit member profile, published separately.',
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
    print(json.dumps({'templates': 2, 'new_definitions': len(packet['records']['spec_definitions']),
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'pending_cases': len(cases['pending_cases']),
                      'patches': len(packet['patches']),
                      'contract_versions': {t['key']: t['contract_version'] for t in packet['records']['spec_templates']},
                      'bindings': before['effective_bindings'], 'published': False, 'facts_changed': 0}))


if __name__ == '__main__':
    main()
