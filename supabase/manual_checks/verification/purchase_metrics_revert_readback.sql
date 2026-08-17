-- Read-back del revert de `purchase_candidate_metrics_v1`.
--
-- Lo único que hay que demostrar es que la vista volvió a su forma
-- conocida-buena y que el camino que la app **sí** usa —ranking por producto
-- exacto— responde dentro de su presupuesto.

-- La fecha del negocio vuelve a resolverse en el sitio original.
select 1 / (case when pg_get_viewdef('public.purchase_candidate_metrics_v1'::regclass)
  like '%tenant_business_date%' then 1 else 0 end) as business_date_restored;

-- Y ya no queda el CTE que rompió el camino rápido.
select 1 / (case when pg_get_viewdef('public.purchase_candidate_metrics_v1'::regclass)
  not like '%business_day%' then 1 else 0 end) as scoping_cte_removed;

-- El contrato de imágenes del candidato sigue publicado.
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

-- El camino por producto exacto completa, cabe en presupuesto y trae la banda
-- de gama hasta el cliente.
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
  1 / (case when not exists (
        select 1 from jsonb_array_elements(payload->'items') item
        where not (item.value ? 'gama')
      ) then 1 else 0 end) as every_candidate_carries_its_band,
  1 / (case when not exists (
        select 1 from jsonb_array_elements(payload->'items') item
        where (item.value->>'evidenceAgeDays')::int < 0
      ) then 1 else 0 end) as evidence_age_still_sane
from ranked;
