-- LOCAL ONLY. Root executes via scripts/db/query.sh local --file <this file>.
-- Two connections, production functions and disposable c0bf... fixtures.
-- No DB execution was performed by the review agent.
-- This commits a baseline so B can see it, then cleans those exact IDs.
-- If interrupted, run row-conditions-review-concurrency-cleanup.sql locally.
-- dblink must already be installed; its schema is discovered, not assumed.
set client_min_messages=warning;
create temp table rc_race_extension(schema_name text);
insert into rc_race_extension select n.nspname
  from pg_extension e join pg_namespace n on n.oid=e.extnamespace
  where e.extname='dblink';
do $preflight$ begin
  if not exists(select 1 from rc_race_extension) then
    raise exception 'Local probe prerequisite: dblink is not installed';
  end if;
  if exists(select 1 from public.tenants where id='c0bf0000-0000-4000-8000-000000000001') then
    raise exception 'Prior c0bf concurrency fixture remains; inspect and run exact cleanup first';
  end if;
end $preflight$;
select set_config('search_path',format('public,%I,pg_temp',schema_name),false) from rc_race_extension;

begin;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values
  ('c0bf0000-0000-4000-8000-000000000001','Row conditions concurrency fixture');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('c0bf0000-0000-4000-8000-000000000091','authenticated','authenticated',
  'row-concurrency-review@example.invalid','',now(),'{}',
  '{"account_type":"public_store_customer","customer_tenant_id":"c0bf0000-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='c0bf0000-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values
  ('c0bf0000-0000-4000-8000-000000000091','c0bf0000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"c0bf0000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','c0bf0000-0000-4000-8000-000000000091',true);
insert into public.spec_definitions(id,key,label,data_type,validation_rules)
select id::uuid,key,key,'json',
  '{"rows_schema":{"version":1,"columns":[{"key":"flag","label":"Prerequisite","type":"boolean"},{"key":"detail","label":"Dependent detail","type":"text"}]}}'::jsonb
from (values
  ('c0bf0000-0000-4000-8000-000000000011','row_race_product_configs'),
  ('c0bf0000-0000-4000-8000-000000000012','row_race_reference_configs'),
  ('c0bf0000-0000-4000-8000-000000000013','row_race_new_configs')) defs(id,key);
insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract)
select id::uuid,'c0bf0000-0000-4000-8000-000000000001',key,key,'row_race',
  '{"rules_version":2,"allowed_when":{},"required_when":{},"allowed_options":{},"prerequisites":{}}'::jsonb
    ||jsonb_build_object('roles',jsonb_build_object(field,'measurement'))
from (values
  ('c0bf0000-0000-4000-8000-000000000050','row_race_product_template','row_race_product_configs'),
  ('c0bf0000-0000-4000-8000-000000000051','row_race_reference_template','row_race_reference_configs'),
  ('c0bf0000-0000-4000-8000-000000000052','row_race_new_template','row_race_new_configs')) t(id,key,field);
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
values
  ('c0bf0000-0000-4000-8000-000000000050','c0bf0000-0000-4000-8000-000000000011','measurement',1),
  ('c0bf0000-0000-4000-8000-000000000051','c0bf0000-0000-4000-8000-000000000012','measurement',1),
  ('c0bf0000-0000-4000-8000-000000000052','c0bf0000-0000-4000-8000-000000000013','measurement',1);
insert into public.product_categories(id,tenant_id,name,full_path) values
  ('c0bf0000-0000-4000-8000-000000000003','c0bf0000-0000-4000-8000-000000000001','Row race new category','Row race new category');
insert into public.category_tech_mappings(tenant_id,category_id,technical_family,template_id,status) values
  ('c0bf0000-0000-4000-8000-000000000001','c0bf0000-0000-4000-8000-000000000003','row_race','c0bf0000-0000-4000-8000-000000000052','active');
insert into public.products(id,tenant_id,name,sku,price,cost,is_active,spec_template_id)
values('c0bf0000-0000-4000-8000-000000000020','c0bf0000-0000-4000-8000-000000000001',
  'Row concurrency fixture','ROW-RACE-REVIEW',100,50,true,'c0bf0000-0000-4000-8000-000000000050');
set constraints all immediate;
commit;

