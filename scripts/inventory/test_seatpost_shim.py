#!/usr/bin/env python3
"""Validate the real shim catalogue and exact replay against native SQL guards."""
import json
import subprocess
import uuid

from compile_non_drivetrain_publication import generate_migration, sql_json
from compile_seatpost_shim import PREFIX, RESEARCH, ROOT, POST, FRAME
from test_existing_spec_candidate import prepare, NAMESPACE


def writer_checks(packet,cases):
    route=lambda value:str(uuid.uuid5(NAMESPACE,value))
    defs={d['key']:d for d in [*packet['reused_definitions'],*packet['records']['spec_definitions']]}
    options=[*packet['records']['spec_definition_values'],*(v for d in packet['reused_definitions'] for v in d['options'])]
    def values(raw):
        result={}
        for key,value in raw.items():
            d=defs[key]
            if d['data_type']=='single_select':
                o=next(o for o in options if o['spec_definition_id']==d['id'] and o['label']==value)
                typed={'value_ids':[route(o['id'])]}
            else:typed={d['data_type']:value}
            result[route(d['id'])]=typed
        return result
    template=packet['records']['spec_templates'][0];tid=route(template['id'])
    by_case={c['id']:c['values'] for c in cases['cases']}
    good=values(by_case['seatpost_shim_circular_valid'])
    header=(ROOT/'supabase/tests/fixtures/product_spec_member_graph.sql').read_text().split('insert into public.spec_definitions',1)[0]
    assertions=f"""
select no_plan();
{header}
insert into public.products(id,tenant_id,name,sku,category_id,spec_template_id,price,cost)
 values ('99e10000-0000-4000-8000-000000000020','99e10000-0000-4000-8000-000000000001',
 'Synthetic reducing sleeve','SHIM-TEST','99e10000-0000-4000-8000-000000000010','{tid}',100,50);
create function pg_temp.shim_save(p_key text,p_values jsonb) returns jsonb language sql as $$
 select public.save_product_with_specs_v1(
 '{{"id":"99e10000-0000-4000-8000-000000000020","name":"Synthetic reducing sleeve","sku":"SHIM-TEST"}}',
 false,'{tid}',{template['contract_version']},p_values,
 (select spec_revision from public.products where id='99e10000-0000-4000-8000-000000000020'),
 null,p_key,(select updated_at from public.products where id='99e10000-0000-4000-8000-000000000020'));
$$;
set constraints all immediate;
set local role authenticated;
select lives_ok($$select pg_temp.shim_save('shim-valid',{sql_json(good)})$$,
 'authenticated writer stores the exact single nominal pair');
select is((select value_number::text from public.spec_facts where
 subject_id='99e10000-0000-4000-8000-000000000020' and spec_definition_id='{route(defs[POST]['id'])}'),
 '27.2','post dimension survives typed save');
"""
    for name in ['equal_nominal_diameters','reversed_nominal_diameters','specific_cannot_keep_round_diameters',
                 'support_exceeds_length','apparel_material_not_a_shim_option']:
        payload=values(by_case['seatpost_shim_'+name])
        assertions+=f"select throws_ok($$select pg_temp.shim_save('shim-{name}',{sql_json(payload)})$$,'23514',null,'writer rejects {name}');\n"
    assertions+=f"""
select is((select value_number::text from public.spec_facts where
 subject_id='99e10000-0000-4000-8000-000000000020' and spec_definition_id='{route(defs[FRAME]['id'])}'),
 '30.9','failed writes retain the original frame dimension');
select lives_ok($$select pg_temp.shim_save('shim-roundtrip',{sql_json(good)})$$,
 'ordinary save retains the pair');
reset role;
select * from finish();
"""
    return assertions


def main():
    packet=json.loads((RESEARCH/(PREFIX+'-packet.json')).read_text())
    cases=json.loads((RESEARCH/(PREFIX+'-cases.json')).read_text())
    if packet['scope']!='new_global_metadata_only' or packet['product_writes']:
        raise ValueError('Only new shim metadata is supported')
    packet['before']={key:[] for key in packet['records']}
    sql=prepare(packet,cases,migration_builder=generate_migration)
    # The local transaction owns the unpublished engine dependency as well.
    strict=(ROOT/'scripts/inventory/sql/product_spec_strict_scalar_candidate.sql').read_text()
    marker='set local session_replication_role=origin;'
    if sql.count(marker)!=1:raise ValueError('Review the current rehearsal boundary')
    sql=sql.replace(marker,marker+'\n'+strict)
    sql=sql.rsplit('rollback;',1)[0]+writer_checks(packet,cases)+'\nrollback;\n'
    out=ROOT/'.tmp/product-spec-catalog/strict-scalar-20260915'
    path=out/'shim-tests.sql';path.write_text(sql)
    result=subprocess.run([str(ROOT/'scripts/db/query.sh'),'local','--file',str(path)],
                          cwd=ROOT,capture_output=True,text=True)
    log=result.stdout+result.stderr;(out/'shim-tests.log').write_text(log)
    if result.returncode or 'not ok' in log or 'ROLLBACK' not in log:
        raise RuntimeError('Shim rehearsal failed; inspect '+str(out/'shim-tests.log'))
    print(json.dumps({'cases':len(cases['cases']),'authenticated_writer_assertions':9,
                      'replay':True,'rollback':True,'product_writes':False}))


if __name__=='__main__':main()
