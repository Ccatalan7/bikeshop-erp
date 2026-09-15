#!/usr/bin/env python3
"""Compile root-adjudicated cockpit/contact fields after the frozen WSS stage."""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path

from compile_product_spec_catalog import RESEARCH, validate_contract
from compile_product_spec_wss_addendum import compile_wss
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha

PACKET = 'cockpit-pedal-contact-addendum-review-2026-09-07.json'
PACKET_SHA = 'f6f48614dcab8411569a19013124f14101c15d3c7983af0930db9ee718567b66'
WSS_SHA = '6ed9cdf73ae5d9fc0aa2284bb4691f4f1eca958c2762c5ea1e7076c5f9358b18'
REASONS = {
    'CPC01': 'La cantidad comercial unidad no permite inferir lado ni mano de rosca.',
    'CPC02': 'Otro requiere su declaración literal; no se convierte automáticamente en estándar compatible.',
    'CPC03': 'Una única propiedad del largo por lado; el genérico conserva la unidad cuyo lado falta.',
    'CPC04': 'La longitud libre necesaria en cada lado no se deduce de una medida única.',
    'CPC05': 'El rótulo explicita que la medida conservada carece de lado.',
    'CPC06': 'El manual Ergon GP1 06/2014 declara mínimos asimétricos; no se extrapolan a otras variantes.',
    'CPC07': 'El mínimo derecho tiene su propia medida y fuente, sin copiar el izquierdo.',
    'CPC08': 'Propietario u Otro no identifican una interfaz completa sin su modelo/sistema.',
    'CPC09': 'El rótulo distingue sistema de anclaje de una supuesta compatibilidad de marca.',
    'CPC10': 'Cada configuración de tija conserva su sistema de anclaje por separado.',
    'CPC11': 'Un dato de otra fila no completa la identidad del anclaje propietario.',
    'CPC12': 'Relación funcional de mandos por modelo/generación, separada de contenido y sin identidad por nombre.',
    'CPC13': 'Mando declarado incluido pide su modelo; ausencia queda pendiente, no inferida.',
    'CPC14': 'El largo total comparte el documento de cotas OEM; no reemplaza observaciones de cuadro/ciclista.',
}


def compile_contact():
    catalogue, fixtures = compile_wss()
    if artifact_sha(catalogue) != WSS_SHA:
        raise ValueError('Reviewed WSS integration changed')
    raw = (RESEARCH / PACKET).read_bytes()
    if hashlib.sha256(raw).hexdigest() != PACKET_SHA:
        raise ValueError('Frozen cockpit/contact proposal changed')
    proposal = json.loads(raw)
    # The contributor reviewed c122. Every patch preimage is rechecked against
    # WSS by the integrator; no foreign-template replacement is carried over.
    source = RESEARCH / Path(proposal['base_artifact']).name
    if hashlib.sha256(source.read_bytes()).hexdigest() != proposal['base_sha256']:
        raise ValueError('Contributor source base changed')
    if set(REASONS) != {p['id'] for p in proposal['patches']}:
        raise ValueError('An unreviewed contact patch cannot enter the stage')
    decision = {
        'schema_version': 1, 'approval_scope': 'field_representation',
        'base_sha256': artifact_sha(catalogue), 'proposal_sha256': PACKET_SHA,
        'source_base_sha256': proposal['base_sha256'],
        'patch_adjudications': [{'patch_id': p['id'], 'decision': 'aceptar',
                               'reason': REASONS[p['id']]} for p in proposal['patches']],
        'mechanical_coverage_complete': False, 'automatic_fill_authorized': False,
    }
    catalogue = apply_reviewed_field_addendum(catalogue, raw, decision, validate_contract)
    for override in proposal['case_overrides']:
        old = next(c for c in fixtures['cases'] if c['id'] == override['id'])
        if old != override['before']:
            raise ValueError('Contact fixture preimage changed: ' + override['id'])
        fixtures['cases'][fixtures['cases'].index(old)] = deepcopy(override['after'])
    for original in proposal['cases']:
        case = deepcopy(original)
        if case.get('expected_pending_contains'):
            case['expected_issue_subset'] = [dict(i, blocking=False)
                                            for i in case['expected_pending_contains']]
        fixtures['cases'].append(case)
    ids = [c['id'] for c in fixtures['cases']]
    if len(ids) != len(set(ids)):
        raise ValueError('Duplicate contact fixture ID')
    fixtures.update(title='All-family representation after contact adjudication',
                    catalogue_sha256=artifact_sha(catalogue),
                    mechanical_coverage_complete=False, automatic_fill_authorized=False)
    return catalogue, fixtures, decision


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=RESEARCH / 'all-family-contact-integrated-2026-09-07.json')
    parser.add_argument('--cases', type=Path, default=RESEARCH / 'all-family-contact-cases-integrated-2026-09-07.json')
    args = parser.parse_args()
    catalogue, fixtures, decision = compile_contact()
    for path, value in ((args.output, catalogue), (args.cases, fixtures),
                        (RESEARCH / 'contact-root-decisions-2026-09-07.json', decision)):
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'catalogue_sha256': artifact_sha(catalogue), 'cases_sha256': artifact_sha(fixtures),
                      **catalogue['stats'], 'representation_cases': len(fixtures['cases'])}))


if __name__ == '__main__':
    main()
