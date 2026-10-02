#!/usr/bin/env python3
"""Worksheet for one family: fields (type, unit, options) and products with current values."""
import json, sys
S = '/private/tmp/claude-502/-Users-Claudio-Dev-bikeshop-erp/c9bb2cb2-3cbb-4d57-91f5-76029661032e/scratchpad/fill'
F = json.load(open(S + '/fields.json')); P = json.load(open(S + '/products.json'))
fam = sys.argv[1]
only = sys.argv[2].split(',') if len(sys.argv) > 2 and sys.argv[2] else None
desc = '--desc' in sys.argv
fields = [f for f in F if f['template_key'] == fam and (f['visible'] or f['data_type'] == 'json') and f['field_key'] != 'spec_evidence_source']
if only: fields = [f for f in fields if f['field_key'] in only]
for f in fields:
    opts = f['options'] or []
    r = f['rules'] or {}
    rs = f['rows_schema']
    extra = ''
    if rs: extra = ' cols=' + ','.join(c['key'] + ('*' if c.get('required') else '') for c in rs['columns'])
    print(f"F {f['field_key']} [{f['data_type']}{' '+f['unit'] if f['unit'] else ''}] {f['label']}" + (f" rules={json.dumps(r,ensure_ascii=False)}" if r else '') + (' opts=' + ' | '.join(opts) if opts and f['data_type'] in ('single_select','multi_select') else '') + extra)
print()
keys = [f['field_key'] for f in fields]
for p in [p for p in P if p['template_key'] == fam]:
    facts = p['facts'] or {}
    cur = []
    for k in keys:
        if k in facts:
            v = facts[k]['v']
            if isinstance(v, dict) and 'rows' in v: v = f"<{len(v['rows'])} filas>"
            cur.append(f"{k}={v if not isinstance(v, list) else '|'.join(map(str, v))}({facts[k]['s'][:2]})")
    line = f"{p['id'][:8]} {p['name']}" + (f" ·B:{p['brand']}" if p['brand'] else '') + (f" ·M:{p['model']}" if p['model'] else '')
    print(line)
    if desc and p['description']: print('   D:', p['description'][:220])
    if cur: print('   =', '; '.join(cur))
