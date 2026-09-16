#!/usr/bin/env python3
"""Capture one product's fresh research snapshot as the actor and summarize it.

Read-only. Saves the exact snapshot JSON for a fill batch folder and prints
what a proposal must match: template, contract version, revision, updated_at,
fingerprints, the template roles of the keys a proposal names, the references
with their facts, and the existing observations.
"""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/inventory'))
from product_spec_sql_actor import SqlActor  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--environment', default='production')
    parser.add_argument('--project', required=True)
    parser.add_argument('--actor-id', required=True)
    parser.add_argument('--product-id', required=True)
    parser.add_argument('--folder', type=Path, required=True)
    parser.add_argument('--keys', default='', help='comma-separated proposal keys to report')
    args = parser.parse_args()
    actor = SqlActor(args.environment, args.project, args.actor_id, args.folder / 'calls')
    snapshot = actor.read('get_product_spec_research_snapshot_v1', {'p_product_id': args.product_id})
    (args.folder / 'snapshot-fresh.json').write_text(json.dumps(snapshot, ensure_ascii=False, indent=1) + '\n')
    product, editor = snapshot['product'], snapshot['editor']
    template = editor.get('template') or {}
    roles = (template.get('form_contract') or {}).get('roles') or {}
    fields = {f['spec_definitions']['key']: f['spec_definitions'] for f in template.get('fields', [])}
    summary = {
        'actor_id': snapshot.get('actor_id'), 'tenant_id': snapshot.get('tenant_id'),
        'snapshot_sha256': snapshot['snapshot_sha256'], 'fingerprints': snapshot['fingerprints'],
        'product': {k: product.get(k) for k in ('id', 'sku', 'name', 'brand', 'model', 'manufacturer_sku', 'gtin',
                                                'spec_revision', 'updated_at', 'spec_reference_id', 'product_type')},
        'template_key': template.get('key'), 'template_id': editor.get('template_id'),
        'contract_version': editor.get('contract_version'),
        'keys': {k: {'present': k in fields, 'role': roles.get(k), 'data_type': fields.get(k, {}).get('data_type'),
                     'unit': fields.get(k, {}).get('unit'), 'current': editor['values'].get(k)}
                 for k in [k for k in args.keys.split(',') if k]},
        'observations': [(o['definition']['key'], o['fact']['source'], o['fact']['confirmed'])
                         for o in snapshot['observations']],
        'references': [{'id': r['id'], 'label': r.get('label') or r.get('name'), 'facts': r.get('facts')}
                       for r in snapshot['references']],
        'editor_values_keys': sorted(editor['values'].keys()),
    }
    (args.folder / 'snapshot-summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=1) + '\n')
    print(json.dumps(summary, ensure_ascii=False, indent=1)[:6000])


if __name__ == '__main__':
    main()
