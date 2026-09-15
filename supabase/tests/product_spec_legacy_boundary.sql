begin;
set local client_min_messages=error;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values
 ('99b90000-0000-4000-8000-000000000001','Spec A'),('99b90000-0000-4000-8000-000000000002','Spec B');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id::uuid,'authenticated','authenticated',email,'',now(),'{}',
 jsonb_build_object('account_type','public_store_customer','customer_tenant_id',tenant),now(),now()
from (values
 ('99b90000-0000-4000-8000-000000000091','spec-a@example.invalid','99b90000-0000-4000-8000-000000000001'),
 ('99b90000-0000-4000-8000-000000000092','spec-b@example.invalid','99b90000-0000-4000-8000-000000000002')) a(id,email,tenant);
delete from public.user_profiles where user_id in ('99b90000-0000-4000-8000-000000000091','99b90000-0000-4000-8000-000000000092');
insert into public.user_profiles(user_id,tenant_id,role) values
 ('99b90000-0000-4000-8000-000000000091','99b90000-0000-4000-8000-000000000001','admin'),
 ('99b90000-0000-4000-8000-000000000092','99b90000-0000-4000-8000-000000000002','admin');
select set_config('request.jwt.claims','{"sub":"99b90000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','99b90000-0000-4000-8000-000000000091',true);
insert into public.product_categories(id,tenant_id,name,full_path) values
 ('99b90000-0000-4000-8000-000000000010','99b90000-0000-4000-8000-000000000001','Spec chains','Spec chains'),
 ('99b90000-0000-4000-8000-000000000011','99b90000-0000-4000-8000-000000000002','Other chains','Other chains');
insert into public.category_tech_mappings(tenant_id,category_id,technical_family,template_id,status)
select '99b90000-0000-4000-8000-000000000001','99b90000-0000-4000-8000-000000000010','chain',id,'active'
from public.spec_templates where key='chain' and tenant_id is null;


