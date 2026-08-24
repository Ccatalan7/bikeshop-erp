-- La ficha de los neumáticos quedó llena, y nada se inventó.
--
-- Primero el diagnóstico —que es lo que le explica al operador qué pasó— y
-- después las afirmaciones, que muerden dividiendo por cero. Sin la fila de
-- diagnóstico delante, el error diría sólo «division by zero» y no qué faltó.

with neumaticos as (
  select p.id, p.name
  from public.products p
  join public.product_categories c on c.id = p.category_id
  where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and p.is_active and c.name = 'Neumáticos'
), hechos as (
  select f.subject_id, d.key, f.source, f.confirmed, f.value_number,
    coalesce(f.value_number::text, f.value_boolean::text,
      (select dv.code from public.spec_fact_values fv
        join public.spec_definition_values dv on dv.id = fv.value_id
       where fv.fact_id = f.id limit 1)) valor
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  join neumaticos on neumaticos.id = f.subject_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and f.subject_type = 'product'
)
select
  (select count(*) from neumaticos) neumaticos,
  count(distinct subject_id) con_ficha,
  count(*) hechos_totales,
  count(*) filter (where key = 'wheel_size') aro,
  count(*) filter (where key = 'tire_width_in') ancho_pulgadas,
  count(*) filter (where key = 'tire_width_mm') ancho_mm,
  count(*) filter (where key = 'tire_bead_type') talon,
  count(*) filter (where key = 'tire_tubeless_ready' and valor = 'true') tubeless,
  -- Todo salió del nombre: acá no se dedujo nada, a diferencia de las cámaras.
  count(*) filter (where source = 'supplier_text') leidos_del_nombre,
  count(*) filter (where source = 'inferred') deducidos,
  -- Nada puede haber quedado marcado como verificado por una persona.
  count(*) filter (where confirmed) falsos_confirmados,
  -- Ninguna selección puede haber quedado sin valor.
  count(*) filter (where valor is null) hechos_sin_valor,
  -- Ningún ancho fuera del rango físico de un neumático de bicicleta.
  count(*) filter (
    where key = 'tire_width_in' and (value_number < 0.7 or value_number > 5.0)
  ) + count(*) filter (
    where key = 'tire_width_mm' and (value_number < 15 or value_number > 90)
  ) anchos_fuera_de_rango
from hechos;

-- Afirmación 1: cada neumático activo tiene su aro.
with neumaticos as (
  select p.id from public.products p
  join public.product_categories c on c.id = p.category_id
  where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and p.is_active and c.name = 'Neumáticos'
)
select 1 / (case when (
  select count(*) from neumaticos
  where not exists (
    select 1 from public.spec_facts f
    join public.spec_definitions d on d.id = f.spec_definition_id
    where f.subject_id = neumaticos.id and f.subject_type = 'product'
      and d.key = 'wheel_size')
) = 0 then 1 else 0 end) as afirma_que_todo_neumatico_tiene_aro;

-- Afirmación 2: cero confirmados falsos y cero hechos sin valor.
with hechos as (
  select f.id, f.confirmed,
    coalesce(f.value_number::text, f.value_boolean::text,
      (select dv.code from public.spec_fact_values fv
        join public.spec_definition_values dv on dv.id = fv.value_id
       where fv.fact_id = f.id limit 1)) valor
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  join public.products p on p.id = f.subject_id
  join public.product_categories c on c.id = p.category_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and f.subject_type = 'product' and c.name = 'Neumáticos'
    and d.key like 'tire%'
)
select 1 / (case when (
  select count(*) from hechos where confirmed or valor is null
) = 0 then 1 else 0 end) as afirma_ni_confirmados_falsos_ni_hechos_vacios;

-- Afirmación 3: ningún ancho fuera del rango físico.
with anchos as (
  select d.key, f.value_number
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  join public.products p on p.id = f.subject_id
  join public.product_categories c on c.id = p.category_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and f.subject_type = 'product' and c.name = 'Neumáticos'
    and d.key in ('tire_width_in', 'tire_width_mm')
)
select 1 / (case when (
  select count(*) from anchos
  where (key = 'tire_width_in' and (value_number < 0.7 or value_number > 5.0))
     or (key = 'tire_width_mm' and (value_number < 15 or value_number > 90))
) = 0 then 1 else 0 end) as afirma_todo_ancho_dentro_de_rango;

-- Afirmación 4: un neumático tiene UN ancho, nunca los dos campos a la vez.
with dobles as (
  select f.subject_id
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  join public.products p on p.id = f.subject_id
  join public.product_categories c on c.id = p.category_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and f.subject_type = 'product' and c.name = 'Neumáticos'
    and d.key in ('tire_width_in', 'tire_width_mm')
  group by f.subject_id having count(*) > 1
)
select 1 / (case when (select count(*) from dobles) = 0 then 1 else 0 end)
  as afirma_un_solo_ancho_por_neumatico;
