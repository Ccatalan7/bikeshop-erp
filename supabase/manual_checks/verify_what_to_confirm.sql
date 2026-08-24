select
  1 / (case when has_function_privilege('authenticated',
    'public.supplier_availability_targets_v1(uuid,integer)', 'execute')
    then 1 else 0 end) as targets_ejecuta,
  1 / (case when has_function_privilege('authenticated',
    'public.record_supplier_availability_check_v1(uuid,uuid,text,text,numeric,numeric,text,jsonb)',
    'execute') then 1 else 0 end) as registro_ejecuta,
  -- Sólo se pregunta por lo que está en cero o bajo el mínimo: un chequeo es
  -- lento y preguntar por lo que no se vende gasta el tiempo del operador.
  1 / (case when (
    select prosrc from pg_proc where proname = 'supplier_availability_targets_v1'
  ) like '%available <= greatest(minimum, 0)%' then 1 else 0 end)
    as pregunta_por_lo_que_falta,
  -- Una sesión caída, un no-encontrado o una página ilegible NO pueden traer
  -- números: sería dejar entrar un cero que nadie demostró.
  1 / (case when (
    select prosrc from pg_proc
    where proname = 'record_supplier_availability_check_v1'
  ) like '%''session_expired'', ''not_found'', ''unreadable''%'
    then 1 else 0 end) as sin_numeros_sin_prueba;
