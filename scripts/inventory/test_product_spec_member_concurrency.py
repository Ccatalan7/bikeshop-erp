#!/usr/bin/env python3
"""Two real LOCAL connections, exact fixture cleanup and function restoration.

The candidate must be visible to both sessions, so this probe installs it only
for the duration of the schedules. It captures the local predecessors first,
refuses any preexisting member extension, and restores those exact bodies and
ACLs afterwards. This is not a production command or a schema-copy proof.
"""
import json
from pathlib import Path
import re

import test_product_spec_publication_concurrency as transport
from compile_product_spec_member_profiles import compile_sql
from compile_product_spec_strict_row_order import compile_sql as strict_sql

ROOT = transport.ROOT
OUTPUT = ROOT / '.tmp/product-spec-member-concurrency'
TABLES = ('product_spec_member_profiles', 'product_spec_member_profile_events',
          'spec_member_graph_revisions')
OLD_NAMES = {
    'get_product_spec_editor_context_v2', 'save_product_with_specs_v1',
    'spec_product_payload_internal_v1', 'spec_template_product_payload_internal_v1',
    'spec_validate_product_internal_v1', 'spec_write_payload_internal_v2',
    'spec_rows_schema_validate_internal_v1', 'spec_rows_validate_internal_v1',
}


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def functions(names):
    return """select p.proname as name,
      format('%%I.%%I(%%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)) as signature,
      pg_get_functiondef(p.oid) as body,md5(pg_get_functiondef(p.oid)) as md5,
      p.proacl::text as acl,p.proowner::regrole::text as owner
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=any(array[%s]) order by p.proname""" % ','.join(map(literal, sorted(names)))


def write_sql(name, sql):
    path = OUTPUT / (name + '.sql')
    path.write_text(sql)
    return path


def fixture():
    source = (ROOT / 'supabase/tests/product_spec_member_profiles.sql').read_text()
    start = source.index("select set_config('request.jwt.claims','{}',true);")
    split = source.index('create temp table member_root_values')
    end = source.index('set local role authenticated;')
    def namespace(text):
        return (text.replace('99e10000-', '99e20000-')
                    .replace('member_test_', 'member_race_')
                    .replace('member_part_test', 'member_part_race')
                    .replace('member_other_test', 'member_other_race')
                    .replace('member_root_test', 'member_root_race')
                    .replace('member-test-reference', 'member-race-reference')
                    .replace('MEMBER-KIT', 'MEMBER-RACE-KIT')
                    .replace('spec-a@example.invalid', 'member-race-a@example.invalid')
                    .replace('spec-b@example.invalid', 'member-race-b@example.invalid'))
    baseline = 'begin;\n' + namespace(source[start:split]) + '\nset constraints all immediate;\ncommit;\n'
    helpers = namespace(source[split:end])
    return baseline, helpers


