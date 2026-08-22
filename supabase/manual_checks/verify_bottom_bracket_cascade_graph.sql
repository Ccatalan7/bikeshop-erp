-- Read-back de 20260820270000_bottom_bracket_cascade_graph.sql

select tf.sort_order, sd.key, tf.section_key,
  case when tf.visibility_rules = '[]'::jsonb then 'siempre'
       else (tf.visibility_rules -> 0 ->> 'field') end as depende_de,
  jsonb_array_length(tf.option_rules) as reglas_de_opcion
from public.spec_templates t
join public.spec_template_fields tf on tf.template_id = t.id
join public.spec_definitions sd on sd.id = tf.spec_definition_id
where t.key = 'bottom_bracket' order by tf.sort_order;

select
  -- Solo la raiz de la cascada se muestra sin condicion. Cualquier otro campo
  -- sin compuerta deja elegir una combinacion que no existe: fue exactamente
  -- el defecto de «Construccion» ofreciendose sin caja del cuadro.
  1 / (case when (
        select count(*) from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        where t.key = 'bottom_bracket'
          and tf.visibility_rules = '[]'::jsonb) = 1
      then 1 else 0 end) as afirma_solo_la_raiz_sin_compuerta,

  -- Ninguna compuerta puede apuntar a una pregunta que se hace despues.
  1 / (case when not exists (
        select 1
        from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        cross join lateral jsonb_array_elements(tf.visibility_rules) regla
        join public.spec_definitions gd on gd.key = regla ->> 'field'
        join public.spec_template_fields gf
          on gf.template_id = tf.template_id
         and gf.spec_definition_id = gd.id
        where t.key = 'bottom_bracket'
          and gf.sort_order >= tf.sort_order)
      then 1 else 0 end) as afirma_las_compuertas_van_antes,

  -- Toda caja del cuadro tiene al menos una construccion posible; si una
  -- quedara sin regla, ofreceria las cinco y volveria el defecto original.
  1 / (case when (
        select count(distinct caja #>> '{}')
        from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        join public.spec_definitions sd on sd.id = tf.spec_definition_id
        cross join lateral jsonb_array_elements(tf.option_rules) regla
        cross join lateral jsonb_array_elements(regla -> 'value') caja
        where t.key = 'bottom_bracket' and sd.key = 'bb_construction') = 15
      then 1 else 0 end) as afirma_las_quince_cajas_acotan_construccion,

  -- Un valor de condicion que no existe en el vocabulario del campo al que
  -- apunta hace que la regla no calce nunca, en silencio. Una tilde corregida
  -- basta para romperlas todas.
  1 / (case when not exists (
        select 1
        from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        cross join lateral jsonb_array_elements(
          tf.visibility_rules || tf.option_rules) regla
        join public.spec_definitions rd
          on rd.key = regla ->> 'field' and rd.tenant_id is null
        cross join lateral jsonb_array_elements(
          case when jsonb_typeof(regla -> 'value') = 'array'
               then regla -> 'value'
               when regla -> 'value' is null then '[]'::jsonb
               else jsonb_build_array(regla -> 'value') end) valor
        where t.key = 'bottom_bracket'
          and rd.data_type in ('single_select', 'multi_select')
          and jsonb_array_length(rd.allowed_values) > 0
          and not exists (
            select 1 from jsonb_array_elements(rd.allowed_values) vocab
            where vocab #>> '{}' = valor #>> '{}'))
      then 1 else 0 end) as afirma_condiciones_dentro_del_vocabulario,

  -- Y lo mismo del lado que ofrece.
  1 / (case when not exists (
        select 1
        from public.spec_template_fields tf
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
      then 1 else 0 end) as afirma_opciones_dentro_del_vocabulario;
