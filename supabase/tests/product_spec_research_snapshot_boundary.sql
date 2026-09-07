-- Independent regression of research snapshot/preview boundaries, local only.
-- Synthetic facts and references are not evidence about any stock product.
begin;
set local client_min_messages=error;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
insert into public.tenants(id,shop_name) values
 ('f2222300-0000-4000-8000-000000000001','Review local A'),
 ('f2222300-0000-4000-8000-000000000002','Review local B');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('f2222300-0000-4000-8000-000000000091','authenticated','authenticated','review-local@example.invalid','',now(),'{}',
 '{"account_type":"public_store_customer","customer_tenant_id":"f2222300-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='f2222300-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role)
values('f2222300-0000-4000-8000-000000000091','f2222300-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"f2222300-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','f2222300-0000-4000-8000-000000000091',true);

insert into public.spec_definitions(id,key,label,data_type,validation_rules,allowed_values) values
 ('f2222300-0000-4000-8000-000000000051','review_amount','Review amount','number','{"min":"0.1","max":"9007199254740993.125"}','[]'),
 ('f2222300-0000-4000-8000-000000000052','review_flag','Review flag','boolean','{}','[]'),
 ('f2222300-0000-4000-8000-000000000053','review_option','Review option','single_select','{}','["01","02"]'),
 ('f2222300-0000-4000-8000-000000000054','review_rows','Review rows','json',
  '{"rows_schema":{"version":1,"columns":[{"key":"length","label":"Length","type":"decimal"},{"key":"note","label":"Note","type":"text"}]}}','[]'),
 ('f2222300-0000-4000-8000-000000000055','review_text','Review text','text','{}','[]'),
 ('f2222300-0000-4000-8000-000000000056','review_retired','Review retired','text','{}','[]'),
 ('f2222300-0000-4000-8000-000000000057','review_outside','Review outside','text','{}','[]'),
 ('f2222300-0000-4000-8000-000000000059','review_reference_text','Review reference text','text','{}','[]'),
 ('f2222300-0000-4000-8000-000000000070','review_reference_flag','Review reference flag','boolean','{}','[]'),
 ('f2222300-0000-4000-8000-000000000071','review_reference_option','Review reference option','single_select','{}','["01"]');
-- Same display key as global active field 55, but a different tenant-owned ID
-- which is not an endpoint in this product's template.
insert into public.spec_definitions(id,tenant_id,key,label,data_type,validation_rules,allowed_values)
values('f2222300-0000-4000-8000-000000000058','f2222300-0000-4000-8000-000000000001',
 'review_text','Review text shadow','text','{}','[]');
insert into public.spec_definition_values(id,spec_definition_id,code,label) values
 ('f2222300-0000-4000-8000-000000000061','f2222300-0000-4000-8000-000000000053','review_01','01'),
 ('f2222300-0000-4000-8000-000000000062','f2222300-0000-4000-8000-000000000053','review_02','02');
insert into public.spec_definition_values(id,spec_definition_id,code,label,is_active)
values('f2222300-0000-4000-8000-000000000063','f2222300-0000-4000-8000-000000000071','review_inactive','01',false);
insert into public.spec_templates(id,key,name,technical_family,form_contract) values
 ('f2222300-0000-4000-8000-000000000050','review_research','Review research','fixture_review_research',
 '{"rules_version":2,"roles":{"review_retired":"legacy"},"allowed_when":{},"required_when":{},"allowed_options":{},"prerequisites":{},"row_conditions":{"version":1,"fields":{"review_rows":{"allowed_when":{"note":{"kind":"when","rows":[[{"field":"length","operator":"lt","value_type":"decimal","value":"5"}]]}},"required_when":{},"allowed_options":{}}}}}');
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select 'f2222300-0000-4000-8000-000000000050',id,'primary',0 from public.spec_definitions
where id in ('f2222300-0000-4000-8000-000000000051','f2222300-0000-4000-8000-000000000052',
 'f2222300-0000-4000-8000-000000000053','f2222300-0000-4000-8000-000000000054',
 'f2222300-0000-4000-8000-000000000055','f2222300-0000-4000-8000-000000000056',
 'f2222300-0000-4000-8000-000000000059','f2222300-0000-4000-8000-000000000070','f2222300-0000-4000-8000-000000000071');
