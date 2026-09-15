#!/usr/bin/env python3
"""Local-only, two-connection regression through the canonical SQL wrapper."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'supabase/tests/fixtures'
OUTPUT = ROOT / '.tmp/product-spec-publication-concurrency'
WRAPPER = ROOT / 'scripts/db/query.sh'


def query(name, *, sql=None, file=None, json_output=False, write=False):
    command = [str(WRAPPER), 'local']
    command += ['--sql', sql] if sql is not None else ['--file', str(file)]
    if write:
        command.append('--write')
    if json_output:
        command += ['--format', 'json']
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    (OUTPUT / f'{name}.log').write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'{name} failed; see {OUTPUT / (name + ".log")}')
    return json.loads(result.stdout) if json_output else None


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    lock = OUTPUT / 'running'
    lock.mkdir()  # A concurrent invocation cannot own these fixture IDs.
    owns_extension = False
    started = False
    try:
        state = query('before', sql="""select
          exists(select 1 from pg_extension where extname='dblink') as installed,
          exists(select 1 from public.tenants
            where id='c0bf0000-0000-4000-8000-000000000001') as fixture_present""",
                      json_output=True)[0]
        if state['fixture_present']:
            raise RuntimeError('A prior concurrency fixture remains; inspect it before retrying.')
        if not state['installed']:
            query('extension-create', sql='create extension dblink with schema extensions', write=True)
            owns_extension = True
        started = True
        for suffix in ('', '-reverse'):
            query('publication' + suffix,
                  file=FIXTURES / f'row-conditions-review-concurrency{suffix}.sql', write=True)
    finally:
        try:
            if started:
                query('cleanup', file=FIXTURES / 'row-conditions-review-concurrency-cleanup.sql', write=True)
            if owns_extension:
                query('extension-remove', sql='drop extension dblink', write=True)
        finally:
            lock.rmdir()
    print('PASS: both transaction orders, existing/new product and reference; fixtures removed.')


if __name__ == '__main__':
    main()
