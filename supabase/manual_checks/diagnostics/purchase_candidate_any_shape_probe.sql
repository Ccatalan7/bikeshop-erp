-- Costo real de la forma de acceso del kernel de scoring, medible y repetible.
--
-- **Qué decide.** La Fase B2 entrega al kernel un arreglo de identidades de
-- candidato, y `rank_purchase_candidates_v1` pasa a resolver su universo y
-- delegar. Eso son **dos** lecturas de `purchase_candidate_metrics_v1` donde
-- antes había una. Este probe mide las tres piezas —baseline de una sola
-- pasada, resolución de ids, y kernel filtrado— para que la decisión se tome
-- con números y no con una corazonada. La lección de agosto: una hipótesis de
-- rendimiento que sólo se valida en producción se mide, no se supone.
--
-- **Cómo se corre.** Lectura, sin escrituras ni despliegue:
--
--   bash scripts/db/query.sh production \
--     --file supabase/manual_checks/diagnostics/purchase_candidate_any_shape_probe.sql
--
-- Se autoconfigura: descubre el tenant con más candidatos y su categoría más
-- poblada, y materializa los identificadores con `\gset` **entre sentencias**.
-- Eso último no es un detalle de estilo, es el punto entero — ver abajo.
--
-- **La forma prohibida: same-statement.** Derivar los ids desde la misma vista
-- dentro de la misma sentencia hace que el planificador evalúe la vista una vez
-- por fila. Medido en producción: **6.494 ms**, con `loops=71824` (268 × 268)
-- contra los 36 ms de un barrido simple. El kernel jamás puede recibir su
-- universo así; llega materializado desde una sentencia previa.
--
--   -- PROHIBIDO, conservado como evidencia:
--   -- with universe as (select array_agg(candidate_id) ids
--   --                   from purchase_candidate_metrics_v1)
--   -- select count(*) from purchase_candidate_metrics_v1 metric, universe
--   -- where metric.candidate_id = any(universe.ids);
--
-- **Resultado medido en producción (2026-08-17, tenant con 268 candidatos):**
--
--   A · barrido completo de la vista, sin filtro .............. 35,0 ms
--   B · = any(1 id) ........................................... 13,8 ms
--   C · = any(10 ids) ......................................... 14,6 ms
--   D · = any(50 ids) ......................................... 17,2 ms
--   E · = any(universo completo, 268) ......................... 35,7 ms
--   F · BASELINE de una pasada (categoría + gama + ventanas) ... 97,7 ms
--   G · WRAPPER 1/2, resolver identidades ..................... 36,6 ms
--   H · WRAPPER 2/2, kernel sobre esas identidades ............ 19,9 ms
--
-- **El wrapper de dos pasadas es más barato que la única pasada anterior:
-- 56,5 ms contra 97,7 ms**, un 42 % menos, y usa el 1,3 % del
-- `statement_timeout` de 4,5 s. La intuición decía lo contrario —dos lecturas
-- de una vista cara tienen que costar más— y estaba equivocada: filtrar por
-- `candidate_id` es selectivo, mientras que filtrar por subárbol de categoría
-- obliga a materializar la vista entera. Por eso se mide.
--
-- **Lo que este probe NO mide.** El kernel no está desplegado en producción:
-- lo medido es la consulta equivalente en línea sobre los mismos datos. Cuando
-- el kernel llegue allá, hay que repetirlo sobre la función real.

\pset pager off
\timing off

-- ── contexto: el tenant y la categoría más poblados ────────────────────────
select tenant_id as probe_tenant,
  category_id as probe_category
from public.purchase_candidate_metrics_v1
group by tenant_id, category_id
order by count(*) desc
limit 1
\gset

\echo '── contexto ──────────────────────────────────────────────────────────'
select :'probe_tenant'::uuid as tenant,
  :'probe_category'::uuid as category,
  (select count(*) from public.purchase_candidate_metrics_v1
   where tenant_id = :'probe_tenant'::uuid) as candidates_in_tenant,
  (select count(*) from public.purchase_candidate_metrics_v1
   where tenant_id = :'probe_tenant'::uuid
     and category_id = :'probe_category'::uuid) as candidates_in_category;

-- ── identidades materializadas ENTRE sentencias ────────────────────────────
select
  (select coalesce(string_agg(quote_literal(candidate_id::text), ','), '''''')
   from (select candidate_id from public.purchase_candidate_metrics_v1
         where tenant_id = :'probe_tenant'::uuid
         order by candidate_id limit 1) s) as ids_1,
  (select coalesce(string_agg(quote_literal(candidate_id::text), ','), '''''')
   from (select candidate_id from public.purchase_candidate_metrics_v1
         where tenant_id = :'probe_tenant'::uuid
         order by candidate_id limit 10) s) as ids_10,
  (select coalesce(string_agg(quote_literal(candidate_id::text), ','), '''''')
   from (select candidate_id from public.purchase_candidate_metrics_v1
         where tenant_id = :'probe_tenant'::uuid
         order by candidate_id limit 50) s) as ids_50,
  (select coalesce(string_agg(quote_literal(candidate_id::text), ','), '''''')
   from (select candidate_id from public.purchase_candidate_metrics_v1
         where tenant_id = :'probe_tenant'::uuid) s) as ids_all,
  (select coalesce(string_agg(quote_literal(candidate_id::text), ','), '''''')
   from (select candidate_id from public.purchase_candidate_metrics_v1
         where tenant_id = :'probe_tenant'::uuid
           and category_id = :'probe_category'::uuid) s) as ids_category
