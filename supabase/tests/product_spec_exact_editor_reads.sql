begin;
set local client_min_messages=error;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values
 ('edac0100-0000-4000-8000-000000000001','Exact A'),('edac0100-0000-4000-8000-000000000002','Exact B');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('edac0100-0000-4000-8000-000000000091','authenticated','authenticated','exact@example.invalid','',now(),'{}',
 '{"account_type":"public_store_customer","customer_tenant_id":"edac0100-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='edac0100-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values('edac0100-0000-4000-8000-000000000091','edac0100-0000-4000-8000-000000000001','admin');
select throws_ok($$select public.get_product_spec_editor_context_v2(null,null)$$,'42501',null,'editor rejects missing principal');
select throws_ok($$select public.get_product_spec_references_v2('fixture')$$,'42501',null,'references reject missing principal');
select set_config('request.jwt.claims','{"sub":"edac0100-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','edac0100-0000-4000-8000-000000000091',true);
insert into public.spec_definitions(id,key,label,data_type,validation_rules) values
 ('edac0100-0000-4000-8000-000000000051','exact_amount','Amount','number','{"min":0.100000000000000001,"max":9007199254740993.125,"positive":true}'),
 ('edac0100-0000-4000-8000-000000000052','exact_flag','Flag','boolean','{}'),
 ('edac0100-0000-4000-8000-000000000053','exact_text','Text','text','{}'),
 ('edac0100-0000-4000-8000-000000000054','exact_orphan','Orphan','number','{}');
insert into public.spec_templates(id,key,name,technical_family,form_contract) values
 ('edac0100-0000-4000-8000-000000000050','exact_read','Exact read','fixture_exact',
 '{"rules_version":2,"allowed_when":{},"required_when":{},"allowed_options":{},"prerequisites":{}}');
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order,default_value_json)
values('edac0100-0000-4000-8000-000000000050','edac0100-0000-4000-8000-000000000051','measurement',2,'0.100000000000000001'),
 ('edac0100-0000-4000-8000-000000000050','edac0100-0000-4000-8000-000000000052','primary',1,null),
 ('edac0100-0000-4000-8000-000000000050','edac0100-0000-4000-8000-000000000053','measurement',3,null);
set constraints all immediate;
insert into public.products(id,tenant_id,name,sku,price,cost,is_active,spec_template_id) values
 ('edac0100-0000-4000-8000-000000000020','edac0100-0000-4000-8000-000000000001','Exact read','EXACT-READ',100,50,true,'edac0100-0000-4000-8000-000000000050'),
 ('edac0100-0000-4000-8000-000000000021','edac0100-0000-4000-8000-000000000002','Foreign','EXACT-FOREIGN',100,50,true,null);
insert into public.product_categories(id,tenant_id,name,full_path) values
 ('edac0100-0000-4000-8000-000000000010','edac0100-0000-4000-8000-000000000001','Exact category','Exact category'),
 ('edac0100-0000-4000-8000-000000000011','edac0100-0000-4000-8000-000000000002','Foreign category','Foreign category');
insert into public.category_tech_mappings(tenant_id,category_id,technical_family,template_id,status) values
 ('edac0100-0000-4000-8000-000000000001','edac0100-0000-4000-8000-000000000010','fixture_exact','edac0100-0000-4000-8000-000000000050','active');
create function pg_temp.exact_save() returns jsonb language sql as $$
 select public.save_product_with_specs_v1(
 '{"id":"edac0100-0000-4000-8000-000000000020","name":"Exact read","sku":"EXACT-READ"}',false,
 'edac0100-0000-4000-8000-000000000050',
 (select contract_version from public.spec_templates where id='edac0100-0000-4000-8000-000000000050'),
 '{"edac0100-0000-4000-8000-000000000051":{"number":"9007199254740993.125"},"edac0100-0000-4000-8000-000000000052":{"boolean":false},"edac0100-0000-4000-8000-000000000053":{"text":"01"}}',
 (select spec_revision from public.products where id='edac0100-0000-4000-8000-000000000020'),null,'exact-read-save',
 (select updated_at from public.products where id='edac0100-0000-4000-8000-000000000020'))
