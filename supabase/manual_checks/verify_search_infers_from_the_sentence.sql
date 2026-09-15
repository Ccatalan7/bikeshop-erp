-- Read-back: el buscador deduce los predicados de la frase y filtra con ellos.
with t as materialized (
  select tenant_id tid from public.product_categories
  where public.assistant_normalize_query_internal_v1(full_path)
    = 'componentes transmision motores' limit 1
), inf as materialized (
  select t.tid, public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'dame los motores de caja BSA con ancho de caja 68 y largo de eje 118'
  ) r from t
), preds as materialized (
  select p.value ->> 'field' f, p.value ->> 'operator' o, p.value -> 'values' v
  from inf, jsonb_array_elements(inf.r -> 'predicates') p(value)
), surf as materialized (
  select pr.id, pr.name, pr.category_id,
    public.assistant_normalize_query_internal_v1(concat_ws(' ', pr.name,
      pr.brand, pr.model, pr.manufacturer, pr.category_name, pr.category)) isurf,
    unaccent(lower(concat_ws(' ', pr.name, pr.brand, pr.model, pr.manufacturer,
      pr.category_name, pr.category))) iraw
  from public.products_with_sets pr, t
  where pr.tenant_id = t.tid and pr.is_active is true
), hit as materialized (
  select s.id, s.name, s.category_id
  from surf s, t
  where (
    select bool_and(
      public.assistant_inventory_technical_predicate_source_internal_v1(
        t.tid, s.id, p.f, p.o, p.v, s.isurf, s.iraw
      ) in ('product_spec', 'identity_fallback')
    ) from preds p
  )
)
select
  -- El buscador llama a la inferencia.
  1 / (case when exists (
    select 1 from pg_proc where proname = 'assistant_search_inventory_v7'
      and prosrc like '%assistant_infer_technical_predicates_internal_v1%'
  ) then 1 else 0 end) as buscador_cableado,
  -- Encuentra los motores que el operador pidió, no cero.
  1 / (case when (select count(*) from hit) >= 3 then 1 else 0 end) as hay_resultados,
  -- Incluye el que tiene stock real.
  1 / (case when exists (
    select 1 from hit where name like 'EJE SELLADO VP-BC73%'
  ) then 1 else 0 end) as incluye_el_con_stock,
  -- No se ensancha fuera de la rama de motores.
  1 / (case when not exists (
    select 1 from hit h join public.product_categories c on c.id = h.category_id
    where public.assistant_normalize_query_internal_v1(c.full_path)
      not like 'componentes transmision motores%'
  ) then 1 else 0 end) as sin_fuga_de_rama;

-- Segunda ronda: la traducción corre siempre y no borra una identidad.
with t as (
  select tenant_id tid from public.product_categories
  where public.assistant_normalize_query_internal_v1(full_path)
    = 'componentes transmision motores' limit 1
), identidad as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'VP-BC73'
  ) r from t
), mixta as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'motor caja BSA VP-BC73'
  ) r from t
)
select
  -- Una identidad sola no genera filtros: el buscador conserva su texto.
  1 / (case when jsonb_array_length((select r -> 'predicates' from identidad))
    = 0 then 1 else 0 end) as identidad_intacta,
  -- En una frase mixta se traduce la ficha y se conserva el código.
  1 / (case when (select r ->> 'residual' from mixta) like '%bc73%'
    then 1 else 0 end) as codigo_conservado,
  -- Y el buscador ya no condiciona la traducción a que el modelo se abstenga.
  1 / (case when exists (
    select 1 from pg_proc where proname = 'assistant_search_inventory_v7'
      and prosrc like '%v_inferred_predicates%'
  ) then 1 else 0 end) as traduce_siempre;

-- Tercera ronda: ninguna palabra de tres letras sobrevive como texto libre.
with t as (
  select tenant_id tid from public.product_categories
  where public.assistant_normalize_query_internal_v1(full_path)
    = 'componentes transmision motores' limit 1
), tal_cual as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'motores de caja BSA con ancho de caja 68 y largo de eje 118'
  ) r from t
), mixta as (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'motor caja BSA VP-BC73'
  ) r from t
)
select
  1 / (case when (select r ->> 'residual' from tal_cual) = ''
    then 1 else 0 end) as sin_residuo_vacio,
  1 / (case when (select r ->> 'residual' from mixta) like '%bc73%'
    then 1 else 0 end) as codigo_sigue_vivo;
