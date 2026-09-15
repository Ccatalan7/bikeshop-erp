-- Read-back de 20260820250000_bottom_bracket_ficha_accents.sql

select key, label from public.spec_definitions
where tenant_id is null and key in
  ('bb_construction','bb_cup_outer_diameter_mm','bb_ball_size_in') order by key;

select
  -- La etiqueta que se ve en la ficha real lleva tilde.
  1 / (case when (select label from public.spec_definitions
        where key = 'bb_construction' and tenant_id is null) = 'Construcción'
      then 1 else 0 end) as afirma_construccion_con_tilde,

  -- Y la ayuda del primer campo de la cascada tambien.
  1 / (case when exists (
        select 1 from public.spec_template_fields tf
        join public.spec_definitions d on d.id = tf.spec_definition_id
        join public.spec_templates t on t.id = tf.template_id
        where d.key = 'bb_shell_standard' and t.key = 'bottom_bracket'
          and tf.helper_text like '%acá%' and tf.helper_text like '%diámetro%')
      then 1 else 0 end) as afirma_ayuda_con_tildes,

  -- El vocabulario de la caja mantiene sus 15 valores tras el reemplazo.
  1 / (case when (select jsonb_array_length(allowed_values)
        from public.spec_definitions
        where key = 'bb_shell_standard' and tenant_id is null) = 15
      then 1 else 0 end) as afirma_quince_cajas,

  -- Y ningun producto quedo con un valor fuera de la lista reescrita.
  1 / (case when not exists (
        select 1 from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key in ('bb_shell_standard','bb_cup_thread_pair')
          and d.tenant_id is null and v.value_option is not null
          and not exists (
            select 1 from jsonb_array_elements(d.allowed_values) vo
            where vo #>> '{}' = v.value_option))
      then 1 else 0 end) as afirma_sin_huerfanos_tras_reescritura;
