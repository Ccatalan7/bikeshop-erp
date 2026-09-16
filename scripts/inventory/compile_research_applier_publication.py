#!/usr/bin/env python3
"""Compile the research applier publication from its reviewed local candidate.

`migration` wraps scripts/inventory/sql/product_spec_application_candidate.sql
in a standalone forward migration with guards (objects absent, exact source
constraint, no research facts, pgcrypto in extensions, pinned predecessors).
`rehearse` applies that migration to the local database inside a transaction,
reads the installed identities and rolls back. `verifier` writes the read-only
production assertion from those pins. Nothing here seeds readiness, registers
an application or writes a product.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CANDIDATE = ROOT / 'scripts/inventory/sql/product_spec_application_candidate.sql'
VERSION = '20260916140000'
SLUG = 'product_spec_research_applier'
MIGRATION = ROOT / f'supabase/migrations/{VERSION}_{SLUG}.sql'
VERIFIER = ROOT / f'supabase/manual_checks/verification/{VERSION}_{SLUG}.sql'
PINS = ROOT / '.tmp/db' / f'{VERSION}-{SLUG}-pins.json'
FUNCTIONS = ['apply_product_spec_research_v1', 'get_product_spec_research_receipt_v1',
             'get_product_spec_research_application_status_v1']
TABLES = ['product_spec_research_readiness', 'product_spec_research_applications',
          'product_spec_research_receipts']
PREDECESSORS = {'get_product_spec_research_snapshot_v1(uuid)': '981026d3283612b825ff3231d0d9ab41',
                'preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text)': 'a48f8882900af7d7e945ad4cbc561df2',
                'spec_validate_product_internal_v1(uuid)': 'ebe417e4a4d802d7dfc60f40768125e7',
                'user_tenant_id()': 'fac7093d7805560ddb01e2699a287169'}
SOURCE_BEFORE = ("CHECK ((source = ANY (ARRAY['mechanic'::text, 'catalog'::text, 'supplier_text'::text, "
                 "'inferred'::text, 'import'::text, 'name_reading'::text])))")
FUNCTION_STATE = """(select jsonb_agg(jsonb_build_object('identity',p.oid::regprocedure::text,
   'md5',md5(pg_get_functiondef(p.oid)),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,
   'security_definer',p.prosecdef,'volatility',p.provolatile::text,'config',to_jsonb(p.proconfig))
   order by p.oid::regprocedure::text)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname=any(array[%s]))""" % ','.join("'%s'" % f for f in FUNCTIONS)
TABLE_STATE = """(select jsonb_agg(jsonb_build_object('name',c.relname,'owner',pg_get_userbyid(c.relowner),
   'acl',c.relacl::text,'rls',c.relrowsecurity,
   'constraints',(select jsonb_agg(jsonb_build_array(conname,pg_get_constraintdef(oid)) order by conname)
     from pg_constraint where conrelid=c.oid),
   'policies',(select count(*) from pg_policies where schemaname='public' and tablename=c.relname))
   order by c.relname)
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname=any(array[%s]))""" % ','.join("'%s'" % t for t in TABLES)
SOURCE_STATE = """(select pg_get_constraintdef(oid) from pg_constraint
  where conrelid='public.spec_facts'::regclass and conname='spec_facts_source_known')"""


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


SOURCE_AFTER = SOURCE_BEFORE.replace("'name_reading'::text]", "'name_reading'::text, 'research'::text]")
SWAP = """alter table public.spec_facts drop constraint spec_facts_source_known;
alter table public.spec_facts add constraint spec_facts_source_known check(source=any(array[
 'mechanic','catalog','supplier_text','inferred','import','name_reading','research']));"""


def q(value):
    return value.replace("'", "''")


def body():
    """The candidate, made rerunnable: a verification that fails after the SQL
    committed must be completed by rerunning the same file, never by editing
    history, so creation is conditional and every grant is idempotent."""
    lines = CANDIDATE.read_text().splitlines()
    while lines and lines[0].startswith('--'):
        lines.pop(0)
    text = '\n'.join(lines).strip('\n')
    for old, new, count in (('create table public.', 'create table if not exists public.', 3),
                            ('create function public.', 'create or replace function public.', 3)):
        assert text.count(old) == count, old
        text = text.replace(old, new)
    assert text.count(SWAP) == 1
    text = text.replace(SWAP, f"""do $source$ begin
 if {SOURCE_STATE}='{q(SOURCE_AFTER)}' then return; end if;
 {SWAP}
end $source$;""")
    return text


def migration_text():
    predecessors = ' or '.join(
        "md5(pg_get_functiondef('public.%s'::regprocedure))<>'%s'" % (identity, md5)
        for identity, md5 in PREDECESSORS.items())
    pins = json.loads(PINS.read_text())
    installed = ' or '.join(
        "md5(pg_get_functiondef('public.%s'::regprocedure))<>'%s'" % (f['identity'], f['md5'])
        for f in pins['functions'])
    return f"""-- Research applier: readiness gate, registered commands, receipts and the
-- authenticated apply RPC, reviewed on 2026-09-07 and rehearsed locally.
-- Publishing it enables nothing: no readiness row exists, `enabled` defaults
-- to false, registration is a privileged reviewed DB write, and the RPC
-- refuses every command until a closed readiness receipt is registered.
-- No product, fact, reference, template or assignment changes.
-- Rerunnable: when the exact reviewed objects are already installed it only
-- re-applies the idempotent grants, so an interrupted verification can be
-- completed by rerunning this same file.
-- Candidate scripts/inventory/sql/product_spec_application_candidate.sql
-- sha256 {digest(CANDIDATE)}.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
create temp table research_applier_state on commit drop as
 select to_regprocedure('public.apply_product_spec_research_v1(uuid)') is not null as installed;
