#!/usr/bin/env python3
"""Lint the website wiki (docs/wiki/sitio-web).

Checks, without network:
  - every page in paginas/ is linked from index.md, and every index link exists;
  - every relative Markdown link in the wiki resolves to a file;
  - pages carry the template fields (titulo, resumen, fuentes, archivos, tablas,
    revisado) and source cards theirs (titulo, resumen, tipo, revisado); dates
    are YYYY-MM-DD;
  - every `fuentes` id names a card in fuentes/;
  - every `archivos` path exists in the repository;
  - every inline evidence tag is a known one ([GSC], [MC], [GA], [WD], [FL],
    [SO], [Repo…], [Prod…], [Consola…], [Dueño…]);
  - every page has an «En el código y la base» section (warning).

With `--db production` (or `local`) it also checks, read-only through
scripts/db/query.sh, that every `tablas` entry is a table of `public`.

Exit 1 when any error is found; warnings do not fail.

Usage:
  python3 scripts/knowledge/lint_site_wiki.py [--db production]
"""
import argparse
import csv
import io
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WIKI = ROOT / 'docs/wiki/sitio-web'
PAGE_FIELDS = ('titulo', 'resumen', 'fuentes', 'archivos', 'tablas', 'revisado')
SOURCE_FIELDS = ('titulo', 'resumen', 'tipo', 'revisado')
LINK = re.compile(r'\]\(([^)#\s]+)(?:#[^)]*)?\)')
TAG = re.compile(r'`\[([A-Za-zñ]+)(?:[ :][^\]`]*)?\]`')
KNOWN_TAGS = {'GSC', 'MC', 'GA', 'WD', 'FL', 'SO', 'Repo', 'Prod', 'Consola', 'Dueño'}


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


def public_tables(environment):
    sql = ROOT / '.tmp' / 'lint_site_wiki_tables.sql'
    sql.parent.mkdir(exist_ok=True)
    sql.write_text("select tablename from pg_tables where schemaname = 'public';\n")
    run = subprocess.run([str(ROOT / 'scripts/db/query.sh'), environment, '--file', str(sql),
                          '--format', 'csv', '--max-rows', '0'],
                         cwd=ROOT, capture_output=True, text=True, timeout=120)
    sql.unlink(missing_ok=True)
    if run.returncode:
        raise SystemExit('could not read public tables: ' + run.stderr.strip()[-300:])
    rows = list(csv.reader(io.StringIO(run.stdout)))
    return {row[0] for row in rows[1:] if row}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--db', choices=('production', 'local'))
    args = parser.parse_args()

    errors, warnings = [], []
    sources = {p.stem for p in (WIKI / 'fuentes').glob('*.md')}
    pages = sorted((WIKI / 'paginas').glob('*.md'))
    tables = public_tables(args.db) if args.db else None

    for path in sorted(WIKI.rglob('*.md')):
        rel = path.relative_to(WIKI)
        fields, body = front_matter(path)
        for target in LINK.findall(path.read_text()):
            if re.match(r'^[a-z]+:', target):
                continue
            if not (path.parent / target).resolve().exists():
                errors.append(f'{rel}: broken link {target}')
        for tag in TAG.findall(body):
            if tag not in KNOWN_TAGS:
                errors.append(f'{rel}: unknown evidence tag [{tag}]')
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
        for file in fields.get('archivos') or []:
            if not (ROOT / file).exists():
                errors.append(f'{rel}: file {file} does not exist')
        if tables is not None:
            for table in fields.get('tablas') or []:
                if table not in tables:
                    errors.append(f'{rel}: table {table} is not in public ({args.db})')
        if '## En el código y la base' not in body:
            warnings.append(f'{rel}: no «En el código y la base» section')

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
          + ('' if tables is None else f', tables checked against {args.db}'))
    sys.exit(1 if errors else 0)


if __name__ == '__main__':
    main()
