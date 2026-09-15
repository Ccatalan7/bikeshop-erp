#!/usr/bin/env python3
"""Root's assignment-only research decisions. Never writes product data."""
from collections import Counter
from copy import deepcopy
import hashlib
import json

from compile_product_spec_catalog import RESEARCH
from product_spec_field_patches import artifact_sha

REVIEW_SHA = '852577ba7176e438be9a145be4327d70d936e464ca613a6571eb46d15a9b155a'
CATALOGUE_SHA = 'e709158d0ac49603ab01dfde19326d1f9f2fd0d0ce50723cb5d0076390226d9d'


def adjudicate():
    raw = (RESEARCH/'assigned-product-family-adjudication-2026-09-07.json').read_bytes()
    if hashlib.sha256(raw).hexdigest() != REVIEW_SHA:
        raise ValueError('Frozen assignment review changed')
    catalogue_raw = (RESEARCH/'all-family-evidence-scopes-integrated-2026-09-07.json').read_bytes()
    if hashlib.sha256(catalogue_raw).hexdigest() != CATALOGUE_SHA:
        raise ValueError('Reviewed template catalogue changed')
    review = json.loads(raw)
    catalogue = json.loads(catalogue_raw)
    templates = {t['id']: t for t in catalogue['templates']}
    by_review = {e['review_id']: e for e in review['adjudications']}
    deltas = {e['review_id']: e for e in review['reviewable_deltas_not_executed']}
    if set(by_review) != {f'AP{i:02}' for i in range(1, 21)} or len(deltas) != 12:
        raise ValueError('Assignment review coverage changed')
    decisions = []
    for key, entry in by_review.items():
        current = entry['preimage']['binding']
        target = templates.get(entry['proposed_template_id'])
        if target and target['key'] != entry['proposed_family']:
            raise ValueError(f'Target template mismatch: {key}')
        verdict = 'preserve_assignment'
        reason = entry['reason']
        local_gate = None
        proposed_delta = None
        if key in {'AP10', 'AP17'}:
            verdict = 'identity_research_pending'
        elif key == 'AP06':
            reason = ('Conservar bearing: su construcción de canastillo y aplicación Pedalier '
                      'ya se representan. La especialización editorial no corrige una '
                      'incompatibilidad demostrada; Thompson no implica Americano.')
            target = templates[current['template_id']]
        elif key == 'AP07':
            verdict = 'delta_waiting_for_content_contract'
            local_gate = 'AG01: quantity/row cardinality, content evidence and downstream consumption remain open.'
            proposed_delta = deepcopy(deltas[key])
        elif key in deltas:
            verdict = 'delta_adjudicated_pending_global_gates'
            proposed_delta = deepcopy(deltas[key])
            if key == 'AP15':
                if target['name'] != 'Conjunto de freno mecánico de disco':
                    raise ValueError('AG02 label correction is absent')
                reason = ('Asignación de conjunto aceptada: rótulo y contrato local no '
                          'presumen manillas ni lista completa. AG02 de representación '
                          'resuelto localmente; Logan/Ozono, revisión y contenido exacto '
                          'continúan pendientes, sin cambios de identidad ni facts.')
        if proposed_delta:
            if proposed_delta['before']['spec_template_id'] != entry['preimage']['spec_template_id']:
                raise ValueError(f'Assignment preimage mismatch: {key}')
            if set(proposed_delta['after']) != {'spec_template_id'}:
                raise ValueError('Assignment decision cannot add fact or identity writes')
            for change in ['fact_payload_changes', 'identity_changes', 'commercial_changes',
                           'erp_set_changes', 'category_mapping_changes']:
                if proposed_delta[change]:
                    raise ValueError(f'Out-of-scope proposed change: {key}/{change}')
            # The independent packet calls its template key "family". In
            # particular mechanical_disc_brake belongs to complete_brake.
            # Preserve both identities; changing a label never rekeys a family.
            proposed_delta['review_template_key_after'] = proposed_delta['family_after']
            proposed_delta['family_after'] = target['technical_family']
            proposed_delta['template_key_after'] = target['key']
        decisions.append({'review_id': key, 'product_id': entry['product_id'], 'sku': entry['sku'],
            'decision': verdict, 'reason': reason, 'local_gate': local_gate,
            'review_preimage_sha256': entry['preimage_canonical_sha256'],
            'before_binding': deepcopy(current),
            'template_target': None if target is None else {
                'id': target['id'], 'key': target['key'], 'family': target['technical_family'],
                'local_template_sha256': artifact_sha(target)},
            'reviewed_delta': proposed_delta,
            'next_research_action': deepcopy(entry['next_research_action']),
            'unresolved': entry['unresolved'], 'preservation_note': entry['preservation_note'],
            'apply_allowed': False, 'identity_model_confirmed': False,
            'mechanical_approval': False, 'fill_allowed': False})
    counts = dict(Counter(e['decision'] for e in decisions))
    if counts != {'preserve_assignment': 7, 'delta_adjudicated_pending_global_gates': 10,
                  'delta_waiting_for_content_contract': 1, 'identity_research_pending': 2}:
        raise ValueError(f'Unexpected assignment decisions: {counts}')
    return {'schema_version': 1, 'reviewed_on': '2026-09-07', 'status': 'root_research_adjudication_only',
        'source_review_sha256': REVIEW_SHA, 'local_catalogue_sha256': CATALOGUE_SHA,
        'production_preimage_captured_at': review['production_captured_at_utc'],
        'evidence_scope': 'Independent review plus Root inspection of AP02, AP06, AP07, AP08, AP09 and AP15 images; source attribution retained.',
        'counts': counts, 'adjudications': decisions,
        'global_gates': {'catalogue_published_and_verified': False,
            'all_family_sanitation_complete': False, 'fresh_authenticated_preimage': False,
            'assignment_only_applicator_verified': False, 'legacy_recovery_verified_in_postgresql': False},
        'assignments_applied': 0, 'products_filled': 0}


if __name__ == '__main__':
    result = adjudicate()
    (RESEARCH/'assigned-product-root-decisions-2026-09-07.json').write_text(
        json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({'sha256': artifact_sha(result), 'counts': result['counts']}))
