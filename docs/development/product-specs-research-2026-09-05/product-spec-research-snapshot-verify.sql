-- Read-only post-deploy verification. Never synthesizes an authenticated actor.
with expected(signature,body_md5,definer,authenticated_execute,volatility) as (values
 ('get_product_spec_references_v1(text)','ac13815c1272725a784596953b771531',true,true,'s'),
 ('get_product_spec_references_v2(text)','ffb27b5770dee7a7ce0675eea552ce9b',true,true,'s'),
 ('get_product_spec_research_snapshot_v1(uuid)','981026d3283612b825ff3231d0d9ab41',true,true,'s'),
 ('preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text)','a48f8882900af7d7e945ad4cbc561df2',true,true,'s'),
 ('spec_merge_research_rows_internal_v1(jsonb,jsonb)','079b3e15c5db9903476f94801394691d',false,false,'i'),
 ('spec_reference_global_scope_internal_v1(text)','f60238e0b53dabe706b1939af477b96a',false,false,'s')
), checked as (
 select e.signature,p.oid is not null
  and md5(pg_get_functiondef(p.oid))=e.body_md5
  and pg_get_userbyid(p.proowner)='postgres'
  and p.prosecdef=e.definer and p.provolatile::text=e.volatility
  and p.proconfig=array['search_path=pg_catalog, public, pg_temp']::text[]
  and not has_function_privilege('anon',p.oid,'execute')
  and has_function_privilege('authenticated',p.oid,'execute')=e.authenticated_execute
  and has_function_privilege('service_role',p.oid,'execute')
  and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where a.grantee not in ('postgres'::regrole::oid,'service_role'::regrole::oid,
      case when e.authenticated_execute then 'authenticated'::regrole::oid else 'postgres'::regrole::oid end)
      or a.grantor<>p.proowner or a.is_grantable or a.privilege_type<>'EXECUTE') ok
 from expected e left join pg_proc p on p.oid=to_regprocedure('public.'||e.signature)
)
select 1/case when count(*)=6 and bool_and(coalesce(ok,false)) then 1 else 0 end
 research_snapshot_functions_verified from checked;

select p.oid::regprocedure::text signature,md5(pg_get_functiondef(p.oid)) body_md5,
 pg_get_userbyid(p.proowner) owner,p.prosecdef,p.provolatile,p.proconfig,p.proacl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
 'get_product_spec_references_v1','get_product_spec_references_v2',
 'get_product_spec_research_snapshot_v1','preview_product_spec_research_v1',
 'spec_merge_research_rows_internal_v1','spec_reference_global_scope_internal_v1')
order by p.proname;
