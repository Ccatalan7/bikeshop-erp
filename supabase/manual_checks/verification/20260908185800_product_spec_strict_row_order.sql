-- Pure SELECT read-back: body, owner, ACL, mode and exact return behavior.
with expected as (select value w from jsonb_array_elements('[{"acl": "{postgres=X/postgres,service_role=X/postgres}", "md5": "c21cb764086b89a50c5580ad72c0c970", "settings": ["search_path=pg_catalog, public, pg_temp"], "signature": "spec_rows_schema_validate_internal_v1(jsonb)", "owner_name": "postgres", "volatility": "i", "security_definer": false, "before_md5": "e4147389be641a0c61e0f625c676e39b"}, {"acl": "{postgres=X/postgres,service_role=X/postgres}", "md5": "a7e629a22356148871253ad48ef25b3f", "settings": ["search_path=pg_catalog, public, pg_temp"], "signature": "spec_rows_validate_internal_v1(jsonb,jsonb)", "owner_name": "postgres", "volatility": "i", "security_definer": false, "before_md5": "79623b3e97219d95b035aa0705be7757"}]'::jsonb)), checked as (
 select w,p.oid,md5(pg_get_functiondef(p.oid)) body_md5,pg_get_userbyid(p.proowner) owner_name,
 p.proacl::text acl,p.prosecdef security_definer,p.provolatile::text volatility,
 to_jsonb(p.proconfig) settings from expected left join pg_proc p
 on p.oid=to_regprocedure('public.'||(w->>'signature')))
select 1/(case when count(*)=2 and bool_and(oid is not null and body_md5=w->>'md5'
 and owner_name=w->>'owner_name' and acl=w->>'acl'
 and security_definer=(w->>'security_definer')::boolean and volatility=w->>'volatility'
 and settings=w->'settings') then 1 else 0 end) as exact_strict_row_functions from checked;
with checked as materialized (select public.spec_rows_schema_validate_internal_v1(
 validation_rules->'rows_schema') as result from public.spec_definitions
 where validation_rules ? 'rows_schema')
select count(*) as existing_row_schemas_validated,
 count(result) as nonnull_void_results from checked;
select 1/(case when public.spec_rows_validate_internal_v1('{"version": 2, "columns": [{"key": "inner", "label": "Diámetro interior", "type": "decimal", "unit": "mm", "required": true, "validation": {"positive": true}}, {"key": "outer", "label": "Diámetro exterior", "type": "decimal", "unit": "mm", "required": true, "validation": {"positive": true}}, {"key": "minimum", "label": "Mínimo", "type": "decimal", "unit": "bar"}, {"key": "maximum", "label": "Máximo", "type": "decimal", "unit": "bar"}, {"key": "name", "label": "Modelo", "type": "text"}, {"key": "middle", "label": "Cota intermedia", "type": "decimal", "unit": "mm"}], "strict_ordered_pairs": [["inner", "outer"]], "ordered_pairs": [["minimum", "maximum"]]}'::jsonb,
 '{"schema_version": 2, "rows": [{"id": "readback-body", "values": {"inner": "30", "outer": "41.8"}, "sources": []}]}'::jsonb)='{"schema_version": 2, "rows": [{"id": "readback-body", "values": {"inner": "30", "outer": "41.8"}, "sources": []}]}'::jsonb then 1 else 0 end) as strict_body_roundtrip;
