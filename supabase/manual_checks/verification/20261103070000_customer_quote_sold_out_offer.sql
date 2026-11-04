-- Read-back of 20261103070000. Fails before the migration and passes after.
-- The request's refusal is 20261103080000's (its own read-back).

select
  (select count(*) from public.customer_quote_sold_out_brands) as marcas_que_se_cotizan_sin_stock,
  (select count(*) from public.product_on_order_terms where quote_when_sold_out is not null)
    as fichas_con_decision_propia;

select 1 / (case when
  to_regclass('public.customer_quote_sold_out_brands') is not null
  and exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'product_on_order_terms'
       and column_name = 'quote_when_sold_out')
  and has_function_privilege('anon', 'public.get_public_sold_out_offers_v1(uuid, uuid[])', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.customer_quote_sold_out_mode_internal(uuid, uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.customer_quote_sold_out_mode_internal(uuid, uuid, uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_sold_out_summary_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_sold_out_summary_v1(uuid)', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.customer_quote_sold_out_brands', 'INSERT')
  and pg_get_functiondef('public.set_product_on_order_terms_v1(uuid, uuid, jsonb)'::regprocedure)
    like '%quote_when_sold_out%'
  and pg_get_functiondef('public.update_customer_quote_settings_v1(uuid, jsonb)'::regprocedure)
    like '%sold_out_brand_ids%'
then 1 else 0 end) as afirma_agotados_que_se_cotizan;
