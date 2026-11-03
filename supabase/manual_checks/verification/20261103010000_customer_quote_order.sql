-- Read-back of 20261103010000. Fails before the migration and passes after.

select
  has_function_privilege('anon', 'public.accept_public_customer_quote_v1(text, jsonb)', 'EXECUTE')
    as anon_acepta_con_enlace,
  (select count(*) from public.online_order_items where fulfillment = 'on_order')
    as lineas_a_pedido,
  (select string_agg(jobname || ' ' || schedule, ', ') from cron.job
    where jobname = 'vinabike_customer_quote_order_arrivals')
    as revision_de_llegadas;

-- The order line knows where it comes from, and nothing old changed source.
select 1 / (case when
  (select count(*) from pg_attribute
    where attrelid = 'public.online_order_items'::regclass and not attisdropped
      and attname in ('fulfillment', 'customer_quote_offer_line_id', 'on_order_supplier_id',
                      'lead_days_min', 'lead_days_max', 'arrived_at')) = 6
  and (select count(*) from pg_constraint
        where conrelid = 'public.online_order_items'::regclass
          and conname in ('online_order_items_fulfillment_check', 'online_order_items_arrival_shape',
                          'online_order_items_lead_days')) = 3
  and not exists (select 1 from public.online_order_items where fulfillment is distinct from 'stock'
                    and customer_quote_offer_line_id is null)
  and (select relrowsecurity from pg_class
        where oid = 'public.customer_quote_purchase_orders'::regclass)
then 1 else 0 end) as afirma_lineas_y_pedidos_a_proveedor;

-- Who may call what: the link accepts and opens the order; staff checks
-- arrivals; the internals are nobody's.
select 1 / (case when
  has_function_privilege('anon', 'public.open_public_customer_quote_order_v1(text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.customer_quote_order_check_arrivals_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_order_check_arrivals_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_orders_check_arrivals_v1()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.customer_quote_orders_check_arrivals_v1()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.customer_quote_order_paid_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_order_fill_line_internal(uuid)', 'EXECUTE')
then 1 else 0 end) as afirma_permisos;

-- The order kernel waits for what comes on order instead of selling stock
-- that is not there.
select 1 / (case when
  (select bool_and(def like '%customer_quote_order_waiting_internal%')
     from (select pg_get_functiondef(oid) as def from pg_proc
            where pronamespace = 'public'::regnamespace
              and proname in ('process_online_order_internal', 'process_mercadopago_payment_observation',
                              'confirm_online_order_payment')) f)
  and (select bool_and(def like '%on_order%')
     from (select pg_get_functiondef(oid) as def from pg_proc
            where pronamespace = 'public'::regnamespace
              and proname in ('reserve_online_order_item_inventory',
                              'renew_online_order_inventory_reservations')) f)
  and (select bool_or(pg_get_functiondef(oid) like '%quote_accept_requires_checkout%')
         from pg_proc where pronamespace = 'public'::regnamespace
          and proname = 'respond_public_customer_quote_v1')
  and exists (select 1 from pg_trigger
               where tgrelid = 'public.online_order_events'::regclass
                 and tgname = 'trg_customer_quote_order_event_mirror' and not tgisinternal)
  and exists (select 1 from cron.job where jobname = 'vinabike_customer_quote_order_arrivals')
then 1 else 0 end) as afirma_nucleo_del_pedido;
