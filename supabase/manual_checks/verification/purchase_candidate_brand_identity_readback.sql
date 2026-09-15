-- Read-back de la identidad de marca en la vista de candidatos.
-- Falla a nivel SQL si la migración 20260817180000 no quedó instalada.
--
-- Lo que se exige: `brand_id` existe, ocupa la **posición 41** —la que
-- `create or replace view` le dio al agregarla al final, único sitio que ese
-- comando admite—, la vista se **ejecuta**, ninguna columna anterior se perdió
-- ni se reordenó, y el texto legible sigue publicándose para el legado que
-- sólo tiene `products.brand`.
--
-- **Corrección 2026-08-18.** La primera versión exigía que `brand_id` fuera la
-- **última** columna y que la proyección tuviera exactamente 41. Las dos cosas
-- eran ciertas el día del despliegue y dejaron de serlo cuando
-- `20260817220000` agregó `price_currency` detrás. Un read-back que sólo puede
-- pasar el día de su migración deja de ser una guarda: fijar la POSICIÓN 41
-- prueba lo mismo —que la columna se agregó al final y nadie reordenó la
-- vista— y sigue siendo verdad después. La evidencia de «última columna» vive
-- ahora en el read-back de la 22, que es quien la agregó al final.

-- ── 1. La columna nueva existe en la posición que el `create or replace` le dio
select 1 / (case when
     (select column_name from information_schema.columns
       where table_schema = 'public'
         and table_name = 'purchase_candidate_metrics_v1'
         and ordinal_position = 41) = 'brand_id'
  then 1 else 0 end) as brand_id_sits_where_it_was_appended;

-- ── 2. Ninguna columna anterior se perdió ni cambió de sitio ──────────────
-- La proyección vigente antes de esta migración terminaba en 40 columnas,
-- `image_urls` la última. Esta es la vista del incidente de los 32 s: su forma
-- no se reestructura por conveniencia, sólo se le agrega al final.
select 1 / (case when count(*) >= 41 then 1 else 0 end) as projection_only_ever_grows
from information_schema.columns
where table_schema = 'public' and table_name = 'purchase_candidate_metrics_v1';

select 1 / (case when
     (select column_name from information_schema.columns
       where table_schema = 'public'
         and table_name = 'purchase_candidate_metrics_v1'
         and ordinal_position = 40) = 'image_urls'
 and (select column_name from information_schema.columns
       where table_schema = 'public'
         and table_name = 'purchase_candidate_metrics_v1'
         and ordinal_position = 39) = 'image_url'
 and (select column_name from information_schema.columns
       where table_schema = 'public'
         and table_name = 'purchase_candidate_metrics_v1'
         and ordinal_position = 38) = 'image_url_optimized'
 and (select column_name from information_schema.columns
       where table_schema = 'public'
         and table_name = 'purchase_candidate_metrics_v1'
         and ordinal_position = 37) = 'latest_purchase_at'
 and (select column_name from information_schema.columns
       where table_schema = 'public'
         and table_name = 'purchase_candidate_metrics_v1'
         and ordinal_position = 36) = 'supplier_availability'
  then 1 else 0 end) as preceding_columns_kept_their_place;

-- El contrato de imágenes sigue publicado: era una invariante de forma previa.
select 1 / (case when count(*) = 3 then 1 else 0 end) as media_contract_survives
from information_schema.columns
where table_schema = 'public'
  and table_name = 'purchase_candidate_metrics_v1'
  and column_name in ('image_url_optimized', 'image_url', 'image_urls');

-- ── 3. La vista se EJECUTA y la identidad casa con la ficha ──────────────
-- Acotada a un tenant real: el camino guardado corre sin RLS y un barrido
-- completo tocaría todos los talleres.
with scope as (
  select need.tenant_id
  from public.supply_needs need
  order by need.created_at desc
  limit 1
), sample as (
  select candidate.product_id, candidate.brand_id, candidate.brand
  from public.purchase_candidate_metrics_v1 candidate, scope
  where candidate.tenant_id = scope.tenant_id
  limit 200
)
select
  1 / (case when (select count(*) from sample) > 0 then 1 else 0 end)
    as view_executes_with_rows,
  -- `brand_id` es identidad: cuando existe, es exactamente la de la ficha.
  1 / (case when not exists (
        select 1 from sample
        join public.products product on product.id = sample.product_id
        where sample.brand_id is distinct from product.brand_id
      ) then 1 else 0 end) as brand_id_is_the_catalog_identity,
  -- El texto legible se conserva, incluido el legado sin identidad.
  1 / (case when not exists (
        select 1 from sample
        join public.products product on product.id = sample.product_id
        where sample.brand is distinct from coalesce(
          product.brand,
          (select b.name from public.product_brands b
            where b.id = product.brand_id and b.tenant_id = product.tenant_id)
        )
      ) then 1 else 0 end) as readable_gloss_survives_for_legacy;

-- ── 4. La vista sigue siendo `security_invoker` ──────────────────────────
-- Sin esto la vista dejaría de respetar RLS y filtraría entre talleres.
select 1 / (case when exists (
  select 1 from pg_class
  where oid = 'public.purchase_candidate_metrics_v1'::regclass
    and 'security_invoker=true' = any(reloptions)
) then 1 else 0 end) as view_stays_security_invoker;

-- ── 5. La salida del ranking no cambia por una columna nueva ─────────────
-- `rank_purchase_candidates_v1` nombra cada campo con `jsonb_build_object`,
-- así que una columna nueva no puede aparecer en su respuesta.
select 1 / (case when pg_get_functiondef(
  'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)'::regprocedure
) not like '%candidate.*%' then 1 else 0 end) as ranking_never_projects_the_star;
