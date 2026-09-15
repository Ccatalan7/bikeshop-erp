#!/usr/bin/env python3
"""Exercise the component-set metadata with exact shared definitions locally.

The existing candidate harness namespaces only identities and keys. Production
definition shapes, options, field rules and expected cases stay unchanged. The
new-metadata publisher is exercised with native triggers, then rolled back.
"""
import json
import subprocess
import uuid

from compile_component_set import ID, PREFIX, RESEARCH, ROOT
from compile_non_drivetrain_publication import generate_migration
from test_existing_spec_candidate import NAMESPACE, prepare


def main():
    packet = json.loads((RESEARCH / (PREFIX + '-packet.json')).read_text())
    cases = json.loads((RESEARCH / (PREFIX + '-cases.json')).read_text())
    if packet['scope'] != 'new_global_metadata_only' or packet['product_writes']:
        raise ValueError('Only the reviewed new metadata is supported')
    packet['before'] = {key: [] for key in packet['records']}
    sql = prepare(packet, cases, migration_builder=generate_migration)
    separator = 'drop table nd_publication_document,nd_publication_before;'
    first, replay = sql.split(separator, 1)
    template_id = str(uuid.uuid5(NAMESPACE, ID))
    definition_id = str(uuid.uuid5(NAMESPACE, packet['reused_definitions'][0]['id']))
    tests = {
        'forward_replay_and_cases': (sql, None),
        'reject_template_drift': (first + separator + f"""
            update public.spec_templates set form_contract=jsonb_set(
              form_contract,'{{helpers}}', '{{"unexpected":"Later edit"}}')
              where id='{template_id}';
            """ + replay, 'Publication drift in spec_templates'),
        'reject_shared_definition_drift': (first + separator + f"""
            update public.spec_definitions set description='Later shared edit'
              where id='{definition_id}';
            """ + replay, 'division by zero'),
    }
    output = ROOT / '.tmp/product-spec-catalog/component-set-20260915/tests'
    output.mkdir(parents=True, exist_ok=True)
    for name, (body, expected_error) in tests.items():
        path = output / (name + '.sql'); path.write_text(body)
        result = subprocess.run([str(ROOT / 'scripts/db/query.sh'), 'local',
                                 '--file', str(path)], cwd=ROOT, text=True,
                                capture_output=True)
        log = result.stdout + result.stderr
        (output / (name + '.log')).write_text(log)
        if ((expected_error is None and (result.returncode or 'ROLLBACK' not in log))
                or (expected_error is not None and
                    (result.returncode == 0 or expected_error not in log))):
            raise RuntimeError('Local regression failed: ' + name)
        print('PASS: ' + name)
    print(json.dumps({'cases': len(cases['cases']), 'rollback': True,
                      'product_writes': False, 'mechanical_approval': False}))


if __name__ == '__main__':
    main()
