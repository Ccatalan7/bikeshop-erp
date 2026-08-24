select
  1 / (case when (
    select prosrc from pg_proc where proname = 'get_supply_need_stock_resolution_v1'
  ) like '%''total'', v_total,%' then 1 else 0 end) as publica_el_total,
  1 / (case when (
    select prosrc from pg_proc where proname = 'get_supply_need_stock_resolution_v1'
  ) like '%''returned'', jsonb_array_length%' then 1 else 0 end)
    as publica_lo_devuelto,
  1 / (case when (
    select prosrc from pg_proc where proname = 'get_supply_need_stock_resolution_v1'
  ) like '%''hasMore'', v_total > p_offset + p_limit%' then 1 else 0 end)
    as hasmore_intacto;
