begin;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values
 ('99b80000-0000-4000-8000-000000000001','Spec A'),('99b80000-0000-4000-8000-000000000002','Spec B');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id::uuid,'authenticated','authenticated',email,'',now(),'{}',
 jsonb_build_object('account_type','public_store_customer','customer_tenant_id',tenant),now(),now()
from (values
 ('99b80000-0000-4000-8000-000000000091','spec-a@example.invalid','99b80000-0000-4000-8000-000000000001'),
 ('99b80000-0000-4000-8000-000000000092','spec-b@example.invalid','99b80000-0000-4000-8000-000000000002')) a(id,email,tenant);
delete from public.user_profiles where user_id in ('99b80000-0000-4000-8000-000000000091','99b80000-0000-4000-8000-000000000092');
insert into public.user_profiles(user_id,tenant_id,role) values
 ('99b80000-0000-4000-8000-000000000091','99b80000-0000-4000-8000-000000000001','admin'),
 ('99b80000-0000-4000-8000-000000000092','99b80000-0000-4000-8000-000000000002','admin');
select set_config('request.jwt.claims','{"sub":"99b80000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','99b80000-0000-4000-8000-000000000091',true);
insert into public.product_categories(id,tenant_id,name,full_path) values
 ('99b80000-0000-4000-8000-000000000010','99b80000-0000-4000-8000-000000000001','Spec chains','Spec chains'),
 ('99b80000-0000-4000-8000-000000000011','99b80000-0000-4000-8000-000000000002','Other chains','Other chains');
insert into public.category_tech_mappings(tenant_id,category_id,technical_family,template_id,status)
select '99b80000-0000-4000-8000-000000000001','99b80000-0000-4000-8000-000000000010','chain',id,'active'
from public.spec_templates where key='chain' and tenant_id is null;


insert into public.products(id,tenant_id,name,sku,category_id,price,cost,is_active,is_published,show_on_website) values
 ('99b80000-0000-4000-8000-000000000020','99b80000-0000-4000-8000-000000000001','Binding test','BIND-TEST','99b80000-0000-4000-8000-000000000010',123,45,true,true,true),
 ('99b80000-0000-4000-8000-000000000021','99b80000-0000-4000-8000-000000000001','Without category','BIND-NOCAT',null,100,50,true,true,true);
insert into public.spec_facts(tenant_id,subject_type,subject_id,spec_definition_id,value_boolean,value_number,source,confirmed)
select '99b80000-0000-4000-8000-000000000001','product','99b80000-0000-4000-8000-000000000020',id,
 case when key='quick_link_included' then false end,case when key='link_count' then 114 end,'name_reading',false
from public.spec_definitions where key in ('quick_link_included','link_count');
insert into public.spec_fact_readings(fact_id,tenant_id,source_text,source_digest,quote,model)
select id,tenant_id,'synthetic package: 114 links, no connector',repeat('a',64),'no connector','synthetic-test'
from public.spec_facts where subject_id='99b80000-0000-4000-8000-000000000020' and spec_definition_id=(select id from public.spec_definitions where key='quick_link_included');
create temp table original_facts as select to_jsonb(f) value from public.spec_facts f where subject_id='99b80000-0000-4000-8000-000000000020';
create temp table original_readings as select to_jsonb(r) value from public.spec_fact_readings r where fact_id in(select (value->>'id')::uuid from original_facts);
create temp table original_revision as select spec_revision from public.products where id='99b80000-0000-4000-8000-000000000020';
create temp table original_product as select to_jsonb(p)-array['spec_template_id','spec_revision','updated_at'] value from public.products p where id='99b80000-0000-4000-8000-000000000020';
create function pg_temp.assign_binding(p_key text,p_template text,p_product uuid default '99b80000-0000-4000-8000-000000000020',p_revision bigint default null,p_updated timestamptz default null)
returns jsonb language sql as $$
 select public.assign_product_spec_template_v1(p_product,(select id from public.spec_templates where key=p_template and tenant_id is null),
 coalesce(p_revision,(select spec_revision from public.products where id=p_product)),
 coalesce(p_updated,(select updated_at from public.products where id=p_product)),p_key,'Synthetic reviewed object class')
