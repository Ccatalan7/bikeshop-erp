-- Read-back of 20261104240000. Fails before the migration (provisioning does
-- not set the link marker) and passes after.

select 1 / (case when
  pg_get_functiondef('public.provision_current_public_store_customer(uuid)'::regprocedure)
    like '%vinabike.portal_claim_relink%'
  and pg_get_functiondef('public.provision_current_public_store_customer(uuid)'::regprocedure)
    like '%Store customer email is already linked to another Auth user%'
  and pg_get_functiondef('public.guard_customer_identity_update()'::regprocedure)
    like '%vinabike.portal_claim_relink%'
  and (select prosecdef from pg_proc
        where oid = 'public.provision_current_public_store_customer(uuid)'::regprocedure)
  and not has_function_privilege('anon',
    'public.provision_current_public_store_customer(uuid)', 'EXECUTE')
then 1 else 0 end) as afirma_ligar_por_correo;
