#!/usr/bin/env python3
"""Prepare a forward member-profile migration and exact read-back, never deploy.

The local candidate runs inside one rollback solely to read its function modes
and table contracts. Live predecessors are checked by the eventual migration;
no schema copy or local success is asserted to prove production compatibility.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

from compile_product_spec_member_profiles import compile_sql
from compile_product_spec_strict_row_order import compile_sql as strict_sql

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / '.tmp/product-spec-member-publication'
TABLES = ('product_spec_member_profiles', 'product_spec_member_profile_events', 'spec_member_graph_revisions')
DATA_TABLES = ('category_tech_mappings', 'product_spec_references', 'product_spec_save_receipts',
               'products', 'spec_definitions', 'spec_facts', 'spec_fact_values',
               'spec_fact_readings', 'spec_template_fields', 'spec_templates')


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def function_query(names):
    return """select p.oid::regprocedure::text as identity,md5(pg_get_functiondef(p.oid)) as md5,
      pg_get_userbyid(p.proowner) as owner,p.proacl::text as acl,
      p.prosecdef as security_definer,p.provolatile::text as volatility,to_jsonb(p.proconfig) as config
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=any(array[%s])""" % ','.join(map(literal, sorted(names)))


def table_query():
    return """select c.relname as name,pg_get_userbyid(c.relowner) as owner,
      c.relacl::text as acl,c.relrowsecurity as rls,
      (select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
        'not_null',a.attnotnull,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
        from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
        where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped) as columns,
      (select jsonb_agg(jsonb_build_array(conname,pg_get_constraintdef(oid)) order by conname)
        from pg_constraint where conrelid=c.oid) as constraints,
      (select jsonb_agg(jsonb_build_array(indexrelid::regclass::text,pg_get_indexdef(indexrelid)) order by indexrelid::regclass::text)
        from pg_index where indrelid=c.oid) as indexes,
      (select jsonb_agg(jsonb_build_array(policyname,roles,cmd,qual,with_check) order by policyname)
        from pg_policies where schemaname='public' and tablename=c.relname) as policies
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=any(array[%s])""" % ','.join(map(literal, TABLES))


def trigger_query(triggers):
    return """select c.relname as table_name,t.tgname as name,t.tgenabled::text as enabled,
      pg_get_triggerdef(t.oid) as definition
      from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and not t.tgisinternal and (c.relname,t.tgname) in (%s)""" % ','.join(
        '(' + literal(table) + ',' + literal(name) + ')' for name, table in sorted(triggers))


def fingerprint():
    return 'select jsonb_build_object(' + ','.join(
        literal(name) + ",(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public." + name + ' x)'
        for name in DATA_TABLES) + ') as value'


def exact_functions(expected, label, when=None):
    return """do $functions$
declare wanted jsonb; actual jsonb;
begin
 %s
 for wanted in select value from jsonb_array_elements(%s::jsonb) loop
   select jsonb_build_object('identity',p.oid::regprocedure::text,'md5',md5(pg_get_functiondef(p.oid)),
     'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'security_definer',p.prosecdef,
     'volatility',p.provolatile::text,'config',to_jsonb(p.proconfig)) into actual
     from pg_proc p where p.oid=to_regprocedure('public.'||(wanted->>'identity'));
   if actual is distinct from wanted then raise exception '%s: %%',wanted->>'identity'; end if;
 end loop;
end $functions$;
""" % (('if not ('+when+') then return; end if;') if when else '',
       literal(json.dumps(expected, separators=(',', ':'))), label)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'20260914[0-9]{6}', args.version):
        raise ValueError('Use a specific timestamp for this reviewed member-profile work.')
    OUTPUT.mkdir(parents=True, exist_ok=True)
    candidate = compile_sql()
    names = set(re.findall(r'create or replace function public\.(\w+)\(', candidate, re.I))
    triggers = re.findall(r'create (?:constraint )?trigger (\w+)\b[^;]*? on public\.(\w+)', candidate, re.I)
    capture = "select 'MEMBER_MANIFEST='||jsonb_build_object('functions',(select jsonb_agg(to_jsonb(f) order by identity) from (" + function_query(names) + ") f),'tables',(select jsonb_agg(to_jsonb(t) order by name) from (" + table_query() + ") t),'triggers',(select jsonb_agg(to_jsonb(t) order by table_name,name) from (" + trigger_query(triggers) + ") t))::text;"
    probe = OUTPUT / 'manifest-probe.sql'
    probe.write_text('begin;\nset local client_min_messages=warning;\n' + strict_sql() + '\n' + candidate + '\n' + capture + '\nrollback;')
    result = subprocess.run([str(ROOT / 'scripts/db/query.sh'), 'local', '--file', str(probe), '--write'],
                            cwd=ROOT, capture_output=True, text=True)
    (OUTPUT / 'manifest-probe.log').write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError('Local manifest capture failed; inspect manifest-probe.log')
    matches = [line.strip().removeprefix('MEMBER_MANIFEST=') for line in result.stdout.splitlines()
               if line.strip().startswith('MEMBER_MANIFEST=')]
    if len(matches) != 1 or 'ROLLBACK' not in result.stdout:
        raise RuntimeError('Manifest or rollback was not confirmed')
    expected = json.loads(matches[0])
    if (len(expected['functions']) != len(names) or len(expected['tables']) != len(TABLES)
            or len(expected['triggers']) != len(triggers)):
        raise RuntimeError('Unexpected candidate manifest inventory')
    predecessors = json.loads((ROOT / 'scripts/inventory/sql/product_spec_member_profile_predecessors.json').read_text())
    before = [{k: item[k] for k in ('identity', 'md5', 'owner', 'acl', 'security_definer', 'volatility', 'config')}
              for item in predecessors['functions']]
    # CREATE OR REPLACE preserves the replaced object's owner and grants.
    # Their authority is the captured live predecessor, not local defaults.
    old_metadata = {item['identity']: item for item in before}
    for item in expected['functions']:
        if item['identity'] in old_metadata:
            for key in ('owner', 'acl'):
                item[key] = old_metadata[item['identity']][key]
    (OUTPUT / 'expected.json').write_text(json.dumps(expected, indent=2) + '\n')
    old_names = {item['name'] for item in predecessors['functions']}
    installed = '(select installed from member_publication_state)'
    preflight = ("create temp table member_publication_state on commit drop as select "
                 "to_regclass('public.product_spec_member_profiles') is not null as installed;\n")
    preflight += exact_functions(before, 'Member predecessor changed', 'not '+installed)
    preflight += exact_functions(expected['functions'], 'Previously installed member function differs', installed)
    preflight += """do $new_objects$ begin
 if not (select installed from member_publication_state) and (exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname=any(array[%s]))
   or %s) then raise exception 'Partial member objects exist; inspect before proceeding'; end if;
 if exists(select 1 from public.spec_facts where subject_type='product' and subject_scope is not null)
   or exists(select 1 from public.spec_templates where form_contract ? 'member_profiles') then
   raise exception 'Unexpected prior member data or configuration'; end if;
 if md5(pg_get_functiondef('public.spec_rows_schema_validate_internal_v1(jsonb)'::regprocedure))<>'c21cb764086b89a50c5580ad72c0c970'
   or md5(pg_get_functiondef('public.spec_rows_validate_internal_v1(jsonb,jsonb)'::regprocedure))<>'a7e629a22356148871253ad48ef25b3f' then
   raise exception 'Strict-row prerequisite differs from the reviewed production state'; end if;
