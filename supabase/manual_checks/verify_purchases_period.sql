-- Read-back: compras ya tiene período y totales verificados.
select
  1 / (case when exists (
    select 1 from pg_proc where proname = 'assistant_search_purchase_invoices_v1'
      and prosrc like '%p_relative_period%'
  ) then 1 else 0 end) as periodo_presente,
  1 / (case when exists (
    select 1 from pg_proc where proname = 'assistant_search_purchase_invoices_v1'
      and prosrc like '%matchedTotal%'
  ) then 1 else 0 end) as totales_verificados,
  -- Y el total real del mes existe para contrastar la respuesta.
  1 / (case when (
    select count(*) from public.purchase_invoice_list_read_model i
    where i.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and (i.date at time zone 'America/Santiago')::date
        between date_trunc('month', date '2026-08-21')::date and date '2026-08-21'
  ) >= 1 then 1 else 0 end) as hay_compras_del_mes;
