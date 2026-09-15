-- Synthetic observations only. No production writes or family activation.
begin;
\ir fixtures/product_spec_reading_receipt_contract.sql
\ir ../../scripts/inventory/sql/product_spec_strict_row_order_candidate.sql
\ir ../../scripts/inventory/sql/product_spec_member_profiles_candidate.sql
select no_plan();
\ir fixtures/product_spec_member_graph.sql

do $$ begin perform pg_temp.member_save('legacy-roundtrip-initial',jsonb_build_array(
 pg_temp.member_profile('r1'),pg_temp.member_profile('r2','9007199254740993.2'))); end $$;
insert into public.products(id,tenant_id,name,sku,spec_template_id,price,cost,is_published,show_on_website)
values ('99e10000-0000-4000-8000-000000000023','99e10000-0000-4000-8000-000000000001',
 'Synthetic standalone','LEGACY-ROUNDTRIP','99e10000-0000-4000-8000-000000000060',1,1,false,false);
select public.spec_write_payload_internal_v2('99e10000-0000-4000-8000-000000000023',
 '99e10000-0000-4000-8000-000000000060',
 '{"99e10000-0000-4000-8000-000000000052":{"number":"7.1"},"99e10000-0000-4000-8000-000000000053":{"boolean":true}}',null);
select public.spec_write_scope_payload_internal_v1('99e10000-0000-4000-8000-000000000020',
 '99e10000-0000-4000-8000-000000000060',
 public.spec_product_scope_payload_internal_v1('99e10000-0000-4000-8000-000000000020','member:99e10000-0000-4000-8000-000000000081')||
 '{"99e10000-0000-4000-8000-000000000054":{"rows":{"schema_version":2,"rows":[{"id":"size","values":{"inner":"10.50","outer":"20.0"},"sources":["https://example.test/size"]}]}}}',
 null,'member:99e10000-0000-4000-8000-000000000081');
set constraints all immediate;
set constraints all deferred;
update public.spec_templates set form_contract=jsonb_set(jsonb_set(form_contract,
 '{roles,member_test_length}','"legacy"'),'{roles,member_test_details}','"legacy"')
 where id='99e10000-0000-4000-8000-000000000060';
set constraints all immediate;
set constraints all deferred;

create function pg_temp.legacy_roundtrip(p_scope text,p_value jsonb,p_reference text default null)
returns integer language plpgsql as $$
declare product uuid:=case when p_scope is null then '99e10000-0000-4000-8000-000000000023'::uuid
 else '99e10000-0000-4000-8000-000000000020'::uuid end;
 payload jsonb:=public.spec_product_scope_payload_internal_v1(product,p_scope)||p_value;
begin
 if p_reference is not null then payload:=payload-'99e10000-0000-4000-8000-000000000052'; end if;
 if p_scope is null then return public.spec_write_payload_internal_v2(product,
   '99e10000-0000-4000-8000-000000000060',payload,p_reference); end if;
 return public.spec_write_scope_payload_internal_v1(product,
   '99e10000-0000-4000-8000-000000000060',payload,p_reference,p_scope);
end $$;

select throws_ok($$select pg_temp.legacy_roundtrip(null,
 '{"99e10000-0000-4000-8000-000000000052":{"number":"7.10"}}')$$,'23514',null,
 'predecessor reproduces the false rejection of an equal legacy decimal');
\ir ../../scripts/inventory/sql/product_spec_legacy_roundtrip_candidate.sql
-- Exact same candidate must also be replayable.
\ir ../../scripts/inventory/sql/product_spec_legacy_roundtrip_candidate.sql
create temp table roundtrip_before as select to_jsonb(f) value from public.spec_facts f
 where f.subject_id in ('99e10000-0000-4000-8000-000000000020','99e10000-0000-4000-8000-000000000023');
select lives_ok($$select pg_temp.legacy_roundtrip(null,
 '{"99e10000-0000-4000-8000-000000000052":{"number":"7.10"}}')$$,
 'root writer accepts the same exact value transported as decimal text');
