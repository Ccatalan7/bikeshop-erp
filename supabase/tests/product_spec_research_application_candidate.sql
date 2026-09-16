begin;
set local client_min_messages=error;
-- The candidate was published as 20260916140000; on a database that already
-- has it the same assertions run against the installed objects.
select to_regprocedure('public.apply_product_spec_research_v1(uuid)') is null as research_candidate_needed \gset
\if :research_candidate_needed
\ir ../../scripts/inventory/sql/product_spec_application_candidate.sql
\endif
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
-- A reading receipt only hangs from a name_reading fact (20260831290000), and
-- readings carry their definition and vocabulary digest.
update public.spec_facts set source='name_reading' where subject_id='f1112300-0000-4000-8000-000000000020'
 and spec_definition_id='f1112300-0000-4000-8000-000000000053';
insert into public.spec_fact_readings(fact_id,tenant_id,source_text,source_digest,quote,model,definition_id,vocabulary_digest)
select id,tenant_id,'Synthetic historical evidence','synthetic-digest','historical','synthetic',
 spec_definition_id,'synthetic-vocabulary-digest'
from public.spec_facts where subject_id='f1112300-0000-4000-8000-000000000020' and spec_definition_id='f1112300-0000-4000-8000-000000000053';

set constraints all deferred;

insert into public.product_spec_research_readiness(id,tenant_id,audit_sha256,review_sha256,closed_at,enabled)
values('f1112300-0000-4000-8000-000000000081','f1112300-0000-4000-8000-000000000001',repeat('a',64),repeat('b',64),now(),false);

