-- Read-back of 20261105010000. Fails before the migration (no phone
-- verification tables or functions; the QR claim links by itself) and passes
-- after.

select 1 / (case when
  (select relrowsecurity from pg_class
    where oid = 'public.customer_portal_phone_verifications'::regclass)
  and (select relrowsecurity from pg_class
        where oid = 'public.customer_portal_verified_phones'::regclass)
  and not has_table_privilege('authenticated', 'public.customer_portal_phone_verifications', 'SELECT')
  and not has_table_privilege('authenticated', 'public.customer_portal_verified_phones', 'SELECT')
  and has_function_privilege('service_role',
    'public.start_customer_phone_verification_internal(uuid, uuid, text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.start_customer_phone_verification_internal(uuid, uuid, text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.finish_customer_phone_verification_send_internal(uuid, boolean, text, text)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.confirm_customer_phone_verification_v1(uuid, text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.confirm_customer_phone_verification_v1(uuid, text)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.customer_portal_phone_state_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.customer_phone_verification_stats_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.link_portal_account_to_customer_internal(uuid, uuid, text, uuid, text, text)', 'EXECUTE')
  and pg_get_functiondef('public.claim_customer_portal_code_v1(uuid, text, text)'::regprocedure)
    like '%link_portal_account_to_customer_internal%'
  and has_function_privilege('authenticated',
    'public.claim_customer_portal_code_v1(uuid, text, text)', 'EXECUTE')
then 1 else 0 end) as afirma_telefono_verificado;
