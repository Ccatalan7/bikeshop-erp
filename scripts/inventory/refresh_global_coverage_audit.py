#!/usr/bin/env python3
"""Refresh the structural coverage audit of every product and template.

Read-only. One MVCC statement captures the tenant's specification bundle
(scripts/inventory/product_spec_legacy_export.sql); bounded batches of 30
products evaluate every mapped product with the deployed validator
(scripts/inventory/product_spec_server_audit.sql); audit_product_spec_coverage
turns both into coverage rows. Nothing is written to the ERP. The result is a
structural count: it does not adjudicate identity, assignment correctness,
compatibility or research completeness, and it never enables bulk fill.
"""
import argparse
import concurrent.futures
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'docs/development/product-specs-research-2026-09-05'
EXPORT = ROOT / 'scripts/inventory/product_spec_legacy_export.sql'
EVALUATION = ROOT / 'scripts/inventory/product_spec_server_audit.sql'
QUERY = ROOT / 'scripts/db/query.sh'
BATCH = 30
sys.path.insert(0, str(ROOT / 'scripts/inventory'))
from audit_product_spec_coverage import audit  # noqa: E402


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_private(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    os.chmod(path, 0o600)


def read_json(environment, path):
    run = subprocess.run([str(QUERY), environment, '--file', str(path), '--format', 'json',
                          '--max-rows', '0'], cwd=ROOT, capture_output=True, text=True, timeout=120)
    if run.returncode:
        raise RuntimeError(f'Read-only statement failed for {path.name}: {run.stderr[-600:]}')
    return json.loads(run.stdout)


def capture_snapshot(environment, folder):
    path = folder / 'snapshot.json'
    if path.exists():
        return json.loads(path.read_text())
    rows = read_json(environment, EXPORT)
    if len(rows) != 1 or 'snapshot' not in rows[0]:
        raise RuntimeError('The export statement must return exactly one snapshot row')
    snapshot = rows[0]['snapshot']
    write_private(path, snapshot)
    return snapshot


def evaluate(environment, folder, snapshot):
    ids = sorted(str(uuid.UUID(row['id'])) for row in snapshot['tables']['products'])
    base = EVALUATION.read_text()
    anchor = 'order by p.id;'
    if base.count(anchor) != 1:
        raise RuntimeError('product_spec_server_audit.sql lost its order-by anchor')
    batches = [ids[i:i + BATCH] for i in range(0, len(ids), BATCH)]

    def read_batch(item):
        index, products = item
        path = folder / f'batch-{index:03}.sql'
        path.write_text(base.replace(anchor, 'and p.id in (' + ','.join(
            "'" + value + "'" for value in products) + ') order by p.id;'))
        rows = read_json(environment, path)
        write_private(folder / f'batch-{index:03}.json', rows)
        return rows

    rows = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for index, result in enumerate(pool.map(read_batch, enumerate(batches)), 1):
            rows.extend(result)
            if index % 10 == 0 or index == len(batches):
                print(f'Read-only evaluation: {index}/{len(batches)} batches', flush=True)
    write_private(folder / 'server-evaluation.json', rows)
    return rows


def family_table(result):
    products = {}
    for row in result['products']:
        products.setdefault(row['template_id'], []).append(row)
    table = []
    for template in result['templates']:
        if not template['active']:
            continue
        own = products.get(template['id'], [])
        table.append({
            'key': template['key'], 'family': template['family'],
            'contract_version': template['contract_version'],
            'products': len(own),
            'products_with_facts': sum(bool(p['facts_count']) for p in own),
            'products_with_pending_issues': sum(bool(p['server_issues']) for p in own),
            'products_with_blocking_issues': sum(
                any(i.get('blocking', True) for i in p['server_issues'] or []) for p in own),
            'products_with_facts_outside_template': sum(bool(p['facts_outside_template']) for p in own),
        })
    return table


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--environment', default='production')
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--previous', type=Path, help='earlier global-coverage-summary to diff against')
    parser.add_argument('--summary-output', type=Path, required=True)
    args = parser.parse_args()
    folder = args.directory
    folder.mkdir(parents=True, exist_ok=True)
    snapshot = capture_snapshot(args.environment, folder)
    fingerprint = snapshot.get('operational_fingerprint', {})
    print(json.dumps({'captured_at': snapshot['captured_at'], 'products': fingerprint.get('products'),
                      'member_profiles': fingerprint.get('member_profiles')}), flush=True)
    rows = evaluate(args.environment, folder, snapshot)
    result = audit(snapshot, rows)
    result['snapshot_sha256'] = digest(folder / 'snapshot.json')
    result['server_evaluation_sha256'] = digest(folder / 'server-evaluation.json')
    write_private(folder / 'coverage.json', result)
    families = family_table(result)
    write_private(folder / 'families.json', families)
    summary = {
        'format_version': 1, 'scope': result['scope'], 'snapshot_at': result['snapshot_at'],
        'summary': result['summary'],
        'snapshot_sha256': result['snapshot_sha256'],
        'server_evaluation_sha256': result['server_evaluation_sha256'],
        'audit_kind': 'structural_coverage_only', 'semantic_completion': None,
        'source': {'snapshot': 'single MVCC statement (product_spec_legacy_export.sql)',
                   'server_evaluation': f'{-(-len(rows) // BATCH)} bounded read-only batches of {BATCH}, '
                                        'exact product revision/updated_at/template/version check, '
                                        f"{result['summary']['stale_server_evaluations']} stale evaluations"},
        'scope_limit': 'Does not adjudicate product identity, compatibility, assignment correctness, or research completeness.',
        'task_product_fills': 0,
        'operational_fingerprint': fingerprint,
        'families': families,
        'unmapped_categories': result['unmapped_categories'],
    }
    if args.previous:
        previous = json.loads(args.previous.read_text())
        summary['previous'] = {'file': args.previous.name, 'snapshot_at': previous['snapshot_at'],
                               'delta': {k: (result['summary'][k] - previous['summary'][k])
                                         for k, v in previous['summary'].items()
                                         if isinstance(v, (int, float)) and not isinstance(v, bool)
                                         and isinstance(result['summary'].get(k), (int, float))}}
    args.summary_output.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result['summary'], indent=2), flush=True)
    if args.previous:
        print(json.dumps(summary['previous'], indent=2), flush=True)


if __name__ == '__main__':
    main()
