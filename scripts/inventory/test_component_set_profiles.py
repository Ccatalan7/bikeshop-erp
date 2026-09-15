#!/usr/bin/env python3
"""Exercise the new collection with authenticated atomic piece saves locally."""
import json
import subprocess
import uuid

from compile_component_set import PREFIX, RESEARCH, ROOT
from compile_non_drivetrain_publication import generate_migration, sql_json
from test_existing_spec_candidate import NAMESPACE, prepare


def build_sql(packet, cases):
    packet['before'] = {key: [] for key in packet['records']}
    route = lambda value: str(uuid.uuid5(NAMESPACE, value))
    defs = {d['key']: route(d['id']) for d in packet['reused_definitions']}
    template = route(packet['records']['spec_templates'][0]['id'])
    collection = defs['kit_members']
    test = prepare(packet, cases, migration_builder=generate_migration)
    dependencies = '\n'.join('\\ir ' + str(ROOT / p) for p in (
        'supabase/tests/fixtures/product_spec_reading_receipt_contract.sql',
        'scripts/inventory/sql/product_spec_strict_row_order_candidate.sql',
        'scripts/inventory/sql/product_spec_member_profiles_candidate.sql',
        'scripts/inventory/sql/product_spec_legacy_roundtrip_candidate.sql',
        'supabase/tests/fixtures/product_spec_member_graph.sql'))
    test = test.replace('set local session_replication_role=replica;',
        dependencies + '\nselect no_plan();\nset local session_replication_role=replica;', 1)
    rows = {'schema_version': 1, 'rows': [
        {'id': row_id, 'values': {'family': family, 'member_role': 'otro',
             'position': 'Sin posición', 'quantity': '1',
             'identity_brand': 'Fixture', 'identity_model': 'Model A'},
         'sources': ['https://example.invalid/synthetic-package']}
        for row_id, family in [('r1', 'bearing'), ('r2', 'fastener')]]}
    payload = {collection: {'rows': rows},
               defs['spec_evidence_source']: {'text': 'Synthetic package'}}
    assertions = f"""
update public.products set spec_template_id='{template}'
 where id='99e10000-0000-4000-8000-000000000020';
set constraints all deferred;
-- Private piece owners test routing; their fields are synthetic, not OEM facts.
update public.spec_templates set tenant_id='99e10000-0000-4000-8000-000000000001',
 key='bearing',technical_family='bearing'
 where id='99e10000-0000-4000-8000-000000000060';
insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract)
select '99e10000-0000-4000-8000-000000000061',tenant_id,'fastener','Synthetic fastener',
 'fastener',form_contract from public.spec_templates
 where id='99e10000-0000-4000-8000-000000000060';
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select '99e10000-0000-4000-8000-000000000061',spec_definition_id,section_key,sort_order
 from public.spec_template_fields where template_id='99e10000-0000-4000-8000-000000000060';
set constraints all immediate;
update member_root_values set value={sql_json(payload)};
create function pg_temp.set_profile(p_row text,p_length text default '7.1',p_patch jsonb default '{{}}')
returns jsonb language sql as $$
 select pg_temp.member_profile(p_row,p_length,jsonb_build_object(
  'collection_definition_id','{collection}',
  'template_id',case p_row when 'r1' then '99e10000-0000-4000-8000-000000000060'
     else '99e10000-0000-4000-8000-000000000061' end,
  'contract_version',(select contract_version from public.spec_templates where id=
    (case p_row when 'r1' then '99e10000-0000-4000-8000-000000000060'
     else '99e10000-0000-4000-8000-000000000061' end)::uuid))||p_patch)
$$;
create function pg_temp.set_save(p_key text,p_profiles jsonb default '[]',p_root_patch jsonb default '{{}}')
returns jsonb language plpgsql as $$
declare prod record; ver integer; vals jsonb;
begin
 select id,spec_revision,updated_at into prod from public.products
  where id='99e10000-0000-4000-8000-000000000020';
 select contract_version into ver from public.spec_templates where id='{template}';
 select value||p_root_patch into vals from member_root_values;
 return public.save_product_with_specs_v2(
 '{{"id":"99e10000-0000-4000-8000-000000000020","name":"Profile kit","sku":"MEMBER-KIT"}}',
 false,'{template}',ver,vals,prod.spec_revision,null,p_key,prod.updated_at,
 jsonb_build_object('schema_version',1,'upserts',p_profiles,'archive_ids','[]'::jsonb));
end $$;
grant execute on function pg_temp.set_profile(text,text,jsonb),pg_temp.set_save(text,jsonb,jsonb) to authenticated;
set local role authenticated;
select is(public.get_product_spec_member_template_v1('{template}','{collection}','bearing')->>'template_id',
 '99e10000-0000-4000-8000-000000000060','set resolves the private bearing owner');
select is(public.get_product_spec_member_template_v1('{template}','{collection}','fastener')->>'template_id',
 '99e10000-0000-4000-8000-000000000061','set resolves the distinct fastener owner');
select lives_ok($$select pg_temp.set_save('two-set-pieces',jsonb_build_array(
 pg_temp.set_profile('r1'),pg_temp.set_profile('r2','8.2')))$$,
 'actual set metadata saves two independently described piece families');
select is(jsonb_array_length(public.get_product_spec_member_profiles_v1(
 '99e10000-0000-4000-8000-000000000020')->'profiles'),2,'two physical rows remain two profiles');
select is(public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')#>>
 '{{profiles,0,values,member_test_length}}','7.1','bearing keeps its own measurement');
select is(public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')#>>
 '{{profiles,1,values,member_test_length}}','8.2','fastener keeps a different measurement');
select throws_ok($$select pg_temp.set_save('measurement-on-root','[]',
 '{{"99e10000-0000-4000-8000-000000000052":{{"number":"7.1"}}}}')$$,
 '23514',null,'a piece measurement cannot become a set-wide assertion');
select throws_ok($$select pg_temp.set_save('wrong-family',jsonb_build_array(
 pg_temp.set_profile('r2','8.2','{{"template_id":"99e10000-0000-4000-8000-000000000060"}}')))$$,
 '23514',null,'a fastener row cannot use a bearing profile');
select throws_ok($$select pg_temp.set_save('root-content-inside-piece',jsonb_build_array(
 pg_temp.set_profile('r1','7.1',{sql_json({'values': payload})})))$$,
 '23514',null,'root content cannot enter a piece template');
select lives_ok($$select pg_temp.set_save('ordinary-root-roundtrip')$$,
 'an ordinary root edit preserves existing piece profiles');
reset role;
select ok(not(public.spec_product_scope_payload_internal_v1(
 '99e10000-0000-4000-8000-000000000020',null) ? '99e10000-0000-4000-8000-000000000052'),
 'piece observations remain absent from the root payload');
set constraints all immediate;
select * from finish();
"""
    return test.rsplit('rollback;', 1)[0] + assertions + '\nrollback;\n'


def main():
    packet = json.loads((RESEARCH / (PREFIX + '-packet.json')).read_text())
    cases = json.loads((RESEARCH / (PREFIX + '-cases.json')).read_text())
    output = ROOT / '.tmp/product-spec-catalog/component-set-20260915/tests'
    path = output / 'profiles.sql'; path.write_text(build_sql(packet, cases))
    result = subprocess.run([str(ROOT / 'scripts/db/query.sh'), 'local', '--file', str(path)],
                            cwd=ROOT, text=True, capture_output=True)
    log = result.stdout + result.stderr; (output / 'profiles.log').write_text(log)
    if result.returncode or 'not ok' in log or 'ROLLBACK' not in log:
        raise RuntimeError('Component-set profile regression failed; inspect ' + str(output))
    print(f'Exact metadata/replay, {len(cases["cases"])} representation cases and 11 profile assertions passed; rolled back.')


if __name__ == '__main__':
    main()
