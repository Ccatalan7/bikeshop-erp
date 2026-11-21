-- Relacionados por lo que es cada producto y por lo que se compra junto
-- (2026-11-21).
--
-- El dueño, mirando en vivo la rodillera Leatt 3DF 5.0 con dos fundas de
-- mochila y un juego infantil debajo: «rediseñes completamente el algoritmo,
-- lógica que hay detrás de los productos relacionados… esa weá es muy
-- importante, tiene que estar muy bien hecha… ¿qué tiene que ver esa weá?».
--
-- La causa: la ficha tomaba hasta 48 productos con stock de la misma
-- categoría y los ordenaba por los valores de ficha técnica que compartían
-- (20261024010000). La rodillera se vende a pedido, igual que las otras
-- Leatt, así que ninguna entraba, y «Protectores» mezcla rodilleras, fundas
-- de mochila, autoadhesivos para el marco y protectores de neumático: lo
-- único con stock eran las fundas. El buscador, además, no conocía
-- «rodillera» y la tomaba por «protector», el mismo tipo que esas fundas.
--
-- Lo nuevo, como lo hacen las tiendas grandes:
-- 1. Vocabulario: rodillera, codera y guía de cadena son piezas; «tubo
--    asiento» es una tija. Se reconstruyen los documentos del buscador.
-- 2. Lo que el local vende junto (`catalog_part_affinity`), por tipo de pieza:
--    boletas pagadas de los últimos 24 meses, 538 con más de un producto al
--    2026-11-21 (cadena con cassette 100 veces, disco con pastillas 40,
--    manilla con shifter, funda con piola). Donde las ventas no alcanzan
--    (equipamiento, reparación de pinchazos) van pares de taller: rodillera
--    con casco y guantes, cámara con parche y desmontador, cadena con
--    lubricante. Más lo que más se vende de cada producto
--    (`catalog_product_popularity`, 12 meses). Las rehace
--    `catalog_related_signals_refresh_v1`; pg_cron cada noche.
-- 3. `get_public_related_v2`, en este orden:
--    - lo que lo reemplaza: la misma pieza, con su medida y su uso, de
--      precio parecido;
--    - lo que lo complementa: las piezas que el local vende con ella, dos de
--      cada una (tres a lo más); la misma marca va primero (Leatt: los
--      guantes GripR para una rodillera 3DF).
--    Queda fuera lo que no calza: otro aro, otra válvula, otras velocidades,
--    otro freno, 29 contra 700, una cadena de 1/8 con una de 3/32, y lo de
--    niño para un adulto o al revés. «Genérico» no cuenta como marca. Una
--    venta de taller junta todo lo de una mantención (puños con cadena): un
--    par de ventas cuenta si se repite ocho veces y tres veces más que el azar. Una
--    tarjeta por modelo, sólo lo que se puede comprar hoy (en stock o a
--    pedido) y lo que la tienda publica. Mejor menos tarjetas que una que no
--    tiene que ver.
-- 4. `get_public_product_page_v2` arma 'related' con la 3. `fits` (las
--    cámaras que calzan con un neumático) sigue igual.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '300s';

-- ---------------------------------------------------------------------------
-- 1. Vocabulario
-- ---------------------------------------------------------------------------

insert into public.catalog_search_terms (tenant_id, concept, kind, label, terms, broader, phrases)
values
  (null, 'rodillera', 'part', 'Rodilleras',
    array['rodillera', 'rodilleras', 'kneepad', 'kneepads'], array[]::text[],
    array['knee guard', 'knee guards', 'knee pad', 'knee pads', 'juego de rodilleras']),
  (null, 'codera', 'part', 'Coderas',
    array['codera', 'coderas', 'elbowpad', 'elbowpads'], array[]::text[],
    array['elbow guard', 'elbow guards', 'elbow pad', 'elbow pads']),
  (null, 'guia_cadena', 'part', 'Guía de cadena',
    array['chainguide', 'chainguides'], array[]::text[],
    array['guia de cadena', 'guia cadena', 'guias de cadena', 'chain guide'])
on conflict (coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), concept)
do update set kind = excluded.kind, label = excluded.label, terms = excluded.terms,
  broader = excluded.broader, phrases = excluded.phrases, updated_at = now();

