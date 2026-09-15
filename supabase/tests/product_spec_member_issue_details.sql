-- Synthetic graph and save errors only, rolled back together.
begin;
\ir fixtures/product_spec_reading_receipt_contract.sql
\ir ../../scripts/inventory/sql/product_spec_strict_row_order_candidate.sql
\ir ../../scripts/inventory/sql/product_spec_member_profiles_candidate.sql
\ir ../../scripts/inventory/sql/product_spec_legacy_roundtrip_candidate.sql
select no_plan();
\ir fixtures/product_spec_member_graph.sql
do $$ begin perform pg_temp.member_save('issue-details-initial',
 jsonb_build_array(pg_temp.member_profile('r1'))); end $$;
set constraints all immediate;
set constraints all deferred;
create function pg_temp.member_error() returns jsonb language plpgsql as $$
declare details text;
begin
 update public.spec_facts set value_number=0 where
  subject_id='99e10000-0000-4000-8000-000000000020' and
  subject_scope='member:99e10000-0000-4000-8000-000000000081' and
  spec_definition_id='99e10000-0000-4000-8000-000000000052';
 perform public.spec_validate_product_member_profiles_internal_v1('99e10000-0000-4000-8000-000000000020');
 return '{}';
exception when check_violation then
 get stacked diagnostics details=PG_EXCEPTION_DETAIL;
 return jsonb_build_object('message',SQLERRM,'details',details);
end $$;
select ok(pg_temp.member_error()->>'message' like 'Ficha de componente contradictoria:%',
 'predecessor exposes structured component issues as raw message text');
\ir ../../scripts/inventory/sql/product_spec_member_issue_details_candidate.sql
\ir ../../scripts/inventory/sql/product_spec_member_issue_details_candidate.sql
create temp table member_error_receipt as select pg_temp.member_error() value;
select diag(value::text) from member_error_receipt;
select is((select value->>'message' from member_error_receipt),
 'Revisa la ficha de la pieza incluida','message explains the action without raw JSON');
select ok((select (value->>'details')::jsonb @> '[{"profile_id":"99e10000-0000-4000-8000-000000000081","field":"member_test_length"}]'::jsonb
 and coalesce(((value->>'details')::jsonb->0->>'blocking')::boolean,true) from member_error_receipt),
 'error details retain the exact profile and field which failed');
select is((select value_number::text from public.spec_facts where
 subject_id='99e10000-0000-4000-8000-000000000020' and
 subject_scope='member:99e10000-0000-4000-8000-000000000081' and
 spec_definition_id='99e10000-0000-4000-8000-000000000052'),
 '7.1','failed validation leaves the original observation intact');
set constraints all immediate;
select * from finish();
rollback;