\gset

\echo ''
\echo '── A · barrido completo de la vista, sin filtro ───────────────────────'
explain (analyze, buffers, timing)
select count(*) from public.purchase_candidate_metrics_v1
where tenant_id = :'probe_tenant'::uuid;

\echo ''
\echo '── B · = any(1 id) ───────────────────────────────────────────────────'
explain (analyze, buffers, timing)
select count(*) from public.purchase_candidate_metrics_v1 metric
where metric.tenant_id = :'probe_tenant'::uuid
  and metric.candidate_id = any(array[:ids_1]::uuid[]);

\echo ''
\echo '── C · = any(10 ids) ─────────────────────────────────────────────────'
explain (analyze, buffers, timing)
select count(*) from public.purchase_candidate_metrics_v1 metric
where metric.tenant_id = :'probe_tenant'::uuid
  and metric.candidate_id = any(array[:ids_10]::uuid[]);

\echo ''
\echo '── D · = any(50 ids) ─────────────────────────────────────────────────'
explain (analyze, buffers, timing)
select count(*) from public.purchase_candidate_metrics_v1 metric
where metric.tenant_id = :'probe_tenant'::uuid
  and metric.candidate_id = any(array[:ids_50]::uuid[]);

\echo ''
\echo '── E · = any(universo completo) ──────────────────────────────────────'
explain (analyze, buffers, timing)
select count(*) from public.purchase_candidate_metrics_v1 metric
where metric.tenant_id = :'probe_tenant'::uuid
  and metric.candidate_id = any(array[:ids_all]::uuid[]);

-- ── El costo del wrapper: sus DOS sentencias contra el baseline de UNA ─────
--
-- Baseline = lo que `rank_purchase_candidates_v1` hacía antes de delegar: una
-- sola pasada por la vista, con el join de gama y las ventanas, filtrada por
-- el subárbol de categoría.
--
-- Wrapper  = sentencia 1 (resolver ids por categoría) + sentencia 2 (kernel
-- sobre esos ids, con el mismo join y las mismas ventanas).

\echo ''
\echo '── F · BASELINE · una pasada: categoría + gama + ventanas ─────────────'
explain (analyze, buffers, timing)
with recursive category_scope as (
  select category.id
  from public.product_categories category
  where category.tenant_id = :'probe_tenant'::uuid
    and category.id = :'probe_category'::uuid
  union all
  select child.id
  from public.product_categories child
  join category_scope parent on child.parent_id = parent.id
  where child.tenant_id = :'probe_tenant'::uuid and child.is_active is true
), gama_scope as materialized (
  select band.category_id, lower(btrim(band.brand)) as brand_key, band.band
  from public.product_gama_v1 band
  where band.tenant_id = :'probe_tenant'::uuid
), filtered as materialized (
  select metric.*, gama.band as gama_band
  from public.purchase_candidate_metrics_v1 metric
  left join gama_scope gama
    on gama.category_id = metric.category_id
   and gama.brand_key = lower(btrim(metric.brand))
  where metric.tenant_id = :'probe_tenant'::uuid
    and metric.category_id in (select id from category_scope)
), bounded as (
  select filtered.*,
    max(purchase_count) over()::numeric as max_purchase_count,
    max(purchased_units) over()::numeric as max_purchased_units
  from filtered
)
select count(*) from bounded;

\echo ''
\echo '── G · WRAPPER 1/2 · resolver identidades por categoría ───────────────'
explain (analyze, buffers, timing)
with recursive category_scope as (
  select category.id
  from public.product_categories category
  where category.tenant_id = :'probe_tenant'::uuid
    and category.id = :'probe_category'::uuid
  union all
  select child.id
  from public.product_categories child
  join category_scope parent on child.parent_id = parent.id
  where child.tenant_id = :'probe_tenant'::uuid and child.is_active is true
)
select array_agg(metric.candidate_id)
from public.purchase_candidate_metrics_v1 metric
where metric.tenant_id = :'probe_tenant'::uuid
  and metric.category_id in (select id from category_scope);

\echo ''
\echo '── H · WRAPPER 2/2 · kernel sobre esas identidades ────────────────────'
explain (analyze, buffers, timing)
with gama_scope as materialized (
  select band.category_id, lower(btrim(band.brand)) as brand_key, band.band
  from public.product_gama_v1 band
  where band.tenant_id = :'probe_tenant'::uuid
), filtered as materialized (
  select metric.*, gama.band as gama_band
  from public.purchase_candidate_metrics_v1 metric
  left join gama_scope gama
    on gama.category_id = metric.category_id
   and gama.brand_key = lower(btrim(metric.brand))
  where metric.tenant_id = :'probe_tenant'::uuid
    and metric.candidate_id = any(array[:ids_category]::uuid[])
), bounded as (
  select filtered.*,
    max(purchase_count) over()::numeric as max_purchase_count,
    max(purchased_units) over()::numeric as max_purchased_units
  from filtered
)
select count(*) from bounded;
