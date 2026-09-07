begin;
select no_plan();
create function pg_temp.draft(p_family text,p_values jsonb) returns jsonb language sql as $$
 select public.spec_validate_draft_internal_v1(id,p_values) from public.spec_templates
 where key=p_family and tenant_id is null
$$;
select is(pg_temp.draft('chain','{"chain_width_family":"1/8","chain_outer_width_mm":9,"link_count":138}'),'[]'::jsonb,'wide chains and long packs are valid measurements');
select ok(jsonb_array_length(pg_temp.draft('chain','{"link_count":114.5}'))>0,'chain length must be an integer');
select ok(jsonb_array_length(pg_temp.draft('chain','{"chain_outer_width_mm":0}'))>0,'width must be positive');
select ok(jsonb_array_length(pg_temp.draft('chain_link','{"chain_link_pack_qty":0.5}'))>0,'pack quantity must count complete connectors');
select ok(jsonb_array_length(pg_temp.draft('chain_link','{"chain_link_pack_qty":-1}'))>0,'pack quantity must be positive');
select is(pg_temp.draft('chain','{"chain_width_family":"1/8"}'),'[]'::jsonb,'width alone cannot establish application');
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.draft('chain','{"chain_width_family":"1/8","chain_speeds":["7"]}')) e where coalesce((e->>'blocking')::boolean,true)),'missing mode is nonblocking');
select ok(jsonb_array_length(pg_temp.draft('chain','{"drivetrain_mode":"Derailleur","chain_speeds":["7"],"chain_width_family":"1/8"}'))>0,'wide chain contradicts declared modern derailleur coverage');
select is(pg_temp.draft('chain_link','{"chain_connector_type":"Missing link","chain_speeds":["10"]}'),'[]'::jsonb,'manual connector needs no bike application or reference');
select is(pg_temp.draft('chain_link','{"chain_connector_type":"Missing link","chain_speeds":["10"],"drivetrain_mode":"Single speed / BMX / IGH"}'),'[]'::jsonb,'legacy application cannot restrict the target chain class');
select is(pg_temp.draft('chain_link','{"chain_connector_type":"Pin","chain_link_reusable":false,"spec_evidence_source":"Envase"}'),'[]'::jsonb,'new connecting rivet can be documented as single use');
select ok(jsonb_array_length(pg_temp.draft('chain_link','{"chain_connector_type":"Pin","chain_link_reusable":true,"spec_evidence_source":"Envase"}'))>0,'replacement rivet is not reusable');
select ok(jsonb_array_length(pg_temp.draft('chain_link','{"chain_connector_type":"Pin","chain_outer_width_mm":7.1}'))>0,'mounted closure width is not a pilot rivet length');
select is(pg_temp.draft('chain_link','{"chain_connector_type":"Eslabón con clip"}'),'[]'::jsonb,'clip closure has distinct anatomy');
select is(public.spec_validate_draft_internal_v1(t.id,public.spec_payload_display_internal_v1(r.fact_values),r.id,r.brand,r.model,coalesce(r.manufacturer_sku,'')),'[]'::jsonb,r.id || ' documented facts validate')
from public.product_spec_references r join public.spec_templates t on t.technical_family=r.technical_family and t.tenant_id is null
where r.id like '%20260906';
select ok(not exists(select 1 from public.product_spec_references r where r.id like '%20260906' and r.technical_family='chain_link' and public.spec_payload_display_internal_v1(r.fact_values) ? 'chain_link_pack_qty'),'model pages do not invent packaging quantities');
select ok((select claims @> '[{"interface":"connector_chain","excludes":["Cualquier cadena Flattop"]}]'::jsonb from public.product_spec_references where id='kmc-cl552-global-20260906'),'explicit Flattop exclusion is retained');

