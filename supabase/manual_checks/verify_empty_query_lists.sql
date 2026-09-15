-- Read-back: las tres aceptan un query vacío y el filtro quedó condicional.
select
  1 / (case when (select count(*) from pg_proc
    where proname in ('assistant_search_suppliers_v1', 'assistant_search_customers_v1',
      'assistant_search_purchase_invoices_v1')
      and prosrc like '%> 240 or p_limit is null%') = 3 then 1 else 0 end) as validacion_relajada,
  1 / (case when (select count(*) from pg_proc
    where proname in ('assistant_search_suppliers_v1', 'assistant_search_customers_v1',
      'assistant_search_purchase_invoices_v1')
      and prosrc like '%v_query = '''' or not exists%') = 3 then 1 else 0 end) as filtro_condicional,
  1 / (case when (select count(*) from pg_proc
    where proname in ('assistant_search_suppliers_v1', 'assistant_search_customers_v1',
      'assistant_search_purchase_invoices_v1')
      and prosrc like '%if v_query = '''' then raise%') = 0 then 1 else 0 end) as sin_error_por_vacio;
