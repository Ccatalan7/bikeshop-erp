-- Read-back de 20260924030000_public_store_data_declares_tenant.
-- Antes de desplegar tiene que fallar contra producción: la proyección no
-- trae `tenant_id`.

select (public.get_public_store_data('5443b130-cc28-45af-a420-cd500b288890')::jsonb)
         ->> 'tenant_id' as tenant_declarado;

select 1 / (case when
  (public.get_public_store_data('5443b130-cc28-45af-a420-cd500b288890')::jsonb)
    ->> 'tenant_id' = '5443b130-cc28-45af-a420-cd500b288890'
then 1 else 0 end) as proyeccion_declara_tenant;

-- La forma que consume la tienda no cambia.
select 1 / (case when
  jsonb_typeof((public.get_public_store_data('5443b130-cc28-45af-a420-cd500b288890')::jsonb) -> 'settings') = 'object'
  and jsonb_typeof((public.get_public_store_data('5443b130-cc28-45af-a420-cd500b288890')::jsonb) -> 'blocks') = 'array'
then 1 else 0 end) as forma_intacta;

-- Anónimo la sigue ejecutando: es la puerta pública de la tienda.
select 1 / has_function_privilege('anon', 'public.get_public_store_data(uuid)', 'EXECUTE')::integer
  as anon_ejecuta;
