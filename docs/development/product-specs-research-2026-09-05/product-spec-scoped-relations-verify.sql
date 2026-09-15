-- Read-only exact deployed contract; absent/drifted objects fail at SQL level.
with reviewed(signature,definition_md5) as(values
('spec_condition_internal_v1(jsonb,jsonb)','d4a28048452544d76cd7153117e4dcc4'),
('spec_reference_relations_guard_internal_v1()','46d959558160f469e0c0c9e95cdedffa'),
('spec_relation_assess_internal_v1(jsonb,jsonb)','30e08b04ea3bd6b3faa66ecc7ecf0402'),
('spec_relation_condition_internal_v1(jsonb,jsonb)','b63b594f1c1a92e8e268790eecebe9c6'),
('spec_relation_validate_internal_v1(jsonb)','3f547847018daeaaa67aba26e125981b'),
('spec_rule_number_internal_v1(jsonb)','402beae4c82ab3a7f38304e2a4f89415')) select 1/case when count(*)=6 and bool_and(coalesce(md5(pg_get_functiondef(to_regprocedure(signature)))=definition_md5,false)) then 1 else 0 end function_contract_assertion from reviewed;
select 1/case when exists(select 1 from pg_trigger where tgrelid='public.product_spec_references'::regclass and tgname='spec_reference_relations_guard' and tgenabled='O' and tgfoid='spec_reference_relations_guard_internal_v1()'::regprocedure) then 1 else 0 end reference_guard_assertion;
with signatures(signature) as(values ('spec_relation_condition_internal_v1(jsonb,jsonb)'),('spec_reference_relations_guard_internal_v1()'),('spec_relation_assess_internal_v1(jsonb,jsonb)'),('spec_relation_validate_internal_v1(jsonb)'),('spec_rule_number_internal_v1(jsonb)')) select 1/case when bool_and(not has_function_privilege('authenticated',signature,'EXECUTE') and not has_function_privilege('anon',signature,'EXECUTE')) then 1 else 0 end private_relation_helpers_assertion from signatures;
select 1/case when not exists(select 1 from public.product_spec_references r cross join lateral jsonb_array_elements(r.claims) c where c ? 'schema_version' and c->>'schema_version'<>'2') then 1 else 0 end existing_claim_versions_assertion;
