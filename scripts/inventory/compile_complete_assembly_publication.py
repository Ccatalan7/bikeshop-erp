#!/usr/bin/env python3
"""Compile three complete assembly templates with the reviewed metadata publisher."""
import json

from compile_mobility_accessories_publication import compile_packet as compile_reviewed_packet
from compile_non_drivetrain_publication import (
    RESEARCH, ROOT, generate_migration, generate_verifier, write_json)
from compile_complete_assembly_catalog import FAMILIES

VERSION = '20260908030000'
CATALOG_SHA = 'c941116c127382ae1839b95184b7cd5ff6fdf41674aac5eca759d75d68ad5e7b'
CASES_SHA = '86de280e6eeb6b65db013ad6124846e0ab0c215d830415b794fca588891c8bfb'
PREIMAGE_SHA = '645a887795e6952b1b689a85f74efce8b5897a4a550f5d2a98db5a9d891f8e21'


def compile_packet():
    return compile_reviewed_packet(
        catalog_path=RESEARCH / 'complete-assembly-catalog-2026-09-07.json',
        cases_path=RESEARCH / 'complete-assembly-cases-2026-09-07.json',
        preimage_path=RESEARCH / 'complete-assembly-publication-preimage-2026-09-07.json',
        catalog_sha=CATALOG_SHA, cases_sha=CASES_SHA, preimage_sha=PREIMAGE_SHA,
        families=FAMILIES, adjudication={
            'CA-root': 'variant_scoped_configuration_components_interfaces_and_wheel_members',
            'CA-source': 'Sheldon_sizing_Park_BB_Surly_CrossCheck_Preamble',
            'CA-scope': 'no_assignment_or_fill_no_dimension_implies_compatibility',
        })


if __name__ == '__main__':
    packet, _, cases = compile_packet()
    write_json(RESEARCH / 'complete-assembly-publication-packet-2026-09-07.json', packet)
    target = ROOT / f'supabase/migrations/{VERSION}_complete_assembly_spec_templates.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    verification = ROOT / 'supabase/manual_checks/verification' / target.name
    verification.write_text(generate_verifier(packet, cases))
    print(json.dumps({'families': len(packet['families']),
                      'new_records': {k: len(v) for k, v in packet['records'].items()},
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'product_writes': False}))