-- «Tubo Asiento Negro 25.4 x 400 mm» es una tija, no un sillín.
update public.catalog_search_terms
   set phrases = array(select distinct phrase
                         from unnest(phrases || array['tubo asiento']) phrase
                        order by phrase),
       updated_at = now()
 where tenant_id is null
   and concept = 'tija'
   and not ('tubo asiento' = any (phrases));

delete from public.catalog_search_documents;
select public.catalog_search_documents_refresh_v1();

-- ---------------------------------------------------------------------------
-- 2. Lo que se vende junto y lo que más se vende
-- ---------------------------------------------------------------------------

create table if not exists public.catalog_part_affinity (
  tenant_id uuid not null,
  part text not null,
  other_part text not null,
  -- Boletas con las dos piezas, y boletas con la primera.
  together integer not null,
  part_tickets integer not null,
  -- P(otra | pieza): de cada 100 boletas con la pieza, cuántas llevan la otra.
  -- Un par de taller vale al menos 0.15.
  strength numeric not null,
  lift numeric,
  source text not null,
  -- A workshop pair counts even when the sales say little.
  workshop boolean not null default false,
  refreshed_at timestamptz not null default now(),
  constraint catalog_part_affinity_pkey primary key (tenant_id, part, other_part),
  constraint catalog_part_affinity_source_check check (source in ('ventas', 'taller')),
  constraint catalog_part_affinity_strength_check check (strength >= 0 and strength <= 1),
  constraint catalog_part_affinity_pair_check check (part <> other_part)
);

comment on table public.catalog_part_affinity is
  'What the shop sells together, by kind of part (catalog_search_terms concepts): paid sales of the last 24 months plus workshop pairs where sales are thin. Rebuilt by catalog_related_signals_refresh_v1; read by get_public_related_v2.';

create table if not exists public.catalog_product_popularity (
  tenant_id uuid not null,
  product_id uuid not null,
  tickets integer not null,
  refreshed_at timestamptz not null default now(),
  constraint catalog_product_popularity_pkey primary key (tenant_id, product_id)
);

comment on table public.catalog_product_popularity is
  'Paid sales tickets per product in the last 12 months. Rebuilt by catalog_related_signals_refresh_v1; read by get_public_related_v2.';

alter table public.catalog_part_affinity enable row level security;
alter table public.catalog_product_popularity enable row level security;
revoke all on public.catalog_part_affinity from public, anon, authenticated, service_role;
revoke all on public.catalog_product_popularity from public, anon, authenticated, service_role;

create or replace function public.catalog_related_signals_refresh_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_pairs integer := 0;
  v_workshop integer := 0;
  v_products integer := 0;
