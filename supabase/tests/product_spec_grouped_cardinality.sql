-- Root-owned local transaction. No published function/catalog/product change.
begin;
set local client_min_messages=error;
set local search_path=public,extensions,pg_temp;
\ir ../../scripts/inventory/sql/product_spec_grouped_cardinality_candidate.sql
\ir fixtures/product_spec_grouped_cardinality.sql
select no_plan();
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values('c0df3500-0000-4000-8000-000000000001','Grouped count fixture');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('c0df3500-0000-4000-8000-000000000091','authenticated','authenticated','grouped-count@example.invalid','',now(),'{}',
 '{"account_type":"public_store_customer","customer_tenant_id":"c0df3500-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='c0df3500-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values('c0df3500-0000-4000-8000-000000000091','c0df3500-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"c0df3500-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','c0df3500-0000-4000-8000-000000000091',true);
create temp table grouped_field_ids(key text primary key,id uuid);
insert into grouped_field_ids values
 ('members','c0df3500-0000-4000-8000-000000000011'),('assemblies','c0df3500-0000-4000-8000-000000000012'),
 ('total','c0df3500-0000-4000-8000-000000000013'),('enabled','c0df3500-0000-4000-8000-000000000014');
insert into public.spec_definitions(id,tenant_id,key,label,data_type,validation_rules)
select f.id,'c0df3500-0000-4000-8000-000000000001',e.key,e.key,e.value->>'data_type',e.value->'validation_rules'
 from grouped_cardinality_document cross join lateral jsonb_each(doc->'fields') e join grouped_field_ids f using(key);
insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract)
select 'c0df3500-0000-4000-8000-000000000050','c0df3500-0000-4000-8000-000000000001',
 'grouped_count_fixture','Grouped count','grouped_count_fixture',doc->'contract' from grouped_cardinality_document;
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select 'c0df3500-0000-4000-8000-000000000050',id,'contents',1 from grouped_field_ids;
set constraints all immediate;
create function pg_temp.grouped_projection(issues jsonb) returns jsonb language sql immutable as $$
 select coalesce(jsonb_agg(jsonb_build_object('code',i->>'code','field',i->>'field','row_id',i->>'row_id',
 'column',i->>'column','collection_field',i->>'collection_field','blocking',coalesce((i->>'blocking')::boolean,true)) order by n),'[]')
 from jsonb_array_elements(issues) with ordinality x(i,n) where i->>'code' like 'row_cardinality_%'
 or i->>'code' like 'row_reference_%' or i->>'code'='row_shape'
$$;
create function pg_temp.grouped_values(p_case text) returns jsonb language sql stable as $$
 select c->'values' from grouped_cardinality_document cross join lateral jsonb_array_elements(doc->'cases') c where c->>'id'=p_case
$$;
select is(pg_temp.grouped_projection(public.spec_coherence_issues_internal_v1(doc->'contract',doc->'fields',c->'values')),
 c->'expected','shared grouped evaluator: '||(c->>'id'))
 from grouped_cardinality_document cross join lateral jsonb_array_elements(doc->'cases') c;
select throws_ok(format('select public.spec_coherence_metadata_internal_v1(%L::jsonb,%L::jsonb)',c->'contract',c->'fields'),
 '23514',null,'invalid metadata: '||(c->>'id'))
 from grouped_cardinality_document cross join lateral jsonb_array_elements(doc->'invalid_metadata') c;
select is(pg_temp.grouped_projection(public.spec_validate_draft_internal_v1('c0df3500-0000-4000-8000-000000000050',c->'values')),
 c->'expected','central grouped validator: '||(c->>'id'))
 from grouped_cardinality_document cross join lateral jsonb_array_elements(doc->'cases') c;
select throws_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{prerequisites,assemblies}','["members"]')
 where id='c0df3500-0000-4000-8000-000000000050'$$,'23514',null,'group link closes prerequisite cycle');
select throws_ok($$update public.spec_definitions set validation_rules=jsonb_set(validation_rules,'{rows_schema,columns,1,type}','"decimal"')
 where id='c0df3500-0000-4000-8000-000000000012'$$,'23514',null,'parent total cannot silently lose integer semantics');
select throws_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{roles,assemblies}','"legacy"')
 where id='c0df3500-0000-4000-8000-000000000050'$$,'23514',null,'group parent cannot retire beneath the rule');
select throws_ok($$delete from public.spec_template_fields where template_id='c0df3500-0000-4000-8000-000000000050'
 and spec_definition_id='c0df3500-0000-4000-8000-000000000012'$$,'23514',null,'parent definition cannot strand a group rule');
update public.spec_templates set form_contract=jsonb_set(form_contract,'{allowed_when,members}','{"kind":"never"}')
 where id='c0df3500-0000-4000-8000-000000000050';
select is(pg_temp.grouped_projection(public.spec_validate_draft_internal_v1('c0df3500-0000-4000-8000-000000000050',
 pg_temp.grouped_values('no_children_does_not_invent_members'))),'[]'::jsonb,'inapplicable collection does not request missing members');