$$;
select ok(not has_table_privilege('authenticated','public.product_spec_bindings_internal_v1','select'),'unscoped binding view is private');
select ok(not has_table_privilege('anon','public.product_spec_bindings_internal_v1','select'),'anonymous cannot read binding view');
select ok(not has_function_privilege('authenticated','public.spec_template_resolution_internal_v1(uuid,uuid,uuid)','execute'),'internal resolver is private');
select ok(not has_function_privilege('anon','public.get_product_spec_editor_context_v1(uuid,uuid)','execute'),'editor requires authenticated access');
select is(public.get_product_spec_snapshot_v1('99b80000-0000-4000-8000-000000000020')->>'binding_source','category','legacy category still supplies default');
select lives_ok($$select pg_temp.assign_binding('bind-tire','tire')$$,'explicit reassignment to a different technical family succeeds');
select is(public.get_product_spec_snapshot_v1('99b80000-0000-4000-8000-000000000020')->>'technical_family','tire','snapshot follows product identity');
select is((select spec_revision from public.products where id='99b80000-0000-4000-8000-000000000020'),(select spec_revision+1 from original_revision),'assignment advances revision once');
select is(public.get_product_spec_contexts_v1(array['99b80000-0000-4000-8000-000000000020'::uuid])->'99b80000-0000-4000-8000-000000000020'->>'__technical_family','tire','workshop context follows product identity');
select ok(not (public.get_product_spec_contexts_v1(array['99b80000-0000-4000-8000-000000000020'::uuid])->'99b80000-0000-4000-8000-000000000020' ? 'quick_link_included'),'old chain fact is not a tire compatibility field');
select is(jsonb_array_length(public.get_product_spec_snapshot_v1('99b80000-0000-4000-8000-000000000020')->'unassigned_facts'),2,'all facts outside new template remain visible for review');
select is((select f->'value' from jsonb_array_elements(public.get_product_spec_snapshot_v1('99b80000-0000-4000-8000-000000000020')->'unassigned_facts') f where f->>'key'='quick_link_included'),'false'::jsonb,'orphan false stays known, not missing');
select is((select count(*)::integer from public.get_public_product_technical_specs('99b80000-0000-4000-8000-000000000001','99b80000-0000-4000-8000-000000000020')),0,'public store does not expose former-family facts');
select results_eq($$select to_jsonb(f) from public.spec_facts f where subject_id='99b80000-0000-4000-8000-000000000020' order by id$$,$$select value from original_facts order by value->>'id'$$,'fact identities, values, sources and timestamps are unchanged');
select results_eq($$select to_jsonb(r) from public.spec_fact_readings r where fact_id in(select (value->>'id')::uuid from original_facts) order by fact_id$$,$$select value from original_readings order by value->>'fact_id'$$,'source readings survive unchanged');
select is((select to_jsonb(p)-array['spec_template_id','spec_revision','updated_at'] from public.products p where id='99b80000-0000-4000-8000-000000000020'),(select value from original_product),'category, identity and operational product values are unchanged');
select ok((pg_temp.assign_binding('bind-tire','tire')->>'replayed')::boolean,'retry replays the reviewed assignment');
select is((select spec_revision from public.products where id='99b80000-0000-4000-8000-000000000020'),(select spec_revision+1 from original_revision),'replay does not advance revision');
select throws_ok($$select pg_temp.assign_binding('bind-tire','chain')$$,'23505',null,'same operation cannot mean a different assignment');
select throws_ok($$select pg_temp.assign_binding('stale-bind','chain',p_revision=>-1)$$,'40001',null,'stale revision cannot reassign');
select throws_ok($$select pg_temp.assign_binding('stale-time','chain',p_updated=>'2000-01-01'::timestamptz)$$,'40001',null,'stale timestamp cannot reassign');
select throws_ok($$select public.save_product_spec_facts_v1('99b80000-0000-4000-8000-000000000020',array[(select id from public.spec_definitions where key='link_count')],'{}')$$,'23514',null,'legacy writer cannot delete a preserved former-family fact');
select is(public.get_product_spec_editor_context_v1('99b80000-0000-4000-8000-000000000020',null)->>'technical_family','tire','draft without category keeps explicit identity');
update public.products set category_id=null where id='99b80000-0000-4000-8000-000000000020';
select is(public.get_product_spec_snapshot_v1('99b80000-0000-4000-8000-000000000020')->>'technical_family','tire','saved category change does not change explicit identity');
select ok('99b80000-0000-4000-8000-000000000020'::uuid=any(public.get_product_ids_for_spec_family_v1('tire')),'family recommendations include uncategorized explicit product');
select ok(not ('99b80000-0000-4000-8000-000000000020'::uuid=any(public.get_product_ids_for_spec_family_v1('chain'))),'family recommendations exclude old category identity');
select lives_ok($$select pg_temp.assign_binding('clear-bind',null)$$,'explicit override can be cleared deliberately');
select is(public.get_product_spec_snapshot_v1('99b80000-0000-4000-8000-000000000020')->>'binding_source','none','no invented fallback when category is missing');
update public.products set category_id='99b80000-0000-4000-8000-000000000010' where id='99b80000-0000-4000-8000-000000000020';
select is(public.get_product_spec_snapshot_v1('99b80000-0000-4000-8000-000000000020')->>'binding_source','category','cleared override resumes the active category default');
select is(jsonb_array_length(public.get_product_spec_snapshot_v1('99b80000-0000-4000-8000-000000000020')->'unassigned_facts'),0,'returning to original template restores all facts to active view');
select lives_ok($$select pg_temp.assign_binding('no-category','tire','99b80000-0000-4000-8000-000000000021')$$,'a product never categorized can receive a ficha');
select is(public.get_product_spec_editor_context_v1(null,null)->>'binding_source','none','new uncategorized editor starts without invented facts');
select is(public.get_product_spec_editor_context_v1(null,'99b80000-0000-4000-8000-000000000010')->>'technical_family','chain','new categorized editor reads default');
select throws_ok($$select public.get_product_spec_editor_context_v1(null,'99b80000-0000-4000-8000-000000000011')$$,'42501',null,'editor rejects foreign draft category');

