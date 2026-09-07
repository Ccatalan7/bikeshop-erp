begin;
set local client_min_messages=error;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values
 ('f1112300-0000-4000-8000-000000000001','Research A'),('f1112300-0000-4000-8000-000000000002','Research B');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('f1112300-0000-4000-8000-000000000091','authenticated','authenticated','research@example.invalid','',now(),'{}',
 '{"account_type":"public_store_customer","customer_tenant_id":"f1112300-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='f1112300-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values('f1112300-0000-4000-8000-000000000091','f1112300-0000-4000-8000-000000000001','admin');
select throws_ok($$select public.get_product_spec_research_snapshot_v1(null)$$,'42501',null,'snapshot rejects missing principal');
select throws_ok($$select public.preview_product_spec_research_v1(null,null)$$,'42501',null,'preview rejects missing principal');
select set_config('request.jwt.claims','{"sub":"f1112300-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','f1112300-0000-4000-8000-000000000091',true);
insert into public.spec_definitions(id,key,label,data_type,validation_rules) values
 ('f1112300-0000-4000-8000-000000000051','research_amount','Amount','number','{"min":"0.1","max":"9007199254740993.125"}'),
 ('f1112300-0000-4000-8000-000000000052','research_flag','Flag','boolean','{}'),
 ('f1112300-0000-4000-8000-000000000053','research_option','Option','single_select','{}'),
 ('f1112300-0000-4000-8000-000000000054','research_rows','Rows','json',
 '{"rows_schema":{"version":1,"columns":[{"key":"length","label":"Length","type":"decimal"}]}}');
insert into public.spec_definition_values(id,spec_definition_id,code,label) values
 ('f1112300-0000-4000-8000-000000000061','f1112300-0000-4000-8000-000000000053','research_01','01'),
 ('f1112300-0000-4000-8000-000000000062','f1112300-0000-4000-8000-000000000053','research_02','02');
update public.spec_definitions set allowed_values='["01","02"]' where id='f1112300-0000-4000-8000-000000000053';
insert into public.spec_templates(id,key,name,technical_family,form_contract) values
 ('f1112300-0000-4000-8000-000000000050','research_snapshot','Research snapshot','fixture_research',
 '{"rules_version":2,"allowed_when":{},"required_when":{},"allowed_options":{},"prerequisites":{}}');
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select 'f1112300-0000-4000-8000-000000000050',id,'primary',sort_order from public.spec_definitions
where id in ('f1112300-0000-4000-8000-000000000051','f1112300-0000-4000-8000-000000000052',
 'f1112300-0000-4000-8000-000000000053','f1112300-0000-4000-8000-000000000054');
set constraints all immediate;
insert into public.products(id,tenant_id,name,sku,brand,model,price,cost,is_active,spec_template_id) values
 ('f1112300-0000-4000-8000-000000000020','f1112300-0000-4000-8000-000000000001','Research read','RESEARCH-READ','Synthetic','Read',100,50,true,'f1112300-0000-4000-8000-000000000050'),
 ('f1112300-0000-4000-8000-000000000021','f1112300-0000-4000-8000-000000000002','Foreign','RESEARCH-FOREIGN','Synthetic','Foreign',100,50,true,null),
 ('f1112300-0000-4000-8000-000000000022','f1112300-0000-4000-8000-000000000001','Unmapped','RESEARCH-UNMAPPED',null,null,100,50,false,null);
select public.save_product_with_specs_v1(
 '{"id":"f1112300-0000-4000-8000-000000000020","name":"Research read","sku":"RESEARCH-READ"}',false,
 'f1112300-0000-4000-8000-000000000050',(select contract_version from public.spec_templates where id='f1112300-0000-4000-8000-000000000050'),
 '{"f1112300-0000-4000-8000-000000000051":{"number":"9007199254740993.125"},"f1112300-0000-4000-8000-000000000052":{"boolean":false},"f1112300-0000-4000-8000-000000000053":{"value_ids":["f1112300-0000-4000-8000-000000000061"]},"f1112300-0000-4000-8000-000000000054":{"rows":{"schema_version":1,"rows":[{"id":"original-row","values":{"length":"0.100000000000000001"},"sources":[]}]}}}',
 (select spec_revision from public.products where id='f1112300-0000-4000-8000-000000000020'),null,'research-read-save',
 (select updated_at from public.products where id='f1112300-0000-4000-8000-000000000020'));
insert into public.spec_fact_readings(fact_id,tenant_id,source_text,source_digest,quote,model)
select id,tenant_id,'Synthetic historical evidence','synthetic-digest','historical','synthetic'
from public.spec_facts where subject_id='f1112300-0000-4000-8000-000000000020' and spec_definition_id='f1112300-0000-4000-8000-000000000053';
create temp table research_read_state(label text primary key,value jsonb);
grant select,insert on research_read_state to authenticated;
set local role authenticated;
insert into research_read_state values('before',public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020'));
select is((select value->>'actor_id' from research_read_state where label='before'),'f1112300-0000-4000-8000-000000000091','server actor is the authenticated principal');
select is((select value->>'tenant_id' from research_read_state where label='before'),'f1112300-0000-4000-8000-000000000001','tenant is resolved by server');
select is((select value#>'{editor,values,research_amount}' from research_read_state where label='before'),'"9007199254740993.125"'::jsonb,'exact editor digits survive');
select is((select o#>'{fact,value_number}' from research_read_state cross join lateral jsonb_array_elements(value->'observations') o where label='before' and o#>>'{definition,key}'='research_amount'),'"9007199254740993.125"'::jsonb,'raw observation digits survive');
select is((select o#>'{fact,value_boolean}' from research_read_state cross join lateral jsonb_array_elements(value->'observations') o where label='before' and o#>>'{definition,key}'='research_flag'),'false'::jsonb,'false remains a known observation');
select is((select (o#>>'{fact,value_json_text}')::jsonb#>>'{rows,0,values,length}' from research_read_state cross join lateral jsonb_array_elements(value->'observations') o where label='before' and o#>>'{definition,key}'='research_rows'),'0.100000000000000001','structured audit envelope is lossless JSON text');
select is((select jsonb_array_length(o->'options') from research_read_state cross join lateral jsonb_array_elements(value->'observations') o where label='before' and o#>>'{definition,key}'='research_option'),1,'existing option IDs and position are retained');
select is((select jsonb_array_length(o->'readings') from research_read_state cross join lateral jsonb_array_elements(value->'observations') o where label='before' and o#>>'{definition,key}'='research_option'),1,'existing reading and source receipt are retained');
select matches((select value->>'snapshot_sha256' from research_read_state where label='before'),'^[a-f0-9]{64}$','snapshot has a server SHA-256');
select throws_ok($$select public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000021')$$,'42501',null,'foreign product is rejected');
select throws_ok($$select public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000099')$$,'42501',null,'absent product uses the same non-disclosing error');
select throws_ok($$select public.preview_product_spec_research_v1('f1112300-0000-4000-8000-000000000020',null)$$,'40001',null,'missing preimage is rejected');
select throws_ok($$select public.preview_product_spec_research_v1('f1112300-0000-4000-8000-000000000020',repeat('0',64))$$,'40001',null,'stale preimage is rejected');
insert into research_read_state select 'preview',public.preview_product_spec_research_v1('f1112300-0000-4000-8000-000000000020',value->>'snapshot_sha256','{"gtin":"000123"}','{"research_amount":"10"}') from research_read_state where label='before';
select is((select value#>>'{identity,gtin}' from research_read_state where label='preview'),'000123','identity retains leading zero');
select is((select value#>>'{values,research_amount}' from research_read_state where label='preview'),'10','candidate contains explicit proposed delta');
select is((select value#>'{values,research_flag}' from research_read_state where label='preview'),'false'::jsonb,'unmentioned known false is preserved');
select is((select value->'valid_draft' from research_read_state where label='preview'),'true'::jsonb,'valid representation can be simulated');
select is((select value->'apply_authorized' from research_read_state where label='preview'),'false'::jsonb,'valid representation never grants fill authority');
select is((select value->'mechanical_approval' from research_read_state where label='preview'),'false'::jsonb,'valid representation never certifies OEM compatibility');
select is(public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020'),(select value from research_read_state where label='before'),'preview leaves entire persisted research snapshot unchanged');
select throws_ok($$select public.preview_product_spec_research_v1('f1112300-0000-4000-8000-000000000020',(select value->>'snapshot_sha256' from research_read_state where label='before'),'{"price":"0"}')$$,'22023',null,'commercial delta is rejected');
select throws_ok($$select public.preview_product_spec_research_v1('f1112300-0000-4000-8000-000000000020',(select value->>'snapshot_sha256' from research_read_state where label='before'),'{}','{"foreign_key":"10"}')$$,'23514',null,'unknown fact key is rejected');
select throws_ok($$select public.preview_product_spec_research_v1('f1112300-0000-4000-8000-000000000020',(select value->>'snapshot_sha256' from research_read_state where label='before'),'{}','{"research_flag":null}')$$,'23514',null,'fill does not silently delete a known false');
select is(public.preview_product_spec_research_v1('f1112300-0000-4000-8000-000000000020',(select value->>'snapshot_sha256' from research_read_state where label='before'),'{}','{"research_amount":"9007199254740993.126"}')->'valid_draft','false'::jsonb,'canonical server validator rejects exact out-of-range value');
select is(public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000022')#>'{editor,template}','null'::jsonb,'unmapped inactive product remains inspectable');
select throws_ok($$select public.preview_product_spec_research_v1('f1112300-0000-4000-8000-000000000022',public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000022')->>'snapshot_sha256')$$,'23514',null,'unmapped product cannot be presented as ready for fill');
reset role;
-- Commercial changes and child evidence drift must invalidate the preimage.
update public.products set cost=51 where id='f1112300-0000-4000-8000-000000000020';
select isnt(public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020')->>'snapshot_sha256',(select value->>'snapshot_sha256' from research_read_state where label='before'),'commercial state participates in preservation fingerprint');
insert into research_read_state values('before_reading',public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020'));
update public.spec_fact_readings set quote='different historical quote' where fact_id in(select id from public.spec_facts where subject_id='f1112300-0000-4000-8000-000000000020');
select isnt(public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020')->>'snapshot_sha256',(select value->>'snapshot_sha256' from research_read_state where label='before_reading'),'reading changes invalidate the preimage independently of product revision');
delete from public.spec_template_fields where template_id='f1112300-0000-4000-8000-000000000050' and spec_definition_id='f1112300-0000-4000-8000-000000000051';
select is(jsonb_array_length(public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020')->'observations'),4,'retired or orphaned facts are preserved in snapshot');
select is(public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020')#>>'{editor,unassigned_facts,0,key}','research_amount','orphan stays visible outside candidate template');
select is((select provolatile::text from pg_proc where oid='public.get_product_spec_research_snapshot_v1(uuid)'::regprocedure),'s','snapshot is STABLE');
select is((select provolatile::text from pg_proc where oid='public.preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text)'::regprocedure),'s','preview is STABLE');
select is(has_function_privilege('anon','public.get_product_spec_research_snapshot_v1(uuid)','execute'),false,'anonymous role has no snapshot privilege');
select is(has_function_privilege('anon','public.preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text)','execute'),false,'anonymous role has no preview privilege');
select * from finish();
rollback;
