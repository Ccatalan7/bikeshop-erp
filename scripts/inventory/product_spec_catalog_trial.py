#!/usr/bin/env python3
"""Emit a LOCAL rollback trial of the compiled all-family field catalogue.

This is not a production migration or fill applicator. The generated SQL ends
in ROLLBACK and verifies that every existing product observation is preserved.
Run its file only through scripts/db/query.sh local --file PATH.
"""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'docs/development/product-specs-research-2026-09-05'


def generate(catalogue, cases):
    # The local catalogue has historical/missing definitions and is not a
    # production clone. Keep field keys/types/conditions exact in a synthetic
    # tenant, changing only database IDs. Production preimages are checked by
    # the compiler against a guarded live metadata snapshot, separately.
    catalogue = deepcopy(catalogue)
    tenant = '99bd0000-0000-4000-8000-000000000001'
    for d in catalogue['definitions'].values():
        d['id'] = str(uuid.uuid5(uuid.NAMESPACE_URL, 'vinabike:catalog-trial:def:' + d['key']))
        d['origin'] = 'new'
    for t in catalogue['templates']:
        t['id'] = str(uuid.uuid5(uuid.NAMESPACE_URL, 'vinabike:catalog-trial:template:' + t['key']))
        t['origin'] = 'new'
    catalogue['representation_cases'] = cases
    encoded = json.dumps(catalogue, ensure_ascii=False, separators=(',', ':'))
    if '$catalog$' in encoded:
        raise ValueError('SQL document delimiter collision')
    return '''-- GENERATED LOCAL-ONLY validation trial; no product write or committed metadata.
begin;
set local client_min_messages=error;
set local statement_timeout='120s';
insert into public.tenants(id,shop_name) values ('99bd0000-0000-4000-8000-000000000001','Catalogue field trial');
create temporary table spec_catalog_trial_document(value jsonb) on commit drop;
insert into spec_catalog_trial_document values ($catalog$''' + encoded + '''$catalog$::jsonb);
create temporary table spec_catalog_trial_baseline as select
 (select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_facts f) facts,
 (select md5(coalesce(jsonb_agg(jsonb_build_array(p.id,p.spec_revision,p.spec_template_id,p.spec_reference_id) order by p.id),'[]')::text) from public.products p) identity;
do $trial$
declare doc jsonb; d jsonb; t jsonb; f jsonb; opt text; n integer; expected public.spec_definitions%rowtype;
begin
 select value into doc from spec_catalog_trial_document;
 for d in select value from jsonb_each(doc->'definitions') loop
   select * into expected from public.spec_definitions where id=(d->>'id')::uuid;
   if d->>'origin'='existing' and found then
     if expected.key<>d->>'key' or expected.data_type<>d->>'data_type'
       or expected.unit is distinct from d->>'unit' then
       raise exception 'Existing definition identity or type drift: %',d->>'key';
     end if;
   elsif found or exists(select 1 from public.spec_definitions where key=d->>'key' and tenant_id='99bd0000-0000-4000-8000-000000000001') then
     raise exception 'New definition collides with existing metadata: %',d->>'key';
   end if;
   insert into public.spec_definitions(id,tenant_id,key,label,data_type,unit,allowed_values,validation_rules)
   values((d->>'id')::uuid,'99bd0000-0000-4000-8000-000000000001',d->>'key',d->>'label',d->>'data_type',d->>'unit',d->'allowed_values',d->'validation_rules')
   on conflict(id) do update set label=excluded.label,allowed_values=excluded.allowed_values,validation_rules=excluded.validation_rules;
   n:=0;
   for opt in select jsonb_array_elements_text(d->'allowed_values') loop
     if not exists(select 1 from public.spec_definition_values v where v.spec_definition_id=(d->>'id')::uuid and v.label=opt and v.is_active) then
       insert into public.spec_definition_values(tenant_id,spec_definition_id,label,code,sort_order)
       values('99bd0000-0000-4000-8000-000000000001',(d->>'id')::uuid,opt,'catalog_'||md5(opt),n);
     end if;
     n:=n+1;
   end loop;
 end loop;
 for t in select value from jsonb_array_elements(doc->'templates') loop
   -- The local fixture can lack production metadata. Seed those exact reviewed
   -- IDs inside this rollback only; an existing local identity must still agree.
   if t->>'origin'='existing' and exists(select 1 from public.spec_templates x where x.id=(t->>'id')::uuid)
      and not exists(select 1 from public.spec_templates x
      where x.id=(t->>'id')::uuid and x.key=t->>'key' and x.technical_family=t->>'technical_family' and x.is_active) then
     raise exception 'Existing template identity drift: %',t->>'key';
   end if;
   insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract,is_active)
   values((t->>'id')::uuid,'99bd0000-0000-4000-8000-000000000001',t->>'key',t->>'name',t->>'technical_family',t->'form_contract',true)
   on conflict(id) do update set name=excluded.name,form_contract=excluded.form_contract;
   for f in select value from jsonb_array_elements(t->'fields') loop
     insert into public.spec_template_fields(tenant_id,template_id,spec_definition_id,section_key,sort_order,is_required,visibility_rules,option_rules,constraint_rules)
     values('99bd0000-0000-4000-8000-000000000001',(t->>'id')::uuid,(doc->'definitions'->(f->>'key')->>'id')::uuid,f->>'section_key',(f->>'sort_order')::integer,false,
       f->'visibility_rules',f->'option_rules',f->'constraint_rules')
     on conflict(template_id,spec_definition_id) do update set section_key=excluded.section_key,sort_order=excluded.sort_order,is_required=false,
       visibility_rules=excluded.visibility_rules,option_rules=excluded.option_rules,constraint_rules=excluded.constraint_rules;
   end loop;
 end loop;
end $trial$;
set constraints all immediate;
do $cases$
declare doc jsonb; c jsonb; t jsonb; issues jsonb; actual jsonb; fields jsonb; wanted jsonb;
begin
 select value into doc from spec_catalog_trial_document;
 for c in select value from jsonb_array_elements(doc->'representation_cases') loop
   select value into strict t from jsonb_array_elements(doc->'templates') where value->>'key'=c->>'template';
   issues:=public.spec_validate_draft_internal_v1((t->>'id')::uuid,c->'values');
   select coalesce(jsonb_agg(jsonb_build_object('code',i->>'code','field',i->>'field') order by i->>'code',i->>'field'),'[]'::jsonb)
     into actual from jsonb_array_elements(issues) i where coalesce((i->>'blocking')::boolean,true);
   wanted:=coalesce(c->'expected_sql_blocking',c->'expected_blocking');
   if actual is distinct from wanted then
     raise exception 'Representation case % failed. Expected %, got %; all issues %',c->>'id',wanted,actual,issues;
   end if;
   if c ? 'expected_issue_subset' or c ? 'expected_sql_issue_subset' then
     select coalesce(jsonb_agg(jsonb_build_object('code',i->>'code','field',i->>'field',
       'blocking',coalesce((i->>'blocking')::boolean,true))),'[]'::jsonb)
       into actual from jsonb_array_elements(issues) i;
     wanted:=coalesce(c->'expected_sql_issue_subset',c->'expected_issue_subset');
     if not (actual @> wanted) then
       raise exception 'Required diagnostic subset missing in %: %',c->>'id',issues;
     end if;
   end if;
   if exists(select 1 from jsonb_array_elements(issues) i
     where i->>'field' in (select jsonb_array_elements_text(coalesce(c->'forbidden_issue_fields','[]')))) then
     raise exception 'Impossible prerequisite remained in %: %',c->>'id',issues;
   end if;
   if c ? 'expected_row_condition_issues' then
     select jsonb_object_agg(f->>'key',jsonb_build_object(
       'data_type',doc->'definitions'->(f->>'key')->'data_type',
       'schema',doc->'definitions'->(f->>'key')->'validation_rules'->'rows_schema'))
       into fields from jsonb_array_elements(t->'fields') f
       where coalesce(t->'form_contract'->'roles'->>(f->>'key'),'primary')<>'legacy';
     issues:=public.spec_row_conditions_issues_internal_v1(t->'form_contract',fields,c->'values');
     -- The central comparison above already owns row_shape. Dart's condition
     -- helper delegates that diagnostic to its row parser; SQL may return it
     -- here, so compare conditional diagnostics separately from schema shape.
     select coalesce(jsonb_agg(i-'message' order by i->>'code',i->>'field',i->>'row_id',i->>'column'),'[]'::jsonb)
       into actual from jsonb_array_elements(issues) i where i->>'code'<>'row_shape';
     select coalesce(jsonb_agg(i order by i->>'code',i->>'field',i->>'row_id',i->>'column'),'[]'::jsonb)
       into wanted from jsonb_array_elements(c->'expected_row_condition_issues') i;
     if actual is distinct from wanted then
       raise exception 'Row conditions case % failed. Expected %, got %',c->>'id',wanted,actual;
     end if;
   end if;
 end loop;
end $cases$;
select jsonb_build_object('templates',count(*),'fields',sum(jsonb_array_length(t->'fields')),'deferred_guards_passed',true) as trial
 from spec_catalog_trial_document d cross join lateral jsonb_array_elements(d.value->'templates') tt(t);
select jsonb_build_object('representation_cases_passed',jsonb_array_length(value->'representation_cases')) from spec_catalog_trial_document;
select 1/case when b.facts=(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_facts f)
 and b.identity=(select md5(coalesce(jsonb_agg(jsonb_build_array(p.id,p.spec_revision,p.spec_template_id,p.spec_reference_id) order by p.id),'[]')::text) from public.products p)
 then 1 else 0 end preserved_product_facts_and_identity from spec_catalog_trial_baseline b;
rollback;
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=RESEARCH / 'all-family-reviewed-fields-2026-09-06.json')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cases', type=Path, default=RESEARCH / 'all-family-representation-cases-2026-09-06.json')
    args = parser.parse_args()
    catalogue = json.loads(args.input.read_text())
    if catalogue['publication_gates']['fill_allowed'] is not False:
        raise ValueError('This trial only accepts an unpublished field proposal')
    cases = json.loads(args.cases.read_text())['cases']
    args.output.write_text(generate(catalogue, cases))
    print(json.dumps({'local_trial': str(args.output), 'source_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
                      'cases_sha256': hashlib.sha256(args.cases.read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()
