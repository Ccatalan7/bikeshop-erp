-- Read-back de 20260923210000_public_product_detail_keeps_stockouts.
-- SQL plano: cada afirmación divide por cero si el estado esperado falta.
-- Antes de desplegar tiene que fallar contra producción: con el sitio en
-- `available_only`, una ficha agotada no se encontraba.

with agotados as (
  select array_agg(p.id) as ids
    from public.products p
   where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
     and p.is_active and p.is_published and p.show_on_website
     and p.product_type = 'product'
     and coalesce(p.track_stock, true)
     and coalesce(p.inventory_qty, 0) <= 0
)
select (select cardinality(ids) from agotados) as agotados_publicados,
       (select count(*) from agotados, public.get_public_products(
          p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
          p_product_ids := agotados.ids,
          p_only_in_stock := false,
          p_limit := 5000)) as fichas_encontradas,
       (select count(*) from agotados, public.get_public_products(
          p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
          p_product_ids := agotados.ids,
          p_only_in_stock := true,
          p_limit := 5000)) as con_filtro_de_stock,
       (select count(*) from public.get_public_products(
          p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
          p_only_in_stock := false,
          p_limit := 5000) where stock_quantity <= 0 and track_stock) as agotados_en_listado;

-- La ficha encuentra más que el filtro de stock (los agotados); con filtro
-- (destacados, carrito) todo lo que vuelve tiene stock, y en los listados no
-- aparece ningún agotado. Algunos productos con inventario 0 son vendibles
-- por reservas o por componentes de un set y vuelven igual con filtro.
select 1 / (case when (
  with agotados as (
    select array_agg(p.id) as ids
      from public.products p
     where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
       and p.is_active and p.is_published and p.show_on_website
       and p.product_type = 'product'
       and coalesce(p.track_stock, true)
       and coalesce(p.inventory_qty, 0) <= 0
  )
  select (select count(*) from agotados, public.get_public_products(
            p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
            p_product_ids := agotados.ids,
            p_only_in_stock := false,
            p_limit := 5000))
     > (select count(*) from agotados, public.get_public_products(
            p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
            p_product_ids := agotados.ids,
            p_only_in_stock := true,
            p_limit := 5000))
     and (select count(*) from agotados, public.get_public_products(
            p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
            p_product_ids := agotados.ids,
            p_only_in_stock := true,
            p_limit := 5000) where stock_quantity <= 0 and track_stock) = 0
     and (select count(*) from public.get_public_products(
            p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
            p_only_in_stock := false,
            p_limit := 5000) where stock_quantity <= 0 and track_stock) = 0
) then 1 else 0 end) as ficha_si_listados_no;

-- Los permisos y la firma no cambian: anónimo la sigue ejecutando.
select 1 / (case when
  has_function_privilege('anon',
    'public.get_public_products(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)',
    'EXECUTE')
  and (select p.prosecdef from pg_proc p
        where p.oid = 'public.get_public_products(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure)
then 1 else 0 end) as firma_y_permisos;
