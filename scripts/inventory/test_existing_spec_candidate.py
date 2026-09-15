#!/usr/bin/env python3
"""Test a reviewed existing-template candidate in a local rollback transaction.

Only metadata identities/keys are namespaced to avoid the shared local fixture.
Rules, columns, options, revision preimages and cases are otherwise unchanged.
This test never connects to production, changes a product or retains metadata.
"""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import uuid

from compile_existing_spec_publication import generate_migration
from compile_non_drivetrain_publication import generate_verifier, sql_json

ROOT = Path(__file__).resolve().parents[2]
NAMESPACE = uuid.UUID('5223d615-eb6f-4372-bd60-2057f5fd7913')


def prepare(packet, cases, *, migration_builder=generate_migration,
            verifier_builder=generate_verifier):
    substitutions = {}
    metadata = [*packet['reused_definitions']]
    for definition in packet['reused_definitions']:
        metadata.extend(definition['options'])
    for group in (packet['records'], packet['before']):
        for records in group.values():
            metadata.extend(records)
    for record in metadata:
        if record.get('id'):
            substitutions[record['id']] = str(uuid.uuid5(NAMESPACE, record['id']))
    for definition in [*packet['reused_definitions'], *packet['records']['spec_definitions']]:
        substitutions[definition['key']] = 'fixture_eb_' + definition['key']
    for template in packet['records']['spec_templates']:
        substitutions[template['key']] = 'fixture_eb_' + template['key']

    def rename(value):
        if isinstance(value, dict):
            return {substitutions.get(k, k): (v if k == 'technical_family' else rename(v)) for k, v in value.items()}
        if isinstance(value, list):
            return [rename(v) for v in value]
        return substitutions.get(value, value) if isinstance(value, str) else value

    routed, fixtures = rename(deepcopy(packet)), rename(deepcopy(cases))
    # UUID remapping changes ordering, while the guard compares the exact
    # ordered option snapshot. Preserve its canonical order after routing.
    for definition in routed['reused_definitions']:
        definition['options'].sort(key=lambda option: option['id'])
    seed = 'begin isolation level repeatable read;\nset local session_replication_role=replica;\n'
    groups = [
        ('spec_definitions', [{k: v for k, v in d.items() if k != 'options'}
                              for d in routed['reused_definitions']]),
        ('spec_definition_values', [v for d in routed['reused_definitions'] for v in d['options']]),
        ('spec_templates', routed['before']['spec_templates']),
        ('spec_template_fields', routed['before']['spec_template_fields']),
    ]
    for table, records in groups:
        for record in records:
            seed += (f'insert into public.{table} select '
                     f'(jsonb_populate_record(null::public.{table}, {sql_json(record)})).*;\n')
    # Recreate historical fixture rows exactly; their revisions predate today's
    # field triggers. This setting exists ONLY inside the local rollback seed.
    # Restore native triggers before either publication or replay is exercised.
    seed += 'set local session_replication_role=origin;\n'
    body = migration_builder(routed, source_sha=packet['catalog_sha256']).split(
        'begin isolation level repeatable read;', 1)[1].rsplit('commit;', 1)[0]
    return seed + body + '\ndrop table nd_publication_document,nd_publication_before;\n' + \
        body + verifier_builder(routed, fixtures) + '\nrollback;\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet', required=True, type=Path)
    parser.add_argument('--cases', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    packet, cases = [json.loads(p.read_text()) for p in (args.packet, args.cases)]
    if packet['scope'] != 'existing_global_metadata_forward_only' or packet['product_writes']:
        raise ValueError('Only existing-template metadata is supported')
    args.output.mkdir(parents=True, exist_ok=True)
    path = args.output / 'forward-replay-and-cases.sql'
    path.write_text(prepare(packet, cases))
    result = subprocess.run([str(ROOT / 'scripts/db/query.sh'), 'local', '--file', str(path)],
                            cwd=ROOT, text=True, capture_output=True)
    log = result.stdout + result.stderr
    (args.output / 'forward-replay-and-cases.log').write_text(log)
    if result.returncode or 'ROLLBACK' not in log:
        raise RuntimeError('Local candidate failed; inspect ' + str(args.output))
    print(json.dumps({'local_forward': True, 'exact_replay': True,
                      'cases': len(cases['cases']), 'rollback': True}))


if __name__ == '__main__':
    main()
