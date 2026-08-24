select
  1 / (case when has_function_privilege('authenticated',
    'public.supplier_for_origin_v1(text)', 'execute') then 1 else 0 end)
    as modulo_ejecuta,
  -- Preguntar quién es no puede escribir evidencia: si lo hiciera, cada
  -- chequeo dejaría una fila `probe_missing` de más.
  1 / (case when (
    select prosrc from pg_proc where proname = 'supplier_for_origin_v1'
  ) not like '%insert into%' then 1 else 0 end) as no_escribe,
  1 / (case when (
    select provolatile from pg_proc where proname = 'supplier_for_origin_v1'
  ) = 's' then 1 else 0 end) as declarada_estable;
