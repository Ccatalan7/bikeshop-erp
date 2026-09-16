#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema[format-nongpl]==4.26.0"]
# ///
"""Local SQL -> Python review/registration -> SQL application -> receipt check.

Only synthetic fixtures, exclusively through query.sh local. SQL authenticated
roles are local test principals, not fabricated hosted JWTs. The HTTP transport
requires separate tests. Owned fixtures/candidate objects are removed finally.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import apply_product_spec_research as client_code
from prepare_product_spec_application import prepare
from prepare_product_spec_registration import registration_sql, sql_text
from simulate_product_spec_research import canonical, proposal_hash, simulate

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / '.tmp/product-spec-application-roundtrip'
ACTOR = 'f1112300-0000-4000-8000-000000000091'
TENANT = 'f1112300-0000-4000-8000-000000000001'
PRODUCT = 'f1112300-0000-4000-8000-000000000020'
PROJECT = 'abcdefghijklmnopqrst'
WRAPPER = ROOT / 'scripts/db/query.sh'


def query(name, sql, *, result=False):
    path = OUTPUT / (name + '.sql')
    path.write_text(sql)
    run = subprocess.run([str(WRAPPER), 'local', '--write', '--file', str(path)],
                         cwd=ROOT, capture_output=True, text=True, timeout=70)
    (OUTPUT / (name + '.log')).write_text(run.stdout + run.stderr)
    if run.returncode or 'not ok ' in run.stdout or 'ERROR:' in run.stderr:
        raise RuntimeError('Local check failed: ' + name)
    if result:
        values = [json.loads(line.strip().removeprefix('RESEARCH_JSON:'))
                  for line in run.stdout.splitlines() if line.strip().startswith('RESEARCH_JSON:')]
        if len(values) != 1:
            raise RuntimeError('Expected one exact JSON result: ' + name)
        return values[0]


def actor_sql(expression, *, commit=False):
    return ("begin; set local role authenticated; set local request.jwt.claim.sub=" + sql_text(ACTOR)
            + "; set local request.jwt.claims=" + sql_text(canonical({'sub': ACTOR, 'role': 'authenticated'}).decode())
            + "; select 'RESEARCH_JSON:'||(" + expression + ")::text; "
            + ('commit;' if commit else 'rollback;'))


class LocalSqlClient:
    actor_id, project = ACTOR, PROJECT

    def __init__(self):
        self.calls = []

    def read(self, command, params):
        if command == 'get_product_spec_research_snapshot_v1':
            args = sql_text(params['p_product_id']) + '::uuid'
        elif command == 'preview_product_spec_research_v1':
            args = ','.join((sql_text(params['p_product_id']) + '::uuid',
                sql_text(params['p_expected_snapshot_sha256']),
                sql_text(canonical(params['p_identity_patch']).decode()) + '::jsonb',
                sql_text(canonical(params['p_values_patch']).decode()) + '::jsonb',
                'null' if params['p_reference_id'] is None else sql_text(params['p_reference_id'])))
        else:
            raise ValueError('Unexpected local read command')
        self.calls.append(command)
        return query(f'call-{len(self.calls):03}', actor_sql('public.' + command + '(' + args + ')'), result=True)

    def application(self, command, operation):
        if command not in (client_code.APPLY, client_code.STATUS, client_code.RECEIPT):
            raise ValueError('Unexpected local application command')
        self.calls.append(command)
        return query(f'call-{len(self.calls):03}', actor_sql('public.' + command + '(' + sql_text(operation)
                     + '::uuid)', commit=command == client_code.APPLY), result=True)


def reviewed_proposal(snapshot):
    content = b'Synthetic roundtrip evidence. No bicycle model or actual compatibility claim.'
    (OUTPUT / 'evidence.txt').write_bytes(content)
    observations = {o['definition']['key']: o for o in snapshot['observations']}
    delta = {'research_option': '02', 'research_rows': {'schema_version': 1, 'rows': [
        {'id': 'new-row', 'values': {'length': '0.200000000000000001'}, 'sources': ['https://example.invalid/synthetic']}]}}
    facts = []
    for key, value in delta.items():
        observation = observations[key]
        facts.append({'key': key, 'current': {'value': snapshot['editor']['values'][key],
            'source': observation['fact']['source'], 'confirmed': observation['fact']['confirmed'],
            'fact_id': observation['fact']['id'], 'fact_sha256': observation['fact_sha256']},
            'proposed': value, 'unit': None, 'method': 'Synthetic document', 'origin': 'research',
            'evidence': ['synthetic'], 'scope': 'Synthetic test only', 'reason': 'Roundtrip regression'})
    proposal = {'schema_version': 2, 'product_id': PRODUCT, 'researcher': 'codex', 'status': 'reviewed',
        'based_on': {'snapshot_sha256': snapshot['snapshot_sha256'], 'tenant_id': TENANT,
            'fingerprints': snapshot['fingerprints'], 'spec_revision': snapshot['product']['spec_revision'],
            'updated_at': snapshot['product']['updated_at'], 'template_id': snapshot['editor']['template_id'],
            'contract_version': snapshot['editor']['contract_version']},
        'identity': [{'field': 'model', 'current': snapshot['product']['model'],
            'proposed': "Fixture ' slash \\ $registration$ $$ ; COMMIT; --", 'evidence': ['synthetic'],
            'reason': 'SQL text quoting regression'}], 'reference': None, 'facts': facts,
        'evidence': [{'id': 'synthetic', 'kind': 'oem_page', 'source': 'https://example.invalid/synthetic',
            'locator': 'Fixture', 'consulted_on': '2026-09-07', 'scope': 'Synthetic',
            'finding': 'No product claim', 'sha256': hashlib.sha256(content).hexdigest(), 'artifact_path': 'evidence.txt'}],
        'conflicts': [], 'review': {'by': 'claude', 'verdict': 'accepted', 'date': '2026-09-07',
            'reviewed_proposal_sha256': None, 'notes': 'Synthetic independent review record'}}
    proposal['review']['reviewed_proposal_sha256'] = proposal_hash(proposal)
    return proposal


def cleanup_sql(constraint, installed=False):
    # All IDs are the known seed fixture, guarded absent before setup. Do not
    # use CASCADE to drop candidate objects or disable business triggers.
    objects = '' if installed else """drop function public.get_product_spec_research_application_status_v1(uuid);
