#!/usr/bin/env python3
"""Close declared physical-port cardinality without counting mode observations."""
from copy import deepcopy
import json

from compile_product_spec_catalog import RESEARCH, validate_contract
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha

BASE = 'all-family-cardinality-integrated-2026-09-07.json'
CASES = 'all-family-cardinality-cases-integrated-2026-09-07.json'
BASE_SHA = '934ce172a6f3eaf8fa8dc616a912d161c965840b97b647fbee23870ccc154562'
CASES_SHA = 'bede596b90cabbe070faf3d1df9505be50b2adf682334fa8e37287e24af6bae6'
REVIEW_SHA = 'aeef526190b16d7a9acd7b0c46de6aa81e82a4a9b2a9a733505cc63ada9e4862'


def compile_port_cardinality():
    base = json.loads((RESEARCH / BASE).read_text())
    cases = json.loads((RESEARCH / CASES).read_text())
    if artifact_sha(base) != BASE_SHA or artifact_sha(cases) != CASES_SHA:
        raise ValueError('Frozen cardinality stage changed')
    template = next(t for t in base['templates'] if t['key'] == 'consumer_electronics')
    before = template['form_contract']['row_coherence']
    if before['version'] != 1:
        raise ValueError('Unexpected port coherence preimage')
    proposal = {
        'schema_version': 1, 'new_definitions': {},
        'source_review_sha256': REVIEW_SHA,
        'required_server_migration': '20260907025000',
        'mechanical_coverage_complete': False, 'automatic_fill_authorized': False,
        'patches': [
            {'id': 'PORT-01', 'op': 'replace_unpublished_numeric_rules',
             'template': None, 'key': 'ports_count',
             'before': deepcopy(base['definitions']['ports_count']['validation_rules']),
             'after': {'positive': True, 'integer': True, 'min': '1'}},
            {'id': 'PORT-02', 'op': 'replace_template_coherence',
             'template': 'consumer_electronics', 'key': 'row_coherence',
             'before': {'present': True, 'value': deepcopy(before)},
             'after': {'version': 2, 'links': deepcopy(before['links']),
                       'cardinalities': [{'id': 'physical_port_occurrences',
                                         'field': 'power_port_configurations',
                                         'total_field': 'ports_count'}]}}
        ]}
    decisions = {
        'approval_scope': 'field_representation', 'base_sha256': BASE_SHA,
        'proposal_sha256': artifact_sha(proposal), 'source_cases_sha256': CASES_SHA,
        'patch_adjudications': [
            {'patch_id': 'PORT-01', 'decision': 'aceptar',
             'reason': 'Explicit minimum 1 preserves the existing positive-integer domain.'},
            {'patch_id': 'PORT-02', 'decision': 'aceptar',
             'reason': 'Each port row is one physical port; unique port_id already prevents duplicate named ports. Profiles and input/output directions are not extra ports.'}],
        'rejected_transfer': {
            'template': 'light', 'field': 'light_mode_configurations',
            'reason': 'Rows preserve member, source, operating conditions and method. They are observations, not guaranteed distinct modes. A set also contains separate lights. Do not compare their row count with a global modes_count.'},
        'mechanical_coverage_complete': False, 'automatic_fill_authorized': False}
    catalog = apply_reviewed_field_addendum(base, proposal, decisions, validate_contract)
    port_field = 'power_port_configurations'

    def ports(count):
        return {'schema_version': 1, 'rows': [
            {'id': f'port-{i}', 'values': {'port_id': f'Puerto {i}',
                'connector': 'USB-C', 'direction': 'Entrada / salida'}, 'sources': []}
            for i in range(count)]}

    def add(suffix, total, count, code=None, field=port_field, blocking=False):
        values = {'device_kind': 'Cargador', port_field: ports(count)}
        if total is not None:
            values['ports_count'] = total
        fixture = {'id': 'PORT-' + suffix, 'template': 'consumer_electronics',
                   'values': values, 'expected_blocking': [],
                   'facts_verified_for_product': False, 'automatic_fill_authorized': False}
        if code:
            if blocking:
                fixture['expected_blocking'] = [{'code': code, 'field': field}]
                if field == 'ports_count':
                    fixture['expected_sql_blocking'] = [{'code': 'field_constraint', 'field': field}]
            else:
                fixture['expected_issue_subset'] = [{'code': code, 'field': field, 'blocking': False}]
        else:
            fixture['forbidden_issue_fields'] = [port_field]
        cases['cases'].append(fixture)
        return fixture

    add('complete', '3', 3)
    add('fewer_ports_pending', '3', 2, 'row_cardinality_pending')
    add('extra_port_conflict', '1', 2, 'row_cardinality_conflict', blocking=True)
    add('unknown_total_pending', None, 2, 'row_cardinality_pending')
    add('bidirectional_port_is_one', '1', 1)
    zero = add('zero_keeps_existing_domain', '0', 0, 'range', 'ports_count', True)
    # Empty row documents are independently malformed; absence isolates the
    # unchanged positive-integer domain instead of exercising two faults.
    del zero['values'][port_field]
    add('fraction_is_not_a_count', '1.5', 1, 'integer', 'ports_count', True)
    missing_label = add('unknown_label_still_counts_occurrence', '1', 2,
                        'row_cardinality_conflict', blocking=True)
    del missing_label['values'][port_field]['rows'][1]['values']['port_id']
    duplicate = add('duplicate_named_port_rejected', '2', 2, 'row_shape', blocking=True)
    duplicate['values'][port_field]['rows'][1]['values']['port_id'] = 'Puerto 0'
    cable = add('cable_has_no_port_count_requirement', None, 0)
    cable['values'] = {'device_kind': 'Cable de datos/carga'}
    cases.update(title='All-family physical-port cardinality',
                 catalogue_sha256=artifact_sha(catalog), required_server_migration='20260907025000')
    return catalog, cases, proposal, decisions


if __name__ == '__main__':
    catalog, cases, proposal, decisions = compile_port_cardinality()
    for name, value in [
            ('all-family-port-cardinality-integrated-2026-09-07.json', catalog),
            ('all-family-port-cardinality-cases-integrated-2026-09-07.json', cases),
            ('port-cardinality-root-proposal-2026-09-07.json', proposal),
            ('port-cardinality-root-decisions-2026-09-07.json', decisions)]:
        (RESEARCH / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'catalogue_sha256': artifact_sha(catalog), 'cases_sha256': artifact_sha(cases),
                      'cases': len(cases['cases']), 'stats': catalog['stats']}))
