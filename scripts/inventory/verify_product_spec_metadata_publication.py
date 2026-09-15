#!/usr/bin/env python3
"""Read back published metadata through the existing authenticated ERP actor.

This is not a product applicator. The transport has a fixed metadata GET and
allowlisted read RPCs; no credentials are written to the evidence artifact.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path

from product_spec_session import ProductSpecSession

ROOT = Path(__file__).resolve().parents[2]
PROJECTION = {
    'spec_templates': {'id', 'tenant_id', 'key', 'name', 'technical_family',
                       'form_contract', 'is_active'},
    'spec_template_fields': {'id', 'tenant_id', 'template_id', 'spec_definition_id',
                             'section_key', 'sort_order', 'is_required',
                             'visibility_rules', 'option_rules', 'constraint_rules'},
    'spec_definitions': {'id', 'tenant_id', 'key', 'label', 'data_type', 'unit',
                         'allowed_values', 'validation_rules', 'is_customer_visible',
                         'is_compatibility_relevant'},
    'spec_definition_values': {'id', 'tenant_id', 'spec_definition_id', 'code',
                               'label', 'sort_order', 'is_active'},
}


def verify(packet, templates):
    actual = {table: {} for table in PROJECTION}
    for template in templates:
        actual['spec_templates'][template['id']] = template
        for field in template['fields']:
            actual['spec_template_fields'][field['id']] = field
            definition = field['definition']
            actual['spec_definitions'][definition['id']] = definition
            for option in definition['options']:
                actual['spec_definition_values'][option['id']] = option
    expected = {table: list(rows) for table, rows in packet['records'].items()}
    for shared in packet['reused_definitions']:
        expected['spec_definitions'].append(shared)
        expected['spec_definition_values'].extend(shared['options'])
    for table, rows in expected.items():
        if set(actual[table]) != {row['id'] for row in rows}:
            raise ValueError('Authenticated metadata cardinality differs: ' + table)
        for wanted in rows:
            row = actual[table][wanted['id']]
            if any(key not in row or row[key] != wanted[key]
                   for key in PROJECTION[table]):
                raise ValueError('Authenticated metadata drift: ' + table + ':' + wanted['id'])
    return {table: len(rows) for table, rows in actual.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    packet = json.loads(args.packet.read_text())
    session = ProductSpecSession(ROOT)
    templates = session.read_template_metadata([
        t['id'] for t in packet['records']['spec_templates']])
    counts = verify(packet, templates)
    references = {family: len(session.read('get_product_spec_references_v2',
                                          {'p_family': family}))
                  for family in packet['families']}
    result = {'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'project': session.project, 'actor_id': session.actor_id,
              'packet_sha256': hashlib.sha256(args.packet.read_bytes()).hexdigest(),
              'counts': counts, 'templates': templates,
              'reference_counts': references, 'writes': 0}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as output:
        json.dump(result, output, ensure_ascii=False, indent=2)
        output.write('\n')
    print(json.dumps({'counts': counts, 'reference_families': len(references),
                      'authenticated': True, 'writes': 0}))


if __name__ == '__main__':
    main()
