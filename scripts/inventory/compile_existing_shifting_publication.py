#!/usr/bin/env python3
"""Prepare adjudicated shifting metadata; publication is a separate operation."""
import json
from compile_existing_spec_publication import (
    compile_packet as prepare, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

CATALOG_SHA = '924a77009aff0db778c3e909c8e286edf9d80037c94f0739a0d800d89d145c39'
CASES_SHA = 'ca7feac7c5b72fb41b4fe495368e611aec1d40ad1a96ed05436186440bd3630a'
PREIMAGE_SHA = '7cee2317b653acf176d48e4bbed3f3afdca54dafae6535de52262a415c40f655'


def compile_packet():
    catalog = load_pinned(RESEARCH/'existing-shifting-adjudicated-catalog-2026-09-08.json', CATALOG_SHA)
    cases = load_pinned(RESEARCH/'existing-shifting-adjudicated-cases-2026-09-08.json', CASES_SHA)
    before = load_pinned(RESEARCH/'existing-shifting-final-preimage-2026-09-08.json', PREIMAGE_SHA)
    packet = prepare(catalog=catalog, cases=cases, before=before,
        families=['shifter', 'rear_derailleur', 'front_derailleur'],
        hashes={'catalog_sha256': CATALOG_SHA, 'cases_sha256': CASES_SHA, 'preimage_sha256': PREIMAGE_SHA},
        adjudication=catalog['root_adjudications'] | {
            'activation_gate': 'Independent review, exact local SQL, live adoption, model-scoped reference integration and client verification/distribution.'})
    return packet, cases


if __name__ == '__main__':
    packet, cases = compile_packet()
    write_json(RESEARCH/'existing-shifting-publication-packet-2026-09-08.json', packet)
    target = ROOT/'.tmp/db/existing-shifting-forward-candidate.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    (target.parent/'existing-shifting-forward-verification.sql').write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': 3, 'new_definitions': len(packet['records']['spec_definitions']),
        'patches': len(packet['patches']), 'cases': len(cases['cases']), 'production_writes': False}))
