-- 20261121120000: despacho de bicicletas. Falla si la tarifa por bicicleta,
-- la lista de categorías o la cotización con líneas no quedaron, si sigue
-- viva la firma de cinco argumentos, si el pedido web o la cotización
-- aceptada no cotizan con sus líneas, o si un carrito sin bicicletas cambió
-- de precio.

select 1 / case
  when exists (
         select 1 from information_schema.columns
          where table_schema = 'public' and table_name = 'online_shipping_zones'
            and column_name = 'bike_shipping_gross')
   and to_regclass('public.online_shipping_bike_categories') is not null
   and to_regprocedure('public.quote_public_online_shipping(uuid,text,numeric,text,text,jsonb)') is not null
   and to_regprocedure('public.quote_online_shipping_internal(uuid,text,numeric,text,text,jsonb)') is not null
   and to_regprocedure('public.quote_public_online_shipping(uuid,text,numeric,text,text)') is null
   and to_regprocedure('public.quote_online_shipping_internal(uuid,text,numeric,text,text)') is null
   and to_regprocedure('public.save_online_shipping_bike_categories_v1(uuid[])') is not null
   and to_regprocedure('public.online_shipping_bike_categories_for_editor()') is not null
  then 1 else 0 end as bike_shipping_exists;

-- El pedido web y la cotización aceptada cotizan con sus líneas.
select 1 / case
  when (select prosrc from pg_proc
         where oid = 'public.create_public_online_order_unkeyed(jsonb,jsonb)'::regprocedure)
       like '%online_order_shipping_lines_internal(v_order_id, v_tenant_id)%'
   and (select prosrc from pg_proc
         where oid = 'public.accept_public_customer_quote_v1(text,jsonb)'::regprocedure)
       like '%online_order_shipping_lines_internal(v_order_id, v_quote.tenant_id)%'
  then 1 else 0 end as orders_quote_with_lines;

-- Un carrito sin bicicletas paga lo mismo que antes: $100.000 a Santiago,
-- con y sin líneas.
select (public.quote_public_online_shipping(
          '5443b130-cc28-45af-a420-cd500b288890', 'shipping', 100000, 'CL', 'Región Metropolitana de Santiago'
        )->>'shipping_gross')::numeric as sin_lineas,
       (public.quote_public_online_shipping(
          '5443b130-cc28-45af-a420-cd500b288890', 'shipping', 100000, 'CL', 'Región Metropolitana de Santiago',
          '[]'::jsonb
        )->>'shipping_gross')::numeric as con_lineas_vacias;

select 1 / case
  when (public.quote_public_online_shipping(
          '5443b130-cc28-45af-a420-cd500b288890', 'shipping', 100000, 'CL', 'Región Metropolitana de Santiago'
        )->>'shipping_gross')::numeric
     = (public.quote_public_online_shipping(
          '5443b130-cc28-45af-a420-cd500b288890', 'shipping', 100000, 'CL', 'Región Metropolitana de Santiago',
          '[]'::jsonb
        )->>'shipping_gross')::numeric
  then 1 else 0 end as parcel_quote_unchanged;

-- La tienda lee el precio por bicicleta y qué es bicicleta.
select 1 / case
  when exists (
         select 1 from public.get_public_online_shipping_tiers('5443b130-cc28-45af-a420-cd500b288890') tier
          where tier.bike_category_ids is not null)
  then 1 else 0 end as store_reads_bike_columns;
