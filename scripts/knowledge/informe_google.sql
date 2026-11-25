-- Partes del informe «Viñabike en Google» que salen de la base (web_presence_*
-- y los pedidos web). Lo demás del archivo —consolas, embudo y negocio— se lee
-- a mano en Search Console, GA4 y la ficha de Google (fuentes/consolas-google.md).
--
--   scripts/db/query.sh production --format json --file scripts/knowledge/informe_google.sql
--
-- «antes» son las 4 semanas previas a los arreglos del 2026-09-23; «ahora», los
-- 28 días que terminan en el último día que Search Console ya entregó. Puesto =
-- promedio ponderado por apariciones. Temas y tipos de página, en el orden de los
-- case. Semanas y visitas: sólo semanas completas (de lunes a domingo).
with t as (select id from public.tenants where subdomain = 'vinabike'),
ultimo as (
  select max(d.day) as dia from public.web_presence_search_daily d, t where d.tenant_id = t.id),
w(periodo, desde, hasta) as (
  select 'antes', date '2026-08-26', date '2026-09-22'
  union all
  select 'ahora', u.dia - 27, u.dia from ultimo u),
daily as (
  select d.day, d.clicks, d.impressions, d.position
    from public.web_presence_search_daily d, t where d.tenant_id = t.id),
traf as (
  select x.day, x.channel, x.sessions, x.engaged_sessions from public.web_presence_traffic_daily x, t
   where x.tenant_id = t.id and x.scope = 'chile'),
ventanas as (
  select w.periodo, w.desde::text as desde, w.hasta::text as hasta,
         sum(d.clicks) as clics, sum(d.impressions) as vistas,
         round(sum(d.position * d.impressions) / nullif(sum(d.impressions), 0), 1) as posicion,
         round(sum(d.clicks)::numeric / ((w.hasta - w.desde) + 1), 1) as clics_dia,
         round(sum(d.impressions)::numeric / ((w.hasta - w.desde) + 1)) as vistas_dia,
         round(100.0 * sum(d.clicks) / nullif(sum(d.impressions), 0), 1) as pct_clic,
         (select coalesce(sum(x.sessions), 0) from traf x where x.day between w.desde and w.hasta) as visitas_chile,
         (select coalesce(sum(x.sessions), 0) from traf x where x.day between w.desde and w.hasta and x.channel = 'Organic Search') as visitas_google,
         (select coalesce(sum(x.sessions), 0) from traf x where x.day between w.desde and w.hasta and x.channel = 'AI Assistant') as visitas_ia,
         (select round(100.0 * sum(x.engaged_sessions) / nullif(sum(x.sessions), 0)) from traf x where x.day between w.desde and w.hasta) as pct_interes
    from w join daily d on d.day between w.desde and w.hasta
   group by w.periodo, w.desde, w.hasta),
meses as (
  select to_char(date_trunc('month', d.day), 'YYYY-MM') as mes, count(*) as dias,
         sum(d.clicks) as clics, sum(d.impressions) as vistas,
         (max(d.day) = (date_trunc('month', min(d.day)) + interval '1 month - 1 day')::date
          and count(*) = extract(day from (date_trunc('month', min(d.day)) + interval '1 month - 1 day'))) as completo,
         round(100.0 * sum(d.clicks) / nullif(sum(d.impressions), 0), 1) as pct_clic,
         round(sum(d.position * d.impressions) / nullif(sum(d.impressions), 0), 1) as posicion,
         round(sum(d.clicks)::numeric / count(*), 2) as clics_dia,
         round(sum(d.impressions)::numeric / count(*)) as vistas_dia
    from daily d where d.day >= date '2025-08-01'
   group by date_trunc('month', d.day)),
semanas as (
  select date_trunc('week', d.day)::date::text as semana, sum(d.clicks) as clics, sum(d.impressions) as vistas,
         round(sum(d.position * d.impressions) / nullif(sum(d.impressions), 0), 1) as posicion,
         round(sum(d.impressions)::numeric / 7) as vistas_dia
    from daily d where d.day >= date '2026-05-04'
   group by date_trunc('week', d.day) having count(*) = 7),
