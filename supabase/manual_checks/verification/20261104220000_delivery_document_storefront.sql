-- Read-back of 20261104220000. Fails before the migration (the projection has
-- no storefront) and passes after.

select 1 / (case when
  pg_get_functiondef('public.job_delivery_document_projection_internal(uuid)'::regprocedure)
    like '%storefront_identity_internal(document.tenant_id)%'
  and pg_get_functiondef('public.job_delivery_document_projection_internal(uuid)'::regprocedure)
    like '%''store_url''%'
  and not has_function_privilege('authenticated',
    'public.job_delivery_document_projection_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.job_delivery_document_projection_internal(uuid)', 'EXECUTE')
then 1 else 0 end) as afirma_membrete_en_el_comprobante;

-- El membrete de Viñabike tiene nombre y la dirección de la tienda.
select 1 / (case when (
  select (public.storefront_identity_internal('5443b130-cc28-45af-a420-cd500b288890') ? 'displayName')
     and exists (
       select 1 from public.website_settings
        where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
          and key = 'store_url' and nullif(btrim(value), '') is not null
     )
) then 1 else 0 end) as afirma_membrete_de_vinabike;
