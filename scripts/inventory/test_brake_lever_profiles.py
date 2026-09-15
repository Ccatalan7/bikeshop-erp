#!/usr/bin/env python3
"""Exercise lever ownership through the actual authenticated writer, in rollback."""
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import uuid

from compile_brake_lever_successor import PREFIX, RESEARCH, ROOT
from compile_non_drivetrain_publication import sql_json
from test_existing_spec_candidate import NAMESPACE, prepare


def build_sql(packet, cases):
    route = lambda value: str(uuid.uuid5(NAMESPACE, value))
    definitions = {d['key']: d for d in [*packet['reused_definitions'], *packet['records']['spec_definitions']]}
    options = [*packet['records']['spec_definition_values'], *(v for d in packet['reused_definitions'] for v in d['options'])]
    template = packet['records']['spec_templates'][0]
    by_case = {c['id']: c['values'] for c in cases['cases']}
    def values(data):
        result = {}
        for key, value in data.items():
            d = definitions[key]
            if d['data_type'] == 'single_select':
                option = next(o for o in options if o['spec_definition_id'] == d['id'] and o['label'] == value)
                typed = {'value_ids': [route(option['id'])]}
            else:
                typed = {{'json': 'rows', 'number': 'number', 'boolean': 'boolean', 'text': 'text'}[d['data_type']]: value}
            result[route(d['id'])] = typed
        return result
    def profile(number, data):
        return {'id': '99e20000-0000-4000-8000-00000000008' + str(number),
            'collection_definition_id': '99e10000-0000-4000-8000-000000000051',
            'member_row_id': 'r' + str(number), 'template_id': route(template['id']),
            'contract_version': template['contract_version'], 'values': values(data)}
    left_data = deepcopy(by_case['lever_bar_end_uses_bore_range'])
    right_data = {**left_data, 'lever_side': 'Derecha', 'lever_bar_bore_min_mm': '20', 'lever_bar_bore_max_mm': '21'}
    members = [profile(1, left_data), profile(2, right_data)]
    root_value = {'99e10000-0000-4000-8000-000000000051': {'rows': {
        'schema_version': 1, 'rows': [{'id': 'r' + str(i), 'sources': ['https://example.invalid/lever-set'],
            'values': {'family': 'fixture_eb_brake_lever', 'member_role': 'Synthetic lever',
                       'position': side, 'quantity': '1'}} for i, side in ((1, 'left'), (2, 'right'))]}}}
    bad_mount = profile(1, by_case['lever_bar_end_cannot_claim_external_clamp'])
    bad_range = profile(1, by_case['lever_bore_range_cannot_be_reversed'])
    bad_inline = profile(1, by_case['lever_principal_cannot_claim_inline_ports'])
    bad_port = profile(1, by_case['lever_principal_port_Entrada'])
    original = json.loads((RESEARCH / 'original-successors-integrated-catalog-2026-09-08.json').read_text())
    foreign = deepcopy(members[0])
    foreign['values'][original['definitions']['integrated_shifter']['id']] = {'boolean': True}
    dependencies = '\n'.join('\\ir ' + str(ROOT / p) for p in (
        'supabase/tests/fixtures/product_spec_reading_receipt_contract.sql',
        'scripts/inventory/sql/product_spec_strict_row_order_candidate.sql',
        'scripts/inventory/sql/product_spec_member_profiles_candidate.sql',
        'scripts/inventory/sql/product_spec_legacy_roundtrip_candidate.sql',
        'supabase/tests/fixtures/product_spec_member_graph.sql'))
    test = prepare(packet, cases).replace('set local session_replication_role=replica;',
        dependencies + '\nselect no_plan();\nset local session_replication_role=replica;', 1)
    assertions = f"""
update public.spec_definitions set validation_rules=jsonb_set(validation_rules,
 '{{rows_schema,columns,0,allowed_values}}','["fixture_eb_brake_lever"]')
 where id='99e10000-0000-4000-8000-000000000051';
update member_root_values set value={sql_json(root_value)};
set constraints all immediate;
set local role authenticated;
select is(public.get_product_spec_member_template_v1(
 '99e10000-0000-4000-8000-000000000050','99e10000-0000-4000-8000-000000000051',
 'fixture_eb_brake_lever')->>'template_id','{route(template['id'])}',
 'the collection resolves the exact lever successor');
select lives_ok($$select pg_temp.member_save('lever-profiles',{sql_json(members)})$$,
 'two levers preserve separate physical measurements');
select is(jsonb_array_length(public.get_product_spec_member_profiles_v1(
 '99e10000-0000-4000-8000-000000000020')->'profiles'),2,'two lever profiles remain');
select is((select p#>>'{{values,fixture_eb_lever_bar_bore_min_mm}}' from jsonb_array_elements(
 public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')->'profiles') p
 where p->>'member_row_id'='r1'),'19','left lever retains its own bore');
select is((select p#>>'{{values,fixture_eb_lever_bar_bore_min_mm}}' from jsonb_array_elements(
 public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')->'profiles') p
 where p->>'member_row_id'='r2'),'20','right lever retains its distinct bore');
select throws_ok($$select pg_temp.member_save('lever-invalid-mount',{sql_json([bad_mount])})$$,
 '23514',null,'an expander cannot store external clamp diameter');
select throws_ok($$select pg_temp.member_save('lever-invalid-range',{sql_json([bad_range])})$$,
 '23514',null,'the writer rejects inverted internal diameter bounds');
select throws_ok($$select pg_temp.member_save('lever-invalid-inline',{sql_json([bad_inline])})$$,
 '23514',null,'a principal lever cannot store auxiliary connections');
select throws_ok($$select pg_temp.member_save('lever-invalid-port',{sql_json([bad_port])})$$,
 '23514',null,'a principal lever cannot store an inlet as its output');
select throws_ok($$select pg_temp.member_save('lever-foreign-control',{sql_json([foreign])})$$,
 '23514',null,'integrated shifting does not enter the physical brake-only owner');
select throws_ok($$select pg_temp.member_save('lever-measurement-at-root','[]','[]',
 {sql_json({**root_value, **values({'lever_bar_bore_min_mm': '19'})})})$$,
 '23514',null,'a lever measurement cannot enter the collection root');
select lives_ok($$select pg_temp.member_save('lever-root-roundtrip')$$,
 'ordinary root editing retains both physical profiles');
select is(jsonb_array_length(public.get_product_spec_member_profiles_v1(
 '99e10000-0000-4000-8000-000000000020')->'profiles'),2,'both profiles survive roundtrip');
reset role;
select * from finish();
"""
    return test.rsplit('rollback;', 1)[0] + assertions + '\nrollback;\n'


def main():
    packet = json.loads((RESEARCH / (PREFIX + '-packet.json')).read_text())
    cases = json.loads((RESEARCH / (PREFIX + '-cases.json')).read_text())
    out = ROOT / '.tmp/product-spec-catalog/brake-lever-20260915/profile-tests'
    out.mkdir(parents=True, exist_ok=True)
    path = out / 'profiles.sql'; path.write_text(build_sql(packet, cases))
    result = subprocess.run([str(ROOT / 'scripts/db/query.sh'), 'local', '--file', str(path)],
                            cwd=ROOT, text=True, capture_output=True)
    log = result.stdout + result.stderr; (out / 'profiles.log').write_text(log)
    if result.returncode or 'not ok' in log or 'ROLLBACK' not in log:
        raise RuntimeError('Lever profile assertions failed; inspect ' + str(out))
    print(json.dumps({'authenticated_profile_assertions': 13, 'rollback': True,
                      'production_writes': 0, 'representation_cases': len(cases['cases'])}))


if __name__ == '__main__':
    main()