-- Credentials stay inside the server-side connection expression and are never
-- selected. This is the same local dblink transport used by repository tests.
select dblink_connect('row_conditions_review_b',format(
  'hostaddr=%s port=%s dbname=%s user=%s password=%s application_name=row_conditions_review_b',
  inet_server_addr(),inet_server_port(),current_database(),current_user,
  coalesce(nullif(current_setting('app.pgtap_database_password',true),''),'postgres')));
select dblink_exec('row_conditions_review_b',$remote_setup$
  create function pg_temp.row_conditions_review_try(p_route text)
  returns jsonb language plpgsql as $command$
  declare result jsonb;
  begin
    if p_route='aggregate' then
      result:=public.save_product_with_specs_v1(
        '{"id":"c0bf0000-0000-4000-8000-000000000020","name":"Row concurrency fixture","sku":"ROW-RACE-REVIEW"}',false,
        'c0bf0000-0000-4000-8000-000000000050',
        (select contract_version from public.spec_templates where id='c0bf0000-0000-4000-8000-000000000050'),
        '{"c0bf0000-0000-4000-8000-000000000011":{"rows":{"schema_version":1,"rows":[{"id":"a","values":{"flag":false,"detail":"Observed under prior contract"},"sources":["https://example.test/row-race"]}]}}}',
        (select spec_revision from public.products where id='c0bf0000-0000-4000-8000-000000000020'),
        null,'row-conditions-review-race-save',
        (select updated_at from public.products where id='c0bf0000-0000-4000-8000-000000000020'));
    elsif p_route='aggregate_new' then
      result:=public.save_product_with_specs_v1(
        '{"id":"c0bf0000-0000-4000-8000-000000000021","name":"New row concurrency fixture","sku":"ROW-RACE-NEW-REVIEW","category_id":"c0bf0000-0000-4000-8000-000000000003","price":100,"cost":50,"is_active":true}',true,
        'c0bf0000-0000-4000-8000-000000000052',
        (select contract_version from public.spec_templates where id='c0bf0000-0000-4000-8000-000000000052'),
        '{"c0bf0000-0000-4000-8000-000000000013":{"rows":{"schema_version":1,"rows":[{"id":"a","values":{"flag":false,"detail":"Observed under prior contract"},"sources":["https://example.test/row-race"]}]}}}',
        null,null,'row-conditions-review-race-new-save',null);
    elsif p_route='reference' then
      insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
      values('row-conditions-review-race-reference','row_race','Fixture','Race','Concurrent reference',
        '{"c0bf0000-0000-4000-8000-000000000012":{"rows":{"schema_version":1,"rows":[{"id":"a","values":{"flag":false,"detail":"Observed under prior contract"},"sources":["https://example.test/row-race"]}]}}}',
        '["https://example.test/row-race"]','2026-09-07');
    else
      raise exception 'Unknown synthetic route';
    end if;
    set constraints all immediate;
    return jsonb_build_object('status','written','route',p_route);
  exception when others then
    return jsonb_build_object('status','rejected','route',p_route,'sqlstate',sqlstate,'message',sqlerrm);
  end $command$;
  grant execute on function pg_temp.row_conditions_review_try(text) to authenticated;
$remote_setup$);

create temp table rc_race_results(route text,result jsonb);
create function pg_temp.row_conditions_review_contract(p_field text)
returns jsonb language sql immutable as $contract$
  select jsonb_build_object('version',1,'fields',jsonb_build_object(p_field,
    '{"allowed_when":{"detail":{"kind":"when","rows":[[{"field":"flag","operator":"eq","value_type":"boolean","value":true}]]}}}'::jsonb))
$contract$;

-- Schedule P: A publishes and exhausts deferred checks while the endpoint is
-- empty. B is an authenticated aggregate writer of an existing product.
begin;
update public.spec_templates
  set form_contract=form_contract||jsonb_build_object('row_conditions',pg_temp.row_conditions_review_contract('row_race_product_configs'))
  where id='c0bf0000-0000-4000-8000-000000000050';
set constraints all immediate;
select dblink_exec('row_conditions_review_b',$begin_b$
  begin;
  set local lock_timeout='750ms';
  set local statement_timeout='4s';
  set local request.jwt.claims='{"sub":"c0bf0000-0000-4000-8000-000000000091","role":"authenticated"}';
  set local request.jwt.claim.sub='c0bf0000-0000-4000-8000-000000000091';
  set local role authenticated;
$begin_b$);
insert into rc_race_results
  select 'aggregate',result from dblink('row_conditions_review_b',
    $$select pg_temp.row_conditions_review_try('aggregate')$$) r(result jsonb);
