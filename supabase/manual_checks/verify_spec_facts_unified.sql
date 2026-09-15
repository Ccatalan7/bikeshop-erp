-- Read-back de 20260821180000_spec_facts_unified.sql

select table_name, count(*) as columnas
from information_schema.columns
where table_schema = 'public' and table_name in ('spec_facts','spec_fact_values')
group by 1 order by 1;

select
  -- Las dos tablas existen.
  1 / (case when (select count(*) from information_schema.tables
        where table_schema = 'public'
          and table_name in ('spec_facts','spec_fact_values')) = 2
      then 1 else 0 end) as afirma_tablas_creadas,

  -- Un sujeto no puede tener dos veces el mismo campo.
  1 / (case when (select count(*) from pg_indexes
        where tablename = 'spec_facts'
          and indexname = 'spec_facts_subject_definition') = 1
      then 1 else 0 end) as afirma_un_hecho_por_campo,

  -- Los tres sujetos, y sólo esos.
  1 / (case when (select pg_get_constraintdef(oid) from pg_constraint
        where conrelid = 'public.spec_facts'::regclass
          and conname = 'spec_facts_subject_type_known')
        like '%product%bike%job_bike%'
      then 1 else 0 end) as afirma_tres_sujetos,

  -- Un hecho lleva un solo escalar, no tres.
  1 / (case when (select count(*) from pg_constraint
        where conrelid = 'public.spec_facts'::regclass
          and conname = 'spec_facts_one_scalar') = 1
      then 1 else 0 end) as afirma_un_solo_escalar,

  -- El valor de lista es llave foránea real: un hecho no puede apuntar a un
  -- valor que no existe, que es justo lo que un texto libre no garantiza.
  1 / (case when (select count(*) from pg_constraint
        where conrelid = 'public.spec_fact_values'::regclass
          and contype = 'f'
          and confrelid = 'public.spec_definition_values'::regclass) = 1
      then 1 else 0 end) as afirma_llave_foranea_al_vocabulario,

  -- Borrar un valor del vocabulario que algún hecho usa tiene que fallar.
  1 / (case when (select confdeltype from pg_constraint
        where conrelid = 'public.spec_fact_values'::regclass
          and confrelid = 'public.spec_definition_values'::regclass) = 'r'
      then 1 else 0 end) as afirma_no_se_borra_un_valor_en_uso,

  -- La forma se cuida con trigger: un campo de seleccion unica no admite dos.
  1 / (case when (select count(*) from pg_trigger
        where tgrelid = 'public.spec_fact_values'::regclass
          and tgname = 'spec_fact_values_shape') = 1
      then 1 else 0 end) as afirma_trigger_de_forma,

  -- Aislamiento por tenant en las dos.
  1 / (case when (select count(*) from pg_class
        where oid in ('public.spec_facts'::regclass,
                      'public.spec_fact_values'::regclass)
          and relrowsecurity) = 2
      then 1 else 0 end) as afirma_rls_en_ambas;
