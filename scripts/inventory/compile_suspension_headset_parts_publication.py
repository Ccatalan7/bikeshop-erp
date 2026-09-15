#!/usr/bin/env python3
"""Compile four suspension/headset templates with the reviewed metadata publisher."""
import json

from compile_mobility_accessories_publication import compile_packet as compile_reviewed_packet
from compile_non_drivetrain_publication import (
    RESEARCH, ROOT, generate_migration, generate_verifier, write_json)
from compile_suspension_headset_parts_catalog import FAMILIES

VERSION = '20260908011000'
CATALOG_SHA = 'ae236f569f5dee24a23f5bce6adbd546de56f3ef29bcc2d25cd20271d9c1d4b0'
CASES_SHA = '7402081a03eaef225123e75cdd23a560ac81fceef41681b8ca086c0ccd3993d7'
PREIMAGE_SHA = 'f38dd94f2d538af6a0d2f9574e04d56f7a9d433d8703e6f1379c2599d116595a'


def compile_packet():
    return compile_reviewed_packet(
        catalog_path=RESEARCH / 'suspension-headset-parts-catalog-2026-09-07.json',
        cases_path=RESEARCH / 'suspension-headset-parts-cases-2026-09-07.json',
        preimage_path=RESEARCH / 'suspension-headset-parts-publication-preimage-2026-09-07.json',
        catalog_sha=CATALOG_SHA, cases_sha=CASES_SHA, preimage_sha=PREIMAGE_SHA,
        families=FAMILIES, adjudication={
            'SH-root': 'paired_shock_size_end_links_exact_range_literal_headset_spacer_members',
            'SH-source': 'FOX_972_01_490_Wolf_CPLUG_STEM5MM_BLK_SPACER_BLK_KIT1',
            'SH-scope': 'no_assignment_or_fill_no_dimension_implies_compatibility',
        })


if __name__ == '__main__':
    packet, _, cases = compile_packet()
    write_json(RESEARCH / 'suspension-headset-parts-publication-packet-2026-09-07.json', packet)
    target = ROOT / f'supabase/migrations/{VERSION}_suspension_headset_part_spec_templates.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    verification = ROOT / 'supabase/manual_checks/verification' / target.name
    verification.write_text(generate_verifier(packet, cases))
    print(json.dumps({'families': len(packet['families']),
                      'new_records': {k: len(v) for k, v in packet['records'].items()},
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'product_writes': False}))
