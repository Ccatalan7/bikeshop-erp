#!/usr/bin/env python3
"""Run the scalar-order boundary cases against real PostgreSQL in rollback."""
import json
from pathlib import Path
import subprocess

from compile_product_spec_strict_scalar import ROOT, compile_candidate


def literal(value):
    return "'" + json.dumps(value, ensure_ascii=False).replace("'", "''") + "'::jsonb"


def main():
    before, bodies = compile_candidate()
    fixture = json.loads((ROOT / 'test/fixtures/product_spec_strict_scalar.json').read_text())
    fields = {key: {'data_type': kind, 'unit': fixture['units'][key]}
              for key, kind in fixture['types'].items()}
    sql = "begin;\nset local statement_timeout='30s';\n" + '\n;\n'.join(f['definition'] for f in before) + '\n;\n'
    sql += f"""
do $older$ begin
 begin
  perform public.spec_coherence_metadata_internal_v1({literal(fixture['contract'])},{literal(fields)});
  raise exception 'Older metadata validator silently accepted strict comparison';
 exception when check_violation then null;
 end;
end $older$;
"""
    sql += '\n;\n'.join(bodies[k] for k in sorted(bodies)) + '\n;\n'
    sql += f"""
do $cases$
declare doc jsonb:={literal(fixture)}; fields jsonb:={literal(fields)};
 c jsonb; issues jsonb; observed jsonb; contract jsonb;
begin
 perform public.spec_coherence_metadata_internal_v1(doc->'contract',fields);
 for c in select value from jsonb_array_elements(doc->'cases') loop
  issues:=public.spec_coherence_issues_internal_v1(doc->'contract',fields,c->'values');
  select coalesce(jsonb_agg(i->'field' order by n),'[]') into observed
   from jsonb_array_elements(issues) with ordinality x(i,n);
  if observed<>c->'expected_fields' or exists(select 1 from jsonb_array_elements(issues) i
    where i->>'code'<>'range_order' or i->'blocking'<>'true'::jsonb) then
   raise exception 'Scalar case %: %',c->>'id',issues;
  end if;
 end loop;
 for c in select value from jsonb_array_elements(doc->'invalid_contracts') loop
  begin
   perform public.spec_coherence_metadata_internal_v1(c->'contract',fields);
   raise exception 'Accepted invalid scalar metadata %',c->>'id';
  exception when check_violation then null;
  end;
 end loop;
 begin
  perform public.spec_coherence_metadata_internal_v1(doc->'contract',jsonb_set(fields,'{{frame_mm,unit}}','"in"'));
  raise exception 'Accepted mismatched scalar units';
 exception when check_violation then null;
 end;
 begin
  perform public.spec_coherence_metadata_internal_v1(jsonb_set(doc->'contract','{{rules_version}}','1'),fields);
  raise exception 'Accepted strict mode on v1';
 exception when check_violation then null;
 end;
 contract:=jsonb_set(doc->'contract','{{scalar_ordered_pairs}}','[["post_mm","frame_mm"]]');
 if public.spec_coherence_issues_internal_v1(contract,fields,'{{"post_mm":"27.2","frame_mm":"27.20"}}')<>'[]' then
  raise exception 'Existing non-strict ranges changed';
 end if;
 contract:='{{"rules_version":2,"scalar_ordered_pairs":[["bearing_inner_diameter_mm","bearing_outer_diameter_mm","lt"]]}}';
 fields:='{{"bearing_inner_diameter_mm":{{"data_type":"number","unit":"mm"}},"bearing_outer_diameter_mm":{{"data_type":"number","unit":"mm"}}}}';
 if jsonb_array_length(public.spec_coherence_pairs_internal_v1(contract,fields))<>1
  or jsonb_array_length(public.spec_coherence_issues_internal_v1(contract,fields,
    '{{"bearing_inner_diameter_mm":"30","bearing_outer_diameter_mm":"30"}}'))<>2 then
  raise exception 'Explicit strict pair duplicated an inherited comparison';
 end if;
end $cases$;
select 'PASS: strict scalar cases, invalid metadata, predecessor rejection and unchanged ordinary ranges' as test_result;
select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
 'md5',md5(pg_get_functiondef(p.oid)),'acl',p.proacl::text,'owner_name',pg_get_userbyid(p.proowner),
 'security_definer',p.prosecdef,'volatility',p.provolatile::text,'settings',to_jsonb(p.proconfig)) order by p.proname)
 as expected_functions from pg_proc p where p.oid=any(array[
 {','.join("'public." + f['signature'] + "'" for f in before)}]::regprocedure[]);
rollback;
"""
    out = ROOT / '.tmp/product-spec-catalog/strict-scalar-20260915'
    path = out / 'tests.sql'; path.write_text(sql)
    result = subprocess.run([str(ROOT / 'scripts/db/query.sh'), 'local', '--file', str(path)],
                            cwd=ROOT, capture_output=True, text=True)
    log = result.stdout + result.stderr
    (out / 'tests.log').write_text(log)
    if result.returncode or 'ROLLBACK' not in log or 'PASS: strict scalar' not in log:
        raise RuntimeError('Strict scalar regression failed; inspect ' + str(out / 'tests.log'))
    print(json.dumps({'value_cases':len(fixture['cases']),
                      'invalid_metadata_cases':len(fixture['invalid_contracts'])+2,
                      'other_assertions':3,'rollback':True,'product_writes':False}))


if __name__ == '__main__':
    main()
