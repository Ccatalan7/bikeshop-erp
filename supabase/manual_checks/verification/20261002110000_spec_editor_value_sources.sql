-- Read-back of 20261002110000: the editor snapshot carries `value_sources`,
-- built from the same facts as `values`. Read-only; division by zero fails it.
select 1/(case when
  position('value_sources' in pg_get_functiondef('public.get_product_spec_editor_context_v2(uuid,uuid)'::regprocedure))>0
  and (select count(*) from pg_proc where proname='spec_product_value_sources_internal_v1')=1
  and not has_function_privilege('authenticated','public.spec_product_value_sources_internal_v1(uuid,uuid)','execute')
then 1 else 0 end) as spec_editor_value_sources_ok;
