#!/usr/bin/env python3
"""Run the publication and drift regressions only in local rollback scopes."""
from copy import deepcopy
import json
import subprocess

from compile_mobility_accessories_publication import (
    ROOT, CATALOG_SHA, compile_packet, generate_migration, generate_verifier)
from compile_non_drivetrain_publication import sql_json

OUTPUT = ROOT / '.tmp/db/mobility-accessories-publication-tests'
WRAPPER = ROOT / 'scripts/db/query.sh'


def legacy_only_field(packet, definition):
    """A local legacy unit is irrelevant only when no active use reads it."""
    templates = {t['id']: t for t in packet['records']['spec_templates']}
    uses = [f for f in packet['records']['spec_template_fields']
            if f['spec_definition_id'] == definition['id']]
    return bool(uses) and all(
        templates[f['template_id']]['form_contract']['roles'].get(definition['key']) == 'legacy'
        for f in uses)


def main(*, compiler=compile_packet, source_sha=CATALOG_SHA, output=OUTPUT,
         allow_legacy_unit_drift=False):
    output.mkdir(parents=True, exist_ok=True)
    packet, _, cases = compiler()
    packet = deepcopy(packet)
    keys = ','.join("'" + d['key'].replace("'", "''") + "'"
                    for d in packet['reused_definitions'])
    query = """select to_jsonb(d)||jsonb_build_object('options',
      (select coalesce(jsonb_agg(to_jsonb(v) order by v.id),'[]')
       from public.spec_definition_values v where v.spec_definition_id=d.id)) as d
      from public.spec_definitions d where tenant_id is null and key in (""" + keys + ')'
    result = subprocess.run([str(WRAPPER), 'local', '--sql', query, '--format', 'json'],
                            cwd=ROOT, text=True, capture_output=True, check=True)
    existing = {r['d']['key']: r['d'] for r in json.loads(result.stdout)}
    baseline = []
    reused = []
    # Seed missing shared definitions from the exact generic preimage inside
    # each rollback; existing local identities are routed explicitly by key.
    for d in packet['reused_definitions']:
        if d['key'] in existing:
            local = existing[d['key']]
            if (d['key'], d['data_type']) != (local['key'], local['data_type']):
                raise ValueError('Local routing cannot change the shared field type')
            if d['unit'] != local['unit']:
                if not allow_legacy_unit_drift or not legacy_only_field(packet, d):
                    raise ValueError('Local routing cannot change an active shared unit')
                # No DB normalization, no production packet change. Only this
                # test's retired observation routes to the existing local ID.
                print('Local legacy unit retained without interpreting it: ' + d['key'])
            for f in packet['records']['spec_template_fields']:
                if f['spec_definition_id'] == d['id']:
                    f['spec_definition_id'] = local['id']
            reused.append(local)
        else:
            baseline.append('insert into public.spec_definitions select '
                            '(jsonb_populate_record(null::public.spec_definitions,' +
                            sql_json({k: v for k, v in d.items() if k != 'options'}) + ')).*;')
            for v in d['options']:
                baseline.append('insert into public.spec_definition_values select '
                                '(jsonb_populate_record(null::public.spec_definition_values,' +
                                sql_json(v) + ')).*;')
            reused.append(d)
    packet['reused_definitions'] = reused
    body = generate_migration(packet, source_sha=source_sha).split(
        'begin isolation level repeatable read;', 1)[1].rsplit('commit;', 1)[0]
    start = 'begin isolation level repeatable read;\n' + '\n'.join(baseline) + '\n'
    cleanup = 'drop table nd_publication_document, nd_publication_before;\n'
    first = packet['records']['spec_templates'][0]
    if not reused:
        raise ValueError('The shared-definition drift probe needs a reused definition')
    # The subject is a shared row, not the kit vocabulary specifically. Preserve
    # the original probe where available; other metadata blocks may not use it.
    shared = next((d for d in reused if d['key'] == 'kit_members'), reused[0])
    tests = {
        'publish_and_replay': (start + body + cleanup + body +
                              generate_verifier(packet, cases) + '\nrollback;', None),
        'reject_template_collision': (start + f"""insert into public.spec_templates
            (id,tenant_id,key,name,technical_family) values
            ('9d270000-0000-4000-8000-000000000003',null,
             '{first['key']}','Existing different template','{first['technical_family']}');
            """ + body, 'Publication key collision'),
        'reject_shared_definition_change': (start + body + cleanup + f"""update
            public.spec_definitions set description='Later shared edit'
            where id='{shared['id']}';
            """ + body, 'division by zero'),
        'reject_additive_rule_change': (start + body + cleanup + f"""update
            public.spec_templates set form_contract=jsonb_set(form_contract,'{{helpers}}',
            coalesce(form_contract->'helpers','{{}}')||'{{"tool_kind":"Later guidance"}}')
            where id='{first['id']}';
            """ + body, 'Publication drift in spec_templates'),
        'reject_new_option_collision': (start + body + cleanup + f"""update
            public.spec_definition_values set label='Later option edit'
            where id='{packet['records']['spec_definition_values'][0]['id']}';
            """ + body, 'Publication drift in spec_definition_values'),
    }
    for name, (sql, error) in tests.items():
        path = output / (name + '.sql')
        path.write_text(sql)
        result = subprocess.run([str(WRAPPER), 'local', '--file', str(path)],
                                cwd=ROOT, text=True, capture_output=True)
        log = result.stdout + result.stderr
        (output / (name + '.log')).write_text(log)
        if ((error is None and result.returncode) or (error is not None and
                (result.returncode == 0 or error not in log))):
            raise RuntimeError('Publication regression failed: ' + name)
        print('PASS: ' + name)
    print('Five local rollback regressions passed; no product writes retained.')


if __name__ == '__main__':
    main()
