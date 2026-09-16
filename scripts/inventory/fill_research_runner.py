#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema[format-nongpl]==4.26.0"]
# ///
"""Run one research application end to end as the real actor over SQL.

Subcommands, each writing its artifact into the batch folder:
  simulate  proposal -> simulation.json (authenticated read-only simulation)
  prepare   proposal + simulation -> bundle.json (sealed command and backup)
  register  bundle + readiness receipt (+ audit and review files) -> register.sql
            for scripts/db/query.sh production --write; the fresh simulation
            it embeds is taken again here
  apply     bundle -> receipt.json through apply_product_spec_research_v1,
            exactly one attempt, then receipt verification and a fresh read-back
The reviewed proposal, the readiness receipt and the two hashed artifacts are
inputs; nothing here creates approvals. Modeled on the round-trip test.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/inventory'))
from product_spec_sql_actor import SqlActor  # noqa: E402
from simulate_product_spec_research import RESEARCH, canonical, load_json, simulate  # noqa: E402
from prepare_product_spec_application import prepare, verify_bundle  # noqa: E402
from prepare_product_spec_registration import registration_sql  # noqa: E402
import apply_product_spec_research as client_code  # noqa: E402


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def actor_for(args):
    return SqlActor(args.environment, args.project, args.actor_id, args.folder / 'calls')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['simulate', 'prepare', 'register', 'apply'])
    parser.add_argument('--environment', default='production')
    parser.add_argument('--project', required=True)
    parser.add_argument('--actor-id', required=True)
    parser.add_argument('--folder', type=Path, required=True)
    parser.add_argument('--proposal', type=Path)
    parser.add_argument('--readiness', type=Path)
    parser.add_argument('--audit', type=Path)
    parser.add_argument('--review', type=Path)
    args = parser.parse_args()
    args.folder.mkdir(parents=True, exist_ok=True)
    if args.action == 'simulate':
        proposal = load_json(args.proposal)
        simulation = simulate(proposal, actor_for(args))
        write_json(args.folder / 'simulation.json', simulation)
        print(json.dumps({'issues': simulation['issues'], 'pending': simulation['pending'],
                          'review_record_consistent': simulation['review_record_consistent'],
                          'snapshot_sha256': simulation['snapshot_sha256'],
                          'preview_valid': (simulation.get('server_preview') or {}).get('valid_draft')}, ensure_ascii=False))
    elif args.action == 'prepare':
        proposal = load_json(args.proposal)
        simulation = json.loads((args.folder / 'simulation.json').read_text())
        bundle = prepare(proposal, simulation)
        write_json(args.folder / 'bundle.json', bundle)
        print(json.dumps({'operation_id': bundle['operation_id'], 'command_sha256': bundle['command_sha256'],
                          'bundle_sha256': bundle['bundle_sha256'], 'changes': len(bundle['command']['changes']),
                          'pending': bundle['pending']}))
    elif args.action == 'register':
        bundle = json.loads((args.folder / 'bundle.json').read_text())
        command = verify_bundle(bundle)
        readiness = load_json(args.readiness)
        for path, key in ((args.audit, 'audit_sha256'), (args.review, 'review_sha256')):
            if digest(path) != readiness[key]:
                raise SystemExit('Readiness ' + key + ' does not match ' + path.name)
        if readiness['tenant_id'] != command['tenant_id'] or readiness['project'] != bundle['project']:
            raise SystemExit('Readiness belongs to another tenant or project')
        sql = registration_sql(bundle, readiness, simulate(bundle['proposal'], actor_for(args)))
        (args.folder / 'register.sql').write_text(sql)
        print(json.dumps({'register_sql': str(args.folder / 'register.sql'), 'operation_id': bundle['operation_id']}))
    elif args.action == 'apply':
        bundle = json.loads((args.folder / 'bundle.json').read_text())
        actor = actor_for(args)
        outcome = client_code.apply_or_recover(bundle, actor)
        write_json(args.folder / 'receipt.json', outcome)
        after = actor.read('get_product_spec_research_snapshot_v1', {'p_product_id': bundle['command']['product_id']})
        write_json(args.folder / 'snapshot-after.json', after)
        print(json.dumps({'current_matches_receipt': outcome['current_matches_receipt'],
                          'recovered_existing_receipt': outcome['recovered_existing_receipt'],
                          'result': outcome.get('receipt', {}).get('result'),
                          'after_revision': after['product']['spec_revision'],
                          'after_observations': [(o['definition']['key'], o['fact']['source'], o['fact']['confirmed'])
                                                 for o in after['observations']]}, ensure_ascii=False))


if __name__ == '__main__':
    main()