-- Identity changes are checked by every existing writer, not just the new one.
select throws_ok($$select public.save_product_with_specs_v1(
 '{"id":"99b80000-0000-4000-8000-000000000021","name":"Without category","sku":"BIND-NOCAT"}',false,
 (select id from public.spec_templates where key='chain' and tenant_id is null),
 (select contract_version from public.spec_templates where key='chain' and tenant_id is null),'{}',
 (select spec_revision from public.products where id='99b80000-0000-4000-8000-000000000021'),null,'wrong-template',
 (select updated_at from public.products where id='99b80000-0000-4000-8000-000000000021'))$$,'40001',null,'old editor cannot save through former template');
select lives_ok($$select public.save_product_with_specs_v1(
 '{"id":"99b80000-0000-4000-8000-000000000021","name":"Without category","sku":"BIND-NOCAT","price":101}',false,
 (select id from public.spec_templates where key='tire' and tenant_id is null),
 (select contract_version from public.spec_templates where key='tire' and tenant_id is null),'{}',
 (select spec_revision from public.products where id='99b80000-0000-4000-8000-000000000021'),null,'normal-save',
 (select updated_at from public.products where id='99b80000-0000-4000-8000-000000000021'))$$,'ordinary product save preserves explicit binding');
select is(public.get_product_spec_snapshot_v1('99b80000-0000-4000-8000-000000000021')->>'technical_family','tire','ordinary save does not erase binding');
select lives_ok($$select public.save_product_spec_facts_v1('99b80000-0000-4000-8000-000000000021',
 array[(select id from public.spec_definitions where key='tire_etrto')],
 (select jsonb_build_object(id,jsonb_build_object('text','37-622')) from public.spec_definitions where key='tire_etrto'))$$,
 'facts can be written through the explicitly assigned template');
select is((select display_value from public.get_public_product_technical_specs('99b80000-0000-4000-8000-000000000001','99b80000-0000-4000-8000-000000000021') where spec_key='tire_etrto'),
 '37-622','public store publishes a known fact of the assigned template');
insert into public.spec_templates(id,tenant_id,key,name,technical_family,is_active) values
 ('99b80000-0000-4000-8000-000000000040','99b80000-0000-4000-8000-000000000002','foreign-binding','Foreign','tire',true),
 ('99b80000-0000-4000-8000-000000000041',null,'inactive-binding','Inactive','tire',false);
