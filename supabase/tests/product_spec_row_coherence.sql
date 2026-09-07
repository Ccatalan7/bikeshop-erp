-- Synthetic integrity cases. These assert representation, never bicycle fitment.
begin;
set local client_min_messages=error;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
create temp table coherence_document(doc jsonb);
\ir fixtures/product_spec_coherence.sql
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values('c0ae0000-0000-4000-8000-000000000001','Coherence fixture');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('c0ae0000-0000-4000-8000-000000000091','authenticated','authenticated','coherence@example.invalid','',now(),'{}',
 '{"account_type":"public_store_customer","customer_tenant_id":"c0ae0000-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='c0ae0000-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values('c0ae0000-0000-4000-8000-000000000091','c0ae0000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"c0ae0000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','c0ae0000-0000-4000-8000-000000000091',true);
insert into public.spec_definitions(id,tenant_id,key,label,data_type,validation_rules)
select ('c0ae0000-0000-4000-8000-'||lpad(position::text,12,'0'))::uuid,'c0ae0000-0000-4000-8000-000000000001',key,key,value,
 case when doc->'schemas' ? key then jsonb_build_object('rows_schema',doc->'schemas'->key) else '{}' end
from coherence_document cross join lateral jsonb_each_text(doc->'types') with ordinality x(key,value,position);
insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract)
select 'c0ae0000-0000-4000-8000-000000000050','c0ae0000-0000-4000-8000-000000000001','coherence_fixture','Coherence fixture','fixture_coherence',
 '{"allowed_when":{},"required_when":{},"prerequisites":{},"allowed_options":{}}'::jsonb||(doc->'contract') from coherence_document;
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select 'c0ae0000-0000-4000-8000-000000000050',id,'measurement',1 from public.spec_definitions where tenant_id='c0ae0000-0000-4000-8000-000000000001';
set constraints all immediate;
create function pg_temp.coherence_projection(issues jsonb) returns jsonb language sql immutable as $$
 select coalesce(jsonb_agg(jsonb_build_object('code',i->>'code','field',i->>'field','row_id',i->>'row_id',
 'blocking',coalesce((i->>'blocking')::boolean,true)) order by position),'[]')
 from jsonb_array_elements(issues) with ordinality x(i,position)
 where i->>'code' in ('row_shape','row_reference_pending','row_reference_unresolved','range_order')
$$;
select is(pg_temp.coherence_projection(public.spec_coherence_issues_internal_v1(doc->'contract',
 public.spec_coherence_fields_internal_v1('c0ae0000-0000-4000-8000-000000000050'),c->'values')),c->'expected','shared evaluator: '||(c->>'id'))
from coherence_document cross join lateral jsonb_array_elements(doc->'cases') c;
select is(pg_temp.coherence_projection(public.spec_validate_draft_internal_v1('c0ae0000-0000-4000-8000-000000000050',c->'values')),
 c->'expected','shared central validator: '||(c->>'id'))