indexacion as (
  select x.day::text as dia,
         round(100.0 * x.indexed / nullif(x.sitemap_urls, 0)) as pct,
         coalesce((x.by_state->>'Excluded by ‘noindex’ tag')::int, 0) as noindex,
         x.sitemap_urls as sitemap, x.indexed as indexadas,
         coalesce((x.by_state->>'URL is unknown to Google')::int, 0) as desconocidas,
         coalesce((x.by_state->>'Discovered - currently not indexed')::int, 0) as descubiertas,
         coalesce((x.by_state->>'Crawled - currently not indexed')::int, 0) as rastreadas_sin_indexar
    from public.web_presence_index_daily x, t where x.tenant_id = t.id),
visitas as (
  select date_trunc('week', x.day)::date::text as semana,
         coalesce(sum(x.sessions) filter (where x.channel = 'AI Assistant'), 0) as ia,
         coalesce(sum(x.sessions) filter (where x.channel not in ('AI Assistant', 'Direct', 'Organic Search', 'Organic Social')), 0) as otros,
         coalesce(sum(x.sessions) filter (where x.channel = 'Organic Social'), 0) as redes,
         sum(x.sessions) as total,
         coalesce(sum(x.sessions) filter (where x.channel = 'Organic Search'), 0) as google,
         coalesce(sum(x.sessions) filter (where x.channel = 'Direct'), 0) as directo,
         round(100.0 * sum(x.engaged_sessions) / nullif(sum(x.sessions), 0)) as pct_interes
    from traf x
   where x.day >= date '2026-07-27' and date_trunc('week', x.day)::date + 6 <= (select dia from ultimo)
   group by date_trunc('week', x.day)),
q as (
  select w.periodo, lower(x.term) as term, x.clicks, x.impressions, x.position
    from w, t, public.web_presence_search_terms x
   where x.tenant_id = t.id and x.kind = 'query' and x.day between w.desde and w.hasta),
fam as (
  select periodo,
         case
           when term ~ 'vi[ñn]a ?bike' then 'marca'
           when term ~ '(taller|arregl|repar|manten|mec[aá]nic|servicio)' then 'taller'
           when term ~ '(tienda|bicicleter|vi[ñn]a)' then 'tienda'
           else 'productos'
         end as familia, clicks, impressions, position
    from q),
famagg as (
  select familia,
         sum(impressions) filter (where periodo = 'ahora') as vistas,
         sum(clicks) filter (where periodo = 'ahora') as clics,
         round(sum(position * impressions) filter (where periodo = 'ahora') / nullif(sum(impressions) filter (where periodo = 'ahora'), 0), 1) as posicion,
         sum(impressions) filter (where periodo = 'antes') as vistas_antes,
         sum(clicks) filter (where periodo = 'antes') as clics_antes,
         round(sum(position * impressions) filter (where periodo = 'antes') / nullif(sum(impressions) filter (where periodo = 'antes'), 0), 1) as posicion_antes
    from fam group by familia),
busq as (
  select term as busqueda,
         coalesce(sum(impressions) filter (where periodo = 'ahora'), 0) as vistas,
         coalesce(sum(clicks) filter (where periodo = 'ahora'), 0) as clics,
         round(sum(position * impressions) filter (where periodo = 'ahora') / nullif(sum(impressions) filter (where periodo = 'ahora'), 0), 1) as posicion,
         coalesce(sum(impressions) filter (where periodo = 'antes'), 0) as vistas_antes,
         coalesce(sum(clicks) filter (where periodo = 'antes'), 0) as clics_antes,
         round(sum(position * impressions) filter (where periodo = 'antes') / nullif(sum(impressions) filter (where periodo = 'antes'), 0), 1) as posicion_antes
    from q group by term order by 2 desc, 3 desc, 1 limit 16),
pg as (
  select w.periodo, regexp_replace(split_part(x.term, '?', 1), '^https?://[^/]+', '') as path,
         x.clicks, x.impressions, x.position
    from w, t, public.web_presence_search_terms x
   where x.tenant_id = t.id and x.kind = 'page' and x.day between w.desde and w.hasta),
