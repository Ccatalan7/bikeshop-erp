-- Verifier: fails (division by zero) until the revocation RPC, its reader and its receipt table exist with visitor-safe grants.
select 1/(case when to_regprocedure('public.revoke_product_spec_research_application_v1(uuid,text)') is not null
  and to_regprocedure('public.get_product_spec_research_revocation_v1(uuid)') is not null
  and to_regclass('public.product_spec_research_revocations') is not null
  and exists (select 1 from information_schema.columns where table_schema='public' and table_name='product_spec_research_applications' and column_name='revoked_reason')
  and has_function_privilege('authenticated','public.revoke_product_spec_research_application_v1(uuid,text)','execute')
  and not has_function_privilege('anon','public.revoke_product_spec_research_application_v1(uuid,text)','execute')
  and not has_function_privilege('service_role','public.revoke_product_spec_research_application_v1(uuid,text)','execute')
  and not has_table_privilege('authenticated','public.product_spec_research_revocations','select')
  then 1 else 0 end) as ok;