select lives_ok($$select pg_temp.legacy_roundtrip('member:99e10000-0000-4000-8000-000000000082',
 '{"99e10000-0000-4000-8000-000000000052":{"number":"9007199254740993.20"}}')$$,
 'component writer compares beyond binary floating-point precision');
select lives_ok($$select pg_temp.legacy_roundtrip(null,'{}','member-test-reference')$$,
 'reference-derived numeric text matches the conserved root observation');
select lives_ok($$select pg_temp.legacy_roundtrip('member:99e10000-0000-4000-8000-000000000081','{}','member-test-reference')$$,
 'reference-derived numeric text matches the conserved component observation');
select throws_ok($$select pg_temp.legacy_roundtrip('member:99e10000-0000-4000-8000-000000000082',
 '{"99e10000-0000-4000-8000-000000000052":{"number":"9007199254740993.3"}}')$$,'23514',null,
 'a changed precise value is still forbidden');
select throws_ok($$select pg_temp.legacy_roundtrip(null,
 '{"99e10000-0000-4000-8000-000000000052":{"number":"7.1","text":"extra"}}')$$,'23514',null,
 'normalization cannot discard extra payload properties');
select throws_ok($$select pg_temp.legacy_roundtrip(null,
 '{"99e10000-0000-4000-8000-000000000052":{"number":"not a number"}}')$$,'23514',null,
 'an invalid number is not an equal legacy observation');
select lives_ok($$select pg_temp.legacy_roundtrip('member:99e10000-0000-4000-8000-000000000081',
 '{"99e10000-0000-4000-8000-000000000054":{"rows":{"schema_version":2,"rows":[{"id":"size","values":{"inner":"10.500","outer":"20"},"sources":["https://example.test/size"]}]}}}')$$,
 'retired rows use the same typed canonicalization as their original writer');
select throws_ok($$select pg_temp.legacy_roundtrip('member:99e10000-0000-4000-8000-000000000081',
 '{"99e10000-0000-4000-8000-000000000054":{"rows":{"schema_version":2,"rows":[{"id":"size","values":{"inner":"10.5","outer":"20"},"sources":["https://example.test/changed"]}]}}}')$$,'23514',null,
 'row equality cannot rewrite its evidence source');
select throws_ok($$select pg_temp.legacy_roundtrip(null,
 '{"99e10000-0000-4000-8000-000000000054":{"rows":{"schema_version":2,"rows":[{"id":"new","values":{"inner":"10","outer":"20"},"sources":["https://example.test/new"]}]}}}')$$,'23514',null,
 'a new retired observation is still refused');
select throws_ok($$select public.spec_write_scope_payload_internal_v1(
 '99e10000-0000-4000-8000-000000000023','99e10000-0000-4000-8000-000000000060',
 '{"99e10000-0000-4000-8000-000000000052":{"number":"7.1"}}',null,'synthetic-empty-scope')$$,'23514',null,
 'a decimal payload cannot create a previously absent retired observation');
select throws_ok($$select pg_temp.legacy_roundtrip('member:99e10000-0000-4000-8000-000000000081',
 '{"99e10000-0000-4000-8000-000000000054":{"rows":{"schema_version":2,"rows":[{"id":"size","values":{"inner":"10.5","outer":"20"},"sources":["https://example.test/size"],"extra":true}]}}}')$$,'23514',null,
 'typed comparison rejects extra properties inside a preserved row');
select is((select jsonb_agg(to_jsonb(f) order by f.id) from public.spec_facts f
 where f.subject_id in ('99e10000-0000-4000-8000-000000000020','99e10000-0000-4000-8000-000000000023')),
 (select jsonb_agg(value order by value->>'id') from roundtrip_before),
 'every fact value, source, timestamp and identity remains byte-for-byte conserved');
set constraints all immediate;
select * from finish();
rollback;