set constraints all immediate;
insert into public.products(id,tenant_id,name,sku,brand,model,price,cost,is_active,spec_template_id)
values('f2222300-0000-4000-8000-000000000020','f2222300-0000-4000-8000-000000000001','Review local','REVIEW-LOCAL','Synthetic','Boundary',100,50,true,'f2222300-0000-4000-8000-000000000050');
select public.save_product_with_specs_v1(
 '{"id":"f2222300-0000-4000-8000-000000000020","name":"Review local","sku":"REVIEW-LOCAL"}',false,
 'f2222300-0000-4000-8000-000000000050',(select contract_version from public.spec_templates where id='f2222300-0000-4000-8000-000000000050'),
 '{"f2222300-0000-4000-8000-000000000051":{"number":"9007199254740993.125"},"f2222300-0000-4000-8000-000000000052":{"boolean":false},"f2222300-0000-4000-8000-000000000053":{"value_ids":["f2222300-0000-4000-8000-000000000061"]},"f2222300-0000-4000-8000-000000000054":{"rows":{"schema_version":1,"rows":[{"id":"original-row","values":{"length":"0.100000000000000001","note":"Retained evidence"},"sources":["https://example.com/synthetic-original-row"]},{"id":"second-row","values":{"length":"2"},"sources":[]}]}},"f2222300-0000-4000-8000-000000000055":{"text":"Original text"}}',
 (select spec_revision from public.products where id='f2222300-0000-4000-8000-000000000020'),null,'review-local-save',
 (select updated_at from public.products where id='f2222300-0000-4000-8000-000000000020'));



insert into public.spec_fact_readings(fact_id,tenant_id,source_text,source_digest,quote,model)
select id,tenant_id,'Independent historical evidence','independent-synthetic-digest','historical','synthetic'
from public.spec_facts where subject_type='product' and subject_id='f2222300-0000-4000-8000-000000000020'
 and spec_definition_id='f2222300-0000-4000-8000-000000000053';

create function pg_temp.boundary_preview(p_patch jsonb default '{}'::jsonb,p_reference text default null)
returns jsonb language sql as $$
 select public.preview_product_spec_research_v1('f2222300-0000-4000-8000-000000000020',
   public.get_product_spec_research_snapshot_v1('f2222300-0000-4000-8000-000000000020')->>'snapshot_sha256',
   '{}',p_patch,p_reference)
$$;
grant execute on function pg_temp.boundary_preview(jsonb,text) to authenticated;
create function pg_temp.boundary_reference_read(p_version integer,p_reference_id text)
returns jsonb language plpgsql as $$
declare result jsonb;
begin
 if p_version=1 then result:=public.get_product_spec_references_v1('fixture_review_research');
 elsif p_version=2 then result:=public.get_product_spec_references_v2('fixture_review_research');
 elsif p_version=3 then result:=public.get_product_spec_research_snapshot_v1('f2222300-0000-4000-8000-000000000020')->'references';
 else return pg_temp.boundary_preview('{}',p_reference_id);
 end if;
 return jsonb_build_object('outcome','returned','reference',
   (select r from jsonb_array_elements(result) r where r->>'id'=p_reference_id));
exception when others then return jsonb_build_object('outcome','rejected','sqlstate',sqlstate);
end $$;
grant execute on function pg_temp.boundary_reference_read(integer,text) to authenticated;

create temp table independent_research_state(label text primary key,value jsonb);
grant select,insert on independent_research_state to authenticated;
set local role authenticated;
insert into independent_research_state values('before',public.get_product_spec_research_snapshot_v1('f2222300-0000-4000-8000-000000000020'));
select throws_ok($$select pg_temp.boundary_preview('{"review_text":{"unexpected":"object"}}')$$,'23514',null,'RS1 object is not text');
select throws_ok($$select pg_temp.boundary_preview('{"review_flag":"unknown"}')$$,'23514',null,'RS1 unknown string is not boolean');
select throws_ok($$select pg_temp.boundary_preview('{"review_amount":10}')$$,'23514',null,'RS1 numeric JSON cannot replace exact decimal transport');
select throws_ok($$select pg_temp.boundary_preview('{"review_option":[null]}')$$,'23514',null,'RS1 single select cannot become an unknown array');
select throws_ok($$select pg_temp.boundary_preview('{"review_rows":"unknown"}')$$,'23514',null,'RS1 unknown string is not a row document');
select is(pg_temp.boundary_preview('{"review_amount":"9007199254740993.125"}')#>>'{values,review_amount}',
 '9007199254740993.125','exact scalar survives a valid research delta');
