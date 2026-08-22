select
  1 / (case when exists (
    select 1 from information_schema.columns
    where table_name = 'assistant_provider_attempts'
      and column_name = 'cached_input_tokens'
  ) then 1 else 0 end) as columna_existe,
  -- La base acepta el cuerpo VIEJO, que es el que la función de borde manda
  -- hasta que se despliegue: si esto falla, muere toda corrida.
  1 / (case when (
    select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'assistant_record_provider_attempt_v2'
      and n.nspname = 'assistant_runtime'
  ) like '%or assistant_runtime.assistant_json_has_exact_keys_internal_v1%'
  then 1 else 0 end) as acepta_ambas_formas;
