-- LOCAL ONLY, root wrapper execution. Reverse interleaving: writer first.
-- Two actors: primary connection holds the write; dblink publishes async.
-- Independent follow-up to the confirmed forward race. No agent DB execution.
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
select dblink_connect('row_conditions_review_publisher',format(
  'hostaddr=%s port=%s dbname=%s user=%s password=%s application_name=row_conditions_review_publisher',
  inet_server_addr(),inet_server_port(),current_database(),current_user,
  coalesce(nullif(current_setting('app.pgtap_database_password',true),''),'postgres')));

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

select dblink_exec('row_conditions_review_publisher',$publisher_setup$
  create function pg_temp.row_conditions_review_publish(p_template uuid,p_field text)
  returns jsonb language plpgsql as $publish$
  begin
    perform set_config('lock_timeout','5s',true);
    perform set_config('statement_timeout','8s',true);
    update public.spec_templates set form_contract=form_contract||jsonb_build_object('row_conditions',
      jsonb_build_object('version',1,'fields',jsonb_build_object(p_field,
        '{"allowed_when":{"detail":{"kind":"when","rows":[[{"field":"flag","operator":"eq","value_type":"boolean","value":true}]]}}}'::jsonb)))
      where id=p_template;
    set constraints all immediate;
    return jsonb_build_object('status','published');
  exception when others then
    return jsonb_build_object('status','rejected','sqlstate',sqlstate,'message',sqlerrm);
  end $publish$;
$publisher_setup$);
create temp table rc_race_publisher(pid integer);
insert into rc_race_publisher select pid from dblink('row_conditions_review_publisher',
  'select pg_backend_pid()') p(pid integer);
create temp table rc_race_reverse_results(route text,phase text,result jsonb);

-- Writer first: aggregate. All of its deferred validation is exhausted before A starts.
begin;
set local request.jwt.claims='{"sub":"c0bf0000-0000-4000-8000-000000000091","role":"authenticated"}';
set local request.jwt.claim.sub='c0bf0000-0000-4000-8000-000000000091';
set local role authenticated;
select pg_temp.row_conditions_review_try('aggregate') writer_result;
reset role;
do $written$ begin
  if not exists(select 1 from public.spec_facts where tenant_id='c0bf0000-0000-4000-8000-000000000001'
      and subject_type='product' and subject_id='c0bf0000-0000-4000-8000-000000000020') then
    raise exception 'Reverse probe prerequisite: aggregate did not create its synthetic fact';
  end if;
end $written$;
set constraints all immediate;
select dblink_send_query('row_conditions_review_publisher',
  $$select pg_temp.row_conditions_review_publish('c0bf0000-0000-4000-8000-000000000050','row_race_product_configs')$$);
do $await$ declare attempt integer; begin
  for attempt in 1..100 loop
    perform pg_stat_clear_snapshot();
    exit when dblink_is_busy('row_conditions_review_publisher')=0
      or exists(select 1 from pg_stat_activity where pid=(select pid from rc_race_publisher)
        and wait_event_type='Lock');
    perform pg_sleep(0.01);
  end loop;
end $await$;
insert into rc_race_reverse_results select 'aggregate','before_writer_commit',jsonb_build_object(
  'publisher_busy',dblink_is_busy('row_conditions_review_publisher')=1,
  'publisher_waiting_on_lock',exists(select 1 from pg_stat_activity where pid=(select pid from rc_race_publisher)
    and wait_event_type='Lock'));
commit;
insert into rc_race_reverse_results select 'aggregate','after_writer_commit',result
  from dblink_get_result('row_conditions_review_publisher') r(result jsonb);
-- Drain the async result before reuse.
select count(*) drained from dblink_get_result('row_conditions_review_publisher') r(result jsonb);

