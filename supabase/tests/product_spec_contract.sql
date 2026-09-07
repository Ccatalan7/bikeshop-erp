begin;
select no_plan();
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values
 ('99b60000-0000-4000-8000-000000000001','Spec A'),('99b60000-0000-4000-8000-000000000002','Spec B');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id::uuid,'authenticated','authenticated',email,'',now(),'{}',
 jsonb_build_object('account_type','public_store_customer','customer_tenant_id',tenant),now(),now()
from (values
 ('99b60000-0000-4000-8000-000000000091','spec-a@example.invalid','99b60000-0000-4000-8000-000000000001'),
 ('99b60000-0000-4000-8000-000000000092','spec-b@example.invalid','99b60000-0000-4000-8000-000000000002')) a(id,email,tenant);
delete from public.user_profiles where user_id in ('99b60000-0000-4000-8000-000000000091','99b60000-0000-4000-8000-000000000092');
insert into public.user_profiles(user_id,tenant_id,role) values
 ('99b60000-0000-4000-8000-000000000091','99b60000-0000-4000-8000-000000000001','admin'),
 ('99b60000-0000-4000-8000-000000000092','99b60000-0000-4000-8000-000000000002','admin');
select set_config('request.jwt.claims','{"sub":"99b60000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','99b60000-0000-4000-8000-000000000091',true);
insert into public.product_categories(id,tenant_id,name,full_path) values
 ('99b60000-0000-4000-8000-000000000010','99b60000-0000-4000-8000-000000000001','Spec chains','Spec chains'),
 ('99b60000-0000-4000-8000-000000000011','99b60000-0000-4000-8000-000000000002','Other chains','Other chains');
insert into public.category_tech_mappings(tenant_id,category_id,technical_family,template_id,status)
select '99b60000-0000-4000-8000-000000000001','99b60000-0000-4000-8000-000000000010','chain',id,'active'
from public.spec_templates where key='chain' and tenant_id is null;

create function pg_temp.spec_options(p_key text,p_labels text[]) returns jsonb language sql as $$
 select jsonb_build_object(d.id,jsonb_build_object('value_ids',jsonb_agg(v.id order by v.label)))
 from public.spec_definitions d join public.spec_definition_values v on v.spec_definition_id=d.id
 where d.key=p_key and v.label=any(p_labels) group by d.id
$$;
create function pg_temp.spec_save(p_key text,p_values jsonb default '{}',p_patch jsonb default '{}',
 p_revision bigint default null,p_reference text default 'kmc-x8-bx08ng114-eu-20260905',
 p_version integer default null,p_new boolean default false,p_components jsonb default null) returns jsonb language sql as $$
 select public.save_product_with_specs_v1(
  '{"id":"99b60000-0000-4000-8000-000000000020","name":"X8 test","sku":"SPEC-X8","brand":"KMC","model":"X8","manufacturer_sku":"BX08NG114","price":100,"cost":50,"category_id":"99b60000-0000-4000-8000-000000000010"}'::jsonb || p_patch,
  p_new,(select id from public.spec_templates where key='chain' and tenant_id is null),
  coalesce(p_version,(select contract_version from public.spec_templates where key='chain' and tenant_id is null)),
  p_values,coalesce(p_revision,(select spec_revision from public.products where id='99b60000-0000-4000-8000-000000000020')),
  p_reference,p_key,(select updated_at from public.products where id='99b60000-0000-4000-8000-000000000020'),p_components)
