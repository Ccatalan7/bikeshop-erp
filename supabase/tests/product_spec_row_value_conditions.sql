-- Synthetic row prerequisites: metadata, same-row scope, publication and writer.
begin;
set local client_min_messages=error;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
create temp table row_value_condition_document(doc jsonb);
\ir fixtures/product_spec_row_value_conditions.sql
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values('c0cf2400-0000-4000-8000-000000000001','Row condition fixture');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('c0cf2400-0000-4000-8000-000000000091','authenticated','authenticated','row-values@example.invalid','',now(),'{}',
 '{"account_type":"public_store_customer","customer_tenant_id":"c0cf2400-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='c0cf2400-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values('c0cf2400-0000-4000-8000-000000000091','c0cf2400-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"c0cf2400-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','c0cf2400-0000-4000-8000-000000000091',true);
insert into public.spec_definitions(id,tenant_id,key,label,data_type,validation_rules)
select 'c0cf2400-0000-4000-8000-000000000011','c0cf2400-0000-4000-8000-000000000001','configurations','Configuraciones','json',
 jsonb_build_object('rows_schema',doc#>'{fields,configurations,schema}') from row_value_condition_document;
insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract)
select 'c0cf2400-0000-4000-8000-000000000050','c0cf2400-0000-4000-8000-000000000001','row_value_condition_fixture','Row value conditions','row_value_condition_fixture',
 '{"allowed_when":{},"required_when":{},"prerequisites":{},"allowed_options":{},"roles":{"configurations":"measurement"}}'::jsonb||(doc->'contract')
 from row_value_condition_document;
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
values('c0cf2400-0000-4000-8000-000000000050','c0cf2400-0000-4000-8000-000000000011','measurement',1);
set constraints all immediate;
create function pg_temp.row_value_projection(issues jsonb) returns jsonb language sql immutable as $$
 select coalesce(jsonb_agg(jsonb_build_object('code',i->>'code','field',i->>'field','row_id',i->>'row_id',
 'column',i->>'column','blocking',coalesce((i->>'blocking')::boolean,true)) order by n),'[]')
 from jsonb_array_elements(issues) with ordinality x(i,n) where i->>'code' like 'row_%'
$$;
select is(pg_temp.row_value_projection(public.spec_row_conditions_issues_internal_v1(c->'contract',doc->'fields',c->'values')),
 c->'expected','shared evaluator: '||(c->>'id'))
 from row_value_condition_document cross join lateral jsonb_array_elements(doc->'cases') c;
select lives_ok(format('select public.spec_row_conditions_metadata_internal_v1(%L::jsonb,%L::jsonb)',c->'contract',doc->'fields'),
 'valid metadata: '||(c->>'id'))
 from row_value_condition_document cross join lateral jsonb_array_elements(doc->'valid_metadata') c;
select throws_ok(format('select public.spec_row_conditions_metadata_internal_v1(%L::jsonb,%L::jsonb)',c->'contract',doc->'fields'),
 '23514',null,'invalid typed metadata: '||(c->>'id'))
 from row_value_condition_document cross join lateral jsonb_array_elements(doc->'invalid_metadata') c;

create function pg_temp.row_value_contract(p_contract jsonb) returns void language sql as $$
 update public.spec_templates set form_contract=
  '{"allowed_when":{},"required_when":{},"prerequisites":{},"allowed_options":{},"roles":{"configurations":"measurement"}}'::jsonb||p_contract
 where id='c0cf2400-0000-4000-8000-000000000050'
$$;
create function pg_temp.row_value_central(p_contract jsonb,p_values jsonb) returns jsonb language plpgsql as $$
begin
 perform pg_temp.row_value_contract(p_contract);
 return public.spec_validate_draft_internal_v1('c0cf2400-0000-4000-8000-000000000050',p_values);
end $$;
select is(pg_temp.row_value_projection(pg_temp.row_value_central(c->'contract',c->'values')),
 c->'expected','central validator: '||(c->>'id'))
 from row_value_condition_document cross join lateral jsonb_array_elements(doc->'cases') c;
select throws_ok(format('select pg_temp.row_value_contract(%L::jsonb)',c->'contract'),'23514',null,
 'publication rejects invalid metadata: '||(c->>'id'))
 from row_value_condition_document cross join lateral jsonb_array_elements(doc->'invalid_metadata') c;
select pg_temp.row_value_contract(doc->'contract') from row_value_condition_document;

select ok(not has_function_privilege('authenticated','public.spec_row_conditions_issues_internal_v1(jsonb,jsonb,jsonb)','execute'),
 'value evaluator stays private from authenticated');
select ok(not has_function_privilege('anon','public.spec_row_conditions_metadata_internal_v1(jsonb,jsonb)','execute'),
 'metadata helper stays private from anon');
select is(public.spec_row_conditions_issues_internal_v1('{}','{}','{}'),'[]'::jsonb,
 'absent extension retains existing behavior');
select throws_ok($$update public.spec_definitions
 set validation_rules=jsonb_set(validation_rules,'{rows_schema,columns,1,type}','"token"')
 where id='c0cf2400-0000-4000-8000-000000000011'$$,'23514',null,
 'definition cannot change the type of an expected boolean');
select throws_ok($$update public.spec_definitions
 set validation_rules=jsonb_set(validation_rules,'{rows_schema,columns,0,allowed_values}','["Con kit opcional"]')
 where id='c0cf2400-0000-4000-8000-000000000011'$$,'23514',null,
 'definition cannot remove a value used by an antecedent');
select throws_ok($$delete from public.spec_template_fields
 where template_id='c0cf2400-0000-4000-8000-000000000050'$$,'23514',null,
 'removing the endpoint cannot strand a value condition');

insert into public.products(id,tenant_id,name,sku,price,cost,is_active,spec_template_id)
 values('c0cf2400-0000-4000-8000-000000000020','c0cf2400-0000-4000-8000-000000000001',
 'Row value fixture','ROW-VALUE',100,50,true,'c0cf2400-0000-4000-8000-000000000050');
create function pg_temp.row_value_save(p_case text,p_operation text) returns jsonb language sql as $$
 select public.save_product_with_specs_v1(
 '{"id":"c0cf2400-0000-4000-8000-000000000020","name":"Row value fixture","sku":"ROW-VALUE"}',false,
 'c0cf2400-0000-4000-8000-000000000050',
 (select contract_version from public.spec_templates where id='c0cf2400-0000-4000-8000-000000000050'),
 (select jsonb_build_object('c0cf2400-0000-4000-8000-000000000011',jsonb_build_object('rows',c#>'{values,configurations}'))
  from row_value_condition_document cross join lateral jsonb_array_elements(doc->'cases') c where c->>'id'=p_case),
 (select spec_revision from public.products where id='c0cf2400-0000-4000-8000-000000000020'),null,p_operation,
 (select updated_at from public.products where id='c0cf2400-0000-4000-8000-000000000020'))
$$;
grant select on row_value_condition_document to authenticated;
grant execute on function pg_temp.row_value_save(text,text) to authenticated;
set constraints product_spec_fact_constraint,product_spec_value_constraint deferred;
set local role authenticated;
select lives_ok($$select pg_temp.row_value_save('optional_false','row-value-optional')$$,
 'optional kit does not force true or false');
reset role;
create temp table row_value_saved as select md5(to_jsonb(p)::text) product_digest,
 (select md5(jsonb_agg(to_jsonb(f) order by f.id)::text) from public.spec_facts f
  where f.subject_type='product' and f.subject_id=p.id) fact_digest
 from public.products p where id='c0cf2400-0000-4000-8000-000000000020';
set local role authenticated;
select throws_ok($$select pg_temp.row_value_save('included_false','row-value-retained-conflict')$$,'23514',null,
 'upstream change cannot save the retained contradictory boolean');
reset role;
select is((select md5(to_jsonb(p)::text) from public.products p where id='c0cf2400-0000-4000-8000-000000000020'),
 (select product_digest from row_value_saved),'failed aggregate preserves identity commercial values and revision');
select is((select md5(jsonb_agg(to_jsonb(f) order by f.id)::text) from public.spec_facts f
 where f.subject_type='product' and f.subject_id='c0cf2400-0000-4000-8000-000000000020'),
 (select fact_digest from row_value_saved),'failed aggregate preserves complete fact provenance');
select throws_ok($$update public.spec_templates set form_contract=form_contract-'row_conditions'
 where id='c0cf2400-0000-4000-8000-000000000050'$$,'23514',null,
 'populated metadata cannot remove value conditions');
select throws_ok($$update public.spec_templates
 set form_contract=jsonb_set(form_contract,'{row_conditions,fields,configurations,value_when,clamp_included,0,expected,value}','false')
 where id='c0cf2400-0000-4000-8000-000000000050'$$,'23514',null,
 'populated metadata cannot invert expected values');
set local role authenticated;
select lives_ok($$select pg_temp.row_value_save('included_missing','row-value-missing')$$,
 'missing expected observation remains a savable pending fact');
reset role;
select is((select value_json from public.spec_facts where subject_type='product'
 and subject_id='c0cf2400-0000-4000-8000-000000000020' and spec_definition_id='c0cf2400-0000-4000-8000-000000000011'),
 (select c#>'{values,configurations}' from row_value_condition_document cross join lateral jsonb_array_elements(doc->'cases') c
  where c->>'id'='included_missing'),'saved rows preserve IDs sources and absence; there is no autofill');
set local role authenticated;
select lives_ok($$select pg_temp.row_value_save('included_true','row-value-confirmed')$$,
 'confirming the required value saves successfully');
reset role;
set constraints product_spec_fact_constraint,product_spec_value_constraint immediate;
select throws_ok($$update public.spec_facts
 set value_json=jsonb_set(value_json,'{rows,0,values,clamp_included}','false')
 where subject_type='product' and subject_id='c0cf2400-0000-4000-8000-000000000020'
 and spec_definition_id='c0cf2400-0000-4000-8000-000000000011'$$,'23514',null,
 'direct fact constraint also rejects a value contradiction');
select is((select value_json#>'{rows,0,values,clamp_included}' from public.spec_facts
 where subject_type='product' and subject_id='c0cf2400-0000-4000-8000-000000000020'
 and spec_definition_id='c0cf2400-0000-4000-8000-000000000011'),'true'::jsonb,
 'rejected direct fact edit preserves the confirmed observation');

-- A reference records an independent observation. Adoption must still validate
-- this template, even if the reference and the draft agree on the contradiction.
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
select 'row-value-conflicting-reference','row_value_condition_fixture','Fixture','Conflict','Row value reference',
 jsonb_build_object('c0cf2400-0000-4000-8000-000000000011',jsonb_build_object('rows',c#>'{values,configurations}')),
 '["https://example.test/row-a"]','2026-09-07'
 from row_value_condition_document cross join lateral jsonb_array_elements(doc->'cases') c where c->>'id'='included_false';
select ok(exists(select 1 from jsonb_array_elements(public.spec_validate_draft_internal_v1(
 'c0cf2400-0000-4000-8000-000000000050',
 (select c->'values' from row_value_condition_document cross join lateral jsonb_array_elements(doc->'cases') c where c->>'id'='included_false'),
 'row-value-conflicting-reference','Fixture','Conflict','')) i where i->>'code'='row_value_conflict' and i->'blocking'='true'::jsonb),
 'matching reference never approves a template-level value contradiction');

select * from finish();
rollback;
