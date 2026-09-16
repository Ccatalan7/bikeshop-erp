#!/usr/bin/env python3
"""Revoke one applied research application as the real actor over SQL.

Runs revoke_product_spec_research_application_v1 through the same guarded
path the applier uses (product_spec_sql_actor.SqlActor): one transaction,
one commit, the receipt written into the batch folder together with the
snapshot read back afterwards. `--dry` calls the RPC inside a rolled-back
transaction first, so the receipt it would produce can be read before
anything changes. A second call returns the stored receipt (replayed).

  python3 scripts/inventory/revoke_product_spec_research.py \
    --project <ref> --actor-id <uuid> --application-id <uuid> \
    --reason 'La fuente resultó equivocada' --folder .tmp/product-spec-catalog/revoke-001 [--dry]
"""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/inventory'))
from product_spec_sql_actor import SqlActor, sql_text  # noqa: E402

REVOKE = 'revoke_product_spec_research_application_v1'
READ_BACK = 'get_product_spec_research_revocation_v1'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--environment', default='production')
    parser.add_argument('--project', required=True)
    parser.add_argument('--actor-id', required=True)
    parser.add_argument('--application-id', required=True)
    parser.add_argument('--reason', required=True)
    parser.add_argument('--folder', type=Path, required=True)
    parser.add_argument('--dry', action='store_true', help='rolled-back call only')
    args = parser.parse_args()
    if len(args.reason.strip()) < 8:
        raise SystemExit('the reason must say why (at least 8 characters)')
    actor = SqlActor(args.environment, args.project, args.actor_id, args.folder / 'calls')
    expression = 'public.' + REVOKE + '(' + sql_text(args.application_id) + '::uuid,' + sql_text(args.reason) + ')'
    actor.calls.append(REVOKE)
    name = f'call-{len(actor.calls):03}-{REVOKE}' + ('-dry' if args.dry else '')
    result = actor._run(name, expression, commit=not args.dry)
    (args.folder / ('revocation-dry.json' if args.dry else 'revocation.json')).write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    summary = {'dry': args.dry, 'applied': result.get('applied'), 'replayed': result.get('replayed'),
               'restored': result.get('restored_fact_ids'), 'deleted': result.get('deleted_fact_ids'),
               'kept': result.get('kept_fact_ids'), 'missing': result.get('missing_fact_ids'),
               'identity_restored': result.get('identity_restored'), 'revision': result.get('revision')}
    if not args.dry:
        actor.calls.append(READ_BACK)
        stored = actor._run(f'call-{len(actor.calls):03}-{READ_BACK}',
                            'public.' + READ_BACK + '(' + sql_text(args.application_id) + '::uuid)', commit=False)
        (args.folder / 'revocation-readback.json').write_text(json.dumps(stored, ensure_ascii=False, indent=2) + '\n')
        summary['readback_matches'] = stored is not None and stored.get('result') == {k: v for k, v in result.items() if k != 'replayed'} | {'replayed': False}
        if result.get('product_id'):
            after = actor.read('get_product_spec_research_snapshot_v1', {'p_product_id': result['product_id']})
            (args.folder / 'snapshot-after-revocation.json').write_text(json.dumps(after, ensure_ascii=False, indent=2) + '\n')
            summary['after_revision'] = after['product']['spec_revision']
            summary['after_observations'] = [(o['definition']['key'], o['fact']['source'], o['fact']['confirmed'])
                                             for o in after['observations']]
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == '__main__':
    main()
