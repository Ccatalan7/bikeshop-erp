-- Verifier: fails (division by zero) while the research merge still pins rows version 1, or while the preview's empty-envelope test or the row-conditions probe still write version 1 in.
-- The merge is immutable, so its probe argument comes from a subquery: a constant call would be folded at plan time and raise before the CASE decides.
select 1/(case when pg_get_functiondef('public.spec_merge_research_rows_internal_v1(jsonb,jsonb)'::regprocedure) not like '%is distinct from ''1''::jsonb%'
  and pg_get_functiondef('public.preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text)'::regprocedure) not like '%"schema_version":1,"rows":[]%'
  and pg_get_functiondef('public.spec_row_conditions_metadata_internal_v1(jsonb,jsonb)'::regprocedure) like '%''schema_version'',schema->''version''%'
  then (case when public.spec_merge_research_rows_internal_v1(null,(select jsonb_build_object('schema_version',2,'rows',jsonb_build_array(jsonb_build_object('id','probe','values',jsonb_build_object('x','1'),'sources','[]'::jsonb))) from pg_class limit 1))->>'schema_version'='2' then 1 else 0 end)
  else 0 end) as ok;
