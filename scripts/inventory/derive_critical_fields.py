#!/usr/bin/env python3
"""Derive a draft critical-fields list per family from the published contracts.

Read-only. catalog-fill-critical-fields.json only covers chain and chain_link,
reviewed by hand. For every other active template this derives, from the
form contract in the global snapshot, the same four groups the reviewed file
uses: identity (brand, model and identity-role fields), presentation
(contents, pack and presentation selectors), technical (primary decisions and
fields required always) and compatibility_evidence (evidence-role fields).
The reviewed families are copied unchanged and marked reviewed; every derived
family is marked derived_unreviewed. A derived list measures research
completeness only: it adds no validation rule and implies no fitment.
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'docs/development/product-specs-research-2026-09-05'
PRESENTATION = re.compile(r'(pack_quantity|sold_as|_presentation$|_included$|link_count|_pack_qty|kit_members|'
                          r'set_members|package_contents|_count_included$|units_per_pack)')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def kind(rule):
    return (rule or {}).get('kind') if isinstance(rule, dict) else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--reviewed', type=Path, default=RESEARCH / 'catalog-fill-critical-fields.json')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    snapshot = json.loads(args.snapshot.read_text())
    reviewed = json.loads(args.reviewed.read_text())
    tables = snapshot['tables']
    definitions = {d['id']: d for d in tables['spec_definitions']}
    fields = {}
    for field in tables['spec_template_fields']:
        fields.setdefault(field['template_id'], []).append(definitions[field['spec_definition_id']]['key'])
    families = {}
    for template in sorted(tables['spec_templates'], key=lambda t: t['key']):
        if not template['is_active']:
            continue
        key = template['key']
        if key in reviewed['families']:
            families[key] = {**reviewed['families'][key], 'status': 'reviewed'}
            continue
        contract = template.get('form_contract') or {}
        roles = contract.get('roles') or {}
        semantic = contract.get('semantic_roles') or {}
        required_when = contract.get('required_when') or {}
        keys = [k for k in fields.get(template['id'], []) if roles.get(k) != 'legacy']
        identity = ['brand', 'model'] + [k for k in keys if semantic.get(k) == 'identity']
        presentation = ['manufacturer_sku'] + [k for k in keys if roles.get(k) == 'contents'
                                               or semantic.get(k) == 'contents' or PRESENTATION.search(k)]
        technical = [k for k in keys if (roles.get(k) == 'primary' or kind(required_when.get(k)) == 'always')
                     and semantic.get(k) not in ('evidence', 'contents') and k not in presentation]
        evidence = [k for k in keys if semantic.get(k) == 'evidence']
        families[key] = {
            'identity': identity, 'presentation': presentation, 'technical': technical,
            'compatibility_evidence': evidence, 'status': 'derived_unreviewed',
            'contract_version': template['contract_version'],
            'note': 'Derived from the published contract (primary decisions and fields required always). '
                    'Nominal values do not prove fitment; review before using as a batch closure criterion.'}
    result = {
        'schema_version': 1,
        'purpose': 'Research completeness only. Does not add validation rules or imply fitment.',
        'derived_at': dt.datetime.now(dt.timezone.utc).isoformat(),
        'snapshot_at': snapshot['captured_at'], 'snapshot_sha256': digest(args.snapshot),
        'reviewed_source': args.reviewed.name, 'reviewed_source_sha256': digest(args.reviewed),
        'families': families,
        'summary': {'families': len(families),
                    'reviewed': sum(1 for f in families.values() if f['status'] == 'reviewed'),
                    'derived_unreviewed': sum(1 for f in families.values() if f['status'] == 'derived_unreviewed'),
                    'derived_without_technical_fields': sorted(k for k, f in families.items()
                                                               if f['status'] != 'reviewed' and not f['technical']),
                    'derived_without_evidence_fields': sorted(k for k, f in families.items()
                                                              if f['status'] != 'reviewed' and not f['compatibility_evidence'])},
        'writes': 0}
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=1) + '\n')
    print(json.dumps(result['summary'], ensure_ascii=False, indent=1))


if __name__ == '__main__':
    main()