select dblink_exec('row_conditions_review_b','commit');
commit;

select 'P_after_both_commit' probe,r.result,
  (select count(*) from public.spec_facts where subject_type='product'
    and subject_id='c0bf0000-0000-4000-8000-000000000020') facts,
  public.spec_validate_draft_internal_v1('c0bf0000-0000-4000-8000-000000000050',
    '{"row_race_product_configs":{"schema_version":1,"rows":[{"id":"a","values":{"flag":false,"detail":"Observed under prior contract"},"sources":["https://example.test/row-race"]}]}}') issues
  from rc_race_results r where route='aggregate';

-- Schedule N: there is no preexisting product row to lock indirectly when A
-- refreshes bindings. A private fixture category resolves the new template.
begin;
update public.spec_templates
  set form_contract=form_contract||jsonb_build_object('row_conditions',pg_temp.row_conditions_review_contract('row_race_new_configs'))
  where id='c0bf0000-0000-4000-8000-000000000052';
set constraints all immediate;
select dblink_exec('row_conditions_review_b',$begin_new$
  begin;
  set local lock_timeout='750ms';
  set local statement_timeout='4s';
  set local request.jwt.claims='{"sub":"c0bf0000-0000-4000-8000-000000000091","role":"authenticated"}';
  set local request.jwt.claim.sub='c0bf0000-0000-4000-8000-000000000091';
  set local role authenticated;
$begin_new$);
insert into rc_race_results
  select 'aggregate_new',result from dblink('row_conditions_review_b',
    $$select pg_temp.row_conditions_review_try('aggregate_new')$$) r(result jsonb);
select dblink_exec('row_conditions_review_b','commit');
commit;
select 'N_after_both_commit' probe,r.result,
  exists(select 1 from public.products where id='c0bf0000-0000-4000-8000-000000000021') product_present,
  (select count(*) from public.spec_facts where subject_type='product'
    and subject_id='c0bf0000-0000-4000-8000-000000000021') facts,
  public.spec_validate_draft_internal_v1('c0bf0000-0000-4000-8000-000000000052',
    '{"row_race_new_configs":{"schema_version":1,"rows":[{"id":"a","values":{"flag":false,"detail":"Observed under prior contract"},"sources":["https://example.test/row-race"]}]}}') issues
  from rc_race_results r where route='aggregate_new';

-- Schedule R: reference guards take definition FOR SHARE. Template publication
-- needs to serialize with this independent path as well as the aggregate RPC.
begin;
update public.spec_templates
  set form_contract=form_contract||jsonb_build_object('row_conditions',pg_temp.row_conditions_review_contract('row_race_reference_configs'))
  where id='c0bf0000-0000-4000-8000-000000000051';
set constraints all immediate;
select dblink_exec('row_conditions_review_b',$begin_ref$
  begin;
  set local lock_timeout='750ms';
  set local statement_timeout='4s';
$begin_ref$);
insert into rc_race_results
  select 'reference',result from dblink('row_conditions_review_b',
    $$select pg_temp.row_conditions_review_try('reference')$$) r(result jsonb);
select dblink_exec('row_conditions_review_b','commit');
commit;
select 'R_after_both_commit' probe,r.result,
  exists(select 1 from public.product_spec_references where id='row-conditions-review-race-reference') reference_present,
  (select form_contract ? 'row_conditions' from public.spec_templates
    where id='c0bf0000-0000-4000-8000-000000000051') conditions_published
  from rc_race_results r where route='reference';
select dblink_disconnect('row_conditions_review_b');

-- Expected vulnerable result: P or N written + facts=1 + blocking applicability,
-- R written + reference_present=true + conditions_published=true.
-- Expected serialization result: each B rejects with lock_timeout 55P03 while
-- A owns publication. This bounded probe never waits indefinitely for A.
select 1/case when count(*)=3 and bool_and(result->>'status'='rejected' and result->>'sqlstate'='55P03') then 1 else 0 end publication_serialization_assertion from rc_race_results;
\ir row-conditions-review-concurrency-cleanup.sql