pgt as (
  select periodo,
         case
           when path in ('', '/') then 'portada'
           when path ~ '^/productos/categoria(/|$)' then 'categorias'
           when path ~ '^/productos/.+' then 'fichas'
           when path ~ '^/(servicios|guias)(/|$)' then 'servicios_guias'
           else 'otras'
         end as tipo, clicks, impressions, position
    from pg),
paginas as (
  select tipo,
         coalesce(sum(clicks) filter (where periodo = 'ahora'), 0) as clics,
         coalesce(sum(impressions) filter (where periodo = 'ahora'), 0) as vistas,
         round(100.0 * sum(clicks) filter (where periodo = 'ahora') / nullif(sum(impressions) filter (where periodo = 'ahora'), 0), 1) as pct_clic,
         round(sum(position * impressions) filter (where periodo = 'ahora') / nullif(sum(impressions) filter (where periodo = 'ahora'), 0), 1) as posicion,
         coalesce(sum(clicks) filter (where periodo = 'antes'), 0) as clics_antes,
         coalesce(sum(impressions) filter (where periodo = 'antes'), 0) as vistas_antes,
         round(sum(position * impressions) filter (where periodo = 'antes') / nullif(sum(impressions) filter (where periodo = 'antes'), 0), 1) as posicion_antes
    from pgt group by tipo),
cobertura as (
  select v.periodo, v.vistas as vistas_total,
         (select coalesce(sum(impressions), 0) from q where q.periodo = v.periodo) as vistas_con_busqueda
    from ventanas v),
pedidos as (
  select i.product_sku as sku, o.created_at::date::text as fecha, o.total::numeric as monto,
         o.order_number as pedido, i.product_name as producto
    from public.online_orders o
    join t on o.tenant_id = t.id
    join public.online_order_items i on i.order_id = o.id and i.tenant_id = o.tenant_id
   where coalesce(o.is_test, false) = false and o.status <> 'cancelled' and o.payment_status = 'paid'
   order by o.created_at)
select json_build_object(
  'ventanas', (select json_agg(row_to_json(v) order by v.desde) from ventanas v),
  'meses', (select json_agg(row_to_json(m) order by m.mes) from meses m),
  'semanas', (select json_agg(row_to_json(s) order by s.semana) from semanas s),
  'indexacion', (select json_agg(row_to_json(i) order by i.dia) from indexacion i),
  'visitas', (select json_agg(row_to_json(v) order by v.semana) from visitas v),
  -- Las tablas «Qué búsquedas crecieron» y «Qué páginas traen los clics» muestran
  -- `nombre` en su primera columna y siguen este orden; sin él salen con «—».
  'familias', (select json_agg(to_jsonb(f) || jsonb_build_object('nombre', case f.familia
                 when 'taller' then 'Taller, arreglos y mantención'
                 when 'tienda' then 'Tienda de bicicletas en Viña'
                 when 'productos' then 'Productos y repuestos'
                 else 'El nombre Viñabike' end)
               order by array_position(array['taller', 'tienda', 'productos', 'marca'], f.familia)) from famagg f),
  'busquedas', (select json_agg(row_to_json(b) order by b.vistas desc, b.clics desc, b.busqueda) from busq b),
  'paginas', (select json_agg(to_jsonb(p) || jsonb_build_object('nombre', case p.tipo
                 when 'portada' then 'Portada'
                 when 'fichas' then 'Fichas de productos'
                 when 'categorias' then 'Categorías'
                 when 'servicios_guias' then 'Servicios y guías'
                 else 'Contacto, envíos y otras' end)
               order by array_position(array['portada', 'fichas', 'categorias', 'servicios_guias', 'otras'], p.tipo)) from paginas p),
  'cobertura', (select json_agg(row_to_json(c) order by c.periodo desc) from cobertura c),
  'pedidos', (select json_agg(row_to_json(p)) from pedidos p)
)::text as doc;
