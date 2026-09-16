-- Read-only read-back of the reviewer-identity update. Fails before it is
-- published (division by zero) and passes only with the exact function body,
-- owner, ACL and configuration installed, and nothing enabled or applied.
select 1/(case when (select jsonb_build_object('identity',p.oid::regprocedure::text,
   'md5',md5(pg_get_functiondef(p.oid)),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,
   'security_definer',p.prosecdef,'volatility',p.provolatile::text,'config',to_jsonb(p.proconfig))
  from pg_proc p where p.oid=to_regprocedure('public.apply_product_spec_research_v1(uuid)'))='{"acl": "{postgres=X/postgres,authenticated=X/postgres}", "config": ["search_path=pg_catalog, public, pg_temp"], "identity": "apply_product_spec_research_v1(uuid)", "md5": "431920eb97996e87c4e44d8e28a10e03", "owner": "postgres", "security_definer": true, "volatility": "v"}'::jsonb then 1 else 0 end) as exact_apply_function;
select 1/(case when (select count(*) from public.product_spec_research_receipts)=0
  and (select count(*) from public.spec_facts where source='research')=0 then 1 else 0 end) as nothing_applied;
select (select count(*) from public.product_spec_research_readiness) as readiness_rows,
 (select count(*) from public.product_spec_research_readiness where enabled) as enabled_readiness,
 (select count(*) from public.product_spec_research_applications) as registered_applications;
