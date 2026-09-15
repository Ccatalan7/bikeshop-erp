#!/usr/bin/env python3
"""Capture authenticated, exact product-spec preimages without writing products.

The inventory input is a guarded current product-ID export. Each RPC has its
own MVCC snapshot; the resulting directory is not a database-wide snapshot.
Existing files are validated and retained so an interrupted read can resume.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys

from product_spec_session import ProductSpecSession

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save_new(path, value):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as output:
        json.dump(value, output, ensure_ascii=False, indent=2)
        output.write('\n')


def capture(client, product_id, directory):
    path = directory / (product_id + '.json')
    if path.exists():
        document = json.loads(path.read_text())
        snapshot = document['snapshot']
        origin = 'retained'
    else:
        snapshot = client.read('get_product_spec_research_snapshot_v1',
                               {'p_product_id': product_id})
        document = {'captured_at': datetime.now(timezone.utc).isoformat(),
                    'project': client.project, 'snapshot': snapshot}
        origin = 'captured'
    if (document['project'] != client.project or
            snapshot['actor_id'] != client.actor_id or
            snapshot['product']['id'] != product_id or
            snapshot['editor']['product_id'] != product_id or
            snapshot['product']['tenant_id'] != snapshot['tenant_id'] or
            snapshot['product']['spec_revision'] != snapshot['editor']['revision'] or
            len(snapshot['snapshot_sha256']) != 64 or
            set(snapshot['fingerprints']) != {'product_sha256', 'facts_sha256',
                                              'template_sha256', 'references_sha256'}):
        raise ValueError('Snapshot identity or revision mismatch')
    for observation in snapshot['observations']:
        fact = observation['fact']
        if (fact['subject_id'] != product_id or
                fact['tenant_id'] != snapshot['tenant_id'] or
                len(observation['fact_sha256']) != 64 or
                (fact['value_number'] is not None and
                 not isinstance(fact['value_number'], str)) or
                (fact['value_json_text'] is not None and
                 not isinstance(fact['value_json_text'], str))):
            raise ValueError('Observation identity or exact transport mismatch')
    if origin == 'captured':
        save_new(path, document)
    return {'product_id': product_id, 'file': path.name,
            'file_sha256': digest(path), 'snapshot_sha256': snapshot['snapshot_sha256'],
            'captured_at': document['captured_at'], 'origin': origin,
            'template_id': snapshot['editor']['template_id'],
            'observations': len(snapshot['observations'])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()
    inventory = json.loads(args.inventory.read_text())
    ids = [p['id'] for p in inventory]
    if not ids or len(ids) != len(set(ids)):
        raise ValueError('Inventory must contain unique product IDs')
    # Restrict names before using IDs as filenames.
    from uuid import UUID
    if any(str(UUID(p)) != p for p in ids):
        raise ValueError('Inventory must contain canonical UUIDs')
    args.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    client = ProductSpecSession(ROOT)
    report = {'schema_version': 1, 'project': client.project,
              'actor_id': client.actor_id, 'inventory_sha256': digest(args.inventory),
              'started_at': datetime.now(timezone.utc).isoformat(),
              'expected_products': len(ids), 'snapshots': [], 'errors': [], 'writes': 0,
              'scope': 'One exact MVCC snapshot per product; not a global transaction.'}
    with ThreadPoolExecutor(max_workers=3) as pool:
        jobs = {pool.submit(capture, client, p, args.directory): p for p in ids}
        for future in as_completed(jobs):
            try:
                report['snapshots'].append(future.result())
            except Exception as error:
                # Do not expose transport bodies, credentials or product values.
                report['errors'].append({'product_id': jobs[future],
                                         'error_type': type(error).__name__})
            done = len(report['snapshots']) + len(report['errors'])
            if done % 100 == 0:
                print(json.dumps({'processed': done, 'expected': len(ids),
                                  'errors': len(report['errors'])}), flush=True)
    report['snapshots'].sort(key=lambda r: r['product_id'])
    report['completed_at'] = datetime.now(timezone.utc).isoformat()
    name = 'manifest-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.json'
    save_new(args.directory / name, report)
    print(json.dumps({'manifest': str(args.directory / name),
                      'snapshots': len(report['snapshots']),
                      'errors': len(report['errors']), 'writes': 0}), flush=True)
    return 1 if report['errors'] else 0


if __name__ == '__main__':
    sys.exit(main())
