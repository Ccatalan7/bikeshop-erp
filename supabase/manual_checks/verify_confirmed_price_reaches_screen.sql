select
  1 / (case when has_function_privilege('authenticated',
    'public.supplier_last_availability_v1(uuid,integer)', 'execute')
    then 1 else 0 end) as modulo_ejecuta,
  -- Un intento que no concluyó se cuenta aparte: sumarlo con los resultados
  -- escondería que la consulta falló.
  1 / (case when (
    select prosrc from pg_proc where proname = 'supplier_last_availability_v1'
  ) like '%''inconclusive''%' then 1 else 0 end) as separa_lo_no_concluido,
  -- La variación contra nuestro costo es la razón de mirar esta pantalla.
  1 / (case when (
    select prosrc from pg_proc where proname = 'supplier_last_availability_v1'
  ) like '%drift_percent%' then 1 else 0 end) as publica_la_variacion,
  -- Un costo en cero no es una base para un porcentaje.
  1 / (case when (
    select prosrc from pg_proc where proname = 'supplier_last_availability_v1'
  ) like '%product.cost <= 0 then null%' then 1 else 0 end) as cero_no_es_base;
