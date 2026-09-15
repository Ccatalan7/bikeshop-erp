#!/usr/bin/env python3
"""Compile the reviewed same-row requirements after the frozen mechanical base.

The f317 base remains intact for the independently owned wheels proposal.
This stage neither publishes metadata nor changes product observations.
"""
import argparse
import hashlib
import json
from pathlib import Path

from compile_product_spec_catalog import RESEARCH, validate_contract
from compile_product_spec_mechanical_addenda import compile_mechanical_addenda
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha


def compile_conditions():
    catalogue, fixtures = compile_mechanical_addenda()
    decision = json.loads((RESEARCH / 'all-family-row-conditions-root-decisions-2026-09-07.json').read_text())
    if hashlib.sha256((RESEARCH / decision['review_file']).read_bytes()).hexdigest() != decision['review_sha256']:
        raise ValueError('Row-condition review changed after adjudication')
    raw = (RESEARCH / decision['proposal_file']).read_bytes()
    proposal = json.loads(raw)
    if artifact_sha(fixtures) != proposal['prior_cases_sha256']:
        raise ValueError('Row-condition case base has drifted')
    catalogue = apply_reviewed_field_addendum(catalogue, raw, decision, validate_contract)
    if set(decision['case_overrides_accepted']) != set(proposal['case_overrides']):
        raise ValueError('Every changed fixture needs explicit adjudication')
    replaced = set()
    for case in fixtures['cases']:
        key = case['id']
        if key in proposal['case_overrides']:
            if case != proposal['case_override_preimages'][key]['before']:
                raise ValueError('Row-condition case preimage has drifted')
            case.update(proposal['case_overrides'][key])
            replaced.add(key)
    if replaced != set(proposal['case_overrides']):
        raise ValueError('Missing row-condition case preimage')
    fixtures['cases'].extend(proposal['fixtures'])
    ids = [case['id'] for case in fixtures['cases']]
    if len(ids) != len(set(ids)):
        raise ValueError('Duplicate representation case identity')
    fixtures.update(title='Representation after mechanical and same-row adjudication',
                    catalogue_sha256=artifact_sha(catalogue),
                    mechanical_coverage_complete=False, automatic_fill_authorized=False)
    return catalogue, fixtures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=RESEARCH / 'all-family-row-conditions-integrated-2026-09-07.json')
    parser.add_argument('--cases', type=Path, default=RESEARCH / 'all-family-row-condition-cases-integrated-2026-09-07.json')
    args = parser.parse_args()
    catalogue, fixtures = compile_conditions()
    args.output.write_text(json.dumps(catalogue, ensure_ascii=False, indent=2) + '\n')
    args.cases.write_text(json.dumps(fixtures, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'catalogue_sha256': artifact_sha(catalogue), 'cases_sha256': artifact_sha(fixtures),
                      **catalogue['stats'], 'representation_cases': len(fixtures['cases'])}))


if __name__ == '__main__':
    main()
