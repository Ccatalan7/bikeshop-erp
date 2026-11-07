-- Read-back of 20261106250000. Fails before the migration (the function does
-- not exist) and passes after.

select 1 / (case when
  to_regprocedure('public.mail_payment_candidates_v1(uuid)') is not null
  and has_function_privilege('authenticated', 'public.mail_payment_candidates_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mail_payment_candidates_v1(uuid)', 'EXECUTE')
  and pg_get_functiondef('public.mail_payment_candidates_v1(uuid)'::regprocedure) like '%mail_require_staff_internal%'
  and pg_get_functiondef('public.mail_payment_candidates_v1(uuid)'::regprocedure) like '%mb.is_active%'
then 1 else 0 end) as cobros_de_una_transferencia;