$$;
grant execute on function pg_temp.exact_save() to authenticated;
create temp table exact_read_result(value jsonb);
grant select,insert on exact_read_result to authenticated;
set local role authenticated;
select lives_ok('select pg_temp.exact_save()','authenticated writer accepts exact scalar text');
insert into exact_read_result select public.get_product_spec_editor_context_v2('edac0100-0000-4000-8000-000000000020',null);
select is((select value#>'{values,exact_amount}' from exact_read_result),'"9007199254740993.125"'::jsonb,'v2 preserves fraction above 2^53 as JSON string');
select is((select value#>'{values,exact_flag}' from exact_read_result),'false'::jsonb,'false retains boolean type');
select is((select value#>'{values,exact_text}' from exact_read_result),'"01"'::jsonb,'text token retains its leading zero');
select is((select value#>'{template,fields,1,spec_definitions,validation_rules,min}' from exact_read_result),'"0.100000000000000001"'::jsonb,'minimum bound is exact before JSON decoding');
select is((select value#>'{template,fields,1,default_value_json}' from exact_read_result),'"0.100000000000000001"'::jsonb,'numeric default is exact before JSON decoding');
select is((select value#>'{template,form_contract,rules_version}' from exact_read_result),'2'::jsonb,'rule version remains integer metadata');
select is((select value#>'{template,fields,1,spec_definitions,validation_rules,positive}' from exact_read_result),'true'::jsonb,'bound rule boolean remains boolean');
select is((select value->'contract_version'=value#>'{template,contract_version}' from exact_read_result),true,'template and snapshot share one version');
select is(jsonb_typeof(public.get_product_spec_editor_context_v1('edac0100-0000-4000-8000-000000000020',null)#>'{values,exact_amount}'),'number','v1 keeps legacy wire type');
select is(public.get_product_spec_editor_context_v2(null,null)->'template','null'::jsonb,'unmapped draft remains explicitly without template');
select is(public.get_product_spec_editor_context_v2(null,'edac0100-0000-4000-8000-000000000010')#>>'{template,id}',
 'edac0100-0000-4000-8000-000000000050','category consumer reads the same atomic template');
select throws_ok($$select public.get_product_spec_editor_context_v2(null,'edac0100-0000-4000-8000-000000000011')$$,'42501',null,'foreign category cannot cross tenant boundary');
select throws_ok($$select public.get_product_spec_editor_context_v2('edac0100-0000-4000-8000-000000000021',null)$$,'42501',null,'foreign product cannot cross tenant boundary');
select throws_ok($$select public.spec_payload_display_exact_internal_v1('{}')$$,'42501',null,'authenticated caller cannot bypass RPC via private formatter');
reset role;
insert into public.spec_definitions(id,key,label,data_type,validation_rules) values
 ('edac0100-0000-4000-8000-000000000055','exact_rows','Exact rows','json',
 '{"rows_schema":{"version":1,"columns":[{"key":"length","label":"Length","type":"decimal"}]}}');
select is(public.spec_payload_display_exact_internal_v1('{"edac0100-0000-4000-8000-000000000055":{"rows":{"schema_version":1,"rows":[{"id":"row-a","values":{"length":"9007199254740993.125"},"sources":[]}]}}}')->'exact_rows',
 '{"schema_version":1,"rows":[{"id":"row-a","values":{"length":"9007199254740993.125"},"sources":[]}]}'::jsonb,'exact scalar formatter preserves structured rows envelope');
select is(public.spec_editor_rule_numbers_as_text_internal_v1('{"rules_version":2,"rows":[[{"value":0.100000000000000001,"allow":[1,"01",false]}]]}'),
 '{"rules_version":2,"rows":[[{"value":"0.100000000000000001","allow":["1","01",false]}]]}'::jsonb,'legacy operands convert only numbers and retain array order');
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on) values
 ('exact-read-reference','fixture_exact','Synthetic','Test','Synthetic exact fixture',
 '{"edac0100-0000-4000-8000-000000000051":{"number":9007199254740993.125}}','["https://example.test/exact"]','2026-09-07');
set local role authenticated;
select is(public.get_product_spec_references_v2('fixture_exact')#>'{0,facts,exact_amount}','"9007199254740993.125"'::jsonb,'reference scalar keeps exact digits');
select is(jsonb_typeof(public.get_product_spec_references_v1('fixture_exact')#>'{0,facts,exact_amount}'),'number','reference v1 is unchanged');
reset role;
-- Retire a field from this template, preserving its original fact identity.
delete from public.spec_template_fields where template_id='edac0100-0000-4000-8000-000000000050' and spec_definition_id='edac0100-0000-4000-8000-000000000051';
set local role authenticated;
select is(public.get_product_spec_editor_context_v2('edac0100-0000-4000-8000-000000000020',null)#>'{unassigned_facts,0,value}',
 '"9007199254740993.125"'::jsonb,'unassigned scalar preserves digits and remains visible');
reset role;
insert into public.spec_definitions(id,tenant_id,key,label,data_type) values
 ('edac0100-0000-4000-8000-000000000056','edac0100-0000-4000-8000-000000000002','exact_foreign_field','Foreign private metadata','text');
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order) values
 ('edac0100-0000-4000-8000-000000000050','edac0100-0000-4000-8000-000000000056','primary',9);
set local role authenticated;
select throws_ok($$select public.get_product_spec_editor_context_v2('edac0100-0000-4000-8000-000000000020',null)$$,'42501',null,'cross-tenant template field fails closed without exposing metadata');
reset role;
select * from finish();
rollback;
