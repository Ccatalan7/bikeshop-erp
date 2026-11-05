-- Read-back of 20261104230000. Fails before the migration (no peek function,
-- no pending claim, no store URL in the issued code) and passes after.

select 1 / (case when
  to_regprocedure('public.peek_customer_portal_claim_code_v1(uuid, text)') is not null
  and has_function_privilege('anon', 'public.peek_customer_portal_claim_code_v1(uuid, text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.peek_customer_portal_claim_code_v1(uuid, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_first_name_internal(text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.customer_first_name_internal(text)', 'EXECUTE')
  and pg_get_functiondef('public.issue_customer_portal_claim_code_v1(uuid, text)'::regprocedure)
    like '%''store_url''%'
  and pg_get_functiondef('public.claim_customer_portal_code_v1(uuid, text, text)'::regprocedure)
    like '%vinabike_claim_code%'
  and pg_get_functiondef('public.claim_customer_portal_code_v1(uuid, text, text)'::regprocedure)
    like '%nothing_pending%'
  and not has_function_privilege('anon', 'public.claim_customer_portal_code_v1(uuid, text, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.issue_customer_portal_claim_code_v1(uuid, text)', 'EXECUTE')
then 1 else 0 end) as afirma_flujo_del_qr;

-- Un código inventado no dice nada, y el nombre de pila no grita.
select 1 / (case when
  public.peek_customer_portal_claim_code_v1(
    '5443b130-cc28-45af-a420-cd500b288890', 'x' || repeat('y', 50)) ->> 'status' = 'invalid'
  and public.customer_first_name_internal('  DORA   PÉREZ ') = 'Dora'
  and public.customer_first_name_internal('María José') = 'María'
  and public.customer_first_name_internal('') is null
then 1 else 0 end) as afirma_respuestas_del_qr;
