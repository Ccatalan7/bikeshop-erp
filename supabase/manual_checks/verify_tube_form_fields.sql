-- El formulario de la cámara tiene los nueve campos, y el ancho es numérico.
select
  count(*) campos,
  count(*) filter (where d.data_type = 'number') numericos,
  count(*) filter (where d.key like 'tube_width%') campos_de_ancho,
  count(*) filter (where d.key = 'tube_has_sealant') sellante,
  count(*) filter (where d.key = 'tube_material') material,
  (select count(*) from public.spec_definition_values v
    join public.spec_definitions d2 on d2.id = v.spec_definition_id
   where d2.key = 'tube_material' and v.is_active) opciones_material,
  -- El ancho NO puede tener lista de opciones: es una medida.
  (select bool_and(jsonb_array_length(coalesce(d3.allowed_values,'[]'::jsonb)) = 0)
     from public.spec_definitions d3 where d3.key like 'tube_width%')
    ancho_sin_lista
from public.spec_template_fields f
join public.spec_templates t on t.id = f.template_id
join public.spec_definitions d on d.id = f.spec_definition_id
where t.key = 'tube';
