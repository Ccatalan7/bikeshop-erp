#!/usr/bin/env python3
"""Prepare, never execute, the reviewed forward update of five original specs."""
import json
from compile_existing_spec_publication import compile_packet as reviewed_packet, load_pinned, generate_migration, generate_verifier
from compile_existing_bearing_bb_catalog import FAMILIES
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

VERSION = '20260908034000'
CATALOG_SHA = '62bd5a7e860000bbc3e36ce2b2a10e9640052b8e501ffca8b6690640a29bc2b6'
CASES_SHA = '5f61afff3507aaca14679858a7904fe9a97c2eed16267d997d108c826b65c4ff'
PREIMAGE_SHA = '385f6924ded3e54254bd4f974792c444f651d0b92e89527648b77a5b2b3868f8'


def compile_packet():
    catalog = load_pinned(RESEARCH / 'existing-bearing-bb-catalog-2026-09-07.json', CATALOG_SHA)
    cases = load_pinned(RESEARCH / 'existing-bearing-bb-cases-2026-09-07.json', CASES_SHA)
    before = load_pinned(RESEARCH / 'existing-bearing-bb-publication-preimage-2026-09-07.json', PREIMAGE_SHA)
    packet = reviewed_packet(catalog=catalog, cases=cases, before=before,
        families=FAMILIES, hashes={'catalog_sha256': CATALOG_SHA,
            'cases_sha256': CASES_SHA, 'preimage_sha256': PREIMAGE_SHA},
        adjudication={
            'bearing_support': 'OEM bearing chamfers remain separate from internal rolling angle; frozen guarantees restored',
            'bb_assembly': 'physical bearing members, ports, model or standard claims and installation widths retain their owners',
            'sources': 'Sheldon, Park, Enduro, NSK and Wheels Mfg; exact limits in root decisions',
            'activation_gate': 'candidate only; final delta review, fresh audit, runtime and client distribution remain open',
        })
    return packet, catalog, cases


if __name__ == '__main__':
    packet, _, cases = compile_packet()
    write_json(RESEARCH / 'existing-bearing-bb-publication-packet-2026-09-07.json', packet)
    # Keep a candidate with open activation gates out of deployable migrations.
    target = ROOT / '.tmp/db/existing-bearing-bb-forward-candidate.sql'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    verification = ROOT / '.tmp/db/existing-bearing-bb-forward-verification.sql'
    verification.write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': len(packet['families']), 'cases': len(cases['cases']),
        'new_definitions': len(packet['records']['spec_definitions']),
        'field_uses': len(packet['records']['spec_template_fields']),
        'patches': len(packet['patches']), 'production_writes': False}))
