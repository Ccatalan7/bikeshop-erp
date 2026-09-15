-- Read-only executable pins for the reviewed field-condition implementation.
with expected(signature,hash,acl,security_definer,volatility) as (values
 ('spec_template_condition_internal_v1(jsonb,jsonb)','b069c020eac9ddc2c088dbbab3bdd091','{postgres=X/postgres,service_role=X/postgres}',false,'i'),
 ('spec_template_rules_guard_internal_v1()','93b6939f2eac40107abfdabb2d27895c','{postgres=X/postgres,service_role=X/postgres}',true,'v'),
 ('spec_template_rules_validate_internal_v1(uuid)','06cbe78b729c4b3a683c7f6d0c2379f9','{postgres=X/postgres,service_role=X/postgres}',true,'v'),
 ('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)','0a9d8a40eaad998ffb26d36170a4c93e','{postgres=X/postgres,service_role=X/postgres}',false,'s')
), checked as (
 select e.*,p.oid,p.proacl,p.prosecdef,p.provolatile,p.proowner,p.proconfig
 from expected e left join pg_proc p on p.oid=to_regprocedure('public.'||e.signature)
)
select 1/case when count(*)=4 and bool_and(oid is not null and md5(pg_get_functiondef(oid))=hash
 and proacl::text=acl and prosecdef=security_definer and provolatile::text=volatility
 and pg_get_userbyid(proowner)='postgres' and proconfig=array['search_path=pg_catalog, public, pg_temp']::text[])
 then 1 else 0 end field_conditions_function_assertion from checked;
with expected(name,relation,hash) as (values
 ('product_spec_definition_revision','spec_definitions','74dc221b889aae1ba07e69ff0870ef42'),
 ('spec_definition_template_rules_guard','spec_definitions','7ea2735625ae81d1aceda141d16fa151'),
 ('spec_template_field_rules_guard','spec_template_fields','e7cef22d324ebdc92894454d91c0c0de'),
 ('spec_template_rules_guard','spec_templates','277df089eb89e702af996630bda57279')
), checked as (
 select e.*,t.oid,t.tgenabled from expected e left join pg_trigger t
 on t.tgname=e.name and t.tgrelid=('public.'||e.relation)::regclass
)
select 1/case when count(*)=4 and bool_and(oid is not null and tgenabled='O' and md5(pg_get_triggerdef(oid))=hash)
 then 1 else 0 end field_conditions_trigger_assertion from checked;
select 1/case when not has_function_privilege('authenticated','public.spec_template_condition_internal_v1(jsonb,jsonb)','execute')
 and not has_function_privilege('anon','public.spec_template_rules_validate_internal_v1(uuid)','execute')
 and has_function_privilege('authenticated','public.save_product_with_specs_v1(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamp with time zone,jsonb)','execute')
 then 1 else 0 end field_conditions_acl_assertion;
