-- Read-back: la función resuelve la ventana de 24 h sin exponer el teléfono.
select
  1 / (case when exists (
    select 1 from pg_proc where proname = 'assistant_prepare_customer_contact_v1'
      and prosecdef and provolatile = 's'
  ) then 1 else 0 end) as funcion_existe,
  -- No devuelve el número, sólo si existe.
  1 / (case when (
    select prosrc from pg_proc where proname = 'assistant_prepare_customer_contact_v1'
  ) not like '%''contactPhone''%' then 1 else 0 end) as sin_telefono_expuesto,
  1 / (case when (
    select prosrc from pg_proc where proname = 'assistant_prepare_customer_contact_v1'
  ) like '%interval ''24 hours''%' then 1 else 0 end) as ventana_de_24h,
  -- Y hay al menos un cliente con conversación para probarla.
  1 / (case when exists (
    select 1 from public.conversation_contexts cc
    where cc.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and cc.context_type = 'customer'
  ) then 1 else 0 end) as hay_conversacion_de_cliente;
