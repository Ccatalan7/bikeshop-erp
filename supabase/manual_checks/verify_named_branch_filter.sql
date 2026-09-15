-- Read-back: la rama nombrada vuelve como filtro y acota el resultado.
with t as materialized (
  select '5443b130-cc28-45af-a420-cd500b288890'::uuid tid
), inf as materialized (
  select public.assistant_infer_technical_predicates_internal_v1(
    t.tid, 'discos de freno de 160'
  ) r from t
), preds as materialized (
  select p.value ->> 'field' f, p.value ->> 'operator' o, p.value -> 'values' v
  from inf, jsonb_array_elements(inf.r -> 'predicates') p(value)
), cats as materialized (
  select (c.value #>> '{}')::uuid id
  from inf, jsonb_array_elements(inf.r -> 'categories') c(value)
), surf as materialized (
  select pr.id, pr.category_id,
    public.assistant_normalize_query_internal_v1(concat_ws(' ', pr.name,
      pr.brand, pr.model, pr.manufacturer, pr.category_name, pr.category)) isurf,
    unaccent(lower(concat_ws(' ', pr.name, pr.brand, pr.model, pr.manufacturer,
      pr.category_name, pr.category))) iraw
  from public.products_with_sets pr, t
  where pr.tenant_id = t.tid and pr.is_active is true
), hit as materialized (
  select s.id from surf s, t
  where s.category_id in (select id from cats)
    and (select bool_and(
      public.assistant_inventory_technical_predicate_source_internal_v1(
        t.tid, s.id, p.f, p.o, p.v, s.isurf, s.iraw
      ) in ('product_spec', 'identity_fallback')) from preds p)
)
select
  1 / (case when (select count(*) from cats) > 0 then 1 else 0 end) as rama_devuelta,
  -- Antes calzaban 23 con el predicado solo; acotado por rama tiene que bajar.
  1 / (case when (select count(*) from hit) < 23 then 1 else 0 end) as se_acoto,
  -- Y sigue trayendo los rotores fichados, no cero.
  1 / (case when (select count(*) from hit) >= 7 then 1 else 0 end) as no_perdio_los_reales,
  1 / (case when exists (
    select 1 from pg_proc where proname = 'assistant_search_inventory_v7'
      and prosrc like '%v_inferred_categories%'
  ) then 1 else 0 end) as buscador_cableado;
