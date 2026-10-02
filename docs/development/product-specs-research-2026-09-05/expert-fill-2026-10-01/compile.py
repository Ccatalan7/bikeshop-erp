#!/usr/bin/env python3
"""Compile expert fill files into checked candidates for record_product_spec_expert_value_v1.

Fill file (one per family, fills/<family>.txt):
  @reason <reason for every line below until the next @reason>
  * key=value; key=value          every product of the family (that lacks it)
  <id8> key=value; key=value      one product (overrides *)
  <id8> -key                      exclude a * default for that product
Values: numbers, sí/no, an option label (exact, case/accents ignored), a|b for
multiple choice, free text, or a JSON array of row values for a rows field.
"""
import json, re, sys, glob, os, unicodedata, collections
S = os.path.dirname(os.path.abspath(__file__))
F = json.load(open(S + '/fields.json')); P = json.load(open(S + '/products.json'))
fields = collections.defaultdict(dict)
for f in F: fields[f['template_key']][f['field_key']] = f
# The effective option list is the definition's intersected with the sheet's.
for a in json.load(open(S + '/allowed.json')):
    for key, allowed in (a['ao'] or {}).items():
        f = fields[a['key']].get(key)
        if f and isinstance(allowed, list):
            f['options'] = [o for o in (f['options'] or []) if o in allowed]
byfam = collections.defaultdict(list)
for p in P: byfam[p['template_key']].append(p)

def norm(s): return ''.join(c for c in unicodedata.normalize('NFD', str(s).lower().strip()) if unicodedata.category(c) != 'Mn')

def typed(f, raw, errors, where):
    t = f['data_type']; raw = raw.strip()
    if t == 'number':
        x = raw.replace(',', '.')
        if not re.fullmatch(r'-?\d+(\.\d+)?', x): errors.append(f'{where}: número inválido {raw}'); return None
        r = f['rules'] or {}
        v = float(x)
        if r.get('positive') and v <= 0: errors.append(f'{where}: debe ser positivo'); return None
        if r.get('integer') and not v.is_integer(): errors.append(f'{where}: debe ser entero'); return None
        for k, op in (('min', lambda a, b: a >= b), ('max', lambda a, b: a <= b)):
            if k in r and r[k] is not None and not op(v, float(r[k])): errors.append(f'{where}: fuera de {k}={r[k]}'); return None
        return int(v) if v.is_integer() else v
    if t == 'boolean':
        if norm(raw) in ('si', 'true', 'yes'): return True
        if norm(raw) in ('no', 'false'): return False
        errors.append(f'{where}: sí/no inválido {raw}'); return None
    if t in ('single_select', 'multi_select'):
        opts = {norm(o): o for o in (f['options'] or [])}
        items = [i for i in raw.split('|')] if t == 'multi_select' else [raw]
        out = []
        for i in items:
            o = opts.get(norm(i))
            if o is None: errors.append(f'{where}: «{i}» no está en {list(opts.values())}'); return None
            out.append(o)
        return out if t == 'multi_select' else out[0]
    if t == 'text':
        return raw
    if t == 'json':
        rows = json.loads(raw)
        cols = {c['key']: c for c in f['rows_schema']['columns']}
        for r in rows:
            for k in r:
                if k not in cols: errors.append(f'{where}: columna desconocida {k}'); return None
            for k, c in cols.items():
                if c.get('required') and not k.startswith('source') and str(r.get(k, '')).strip() == '': errors.append(f'{where}: falta columna {k}'); return None
                if c.get('type') == 'token' and k in r and c.get('allowed_values') and r[k] not in c['allowed_values']:
                    errors.append(f'{where}: {k}={r[k]} no está en {c["allowed_values"]}'); return None
        return {'schema_version': f['rows_schema'].get('version', 1), 'rows': [{'id': f'expert-{i+1}', 'values': {k: (v if isinstance(v, (bool,)) else str(v)) for k, v in r.items()}, 'sources': []} for i, r in enumerate(rows)]}
    errors.append(f'{where}: tipo {t}'); return None

def parse_assign(text):
    out = {}
    excl = set()
    for part in re.split(r';\s*(?=-?[a-z_0-9]+\s*=|-[a-z_0-9]+\s*(?:;|$))', text.strip()):
        part = part.strip()
        if not part: continue
        if part.startswith('-') and '=' not in part: excl.add(part[1:].strip()); continue
        k, _, v = part.partition('=')
        out[k.strip()] = v.strip()
    return out, excl

def compile_family(path, errors):
    fam = os.path.basename(path)[:-4]
    fl = fields.get(fam)
    if not fl: errors.append(f'{fam}: familia desconocida'); return []
    prods = {p['id'][:8]: p for p in byfam[fam]}
    reason = None
    defaults = []  # (assignments, reason)
    per = collections.defaultdict(list)
    for n, line in enumerate(open(path), 1):
        line = line.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('//'): continue
        if line.startswith('@reason'): reason = line[7:].strip(); continue
        head, _, rest = line.partition(' ')
        rest, _, lreason = rest.partition(' # ')
        assigns, excl = parse_assign(rest)
        if head == '*': defaults.append((assigns, lreason.strip() or reason, n)); continue
        if head not in prods: errors.append(f'{fam}:{n}: producto {head} no es de la familia'); continue
        per[head].append((assigns, excl, lreason.strip() or reason, n))
    cands = []
    for pid8, p in prods.items():
        facts = p['facts'] or {}
        want = {}
        excl_all = set()
        for a, ex, r, n in per.get(pid8, []): excl_all |= ex
        for a, r, n in defaults:
            for k, v in a.items():
                if k not in excl_all: want[k] = (v, r, n)
        for a, ex, r, n in per.get(pid8, []):
            for k, v in a.items(): want[k] = (v, r, n)
        for k, (v, r, n) in want.items():
            f = fl.get(k)
            where = f'{fam}:{n}:{pid8}:{k}'
            if f is None: errors.append(f'{where}: campo no está en la ficha (o retirado)'); continue
            if k in facts and facts[k]['s'] != 'inferred': continue
            if v == '': continue
            val = typed(f, v, errors, where)
            if val is None: continue
            if not r: errors.append(f'{where}: falta razón'); continue
            cands.append({'product_id': p['id'], 'family': fam, 'name': p['name'], 'field_key': k, 'value': val, 'reason': r[:500]})
    return cands

if __name__ == '__main__':
    errors = []
    files = sorted(glob.glob(S + '/fills/*.txt')) if len(sys.argv) < 2 else [S + f'/fills/{x}.txt' for x in sys.argv[1:]]
    allc = []
    for path in files: allc += compile_family(path, errors)
    for e in errors: print('ERROR', e)
    out = S + '/candidates_expert.json'
    if len(sys.argv) < 2:
        json.dump({'candidates': allc}, open(out, 'w'), ensure_ascii=False, indent=0)
    c = collections.Counter(x['family'] for x in allc)
    print(len(allc), 'valores en', len({x["product_id"] for x in allc}), 'productos;', dict(c))