select is((select count(*) from jsonb_array_elements(public.spec_validate_draft_internal_v1('c0df3500-0000-4000-8000-000000000050',
 pg_temp.grouped_values('one_short_one_long_cannot_cancel'))) i where coalesce((i->>'blocking')::boolean,true)),1::bigint,
 'populated inapplicable collection retains its single applicability owner');
update public.spec_templates set form_contract=jsonb_set(form_contract,'{allowed_when}','{}') where id='c0df3500-0000-4000-8000-000000000050';
update public.spec_templates set form_contract=jsonb_set(form_contract,'{allowed_when,assemblies}','{"kind":"never"}')
 where id='c0df3500-0000-4000-8000-000000000050';
select is(pg_temp.grouped_projection(public.spec_validate_draft_internal_v1('c0df3500-0000-4000-8000-000000000050','{}')),
 '[]'::jsonb,'inapplicable parent does not request a configuration');
update public.spec_templates set form_contract=jsonb_set(form_contract,'{allowed_when}','{}') where id='c0df3500-0000-4000-8000-000000000050';
insert into public.products(id,tenant_id,name,sku,price,cost,is_active,spec_template_id)
 values('c0df3500-0000-4000-8000-000000000020','c0df3500-0000-4000-8000-000000000001','Grouped count fixture','GROUPED_COUNT',100,50,true,'c0df3500-0000-4000-8000-000000000050');
create function pg_temp.grouped_save(p_case text,p_operation text,p_version_delta integer default 0) returns jsonb language sql as $$
 select public.save_product_with_specs_v1(
 '{"id":"c0df3500-0000-4000-8000-000000000020","name":"Grouped count fixture","sku":"GROUPED_COUNT"}',false,
 'c0df3500-0000-4000-8000-000000000050',
 (select contract_version+p_version_delta from public.spec_templates where id='c0df3500-0000-4000-8000-000000000050'),
 (select coalesce(jsonb_object_agg(f.id::text,case when e.key='total' then jsonb_build_object('number',e.value)
   else jsonb_build_object('rows',e.value) end),'{}') from jsonb_each(pg_temp.grouped_values(p_case)) e join grouped_field_ids f using(key)),
 (select spec_revision from public.products where id='c0df3500-0000-4000-8000-000000000020'),null,p_operation,
 (select updated_at from public.products where id='c0df3500-0000-4000-8000-000000000020'))
$$;
grant select on grouped_cardinality_document,grouped_field_ids to authenticated;
grant execute on function pg_temp.grouped_save(text,text,integer),pg_temp.grouped_values(text) to authenticated;
set constraints product_spec_fact_constraint,product_spec_value_constraint deferred;
set local role authenticated;
select lives_ok($$select pg_temp.grouped_save('both_configurations_complete_scalar_remains_two','group-equal')$$,'authenticated aggregate accepts complete groups');
reset role;
create temp table grouped_saved as select md5(to_jsonb(p)::text) product_digest,
 (select md5(jsonb_agg(to_jsonb(f) order by f.id)::text) from public.spec_facts f where f.subject_type='product' and f.subject_id=p.id) fact_digest
 from public.products p where id='c0df3500-0000-4000-8000-000000000020';
set local role authenticated;
select throws_ok($$select pg_temp.grouped_save('one_short_one_long_cannot_cancel','group-conflict')$$,'23514',null,'save cannot compensate one group with another');
select throws_ok($$select pg_temp.grouped_save('both_configurations_complete_scalar_remains_two','group-stale',-1)$$,'40001',null,'old contract cannot bypass grouped validation');
reset role;
select is((select md5(to_jsonb(p)::text) from public.products p where id='c0df3500-0000-4000-8000-000000000020'),
 (select product_digest from grouped_saved),'failed save preserves every product column');
select is((select md5(jsonb_agg(to_jsonb(f) order by f.id)::text) from public.spec_facts f
 where f.subject_type='product' and f.subject_id='c0df3500-0000-4000-8000-000000000020'),
 (select fact_digest from grouped_saved),'failed save preserves all facts and provenance');
set constraints product_spec_fact_constraint,product_spec_value_constraint immediate;
select throws_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{row_coherence,cardinalities}','[]')
 where id='c0df3500-0000-4000-8000-000000000050'$$,'23514',null,'populated groups cannot be silently disabled');
select lives_ok($$update public.spec_templates set form_contract=jsonb_set(jsonb_set(form_contract,
 '{row_coherence,links,0,id}','"renamed_link"'),'{row_coherence,cardinalities,0,group_by}','"renamed_link"')
 where id='c0df3500-0000-4000-8000-000000000050'$$,'link identifier and reference may rename together without changing ownership');
select lives_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{row_coherence,links,0,label_columns}','["name","quantity"]')
 where id='c0df3500-0000-4000-8000-000000000050'$$,'display labels cannot redirect populated groups');
select ok(not has_function_privilege('authenticated','public.spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)','execute')
 and not has_function_privilege('anon','public.spec_coherence_metadata_internal_v1(jsonb,jsonb)','execute'),'helpers retain private ACLs');
select * from finish();
rollback;
