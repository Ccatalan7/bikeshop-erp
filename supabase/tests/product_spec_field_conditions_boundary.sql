-- Independent form-contract regressions. These are not mechanical fitment tests.
begin;
set local client_min_messages=error;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values('a4cc2100-0000-4000-8000-000000000001','Conditions boundary');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('a4cc2100-0000-4000-8000-000000000091','authenticated','authenticated','conditions-boundary@example.invalid','',now(),'{}',
 '{"account_type":"public_store_customer","customer_tenant_id":"a4cc2100-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='a4cc2100-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values('a4cc2100-0000-4000-8000-000000000091','a4cc2100-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"a4cc2100-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a4cc2100-0000-4000-8000-000000000091',true);
insert into public.spec_definitions(id,key,label,data_type,allowed_values) values
 ('a4cc2100-0000-4000-8000-000000000051','conditions_boundary_mode','Mode','single_select','["A","B","01","1"]'),
 ('a4cc2100-0000-4000-8000-000000000052','conditions_boundary_child','Child','single_select','["01","1"]'),
 ('a4cc2100-0000-4000-8000-000000000053','conditions_boundary_amount','Amount','number','[]'),
 ('a4cc2100-0000-4000-8000-000000000054','conditions_boundary_list','List','multi_select','["01","1"]'),
 ('a4cc2100-0000-4000-8000-000000000055','conditions_boundary_flag','Flag','boolean','[]');
insert into public.spec_templates(id,key,name,technical_family,form_contract) values
 ('a4cc2100-0000-4000-8000-000000000050','conditions_boundary','Conditions boundary','fixture',
 '{"rules_version":2,"allowed_when":{},"required_when":{},"allowed_options":{},"prerequisites":{}}');
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select 'a4cc2100-0000-4000-8000-000000000050',id,'primary',1 from public.spec_definitions where id in
 ('a4cc2100-0000-4000-8000-000000000051','a4cc2100-0000-4000-8000-000000000052','a4cc2100-0000-4000-8000-000000000053','a4cc2100-0000-4000-8000-000000000054','a4cc2100-0000-4000-8000-000000000055');
set constraints spec_template_rules_guard,spec_template_field_rules_guard,spec_definition_template_rules_guard immediate;
create function pg_temp.conditions_boundary_contract(p_extra jsonb) returns void language sql as $$
 update public.spec_templates set form_contract='{"rules_version":2,"allowed_when":{},"required_when":{},"allowed_options":{},"prerequisites":{}}'::jsonb||p_extra
 where id='a4cc2100-0000-4000-8000-000000000050'
$$;
create function pg_temp.conditions_boundary_issues(p_values jsonb) returns jsonb language sql stable as $$
 select public.spec_validate_draft_internal_v1('a4cc2100-0000-4000-8000-000000000050',p_values)
$$;
create function pg_temp.conditions_boundary_blocked(p_values jsonb) returns boolean language sql stable as $$
 select exists(select 1 from jsonb_array_elements(pg_temp.conditions_boundary_issues(p_values)) i where coalesce((i->>'blocking')::boolean,true))
$$;
select pg_temp.conditions_boundary_contract('{"allowed_when":{"conditions_boundary_child":{"kind":"when","rows":[[{"field":"conditions_boundary_amount","operator":"gte","value_type":"decimal","value":"2"}]]}},"required_when":{"conditions_boundary_child":{"kind":"always"}}}');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.conditions_boundary_issues(jsonb_build_object('conditions_boundary_amount',v))) i where i->>'code'='required_missing' and i->>'blocking'='false'),
 'ordinary number or decimal text activates the child: '||v::text) from (values('2'::jsonb),('"2"'::jsonb),('2.5'::jsonb),('"2.5"'::jsonb)) x(v);
select is(public.spec_relation_condition_internal_v1('{"field":"amount","value_type":"decimal","operator":"eq","value":"2"}','{"amount":2}'),null::boolean,'form projection does not loosen relation transport');
select throws_ok(format('select public.spec_template_condition_internal_v1(%L::jsonb,%L::jsonb)',
 jsonb_build_object('kind','when','rows',jsonb_build_array(jsonb_build_array(jsonb_build_object('field','amount','operator','eq','value_type','decimal','value',v)))),
 '{"amount":"2"}'),'22023',null,'metadata decimal rejects whitespace/comma: '||quote_literal(v)) from (values('2,5'),(' 2 '),('2 '),(E'\n2')) x(v);