begin
  if p_tenant_id is null then
    raise exception 'catalog_related_signals_refresh_v1: tenant required';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended('catalog_related_signals:' || p_tenant_id::text, 0));

  delete from public.catalog_part_affinity where tenant_id = p_tenant_id;

  -- Each paid sale once, with the kinds of part it carried (services out).
  insert into public.catalog_part_affinity (
    tenant_id, part, other_part, together, part_tickets, strength, lift, source)
  with lines as (
    select distinct invoice.id as ticket, (item->>'product_id')::uuid as product_id
      from public.sales_invoices invoice
      cross join lateral jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb)) item
     where invoice.tenant_id = p_tenant_id
       and invoice.status in ('paid', 'confirmed', 'sent', 'enviado')
       and invoice.date >= now() - interval '24 months'
       and not coalesce((item->>'is_service')::boolean, false)
       and item->>'product_id' ~ '^[0-9a-fA-F-]{36}$'
  ),
  typed as (
    select distinct lines.ticket, part
      from lines
      join public.catalog_search_documents document
        on document.tenant_id = p_tenant_id
       and document.product_id = lines.product_id
      cross join lateral unnest(coalesce(document.own_parts, '{}'::text[])) part
  ),
  part_tickets as (
    select typed.part, count(*)::numeric as tickets from typed group by typed.part
  ),
  total as (
    select greatest(count(distinct typed.ticket), 1)::numeric as tickets from typed
  )
  select p_tenant_id,
         one.part,
         other.part,
         count(*)::integer,
         first.tickets::integer,
         round(least(1, count(*) / first.tickets), 4),
         round(count(*) * total.tickets / (first.tickets * second.tickets), 3),
         'ventas'
    from typed one
    join typed other on other.ticket = one.ticket and other.part <> one.part
    join part_tickets first on first.part = one.part
    join part_tickets second on second.part = other.part
    cross join total
   group by one.part, other.part, first.tickets, second.tickets, total.tickets
  having count(*) >= 3;
  get diagnostics v_pairs = row_count;

  -- Workshop pairs: what goes with a part where the shop's sales do not say
  -- it yet. They never lower what the sales say.
  insert into public.catalog_part_affinity (
    tenant_id, part, other_part, together, part_tickets, strength, lift, source, workshop)
  select p_tenant_id, pair.part, pair.other_part, 0, 0, 0.15, null, 'taller', true
    from (values
      ('rodillera', 'codera'), ('rodillera', 'casco'), ('rodillera', 'guante'),
      ('codera', 'rodillera'), ('codera', 'casco'), ('codera', 'guante'),
      ('casco', 'guante'), ('casco', 'lentes'), ('casco', 'luz'),
      ('guante', 'casco'), ('guante', 'lentes'),
      ('lentes', 'casco'), ('lentes', 'guante'),
      ('camara', 'parche'), ('camara', 'desmontador'), ('camara', 'inflador'),
      ('camara', 'neumatico'),
      ('neumatico', 'camara'), ('neumatico', 'desmontador'), ('neumatico', 'inflador'),
      ('parche', 'camara'), ('parche', 'desmontador'), ('parche', 'inflador'),
      ('desmontador', 'parche'), ('desmontador', 'camara'),
      ('inflador', 'camara'), ('inflador', 'parche'),
      ('cadena', 'cassette'), ('cadena', 'lubricante'), ('cadena', 'cortacadena'),
      ('cadena', 'eslabon'),
      ('cassette', 'cadena'), ('cassette', 'lubricante'),
      ('lubricante', 'cadena'), ('lubricante', 'desengrasante'),
      ('desengrasante', 'lubricante'), ('desengrasante', 'cepillo'),
      ('pastilla', 'disco'), ('disco', 'pastilla'), ('disco', 'adaptador'),
      ('asiento', 'tija'), ('tija', 'asiento'), ('tija', 'abrazadera'),
      ('puno', 'manubrio'), ('manubrio', 'puno'),
      ('manubrio', 'cinta_manubrio'), ('cinta_manubrio', 'manubrio'),
      ('pedal', 'cala'), ('cala', 'pedal'),
      ('caramayola', 'portacaramayola'), ('portacaramayola', 'caramayola'),
      ('llanta', 'cinta_llanta'), ('cinta_llanta', 'llanta'),
      ('llanta', 'rayo'), ('rayo', 'niple'),
      ('candado', 'luz'), ('luz', 'candado'),
      ('cambio', 'pata_de_cambio'), ('pata_de_cambio', 'cambio'),
      ('cambio', 'shifter'), ('shifter', 'cambio'),
      ('piola', 'funda'), ('funda', 'piola'),
      ('guia_cadena', 'plato'), ('plato', 'guia_cadena')
    ) as pair(part, other_part)
  on conflict (tenant_id, part, other_part) do update
     set strength = greatest(catalog_part_affinity.strength, excluded.strength),
         source = case
           when catalog_part_affinity.strength >= excluded.strength
             then catalog_part_affinity.source
           else excluded.source
         end,
         workshop = true,
         refreshed_at = now();
  get diagnostics v_workshop = row_count;

  delete from public.catalog_product_popularity where tenant_id = p_tenant_id;
  insert into public.catalog_product_popularity (tenant_id, product_id, tickets)
  select p_tenant_id, sold.product_id, count(distinct sold.ticket)::integer
    from (
      select invoice.id as ticket, (item->>'product_id')::uuid as product_id
        from public.sales_invoices invoice
        cross join lateral jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb)) item
       where invoice.tenant_id = p_tenant_id
         and invoice.status in ('paid', 'confirmed', 'sent', 'enviado')
         and invoice.date >= now() - interval '12 months'
         and item->>'product_id' ~ '^[0-9a-fA-F-]{36}$'
    ) sold
    join public.products product
      on product.tenant_id = p_tenant_id
     and product.id = sold.product_id
   group by sold.product_id;
  get diagnostics v_products = row_count;

  return jsonb_build_object(
    'pairs', v_pairs, 'workshop_pairs', v_workshop, 'products', v_products);
end;
$$;

comment on function public.catalog_related_signals_refresh_v1(uuid) is
  'Rebuilds catalog_part_affinity and catalog_product_popularity for one tenant from its paid sales (24 and 12 months) and the workshop pairs.';

