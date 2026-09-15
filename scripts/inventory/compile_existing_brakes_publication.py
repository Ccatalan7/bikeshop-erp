#!/usr/bin/env python3
"""Prepare the seven original brake templates; never execute a publication."""
import json

from compile_existing_brakes_catalog import FAMILIES
from compile_existing_spec_publication import (
    compile_packet as reviewed_packet, generate_migration, generate_verifier,
    load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

CATALOG_SHA = 'a3c9c6c17151a3433ff8792718e827f6376ebda64b04ce760f56754179171ee4'
CASES_SHA = '391091f349b05ab2ff9cade412ddd9c6caead047b776aced722a0baef5449d7e'
PREIMAGE_SHA = 'f92157c1e80df72711eb0c9e971e913407cd28b127ae452905961c621abdf52a'


def compile_packet():
    catalog = load_pinned(RESEARCH / 'existing-brakes-catalog-2026-09-07.json', CATALOG_SHA)
    cases = load_pinned(RESEARCH / 'existing-brakes-cases-2026-09-07.json', CASES_SHA)
    before = load_pinned(RESEARCH / 'existing-brakes-publication-preimage-2026-09-08.json', PREIMAGE_SHA)
    packet = reviewed_packet(
        catalog=catalog, cases=cases, before=before, families=FAMILIES,
        hashes={'catalog_sha256': CATALOG_SHA, 'cases_sha256': CASES_SHA,
                'preimage_sha256': PREIMAGE_SHA},
        adjudication={
            'members': 'inclusion, dimensions and model properties belong to each physical circuit position',
            'fluid': 'new model and edition scope; live shared definition remains byte-for-byte unchanged',
            'legacy': 'used rotor inspection and unowned tool text are not active rotor properties',
            'sources': 'Sheldon, Park, TRP, SRAM, MAGURA; exact scope in root decisions',
            'activation_gate': 'candidate only; remaining domain branches, independent delta review, product audit and client distribution open',
        })
    return packet, catalog, cases


if __name__ == '__main__':
    packet, _, cases = compile_packet()
    write_json(RESEARCH / 'existing-brakes-publication-packet-2026-09-08.json', packet)
    target = ROOT / '.tmp/db/existing-brakes-forward-candidate.sql'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    (target.parent / 'existing-brakes-forward-verification.sql').write_text(
        generate_verifier(packet, cases))
    print(json.dumps({'templates': len(packet['families']), 'cases': len(cases['cases']),
                      'new_definitions': len(packet['records']['spec_definitions']),
                      'field_uses': len(packet['records']['spec_template_fields']),
                      'patches': len(packet['patches']), 'production_writes': False}))
