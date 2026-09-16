#!/usr/bin/env python3
"""Run the research read and application commands as the real actor over SQL.

The HTTP transport (product_spec_session.py, apply_product_spec_research.py)
needs the live desktop app token. When that token is unavailable the same
commands run through scripts/db/query.sh as the actor: every statement sets
`role authenticated` and the actor's JWT claims inside one transaction, so
auth.uid() and user_tenant_id() resolve exactly as they would over HTTP. Reads
end in rollback; only the apply command commits, and only once. Nothing here
bypasses the applier: readiness, registration, preimage and receipt checks
still run inside the RPC. Modeled on the local client of the round-trip test.
"""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
QUERY = ROOT / 'scripts/db/query.sh'
STATUS = 'get_product_spec_research_application_status_v1'
RECEIPT = 'get_product_spec_research_receipt_v1'
APPLY = 'apply_product_spec_research_v1'
READS = {'get_product_spec_research_snapshot_v1', 'preview_product_spec_research_v1'}
MARKER = 'RESEARCH_JSON:'


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def sql_text(value):
    if not isinstance(value, str) or '\x00' in value:
        raise ValueError('SQL text must be a NUL-free string')
    return "'" + value.replace("'", "''") + "'"


class SqlActor:
    """Reads and applications as one authenticated actor of one hosted project."""

    def __init__(self, environment, project, actor_id, output):
        self.environment, self.project, self.actor_id = environment, project, actor_id
        self.output = Path(output)
        self.output.mkdir(parents=True, exist_ok=True)
        self.calls = []

    def _run(self, name, expression, *, commit):
        claims = canonical({'sub': self.actor_id, 'role': 'authenticated'})
        # Hosted reads run inside the wrapper's own read-only transaction, so the
        # file must not open or close one; a write opens its own and commits once.
        body = ('set local role authenticated;\nset local request.jwt.claim.sub=' + sql_text(self.actor_id)
                + ';\nset local request.jwt.claims=' + sql_text(claims)
                + ";\nselect '" + MARKER + "'||(" + expression + ')::text as research_result;\n')
        sql = ('begin;\n' + body + 'commit;\n') if commit else body
        path = self.output / (name + '.sql')
        path.write_text(sql)
        arguments = [str(QUERY), self.environment] + (['--write'] if commit else []) + [
            '--file', str(path), '--format', 'csv', '--max-rows', '0']
        environment = dict(os.environ)
        if commit and self.environment == 'production':
            environment['VINABIKE_DB_WRITE_CONFIRM'] = 'production'
        run = subprocess.run(arguments, cwd=ROOT, capture_output=True, text=True, timeout=180, env=environment)
        (self.output / (name + '.log')).write_text(run.stdout + run.stderr)
        if run.returncode or 'ERROR:' in run.stderr:
            raise RuntimeError('Actor command failed: ' + name + ': ' + run.stderr.strip()[-600:])
        values = []
        import csv
        import io
        csv.field_size_limit(1 << 30)
        for row in csv.reader(io.StringIO(run.stdout)):
            if row and row[0].startswith(MARKER):
                values.append(json.loads(row[0][len(MARKER):]))
        if len(values) != 1:
            raise RuntimeError('Expected one exact JSON result: ' + name)
        return values[0]

    def read(self, command, params):
        if command not in READS or not isinstance(params, dict):
            raise ValueError('Unexpected read command')
        if command == 'get_product_spec_research_snapshot_v1':
            arguments = sql_text(params['p_product_id']) + '::uuid'
        else:
            arguments = ','.join((sql_text(params['p_product_id']) + '::uuid',
                                  sql_text(params['p_expected_snapshot_sha256']),
                                  sql_text(canonical(params['p_identity_patch'])) + '::jsonb',
                                  sql_text(canonical(params['p_values_patch'])) + '::jsonb',
                                  'null' if params['p_reference_id'] is None else sql_text(params['p_reference_id'])))
        self.calls.append(command)
        return self._run(f'call-{len(self.calls):03}-{command}', 'public.' + command + '(' + arguments + ')', commit=False)

    def application(self, command, operation):
        if command not in (APPLY, STATUS, RECEIPT):
            raise ValueError('Unexpected application command')
        self.calls.append(command)
        return self._run(f'call-{len(self.calls):03}-{command}',
                         'public.' + command + '(' + sql_text(operation) + '::uuid)', commit=command == APPLY)
