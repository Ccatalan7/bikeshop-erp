-- Read-back of 20261106270000. Fails before the migration (the
-- acknowledgment rule does not exist) and passes after.

select 1 / (case when
  to_regprocedure('public.mail_is_acknowledgment_internal(text, text)') is not null
  and not has_function_privilege('authenticated', 'public.mail_is_acknowledgment_internal(text, text)', 'EXECUTE')
  and pg_get_functiondef('public.mail_message_state_internal(uuid)'::regprocedure) like '%mail_is_acknowledgment_internal%'
  and public.mail_is_acknowledgment_internal('Caso registrado: AB-1', null)
  and not public.mail_is_acknowledgment_internal('Re: Caso registrado: AB-1', 'Le confirmamos la devolución.')
then 1 else 0 end) as de_quien_es_el_turno;
