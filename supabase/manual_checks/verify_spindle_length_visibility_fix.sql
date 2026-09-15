-- Read-back de 20260820280000_spindle_length_visibility_fix.sql

select d.key, tf.visibility_rules
from public.spec_template_fields tf
join public.spec_templates t on t.id = tf.template_id
join public.spec_definitions d on d.id = tf.spec_definition_id
where t.key = 'bottom_bracket' and d.key = 'spindle_length_mm';

select
  -- Ningun pedalier con largo guardado puede quedar con el campo escondido:
  -- el guardado borra lo que no viene en el payload.
  1 / (case when not exists (
        select 1
        from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        join public.products p on p.id = v.product_id
        join public.product_categories c on c.id = p.category_id
        join public.category_tech_mappings m
          on m.category_id = c.id and m.status = 'active'
        join public.spec_templates t
          on t.id = m.template_id and t.key = 'bottom_bracket'
        join public.spec_template_fields tf
          on tf.template_id = t.id and tf.spec_definition_id = d.id
        cross join lateral jsonb_array_elements(tf.visibility_rules) regla
        where d.key = 'spindle_length_mm'
          and v.value_number is not null
          -- la compuerta apunta a una interfaz que este producto no tiene
          and regla ->> 'field' = 'spindle_interface'
          and regla ->> 'operator' = 'in'
          and not exists (
            select 1 from public.product_spec_values iv
            join public.spec_definitions id2 on id2.id = iv.spec_definition_id
            where iv.product_id = p.id and id2.key = 'spindle_interface'))
      then 1 else 0 end) as afirma_ningun_largo_escondido,

  -- Y la interfaz pasante si lo esconde.
  1 / (case when exists (
        select 1 from public.spec_template_fields tf
        join public.spec_templates t on t.id = tf.template_id
        join public.spec_definitions d on d.id = tf.spec_definition_id
        cross join lateral jsonb_array_elements(tf.visibility_rules) regla
        where t.key = 'bottom_bracket' and d.key = 'spindle_length_mm'
          and regla ->> 'field' = 'spindle_interface'
          and regla ->> 'operator' = 'not_in')
      then 1 else 0 end) as afirma_esconde_solo_los_pasantes;
