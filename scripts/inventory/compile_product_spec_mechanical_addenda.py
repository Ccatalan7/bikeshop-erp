#!/usr/bin/env python3
"""Reproduce reviewed mechanical metadata on top of the frozen A/B catalogue.

Pure local transformation. It neither publishes reference claims nor changes
product observations, assignments or any publication/fill gate.
"""
import argparse
import hashlib
import json
from pathlib import Path

from compile_product_spec_catalog import RESEARCH, validate_contract
from compile_product_spec_field_addenda import compile_addenda
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha


def compile_mechanical_addenda():
    catalogue, fixtures = compile_addenda()
    decision = json.loads((RESEARCH / 'brake-family-root-decisions-2026-09-07.json').read_text())
    review = (RESEARCH / decision['review_file']).read_bytes()
    if hashlib.sha256(review).hexdigest() != decision['review_sha256']:
        raise ValueError('Brake review changed after root adjudication')
    catalogue = apply_reviewed_field_addendum(
        catalogue, (RESEARCH / decision['proposal_file']).read_bytes(),
        decision, validate_contract)
    brake_cases = json.loads((RESEARCH / 'brake-family-representation-cases-2026-09-07.json').read_text())
    fixtures['cases'].extend(brake_cases['cases'])
    decision = json.loads((RESEARCH / 'light-power-sensor-root-decisions-2026-09-07.json').read_text())
    for kind in ('independent_review', 'original_proposal'):
        raw = (RESEARCH / decision[kind + '_file']).read_bytes()
        if hashlib.sha256(raw).hexdigest() != decision[kind + '_sha256']:
            raise ValueError('LPS review/source changed after root adjudication')
    catalogue = apply_reviewed_field_addendum(catalogue,
        (RESEARCH / 'light-power-sensor-normalized-patches-2026-09-07.json').read_bytes(),
        decision, validate_contract)
    replacements = decision['case_replacements']
    replaced = set()
    for index, case in enumerate(fixtures['cases']):
        replacement = replacements.get(case['id'])
        if replacement is not None:
            if artifact_sha(case) != replacement['before_sha256']:
                raise ValueError('A corrected research fixture has drifted')
            fixtures['cases'][index] = replacement['after']
            replaced.add(case['id'])
    if replaced != set(replacements):
        raise ValueError('Missing research fixture preimage')
    lps_cases = json.loads((RESEARCH / 'light-power-sensor-representation-cases-2026-09-07.json').read_text())
    fixtures['cases'].extend(case for case in lps_cases['cases'] if case['id'] not in replaced)
    ids = [case['id'] for case in fixtures['cases']]
    if len(ids) != len(set(ids)):
        raise ValueError('Duplicate representation case identity')
    fixtures.update(
        title='Representation after A/B and root mechanical adjudication',
        catalogue_sha256=artifact_sha(catalogue),
        mechanical_coverage_complete=False, automatic_fill_authorized=False)
    return catalogue, fixtures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=RESEARCH / 'all-family-reviewed-fields-integrated-2026-09-07.json')
    parser.add_argument('--cases', type=Path, default=RESEARCH / 'all-family-representation-cases-integrated-2026-09-07.json')
    args = parser.parse_args()
    catalogue, fixtures = compile_mechanical_addenda()
    args.output.write_text(json.dumps(catalogue, ensure_ascii=False, indent=2) + '\n')
    args.cases.write_text(json.dumps(fixtures, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'catalogue_sha256': artifact_sha(catalogue),
        'cases_sha256': artifact_sha(fixtures), **catalogue['stats'],
        'representation_cases': len(fixtures['cases'])}))


if __name__ == '__main__':
    main()
