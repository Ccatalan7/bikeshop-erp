#!/usr/bin/env python3
"""Compile four drivetrain small-part templates with the reviewed metadata publisher."""
import json

from compile_mobility_accessories_publication import compile_packet as compile_reviewed_packet
from compile_non_drivetrain_publication import (
    RESEARCH, ROOT, generate_migration, generate_verifier, write_json)
from compile_drivetrain_small_parts_catalog import FAMILIES

VERSION = '20260908013000'
CATALOG_SHA = 'e847f24f1a6cac14a34d90f2cf54a713df621dced5bb2f9a9eda7cc07a10b25d'
CASES_SHA = '3b9a86eb94fdb6fd5818162936998e9896928d2e25ff94a4217db7c0fac28f12'
PREIMAGE_SHA = '0b94c71cd171fbbbaac8936ad1b0319c9e9163142e80217a70ebc3c8d2a556d0'


def compile_packet():
    return compile_reviewed_packet(
        catalog_path=RESEARCH / 'drivetrain-small-parts-catalog-2026-09-07.json',
        cases_path=RESEARCH / 'drivetrain-small-parts-cases-2026-09-07.json',
        preimage_path=RESEARCH / 'drivetrain-small-parts-publication-preimage-reviewed-2026-09-07.json',
        catalog_sha=CATALOG_SHA, cases_sha=CASES_SHA, preimage_sha=PREIMAGE_SHA,
        families=FAMILIES, adjudication={
            'DS-root': 'kit_pitch_value_unit_scoped_cassette_pairs_guard_mount_links_lockring_owner',
            'DS-source': 'Park_threads_Sheldon_lockrings_Wolf_RoadLink_DM_OneUp_V2',
            'DS-scope': 'no_assignment_or_fill_no_dimension_implies_compatibility',
        })


if __name__ == '__main__':
    packet, _, cases = compile_packet()
    write_json(RESEARCH / 'drivetrain-small-parts-publication-packet-2026-09-07.json', packet)
    target = ROOT / f'supabase/migrations/{VERSION}_drivetrain_small_part_spec_templates.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    verification = ROOT / 'supabase/manual_checks/verification' / target.name
    verification.write_text(generate_verifier(packet, cases))
    print(json.dumps({'families': len(packet['families']),
                      'new_records': {k: len(v) for k, v in packet['records'].items()},
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'product_writes': False}))