def schedules(helpers):
    # SQLSTATE is the assertion; exception text is retained as diagnostic evidence.
    attempt = """
create temp table member_old_revision as select spec_revision as revision from public.products
 where id='99e20000-0000-4000-8000-000000000020';
grant select on member_old_revision to authenticated;
create function pg_temp.member_try(p_route text) returns jsonb language plpgsql as $try$
declare answer jsonb;
begin
 if p_route='save' then
   answer:=pg_temp.member_save('race-save',jsonb_build_array(pg_temp.member_profile('r1')));
 elsif p_route='stale' then
   answer:=pg_temp.member_save('race-stale',jsonb_build_array(pg_temp.member_profile('r1')),
     p_revision=>(select revision from member_old_revision));
 elsif p_route='parent' then
   update public.spec_templates set form_contract=form_contract-'member_profiles'
     where id='99e20000-0000-4000-8000-000000000050';
 elsif p_route='child' then
   update public.spec_templates set key='member_race_changed'
     where id='99e20000-0000-4000-8000-000000000060';
 elsif p_route='bounds' then
   update public.spec_definitions set validation_rules='{"positive":true,"max":8}'
     where id='99e20000-0000-4000-8000-000000000052';
 elsif p_route='category-pending' then
   update public.category_tech_mappings set status='pending'
     where tenant_id='99e20000-0000-4000-8000-000000000001'
       and category_id='99e20000-0000-4000-8000-000000000010';
 elsif p_route='category-create' then
   answer:=pg_temp.member_save('race-category-create',jsonb_build_array(pg_temp.member_profile('r2','9')));
 else raise exception 'Unknown local race route'; end if;
 set constraints all immediate;
 return jsonb_build_object('sqlstate','00000','result',answer);
exception when others then
 return jsonb_build_object('sqlstate',sqlstate,'message',sqlerrm);
end $try$;
grant execute on function pg_temp.member_try(text) to authenticated;
"""
    setup = """
set client_min_messages=warning;
select set_config('search_path',format('public,%I,pg_temp',n.nspname),false)
 from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='dblink';
select dblink_connect('member_graph_b',format(
 'hostaddr=%s port=%s dbname=%s user=%s password=%s application_name=member_graph_b',
 inet_server_addr(),inet_server_port(),current_database(),current_user,
 coalesce(nullif(current_setting('app.pgtap_database_password',true),''),'postgres')));
"""
    setup += helpers + attempt
    setup += 'select dblink_exec(\'member_graph_b\',$helpers$\n' + helpers + attempt + '\n$helpers$);\n'
    setup += 'create temp table member_race_results(probe text,expected text,result jsonb);\n'
    auth = """set local request.jwt.claims='{"sub":"99e20000-0000-4000-8000-000000000091","role":"authenticated"}';
set local request.jwt.claim.sub='99e20000-0000-4000-8000-000000000091';
set local role authenticated;"""

    def begin_b(*, user=False, rr=False):
        sql = 'begin isolation level repeatable read;' if rr else 'begin;'
        sql += "set local lock_timeout='750ms';set local statement_timeout='5s';"
        if user:
            sql += auth
        return "select dblink_exec('member_graph_b',$begin_b$" + sql + "$begin_b$);\n"

    def probe(name, route, expected):
        return ("insert into member_race_results select " + literal(name) + ',' + literal(expected)
                + ",result from dblink('member_graph_b'," + literal("select pg_temp.member_try('" + route + "')")
                + ") r(result jsonb);\nselect dblink_exec('member_graph_b','rollback');\n")

    # A has exhausted metadata checks while the graph is still empty. B may
    # not slip a new header between that check and A's commit.
    sql = setup + """
begin;
update public.spec_templates set form_contract=form_contract-'member_profiles'
 where id='99e20000-0000-4000-8000-000000000050';
set constraints all immediate;
""" + begin_b(user=True) + probe('publication_before_new_profile', 'save', '55P03') + """
select result::text as member_first_result from member_race_results
 where probe='publication_before_new_profile' \\gset
rollback;
insert into member_race_results values
 ('publication_before_new_profile','55P03',:'member_first_result'::jsonb);
"""

    # B's RR view says there are no profiles. A commits one afterwards. The
    # epoch is a real conflicting row write, so B must get serialization failure.
    sql += begin_b(rr=True)
    sql += "select * from dblink('member_graph_b','select count(*) from public.product_spec_member_profiles') r(n bigint);\n"
    sql += 'begin;\n' + auth + "\nselect pg_temp.member_save('race-create',jsonb_build_array(pg_temp.member_profile('r1')))->>'revision' as saved;\nset constraints all immediate;commit;\n"
    sql += probe('repeatable_read_profile_phantom', 'parent', '40001')

    # A updates a component using the same aggregate writer as the UI. Child
    # publication and an old editor must both wait, with no partial root edit.
    sql += "select dblink_exec('member_graph_b',$snapshot$update member_old_revision set revision=(select spec_revision from public.products where id='99e20000-0000-4000-8000-000000000020')$snapshot$);\n"
    sql += 'begin;\n' + auth + "\nselect pg_temp.member_save('race-edit-eight',jsonb_build_array(pg_temp.member_profile('r1','8')))->>'revision' as saved;\nset constraints all immediate;reset role;\n"
    sql += begin_b() + probe('profile_before_child_metadata', 'child', '55P03')
    sql += begin_b(user=True) + probe('parallel_editor', 'stale', '55P03')
    sql += 'commit;\n'
    sql += begin_b() + probe('fresh_child_metadata_revalidation', 'child', '23514')
    sql += begin_b(user=True) + probe('old_editor_after_commit', 'stale', '40001')

    # An existing profile's new fact is also protected from stale metadata
    # snapshots, not just from the first creation of its header.
    sql += begin_b(rr=True)
    sql += "select * from dblink('member_graph_b','select count(*) from public.spec_facts') r(n bigint);\n"
    sql += 'begin;\n' + auth + "\nselect pg_temp.member_save('race-edit-nine',jsonb_build_array(pg_temp.member_profile('r1','9')))->>'revision' as saved;\nset constraints all immediate;commit;\n"
    sql += probe('repeatable_read_observation_phantom', 'bounds', '40001')
    # Retain the first profile as history, then exercise the category route
    # with no active profiles. Its epoch must still conflict with a new one.
    sql += 'begin;\n' + auth + """
select pg_temp.member_save('race-archive-first',p_archive=>'["99e20000-0000-4000-8000-000000000081"]')->>'revision';
reset role;
update public.category_tech_mappings set template_id='99e20000-0000-4000-8000-000000000050',technical_family='drivetrain_kit'
 where tenant_id='99e20000-0000-4000-8000-000000000001' and category_id='99e20000-0000-4000-8000-000000000010';
update public.products set spec_template_id=null where id='99e20000-0000-4000-8000-000000000020';
set constraints all immediate;commit;
begin;
update public.category_tech_mappings set status='pending'
 where tenant_id='99e20000-0000-4000-8000-000000000001' and category_id='99e20000-0000-4000-8000-000000000010';
set constraints all immediate;
""" + begin_b(user=True) + probe('category_before_new_profile', 'category-create', '55P03') + """
select result::text as member_category_result from member_race_results
 where probe='category_before_new_profile' \\gset
rollback;
insert into member_race_results values
 ('category_before_new_profile','55P03',:'member_category_result'::jsonb);
"""
    sql += begin_b(rr=True)
    sql += "select * from dblink('member_graph_b','select count(*) from public.product_spec_member_profiles where archived_at is null') r(n bigint);\n"
    sql += 'begin;\n' + auth + """
select pg_temp.member_save('race-category-second',jsonb_build_array(pg_temp.member_profile('r2','9')))->>'revision';
reset role;
update public.products set spec_template_id=null where id='99e20000-0000-4000-8000-000000000020';
set constraints all immediate;commit;
"""
    sql += probe('repeatable_read_category_profile_phantom', 'category-pending', '40001')
    sql += 'begin;\n' + auth + """
select pg_temp.member_save('race-category-edit',jsonb_build_array(pg_temp.member_profile('r2','10')))->>'revision';
reset role;
update public.products set spec_template_id=null where id='99e20000-0000-4000-8000-000000000020';
set constraints all immediate;reset role;
"""
    sql += begin_b() + probe('profile_before_category_reassignment', 'category-pending', '55P03')
    sql += 'commit;\n'
    sql += begin_b() + probe('fresh_category_revalidation', 'category-pending', '23514')
    sql += """
select probe,expected,result from member_race_results order by probe;
select 1/case when count(*)=11 and bool_and(result->>'sqlstate'=expected) then 1 else 0 end
 as all_member_concurrency_schedules_pass from member_race_results;
select 1/case when value_number=9 then 1 else 0 end as final_observation_preserved
 from public.spec_facts where subject_type='product' and subject_id='99e20000-0000-4000-8000-000000000020'
 and subject_scope='member:99e20000-0000-4000-8000-000000000081'
 and spec_definition_id='99e20000-0000-4000-8000-000000000052';
select dblink_disconnect('member_graph_b');
"""
    return sql


