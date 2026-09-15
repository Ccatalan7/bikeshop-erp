#!/usr/bin/env python3
"""Prepare exact spoke metadata for local evaluation; never publish it."""
import json

from compile_existing_spec_publication import (
    compile_packet as prepare, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

CATALOG_SHA = '4a604b432a05f598dc3d1233880c111e4714fed986a6823b71a3292142f2353f'
CASES_SHA = 'c3e3668e8d9124d72cb35a8c96c262238e9857ae9c78e4bf6b59649e565e5c4d'
PREIMAGE_SHA = '4d62f70e114ea85457a1f4d29e8120dbef86edd418374dffe7fb7ca25ddaab3c'


def compile_packet():
    catalog = load_pinned(RESEARCH / 'existing-spoke-catalog-2026-09-08.json', CATALOG_SHA)
    cases = load_pinned(RESEARCH / 'existing-spoke-cases-2026-09-08.json', CASES_SHA)
    before = load_pinned(RESEARCH / 'existing-spoke-review-preimage-2026-09-08.json', PREIMAGE_SHA)
    packet = prepare(catalog=catalog, cases=cases, before=before, families=['spoke'],
                     hashes={'catalog_sha256': CATALOG_SHA, 'cases_sha256': CASES_SHA,
                             'preimage_sha256': PREIMAGE_SHA}, adjudication={
        'sections': 'Physical positions within this SKU, never all OEM variants.',
        'thread': 'Wire diameter, major thread diameter and gauge are separate declarations.',
        'contents': 'Included nipples have component identity and quantity; no inferred tool or wheel approval.',
        'legacy': 'Published gauge and two-choice head readings are retained without becoming active compatibility.',
        'activation_gate': 'Independent review, model-scoped fitment integration and client distribution remain open.',
    })
    return packet, cases


if __name__ == '__main__':
    packet, cases = compile_packet()
    write_json(RESEARCH / 'existing-spoke-publication-packet-2026-09-08.json', packet)
    target = ROOT / '.tmp/db/existing-spoke-forward-candidate.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    (target.parent / 'existing-spoke-forward-verification.sql').write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': 1, 'cases': len(cases['cases']),
                      'new_definitions': len(packet['records']['spec_definitions']),
                      'patches': len(packet['patches']), 'production_writes': False}))
