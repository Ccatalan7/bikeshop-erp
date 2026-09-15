-- Read-back de 20260821160000_spec_vocabulary_as_rows.sql (sólo la estructura;
-- el llenado lo verifica 20260821170000).

select column_name, data_type from information_schema.columns
where table_schema = 'public' and table_name = 'spec_definition_values'
order by ordinal_position;

select
  -- La tabla del vocabulario existe.
  1 / (case when (select count(*) from information_schema.tables
        where table_schema = 'public'
          and table_name = 'spec_definition_values') = 1
      then 1 else 0 end) as afirma_tabla_creada,

  -- Un codigo no se repite dentro de un campo: es la identidad del valor.
  1 / (case when (select count(*) from pg_indexes
        where tablename = 'spec_definition_values'
          and indexname = 'spec_definition_values_definition_code') = 1
      then 1 else 0 end) as afirma_codigo_unico_por_campo,

  -- La forma del codigo esta forzada por la base, no por convencion.
  1 / (case when (select count(*) from pg_constraint
        where conrelid = 'public.spec_definition_values'::regclass
          and conname = 'spec_definition_values_code_shape') = 1
      then 1 else 0 end) as afirma_forma_forzada,

  -- Aislamiento por tenant, como toda tabla del ERP.
  1 / (case when (select relrowsecurity from pg_class
        where oid = 'public.spec_definition_values'::regclass)
      then 1 else 0 end) as afirma_rls_activa,

  -- Una etiqueta numerica produce un codigo valido: «10» no puede quedar como
  -- codigo porque empieza con digito.
  1 / (case when public.spec_value_code_from_label_internal_v1('10') = 'v_10'
      then 1 else 0 end) as afirma_slug_numerico,

  -- Y una etiqueta con acentos y simbolos tambien.
  1 / (case when public.spec_value_code_from_label_internal_v1(
        'BSA / Caja inglesa 34,8 mm (1.37") x 24') = 'bsa_caja_inglesa_34_8_mm_1_37_x_24'
      then 1 else 0 end) as afirma_slug_con_acentos;
