-- Read-back de 20260821160000 + 20260821170000

select
  (select count(*) from public.spec_definition_values) as valores_de_vocabulario,
  (select count(distinct spec_definition_id) from public.spec_definition_values) as campos_cubiertos,
  (select count(*) from public.spec_definition_values sv
     join public.spec_definitions d on d.id = sv.spec_definition_id
     where exists (select 1 from public.service_profile_questions q,
       lateral jsonb_array_elements(q.options_json) o
       where q.key = d.key and o ->> 'value' = sv.code)) as codigos_heredados_del_wizard;

select
  -- Todo valor del vocabulario tiene su fila. Si falta uno, un producto podría
  -- quedar apuntando a un código que no existe cuando migren los hechos.
  1 / (case when (
        select count(*) from public.spec_definitions d
        cross join lateral jsonb_array_elements(d.allowed_values) v
        where jsonb_array_length(d.allowed_values) > 0
          and not exists (
            select 1 from public.spec_definition_values sv
            where sv.spec_definition_id = d.id and sv.label = v #>> '{}')) = 0
      then 1 else 0 end) as afirma_vocabulario_completo,

  -- El pedalier lleva los codigos curados, no un slug de su etiqueta larga.
  1 / (case when (
        select sv.code from public.spec_definition_values sv
        join public.spec_definitions d on d.id = sv.spec_definition_id
        where d.key = 'bb_shell_standard'
          and sv.label = 'BSA / Caja inglesa 34,8 mm (1.37") x 24') = 'bsa_threaded'
      then 1 else 0 end) as afirma_codigo_curado_del_pedalier,

  -- Y el resto hereda el codigo que el wizard ya usaba: es lo que hace que
  -- esto una las cuatro formas en vez de agregar una quinta.
  1 / (case when (
        select sv.code from public.spec_definition_values sv
        join public.spec_definitions d on d.id = sv.spec_definition_id
        where d.key = 'freehub_type' and sv.label = 'Micro Spline') = 'microspline'
      then 1 else 0 end) as afirma_codigo_heredado_del_wizard,

  -- Ningun codigo se repite dentro de un mismo campo.
  1 / (case when not exists (
        select 1 from public.spec_definition_values
        group by spec_definition_id, code having count(*) > 1)
      then 1 else 0 end) as afirma_codigos_unicos,

  -- Y todos cumplen la forma: empiezan por letra, sin acentos ni espacios.
  1 / (case when not exists (
        select 1 from public.spec_definition_values
        where code !~ '^[a-z][a-z0-9_]{0,63}$')
      then 1 else 0 end) as afirma_forma_del_codigo;
