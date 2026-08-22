-- Read-back: la herramienta de ventas ya trae el desglose por cliente.
select
  1 / (case when (
    select prosrc from pg_proc where proname = 'assistant_analyze_sales_period_v1'
  ) like '%topCustomers%' then 1 else 0 end) as campo_presente,
  1 / (case when (
    select prosrc from pg_proc where proname = 'assistant_analyze_sales_period_v1'
  ) like '%customer_rank%' then 1 else 0 end) as ranking_calculado,
  -- El cliente máximo del mes existe y es el que esperamos comparar.
  1 / (case when (
    select coalesce(nullif(btrim(i.customer_name), ''), 'Sin cliente registrado')
    from public.sales_invoices i
    where i.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and lower(coalesce(i.status, '')) not in ('draft', 'borrador')
      and (i.date at time zone 'America/Santiago')::date
        between date_trunc('month', date '2026-08-21')::date and date '2026-08-21'
    group by 1 order by sum(i.total) desc limit 1
  ) = 'Cliente Mostrador' then 1 else 0 end) as maximo_conocido;