insert into public.products(id,tenant_id,name,sku,category_id,price,cost,is_active)
values('99b90000-0000-4000-8000-000000000020','99b90000-0000-4000-8000-000000000001','Legacy boundary','SPEC-LEGACY-BOUNDARY','99b90000-0000-4000-8000-000000000010',100,50,true);
insert into public.spec_facts(tenant_id,subject_type,subject_id,spec_definition_id,value_number,source,confirmed)
select '99b90000-0000-4000-8000-000000000001','product','99b90000-0000-4000-8000-000000000020',id,114,'supplier_text',true
from public.spec_definitions where key='link_count' and tenant_id is null;
insert into public.spec_fact_readings(fact_id,tenant_id,source_text,source_digest,quote,model)
select id,tenant_id,'synthetic legacy 114',repeat('a',64),'114','fixture'
from public.spec_facts where subject_id='99b90000-0000-4000-8000-000000000020';
update public.spec_templates set form_contract=jsonb_set(form_contract,'{roles,link_count}','"legacy"') where key='chain' and tenant_id is null;
insert into public.spec_facts(tenant_id,subject_type,subject_id,spec_definition_id,source)
select '99b90000-0000-4000-8000-000000000001','product','99b90000-0000-4000-8000-000000000020',id,'import'
from public.spec_definitions where key='chain_profile_family' and tenant_id is null;
insert into public.spec_fact_values(fact_id,value_id,position)
select f.id,v.id,0 from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
cross join lateral(select id from public.spec_definition_values where spec_definition_id=d.id order by sort_order,id limit 1) v
where f.subject_id='99b90000-0000-4000-8000-000000000020' and d.key='chain_profile_family';
create temp table original_options as select to_jsonb(v) row from public.spec_fact_values v join public.spec_facts f on f.id=v.fact_id where f.subject_id='99b90000-0000-4000-8000-000000000020';
create temp table original_facts as select to_jsonb(f) row from public.spec_facts f where subject_id='99b90000-0000-4000-8000-000000000020';
create temp table original_readings as select to_jsonb(r) row from public.spec_fact_readings r where fact_id in(select (row->>'id')::uuid from original_facts);
select set_config('request.jwt.claim.sub','99b90000-0000-4000-8000-000000000091',true);
select is(public.spec_validate_draft_internal_v1((select id from public.spec_templates where key='chain' and tenant_id is null),'{"link_count":-99,"tube_width_min_mm":200,"tube_width_max_mm":10}'),'[]'::jsonb,'retired and foreign measurements cannot block the active draft');
select lives_ok($$select public.spec_write_payload_internal_v2('99b90000-0000-4000-8000-000000000020',(select id from public.spec_templates where key='chain' and tenant_id is null),'{}',null)$$,'omitting a retired answer preserves it');
select lives_ok($$select public.spec_write_payload_internal_v2('99b90000-0000-4000-8000-000000000020',(select id from public.spec_templates where key='chain' and tenant_id is null),public.spec_product_payload_internal_v1('99b90000-0000-4000-8000-000000000020'),null)$$,'unchanged normalized legacy round trip is allowed');
select throws_ok($$select public.spec_write_payload_internal_v2('99b90000-0000-4000-8000-000000000020',(select id from public.spec_templates where key='chain' and tenant_id is null),(select jsonb_build_object(id::text,'{"number":116}'::jsonb) from public.spec_definitions where key='link_count' and tenant_id is null),null)$$,'23514',null,'normalized save cannot overwrite a retired answer');
select lives_ok($$select public.save_product_spec_facts_v1('99b90000-0000-4000-8000-000000000020',array[(select id from public.spec_definitions where key='link_count' and tenant_id is null)],'{}')$$,'old client omission cannot erase retired data');
select lives_ok($$select public.save_product_spec_facts_v1('99b90000-0000-4000-8000-000000000020',array[(select id from public.spec_definitions where key='link_count' and tenant_id is null)],(select jsonb_build_object(id::text,'{"number":114}'::jsonb) from public.spec_definitions where key='link_count' and tenant_id is null))$$,'old client unchanged retired round trip preserves provenance');
select throws_ok($$select public.save_product_spec_facts_v1('99b90000-0000-4000-8000-000000000020',array[(select id from public.spec_definitions where key='link_count' and tenant_id is null)],(select jsonb_build_object(id::text,'{"number":116}'::jsonb) from public.spec_definitions where key='link_count' and tenant_id is null))$$,'23514',null,'old client cannot change retired data');
select results_eq($$select to_jsonb(f) from public.spec_facts f where subject_id='99b90000-0000-4000-8000-000000000020'$$,$$select row from original_facts$$,'legacy fact id, provenance, confirmation and timestamps are exact');
select results_eq($$select to_jsonb(r) from public.spec_fact_readings r where fact_id in(select (row->>'id')::uuid from original_facts)$$,$$select row from original_readings$$,'source readings remain exact');
select results_eq($$select to_jsonb(v) from public.spec_fact_values v join public.spec_facts f on f.id=v.fact_id where f.subject_id='99b90000-0000-4000-8000-000000000020'$$,$$select row from original_options$$,'retired option identities and positions are preserved');
set local role authenticated;
select throws_ok($$insert into public.spec_facts(tenant_id,subject_type,subject_id,spec_definition_id,value_boolean) select '99b90000-0000-4000-8000-000000000001','product','99b90000-0000-4000-8000-000000000020',id,true from public.spec_definitions where key='quick_link_included' and tenant_id is null$$,'42501',null,'direct product fact insertion cannot bypass commands');
with changed as(update public.spec_facts set value_number=116 where subject_id='99b90000-0000-4000-8000-000000000020' returning id) select is((select count(*)::integer from changed),0,'direct product fact update cannot bypass revision and legacy guards');
with changed as(delete from public.spec_facts where subject_id='99b90000-0000-4000-8000-000000000020' returning id) select is((select count(*)::integer from changed),0,'direct product fact delete cannot erase history');
with changed as(delete from public.product_spec_values where product_id='99b90000-0000-4000-8000-000000000020' returning id) select is((select count(*)::integer from changed),0,'the legacy projection cannot be deleted by a client');
select lives_ok($$select public.save_product_spec_facts_v1('99b90000-0000-4000-8000-000000000020',array[(select id from public.spec_definitions where key='quick_link_included' and tenant_id is null)],(select jsonb_build_object(id::text,'{"boolean":false}'::jsonb) from public.spec_definitions where key='quick_link_included' and tenant_id is null))$$,'authenticated command still writes an active false answer');
with changed as(delete from public.spec_fact_values where fact_id in(select id from public.spec_facts where subject_id='99b90000-0000-4000-8000-000000000020') returning fact_id) select is((select count(*)::integer from changed),0,'direct product option deletion cannot bypass commands');
with changed as(update public.spec_fact_values set position=2 where fact_id in(select id from public.spec_facts where subject_id='99b90000-0000-4000-8000-000000000020') returning fact_id) select is((select count(*)::integer from changed),0,'direct product option reordering cannot bypass commands');
select throws_ok($$insert into public.spec_fact_values(fact_id,value_id,position) select f.id,v.id,1 from public.spec_facts f join public.spec_definition_values v on v.spec_definition_id=f.spec_definition_id where f.subject_id='99b90000-0000-4000-8000-000000000020' and f.spec_definition_id=(select id from public.spec_definitions where key='chain_profile_family' and tenant_id is null) and not exists(select 1 from public.spec_fact_values used where used.fact_id=f.id and used.value_id=v.id) limit 1$$,'42501',null,'direct product option insertion cannot bypass commands');
select lives_ok($$insert into public.spec_facts(tenant_id,subject_type,subject_id,spec_definition_id,value_number) select '99b90000-0000-4000-8000-000000000001','bike','99b90000-0000-4000-8000-000000000030',id,114 from public.spec_definitions where key='link_count' and tenant_id is null$$,'existing tenant writes for bike subjects remain allowed');
with changed as(update public.spec_facts set value_number=116 where subject_type='bike' and subject_id='99b90000-0000-4000-8000-000000000030' returning id) select is((select count(*)::integer from changed),1,'bike scalar edits retain their existing policy');
with changed as(delete from public.spec_facts where subject_type='bike' and subject_id='99b90000-0000-4000-8000-000000000030' returning id) select is((select count(*)::integer from changed),1,'bike fact deletion retains its existing policy');
reset role;
select is((select value_boolean from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id where subject_id='99b90000-0000-4000-8000-000000000020' and d.key='quick_link_included'),false,'active false remains a real answer');
select ok(exists(select 1 from public.product_spec_values v join public.spec_definitions d on d.id=v.spec_definition_id where product_id='99b90000-0000-4000-8000-000000000020' and d.key='quick_link_included'),'the security-definer mirror still updates its projection');

