-- Read-back: la función ya no referencia un CTE fuera de su sentencia.
select
  1 / (case when (
    select prosrc from pg_proc where proname = 'assistant_rank_sales_customers_v1'
  ) not like '%(select count(*) from ranked)%' then 1 else 0 end) as sin_cte_huerfano,
  1 / (case when (
    select prosrc from pg_proc where proname = 'assistant_rank_sales_customers_v1'
  ) like '%into v_items, v_total, v_rows%' then 1 else 0 end) as conteo_en_el_query;