end $new_objects$;
""" % (','.join(map(literal, sorted(names-old_names))), ' or '.join("to_regclass('public."+name+"') is not null" for name in TABLES))
    assertions = exact_functions(expected['functions'], 'Published member function mismatch')
    table_json = literal(json.dumps(expected['tables'], separators=(',', ':')))
    table_assertion = "select 1/case when (select jsonb_agg(to_jsonb(t) order by name) from ("+table_query()+") t)="+table_json+"::jsonb then 1 else 0 end as exact_member_tables;\n"
    trigger_assertion = "select 1/case when (select jsonb_agg(to_jsonb(t) order by table_name,name) from ("+trigger_query(triggers)+") t)="+literal(json.dumps(expected['triggers'], separators=(',', ':')))+"::jsonb then 1 else 0 end as exact_member_triggers;\n"
    # Recovery from a successful SQL apply followed by failed transport/read-back
    # accepts only the exact installed framework. It never overwrites drift.
    preflight += "do $existing$ begin if (select installed from member_publication_state) then\n"
    for statement in (table_assertion, trigger_assertion):
        preflight += statement.replace('select 1/case', 'perform 1/case', 1).rsplit(' as exact_', 1)[0]+';\n'
    preflight += 'end if; end $existing$;\n'
    migration = ('-- Member profile framework only. No family activation, assignment or product filling.\n'
                 'begin;\nset local lock_timeout=\'5s\';\nset local statement_timeout=\'120s\';\n'
                 'lock table ' + ','.join('public.'+name for name in DATA_TABLES) + ' in share row exclusive mode;\n'
                 + preflight + 'create temp table member_data_before on commit drop as '+fingerprint()+';\n'
                 + candidate + '\n' + assertions + table_assertion + trigger_assertion
                 + 'select 1/case when (select value from member_data_before)=(select value from ('+fingerprint()+') now) then 1 else 0 end as original_rows_unchanged;\n'
                 + "notify pgrst,'reload schema';\ncommit;\n")
    file_name = args.version + '_product_spec_member_profiles.sql'
    path = ROOT / 'supabase/migrations' / file_name
    if path.exists():
        raise RuntimeError('Refusing to overwrite a prepared migration; review it explicitly.')
    path.write_text(migration)
    # The verification is read-only even when invoked without --write.
    readback = '-- Exact read-only framework read-back. It does not create a synthetic product.\n'
    readback += "with expected as (select value as wanted from jsonb_array_elements(" + literal(json.dumps(expected['functions'], separators=(',', ':'))) + "::jsonb)), actual as ("+function_query(names)+")\n"
    readback += 'select 1/case when count(*)='+str(len(names))+' and bool_and(to_jsonb(a)=e.wanted) then 1 else 0 end as exact_member_functions\nfrom expected e left join actual a on a.identity=e.wanted->>\'identity\';\n'
    readback += table_assertion + trigger_assertion
    readback += "select (select count(*) from public.product_spec_member_profiles) as member_profiles,\n (select count(*) from public.product_spec_member_profile_events) as profile_events,\n (select count(*) from public.spec_facts where subject_type='product' and subject_scope is not null) as scoped_product_facts,\n (select count(*) from public.spec_templates where form_contract ? 'member_profiles') as opted_in_templates;\n"
    (ROOT / 'supabase/manual_checks/verification' / file_name).write_text(readback)
    (OUTPUT / 'production-preflight.sql').write_text(function_query(names) + ';\n' +
        "select count(*) as scoped_product_facts from public.spec_facts where subject_type='product' and subject_scope is not null;\n")
    print(path.relative_to(ROOT))
    print('Prepared only; independent review, live preflight and deployment/read-back remain required.')


if __name__ == '__main__':
    main()
