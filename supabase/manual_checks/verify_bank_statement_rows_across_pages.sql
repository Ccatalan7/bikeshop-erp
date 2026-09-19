-- Falla si una cartola con un movimiento cortado por un salto de página
-- vuelve a ser rechazada: la fila guarda la página donde termina.
select
  exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'bank_statement_rows'
       and column_name = 'source_page_end'
  ) as guarda_pagina_final,
  not exists (
    select 1 from pg_constraint
     where conrelid = 'public.bank_statement_rows'::regclass
       and conname = 'bank_statement_rows_check'
  ) as sin_regla_de_una_pagina;

select 1 / (case when
  exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'bank_statement_rows'
       and column_name = 'source_page_end'
  )
  and not exists (
    select 1 from pg_constraint
     where conrelid = 'public.bank_statement_rows'::regclass
       and conname = 'bank_statement_rows_check'
  )
  and exists (
    select 1 from pg_constraint
     where conrelid = 'public.bank_statement_rows'::regclass
       and conname = 'bank_statement_rows_source_span_check'
  )
  and pg_get_functiondef('public.save_bank_statement_import_v1(text,text,text,uuid,jsonb,jsonb)'::regprocedure)
    like '%source_page_end%'
  and has_function_privilege('authenticated', 'public.save_bank_statement_import_v1(text,text,text,uuid,jsonb,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.save_bank_statement_import_v1(text,text,text,uuid,jsonb,jsonb)', 'EXECUTE')
then 1 else 0 end) as afirma_filas_entre_paginas;
