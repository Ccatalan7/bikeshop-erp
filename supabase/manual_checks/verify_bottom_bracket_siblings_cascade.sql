-- Read-back de 20260820300000_bottom_bracket_siblings_cascade.sql

select t.key as plantilla, count(*) as campos,
  count(*) filter (where tf.visibility_rules <> '[]'::jsonb) as con_compuerta,
  count(*) filter (where tf.option_rules <> '[]'::jsonb) as con_acotado
from public.spec_templates t
join public.spec_template_fields tf on tf.template_id = t.id
where t.key like 'bottom_bracket%' group by 1 order by 1;

select
  -- Cada plantilla del pedalier tiene exactamente una raiz sin compuerta.
  1 / (case when not exists (
        select 1 from public.spec_templates t
        join public.spec_template_fields tf on tf.template_id = t.id
        where t.key like 'bottom_bracket%'
        group by t.key
        having count(*) filter (where tf.visibility_rules = '[]'::jsonb) <> 1)
      then 1 else 0 end) as afirma_una_raiz_por_plantilla,

  -- Ninguna compuerta apunta a una pregunta posterior, en ninguna de las cuatro.
  1 / (case when not exists (
        select 1 from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        cross join lateral jsonb_array_elements(tf.visibility_rules) regla
        join public.spec_definitions gd on gd.key = regla ->> 'field'
        join public.spec_template_fields gf
          on gf.template_id = tf.template_id and gf.spec_definition_id = gd.id
        where t.key like 'bottom_bracket%' and gf.sort_order >= tf.sort_order)
      then 1 else 0 end) as afirma_compuertas_antes,

  -- Un rodamiento de bolas y uno sellado no comparten campos: la raiz separa.
  1 / (case when (
        select count(*) from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        join public.spec_definitions d on d.id = tf.spec_definition_id
        cross join lateral jsonb_array_elements(tf.visibility_rules) regla
        where t.key = 'bottom_bracket_bearing'
          and regla ->> 'field' = 'bb_construction'
          and d.key in ('bb_ball_size_in', 'bb_ball_count_per_side')) = 2
      then 1 else 0 end) as afirma_rama_canastillo,

  -- Una cubeta nunca es un cartucho sellado.
  1 / (case when not exists (
        select 1 from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        join public.spec_definitions d on d.id = tf.spec_definition_id
        cross join lateral jsonb_array_elements(tf.option_rules) regla
        cross join lateral jsonb_array_elements(
          coalesce(regla -> 'allow', '[]'::jsonb)) permitido
        where t.key = 'bottom_bracket_cup' and d.key = 'bb_construction'
          and permitido #>> '{}' = 'Cartucho sellado')
      then 1 else 0 end) as afirma_cubeta_no_es_cartucho,

  -- Y toda opcion ofrecida existe en el vocabulario de su campo.
  1 / (case when not exists (
        select 1 from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        join public.spec_definitions d on d.id = tf.spec_definition_id
        cross join lateral jsonb_array_elements(tf.option_rules) regla
        cross join lateral jsonb_array_elements(
          coalesce(regla -> 'allow', '[]'::jsonb)) permitido
        where t.key like 'bottom_bracket%'
          and jsonb_array_length(d.allowed_values) > 0
          and not exists (
            select 1 from jsonb_array_elements(d.allowed_values) vocab
            where vocab #>> '{}' = permitido #>> '{}'))
      then 1 else 0 end) as afirma_opciones_en_vocabulario;
