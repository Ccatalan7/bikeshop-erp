-- Read-back de 20260820220000_bottom_bracket_compatibility_axes.sql
--
-- SQL plano: el camino de lectura alojada rechaza los bloques `do $$ … end; $$`
-- (ver AGENT_DATABASE_CONTRACT.md).

select
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'spec_template_fields'
      and column_name = 'option_rules') as columna_option_rules,
  (select count(*) from public.spec_definitions
    where tenant_id is null and key in (
      'bb_shell_standard','bb_construction','includes_spindle',
      'spindle_interface_accepted','bb_cup_thread_pair',
      'bb_cup_outer_diameter_mm','bb_ball_size_in','bb_ball_count_per_side'
    )) as definiciones_nuevas,
  (select jsonb_array_length(allowed_values) from public.spec_definitions
    where tenant_id is null and key = 'spindle_interface') as valores_interfaz,
  (select count(*) from public.spec_template_fields tf
    join public.spec_templates t on t.id = tf.template_id
    where t.key = 'bottom_bracket') as campos_pedalier;

select
  -- Sin la columna, `option_rules` se lee como null y la cascada no acota
  -- ninguna opción: el formulario vuelve a ofrecer el vocabulario entero.
  1 / (case when exists (
              select 1 from information_schema.columns
              where table_schema = 'public'
                and table_name = 'spec_template_fields'
                and column_name = 'option_rules')
            then 1 else 0 end) as afirma_columna_option_rules,

  -- Los tres ejes y los hechos de cubeta/rodamiento que el catálogo ya exige.
  1 / (case when (
              select count(*) from public.spec_definitions
              where tenant_id is null and key in (
                'bb_shell_standard','bb_construction','includes_spindle',
                'spindle_interface_accepted','bb_cup_thread_pair',
                'bb_cup_outer_diameter_mm','bb_ball_size_in',
                'bb_ball_count_per_side')) = 8
            then 1 else 0 end) as afirma_ocho_definiciones,

  -- `spindle_interface_accepted` tiene que ser multi_select: un pedalier de
  -- copas acepta 24/24 y 22/24 a la vez, y con selección única eso se pierde.
  1 / (case when (
              select data_type from public.spec_definitions
              where tenant_id is null
                and key = 'spindle_interface_accepted') = 'multi_select'
            then 1 else 0 end) as afirma_interfaz_multivalor,

  -- «Otro» y «Desconocido» no son estándares sino estados de conocimiento.
  -- Mientras vivan en la lista de valores, la marca `confirmed` que va al lado
  -- no puede significar nada.
  1 / (case when not exists (
              select 1 from public.spec_definitions d
              cross join lateral jsonb_array_elements(d.allowed_values) v
              where d.tenant_id is null
                and d.key in ('spindle_interface','spindle_interface_accepted',
                              'bb_shell_standard','bb_construction')
                and (v #>> '{}' ilike '%otro%'
                     or v #>> '{}' ilike '%desconocid%'))
            then 1 else 0 end) as afirma_sin_estados_de_duda,

  -- Un número sin `allowed_values` se dibuja como caja de texto libre, que es
  -- lo que dejaba entrar un largo de eje de 117,71 mm.
  1 / (case when not exists (
              select 1 from public.spec_definitions
              where tenant_id is null
                and key in ('bb_shell_width_mm','bb_shell_diameter_mm',
                            'spindle_length_mm','spindle_diameter_mm')
                and jsonb_array_length(allowed_values) = 0)
            then 1 else 0 end) as afirma_numeros_acotados,

  -- 124,5 mm es el único valor de ficha vivo en toda la vecindad del pedalier.
  -- Si el vocabulario no lo admite, la migración rompió dato real.
  1 / (case when exists (
              select 1 from public.spec_definitions d
              cross join lateral jsonb_array_elements(d.allowed_values) v
              where d.tenant_id is null and d.key = 'spindle_length_mm'
                and (v #>> '{}')::numeric = 124.5)
            then 1 else 0 end) as afirma_largo_real_admitido,

  -- El orden de secciones sale del primer `sort_order` visto. Si un campo de
  -- dimensiones queda antes que el estándar, el formulario vuelve a pedir las
  -- medidas antes de saber qué caja es.
  1 / (case when (
              select tf.section_key from public.spec_template_fields tf
              join public.spec_templates t on t.id = tf.template_id
              where t.key = 'bottom_bracket'
              order by tf.sort_order limit 1) = 'compatibility'
            then 1 else 0 end) as afirma_compatibilidad_primero,

  -- Los dos campos mal ejeados salen de las plantillas de pedalier.
  1 / (case when not exists (
              select 1 from public.spec_template_fields tf
              join public.spec_templates t on t.id = tf.template_id
              join public.spec_definitions d on d.id = tf.spec_definition_id
              where t.key in ('bottom_bracket','bottom_bracket_cup',
                              'bottom_bracket_axle','bottom_bracket_bearing')
                and d.key in ('bottom_bracket_family','bb_thread_standard'))
            then 1 else 0 end) as afirma_ejes_mezclados_retirados,

  -- Una regla que ofrece un valor fuera de `allowed_values` deja al mecánico
  -- elegir algo que después no se puede guardar.
  1 / (case when not exists (
              select 1
              from public.spec_template_fields tf
              join public.spec_definitions d on d.id = tf.spec_definition_id
              cross join lateral jsonb_array_elements(tf.option_rules) regla
              cross join lateral jsonb_array_elements(
                coalesce(regla -> 'allow', '[]'::jsonb)) permitido
              where jsonb_array_length(d.allowed_values) > 0
                and not exists (
                  select 1
                  from jsonb_array_elements(d.allowed_values) vocabulario
                  where vocabulario #>> '{}' = permitido #>> '{}'))
            then 1 else 0 end) as afirma_reglas_dentro_del_vocabulario,

  -- Toda regla apunta a un campo que existe en la misma plantilla; si no, la
  -- condición nunca se cumple y el campo queda oculto o sin acotar para siempre.
  1 / (case when not exists (
              select 1
              from public.spec_template_fields tf
              cross join lateral jsonb_array_elements(
                tf.visibility_rules || tf.option_rules) regla
              where regla ? 'field'
                and not exists (
                  select 1
                  from public.spec_template_fields hermano
                  join public.spec_definitions hd
                    on hd.id = hermano.spec_definition_id
                  where hermano.template_id = tf.template_id
                    and hd.key = regla ->> 'field'))
            then 1 else 0 end) as afirma_reglas_apuntan_a_campos_reales;