revoke all on function public.catalog_related_signals_refresh_v1(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.catalog_related_signals_refresh_all_v1()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant uuid;
  v_count integer := 0;
begin
  for v_tenant in
    select distinct document.tenant_id from public.catalog_search_documents document
  loop
    perform public.catalog_related_signals_refresh_v1(v_tenant);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.catalog_related_signals_refresh_all_v1()
  from public, anon, authenticated, service_role;

select public.catalog_related_signals_refresh_all_v1();

-- ---------------------------------------------------------------------------
-- 3. Los relacionados
-- ---------------------------------------------------------------------------

-- The nominal wheel size a name says: «29 x 2.25» and «aro 29» → 29;
-- «700x23C» and «28 x 1.75» → 700. 29 and 700c share the 622 bead seat, but
-- a 29 x 2.25 tyre or tube is no alternative to a 700 x 23 one.
create or replace function public.catalog_related_size_label_internal_v1(p_name text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select case coalesce(found.size[1], found.size[2])
           when '28' then '700'
           when '650b' then '27.5'
           when '27,5' then '27.5'
           else coalesce(found.size[1], found.size[2])
         end
    from (
      select regexp_match(
               lower(coalesce(p_name, '')),
               '(?:^|[^0-9.,/])(700|650b|29|28|27[.,]5|26|24|20|16|14|12)\s*(?:x|"|”|''''|c\y)'
               || '|(?:aro|rin|rodado)\s*(700|650b|29|28|27[.,]5|26|24|20|16|14|12)\y'
             ) as size
    ) found
$$;

-- A chain's width as its name says it: «1/2 X 1/8» is a single-speed chain,
-- «1/2 x 3/32» one of 5 to 8 speeds, «1/2 x 11/128» one of 9 to 12.
create or replace function public.catalog_related_chain_width_internal_v1(p_name text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select (regexp_match(
            lower(coalesce(p_name, '')),
            '1/2\s*"?\s*x\s*(1/8|3/32|11/128|5/64)'))[1]
$$;

-- Children's gear by its name: an adult's product never suggests it, nor the
-- other way round.
create or replace function public.catalog_related_is_kids_internal_v1(p_name_n text)
returns boolean
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select (' ' || coalesce(p_name_n, '') || ' ')
         ~ ' (nino|nina|ninos|ninas|infantil|infantiles|youth|junior|kids|kid|juvenil) '
$$;

revoke all on function public.catalog_related_size_label_internal_v1(text)
  from public, anon, authenticated, service_role;
revoke all on function public.catalog_related_chain_width_internal_v1(text)
  from public, anon, authenticated, service_role;
revoke all on function public.catalog_related_is_kids_internal_v1(text)
  from public, anon, authenticated, service_role;

create or replace function public.get_public_related_v2(
  p_tenant_id uuid,
  p_product_id uuid,
  p_limit integer default 9
)
returns table(product_id uuid, place integer, kind text)
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  with products as (
    -- Each product of the store as the ranking reads it.
    select p.id,
           p.category_id,
           -- «Genérico», a marketplace or a country says nothing of the
           -- product: only a real brand counts as the same brand.
           case
             when lower(coalesce(brand.name, '')) in (
               '', 'genérico', 'generico', 'genérica', 'generica', 'aliexpress',
               'taiwan', 'china', 'sin marca', 'compatible', 'varios', 'otros')
               then null
             else p.brand_id
           end as brand_key,
           coalesce(nullif(p.website_price, 0), p.price) as price,
           coalesce(document.own_parts, '{}'::text[]) as parts,
           coalesce(nullif(document.name_n, ''), lower(p.name)) as name_n,
           -- A 1/8 chain is single speed: it says «speeds 1» to whatever
           -- names its speeds.
           coalesce(document.measures, '{}'::text[])
             || case
                  when public.catalog_related_chain_width_internal_v1(p.name) = '1/8'
                   and not exists (
                         select 1
                           from unnest(coalesce(document.measures, '{}'::text[])) measure
                          where measure like 'speeds:%')
                    then array['speeds:1']
                  else '{}'::text[]
                end as measures,
           public.catalog_related_size_label_internal_v1(p.name) as size_label,
           public.catalog_related_chain_width_internal_v1(p.name) as chain_width,
           public.catalog_related_is_kids_internal_v1(
             coalesce(nullif(document.name_n, ''), lower(p.name))) as kids,
           member.model_id,
           p.is_active
             and p.is_published
             and p.show_on_website
             and not coalesce(p.is_service, false)
             and coalesce(p.product_type, 'product') <> 'service'
             and coalesce(nullif(p.website_price, 0), p.price) > 0
             -- Buyable today: on the shelf, not counted, or bought to order.
             and (coalesce(p.stock_quantity, 0) > 0
                  or not coalesce(p.track_stock, true)
                  or coalesce(terms.is_active, false)) as offered,
           (coalesce(p.stock_quantity, 0) > 0 or not coalesce(p.track_stock, true)) as in_stock,
           coalesce(popularity.tickets, 0) as tickets
      from public.products p
      left join public.product_brands brand
        on brand.id = p.brand_id
      left join public.catalog_search_documents document
        on document.tenant_id = p.tenant_id
       and document.product_id = p.id
      left join public.product_model_members member
        on member.tenant_id = p.tenant_id
       and member.product_id = p.id
      left join public.product_on_order_terms terms
        on terms.tenant_id = p.tenant_id
       and terms.product_id = p.id
      left join public.catalog_product_popularity popularity
        on popularity.tenant_id = p.tenant_id
       and popularity.product_id = p.id
     where p.tenant_id = p_tenant_id
  ),
  base as (
    select products.* from products where products.id = p_product_id
  ),
  links as (
    -- What the shop sells with this kind of part: a workshop pair, or a sale
    -- pattern seen at least eight times, in at least 8 of each 100 tickets,
    -- and three times more than chance (a full service sells grips with a
    -- chain; that is not a reason to suggest them).
    select link.other_part, max(link.strength) as strength
      from base
      join public.catalog_part_affinity link
        on link.tenant_id = p_tenant_id
       and link.part = any (base.parts)
       and not (link.other_part = any (base.parts))
     where link.workshop
        or (link.together >= 8 and link.strength >= 0.08 and coalesce(link.lift, 0) >= 3)
     group by link.other_part
  ),
  pool as (
    select products.*
      from products
      cross join base
     where products.id <> base.id
       and products.offered
       -- The page's own sizes and colors are in its selector.
       and (base.model_id is null or products.model_id is distinct from base.model_id)
  ),
  first_pass as (
    select pool.*,
           case
             when cardinality(base.parts) > 0 and pool.parts && base.parts then 'alternativa'
             when link.strength is not null then 'complemento'
             when pool.category_id = base.category_id then 'categoria'
           end as kind,
           link.other_part as via_part,
           coalesce(link.strength, 0) as strength,
           -- A broad word (a «protector» may be a frame sticker or a
           -- backpack cover) needs a resemblance to count as the same thing.
           (pool.parts && base.parts
             and array(select unnest(pool.parts) intersect select unnest(base.parts))
                 <@ array['protector', 'herramienta', 'adaptador']) as broad_type,
           similarity(pool.name_n, base.name_n) as likeness,
           coalesce(base.brand_key is not null and pool.brand_key = base.brand_key, false) as same_brand,
           case
             when base.price > 0 and pool.price > 0
               then greatest(-1, 1 - abs(ln(pool.price / base.price)) / ln(4))
             else 0
           end as price_close,
           (pool.kids is distinct from base.kids) as kids_clash,
           (pool.size_label is not null and base.size_label is not null
             and pool.size_label <> base.size_label) as size_clash,
           (pool.chain_width is not null and base.chain_width is not null
             and pool.chain_width <> base.chain_width) as chain_clash,
           -- A tube, tyre, rim or wheel that does not say its size, for a
           -- product that does.
           (base.size_label is not null and pool.size_label is null
             and pool.parts && array['camara', 'neumatico', 'llanta', 'rueda', 'cinta_llanta']
           ) as size_unknown,
           -- A measure both name (bead seat, speeds) with no value in common.
           exists (
             select 1
               from unnest(pool.measures) own(measure)
              where split_part(own.measure, ':', 1) in (
                      select split_part(other.measure, ':', 1)
                        from unnest(base.measures) other(measure))
              group by split_part(own.measure, ':', 1)
             having not bool_or(own.measure = any (base.measures))
           ) as measure_clash
      from pool
      cross join base
      left join lateral (
        select candidate_link.other_part, candidate_link.strength
          from links candidate_link
         where candidate_link.other_part = any (pool.parts)
         order by candidate_link.strength desc, candidate_link.other_part
         limit 1
      ) link on true
  ),
  pre as (
    select first_pass.*,
           case first_pass.kind
             -- A much cheaper or dearer one (four times or more) is another
             -- class of product: a $6.000 kids' set is no alternative to a
             -- $65.990 Leatt knee pad.
             when 'alternativa' then 1000 + 250 * first_pass.likeness
               + case when first_pass.price_close >= 0 then 120 else 300 end
                 * first_pass.price_close
             when 'complemento' then 600 + 400 * least(first_pass.strength, 1)
             else 200 + 300 * first_pass.likeness
           end
           + 60 * first_pass.same_brand::int
           + 20 * first_pass.in_stock::int
           + least(30, 6 * ln(1 + first_pass.tickets))
           - case
               when first_pass.kids_clash or first_pass.size_clash
                 or first_pass.chain_clash or first_pass.measure_clash then 2000
               else 0
             end
           - case when first_pass.size_unknown then 600 else 0 end as pre_score
      from first_pass
     where first_pass.kind is not null
  ),
  top as (
    select pre.*
      from pre
     where pre.pre_score > 0
     order by pre.pre_score desc, pre.id
     limit 60
  ),
  facets as (
    select value.product_id, value.spec_key, value.value_text
      from public.spec_public_facet_values_compute_internal_v1(
             p_tenant_id,
             array(select top.id from top) || array[p_product_id]
           ) value
  ),
  base_facets as (
    select facets.spec_key, facets.value_text
      from facets
     where facets.product_id = p_product_id
  ),
  critical as (
    -- Keys where a different value means it does not fit or is not the same
    -- thing: rim, valve, speeds, brake, mounts, threads, who it is for.
    select key
      from unnest(array[
        'bead_seat_diameter_mm', 'valve_standard', 'sprocket_count', 'chain_width_family',
        'braking_surface', 'rotor_mount_type', 'handlebar_clamp_mm',
        'grip_bar_nominal_diameter_mm', 'pedal_thread_standard', 'pedal_thread',
        'cassette_spline_standard', 'hub_old_mm', 'intended_audience', 'intended_rider',
        'tire_use', 'spoke_hole_count', 'drivetrain_mode', 'rear_derailleur_mount_type',
        'freewheel_thread_standard', 'spindle_interface', 'hub_axle_mount_kind', 'tool_kind'
      ]) key
     where key in (select base_facets.spec_key from base_facets)
  ),
  fit as (
    select top.id,
           (select count(distinct candidate.spec_key)
              from facets candidate
              join base_facets own
                on own.spec_key = candidate.spec_key
               and own.value_text = candidate.value_text
             where candidate.product_id = top.id) as shared,
           (select count(*)
              from critical
             where exists (
                     select 1 from facets candidate
                      where candidate.product_id = top.id
                        and candidate.spec_key = critical.key)
               and not exists (
                     select 1
                       from facets candidate
                       join base_facets own
                         on own.spec_key = candidate.spec_key
                        and own.value_text = candidate.value_text
                      where candidate.product_id = top.id
                        and candidate.spec_key = critical.key)) as clash,
           (select count(*)
              from critical
             where exists (
                     select 1 from facets candidate
                      where candidate.product_id = top.id
                        and candidate.spec_key = critical.key)) as known
      from top
  ),
  scored as (
    select top.*,
           top.pre_score
             + 80 * least(fit.shared, 4)
             - case when fit.clash > 0 then 2000 else 0 end
             -- Nothing in its sheet says it is the same size or use.
             - case
                 when top.kind = 'alternativa'
                  and fit.known = 0
                  and exists (select 1 from critical) then 150
                 else 0
               end
             -- A broad word with nothing else in common is not the same thing.
             - case
                 when top.kind = 'alternativa'
                  and top.broad_type
                  and top.likeness < 0.25
                  and fit.shared = 0
                  and not top.same_brand then 600
                 else 0
               end as score
      from top
      join fit on fit.id = top.id
  ),
  listed as (
    -- What the store publishes today, with the page's own id so the list is
    -- never empty (an empty list would read the whole catalog).
    select listed.id
      from public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_product_ids := array(select scored.id from scored where scored.score > 0)
                              || array[p_product_id],
             p_only_in_stock := false,
             p_limit := 61
           ) listed
  ),
  kept as (
    select scored.*,
           row_number() over (
             partition by coalesce(scored.model_id, scored.id)
             order by scored.score desc, scored.in_stock desc, scored.id
           ) as model_rank
      from scored
      join listed on listed.id = scored.id
     where scored.score >= case scored.kind
             when 'alternativa' then 900
             when 'complemento' then 550
             else 250
           end
  ),
  grouped as (
    select kept.*,
           row_number() over (
             partition by kept.kind,
                          case when kept.kind = 'complemento' then kept.via_part end
             order by kept.score desc, kept.id
           ) as in_group
      from kept
     where kept.model_rank = 1
  ),
  ordered as (
    -- Up to five that replace it, then two of each thing that goes with it,
    -- then the rest by score: a third of a kind that goes with it at most,
    -- and the category's last.
    select grouped.id,
           grouped.kind,
           row_number() over (
             order by
               case
                 when grouped.kind = 'alternativa' and grouped.in_group <= 5 then 0
                 when grouped.kind = 'complemento' and grouped.in_group <= 2 then 1
                 when grouped.kind <> 'categoria' then 2
                 else 3
               end,
               grouped.score desc,
               grouped.id
           )::integer as place
      from grouped
     where grouped.kind <> 'complemento' or grouped.in_group <= 3
  )
  select ordered.id, ordered.place, ordered.kind
    from ordered
   where ordered.place <= greatest(1, least(coalesce(p_limit, 9), 24))
   order by ordered.place
$$;

comment on function public.get_public_related_v2(uuid, uuid, integer) is
  'The related products of a product page: what replaces it (same part, size and use, similar price), then what goes with it (what the shop sells with that part, two of each, the same brand first). Never what does not fit (rim, valve, speeds, brake, 29 against 700) nor children''s gear for an adult; one card per model; only what the store publishes and can sell today.';

revoke all on function public.get_public_related_v2(uuid, uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_related_v2(uuid, uuid, integer)
  to anon, authenticated, service_role;

do $$
declare
  v_job record;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron unavailable; related signals were not scheduled';
    return;
  end if;
  for v_job in
    select jobid from cron.job where jobname = 'vinabike_catalog_related_signals'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
  -- 04:41 en Chile en verano, lejos de los cuartos de hora de los otros.
  perform cron.schedule(
    'vinabike_catalog_related_signals',
    '41 7 * * *',
    $job$select public.catalog_related_signals_refresh_all_v1()$job$
  );
end
$$;

-- ---------------------------------------------------------------------------
-- 4. La ficha
-- ---------------------------------------------------------------------------

create or replace function public.get_public_product_page_v2(
  p_tenant_id uuid,
  p_sku text default null::text,
  p_product_id uuid default null::uuid,
  p_group_models boolean default false
)
returns jsonb
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  with base as (
    select to_jsonb(product) - 'cost' - 'total_count' as row,
           product.id,
           product.category_id,
           product.brand_id
      from public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_product_ids := case
               when p_product_id is not null then array[p_product_id]
             end,
             p_sku := case when p_product_id is null then p_sku end,
             p_only_in_stock := false,
             p_limit := 1
           ) product
     -- Without a SKU or an id the listing would return any product.
     where p_product_id is not null or nullif(btrim(p_sku), '') is not null
     limit 1
  ),
  picked as (
    -- 20261121020000: what replaces it, then what goes with it
    -- (get_public_related_v2), instead of the category's first 48 in stock.
    select pick.product_id, pick.place
      from base
      cross join lateral public.get_public_related_v2(p_tenant_id, base.id, 9) pick
  ),
  related as (
    select to_jsonb(item) - 'cost' - 'total_count' as row,
           item.id,
           item.brand_id,
           picked.place as position
      from picked
      join public.get_public_products(
             p_tenant_id := p_tenant_id,
             -- With the page's own id the list is never empty (an empty
             -- list would read the whole catalog).
             p_product_ids := array(select picked.product_id from picked)
                              || array(select base.id from base),
             p_only_in_stock := false,
             p_limit := 25
           ) item on item.id = picked.product_id
  ),
  pool_models as (
    -- 20261120230000: con p_group_models, el modelo de cada relacionado para
    -- su tarjeta. Sin el parámetro no se lee nada y no hay modelos.
    select found.product_id, found.model_id, found.model_name,
           found.variant_count, found.axes, found.price_min, found.price_max
      from public.get_public_product_models_v1(
             p_tenant_id,
             case when coalesce(p_group_models, false) then
               array(select related.id from related) || array(select base.id from base)
             else '{}'::uuid[] end
           ) found
  ),
  fits as (
    -- What goes with the product: the tubes that fit a tyre, the tyres a
    -- tube fits (20261024020000), cheapest first.
    select to_jsonb(item) - 'cost' - 'total_count' as row,
           item.id,
           item.brand_id,
           fit.kind,
           fit.fit_position as position
      from base
      cross join lateral public.get_public_product_fits_v1(
             p_tenant_id, base.id, 6) fit
      join lateral public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_product_ids := array[fit.product_id],
             p_only_in_stock := true,
             p_limit := 1
           ) item on true
  ),
  website as (
    select p.id, to_jsonb(fields) as fields
      from public.products p
      cross join lateral (
        select p.is_set, p.set_type, p.parent_set_id, p.component_label,
               p.component_position, p.website_name, p.website_price,
               p.website_price_mode, p.website_description, p.website_seo_title,
               p.website_seo_description, p.website_search_terms,
               p.website_merchant_title, p.website_merchant_description,
               p.website_merchant_brand, p.website_merchant_gtin,
               p.website_merchant_mpn, p.website_google_product_category,
               p.website_image_url, p.website_image_url_optimized,
               p.website_image_urls, p.price_currency
      ) fields
     where p.tenant_id = p_tenant_id
       and p.id in (
         select id from base
         union all select id from related
         union all select id from fits
       )
  )
  select jsonb_build_object(
    'product', base.row || coalesce(
      (select website.fields from website where website.id = base.id),
      '{}'::jsonb),
    -- Raw rows of this store's or global brands: the client decides with
    -- canonicalPublicProductBrandNames, the rule the Flutter store applies.
    'brand_rows', coalesce((
      select jsonb_agg(to_jsonb(brand))
        from (
          select b.id, b.name, b.tenant_id, b.is_active
            from public.product_brands b
           where b.is_active
             and (b.tenant_id = p_tenant_id or b.tenant_id is null)
             and b.id in (
               select base.brand_id
               union
               select related.brand_id from related
               union
               select fits.brand_id from fits
             )
        ) brand
    ), '[]'::jsonb),
    'specs', coalesce((
      select jsonb_agg(to_jsonb(spec))
        from public.get_public_product_technical_specs(p_tenant_id, base.id) spec
    ), '[]'::jsonb),
    'related', coalesce((
      select jsonb_agg(
               related.row
                 || coalesce(website.fields, '{}'::jsonb)
                 -- Con p_group_models, el modelo del relacionado para su
                 -- tarjeta («2 colores · 3 tallas», «Desde $X»).
                 || coalesce((
                      select jsonb_build_object(
                               'model_id', model.model_id,
                               'model_name', model.model_name,
                               'model_summary', jsonb_build_object(
                                 'variants', model.variant_count,
                                 'axes', model.axes,
                                 'priceMin', model.price_min,
                                 'priceMax', model.price_max))
                        from pool_models model
                       where model.product_id = related.id), '{}'::jsonb)
               order by related.position)
        from related
        left join website on website.id = related.id
    ), '[]'::jsonb),
    'fits', coalesce((
      select jsonb_build_object(
               'kind', min(fits.kind),
               'items', jsonb_agg(
                 fits.row || coalesce(website.fields, '{}'::jsonb)
                 order by fits.position))
        from fits
        left join website on website.id = fits.id
    ), '{}'::jsonb)
  )
  -- El modelo de la ficha con sus variantes, sólo si la tienda lo pide.
  || case
       when coalesce(p_group_models, false) then jsonb_build_object(
         'model', public.get_public_product_model_v1(p_tenant_id, base.id))
       else '{}'::jsonb
     end
    from base;
$function$;

revoke all on function public.get_public_product_page_v2(uuid, text, uuid, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_product_page_v2(uuid, text, uuid, boolean)
  to anon, authenticated, service_role;

comment on function public.get_public_product_page_v2(uuid, text, uuid, boolean) is
  'A product page: the product, its brand rows, its spec sheet, its related products (get_public_related_v2: what replaces it, then what goes with it) and what fits it; with p_group_models, its model.';

commit;
