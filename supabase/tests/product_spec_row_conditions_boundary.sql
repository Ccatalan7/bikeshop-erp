-- Independent synthetic boundaries. Run only locally through the root owner.
-- This is supplemental to product_spec_row_conditions.sql, not OEM evidence.
begin;
set local client_min_messages=error;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();

select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name)
values('c0bd0000-0000-4000-8000-000000000001','Independent row boundary');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('c0bd0000-0000-4000-8000-000000000091','authenticated','authenticated',
  'independent-row-boundary@example.invalid','',now(),'{}',
  '{"account_type":"public_store_customer","customer_tenant_id":"c0bd0000-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='c0bd0000-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role)
values('c0bd0000-0000-4000-8000-000000000091','c0bd0000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"c0bd0000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','c0bd0000-0000-4000-8000-000000000091',true);

create function pg_temp.boundary_when(p_field text,p_type text,p_value jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object('kind','when','rows',jsonb_build_array(jsonb_build_array(
    jsonb_build_object('field',p_field,'operator','eq','value_type',p_type,'value',p_value))))
$$;
create function pg_temp.boundary_contract(p_rules jsonb)
returns jsonb language sql immutable as $$
  select '{"rules_version":2,"allowed_when":{},"required_when":{},"allowed_options":{},"prerequisites":{},"roles":{"row_boundary_configs":"measurement"}}'::jsonb
    ||jsonb_build_object('row_conditions',jsonb_build_object('version',1,'fields',jsonb_build_object('row_boundary_configs',p_rules)))
$$;
create function pg_temp.boundary_values(p_cells jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object('row_boundary_configs',jsonb_build_object('schema_version',1,'rows',jsonb_build_array(
    jsonb_build_object('id','a','values',p_cells,'sources','["https://example.test/row-a"]'::jsonb))))
$$;
insert into public.spec_definitions(id,key,label,data_type,validation_rules)
values('c0bd0000-0000-4000-8000-000000000011','row_boundary_configs','Independent row boundary','json',
  '{"rows_schema":{"version":1,"columns":[
    {"key":"fixed","label":"Static required","type":"token","required":true,"allowed_values":["record"]},
    {"key":"kind","label":"Open kind","type":"token"},
    {"key":"flag","label":"Prerequisite","type":"boolean"},
    {"key":"code","label":"Literal code","type":"token","allowed_values":["01","1"]},
    {"key":"quantity","label":"Exact quantity","type":"decimal"},
    {"key":"detail","label":"Dependent detail","type":"text"},
    {"key":"ref_id","label":"Member reference","type":"token"}
  ]}}');
insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract)
values('c0bd0000-0000-4000-8000-000000000050','c0bd0000-0000-4000-8000-000000000001',
  'row_boundary_template','Independent row boundary','row_boundary',
  pg_temp.boundary_contract(jsonb_build_object(
    'allowed_when',jsonb_build_object('detail',pg_temp.boundary_when('flag','boolean','true')),
    'required_when',jsonb_build_object('detail',pg_temp.boundary_when('flag','boolean','true'),
      'fixed','{"kind":"never"}'::jsonb,'kind',pg_temp.boundary_when('code','token','"01"')),
    'allowed_options','{"kind":["A","B"]}'::jsonb)));
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
values('c0bd0000-0000-4000-8000-000000000050','c0bd0000-0000-4000-8000-000000000011','measurement',1);
set constraints all immediate;

create function pg_temp.boundary_issues(p_cells jsonb)
returns jsonb language sql stable as $$
  select public.spec_validate_draft_internal_v1('c0bd0000-0000-4000-8000-000000000050',pg_temp.boundary_values(p_cells))
$$;
select ok(exists(select 1 from jsonb_array_elements(pg_temp.boundary_issues('{"kind":"A"}')) i
  where i->>'code'='row_incomplete' and i->'blocking'='false'::jsonb),
  'required_when never cannot negate static schema completeness');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.boundary_issues('{"fixed":"record","code":"01"}')) i
  where i->>'code'='row_required_missing' and i->>'column'='kind'),
  'literal 01 requires the dependent kind');
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.boundary_issues('{"fixed":"record","code":"1"}')) i
  where i->>'code'='row_required_missing' and i->>'column'='kind'),
  'literal 1 does not satisfy a predicate for 01');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.boundary_issues('{"fixed":"record","flag":false,"detail":"Kept"}')) i
  where i->>'code'='row_field_applicability' and i->'blocking'='true'::jsonb),
  'false is a known contradiction, not an unknown prerequisite');