-- Synthetic local-only integration; no production test product is ever needed.
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values ('99b61000-0000-4000-8000-000000000001','Connector tests');
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('99b61000-0000-4000-8000-000000000091','authenticated','authenticated','connector@example.invalid','',now(),'{}','{"account_type":"public_store_customer","customer_tenant_id":"99b61000-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='99b61000-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values ('99b61000-0000-4000-8000-000000000091','99b61000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"99b61000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','99b61000-0000-4000-8000-000000000091',true);
insert into public.product_categories(id,tenant_id,name,full_path) values ('99b61000-0000-4000-8000-000000000010','99b61000-0000-4000-8000-000000000001','Connectors','Connectors');
insert into public.category_tech_mappings(tenant_id,category_id,technical_family,template_id,status)
select '99b61000-0000-4000-8000-000000000001','99b61000-0000-4000-8000-000000000010','chain_link',id,'active'
from public.spec_templates where key='chain_link' and tenant_id is null;
create function pg_temp.save_connector(p_key text,p_new boolean default false,p_values jsonb default '{}',p_name text default 'CL552 test',p_reference text default 'kmc-cl552-global-20260906') returns jsonb language sql as $$
 select public.save_product_with_specs_v1(
 '{"id":"99b61000-0000-4000-8000-000000000020","sku":"SPEC-CL552","brand":"KMC","model":"CL552","manufacturer_sku":"KEEP-MPN","price":100,"cost":50,"category_id":"99b61000-0000-4000-8000-000000000010"}'::jsonb || jsonb_build_object('name',p_name),
 p_new,t.id,t.contract_version,p_values,
 (select spec_revision from public.products where id='99b61000-0000-4000-8000-000000000020'),
 p_reference,p_key,
 (select updated_at from public.products where id='99b61000-0000-4000-8000-000000000020'),null)
 from public.spec_templates t where key='chain_link' and tenant_id is null
$$;
select lives_ok($$select pg_temp.save_connector('create',true)$$,'connector reference and product save atomically');
select is((public.get_product_spec_snapshot_v1('99b61000-0000-4000-8000-000000000020')->'values'->>'chain_link_reusable'),'false','single-use declaration persists');
select is((select manufacturer_sku from public.products where id='99b61000-0000-4000-8000-000000000020'),'KEEP-MPN','model-only reference preserves manual manufacturer code');
select throws_ok($$select pg_temp.save_connector('wrong',false,(select jsonb_build_object(id,jsonb_build_object('boolean',true)) from public.spec_definitions where key='chain_link_reusable' and tenant_id is null),'must roll back')$$,'23514',null,'manual reuse contradiction rejects entire save');
select is((select name from public.products where id='99b61000-0000-4000-8000-000000000020'),'CL552 test','rejected connector leaves identity unchanged');
select ok((pg_temp.save_connector('create',true)->>'replayed')::boolean,'connector command replays without writing twice');
select lives_ok($$select pg_temp.save_connector('note',false,(select jsonb_build_object(id,jsonb_build_object('text','Envase revisado')) from public.spec_definitions where key='spec_evidence_source' and tenant_id is null))$$,'operator evidence can supplement a linked reference');
select is((public.get_product_spec_snapshot_v1('99b61000-0000-4000-8000-000000000020')->'values'->>'spec_evidence_source'),'Envase revisado','evidence note survives a fresh snapshot');
select is((select f.source from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id where f.subject_type='product' and f.subject_id='99b61000-0000-4000-8000-000000000020' and d.key='spec_evidence_source'),'mechanic','operator note is never attributed to the catalogue');
select ok(not (public.get_product_spec_snapshot_v1('99b61000-0000-4000-8000-000000000020')->'catalog_keys' ? 'spec_evidence_source'),'reload will not remove the note as an automatic value');
select ok((select sources @> '["https://www.kmcchain.com/en/product/connector-missing-link-cl552-12-speed"]'::jsonb from public.product_spec_references where id='kmc-cl552-global-20260906'),'manufacturer source remains on the immutable reference');
select lives_ok($$select pg_temp.save_connector('detach',false,(select jsonb_build_object(id,jsonb_build_object('text','Envase revisado')) from public.spec_definitions where key='spec_evidence_source' and tenant_id is null),p_reference=>null)$$,'reference can be detached while retaining the operator note');
select is((public.get_product_spec_snapshot_v1('99b61000-0000-4000-8000-000000000020')->'values'),' {"spec_evidence_source":"Envase revisado"}'::jsonb,'detaching removes automatic facts and retains independent evidence');
create function pg_temp.manual_connector_facts() returns jsonb language sql as $$
 select jsonb_object_agg(e.key,e.value) from public.product_spec_references r,
 jsonb_each(r.fact_values) e join public.spec_definitions d on d.id::text=e.key
 where r.id='kmc-cl552-global-20260906' and d.key in ('chain_connector_type','chain_link_reusable')
$$;
select lives_ok($$select pg_temp.save_connector('manual-facts',false,pg_temp.manual_connector_facts(),p_reference=>null)$$,'independent observations can precede a matching reference');
create temporary table independent_fact_observations as
 select f.id,f.source,f.updated_at from public.spec_facts f
 where f.subject_type='product' and f.subject_id='99b61000-0000-4000-8000-000000000020';
select lives_ok($$select pg_temp.save_connector('link-observations',false,pg_temp.manual_connector_facts())$$,'a matching reference can supplement independent observations');
select ok((select count(*)=2 and bool_and(f.source=o.source and f.source='mechanic' and f.updated_at=o.updated_at) from independent_fact_observations o join public.spec_facts f on f.id=o.id),'binding preserves the source and timestamp of identical manual facts');
select ok(not (public.get_product_spec_snapshot_v1('99b61000-0000-4000-8000-000000000020')->'catalog_keys' ?| array['chain_connector_type','chain_link_reusable']),'matching manual facts are not automatic after reload');
select lives_ok($$select pg_temp.save_connector('unlink-observations',false,pg_temp.manual_connector_facts(),p_reference=>null)$$,'detaching a reference retains identical preexisting observations');
select is((public.get_product_spec_snapshot_v1('99b61000-0000-4000-8000-000000000020')->'values'),' {"chain_connector_type":"Missing link","chain_link_reusable":false}'::jsonb,'only automatic facts disappear on detach');
set constraints all immediate;
select pass('deferred aggregate guards accept the final connector');
select * from finish();
rollback;
