-- Read-back of 20261108200000. Fails before the migration and passes after:
-- * a repeated tap of the recorded answer is answered as the same decision;
-- * only the service role can apply a WhatsApp job action.

select 1 / (case when
  position('repeated_answer' in
    pg_get_functiondef('public.apply_whatsapp_job_action(uuid,text,text,jsonb,text,bigint)'::regprocedure)) > 0
then 1 else 0 end) as toque_repetido_no_es_rechazo;

select 1 / (case when
  has_function_privilege('service_role', 'public.apply_whatsapp_job_action(uuid,text,text,jsonb,text,bigint)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.apply_whatsapp_job_action(uuid,text,text,jsonb,text,bigint)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.apply_whatsapp_job_action(uuid,text,text,jsonb,text,bigint)', 'EXECUTE')
then 1 else 0 end) as solo_el_servicio_aplica;
