-- Synthetic graph shared by rollback-only member tests. Caller owns BEGIN.
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values
 ('99e10000-0000-4000-8000-000000000001','Spec A'),('99e10000-0000-4000-8000-000000000002','Spec B');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id::uuid,'authenticated','authenticated',email,'',now(),'{}',
 jsonb_build_object('account_type','public_store_customer','customer_tenant_id',tenant),now(),now()
from (values
 ('99e10000-0000-4000-8000-000000000091','spec-a@example.invalid','99e10000-0000-4000-8000-000000000001'),
 ('99e10000-0000-4000-8000-000000000092','spec-b@example.invalid','99e10000-0000-4000-8000-000000000002')) a(id,email,tenant);
delete from public.user_profiles where user_id in ('99e10000-0000-4000-8000-000000000091','99e10000-0000-4000-8000-000000000092');
insert into public.user_profiles(user_id,tenant_id,role) values
 ('99e10000-0000-4000-8000-000000000091','99e10000-0000-4000-8000-000000000001','admin'),
 ('99e10000-0000-4000-8000-000000000092','99e10000-0000-4000-8000-000000000002','admin');
select set_config('request.jwt.claims','{"sub":"99e10000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','99e10000-0000-4000-8000-000000000091',true);
insert into public.product_categories(id,tenant_id,name,full_path) values
 ('99e10000-0000-4000-8000-000000000010','99e10000-0000-4000-8000-000000000001','Spec chains','Spec chains'),
 ('99e10000-0000-4000-8000-000000000011','99e10000-0000-4000-8000-000000000002','Other chains','Other chains');
insert into public.category_tech_mappings(tenant_id,category_id,technical_family,template_id,status)
select '99e10000-0000-4000-8000-000000000001','99e10000-0000-4000-8000-000000000010','chain',id,'active'
from public.spec_templates where key='chain' and tenant_id is null;

insert into public.spec_definitions(id,key,label,data_type,unit,validation_rules,is_customer_visible) values
 ('99e10000-0000-4000-8000-000000000051','member_test_collection','Included parts','json',null,
 '{"rows_schema":{"version":1,"columns":[
 {"key":"family","label":"Family","type":"token","required":true,"allowed_values":["member_part_test","member_other_test"]},
 {"key":"member_role","label":"Role","type":"text"},
 {"key":"position","label":"Position","type":"text"},
 {"key":"identity_brand","label":"Brand","type":"text"},
 {"key":"identity_model","label":"Model","type":"text"},
 {"key":"quantity","label":"Quantity","type":"integer","validation":{"positive":true}}]}}',true),
 ('99e10000-0000-4000-8000-000000000052','member_test_length','Length','number','mm','{"positive":true}',true),
 ('99e10000-0000-4000-8000-000000000053','member_test_included','Included axle','boolean',null,'{}',true),
 ('99e10000-0000-4000-8000-000000000054','member_test_details','Intrinsic rows','json',null,
 '{"rows_schema":{"version":2,"columns":[{"key":"inner","label":"Inner","type":"decimal","unit":"mm"},
 {"key":"outer","label":"Outer","type":"decimal","unit":"mm"}],"strict_ordered_pairs":[["inner","outer"]]}}',true);
insert into public.spec_templates(id,key,name,technical_family,form_contract) values
 ('99e10000-0000-4000-8000-000000000050','member_root_test','Test kit','drivetrain_kit',
 '{"rules_version":2,"roles":{"member_test_collection":"contents"},"member_profiles":{"version":1,
 "collections":[{"field":"member_test_collection","family_column":"family",
 "identity_columns":["member_role","position","identity_brand","identity_model"]}]}}'),
 ('99e10000-0000-4000-8000-000000000060','member_part_test','Test component','complete_brake',
 '{"rules_version":2,"roles":{"member_test_length":"measurement","member_test_included":"contents","member_test_details":"contents"},
 "required_when":{"member_test_length":{"kind":"when","rows":[[{"field":"member_test_included","operator":"eq","value_type":"boolean","value":true}]]}},
 "allowed_when":{"member_test_length":{"kind":"when","rows":[[{"field":"member_test_included","operator":"eq","value_type":"boolean","value":true}]]}}}');
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order) values
 ('99e10000-0000-4000-8000-000000000050','99e10000-0000-4000-8000-000000000051','contents',1),
 ('99e10000-0000-4000-8000-000000000060','99e10000-0000-4000-8000-000000000052','measurement',1),
 ('99e10000-0000-4000-8000-000000000060','99e10000-0000-4000-8000-000000000053','contents',2),
 ('99e10000-0000-4000-8000-000000000060','99e10000-0000-4000-8000-000000000054','contents',3);
