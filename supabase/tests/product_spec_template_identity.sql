-- Definition identity, scoped through templates before key projection.
-- Synthetic rollback regression; no OEM or production product data.
begin;
set local client_min_messages=error;
-- Synthetic-test prerequisite only. The minimal historical local fixture lacks
-- the two reading columns added by 20260831270000. Their production constraints
-- are covered by that migration's own tests, not recreated by this binding test.
alter table public.spec_fact_readings add column if not exists vocabulary_digest text;
alter table public.spec_fact_readings add column if not exists definition_id uuid;

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
values('99b90000-0000-4000-8000-000000000020','99b90000-0000-4000-8000-000000000001','Legacy boundary 7.1 7.2','SPEC-LEGACY-BOUNDARY','99b90000-0000-4000-8000-000000000010',100,50,true);

-- Definition keys are unique per tenant, not across tenant/global namespaces.
insert into public.spec_definitions(id,tenant_id,key,label,data_type,is_filterable)
values('00000000-0000-4000-8000-000000000098','99b90000-0000-4000-8000-000000000001','chain_outer_width_mm','Unassigned width shadow','number',true);
insert into public.spec_facts(tenant_id,subject_type,subject_id,spec_definition_id,value_number,source)
values('99b90000-0000-4000-8000-000000000001','product','99b90000-0000-4000-8000-000000000020','00000000-0000-4000-8000-000000000098',7.2,'catalog');
select ok(not(public.spec_active_product_values_internal_v1('99b90000-0000-4000-8000-000000000020',(select id from public.spec_templates where key='chain' and tenant_id is null)) ? 'chain_outer_width_mm'),'unassigned definition ID cannot become an active fact via its key');
select ok(not(public.get_product_spec_contexts_v1(array['99b90000-0000-4000-8000-000000000020'::uuid])->'99b90000-0000-4000-8000-000000000020' ? 'chain_outer_width_mm'),'context excludes the unassigned shadow');
select ok(not(public.get_product_spec_snapshot_v1('99b90000-0000-4000-8000-000000000020')->'values' ? 'chain_outer_width_mm'),'editor values cannot prefill an active field from an unassigned shadow');
select is(public.assistant_inventory_technical_predicate_source_internal_v1('99b90000-0000-4000-8000-000000000001','99b90000-0000-4000-8000-000000000020','chain_outer_width_mm','eq','[7.2]','',''),'unresolved','unassigned fact cannot satisfy a typed predicate');
select is(public.assistant_inventory_technical_filter_source_internal_v1('99b90000-0000-4000-8000-000000000001','99b90000-0000-4000-8000-000000000020','chain_outer_width_mm','7.2','',''),'unresolved','unassigned projection cannot satisfy the legacy filter');
set local role authenticated;
select is(public.record_product_spec_reading_v1('99b90000-0000-4000-8000-000000000020','chain_outer_width_mm','7.1','7.1','synthetic-shadow-review')->>'verdict','recorded','reading resolves the assigned global definition ID');
reset role;
select is((select f.value_number::text from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id where f.subject_type='product' and f.subject_id='99b90000-0000-4000-8000-000000000020' and d.key='chain_outer_width_mm' and d.tenant_id is null),'7.1','reading writes the exact assigned definition');
select is((select f.value_number::text from public.spec_facts f where f.subject_type='product' and f.subject_id='99b90000-0000-4000-8000-000000000020' and f.spec_definition_id='00000000-0000-4000-8000-000000000098'),'7.2','unassigned history remains unchanged');
select is((select row->>'value' from jsonb_array_elements(public.spec_unassigned_facts_internal_v1('99b90000-0000-4000-8000-000000000020',(select id from public.spec_templates where key='chain' and tenant_id is null))) row where row->>'definition_id'='00000000-0000-4000-8000-000000000098'),'7.2','unassigned display reports its own ID value, not the assigned same-key value');

select ok(not(public.get_product_spec_snapshot_v1('99b90000-0000-4000-8000-000000000020')->'catalog_keys' ? 'chain_outer_width_mm'),'unassigned catalog source cannot mark the assigned field automatic');
select ok(not public.spec_product_definition_is_active_internal_v1('99b90000-0000-4000-8000-000000000001','99b90000-0000-4000-8000-000000000020','00000000-0000-4000-8000-000000000098'),'typed active helper rejects the shadow ID');
select ok(public.spec_product_definition_is_active_internal_v1('99b90000-0000-4000-8000-000000000001','99b90000-0000-4000-8000-000000000020',(select id from public.spec_definitions where key='chain_outer_width_mm' and tenant_id is null)),'typed active helper admits the assigned ID');
select is(public.spec_product_field_definition_internal_v1('99b90000-0000-4000-8000-000000000002','99b90000-0000-4000-8000-000000000020','chain_outer_width_mm'),null::uuid,'field identity resolver cannot cross tenant');
update public.products set is_published=true,show_on_website=true where id='99b90000-0000-4000-8000-000000000020';
update public.spec_definitions set is_customer_visible=true where key='chain_outer_width_mm';
select is((select display_value from public.get_public_product_technical_specs('99b90000-0000-4000-8000-000000000001','99b90000-0000-4000-8000-000000000020') where spec_key='chain_outer_width_mm'),'7.1','storefront projects the exact assigned definition value');
-- A duplicate active key in the template is malformed metadata. Returning an
-- empty editable draft here would turn ordinary omission into data loss.
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select id,'00000000-0000-4000-8000-000000000098','compatibility',999 from public.spec_templates where key='chain' and tenant_id is null;
select is(public.spec_product_field_definition_internal_v1('99b90000-0000-4000-8000-000000000001','99b90000-0000-4000-8000-000000000020','chain_outer_width_mm'),null::uuid,'ambiguous template keys do not prefer a tenant or global definition');
select throws_ok($$select public.get_product_spec_snapshot_v1('99b90000-0000-4000-8000-000000000020')$$,'23514',null,'ambiguous metadata cannot produce an empty editable snapshot');
select is((select count(*)::integer from public.spec_facts where subject_type='product' and subject_id='99b90000-0000-4000-8000-000000000020'),2,'ambiguity errors preserve both fact IDs');
select ok(not has_function_privilege('authenticated','spec_product_field_definition_internal_v1(uuid,uuid,text)','execute') and not has_function_privilege('anon','spec_template_product_payload_internal_v1(uuid,uuid,boolean)','execute'),'identity helpers remain private');
select * from finish();
rollback;