select throws_ok($$select public.assign_product_spec_template_v1('99b80000-0000-4000-8000-000000000021','99b80000-0000-4000-8000-000000000040',
 (select spec_revision from public.products where id='99b80000-0000-4000-8000-000000000021'),
 (select updated_at from public.products where id='99b80000-0000-4000-8000-000000000021'),'foreign-template','reason')$$,'42501',null,'foreign template is rejected before mutation');
select throws_ok($$select pg_temp.assign_binding('inactive-template','inactive-binding')$$,'42501',null,'inactive explicit template is rejected');
select lives_ok($$select public.save_product_with_specs_v1(
 '{"id":"99b80000-0000-4000-8000-000000000022","name":"Referenced X8","sku":"BIND-X8","brand":"KMC","model":"X8","manufacturer_sku":"BX08NG114","price":100,"cost":50,"category_id":"99b80000-0000-4000-8000-000000000010"}',true,
 (select id from public.spec_templates where key='chain' and tenant_id is null),
 (select contract_version from public.spec_templates where key='chain' and tenant_id is null),'{}',0,'kmc-x8-bx08ng114-eu-20260905','create-reference',null)$$,'reference fixture uses atomic writer');
select throws_ok($$select pg_temp.assign_binding('wrong-reference-family','tire','99b80000-0000-4000-8000-000000000022')$$,'23514',null,'reference identity cannot be moved to another family');
select is(public.get_product_spec_snapshot_v1('99b80000-0000-4000-8000-000000000022')->>'technical_family','chain','rejected reference move leaves binding unchanged');
select lives_ok($$select pg_temp.assign_binding('reference-explicit-chain','chain','99b80000-0000-4000-8000-000000000022')$$,'same-family reference can receive explicit identity');
select lives_ok($$select pg_temp.assign_binding('mixed-category','tire')$$,'one category may contain different product identities');
select is((select count(distinct technical_family)::integer from public.category_spec_template_scope_internal_v1 where tenant_id='99b80000-0000-4000-8000-000000000001' and category_id='99b80000-0000-4000-8000-000000000010'),2,'schema discovery includes both classes in a mixed category');
select is(public.assistant_inventory_technical_predicate_source_internal_v1('99b80000-0000-4000-8000-000000000001','99b80000-0000-4000-8000-000000000020','link_count','eq','[114]','binding test 114','binding test 114'),'unresolved','preserved chain fact and matching name cannot satisfy a tire predicate');
select is(public.assistant_inventory_technical_filter_source_internal_v1('99b80000-0000-4000-8000-000000000001','99b80000-0000-4000-8000-000000000020','link_count','114','binding test 114','binding test 114'),'unresolved','legacy search cannot reuse out-of-template values');
select lives_ok($$select public.assistant_inspect_inventory_schema_v3('Spec chains','Spec chains')$$,'AI schema inspector executes against mixed product bindings');
select ok(exists(select 1 from jsonb_array_elements(public.assistant_inspect_inventory_schema_v3('Spec chains','Spec chains')->'items') r where r->>'kind'='field' and r->>'technicalFamily'='tire'),'AI field discovery exposes the explicit family in a mixed category');
select ok(exists(select 1 from jsonb_array_elements(public.assistant_inspect_inventory_schema_v3('Spec chains','Spec chains')->'items') r where r->>'kind'='category' and r->>'technicalFamily' is null),'AI category header does not invent a single family for a mixed category');
select ok(not exists(select 1 from jsonb_array_elements(public.assistant_inspect_inventory_schema_v3('Spec chains','Spec chains')->'items') r where r->>'kind'='field' and r->>'field' in ('chain_profile_family','drivetrain_primary_ecosystem')),'current discovery excludes retired chain criteria');
select ok(not exists(select 1 from jsonb_array_elements(public.assistant_inspect_inventory_schema_v1('Spec chains','Spec chains')->'items') r where r->>'kind'='field' and r->>'field' in ('chain_profile_family','drivetrain_primary_ecosystem')),'legacy discovery cannot resurrect retired chain criteria');
select lives_ok($$select public.assistant_search_inventory_v7('Binding test',null,'any','[]','[]','name','asc',10,'all_matches')$$,'current AI inventory search executes with explicit identity');
select throws_ok($$update public.spec_templates set is_active=false where key='tire' and tenant_id is null$$,'23514',null,'a referenced template cannot be retired');
select throws_ok($$update public.spec_templates set technical_family='chain' where key='tire' and tenant_id is null$$,'23514',null,'template identity cannot change under assigned products');
-- The FK is independent of the friendly trigger and survives concurrency.
-- Drain metadata guards before changing trigger state in this synthetic probe.
set constraints all immediate;
alter table public.spec_templates disable trigger spec_template_retirement_guard;
select throws_ok($$update public.spec_templates set is_active=false where key='tire' and tenant_id is null$$,'23503',null,'foreign key protects active assignment even without advisory trigger');
alter table public.spec_templates enable trigger spec_template_retirement_guard;
-- Only this synthetic fixture simulates an unavailable historical binding.
alter table public.spec_templates disable trigger spec_template_retirement_guard;
set constraints products_spec_template_active_fk deferred;
update public.spec_templates set is_active=false where key='tire' and tenant_id is null;
select is(public.get_product_spec_snapshot_v1('99b80000-0000-4000-8000-000000000020')->>'binding_source','explicit_unavailable','inactive explicit template never falls back to category');
select is(public.get_product_spec_contexts_v1(array['99b80000-0000-4000-8000-000000000020'::uuid])->'99b80000-0000-4000-8000-000000000020'->'__spec_issues'->0->>'code','template_unavailable','workshop receives unavailable-template caution');
select is(public.get_product_spec_editor_context_v1('99b80000-0000-4000-8000-000000000020','99b80000-0000-4000-8000-000000000010')->>'binding_source','explicit_unavailable','editor exposes unavailable assignment with preserved data');
update public.spec_templates set is_active=true where key='tire' and tenant_id is null;
set constraints products_spec_template_active_fk immediate;
alter table public.spec_templates enable trigger spec_template_retirement_guard;
set local role authenticated;
select ok(not has_column_privilege('authenticated','products','spec_template_id','UPDATE'),'table-wide privilege cannot bypass assignment command');
select ok(not has_column_privilege('authenticated','products','spec_reference_id','INSERT'),'direct insert cannot bypass reference command');
select throws_ok($$update public.products set spec_template_id=null where id='99b80000-0000-4000-8000-000000000021'$$,'42501',null,'actual client role cannot write protected identity directly');
select lives_ok($$update public.products set price=102 where id='99b80000-0000-4000-8000-000000000021'$$,'ordinary column permissions remain available');
select lives_ok($$select pg_temp.assign_binding('authenticated-assignment','tire','99b80000-0000-4000-8000-000000000021')$$,'actual authenticated role can assign through reviewed command');

