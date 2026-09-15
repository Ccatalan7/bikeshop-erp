-- El pedido guardado se encuentra por proveedor y sin proveedor, y sus líneas
-- se pueden recuperar para retomarlo.
select set_config(
  'request.jwt.claim.sub',
  (select up.user_id::text from public.user_profiles up
    where up.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and up.user_id is not null
      and up.role in ('owner', 'admin', 'manager')
    order by case up.role when 'owner' then 1 when 'admin' then 2 else 3 end,
             up.created_at asc nulls last
    limit 1),
  true
) as actor_fijado;
select set_config('request.jwt.claim.role', 'authenticated', true) as rol;

select
  (todos->>'total')::int pedidos_totales,
  (todos->'items'->0->>'orderNumber') primer_folio,
  (todos->'items'->0->>'status') estado,
  (todos->'items'->0->>'supplierName') proveedor,
  (todos->'items'->0->>'lineCount')::int lineas,
  (todos->'items'->0->>'total')::numeric total,
  (select jsonb_array_length(
    public.purchase_order_lines_v1(
      (todos->'items'->0->>'orderId')::uuid)->'lines')) lineas_recuperadas,
  (select (public.purchase_orders_page_v1(
    (todos->'items'->0->>'supplierId')::uuid)->>'total')::int) del_proveedor
from (select public.purchase_orders_page_v1() todos) probe;
