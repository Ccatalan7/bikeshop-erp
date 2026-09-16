#!/usr/bin/env python3
"""Rebuild the CL573R connector proposal against chain_link contract 40.

The v2 proposal (2026-09-07, researched by Codex) bound the product to the
KMC CL573R reference and derived six facts from it. On 2026-09-16 the
chain_link template was replaced: chain_connector_target is legacy, and
connector_target_declarations (rows) is required. A reference effect on a
legacy key cannot be applied, so this rebuild keeps every value Codex
researched, states each as a research-origin fact backed by the same archived
KMC evidence, adds the target declarations as rows from the same page, and
binds no reference. The preimage is the fresh authenticated snapshot captured
by fill_snapshot_probe.py. Status review_ready; the review record stays empty
until a distinct reviewer fills it.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'docs/development/product-specs-research-2026-09-05'
KMC = 'https://www.kmcchain.com/en/product/connector-missing-link-cl573r-8s-7s-6s-speed'
TARGETS = ['X8', 'Z8.3', 'Z7', 'Z6']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--previous', type=Path, default=RESEARCH / 'catalog-fill-first-proposal-cl573r-v2.json')
    parser.add_argument('--researcher', default='claude')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    snapshot = json.loads(args.snapshot.read_text())
    previous = json.loads(args.previous.read_text())
    product, editor = snapshot['product'], snapshot['editor']
    if product['id'] != previous['product_id'] or snapshot['observations']:
        raise SystemExit('unexpected product or existing observations; review by hand')
    current = {'value': None, 'source': None, 'fact_id': None, 'fact_sha256': None, 'confirmed': None}
    fields = {f['spec_definitions']['key']: f['spec_definitions'] for f in editor['template']['fields']}
    roles = editor['template']['form_contract']['roles']

    def fact(key, proposed, method, scope, reason):
        if key not in fields or roles.get(key) == 'legacy':
            raise SystemExit('key not active in contract: ' + key)
        return {'key': key, 'current': dict(current), 'proposed': proposed, 'unit': fields[key].get('unit'),
                'method': method, 'origin': 'research', 'evidence': ['kmc-model'], 'scope': scope, 'reason': reason}

    rows = {'schema_version': 1, 'rows': [
        {'id': 'kmc-' + model.lower().replace('.', '-'),
         'values': {'claim_identity': 'KMC CL573R admite cadena KMC ' + model, 'scope_kind': 'Modelo documentado',
                    'target_brand': 'KMC', 'target_model': model, 'verdict': 'Admitido por la fuente',
                    'source_document': 'Página de producto KMC CL573R, sección de compatibilidad (archivo kmc-cl573r-20260906.md)',
                    'source_url': KMC},
         'sources': [KMC]} for model in TARGETS]}
    facts = [
        fact('chain_connector_type', 'Missing link', 'Declaración OEM en la página del modelo',
             'Modelo CL573R; la presentación en stock no se certifica', 'La página lo identifica como Missinglink.'),
        fact('spec_evidence_source', KMC, 'URL de la página OEM consultada el 2026-09-06 y archivada con hash',
             'Fuente de todos los hechos de esta propuesta', 'Fuente exigida por el contrato para las medidas.'),
        fact('chain_speeds', ['6', '7', '8'], 'Declaración OEM: clases de cadena 6, 7 y 8',
             'Sólo el modelo CL573R', 'La página enumera 8s, 7s y 6s.'),
        fact('chain_link_reusable', True, 'Declaración OEM: «Missinglink Reusable»',
             'Sólo el modelo CL573R', 'Reutilizable según el fabricante; no fija un número de reusos.'),
        fact('chain_connector_directional', False, 'Declaración OEM: «Non directional design»',
             'Sólo el modelo CL573R', 'Sin sentido de montaje según el fabricante.'),
        fact('connector_target_declarations', rows, 'Declaración OEM de cadenas objetivo: X8, Z8.3, Z7, Z6',
             'Declaración de la fuente; no es una exclusión de otras cadenas ni prueba de montaje',
             'El contrato 40 exige la declaración por filas; sustituye al campo retirado chain_connector_target.'),
    ]
    proposal = {
        'schema_version': 2, 'product_id': product['id'], 'researcher': args.researcher, 'status': 'review_ready',
        'based_on': {'tenant_id': snapshot['tenant_id'], 'snapshot_sha256': snapshot['snapshot_sha256'],
                     'fingerprints': snapshot['fingerprints'], 'spec_revision': product['spec_revision'],
                     'updated_at': product['updated_at'], 'template_id': editor['template_id'],
                     'contract_version': editor['contract_version']},
        'identity': [{'field': 'model', 'current': product.get('model'), 'proposed': 'CL573R',
                      'evidence': ['product-name', 'kmc-model'],
                      'reason': 'El nombre guardado identifica CL573R y KMC documenta ese modelo; no se deduce de las velocidades.'}],
        'reference': None, 'facts': facts, 'evidence': previous['evidence'], 'conflicts': [],
        'review': {'by': None, 'verdict': 'pending', 'date': None, 'reviewed_proposal_sha256': None,
                   'notes': 'Reconstruida el 2026-09-16 sobre el contrato 40 de chain_link a partir de la investigación de Codex del 2026-09-07 (v2). Mismos valores y misma evidencia; sin vínculo de referencia porque chain_connector_target es legacy; declaración de destinos por filas.'},
    }
    args.output.write_text(json.dumps(proposal, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'output': str(args.output), 'facts': len(facts), 'rows': len(rows['rows']),
                      'contract_version': editor['contract_version'], 'snapshot_sha256': snapshot['snapshot_sha256']}))


if __name__ == '__main__':
    main()
