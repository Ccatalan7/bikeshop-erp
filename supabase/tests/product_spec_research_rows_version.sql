begin;
set local client_min_messages=error;
select plan(8);
-- A research fill names the rows schema version its definition declares; the
-- merge keeps it, refuses a delta over rows of another version and still
-- treats version 1 as before (20260916260000).
select is(public.spec_merge_research_rows_internal_v1(null,
 '{"schema_version":2,"rows":[{"id":"a","values":{"x":"1"},"sources":[]}]}'::jsonb)->>'schema_version','2',
 'a first fill keeps the version its definition declares');
select is(jsonb_array_length(public.spec_merge_research_rows_internal_v1(
 '{"schema_version":2,"rows":[{"id":"a","values":{"x":"1"},"sources":[]}]}'::jsonb,
 '{"schema_version":2,"rows":[{"id":"b","values":{"x":"2"},"sources":[]}]}'::jsonb)->'rows'),2,
 'rows of the same version merge by id');
select is(public.spec_merge_research_rows_internal_v1(null,
 '{"schema_version":1,"rows":[{"id":"a","values":{"x":"1"},"sources":[]}]}'::jsonb)->>'schema_version','1',
 'version 1 fills are unchanged');
select throws_ok($$select public.spec_merge_research_rows_internal_v1('{"schema_version":1,"rows":[]}'::jsonb,
 '{"schema_version":2,"rows":[{"id":"a","values":{"x":"1"},"sources":[]}]}'::jsonb)$$,
 '23514',null,'a delta never migrates rows written under another version');
select throws_ok($$select public.spec_merge_research_rows_internal_v1(null,
 '{"schema_version":"2","rows":[{"id":"a","values":{"x":"1"},"sources":[]}]}'::jsonb)$$,
 '23514',null,'the version is a JSON integer, not text');
select throws_ok($$select public.spec_merge_research_rows_internal_v1(null,
 '{"schema_version":0,"rows":[{"id":"a","values":{"x":"1"},"sources":[]}]}'::jsonb)$$,
 '23514',null,'the version is positive');
select throws_ok($$select public.spec_merge_research_rows_internal_v1(null,
 '{"schema_version":2,"rows":[]}'::jsonb)$$,
 '23514',null,'an empty fill is still refused');
-- Every rows definition of the installed catalogue is fillable by research at
-- the version it declares: the merge and the row validator agree on it.
select lives_ok($$
 do $probe$
 declare d record; envelope jsonb;
 begin
  for d in select key,validation_rules->'rows_schema' as schema from public.spec_definitions where validation_rules ? 'rows_schema' loop
   envelope:=jsonb_build_object('schema_version',d.schema->'version','rows',
     jsonb_build_array(jsonb_build_object('id','probe','values',jsonb_build_object(d.schema#>>'{columns,0,key}','probe'),'sources','[]'::jsonb)));
   perform public.spec_merge_research_rows_internal_v1(null,envelope);
   if (public.spec_merge_research_rows_internal_v1(null,envelope)->'schema_version') is distinct from d.schema->'version' then
    raise exception 'merge changed the version of %',d.key;
   end if;
  end loop;
 end $probe$;
$$,'every installed rows definition merges at its own version');
select * from finish();
rollback;
