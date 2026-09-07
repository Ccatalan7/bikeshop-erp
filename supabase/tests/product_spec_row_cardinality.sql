-- Local synthetic boundary checks. Root serializes execution; no product fill.
begin;
set local client_min_messages=error;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
create temp table row_cardinality_document(doc jsonb);
\ir fixtures/product_spec_row_cardinality.sql
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values('c0df2500-0000-4000-8000-000000000001','Cardinality fixture');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('c0df2500-0000-4000-8000-000000000091','authenticated','authenticated','cardinality@example.invalid','',now(),'{}',
 '{"account_type":"public_store_customer","customer_tenant_id":"c0df2500-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='c0df2500-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values('c0df2500-0000-4000-8000-000000000091','c0df2500-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"c0df2500-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','c0df2500-0000-4000-8000-000000000091',true);
create temp table cardinality_field_ids(key text primary key,id uuid);
insert into cardinality_field_ids values
 ('items','c0df2500-0000-4000-8000-000000000011'),('other_items','c0df2500-0000-4000-8000-000000000012'),
 ('total','c0df2500-0000-4000-8000-000000000013'),('other_total','c0df2500-0000-4000-8000-000000000014'),
 ('description','c0df2500-0000-4000-8000-000000000015');
insert into public.spec_definitions(id,tenant_id,key,label,data_type,validation_rules)
select f.id,'c0df2500-0000-4000-8000-000000000001',e.key,e.key,e.value->>'data_type',e.value->'validation_rules'
 from row_cardinality_document cross join lateral jsonb_each(doc->'fields') e join cardinality_field_ids f using(key);
insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract)
select 'c0df2500-0000-4000-8000-000000000050','c0df2500-0000-4000-8000-000000000001',
 'row_cardinality_fixture','Cardinality','row_cardinality_fixture',doc->'contract' from row_cardinality_document;
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select 'c0df2500-0000-4000-8000-000000000050',id,'contents',1 from cardinality_field_ids;
set constraints all immediate;

create function pg_temp.cardinality_projection(issues jsonb) returns jsonb language sql immutable as $$
 select coalesce(jsonb_agg(jsonb_build_object('code',i->>'code','field',i->>'field','row_id',i->>'row_id',
 'blocking',coalesce((i->>'blocking')::boolean,true)) order by n),'[]')
 from jsonb_array_elements(issues) with ordinality x(i,n) where i->>'code' like 'row_cardinality_%' or i->>'code'='row_shape'
$$;
create function pg_temp.cardinality_values(p_case text) returns jsonb language sql stable as $$
 select c->'values' from row_cardinality_document cross join lateral jsonb_array_elements(doc->'cases') c where c->>'id'=p_case
$$;
select is(pg_temp.cardinality_projection(public.spec_coherence_issues_internal_v1(doc->'contract',doc->'fields',c->'values')),
 c->'expected','shared evaluator: '||(c->>'id'))
 from row_cardinality_document cross join lateral jsonb_array_elements(doc->'cases') c;
select throws_ok(format('select public.spec_coherence_metadata_internal_v1(%L::jsonb,%L::jsonb)',c->'contract',c->'fields'),
 '23514',null,'invalid metadata: '||(c->>'id'))
 from row_cardinality_document cross join lateral jsonb_array_elements(doc->'invalid_metadata') c;
select is(pg_temp.cardinality_projection(public.spec_validate_draft_internal_v1('c0df2500-0000-4000-8000-000000000050',c->'values')),
 c->'expected','central validator: '||(c->>'id'))
 from row_cardinality_document cross join lateral jsonb_array_elements(doc->'cases') c
 where c->>'id' not like 'invalid_total_%';
select is((select count(*) from jsonb_array_elements(public.spec_validate_draft_internal_v1(
 'c0df2500-0000-4000-8000-000000000050',pg_temp.cardinality_values('invalid_total_fractional'))) i
 where coalesce((i->>'blocking')::boolean,true)),1::bigint,'invalid total has one blocking scalar owner');
select is(public.spec_coherence_issues_internal_v1('{}','{}','{}'),'[]'::jsonb,'absent extension keeps its previous behavior');
select lives_ok($$select public.spec_coherence_metadata_internal_v1('{"rules_version":2,"row_coherence":{"version":1,"links":[]}}','{}')$$,
 'v1 remains supported');

-- Same-template endpoints and dependencies cannot be changed beneath a rule.
select throws_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{prerequisites,total}','["items"]')
 where id='c0df2500-0000-4000-8000-000000000050'$$,'23514',null,'cardinality closes a reverse prerequisite cycle');
select throws_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{roles,total}','"legacy"')
 where id='c0df2500-0000-4000-8000-000000000050'$$,'23514',null,'retired total is not a current endpoint');
select throws_ok($$update public.spec_definitions set validation_rules=validation_rules-'integer'
 where id='c0df2500-0000-4000-8000-000000000013'$$,'23514',null,'definition cannot remove the integer domain');
