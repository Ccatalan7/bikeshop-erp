-- Read-back of 20261103050000. Fails before the migration and passes after.

select
  has_function_privilege('authenticated', 'public.customer_quote_offer_document_v1(uuid, uuid)', 'EXECUTE')
    as el_equipo_lee_la_oferta,
  (select count(*) from public.tenants t
    where t.is_active is true
      and public.storefront_identity_internal(t.id) ->> 'displayName' is not null)
    as talleres_con_membrete;

select 1 / (case when
  has_function_privilege('authenticated', 'public.customer_quote_offer_document_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.customer_quote_offer_document_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.storefront_identity_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.storefront_identity_internal(uuid)', 'EXECUTE')
  and pg_get_functiondef('public.capture_online_order_storefront_snapshot(uuid, uuid)'::regprocedure)
    like '%storefront_identity_internal%'
  and pg_get_functiondef('public.customer_quote_public_projection_internal(uuid)'::regprocedure)
    like '%''storefront''%'
  and (select count(*) from public.tenants t where t.is_active is true)
    = (select count(*) from public.tenants t
        where t.is_active is true
          and public.storefront_identity_internal(t.id) ->> 'displayName' is not null)
then 1 else 0 end) as afirma_membrete_de_la_oferta;
