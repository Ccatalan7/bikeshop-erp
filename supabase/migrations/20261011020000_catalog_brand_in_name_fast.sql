-- «La marca está en el nombre», sin agregarle 1,6 s a la lista del catálogo.
--
-- 20261011010000 armaba, por cada producto candidato, dos expresiones
-- regulares por cada una de las 186 marcas. Postgres guarda pocas
-- expresiones compiladas, así que recompilaba todas cada vez: con los ~230
-- candidatos del 2026-10-11, `catalog_web_items_v1` pasó de ~4,4 s a 6,1 s.
-- Ahora la marca se busca como palabra en el texto normalizado (`position`,
-- sin expresión), la lista de marcas se normaliza una vez por lista y la
-- expresión del «para …» sólo se arma para la marca que sí aparece. La regla
-- es la misma; la prueba de 20261011010000 la sigue cubriendo.

-- El texto como palabras: minúsculas, todo lo que no es letra o número a un
-- espacio, con un espacio en cada borde.
create or replace function public.catalog_brand_text_v1(p_text text)
returns text
language sql
immutable
as $$
  select ' ' || btrim(regexp_replace(lower(coalesce(p_text, '')), '[^[:alnum:]]+', ' ', 'g')) || ' ';
$$;

-- Las marcas que puede sugerir: reales, activas, del tenant o globales, y que
-- no son palabras comunes del catálogo. Primero las del tenant.
create or replace function public.catalog_brand_words_v1(p_tenant_id uuid)
returns table (id uuid, name_key text)
language sql
stable
set search_path = pg_catalog, public, pg_temp
as $$
  select b.id, btrim(public.catalog_brand_text_v1(b.name))
    from public.product_brands b
   where b.is_active
     and (b.tenant_id is null or b.tenant_id = p_tenant_id)
     and length(btrim(b.name)) >= 3
     and public.catalog_is_public_brand_v1(b.name)
     and btrim(public.catalog_brand_text_v1(b.name)) not in ('doble', 'pro', 'velo')
   order by (b.tenant_id is null), b.id;
$$;

-- La única marca de la lista que el texto nombra como palabra entera, sin
-- «para», «compatible con», «tipo» o «réplica» delante; null si ninguna o
-- más de una.
create or replace function public.catalog_brand_from_words_v1(
  p_text text,
  p_ids uuid[],
  p_keys text[]
)
returns uuid
language sql
immutable
as $$
  with text_words as (
    select public.catalog_brand_text_v1(p_text) as padded,
           lower(coalesce(p_text, '')) as raw
  ), named as (
    select distinct on (word.name_key) word.id
      from unnest(coalesce(p_ids, '{}'::uuid[]), coalesce(p_keys, '{}'::text[]))
             with ordinality as word(id, name_key, position),
           text_words
     where case
             when position(' ' || word.name_key || ' ' in text_words.padded) > 0
               then text_words.raw !~ (
                 '(para|compatible con|p/|tipo|estilo|r[eé]plica|igual a)\s+([[:alnum:]-]+\s+){0,2}'
                 || replace(word.name_key, ' ', '[^[:alnum:]]+') || '($|[^[:alnum:]])')
             else false
           end
     order by word.name_key, word.position
  )
  select case when count(*) = 1 then (array_agg(named.id))[1] end
    from named;
$$;

-- La misma regla para un texto suelto (la usa «Usar la marca del nombre»).
create or replace function public.catalog_brand_from_name_v1(
  p_tenant_id uuid,
  p_text text
)
returns uuid
language sql
stable
set search_path = pg_catalog, public, pg_temp
as $$
  select public.catalog_brand_from_words_v1(
           p_text,
           array_agg(word.id order by word.position),
           array_agg(word.name_key order by word.position))
    from public.catalog_brand_words_v1(p_tenant_id) with ordinality as word(id, name_key, position);
$$;

revoke all on function public.catalog_brand_text_v1(text) from public, anon;
grant execute on function public.catalog_brand_text_v1(text) to authenticated;
revoke all on function public.catalog_brand_words_v1(uuid) from public, anon;
grant execute on function public.catalog_brand_words_v1(uuid) to authenticated;
revoke all on function public.catalog_brand_from_words_v1(text, uuid[], text[]) from public, anon;
grant execute on function public.catalog_brand_from_words_v1(text, uuid[], text[]) to authenticated;

