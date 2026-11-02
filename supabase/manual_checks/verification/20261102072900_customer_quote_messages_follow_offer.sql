-- Read-back of 20261102072900. Fails before the migration and passes after.

select
  (select count(*) from pg_trigger
    where tgrelid = 'public.customer_quote_offers'::regclass
      and tgname = 'trg_customer_quote_offers_close_messages' and not tgisinternal) as disparador;

select 1 / (case when exists (
  select 1 from pg_trigger
   where tgrelid = 'public.customer_quote_offers'::regclass
     and tgname = 'trg_customer_quote_offers_close_messages'
     and not tgisinternal and tgenabled = 'O'
     and pg_get_triggerdef(oid) like '%AFTER UPDATE OF status ON public.customer_quote_offers FOR EACH ROW%'
) then 1 else 0 end) as afirma_disparador;

select 1 / (case when
  (select prosecdef from pg_proc where oid = 'public.customer_quote_offers_close_messages()'::regprocedure)
  and not has_function_privilege('authenticated', 'public.customer_quote_offers_close_messages()', 'EXECUTE')
then 1 else 0 end) as afirma_funcion_cerrada;
