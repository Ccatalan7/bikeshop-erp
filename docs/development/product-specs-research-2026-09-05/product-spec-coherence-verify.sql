-- Executable read-only proof for the reviewed coherence forward.
with expected(signature,hash,acl,security_definer,volatility) as (values
 ('get_product_spec_typed_configurations_v1(uuid[])','0e71196e4ea36bae1b69f4e016947ff8','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'s'),
 ('get_public_product_technical_specs(uuid,uuid)','89e21f13bb41bdac92b17e62b059df06','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres,anon=X/postgres}',true,'s'),
 ('record_product_spec_reading_v1(uuid,text,jsonb,text,text)','39eaa8aca4660283e431bd064540bbc3','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}',true,'v'),
 ('spec_coherence_display_rows_internal_v1(jsonb,jsonb)','7eeeea10db32822bae62c076e06363dd','{postgres=X/postgres,service_role=X/postgres}',false,'i'),
 ('spec_coherence_fields_internal_v1(uuid)','e3b437887bdcbb2766d46805beb3a719','{postgres=X/postgres,service_role=X/postgres}',false,'s'),
 ('spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)','06dc1b93436b1ac5693142b2eace82ec','{postgres=X/postgres,service_role=X/postgres}',false,'i'),
 ('spec_coherence_labels_internal_v1(text,jsonb,jsonb)','7699347e366f71e9a3bce36c06420fa5','{postgres=X/postgres,service_role=X/postgres}',false,'i'),
 ('spec_coherence_metadata_internal_v1(jsonb,jsonb)','94ea287f2f4b1c0782253c722eb3e0e7','{postgres=X/postgres,service_role=X/postgres}',false,'i'),
 ('spec_coherence_pairs_internal_v1(jsonb,jsonb)','f8f1df3554fcb19199e1c62e55164a65','{postgres=X/postgres,service_role=X/postgres}',false,'i'),
 ('spec_coherence_publication_guard_internal_v1()','bcc98eaa28aeb87f265e569ba587c007','{postgres=X/postgres,service_role=X/postgres}',true,'v'),
 ('spec_template_rules_validate_internal_v1(uuid)','fc4875e265b52a847b6a63f406487f96','{postgres=X/postgres,service_role=X/postgres}',true,'v'),
 ('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)','25a18d1d600cf2d8da7c30a59e54123f','{postgres=X/postgres,service_role=X/postgres}',false,'s')
), checked as (
 select e.*,p.oid,p.proacl,p.prosecdef,p.provolatile,p.proowner,p.proconfig
 from expected e left join pg_proc p on p.oid=to_regprocedure('public.'||e.signature)
)
select 1/case when count(*)=12 and bool_and(oid is not null and md5(pg_get_functiondef(oid))=hash
 and proacl::text=acl and prosecdef=security_definer and provolatile::text=volatility
 and pg_get_userbyid(proowner)='postgres' and proconfig=array['search_path=pg_catalog, public, pg_temp']::text[])
 then 1 else 0 end coherence_function_assertion from checked;
select 1/case when
 exists(select 1 from pg_trigger where tgrelid='public.spec_templates'::regclass and tgname='spec_coherence_publication_guard'
   and not tgisinternal and tgdeferrable and tginitdeferred and tgenabled='O'
   and pg_get_triggerdef(oid) like '%AFTER INSERT OR UPDATE%' and tgfoid=to_regprocedure('public.spec_coherence_publication_guard_internal_v1()'))
 and exists(select 1 from pg_trigger where tgrelid='public.spec_definitions'::regclass and tgname='spec_definition_template_rules_guard'
   and tgdeferrable and tginitdeferred and tgenabled='O' and pg_get_triggerdef(oid) like '%old.validation_rules%' and pg_get_triggerdef(oid) like '%old.unit%')
 then 1 else 0 end coherence_trigger_assertion;
select 1/case when not has_function_privilege('anon','public.get_product_spec_typed_configurations_v1(uuid[])','execute')
 and has_function_privilege('authenticated','public.get_product_spec_typed_configurations_v1(uuid[])','execute')
 and not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'spec_coherence_%'
   and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute')))
 then 1 else 0 end coherence_acl_assertion;
-- Pure read smoke, independent of catalogue metadata and physical fitment.
select 1/case when public.spec_coherence_issues_internal_v1(
 '{"rules_version":2,"scalar_ordered_pairs":[["lo","hi"]]}',
 '{"lo":{"data_type":"number","unit":"mm"},"hi":{"data_type":"number","unit":"mm"}}',
 '{"lo":"0.100000000000000001","hi":"0.100000000000000000"}')
 @> '[{"code":"range_order","field":"lo","blocking":true},{"code":"range_order","field":"hi","blocking":true}]'::jsonb
 then 1 else 0 end coherence_exact_range_smoke;
