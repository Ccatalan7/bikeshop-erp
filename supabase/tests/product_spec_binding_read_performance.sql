-- Functional regression for the set-based inference projection. Synthetic
-- fixtures only; wall-clock performance is measured separately with guarded
-- production SELECTs, not asserted against a variable CI timer.
begin;
set local client_min_messages=error;
select no_plan();
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values
 ('99ba0000-0000-4000-8000-000000000001','Performance A'),
 ('99ba0000-0000-4000-8000-000000000002','Performance B');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99ba0000-0000-4000-8000-000000000091','authenticated','authenticated','perf-a@example.invalid','',now(),'{}',
 '{"account_type":"public_store_customer","customer_tenant_id":"99ba0000-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='99ba0000-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role)
values('99ba0000-0000-4000-8000-000000000091','99ba0000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claim.sub','99ba0000-0000-4000-8000-000000000091',true);
select set_config('request.jwt.claims','{"sub":"99ba0000-0000-4000-8000-000000000091","role":"authenticated"}',true);

insert into public.spec_definitions(id,tenant_id,key,label,data_type,is_filterable) values
 ('99ba0000-0000-4000-8000-000000000031',null,'performance_measure','Perfmeasure','number',true),
 ('99ba0000-0000-4000-8000-000000000032','99ba0000-0000-4000-8000-000000000001','performance_measure','Perfmeasure','number',true);
insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract) values
 ('99ba0000-0000-4000-8000-000000000041','99ba0000-0000-4000-8000-000000000001','performance_active','Performance active','performance_fixture','{}'),
 ('99ba0000-0000-4000-8000-000000000042','99ba0000-0000-4000-8000-000000000001','performance_override','Performance override','performance_fixture','{}'),
 ('99ba0000-0000-4000-8000-000000000043','99ba0000-0000-4000-8000-000000000001','performance_legacy','Performance legacy','performance_fixture','{"roles":{"performance_measure":"legacy"}}'),
 ('99ba0000-0000-4000-8000-000000000044','99ba0000-0000-4000-8000-000000000002','performance_foreign','Performance foreign','performance_fixture','{}');
insert into public.spec_template_fields(template_id,spec_definition_id)
select id,'99ba0000-0000-4000-8000-000000000031' from public.spec_templates
where id in ('99ba0000-0000-4000-8000-000000000041','99ba0000-0000-4000-8000-000000000043','99ba0000-0000-4000-8000-000000000044');
insert into public.product_categories(id,tenant_id,name,full_path) values
 ('99ba0000-0000-4000-8000-000000000011','99ba0000-0000-4000-8000-000000000001','Perffixtures','Perffixtures'),
 ('99ba0000-0000-4000-8000-000000000012','99ba0000-0000-4000-8000-000000000002','Foreign fixtures','Foreign fixtures');
insert into public.category_tech_mappings(tenant_id,category_id,template_id,technical_family,status) values
 ('99ba0000-0000-4000-8000-000000000001','99ba0000-0000-4000-8000-000000000011','99ba0000-0000-4000-8000-000000000041','performance_fixture','active'),
 ('99ba0000-0000-4000-8000-000000000002','99ba0000-0000-4000-8000-000000000012','99ba0000-0000-4000-8000-000000000044','performance_fixture','active');
insert into public.products(id,tenant_id,name,sku,category_id,spec_template_id,price,cost,is_active) values
 ('99ba0000-0000-4000-8000-000000000021','99ba0000-0000-4000-8000-000000000001','Active fixture','PERF-ACTIVE','99ba0000-0000-4000-8000-000000000011',null,100,50,true),
 ('99ba0000-0000-4000-8000-000000000022','99ba0000-0000-4000-8000-000000000001','Override fixture','PERF-OVERRIDE','99ba0000-0000-4000-8000-000000000011','99ba0000-0000-4000-8000-000000000042',100,50,true),
 ('99ba0000-0000-4000-8000-000000000023','99ba0000-0000-4000-8000-000000000001','Legacy fixture','PERF-LEGACY','99ba0000-0000-4000-8000-000000000011','99ba0000-0000-4000-8000-000000000043',100,50,true),
 ('99ba0000-0000-4000-8000-000000000024','99ba0000-0000-4000-8000-000000000001','Unbound fixture','PERF-UNBOUND',null,null,100,50,true),
 ('99ba0000-0000-4000-8000-000000000025','99ba0000-0000-4000-8000-000000000002','Foreign fixture','PERF-FOREIGN','99ba0000-0000-4000-8000-000000000012',null,100,50,true);
