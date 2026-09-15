#!/usr/bin/env python3
"""Prepare the adjudicated hub/rim metadata for a local trial, not deployment."""
import json

from compile_existing_spec_publication import (
    compile_packet as prepare, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

CATALOG_SHA = '7585bdb1f1b5365e7474324b37e6d20a287d92cbce74319ed53af3ffb663b1a3'
CASES_SHA = 'bab19fbb361c1823c01c373704298013ba6ff3c56027bb44f01eb972552f774c'
PREIMAGE_SHA = '247c106d4aab8d342931739dc4acb964ddbe6184fd18f0c9a4d8357e653f5b78'


def compile_packet():
    catalog = load_pinned(RESEARCH / 'existing-hub-rim-catalog-2026-09-08.json', CATALOG_SHA)
    cases = load_pinned(RESEARCH / 'existing-hub-rim-cases-2026-09-08.json', CASES_SHA)
    before = load_pinned(RESEARCH / 'existing-hub-rim-final-preimage-2026-09-08.json', PREIMAGE_SHA)
    packet = prepare(catalog=catalog, cases=cases, before=before, families=['hub', 'rim'],
        hashes={'catalog_sha256': CATALOG_SHA, 'cases_sha256': CASES_SHA,
                'preimage_sha256': PREIMAGE_SHA}, adjudication={
            'hub_ownership': 'A front/rear package preserves separate axles, bearings, spoke anchors, rotors and flange geometry.',
            'axle': 'An axle dimension needs its datum; frame thru-axle threads are not hub bore facts.',
            'rim': 'Clincher bead measurements require a clincher profile; a component tension limit is not an assembled-wheel observation.',
            'legacy': 'All published definitions and existing observation IDs remain unchanged; retired usage is explicit.',
            'activation_gate': 'Independent final review, model-scoped configuration integration and client qualification/distribution remain open.',
        })
    return packet, cases


if __name__ == '__main__':
    packet, cases = compile_packet()
    write_json(RESEARCH / 'existing-hub-rim-publication-packet-2026-09-08.json', packet)
    target = ROOT / '.tmp/db/existing-hub-rim-forward-candidate.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    (target.parent / 'existing-hub-rim-forward-verification.sql').write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': 2, 'cases': len(cases['cases']),
                      'new_definitions': len(packet['records']['spec_definitions']),
                      'patches': len(packet['patches']), 'production_writes': False}))
