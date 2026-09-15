#!/usr/bin/env python3
"""Compile the frozen row-condition base and root-adjudicated WSS representation."""
import argparse
import hashlib
import json
from pathlib import Path

from compile_product_spec_catalog import RESEARCH, validate_contract
from compile_product_spec_condition_addendum import compile_conditions
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha


def compile_wss():
    catalogue, fixtures = compile_conditions()
    decision = json.loads((RESEARCH / 'wss-root-decisions-2026-09-07.json').read_text())
    for filename, sha in decision['source_hashes'].items():
        if hashlib.sha256((RESEARCH / filename).read_bytes()).hexdigest() != sha:
            raise ValueError('Frozen WSS source/review changed: ' + filename)
    catalogue = apply_reviewed_field_addendum(catalogue,
        (RESEARCH / decision['proposal_file']).read_bytes(), decision, validate_contract)
    cases = json.loads((RESEARCH / 'wss-representation-cases-2026-09-07.json').read_text())
    if artifact_sha(cases) != decision['cases_sha256']:
        raise ValueError('Adjudicated WSS cases changed')
    fixtures['cases'].extend(cases['cases'])
    ids = [c['id'] for c in fixtures['cases']]
    if len(ids) != len(set(ids)):
        raise ValueError('Duplicate WSS case identity')
    fixtures.update(title='All-family representation after WSS adjudication',
        catalogue_sha256=artifact_sha(catalogue), mechanical_coverage_complete=False,
        automatic_fill_authorized=False)
    return catalogue, fixtures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=RESEARCH / 'all-family-wss-integrated-2026-09-07.json')
    parser.add_argument('--cases', type=Path, default=RESEARCH / 'all-family-wss-cases-integrated-2026-09-07.json')
    args = parser.parse_args()
    catalogue, fixtures = compile_wss()
    args.output.write_text(json.dumps(catalogue, ensure_ascii=False, indent=2) + '\n')
    args.cases.write_text(json.dumps(fixtures, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'catalogue_sha256': artifact_sha(catalogue), 'cases_sha256': artifact_sha(fixtures),
        **catalogue['stats'], 'representation_cases': len(fixtures['cases'])}))


if __name__ == '__main__':
    main()
