#!/usr/bin/env python3
"""Compile three hydraulic templates with the reviewed metadata publisher."""
import json

from compile_mobility_accessories_publication import compile_packet as compile_reviewed_packet
from compile_non_drivetrain_publication import (
    RESEARCH, ROOT, generate_migration, generate_verifier, write_json)
from compile_hydraulic_parts_catalog import FAMILIES

VERSION = '20260908024000'
CATALOG_SHA = 'db035cb385f7d39a1f815c8331195c0939b251b846753fab7a6cb1b33e16a6d6'
CASES_SHA = '1e49f0a889a59cbfc119c3e6654c1e7e6b8abbb32731bc2a469aff4892c4a9e1'
PREIMAGE_SHA = '1670b9ef688a8c90879c1241e9390101ee632d3ab466b384a213ac8a8e080a3f'


def compile_packet():
    return compile_reviewed_packet(
        catalog_path=RESEARCH / 'hydraulic-parts-catalog-2026-09-07.json',
        cases_path=RESEARCH / 'hydraulic-parts-cases-2026-09-07.json',
        preimage_path=RESEARCH / 'hydraulic-parts-publication-preimage-2026-09-07.json',
        catalog_sha=CATALOG_SHA, cases_sha=CASES_SHA, preimage_sha=PREIMAGE_SHA,
        families=FAMILIES, adjudication={
            'HY-root': 'physical_members_ends_formulation_identity_and_source_scoped_claims',
            'HY-source': 'Park_bleed_tools_Jagwire_2021_SRAM_DOT_FMVSS116_ISO_historical',
            'HY-scope': 'no_assignment_or_fill_no_dimension_implies_compatibility',
        })


if __name__ == '__main__':
    packet, _, cases = compile_packet()
    write_json(RESEARCH / 'hydraulic-parts-publication-packet-2026-09-07.json', packet)
    target = ROOT / f'supabase/migrations/{VERSION}_hydraulic_part_spec_templates.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    verification = ROOT / 'supabase/manual_checks/verification' / target.name
    verification.write_text(generate_verifier(packet, cases))
    print(json.dumps({'families': len(packet['families']),
                      'new_records': {k: len(v) for k, v in packet['records'].items()},
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'product_writes': False}))
