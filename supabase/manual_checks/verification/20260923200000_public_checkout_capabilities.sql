-- Read-back de 20260923200000_public_checkout_capabilities.
-- SQL plano: cada afirmación divide por cero si el estado esperado falta.
-- Antes de desplegar tiene que fallar contra producción (la función no existe).

select to_regprocedure('public.get_public_checkout_capabilities(uuid)') is not null as fachada,
       to_regprocedure('public.resolve_public_checkout_capabilities(uuid)') is not null as resolvedor,
       to_regprocedure('public.capture_online_order_storefront_snapshot(uuid,uuid)') is not null as foto,
       to_regclass('public.online_order_storefront_snapshots') is not null as tabla_fotos;

-- La fachada pública existe, es SECURITY DEFINER y la pueden llamar anónimo y
-- clientes; el resolvedor y la foto no se llaman desde fuera.
select 1 / (case when
  coalesce((select p.prosecdef
              from pg_proc p
             where p.oid = to_regprocedure('public.get_public_checkout_capabilities(uuid)')), false)
  and has_function_privilege('anon', 'public.get_public_checkout_capabilities(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.get_public_checkout_capabilities(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.resolve_public_checkout_capabilities(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.resolve_public_checkout_capabilities(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.capture_online_order_storefront_snapshot(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.capture_online_order_storefront_snapshot(uuid,uuid)', 'EXECUTE')
then 1 else 0 end) as fachada_publica_resto_privado;

-- La tabla de fotos existe, con RLS y sin acceso para anónimo ni clientes.
select 1 / (case when
  coalesce((select c.relrowsecurity from pg_class c
             where c.oid = to_regclass('public.online_order_storefront_snapshots')), false)
  and not has_table_privilege('anon', 'public.online_order_storefront_snapshots', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.online_order_storefront_snapshots', 'SELECT,INSERT,UPDATE,DELETE')
then 1 else 0 end) as fotos_cerradas;

-- Crear pedido comprueba el medio y toma la foto; leer por token la muestra.
-- La foto sólo toma contacto de campos públicos.
select 1 / (case when
  (select p.prosrc like '%resolve_public_checkout_capabilities%'
      and p.prosrc like '%capture_online_order_storefront_snapshot%'
     from pg_proc p
    where p.oid = to_regprocedure('public.create_public_online_order_with_access(jsonb,jsonb)'))
  and (select p.prosrc like '%online_order_storefront_snapshots%'
         from pg_proc p
        where p.oid = to_regprocedure('public.get_public_online_order_by_access_token(text)'))
  and (select p.prosrc not like '%owner_email%'
          and p.prosrc not like '%company.email%'
          and p.prosrc not like '%company.phone%'
         from pg_proc p
        where p.oid = to_regprocedure('public.capture_online_order_storefront_snapshot(uuid,uuid)'))
then 1 else 0 end) as pedido_y_foto_publica;

-- Con la configuración real de Viñabike, los dos medios quedan disponibles.
-- Sólo se imprimen códigos y booleanos: la función no devuelve credenciales.
select method->>'code' as medio,
       method->>'available' as disponible,
       method->>'reasonCode' as motivo
  from jsonb_array_elements(
    public.get_public_checkout_capabilities('5443b130-cc28-45af-a420-cd500b288890')->'methods'
  ) method;

select 1 / (case when (
  select count(*) filter (where (method->>'available')::boolean) = 2
    from jsonb_array_elements(
      public.get_public_checkout_capabilities('5443b130-cc28-45af-a420-cd500b288890')->'methods'
    ) method
) then 1 else 0 end) as vinabike_con_dos_medios;
