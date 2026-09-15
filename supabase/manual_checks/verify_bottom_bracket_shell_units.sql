-- Read-back de 20260821120000_bottom_bracket_shell_units.sql

select d.allowed_values from public.spec_definitions d
where d.key = 'bb_shell_standard' and d.tenant_id is null;

select coalesce(v.value_option, '—') as caja, count(*)
from public.product_spec_values v
join public.spec_definitions d on d.id = v.spec_definition_id
where d.key = 'bb_shell_standard' group by 1 order by 2 desc;

select
  -- Milimetro adelante, pulgada entre parentesis.
  1 / (case when exists (
        select 1 from public.spec_definitions d
        cross join lateral jsonb_array_elements(d.allowed_values) v
        where d.key = 'bb_shell_standard' and d.tenant_id is null
          and v #>> '{}' = 'BSA / Caja inglesa 34,8 mm (1.37") x 24')
      then 1 else 0 end) as afirma_mm_y_pulgada,

  -- Toda opcion con medida la lleva con su unidad y espacio: no quedan
  -- «41mm» pegados ni puntos decimales.
  1 / (case when not exists (
        select 1 from public.spec_definitions d
        cross join lateral jsonb_array_elements(d.allowed_values) v
        where d.key = 'bb_shell_standard' and d.tenant_id is null
          and (v #>> '{}' ~ '[0-9]mm' or v #>> '{}' ~ '[0-9]\.[0-9]+ mm'))
      then 1 else 0 end) as afirma_unidades_parejas,

  -- Los 42 productos migrados a la vez que el vocabulario.
  1 / (case when (
        select count(*) from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key = 'bb_shell_standard') = 42
      then 1 else 0 end) as afirma_cuarenta_y_dos_productos,

  -- Ninguna regla quedo apuntando a un nombre viejo.
  1 / (case when not exists (
        select 1 from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        cross join lateral jsonb_array_elements(
          tf.visibility_rules || tf.option_rules) regla
        cross join lateral jsonb_array_elements(
          case when jsonb_typeof(regla -> 'value') = 'array' then regla -> 'value'
               when regla -> 'value' is null then '[]'::jsonb
               else jsonb_build_array(regla -> 'value') end) valor
        join public.spec_definitions rd
          on rd.key = regla ->> 'field' and rd.tenant_id is null
        where t.key like 'bottom_bracket%'
          and rd.key = 'bb_shell_standard'
          and not exists (
            select 1 from jsonb_array_elements(rd.allowed_values) vocab
            where vocab #>> '{}' = valor #>> '{}'))
      then 1 else 0 end) as afirma_reglas_migradas,

  -- Y ningun valor guardado quedo huerfano en todo el catalogo.
  1 / (case when not exists (
        select 1 from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.tenant_id is null
          and jsonb_array_length(d.allowed_values) > 0
          and v.value_option is not null
          and not exists (
            select 1 from jsonb_array_elements(d.allowed_values) vocab
            where vocab #>> '{}' = v.value_option))
      then 1 else 0 end) as afirma_sin_huerfanos;
