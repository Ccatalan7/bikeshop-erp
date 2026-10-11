-- «La marca está en el nombre» también enlaza la marca escrita a mano, y lee
-- sólo el nombre que se ve.
--
-- Medido en producción el 2026-10-11, después de 20261011020000:
-- - 39 productos a la venta tenían la marca escrita como texto («Shimano»,
--   «ZTTO», «Maxxis», «Bucklos»…) y el nombre la decía, pero no estaban
--   enlazados a la marca. La tienda declaraba la marca a Google desde el
--   texto, pero el filtro de marcas de la tienda no los encontraba y «Por
--   resolver» los contaba «a la venta sin marca», sin arreglo de un toque.
--   Ahora la sugerencia vale para todo lo que no tiene una marca real
--   enlazada, siempre que una marca escrita a mano no diga otra.
-- - La cámara 6938112671129 recibió la sugerencia «ORNATE» de una nota en su
--   nombre del ERP («NO ES EXACTAMENTE LA MISMA: 1.50X2.2 ORNATE»): una nota
--   de inventario, no la marca de la ficha. La regla lee el nombre que ve el
--   cliente (el nombre web, o el del ERP si no hay).

-- ¿Una marca escrita (o nada) está de acuerdo con la sugerida?
create or replace function public.catalog_brand_agrees_v1(
  p_written text,
  p_brand_id uuid
)
returns boolean
language sql
stable
set search_path = pg_catalog, public, pg_temp
as $$
  select not public.catalog_is_public_brand_v1(p_written)
      or exists (
           select 1
             from public.product_brands b
            where b.id = p_brand_id
              and btrim(public.catalog_brand_text_v1(b.name))
                  = btrim(public.catalog_brand_text_v1(p_written)));
$$;

revoke all on function public.catalog_brand_agrees_v1(text, uuid) from public, anon;
grant execute on function public.catalog_brand_agrees_v1(text, uuid) to authenticated;

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
  ), suggested as (
    -- A la venta sin una marca real enlazada, y el nombre que se ve dice cuál
    -- es (20261011010000, 20261011030000).
    select st.*,
           case
             when st.item_state in ('venta', 'agotado')
                  and st.item_kind in ('product', 'kit')
                  and not public.catalog_is_public_brand_v1(st.linked_brand_name)
               then public.catalog_brand_from_words_v1(
                 coalesce(nullif(btrim(st.website_name), ''), st.name),
                 (select brand_words.ids from brand_words),
                 (select brand_words.keys from brand_words))
           end as named_brand
      from stated st
  ), branded as (
    -- Una marca escrita a mano que dice otra cosa no se pisa.
    select sg.*,
           case
             when sg.named_brand is not null
                  and public.catalog_brand_agrees_v1(sg.brand, sg.named_brand)
                  and public.catalog_brand_agrees_v1(sg.website_merchant_brand, sg.named_brand)
               then sg.named_brand
           end as brand_suggestion
      from suggested sg
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


-- «Usar la marca del nombre», con la misma regla que la lista.
create or replace function public.catalog_apply_brand_from_name_v1(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_changed jsonb;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);

  with target as (
    select p.id,
           p.brand_id as previous_brand_id,
           p.brand as previous_brand,
           public.catalog_brand_from_name_v1(
             p_tenant_id,
             coalesce(nullif(btrim(p.website_name), ''), p.name)) as suggestion,
           p.brand as written_brand,
           p.website_merchant_brand as merchant_brand
      from public.products p
      left join public.product_brands linked_brand
        on linked_brand.id = p.brand_id
       and linked_brand.is_active
       and (linked_brand.tenant_id is null or linked_brand.tenant_id = p.tenant_id)
     where p.tenant_id = p_tenant_id
       and p.id = any (coalesce(p_product_ids, '{}'::uuid[]))
       and not public.catalog_is_public_brand_v1(linked_brand.name)
     for update of p
  ), changed as (
    update public.products p
       set brand_id = target.suggestion,
           brand = suggested.name
      from target
      join public.product_brands suggested on suggested.id = target.suggestion
     where p.id = target.id
       and p.tenant_id = p_tenant_id
       and public.catalog_brand_agrees_v1(target.written_brand, target.suggestion)
       and public.catalog_brand_agrees_v1(target.merchant_brand, target.suggestion)
    returning p.id, target.previous_brand_id, target.previous_brand, p.brand_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', changed.id,
           'previous_brand_id', changed.previous_brand_id,
           'previous_brand', changed.previous_brand,
           'brand_id', changed.brand_id)), '[]'::jsonb)
    into v_changed
    from changed;

  return jsonb_build_object('changed', v_changed);
end;
$$;

revoke all on function public.catalog_apply_brand_from_name_v1(uuid, uuid[]) from public, anon;
grant execute on function public.catalog_apply_brand_from_name_v1(uuid, uuid[]) to authenticated;
