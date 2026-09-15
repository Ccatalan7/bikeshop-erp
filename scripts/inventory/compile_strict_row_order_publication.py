#!/usr/bin/env python3
"""Build the guarded forward for the independently reviewed row-order delta."""
import hashlib
import json
from pathlib import Path
from compile_product_spec_strict_row_order import compile_sql

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT/'docs/development/product-specs-research-2026-09-05'
VERSION = '20260908185800'
NAME = VERSION + '_product_spec_strict_row_order.sql'
PINS = {
 'strict-row-order-publication-preimage-2026-09-08.json':'301776892966ee78575772d11d564e02658430455b1b763e1b789e7d6c597085',
 'strict-row-order-publication-expected-2026-09-08.json':'bd13ab227d95a0f292892b8f10996f3087cfd01791e04fe11cb8120e3730ddda'}


def load(name):
    p=RESEARCH/name
    if hashlib.sha256(p.read_bytes()).hexdigest()!=PINS[name]:
        raise ValueError('Unreviewed input: '+name)
    return json.loads(p.read_text())


def literal(value):
    return "'"+json.dumps(value,ensure_ascii=False).replace("'","''")+"'::jsonb"


def compile_publication():
    before=load('strict-row-order-publication-preimage-2026-09-08.json')
    after=load('strict-row-order-publication-expected-2026-09-08.json')
    old={f['signature']:f for f in before['functions']}
    new={f['signature']:f for f in after['functions']}
    if set(old)!=set(new) or len(old)!=2:
        raise ValueError('Exactly two reviewed functions')
    metadata=[{k:v for k,v in f.items() if k!='definition'} for f in new.values()]
    for f in metadata:
        if {k:v for k,v in f.items() if k!='md5'}!={k:v for k,v in old[f['signature']].items()
                if k not in ('md5','definition')}:
            raise ValueError('Function permissions or execution mode changed')
        f['before_md5']=old[f['signature']]['md5']
    state=literal(metadata)
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
   raise exception 'Unreviewed strict-row function permissions or mode';
  end if;
  old_count:=old_count+case when actual.body_md5=wanted->>'before_md5' then 1 else 0 end;
  new_count:=new_count+case when actual.body_md5=wanted->>'md5' then 1 else 0 end;
 end loop;
 if old_count<>2 and new_count<>2 then
  raise exception 'Unreviewed or mixed strict-row function bodies';
 end if;
end $before$;
"""
    digest="""select jsonb_build_object(
 'definitions',(select md5(coalesce(jsonb_agg(to_jsonb(d) order by d.id),'[]')::text) from public.spec_definitions d),
 'templates',(select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')::text) from public.spec_templates t),
 'fields',(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_template_fields f),
 'facts',(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_facts f),
 'references',(select md5(coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]')::text) from public.product_spec_references r),
 'products',(select md5(coalesce(jsonb_agg(jsonb_build_array(p.id,p.spec_revision,p.spec_template_id,p.spec_reference_id) order by p.id),'[]')::text) from public.products p)) as fingerprint
"""
    verify=f"""-- Pure SELECT read-back: body, owner, ACL, mode and exact return behavior.
with expected as (select value w from jsonb_array_elements({state})), checked as (
 select w,p.oid,md5(pg_get_functiondef(p.oid)) body_md5,pg_get_userbyid(p.proowner) owner_name,
 p.proacl::text acl,p.prosecdef security_definer,p.provolatile::text volatility,
 to_jsonb(p.proconfig) settings from expected left join pg_proc p
 on p.oid=to_regprocedure('public.'||(w->>'signature')))
select 1/(case when count(*)=2 and bool_and(oid is not null and body_md5=w->>'md5'
 and owner_name=w->>'owner_name' and acl=w->>'acl'
 and security_definer=(w->>'security_definer')::boolean and volatility=w->>'volatility'
 and settings=w->'settings') then 1 else 0 end) as exact_strict_row_functions from checked;
with checked as materialized (select public.spec_rows_schema_validate_internal_v1(
 validation_rules->'rows_schema') as result from public.spec_definitions
 where validation_rules ? 'rows_schema')
select count(*) as existing_row_schemas_validated,
 count(result) as nonnull_void_results from checked;
"""
    fixture=json.loads((ROOT/'test/fixtures/product_spec_strict_row_order.json').read_text())
    schema=fixture['schema']
    values={'schema_version':2,'rows':[{'id':'readback-body','values':{'inner':'30','outer':'41.8'},'sources':[]}]}
    verify+=f"""select 1/(case when public.spec_rows_validate_internal_v1({literal(schema)},
 {literal(values)})={literal(values)} then 1 else 0 end) as strict_body_roundtrip;
"""
    migration=("-- Reviewed extension: two private functions; no metadata/data rewrite or new grants.\n"
        "begin isolation level repeatable read;\nset local lock_timeout='5s';\nset local statement_timeout='30s';\n"
        "lock table public.spec_definitions in share mode;\n"+guard+
        "create temporary table strict_row_before on commit drop as "+digest+";\n"+
        compile_sql().split('\n',1)[1]+"\n"+verify+
        "select 1/(case when b.fingerprint=a.fingerprint then 1 else 0 end) as unchanged_catalog_and_products\n"
        "from strict_row_before b cross join ("+digest+") a;\ncommit;\n")
    return migration,verify


if __name__=='__main__':
    migration,verify=compile_publication()
    (ROOT/'supabase/migrations'/NAME).write_text(migration)
    (ROOT/'supabase/manual_checks/verification'/NAME).write_text(verify)
    print(NAME)
