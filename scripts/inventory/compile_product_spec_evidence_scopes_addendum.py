#!/usr/bin/env python3
"""Preserve supplied crown occurrences and separately sourced tire limits."""
from copy import deepcopy
import hashlib
import json

from compile_product_spec_catalog import RESEARCH, validate_contract
from compile_product_spec_wss_residual_addendum import compile_wss_residual
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha

BASE_SHA = '00041bb82cbddec1278a4d310d26747601518356abce5af4138da9bab7aa4b06'
CASES_SHA = 'da0b43e638820fce0fafcf93b53431c96d4be174e4bc180038e20e2d5ab851d9'
CONTENTS_SHA = '6d112ece1b1dc41c282dea5a3fa751ff779636f7871aaca36da571a8941d0fdd'
PRESSURE_SHA = 'd732586dd25b2f8d44ffed2a5fa2df6b33dd8648dbcd1a52f5d18cc25ca238a7'


def frozen(name, expected):
    raw = (RESEARCH/name).read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError(f'Frozen review changed: {name}')
    return json.loads(raw)


def compile_evidence_scopes():
    base, cases, _, _ = compile_wss_residual()
    if artifact_sha(base) != BASE_SHA or artifact_sha(cases) != CASES_SHA:
        raise ValueError('WSS residual stage changed')
    contents = frozen('package-contents-boundary-review-2026-09-07.json', CONTENTS_SHA)
    pressure = frozen('tire-pressure-dual-unit-proposal-2026-09-07.json', PRESSURE_SHA)
    templates = {t['key']: t for t in base['templates']}
    patches = deepcopy(contents['metadata_patch_proposal']['patches'])
    original = {p['id']: p for p in pressure['patches']}
    rebased = deepcopy(pressure['patches'])
    row_patch = next(p for p in rebased if p['id'] == 'TPDU-02-row-conditions-unit-gates-value')
    old_conditions = row_patch['before']['value']
    current_conditions = templates['tire']['form_contract']['row_conditions']
    if (old_conditions['version'] != 1 or current_conditions['version'] != 1
            or set(old_conditions['fields']) != {'tire_rim_configurations'}
            or set(current_conditions['fields']) != {'tire_rim_configurations'}
            or row_patch['after']['fields']['tire_rim_configurations']
                != old_conditions['fields']['tire_rim_configurations']):
        raise ValueError('Pressure proposal changes an unreviewed condition')
    # R6 is already integrated in the new base. Add one owner without losing
    # the hookless width/unit requirements absent from Claude's older base.
    row_patch['before'] = {'present': True, 'value': deepcopy(current_conditions)}
    row_patch['after'] = deepcopy(current_conditions)
    row_patch['after']['fields']['tire_general_max_pressures'] = deepcopy(
        original[row_patch['id']]['after']['fields']['tire_general_max_pressures'])
    contract = templates['tire']['form_contract']
    if any(contract[k]['tire_max_pressure_psi'] != 'legacy'
           for k in ['roles', 'semantic_roles']):
        raise ValueError('Previously retired pressure scalar drifted')
    patches.extend(rebased)
    proposal = {'schema_version': 1, 'base_sha256': BASE_SHA,
        'new_definitions': deepcopy(pressure['new_definitions']), 'patches': patches,
        'source_reviews': {'package_contents': CONTENTS_SHA, 'dual_pressure': PRESSURE_SHA},
        'rebase': {'patch_id': row_patch['id'], 'before': original[row_patch['id']],
                   'after': deepcopy(row_patch), 'reason': 'Preserve integrated R6 verbatim.'},
        'mechanical_coverage_complete': False, 'automatic_fill_authorized': False}
    decisions = {'approval_scope': 'field_representation', 'base_sha256': BASE_SHA,
        'proposal_sha256': artifact_sha(proposal), 'source_cases_sha256': CASES_SHA,
        'patch_adjudications': [], 'mechanical_coverage_complete': False,
        'automatic_fill_authorized': False, 'cardinality_activated': False}
    for patch in patches:
        verdict = {'patch_id': patch['id'], 'decision': 'aceptar',
            'reason': 'Preserve content occurrence or exact declaration scope, units and document; no assembly approval.'}
        if patch['id'] == 'TPDU-03-retire-max-pressure-psi':
            verdict.update(decision='rechazar', reason='Already integrated by WRFP-R3 on this exact base; no second mutation.')
        elif patch['id'] == 'TPDU-01-general-max-pressures-table':
            after = deepcopy(patch['after'])
            after['helpers'] = ('Una fila por máximo que la fuente declara para esta variante sin condicionarlo a un perfil de llanta. Conserva unidad, alcance y documento; no conviertas cifras. Los límites condicionados van en las declaraciones de montaje. Fuentes discrepantes requieren revisión antes de usar sus límites.')
            verdict.update(decision='corregir', after_override=after,
                reason='Keep the source/example discussion in research; concise operator guidance preserves documentary conflict as unresolved.')
        decisions['patch_adjudications'].append(verdict)
    catalogue = apply_reviewed_field_addendum(base, proposal, decisions, validate_contract)
    overrides = []
    added = []
    # Only metadata boundaries here. The review's count-versus-rows cases are
    # reserved for the separately versioned engine; never label that gap fixed.
    metadata_ids = {'PCB-C05', 'PCB-C08', 'PCB-C09', 'PCB-C10', 'PCB-C15', 'PCB-C16'}
    for source in contents['fixtures']:
        if source['id'] not in metadata_ids:
            continue
        case = deepcopy(source)
        case.update(expected_blocking=[], cardinality_activated=False)
        if case['id'] == 'PCB-C10':
            case['expected_issue_subset'] = [{'code': 'row_incomplete',
                'field': 'chainring_teeth_rows', 'blocking': False}]
        else:
            case['forbidden_issue_fields'] = ['chainring_teeth_rows']
        added.append(case)
    for source in pressure['fixtures']:
        case = deepcopy(source)
        before = deepcopy(case)
        rows = case.get('values', {}).get('tire_general_max_pressures', {}).get('rows', [])
        for row in rows:
            document = row['values'].get('source_document', '')
            # A year in a product page title is not a document revision.
            row['values']['source_document'] = document.replace(', edición 2014', '') if document else document
            if not document:
                row['values'].pop('source_document', None)
        if case != before:
            overrides.append({'id': case['id'], 'before': before, 'after': deepcopy(case),
                'reason': 'Root verified both pages; 2014 is not established as document edition.'})
        observed = case.pop('observed_in_local_trial', [])
        subset = [{'code': i['code'], 'field': i['field'], 'blocking': i['blocking']}
                  for i in observed if i['code'] == 'row_incomplete']
        if subset:
            case['expected_issue_subset'] = subset
        if case['id'] == 'tpdu_value_without_unit_is_not_authorized':
            case['expected_row_condition_issues'] = [{'code': 'row_prerequisite',
                'field': 'tire_general_max_pressures', 'row_id': 'r1',
                'column': 'max_pressure_value', 'blocking': False}]
        if 'expected_row_count' in case:
            case['expected_row_counts'] = {'tire_general_max_pressures': case.pop('expected_row_count')}
        case.update(facts_verified_for_product=False, automatic_fill_authorized=False)
        added.append(case)
    if len(added) != 15:
        raise ValueError('Unreviewed evidence-scope fixture set')
    cases['cases'].extend(added)
    cases.update(title='All-family supplied occurrences and documentary pressure scopes',
        catalogue_sha256=artifact_sha(catalogue), mechanical_coverage_complete=False,
        automatic_fill_authorized=False, deferred_pressure_fixture_ids=[],
        superseded_pressure_fixtures=sorted(base_name for base_name in [
            'wrfp_schwalbe_general_maximum_in_bar', 'wrfp_unit_without_value_is_pending',
            'wrfp_value_without_unit_stays_pending', 'wrfp_hookless_row_maximum_is_not_the_headline']))
    if len({c['id'] for c in cases['cases']}) != len(cases['cases']):
        raise ValueError('Duplicate fixture identity')
    return catalogue, cases, proposal, decisions, overrides


if __name__ == '__main__':
    catalogue, cases, proposal, decisions, overrides = compile_evidence_scopes()
    for name, value in [('all-family-evidence-scopes-integrated-2026-09-07.json', catalogue),
                        ('all-family-evidence-scopes-cases-integrated-2026-09-07.json', cases),
                        ('evidence-scopes-root-proposal-2026-09-07.json', proposal),
                        ('evidence-scopes-root-decisions-2026-09-07.json', decisions),
                        ('evidence-scopes-root-fixture-overrides-2026-09-07.json', overrides)]:
        (RESEARCH/name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({'catalogue_sha256': artifact_sha(catalogue), 'cases_sha256': artifact_sha(cases),
                     'stats': catalogue['stats'], 'cases': len(cases['cases'])}))
