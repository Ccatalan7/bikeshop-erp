-- Read-back de la gama materializada.
--
-- Lo que importa no es que exista: es que el ranking **vuelva a caber** en su
-- presupuesto. Una función correcta que se pasa del `statement_timeout` no
-- sirve, y eso sólo se ve ejecutando.

select 1 / (case when to_regclass('public.product_gama_bands_mv') is null
  then 0 else 1 end) as snapshot_present;

-- `refresh concurrently` exige el índice único; sin él el refresco bloquea.
select 1 / (case when exists (
  select 1 from pg_indexes
   where schemaname = 'public'
     and tablename = 'product_gama_bands_mv'
     and indexdef like '%UNIQUE%'
) then 1 else 0 end) as unique_index_for_concurrent_refresh;

select 1 / (case when exists (
  select 1 from pg_proc where proname = 'refresh_product_gama_bands_v1'
) then 1 else 0 end) as refresh_function_present;

-- La vista vigente ya no deriva en vivo.
select 1 / (case when pg_get_viewdef('public.product_gama_v1'::regclass)
  like '%product_gama_bands_mv%' then 1 else 0 end) as resolved_view_reads_snapshot;

-- Contexto de tenant para las comprobaciones que ejecutan.
select set_config(
  'request.jwt.claim.sub',
  (select p.user_id::text
     from public.user_profiles p
     join public.tenants t on t.id = p.tenant_id and t.is_active is true
    where p.is_active is true
      and exists (
        select 1 from public.purchase_candidate_metrics_v1 m
        where m.tenant_id = p.tenant_id
      )
    group by p.user_id
   having count(*) = 1
    limit 1),
  true
) as tenant_context_ready;

-- El ranking corre y cabe: si volviera a excederse, esto falla acá y no en
-- manos del operador.
-- El ranking exige al menos un criterio: se le da un producto real del tenant.
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
        then 1 else 0 end) as ranking_completes_within_budget,
  1 / (case when jsonb_typeof(payload->'items') = 'array'
        then 1 else 0 end) as ranking_returns_a_list
from ranked;

-- Y sigue llevando la banda hasta el cliente.
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
    where not (item.value ? 'gama')
  ) then 1 else 0 end) as every_candidate_carries_its_band
from ranked;
