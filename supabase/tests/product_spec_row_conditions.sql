-- Synthetic row prerequisites: metadata, same-row scope, publication and writer.
begin;
set local client_min_messages=error;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
create temp table row_condition_document(doc jsonb);
\ir fixtures/product_spec_row_conditions.sql
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values('c0ce0000-0000-4000-8000-000000000001','Row condition fixture');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('c0ce0000-0000-4000-8000-000000000091','authenticated','authenticated','row-conditions@example.invalid','',now(),'{}',
 '{"account_type":"public_store_customer","customer_tenant_id":"c0ce0000-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='c0ce0000-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values('c0ce0000-0000-4000-8000-000000000091','c0ce0000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"c0ce0000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','c0ce0000-0000-4000-8000-000000000091',true);
insert into public.spec_definitions(id,tenant_id,key,label,data_type,validation_rules)
select 'c0ce0000-0000-4000-8000-000000000011','c0ce0000-0000-4000-8000-000000000001','configurations','Configuraciones','json',
 jsonb_build_object('rows_schema',doc#>'{fields,configurations,schema}') from row_condition_document;
insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract)
select 'c0ce0000-0000-4000-8000-000000000050','c0ce0000-0000-4000-8000-000000000001','row_condition_fixture','Row conditions','row_condition_fixture',
 '{"allowed_when":{},"required_when":{},"prerequisites":{},"allowed_options":{},"roles":{"configurations":"measurement"}}'::jsonb||(doc->'contract')
 from row_condition_document;
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
values('c0ce0000-0000-4000-8000-000000000050','c0ce0000-0000-4000-8000-000000000011','measurement',1);
set constraints all immediate;
create function pg_temp.row_projection(issues jsonb) returns jsonb language sql immutable as $$
 select coalesce(jsonb_agg(jsonb_build_object('code',i->>'code','field',i->>'field','row_id',i->>'row_id',
 'column',i->>'column','blocking',coalesce((i->>'blocking')::boolean,true)) order by n),'[]')
 from jsonb_array_elements(issues) with ordinality x(i,n)
 where i->>'code' in ('row_field_applicability','row_prerequisite','row_required_missing','row_option')
$$;
select is(pg_temp.row_projection(public.spec_row_conditions_issues_internal_v1(doc->'contract',doc->'fields',c->'values')),
 c->'expected','shared row evaluator: '||(c->>'id')) from row_condition_document cross join lateral jsonb_array_elements(doc->'cases') c;
select is(pg_temp.row_projection(public.spec_validate_draft_internal_v1('c0ce0000-0000-4000-8000-000000000050',c->'values')),
 c->'expected','central row evaluator: '||(c->>'id')) from row_condition_document cross join lateral jsonb_array_elements(doc->'cases') c;
select throws_ok(format('select public.spec_row_conditions_metadata_internal_v1(%L::jsonb,%L::jsonb)',c->'contract',doc->'fields'),
 '23514',null,'invalid row metadata: '||(c->>'id')) from row_condition_document cross join lateral jsonb_array_elements(doc->'invalid_metadata') c;
create function pg_temp.row_contract(p_contract jsonb) returns void language sql as $$
 update public.spec_templates set form_contract= '{"allowed_when":{},"required_when":{},"prerequisites":{},"allowed_options":{},"roles":{"configurations":"measurement"}}'::jsonb||p_contract
 where id='c0ce0000-0000-4000-8000-000000000050'
$$;
select throws_ok(format('select pg_temp.row_contract(%L::jsonb)',c->'contract'),'23514',null,'publication validates row metadata: '||(c->>'id'))
 from row_condition_document cross join lateral jsonb_array_elements(doc->'invalid_metadata') c;
select ok(not has_function_privilege('authenticated','public.spec_row_conditions_issues_internal_v1(jsonb,jsonb,jsonb)','execute'),'row evaluator stays private');
select ok(not has_function_privilege('anon','public.spec_row_conditions_metadata_internal_v1(jsonb,jsonb)','execute'),'row metadata stays private');
select is(public.spec_row_conditions_issues_internal_v1('{}','{}','{}'),'[]'::jsonb,'absent extension keeps old contract behavior');
-- A malformed endpoint owned by both extensions yields one shape issue.
select is((select count(*) from jsonb_array_elements(public.spec_coherence_issues_internal_v1(
 doc->'contract'||'{"row_coherence":{"version":1,"links":[{"id":"same_owner","field":"configurations","column":"adapter_model","target_field":"targets","label_columns":["member_role"]}]}}'::jsonb,
 doc->'fields'||jsonb_build_object('targets',doc#>'{fields,configurations}'),
 '{"configurations":{"schema_version":1,"rows":[{"id":"bad","values":{"width_mm":1},"sources":[]}]}}')) i
 where i->>'code'='row_shape'),1::bigint,'row coherence and row conditions report a malformed field once')
 from row_condition_document;
insert into public.products(id,tenant_id,name,sku,price,cost,is_active,spec_template_id) values
 ('c0ce0000-0000-4000-8000-000000000020','c0ce0000-0000-4000-8000-000000000001','Row condition fixture','ROW-CONDITION',100,50,true,'c0ce0000-0000-4000-8000-000000000050');
create function pg_temp.row_save(p_case text,p_operation text) returns jsonb language sql as $$
 select public.save_product_with_specs_v1(
 '{"id":"c0ce0000-0000-4000-8000-000000000020","name":"Row condition fixture","sku":"ROW-CONDITION"}',false,
 'c0ce0000-0000-4000-8000-000000000050',
 (select contract_version from public.spec_templates where id='c0ce0000-0000-4000-8000-000000000050'),
 (select jsonb_build_object('c0ce0000-0000-4000-8000-000000000011',jsonb_build_object('rows',c#>'{values,configurations}'))
  from row_condition_document cross join lateral jsonb_array_elements(doc->'cases') c where c->>'id'=p_case),
 (select spec_revision from public.products where id='c0ce0000-0000-4000-8000-000000000020'),null,p_operation,
 (select updated_at from public.products where id='c0ce0000-0000-4000-8000-000000000020'))
$$;
grant select on row_condition_document to authenticated;
grant execute on function pg_temp.row_save(text,text) to authenticated;
set constraints product_spec_fact_constraint,product_spec_value_constraint deferred;
set local role authenticated;
select lives_ok($$select pg_temp.row_save('true_with_model','row-conditions-valid')$$,'authenticated writer saves same-row model');
reset role;
create temp table row_condition_saved as select spec_revision,
 (select md5(jsonb_agg(to_jsonb(f) order by f.id)::text) from public.spec_facts f where f.subject_type='product' and f.subject_id=p.id) facts
 from public.products p where p.id='c0ce0000-0000-4000-8000-000000000020';
set local role authenticated;
select throws_ok($$select pg_temp.row_save('changed_upstream_retains_conflict','row-conditions-invalid')$$,'23514',null,'writer rejects retained incompatible downstream');
reset role;
select is((select md5(jsonb_agg(to_jsonb(f) order by f.id)::text) from public.spec_facts f where f.subject_type='product' and f.subject_id='c0ce0000-0000-4000-8000-000000000020'),
 (select facts from row_condition_saved),'rejected writer preserves all fact provenance');
select is((select spec_revision from public.products where id='c0ce0000-0000-4000-8000-000000000020'),
 (select spec_revision from row_condition_saved),'rejected writer preserves revision');
select throws_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{row_conditions,fields,configurations,allowed_options,member_role}','["cable"]')
 where id='c0ce0000-0000-4000-8000-000000000050'$$,'23514',null,'populated row options require reviewed migration');
set local role authenticated;
select lives_ok($$select pg_temp.row_save('true_requires_model','row-conditions-partial')$$,'missing evidence remains a savable partial observation');
reset role;
select ok(exists(select 1 from jsonb_array_elements(public.spec_validate_draft_internal_v1('c0ce0000-0000-4000-8000-000000000050',
 (select c->'values' from row_condition_document cross join lateral jsonb_array_elements(doc->'cases') c where c->>'id'='true_requires_model'))) i
 where i->>'code'='row_required_missing' and i->'blocking'='false'::jsonb),'partial observation is explicitly incomplete');
select * from finish();
rollback;
