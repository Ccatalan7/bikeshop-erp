-- Falla si el riesgo de inventario vuelve a ignorar la demanda o a esconder el
-- total. La RPC no se puede llamar desde aquí —exige identidad de asistente—,
-- así que se comprueba (a) que el sobre compartido sepa llevar el total, y
-- (b) que el orden nuevo, corrido sobre los datos reales del taller, ponga
-- adelante algo que efectivamente se movió.
with sobre as (
  select public.assistant_tool_envelope_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid,
    '[{"a":1}]'::jsonb, true, 1016
  ) e
), demanda as (
  select linea.product_id, sum(linea.quantity) units
  from (
    select (item ->> 'product_id')::uuid product_id,
      coalesce((item ->> 'quantity')::numeric, 0) quantity
    from public.sales_invoices invoice
      cross join lateral jsonb_array_elements(invoice.items) item
    where invoice.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and invoice.voided_at is null
      and invoice.date >= current_date - 90
      and jsonb_typeof(invoice.items) = 'array'
      and (item ->> 'product_id') ~ '^[0-9a-f-]{36}$'
    union all
    select job_item.product_id, coalesce(job_item.quantity, 0)
    from public.mechanic_job_items job_item
    where job_item.product_id is not null
      and job_item.created_at >= current_date - 90
  ) linea
  group by linea.product_id
), en_riesgo as (
  select product.id,
    coalesce(product.stock_quantity, product.inventory_qty, 0) stock,
    greatest(coalesce(product.min_stock_level, 0), 0) minimo,
    floor(coalesce(demanda.units, 0))::int vendidos
  from public.products product
    left join demanda on demanda.product_id = product.id
  where product.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and product.is_active is true
    and coalesce(product.track_stock, true) is true
    and coalesce(product.is_service, false) is false
    and coalesce(product.purchase_treatment, 'inventory') = 'inventory'
    and (coalesce(product.stock_quantity, product.inventory_qty, 0) <= 0
      or coalesce(product.stock_quantity, product.inventory_qty, 0)
         <= greatest(coalesce(product.min_stock_level, 0), 0))
), primero as (
  select vendidos from en_riesgo
  order by case when vendidos > 0 then 0 else 1 end,
    case when stock <= 0 then 0 else 1 end,
    vendidos desc, stock
  limit 1
)
select 1 / (case when
  (select (e ->> 'totalMatches')::int from sobre) = 1016
  and (select (e ->> 'resultCount')::int from sobre) = 1
  and (select count(*) from en_riesgo) > 10
  and (select vendidos from primero) > 0
then 1 else 0 end) as riesgo_ordenado_por_demanda;
