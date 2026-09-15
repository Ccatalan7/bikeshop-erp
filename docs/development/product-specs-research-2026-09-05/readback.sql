-- Read-only production assertions. A false invariant raises at SQL level.
select 1 / case when bool_and(to_regprocedure(e.key) is not null and
  md5(pg_get_functiondef(to_regprocedure(e.key)))=e.value) then 1 else 0 end as exact_function_definitions
from jsonb_each_text($expected${"spec_rule_set_internal_v1(jsonb)":"9f8fad12ec3729ddfb376246a9aa79ce","get_product_spec_snapshot_v1(uuid)":"180c131636eebed774aeebdfb4a14435","spec_rule_known_internal_v1(jsonb)":"db7a2cfdfa5061de8b965e9a5e916518","spec_product_revision_internal_v1()":"b094ece92ab8505baa3262b0be1e639f","get_product_spec_contexts_v1(uuid[])":"5190cde862b60b351cedc46bf79ed041","get_product_spec_references_v1(text)":"a5b42a3914d654170a43b2c8a16c626f","spec_contract_revision_internal_v1()":"b28e66de272dff52b6b8dae30042b71f","spec_product_constraint_internal_v1()":"a433db96f91cf69c1976f1972649a202","spec_product_fact_graph_internal_v1()":"ac97d0940122e6e665f526507321e515","spec_product_payload_internal_v1(uuid)":"d65a4cd1fff1414b8e1ae027ea8dbd10","spec_reference_immutable_internal_v1()":"099d85df64494999495a08c6563b64bb","spec_rule_normalize_internal_v1(jsonb)":"6cfad8c9e6fa3d2ca8a08dc279394191","spec_condition_internal_v1(jsonb,jsonb)":"a5ca43af3ac118c3c5c560d57ba0e7e6","spec_payload_display_internal_v1(jsonb)":"6915ca93061a09dba339aa1e0e3ea602","spec_validate_product_internal_v1(uuid)":"f57e58b871a767f8b170d61d169034c0","get_public_product_technical_specs(uuid,uuid)":"16a58c51cd6402c93fecca5be88c1d80","save_product_spec_facts_v1(uuid,uuid[],jsonb)":"748a15f661dcafedad468b0bddb287ee","spec_write_payload_internal_v2(uuid,uuid,jsonb,text)":"1eaf7758c45a721f48777aed10d86143","spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)":"0050b6ccc5ccec5d94934e7005ab2b59","save_product_with_specs_v1(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamp with time zone,jsonb)":"66b69b3594b6ede2e102348e054d5b09"}$expected$::jsonb) e;
select 1 / case when count(*)=3 and bool_and(jsonb_array_length(public.spec_validate_draft_internal_v1(
  (select id from public.spec_templates where key='chain' and tenant_id is null),
  public.spec_payload_display_internal_v1(fact_values),id,brand,model,manufacturer_sku))=0)
then 1 else 0 end as manufacturer_references_valid
from public.product_spec_references where id in ('kmc-x8-bx08ng114-eu-20260905','kmc-eglide-us-20260905','kmc-x11-us-118-20260905');
select 1 / case when count(*)>0 and bool_and(contract_version>=2 and form_contract->>'version'='1') then 1 else 0 end as all_active_templates_versioned
from public.spec_templates where is_active;
select 1 / case when not has_function_privilege('anon','public.get_product_spec_snapshot_v1(uuid)','execute')
  and not has_function_privilege('authenticated','public.spec_write_payload_internal_v2(uuid,uuid,jsonb,text)','execute')
  and has_function_privilege('authenticated','public.save_product_with_specs_v1(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamptz,jsonb)','execute')
  and not has_table_privilege('authenticated','public.product_spec_references','insert')
  and not has_table_privilege('authenticated','public.product_spec_save_receipts','select')
then 1 else 0 end as effective_permissions;
select 1 / case when public.spec_condition_internal_v1('{"field":"x","operator":"neq","value":"A"}','{}') is null
  and public.spec_rule_known_internal_v1('false') and public.spec_rule_known_internal_v1('0')
then 1 else 0 end as unknown_is_not_false;
select 1 / case when count(*)=3 then 1 else 0 end as deferred_guards
from pg_trigger where tgname in ('product_spec_identity_constraint','product_spec_fact_constraint','product_spec_value_constraint') and tgdeferrable and tginitdeferred;
select 1 / case when count(*)=4 then 1 else 0 end as metadata_revision_guards
from pg_trigger where tgname in ('product_spec_template_revision','product_spec_field_revision','product_spec_definition_revision','product_spec_option_revision');