-- Real authenticated aggregate: both accepted numeric wire formats emerge as
-- ordinary JSON number, then activate the same applicability/required rule.
insert into public.products(id,tenant_id,name,sku,price,cost,is_active,spec_template_id) values
 ('a4cc2100-0000-4000-8000-000000000020','a4cc2100-0000-4000-8000-000000000001','Conditions boundary','CONDITIONS-BOUNDARY',100,50,true,'a4cc2100-0000-4000-8000-000000000050');
create function pg_temp.conditions_boundary_save(p_value jsonb,p_operation text) returns jsonb language sql as $$
 select public.save_product_with_specs_v1(
 '{"id":"a4cc2100-0000-4000-8000-000000000020","name":"Conditions boundary","sku":"CONDITIONS-BOUNDARY"}',false,
 'a4cc2100-0000-4000-8000-000000000050',
 (select contract_version from public.spec_templates where id='a4cc2100-0000-4000-8000-000000000050'),p_value,
 (select spec_revision from public.products where id='a4cc2100-0000-4000-8000-000000000020'),null,p_operation,
 (select updated_at from public.products where id='a4cc2100-0000-4000-8000-000000000020'))
$$;
grant execute on function pg_temp.conditions_boundary_save(jsonb,text) to authenticated;
set local role authenticated;
select lives_ok($$select pg_temp.conditions_boundary_save('{"a4cc2100-0000-4000-8000-000000000053":{"number":2}}','conditions-number')$$,'authenticated aggregate writes numeric number');
reset role;
select is(jsonb_typeof(public.spec_active_product_values_internal_v1('a4cc2100-0000-4000-8000-000000000020','a4cc2100-0000-4000-8000-000000000050')->'conditions_boundary_amount'),'number','ordinary active projection emits JSON number');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.conditions_boundary_issues(public.spec_active_product_values_internal_v1('a4cc2100-0000-4000-8000-000000000020','a4cc2100-0000-4000-8000-000000000050'))) i where i->>'code'='required_missing' and i->>'blocking'='false'),'saved number activates the child requirement');
set local role authenticated;
select lives_ok($$select pg_temp.conditions_boundary_save('{"a4cc2100-0000-4000-8000-000000000053":{"number":"2.5"}}','conditions-number-string')$$,'authenticated aggregate writes numeric text');
reset role;
select is(public.spec_active_product_values_internal_v1('a4cc2100-0000-4000-8000-000000000020','a4cc2100-0000-4000-8000-000000000050')->'conditions_boundary_amount','2.5'::jsonb,'numeric text persists and projects as exact database number');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.conditions_boundary_issues(public.spec_active_product_values_internal_v1('a4cc2100-0000-4000-8000-000000000020','a4cc2100-0000-4000-8000-000000000050'))) i where i->>'code'='required_missing' and i->>'blocking'='false'),'saved decimal text activates child after number projection');

select throws_ok(format('select pg_temp.conditions_boundary_contract(%L::jsonb)',jsonb_build_object('rules_version',v)),'23514',null,'reject invalid version: '||v::text)
 from (values('"2"'::jsonb),('2.1'::jsonb),('null'::jsonb),('false'::jsonb),('{}'::jsonb)) x(v);
select throws_ok(format('select pg_temp.conditions_boundary_contract(%L::jsonb)',jsonb_build_object('prerequisites',jsonb_build_object('conditions_boundary_child',jsonb_build_array(v)))),
 '23514',null,'reject non-key prerequisite member: '||v::text) from (values('null'::jsonb),('1'::jsonb),('false'::jsonb),('{}'::jsonb),('""'::jsonb)) x(v);