from coherence_document cross join lateral jsonb_array_elements(doc->'cases') c;
-- A label change and reorder preserve exact IDs, both in typed values and labels.
select is(public.spec_coherence_labels_internal_v1('allocations',doc->'contract',doc#>'{cases,0,values}')#>>'{port_row_id,p1}',
 'USB-C 1','derived label resolves a stable target ID') from coherence_document;
select ok(public.spec_rows_display_internal_v1(doc#>'{schemas,allocations}',
 public.spec_coherence_display_rows_internal_v1(doc#>'{cases,0,values,allocations}',
 public.spec_coherence_labels_internal_v1('allocations',doc->'contract',doc#>'{cases,0,values}'))) not like '%p1%','display removes internal row ID') from coherence_document;
select is(public.spec_coherence_labels_internal_v1('allocations',doc->'contract','{}'),'{"port_row_id":{}}'::jsonb,'pending target cannot fabricate display choices') from coherence_document;
create function pg_temp.coherence_contract(p_extra jsonb) returns void language sql as $$
 update public.spec_templates set form_contract=(select '{"allowed_when":{},"required_when":{},"prerequisites":{},"allowed_options":{}}'::jsonb||(doc->'contract')||p_extra from coherence_document)
 where id='c0ae0000-0000-4000-8000-000000000050'
$$;
select throws_ok($$select pg_temp.coherence_contract('{"rules_version":1}')$$,'23514',null,'v1 cannot opt into coherence');
select throws_ok($$select pg_temp.coherence_contract('{"row_coherence":null}')$$,'23514',null,'null link metadata rejected');
select throws_ok($$select pg_temp.coherence_contract('{"prerequisites":{"ports":["allocations"]}}')$$,'23514',null,'link participates in the existing dependency DAG');
select throws_ok($$update public.spec_definitions set unit='in' where tenant_id='c0ae0000-0000-4000-8000-000000000001' and key='upper'$$,'23514',null,'definition unit change cannot invalidate an active range');
select throws_ok($$select pg_temp.coherence_contract('{"roles":{"ports":"legacy"}}')$$,'23514',null,'retiring a link endpoint rejects metadata atomically');
select throws_ok($$select pg_temp.coherence_contract('{"scalar_ordered_pairs":[["upper","upper"]]}')$$,'23514',null,'self scalar pair rejected');
select throws_ok($$select pg_temp.coherence_contract('{"scalar_ordered_pairs":[["lower","upper"],["lower","upper"]]}')$$,'23514',null,'duplicate scalar pair rejected');
select ok(not has_function_privilege('authenticated','public.spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)','execute'),'coherence helper is private');
select ok(not has_function_privilege('anon','public.spec_coherence_fields_internal_v1(uuid)','execute'),'template field helper is private');
insert into public.products(id,tenant_id,name,sku,price,cost,is_active,is_published,show_on_website,spec_template_id) values
 ('c0ae0000-0000-4000-8000-000000000020','c0ae0000-0000-4000-8000-000000000001','Coherence 30 mm','COHERENCE',100,50,true,true,true,'c0ae0000-0000-4000-8000-000000000050');
create function pg_temp.coherence_save(p_values jsonb,p_operation text,p_revision bigint default null) returns jsonb language sql as $$
 select public.save_product_with_specs_v1(
 '{"id":"c0ae0000-0000-4000-8000-000000000020","name":"Coherence 30 mm","sku":"COHERENCE"}',false,
 'c0ae0000-0000-4000-8000-000000000050',
 (select contract_version from public.spec_templates where id='c0ae0000-0000-4000-8000-000000000050'),
 (select jsonb_object_agg(d.id,jsonb_build_object(case when d.data_type='json' then 'rows' else 'number' end,e.value))
   from jsonb_each(p_values) e join public.spec_definitions d on d.key=e.key and d.tenant_id='c0ae0000-0000-4000-8000-000000000001'),
 coalesce(p_revision,(select spec_revision from public.products where id='c0ae0000-0000-4000-8000-000000000020')),null,p_operation,
 (select updated_at from public.products where id='c0ae0000-0000-4000-8000-000000000020'))
$$;
grant execute on function pg_temp.coherence_save(jsonb,text,bigint) to authenticated;
grant select on coherence_document to authenticated;
set constraints product_spec_fact_constraint,product_spec_value_constraint deferred;
set local role authenticated;
select lives_ok($$select pg_temp.coherence_save((select doc#>'{cases,0,values}' from coherence_document)||'{"lower":"10","upper":"20"}'::jsonb,'coherence-initial')$$,'authenticated aggregate stores linked rows');
reset role;
create temp table coherence_saved as select public.spec_active_product_values_internal_v1('c0ae0000-0000-4000-8000-000000000020','c0ae0000-0000-4000-8000-000000000050') vals,
 (select spec_revision from public.products where id='c0ae0000-0000-4000-8000-000000000020') revision;
grant select on coherence_saved to authenticated;
set local role authenticated;
select throws_ok($$select pg_temp.coherence_save((select jsonb_set(vals,'{ports,rows,0,id}','"replacement"') from coherence_saved),'coherence-orphan')$$,'23514',null,'replacing a target without relinking rejects the whole save');
select is(public.get_product_spec_typed_configurations_v1(array['c0ae0000-0000-4000-8000-000000000020'::uuid])#>>'{c0ae0000-0000-4000-8000-000000000020,fields,allocations,value,rows,0,values,port_row_id}',
 'p1','typed consumer keeps the stable row ID');
select is(public.get_product_spec_typed_configurations_v1(array['c0ae0000-0000-4000-8000-000000000020'::uuid])#>>'{c0ae0000-0000-4000-8000-000000000020,fields,allocations,row_labels,port_row_id,p1}',
 'USB-C 1','typed consumer receives derived labels separately');
select ok((select display_value like '%USB-C 1%' and display_value not like '%p1%' from public.get_public_product_technical_specs('c0ae0000-0000-4000-8000-000000000001','c0ae0000-0000-4000-8000-000000000020') where spec_key='allocations'),
 'public display resolves the link label');
select lives_ok($$select pg_temp.coherence_save((select jsonb_set(vals,'{ports,rows,0,values,name}','"Frontal"') from coherence_saved),'coherence-rename')$$,'renaming the target preserves its identity');
select throws_ok($$select pg_temp.coherence_save((select vals from coherence_saved),'coherence-stale',(select revision from coherence_saved))$$,'40001',null,'stale revision cannot resurrect a replaced target');
reset role;
select is((select value_json#>>'{rows,0,values,port_row_id}' from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
 where f.subject_id='c0ae0000-0000-4000-8000-000000000020' and d.key='allocations'),'p1','all rejected attempts preserve the source observation');
select throws_ok($$select pg_temp.coherence_contract('{"row_coherence":{"version":1,"links":[]}}')$$,'23514',null,'published coherence cannot be removed over populated endpoints');
-- A reading conflict is a rejected observation, not a transport failure, and
-- rolls back its tentative write and provenance before returning.
update public.spec_facts f set source='name_reading' from public.spec_definitions d
 where d.id=f.spec_definition_id and d.key='lower' and f.subject_id='c0ae0000-0000-4000-8000-000000000020';
create temp table coherence_before_read as select to_jsonb(f) fact from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
 where d.key='lower' and f.subject_id='c0ae0000-0000-4000-8000-000000000020';
set local role authenticated;
select is(public.record_product_spec_reading_v1('c0ae0000-0000-4000-8000-000000000020','lower','30','30','synthetic-test')->>'verdict','rejected',
 'reading that reverses the range returns rejected');
reset role;
select is((select to_jsonb(f) from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
 where d.key='lower' and f.subject_id='c0ae0000-0000-4000-8000-000000000020'),(select fact from coherence_before_read),'rejected reading preserves complete prior fact');
set constraints all immediate;

-- Representative aggregate, including deferred checks: 32 fields and 20 linked rows.
insert into public.spec_definitions(id,tenant_id,key,label,data_type)
select ('c0ae0000-0000-4000-8000-'||lpad((1000+i)::text,12,'0'))::uuid,'c0ae0000-0000-4000-8000-000000000001','coherence_measure_'||i,'Measurement '||i,'number' from generate_series(1,28) i;
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select 'c0ae0000-0000-4000-8000-000000000050',id,'measurement',100 from public.spec_definitions
 where tenant_id='c0ae0000-0000-4000-8000-000000000001' and key like 'coherence_measure_%';
create temp table coherence_benchmark(value jsonb);
create function pg_temp.coherence_benchmark() returns void language plpgsql as $$
declare values_json jsonb; started timestamptz; saved jsonb;
begin
 select jsonb_object_agg('coherence_measure_'||i,to_jsonb(i::text)) into values_json from generate_series(1,28) i;
 values_json:=values_json||'{"lower":"10","upper":"20"}'::jsonb||jsonb_build_object(
  'ports',jsonb_build_object('schema_version',1,'rows',(select jsonb_agg(jsonb_build_object('id','p'||i,'values',jsonb_build_object('name','Port '||i),'sources','[]'::jsonb)) from generate_series(1,10) i)),
  'allocations',jsonb_build_object('schema_version',1,'rows',(select jsonb_agg(jsonb_build_object('id','c'||i,'values',jsonb_build_object('port_row_id','p'||i,'power_w','20'),'sources','[]'::jsonb)) from generate_series(1,10) i)));
 set constraints product_spec_fact_constraint,product_spec_value_constraint deferred;
 started:=clock_timestamp();
 saved:=pg_temp.coherence_save(values_json,'coherence-performance');
 set constraints product_spec_fact_constraint,product_spec_value_constraint immediate;
 insert into coherence_benchmark values(jsonb_build_object('fields',32,'linked_rows',20,'elapsed_ms',round((extract(epoch from clock_timestamp()-started)*1000)::numeric,3)));
end $$;
select lives_ok('select pg_temp.coherence_benchmark()','32-field aggregate including deferred validation succeeds');
select diag('Coherence aggregate benchmark: '||value::text) from coherence_benchmark;

select * from finish();
rollback;