-- The real purchasing reader obeys the same current-template/legacy boundary.
update public.products set name='Synthetic chain width 7.1 7.2 mm' where id='99b90000-0000-4000-8000-000000000020';
insert into public.products(id,tenant_id,name,sku,price,cost,is_active) values
('99b90000-0000-4000-8000-000000000021','99b90000-0000-4000-8000-000000000001','Unassigned width 7.1 mm','UNASSIGNED-WIDTH',100,50,true);
set local role authenticated;
select is(public.record_product_spec_reading_v1('99b90000-0000-4000-8000-000000000020','chain_outer_width_mm','7.1','7.1','fixture')->>'verdict','recorded','the purchasing reader still accepts an active in-template measurement');
select is(public.record_product_spec_reading_v1('99b90000-0000-4000-8000-000000000020','tube_width_min_mm','7.1','7.1','fixture')->>'verdict','rejected','the purchasing reader rejects a different family field');
select is(public.record_product_spec_reading_v1('99b90000-0000-4000-8000-000000000021','chain_outer_width_mm','7.1','7.1','fixture')->>'verdict','rejected','an unassigned product cannot acquire a technical criterion through the reader');
reset role;
create temp table original_auto_reading as select to_jsonb(f) fact,to_jsonb(r) reading from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id join public.spec_fact_readings r on r.fact_id=f.id where f.subject_id='99b90000-0000-4000-8000-000000000020' and d.key='chain_outer_width_mm';
update public.spec_templates set form_contract=jsonb_set(form_contract,'{roles,chain_outer_width_mm}','"legacy"') where key='chain' and tenant_id is null;
set local role authenticated;
select is(public.record_product_spec_reading_v1('99b90000-0000-4000-8000-000000000020','chain_outer_width_mm','7.2','7.2','fixture')->>'verdict','rejected','retiring a field prevents automatic replacement by a new reading');
reset role;
select results_eq($$select to_jsonb(f),to_jsonb(r) from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id join public.spec_fact_readings r on r.fact_id=f.id where f.subject_id='99b90000-0000-4000-8000-000000000020' and d.key='chain_outer_width_mm'$$,$$select fact,reading from original_auto_reading$$,'rejected auto-reading preserves the legacy value, quote and provenance');

