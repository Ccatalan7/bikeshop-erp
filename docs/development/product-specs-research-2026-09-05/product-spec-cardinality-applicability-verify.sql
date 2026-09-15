-- Strict assertion: old body or changed security fails, never a silent false.
select 1/case when count(*)=1 and bool_and(
 md5(pg_get_functiondef(p.oid))='ac0738d5c2039412b603dc71adc41721'
 and pg_get_userbyid(p.proowner)='postgres' and not p.prosecdef and p.provolatile='s'
 and p.proconfig=array['search_path=pg_catalog, public, pg_temp']::text[]
 and p.proacl::text='{postgres=X/postgres,service_role=X/postgres}'
 and not has_function_privilege('anon',p.oid,'execute')
 and not has_function_privilege('authenticated',p.oid,'execute')
 and has_function_privilege('service_role',p.oid,'execute')) then 1 else 0 end as verified_function_and_security
from pg_proc p where p.oid=to_regprocedure('public.spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)');
-- Execute the changed validator against every active template currently bound
-- in this tenant; this is a read-only smoke, not unpublished-metadata coverage.
select 1/case when count(*)>0 and bool_and(jsonb_typeof(issues)='array') then 1 else 0 end as current_templates_executed,
 count(*) as templates, sum(jsonb_array_length(issues)) as missing_or_conflicting_inputs
from (select public.spec_validate_draft_internal_v1(b.template_id,'{}'::jsonb) issues
 from (select distinct template_id from public.product_spec_bindings_internal_v1
  where tenant_id='5443b130-cc28-45af-a420-cd500b288890' and template_id is not null) b) evaluated;