$$;
select is(public.spec_condition_internal_v1('{"field":"x","operator":"neq","value":"A"}','{}'),null::boolean,'missing does not satisfy neq');
select is(public.spec_condition_internal_v1('{"field":"x","operator":"not_in","value":["A"]}','{}'),null::boolean,'missing does not satisfy not_in');
select ok(public.spec_rule_known_internal_v1('false'),'false is known');
select ok(public.spec_rule_known_internal_v1('0'),'zero is known');
select ok(not public.spec_rule_known_internal_v1('"Desconocido / sin confirmar"'),'unknown label is unknown');
select ok(public.spec_condition_internal_v1('{"field":"x","value":[6,7]}','{"x":["7","6"]}'),'sets normalize type and order');
select ok(not public.spec_condition_internal_v1('{"field":"x","operator":"in","value":[6,7]}','{"x":[6,8]}'),'in requires every selected member');
select throws_ok($$select public.spec_condition_internal_v1('{"field":"x","operator":"typo"}','{}')$$,'22023',null,'invalid operator fails closed');
select ok(not has_function_privilege('authenticated','public.spec_write_payload_internal_v2(uuid,uuid,jsonb,text)','execute'),'internal writer is private');
select ok(not has_function_privilege('anon','public.get_product_spec_snapshot_v1(uuid)','execute'),'anonymous cannot read private specs');
select ok(has_function_privilege('authenticated','public.save_product_with_specs_v1(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamptz,jsonb)','execute'),'authenticated command is available');
select lives_ok($$select pg_temp.spec_save('create',p_new=>true)$$,'create binds identity and all documented facts atomically');
select is((public.get_product_spec_snapshot_v1('99b60000-0000-4000-8000-000000000020')->'values'->>'chain_width_family'),'3/32','reference supplies nominal width');
select is((public.get_product_spec_snapshot_v1('99b60000-0000-4000-8000-000000000020')->'values'->'chain_speeds'),'["6","7","8"]'::jsonb,'reference supplies real declared speeds');
select is((public.get_product_spec_snapshot_v1('99b60000-0000-4000-8000-000000000020')->'values'->>'link_count'),'114','exact EU pack length');
select ok((public.get_product_spec_snapshot_v1('99b60000-0000-4000-8000-000000000020')->>'revision')::bigint>0,'facts advance revision');
select ok((pg_temp.spec_save('create',p_new=>true)->>'replayed')::boolean,'identical retry replays original create');
select throws_ok($$select pg_temp.spec_save('create',p_patch=>'{"name":"different"}',p_new=>true)$$,'23505',null,'operation key cannot authorize another request');
select throws_ok($$select pg_temp.spec_save('bad-width',pg_temp.spec_options('chain_width_family',array['11/128']),'{"name":"must roll back"}')$$,'23514',null,'reference contradiction rejects the entire command');
select is((select name from public.products where id='99b60000-0000-4000-8000-000000000020'),'X8 test','failed spec command leaves commercial data unchanged');
select throws_ok($$update public.spec_facts set subject_id='99b60000-0000-4000-8000-000000000030' where subject_id='99b60000-0000-4000-8000-000000000020'$$,'23514',null,'moving observations cannot bypass the old reference guard');
select is((select count(*)::integer from public.product_spec_save_receipts where operation_key='bad-width'),0,'failed command creates no receipt');
select throws_ok($$select pg_temp.spec_save('stale',p_revision=>-1)$$,'40001',null,'stale editor cannot overwrite newer facts');
select throws_ok($$select pg_temp.spec_save('old-template',p_version=>1)$$,'40001',null,'old template rejected');
select throws_ok($$select pg_temp.spec_save('foreign',p_patch=>'{"tenant_id":"99b60000-0000-4000-8000-000000000002"}')$$,'42501',null,'tenant cannot be selected in the payload');
select throws_ok($$select pg_temp.spec_save('foreign-category',p_patch=>'{"category_id":"99b60000-0000-4000-8000-000000000011"}',p_version=>null)$$,null,null,'foreign category cannot be attached');
select throws_ok($$select pg_temp.spec_save('wrong-mpn',p_patch=>'{"manufacturer_sku":"CN-other"}')$$,'23514',null,'reference requires the precise variant');
select throws_ok($$select public.save_product_spec_facts_v1('99b60000-0000-4000-8000-000000000020',array[(select id from public.spec_definitions where key='chain_width_family')],(select jsonb_build_object(id,jsonb_build_object('labels',jsonb_build_array('imaginary'))) from public.spec_definitions where key='chain_width_family'))$$,'23514',null,'legacy label writer cannot silently drop an invalid label');
select throws_ok($$select pg_temp.spec_save('unsupported-claim',pg_temp.spec_options('drivetrain_platform',array['SRAM Eagle']))$$,'23514',null,'a selected reference cannot absorb an undocumented manual declaration');
select throws_ok($$select pg_temp.spec_save('foreign-option',(select jsonb_build_object(d.id,jsonb_build_object('value_ids',jsonb_build_array(v.id))) from public.spec_definitions d cross join public.spec_definition_values v where d.key='chain_width_family' and v.spec_definition_id<>d.id limit 1))$$,'23514',null,'normalized option UUID must belong to its field');
select ok((select claims @> '[{"exclusive":true,"platform":"Shimano LINKGLIDE"}]'::jsonb from public.product_spec_references where id='kmc-eglide-us-20260905'),'eGlide declaration keeps exclusive platform scope');
select ok((select claims->0->'systems' ? 'Campagnolo' from public.product_spec_references where id='kmc-x11-us-118-20260905'),'X11 explicitly supports Campagnolo');
select throws_ok($$update public.product_spec_references set model='changed' where id='kmc-x11-us-118-20260905'$$,'23514',null,'reference editions are immutable');
create temp table original_revision as select spec_revision from public.products where id='99b60000-0000-4000-8000-000000000020';
update public.products set spec_revision=0 where id='99b60000-0000-4000-8000-000000000020';
select is((select spec_revision from public.products where id='99b60000-0000-4000-8000-000000000020'),(select spec_revision from original_revision),'direct client cannot reset revision');
select set_config('request.jwt.claim.sub','99b60000-0000-4000-8000-000000000092',true);
select set_config('request.jwt.claims','{"sub":"99b60000-0000-4000-8000-000000000092","role":"authenticated"}',true);
select throws_ok($$select public.get_product_spec_snapshot_v1('99b60000-0000-4000-8000-000000000020')$$,'42501',null,'other tenant cannot read snapshot');
select throws_ok($$select pg_temp.spec_save('foreign-update')$$,'42501',null,'other tenant cannot update product');
select throws_ok($$insert into public.spec_facts(tenant_id,subject_type,subject_id,spec_definition_id,value_number,source,confirmed)
 select '99b60000-0000-4000-8000-000000000002','product','99b60000-0000-4000-8000-000000000020',id,120,'mechanic',false from public.spec_definitions where key='link_count'$$,'42501',null,'direct facts cannot cross the product tenant graph');
