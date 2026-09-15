#!/usr/bin/env python3
"""Prepare reviewed service-part metadata for local evaluation, never deploy."""
import json

from compile_existing_spec_publication import (
    compile_packet as prepare, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

CATALOG_SHA = '1c10d400a1bea3f26c33c67c5a81dece3cdae9c7a4f954eea74be695b0c2216f'
CASES_SHA = '5084eeb7d917e294ed21caaea4c7b266a7989cc6b963410f184c543a871fbb9b'
PREIMAGE_SHA = '09a0e6b26958535000cda8e234992b904c4371387dc47e0b702dbd8ba076e1c9'
FAMILIES = ['derailleur_hanger', 'derailleur_pulley', 'chain_guide']


def compile_packet():
    catalog = load_pinned(RESEARCH / 'existing-drivetrain-service-parts-catalog-2026-09-08.json', CATALOG_SHA)
    cases = load_pinned(RESEARCH / 'existing-drivetrain-service-parts-cases-2026-09-08.json', CASES_SHA)
    before = load_pinned(RESEARCH / 'existing-drivetrain-service-parts-final-preimage-2026-09-08.json', PREIMAGE_SHA)
    packet = prepare(catalog=catalog, cases=cases, before=before, families=FAMILIES,
        hashes={'catalog_sha256': CATALOG_SHA, 'cases_sha256': CASES_SHA,
                'preimage_sha256': PREIMAGE_SHA}, adjudication={
            'hanger': 'The frame and derailleur ends are separate; the mounting bolt does not identify the hanger.',
            'pulley': 'Each physical packaged pulley owns its dimensions and speed/cage/model declarations.',
            'guide': 'Mounting, individual included parts and assembled configurations have separate owners.',
            'weight': 'OneUp assembly weights cannot be copied into loose bash plate weights.',
            'legacy': 'All published definitions and observations retain their identity; retired uses remain auditable.',
            'activation_gate': 'Independent final review, live adoption, assignment review, OEM relations and client verification/distribution remain open.',
        })
    return packet, cases


if __name__ == '__main__':
    packet, cases = compile_packet()
    write_json(RESEARCH / 'existing-drivetrain-service-parts-publication-packet-2026-09-08.json', packet)
    target = ROOT / '.tmp/db/existing-drivetrain-service-parts-forward-candidate.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    (target.parent / 'existing-drivetrain-service-parts-forward-verification.sql').write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': len(FAMILIES), 'cases': len(cases['cases']),
        'new_definitions': len(packet['records']['spec_definitions']),
        'patches': len(packet['patches']), 'production_writes': False}))