create or replace function public.catalog_web_items_v1(p_tenant_id uuid)
returns table (
  id uuid,
  name text,
  website_name text,
  sku text,
  gtin text,
  product_type text,
  kind text,
  category_id uuid,
  category_name text,
  brand_id uuid,
  brand text,
  price numeric,
  web_price numeric,
  cost numeric,
  tax_rate numeric,
  min_web_price numeric,
  image_url text,
  has_description boolean,
  web_on boolean,
  is_active boolean,
  clearance_until date,
  price_mode text,
  stock integer,
  available integer,
  block text,
  state text,
  sold_counter_12m integer,
  used_jobs_12m integer,
  sold_total_12m integer,
  issues text[],
  suggested_brand_id uuid,
  suggested_brand text,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
#variable_conflict use_column
begin
  perform public.catalog_assert_reader_v1(p_tenant_id);

  return query
  with policy as (
    select public.catalog_web_policy_v1(p_tenant_id) as v
  ), brand_words as materialized (
    -- Las marcas se normalizan una vez por lista, no una vez por producto
    -- (20261011020000).
    select array_agg(word.id order by word.position) as ids,
           array_agg(word.name_key order by word.position) as keys
      from public.catalog_brand_words_v1(p_tenant_id) with ordinality as word(id, name_key, position)
  ), reserved as (
    select reservation.product_id,
           sum(reservation.quantity)::integer as quantity
      from public.online_order_inventory_reservations reservation
     where reservation.tenant_id = p_tenant_id
       and reservation.state = 'active'
       and reservation.expires_at > clock_timestamp()
     group by reservation.product_id
  ), base as (
    select p.*,
           public.catalog_product_web_block_v1(p, (select policy.v from policy)) as blk,
           linked_brand.name as linked_brand_name
      from public.products p
      left join public.product_brands linked_brand
        on linked_brand.id = p.brand_id
       and linked_brand.is_active
       and (linked_brand.tenant_id is null or linked_brand.tenant_id = p.tenant_id)
     where p.tenant_id = p_tenant_id
  ), set_avail as (
    select b.id,
           min(greatest(floor(
             (coalesce(component.stock_quantity, component.inventory_qty, 0)
               - coalesce(component_reserved.quantity, 0))::numeric
             / nullif(set_component.quantity_in_set, 0)
           ), 0))::integer as available_quantity
      from base b
      join public.product_set_components set_component
        on set_component.tenant_id = b.tenant_id
       and set_component.set_product_id = b.id
      join public.products component
        on component.id = set_component.component_product_id
       and component.tenant_id = set_component.tenant_id
      left join reserved component_reserved
        on component_reserved.product_id = component.id
     where coalesce(b.is_set, false)
     group by b.id
  ), lines as (
    select (line ->> 'product_id')::uuid as product_id,
           coalesce((line ->> 'quantity')::numeric, 0) as quantity,
           (line ? 'job_bike_id' and line ->> 'job_bike_id' is not null) as in_job,
           invoice.created_at > now() - interval '12 months' as recent
      from public.sales_invoices invoice
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(invoice.items) = 'array' then invoice.items else '[]'::jsonb end
      ) line
     where invoice.tenant_id = p_tenant_id
       and coalesce(invoice.status, '') not in ('cancelled', 'void', 'anulada', 'draft')
       and (line ->> 'product_id') ~ '^[0-9a-f-]{36}$'
  ), sales as (
    select lines.product_id,
           coalesce(sum(lines.quantity) filter (where lines.recent and not lines.in_job), 0)::integer as counter_12m,
           coalesce(sum(lines.quantity) filter (where lines.recent and lines.in_job), 0)::integer as jobs_12m,
           coalesce(sum(lines.quantity) filter (where lines.recent), 0)::integer as total_12m,
           count(*) as ever
      from lines
     group by lines.product_id
  ), bought as (
    select distinct purchase_line.product_id
      from public.purchase_invoice_lines purchase_line
     where purchase_line.tenant_id = p_tenant_id
       and purchase_line.product_id is not null
  ), ordered as (
    select distinct order_item.product_id
      from public.online_order_items order_item
      join public.online_orders online_order
        on online_order.id = order_item.order_id
     where online_order.tenant_id = p_tenant_id
  ), shaped as (
    select b.*,
           case
             when coalesce(b.product_type, 'product') = 'service' then 'service'
             when coalesce(b.purchase_treatment, 'inventory') = 'workshop_consumable' then 'consumable'
             when coalesce(b.is_set, false) then 'kit'
             else 'product'
           end as item_kind,
           greatest(coalesce(b.stock_quantity, 0), coalesce(b.inventory_qty, 0)) as raw_stock,
           case
             when coalesce(b.product_type, 'product') = 'service' then null::integer
             when coalesce(b.purchase_treatment, 'inventory') = 'workshop_consumable' then null::integer
             when not coalesce(b.track_stock, true) then null::integer
             when coalesce(b.is_set, false) then coalesce(sa.available_quantity, 0)
             else greatest(coalesce(b.stock_quantity, b.inventory_qty, 0) - coalesce(r.quantity, 0), 0)
           end as available_quantity,
           coalesce(s.counter_12m, 0) as counter_12m,
           coalesce(s.jobs_12m, 0) as jobs_12m,
           coalesce(s.total_12m, 0) as total_12m,
           (s.product_id is null and bo.product_id is null and o.product_id is null) as never_used,
           coalesce(
             nullif(btrim(b.website_image_url_optimized), ''),
             nullif(btrim(b.website_image_url), ''),
             (b.website_image_urls)[1],
             nullif(btrim(b.image_url_optimized), ''),
             nullif(btrim(b.image_url), ''),
             (b.image_urls)[1]
           ) as thumb
      from base b
      left join set_avail sa on sa.id = b.id
      left join reserved r on r.product_id = b.id
      left join sales s on s.product_id = b.id
      left join bought bo on bo.product_id = b.id
      left join ordered o on o.product_id = b.id
  ), stated as (
    select sh.*,
           case
             when sh.blk = 'workshop_consumable' then 'taller'
             when sh.blk in ('inactive', 'web_off') then 'oculto'
             when sh.blk is not null then 'falta'
             when sh.item_kind = 'service' then 'venta'
             when not coalesce(sh.track_stock, true) then 'venta'
             when coalesce(sh.available_quantity, 0) <= 0 then 'agotado'
             else 'venta'
           end as item_state
      from shaped sh
  ), branded as (
    -- A la venta con un distribuidor, un país o nada como marca, y la marca
    -- real en el nombre (20261011010000).
    select st.*,
           case
             when st.item_state in ('venta', 'agotado')
                  and st.item_kind in ('product', 'kit')
                  and not (public.catalog_is_public_brand_v1(st.website_merchant_brand)
                           or public.catalog_is_public_brand_v1(st.linked_brand_name)
                           or public.catalog_is_public_brand_v1(st.brand))
               then public.catalog_brand_from_words_v1(
                 coalesce(nullif(btrim(st.website_name), ''), st.name) || ' ' || coalesce(st.name, ''),
                 (select brand_words.ids from brand_words),
                 (select brand_words.keys from brand_words))
           end as brand_suggestion
      from stated st
  ), flagged as (
    select st.*,
           array_remove(array[
             case when st.item_state = 'falta' then st.blk end,
             case
               when st.item_kind in ('product', 'kit')
                    and nullif(btrim(coalesce(st.gtin, '')), '') is null
                    and nullif(btrim(coalesce(st.barcode, '')), '') is null
                    and public.catalog_gtin_is_valid_v1(btrim(st.sku))
                 then 'gtin_in_sku'
             end,
             case
               when st.item_state in ('venta', 'agotado')
                    and st.item_kind <> 'service'
                    and nullif(btrim(coalesce(st.website_name, '')), '') is null
                 then 'no_web_name'
             end,
             case
               when st.item_state in ('venta', 'agotado')
                    and st.item_kind in ('product', 'kit')
                    and st.brand_id is null
                    and st.brand_suggestion is null
                 then 'no_brand'
             end,
             case
               when st.brand_suggestion is not null
                 then 'brand_in_name'
             end,
             case
               when st.item_kind = 'consumable' and st.counter_12m > 0
                 then 'counter_consumable'
             end,
             case
               when st.item_kind in ('product', 'kit')
                    and st.item_state in ('venta', 'agotado')
                    and coalesce(nullif(btrim(st.website_name), ''), st.name)
                        ~* '(rollo\s+(de\s+)?[0-9]|gruesa|caja de [0-9]|pack de [0-9]|\([0-9]+ ?(un|pcs|unid|u)\.?\))'
                 then 'bulk_pack'
             end,
             case
               when st.item_kind = 'product'
                    and st.is_active
                    and coalesce(st.price, 0) <= 0
                    and coalesce(st.cost, 0) <= 0
                    and st.raw_stock <= 0
                    and st.never_used
                 then 'empty_record'
             end
           ], null) as raw_issues
      from branded st
  )
  select f.id,
         f.name,
         f.website_name,
         f.sku,
         f.gtin,
         f.product_type,
         f.item_kind,
         f.category_id,
         f.category_name,
         f.brand_id,
         f.brand,
         f.price,
         coalesce(f.website_price, f.price),
         f.cost,
         f.tax_rate,
         case
           when f.item_kind in ('product', 'kit') and coalesce(f.cost, 0) > 0
             then ceil(f.cost * public.catalog_tax_factor_v1(f.tax_rate))
         end,
         f.thumb,
         nullif(btrim(coalesce(f.website_description, '')), '') is not null,
         coalesce(f.is_published, false) and coalesce(f.show_on_website, false),
         coalesce(f.is_active, false),
         f.web_clearance_until,
         f.website_price_mode,
         f.raw_stock,
         f.available_quantity,
         f.blk,
         f.item_state,
         f.counter_12m,
         f.jobs_12m,
         f.total_12m,
         array(
           select candidate.issue_code
             from unnest(f.raw_issues) as candidate(issue_code)
            where not exists (
              select 1
                from public.catalog_issue_dismissals dismissal
               where dismissal.tenant_id = p_tenant_id
                 and dismissal.product_id = f.id
                 and dismissal.issue = candidate.issue_code
            )
         ),
         f.brand_suggestion,
         (select suggested.name from public.product_brands suggested where suggested.id = f.brand_suggestion),
         f.updated_at
    from flagged f
   order by coalesce(nullif(btrim(f.website_name), ''), f.name), f.id;
end;
$$;

revoke all on function public.catalog_web_items_v1(uuid) from public, anon;
grant execute on function public.catalog_web_items_v1(uuid) to authenticated;
