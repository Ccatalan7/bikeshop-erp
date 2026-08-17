-- La banda de gama se materializa: derivarla en vivo cuesta más que rankear.
--
-- Medición sobre producción: `purchase_candidate_metrics_v1` tarda ~0,7 s de
-- base y `product_gama_v1` agrega ~1,3 s más, porque deriva las bandas con
-- funciones de ventana sobre esas mismas métricas. El ranking ya escanea las
-- métricas una vez; sumarle la gama en vivo lo empujó sobre el
-- `statement_timeout` de 4,5 s y lo dejó inutilizable para el taller real.
--
-- No se puede derivar la banda dentro del propio escaneo del ranking: la
-- posición es relativa a **toda** la categoría, no al subconjunto que la
-- consulta filtró. Calcularla sobre lo filtrado daría una banda distinta para
-- la misma marca según lo que se buscó.
--
-- Por eso se materializa. Las bandas cambian con cada factura de compra, no con
-- cada consulta: una vista materializada es la forma correcta, y el momento del
-- refresco queda explícito y auditable.

begin;

create materialized view if not exists public.product_gama_bands_mv as
select
  tenant_id,
  category_id,
  category_path,
  brand,
  lower(btrim(brand)) as brand_key,
  average_landed_unit_cost_net,
  purchase_count,
  candidate_count,
  brands_in_category,
  price_position,
  derived_band,
  band_is_confident,
  now() as refreshed_at
from public.product_gama_bands_v1;

comment on materialized view public.product_gama_bands_mv is
  'Instantánea de la banda derivada por marca y categoría. Se refresca con refresh_product_gama_bands_v1(); derivarla en vivo excede el presupuesto del ranking.';

create unique index if not exists product_gama_bands_mv_key
  on public.product_gama_bands_mv (tenant_id, category_id, brand_key);

-- La banda vigente pasa a leer la instantánea. La corrección del operador sigue
-- resolviéndose en vivo: es una decisión suya y debe verse al instante.
create or replace view public.product_gama_v1
with (security_invoker = true)
as
select
  bands.tenant_id,
  bands.category_id,
  bands.category_path,
  bands.brand,
  bands.average_landed_unit_cost_net,
  bands.purchase_count,
  bands.brands_in_category,
  bands.price_position,
  coalesce(override.band, bands.derived_band) as band,
  (override.band is not null) as band_is_manual,
  case when override.band is not null then true else bands.band_is_confident end
    as band_is_confident,
  override.note as band_note,
  bands.refreshed_at
from public.product_gama_bands_mv bands
left join public.product_gama_overrides override
  on override.tenant_id = bands.tenant_id
 and override.category_id = bands.category_id
 and lower(btrim(override.brand)) = bands.brand_key

union all

select
  override.tenant_id,
  override.category_id,
  category.full_path,
  override.brand,
  null::numeric,
  0,
  0,
  null::numeric,
  override.band,
  true,
  true,
  override.note,
  null::timestamptz
from public.product_gama_overrides override
join public.product_categories category
  on category.tenant_id = override.tenant_id
 and category.id = override.category_id
where not exists (
  select 1
  from public.product_gama_bands_mv bands
  where bands.tenant_id = override.tenant_id
    and bands.category_id = override.category_id
    and bands.brand_key = lower(btrim(override.brand))
);

-- Refresco explícito. `concurrently` necesita el índice único de arriba y deja
-- la vista legible mientras se recalcula.
create or replace function public.refresh_product_gama_bands_v1()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  refresh materialized view concurrently public.product_gama_bands_mv;
end;
$$;

revoke all on function public.refresh_product_gama_bands_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.refresh_product_gama_bands_v1() to authenticated;

comment on function public.refresh_product_gama_bands_v1() is
  'Recalcula la instantánea de bandas de gama. Pensada para correr tras cargar facturas de compra, no en cada consulta.';

grant select on public.product_gama_bands_mv to authenticated;

commit;
