#!/usr/bin/env python3
"""Compile reviewed tyre/tube metadata for local tests, without publication."""
import json

from compile_existing_spec_publication import (
    compile_packet as prepare, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

CATALOG_SHA = 'b9e30b145346d52489dc807400a56e7dd38788e74a0e0b269c48f2f35412e619'
CASES_SHA = '7cc47f5df2e152547b3bb0795b3fa6fcd11403bfe88e20bec72010018ea4c9b5'
PREIMAGE_SHA = '48b5602be1decc4ff156bae62ffd1dec409407a0815e9dbf38b67f2dc81097d5'


def compile_packet():
    catalog = load_pinned(RESEARCH / 'existing-tires-tubes-catalog-2026-09-08.json', CATALOG_SHA)
    cases = load_pinned(RESEARCH / 'existing-tires-tubes-cases-2026-09-08.json', CASES_SHA)
    before = load_pinned(RESEARCH / 'existing-tires-tubes-publication-preimage-2026-09-08.json', PREIMAGE_SHA)
    packet = prepare(catalog=catalog, cases=cases, before=before,
                     families=['tire', 'tube', 'rim_strip', 'tubeless_consumable', 'tubeless_valve'],
                     hashes={'catalog_sha256': CATALOG_SHA, 'cases_sha256': CASES_SHA,
                             'preimage_sha256': PREIMAGE_SHA}, adjudication={
        'dose': 'Application identity includes tyre size and conditions, never just MTB or bottle capacity.',
        'valve': 'Core removal is separately evidenced, not inferred from Presta/Schrader/Dunlop.',
        'pressures': 'Order only the minimum/maximum within one scope and unit; preserve other system owners.',
        'contents': 'A component has one identity; its family is not an independent free choice.',
        'relations': 'Existing evaluator tested; source scope and editor/reference integration remain separate gates.',
        'activation_gate': 'Original templates remain unpublished until final independent review and client distribution.',
    })
    return packet, cases


if __name__ == '__main__':
    packet, cases = compile_packet()
    write_json(RESEARCH / 'existing-tires-tubes-publication-packet-2026-09-08.json', packet)
    target = ROOT / '.tmp/db/existing-tires-tubes-forward-candidate.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    (target.parent / 'existing-tires-tubes-forward-verification.sql').write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': 5, 'cases': len(cases['cases']),
                      'new_definitions': len(packet['records']['spec_definitions']),
                      'patches': len(packet['patches']), 'production_writes': False}))