def cleanup_sql(before, added, triggers):
    # Drop only the triggers this candidate just created, then restore the local
    # root contracts before removing the disposable member tables and facts.
    sql = 'begin;\nset local request.jwt.claims=\'{}\';\nset local request.jwt.claim.sub=\'\';\n'
    sql += '\n'.join(f'drop trigger if exists {name} on public.{table};' for name, table in triggers)
    sql += '\n' + '\n'.join(item['body'].rstrip().rstrip(';') + ';' for item in before)
    sql += """
do $owned$ begin
 if exists(select 1 from public.product_spec_member_profiles where tenant_id not in
   ('99e20000-0000-4000-8000-000000000001','99e20000-0000-4000-8000-000000000002')) then
   raise exception 'Non-fixture profile appeared: refuse cleanup';
 end if;
end $owned$;
drop table public.product_spec_member_profile_events;
drop table public.product_spec_member_profiles;
drop table public.spec_member_graph_revisions;
delete from public.spec_facts where tenant_id='99e20000-0000-4000-8000-000000000001'
 and subject_type='product' and subject_id='99e20000-0000-4000-8000-000000000020';
delete from public.products where id='99e20000-0000-4000-8000-000000000020'
 and tenant_id='99e20000-0000-4000-8000-000000000001';
delete from public.product_spec_save_receipts where tenant_id='99e20000-0000-4000-8000-000000000001';
lock table public.product_spec_references in share row exclusive mode;
do $guard$ begin
 if (select tgenabled from pg_trigger where tgrelid='public.product_spec_references'::regclass
     and tgname='product_spec_reference_immutable' and not tgisinternal) is distinct from 'O' then
   raise exception 'Reference guard not enabled; refuse cleanup';
 end if;
end $guard$;
alter table public.product_spec_references disable trigger product_spec_reference_immutable;
delete from public.product_spec_references where id='member-race-reference';
alter table public.product_spec_references enable trigger product_spec_reference_immutable;
delete from public.category_tech_mappings where tenant_id in
 ('99e20000-0000-4000-8000-000000000001','99e20000-0000-4000-8000-000000000002');
delete from public.product_categories where tenant_id in
 ('99e20000-0000-4000-8000-000000000001','99e20000-0000-4000-8000-000000000002');
delete from public.spec_templates where id in
 ('99e20000-0000-4000-8000-000000000050','99e20000-0000-4000-8000-000000000060');
delete from public.spec_definitions where id in
 ('99e20000-0000-4000-8000-000000000051','99e20000-0000-4000-8000-000000000052',
  '99e20000-0000-4000-8000-000000000053','99e20000-0000-4000-8000-000000000054');
delete from auth.users where id in
 ('99e20000-0000-4000-8000-000000000091','99e20000-0000-4000-8000-000000000092');
delete from public.tenants where id in
 ('99e20000-0000-4000-8000-000000000001','99e20000-0000-4000-8000-000000000002');
"""
    sql += '\n'.join('drop function ' + item['signature'] + ';' for item in added)
    return sql + '\nset constraints all immediate;\ncommit;\n'


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    transport.OUTPUT = OUTPUT
    query = transport.query
    lock = OUTPUT / 'running'
    lock.mkdir()
    installed = False
    owns_extension = False
    cleanup = None
    try:
        candidate = strict_sql() + '\n' + compile_sql()
        names = set(re.findall(r'create or replace function public\.(\w+)\(', candidate, re.I))
        state = query('state-before', sql="select exists(select 1 from pg_extension where extname='dblink') as dblink," +
            ' or '.join("to_regclass('public." + name + "') is not null" for name in TABLES) +
            " as extension_present,exists(select 1 from public.tenants where id::text like '99e20000-%') as fixture_present", json_output=True)[0]
        if state['extension_present'] or state['fixture_present']:
            raise RuntimeError('Preexisting extension/fixture; inspect it, do not overwrite.')
        before = query('functions-before', sql=functions(names), json_output=True)
        if {item['name'] for item in before} != OLD_NAMES:
            raise RuntimeError('Unexpected predecessor set; inspect functions-before.log')
        triggers = re.findall(r'create (?:constraint )?trigger (\w+)\b[^;]*? on public\.(\w+)', candidate, re.I)
        if len(triggers) != 12:
            raise RuntimeError('Candidate trigger inventory changed')
        if not state['dblink']:
            query('extension-create', sql='create extension dblink with schema extensions', write=True)
            owns_extension = True
        # Atomic install: failure leaves no partial extension. The exact local
        # predecessor snapshot is already durable before this mutation.
        query('install', file=write_sql('install', 'begin;\n' + candidate + '\ncommit;'), write=True)
        installed = True
        installed_functions = query('functions-installed', sql=functions(names), json_output=True)
        old_signatures = {item['signature'] for item in before}
        added = [item for item in installed_functions if item['signature'] not in old_signatures]
        cleanup = write_sql('restore-local', cleanup_sql(before, added, triggers))
        baseline, helpers = fixture()
        query('baseline', file=write_sql('baseline', baseline), write=True)
        query('schedules', file=write_sql('schedules', schedules(helpers)), write=True)
    finally:
        try:
            if installed:
                if cleanup is None:
                    raise RuntimeError('Restore packet unavailable; local preimage is functions-before.log')
                current = query('functions-before-restore', sql=functions(names), json_output=True)
                if current != installed_functions:
                    raise RuntimeError('Candidate functions changed concurrently; refuse overwrite.')
                query('restore', file=cleanup, write=True)
                after = query('functions-after', sql=functions(names), json_output=True)
                if after != before:
                    raise RuntimeError('Local function/ACL restoration mismatch')
                remaining = query('state-after', sql="select exists(select 1 from public.tenants where id::text like '99e20000-%') as fixture_present," +
                    ' or '.join("to_regclass('public." + name + "') is not null" for name in TABLES) + ' as extension_present', json_output=True)[0]
                if any(remaining.values()):
                    raise RuntimeError('Local cleanup incomplete')
            if owns_extension:
                query('extension-remove', sql='drop extension dblink', write=True)
        finally:
            lock.rmdir()
    print('PASS: 11 member concurrency schedules; exact local functions/ACLs restored, fixtures removed.')


if __name__ == '__main__':
    main()