select throws_ok($$select pg_temp.conditions_boundary_contract('{"prerequisites":{"conditions_boundary_child":["alien"]}}')$$,'23514',null,'foreign prerequisite rejected');
select throws_ok($$select pg_temp.conditions_boundary_contract('{"roles":{"conditions_boundary_mode":"legacy"},"prerequisites":{"conditions_boundary_child":["conditions_boundary_mode"]}}')$$,'23514',null,'explicit prerequisite cannot depend on retired field');
select throws_ok($$select pg_temp.conditions_boundary_contract('{"roles":{"conditions_boundary_mode":"legacy"},"allowed_when":{"conditions_boundary_child":{"kind":"when","rows":[[{"field":"conditions_boundary_mode","value_type":"token","operator":"eq","value":"A"}]]}}}')$$,'23514',null,'applicability cannot depend on retired field');
select throws_ok($$select pg_temp.conditions_boundary_contract('{"roles":{"conditions_boundary_mode":"legacy"},"required_when":{"conditions_boundary_child":{"kind":"when","rows":[[{"field":"conditions_boundary_mode","value_type":"token","operator":"eq","value":"A"}]]}}}')$$,'23514',null,'required condition cannot depend on retired field');
select throws_ok($$select pg_temp.conditions_boundary_contract('{"allowed_when":{"conditions_boundary_child":{"kind":"when","rows":[[{"field":"alien","value_type":"token","operator":"eq","value":"A"}]]}}}')$$,'23514',null,'foreign applicability dependency rejected');
select throws_ok($$select pg_temp.conditions_boundary_contract('{"prerequisites":{"conditions_boundary_mode":["conditions_boundary_child"],"conditions_boundary_child":["conditions_boundary_mode"]}}')$$,'23514',null,'direct prerequisite cycle rejected');
select throws_ok($$select pg_temp.conditions_boundary_contract('{"allowed_when":{"conditions_boundary_mode":{"kind":"when","rows":[[{"field":"conditions_boundary_child","value_type":"token","operator":"eq","value":"01"}]]},"conditions_boundary_child":{"kind":"when","rows":[[{"field":"conditions_boundary_mode","value_type":"token","operator":"eq","value":"A"}]]}}}')$$,'23514',null,'cycle through two applicability expressions rejected');
select pg_temp.conditions_boundary_contract('{"allowed_when":{"conditions_boundary_child":{"kind":"when","rows":[[{"field":"conditions_boundary_mode","operator":"eq","value_type":"token","value":"A"}]]}}}');
select throws_ok($$update public.spec_definitions set key='conditions_boundary_renamed_mode' where id='a4cc2100-0000-4000-8000-000000000051'$$,'23514',null,'key-only edit cannot strand dependency');
select throws_ok($$update public.spec_definitions set data_type='number' where id='a4cc2100-0000-4000-8000-000000000051'$$,'23514',null,'upstream type edit cannot reinterpret token condition');
select throws_ok($$update public.spec_definitions set allowed_values='["B","01","1"]' where id='a4cc2100-0000-4000-8000-000000000051'$$,'23514',null,'upstream domain edit cannot remove the compared option');
select throws_ok($$delete from public.spec_template_fields where template_id='a4cc2100-0000-4000-8000-000000000050' and spec_definition_id='a4cc2100-0000-4000-8000-000000000051'$$,'23514',null,'binding deletion cannot strand dependency');
select lives_ok($$update public.spec_definitions set label='Mode reviewed' where id='a4cc2100-0000-4000-8000-000000000051'$$,'label change preserves valid conditions');

