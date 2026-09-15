#!/usr/bin/env python3
"""Compile four brake adapter templates with the reviewed metadata publisher."""
import json

from compile_mobility_accessories_publication import compile_packet as compile_reviewed_packet
from compile_non_drivetrain_publication import (
    RESEARCH, ROOT, generate_migration, generate_verifier, write_json)
from compile_brake_adapter_parts_catalog import FAMILIES

VERSION = '20260908025000'
CATALOG_SHA = 'a5e3add682ae2ee881daaa158b55478d3762341de2f7fb35ddf05525a928897a'
CASES_SHA = '44afed36113d8e87c755fdf438be1b96119f6a5d25e3f7fbd523466fce608135'
PREIMAGE_SHA = '1732859b6960a51dee0ee5b7de7eec5c91aad57dc10f83515f63d491b7aefceb'


def compile_packet():
    return compile_reviewed_packet(
        catalog_path=RESEARCH / 'brake-adapter-parts-catalog-2026-09-07.json',
        cases_path=RESEARCH / 'brake-adapter-parts-cases-2026-09-07.json',
        preimage_path=RESEARCH / 'brake-adapter-parts-publication-preimage-2026-09-07.json',
        catalog_sha=CATALOG_SHA, cases_sha=CASES_SHA, preimage_sha=PREIMAGE_SHA,
        families=FAMILIES, adjudication={
            'BA-root': 'configuration_identity_thread_owners_scoped_parts_and_hub_interfaces',
            'BA-source': 'Sheldon_coaster_Park_mounts_Shimano_MDBR001_05_Wolf_Boostinator',
            'BA-scope': 'no_assignment_or_fill_no_dimension_implies_compatibility',
        })


if __name__ == '__main__':
    packet, _, cases = compile_packet()
    write_json(RESEARCH / 'brake-adapter-parts-publication-packet-2026-09-07.json', packet)
    target = ROOT / f'supabase/migrations/{VERSION}_brake_adapter_part_spec_templates.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    verification = ROOT / 'supabase/manual_checks/verification' / target.name
    verification.write_text(generate_verifier(packet, cases))
    print(json.dumps({'families': len(packet['families']),
                      'new_records': {k: len(v) for k, v in packet['records'].items()},
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'product_writes': False}))
