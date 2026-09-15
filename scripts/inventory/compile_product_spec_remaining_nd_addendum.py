#!/usr/bin/env python3
"""Compile contact + root-adjudicated remaining ND without publication gates."""
import argparse
import hashlib
import json
from pathlib import Path

from compile_product_spec_catalog import RESEARCH, validate_contract
from compile_product_spec_contact_addendum import compile_contact
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha


def compile_remaining_nd():
    catalogue, fixtures, _ = compile_contact()
    if artifact_sha(fixtures) != 'de0d38c2416bae1c086ff5ea7fa9143f1326e360861af8e39bba647c66a685b5':
        raise ValueError('Full fixture preimage changed before ND adjudication')
    decision = json.loads((RESEARCH / 'remaining-nd-root-decisions-2026-09-07.json').read_text())
    for name, sha in decision['source_hashes'].items():
        if hashlib.sha256((RESEARCH / name).read_bytes()).hexdigest() != sha:
            raise ValueError('Frozen ND source changed: ' + name)
    catalogue = apply_reviewed_field_addendum(catalogue,
        (RESEARCH / decision['proposal_file']).read_bytes(), decision, validate_contract)
    cases = json.loads((RESEARCH / 'remaining-nd-representation-cases-2026-09-07.json').read_text())
    if artifact_sha(cases) != decision['cases_sha256']:
        raise ValueError('ND cases changed after adjudication')
    overrides = []
    for case in fixtures['cases']:
        if case['id'] == 'RCF25':
            if case['expected_blocking']:
                raise ValueError('Foreign-mount-variant fixture preimage changed')
            case['expected_blocking'] = [{'code': 'row_shape', 'field': 'bar_clamp_configurations'}]
            case['note'] = 'Una variante distinta del soporte no es montaje de este SKU; se rechaza el token retirado.'
            overrides.append({'id': case['id'], 'reason': case['note']})
        if case['id'] == 'helmet_smith_mainline_certifications_by_row':
            case['values']['helmet_construction'] = case['values'].pop('helmet_kind')
            case['note'] += ' Integral se conserva como construcción general; no se infiere método de fabricación o materiales.'
            overrides.append({'id': case['id'], 'reason': 'Integral pertenece al eje de construcción, no al uso.'})
        if case['id'] == 'helmet_inventory_best_enduro_certificado_sin_norma':
            case['values']['helmet_kind'] = 'Enduro'
            overrides.append({'id': case['id'], 'reason': 'Se conserva Enduro sin inferir cobertura desde el título.'})
        if case['values'].get('helmet_kind') in ('Integral', 'Niño', 'Enduro (cobertura extendida)'):
            raise ValueError('Existing helmet fixture needs explicit root adjudication: ' + case['id'])
    if len(overrides) != 3:
        raise ValueError('Expected three exact ND fixture overrides')
    fixtures['cases'].extend(cases['cases'])
    ids = [c['id'] for c in fixtures['cases']]
    if len(ids) != len(set(ids)):
        raise ValueError('Duplicate ND case ID')
    fixtures.update(title='All-family representation after remaining ND adjudication',
                    catalogue_sha256=artifact_sha(catalogue), root_nd_case_overrides=overrides,
                    mechanical_coverage_complete=False, automatic_fill_authorized=False)
    return catalogue, fixtures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=RESEARCH / 'all-family-remaining-nd-integrated-2026-09-07.json')
    parser.add_argument('--cases', type=Path, default=RESEARCH / 'all-family-remaining-nd-cases-integrated-2026-09-07.json')
    args = parser.parse_args()
    catalogue, fixtures = compile_remaining_nd()
    args.output.write_text(json.dumps(catalogue, ensure_ascii=False, indent=2) + '\n')
    args.cases.write_text(json.dumps(fixtures, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'catalogue_sha256': artifact_sha(catalogue), 'cases_sha256': artifact_sha(fixtures),
                      **catalogue['stats'], 'representation_cases': len(fixtures['cases'])}))


if __name__ == '__main__':
    main()
