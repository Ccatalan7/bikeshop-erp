#!/usr/bin/env python3
"""Propose customer-visibility and filter flags for the blind active fields.

Read-only. 68 active templates carry 609 active fields whose definitions were
born with is_customer_visible = false and is_filterable = false, so nothing
filled in them would reach the public store, the assistant, the supply needs
or the supplier portal. This applies one explicit rule to every active,
non-legacy field of every active template and writes a proposal per
definition, with the rule that fired and the templates that use the field.
It never proposes to hide or unfilter a field that a family adjudication
already made visible; those outside the rule are listed for review only.
It does not publish: flags are a product decision about what a customer sees
and what the matcher may ask; the proposal exists so that decision can be
made over a concrete list instead of 609 blanks.

Rule (2026-09-16):
  customer_visible = scalar data type (number, boolean, text, single_select,
                     multi_select), semantic role other than evidence, field
                     role not legacy;
  filterable       = customer_visible and data type single_select,
                     multi_select, number or boolean.
Evidence fields and json rows stay internal: no consumer renders rows yet.
"""
import argparse
import collections
import datetime as dt
import hashlib
import json
from pathlib import Path

INTERNAL_ROLES = {'evidence'}
SCALAR = {'number', 'boolean', 'text', 'single_select', 'multi_select'}
FILTERABLE = {'number', 'boolean', 'single_select', 'multi_select'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    snapshot = json.loads(args.snapshot.read_text())
    tables = snapshot['tables']
    definitions = {d['id']: d for d in tables['spec_definitions'] if d['tenant_id'] is None}
    templates = {t['id']: t for t in tables['spec_templates'] if t['is_active']}
    uses = collections.defaultdict(list)
    for field in tables['spec_template_fields']:
        template = templates.get(field['template_id'])
        definition = definitions.get(field['spec_definition_id'])
        if not template or not definition:
            continue
        contract = template.get('form_contract') or {}
        role = (contract.get('roles') or {}).get(definition['key'])
        semantic = (contract.get('semantic_roles') or {}).get(definition['key'])
        uses[definition['id']].append({'template': template['key'], 'role': role, 'semantic': semantic})
    proposals, review_only = [], []
    for definition_id, entries in uses.items():
        definition = definitions[definition_id]
        active = [e for e in entries if e['role'] != 'legacy']
        if not active:
            continue
        semantics = {e['semantic'] for e in active}
        visible = definition['data_type'] in SCALAR and not (semantics <= INTERNAL_ROLES)
        filterable = visible and definition['data_type'] in FILTERABLE
        current = {'is_customer_visible': bool(definition['is_customer_visible']),
                   'is_filterable': bool(definition['is_filterable'])}
        proposed = {'is_customer_visible': current['is_customer_visible'] or visible,
                    'is_filterable': current['is_filterable'] or filterable}
        entry = {
            'definition_id': definition_id, 'key': definition['key'], 'label': definition['label'],
            'data_type': definition['data_type'], 'semantic_roles': sorted(s or 'unset' for s in semantics),
            'templates': sorted({e['template'] for e in active}), 'current': current, 'proposed': proposed,
        }
        if proposed != current:
            entry['rule'] = 'scalar_non_evidence_field_becomes_visible' + ('_and_filterable' if filterable and not current['is_filterable'] else '')
            proposals.append(entry)
        elif (current['is_customer_visible'] and not visible) or (current['is_filterable'] and not filterable):
            entry['note'] = 'visible or filterable today although outside the rule; kept as adjudicated'
            review_only.append(entry)
    proposals.sort(key=lambda p: p['key'])
    review_only.sort(key=lambda p: p['key'])
    summary = {
        'definitions_with_active_use': sum(1 for e in uses.values() if any(x['role'] != 'legacy' for x in e)),
        'proposed_changes': len(proposals),
        'to_visible': sum(1 for p in proposals if p['proposed']['is_customer_visible'] and not p['current']['is_customer_visible']),
        'to_filterable': sum(1 for p in proposals if p['proposed']['is_filterable'] and not p['current']['is_filterable']),
        'downgrades_proposed': 0, 'review_only_outside_rule': len(review_only),
        'by_data_type': dict(collections.Counter(p['data_type'] for p in proposals)),
        'by_semantic_role': dict(collections.Counter(s for p in proposals for s in p['semantic_roles'])),
        'templates_touched': len({t for p in proposals for t in p['templates']}),
    }
    result = {'format_version': 1, 'scope': 'definition_flag_proposal_not_published',
              'proposed_at': dt.datetime.now(dt.timezone.utc).isoformat(),
              'snapshot_at': snapshot['captured_at'], 'snapshot_sha256': digest(args.snapshot),
              'rule': {'customer_visible': 'scalar data type and semantic role other than evidence, on an active non-legacy field',
                       'filterable': 'customer_visible and data type in single_select/multi_select/number/boolean',
                       'internal': 'evidence fields and json rows',
                       'never': 'no flag that a family adjudication already enabled is proposed for removal'},
              'summary': summary, 'proposals': proposals, 'review_only': review_only,
              'publication_authorized': False, 'writes': 0}
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=1) + '\n')
    print(json.dumps(summary, indent=1))


if __name__ == '__main__':
    main()
