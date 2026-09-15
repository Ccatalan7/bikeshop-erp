-- La bodega filtra por las características guardadas, no por la frase.
select set_config('request.jwt.claim.sub',
  (select up.user_id::text from public.user_profiles up
    where up.tenant_id='5443b130-cc28-45af-a420-cd500b288890'
      and up.user_id is not null and up.role in ('owner','admin','manager')
    order by case up.role when 'owner' then 1 when 'admin' then 2 else 3 end,
             up.created_at asc nulls last limit 1), true) as actor;
select set_config('request.jwt.claim.role','authenticated', true) as rol;

with necesidad as (
  select n.id from public.supply_needs n
  where n.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
    and n.original_description ilike '%27.5%'
    and n.original_description ilike '%auto%'
  order by n.created_at desc limit 1
), verdad as (
  -- Lo que la ficha dice: 27.5" + Schrader.
  select count(*) n from public.products p
  where p.tenant_id = '5443b130-cc28-45af-a420-cd500b288890' and p.is_active
    and exists (select 1 from public.spec_facts f
      join public.spec_definitions d on d.id = f.spec_definition_id
      join public.spec_fact_values fv on fv.fact_id = f.id
      join public.spec_definition_values dv on dv.id = fv.value_id
      where f.subject_id = p.id and d.key = 'wheel_size' and dv.code = 'v_27_5')
    and exists (select 1 from public.spec_facts f
      join public.spec_definitions d on d.id = f.spec_definition_id
      join public.spec_fact_values fv on fv.fact_id = f.id
      join public.spec_definition_values dv on dv.id = fv.value_id
      where f.subject_id = p.id and d.key = 'valve_type' and dv.code = 'schrader')
)
select
  (select n from verdad) segun_la_ficha,
  (public.supply_need_stock_candidates_v1((select id from necesidad), 8)
    ->> 'totalMatches')::int devuelve_el_paso,
  (select n from verdad) =
    (public.supply_need_stock_candidates_v1((select id from necesidad), 8)
      ->> 'totalMatches')::int calzan;
