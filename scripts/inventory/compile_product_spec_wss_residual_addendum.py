#!/usr/bin/env python3
"""Integrate reviewed bearing/hookless residuals; defer scalar pressure loss."""
from copy import deepcopy
import hashlib
import json
from compile_product_spec_catalog import RESEARCH, validate_contract
from compile_product_spec_package_contents_addendum import compile_package_contents
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha

PACKET_SHA = '239ab6607e25f4211f88d5c4998cec25af52d07278d75d983c98f0cfa8b05087'
BASE_SHA = '20a9c1eabdf84dd5e3e9cb5a4a922a695c6e91deff53bebdb2e0c584b5e8edee'
CASES_SHA = 'f87a94087f0a325d637f58833d61c5568e95cc52bb5e27fd126a1306aa5eb1ae'
DEFERRED = {
 'wrfp_schwalbe_general_maximum_in_bar', 'wrfp_unit_without_value_is_pending',
 'wrfp_value_without_unit_stays_pending', 'wrfp_hookless_row_maximum_is_not_the_headline',
}


def compile_wss_residual():
    catalogue, cases, _, _ = compile_package_contents()
    if artifact_sha(catalogue) != BASE_SHA or artifact_sha(cases) != CASES_SHA:
        raise ValueError('Contents stage drifted')
    raw = (RESEARCH/'wss-residual-field-packet-2026-09-07.json').read_bytes()
    if hashlib.sha256(raw).hexdigest() != PACKET_SHA:
        raise ValueError('Frozen WSS residual packet changed')
    proposal = json.loads(raw)
    decisions = {'approval_scope': 'field_representation', 'base_sha256': BASE_SHA,
        'proposal_sha256': PACKET_SHA, 'source_cases_sha256': CASES_SHA,
        'patch_adjudications': [], 'deferred_fixture_ids': sorted(DEFERRED),
        'mechanical_coverage_complete': False, 'automatic_fill_authorized': False}
    for p in proposal['patches']:
        verdict = {'patch_id': p['id'], 'decision': 'aceptar',
            'reason': 'Prerrequisito por construcción/configuración y magnitud OEM explícita; no acredita un montaje ni rellena productos.'}
        if p['id'] in ['WRFP-R3-max-pressure-unit', 'WRFP-R3-max-pressure-value']:
            verdict.update(decision='rechazar', reason='El único par escalar pierde una de las dos cifras OEM impresas. Se prepara representación repetible por unidad, fuente y alcance; no se convierte ni inventa una cifra.')
        if p['id'] in ['WRFP-R1-inner-bevel-helper', 'WRFP-R1-outer-bevel-helper']:
            verdict['before_extensions'] = {'helpers': {'present': False, 'value': None}}
        if p['id'] == 'WRFP-R1-race-contact-angle':
            after = deepcopy(p['after'])
            after['helpers'] = ('Magnitud del ángulo interno α respecto del plano perpendicular al eje (0–90°). Sólo si el fabricante declara un único valor nominal común. No se deduce de MAX, la aplicación Dirección ni de los biseles. Un pedalier puede declarar el ángulo de sus rodamientos internos sin identificar un SKU suelto: no se copia a este producto sin confirmar esa identidad.')
            verdict.update(decision='corregir', after_override=after,
                reason='El ángulo caracteriza el contacto del rodamiento; el SKU del conjunto no identifica automáticamente un producto suelto.')
        decisions['patch_adjudications'].append(verdict)
    catalogue = apply_reviewed_field_addendum(catalogue, raw, decisions, validate_contract)
    overrides = []
    targets = {c['case_id'] for c in proposal['previous_fixture_changes']}
    expected = {'wss_root_pressure_unit_requires_its_value', 'wss_SF6', 'wss_tire_same_variant_profile_method_twice'}
    if targets != expected:
        raise ValueError('Unknown old fixture change')
    for case in cases['cases']:
        if case['id'] not in targets: continue
        before = deepcopy(case)
        rows = case['values']['tire_rim_configurations']['rows']
        additions = [{'code': 'row_required_missing', 'field': 'tire_rim_configurations',
            'row_id': r['id'], 'column': 'rim_internal_width_max_mm', 'blocking': False}
            for r in rows]
        if case['id'] == 'wss_root_pressure_unit_requires_its_value':
            case['expected_row_condition_issues'] = additions + case['expected_row_condition_issues']
        else:
            # Invalid row shape short-circuits conditional cell evaluation.
            # Preserve the hard duplicate error; it emits no later pendings.
            case['expected_row_condition_issues'] = []
        overrides.append({'id': case['id'], 'before': before, 'after': deepcopy(case)})
    added = []
    for original in proposal['fixtures']:
        if original['id'] in DEFERRED: continue
        case = deepcopy(original)
        case.update(facts_verified_for_product=False, automatic_fill_authorized=False)
        if case['id'] == 'wrfp_race_contact_angle_outside_domain':
            case['expected_sql_blocking'] = [{'code': 'field_constraint', 'field': 'bearing_race_contact_angle_deg'}]
        if case['id'] == 'wrfp_hookless_row_pending_unit_and_width':
            row_id = case['values']['tire_rim_configurations']['rows'][0]['id']
            case['expected_row_condition_issues'] = [
                {'code': 'row_required_missing', 'field': 'tire_rim_configurations', 'row_id': row_id, 'column': 'rim_internal_width_max_mm', 'blocking': False},
                {'code': 'row_prerequisite', 'field': 'tire_rim_configurations', 'row_id': row_id, 'column': 'max_pressure', 'blocking': False},
                {'code': 'row_required_missing', 'field': 'tire_rim_configurations', 'row_id': row_id, 'column': 'pressure_unit', 'blocking': False},
            ]
        added.append(case)
    if len(added) != 15 or len(overrides) != 3:
        raise ValueError('Unreviewed residual fixture coverage')
    cases['cases'].extend(added)
    cases.update(title='All-family with bearing and hookless residuals',
        catalogue_sha256=artifact_sha(catalogue), mechanical_coverage_complete=False,
        automatic_fill_authorized=False, deferred_pressure_fixture_ids=sorted(DEFERRED))
    if len({c['id'] for c in cases['cases']}) != len(cases['cases']):
        raise ValueError('Duplicate fixture')
    return catalogue, cases, decisions, overrides


if __name__ == '__main__':
    catalogue, cases, decisions, overrides = compile_wss_residual()
    for name, value in [('all-family-wss-residual-integrated-2026-09-07.json', catalogue),
                        ('all-family-wss-residual-cases-integrated-2026-09-07.json', cases),
                        ('wss-residual-root-decisions-2026-09-07.json', decisions),
                        ('wss-residual-root-fixture-overrides-2026-09-07.json', overrides)]:
        (RESEARCH/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'catalogue_sha256': artifact_sha(catalogue), 'cases_sha256': artifact_sha(cases),
                     'stats': catalogue['stats'], 'cases': len(cases['cases'])}))
