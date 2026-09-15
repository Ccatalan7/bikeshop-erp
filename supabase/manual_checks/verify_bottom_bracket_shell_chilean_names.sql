-- Read-back de 20260821110000_bottom_bracket_shell_chilean_names.sql

select d.label, d.allowed_values -> 0 as primera_caja
from public.spec_definitions d
where d.key = 'bb_shell_standard' and d.tenant_id is null;

select coalesce(v.value_option, '—') as caja, count(*)
from public.product_spec_values v
join public.spec_definitions d on d.id = v.spec_definition_id
where d.key = 'bb_shell_standard' group by 1 order by 2 desc;

select
  -- El nombre que usa el mecanico chileno, junto a la sigla del catalogo.
  1 / (case when exists (
        select 1 from public.spec_definitions d
        cross join lateral jsonb_array_elements(d.allowed_values) v
        where d.key = 'bb_shell_standard' and d.tenant_id is null
          and v #>> '{}' = 'BSA / Caja inglesa 1.37x24')
      then 1 else 0 end) as afirma_caja_inglesa,

  -- Los 39 productos migrados, no a medias: 33 de la categoria Motor mas las
  -- 6 cubetas de caja inglesa que llenó el backfill de hermanos. Los otros 3
  -- son americanos y un Mid BMX, que no son inglesas.
  1 / (case when (
        select count(*) from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key = 'bb_shell_standard'
          and v.value_option = 'BSA / Caja inglesa 1.37x24') = 39
      then 1 else 0 end) as afirma_treinta_y_tres_migrados,

  -- Ninguna regla quedo apuntando al nombre viejo: son texto literal y si se
  -- olvida una, deja de calzar en silencio.
  1 / (case when not exists (
        select 1 from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        cross join lateral jsonb_array_elements(
          tf.visibility_rules || tf.option_rules) regla
        cross join lateral jsonb_array_elements(
          case when jsonb_typeof(regla -> 'value') = 'array' then regla -> 'value'
               when regla -> 'value' is null then '[]'::jsonb
               else jsonb_build_array(regla -> 'value') end) valor
        where t.key like 'bottom_bracket%'
          and valor #>> '{}' = 'BSA 1.37x24')
      then 1 else 0 end) as afirma_reglas_migradas,

  -- Y ningun valor guardado quedo fuera de su vocabulario.
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
