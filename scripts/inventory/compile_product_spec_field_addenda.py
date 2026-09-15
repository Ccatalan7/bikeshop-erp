#!/usr/bin/env python3
"""Reproduce adjudicated local field metadata and its representation fixtures.

Never writes the database or opens publication/fill gates. The original
proposals, independent reviews and root decisions remain separate artifacts.
"""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
from compile_product_spec_catalog import build, validate_contract, RESEARCH
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha


def read(name):
    return json.loads((RESEARCH / name).read_text())


def compile_addenda():
    result = build()
    base_cases = read('all-family-representation-cases-2026-09-06.json')
    cases = deepcopy(base_cases['cases'])
    reviews = []
    for letter in ['a', 'b']:
        suffix = '' if letter == 'a' else '-b'
        proposal_name = f'all-family-field-addendum{suffix}-2026-09-07.json'
        decision = read(f'field-addendum-{letter}-root-decisions-2026-09-07.json')
        review_bytes = (RESEARCH / decision['independent_review_file']).read_bytes()
        if hashlib.sha256(review_bytes).hexdigest() != decision['independent_review_sha256']:
            raise ValueError('Independent review changed after root adjudication')
        review = json.loads(review_bytes)
        proposal_bytes = (RESEARCH / proposal_name).read_bytes()
        result = apply_reviewed_field_addendum(result, proposal_bytes, decision, validate_contract)
        reviews.append(decision['independent_review_sha256'])
        for original in json.loads(proposal_bytes)['representation_cases']:
            case = deepcopy(review['case_overrides'].get(original['id'], original))
            if case.get('exclude'):
                continue
            case['automatic_fill_authorized'] = False
            case['facts_verified_for_product'] = False
            case['root_reconciliation'] = []
            if case['values'].get('head_drive') in ('Torx T25', 'Torx T30'):
                code = case['values']['head_drive'].split()[-1]
                case['values'].update(head_drive='Torx', torx_size=code)
                case['root_reconciliation'].append('Torx family and literal size have separate owners.')
            removed = {key: case['values'].pop(key) for key in list(case['values']) if key.startswith('sensor_link_')}
            if removed:
                case['unassigned_proposal_observations'] = removed
                case['root_reconciliation'].append('Sensor/transport rows own the scoped claims; rejected duplicate booleans are retained here as proposal history.')
            if case['id'] == 'light_inventory_ae_kit_pending':
                removed = {key: case['values'].pop(key) for key in ['power_source'] if key in case['values']}
                case['unassigned_proposal_observations'] = removed
                case['root_reconciliation'].append('An unidentified kit has no confirmed common power source; per-light research remains pending.')
            cases.append(case)
    result = apply_reviewed_field_addendum(result,
        (RESEARCH / 'field-integration-corrections-2026-09-07.json').read_bytes(),
        read('field-integration-root-decisions-2026-09-07.json'), validate_contract)
    templates = {t['key']: t for t in result['templates']}
    for case in cases:
        values = case['values']
        contract = templates[case['template']]['form_contract']
        for link in contract.get('row_coherence', {}).get('links', []):
            source = values.get(link['field'], {}).get('rows', [])
            targets = values.get(link['target_field'], {}).get('rows', [])
            for row in source:
                literal = row['values'].get(link['column'])
                if literal is None or any(t['id'] == literal for t in targets):
                    continue
                # Only reconcile reviewed fixtures, never product observations.
                # The row-link proposal explicitly named this unique target.
                matched = [t for t in targets if t['values'].get(link['label_columns'][0]) == literal]
                if len(matched) != 1:
                    raise ValueError(f'Fixture link needs explicit adjudication: {case["id"]}/{row["id"]}/{literal}')
                row['values'][link['column']] = matched[0]['id']
                case.setdefault('root_reconciliation', []).append({
                    'source_field': link['field'], 'source_row': row['id'],
                    'target_field': link['target_field'], 'target_row': matched[0]['id'],
                    'original_target_label': literal})
    return result, {'schema_version': 1, 'title': 'Representation cases after independent A/B review',
        'catalogue_sha256': artifact_sha(result), 'independent_review_hashes': reviews,
        'mechanical_coverage_complete': False, 'automatic_fill_authorized': False, 'cases': cases}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=RESEARCH / 'all-family-reviewed-fields-2026-09-07.json')
    parser.add_argument('--cases', type=Path, default=RESEARCH / 'all-family-representation-cases-2026-09-07.json')
    args = parser.parse_args()
    result, cases = compile_addenda()
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    args.cases.write_text(json.dumps(cases, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'catalogue_sha256': artifact_sha(result), 'cases_sha256': artifact_sha(cases),
        **result['stats'], 'representation_cases': len(cases['cases'])}))


if __name__ == '__main__':
    main()