update public.spec_templates set form_contract=
 '{"allowed_when":{},"required_when":{},"allowed_options":{},"prerequisites":{}}'::jsonb||form_contract
 where id in ('99e10000-0000-4000-8000-000000000050','99e10000-0000-4000-8000-000000000060');
set constraints all immediate;
set constraints all deferred;
-- Template keys and technical families differ intentionally, as for real disc brakes.
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on) values
 ('member-test-reference','complete_brake','Fixture','Model A','Synthetic component reference',
 '{"99e10000-0000-4000-8000-000000000052":{"number":"7.1"},"99e10000-0000-4000-8000-000000000053":{"boolean":true}}',
 '["https://example.test/member-manual"]','2026-09-14');
insert into public.products(id,tenant_id,name,sku,category_id,spec_template_id,price,cost,is_published,show_on_website) values
 ('99e10000-0000-4000-8000-000000000020','99e10000-0000-4000-8000-000000000001','Profile kit','MEMBER-KIT',
 '99e10000-0000-4000-8000-000000000010','99e10000-0000-4000-8000-000000000050',100,50,true,true);
create temp table member_root_values(value jsonb);
insert into member_root_values values ('{"99e10000-0000-4000-8000-000000000051":{"rows":{"schema_version":1,"rows":[
 {"id":"r1","values":{"family":"member_part_test","member_role":"caliper","position":"front","identity_brand":"Fixture","identity_model":"Model A","quantity":"1"},"sources":["https://example.test/pack"]},
 {"id":"r2","values":{"family":"member_part_test","member_role":"caliper","position":"rear","identity_brand":"Fixture","quantity":"1"},"sources":["https://example.test/pack"]}]}}}');
create function pg_temp.member_profile(p_row text,p_length text default '7.1',p_patch jsonb default '{}') returns jsonb language sql as $$
 select jsonb_build_object('id',case p_row when 'r1' then '99e10000-0000-4000-8000-000000000081' else '99e10000-0000-4000-8000-000000000082' end,
 'collection_definition_id','99e10000-0000-4000-8000-000000000051','member_row_id',p_row,
 'template_id','99e10000-0000-4000-8000-000000000060',
 'contract_version',(select contract_version from public.spec_templates where id='99e10000-0000-4000-8000-000000000060'),
 'values',jsonb_build_object('99e10000-0000-4000-8000-000000000052',jsonb_build_object('number',p_length),
 '99e10000-0000-4000-8000-000000000053',jsonb_build_object('boolean',true)))||p_patch
$$;
create function pg_temp.member_save(p_key text,p_upserts jsonb default '[]',p_archive jsonb default '[]',
 p_root jsonb default null,p_patch jsonb default '{}',p_revision bigint default null,p_v1 boolean default false)
returns jsonb language plpgsql as $$
declare prod jsonb:='{"id":"99e10000-0000-4000-8000-000000000020","name":"Profile kit","sku":"MEMBER-KIT"}';
 vals jsonb; ver integer; rev bigint; updated timestamptz;
begin
 select coalesce(p_root,value) into vals from member_root_values;
 select contract_version into ver from public.spec_templates where id='99e10000-0000-4000-8000-000000000050';
 select coalesce(p_revision,spec_revision),updated_at into rev,updated from public.products where id='99e10000-0000-4000-8000-000000000020';
 if p_v1 then return public.save_product_with_specs_v1(prod||p_patch,false,'99e10000-0000-4000-8000-000000000050',ver,vals,rev,null,p_key,updated); end if;
 return public.save_product_with_specs_v2(prod||p_patch,false,'99e10000-0000-4000-8000-000000000050',ver,vals,rev,null,p_key,updated,
   jsonb_build_object('schema_version',1,'upserts',p_upserts,'archive_ids',p_archive));
end $$;
grant select on member_root_values to authenticated;
grant execute on function pg_temp.member_profile(text,text,jsonb),pg_temp.member_save(text,jsonb,jsonb,jsonb,jsonb,bigint,boolean) to authenticated;
