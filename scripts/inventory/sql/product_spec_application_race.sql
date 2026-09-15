-- LOCAL ONLY. Requires the roundtrip owner's committed synthetic seed,
-- registered command and dblink. :application_id is bound by that owner.
set client_min_messages=warning;
select set_config('search_path',format('public,%I,pg_temp',n.nspname),false)
 from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='dblink';
create temp table research_race_results(route text,result jsonb);
select dblink_connect('research_application_b',format(
 'hostaddr=%s port=%s dbname=%s user=%s password=%s application_name=research_application_b',
 inet_server_addr(),inet_server_port(),current_database(),current_user,
 coalesce(nullif(current_setting('app.pgtap_database_password',true),''),'postgres')));
select dblink_exec('research_application_b',$remote_setup$
 create function pg_temp.research_try(p_route text,p_id uuid) returns jsonb language plpgsql as $body$
 declare v_result jsonb;
 begin
  if p_route='apply' then
   v_result:=public.apply_product_spec_research_v1(p_id);
  else
   v_result:=public.save_product_with_specs_v1(
    '{"id":"f1112300-0000-4000-8000-000000000020","name":"Research read","sku":"RESEARCH-READ"}',false,
    'f1112300-0000-4000-8000-000000000050',
    (select contract_version from public.spec_templates where id='f1112300-0000-4000-8000-000000000050'),
    '{"f1112300-0000-4000-8000-000000000052":{"boolean":true}}',
    (select spec_revision from public.products where id='f1112300-0000-4000-8000-000000000020'),
    null,'research-legacy-contender',
    (select updated_at from public.products where id='f1112300-0000-4000-8000-000000000020'));
  end if;
  return jsonb_build_object('status','written','result',v_result);
 exception when others then
  return jsonb_build_object('status','rejected','sqlstate',sqlstate);
 end $body$;
$remote_setup$);
select dblink_exec('research_application_b',$remote_identity$
 set lock_timeout='750ms'; set statement_timeout='4s';
 set request.jwt.claims='{"sub":"f1112300-0000-4000-8000-000000000091","role":"authenticated"}';
 set request.jwt.claim.sub='f1112300-0000-4000-8000-000000000091';
 set role authenticated;
$remote_identity$);

-- A applies, holding the actual application + product/fact locks. B attempts
-- both a legacy aggregate save and the same registered research command.
begin;
set local request.jwt.claims='{"sub":"f1112300-0000-4000-8000-000000000091","role":"authenticated"}';
set local request.jwt.claim.sub='f1112300-0000-4000-8000-000000000091';
set local role authenticated;
select public.apply_product_spec_research_v1(:application_id::uuid);
reset role;
create temp table held_application_results as
 select 'legacy_after_application'::text route,result from dblink('research_application_b',
  format('select pg_temp.research_try(''legacy'',%L::uuid)',:application_id)) r(result jsonb)
 union all
 select 'duplicate_application',result from dblink('research_application_b',
  format('select pg_temp.research_try(''apply'',%L::uuid)',:application_id)) r(result jsonb);
-- Persist only the diagnostic via psql variables across A's rollback.
select result::text as legacy_result from held_application_results where route='legacy_after_application' \gset
select result::text as duplicate_result from held_application_results where route='duplicate_application' \gset
rollback;
insert into research_race_results values('legacy_after_application',:'legacy_result'::jsonb),
 ('duplicate_application',:'duplicate_result'::jsonb);

-- Reverse order: A's real legacy writer owns the same product. B cannot apply
-- research against the preimage it saw before that save.
begin;
set local request.jwt.claims='{"sub":"f1112300-0000-4000-8000-000000000091","role":"authenticated"}';
set local request.jwt.claim.sub='f1112300-0000-4000-8000-000000000091';
set local role authenticated;
select public.save_product_with_specs_v1(
 '{"id":"f1112300-0000-4000-8000-000000000020","name":"Research read","sku":"RESEARCH-READ"}',false,
 'f1112300-0000-4000-8000-000000000050',
 (select contract_version from public.spec_templates where id='f1112300-0000-4000-8000-000000000050'),
 '{"f1112300-0000-4000-8000-000000000052":{"boolean":true}}',
 (select spec_revision from public.products where id='f1112300-0000-4000-8000-000000000020'),null,
 'research-legacy-owner',
 (select updated_at from public.products where id='f1112300-0000-4000-8000-000000000020'));
reset role;
select result::text as reverse_result from dblink('research_application_b',
 format('select pg_temp.research_try(''apply'',%L::uuid)',:application_id)) r(result jsonb) \gset
rollback;
insert into research_race_results values('application_after_legacy',:'reverse_result'::jsonb);
select dblink_disconnect('research_application_b');
select 1/case when count(*)=3 and bool_and(result->>'status'='rejected' and result->>'sqlstate'='55P03')
 then 1 else 0 end as both_transaction_orders_serialize from research_race_results;
select 1/case when not exists(select 1 from public.product_spec_research_receipts)
 and not exists(select 1 from public.spec_facts where subject_id='f1112300-0000-4000-8000-000000000020'
   and source='research') then 1 else 0 end as probe_rollbacks_preserved_seed;
select * from research_race_results order by route;
