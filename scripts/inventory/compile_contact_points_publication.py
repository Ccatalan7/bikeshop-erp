#!/usr/bin/env python3
"""Compile ten new contact-point templates using the guarded metadata publisher."""
import json

from compile_mobility_accessories_publication import compile_packet as compile_reviewed_packet
from compile_non_drivetrain_publication import (
    RESEARCH, ROOT, generate_migration, generate_verifier, write_json)
from compile_contact_points_catalog import FAMILIES

VERSION = '20260907235000'
CATALOG_SHA = '1a10d6e52e4b50ae2da80dc2590cd0c510a639884edb8e46d0c7c81b1c0dc40a'
CASES_SHA = '6695414854f1f025653d99d3d2a9ba35cd4a3ab1b01578f4f64a5b3af0e0d1dc'
PREIMAGE_SHA = '5e12173a2fb34f0aa2ed69c2bcfb74f8a9fb368ad352022a94b9c142ac40ccae'


def compile_packet():
    return compile_reviewed_packet(
        catalog_path=RESEARCH / 'contact-points-catalog-2026-09-07.json',
        cases_path=RESEARCH / 'contact-points-cases-2026-09-07.json',
        preimage_path=RESEARCH / 'contact-points-publication-preimage-2026-09-07.json',
        catalog_sha=CATALOG_SHA, cases_sha=CASES_SHA, preimage_sha=PREIMAGE_SHA,
        families=FAMILIES, adjudication={
            'CP-1': 'distinct_axes_already_existed_add_measurement_context_no_equality_rule',
            'CP-2': 'legacy_condition_cleanup_not_a_mechanical_fix',
            'CP-3': 'preserve_independent_interface_definitions',
            'CP-4': 'reuse_live_shared_preimages_without_mutation',
            'ROOT-TORQUE': 'preserve_OEM_torque_range_units_and_configuration',
        })


if __name__ == '__main__':
    packet, _, cases = compile_packet()
    write_json(RESEARCH / 'contact-points-publication-packet-2026-09-07.json', packet)
    target = ROOT / f'supabase/migrations/{VERSION}_contact_point_spec_templates.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    verification = ROOT / 'supabase/manual_checks/verification' / target.name
    verification.write_text(generate_verifier(packet, cases))
    print(json.dumps({'families': len(packet['families']),
                      'new_records': {k: len(v) for k, v in packet['records'].items()},
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'product_writes': False}))
