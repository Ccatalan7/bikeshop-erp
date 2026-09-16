#!/usr/bin/env python3
"""Run name-reading candidates through `record_product_spec_reading_v1` as the actor.

Input is the candidates file of spec_name_reading_rules.py. Every candidate is
one RPC call made as the real authenticated actor over scripts/db/query.sh, in
chunks of products inside one transaction each. `--mode dry` ends every chunk
with rollback and reports the live verdicts without persisting anything;
`--mode commit` ends with commit. The RPC is the gate: it re-checks the quote,
the vocabulary, the existing facts and the product coherence guard, and it
writes the `name_reading` fact plus its reading receipt. This runner only
sequences the calls, keeps the verdict of each one and summarises them.

Usage:
  fill_name_readings.py --candidates candidates.json --actor <uuid> --output <dir> \
      [--environment production] [--mode dry|commit] [--chunk 25] [--families hub,rim]
"""
import argparse
import collections
import csv
import io
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
QUERY = ROOT / 'scripts/db/query.sh'
MARKER = 'NR_JSON:'
RPC = 'public.record_product_spec_reading_v1'

csv.field_size_limit(1 << 30)


def sql_text(value):
    if not isinstance(value, str) or '\x00' in value:
        raise ValueError('SQL text must be a NUL-free string')
    return "'" + value.replace("'", "''") + "'"


def json_value(value):
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    return json.dumps(value, ensure_ascii=False)


def chunk_sql(actor_id, model, rows, *, commit):
    claims = json.dumps({'sub': actor_id, 'role': 'authenticated'}, sort_keys=True, separators=(',', ':'))
    lines = ['begin;', 'set local role authenticated;',
             'set local request.jwt.claim.sub=' + sql_text(actor_id) + ';',
             'set local request.jwt.claims=' + sql_text(claims) + ';']
    for i, row in enumerate(rows):
        call = (RPC + '(' + sql_text(row['product_id']) + '::uuid, ' + sql_text(row['field_key']) + ', '
                + sql_text(json_value(row['value'])) + '::jsonb, ' + sql_text(row['quote']) + ', ' + sql_text(model) + ')')
        lines.append("select '" + MARKER + "'||jsonb_build_object('i', " + str(i)
                     + ", 'product_id', " + sql_text(row['product_id']) + ", 'field_key', " + sql_text(row['field_key'])
                     + ", 'verdict', " + call + ')::text as reading;')
    lines.append('commit;' if commit else 'rollback;')
    return '\n'.join(lines) + '\n'


def run_chunk(environment, path):
    arguments = [str(QUERY), environment, '--write', '--file', str(path), '--format', 'csv', '--max-rows', '0']
    env = dict(os.environ)
    if environment == 'production':
        env['VINABIKE_DB_WRITE_CONFIRM'] = 'production'
    run = subprocess.run(arguments, cwd=ROOT, capture_output=True, text=True, timeout=300, env=env)
    path.with_suffix('.log').write_text(run.stdout + run.stderr)
    if run.returncode or 'ERROR:' in run.stderr:
        return None, run.stderr.strip()[-800:]
    results = []
    for row in csv.reader(io.StringIO(run.stdout)):
        if row and row[0].startswith(MARKER):
            results.append(json.loads(row[0][len(MARKER):]))
    return results, None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--candidates', required=True)
    parser.add_argument('--actor', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--environment', default='production')
    parser.add_argument('--mode', choices=('dry', 'commit'), default='dry')
    parser.add_argument('--chunk', type=int, default=25)
    parser.add_argument('--families', default='')
    parser.add_argument('--model', default='rules:spec_name_reading_rules.py')
    args = parser.parse_args()

    families = {f for f in args.families.split(',') if f}
    candidates = json.loads(Path(args.candidates).read_text())['candidates']
    if families:
        candidates = [c for c in candidates if c['family'] in families]
    by_product = collections.OrderedDict()
    for c in candidates:
        by_product.setdefault(c['product_id'], []).append(c)
    products = list(by_product)
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)

    verdicts, failures = [], []
    for n in range(0, len(products), args.chunk):
        rows = [c for pid in products[n:n + args.chunk] for c in by_product[pid]]
        name = f'{args.mode}-chunk-{n // args.chunk + 1:03}'
        path = output / (name + '.sql')
        path.write_text(chunk_sql(args.actor, args.model, rows, commit=args.mode == 'commit'))
        results, error = run_chunk(args.environment, path)
        if error is not None:
            failures.append({'chunk': name, 'products': len(products[n:n + args.chunk]), 'error': error})
            print(f'{name}: FAILED {error[-200:]}')
            continue
        if len(results) != len(rows):
            failures.append({'chunk': name, 'error': f'expected {len(rows)} results, got {len(results)}'})
            print(f'{name}: result count mismatch')
            continue
        for r in results:
            row = rows[r['i']]
            verdicts.append({**{k: row[k] for k in ('product_id', 'family', 'name', 'field_key', 'value', 'quote')},
                             'chunk': name, **r['verdict']})
        counts = collections.Counter(v['verdict'] for v in verdicts if v['chunk'] == name)
        print(f'{name}: {len(rows)} calls -> ' + ', '.join(f'{k} {v}' for k, v in sorted(counts.items())))

    summary = {
        'mode': args.mode, 'environment': args.environment, 'products': len(products), 'calls': len(candidates),
        'verdicts': dict(collections.Counter(v['verdict'] for v in verdicts)),
        'rejections': dict(collections.Counter(v.get('reason', '') for v in verdicts if v['verdict'] == 'rejected')),
        'per_family': {family: dict(collections.Counter(v['verdict'] for v in verdicts if v['family'] == family))
                       for family in sorted({v['family'] for v in verdicts})},
        'failures': failures,
    }
    (output / f'{args.mode}-verdicts.json').write_text(json.dumps({'summary': summary, 'verdicts': verdicts},
                                                                   ensure_ascii=False, indent=1) + '\n')
    print(json.dumps(summary, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    main()
