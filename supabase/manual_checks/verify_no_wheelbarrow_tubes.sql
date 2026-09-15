-- Ninguna cámara de bicicleta queda sin medida de rueda, y la de carretilla
-- ya no puede colarse como alternativa de un aro 27.5.
select
  (select count(*) from public.products p
    where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890' and p.is_active
      and (p.name ilike 'camara%' or p.name ilike 'cámara%')
      and p.name not ilike '%servicio%'
      and not exists (
        select 1 from public.spec_facts f
        join public.spec_definitions d on d.id = f.spec_definition_id
        where f.subject_id = p.id and d.key = 'wheel_size'))
    camaras_sin_medida,
  (select dv.label from public.products p
    join public.spec_facts f on f.subject_id = p.id
    join public.spec_definitions d on d.id = f.spec_definition_id and d.key = 'wheel_size'
    join public.spec_fact_values fv on fv.fact_id = f.id
    join public.spec_definition_values dv on dv.id = fv.value_id
    where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and p.name ilike '%carretilla%' limit 1) la_de_carretilla,
  (select dv.label from public.products p
    join public.spec_facts f on f.subject_id = p.id
    join public.spec_definitions d on d.id = f.spec_definition_id and d.key = 'wheel_size'
    join public.spec_fact_values fv on fv.fact_id = f.id
    join public.spec_definition_values dv on dv.id = fv.value_id
    where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and p.name ilike '%12 1/2 X 1.75%' limit 1) la_de_aro_12;
