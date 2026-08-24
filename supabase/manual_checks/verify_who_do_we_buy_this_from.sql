-- Read-back: la función existe, sólo la puede ejecutar `authenticated`, y su
-- alcance se resuelve por la hoja que el operador nombra, no por la categoría
-- padre.
select
  1 / (case when exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'assistant_rank_purchase_suppliers_v1'
      and p.prosecdef
  ) then 1 else 0 end) as existe_security_definer,
  1 / (case when has_function_privilege('authenticated',
    'public.assistant_rank_purchase_suppliers_v1(text,text,text,integer)',
    'execute') then 1 else 0 end) as authenticated_ejecuta,
  1 / (case when not has_function_privilege('anon',
    'public.assistant_rank_purchase_suppliers_v1(text,text,text,integer)',
    'execute') then 1 else 0 end) as anon_no_ejecuta,
  1 / (case when (
    select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'assistant_rank_purchase_suppliers_v1'
  ) = 1 then 1 else 0 end) as sin_sobrecarga,
  -- Se agrega la vista de LÍNEAS, nunca la de candidatos: ésa trae una fila
  -- por producto y le atribuiría toda la historia al último proveedor.
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'assistant_rank_purchase_suppliers_v1'
  ) like '%purchase_line_landed_cost_observations_v1%' then 1 else 0 end)
    as agrega_lineas,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'assistant_rank_purchase_suppliers_v1'
  ) not like '%purchase_candidate_metrics_v1%' then 1 else 0 end)
    as no_usa_candidatos,
  -- La gama informa, no filtra: aparece en la mezcla y jamás en un `where`.
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'assistant_rank_purchase_suppliers_v1'
  ) like '%gamaMix%' then 1 else 0 end) as gama_se_informa;

-- Read-back: las palabras de gama salen del texto libre. Dejarlas dentro hacía
-- que «neumáticos 29 de gama media y alta» devolviera cero proveedores.
select
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'assistant_rank_purchase_suppliers_v1'
  ) like '%v_requested_gamas%' then 1 else 0 end) as gama_se_consume,
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'assistant_rank_purchase_suppliers_v1'
  ) like '%requestedGamaLines%' then 1 else 0 end) as gama_informa_por_proveedor;