-- Deferred validation allows an internally consistent atomic metadata edit.
set constraints spec_template_rules_guard,spec_template_field_rules_guard,spec_definition_template_rules_guard deferred;
update public.spec_definitions set key='conditions_boundary_renamed_mode' where id='a4cc2100-0000-4000-8000-000000000051';
update public.spec_templates set form_contract=replace(form_contract::text,'conditions_boundary_mode','conditions_boundary_renamed_mode')::jsonb where id='a4cc2100-0000-4000-8000-000000000050';
select lives_ok($$set constraints spec_template_rules_guard,spec_template_field_rules_guard,spec_definition_template_rules_guard immediate$$,'key and condition can be updated atomically');
set constraints spec_template_rules_guard,spec_template_field_rules_guard,spec_definition_template_rules_guard deferred;
update public.spec_definitions set key='conditions_boundary_mode' where id='a4cc2100-0000-4000-8000-000000000051';
update public.spec_templates set form_contract=replace(form_contract::text,'conditions_boundary_renamed_mode','conditions_boundary_mode')::jsonb where id='a4cc2100-0000-4000-8000-000000000050';
set constraints spec_template_rules_guard,spec_template_field_rules_guard,spec_definition_template_rules_guard immediate;
select pg_temp.conditions_boundary_contract('{"allowed_when":{"conditions_boundary_child":{"kind":"always"}},"required_when":{"conditions_boundary_child":{"kind":"always"}}}');
update public.spec_template_fields set visibility_rules='[{"field":"conditions_boundary_mode","operator":"eq","value":"A"}]' where template_id='a4cc2100-0000-4000-8000-000000000050' and spec_definition_id='a4cc2100-0000-4000-8000-000000000052';
select is(pg_temp.conditions_boundary_blocked('{"conditions_boundary_mode":"B","conditions_boundary_child":"01"}'),true,'inherited visibility blocks contradiction even with new always');
select is(pg_temp.conditions_boundary_issues('{"conditions_boundary_mode":"B"}'),'[]'::jsonb,'hidden child is not required by new always');
select is(pg_temp.conditions_boundary_issues('{}'),'[]'::jsonb,'unknown inherited visibility does not require absent child');
select is(pg_temp.conditions_boundary_blocked('{"conditions_boundary_child":"01"}'),false,'unknown inherited visibility remains nonblocking');
select is(pg_temp.conditions_boundary_blocked('{"conditions_boundary_mode":"A","conditions_boundary_child":"01"}'),false,'both applicability guards can hold');
select throws_ok($$select pg_temp.conditions_boundary_contract('{"allowed_when":{"conditions_boundary_mode":{"kind":"when","rows":[[{"field":"conditions_boundary_child","operator":"eq","value_type":"token","value":"01"}]]}}}')$$,'23514',null,'cycle crossing new and inherited visibility is rejected');
select pg_temp.conditions_boundary_contract('{}');
select throws_ok($$update public.spec_template_fields set visibility_rules='[{"field":"alien","operator":"eq","value":"A"}]' where template_id='a4cc2100-0000-4000-8000-000000000050' and spec_definition_id='a4cc2100-0000-4000-8000-000000000052'$$,'23514',null,'inherited visibility cannot depend on foreign field in v2');
-- Restore the valid fixture even on a failing guard so later checks remain independent.
update public.spec_template_fields set visibility_rules='[]',constraint_rules='[{"field":"conditions_boundary_mode","operator":"eq","value":"A","allow":["01"]}]' where template_id='a4cc2100-0000-4000-8000-000000000050' and spec_definition_id='a4cc2100-0000-4000-8000-000000000052';
select pg_temp.conditions_boundary_contract('{"allowed_options":{"conditions_boundary_child":["01"]}}');
select is(pg_temp.conditions_boundary_blocked('{"conditions_boundary_mode":"A","conditions_boundary_child":"01"}'),false,'legacy allow keeps exact option01 in v2 intersection');
select is(pg_temp.conditions_boundary_blocked('{"conditions_boundary_mode":"A","conditions_boundary_child":"1"}'),true,'legacy allow does not equate option1 and option01');
update public.spec_template_fields set constraint_rules='[]' where template_id='a4cc2100-0000-4000-8000-000000000050';
select pg_temp.conditions_boundary_contract('{"allowed_options":{"conditions_boundary_flag":["true"]}}');
select is(pg_temp.conditions_boundary_blocked('{"conditions_boundary_flag":true}'),false,'explicit boolean true option is accepted');
select is(pg_temp.conditions_boundary_blocked('{"conditions_boundary_flag":false}'),true,'boolean false is a real disallowed answer');
select is(pg_temp.conditions_boundary_blocked('{"conditions_boundary_flag":"true"}'),true,'string true cannot masquerade as bool');
select is(pg_temp.conditions_boundary_blocked('{"conditions_boundary_child":1}'),true,'single select rejects numeric option');
select is(pg_temp.conditions_boundary_blocked('{"conditions_boundary_list":[1]}'),true,'multi select rejects numeric member');
select is(pg_temp.conditions_boundary_blocked('{"conditions_boundary_child":"01","conditions_boundary_list":["01","1"]}'),false,'literal option strings remain valid');
select is(pg_temp.conditions_boundary_issues('{"alien":"A"}'),'[]'::jsonb,'foreign values cannot alter active draft validation');
select * from finish();
rollback;