drop function public.get_product_spec_research_receipt_v1(uuid);
drop function public.apply_product_spec_research_v1(uuid);
drop table public.product_spec_research_receipts;
drop table public.product_spec_research_applications;
drop table public.product_spec_research_readiness;
"""
    rows = f"""delete from public.product_spec_research_receipts where tenant_id in ('{TENANT}','f1112300-0000-4000-8000-000000000002');
delete from public.product_spec_research_applications where tenant_id in ('{TENANT}','f1112300-0000-4000-8000-000000000002');
delete from public.product_spec_research_readiness where tenant_id in ('{TENANT}','f1112300-0000-4000-8000-000000000002');
""" if installed else ''
    restore = '' if installed else f"""alter table public.spec_facts drop constraint spec_facts_source_known;
alter table public.spec_facts add constraint spec_facts_source_known {constraint};
"""
    return f"""begin;
set local request.jwt.claims='{{}}'; set local request.jwt.claim.sub='';
{objects}{rows}delete from public.spec_facts where tenant_id in ('{TENANT}','f1112300-0000-4000-8000-000000000002');
delete from public.product_spec_save_receipts where tenant_id in ('{TENANT}','f1112300-0000-4000-8000-000000000002');
delete from public.products where tenant_id in ('{TENANT}','f1112300-0000-4000-8000-000000000002');
delete from public.spec_template_fields where template_id='f1112300-0000-4000-8000-000000000050';
delete from public.spec_templates where id='f1112300-0000-4000-8000-000000000050';
delete from public.spec_definitions where id in ('f1112300-0000-4000-8000-000000000051',
 'f1112300-0000-4000-8000-000000000052','f1112300-0000-4000-8000-000000000053','f1112300-0000-4000-8000-000000000054');
