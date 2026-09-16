#!/usr/bin/env python3
"""Audit every specification definition that a consumer reads by key.

Read-only. Consumers are the Dart client (lib/), the edge functions
(supabase/functions/**/*.ts) and the live production functions and views
whose bodies read specification tables (captured by the caller into a JSON
file). A consumer is any source that names a definition key as a quoted
literal. For each key the audit says whether it exists, in which active
templates and with which role, whether it is filterable or customer visible,
and how many products hold a fact for it. Reading a key that is legacy in
every template, absent from every active template, or not filterable when the
consumer is the matcher, is a structural finding; it never decides mechanical
semantics, identity or compatibility.
"""
import argparse
import collections
import datetime as dt
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
LITERAL = re.compile(r"""['"]([a-z][a-z0-9]*(?:_[a-z0-9]+)+)['"]""")
KEY_LIKE = re.compile(r'(_mm|_in|_teeth|_count|_type|_standard|_interface|_width|_diameter|_length|'
                      r'_speeds|_bcd|_size|_material|_included|_ready|_value|_rows|_scope|_surface|'
                      r'_actuation|_position|_presentation)$')
MATCHER_SOURCES = ('assistant_', 'supply_need', 'supplier_need', 'supply_request', 'tool_executor')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_keys(snapshot):
    tables = snapshot['tables']
    definitions = {d['id']: d for d in tables['spec_definitions'] if d['tenant_id'] is None}
    templates = {t['id']: t for t in tables['spec_templates'] if t['is_active']}
    facts = collections.defaultdict(set)
    for fact in tables['spec_facts']:
        if fact['subject_scope'] is None:
            facts[fact['spec_definition_id']].add(fact['subject_id'])
    info = {}
    for definition in definitions.values():
        info[definition['key']] = {
            'definition_id': definition['id'], 'data_type': definition['data_type'],
            'is_filterable': definition['is_filterable'],
            'is_customer_visible': definition['is_customer_visible'],
            'templates': [], 'products_with_facts': len(facts[definition['id']])}
    for field in tables['spec_template_fields']:
        template = templates.get(field['template_id'])
        definition = definitions.get(field['spec_definition_id'])
        if not template or not definition:
            continue
        role = ((template.get('form_contract') or {}).get('roles') or {}).get(definition['key'])
        info[definition['key']]['templates'].append({'template': template['key'], 'role': role})
    for entry in info.values():
        entry['templates'].sort(key=lambda t: t['template'])
        roles = {t['role'] for t in entry['templates']}
        entry['active_templates'] = len(entry['templates'])
        entry['legacy_everywhere'] = bool(entry['templates']) and roles == {'legacy'}
        entry['no_active_template'] = not entry['templates']
    return info


def scan_text(name, kind, text, keys):
    found = collections.Counter()
    unknown = collections.Counter()
    for match in LITERAL.finditer(text):
        literal = match.group(1)
        if literal in keys:
            found[literal] += 1
        elif KEY_LIKE.search(literal):
            unknown[literal] += 1
    if not found and not unknown:
        return None
    return {'name': name, 'kind': kind, 'keys': dict(sorted(found.items())),
            'key_like_unknown': dict(sorted(unknown.items()))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, required=True)
    parser.add_argument('--sql-consumers', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    snapshot = json.loads(args.snapshot.read_text())
    keys = load_keys(snapshot)
    sources = []
    for path in sorted((ROOT / 'lib').rglob('*.dart')):
        entry = scan_text(str(path.relative_to(ROOT)), 'dart', path.read_text(), keys)
        if entry:
            sources.append(entry)
    for path in sorted((ROOT / 'supabase/functions').rglob('*.ts')):
        if path.name.endswith('_test.ts'):
            continue
        entry = scan_text(str(path.relative_to(ROOT)), 'edge', path.read_text(), keys)
        if entry:
            sources.append(entry)
    live = json.loads(args.sql_consumers.read_text())
    for item in (live.get('functions') or []) + (live.get('views') or []):
        entry = scan_text(item['name'], 'sql_' + item['kind'], item['definition'], keys)
        if entry:
            sources.append(entry)
    consumers_by_key = collections.defaultdict(list)
    for source in sources:
        for key in source['keys']:
            consumers_by_key[key].append(source['name'])
    findings = []
    for key, names in sorted(consumers_by_key.items()):
        entry = keys[key]
        matcher = [n for n in names if any(m in n for m in MATCHER_SOURCES)]
        if entry['no_active_template']:
            findings.append({'key': key, 'code': 'read_but_in_no_active_template', 'consumers': names})
        elif entry['legacy_everywhere']:
            findings.append({'key': key, 'code': 'read_but_legacy_in_every_template', 'consumers': names,
                             'templates': [t['template'] for t in entry['templates']],
                             'products_with_facts': entry['products_with_facts']})
        if matcher and not entry['is_filterable'] and not entry['no_active_template']:
            findings.append({'key': key, 'code': 'matcher_reads_non_filterable_key', 'consumers': matcher})
    unknown = collections.Counter()
    for source in sources:
        for literal, count in source['key_like_unknown'].items():
            unknown[literal] += count
    read_keys = {k: {**keys[k], 'consumers': sorted(set(consumers_by_key[k]))} for k in consumers_by_key}
    summary = {
        'live_global_definitions': len(keys),
        'definitions_read_by_some_consumer': len(read_keys),
        'definitions_read_by_nobody': len(keys) - len(read_keys),
        'consumer_sources': len(sources),
        'sources_by_kind': dict(collections.Counter(s['kind'] for s in sources)),
        'findings_by_code': dict(collections.Counter(f['code'] for f in findings)),
        'key_like_literals_not_definitions': len(unknown),
    }
    result = {'format_version': 1, 'scope': 'definition_consumers_structural_only',
              'audited_at': dt.datetime.now(dt.timezone.utc).isoformat(),
              'snapshot_at': snapshot['captured_at'], 'snapshot_sha256': digest(args.snapshot),
              'sql_consumers_sha256': digest(args.sql_consumers),
              'summary': summary, 'findings': findings, 'keys_read': read_keys,
              'sources': sources,
              'key_like_literals_not_definitions': dict(sorted(unknown.items())),
              'scope_limit': 'Names which code reads which definition key. It does not judge whether the '
                             'value read is correct, whether the consumer resolves identity or compatibility '
                             'consistently, or whether a family is semantically complete.',
              'writes': 0}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=1) + '\n')
    print(json.dumps(summary, indent=1))
    for finding in findings:
        print(finding['code'], finding['key'], '<-', ', '.join(finding['consumers'])[:160])


if __name__ == '__main__':
    main()
