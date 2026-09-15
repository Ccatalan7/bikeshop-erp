begin;
set local client_min_messages=error;
-- The extension stays inside this local rollback; it is not a migration.
\ir ../../scripts/inventory/sql/product_spec_strict_row_order_candidate.sql
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
create temp table strict_order_cases(c jsonb);
create temp table strict_order_invalid_schemas(c jsonb);
\ir fixtures/product_spec_strict_row_order_cases.sql

create function pg_temp.validate_strict_case(p_id text) returns jsonb
language sql as $$
 select public.spec_rows_validate_internal_v1(c->'schema',c->'value')
 from strict_order_cases where c->>'id'=p_id
$$;
select case when (c->>'valid')::boolean then
 lives_ok(format('select pg_temp.validate_strict_case(%L)',c->>'id'),c->>'id')
 else throws_ok(format('select pg_temp.validate_strict_case(%L)',c->>'id'),
   '23514',null,c->>'id') end
from strict_order_cases;

select is(public.spec_rows_validate_internal_v1(c->'schema',pg_temp.validate_strict_case(c->>'id')),
 pg_temp.validate_strict_case(c->>'id'), 'canonical replay: '||(c->>'id'))
from strict_order_cases where (c->>'valid')::boolean;

select throws_ok(format('select public.spec_rows_schema_validate_internal_v1(%L::jsonb)',c->'schema'),
 '22023',null,c->>'id') from strict_order_invalid_schemas;

-- The ordinary draft validator must use the same row contract, rather than
-- reporting a valid shape after the row parser rejected it.
insert into public.spec_definitions(id,key,label,data_type,validation_rules)
select '99bc0000-0000-4000-8000-000000000051','strict_row_body_fixture','Cuerpo',
 'json',jsonb_build_object('rows_schema',c->'schema')
from strict_order_cases where c->>'id'='positive_annular_body';
insert into public.spec_templates(id,key,name,technical_family)
values('99bc0000-0000-4000-8000-000000000050','strict_row_fixture','Strict rows','fixture');
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
values('99bc0000-0000-4000-8000-000000000050','99bc0000-0000-4000-8000-000000000051','measurement',0);

select ok(exists(select 1 from jsonb_array_elements(public.spec_validate_draft_internal_v1(
 '99bc0000-0000-4000-8000-000000000050',jsonb_build_object('strict_row_body_fixture',c->'value'))) i
 where coalesce((i->>'blocking')::boolean,true)), 'ordinary draft blocks: '||(c->>'id'))
from strict_order_cases where not (c->>'valid')::boolean;

select ok(exists(select 1 from jsonb_array_elements(public.spec_validate_draft_internal_v1(
 '99bc0000-0000-4000-8000-000000000050',jsonb_build_object('strict_row_body_fixture',c->'value'))) i
 where i->>'code'='row_incomplete' and i->>'blocking'='false'),
 'missing data stays pending: '||(c->>'id'))
from strict_order_cases where (c->>'missing_required')::integer>0;
select * from finish();
rollback;