delete from auth.users where id='{ACTOR}';
delete from public.tenants where id in ('{TENANT}','f1112300-0000-4000-8000-000000000002');
set constraints all immediate;
{restore}set constraints all immediate;
commit;
"""


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    lock = OUTPUT / 'running'
    lock.mkdir()
    started = False
    installed = False
    owns_dblink = False
    try:
        state = query('before', "select 'RESEARCH_JSON:'||jsonb_build_object("
            "'objects',to_regclass('public.product_spec_research_readiness') is not null "
            "or to_regprocedure('public.apply_product_spec_research_v1(uuid)') is not null,"
            "'fixture',exists(select 1 from public.tenants where id in ('" + TENANT
            + "','f1112300-0000-4000-8000-000000000002')),"
            "'dblink',exists(select 1 from pg_extension where extname='dblink'),"
            "'constraint',(select pg_get_constraintdef(oid) from pg_constraint "
            "where conrelid='public.spec_facts'::regclass and conname='spec_facts_source_known'))::text;", result=True)
        if state['fixture'] or not state['constraint']:
            raise RuntimeError('Prior fixtures exist; refusing to overwrite them')
        # Since 20260916140000 the applier is published; a database that has it
        # keeps its objects and constraint, and only the synthetic seed is owned.
        installed = bool(state['objects'])
        if installed and "'research'" not in state['constraint']:
            raise RuntimeError('Installed applier without the research source; refusing to continue')
        # Reuse the real SQL test seed and real save command, preserving the
        # baseline assertions. Only the local transaction ending differs.
        seed = (ROOT / 'supabase/tests/product_spec_research_application_candidate.sql').read_text()
        marker = 'set constraints all deferred;'
        if seed.count(marker) != 1:
            raise RuntimeError('SQL fixture anchor changed')
        seed = seed.split(marker)[0]
        anchor = '\\ir ../../scripts/inventory/sql/product_spec_application_candidate.sql'
        if seed.count(anchor) != 1:
            raise RuntimeError('SQL fixture candidate anchor changed')
        seed = seed.replace(anchor, '' if installed else
                            '\\ir ' + str(ROOT / 'scripts/inventory/sql/product_spec_application_candidate.sql'))
        # The psql conditional around that anchor only matters under psql -f.
        seed = seed.replace('\\if :research_candidate_needed\n', '').replace('\\endif\n', '')
        # Optional reading-column prerequisites belong to rollback tests. This
        # committed seed does not modify unrelated historical schema columns.
        seed = seed.replace('\\ir fixtures/product_spec_binding_prerequisites.sql', '')
        # The candidate and fixtures either commit together or do not exist.
        query('setup', seed + '\nset constraints all immediate; commit;')
        started = True
        local = LocalSqlClient()
        snapshot = local.read('get_product_spec_research_snapshot_v1', {'p_product_id': PRODUCT})
        proposal = reviewed_proposal(snapshot)
        simulation = simulate(proposal, local, OUTPUT)
        bundle = prepare(proposal, simulation, OUTPUT)
        (OUTPUT / 'bundle.json').write_bytes(canonical(bundle))
        gate = {'schema_version': 1, 'project': PROJECT, 'tenant_id': TENANT,
            'id': 'f1112300-0000-4000-8000-000000000081', 'audit_sha256': 'a' * 64,
            'review_sha256': 'b' * 64, 'closed_at': '2026-09-07T10:00:00+00:00', 'enabled': True}
        query('synthetic-readiness', "insert into public.product_spec_research_readiness "
            "(id,tenant_id,audit_sha256,review_sha256,closed_at,enabled) values ("
            + ','.join(sql_text(gate[k]) for k in ('id', 'tenant_id', 'audit_sha256', 'review_sha256', 'closed_at'))
            + ',true);')
        sql = registration_sql(bundle, gate, simulate(proposal, local, OUTPUT), OUTPUT)
        query('register', sql)
        query('register-exact-replay', sql)
        if not state['dblink']:
            query('dblink-create', 'create extension dblink with schema extensions;')
            owns_dblink = True
        race = (ROOT / 'scripts/inventory/sql/product_spec_application_race.sql').read_text()
        if ':application_id' not in race:
            raise RuntimeError('Race fixture lost its operation parameter')
        query('two-session-races', race.replace(':application_id', sql_text(bundle['operation_id'])))
        if local.read('get_product_spec_research_snapshot_v1', {'p_product_id': PRODUCT}) != snapshot:
            raise RuntimeError('Rollback race probe altered its complete preimage')
        applied = client_code.apply_or_recover(bundle, local, OUTPUT)
        if not applied['current_matches_receipt'] or applied['recovered_existing_receipt']:
            raise RuntimeError('Applied receipt does not match the current complete state')
        (OUTPUT / 'receipt.json').write_bytes(canonical(applied))
        calls = len(local.calls)
        # Later edits and evidence availability must not prevent recovering
        # the committed receipt or cause a stale research write to be repeated.
        query('later-change', f"update public.products set cost=51 where id='{PRODUCT}' and tenant_id='{TENANT}'; "
              "update public.product_spec_research_readiness set enabled=false;")
        (OUTPUT / 'evidence.txt').unlink()
        recovered = client_code.apply_or_recover(bundle, local, OUTPUT, recover_only=True)
        if (recovered['current_matches_receipt'] or not recovered['recovered_existing_receipt']
                or client_code.APPLY in local.calls[calls:]):
            raise RuntimeError('Receipt recovery repeated a write or hid a later edit')
        # Independent receipt verifier must detect monetary or provenance
        # tampering even when the caller recomputes the enclosing product hash.
        receipt = deepcopy(applied['receipt'])
        text = receipt['after_product_text'].replace('"cost": 50', '"cost": 51')
        if text == receipt['after_product_text']:
            raise RuntimeError('Monetary mutation fixture no longer matches the SQL projection')
        receipt['after_product_text'] = text
        receipt['after_snapshot']['fingerprints']['product_sha256'] = hashlib.sha256(text.encode()).hexdigest()
        try:
            client_code.verify_receipt(bundle, receipt)
        except ValueError:
            pass
        else:
            raise RuntimeError('Receipt verifier accepted a changed monetary column')
    finally:
        try:
            if started:
                query('cleanup', cleanup_sql(state['constraint'], installed))
                final = query('cleanup-readback', "select 'RESEARCH_JSON:'||jsonb_build_object("
                    "'removed',(to_regclass('public.product_spec_research_readiness') is null) = "
                    + ('false' if installed else 'true') + " and not exists("
                    "select 1 from public.tenants where id='" + TENANT + "'),"
                    "'constraint',(select pg_get_constraintdef(oid) from pg_constraint "
                    "where conrelid='public.spec_facts'::regclass and conname='spec_facts_source_known'))::text;", result=True)
                if not final['removed'] or final['constraint'] != state['constraint']:
                    raise RuntimeError('Local fixture cleanup did not restore the exact constraint')
            if owns_dblink:
                query('dblink-remove', 'drop extension dblink;')
        finally:
            lock.rmdir()
    print('PASS: fresh SQL snapshot/preview, Python review, quoted exact registration/replay, '
          'three two-session contention schedules, authenticated-role SQL apply, complete receipt, '
          'later-edit recovery, monetary tamper rejection and fixture/constraint cleanup.')


if __name__ == '__main__':
    main()