select ok(exists(select 1 from jsonb_array_elements(public.spec_validate_draft_internal_v1(
  'c0bd0000-0000-4000-8000-000000000050',pg_temp.boundary_values('{"fixed":"record","detail":"Kept"}')||'{"flag":true}')) i
  where i->>'code'='row_prerequisite' and i->'blocking'='false'::jsonb),
  'same named top-level input cannot satisfy a row prerequisite');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.boundary_issues('{"fixed":"record","kind":"C"}')) i
  where i->>'code'='row_option' and i->'blocking'='true'::jsonb),
  'template options narrow an otherwise open token');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.boundary_issues(
  '{"fixed":"record","quantity":9007199254740993,"detail":"Kept"}')) i
  where i->>'code'='row_shape' and i->'blocking'='true'::jsonb),
  'numeric JSON cells never enter exact decimal row comparison');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.boundary_issues(
  '{"fixed":"record","quantity":"1,5","detail":"Kept"}')) i
  where i->>'code'='row_shape' and i->'blocking'='true'::jsonb),
  'wire rows require decimal text; locale conversion belongs to the editor');

select throws_ok($$update public.spec_definitions
  set validation_rules=jsonb_set(validation_rules,'{rows_schema,columns,2,type}','"token"')
  where id='c0bd0000-0000-4000-8000-000000000011'$$,'23514',null,
  'empty definition cannot change the type of a predicate input');
select throws_ok($$update public.spec_definitions
  set validation_rules=jsonb_set(validation_rules,'{rows_schema,columns,3,allowed_values}','["1"]')
  where id='c0bd0000-0000-4000-8000-000000000011'$$,'23514',null,
  'empty definition cannot remove a literal consumed by a predicate');
select throws_ok($$update public.spec_definitions
  set validation_rules=jsonb_set(validation_rules,'{rows_schema,columns,5,key}','"renamed_detail"')
  where id='c0bd0000-0000-4000-8000-000000000011'$$,'23514',null,
  'empty definition cannot rename a condition target silently');
select throws_ok($$update public.spec_templates
  set form_contract=jsonb_set(form_contract,'{roles,row_boundary_configs}','"legacy"')
  where id='c0bd0000-0000-4000-8000-000000000050'$$,'23514',null,
  'a row condition cannot bind a legacy field');
select throws_ok($$delete from public.spec_template_fields
  where template_id='c0bd0000-0000-4000-8000-000000000050'
    and spec_definition_id='c0bd0000-0000-4000-8000-000000000011'$$,'23514',null,
  'removing an empty field cannot strand its row conditions');
select throws_ok($$update public.spec_templates
  set form_contract=jsonb_set(form_contract,'{row_conditions,fields,row_boundary_configs,allowed_when,fixed}','{"kind":"never"}')
  where id='c0bd0000-0000-4000-8000-000000000050'$$,'23514',null,
  'an always required schema cell cannot become conditionally inapplicable');

-- A reference is already population even without an adopting product.
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('independent-row-boundary-reference','row_boundary','Fixture','Reference','Independent row reference',
  jsonb_build_object('c0bd0000-0000-4000-8000-000000000011',jsonb_build_object('rows',
    pg_temp.boundary_values('{"fixed":"record","kind":"A","flag":true,"detail":"Observed"}')->'row_boundary_configs')),
  '["https://example.test/row-a"]','2026-09-07');
create temp table boundary_reference_before as
  select md5(to_jsonb(r)::text) digest from public.product_spec_references r
  where id='independent-row-boundary-reference';
select is((select count(*) from public.spec_facts
  where spec_definition_id='c0bd0000-0000-4000-8000-000000000011'),0::bigint,
  'publication guard fixture has a reference but no facts');
select throws_ok($$update public.spec_templates
  set form_contract=jsonb_set(form_contract,'{row_conditions,fields,row_boundary_configs,allowed_options,kind}','["A"]')
  where id='c0bd0000-0000-4000-8000-000000000050'$$,'23514',null,
  'reference-only population prevents an in-place condition change');
select throws_ok($$update public.spec_templates set form_contract=form_contract-'row_conditions'
  where id='c0bd0000-0000-4000-8000-000000000050'$$,'23514',null,
  'reference-only population also prevents silently removing conditions');
select throws_ok($$update public.spec_definitions
  set validation_rules=jsonb_set(validation_rules,'{rows_schema,columns,4,unit}','"mm"')
  where id='c0bd0000-0000-4000-8000-000000000011'$$,'23514',null,
  'reference-only population preserves the row schema meaning');
select lives_ok($$update public.spec_templates set name='Renamed fixture'
  where id='c0bd0000-0000-4000-8000-000000000050'$$,
  'a display name does not reinterpret existing row conditions');