select is(pg_temp.boundary_preview('{"review_flag":false}')#>'{values,review_flag}','false'::jsonb,'known false survives a valid delta');
select is(pg_temp.boundary_preview('{"review_option":"01"}')#>>'{values,review_option}','01','option token 01 remains literal');
select throws_ok($$select pg_temp.boundary_preview('{"review_option":"1"}')$$,'23514',null,'option 1 is not token 01');
select throws_ok($$select pg_temp.boundary_preview('{"review_retired":"new"}')$$,'23514',null,'RS2 explicit legacy delta is rejected');
select throws_ok($$select pg_temp.boundary_preview('{"review_outside":"new"}')$$,'23514',null,'RS2 explicit out-of-template delta is rejected');

insert into independent_research_state values('merge',pg_temp.boundary_preview(
 '{"review_rows":{"schema_version":1,"rows":[{"id":"original-row","values":{"length":"1"},"sources":["https://example.com/synthetic-added-source"]}]}}'));
select is((select value->'valid_draft' from independent_research_state where label='merge'),'true'::jsonb,'valid row merge remains a valid representation');
select is((select value#>>'{values,review_rows,rows,0,values,length}' from independent_research_state where label='merge'),'1','merge changes the explicitly proposed cell');
select is((select value#>>'{values,review_rows,rows,0,values,note}' from independent_research_state where label='merge'),'Retained evidence','merge retains omitted cell');
select is((select value#>>'{values,review_rows,rows,1,id}' from independent_research_state where label='merge'),'second-row','merge retains omitted row identity');
select is((select value#>'{values,review_rows,rows,0,sources}' from independent_research_state where label='merge'),
 '["https://example.com/synthetic-original-row","https://example.com/synthetic-added-source"]'::jsonb,'merge unions evidence sources in stable order');
insert into independent_research_state values('append',pg_temp.boundary_preview(
 '{"review_rows":{"schema_version":1,"rows":[{"id":"added-row","values":{"length":"3"},"sources":["https://example.com/synthetic-added-row"]}]}}'));
select is((select jsonb_array_length(value#>'{values,review_rows,rows}') from independent_research_state where label='append'),3,'append retains both existing rows');
select is((select value#>>'{values,review_rows,rows,0,values,length}' from independent_research_state where label='append'),
 '0.100000000000000001','append leaves the original exact decimal intact');
select throws_ok($$select pg_temp.boundary_preview('{"review_rows":{"schema_version":1,"rows":[{"id":"original-row","values":{"note":null},"sources":[]}]}}')$$,
 '23514',null,'row delta cannot delete a cell through null');
select throws_ok($$select pg_temp.boundary_preview('{"review_rows":{"schema_version":1,"rows":[{"id":"original-row","values":{"length":"3"},"sources":[]},{"id":"original-row","values":{"length":"4"},"sources":[]}]}}')$$,
 '23514',null,'row delta cannot contain the same stable ID twice');
insert into independent_research_state values('conflict',pg_temp.boundary_preview(
 '{"review_rows":{"schema_version":1,"rows":[{"id":"original-row","values":{"length":"10"},"sources":[]}]}}'));
select is((select value#>>'{values,review_rows,rows,0,values,note}' from independent_research_state where label='conflict'),
 'Retained evidence','upstream change retains now-inapplicable dependent evidence');
select is((select value->'valid_draft' from independent_research_state where label='conflict'),'false'::jsonb,
 'upstream change is validated after merge and blocks incompatibility');
select ok((select exists(select 1 from jsonb_array_elements(value->'issues') i where i->>'code'='row_field_applicability'
 and i->>'row_id'='original-row' and i->>'column'='note' and i->'blocking'='true'::jsonb)
 from independent_research_state where label='conflict'),'conflict points to the retained cell in the correct row');
select is(public.get_product_spec_research_snapshot_v1('f2222300-0000-4000-8000-000000000020'),
 (select value from independent_research_state where label='before'),'all previews preserve the entire persisted research snapshot');
select is((select jsonb_array_length(o->'readings') from independent_research_state cross join lateral jsonb_array_elements(value->'observations') o
 where label='before' and o#>>'{definition,key}'='review_option'),1,'historical reading remains part of the snapshot');
reset role;

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000059":{"text":{"unexpected":"object"}}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(4,'review-malformed-global') result \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_result'::jsonb->>'sqlstate','23514','RS1/2 reference text object cannot derive a valid candidate');

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000070":{"boolean":"unknown"}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(4,'review-malformed-global') result \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_result'::jsonb->>'sqlstate','23514','RS1/2 reference boolean unknown string cannot derive a valid candidate');

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000057":{"text":"Outside"}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(4,'review-malformed-global') result \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_result'::jsonb->>'sqlstate','23514','RS1/2 reference outside template cannot derive a valid candidate');

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000056":{"text":"Retired"}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(4,'review-malformed-global') result \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_result'::jsonb->>'sqlstate','23514','RS1/2 reference legacy field cannot derive a valid candidate');

insert into public.spec_definitions(id,tenant_id,key,label,data_type,validation_rules,allowed_values)
values('f2222300-0000-4000-8000-000000000072','f2222300-0000-4000-8000-000000000002',
 'review_foreign_select','Foreign private field','single_select','{}','["Foreign tenant private option"]');
insert into public.spec_definition_values(id,tenant_id,spec_definition_id,code,label) values
 ('f2222300-0000-4000-8000-000000000064','f2222300-0000-4000-8000-000000000002',
 'f2222300-0000-4000-8000-000000000072','review_private','Foreign tenant private option'),
 ('f2222300-0000-4000-8000-000000000065','f2222300-0000-4000-8000-000000000002',
 'f2222300-0000-4000-8000-000000000053','review_private_overlay','Foreign private overlay');
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-global-valid','fixture_review_research','Synthetic','Boundary','Review global valid',
 '{"f2222300-0000-4000-8000-000000000051":{"number":9007199254740993.125},"f2222300-0000-4000-8000-000000000052":{"boolean":false},"f2222300-0000-4000-8000-000000000053":{"value_ids":["f2222300-0000-4000-8000-000000000061"]}}',
 '["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select is((select count(*)::integer from public.spec_definition_values where id in ('f2222300-0000-4000-8000-000000000064','f2222300-0000-4000-8000-000000000065')),0,
 'private option fixtures are not directly visible under tenant A RLS');
select is(jsonb_typeof(pg_temp.boundary_reference_read(1,'review-global-valid')#>'{reference,facts,review_amount}'),'number','legacy reference v1 keeps JSON number wire format');
select is(jsonb_typeof(pg_temp.boundary_reference_read(2,'review-global-valid')#>'{reference,facts,review_amount}'),'string','exact reference v2 keeps string wire format');
select is(pg_temp.boundary_reference_read(2,'review-global-valid')#>>'{reference,facts,review_amount}','9007199254740993.125','reference v2 preserves every numeric digit');
select is(pg_temp.boundary_reference_read(1,'review-global-valid')#>'{reference,facts,review_flag}','false'::jsonb,'legacy reference preserves false');
select is(pg_temp.boundary_reference_read(2,'review-global-valid')#>>'{reference,facts,review_option}','01','reference option remains literal 01');
select ok(not(pg_temp.boundary_reference_read(1,'review-global-valid')->'reference' ? 'read_schema_version'),'v1 reference gains no v2 schema header');
reset role;

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000072":{"value_ids":["f2222300-0000-4000-8000-000000000064"]}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(1,'review-malformed-global') v1,
 pg_temp.boundary_reference_read(2,'review-malformed-global') v2,
 pg_temp.boundary_reference_read(3,'review-malformed-global') snapshot \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_v1'::jsonb->>'sqlstate','42501','RS4 v1 rejects foreign definition');
select is(:'independent_v2'::jsonb->>'sqlstate','42501','RS4 v2 rejects foreign definition');
select is(:'independent_snapshot'::jsonb->>'sqlstate','42501','RS4 snapshot rejects foreign definition');

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000058":{"text":"Original text"}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(1,'review-malformed-global') v1,
 pg_temp.boundary_reference_read(2,'review-malformed-global') v2,
 pg_temp.boundary_reference_read(3,'review-malformed-global') snapshot \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_v1'::jsonb->>'sqlstate','42501','RS4 v1 rejects own tenant homonymous definition');
select is(:'independent_v2'::jsonb->>'sqlstate','42501','RS4 v2 rejects own tenant homonymous definition');
select is(:'independent_snapshot'::jsonb->>'sqlstate','42501','RS4 snapshot rejects own tenant homonymous definition');

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000053":{"value_ids":["f2222300-0000-4000-8000-000000000065"]}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(1,'review-malformed-global') v1,
 pg_temp.boundary_reference_read(2,'review-malformed-global') v2,
 pg_temp.boundary_reference_read(3,'review-malformed-global') snapshot \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_v1'::jsonb->>'sqlstate','42501','RS4 v1 rejects foreign option on global definition');
select is(:'independent_v2'::jsonb->>'sqlstate','42501','RS4 v2 rejects foreign option on global definition');
select is(:'independent_snapshot'::jsonb->>'sqlstate','42501','RS4 snapshot rejects foreign option on global definition');

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000071":{"value_ids":["f2222300-0000-4000-8000-000000000061"]}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(1,'review-malformed-global') v1,
 pg_temp.boundary_reference_read(2,'review-malformed-global') v2,
 pg_temp.boundary_reference_read(3,'review-malformed-global') snapshot \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_v1'::jsonb->>'sqlstate','42501','RS4 v1 rejects option on a different global endpoint');
select is(:'independent_v2'::jsonb->>'sqlstate','42501','RS4 v2 rejects option on a different global endpoint');
select is(:'independent_snapshot'::jsonb->>'sqlstate','42501','RS4 snapshot rejects option on a different global endpoint');

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000099":{"text":"Missing field"}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(1,'review-malformed-global') v1,
 pg_temp.boundary_reference_read(2,'review-malformed-global') v2,
 pg_temp.boundary_reference_read(3,'review-malformed-global') snapshot \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_v1'::jsonb->>'sqlstate','42501','RS4 v1 rejects missing global definition');
select is(:'independent_v2'::jsonb->>'sqlstate','42501','RS4 v2 rejects missing global definition');
select is(:'independent_snapshot'::jsonb->>'sqlstate','42501','RS4 snapshot rejects missing global definition');

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000053":{"value_ids":["f2222300-0000-4000-8000-000000000098"]}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(1,'review-malformed-global') v1,
 pg_temp.boundary_reference_read(2,'review-malformed-global') v2,
 pg_temp.boundary_reference_read(3,'review-malformed-global') snapshot \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_v1'::jsonb->>'sqlstate','42501','RS4 v1 rejects missing global option');
select is(:'independent_v2'::jsonb->>'sqlstate','42501','RS4 v2 rejects missing global option');
select is(:'independent_snapshot'::jsonb->>'sqlstate','42501','RS4 snapshot rejects missing global option');

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000071":{"value_ids":["f2222300-0000-4000-8000-000000000063"]}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(1,'review-malformed-global') v1,
 pg_temp.boundary_reference_read(2,'review-malformed-global') v2,
 pg_temp.boundary_reference_read(3,'review-malformed-global') snapshot \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_v1'::jsonb->>'sqlstate','42501','RS4 v1 rejects inactive global option');
select is(:'independent_v2'::jsonb->>'sqlstate','42501','RS4 v2 rejects inactive global option');
select is(:'independent_snapshot'::jsonb->>'sqlstate','42501','RS4 snapshot rejects inactive global option');

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000053":{"value_ids":["f2222300-0000-4000-8000-000000000061","f2222300-0000-4000-8000-000000000062"]}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(1,'review-malformed-global') v1,
 pg_temp.boundary_reference_read(2,'review-malformed-global') v2,
 pg_temp.boundary_reference_read(3,'review-malformed-global') snapshot \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_v1'::jsonb->>'sqlstate','42501','RS4 v1 rejects multiple single-select options');
select is(:'independent_v2'::jsonb->>'sqlstate','42501','RS4 v2 rejects multiple single-select options');
select is(:'independent_snapshot'::jsonb->>'sqlstate','42501','RS4 snapshot rejects multiple single-select options');

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000053":{"value_ids":["f2222300-0000-4000-8000-000000000061","f2222300-0000-4000-8000-000000000061"]}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(1,'review-malformed-global') v1,
 pg_temp.boundary_reference_read(2,'review-malformed-global') v2,
 pg_temp.boundary_reference_read(3,'review-malformed-global') snapshot \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_v1'::jsonb->>'sqlstate','42501','RS4 v1 rejects duplicate single-select option');
select is(:'independent_v2'::jsonb->>'sqlstate','42501','RS4 v2 rejects duplicate single-select option');
select is(:'independent_snapshot'::jsonb->>'sqlstate','42501','RS4 snapshot rejects duplicate single-select option');

savepoint independent_reference_case;
insert into public.product_spec_references(id,technical_family,brand,model,label,fact_values,sources,reviewed_on)
values('review-malformed-global','fixture_review_research','Synthetic','Boundary','Review malformed global',
 '{"f2222300-0000-4000-8000-000000000053":{"value_ids":[null]}}','["https://example.com/synthetic-review-reference"]',current_date);
set local role authenticated;
select pg_temp.boundary_reference_read(1,'review-malformed-global') v1,
 pg_temp.boundary_reference_read(2,'review-malformed-global') v2,
 pg_temp.boundary_reference_read(3,'review-malformed-global') snapshot \gset independent_
reset role;
rollback to independent_reference_case;
release independent_reference_case;
select is(:'independent_v1'::jsonb->>'sqlstate','42501','RS4 v1 rejects null option ID');
select is(:'independent_v2'::jsonb->>'sqlstate','42501','RS4 v2 rejects null option ID');
select is(:'independent_snapshot'::jsonb->>'sqlstate','42501','RS4 snapshot rejects null option ID');

-- Orphan history still participates in the research preimage.
delete from public.spec_template_fields where template_id='f2222300-0000-4000-8000-000000000050'
 and spec_definition_id='f2222300-0000-4000-8000-000000000053';
insert into independent_research_state values('orphan_before',public.get_product_spec_research_snapshot_v1('f2222300-0000-4000-8000-000000000020'));
update public.spec_definition_values set label='01 revised' where id='f2222300-0000-4000-8000-000000000061';
insert into independent_research_state values('orphan_after',public.get_product_spec_research_snapshot_v1('f2222300-0000-4000-8000-000000000020'));
select isnt((select value->>'snapshot_sha256' from independent_research_state where label='orphan_after'),
 (select value->>'snapshot_sha256' from independent_research_state where label='orphan_before'),'RS3 orphan label change invalidates the snapshot hash');
select isnt((select value->'observations' from independent_research_state where label='orphan_after'),
 (select value->'observations' from independent_research_state where label='orphan_before'),'RS3 option metadata change is part of observations fingerprint');
set local role authenticated;
select throws_ok($$select public.preview_product_spec_research_v1('f2222300-0000-4000-8000-000000000020',
 (select value->>'snapshot_sha256' from independent_research_state where label='orphan_before'))$$,
 '40001',null,'RS3 old orphan preimage cannot simulate');
reset role;
update public.spec_definition_values set code='review_01_revised' where id='f2222300-0000-4000-8000-000000000061';
select isnt(public.get_product_spec_research_snapshot_v1('f2222300-0000-4000-8000-000000000020')->>'snapshot_sha256',
 (select value->>'snapshot_sha256' from independent_research_state where label='orphan_after'),'RS3 unrendered orphan option code also invalidates hash');
select is(public.get_product_spec_research_snapshot_v1('f2222300-0000-4000-8000-000000000020')->'editor',
 (select value->'editor' from independent_research_state where label='orphan_after'),'orphan code test isolates metadata not visible in editor');
select * from finish();
rollback;
