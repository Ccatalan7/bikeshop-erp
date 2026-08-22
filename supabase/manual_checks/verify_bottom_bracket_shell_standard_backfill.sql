-- Read-back de 20260820260000_bottom_bracket_shell_standard_backfill.sql

select coalesce(v.value_option, 'sin caja') as caja, count(*)
from public.products p
join public.product_categories c on c.id = p.category_id
join public.category_tech_mappings m
  on m.category_id = c.id and m.status = 'active'
join public.spec_templates t on t.id = m.template_id and t.key = 'bottom_bracket'
left join public.spec_definitions d
  on d.key = 'bb_shell_standard' and d.tenant_id is null
left join public.product_spec_values v
  on v.product_id = p.id and v.spec_definition_id = d.id
where p.is_active is true
group by 1 order by 2 desc;

select
  -- Ningun pedalier queda sin caja: la ficha ya no abre con un campo
  -- obligatorio en blanco.
  1 / (case when not exists (
        select 1 from public.products p
        join public.product_categories c on c.id = p.category_id
        join public.category_tech_mappings m
          on m.category_id = c.id and m.status = 'active'
        join public.spec_templates t
          on t.id = m.template_id and t.key = 'bottom_bracket'
        where p.is_active is true
          and not exists (
            select 1 from public.product_spec_values v
            join public.spec_definitions d on d.id = v.spec_definition_id
            where v.product_id = p.id and d.key = 'bb_shell_standard'))
      then 1 else 0 end) as afirma_todos_con_caja,

  -- El Mid BMX conserva la suya: no se lo pinto de BSA por barrer parejo.
  1 / (case when exists (
        select 1 from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key = 'bb_shell_standard' and v.value_option = 'Mid BMX 41.2mm')
      then 1 else 0 end) as afirma_mid_bmx_intacto,

  -- Y ninguna caja quedo fuera del vocabulario.
  1 / (case when not exists (
        select 1 from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key = 'bb_shell_standard' and d.tenant_id is null
          and not exists (
            select 1 from jsonb_array_elements(d.allowed_values) vo
            where vo #>> '{}' = v.value_option))
      then 1 else 0 end) as afirma_cajas_en_vocabulario;
