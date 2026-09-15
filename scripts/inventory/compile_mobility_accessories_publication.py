#!/usr/bin/env python3
"""Compile an exact new-metadata publication from the reviewed successor.

No SQL is executed. Shared records are checked in full and never updated.
Product facts, identity, assignments and category defaults remain outside scope.
"""
import hashlib
import json

from compile_non_drivetrain_publication import (
    RESEARCH, ROOT, TENANT, metadata_records, generate_migration,
    generate_verifier, write_json)
from compile_mobility_accessories_catalog import FAMILIES
from compile_product_spec_catalog import validate_contract

VERSION = '20260907233000'
CATALOG = RESEARCH / 'mobility-accessories-catalog-2026-09-07.json'
CASES = RESEARCH / 'mobility-accessories-cases-2026-09-07.json'
PREIMAGE = RESEARCH / 'mobility-accessories-publication-preimage-2026-09-07.json'
CATALOG_SHA = 'cd477af08f8c39225d8abef182f3ce326145b0be7d1cfe043d579132838e8a44'
CASES_SHA = '1ca9ec14aa994014d89ae30a85b86beaa22c5471359197b3ef41288d4e933559'
PREIMAGE_SHA = '2c1bc85e8174aaee2a3b510a2ef04ca7ca96529d81d772c821bf4785c6e99945'


def compile_packet(*, catalog_path=CATALOG, cases_path=CASES, preimage_path=PREIMAGE,
                   catalog_sha=CATALOG_SHA, cases_sha=CASES_SHA,
                   preimage_sha=PREIMAGE_SHA, families=FAMILIES, adjudication=None):
    for path, expected in ((catalog_path, catalog_sha), (cases_path, cases_sha),
                            (preimage_path, preimage_sha)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Reviewed input changed: ' + str(path))
    catalog = json.loads(catalog_path.read_text())
    cases = json.loads(cases_path.read_text())
    before = json.loads(preimage_path.read_text())[0]['metadata']
    templates, definitions = catalog['templates'], catalog['definitions']
    if (before['tenant_id'] != TENANT or before['template_collisions'] or
            len(templates) != len(families) or
            {t['key'] for t in templates} != set(families) or
            any(t['origin'] != 'new' for t in templates)):
        raise ValueError('Only the explicitly selected new templates are authorized')
    reused = {d['key']: d for d in before['existing_definitions']}
    if (len(reused) != len(before['existing_definitions']) or
            not set(reused) <= set(definitions) or
            not {k for k, d in definitions.items() if d['origin'] == 'existing'}
            <= set(reused)):
        raise ValueError('Missing or ambiguous shared preimage')
    for key, actual in reused.items():
        if actual['tenant_id'] is not None or any(
                actual[c] != definitions[key][c] for c in
                ('id', 'key', 'label', 'data_type', 'unit', 'allowed_values',
                 'validation_rules')):
            raise ValueError('Shared definition must remain unchanged: ' + key)
        if any(v['tenant_id'] is not None or not v['is_active']
               for v in actual['options']):
            raise ValueError('Shared option cannot support immutable OEM references')
    if cases['catalogue_sha256'] != catalog_sha or any(
            c['template'] not in families for c in cases['cases']):
        raise ValueError('Cases do not belong to this reviewed catalogue')
    for t in templates:
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    return {
        'schema_version': 1, 'scope': 'new_global_metadata_only',
        'audited_tenant_id': TENANT, 'catalog_sha256': catalog_sha,
        'cases_sha256': cases_sha, 'preimage_sha256': preimage_sha,
        'families': list(families), 'reused_definitions': list(reused.values()),
        'records': metadata_records(templates, definitions, set(reused)),
        'product_writes': False, 'fill_allowed': False, 'mechanical_approval': False,
        'adjudication': adjudication if adjudication is not None else {
            'MA-1': 'typed_wheel_declarations_without_inferred_conversion',
            'MA-2': 'scalar_consumer_and_editor_share_eligibility',
            'MA-3': 'tool_pressure_scope_and_printed_units',
            'MA-4': 'separate_volume_basis_and_package_scope',
            'DL-1': 'additional_co2_capability_separate_from_pump_format',
            'DL-2': 'waist_pack_and_included_reservoir_separate',
            'DL-5': 'legacy_pressure_is_unreachable_not_canonical',
        },
    }, catalog, cases


if __name__ == '__main__':
    packet, _, cases = compile_packet()
    write_json(RESEARCH / 'mobility-accessories-publication-packet-2026-09-07.json', packet)
    target = ROOT / f'supabase/migrations/{VERSION}_mobility_accessory_spec_templates.sql'
    target.write_text(generate_migration(packet, source_sha=CATALOG_SHA))
    verification = ROOT / 'supabase/manual_checks/verification' / target.name
    verification.write_text(generate_verifier(packet, cases))
    print(json.dumps({'families': len(packet['families']),
                      'new_records': {k: len(v) for k, v in packet['records'].items()},
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'product_writes': False}))
