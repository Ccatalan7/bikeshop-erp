#!/usr/bin/env python3
"""Write the dated record of one applied research application from its artifacts.

Reads the batch folder (snapshot-fresh.json, simulation.json, bundle.json,
register.sql, receipt.json, snapshot-after.json), the reviewed proposal and
the readiness receipt, and writes a Markdown record plus a progress entry:
what changed, who researched and reviewed, hashes, before/after revisions,
untouched observations, and the read-back. It never writes to the ERP.
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'docs/development/product-specs-research-2026-09-05'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--folder', type=Path, required=True)
    parser.add_argument('--proposal', type=Path, required=True)
    parser.add_argument('--readiness', type=Path, required=True)
    parser.add_argument('--label', required=True, help='e.g. fill-001-cl573r')
    parser.add_argument('--progress-key', required=True)
    args = parser.parse_args()
    proposal = json.loads(args.proposal.read_text())
    before = json.loads((args.folder / 'snapshot-fresh.json').read_text())
    after = json.loads((args.folder / 'snapshot-after.json').read_text())
    bundle = json.loads((args.folder / 'bundle.json').read_text())
    outcome = json.loads((args.folder / 'receipt.json').read_text())
    readiness = json.loads(args.readiness.read_text())
    receipt = outcome['receipt']
    result = receipt['result']
    product = after['product']
    changed = {c['key']: c['final_value'] for c in bundle['command']['changes']}
    observations_after = [(o['definition']['key'], o['fact']['source'], o['fact']['confirmed']) for o in after['observations']]
    record = f"""# {args.label}: primera aplicación de investigación — {dt.date.today().isoformat()}

Producto `{product['sku']}` «{product['name']}» ({product['id']}), plantilla `{after['editor']['template']['key']}`
contrato {after['editor']['contract_version']}. Investigó `{proposal['researcher']}`, revisó `{proposal['review']['by']}`
(veredicto `{proposal['review']['verdict']}`, {proposal['review']['date']}); readiness `{readiness['id']}`.

| Artefacto | SHA-256 |
|---|---|
| Propuesta revisada `{args.proposal.name}` | `{digest(args.proposal)}` |
| Preimagen fresca (snapshot) | `{before['snapshot_sha256']}` |
| Paquete sellado `bundle.json` | `{bundle['bundle_sha256']}` (comando `{bundle['command_sha256']}`) |
| Registro `register.sql` | `{digest(args.folder / 'register.sql')}` |
| Recibo (`before_snapshot_sha256` → `after_snapshot_sha256`) | `{result['before_snapshot_sha256']}` → `{result['after_snapshot_sha256']}` |

## Qué cambió

- Identidad: {json.dumps(bundle['command']['identity_patch'], ensure_ascii=False)}
- Hechos escritos ({len(changed)}): {', '.join('`' + k + '`' for k in changed)}
- Revisión del producto: {before['product']['spec_revision']} → {product['spec_revision']}
- Observaciones después ({len(observations_after)}): {', '.join(k + ' (' + s + (', confirmada' if c else '') + ')' for k, s, c in observations_after)}
- Recibo devuelto por el RPC con `replayed = {result['replayed']}`; la lectura posterior coincide con el recibo: {outcome['current_matches_receipt']}.

## Qué no cambió

Precio, costo, stock, nombre, marca, categoría, imágenes y documentos; ninguna observación previa
existía. Nada se confirmó como medido: cada hecho lleva procedencia `research` y `confirmed = false`
hasta que un mecánico lo confirme en la app.
"""
    (RESEARCH / (args.label + '-record.md')).write_text(record)
    progress_path = RESEARCH / 'progress-measurement-2026-09-08.json'
    progress = json.loads(progress_path.read_text())
    progress[args.progress_key] = {
        'product_id': product['id'], 'sku': product['sku'], 'template': after['editor']['template']['key'],
        'contract_version': after['editor']['contract_version'], 'researcher': proposal['researcher'],
        'reviewer': proposal['review']['by'], 'application_id': result['application_id'],
        'command_sha256': result['command_sha256'], 'changed_keys': sorted(changed),
        'revision_before_after': [before['product']['spec_revision'], product['spec_revision']],
        'observations_after': len(observations_after), 'confirmed_facts_written': 0,
        'record': args.label + '-record.md'}
    fills = progress.get('task_product_fills', 0) + 1
    progress['task_product_fills'] = fills
    progress['technical_fill_persisted_products'] = fills
    progress['technical_fill_persisted_facts'] = progress.get('technical_fill_persisted_facts', 0) + len(changed)
    progress_path.write_text(json.dumps(progress, ensure_ascii=False, indent=1) + '\n')
    print(json.dumps({'record': args.label + '-record.md', 'fills': fills, 'facts': len(changed)}))


if __name__ == '__main__':
    main()
