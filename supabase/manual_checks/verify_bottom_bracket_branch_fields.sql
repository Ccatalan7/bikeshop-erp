-- Read-back de 20260820290000_bottom_bracket_branch_fields.sql

select tf.sort_order, sd.key, tf.section_key,
  coalesce((tf.visibility_rules -> 0 ->> 'field'), 'siempre') as depende_de
from public.spec_templates t
join public.spec_template_fields tf on tf.template_id = t.id
join public.spec_definitions sd on sd.id = tf.spec_definition_id
where t.key = 'bottom_bracket' order by tf.sort_order;

select
  -- La ficha del pedalier ya no es una lista fija de nueve.
  1 / (case when (
        select count(*) from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        where t.key = 'bottom_bracket') = 15
      then 1 else 0 end) as afirma_quince_campos,

  -- Copa y cono tiene que traer sus cuatro preguntas propias; ninguna de ellas
  -- existia para un producto de la categoria Motor antes de esto.
  1 / (case when (
        select count(*) from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        join public.spec_definitions d on d.id = tf.spec_definition_id
        cross join lateral jsonb_array_elements(tf.visibility_rules) regla
        where t.key = 'bottom_bracket'
          and regla ->> 'field' = 'bb_construction'
          and d.key in ('bb_cup_thread_pair', 'bb_cup_outer_diameter_mm',
                        'bb_ball_size_in', 'bb_ball_count_per_side')) = 4
      then 1 else 0 end) as afirma_rama_copa_y_cono,

  -- Y copas externas la suya.
  1 / (case when exists (
        select 1 from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        join public.spec_definitions d on d.id = tf.spec_definition_id
        cross join lateral jsonb_array_elements(tf.visibility_rules) regla
        where t.key = 'bottom_bracket' and d.key = 'bb_spacer_stack_mm'
          and regla ->> 'field' = 'bb_construction')
      then 1 else 0 end) as afirma_rama_copas_externas,

  -- Sigue habiendo una sola raiz sin compuerta.
  1 / (case when (
        select count(*) from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        where t.key = 'bottom_bracket'
          and tf.visibility_rules = '[]'::jsonb) = 1
      then 1 else 0 end) as afirma_una_sola_raiz,

  -- Ninguna compuerta apunta a una pregunta posterior.
  1 / (case when not exists (
        select 1 from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        cross join lateral jsonb_array_elements(tf.visibility_rules) regla
        join public.spec_definitions gd on gd.key = regla ->> 'field'
        join public.spec_template_fields gf
          on gf.template_id = tf.template_id and gf.spec_definition_id = gd.id
        where t.key = 'bottom_bracket' and gf.sort_order >= tf.sort_order)
      then 1 else 0 end) as afirma_compuertas_antes,

  -- Y toda opcion ofrecida existe en el vocabulario de su campo.
  1 / (case when not exists (
        select 1 from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        join public.spec_definitions d on d.id = tf.spec_definition_id
        cross join lateral jsonb_array_elements(tf.option_rules) regla
        cross join lateral jsonb_array_elements(
          coalesce(regla -> 'allow', '[]'::jsonb)) permitido
        where t.key = 'bottom_bracket'
          and jsonb_array_length(d.allowed_values) > 0
          and not exists (
            select 1 from jsonb_array_elements(d.allowed_values) vocab
            where vocab #>> '{}' = permitido #>> '{}'))
      then 1 else 0 end) as afirma_opciones_en_vocabulario;
