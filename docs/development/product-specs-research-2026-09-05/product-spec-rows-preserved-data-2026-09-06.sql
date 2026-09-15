-- Compare the previous logical row shape; the new nullable storage column is not a fact edit.
-- Metadata-only sanitation must preserve every technical observation and identity.
with current_state as (select jsonb_build_object(
 'products', (select count(*) from public.products),
 'product_technical_identity_md5',(select md5(jsonb_agg(jsonb_build_array(id,tenant_id,category_id,brand,model,manufacturer_sku,spec_reference_id,spec_revision) order by id)::text) from public.products),
 'facts_md5',(select md5(jsonb_agg(to_jsonb(f)-'value_json' order by id)::text) from public.spec_facts f),
 'fact_options_md5',(select md5(jsonb_agg(to_jsonb(v) order by fact_id,position,value_id)::text) from public.spec_fact_values v),
 'readings_md5',(select md5(jsonb_agg(to_jsonb(r) order by fact_id)::text) from public.spec_fact_readings r),
 'category_mappings_md5',(select md5(jsonb_agg(to_jsonb(m)-'spec_template_active_guard' order by id)::text) from public.category_tech_mappings m),
 'templates_md5',(select md5(jsonb_agg(to_jsonb(t) order by id)::text) from public.spec_templates t),
 'receipts_md5',(select md5(coalesce(jsonb_agg(to_jsonb(r) order by tenant_id,operation_key),'[]')::text) from public.product_spec_save_receipts r)
) baseline) select 1/case when baseline=$baseline${"products":1665,"facts_md5":"18dd97595ce751864b9d1fb01302d4f6","readings_md5":"cf177c960938240251a88277890ca220","receipts_md5":"d751713988987e9331980363e24189ce","templates_md5":"0dcae696f4793a0c9314aa2546b08be7","fact_options_md5":"ce5b47bccf0a878598012a490f5378d0","category_mappings_md5":"708e71554a15bac93eef57783a82cce3","product_technical_identity_md5":"2116b227f079661b8bf2c994ac6f3f28"}$baseline$::jsonb then 1 else 0 end preserved_technical_data_assertion from current_state;

select 1/case when not exists(select 1 from public.spec_facts f where coalesce(to_jsonb(f)->'value_json'<>'null'::jsonb,false)) then 1 else 0 end no_structured_product_data_written;
