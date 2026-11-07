-- Read-back of 20261106230000. Fails before the migration (the v2 reads do
-- not exist) and passes after.

select 1 / (case when
  to_regprocedure('public.mail_inbox_v2(text, text, text, integer, timestamptz, text)') is not null
  and to_regprocedure('public.mail_counts_v2(text)') is not null
  and has_function_privilege('authenticated', 'public.mail_inbox_v2(text, text, text, integer, timestamptz, text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mail_counts_v2(text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mail_inbox_v2(text, text, text, integer, timestamptz, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mail_counts_v2(text)', 'EXECUTE')
  and pg_get_functiondef('public.mail_inbox_v2(text, text, text, integer, timestamptz, text)'::regprocedure)
        like '%mail_require_staff_internal%'
  and pg_get_functiondef('public.mail_counts_v2(text)'::regprocedure) like '%mail_require_staff_internal%'
  -- las v1 siguen para las apps que no se han actualizado
  and to_regprocedure('public.mail_inbox_v1(text, text, text, integer, timestamptz)') is not null
then 1 else 0 end) as una_casilla_o_todas;
