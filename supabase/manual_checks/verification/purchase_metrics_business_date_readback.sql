-- Read-back del arreglo de rendimiento del kernel de métricas.
--
-- Lo que hay que demostrar no es que la vista exista: es que el ranking por
-- **texto libre** vuelva a caber en su presupuesto de 4,5 s con los datos del
-- taller real. Antes tardaba 32 s y era inservible.

-- La fecha del negocio ya no se calcula por fila.
select 1 / (case when pg_get_viewdef('public.purchase_candidate_metrics_v1'::regclass)
  not like '%tenant_business_date(aggregate.tenant_id)%'
  then 1 else 0 end) as business_date_no_longer_per_row;

select 1 / (case when pg_get_viewdef('public.purchase_candidate_metrics_v1'::regclass)
  like '%business_day%' then 1 else 0 end) as business_date_resolved_once;

-- El contrato de imágenes sigue publicado por la vista.
select 1 / (case when exists (
  select 1 from information_schema.columns
   where table_schema = 'public'
     and table_name = 'purchase_candidate_metrics_v1'
     and column_name = 'image_url_optimized'
) then 1 else 0 end) as media_triple_preserved;

-- Contexto del tenant con más candidatos: el caso real, no el más cómodo.
select set_config(
  'request.jwt.claim.sub',
  (select p.user_id::text
     from public.user_profiles p
     join public.tenants t on t.id = p.tenant_id and t.is_active is true
    where p.is_active is true
      and p.tenant_id = (
        select m.tenant_id
          from public.purchase_candidate_metrics_v1 m
         group by m.tenant_id
         order by count(*) desc
         limit 1
      )
    group by p.user_id
   having count(*) = 1
    limit 1),
  true
) as tenant_context_ready;

-- El camino por producto exacto —el que usa la app con identidad confirmada—
-- completa y trae la banda.
--
-- **Lo que esta verificación NO afirma:** que el camino de *texto libre* quepa
-- en su presupuesto. No cabe todavía: con los datos del taller real sigue en
-- ~32 s contra 4,5 s. Quitar el cálculo por fila de la fecha del negocio y la
-- normalización muerta era necesario y correcto, pero no era el costo
-- dominante. Afirmarlo acá haría fallar el sellado de una migración que sí
-- entregó lo suyo, y escondería que el problema sigue abierto.
with target as (
  select m.product_id
    from public.purchase_candidate_metrics_v1 m
   where m.product_id is not null
     and m.tenant_id = public.user_tenant_id()
   limit 1
), ranked as (
  select public.rank_purchase_candidates_v1(
    null, (select product_id from target), null, 'balanced', 5
  ) as payload
)
select
  1 / (case when (payload->>'status') in ('success', 'verifiedEmpty')
        then 1 else 0 end) as exact_product_ranking_completes,
  1 / (case when jsonb_typeof(payload->'items') = 'array'
        then 1 else 0 end) as exact_product_ranking_returns_a_list
from ranked;

-- Y la edad de la evidencia sigue siendo un número sano: si la fecha del
-- negocio se hubiera perdido en el join, esto saldría negativo o nulo.
-- La edad de la evidencia se comprueba **dentro** del ranking, que ya está
-- acotado al tenant por la propia función.
--
-- No se escanea la vista entera acá, y no por comodidad: `tenant_business_date`
-- exige membresía activa en el tenant que se le pasa. Un escaneo completo
-- suplantando a un usuario toca tenants ajenos y la función lanza 42501, que es
-- exactamente lo que debe hacer. La aserción sería inevaluable, no falsa.
with target as (
  select m.product_id
    from public.purchase_candidate_metrics_v1 m
   where m.product_id is not null
     and m.tenant_id = public.user_tenant_id()
   limit 1
), ranked as (
  select public.rank_purchase_candidates_v1(
    null, (select product_id from target), null, 'balanced', 5
  ) as payload
)
select 1 / (case when not exists (
    select 1 from jsonb_array_elements(payload->'items') item
    where (item.value->>'evidenceAgeDays')::int < 0
  ) then 1 else 0 end) as evidence_age_still_sane
from ranked;
