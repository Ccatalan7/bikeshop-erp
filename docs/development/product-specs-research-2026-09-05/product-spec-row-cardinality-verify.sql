-- Read-only exact function/security verification; no product fill or mechanical gate.
with expected(signature,digest,definer,volatility) as (values
 ('spec_coherence_fields_internal_v1(uuid)','842a6575f1eedcef45b7749b76e458e9',false,'s'),
 ('spec_coherence_metadata_internal_v1(jsonb,jsonb)','62b9c8349bf9d4fa4f983d3009980171',false,'i'),
 ('spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)','d57404a97c12b336e64b59202b3d56f4',false,'i'),
 ('spec_coherence_publication_guard_internal_v1()','235850d2afe7e1571431c7f7c4942b7b',true,'v'),
 ('spec_template_rules_validate_internal_v1(uuid)','61cc6156d8ec2f36a7e9a1cc47b95c53',true,'v'),
 ('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)','9ea12d82761d6ffd0584d460cbc998d6',false,'s')
), actual as (
 select e.*,p.oid,md5(pg_get_functiondef(p.oid)) actual_digest,pg_get_userbyid(p.proowner) owner_name,
   p.prosecdef,p.provolatile,p.proconfig,p.proacl
 from expected e left join pg_proc p on p.oid=to_regprocedure('public.'||e.signature)
)
select 1/case when count(*)=6 and bool_and(coalesce(actual_digest=digest and owner_name='postgres'
 and prosecdef=definer and provolatile::text=volatility
 and proconfig=array['search_path=pg_catalog, public, pg_temp']::text[]
 and proacl::text='{postgres=X/postgres,service_role=X/postgres}',false)) then 1 else 0 end as function_security_assertion,
 jsonb_agg(jsonb_build_object('signature',signature,'expected',digest,'actual',actual_digest) order by signature) as function_state
from actual;
