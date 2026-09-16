#!/usr/bin/env python3
"""Compile the reviewer-identity update of the research applier.

`migration` takes apply_product_spec_research_v1 from the reviewed candidate
(scripts/inventory/sql/product_spec_application_candidate.sql, where the
accepted reviewer identities are now codex, claude, claude-peer and owner)
and writes a standalone, rerunnable migration that replaces only that
function, guarded by the md5 the applier publication pinned. `pins` reads
the installed function identity from the local database after the migration
ran there; `verifier` writes the read-only production assertion from it.
Tables, grants, readiness rows and facts are untouched.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CANDIDATE = ROOT / 'scripts/inventory/sql/product_spec_application_candidate.sql'
VERSION = '20260916160000'
SLUG = 'research_reviewer_identities'
MIGRATION = ROOT / f'supabase/migrations/{VERSION}_{SLUG}.sql'
VERIFIER = ROOT / f'supabase/manual_checks/verification/{VERSION}_{SLUG}.sql'
PINS = ROOT / '.tmp/db' / f'{VERSION}-{SLUG}-pins.json'
PREVIOUS_MD5 = 'dd356e99326b'  # prefix of the applier publication pin; full value read from its pins file
PREVIOUS_PINS = ROOT / '.tmp/db/20260916140000-product_spec_research_applier-pins.json'
IDENTITY = 'apply_product_spec_research_v1(uuid)'
FUNCTION_STATE = """(select jsonb_build_object('identity',p.oid::regprocedure::text,
   'md5',md5(pg_get_functiondef(p.oid)),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,
   'security_definer',p.prosecdef,'volatility',p.provolatile::text,'config',to_jsonb(p.proconfig))
  from pg_proc p where p.oid=to_regprocedure('public.apply_product_spec_research_v1(uuid)'))"""


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def previous_md5():
    pins = json.loads(PREVIOUS_PINS.read_text())
    for f in pins['functions']:
        if f['identity'] == IDENTITY:
            assert f['md5'].startswith(PREVIOUS_MD5)
            return f['md5']
    raise SystemExit('previous pin not found')


def function_block():
    text = CANDIDATE.read_text()
    start = text.index('create function public.apply_product_spec_research_v1(')
    end = text.index('end $apply$;', start) + len('end $apply$;')
    block = text[start:end].replace('create function public.', 'create or replace function public.', 1)
    assert "'codex','claude','claude-peer','owner'" in block
    return block


def migration_text():
    old = previous_md5()
    new = json.loads(PINS.read_text())['md5'] if PINS.exists() else None
    installed = f" and md5(pg_get_functiondef('public.{IDENTITY}'::regprocedure))<>'{new}'" if new else ''
    return f"""-- Research applier: the reviewer of a proposal may be codex, claude,
-- claude-peer (a separate Claude session with fresh context) or owner, and
-- must still differ from the researcher. Only apply_product_spec_research_v1
-- changes; tables, grants, readiness, applications, receipts and facts stay.
-- Rerunnable: with the new body already installed it exits.
-- Candidate sha256 {digest(CANDIDATE)}.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
do $guard$ begin
 if to_regprocedure('public.{IDENTITY}') is null then
  raise exception 'The research applier is not installed';
 end if;
 if md5(pg_get_functiondef('public.{IDENTITY}'::regprocedure))<>'{old}'{installed} then
  raise exception 'apply_product_spec_research_v1 differs from the reviewed publication';
 end if;
end $guard$;

{function_block()}
revoke all on function public.apply_product_spec_research_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.apply_product_spec_research_v1(uuid) to authenticated;

commit;
"""


def read_pins(environment):
    sql = f"select {FUNCTION_STATE}::text as pins;\n"
    path = ROOT / '.tmp/db' / f'{VERSION}-{SLUG}-pins.sql'
    path.write_text(sql)
    run = subprocess.run([str(ROOT / 'scripts/db/query.sh'), environment, '--file', str(path), '--format', 'csv',
                          '--max-rows', '0'], cwd=ROOT, capture_output=True, text=True, timeout=120)
    import csv, io
    rows = [r for r in csv.reader(io.StringIO(run.stdout)) if r]
    for i, row in enumerate(rows):
        if row == ['pins'] and i + 1 < len(rows):
            return json.loads(rows[i + 1][0])
    raise SystemExit('pins not returned: ' + run.stderr[-400:])


def verifier_text():
    pins = json.loads(PINS.read_text())
    lit = json.dumps(pins, ensure_ascii=False, sort_keys=True).replace("'", "''")
    return f"""-- Read-only read-back of the reviewer-identity update. Fails before it is
-- published (division by zero) and passes only with the exact function body,
-- owner, ACL and configuration installed, and nothing enabled or applied.
select 1/(case when {FUNCTION_STATE}='{lit}'::jsonb then 1 else 0 end) as exact_apply_function;
select 1/(case when (select count(*) from public.product_spec_research_receipts)=0
  and (select count(*) from public.spec_facts where source='research')=0 then 1 else 0 end) as nothing_applied;
select (select count(*) from public.product_spec_research_readiness) as readiness_rows,
 (select count(*) from public.product_spec_research_readiness where enabled) as enabled_readiness,
 (select count(*) from public.product_spec_research_applications) as registered_applications;
"""


def main():
    action = sys.argv[1] if len(sys.argv) == 2 else None
    if action == 'migration':
        MIGRATION.write_text(migration_text())
        print(json.dumps({'migration': str(MIGRATION.relative_to(ROOT)), 'sha256': digest(MIGRATION)}))
    elif action == 'pins':
        pins = read_pins('local')
        PINS.write_text(json.dumps(pins, ensure_ascii=False, indent=1) + '\n')
        print(json.dumps({'md5': pins['md5'], 'acl': pins['acl']}))
    elif action == 'verifier':
        VERIFIER.write_text(verifier_text())
        print(json.dumps({'verifier': str(VERIFIER.relative_to(ROOT)), 'sha256': digest(VERIFIER)}))
    else:
        raise SystemExit('Usage: compile_research_reviewer_publication.py migration|pins|verifier')


if __name__ == '__main__':
    main()