select throws_ok($$update public.spec_definitions set validation_rules=jsonb_set(validation_rules,'{min}','-1')
 where id='c0df2500-0000-4000-8000-000000000013'$$,'23514',null,'definition cannot allow negative totals');
select throws_ok($$delete from public.spec_template_fields where template_id='c0df2500-0000-4000-8000-000000000050'
 and spec_definition_id='c0df2500-0000-4000-8000-000000000013'$$,'23514',null,'deleting the total cannot strand a rule');

update public.spec_templates set form_contract=jsonb_set(form_contract,'{allowed_when,items}',
 '{"kind":"when","rows":[[{"field":"total","operator":"gt","value_type":"decimal","value":"0"}]]}')
 where id='c0df2500-0000-4000-8000-000000000050';
select is((select jsonb_agg(i->>'code') from jsonb_array_elements(public.spec_validate_draft_internal_v1(
 'c0df2500-0000-4000-8000-000000000050',pg_temp.cardinality_values('zero_does_not_delete_rows'))) i
 where coalesce((i->>'blocking')::boolean,true)), '["field_applicability"]'::jsonb,
 'zero and populated table retain one applicability conflict without duplicate cardinality');
update public.spec_templates set form_contract=jsonb_set(form_contract,'{allowed_when}','{}')
 where id='c0df2500-0000-4000-8000-000000000050';

-- Required-cell parity: an unknown token is pending; false and zero are known.
select ok(exists(select 1 from jsonb_array_elements(public.spec_validate_draft_internal_v1(
 'c0df2500-0000-4000-8000-000000000050',jsonb_set(pg_temp.cardinality_values('equal_two_rows'),
 '{items,rows,0,values,state}','"Desconocido / sin confirmar"'))) i
 where i->>'code'='row_incomplete' and i->'blocking'='false'::jsonb),
 'required unknown token remains pending even though its key exists');
update public.spec_definitions set validation_rules=jsonb_set(validation_rules,'{rows_schema,columns,3,required}','true')
 where id='c0df2500-0000-4000-8000-000000000011';
select ok(not exists(select 1 from jsonb_array_elements(public.spec_validate_draft_internal_v1(
 'c0df2500-0000-4000-8000-000000000050',jsonb_set(jsonb_set(pg_temp.cardinality_values('equal_two_rows'),
 '{items,rows,0,values,active}','false'),'{items,rows,1,values,active}','false'))) i
 where i->>'code'='row_incomplete'),'required false and zero remain known observations');
