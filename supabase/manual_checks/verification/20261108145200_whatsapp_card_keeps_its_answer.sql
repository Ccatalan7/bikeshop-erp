-- Read-back of 20261108145200. Fails before the migration and passes after:
-- * completing an outbox send keeps a card's answer (`responded_at` rule);
-- * no WhatsApp card is left «accepted» without a customer answer;
-- * only the service role can complete an outbox send.

select 1 / (case when
  position('responded_at' in
    pg_get_functiondef('public.finish_whatsapp_outbox_v1(uuid,text,text,jsonb)'::regprocedure)) > 0
then 1 else 0 end) as tarjeta_conserva_respuesta;

select 1 / (case when not exists (
  select 1
    from public.messages m
   where m.type = 'action_request'
     and m.message_direction = 'outbound'
     and m.external_provider = 'whatsapp'
     and m.metadata->>'status' = 'accepted'
     and not (m.metadata ? 'responded_at')
     and coalesce(m.external_status, '') <> 'failed'
) then 1 else 0 end) as ninguna_tarjeta_pisada;

select 1 / (case when
  has_function_privilege('service_role', 'public.finish_whatsapp_outbox_v1(uuid,text,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.finish_whatsapp_outbox_v1(uuid,text,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.finish_whatsapp_outbox_v1(uuid,text,text,jsonb)', 'EXECUTE')
then 1 else 0 end) as solo_el_servicio_completa;
