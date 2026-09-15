-- Gama como dato, no como una frase que ojalá el modelo interprete.
--
-- El dueño pidió priorizar compras «por gama, ya sea marca o rango de precio».
-- El kernel de ranking devolvía la marca pero no la puntuaba: ninguna de sus
-- seis dimensiones era marca ni rango de precio, así que «muéstrame la gama
-- económica» no era una operación del motor.
--
-- La banda se deriva de lo que el taller YA compró: dentro de cada categoría,
-- las marcas se ordenan por su costo aterrizado promedio y se reparten en tres
-- bandas por posición relativa. Así funciona desde el primer día sin que nadie
-- llene una tabla, y una corrección explícita del dueño la pisa para siempre.
--
-- Medición al escribir esto, sobre producción: 208 de 268 candidatos traen
-- marca, 52 marcas distintas, y las categorías con más movimiento tienen entre
-- 3 y 8 marcas cada una — suficiente para separar bandas con sentido.

-- ── Corrección explícita del operador ───────────────────────────────────────
create table if not exists public.product_gama_overrides (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants (id) on delete cascade,
  category_id uuid not null references public.product_categories (id) on delete cascade,
  brand text not null,
  band text not null check (band in ('economica', 'media', 'alta')),
  note text,
  set_by uuid references auth.users (id),
  set_at timestamptz not null default now(),
  constraint product_gama_overrides_brand_not_blank check (btrim(brand) <> ''),
  constraint product_gama_overrides_unique unique (tenant_id, category_id, brand)
);

comment on table public.product_gama_overrides is
  'Corrección explícita de la banda de gama de una marca dentro de una categoría. Pisa la banda derivada del historial.';

alter table public.product_gama_overrides enable row level security;

drop policy if exists product_gama_overrides_tenant_read on public.product_gama_overrides;
create policy product_gama_overrides_tenant_read
  on public.product_gama_overrides for select
  using (tenant_id = public.user_tenant_id());

drop policy if exists product_gama_overrides_tenant_write on public.product_gama_overrides;
create policy product_gama_overrides_tenant_write
  on public.product_gama_overrides for all
  using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());

create index if not exists product_gama_overrides_tenant_category_idx
  on public.product_gama_overrides (tenant_id, category_id);

-- ── Banda derivada del historial ───────────────────────────────────────────
--
-- La posición es relativa dentro de la categoría, no un umbral de precio en
-- pesos: una categoría cara y una barata no comparten escala. Con una sola
-- marca no hay nada que distinguir y la banda queda 'media' declarándolo.
create or replace view public.product_gama_bands_v1
with (security_invoker = true)
as
with per_brand as (
  select
    metric.tenant_id,
    metric.category_id,
    metric.category_path,
    metric.brand,
    avg(metric.average_landed_unit_cost_net) as average_cost,
    sum(metric.purchase_count)::integer as purchase_count,
    count(*)::integer as candidate_count
  from public.purchase_candidate_metrics_v1 metric
  where metric.brand is not null
    and btrim(metric.brand) <> ''
    and metric.category_id is not null
    and metric.average_landed_unit_cost_net > 0
  group by 1, 2, 3, 4
), bounded as (
  select
    per_brand.*,
    min(average_cost) over (partition by tenant_id, category_id) as category_min,
    max(average_cost) over (partition by tenant_id, category_id) as category_max,
    count(*) over (partition by tenant_id, category_id)::integer as brands_in_category
  from per_brand
)
select
  tenant_id,
  category_id,
  category_path,
  brand,
  round(average_cost)::numeric as average_landed_unit_cost_net,
  purchase_count,
  candidate_count,
  brands_in_category,
  case
    when brands_in_category < 2 or category_max <= category_min then null
    else round(
      ((average_cost - category_min) / (category_max - category_min))::numeric, 4
    )
  end as price_position,
  case
    when brands_in_category < 2 or category_max <= category_min then 'media'
    when (average_cost - category_min) / (category_max - category_min) < 0.34
      then 'economica'
    when (average_cost - category_min) / (category_max - category_min) < 0.67
      then 'media'
    else 'alta'
  end as derived_band,
  -- Una sola compra es un dato, no una recomendación: la interfaz baja la voz
  -- con esto en vez de esconder la marca.
  (purchase_count >= 3 and brands_in_category >= 3) as band_is_confident
from bounded;

comment on view public.product_gama_bands_v1 is
  'Banda de gama derivada del costo aterrizado promedio de cada marca dentro de su categoría. Posición relativa, nunca un umbral en pesos.';

-- ── Banda vigente: la corrección manda sobre lo derivado ───────────────────
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
  case
    when override.band is not null then true
    else bands.band_is_confident
  end as band_is_confident,
  override.note as band_note
from public.product_gama_bands_v1 bands
left join public.product_gama_overrides override
  on override.tenant_id = bands.tenant_id
 and override.category_id = bands.category_id
 and lower(btrim(override.brand)) = lower(btrim(bands.brand))

union all

-- Marcas corregidas a mano que todavía no tienen historial de compra: la
-- decisión del dueño existe aunque el kernel aún no vea evidencia.
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
  override.note
from public.product_gama_overrides override
join public.product_categories category
  on category.tenant_id = override.tenant_id
 and category.id = override.category_id
where not exists (
  select 1
  from public.product_gama_bands_v1 bands
  where bands.tenant_id = override.tenant_id
    and bands.category_id = override.category_id
    and lower(btrim(bands.brand)) = lower(btrim(override.brand))
);

comment on view public.product_gama_v1 is
  'Banda de gama vigente por marca y categoría: la corrección explícita del operador pisa la derivada del historial.';

grant select on public.product_gama_bands_v1 to authenticated;
grant select on public.product_gama_v1 to authenticated;
grant select, insert, update, delete on public.product_gama_overrides to authenticated;
