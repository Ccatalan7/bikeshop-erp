#!/usr/bin/env python3
"""Compile four control cable templates with the reviewed metadata publisher."""
import json

from compile_mobility_accessories_publication import compile_packet as compile_reviewed_packet
from compile_non_drivetrain_publication import (
    RESEARCH, ROOT, generate_migration, generate_verifier, write_json)
from compile_control_cable_parts_catalog import FAMILIES

VERSION = '20260908022000'
CATALOG_SHA = '15a2f1d0aa97e6413cf79419f45a711e1c2cb4234dcd38ab87893bf6c83ba412'
CASES_SHA = '7f2aebcfd66e5c54d8abd39fd997b913f75e8f215f5a79b9409e08c9c9ccedce'
PREIMAGE_SHA = '0ef47fd09b3b61e01f7a873c706a7fc481365b375a5f5b9584bbd3cc4a274cf4'


def compile_packet():
    return compile_reviewed_packet(
        catalog_path=RESEARCH / 'control-cable-parts-catalog-2026-09-07.json',
        cases_path=RESEARCH / 'control-cable-parts-cases-2026-09-07.json',
        preimage_path=RESEARCH / 'control-cable-parts-publication-preimage-2026-09-07.json',
        catalog_sha=CATALOG_SHA, cases_sha=CASES_SHA, preimage_sha=PREIMAGE_SHA,
        families=FAMILIES, adjudication={
            'CC-root': 'per_run_geometry_end_links_scoped_housing_brake_construction',
            'CC-source': 'Sheldon_cables_Park_threads_Jagwire_KEB_UCK800_EliteLink_Odyssey_M2',
            'CC-scope': 'no_assignment_or_fill_no_dimension_implies_compatibility',
        })


if __name__ == '__main__':
    packet, _, cases = compile_packet()
    write_json(RESEARCH / 'control-cable-parts-publication-packet-2026-09-07.json', packet)
    target = ROOT / f'supabase/migrations/{VERSION}_control_cable_part_spec_templates.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    verification = ROOT / 'supabase/manual_checks/verification' / target.name
    verification.write_text(generate_verifier(packet, cases))
    print(json.dumps({'families': len(packet['families']),
                      'new_records': {k: len(v) for k, v in packet['records'].items()},
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'product_writes': False}))
