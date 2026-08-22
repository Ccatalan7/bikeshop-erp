-- Read-back de 20260820230000_backfill_bottom_bracket_ficha.sql
--
-- SQL plano: el camino de lectura alojada rechaza los bloques `do $$ … end; $$`.

with pedalier as (
  select p.id, p.tenant_id
  from public.products p
  join public.product_categories c on c.id = p.category_id
  join public.category_tech_mappings m
    on m.category_id = c.id and m.status = 'active'
  join public.spec_templates t
    on t.id = m.template_id and t.key = 'bottom_bracket'
  where p.is_active is true
),
valores as (
  select d.key, v.value_option, v.value_boolean, v.value_number, v.product_id
  from public.product_spec_values v
  join pedalier on pedalier.id = v.product_id
  join public.spec_definitions d on d.id = v.spec_definition_id
)
select
  (select count(*) from pedalier) as productos,
  (select count(*) from valores where key = 'bb_construction') as con_construccion,
  (select count(*) from valores where key = 'includes_spindle') as con_trae_eje,
  (select count(*) from valores where key = 'includes_spindle' and value_boolean) as traen_eje,
  (select count(*) from valores where key = 'spindle_length_mm') as con_largo,
  (select count(*) from valores where key = 'bb_shell_width_mm') as con_ancho,
  (select count(*) from valores where key = 'spindle_interface') as con_interfaz_adivinada;

select
  -- Toda la familia queda descrita en el eje que faltaba. Un solo hueco aca
  -- significa que la clasificacion por nombre dejo un producto sin construccion.
  1 / (case when (
        select count(*) from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        join public.products p on p.id = v.product_id
        join public.product_categories c on c.id = p.category_id
        join public.category_tech_mappings m
          on m.category_id = c.id and m.status = 'active'
        join public.spec_templates t
          on t.id = m.template_id and t.key = 'bottom_bracket'
        where d.key = 'bb_construction' and p.is_active is true) = 34
      then 1 else 0 end) as afirma_treinta_y_cuatro_con_construccion,

  -- 29 cartuchos traen eje, 4 copas externas y 1 prensado no.
  1 / (case when (
        select count(*) from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key = 'includes_spindle' and v.value_boolean is true) = 29
      then 1 else 0 end) as afirma_veintinueve_traen_eje,

  -- El HASSNS acepta Hollowtech y GXP a la vez. Si esto vuelve a un solo valor,
  -- se perdio la razon por la que la interfaz aceptada es multivalor.
  1 / (case when exists (
        select 1 from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key = 'spindle_interface_accepted'
          and jsonb_array_length(v.value_json) = 2) then 1 else 0 end)
      as afirma_producto_de_doble_interfaz,

  -- Un nombre que dice SQUARE TYPE prueba que el eje es cuadrado, no que sea
  -- JIS o ISO. Si aparecio un `spindle_interface`, alguien adivino.
  1 / (case when not exists (
        select 1 from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        join public.products p on p.id = v.product_id
        join public.product_categories c on c.id = p.category_id
        join public.category_tech_mappings m
          on m.category_id = c.id and m.status = 'active'
        join public.spec_templates t
          on t.id = m.template_id and t.key = 'bottom_bracket'
        where d.key = 'spindle_interface') then 1 else 0 end)
      as afirma_ninguna_interfaz_adivinada,

  -- Todo valor que este backfill escribio tiene que existir en el vocabulario de
  -- su definicion. Un valor fuera de la lista no se puede filtrar en
  -- `assistant_search_inventory_v7`, que valida contra `allowed_values`.
  --
  -- El alcance es la familia del pedalier a proposito. La misma consulta sin
  -- filtrar encuentra 4 filas heredadas de otra familia
  -- (`valve_length_mm` = 40 y 48, fuera de su lista 35/44/60/80), que es un
  -- defecto real y anterior a esta migracion; se arregla aparte y no puede
  -- bloquear el sello de este cambio.
  1 / (case when not exists (
        select 1 from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        join public.products p on p.id = v.product_id
        join public.product_categories c on c.id = p.category_id
        join public.category_tech_mappings m
          on m.category_id = c.id and m.status = 'active'
        join public.spec_templates t
          on t.id = m.template_id and t.key = 'bottom_bracket'
        where d.tenant_id is null
          and jsonb_array_length(d.allowed_values) > 0
          and coalesce(v.value_option, v.value_number::text) is not null
          and not exists (
            select 1 from jsonb_array_elements(d.allowed_values) vocab
            where vocab #>> '{}' = coalesce(v.value_option, v.value_number::text)))
      then 1 else 0 end) as afirma_valores_dentro_del_vocabulario;
