-- Read-back de 20260821100000_bottom_bracket_chilean_vocabulary.sql

select d.key, d.label, d.allowed_values
from public.spec_definitions d
where d.tenant_id is null
  and d.key in ('bb_construction', 'bb_shell_standard', 'spindle_interface');

select coalesce(v.value_option, '—') as construccion, count(*)
from public.product_spec_values v
join public.spec_definitions d on d.id = v.spec_definition_id
where d.key = 'bb_construction' group by 1 order by 2 desc;

select
  -- La palabra del taller, no la traducida.
  1 / (case when exists (
        select 1 from public.spec_definitions d
        cross join lateral jsonb_array_elements(d.allowed_values) v
        where d.key = 'bb_construction' and d.tenant_id is null
          and v #>> '{}' = 'Rodamiento sellado')
      then 1 else 0 end) as afirma_rodamiento_sellado,

  1 / (case when (select label from public.spec_definitions
        where key = 'bb_shell_standard' and tenant_id is null) = 'Caja de motor'
      then 1 else 0 end) as afirma_caja_de_motor,

  1 / (case when (select label from public.spec_definitions
        where key = 'spindle_interface' and tenant_id is null) = 'Punta del eje'
      then 1 else 0 end) as afirma_punta_del_eje,

  -- Ni una sola palabra traducida sobrevive en el vocabulario del motor.
  1 / (case when not exists (
        select 1 from public.spec_definitions d
        cross join lateral jsonb_array_elements(d.allowed_values) v
        where d.tenant_id is null and d.key = 'bb_construction'
          and v #>> '{}' in ('Cartucho sellado', 'Copas externas',
                             'Copa y cono', 'Rodamientos prensados',
                             'Thread-together'))
      then 1 else 0 end) as afirma_sin_vocabulario_traducido,

  -- Ni en las reglas, que llevan los valores como texto literal.
  1 / (case when not exists (
        select 1 from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        where t.key like 'bottom_bracket%'
          and (tf.visibility_rules::text like '%Cartucho sellado%'
            or tf.option_rules::text like '%Cartucho sellado%'
            or tf.option_rules::text like '%Copas externas%'
            or tf.option_rules::text like '%Copa y cono%'
            or tf.option_rules::text like '%Thread-together%'))
      then 1 else 0 end) as afirma_reglas_sin_traduccion,

  -- Ni en los textos de ayuda que lee el mecánico.
  1 / (case when not exists (
        select 1 from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        where t.key like 'bottom_bracket%'
          and tf.helper_text ilike '%pedalier%')
      then 1 else 0 end) as afirma_ayudas_dicen_motor,

  -- Y los 48 productos quedaron migrados, no a medias.
  1 / (case when (
        select count(*) from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key = 'bb_construction'
          and v.value_option = 'Rodamiento sellado') = 30
      then 1 else 0 end) as afirma_treinta_rodamientos_sellados,

  -- Ningun valor guardado quedo fuera del vocabulario reescrito: es la trampa
  -- de renombrar un valor y olvidar una de las cuatro partes.
  1 / (case when not exists (
        select 1 from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.tenant_id is null
          and jsonb_array_length(d.allowed_values) > 0
          and v.value_option is not null
          and not exists (
            select 1 from jsonb_array_elements(d.allowed_values) vocab
            where vocab #>> '{}' = v.value_option))
      then 1 else 0 end) as afirma_sin_valores_huerfanos;
