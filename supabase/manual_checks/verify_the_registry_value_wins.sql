-- Read-back: sobre un campo que la frase nombró manda el valor del registro.
select
  1 / (case when exists (
    select 1 from pg_proc where proname = 'assistant_search_inventory_v7'
      and prosrc like '%manda el valor deducido%'
  ) then 1 else 0 end) as regla_presente,
  -- El predicado del modelo sobre ese campo se descarta, no se acumula.
  1 / (case when exists (
    select 1 from pg_proc where proname = 'assistant_search_inventory_v7'
      and prosrc like '%where inferred.value ->> ''field'' = kept.value ->> ''field''%'
  ) then 1 else 0 end) as descarta_el_del_modelo,
  -- Y el valor abreviado que manda el modelo efectivamente no resuelve solo:
  -- si resolviera, esta regla sobraría.
  1 / (case when (
    select public.assistant_inventory_technical_predicate_source_internal_v1(
      p.tenant_id, p.id, 'bb_shell_standard', 'eq', '["BSA"]'::jsonb, '', ''
    ) from public.products p where p.sku = '9938' limit 1
  ) <> 'product_spec' then 1 else 0 end) as abreviatura_no_resolvia;
