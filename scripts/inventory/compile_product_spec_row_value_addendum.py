#!/usr/bin/env python3
"""Integrate two reviewed same-row implications; keep all fill gates closed."""
from copy import deepcopy
import json

from compile_product_spec_catalog import RESEARCH, validate_contract
from compile_product_spec_remaining_nd_addendum import compile_remaining_nd
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha

BASE_SHA = 'f1826a9a782a200754b21ba6c5420af0f9c39b89482503cab77f96779fc739b1'
CASES_SHA = '14b6905563349eda7581cf651819f3b07e9c8de72de313c7250c1424de46f4ac'


def condition(field, value):
    return {'kind': 'when', 'rows': [[{
        'field': field, 'operator': 'eq', 'value_type': 'token', 'value': value}]]}


def compile_row_values():
    base, cases = compile_remaining_nd()
    if artifact_sha(base) != BASE_SHA or artifact_sha(cases) != CASES_SHA:
        raise ValueError('Frozen remaining ND catalogue or fixture preimage changed')
    patches = []
    templates = {t['key']: t for t in base['templates']}
    targets = [
        ('seatpost', 'seatpost_saddle_configurations', 'configuration_state',
         'Con kit incluido', 'Con kit opcional', 'clamp_included'),
        ('accessory_mount', 'bar_clamp_configurations', 'fit_method',
         'Con espaciador incluido', 'Con espaciador opcional', 'included'),
    ]
    for template, field, selector, included, optional, target in targets:
        before = templates[template]['form_contract']['row_conditions']
        after = deepcopy(before)
        if 'value_when' in after['fields'][field]:
            raise ValueError('Value rules already exist in the frozen preimage')
        after['fields'][field]['value_when'] = {target: [{
            'when': condition(selector, included),
            'expected': {'value_type': 'boolean', 'value': True}}]}
        patches.append({'id': 'RV-' + template, 'op': 'replace_template_coherence',
            'template': template, 'key': 'row_conditions',
            'before': {'present': True, 'value': before}, 'after': after})
    proposal = {'patches': patches, 'new_definitions': {}}
    decisions = {'approval_scope': 'field_representation', 'base_sha256': BASE_SHA,
        'source_cases_sha256': CASES_SHA,
        'proposal_sha256': artifact_sha(proposal), 'patch_adjudications': [
            {'patch_id': p['id'], 'decision': 'aceptar',
             'reason': 'Una configuración declarada con pieza incluida exige incluido=true en su misma fila. Opcional no impone false; desconocido queda pendiente, sin autofill.'}
            for p in patches],
        'mechanical_coverage_complete': False, 'automatic_fill_authorized': False}
    # The complete old fixture set is pinned above; these two cases documented
    # the missing implication and now must fail for the precise new reason.
    overrides = []
    for case in cases['cases']:
        if case['id'] in ('RCF08', 'CPC_GAP_INCLUDED_CLAMP_FALSE'):
            if case['expected_blocking'] != []:
                raise ValueError('Included-clamp fixture was already adjudicated')
            case['expected_blocking'] = [{'code': 'row_value_conflict',
                                         'field': 'seatpost_saddle_configurations'}]
            if 'expected_row_condition_issues' in case:
                case['expected_row_condition_issues'] = [{
                    'code': 'row_value_conflict', 'field': 'seatpost_saddle_configurations',
                    'row_id': 'r1', 'column': 'clamp_included', 'blocking': True}]
            case['kind'] = 'closed_engine_gap_regression'
            case['purpose'] = 'Con kit incluido y abrazadera no incluida contradicen la misma configuración; 2400 lo bloquea.'
            case['closed_gap_ids'] = case.pop('gap_ids', [])
            overrides.append(case['id'])
        # The existing scalar validators name an unknown applicability
        # differently. Pin the SQL diagnostic explicitly without changing its
        # blocking status or omitting the assertion in either engine.
        if case['id'] in ('CPC_GRIP_SIDE_NOT_CONFIRMED',
                          'CPC_DROPPER_CONTROL_KIND_UNKNOWN',
                          'CPC_POST_TOTAL_DATUM_PENDING'):
            expected = case['expected_issue_subset']
            if len(expected) != 1 or expected[0]['code'] != 'prerequisite' or expected[0]['blocking']:
                raise ValueError('Unreviewed scalar diagnostic transport drift')
            sql_code = ('prerequisite_missing' if case['id'] == 'CPC_POST_TOTAL_DATUM_PENDING'
                        else 'field_applicability')
            case['expected_sql_issue_subset'] = [dict(expected[0], code=sql_code)]
            case['diagnostic_transport_note'] = 'SQL ' + sql_code + ' y Dart prerequisite: mismo requisito desconocido y no bloqueante.'
        if case['id'] in ('CPC_GRIP_INVALID_SPACE', 'rnd_root_helmet_construction_in_wrong_axis'):
            expected = case['expected_blocking']
            dart_code = 'range' if case['id'] == 'CPC_GRIP_INVALID_SPACE' else 'option'
            if len(expected) != 1 or expected[0]['code'] != dart_code:
                raise ValueError('Unreviewed blocking diagnostic transport drift')
            case['expected_sql_blocking'] = [dict(expected[0], code='field_constraint')]
            case['diagnostic_transport_note'] = 'SQL field_constraint y Dart ' + dart_code + ': mismo valor explícito fuera del dominio, bloqueante.'
    if len(overrides) != 2:
        raise ValueError('Expected both previously documented inclusion gaps')

    added = []
    for template, field, selector, included, optional, target in targets:
        other_cells = ({'rail_geometry': 'Oval 7x9 mm', 'clamp_part': 'Pieza sintética'}
                       if template == 'seatpost' else
                       {'nominal_diameter_mm': '25.4', 'spacer_or_variant': 'Pieza sintética'})
        base_values = {'seatpost_kind': 'Rígida'} if template == 'seatpost' else {}
        for name, selection, observation, outcome in [
            ('included_true', included, True, None),
            ('included_false', included, False, 'row_value_conflict'),
            ('included_unknown', included, None, 'row_value_pending'),
            ('optional_true', optional, True, None),
            ('optional_false', optional, False, None),
            ('optional_unknown', optional, None, None),
            ('selector_unknown', None, False, 'row_value_pending'),
        ]:
            cells = dict(other_cells)
            if selection is not None:
                cells[selector] = selection
            if observation is not None:
                cells[target] = observation
            case = {'id': 'rv_' + template + '_' + name, 'template': template,
                'values': dict(base_values, **{field: {'schema_version': 1, 'rows': [
                    {'id': 'first', 'values': cells, 'sources': []}]}}),
                'kind': 'synthetic_representation', 'expected_blocking': [],
                'facts_verified_for_product': False, 'automatic_fill_authorized': False}
            if outcome:
                case['expected_issue_subset'] = [{'code': outcome, 'field': field,
                                                  'blocking': outcome == 'row_value_conflict'}]
            if outcome == 'row_value_conflict':
                case['expected_blocking'] = [{'code': outcome, 'field': field}]
            added.append(case)
        # A second row cannot supply the missing inclusion value of the first.
        cross_row = deepcopy(added[-5])
        if not cross_row['id'].endswith('included_unknown'):
            raise ValueError('Cross-row test must start from a missing included value')
        cross_row['id'] = 'rv_' + template + '_other_row_does_not_complete'
        cross_row['values'][field]['rows'].append({'id': 'second',
            'values': dict(other_cells, **{selector: optional, target: True}), 'sources': []})
        added.append(cross_row)

    # Legacy values are preserved, but never regain authority over new rows.
    added.extend([
        {'id': 'rv_pump_legacy_scalar_not_canonical', 'template': 'pump',
         'values': {'pump_kind': 'Inflador CO2', 'max_pressure_psi': '160'},
         'forbidden_issue_fields': ['max_pressure_psi'], 'expected_blocking': []},
        {'id': 'rv_pressure_missing_configuration_is_pending', 'template': 'pump',
         'values': {'pump_pressure_specifications': {'schema_version': 1, 'rows': [
             {'id': 'gauge', 'values': {'quantity_kind': 'Fondo de escala del manómetro',
                 'value': '160', 'unit': 'psi'}, 'sources': []}]}},
         'expected_issue_subset': [{'code': 'row_incomplete', 'field': 'pump_pressure_specifications', 'blocking': False}],
         'expected_blocking': []},
        {'id': 'rv_bottle_missing_datum_is_pending', 'template': 'bottle',
         'values': {'bottle_body_dimensions': {'schema_version': 1, 'rows': [
             {'id': 'body', 'values': {'dimension': 'Ancho', 'value_mm': '76',
                 'configuration': 'Botella con base incluida'}, 'sources': []}]}},
         'expected_issue_subset': [{'code': 'row_incomplete', 'field': 'bottle_body_dimensions', 'blocking': False}],
         'expected_blocking': []},
    ])
    for case in added:
        case.update(facts_verified_for_product=False, automatic_fill_authorized=False)
    decisions['cases_sha256'] = artifact_sha(added)
    catalogue = apply_reviewed_field_addendum(base, proposal, decisions, validate_contract)
    cases['cases'].extend(added)
    cases.update(title='All-family representation with same-row conditional values',
                 catalogue_sha256=artifact_sha(catalogue),
                 root_row_value_case_overrides=overrides,
                 mechanical_coverage_complete=False, automatic_fill_authorized=False)
    ids = [c['id'] for c in cases['cases']]
    if len(ids) != len(set(ids)):
        raise ValueError('Duplicate row value case identity')
    return catalogue, cases, proposal, decisions


def main():
    catalogue, cases, proposal, decisions = compile_row_values()
    for name, value in [
        ('all-family-row-values-integrated-2026-09-07.json', catalogue),
        ('all-family-row-values-cases-integrated-2026-09-07.json', cases),
        ('row-values-catalogue-proposal-2026-09-07.json', proposal),
        ('row-values-catalogue-decisions-2026-09-07.json', decisions),
    ]:
        (RESEARCH / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'catalogue_sha256': artifact_sha(catalogue),
                     'cases_sha256': artifact_sha(cases), **catalogue['stats'],
                     'representation_cases': len(cases['cases'])}))


if __name__ == '__main__':
    main()
