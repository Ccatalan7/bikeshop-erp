#!/usr/bin/env python3
"""Fail when the app calls a database function or table production lacks.

A migration in git is not a deployed migration. On 2026-10-14 the client had
been calling four functions since July whose migrations were never applied
(`get_storefront_publication_status`, `retry_storefront_publication`,
`ensure_default_footer_navigation`, `get_my_employee_self_service`), and the
screens that use them showed «no se pudo consultar» for three months. This
check reads every `.rpc('name'` / `...Rpc = 'name'` and `.from('name')` in the
shipped Dart code and asks production whether each one exists (functions in
`public`, tables/views in `public`, storage buckets).

Usage: python3 -I scripts/db/client_schema_drift.py [--root DIR]
Exit 0 when nothing is missing, 1 when something is, 2 when production could
not be read. Reads only; never prints credentials.
"""

from __future__ import annotations

import argparse
import csv
import io
import os
import re
import subprocess
import sys

SOURCE_DIRS = ("lib", "packages")
RPC_PATTERNS = (
    re.compile(r"\.rpc(?:<[^>]*>)?\(\s*'([a-z0-9_]+)'"),
    re.compile(r"static const (?:String )?\w*[Rr]pc\w* = '([a-z0-9_]+)'"),
)
FROM_PATTERN = re.compile(r"\.from\(\s*'([a-z0-9_\-]+)'\s*\)")


def scan(root: str) -> tuple[dict[str, str], dict[str, str]]:
    rpcs: dict[str, str] = {}
    relations: dict[str, str] = {}
    for base in SOURCE_DIRS:
        for dirpath, dirnames, filenames in os.walk(os.path.join(root, base)):
            dirnames[:] = [
                d for d in dirnames if d not in {".dart_tool", "build", "test"}
            ]
            for filename in filenames:
                if not filename.endswith(".dart"):
                    continue
                path = os.path.join(dirpath, filename)
                with open(path, encoding="utf-8", errors="ignore") as handle:
                    text = handle.read()
                relative = os.path.relpath(path, root)
                for pattern in RPC_PATTERNS:
                    for match in pattern.finditer(text):
                        rpcs.setdefault(match.group(1), relative)
                for match in FROM_PATTERN.finditer(text):
                    relations.setdefault(match.group(1), relative)
    return rpcs, relations


def sql_array(names: list[str]) -> str:
    quoted = ",".join("'" + name.replace("'", "''") + "'" for name in names)
    return f"array[{quoted}]::text[]"


def missing_in_production(root: str, rpcs: list[str], relations: list[str]):
    sql = f"""
select 'function' as kind, name
  from unnest({sql_array(rpcs)}) name
 where not exists (
   select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = name)
union all
select 'table' as kind, name
  from unnest({sql_array(relations)}) name
 where not exists (
   select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = name)
   and not exists (select 1 from storage.buckets b where b.id = name)
order by 1, 2
"""
    result = subprocess.run(
        [
            "bash",
            os.path.join(root, "scripts/db/query.sh"),
            "production",
            "--format",
            "csv",
            "--max-rows",
            "0",
            "--sql",
            sql,
        ],
        cwd=root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr[-2000:])
        return None
    rows = list(csv.reader(io.StringIO(result.stdout)))
    return [
        (row[0], row[1])
        for row in rows
        if len(row) == 2 and row[0] in {"function", "table"}
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        default=os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")),
    )
    args = parser.parse_args()
    rpcs, relations = scan(args.root)
    missing = missing_in_production(args.root, sorted(rpcs), sorted(relations))
    if missing is None:
        print("No se pudo leer producción: el chequeo no es concluyente.", file=sys.stderr)
        return 2
    print(
        f"La app llama {len(rpcs)} funciones y {len(relations)} tablas o buckets."
    )
    if not missing:
        print("Todas existen en producción.")
        return 0
    print("Faltan en producción:")
    for kind, name in missing:
        source = (rpcs if kind == "function" else relations).get(name, "?")
        print(f"  {kind:8} {name}  ← {source}")
    print(
        "Aplica su migración con scripts/db/deploy_migration.sh o quita la "
        "llamada; una migración en git no es una migración desplegada."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