create function pg_temp.register_application(p_patch jsonb,p_identity jsonb default '{}') returns uuid
language plpgsql as $$
declare s jsonb; v jsonb; c jsonb; d jsonb; changes jsonb:='[]'; new_id uuid:=gen_random_uuid();
begin
 s:=public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020');
 v:=public.preview_product_spec_research_v1('f1112300-0000-4000-8000-000000000020',s->>'snapshot_sha256',p_identity,p_patch);
 for d in select jsonb_build_object('key',e.key,'definition_id',sd.id,'current','{}'::jsonb,
   'final_value',v#>array['values',e.key],'origin','research','evidence','["synthetic"]'::jsonb)
   from jsonb_each(p_patch) e join public.spec_definitions sd on sd.key=e.key loop
  changes:=changes||jsonb_build_array(d);
 end loop;
 c:=jsonb_build_object('schema_version',1,'product_id',s#>'{product,id}','tenant_id',s->'tenant_id','actor_id',s->'actor_id',
  'based_on',jsonb_build_object('snapshot_sha256',s->'snapshot_sha256','fingerprints',s->'fingerprints',
   'tenant_id',s->'tenant_id','spec_revision',s#>'{product,spec_revision}','updated_at',s#>'{product,updated_at}',
   'template_id',s#>'{editor,template_id}','contract_version',s#>'{editor,contract_version}'),
  'proposal_sha256',repeat('c',64),'identity_patch',p_identity,'values_patch',p_patch,'reference_id',v->'reference_id',
  'expected_identity',v->'identity','expected_values',v->'values','changes',changes);
 insert into public.product_spec_research_applications(id,tenant_id,actor_id,readiness_id,command_text,command_sha256,proposal,bundle_sha256)
 values(new_id,(s->>'tenant_id')::uuid,(s->>'actor_id')::uuid,'f1112300-0000-4000-8000-000000000081',c::text,
  encode(extensions.digest(c::text,'sha256'),'hex'),jsonb_build_object('product_id',s#>'{product,id}',
   'status','reviewed','researcher','codex','based_on',c->'based_on',
   'review',jsonb_build_object('by','claude','verdict','accepted','reviewed_proposal_sha256',repeat('c',64))),repeat('d',64));
 return new_id;
end $$;

create temp table application_fixture(label text primary key,value jsonb);
grant select,insert on application_fixture to authenticated;
insert into application_fixture values('before',public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020'));
insert into application_fixture select 'application',to_jsonb(pg_temp.register_application(
 '{"research_option":"02","research_rows":{"schema_version":1,"rows":[{"id":"new-row","values":{"length":"0.200000000000000001"},"sources":["https://example.invalid/synthetic"]}]}}',
 '{"model":"Reviewed","gtin":"0000123"}'));
set local role authenticated;
select is(public.get_product_spec_research_application_status_v1(
 (select (value#>>'{}')::uuid from application_fixture where label='application'))->'applied',
 'false'::jsonb,'registered command is not an applied receipt');
select is(public.get_product_spec_research_application_status_v1(
 (select (value#>>'{}')::uuid from application_fixture where label='application'))->'readiness_enabled',
 'false'::jsonb,'status reports the closed readiness gate without enabling it');
select throws_ok($$select public.apply_product_spec_research_v1((select (value#>>'{}')::uuid from application_fixture where label='application'))$$,
 '42501',null,'disabled global readiness blocks an otherwise registered command');
select throws_ok($$select public.apply_product_spec_research_v1('f1112300-0000-4000-8000-000000000099')$$,
 '42501',null,'client cannot invent an application');
select throws_ok($$update public.product_spec_research_readiness set enabled=true$$,
 '42501',null,'authenticated client cannot enable its own global readiness');
select throws_ok($$insert into public.product_spec_research_applications(id) values(gen_random_uuid())$$,
 '42501',null,'authenticated client cannot register arbitrary changes');
reset role;
update public.product_spec_research_readiness set enabled=true;
set local role authenticated;
insert into application_fixture select 'result',public.apply_product_spec_research_v1((select (value#>>'{}')::uuid from application_fixture where label='application'));
insert into application_fixture select 'after',public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020');
select is((select value#>>'{editor,values,research_option}' from application_fixture where label='after'),'02','reviewed option resolves canonical ID');
select is((select value#>>'{editor,values,research_amount}' from application_fixture where label='after'),'9007199254740993.125','unmentioned exact decimal is preserved');
select is((select value#>'{editor,values,research_flag}' from application_fixture where label='after'),'false'::jsonb,'unmentioned false is preserved');
select is((select value#>>'{editor,values,research_rows,rows,0,values,length}' from application_fixture where label='after'),
 '0.100000000000000001','existing row and exact decimal retained when appending a row');
select is((select value#>>'{editor,values,research_rows,rows,1,values,length}' from application_fixture where label='after'),
 '0.200000000000000001','new row and exact decimal survive SQL');
select is((select value#>>'{product,gtin}' from application_fixture where label='after'),'0000123','GTIN leading zero survives');
select is(public.apply_product_spec_research_v1((select (value#>>'{}')::uuid from application_fixture where label='application'))->'replayed','true'::jsonb,'same operation returns receipt');
select is(public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020'),
 (select value from application_fixture where label='after'),'retry has zero further effects');
select is(public.get_product_spec_research_application_status_v1(
 (select (value#>>'{}')::uuid from application_fixture where label='application'))->'applied',
 'true'::jsonb,'status exposes receipt availability for recovery without a second write');
reset role;
select is((select count(*) from public.product_spec_research_receipts),1::bigint,'single immutable application receipt');
select is((select before_snapshot from public.product_spec_research_receipts),
 (select value from application_fixture where label='before'),'receipt contains every prior observation and reading');
select is((select after_snapshot from public.product_spec_research_receipts),
 (select value from application_fixture where label='after'),'receipt contains complete applied postimage');
select is((select count(*) from public.spec_fact_readings r join public.spec_facts f on f.id=r.fact_id
 where f.subject_id='f1112300-0000-4000-8000-000000000020'),0::bigint,'old reading is archived, never attributed to replacement');
select is((select source from public.spec_facts where subject_id='f1112300-0000-4000-8000-000000000020'
 and spec_definition_id='f1112300-0000-4000-8000-000000000053'),'research','documentary reading is not called mechanic');
select is((select price from public.products where id='f1112300-0000-4000-8000-000000000020'),100::numeric,'price preserved');
select is((select cost from public.products where id='f1112300-0000-4000-8000-000000000020'),50::numeric,'cost preserved');
select is((select before_product_text::jsonb-array['model','gtin','spec_reference_id','spec_revision','updated_at']
 from public.product_spec_research_receipts),
 (select after_product_text::jsonb-array['model','gtin','spec_reference_id','spec_revision','updated_at']
 from public.product_spec_research_receipts),'all other product columns preserved, not only price and cost');

-- A concurrent commercial change or source receipt invalidates the full basis.
insert into application_fixture select 'stale_application',to_jsonb(pg_temp.register_application('{"research_flag":true}'));
update public.products set cost=51 where id='f1112300-0000-4000-8000-000000000020';
insert into application_fixture values('before_stale',public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020'));
set local role authenticated;
select throws_ok($$select public.apply_product_spec_research_v1((select (value#>>'{}')::uuid from application_fixture where label='stale_application'))$$,
 '40001',null,'changed commercial state invalidates research without overwriting it');
select is(public.get_product_spec_research_snapshot_v1('f1112300-0000-4000-8000-000000000020'),
 (select value from application_fixture where label='before_stale'),'failed stale operation leaves full state intact');
reset role;
select is((select count(*) from public.product_spec_research_receipts),1::bigint,'failed stale command writes no receipt');
update public.product_spec_research_readiness set enabled=false;
set local role authenticated;
select is(public.apply_product_spec_research_v1((select (value#>>'{}')::uuid from application_fixture where label='application'))->'replayed',
 'true'::jsonb,'receipt recovery survives later disabled readiness without applying anything');
reset role;
select is(has_function_privilege('anon','public.apply_product_spec_research_v1(uuid)','execute'),false,'anonymous execution denied');
select is(has_function_privilege('service_role','public.apply_product_spec_research_v1(uuid)','execute'),false,'service role cannot impersonate a researcher');
update public.product_spec_research_readiness set enabled=true;
insert into application_fixture select 'uppercase_application',to_jsonb(pg_temp.register_application('{"research_amount":"10"}'));
update public.product_spec_research_applications a set
 command_text=jsonb_set(command_text::jsonb,'{product_id}',to_jsonb(upper(command_text::jsonb->>'product_id')))::text,
 command_sha256=encode(extensions.digest(jsonb_set(command_text::jsonb,'{product_id}',
   to_jsonb(upper(command_text::jsonb->>'product_id')))::text,'sha256'),'hex'),
 proposal=jsonb_set(proposal,'{product_id}',to_jsonb(upper(proposal->>'product_id')))
where id=(select (value#>>'{}')::uuid from application_fixture where label='uppercase_application');
set local role authenticated;
insert into application_fixture select 'uppercase_result',public.apply_product_spec_research_v1(
 (select (value#>>'{}')::uuid from application_fixture where label='uppercase_application'));
reset role;
select ok(exists(select 1 from pg_locks l cross join lateral(select hashtextextended(
 'f1112300-0000-4000-8000-000000000001:spec_fact:'||'F1112300-0000-4000-8000-000000000020'::uuid::text,0) k) h
 where l.locktype='advisory' and l.pid=pg_backend_pid() and l.granted and l.objsubid=1
 and l.classid::bigint=((h.k>>32)&4294967295) and l.objid::bigint=(h.k&4294967295)),
 'actual uppercase command owns the same advisory key as the typed legacy writer');
select ok(not exists(select 1 from pg_locks l cross join lateral(select hashtextextended(
 'f1112300-0000-4000-8000-000000000001:spec_fact:F1112300-0000-4000-8000-000000000020',0) k) h
 where l.locktype='advisory' and l.pid=pg_backend_pid() and l.granted and l.objsubid=1
 and l.classid::bigint=((h.k>>32)&4294967295) and l.objid::bigint=(h.k&4294967295)),
 'uppercase application never acquires a divergent raw-text product lock');
select is((select value_number from public.spec_facts where subject_id='f1112300-0000-4000-8000-000000000020'
 and spec_definition_id='f1112300-0000-4000-8000-000000000051'),10::numeric,'numeric replacement remains exact');
update public.spec_facts set confirmed=true where subject_id='f1112300-0000-4000-8000-000000000020'
 and spec_definition_id='f1112300-0000-4000-8000-000000000052';
insert into application_fixture select 'confirmed_application',to_jsonb(pg_temp.register_application('{"research_flag":true}'));
set local role authenticated;
select throws_ok($$select public.apply_product_spec_research_v1((select (value#>>'{}')::uuid from application_fixture where label='confirmed_application'))$$,
 '23514',null,'documentary replacement cannot silently overrule physically confirmed observation');
reset role;
select is((select confirmed from public.spec_facts where subject_id='f1112300-0000-4000-8000-000000000020'
 and spec_definition_id='f1112300-0000-4000-8000-000000000052'),true,'rejected replacement preserves physical confirmation');
update public.product_spec_research_applications set proposal=proposal||
 '{"conflicts":[{"field":"research_flag","resolution":"Explicit synthetic adjudication"}]}'::jsonb
 where id=(select (value#>>'{}')::uuid from application_fixture where label='confirmed_application');
set local role authenticated;
insert into application_fixture select 'confirmed_result',public.apply_product_spec_research_v1(
 (select (value#>>'{}')::uuid from application_fixture where label='confirmed_application'));
select is(public.get_product_spec_research_receipt_v1((select (value#>>'{}')::uuid from application_fixture where label='confirmed_application'))->'result',
 (select value from application_fixture where label='confirmed_result'),'authenticated actor can recover full atomic receipt');
select throws_ok($$select public.get_product_spec_research_receipt_v1('f1112300-0000-4000-8000-000000000099')$$,
 '42501',null,'absent or foreign receipt has a nondisclosing error');
reset role;
select is((select count(*) from public.product_spec_research_receipts),3::bigint,'three actual commands and no extra receipt for rejected attempts');
select is(has_function_privilege('anon','public.get_product_spec_research_receipt_v1(uuid)','execute'),false,'anonymous receipt read denied');
select is(has_function_privilege('anon','public.get_product_spec_research_application_status_v1(uuid)','execute'),false,'anonymous application status denied');
set local role authenticated;
select throws_ok($$select public.get_product_spec_research_application_status_v1('f1112300-0000-4000-8000-000000000099')$$,
 '42501',null,'absent or foreign application status does not disclose its registration');
reset role;
select * from finish();
rollback;