select is(public.get_product_spec_bindings_v1(array['99b80000-0000-4000-8000-000000000021'::uuid])->'99b80000-0000-4000-8000-000000000021'->>'binding_source','explicit','authenticated role can use the guarded binding reader');
select lives_ok($$select public.get_product_spec_editor_context_v1('99b80000-0000-4000-8000-000000000021',null)$$,'authenticated role can use the editor reader');
reset role;
select set_config('request.jwt.claim.sub','99b80000-0000-4000-8000-000000000092',true);
select set_config('request.jwt.claims','{"sub":"99b80000-0000-4000-8000-000000000092","role":"authenticated"}',true);
set local role authenticated;
select is(public.get_product_spec_bindings_v1(array['99b80000-0000-4000-8000-000000000020'::uuid]),'{}'::jsonb,'binding reader cannot cross tenants');
select ok(not ('99b80000-0000-4000-8000-000000000021'::uuid=any(public.get_product_ids_for_spec_family_v1('tire'))),'family reader cannot cross tenants');
select throws_ok($$select public.get_product_spec_editor_context_v1('99b80000-0000-4000-8000-000000000021',null)$$,'42501',null,'editor cannot cross tenants');
select throws_ok($$select public.assign_product_spec_template_v1('99b80000-0000-4000-8000-000000000021',null,0,now(),'foreign-bind','reason')$$,'42501',null,'assignment cannot cross tenants');
reset role;
set constraints all immediate;
select pass('deferred integrity guards accept the preserved observations');
select * from finish();
rollback;
