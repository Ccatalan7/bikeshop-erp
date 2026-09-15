#!/usr/bin/env python3
"""Compile nine new wheel/repair templates with the reviewed metadata publisher."""
import json

from compile_mobility_accessories_publication import compile_packet as compile_reviewed_packet
from compile_non_drivetrain_publication import (
    RESEARCH, ROOT, generate_migration, generate_verifier, write_json)
from compile_wheel_small_parts_catalog import FAMILIES

VERSION = '20260908001000'
CATALOG_SHA = '1f38ce44b48c9d58154a5342ddc014642af15f3401718e467643b6bb0608b501'
CASES_SHA = '5463a15b9385df3c2db8815b3fb1337fe4995961afec695edbf763fe5fe23852'
PREIMAGE_SHA = '8f0d8c6ed1a1f296d2623a579c75f3afbfd1822a84ace80d99f5786bd8c49837'


def compile_packet():
    return compile_reviewed_packet(
        catalog_path=RESEARCH / 'wheel-small-parts-catalog-2026-09-07.json',
        cases_path=RESEARCH / 'wheel-small-parts-cases-2026-09-07.json',
        preimage_path=RESEARCH / 'wheel-small-parts-publication-preimage-2026-09-07.json',
        catalog_sha=CATALOG_SHA, cases_sha=CASES_SHA, preimage_sha=PREIMAGE_SHA,
        families=FAMILIES, adjudication={
            'WS-1': 'new_valve_row_interface_uses_missing_state_other_families_still_pending',
            'WS-2': 'separate_interface_geometry_from_axle_construction',
            'WS-3': 'preserve_partial_thread_designation_without_inventing_pitch',
            'WS-4': 'replace_unscoped_diameter_list_with_scoped_liner_rows',
            'WS-5': 'retain_distinct_nipple_gauge_and_thread_meanings',
            'WS-6': 'nipple_tool_geometry_and_measurement_datum',
            'WS-7': 'repair_surface_material_and_OEM_scope',
            'WS-8': 'paired_liner_size_width_form_and_unit_no_conversion',
            'WS-9': 'retention_component_configuration_and_thread_link',
            'WS-10': 'plain_or_threaded_interfaces_not_inferred_from_part_kind',
            'WS-11': 'plug_model_and_target_tool_declarations',
            'WS-12': 'valve_direction_and_core_relocation_prerequisite',
        })


if __name__ == '__main__':
    packet, _, cases = compile_packet()
    write_json(RESEARCH / 'wheel-small-parts-publication-packet-2026-09-07.json', packet)
    target = ROOT / f'supabase/migrations/{VERSION}_wheel_small_part_spec_templates.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    verification = ROOT / 'supabase/manual_checks/verification' / target.name
    verification.write_text(generate_verifier(packet, cases))
    print(json.dumps({'families': len(packet['families']),
                      'new_records': {k: len(v) for k, v in packet['records'].items()},
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'product_writes': False}))
