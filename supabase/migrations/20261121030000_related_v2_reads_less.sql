-- Los relacionados leen sólo lo que pueden mostrar (2026-11-21).
--
-- get_public_related_v2 (20261121020000) revisaba el nombre de cada producto
-- de la tienda, también los que no se publican ni se venden, para su medida,
-- su ancho de cadena y si es de niño: 165 ms por ficha medidos en producción,
-- casi todo en esas lecturas. Ahora lee la ficha y lo que se puede mostrar:
-- ~100 ms, con los mismos relacionados en las 26 fichas de prueba.
begin;
set local lock_timeout = '5s';

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
       -- Only the page's product and what could be shown: the names of
       -- everything else are never read (20261121030000: 165 ms → ~100).
       and (p.id = p_product_id
            or (p.is_active
                and p.is_published
                and p.show_on_website
                and not coalesce(p.is_service, false)
                and coalesce(p.product_type, 'product') <> 'service'
                and coalesce(nullif(p.website_price, 0), p.price) > 0
                and (coalesce(p.stock_quantity, 0) > 0
                     or not coalesce(p.track_stock, true)
                     or coalesce(terms.is_active, false))))
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

comment on function public.get_public_related_v2(uuid, uuid, integer) is
  'The related products of a product page: what replaces it (same part, size and use, similar price), then what goes with it (what the shop sells with that part, two of each, the same brand first). Never what does not fit (rim, valve, speeds, brake, 29 against 700) nor children''s gear for an adult; one card per model; only what the store publishes and can sell today.';

revoke all on function public.get_public_related_v2(uuid, uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_related_v2(uuid, uuid, integer)
  to anon, authenticated, service_role;

commit;
