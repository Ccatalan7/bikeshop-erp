-- Real central-validator regression: a data cable cannot need charger ports.
begin;
set local client_min_messages=error;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
create temp table row_cardinality_document(doc jsonb);
\ir fixtures/product_spec_row_cardinality.sql
insert into public.tenants(id,shop_name)
values('c0df2600-0000-4000-8000-000000000001','Cardinality applicability fixture');
create temp table applicability_field_ids(key text primary key,id uuid);
insert into applicability_field_ids values
 ('items','c0df2600-0000-4000-8000-000000000011'),
 ('other_items','c0df2600-0000-4000-8000-000000000012'),
 ('total','c0df2600-0000-4000-8000-000000000013'),
 ('other_total','c0df2600-0000-4000-8000-000000000014'),
 ('description','c0df2600-0000-4000-8000-000000000015');
insert into public.spec_definitions(id,tenant_id,key,label,data_type,validation_rules)
select f.id,'c0df2600-0000-4000-8000-000000000001',e.key,e.key,
 e.value->>'data_type',e.value->'validation_rules'
from row_cardinality_document cross join lateral jsonb_each(doc->'fields') e
join applicability_field_ids f using(key);
insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract)
select 'c0df2600-0000-4000-8000-000000000050','c0df2600-0000-4000-8000-000000000001',
 'cardinality_applicability','Cardinality applicability','cardinality_applicability',
 jsonb_set(doc->'contract','{allowed_when,items}','{"kind":"never"}')
from row_cardinality_document;
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select 'c0df2600-0000-4000-8000-000000000050',id,'contents',1 from applicability_field_ids;
set constraints all immediate;

create function pg_temp.applicability_issues(v jsonb) returns jsonb language sql stable as $$
 select public.spec_validate_draft_internal_v1('c0df2600-0000-4000-8000-000000000050',v)
$$;
create function pg_temp.count_pending(v jsonb) returns bigint language sql stable as $$
 select count(*) from jsonb_array_elements(pg_temp.applicability_issues(v)) i
 where i->>'code'='row_cardinality_pending'
$$;
create function pg_temp.cardinality_values(case_id text) returns jsonb language sql stable as $$
 select c->'values' from row_cardinality_document
 cross join lateral jsonb_array_elements(doc->'cases') c where c->>'id'=case_id
$$;

select is(pg_temp.count_pending('{}'),0::bigint,
 'a collection that never applies cannot require its missing total');
select is(pg_temp.count_pending(pg_temp.cardinality_values('total_missing_with_rows')),0::bigint,
 'inapplicable saved rows do not create a missing-total request');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.applicability_issues(
 pg_temp.cardinality_values('total_missing_with_rows'))) i
 where i->>'code'='field_applicability' and i->'blocking'='true'),
 'inapplicable saved rows still block through applicability');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.applicability_issues(
 pg_temp.cardinality_values('invalid_rows_wrong_document'))) i where i->>'code'='row_shape'),
 'inapplicability cannot hide malformed observations');

update public.spec_templates set form_contract=jsonb_set(form_contract,'{allowed_when,items}',
 '{"kind":"when","rows":[[{"field":"description","operator":"eq","value_type":"token","value":"Charger"}]]}')
where id='c0df2600-0000-4000-8000-000000000050';
select is(pg_temp.count_pending('{"description":"Cable"}'),0::bigint,
 'choosing a cable removes the charger completeness requirement');
select is(pg_temp.count_pending('{"description":"Charger"}'),1::bigint,
 'choosing a charger retains its completeness requirement');
select is(pg_temp.count_pending('{}'),1::bigint,
 'unknown applicability is not treated as false');
select ok(exists(select 1 from jsonb_array_elements(pg_temp.applicability_issues(
 pg_temp.cardinality_values('more_rows_than_total'))) i
 where i->>'code'='row_cardinality_conflict' and i->'blocking'='true'),
 'unknown applicability cannot excuse a declared excess');

update public.spec_templates set form_contract=jsonb_set(form_contract,'{allowed_when,items}','{"kind":"always"}')
where id='c0df2600-0000-4000-8000-000000000050';
update public.spec_template_fields set visibility_rules='[{"field":"description","operator":"eq","value":"Charger"}]'
where template_id='c0df2600-0000-4000-8000-000000000050'
 and spec_definition_id='c0df2600-0000-4000-8000-000000000011';
select is(pg_temp.count_pending('{"description":"Cable"}'),0::bigint,
 'legacy visibility also participates in the decision');
select is(pg_temp.count_pending('{}'),1::bigint,
 'unknown legacy visibility keeps the existing pending state');

select * from finish();
rollback;
