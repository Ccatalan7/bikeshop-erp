-- La ficha de la transmisión quedó llena, y ningún código de modelo se coló
-- como velocidad.

with piezas as (
  select p.id, c.name categoria
  from public.products p
  join public.product_categories c on c.id = p.category_id
  where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and p.is_active and c.name in ('Cadenas','Cassette','Piñones')
), hechos as (
  select piezas.categoria, d.key, f.source, f.confirmed, f.value_number,
    coalesce(f.value_number::text,
      (select dv.label from public.spec_fact_values fv
        join public.spec_definition_values dv on dv.id = fv.value_id
       where fv.fact_id = f.id limit 1)) valor
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  join piezas on piezas.id = f.subject_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and f.subject_type = 'product'
)
select categoria,
  count(*) hechos,
  count(*) filter (where key in ('chain_speeds','drivetrain_speeds')) velocidades,
  count(*) filter (where key = 'chain_width_family') ancho_cadena,
  count(*) filter (where key = 'link_count') eslabones,
  count(*) filter (where key = 'smallest_cog_teeth') corona_chica,
  count(*) filter (where key = 'largest_cog_teeth') corona_grande,
  count(*) filter (where source = 'inferred') deducidos,
  count(*) filter (where confirmed) falsos_confirmados,
  count(*) filter (where valor is null) hechos_sin_valor
from hechos group by 1 order by 2 desc;

-- Afirmación 1: cero confirmados falsos, cero hechos sin valor y nada deducido.
with hechos as (
  select f.confirmed, f.source,
    coalesce(f.value_number::text,
      (select dv.label from public.spec_fact_values fv
        join public.spec_definition_values dv on dv.id = fv.value_id
       where fv.fact_id = f.id limit 1)) valor
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  join public.products p on p.id = f.subject_id
  join public.product_categories c on c.id = p.category_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and f.subject_type = 'product'
    and c.name in ('Cadenas','Cassette','Piñones')
    and d.key in ('chain_speeds','drivetrain_speeds','chain_width_family',
                  'link_count','smallest_cog_teeth','largest_cog_teeth')
)
select 1 / (case when (
  select count(*) from hechos
  where confirmed or valor is null or source = 'inferred'
) = 0 then 1 else 0 end) as afirma_solo_lo_que_el_nombre_dice;

-- Afirmación 2: ningún rango invertido ni fuera del rango físico de una corona.
-- Un piñón «12-14» sería la secuencia completa leída por su primer par.
with coronas as (
  select f.subject_id,
    max(f.value_number) filter (where d.key = 'smallest_cog_teeth') chica,
    max(f.value_number) filter (where d.key = 'largest_cog_teeth') grande
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  join public.products p on p.id = f.subject_id
  join public.product_categories c on c.id = p.category_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and f.subject_type = 'product'
    and c.name in ('Cassette','Piñones')
    and d.key in ('smallest_cog_teeth','largest_cog_teeth')
  group by f.subject_id
)
select 1 / (case when (
  select count(*) from coronas
  where chica is null or grande is null or chica >= grande
     or chica < 9 or chica > 18 or grande < 21 or grande > 60
) = 0 then 1 else 0 end) as afirma_rangos_de_corona_sanos;

-- Afirmación 3: ninguna velocidad absurda. Una bicicleta no tiene 410 ni 4100
-- velocidades: si un código de modelo se coló, aparece acá.
with velocidades as (
  select dv.label::int vel
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  join public.spec_fact_values fv on fv.fact_id = f.id
  join public.spec_definition_values dv on dv.id = fv.value_id
  join public.products p on p.id = f.subject_id
  join public.product_categories c on c.id = p.category_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and f.subject_type = 'product'
    and c.name in ('Cadenas','Cassette','Piñones')
    and d.key in ('chain_speeds','drivetrain_speeds')
)
select 1 / (case when (
  select count(*) from velocidades where vel < 1 or vel > 13
) = 0 then 1 else 0 end) as afirma_ningun_codigo_de_modelo_como_velocidad;
