#!/usr/bin/env python3
"""Exercise the exact kit candidate and aggregate writer in local rollback.

Only metadata is copied from the publication packet. Products, identities,
observations and sources below are synthetic. No production connection exists.
"""
import json
from pathlib import Path
import subprocess
import uuid

from compile_drivetrain_kit_members import PREFIX, generate_migration, generate_verifier
from compile_non_drivetrain_publication import RESEARCH, ROOT, sql_json
from test_existing_spec_candidate import NAMESPACE, prepare


def build_sql(packet, cases):
    route = lambda value: str(uuid.uuid5(NAMESPACE, value))
    definitions = {d['key']: route(d['id']) for d in packet['reused_definitions']}
    template = route(packet['records']['spec_templates'][0]['id'])
    collection = definitions['kit_members']
    legacy = definitions['crank_arm_length_mm']
    source = definitions['spec_evidence_source']
    test = prepare(packet, cases, migration_builder=generate_migration,
                   verifier_builder=generate_verifier)
    dependencies = '\n'.join('\\ir ' + str(ROOT / p) for p in (
        'supabase/tests/fixtures/product_spec_reading_receipt_contract.sql',
        'scripts/inventory/sql/product_spec_strict_row_order_candidate.sql',
        'scripts/inventory/sql/product_spec_member_profiles_candidate.sql',
        'scripts/inventory/sql/product_spec_legacy_roundtrip_candidate.sql',
        'supabase/tests/fixtures/product_spec_member_graph.sql'))
    test = test.replace('set local session_replication_role=replica;',
                        dependencies + '\nselect no_plan();\nset local session_replication_role=replica;', 1)
    # Seed an ordinary observation under the actual pre-publication kit rules.
    seed = f"""
update public.products set spec_template_id='{template}'
 where id='99e10000-0000-4000-8000-000000000020';
select public.spec_write_payload_internal_v2('99e10000-0000-4000-8000-000000000020',
 '{template}', {sql_json({legacy: {'number': '170.0'}})}, null);
create temp table kit_legacy_before as select to_jsonb(f) value from public.spec_facts f
 where subject_id='99e10000-0000-4000-8000-000000000020' and spec_definition_id='{legacy}';
-- A private synthetic chain template exercises the real tenant resolver.
update public.spec_templates set tenant_id='99e10000-0000-4000-8000-000000000001',key='chain'
 where id='99e10000-0000-4000-8000-000000000060';
"""
    test = test.replace('set local session_replication_role=origin;',
                        'set local session_replication_role=origin;\n' + seed, 1)
    rows = {'schema_version': 1, 'rows': [
        {'id': row_id, 'values': {'family': 'chain', 'member_role': 'cadena',
            'position': 'Sin posición', 'quantity': '1', 'identity_brand': 'Fixture',
            'identity_model': 'Model A'}, 'sources': ['https://example.test/kit-package']}
        for row_id in ('r1', 'r2')]}
    payload = {collection: {'rows': rows}, source: {'text': 'Synthetic package'},
               legacy: {'number': '170.00'}}
    assertions = f"""
update member_root_values set value={sql_json(payload)};
create function pg_temp.kit_profile(p_row text,p_length text default '7.1',p_patch jsonb default '{{}}')
returns jsonb language sql as $$
 select pg_temp.member_profile(p_row,p_length,
 jsonb_build_object('collection_definition_id','{collection}')||p_patch)
$$;
create function pg_temp.kit_save(p_key text,p_profiles jsonb default '[]',p_root_patch jsonb default '{{}}')
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
grant execute on function pg_temp.kit_profile(text,text,jsonb),pg_temp.kit_save(text,jsonb,jsonb) to authenticated;
set local role authenticated;
select is(public.get_product_spec_member_template_v1('{template}','{collection}','chain')->>'template_id',
 '99e10000-0000-4000-8000-000000000060','kit resolves the exact private member template');
select lives_ok($$select pg_temp.kit_save('two-kit-pieces',jsonb_build_array(
 pg_temp.kit_profile('r1'),pg_temp.kit_profile('r2','8.2')))$$,
 'actual kit metadata saves two independent physical pieces');
select is(jsonb_array_length(public.get_product_spec_member_profiles_v1(
 '99e10000-0000-4000-8000-000000000020')->'profiles'),2,'identical model rows remain distinct pieces');
select is(public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')#>>
 '{{profiles,0,values,member_test_length}}','7.1','first piece keeps its own measurement');
select is(public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')#>>
 '{{profiles,1,values,member_test_length}}','8.2','second piece keeps its own different measurement');
select throws_ok($$select pg_temp.kit_save('foreign-piece-value',jsonb_build_array(
 pg_temp.kit_profile('r1','7.1',{sql_json({'values': {legacy: {'number': '170'}}})})))$$,
 '23514',null,'a piece cannot borrow the root crank observation');
select throws_ok($$select pg_temp.kit_save('two-profiles-same-row',jsonb_build_array(
 pg_temp.kit_profile('r1'),pg_temp.kit_profile('r2','8.2','{{"member_row_id":"r1"}}')))$$,
 '23514',null,'two active profiles cannot own one physical row');
select throws_ok($$select pg_temp.kit_save('changed-legacy','[]',
 {sql_json({legacy: {'number': '171'}})})$$,'23514',null,'retired kit measurements cannot be overwritten');
select lives_ok($$select pg_temp.kit_save('equal-legacy-decimal')$$,
 'an equal legacy decimal string survives the aggregate roundtrip');
select ok(public.get_product_spec_editor_context_v3(
 '99e10000-0000-4000-8000-000000000020',null)->'values' ? 'fixture_eb_crank_arm_length_mm',
 'legacy remains available in the authenticated editor');
select throws_ok($$select pg_temp.kit_save('unpublished-prototype','[]',
 '{{"1b828eee-89d5-52ae-9d3c-30768f6c9c3d":{{"text":"unowned MPN"}}}}')$$,
 '23514',null,'unpublished prototype facts cannot enter the root');
reset role;
select is((select jsonb_agg(to_jsonb(f) order by f.id) from public.spec_facts f
 where subject_id='99e10000-0000-4000-8000-000000000020' and spec_definition_id='{legacy}'),
 (select jsonb_agg(value order by value->>'id') from kit_legacy_before),
 'publication and saves preserve every legacy fact property');
select ok(not(public.spec_product_scope_payload_internal_v1(
 '99e10000-0000-4000-8000-000000000020',null) ? '99e10000-0000-4000-8000-000000000052'),
 'member measurements never enter the root fact payload');
set constraints all immediate;
select * from finish();
"""
    return test.rsplit('rollback;', 1)[0] + assertions + '\nrollback;\n'


def main():
    packet = json.loads((RESEARCH / (PREFIX + '-packet.json')).read_text())
    cases = json.loads((RESEARCH / (PREFIX + '-cases.json')).read_text())
    output = ROOT / '.tmp/product-spec-catalog/drivetrain-kit-members-20260915'
    path = output / 'aggregate-regression.sql'; path.write_text(build_sql(packet, cases))
    result = subprocess.run([str(ROOT / 'scripts/db/query.sh'), 'local', '--write',
        '--file', str(path)], cwd=ROOT, text=True, capture_output=True)
    log = result.stdout + result.stderr
    (output / 'aggregate-regression.log').write_text(log)
    if result.returncode or 'not ok' in log or 'ROLLBACK' not in log:
        raise RuntimeError('Kit aggregate regression failed; inspect ' + str(output))
    print('Exact kit forward/replay, 11 representation cases and 13 aggregate assertions passed; rolled back.')


if __name__ == '__main__':
    main()
