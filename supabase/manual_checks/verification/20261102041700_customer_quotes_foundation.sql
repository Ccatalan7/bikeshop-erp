-- Read-back of 20261102041700. Fails before the migration and passes after.

select
  (select count(*)
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relrowsecurity
      and c.relname in (
        'customer_quote_settings', 'product_on_order_terms', 'customer_quotes',
        'customer_quote_lines', 'customer_quote_offers', 'customer_quote_offer_lines',
        'customer_quote_supplier_tasks', 'customer_quote_events', 'customer_quote_access_tokens'
      )) as tablas_con_rls,
  (select count(*)
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname like 'customer_quote%'
           or p.proname in ('request_public_customer_quote_v1', 'get_public_customer_quote_v1',
                            'respond_public_customer_quote_v1', 'get_public_on_order_terms_v1',
                            'create_staff_customer_quote_v1', 'set_product_on_order_terms_v1',
                            'update_customer_quote_settings_v1', 'expire_customer_quote_offers_v1'))) as funciones;

select 1 / (case when (
  select count(*)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relrowsecurity
     and c.relname in (
       'customer_quote_settings', 'product_on_order_terms', 'customer_quotes',
       'customer_quote_lines', 'customer_quote_offers', 'customer_quote_offer_lines',
       'customer_quote_supplier_tasks', 'customer_quote_events', 'customer_quote_access_tokens'
     )
) = 9 then 1 else 0 end) as afirma_tablas;

select 1 / (case when
  has_function_privilege('anon', 'public.request_public_customer_quote_v1(uuid,jsonb)', 'EXECUTE')
  and has_function_privilege('anon', 'public.get_public_customer_quote_v1(text)', 'EXECUTE')
  and has_function_privilege('anon', 'public.respond_public_customer_quote_v1(text,jsonb)', 'EXECUTE')
  and has_function_privilege('anon', 'public.get_public_on_order_terms_v1(uuid,uuid[])', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_inbox_v1(uuid,text,integer,integer)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_detail_v1(uuid,uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_confirm_line_v1(uuid,uuid,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_send_offer_v1(uuid,uuid,uuid,text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_revise_offer_v1(uuid,uuid,uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_cancel_v1(uuid,uuid,uuid,text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.create_staff_customer_quote_v1(uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_send_offer_v1(uuid,uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_detail_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.customer_quote_prepare_offer_internal(uuid,text,uuid,uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_issue_token_internal(uuid,text[],timestamp with time zone,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.expire_customer_quote_offers_v1()', 'EXECUTE')
  and not has_table_privilege('anon', 'public.customer_quotes', 'SELECT')
  and not has_table_privilege('authenticated', 'public.customer_quotes', 'INSERT')
  and not has_table_privilege('authenticated', 'public.customer_quote_access_tokens', 'SELECT')
then 1 else 0 end) as afirma_permisos;

select 1 / (case when (
  select count(*)
    from pg_trigger
   where not tgisinternal
     and tgenabled = 'O'
     and (tgrelid, tgname) in (
       ('public.customer_quote_events'::regclass, 'trg_customer_quote_events_append_only'),
       ('public.customer_quote_offers'::regclass, 'trg_customer_quote_offers_frozen'),
       ('public.customer_quote_offer_lines'::regclass, 'trg_customer_quote_offer_lines_frozen')
     )
) = 3 then 1 else 0 end) as afirma_historia_y_oferta_congeladas;

-- The shop answers with the default values while it has no settings row.
select 1 / (case when (
  select s.offer_validity_hours = 72 and s.on_order_prepay_percent = 100
    from public.customer_quote_settings_internal('5443b130-cc28-45af-a420-cd500b288890') s
) then 1 else 0 end) as afirma_ajustes_por_omision;

-- The promised stock reads against the live catalog and its web reservations.
select 1 / (case when (
  select public.customer_quote_available_stock_internal(p.tenant_id, p.id) between 0 and greatest(p.inventory_qty, 0)
    from public.products p
   where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
     and coalesce(p.track_stock, true)
   order by p.updated_at desc
   limit 1
) then 1 else 0 end) as afirma_stock_disponible;

-- The expiry job is scheduled (only its name and schedule are read).
select 1 / (case when exists (
  select 1
    from cron.job
   where jobname = 'vinabike_expire_customer_quote_offers'
     and schedule = '7,22,37,52 * * * *'
) then 1 else 0 end) as afirma_vencimiento_programado;
