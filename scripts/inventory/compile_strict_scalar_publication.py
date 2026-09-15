#!/usr/bin/env python3
"""Prepare a guarded four-function forward, without activating a template."""
import hashlib
import json

from compile_product_spec_strict_scalar import ROOT, compile_candidate

RESEARCH=ROOT/'docs/development/product-specs-research-2026-09-05'
EXPECTED={
 'spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)':'be905e64b956bff3c947784d791a7c00',
 'spec_coherence_metadata_internal_v1(jsonb,jsonb)':'1ac8377c198430e211730278917cfdf3',
 'spec_coherence_pairs_internal_v1(jsonb,jsonb)':'7eedf2cd0074f0d14fa89a8f145b5c8f',
 'spec_coherence_publication_guard_internal_v1()':'f95f1176094ae7376a826a85b0dbd8f0',
}


def literal(value):
    return "'"+json.dumps(value,ensure_ascii=False).replace("'","''")+"'::jsonb"


def compile_publication():
    previous,bodies=compile_candidate()
    expected=json.loads((RESEARCH/'strict-scalar-expected-2026-09-15.json').read_text())['functions']
    old={f['signature']:f for f in previous}
    if {f['signature']:f['md5'] for f in expected}!=EXPECTED or set(old)!=set(EXPECTED):
        raise ValueError('Unreviewed function set or expected bodies')
    for f in expected:
        if {k:v for k,v in f.items() if k!='md5'}!={k:v for k,v in old[f['signature']].items() if k not in {'md5','definition'}}:
            raise ValueError('Permissions or execution mode changed')
        f['before_md5']=old[f['signature']]['md5']
    state=literal(expected)
    guard=f"""do $before$
declare wanted jsonb; actual record; old_count integer:=0; new_count integer:=0;
begin
 for wanted in select value from jsonb_array_elements({state}) loop
  select md5(pg_get_functiondef(p.oid)) body_md5,pg_get_userbyid(p.proowner) owner_name,
   p.proacl::text acl,p.prosecdef security_definer,p.provolatile::text volatility,
   to_jsonb(p.proconfig) settings into actual from pg_proc p
   where p.oid=to_regprocedure('public.'||(wanted->>'signature'));
  if not found or actual.owner_name is distinct from wanted->>'owner_name'
   or actual.acl is distinct from wanted->>'acl'
   or actual.security_definer is distinct from (wanted->>'security_definer')::boolean
   or actual.volatility is distinct from wanted->>'volatility'
   or actual.settings is distinct from wanted->'settings' then
   raise exception 'Unreviewed scalar-order function permissions or mode';
  end if;
  old_count:=old_count+case when actual.body_md5=wanted->>'before_md5' then 1 else 0 end;
  new_count:=new_count+case when actual.body_md5=wanted->>'md5' then 1 else 0 end;
 end loop;
 if old_count<>4 and new_count<>4 then
  raise exception 'Unreviewed or mixed scalar-order function bodies';
 end if;
end $before$;
"""
    verify=f"""-- Read-only exact code, ACL, mode and behavior verification.
with expected as (select value w from jsonb_array_elements({state})), checked as (
 select w,p.oid,md5(pg_get_functiondef(p.oid)) body_md5,pg_get_userbyid(p.proowner) owner_name,
 p.proacl::text acl,p.prosecdef security_definer,p.provolatile::text volatility,
 to_jsonb(p.proconfig) settings from expected left join pg_proc p
 on p.oid=to_regprocedure('public.'||(w->>'signature')))
select 1/(case when count(*)=4 and bool_and(oid is not null and body_md5=w->>'md5'
 and owner_name=w->>'owner_name' and acl=w->>'acl'
 and security_definer=(w->>'security_definer')::boolean and volatility=w->>'volatility'
 and settings=w->'settings') then 1 else 0 end) as exact_strict_scalar_functions from checked;
with checked as materialized (select public.spec_coherence_metadata_internal_v1(
 t.form_contract,public.spec_coherence_fields_internal_v1(t.id)) as result
 from public.spec_templates t)
select count(*) as existing_template_contracts_validated,count(result) as nonnull_void_results from checked;
"""
    fixture=json.loads((ROOT/'test/fixtures/product_spec_strict_scalar.json').read_text())
    fields={k:{'data_type':t,'unit':fixture['units'][k]} for k,t in fixture['types'].items()}
    verify+=f"""with data as (select {literal(fixture)} doc), cases as (
 select c,public.spec_coherence_issues_internal_v1(doc->'contract',{literal(fields)},c->'values') issues
 from data cross join lateral jsonb_array_elements(doc->'cases') c), checked as (
 select c,issues,(select coalesce(jsonb_agg(i->'field' order by n),'[]')
 from jsonb_array_elements(issues) with ordinality x(i,n)) observed from cases)
select count(*) as strict_scalar_cases,1/(case when count(*)=11 and bool_and(
 observed=c->'expected_fields' and not exists(select 1 from jsonb_array_elements(issues) i
 where i->>'code'<>'range_order' or i->'blocking'<>'true'::jsonb)) then 1 else 0 end) as strict_scalar_behavior_matches from checked;
"""
    digest="""select jsonb_build_object(
 'definitions',(select md5(coalesce(jsonb_agg(to_jsonb(d) order by d.id),'[]')::text) from public.spec_definitions d),
 'templates',(select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')::text) from public.spec_templates t),
 'fields',(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_template_fields f),
 'facts',(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_facts f),
 'references',(select md5(coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]')::text) from public.product_spec_references r),
 'products',(select md5(coalesce(jsonb_agg(jsonb_build_array(p.id,p.spec_revision,p.spec_template_id,p.spec_reference_id) order by p.id),'[]')::text) from public.products p)) as fingerprint
"""
    migration=("-- Strict scalar comparison only: four existing functions; no grants, metadata or product changes.\n"
        "begin isolation level repeatable read;\nset local lock_timeout='5s';\nset local statement_timeout='30s';\n"
        "lock table public.spec_definitions in share mode;\n"+guard+
        "create temporary table strict_scalar_before on commit drop as "+digest+";\n"+
        '\n;\n'.join(bodies[k] for k in sorted(bodies))+'\n;\n'+verify+
        "select 1/(case when b.fingerprint=a.fingerprint then 1 else 0 end) as unchanged_catalog_and_products\n"
        "from strict_scalar_before b cross join ("+digest+") a;\ncommit;\n")
    return migration,verify


if __name__=='__main__':
    migration,verify=compile_publication()
    for name,body in [('candidate',migration),('verification',verify)]:
        path=ROOT/'.tmp/db'/('strict-scalar-2026-09-15-'+name+'.sql');path.write_text(body)
    print(json.dumps({'functions':4,'sha256':hashlib.sha256(migration.encode()).hexdigest(),'applied':False}))
