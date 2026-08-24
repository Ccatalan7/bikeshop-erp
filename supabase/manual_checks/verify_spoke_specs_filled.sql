-- La ficha de los rayos quedó llena, y ningún nipple se coló como largo.
--
-- Diagnóstico primero —es lo que explica qué faltó cuando una afirmación
-- muerde— y después las afirmaciones, que dividen por cero.

with rayos as (
  select p.id, p.name
  from public.products p
  join public.product_categories c on c.id = p.category_id
  where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and p.is_active and c.name = 'Rayos'
), hechos as (
  select f.subject_id, d.key, f.source, f.confirmed, f.value_number,
    coalesce(f.value_number::text,
      (select dv.code from public.spec_fact_values fv
        join public.spec_definition_values dv on dv.id = fv.value_id
       where fv.fact_id = f.id limit 1)) valor
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  join rayos on rayos.id = f.subject_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and f.subject_type = 'product'
)
select
  (select count(*) from rayos) rayos,
  count(distinct subject_id) con_ficha,
  count(*) hechos_totales,
  count(*) filter (where key = 'spoke_length_mm') largo,
  count(*) filter (where key = 'spoke_gauge') calibre,
  count(*) filter (where key = 'spoke_bend_type') curva,
  min(value_number) filter (where key = 'spoke_length_mm') largo_min,
  max(value_number) filter (where key = 'spoke_length_mm') largo_max,
  count(*) filter (where source = 'supplier_text') leidos_del_nombre,
  count(*) filter (where source = 'inferred') deducidos,
  count(*) filter (where confirmed) falsos_confirmados,
  count(*) filter (where valor is null) hechos_sin_valor,
  -- Un nipple mide 12-16 mm: si uno se coló como largo, aparece acá.
  count(*) filter (
    where key = 'spoke_length_mm' and (value_number < 150 or value_number > 310)
  ) largos_fuera_de_rango
from hechos;

-- Afirmación 1: todo rayo activo tiene su largo. Es el dato por el que se
-- pregunta, así que un rayo sin él no sirve para nada en la cadena.
with rayos as (
  select p.id from public.products p
  join public.product_categories c on c.id = p.category_id
  where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and p.is_active and c.name = 'Rayos'
)
select 1 / (case when (
  select count(*) from rayos
  where not exists (
    select 1 from public.spec_facts f
    join public.spec_definitions d on d.id = f.spec_definition_id
    where f.subject_id = rayos.id and f.subject_type = 'product'
      and d.key = 'spoke_length_mm')
) = 0 then 1 else 0 end) as afirma_que_todo_rayo_tiene_largo;

-- Afirmación 2: ningún largo fuera del rango físico — o sea, ningún nipple ni
-- grosor de alambre disfrazado de largo.
with largos as (
  select f.value_number
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  join public.products p on p.id = f.subject_id
  join public.product_categories c on c.id = p.category_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and f.subject_type = 'product' and c.name = 'Rayos'
    and d.key = 'spoke_length_mm'
)
select 1 / (case when (
  select count(*) from largos where value_number < 150 or value_number > 310
) = 0 then 1 else 0 end) as afirma_ningun_nipple_como_largo;

-- Afirmación 3: cero confirmados falsos, cero hechos sin valor y nada deducido.
with hechos as (
  select f.confirmed, f.source,
    coalesce(f.value_number::text,
      (select dv.code from public.spec_fact_values fv
        join public.spec_definition_values dv on dv.id = fv.value_id
       where fv.fact_id = f.id limit 1)) valor
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  join public.products p on p.id = f.subject_id
  join public.product_categories c on c.id = p.category_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and f.subject_type = 'product' and c.name = 'Rayos'
    and d.key like 'spoke%'
)
select 1 / (case when (
  select count(*) from hechos
  where confirmed or valor is null or source = 'inferred'
) = 0 then 1 else 0 end) as afirma_solo_lo_que_el_nombre_dice;