insert into public.spec_facts(tenant_id,subject_type,subject_id,spec_definition_id,value_number,source) values
 ('99ba0000-0000-4000-8000-000000000001','product','99ba0000-0000-4000-8000-000000000021','99ba0000-0000-4000-8000-000000000031',10,'catalog'),
 ('99ba0000-0000-4000-8000-000000000001','product','99ba0000-0000-4000-8000-000000000022','99ba0000-0000-4000-8000-000000000031',777,'catalog'),
 ('99ba0000-0000-4000-8000-000000000001','product','99ba0000-0000-4000-8000-000000000023','99ba0000-0000-4000-8000-000000000031',555,'catalog'),
 ('99ba0000-0000-4000-8000-000000000001','product','99ba0000-0000-4000-8000-000000000024','99ba0000-0000-4000-8000-000000000031',666,'catalog'),
 ('99ba0000-0000-4000-8000-000000000002','product','99ba0000-0000-4000-8000-000000000025','99ba0000-0000-4000-8000-000000000031',333,'catalog'),
 ('99ba0000-0000-4000-8000-000000000001','product','99ba0000-0000-4000-8000-000000000021','99ba0000-0000-4000-8000-000000000032',888,'catalog');
insert into public.spec_facts(tenant_id,subject_type,subject_scope,subject_id,spec_definition_id,value_number,source) values
 ('99ba0000-0000-4000-8000-000000000001','product','synthetic-scope','99ba0000-0000-4000-8000-000000000021','99ba0000-0000-4000-8000-000000000031',444,'catalog');

create function pg_temp.perf_predicates(q text) returns jsonb language sql as $$
 select public.assistant_infer_technical_predicates_internal_v1('99ba0000-0000-4000-8000-000000000001',q)->'predicates'
$$;
select is(pg_temp.perf_predicates('Perfmeasure 10')->0->>'field','performance_measure','active assigned definition supplies numeric cue');
select is(pg_temp.perf_predicates('Perfmeasure 10')->0->'values','[10]'::jsonb,'numeric value is unchanged');
select is(pg_temp.perf_predicates('Perffixtures 10')->0->'values','[10]'::jsonb,'category-scoped fact inference still works without a numeric cue');
select is(pg_temp.perf_predicates('Perfmeasure 777'),'[]'::jsonb,'explicit binding supersedes category field coverage');
select is(pg_temp.perf_predicates('Perffixtures 777'),'[]'::jsonb,'out-of-template fact cannot satisfy a category-scoped numeric lookup');
select is(pg_temp.perf_predicates('Perfmeasure 555'),'[]'::jsonb,'retired roles cannot widen inferred numeric range');
select is(pg_temp.perf_predicates('Perfmeasure 666'),'[]'::jsonb,'unbound products cannot widen inferred numeric range');
select is(pg_temp.perf_predicates('Perfmeasure 333'),'[]'::jsonb,'another tenant cannot widen inferred numeric range');
select is(pg_temp.perf_predicates('Perfmeasure 888'),'[]'::jsonb,'same-key tenant definition outside template cannot widen range');
select is(pg_temp.perf_predicates('Perfmeasure 444'),'[]'::jsonb,'scoped observation cannot become an unscoped product fact');

-- Simulate unavailable historical metadata only inside this rollback fixture.
set constraints all immediate;
alter table public.spec_templates disable trigger spec_template_retirement_guard;
set constraints products_spec_template_active_fk deferred;
update public.spec_templates set is_active=false where id='99ba0000-0000-4000-8000-000000000042';
select is(pg_temp.perf_predicates('Perfmeasure 777'),'[]'::jsonb,'unavailable explicit binding does not fall back to category');
update public.spec_templates set is_active=true where id='99ba0000-0000-4000-8000-000000000042';
set constraints products_spec_template_active_fk immediate;
alter table public.spec_templates enable trigger spec_template_retirement_guard;

insert into public.spec_template_fields(template_id,spec_definition_id)
values('99ba0000-0000-4000-8000-000000000041','99ba0000-0000-4000-8000-000000000032');
select is(pg_temp.perf_predicates('Perfmeasure 10'),'[]'::jsonb,'ambiguous key does not silently prefer global definition');
select is(pg_temp.perf_predicates('Perfmeasure 888'),'[]'::jsonb,'ambiguous key does not silently prefer tenant definition');
update public.spec_definitions set is_filterable=false where id='99ba0000-0000-4000-8000-000000000032';
select is(pg_temp.perf_predicates('Perfmeasure 10'),'[]'::jsonb,'non-filterable shadow still makes the assigned key ambiguous');
delete from public.spec_template_fields where template_id='99ba0000-0000-4000-8000-000000000041' and spec_definition_id='99ba0000-0000-4000-8000-000000000032';
select is(pg_temp.perf_predicates('Perfmeasure 10')->0->'values','[10]'::jsonb,'removing metadata ambiguity restores the assigned observation');
select is((select count(*)::integer from public.spec_facts where tenant_id in ('99ba0000-0000-4000-8000-000000000001','99ba0000-0000-4000-8000-000000000002')),7,'inference preserved every active and unassigned observation');
select ok(not has_function_privilege('authenticated','public.assistant_infer_technical_predicates_internal_v1(uuid,text)','execute') and not has_function_privilege('anon','public.assistant_infer_technical_predicates_internal_v1(uuid,text)','execute'),'private tenant-parameterized reader remains inaccessible to clients');
select * from finish();
rollback;