do $guard$ begin
 if (select installed from research_applier_state) then
  if {installed} or {SOURCE_STATE} is distinct from '{q(SOURCE_AFTER)}' then
   raise exception 'Installed research applier differs from the reviewed candidate';
  end if;
  return;
 end if;
 if to_regclass('public.product_spec_research_readiness') is not null
  or to_regclass('public.product_spec_research_applications') is not null
  or to_regclass('public.product_spec_research_receipts') is not null
  or to_regprocedure('public.apply_product_spec_research_v1(uuid)') is not null
  or to_regprocedure('public.get_product_spec_research_receipt_v1(uuid)') is not null
  or to_regprocedure('public.get_product_spec_research_application_status_v1(uuid)') is not null then
  raise exception 'Research applier objects already exist';
 end if;
 if {SOURCE_STATE} is distinct from '{SOURCE_BEFORE.replace(chr(39), chr(39) * 2)}' then
  raise exception 'spec_facts_source_known differs from the reviewed production state';
 end if;
 if exists(select 1 from public.spec_facts where source='research') then
  raise exception 'Unexpected research-sourced facts before the applier exists';
 end if;
 if (select extnamespace::regnamespace::text from pg_extension where extname='pgcrypto') is distinct from 'extensions' then
  raise exception 'pgcrypto must live in the extensions schema';
 end if;
 if {predecessors} then
  raise exception 'A reviewed predecessor function differs from the pinned production state';
 end if;
end $guard$;

{body()}
-- Production default privileges grant SELECT on new public tables to the
-- read-only codex_test_runner role; the reviewed ACL keeps these tables
-- owner-only, readable solely through the definer RPCs.
do $runner$ begin
 if exists(select 1 from pg_roles where rolname='codex_test_runner') then
  execute 'revoke all on public.product_spec_research_readiness,public.product_spec_research_applications,'
   'public.product_spec_research_receipts from codex_test_runner';
 end if;
end $runner$;

commit;
"""


def rehearse():
    text = migration_text()
    assert text.rstrip().endswith('commit;')
    readback = (text.rstrip()[:-len('commit;')]
                + "select jsonb_build_object('functions',%s,'tables',%s,'source',%s)::text as pins;\nrollback;\n"
                % (FUNCTION_STATE, TABLE_STATE, SOURCE_STATE))
    path = ROOT / '.tmp/db' / f'{VERSION}-{SLUG}-rehearsal.sql'
    path.write_text(readback)
    run = subprocess.run([str(ROOT / 'scripts/db/query.sh'), 'local', '--write', '--file', str(path),
                          '--format', 'csv'], cwd=ROOT, capture_output=True, text=True, timeout=300)
    (ROOT / '.tmp/db' / f'{VERSION}-{SLUG}-rehearsal.log').write_text(run.stdout + run.stderr)
    if run.returncode or 'ERROR' in run.stderr:
        raise SystemExit('Local rehearsal failed: ' + run.stderr[-800:])
    import csv, io
    csv.field_size_limit(1 << 30)
    rows = [r for r in csv.reader(io.StringIO(run.stdout)) if r]
    pins = None
    for i, row in enumerate(rows):
        if row == ['pins'] and i + 1 < len(rows):
            pins = json.loads(rows[i + 1][0])
    if not pins or not pins['functions'] or not pins['tables']:
        raise SystemExit('Rehearsal did not return the installed identities')
    PINS.write_text(json.dumps(pins, ensure_ascii=False, indent=1) + '\n')
    print(json.dumps({'rehearsal': 'rollback', 'functions': len(pins['functions']),
                      'tables': len(pins['tables']), 'source': pins['source']}))


def verifier_text():
    pins = json.loads(PINS.read_text())
    def literal(value):
        return json.dumps(value, ensure_ascii=False, sort_keys=True).replace("'", "''")
    return f"""-- Read-only research applier read-back. Fails before publication (division
-- by zero), passes only when the exact reviewed objects are installed and
-- nothing is enabled, registered or applied.
select 1/(case when {FUNCTION_STATE}='{literal(pins['functions'])}'::jsonb then 1 else 0 end) as exact_applier_functions;
select 1/(case when {TABLE_STATE}='{literal(pins['tables'])}'::jsonb then 1 else 0 end) as exact_applier_tables;
select 1/(case when {SOURCE_STATE}='{pins['source'].replace(chr(39), chr(39) * 2)}' then 1 else 0 end) as research_source_admitted;
select 1/(case when (select count(*) from public.product_spec_research_readiness)=0
  and (select count(*) from public.product_spec_research_applications)=0
  and (select count(*) from public.product_spec_research_receipts)=0
  and (select count(*) from public.spec_facts where source='research')=0 then 1 else 0 end) as nothing_enabled_registered_or_applied;
"""


def main():
    action = sys.argv[1] if len(sys.argv) == 2 else None
    if action == 'migration':
        MIGRATION.write_text(migration_text())
        print(json.dumps({'migration': str(MIGRATION.relative_to(ROOT)), 'sha256': digest(MIGRATION)}))
    elif action == 'rehearse':
        rehearse()
    elif action == 'verifier':
        VERIFIER.write_text(verifier_text())
        print(json.dumps({'verifier': str(VERIFIER.relative_to(ROOT)), 'sha256': digest(VERIFIER)}))
    else:
        raise SystemExit('Usage: compile_research_applier_publication.py migration|rehearse|verifier')


if __name__ == '__main__':
    main()
