-- Read-back of 20261102175500. Fails before the migration and passes after.

select
  has_function_privilege('anon', 'public.request_public_customer_quote_v1(uuid, jsonb)', 'EXECUTE')
    as anon_puede_cotizar,
  (select attgenerated from pg_attribute
    where attrelid = 'public.customer_quotes'::regclass and attname = 'preferred_channel')
    as canal_calculado;

select 1 / (case when
  not has_function_privilege('anon', 'public.request_public_customer_quote_v1(uuid, jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.request_public_customer_quote_v1(uuid, jsonb)', 'EXECUTE')
  and pg_get_functiondef('public.request_public_customer_quote_v1(uuid, jsonb)'::regprocedure)
    like '%quote_account_required%'
then 1 else 0 end) as afirma_cuenta_obligatoria;

select 1 / (case when
  (select count(*) from pg_attribute
    where attrelid = 'public.customer_quotes'::regclass
      and attname in ('notify_email', 'notify_whatsapp')
      and attnotnull and not attisdropped) = 2
  and (select attgenerated from pg_attribute
        where attrelid = 'public.customer_quotes'::regclass and attname = 'preferred_channel') = 's'
  and (select count(*) from pg_constraint
        where conrelid = 'public.customer_quotes'::regclass
          and conname in ('customer_quotes_notify', 'customer_quotes_notify_reachable')) = 2
then 1 else 0 end) as afirma_avisos_elegidos;

select 1 / (case when
  pg_get_functiondef('public.customer_quote_enqueue_message_internal(uuid, text, uuid)'::regprocedure)
    like '%notify_whatsapp%'
  and pg_get_functiondef('public.customer_quote_inbox_v1(uuid, text, integer, integer)'::regprocedure)
    like '%notifyWhatsapp%'
  and exists (
    select 1 from pg_trigger
     where tgrelid = 'public.customers'::regclass
       and tgname = 'trg_customers_quotes_follow_account'
       and not tgisinternal
  )
then 1 else 0 end) as afirma_mensajes_y_cuenta;
