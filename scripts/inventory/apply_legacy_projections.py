#!/usr/bin/env python3
"""Project retired (`legacy`) wheel and cog observations onto their scalar
successors, product by product, where the projection is a unit conversion or
an ISO 5775 table lookup and never a guess.

The 2026-09 templates retired `wheel_size`, `tire_width_in`, `valve_type`,
`valve_length_mm`, `tube_width_*`, `spoke_gauge`, `hub_spacing_mm` and
`freehub_type` to role `legacy`, and every consumer (storefront, workshop,
matcher) excludes `legacy`. The supplier and import observations that lived
there are still evidence; this applier writes the same observation under the
successor key, with the same `source` and `confirmed = false`, only where the
successor is still empty.

Rules (each projection records which one it used):

- `bsd`: a wheel-size label becomes an ISO bead seat diameter. `700c`, `29"`
  and `27.5"` are one diameter each. `26"`, `24"`, `20"`, `16"` and `12"` cover
  several ISO diameters, so the product name decides by its width notation
  (ISO 5775 / Sheldon Brown): a decimal width (`26 x 2.10`) is the decimal
  series (559, 507, 406, 305), a fractional width (`26 x 1 3/8`, `20 x 1 3/8`,
  `16 x 1 3/8`, `12 1/2 x 2 1/4`) is the fractional series (590, 451, 349, 203).
  `24 x 1 3/8` is left alone (540 and 520 both exist). A name that shows the
  ISO number itself (`622X30`) wins. Anything else is not projected.
- `inch_to_mm`: a width in inches becomes millimetres (x 25.4, one decimal).
- `label_to_number`: a numeric option label (`48`, `135`) becomes the number.
- `option`: an option label becomes its successor's option (valve standard,
  drive receiver kind, spoke head).
- `copy_text`: an option label becomes the successor's free text (spoke gauge).
- `tube_fit_row`: size label + width range become one `tube_fit_rows` row.

Usage:
  apply_legacy_projections.py --input projection-input.csv \
      --version 20260916200000 --name legacy_projections_wheels_cogs \
      --record docs/.../legacy-projections-2026-09-16.json
Writes the migration, its verifier and a dry-run file (same statements inside
begin/rollback with a diagnostic read-back) and prints a summary.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

UNAMBIGUOUS_BSD = {'700c': 622, '29"': 622, '27.5"': 584, '650b': 584}
DECIMAL_BSD = {'26"': 559, '24"': 507, '20"': 406, '16"': 305, '12"': 203}
FRACTIONAL_BSD = {'26"': 590, '20"': 451, '16"': 349, '12"': 203}
KNOWN_ISO = (203, 305, 349, 355, 406, 451, 507, 520, 540, 559, 571, 584, 590, 597, 622, 630, 635)

VALVE_OPTION = {
    'Presta (francesa)': 'Francesa (Presta)',
    'Schrader (americana / auto)': 'Auto (Schrader / americana)',
    'Dunlop (inglesa)': 'Dunlop (inglesa)',
}
RECEIVER_OPTION = {
    'Shimano HG': 'Núcleo de cassette',
    'Shimano HG Road 11': 'Núcleo de cassette',
    'Micro Spline': 'Núcleo de cassette',
    'SRAM XD': 'Núcleo de cassette',
    'SRAM XDR': 'Núcleo de cassette',
    'Campagnolo': 'Núcleo de cassette',
    'Campagnolo N3W': 'Núcleo de cassette',
    'Rueda libre roscada': 'Rosca para piñón (rueda libre)',
    'Rosca fija / contratuerca': 'Rosca para piñón fijo',
    'Driver BMX': 'Driver BMX',
}
SPOKE_HEAD_OPTION = {'J-Bend': 'J-Bend', 'Straight Pull': 'Straight Pull'}
POSITION_OPTION = {'Delantera': 'Delantera', 'Trasera': 'Trasera', 'Universal': 'Universal'}

# A fractional width: whole inches, a separator, a one-digit numerator and a
# denominator of 2, 4, 8 or 16 that is not the start of a decimal (`1 3/8`,
# `1-3/8`, `1.3/8`, `1"3/8`, `2.1/4`). A decimal range such as `1.95/2.125` or
# `1.5/2.2` never matches: the digit after the slash continues as a decimal.
FRACTION_RE = re.compile(r'(?<![0-9])\d{1,2}[\s\-."\u201d]?\s*[1-3]\s*/\s*(?:16|2|4|8)(?![0-9]|[.,]\d)')
# An ISO diameter written in the name, in ETRTO form (`54-559`, `40/63-559`)
# or as a rim size (`622X30`).
ISO_IN_NAME_RE = re.compile(r'(?:\d{2}\s*[-\u2013]\s*)(203|305|349|355|406|451|507|520|540|559|571|584|590|597|622|630|635)(?![0-9])'
                            r'|(?<![0-9])(203|305|349|355|406|451|507|520|540|559|571|584|590|597|622|630|635)(?=\s*[xX\u00d7]\s*\d)')


def sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def bsd_for(label: str, name: str) -> tuple[int | None, str]:
    """(bsd, rule detail) or (None, reason)."""
    iso = ISO_IN_NAME_RE.search(name or '')
    if iso:
        return int(iso.group(1) or iso.group(2)), 'iso number in the name'
    if label in UNAMBIGUOUS_BSD:
        return UNAMBIGUOUS_BSD[label], f'{label} is one ISO diameter'
    if label in DECIMAL_BSD:
        if FRACTION_RE.search(name or ''):
            if label in FRACTIONAL_BSD:
                return FRACTIONAL_BSD[label], f'{label} with a fractional width'
            return None, f'{label} fractional width is ambiguous (540/520)'
        if re.search(r'\d[.,]\d', name or ''):
            return DECIMAL_BSD[label], f'{label} with a decimal width'
        return None, f'{label} without a width notation in the name'
    return None, f'label {label!r} has no ISO mapping'


def inch_to_mm(value: str) -> float | None:
    try:
        inches = float(value)
    except (TypeError, ValueError):
        return None
    if inches <= 0 or inches > 6:
        return None
    return round(inches * 25.4, 1)


def number(value: str) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def fmt(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else f'{value:g}'


def project(product: dict) -> list[dict]:
    """Every projection for one product: dicts with successor key, kind, value."""
    facts = product['facts']
    tkey = product['tkey']
    name = product['name'] or ''
    out: list[dict] = []

    def legacy(key):
        fact = facts.get(key)
        if not fact or fact.get('role') != 'legacy':
            return None
        return fact

    def has(key):
        return key in facts

    def add(successor, kind, value, legacy_key, legacy_fact, rule):
        out.append({
            'successor': successor, 'kind': kind, 'value': value,
            'legacy_key': legacy_key, 'legacy_value': legacy_fact['v'],
            'source': legacy_fact['src'], 'rule': rule,
        })

    if tkey in ('tire', 'rim', 'rim_strip'):
        size = legacy('wheel_size')
        if size and not has('bead_seat_diameter_mm'):
            bsd, rule = bsd_for(size['v'], name)
            if bsd is not None:
                add('bead_seat_diameter_mm', 'number', bsd, 'wheel_size', size, f'bsd: {rule}')
            else:
                out.append({'skipped': 'bead_seat_diameter_mm', 'legacy_key': 'wheel_size',
                            'legacy_value': size['v'], 'reason': rule})
    if tkey == 'tire':
        width = legacy('tire_width_in')
        if width and not has('tire_width_mm'):
            mm = inch_to_mm(width['v'])
            if mm is not None:
                add('tire_width_mm', 'number', mm, 'tire_width_in', width, 'inch_to_mm')
    if tkey == 'tube':
        size = legacy('wheel_size')
        lo_in, hi_in = legacy('tube_width_min_in'), legacy('tube_width_max_in')
        lo_mm, hi_mm = legacy('tube_width_min_mm'), legacy('tube_width_max_mm')
        if size and not has('tube_fit_rows'):
            bsd, rule = bsd_for(size['v'], name)
            lo = hi = None
            if lo_mm and hi_mm:
                lo, hi = number(lo_mm['v']), number(hi_mm['v'])
            elif lo_in and hi_in:
                lo, hi = inch_to_mm(lo_in['v']), inch_to_mm(hi_in['v'])
            if bsd is None:
                out.append({'skipped': 'tube_fit_rows', 'legacy_key': 'wheel_size',
                            'legacy_value': size['v'], 'reason': rule})
            elif lo is None or hi is None or lo > hi:
                out.append({'skipped': 'tube_fit_rows', 'legacy_key': 'wheel_size',
                            'legacy_value': size['v'], 'reason': 'no usable width range'})
            else:
                # The row validator wants each row as {id, values, sources} with
                # every numeric cell as text (numeric JSON is rejected).
                add('tube_fit_rows', 'rows',
                    {'schema_version': 1, 'rows': [{
                        'id': f'bsd-{bsd}',
                        'values': {'bead_seat_diameter_mm': str(bsd),
                                   'width_min_mm': fmt(lo), 'width_max_mm': fmt(hi)},
                        'sources': []}]},
                    'wheel_size', size, f'tube_fit_row: {rule}; widths {"mm" if lo_mm else "inch_to_mm"}')
    if tkey in ('tube', 'tubeless_valve'):
        valve = legacy('valve_type')
        if valve and not has('valve_standard') and valve['v'] in VALVE_OPTION:
            add('valve_standard', 'option', VALVE_OPTION[valve['v']], 'valve_type', valve, 'option')
        length = legacy('valve_length_mm')
        if length and not has('valve_length_mm_value'):
            n = number(length['v'])
            if n is not None and 20 <= n <= 120:
                add('valve_length_mm_value', 'number', n, 'valve_length_mm', length, 'label_to_number')
    if tkey in ('cassette', 'freewheel'):
        speeds = legacy('drivetrain_speeds')
        if speeds and not has('sprocket_count'):
            n = number(speeds['v'])
            if n is not None and n.is_integer() and 1 <= n <= 13:
                add('sprocket_count', 'number', n, 'drivetrain_speeds', speeds, 'label_to_number')
    if tkey == 'hub':
        spacing = legacy('hub_spacing_mm')
        if spacing and not has('hub_old_mm'):
            n = number(spacing['v'])
            if n is not None:
                add('hub_old_mm', 'number', n, 'hub_spacing_mm', spacing, 'label_to_number')
        holes = legacy('spoke_holes')
        if holes and not has('spoke_hole_count'):
            n = number(holes['v'])
            if n is not None:
                add('spoke_hole_count', 'number', n, 'spoke_holes', holes, 'label_to_number')
        position = legacy('wheel_position')
        if position and not has('hub_package_position') and position['v'] in POSITION_OPTION:
            add('hub_package_position', 'option', POSITION_OPTION[position['v']], 'wheel_position', position, 'option')
        freehub = legacy('freehub_type')
        if freehub and not has('hub_drive_receiver_kind') and freehub['v'] in RECEIVER_OPTION:
            add('hub_drive_receiver_kind', 'option', RECEIVER_OPTION[freehub['v']], 'freehub_type', freehub, 'option')
    if tkey == 'rim':
        holes = legacy('spoke_holes')
        if holes and not has('spoke_hole_count'):
            n = number(holes['v'])
            if n is not None:
                add('spoke_hole_count', 'number', n, 'spoke_holes', holes, 'label_to_number')
    if tkey == 'spoke':
        gauge = legacy('spoke_gauge')
        if gauge and not has('spoke_gauge_designation'):
            add('spoke_gauge_designation', 'text', gauge['v'], 'spoke_gauge', gauge, 'copy_text')
        bend = legacy('spoke_bend_type')
        if bend and not has('spoke_head_interface') and bend['v'] in SPOKE_HEAD_OPTION:
            add('spoke_head_interface', 'option', SPOKE_HEAD_OPTION[bend['v']], 'spoke_bend_type', bend, 'option')
    return out


def fact_insert(product: dict, p: dict) -> str:
    tenant = sql_text(product['tenant_id'])
    pid = sql_text(product['pid'])
    key = sql_text(p['successor'])
    src = sql_text(p['source'])
    guard = (f"not exists (select 1 from public.spec_facts x where x.tenant_id={tenant} and x.subject_type='product' "
             f"and x.subject_id={pid} and x.subject_scope is null and x.spec_definition_id=d.id)")
    base = (f"select {tenant}, 'product', {pid}::uuid, d.id, {{cols}}, {src}, false "
            f"from public.spec_definitions d where d.tenant_id is null and d.key={key} and {guard}")
    if p['kind'] == 'number':
        return (f"insert into public.spec_facts (tenant_id, subject_type, subject_id, spec_definition_id, value_number, source, confirmed) "
                + base.format(cols=f"{fmt(p['value'])}::numeric") + ';')
    if p['kind'] == 'text':
        return (f"insert into public.spec_facts (tenant_id, subject_type, subject_id, spec_definition_id, value_text, source, confirmed) "
                + base.format(cols=sql_text(str(p['value']))) + ';')
    if p['kind'] == 'rows':
        payload = json.dumps(p['value'], ensure_ascii=False, separators=(',', ':'))
        return (f"insert into public.spec_facts (tenant_id, subject_type, subject_id, spec_definition_id, value_json, source, confirmed) "
                + base.format(cols=f"{sql_text(payload)}::jsonb") + ';')
    if p['kind'] == 'option':
        label = sql_text(p['value'])
        return (f"with f as (insert into public.spec_facts (tenant_id, subject_type, subject_id, spec_definition_id, source, confirmed) "
                f"select {tenant}, 'product', {pid}::uuid, d.id, {src}, false from public.spec_definitions d "
                f"where d.tenant_id is null and d.key={key} and {guard} returning id, spec_definition_id) "
                f"insert into public.spec_fact_values (fact_id, value_id, position) "
                f"select f.id, v.id, 0 from f join public.spec_definition_values v on v.spec_definition_id=f.spec_definition_id "
                f"and v.is_active and v.label={label};")
    raise ValueError(p['kind'])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', required=True)
    ap.add_argument('--version', required=True)
    ap.add_argument('--name', required=True)
    ap.add_argument('--record', required=True)
    args = ap.parse_args()

    rows = list(csv.DictReader(open(args.input, encoding='utf-8')))
    products = [{**r, 'facts': json.loads(r['facts'])} for r in rows]

    projections, skipped = [], []
    option_labels: dict[str, set[str]] = defaultdict(set)
    for product in products:
        for p in project(product):
            entry = {'product_id': product['pid'], 'sku': product['sku'], 'name': product['name'],
                     'template': product['tkey'], **p}
            if 'skipped' in p:
                skipped.append(entry)
            else:
                projections.append(entry)
                if p['kind'] == 'option':
                    option_labels[p['successor']].add(p['value'])

    by_pair = Counter((p['template'], p['legacy_key'], p['successor']) for p in projections)
    touched = sorted({p['product_id'] for p in projections})

    stem = f"{args.version}_{args.name}"
    mig = ROOT / 'supabase/migrations' / f'{stem}.sql'
    ver = ROOT / 'supabase/manual_checks/verification' / f'{stem}.sql'
    dry = ROOT / '.tmp/db' / f'{stem}-dry-run.sql'
    dry.parent.mkdir(parents=True, exist_ok=True)

    asserts = []
    for key, labels in sorted(option_labels.items()):
        for label in sorted(labels):
            asserts.append(
                f"  if not exists (select 1 from public.spec_definitions d join public.spec_definition_values v on v.spec_definition_id=d.id and v.is_active "
                f"where d.tenant_id is null and d.key={sql_text(key)} and v.label={sql_text(label)}) then "
                f"raise exception 'missing option % for %', {sql_text(label)}, {sql_text(key)}; end if;")
    statements = [fact_insert(pr, p) for pr in products for p in (x for x in projections if x['product_id'] == pr['pid'])]

    header = [
        f"-- Legacy observations projected onto their successor keys ({len(projections)} facts, {len(touched)} products).",
        "-- Same source and confirmed=false as the retired fact; only where the successor is empty.",
        "-- Rerunnable: every insert is guarded by the absence of a successor fact.",
        f"-- Generated by scripts/inventory/apply_legacy_projections.py --version {args.version}; record in {Path(args.record).name}.",
    ]
    body = ["set local lock_timeout='5s';", "set local statement_timeout='600s';",
            "set local role postgres;" if False else "-- runs as the migration role",
            "do $$ begin"] + asserts + ["end $$;"] + statements

    ids_list = ', '.join(sql_text(i) + '::uuid' for i in touched)
    # Remaining gaps among the touched products: (definition, product) pairs this migration must fill.
    expected_pairs = ' union all '.join(
        f"select {sql_text(p['product_id'])}::uuid as pid, {sql_text(p['successor'])} as key" for p in projections)
    gap_sql = (f"select count(*) from ({expected_pairs}) e join public.spec_definitions d on d.tenant_id is null and d.key=e.key "
               f"where not exists (select 1 from public.spec_facts f where f.subject_type='product' and f.subject_scope is null "
               f"and f.subject_id=e.pid and f.spec_definition_id=d.id)")

    mig.write_text('\n'.join(header + ['begin;'] + body + ['commit;']) + '\n', encoding='utf-8')
    ver.write_text('\n'.join([
        f"-- Verifier: fails (division by zero) while any projected successor fact is still missing ({len(projections)} expected).",
        f"select 1/(case when ({gap_sql})=0 then 1 else 0 end) as ok;",
    ]) + '\n', encoding='utf-8')
    # The product constraint trigger is deferred; under rollback it would never
    # run. Forcing constraints immediate makes every insert face the validator.
    dry.write_text('\n'.join(['begin;', 'set constraints all immediate;'] + body + [
        f"select 'GAP_AFTER='||({gap_sql}) as diag;",
        f"select 'TOUCHED='||count(*) as diag from (select unnest(array[{ids_list}]) as pid) p;",
        'rollback;']) + '\n', encoding='utf-8')

    record = {
        'version': args.version, 'name': args.name, 'input': str(args.input),
        'products_in_scope': len(products), 'products_touched': len(touched),
        'projections': len(projections), 'skipped': len(skipped),
        'by_pair': [{'template': t, 'legacy_key': l, 'successor': s, 'facts': n} for (t, l, s), n in sorted(by_pair.items())],
        'rules': Counter(p['rule'].split(':')[0] for p in projections),
        'skipped_reasons': Counter(s['reason'] for s in skipped),
        'entries': projections, 'skipped_entries': skipped,
    }
    Path(args.record).write_text(json.dumps(record, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    print(f'projections {len(projections)} in {len(touched)} products; skipped {len(skipped)}')
    for (t, l, s), n in sorted(by_pair.items()):
        print(f'  {t:14} {l:20} -> {s:24} {n}')
    for reason, n in record['skipped_reasons'].items():
        print(f'  skipped {n:4}  {reason}')
    print('migration', mig.relative_to(ROOT))
    print('verifier ', ver.relative_to(ROOT))
    print('dry run  ', dry.relative_to(ROOT))


if __name__ == '__main__':
    main()
