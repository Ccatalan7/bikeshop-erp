-- Read-back of 20261106220000. Fails before the migration (the name matcher
-- does not exist) and passes after. Counts only: no payer names are printed.

select 1 / (case when
  to_regprocedure('public.mail_names_match_internal(text, text)') is not null
  and public.mail_names_match_internal('Ana Maria Prueba', 'Ana Prueba')
  and not public.mail_names_match_internal('Ana Soto', 'Juan Soto')
  and not has_function_privilege('authenticated', 'public.mail_names_match_internal(text, text)', 'EXECUTE')
  and pg_get_functiondef('public.mail_message_state_internal(uuid)'::regprocedure) like '%mail_names_match_internal%'
  and public.mail_extract_facts_internal('Transferencia',
        'Le informamos que Camila Prueba le ha transferido $45.990', 'a@bancochile.cl')->>'payer' = 'Camila Prueba'
  and public.mail_extract_facts_internal('Transferencia realizada',
        'Le informamos que hoy, 05-11-2026, nuestro(a) cliente Juan Diaz ha instruido una transferencia',
        'a@cl.bancofalabella.com')->>'payer' = 'Juan Diaz'
then 1 else 0 end) as la_transferencia_pide_el_nombre;

-- Cuántos avisos de transferencia guardados tienen ahora el nombre de quien pagó.
select count(*) as transferencias,
       count(*) filter (where nullif(facts->>'payer', '') is not null) as con_nombre
  from public.mail_messages
 where kind = 'transfer';
