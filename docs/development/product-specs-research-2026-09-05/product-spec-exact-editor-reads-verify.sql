-- Read-only assertions for the exact scalar editor/reference RPC boundary.
with expected(signature,hash,acl,security_definer,volatility) as (values
 ('get_product_spec_editor_context_v2(uuid,uuid)','ffc95bc18f46105a9b7dc3a702e485a6','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'s'),
 ('get_product_spec_references_v2(text)','9fa7a332a7002cbdfe9a815d246096fb','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'s'),
 ('spec_editor_rule_numbers_as_text_internal_v1(jsonb)','4d73e8cbbaeb6dd2c373f4369dacbba5','{postgres=X/postgres,service_role=X/postgres}',false,'i'),
 ('spec_json_numbers_as_text_internal_v1(jsonb)','29bc24fcc3975cc2ad6ba42268da60d4','{postgres=X/postgres,service_role=X/postgres}',false,'i'),
 ('spec_payload_display_exact_internal_v1(jsonb)','052421b50d689600494ef0f7ab33dc73','{postgres=X/postgres,service_role=X/postgres}',false,'s')
), checked as (
 select e.*,p.oid,p.proacl,p.prosecdef,p.provolatile,p.proowner,p.proconfig
 from expected e left join pg_proc p on p.oid=to_regprocedure('public.'||e.signature)
)
select 1/case when count(*)=5 and bool_and(oid is not null and md5(pg_get_functiondef(oid))=hash
 and proacl::text=acl and prosecdef=security_definer and provolatile::text=volatility
 and pg_get_userbyid(proowner)='postgres' and proconfig=array['search_path=pg_catalog, public, pg_temp']::text[])
 then 1 else 0 end exact_editor_function_assertion from checked;
select 1/case when not has_function_privilege('authenticated','public.spec_payload_display_exact_internal_v1(jsonb)','execute')
 and not has_function_privilege('anon','public.get_product_spec_editor_context_v2(uuid,uuid)','execute')
 and not has_function_privilege('anon','public.get_product_spec_references_v2(text)','execute')
 and has_function_privilege('authenticated','public.get_product_spec_editor_context_v2(uuid,uuid)','execute')
 and has_function_privilege('authenticated','public.get_product_spec_references_v2(text)','execute')
 then 1 else 0 end exact_editor_acl_assertion;

-- Existing readers and display contracts remain byte-identical.
with expected(signature,hash,acl) as (values
 ('get_product_spec_editor_context_v1(uuid,uuid)','f22771ee06c6934df9637f11a2e8030c','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
 ('spec_payload_display_internal_v1(jsonb)','4b968349fa25437f1c931ec50378f452','{postgres=X/postgres,service_role=X/postgres}'),
 ('spec_template_product_payload_internal_v1(uuid,uuid,boolean)','a56ef26e739ff4b3687d9f07f9065cb0','{postgres=X/postgres,service_role=X/postgres}'),
 ('get_product_spec_references_v1(text)','a5b42a3914d654170a43b2c8a16c626f','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
 ('spec_unassigned_facts_internal_v1(uuid,uuid)','3bf820b8dc28859670c5d0fa5e11f89e','{postgres=X/postgres,service_role=X/postgres}')
) select 1/case when count(*)=5 and bool_and(p.oid is not null and md5(pg_get_functiondef(p.oid))=e.hash and p.proacl::text=e.acl) then 1 else 0 end exact_editor_legacy_assertion from expected e left join pg_proc p on p.oid=to_regprocedure('public.'||e.signature);
