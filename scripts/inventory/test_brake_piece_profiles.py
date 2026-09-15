#!/usr/bin/env python3
"""Exercise the exact three successor templates in scoped, rollback-only saves.

The containing graph and product identities are synthetic. Piece field metadata,
option IDs and contracts come from the candidate, never substitute piece fields.
"""
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import uuid

from compile_brake_piece_successors import PREFIX, RESEARCH, ROOT
from compile_non_drivetrain_publication import sql_json
from test_existing_spec_candidate import NAMESPACE, prepare


def build_sql(packet, cases):
    route = lambda value: str(uuid.uuid5(NAMESPACE, value))
    definitions = {d['key']: d for d in [*packet['reused_definitions'],
                                        *packet['records']['spec_definitions']]}
    options = [*packet['records']['spec_definition_values'],
               *(o for d in packet['reused_definitions'] for o in d['options'])]
    templates = {t['key']: t for t in packet['records']['spec_templates']}

    def payload(values):
        answer = {}
        for key, value in values.items():
            definition = definitions[key]
            kind = definition['data_type']
            if kind == 'single_select':
                option = next(o for o in options if o['spec_definition_id'] == definition['id']
                              and o['label'] == value)
                typed = {'value_ids': [route(option['id'])]}
            else:
                typed = { {'json': 'rows', 'number': 'number', 'boolean': 'boolean',
                           'text': 'text'}[kind]: value}
            answer[route(definition['id'])] = typed
        return answer

    def profile(family, row, values):
        template = templates[family]
        return {'id': f'99e10000-0000-4000-8000-00000000008{row}',
                'collection_definition_id': '99e10000-0000-4000-8000-000000000051',
                'member_row_id': 'r' + str(row), 'template_id': route(template['id']),
                'contract_version': template['contract_version'], 'values': payload(values)}

    members = [profile('brake_caliper', 1, {'braking_surface': 'Disco',
        'brake_actuation': 'Mecánico (cable)', 'caliper_mount_interface': 'Flat Mount'}),
        profile('brake_pad', 2, {'braking_surface': 'Llanta',
            'rim_pad_construction': 'Recambio de cartucho',
            'rim_pad_interface_model': 'Synthetic cartridge interface'}),
        profile('rotor', 3, {'rotor_diameter_mm_value': '160',
            'rotor_mount_type': '6 pernos', 'rotor_material': 'Acero Inoxidable'})]
    # This deliberately mixes non-matching parts. Containment is not a claim
    # that a rim pad works with a disc caliper or that any mounting is approved.
    rows = {'schema_version': 1, 'rows': [{'id': 'r' + str(i),
        'values': {'family': 'fixture_eb_' + family, 'member_role': 'Synthetic piece',
                   'position': 'front', 'quantity': '1'},
        'sources': ['https://example.invalid/synthetic-package']}
        for i, family in enumerate(templates, 1)]}
    root_payload = {'99e10000-0000-4000-8000-000000000051': {'rows': rows}}
    collection_families = ['fixture_eb_' + family for family in templates]
    dependencies = '\n'.join('\\ir ' + str(ROOT / p) for p in (
        'supabase/tests/fixtures/product_spec_reading_receipt_contract.sql',
        'scripts/inventory/sql/product_spec_strict_row_order_candidate.sql',
        'scripts/inventory/sql/product_spec_member_profiles_candidate.sql',
        'scripts/inventory/sql/product_spec_legacy_roundtrip_candidate.sql',
        'supabase/tests/fixtures/product_spec_member_graph.sql'))
    test = prepare(packet, cases).replace('set local session_replication_role=replica;',
        dependencies + '\nselect no_plan();\nset local session_replication_role=replica;', 1)
    caliper = members[0]
    contradictory_recipe = {'schema_version': 1, 'rows': [{'id': 'r1', 'sources': [],
        'values': {'configuration': 'Synthetic recipe', 'position': 'Delantero',
                   'rotor_diameter_mm': '160', 'frame_mount': 'Post Mount',
                   'caliper_mount': 'Post Mount', 'adapter_required': False,
                   'source_url': 'https://example.invalid/fitment'}}]}
    contradictory = deepcopy(caliper)
    contradictory['values'].update(payload({'rotor_size_recipe': contradictory_recipe}))
    wrong = {**members[0], 'template_id': members[2]['template_id'],
             'contract_version': members[2]['contract_version'], 'values': members[2]['values']}
    insert_stud = deepcopy(members[1])
    insert_stud['values'].update(payload({'rim_pad_stud_type': 'Espárrago roscado'}))
    original = json.loads((RESEARCH / 'original-successors-integrated-catalog-2026-09-08.json').read_text())
    external = deepcopy(caliper)
    external['values'][original['definitions']['brake_external_converter_model']['id']] = {'text': 'Another piece'}
    dkey = lambda key: 'fixture_eb_' + key
    root_rotor = templates['rotor']
    old_diameter = definitions['rotor_diameter_mm']
    old_option = next(o for o in options if o['spec_definition_id'] == old_diameter['id'])

    assertions = f"""
update public.spec_definitions set validation_rules=jsonb_set(validation_rules,
 '{{rows_schema,columns,0,allowed_values}}',{sql_json(collection_families)})
 where id='99e10000-0000-4000-8000-000000000051';
update member_root_values set value={sql_json(root_payload)};
set constraints all immediate;
set local role authenticated;
select is(public.get_product_spec_member_template_v1(
 '99e10000-0000-4000-8000-000000000050','99e10000-0000-4000-8000-000000000051',
 'fixture_eb_brake_caliper')->>'template_id','{caliper['template_id']}',
 'the collection resolves the exact caliper successor');
select lives_ok($$select pg_temp.member_save('brake-piece-owners',{sql_json(members)})$$,
 'three physical profiles save independently with the exact successor fields');
select is(jsonb_array_length(public.get_product_spec_member_profiles_v1(
 '99e10000-0000-4000-8000-000000000020')->'profiles'),3,'all three profiles are retained');
select is((select p#>>'{{values,{dkey('caliper_mount_interface')}}}' from jsonb_array_elements(
 public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')->'profiles') p
 where p->>'member_row_id'='r1'),'Flat Mount','mount remains on the caliper');
select is((select p#>>'{{values,{dkey('rim_pad_construction')}}}' from jsonb_array_elements(
 public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')->'profiles') p
 where p->>'member_row_id'='r2'),'Recambio de cartucho','insert persists without an invented stud');
select is((select p#>>'{{values,{dkey('rotor_diameter_mm_value')}}}' from jsonb_array_elements(
 public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')->'profiles') p
 where p->>'member_row_id'='r3'),'160','rotor diameter remains on the rotor');
select throws_ok($$select pg_temp.member_save('row-mount-contradiction',{sql_json([contradictory])})$$,
 '23514',null,'a fitment row cannot override the caliper mount');
select throws_ok($$select pg_temp.member_save('insert-with-stud',{sql_json([insert_stud])})$$,
 '23514',null,'an insert cannot acquire the holder stud through the writer');
select throws_ok($$select pg_temp.member_save('wrong-template',{sql_json([wrong])})$$,
 '23514',null,'a caliper row cannot switch to the rotor template');
select throws_ok($$select pg_temp.member_save('external-converter',{sql_json([external])})$$,
 '23514',null,'the removed external-converter definition is rejected by the writer');
select throws_ok($$select pg_temp.member_save('piece-field-at-root','[]','[]',
 {sql_json({**root_payload, **payload({'rotor_diameter_mm_value': '160'})})})$$,
 '23514',null,'the collection cannot contain a root-wide rotor measurement');
select lives_ok($$select pg_temp.member_save('ordinary-root-edit')$$,
 'an ordinary root edit keeps piece observations');
select is(jsonb_array_length(public.get_product_spec_member_profiles_v1(
 '99e10000-0000-4000-8000-000000000020')->'profiles'),3,'root round trip retains all three pieces');
reset role;
select ok(not(public.spec_product_scope_payload_internal_v1(
 '99e10000-0000-4000-8000-000000000020',null) ? '{route(definitions['rotor_diameter_mm_value']['id'])}'),
 'the rotor measurement never enters the root payload');
insert into public.products(id,tenant_id,name,sku,spec_template_id,price,cost,is_published,show_on_website)
 values('99e10000-0000-4000-8000-000000000021','99e10000-0000-4000-8000-000000000001',
 'Synthetic rotor','SYNTHETIC-ROTOR','{route(root_rotor['id'])}',100,50,true,true);
set local role authenticated;
select lives_ok($$select public.save_product_with_specs_v1(
 '{{"id":"99e10000-0000-4000-8000-000000000021","name":"Synthetic rotor","sku":"SYNTHETIC-ROTOR"}}',
 false,'{route(root_rotor['id'])}',{root_rotor['contract_version']},
 {sql_json(members[2]['values'])},0,null,'root-rotor-successor',
 (select updated_at from public.products where id='99e10000-0000-4000-8000-000000000021'))$$,
 'the successor also saves as an ordinary standalone rotor');
reset role;
-- Recreate an old import only in this rollback fixture. The product writer
-- itself rejects new/changed legacy facts; do not use this seed in production.
insert into public.spec_facts(id,tenant_id,subject_type,subject_id,spec_definition_id,source,confirmed)
 values('99e10000-0000-4000-8000-000000000121','99e10000-0000-4000-8000-000000000001',
 'product','99e10000-0000-4000-8000-000000000021','{route(old_diameter['id'])}','import',false);
insert into public.spec_fact_values(fact_id,value_id,position) values
 ('99e10000-0000-4000-8000-000000000121','{route(old_option['id'])}',0);
select is(public.assistant_inventory_technical_predicate_source_internal_v1(
 '99e10000-0000-4000-8000-000000000001','99e10000-0000-4000-8000-000000000021',
 '{dkey('rotor_diameter_mm')}','eq','[160]','',''),'unresolved',
 'an existing legacy rotor observation cannot satisfy a new search predicate');
select is(public.assistant_inventory_technical_predicate_source_internal_v1(
 '99e10000-0000-4000-8000-000000000001','99e10000-0000-4000-8000-000000000021',
 '{dkey('rotor_diameter_mm_value')}','eq','[160]','',''),'product_spec',
 'a new numeric observation is usable as a catalog search criterion');
select is(public.assistant_inventory_technical_predicate_source_internal_v1(
 '99e10000-0000-4000-8000-000000000001','99e10000-0000-4000-8000-000000000021',
 '{dkey('rotor_diameter_mm_value')}','eq','[180]','',''),'conflict',
 'a different numeric diameter conflicts with the search criterion');
set local role anon;
select ok(exists(select 1 from public.get_public_product_technical_specs(
 '99e10000-0000-4000-8000-000000000001','99e10000-0000-4000-8000-000000000021')
 where spec_key='{dkey('rotor_diameter_mm_value')}'),
 'the public renderer can display the new scalar rotor diameter');
select ok(not exists(select 1 from public.get_public_product_technical_specs(
 '99e10000-0000-4000-8000-000000000001','99e10000-0000-4000-8000-000000000021')
 where spec_key='{dkey('rotor_diameter_mm')}'),
 'the public renderer does not republish the retired import');
reset role;
set constraints all immediate;
select * from finish();
"""
    return test.rsplit('rollback;', 1)[0] + assertions + '\nrollback;\n'


def main():
    packet = json.loads((RESEARCH / (PREFIX + '-packet.json')).read_text())
    cases = json.loads((RESEARCH / (PREFIX + '-cases.json')).read_text())
    output = ROOT / '.tmp/product-spec-catalog/brake-pieces-20260915/profile-tests'
    output.mkdir(parents=True, exist_ok=True)
    path = output / 'profiles.sql'; path.write_text(build_sql(packet, cases))
    result = subprocess.run([str(ROOT / 'scripts/db/query.sh'), 'local', '--file', str(path)],
                            cwd=ROOT, text=True, capture_output=True)
    log = result.stdout + result.stderr; (output / 'profiles.log').write_text(log)
    if result.returncode or 'not ok' in log or 'ROLLBACK' not in log:
        raise RuntimeError('Brake-piece profile regression failed; inspect ' + str(output))
    print('Exact metadata/replay, 58 representation cases and 20 profile/consumer assertions passed; rolled back.')


if __name__ == '__main__':
    main()
