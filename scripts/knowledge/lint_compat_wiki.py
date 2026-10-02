#!/usr/bin/env python3
"""Lint the compatibility wiki (docs/wiki/compatibilidad).

Checks, without network:
  - every page in paginas/ is linked from index.md, and every index link exists;
  - every relative Markdown link in the wiki resolves to a file;
  - pages carry the template fields (titulo, resumen, fuentes, k, claves_bici,
    claves_producto, revisado) and source cards theirs (titulo, resumen, tipo,
    revisado); dates are YYYY-MM-DD;
  - every `fuentes` id names a card in fuentes/;
  - every K-id (front matter or inline `[K14]`) exists in the evidence register
    docs/architecture/bicycle-compatibility-knowledge.md;
  - every `claves_bici` key appears as a quoted string in lib/.

With `--db production` (or `local`) it also reads the global spec_definitions
keys through scripts/db/query.sh (read-only) and checks every `claves_producto`.

Exit 1 when any error is found; warnings do not fail.

Usage:
  python3 scripts/knowledge/lint_compat_wiki.py [--db production]
"""
import argparse
import csv
import io
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WIKI = ROOT / 'docs/wiki/compatibilidad'
REGISTER = ROOT / 'docs/architecture/bicycle-compatibility-knowledge.md'
PAGE_FIELDS = ('titulo', 'resumen', 'fuentes', 'k', 'claves_bici', 'claves_producto', 'revisado')
SOURCE_FIELDS = ('titulo', 'resumen', 'tipo', 'revisado')
LINK = re.compile(r'\]\(([^)#\s]+)(?:#[^)]*)?\)')
K_INLINE = re.compile(r'\[K(\d{2,3})\]')


def front_matter(path):
    text = path.read_text()
    if not text.startswith('---\n'):
        return None, text
    end = text.find('\n---\n', 4)
    if end < 0:
        return None, text
    fields = {}
    for line in text[4:end].splitlines():
        if ':' not in line:
            continue
        key, value = line.split(':', 1)
        value = value.strip()
        if value.startswith('[') and value.endswith(']'):
            value = [item.strip() for item in value[1:-1].split(',') if item.strip()]
        fields[key.strip()] = value
    return fields, text[end + 5:]


def spec_keys(environment):
    sql = ROOT / '.tmp' / 'lint_compat_wiki_keys.sql'
    sql.parent.mkdir(exist_ok=True)
    sql.write_text('select key from public.spec_definitions where tenant_id is null;\n')
    run = subprocess.run([str(ROOT / 'scripts/db/query.sh'), environment, '--file', str(sql),
                          '--format', 'csv', '--max-rows', '0'],
                         cwd=ROOT, capture_output=True, text=True, timeout=120)
    sql.unlink(missing_ok=True)
    if run.returncode:
        raise SystemExit('could not read spec_definitions: ' + run.stderr.strip()[-300:])
    rows = list(csv.reader(io.StringIO(run.stdout)))
    return {row[0] for row in rows[1:] if row}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--db', choices=('production', 'local'))
    args = parser.parse_args()

    errors, warnings = [], []
    register = REGISTER.read_text()
    known_k = {int(n) for n in re.findall(r'^#{2,3} K(\d+)\b', register, re.MULTILINE)}
    sources = {p.stem for p in (WIKI / 'fuentes').glob('*.md')}
    pages = sorted((WIKI / 'paginas').glob('*.md'))
    lib_text = '\n'.join(p.read_text(errors='ignore') for p in (ROOT / 'lib').rglob('*.dart'))
    product_keys = spec_keys(args.db) if args.db else None

    for path in sorted(WIKI.rglob('*.md')):
        rel = path.relative_to(WIKI)
        fields, body = front_matter(path)
        for target in LINK.findall(path.read_text()):
            if re.match(r'^[a-z]+:', target):
                continue
            if not (path.parent / target).resolve().exists():
                errors.append(f'{rel}: broken link {target}')
        for number in K_INLINE.findall(body):
            if int(number) not in known_k:
                errors.append(f'{rel}: [K{number}] is not in the evidence register')
        if rel.parts[0] == 'paginas':
            required = PAGE_FIELDS
        elif rel.parts[0] == 'fuentes':
            required = SOURCE_FIELDS
        else:
            continue
        if fields is None:
            errors.append(f'{rel}: missing front matter')
            continue
        for field in required:
            if field not in fields:
                errors.append(f'{rel}: missing field {field}')
        if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', str(fields.get('revisado', ''))):
            errors.append(f'{rel}: revisado must be YYYY-MM-DD')
        if rel.parts[0] != 'paginas':
            continue
        for source in fields.get('fuentes') or []:
            if source not in sources:
                errors.append(f'{rel}: unknown source {source}')
        for k in fields.get('k') or []:
            if not re.fullmatch(r'K\d+', k) or int(k[1:]) not in known_k:
                errors.append(f'{rel}: {k} is not in the evidence register')
        for key in fields.get('claves_bici') or []:
            if f"'{key}'" not in lib_text and f'"{key}"' not in lib_text:
                errors.append(f'{rel}: bike key {key} is not used in lib/')
        if product_keys is not None:
            for key in fields.get('claves_producto') or []:
                if key not in product_keys:
                    errors.append(f'{rel}: product key {key} is not a global spec_definitions key')
        if '## En Vinabike' not in body and path.name != 'modelo-vinabike.md':
            warnings.append(f'{rel}: no «En Vinabike» section')

    index = (WIKI / 'index.md').read_text()
    linked = {Path(t).name for t in LINK.findall(index) if t.startswith('paginas/')}
    for page in pages:
        if page.name not in linked:
            errors.append(f'paginas/{page.name}: not linked from index.md')

    for line in warnings:
        print('warning:', line)
    for line in errors:
        print('error:', line)
    print(f'{len(pages)} pages, {len(sources)} sources, {len(errors)} errors, {len(warnings)} warnings'
          + ('' if product_keys is None else f', {len(product_keys)} spec keys checked against {args.db}'))
    sys.exit(1 if errors else 0)


if __name__ == '__main__':
    main()
