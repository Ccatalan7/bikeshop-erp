-- El ancho llegó a las que faltaban, y ninguna quedó con una medida imposible.
with camaras as (
  select id, name from public.products
  where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and is_active and (name ilike 'camara%' or name ilike 'cámara%')
), ancho as (
  select c.id, c.name,
    max(case when d.key = 'tube_width_min_in' then f.value_number end) min_in,
    max(case when d.key = 'tube_width_max_in' then f.value_number end) max_in,
    max(case when d.key = 'tube_width_min_mm' then f.value_number end) min_mm,
    max(case when d.key = 'tube_width_max_mm' then f.value_number end) max_mm
  from camaras c
  left join public.spec_facts f on f.subject_id = c.id
    and f.subject_type = 'product'
    and f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  left join public.spec_definitions d on d.id = f.spec_definition_id
    and d.key like 'tube_width%'
  group by c.id, c.name
)
select
  count(*) camaras,
  count(*) filter (where min_in is not null or min_mm is not null) con_ancho,
  count(*) filter (where min_in is not null) en_pulgadas,
  count(*) filter (where min_mm is not null) en_milimetros,
  count(*) filter (where min_in = max_in or min_mm = max_mm) ancho_unico,
  -- Ninguna medida imposible: ni máximo bajo el mínimo, ni pulgadas absurdas.
  count(*) filter (where max_in < min_in or max_mm < min_mm) invertidas,
  count(*) filter (where min_in is not null
    and (min_in < 0.5 or max_in > 3.5)) pulgadas_fuera_de_rango,
  count(*) filter (where min_mm is not null
    and (min_mm < 10 or max_mm > 120)) mm_fuera_de_rango
from ancho;
