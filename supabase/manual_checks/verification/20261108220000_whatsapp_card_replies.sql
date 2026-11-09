-- Read-back of 20261108220000. Fails before the migration and passes after:
-- * an applied WhatsApp approval queues the thank-you reply;
-- * «Tengo una consulta» on a quote card is answered by the trigger;
-- * the reply helper is closed and apply keeps its grants.

select 1 / (case when
  position('whatsapp_card_reply_internal' in pg_get_functiondef(
    'public.apply_whatsapp_job_action(uuid,text,text,jsonb,text,bigint)'::regprocedure)) > 0
then 1 else 0 end) as aprobar_responde;

select 1 / (case when exists (
  select 1 from pg_trigger t
   where t.tgrelid = 'public.messages'::regclass
     and t.tgname = 'trg_messages_whatsapp_card_question_reply'
     and t.tgenabled <> 'D')
then 1 else 0 end) as consulta_responde;

select 1 / (case when
  not has_function_privilege('authenticated', 'public.whatsapp_card_reply_internal(uuid,uuid,uuid,text,uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.whatsapp_card_reply_internal(uuid,uuid,uuid,text,uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.whatsapp_card_reply_internal(uuid,uuid,uuid,text,uuid,text,text)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.apply_whatsapp_job_action(uuid,text,text,jsonb,text,bigint)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.apply_whatsapp_job_action(uuid,text,text,jsonb,text,bigint)', 'EXECUTE')
then 1 else 0 end) as permisos_cerrados;
