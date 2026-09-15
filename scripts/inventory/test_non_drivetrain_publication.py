#!/usr/bin/env python3
"""Exercise the exact publication generator in local rollback transactions."""
from copy import deepcopy
import json
import subprocess

from compile_non_drivetrain_publication import (
    ROOT, compile_packet, generate_migration, generate_verifier)

OUTPUT = ROOT / '.tmp/db/non-drivetrain-publication-tests'
WRAPPER = ROOT / 'scripts/db/query.sh'


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    read = subprocess.run([str(WRAPPER), 'local', '--sql', """select to_jsonb(d) ||
      jsonb_build_object('options',(select coalesce(jsonb_agg(to_jsonb(v) order by v.id),'[]')
       from public.spec_definition_values v where v.spec_definition_id=d.id)) as definition
      from public.spec_definitions d where d.key='spec_evidence_source' and d.tenant_id is null""",
      '--format', 'json'], cwd=ROOT, text=True, capture_output=True, check=True)
    rows = json.loads(read.stdout)
    if len(rows) != 1:
        raise ValueError('Local shared evidence definition is ambiguous')
    packet, _, cases = compile_packet()
    packet = deepcopy(packet)
    shared = rows[0]['definition']
    old_id = packet['reused_definitions'][0]['id']
    packet['reused_definitions'] = [shared]
    for records in packet['records'].values():
        for record in records:
            if record.get('spec_definition_id') == old_id:
                record['spec_definition_id'] = shared['id']
    # Only database routing/IDs differ. Field types, rules and publication
    # preimage enforcement are the same generator used by the forward file.
    body = generate_migration(packet).split('begin isolation level repeatable read;', 1)[1]
    body = body.rsplit('commit;', 1)[0]
    cleanup = 'drop table nd_publication_document, nd_publication_before;\n'
    start = 'begin isolation level repeatable read;\n'
    first_template = packet['records']['spec_templates'][0]
    first_definition = packet['records']['spec_definitions'][0]
    tests = {
        'publish_and_replay': (start + body + cleanup + body +
                               generate_verifier(packet, cases) + '\nrollback;', None),
        'reject_key_collision': (start + f"""insert into public.spec_templates
            (id,tenant_id,key,name,technical_family) values
            ('9d270000-0000-4000-8000-000000000002',null,
             '{first_template['key']}','Existing different template','{first_template['technical_family']}');
            """ + body, 'Publication key collision'),
        'reject_later_edit': (start + body + cleanup + f"""update public.spec_definitions
            set label='Later operator edit' where id='{first_definition['id']}';
            """ + body, 'Publication drift in spec_definitions'),
        'reject_shared_preimage_drift': (start + body + cleanup + f"""update public.spec_definitions
            set description='Later shared edit' where id='{shared['id']}';
            """ + body, 'division by zero'),
        'reject_additive_contract_edit': (start + body + cleanup + f"""update public.spec_templates
            set form_contract=jsonb_set(form_contract,'{{helpers}}',
             coalesce(form_contract->'helpers','{{}}') || '{{"chemical_kind":"Later guidance"}}')
            where id='{first_template['id']}';
            """ + body, 'Publication drift in spec_templates'),
    }
    for name, (sql, error) in tests.items():
        source = OUTPUT / (name + '.sql')
        source.write_text(sql)
        result = subprocess.run([str(WRAPPER), 'local', '--file', str(source)],
                                cwd=ROOT, text=True, capture_output=True)
        log = result.stdout + result.stderr
        (OUTPUT / (name + '.log')).write_text(log)
        if (error is None and result.returncode) or (
                error is not None and (result.returncode == 0 or error not in log)):
            raise RuntimeError('Publication regression failed: ' + name)
        print('PASS: ' + name)
    print('All transactions rolled back; no local product or metadata changes retained.')


if __name__ == '__main__':
    main()
