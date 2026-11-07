-- Read-back of 20261106260000. Fails before the migration (the summary and
-- the view rule do not exist) and passes after.

select 1 / (case when
  to_regprocedure('public.mail_morning_summary_v1()') is not null
  and to_regprocedure('public.mail_in_view_internal(text, public.mail_messages, jsonb)') is not null
  and to_regprocedure('public.mail_expects_reply_internal(text)') is not null
  and to_regprocedure('public.mail_bank_named_internal(text)') is not null
  and has_function_privilege('authenticated', 'public.mail_morning_summary_v1()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mail_morning_summary_v1()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.mail_in_view_internal(text, public.mail_messages, jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.mail_message_state_internal(uuid)', 'EXECUTE')
  and pg_get_functiondef('public.mail_message_state_internal(uuid)'::regprocedure) like '%''remind''%'
  and pg_get_functiondef('public.mail_classify_message_internal(uuid)'::regprocedure) like '%to_party%'
  and pg_get_functiondef('public.mail_classify_message_internal(uuid)'::regprocedure) like '%fake_bank%'
  and pg_get_functiondef('public.mail_inbox_v2(text, text, text, integer, timestamptz, text)'::regprocedure)
      like '%mail_in_view_internal%'
  and pg_get_functiondef('public.mail_counts_v2(text)'::regprocedure) like '%mail_in_view_internal%'
  and public.mail_expects_reply_internal('¿Tienen stock?')
  and not public.mail_expects_reply_internal(E'Gracias.\n\nEl jue, Ana escribió:\n> ¿Me confirmas?')
  and public.mail_bank_named_internal('Banco de Chile') = 'Banco de Chile'
then 1 else 0 end) as lo_que_espera_respuesta;