select is(public.get_product_spec_contexts_v1(array['99b60000-0000-4000-8000-000000000020'::uuid]),'{}'::jsonb,'batch context does not leak foreign products');
select set_config('request.jwt.claim.sub','99b60000-0000-4000-8000-000000000091',true);
select set_config('request.jwt.claims','{"sub":"99b60000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select lives_ok($$select pg_temp.spec_save('manual-false',(select jsonb_build_object(id,jsonb_build_object('boolean',false)) from public.spec_definitions where key='quick_link_included'),p_reference=>null)$$,'manual false is persisted');
select is(public.get_product_spec_snapshot_v1('99b60000-0000-4000-8000-000000000020')->'values'->'quick_link_included','false'::jsonb,'false stays distinct from missing');
select lives_ok($$select pg_temp.spec_save('public-false',
 (select jsonb_object_agg(id,case key when 'quick_link_included' then '{"boolean":false}'::jsonb else '{"text":"private packaging note"}'::jsonb end)
  from public.spec_definitions where key in ('quick_link_included','spec_evidence_source')),
 '{"is_published":true,"show_on_website":true}',p_reference=>null)$$,'publish fixture using the same atomic contract');
select is((select display_value from public.get_public_product_technical_specs('99b60000-0000-4000-8000-000000000001','99b60000-0000-4000-8000-000000000020') where spec_key='quick_link_included'),'No','public store preserves an explicit false');
select is((select count(*)::integer from public.get_public_product_technical_specs('99b60000-0000-4000-8000-000000000001','99b60000-0000-4000-8000-000000000020') where spec_key='spec_evidence_source'),0,'private source notes stay private');
select is((select count(*)::integer from public.get_public_product_technical_specs('99b60000-0000-4000-8000-000000000002','99b60000-0000-4000-8000-000000000020')),0,'public tenant/product pair cannot be crossed');
select lives_ok($$select pg_temp.spec_save('legacy-speeds',pg_temp.spec_options('chain_speeds',array['8']),'{"is_published":true,"show_on_website":true}',p_reference=>null)$$,'existing speeds without mode remain valid incomplete observations');
select is((select display_value from public.get_public_product_technical_specs('99b60000-0000-4000-8000-000000000001','99b60000-0000-4000-8000-000000000020') where spec_key='chain_speeds'),'8','a missing prerequisite does not erase known public facts');
update public.spec_facts set source='name_reading' where subject_id='99b60000-0000-4000-8000-000000000020' and spec_definition_id=(select id from public.spec_definitions where key='chain_speeds');
select lives_ok($$select pg_temp.spec_save('price-only',pg_temp.spec_options('chain_speeds',array['8']),'{"price":200}',p_reference=>null)$$,'commercial edit preserves an unchanged observation');
select is((select source from public.spec_facts where subject_id='99b60000-0000-4000-8000-000000000020' and spec_definition_id=(select id from public.spec_definitions where key='chain_speeds')),'name_reading','unchanged evidence is not relabelled as a mechanic answer');
select lives_ok($$select pg_temp.spec_save('manual-empty',p_reference=>null)$$,'clearing a boolean removes its observation');
select ok(not (public.get_product_spec_snapshot_v1('99b60000-0000-4000-8000-000000000020')->'values' ? 'quick_link_included'),'missing remains unknown');
select throws_ok($$select pg_temp.spec_save('invalid-set',p_values=>pg_temp.spec_options('chain_width_family',array['11/128']),
 p_patch=>'{"id":"99b60000-0000-4000-8000-000000000030","sku":"SPEC-SET","is_set":true,"set_type":"front_rear"}',p_new=>true,
 p_components=>'[{"sku":"SPEC-SET-A","name":"A","label":"A","position":1,"quantity_in_set":1,"price":50,"cost":25},{"sku":"SPEC-SET-B","name":"B","label":"B","position":2,"quantity_in_set":1,"price":50,"cost":25}]')$$,'23514',null,'invalid specs roll back the whole set aggregate');
select is((select count(*)::integer from public.products where id='99b60000-0000-4000-8000-000000000030' or parent_set_id='99b60000-0000-4000-8000-000000000030'),0,'no set parent or components survive the failed command');
create temp table template_revision as select id,contract_version from public.spec_templates where key='chain' and tenant_id is null;
update public.spec_template_fields set helper_text=coalesce(helper_text,'') || ' test' where template_id=(select id from template_revision) and spec_definition_id=(select id from public.spec_definitions where key='chain_speeds');
select ok((select t.contract_version>r.contract_version from public.spec_templates t join template_revision r using(id)),'field changes invalidate the contract version');
select throws_ok($$select pg_temp.spec_save('stale-config',p_reference=>null,p_version=>(select contract_version from template_revision))$$,'40001',null,'an editor cannot silently use changed metadata');
set constraints all immediate;
select pass('all deferred guards accept the final consistent state');
select * from finish();
rollback;