select is((select md5(to_jsonb(r)::text) from public.product_spec_references r
  where id='independent-row-boundary-reference'),(select digest from boundary_reference_before),
  'rejected metadata writes preserve the complete reference');

-- A reference carries independent observations. Matching it must not bypass
-- the destination product template's additional conditions when adopted.
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('independent-row-boundary-conflict','row_boundary','Fixture','Conflict','Conditional conflict reference',
  jsonb_build_object('c0bd0000-0000-4000-8000-000000000011',jsonb_build_object('rows',
    pg_temp.boundary_values('{"fixed":"record","kind":"A","flag":false,"detail":"Observed"}')->'row_boundary_configs')),
  '["https://example.test/row-a"]','2026-09-07');
select ok(exists(select 1 from jsonb_array_elements(public.spec_validate_draft_internal_v1(
  'c0bd0000-0000-4000-8000-000000000050',
  pg_temp.boundary_values('{"fixed":"record","kind":"A","flag":false,"detail":"Observed"}'),
  'independent-row-boundary-conflict','Fixture','Conflict','')) i
  where i->>'code'='row_field_applicability' and i->'blocking'='true'::jsonb),
  'matching a reference does not approve a template-level row contradiction');

insert into public.products(id,tenant_id,name,sku,price,cost,is_active,spec_template_id)
values('c0bd0000-0000-4000-8000-000000000020','c0bd0000-0000-4000-8000-000000000001',
  'Independent row boundary','ROW-BOUNDARY',100,50,true,'c0bd0000-0000-4000-8000-000000000050');
create function pg_temp.boundary_save(p_cells jsonb,p_operation text)
returns jsonb language sql as $$
  select public.save_product_with_specs_v1(
    '{"id":"c0bd0000-0000-4000-8000-000000000020","name":"Independent row boundary","sku":"ROW-BOUNDARY"}',false,
    'c0bd0000-0000-4000-8000-000000000050',
    (select contract_version from public.spec_templates where id='c0bd0000-0000-4000-8000-000000000050'),
    jsonb_build_object('c0bd0000-0000-4000-8000-000000000011',jsonb_build_object('rows',
      pg_temp.boundary_values(p_cells)->'row_boundary_configs')),
    (select spec_revision from public.products where id='c0bd0000-0000-4000-8000-000000000020'),null,p_operation,
    (select updated_at from public.products where id='c0bd0000-0000-4000-8000-000000000020'))
$$;
grant execute on function pg_temp.boundary_values(jsonb),pg_temp.boundary_save(jsonb,text) to authenticated;
set constraints product_spec_fact_constraint,product_spec_value_constraint deferred;
set local role authenticated;
select lives_ok($$select pg_temp.boundary_save(
  '{"fixed":"record","kind":"A","detail":"Kept","quantity":"9007199254740993.125"}',
  'independent-row-unknown-save')$$,
  'authenticated save preserves a dependent observation while prerequisite is unknown');
reset role;
select is((select value_json from public.spec_facts
  where subject_type='product' and subject_id='c0bd0000-0000-4000-8000-000000000020'
    and spec_definition_id='c0bd0000-0000-4000-8000-000000000011'),
  public.spec_rows_validate_internal_v1(
    (select validation_rules->'rows_schema' from public.spec_definitions where id='c0bd0000-0000-4000-8000-000000000011'),
    pg_temp.boundary_values('{"fixed":"record","kind":"A","detail":"Kept","quantity":"9007199254740993.125"}')->'row_boundary_configs'),
  'saved row keeps its exact decimal, dependent cell, id and sources together');
create temp table boundary_product_before as select p.spec_revision,
  (select md5(jsonb_agg(to_jsonb(f) order by f.id)::text) from public.spec_facts f
    where f.subject_type='product' and f.subject_id=p.id) digest
  from public.products p where id='c0bd0000-0000-4000-8000-000000000020';
set local role authenticated;
select throws_ok($$select pg_temp.boundary_save('{"fixed":"record","kind":"A","flag":false,"detail":"Kept"}',
  'independent-row-known-conflict')$$,'23514',null,
  'resolving unknown to false rejects retained incompatible dependent data');
reset role;
select is((select md5(jsonb_agg(to_jsonb(f) order by f.id)::text) from public.spec_facts f
  where f.subject_type='product' and f.subject_id='c0bd0000-0000-4000-8000-000000000020'),
  (select digest from boundary_product_before),'rejected resolution preserves all stored fact provenance');
select is((select spec_revision from public.products where id='c0bd0000-0000-4000-8000-000000000020'),
  (select spec_revision from boundary_product_before),'rejected resolution preserves the product revision');

select * from finish();
rollback;
