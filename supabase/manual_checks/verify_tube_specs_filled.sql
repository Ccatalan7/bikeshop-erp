-- La ficha de las cámaras quedó llena, y nada se inventó.
with camaras as (
  select id, name from public.products
  where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and is_active and (name ilike 'camara%' or name ilike 'cámara%')
), hechos as (
  select f.subject_id, d.key, f.source, f.confirmed,
    coalesce(f.value_number::text, f.value_boolean::text,
      (select dv.code from public.spec_fact_values fv
        join public.spec_definition_values dv on dv.id = fv.value_id
       where fv.fact_id = f.id limit 1)) valor
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  join camaras on camaras.id = f.subject_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and f.subject_type = 'product'
)
select
  (select count(*) from camaras) camaras,
  count(distinct subject_id) con_ficha,
  count(*) hechos_totales,
  count(*) filter (where key = 'wheel_size') rueda,
  count(*) filter (where key = 'valve_type') valvula,
  count(*) filter (where key = 'valve_length_mm') largo,
  count(*) filter (where key like 'tube_width%') anchos,
  count(*) filter (where key = 'tube_has_sealant' and valor = 'true') con_liquido,
  count(*) filter (where key = 'tube_material') material,
  count(*) filter (where source = 'supplier_text') leidos_del_nombre,
  count(*) filter (where source = 'inferred') deducidos,
  -- Nada puede haber quedado marcado como verificado por una persona.
  count(*) filter (where confirmed and source in ('supplier_text','inferred'))
    falsos_confirmados,
  -- Ninguna selección puede haber quedado sin valor.
  count(*) filter (where valor is null) hechos_sin_valor
from hechos;