update public.spec_definitions set validation_rules=(select doc#>'{fields,items,validation_rules}' from row_cardinality_document)
 where id='c0df2500-0000-4000-8000-000000000011';

insert into public.products(id,tenant_id,name,sku,price,cost,is_active,spec_template_id)
 values('c0df2500-0000-4000-8000-000000000020','c0df2500-0000-4000-8000-000000000001',
 'Cardinality fixture','CARDINALITY',100,50,true,'c0df2500-0000-4000-8000-000000000050');
create function pg_temp.cardinality_save(p_case text,p_operation text,p_version_delta integer default 0) returns jsonb language sql as $$
 select public.save_product_with_specs_v1(
 '{"id":"c0df2500-0000-4000-8000-000000000020","name":"Cardinality fixture","sku":"CARDINALITY"}',false,
 'c0df2500-0000-4000-8000-000000000050',
 (select contract_version+p_version_delta from public.spec_templates where id='c0df2500-0000-4000-8000-000000000050'),
 (select coalesce(jsonb_object_agg(f.id::text,case when e.key='total' then jsonb_build_object('number',e.value)
   else jsonb_build_object('rows',e.value) end),'{}') from jsonb_each(pg_temp.cardinality_values(p_case)) e
   join cardinality_field_ids f using(key)),
 (select spec_revision from public.products where id='c0df2500-0000-4000-8000-000000000020'),null,p_operation,
 (select updated_at from public.products where id='c0df2500-0000-4000-8000-000000000020'))
$$;
grant select on row_cardinality_document,cardinality_field_ids to authenticated;
grant execute on function pg_temp.cardinality_save(text,text,integer),pg_temp.cardinality_values(text) to authenticated;
set constraints product_spec_fact_constraint,product_spec_value_constraint deferred;
set local role authenticated;
select lives_ok($$select pg_temp.cardinality_save('equal_two_rows','cardinality-equal')$$,'authenticated aggregate accepts exact equality');
reset role;
create temp table cardinality_saved as select md5(to_jsonb(p)::text) product_digest,
 (select md5(jsonb_agg(to_jsonb(f) order by f.id)::text) from public.spec_facts f where f.subject_type='product' and f.subject_id=p.id) fact_digest
 from public.products p where id='c0df2500-0000-4000-8000-000000000020';
set local role authenticated;
select throws_ok($$select pg_temp.cardinality_save('more_rows_than_total','cardinality-conflict')$$,'23514',null,
 'authenticated aggregate rejects excess occurrence count');
select throws_ok($$select pg_temp.cardinality_save('equal_two_rows','cardinality-old-version',-1)$$,'40001',null,
 'an old template version cannot bypass the cardinality contract');
reset role;
select is((select md5(to_jsonb(p)::text) from public.products p where id='c0df2500-0000-4000-8000-000000000020'),
 (select product_digest from cardinality_saved),'failed save preserves product identity commercial fields and revision');
select is((select md5(jsonb_agg(to_jsonb(f) order by f.id)::text) from public.spec_facts f
 where f.subject_type='product' and f.subject_id='c0df2500-0000-4000-8000-000000000020'),
 (select fact_digest from cardinality_saved),'failed save preserves every fact row and source');
set constraints product_spec_fact_constraint,product_spec_value_constraint immediate;
select throws_ok($$update public.spec_facts set value_number=1 where subject_type='product'
 and subject_id='c0df2500-0000-4000-8000-000000000020' and spec_definition_id='c0df2500-0000-4000-8000-000000000013'$$,
 '23514',null,'direct fact edit cannot contradict the populated collection');
set constraints product_spec_fact_constraint,product_spec_value_constraint deferred;
set local role authenticated;
select lives_ok($$select pg_temp.cardinality_save('fewer_rows_than_total','cardinality-partial')$$,'incomplete collection can be saved without autofill');
select lives_ok($$select pg_temp.cardinality_save('total_missing_with_rows','cardinality-unknown-total')$$,'unknown total can be saved without inferring it');
reset role;
select is((select count(*) from public.spec_facts where subject_type='product'
 and subject_id='c0df2500-0000-4000-8000-000000000020' and spec_definition_id='c0df2500-0000-4000-8000-000000000013'),
 0::bigint,'no inferred total is persisted');
select is((select value_json from public.spec_facts where subject_type='product'
 and subject_id='c0df2500-0000-4000-8000-000000000020' and spec_definition_id='c0df2500-0000-4000-8000-000000000011'),
 pg_temp.cardinality_values('total_missing_with_rows')->'items','partial saves retain IDs cells and per-row sources');
set constraints product_spec_fact_constraint,product_spec_value_constraint immediate;
select throws_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{row_coherence}','{"version":1,"links":[]}')
 where id='c0df2500-0000-4000-8000-000000000050'$$,'23514',null,'populated endpoint prevents in-place removal of cardinality');

-- References are independent observations; adoption still evaluates the rule.
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
select 'cardinality-conflicting-reference','row_cardinality_fixture','Fixture','Model','Cardinality reference',
 jsonb_build_object('c0df2500-0000-4000-8000-000000000011',jsonb_build_object('rows',pg_temp.cardinality_values('more_rows_than_total')->'items'),
 'c0df2500-0000-4000-8000-000000000013',jsonb_build_object('number','1')),
 '["https://example.com/document"]','2026-09-07';
select ok(exists(select 1 from jsonb_array_elements(public.spec_validate_draft_internal_v1(
 'c0df2500-0000-4000-8000-000000000050',pg_temp.cardinality_values('more_rows_than_total'),
 'cardinality-conflicting-reference','Fixture','Model','')) i
 where i->>'code'='row_cardinality_conflict' and i->'blocking'='true'::jsonb),
 'matching reference does not approve a cardinality contradiction');
insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract)
 values('c0df2500-0000-4000-8000-000000000051','c0df2500-0000-4000-8000-000000000001',
 'row_cardinality_reference_fixture','Reference population','row_cardinality_reference_fixture',
 '{"rules_version":2,"allowed_when":{},"required_when":{},"allowed_options":{},"prerequisites":{},"row_coherence":{"version":1,"links":[]}}');
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order) values
 ('c0df2500-0000-4000-8000-000000000051','c0df2500-0000-4000-8000-000000000012','contents',1),
 ('c0df2500-0000-4000-8000-000000000051','c0df2500-0000-4000-8000-000000000014','contents',2);
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
 values('cardinality-total-only-reference','row_cardinality_reference_fixture','Fixture','Total','Total only',
 '{"c0df2500-0000-4000-8000-000000000014":{"number":"0"}}','["https://example.com/document"]','2026-09-07');
select throws_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{row_coherence}',
 '{"version":2,"links":[],"cardinalities":[{"id":"reference_total","field":"other_items","total_field":"other_total"}]}')
 where id='c0df2500-0000-4000-8000-000000000051'$$,'23514',null,
 'a reference containing only the total also prevents in-place activation');
select ok(not has_function_privilege('authenticated','public.spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)','execute')
 and not has_function_privilege('anon','public.spec_coherence_metadata_internal_v1(jsonb,jsonb)','execute'),
 'metadata and evaluator remain private helpers');
select * from finish();
rollback;
