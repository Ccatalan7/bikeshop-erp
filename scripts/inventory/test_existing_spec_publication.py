#!/usr/bin/env python3
"""Exercise existing-template metadata updates only in local rollback scopes."""
from copy import deepcopy
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'test/scripts'))
# Import the test fixture by path: the two files intentionally have distinct
# responsibilities but their common test name must not shadow the fixture.
import importlib.util
spec = importlib.util.spec_from_file_location(
    'existing_publication_fixture', ROOT / 'test/scripts/test_existing_spec_publication.py')
fixture_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture_module)
from compile_existing_spec_publication import compile_packet, generate_migration
from compile_non_drivetrain_publication import generate_verifier, sql_json


def main():
    data = fixture_module.fixture()
    packet = compile_packet(**data)
    output = ROOT / '.tmp/db/existing-spec-publication-tests'
    output.mkdir(parents=True, exist_ok=True)
    body = generate_migration(packet, source_sha='a'*64).split(
        'begin isolation level repeatable read;', 1)[1].rsplit('commit;', 1)[0]
    before = packet['before']
    seed_templates = deepcopy(before['spec_templates'])
    for t in seed_templates:
        t['contract_version'] -= sum(
            f['template_id'] == t['id'] for f in before['spec_template_fields'])
        if t['contract_version'] < 1:
            raise ValueError('Fixture revision must allow native field triggers')
    seed = 'begin isolation level repeatable read;\n'
    for table, rows in (
            ('spec_definitions', [{k: v for k, v in d.items() if k != 'options'}
                                  for d in packet['reused_definitions']]),
            ('spec_templates', seed_templates),
            ('spec_template_fields', before['spec_template_fields'])):
        for row in rows:
            seed += (f'insert into public.{table} select '
                     f'(jsonb_populate_record(null::public.{table},{sql_json(row)})).*;\n')
    cleanup = 'drop table nd_publication_document, nd_publication_before;\n'
    tid = before['spec_templates'][0]['id']
    fid = before['spec_template_fields'][0]['id']
    did = packet['reused_definitions'][0]['id']
    oid = packet['records']['spec_definition_values'][0]['id']
    tests = {
        'forward_and_exact_replay': (
            seed + body + cleanup + body + generate_verifier(packet, data['cases']) +
            '\nrollback;', None),
        'reject_concurrent_template_edit': (
            seed + f"update public.spec_templates set description='Later edit' where id='{tid}';\n" +
            body, 'Forward publication preimage drift'),
        'reject_concurrent_field_edit': (
            seed + f"update public.spec_template_fields set helper_text='Later edit' where id='{fid}';\n" +
            body, 'Forward publication preimage drift'),
        'reject_newer_contract_version': (
            seed + f"update public.spec_templates set contract_version=contract_version+1 where id='{tid}';\n" +
            body, 'Forward publication preimage drift'),
        'reject_shared_definition_change': (
            seed + f"update public.spec_definitions set description='Later edit' where id='{did}';\n" +
            body, 'Forward publication shared-definition drift'),
        'reject_edited_published_field': (
            seed + body + cleanup +
            f"update public.spec_template_fields set helper_text='Later edit' where id='{fid}';\n" +
            body, 'Forward publication preimage drift'),
        'reject_edited_published_option': (
            seed + body + cleanup +
            f"update public.spec_definition_values set label='Later option' where id='{oid}';\n" +
            body, 'Forward publication preimage drift'),
    }
    for name, (sql, expected_error) in tests.items():
        path = output / (name + '.sql')
        path.write_text(sql)
        result = subprocess.run([str(ROOT/'scripts/db/query.sh'), 'local',
                                 '--file', str(path)], cwd=ROOT,
                                text=True, capture_output=True)
        log = result.stdout + result.stderr
        (output/(name+'.log')).write_text(log)
        if expected_error is None:
            passed = result.returncode == 0 and 'ROLLBACK' in log
        else:
            passed = result.returncode != 0 and expected_error in log
        if not passed:
            raise RuntimeError('Local forward regression failed: ' + name +
                               '; inspect ' + str(output/(name+'.log')))
        print('PASS: ' + name, flush=True)
    print('Seven local rollback regressions passed; no metadata retained.', flush=True)


if __name__ == '__main__':
    main()
