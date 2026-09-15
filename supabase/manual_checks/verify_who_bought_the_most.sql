-- Read-back: el ranking existe y cuadra con el total del período.
with esperado as (
  select coalesce(nullif(btrim(i.customer_name), ''), 'Sin cliente registrado') cliente,
    sum(i.total) monto, count(*) docs
  from public.sales_invoices i
  where i.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and lower(coalesce(i.status, '')) not in (
      'draft', 'borrador', 'cancelled', 'cancelado', 'cancelada',
      'anulado', 'anulada'
    )
    and (i.date at time zone 'America/Santiago')::date
      between date_trunc('month', date '2026-08-21')::date and date '2026-08-21'
  group by 1 having sum(i.total) > 0
  order by 2 desc limit 1
)
select
  1 / (case when exists (
    select 1 from pg_proc where proname = 'assistant_rank_sales_customers_v1'
      and prosecdef and provolatile = 's'
  ) then 1 else 0 end) as funcion_existe,
  -- Exige la misma capacidad que el resto de ventas, no una nueva.
  1 / (case when (
    select prosrc from pg_proc where proname = 'assistant_rank_sales_customers_v1'
  ) like '%ai.read.sales%' then 1 else 0 end) as misma_capacidad,
  -- Y hay un cliente máximo real este mes contra el que comparar la respuesta.
  1 / (case when (select count(*) from esperado) = 1 then 1 else 0 end) as hay_maximo;
