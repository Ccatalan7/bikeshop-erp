-- Read-back of 20261024060000: with «Incluir agotados», what can be bought
-- comes first. Plain SQL: a missing invariant divides by zero after printing
-- what it found.

with listed as (
  select row_number() over () as n, left(r.name, 50) as name,
    (r.product_type = 'service' or not coalesce(r.track_stock, true)
      or coalesce(r.stock_quantity, r.inventory_qty, 0) > 0) as in_stock
  from public.get_public_products_faceted_v2(
    p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'camara fv',
    p_only_in_stock := false, p_limit := 100, p_include_out_of_stock := true) r
)
select n, name, in_stock from listed where n <= 5 order by n;

with listed as (
  select row_number() over () as n,
    (r.product_type = 'service' or not coalesce(r.track_stock, true)
      or coalesce(r.stock_quantity, r.inventory_qty, 0) > 0) as in_stock
  from public.get_public_products_faceted_v2(
    p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890', p_search_term := 'camara fv',
    p_only_in_stock := false, p_limit := 100, p_include_out_of_stock := true) r
)
select 1 / (case when not exists (
    select 1 from listed a join listed b on b.n > a.n where not a.in_stock and b.in_stock
  ) and exists (select 1 from listed where in_stock) and exists (select 1 from listed where not in_stock)
  then 1 else 0 end) as afirma_disponibles_primero;
