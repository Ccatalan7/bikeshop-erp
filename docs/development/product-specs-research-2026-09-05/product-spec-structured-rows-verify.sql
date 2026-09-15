-- Read only. These pins describe the reviewed structured-row implementation.
with expected(signature,md5,acl,security_definer,volatility) as (values
  ('get_product_spec_typed_configurations_v1(uuid[])','cdfe087a7aefbfcd4f9d7c1573f1041d','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'s'),
  ('get_public_product_technical_specs(uuid,uuid)','39a483344a232591c125a6704a542bc4','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres}',true,'s'),
  ('mirror_facts_into_product_specs_internal_v1()','317d1258c4d0b662cf2b78525238f2c4','{postgres=X/postgres,service_role=X/postgres}',true,'v'),
  ('save_product_spec_facts_v1(uuid,uuid[],jsonb)','b108fef679ba1ecb6768b07261dcde52','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'v'),
  ('spec_fact_value_shape_internal_v1()','7d1f271a2e0bd0d27832a60ea679b0fc','{=X/postgres,postgres=X/postgres,service_role=X/postgres}',false,'v'),
  ('spec_payload_display_internal_v1(jsonb)','4b968349fa25437f1c931ec50378f452','{postgres=X/postgres,service_role=X/postgres}',false,'s'),
  ('spec_product_payload_internal_v1(uuid)','a353807af49f812d0b349fbc6f112c4c','{postgres=X/postgres,service_role=X/postgres}',false,'s'),
  ('spec_rows_definition_guard_internal_v1()','80993f8ada4395792512f3f783f71abe','{postgres=X/postgres,service_role=X/postgres}',true,'v'),
  ('spec_rows_display_internal_v1(jsonb,jsonb)','d9d008b84a3e9c69cc44f6a5d2fa2300','{postgres=X/postgres,service_role=X/postgres}',false,'i'),
  ('spec_rows_fact_guard_internal_v1()','4b5cd3700daeb26f34b18ecb0a5ad439','{postgres=X/postgres,service_role=X/postgres}',true,'v'),
  ('spec_rows_reference_guard_internal_v1()','69af5b011d214f3b0009a33e0685a1c9','{postgres=X/postgres,service_role=X/postgres}',true,'v'),
  ('spec_rows_schema_validate_internal_v1(jsonb)','e4147389be641a0c61e0f625c676e39b','{postgres=X/postgres,service_role=X/postgres}',false,'i'),
  ('spec_rows_validate_internal_v1(jsonb,jsonb)','79623b3e97219d95b035aa0705be7757','{postgres=X/postgres,service_role=X/postgres}',false,'i'),
  ('spec_source_url_valid_internal_v1(text)','562a31f106b7286b3c8347499c56929d','{postgres=X/postgres,service_role=X/postgres}',false,'i'),
  ('spec_unassigned_facts_internal_v1(uuid,uuid)','3bf820b8dc28859670c5d0fa5e11f89e','{postgres=X/postgres,service_role=X/postgres}',false,'s'),
  ('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)','76a3e46dd75f5a3c444bbf3755ab0bc6','{postgres=X/postgres,service_role=X/postgres}',false,'s'),
  ('spec_write_payload_internal_v2(uuid,uuid,jsonb,text)','4000850abcb96fe223f1df53584eadfb','{postgres=X/postgres,service_role=X/postgres}',true,'v')
), checked as (
 select e.*,p.oid,p.proacl,p.prosecdef,p.provolatile,p.proowner,p.proconfig
 from expected e left join pg_proc p on p.oid=to_regprocedure('public.'||e.signature)
)
select 1/case when count(*)=17 and bool_and(oid is not null and
 md5(pg_get_functiondef(oid))=md5 and proacl::text=acl and prosecdef=security_definer
 and provolatile::text=volatility and pg_get_userbyid(proowner)='postgres'
 and proconfig=array['search_path=pg_catalog, public, pg_temp']::text[]) then 1 else 0 end
 structured_rows_function_assertion from checked;
select 1/case when exists(select 1 from information_schema.columns where table_schema='public'
 and table_name='spec_facts' and column_name='value_json' and data_type='jsonb' and is_nullable='YES')
 and (select count(*) from pg_trigger where not tgisinternal and tgenabled='O' and
 (tgname,tgrelid::regclass::text,tgtype::integer) in
 (('spec_rows_definition_guard','spec_definitions',31),('spec_rows_fact_guard','spec_facts',23),
 ('spec_rows_reference_guard','product_spec_references',23)))=3 then 1 else 0 end structured_rows_storage_assertion;
select 1/case when not has_function_privilege('anon','get_product_spec_typed_configurations_v1(uuid[])','execute')
 and has_function_privilege('authenticated','get_product_spec_typed_configurations_v1(uuid[])','execute')
 and not has_function_privilege('authenticated','spec_rows_validate_internal_v1(jsonb,jsonb)','execute')
 and not has_function_privilege('authenticated','spec_write_payload_internal_v2(uuid,uuid,jsonb,text)','execute')
 then 1 else 0 end structured_rows_acl_assertion;