-- Writer first: aggregate_new. All of its deferred validation is exhausted before A starts.
begin;
set local request.jwt.claims='{"sub":"c0bf0000-0000-4000-8000-000000000091","role":"authenticated"}';
set local request.jwt.claim.sub='c0bf0000-0000-4000-8000-000000000091';
set local role authenticated;
select pg_temp.row_conditions_review_try('aggregate_new') writer_result;
reset role;
do $written$ begin
  if not exists(select 1 from public.spec_facts where tenant_id='c0bf0000-0000-4000-8000-000000000001'
      and subject_type='product' and subject_id='c0bf0000-0000-4000-8000-000000000021') then
    raise exception 'Reverse probe prerequisite: aggregate_new did not create its synthetic fact';
  end if;
end $written$;
set constraints all immediate;
select dblink_send_query('row_conditions_review_publisher',
  $$select pg_temp.row_conditions_review_publish('c0bf0000-0000-4000-8000-000000000052','row_race_new_configs')$$);
do $await$ declare attempt integer; begin
  for attempt in 1..100 loop
    perform pg_stat_clear_snapshot();
    exit when dblink_is_busy('row_conditions_review_publisher')=0
      or exists(select 1 from pg_stat_activity where pid=(select pid from rc_race_publisher)
        and wait_event_type='Lock');
    perform pg_sleep(0.01);
  end loop;
end $await$;
insert into rc_race_reverse_results select 'aggregate_new','before_writer_commit',jsonb_build_object(
  'publisher_busy',dblink_is_busy('row_conditions_review_publisher')=1,
  'publisher_waiting_on_lock',exists(select 1 from pg_stat_activity where pid=(select pid from rc_race_publisher)
    and wait_event_type='Lock'));
commit;
insert into rc_race_reverse_results select 'aggregate_new','after_writer_commit',result
  from dblink_get_result('row_conditions_review_publisher') r(result jsonb);
-- Drain the async result before reuse.
select count(*) drained from dblink_get_result('row_conditions_review_publisher') r(result jsonb);

-- Writer first: reference. All of its deferred validation is exhausted before A starts.
begin;
select pg_temp.row_conditions_review_try('reference') writer_result;
do $written$ begin
  if not exists(select 1 from public.product_spec_references where id='row-conditions-review-race-reference') then
    raise exception 'Reverse probe prerequisite: reference was not inserted';
  end if;
end $written$;
set constraints all immediate;
select dblink_send_query('row_conditions_review_publisher',
  $$select pg_temp.row_conditions_review_publish('c0bf0000-0000-4000-8000-000000000051','row_race_reference_configs')$$);
do $await$ declare attempt integer; begin
  for attempt in 1..100 loop
    perform pg_stat_clear_snapshot();
    exit when dblink_is_busy('row_conditions_review_publisher')=0
      or exists(select 1 from pg_stat_activity where pid=(select pid from rc_race_publisher)
        and wait_event_type='Lock');
    perform pg_sleep(0.01);
  end loop;
end $await$;
insert into rc_race_reverse_results select 'reference','before_writer_commit',jsonb_build_object(
  'publisher_busy',dblink_is_busy('row_conditions_review_publisher')=1,
  'publisher_waiting_on_lock',exists(select 1 from pg_stat_activity where pid=(select pid from rc_race_publisher)
    and wait_event_type='Lock'));
commit;
insert into rc_race_reverse_results select 'reference','after_writer_commit',result
  from dblink_get_result('row_conditions_review_publisher') r(result jsonb);
-- Drain the async result before reuse.
select count(*) drained from dblink_get_result('row_conditions_review_publisher') r(result jsonb);

select route,phase,result from rc_race_reverse_results order by route,phase;
select dblink_disconnect('row_conditions_review_publisher');
-- Correct serialization: publisher waits while the write is uncommitted;
-- after it commits publication rejects 23514 for a populated endpoint.
-- A 55P03 timeout is inconclusive here: only 23514 proves the fresh read-back.
select 1/case when count(*)=6 and bool_and(case when phase='before_writer_commit' then result->'publisher_busy'='true'::jsonb and result->'publisher_waiting_on_lock'='true'::jsonb else result->>'status'='rejected' and result->>'sqlstate'='23514' end) then 1 else 0 end publication_fresh_population_assertion from rc_race_reverse_results;
\ir row-conditions-review-concurrency-cleanup.sql