-- The command checks the active dependency graph before reporting success.
update public.spec_templates set form_contract=jsonb_set(form_contract,'{roles,chain_outer_width_mm}','"measurement"') where key='chain' and tenant_id is null;
update public.spec_template_fields set visibility_rules='[{"field":"quick_link_included","operator":"eq","value":true}]'
where template_id=(select id from public.spec_templates where key='chain' and tenant_id is null)
and spec_definition_id=(select id from public.spec_definitions where key='chain_outer_width_mm' and tenant_id is null);
set local role authenticated;
select is(public.record_product_spec_reading_v1('99b90000-0000-4000-8000-000000000020','chain_outer_width_mm','7.2','7.2','fixture')->>'verdict','rejected','automatic reading cannot report success for a contradictory dependency graph');
reset role;
select results_eq($$select to_jsonb(f),to_jsonb(r) from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id join public.spec_fact_readings r on r.fact_id=f.id where f.subject_id='99b90000-0000-4000-8000-000000000020' and d.key='chain_outer_width_mm'$$,$$select fact,reading from original_auto_reading$$,'a contradictory dependency rejection preserves the prior fact and reading atomically');
update public.spec_template_fields set visibility_rules='[]' where template_id=(select id from public.spec_templates where key='chain' and tenant_id is null) and spec_definition_id=(select id from public.spec_definitions where key='chain_outer_width_mm' and tenant_id is null);

-- Subject UUIDs are only unique within their kind. The DELETE trigger must
-- test that kind before touching the product projection.
create temp table original_projection as select to_jsonb(v) row from public.product_spec_values v where product_id='99b90000-0000-4000-8000-000000000020';
set local role authenticated;
insert into public.spec_facts(tenant_id,subject_type,subject_id,spec_definition_id,value_number)
select '99b90000-0000-4000-8000-000000000001','bike','99b90000-0000-4000-8000-000000000020',id,999 from public.spec_definitions where key='link_count' and tenant_id is null;
delete from public.spec_facts where subject_type='bike' and subject_id='99b90000-0000-4000-8000-000000000020';
reset role;
select results_eq($$select to_jsonb(v) from public.product_spec_values v where product_id='99b90000-0000-4000-8000-000000000020'$$,$$select row from original_projection$$,'deleting a bike observation cannot remove the product projection sharing its UUID');
select ok(not has_function_privilege('anon','record_product_spec_reading_v1(uuid,text,jsonb,text,text)','execute'),'anonymous cannot invoke the purchasing write command');

select * from finish();
rollback;
