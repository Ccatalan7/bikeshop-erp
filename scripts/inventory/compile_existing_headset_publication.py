#!/usr/bin/env python3
"""Prepare original headset metadata for local evaluation; never publish it."""
import json

from compile_existing_spec_publication import (
    compile_packet as prepare, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

CATALOG_SHA = '02968a0066cc3c51f401de205bc6dab933923b8cfe3ea4e9d2c42561f166db57'
CASES_SHA = '1eda457a90cf3e17c17a8c52ba420db1d755a2da47d1acc6fde342d1ad33fa75'
PREIMAGE_SHA = '4112b2b4b7bbc970617aafcd0c5cca54903d7f3f82cdb1a0897959358a469131'


def compile_packet():
    catalog = load_pinned(RESEARCH / 'existing-headset-catalog-2026-09-08.json', CATALOG_SHA)
    cases = load_pinned(RESEARCH / 'existing-headset-cases-2026-09-08.json', CASES_SHA)
    before = load_pinned(RESEARCH / 'existing-headset-publication-preimage-2026-09-08.json', PREIMAGE_SHA)
    packet = prepare(catalog=catalog, cases=cases, before=before, families=['headset'],
        hashes={'catalog_sha256': CATALOG_SHA, 'cases_sha256': CASES_SHA,
                'preimage_sha256': PREIMAGE_SHA}, adjudication={
            'ends': 'Upper and lower SHIS, bearings and installed heights have separate physical owners.',
            'dimensions': 'SHIS codes are not literal measured bores; cartridge bodies and loose balls have different dimensions.',
            'contents': 'A supplied crown race is identified content and does not declare a fork interface.',
            'legacy': 'Existing standard, steerer and bearing-system readings are retained without selecting new end interfaces.',
            'activation_gate': 'Requires the undeployed rows-schema v2 strict-order extension, independent review, model-scoped relations and client distribution.',
        })
    return packet, cases


if __name__ == '__main__':
    packet, cases = compile_packet()
    write_json(RESEARCH / 'existing-headset-publication-packet-2026-09-08.json', packet)
    target = ROOT / '.tmp/db/existing-headset-forward-candidate.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    (target.parent / 'existing-headset-forward-verification.sql').write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': 1, 'cases': len(cases['cases']),
                      'new_definitions': len(packet['records']['spec_definitions']),
                      'patches': len(packet['patches']), 'production_writes': False}))
