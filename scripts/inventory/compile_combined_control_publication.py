#!/usr/bin/env python3
"""Compile the combined control template with the reviewed metadata publisher."""
import json

from compile_mobility_accessories_publication import compile_packet as compile_reviewed_packet
from compile_non_drivetrain_publication import (
    RESEARCH, ROOT, generate_migration, generate_verifier, write_json)
from compile_combined_control_catalog import FAMILY

FAMILIES = (FAMILY,)

VERSION = '20260908032000'
CATALOG_SHA = '733781370463914b23c107a65d005109189ed9f1496b91053a1b628842fb5a44'
CASES_SHA = '26b26bcf71e211175822fa08ae45ddaeaaa0b86765288e311468cf1a88488772'
PREIMAGE_SHA = 'fd4f5321739283a149ed5d01a118e0f51ce0fad78b3702fc85487a4338048e28'


def compile_packet():
    return compile_reviewed_packet(
        catalog_path=RESEARCH / 'combined-control-catalog-2026-09-07.json',
        cases_path=RESEARCH / 'combined-control-cases-2026-09-07.json',
        preimage_path=RESEARCH / 'combined-control-publication-preimage-2026-09-07.json',
        catalog_sha=CATALOG_SHA, cases_sha=CASES_SHA, preimage_sha=PREIMAGE_SHA,
        families=FAMILIES, adjudication={
            'CC-root': 'physical_occurrences_with_owned_brake_and_shift_configurations',
            'CC-source': 'Sheldon_Park_SRAM_exact_electronic_modes',
            'CC-scope': 'no_assignment_or_fill_no_dimension_implies_compatibility',
        })


if __name__ == '__main__':
    packet, _, cases = compile_packet()
    write_json(RESEARCH / 'combined-control-publication-packet-2026-09-07.json', packet)
    target = ROOT / f'supabase/migrations/{VERSION}_combined_control_spec_templates.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    verification = ROOT / 'supabase/manual_checks/verification' / target.name
    verification.write_text(generate_verifier(packet, cases))
    print(json.dumps({'families': len(packet['families']),
                      'new_records': {k: len(v) for k, v in packet['records'].items()},
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'product_writes': False}))
