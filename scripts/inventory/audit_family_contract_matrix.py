#!/usr/bin/env python3
"""Structural matrix of every active template against the family contract.

Read-only. For each active template the audit reads the published form
contract in the global snapshot and reports what the family matrix asks a
family to define: an initial decision (primary field or governed options),
dependent fields (applicability gates and prerequisites), interface and
variant discriminators (semantic roles), publication conditions (required
fields), evidence sources, and forbidden combinations (allowed options, row
conditions, ordered pairs, row coherence). It joins the coverage rows (how
many products and facts), the definition flags of the active fields (what a
customer or the matcher could ever see), the consumer audit (which keys code
still reads) and the critical-fields file. Structural only: it never says a
family is mechanically complete or that a product may be filled.
"""
import argparse
import collections
import datetime as dt
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'docs/development/product-specs-research-2026-09-05'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def kind(rule):
    return (rule or {}).get('kind') if isinstance(rule, dict) else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--coverage', type=Path, required=True)
    parser.add_argument('--consumers', type=Path, required=True)
    parser.add_argument('--critical-fields', type=Path, default=RESEARCH / 'catalog-fill-critical-fields.json')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    snapshot = json.loads(args.snapshot.read_text())
    coverage = json.loads(args.coverage.read_text())
    consumers = json.loads(args.consumers.read_text())
    critical = json.loads(args.critical_fields.read_text()).get('families', {})
    tables = snapshot['tables']
    definitions = {d['id']: d for d in tables['spec_definitions']}
    fields = collections.defaultdict(list)
    for field in tables['spec_template_fields']:
        fields[field['template_id']].append(field)
    products = collections.defaultdict(list)
    for row in coverage['products']:
        if row['template_id']:
            products[row['template_id']].append(row)
    read_keys = consumers['keys_read']
    rows = []
    for template in sorted(tables['spec_templates'], key=lambda t: t['key']):
        if not template['is_active']:
            continue
        contract = template.get('form_contract') or {}
        roles = contract.get('roles') or {}
        semantic = contract.get('semantic_roles') or {}
        allowed_when = contract.get('allowed_when') or {}
        required_when = contract.get('required_when') or {}
        evidence = contract.get('evidence_requirements') or {}
        own = [definitions[f['spec_definition_id']] for f in fields[template['id']]]
        keys = [d['key'] for d in own]
        active = [d for d in own if roles.get(d['key']) != 'legacy']
        legacy = [d for d in own if roles.get(d['key']) == 'legacy']
        gated = [k for k in keys if kind(allowed_when.get(k)) == 'when']
        never = [k for k in keys if kind(allowed_when.get(k)) == 'never']
        required_always = [k for k in keys if kind(required_when.get(k)) == 'always']
        required_when_gated = [k for k in keys if kind(required_when.get(k)) == 'when']
        prerequisites = contract.get('prerequisites') or {}
        row_conditions = ((contract.get('row_conditions') or {}).get('fields') or {})
        coherence = contract.get('row_coherence') or {}
        pairs = contract.get('scalar_ordered_pairs') or []
        member = contract.get('member_profiles') or {}
        consumer_active = sorted(k for k in keys if k in read_keys and roles.get(k) != 'legacy')
        consumer_legacy = sorted(k for k in keys if k in read_keys and roles.get(k) == 'legacy')
        own_products = products.get(template['id'], [])
        entry = {
            'template': template['key'], 'family': template['technical_family'],
            'contract_version': template['contract_version'], 'rules_version': contract.get('rules_version'),
            'products': len(own_products),
            'products_with_facts': sum(bool(p['facts_count']) for p in own_products),
            'products_with_pending_issues': sum(bool(p['server_issues']) for p in own_products),
            'fields': len(own), 'active_fields': len(active), 'legacy_fields': len(legacy),
            'roles': dict(collections.Counter(roles.get(k) or 'unset' for k in keys)),
            'semantic_roles': dict(collections.Counter(semantic.get(k) or 'unset' for k in keys if roles.get(k) != 'legacy')),
            'initial_decision': {'primary_fields': [k for k in keys if roles.get(k) == 'primary'],
                                 'governed_options': sorted((contract.get('allowed_options') or {}).keys())},
            'dependent_fields': {'gated_by_applicability': gated, 'never_allowed': never,
                                 'with_prerequisites': sorted(prerequisites.keys())},
            'publication_conditions': {'required_always': required_always,
                                       'required_when': required_when_gated},
            'evidence_requirements': dict(collections.Counter(evidence.values())),
            'required_without_evidence': sorted(k for k in required_always if k not in evidence),
            'forbidden_combinations': {'allowed_options_fields': len(contract.get('allowed_options') or {}),
                                       'row_condition_fields': len(row_conditions),
                                       'scalar_ordered_pairs': len(pairs),
                                       'row_coherence_links': len(coherence.get('links') or []),
                                       'row_coherence_cardinalities': len(coherence.get('cardinalities') or [])},
            'member_profiles': bool(member),
            'active_customer_visible': sum(bool(d['is_customer_visible']) for d in active),
            'active_filterable': sum(bool(d['is_filterable']) for d in active),
            'critical_fields_defined': template['technical_family'] in critical or template['key'] in critical,
            'consumer_keys_active': consumer_active, 'consumer_keys_legacy': consumer_legacy,
        }
        findings = []
        if not entry['initial_decision']['primary_fields'] and not entry['initial_decision']['governed_options']:
            findings.append('no_initial_decision')
        if not evidence:
            findings.append('no_evidence_requirement')
        if entry['required_without_evidence']:
            findings.append('required_without_evidence')
        if active and entry['active_customer_visible'] == 0:
            findings.append('no_visible_active_field')
        if active and entry['active_filterable'] == 0:
            findings.append('no_filterable_active_field')
        if consumer_legacy and not consumer_active:
            findings.append('consumers_read_only_legacy_keys')
        if not own_products:
            findings.append('no_products')
        if not entry['critical_fields_defined']:
            findings.append('no_critical_fields_defined')
        entry['findings'] = findings
        rows.append(entry)
    summary = {
        'active_templates': len(rows),
        'templates_with_products': sum(1 for r in rows if r['products']),
        'templates_with_facts': sum(1 for r in rows if r['products_with_facts']),
        'findings_by_code': dict(collections.Counter(f for r in rows for f in r['findings'])),
        'templates_without_findings_except_critical': sum(
            1 for r in rows if set(r['findings']) <= {'no_critical_fields_defined'}),
        'families_with_critical_fields': sorted(critical.keys()),
    }
    result = {'format_version': 1, 'scope': 'family_contract_matrix_structural_only',
              'audited_at': dt.datetime.now(dt.timezone.utc).isoformat(),
              'snapshot_at': snapshot['captured_at'], 'snapshot_sha256': digest(args.snapshot),
              'coverage_sha256': digest(args.coverage), 'consumers_sha256': digest(args.consumers),
              'summary': summary, 'templates': rows,
              'scope_limit': 'Reads what each published contract declares. It does not judge whether the '
                             'declared decisions, interfaces or sources are the mechanically right ones, and '
                             'a template without findings is not a family ready to fill.',
              'writes': 0}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=1) + '\n')
    print(json.dumps(summary, indent=1))
    for row in sorted(rows, key=lambda r: -r['products'])[:40]:
        print(f"{row['template']:34} p={row['products']:4} f={row['products_with_facts']:4} "
              f"act={row['active_fields']:3} leg={row['legacy_fields']:3} vis={row['active_customer_visible']:3} "
              f"filt={row['active_filterable']:3} {','.join(row['findings'])}")


if __name__ == '__main__':
    main()
