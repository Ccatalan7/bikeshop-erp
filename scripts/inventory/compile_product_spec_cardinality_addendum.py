#!/usr/bin/env python3
"""Bind the versioned row-count contract only to supplied crankset crowns."""
from copy import deepcopy
import json

from compile_product_spec_catalog import RESEARCH, validate_contract
from compile_product_spec_evidence_scopes_addendum import compile_evidence_scopes, frozen, CONTENTS_SHA
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha

BASE_SHA = 'e709158d0ac49603ab01dfde19326d1f9f2fd0d0ce50723cb5d0076390226d9d'
CASES_SHA = '456946a2bb7b2ca23bb9decc77a729a5f157eec7ce983f27d8f0aaaeab5b884e'


def compile_cardinality():
    base, cases, _, _, _ = compile_evidence_scopes()
    if artifact_sha(base) != BASE_SHA or artifact_sha(cases) != CASES_SHA:
        raise ValueError('Frozen evidence-scope stage changed')
    template = next(t for t in base['templates'] if t['key'] == 'crankset')
    before = template['form_contract'].get('row_coherence')
    if before is not None and before['version'] != 1:
        raise ValueError('Unexpected existing coherence version')
    after = {'version': 2, 'links': deepcopy((before or {}).get('links', [])),
             'cardinalities': [{'id': 'included_crown_occurrences',
                 'field': 'chainring_teeth_rows', 'total_field': 'included_chainring_count'}]}
    proposal = {'schema_version': 1, 'new_definitions': {}, 'patches': [
        {'id': 'CARD-01', 'op': 'replace_template_coherence', 'template': 'crankset',
         'key': 'row_coherence', 'before': {'present': before is not None, 'value': deepcopy(before)},
         'after': after}], 'source_review_sha256': CONTENTS_SHA,
        'required_server_migration': '20260907025000', 'mechanical_coverage_complete': False,
        'automatic_fill_authorized': False}
    decisions = {'approval_scope': 'field_representation', 'base_sha256': BASE_SHA,
        'proposal_sha256': artifact_sha(proposal), 'source_cases_sha256': CASES_SHA,
        'patch_adjudications': [{'patch_id': 'CARD-01', 'decision': 'aceptar',
          'reason': 'Compare declared count with distinct supplied crown occurrences. Too few is incomplete; too many contradict the total. No mounting or kit quantity inference.'}],
        'mechanical_coverage_complete': False, 'automatic_fill_authorized': False}
    catalogue = apply_reviewed_field_addendum(base, proposal, decisions, validate_contract)
    review = frozen('package-contents-boundary-review-2026-09-07.json', CONTENTS_SHA)
    existing = {c['id'] for c in cases['cases']}
    selected = {'PCB-C01', 'PCB-C02', 'PCB-C03', 'PCB-C04', 'PCB-C06',
                'PCB-C07', 'PCB-C11', 'PCB-C12', 'PCB-C13', 'PCB-C14', 'PCB-C17'}
    for original in review['fixtures']:
        if original['id'] not in selected:
            continue
        if original['id'] in existing:
            raise ValueError('Cardinality fixture already exists')
        case = deepcopy(original)
        case.update(engine_implemented=True, cardinality_activated=case['template'] == 'crankset',
                    expected_blocking=[], facts_verified_for_product=False, automatic_fill_authorized=False)
        code = {'PCB-C02': 'field_applicability', 'PCB-C03': 'row_cardinality_conflict',
                'PCB-C12': 'integer', 'PCB-C13': 'range'}.get(case['id'])
        if code:
            field = 'included_chainring_count' if case['id'] in {'PCB-C12','PCB-C13'} else 'chainring_teeth_rows'
            case['expected_blocking'] = [{'code': code, 'field': field}]
            if case['id'] in {'PCB-C12', 'PCB-C13'}:
                case['expected_sql_blocking'] = [{'code': 'field_constraint', 'field': field}]
        elif case['id'] in {'PCB-C04','PCB-C06','PCB-C07','PCB-C11','PCB-C14'}:
            case['expected_issue_subset'] = [{'code': 'row_cardinality_pending',
                'field': 'chainring_teeth_rows', 'blocking': False}]
        elif case['id'] == 'PCB-C17':
            case['forbidden_issue_fields'] = ['chainring_teeth_rows']
        cases['cases'].append(case)
    # The old metadata cases remain immutable above; record activation in the
    # new derivative instead of rewriting their source review.
    for case in cases['cases']:
        if case['id'] in {'PCB-C05','PCB-C08','PCB-C09','PCB-C10','PCB-C15','PCB-C16'}:
            case.update(engine_implemented=True, cardinality_activated=True)
    cases.update(title='All-family supplied-crown cardinality', catalogue_sha256=artifact_sha(catalogue),
                 required_server_migration='20260907025000')
    return catalogue, cases, proposal, decisions


if __name__ == '__main__':
    catalogue, cases, proposal, decisions = compile_cardinality()
    for name, value in [('all-family-cardinality-integrated-2026-09-07.json', catalogue),
                        ('all-family-cardinality-cases-integrated-2026-09-07.json', cases),
                        ('cardinality-root-proposal-2026-09-07.json', proposal),
                        ('cardinality-root-decisions-2026-09-07.json', decisions)]:
        (RESEARCH/name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({'catalogue_sha256': artifact_sha(catalogue), 'cases_sha256': artifact_sha(cases),
                     'stats': catalogue['stats'], 'cases': len(cases['cases'])}))
