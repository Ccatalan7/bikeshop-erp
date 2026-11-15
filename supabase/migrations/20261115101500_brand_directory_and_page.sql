-- Marcas: el directorio con sus cifras y la página de una marca (2026-11-15).
--
-- El dueño pidió rehacer Inventario › Marcas en lista y tarjetas, y que el
-- buscador encuentre la marca y lleve a «ver todo eso». Antes la lista leía
-- sólo `product_brands`: nombre, país y sitio, que 279 de 280 marcas no
-- tienen. Las dos lecturas de aquí traen lo que sí dice algo de una marca, en
-- un viaje cada una:
--
-- * `brand_directory_v1`: cada marca que ve el taller (las suyas y las del
--   catálogo compartido) con sus productos activos, cuántos tienen stock, las
--   unidades y su valor a costo, cuántos están en la web, lo vendido en 12
--   meses y la última venta, hasta tres fotos de sus productos más vendidos y
--   el proveedor que se nombra primero con cuántos más la traen.
-- * `brand_page_v1`: una marca con sus productos, sus proveedores, los
--   trabajos que usaron sus productos y los archivos recibidos que la nombran.
--
-- Lo vendido es lo que salió por venta (`sale`, `sales_invoice`) menos lo que
-- volvió por anulación (`sales_invoice_reversal`), por producto y nunca bajo
-- cero. El proveedor que se nombra primero es el representante oficial; si no
-- hay, al que más documentos de compra recibidos o pagados se le hicieron, y en
-- empate el de la compra más reciente. Los demás son los que la traen
-- (`supplier_brands`) más a los que se les compró.
begin;

create or replace function public.brand_directory_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_result jsonb;
begin
  if v_role <> 'service_role' and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required' using errcode = '42501';
  end if;

  with brands as (
    select b.id, b.name, b.logo_url, b.is_active, b.tenant_id is null as shared
      from public.product_brands b
     where b.tenant_id = p_tenant_id
        or b.tenant_id is null
  ),
  goods as (
    select p.id,
           p.brand_id,
           p.is_active,
           lower(p.name) as sort_name,
           greatest(coalesce(p.stock_quantity, 0), 0) as units,
           coalesce(p.cost, 0) as cost,
           coalesce(p.is_published, false) or coalesce(p.show_on_website, false) as on_web,
           coalesce(nullif(btrim(p.image_url_optimized), ''), nullif(btrim(p.image_url), '')) as image
      from public.products p
     where p.tenant_id = p_tenant_id
       and p.brand_id is not null
       and coalesce(p.is_service, false) = false
  ),
  sold as (
    select sm.product_id,
           greatest(
             coalesce(sum(abs(sm.quantity)) filter (
               where sm.movement_type in ('sale', 'sales_invoice')), 0)
             - coalesce(sum(abs(sm.quantity)) filter (
               where sm.movement_type = 'sales_invoice_reversal'), 0),
             0) as units,
           max(sm.created_at) filter (
             where sm.movement_type in ('sale', 'sales_invoice')) as last_sale
      from public.stock_movements sm
     where sm.tenant_id = p_tenant_id
       and sm.created_at >= now() - interval '12 months'
       and sm.movement_type in ('sale', 'sales_invoice', 'sales_invoice_reversal')
     group by sm.product_id
  ),
  per_brand as (
    select g.brand_id,
           count(*) filter (where g.is_active)::integer as products,
           count(*) filter (where g.is_active and g.units > 0)::integer as in_stock,
           coalesce(sum(g.units) filter (where g.is_active), 0) as units,
           round(coalesce(sum(g.units * g.cost) filter (where g.is_active), 0)) as stock_cost,
           count(*) filter (where g.is_active and g.on_web)::integer as on_web,
           coalesce(sum(s.units), 0) as sold_12m,
           max(s.last_sale) as last_sale
      from goods g
      left join sold s on s.product_id = g.id
     group by g.brand_id
  ),
  photos as (
    select ranked.brand_id,
           jsonb_agg(ranked.image order by ranked.position) as images
      from (
        select g.brand_id,
               g.image,
               row_number() over (
                 partition by g.brand_id
                 order by coalesce(s.units, 0) desc, g.units desc, g.sort_name, g.id
               ) as position
          from goods g
          left join sold s on s.product_id = g.id
         where g.is_active
           and g.image is not null
      ) ranked
     where ranked.position <= 3
     group by ranked.brand_id
  ),
  carriers as (
    select sb.brand_id, sb.supplier_id, sb.official
      from public.supplier_brands sb
     where sb.tenant_id = p_tenant_id
       and sb.removed_at is null
  ),
  bought as (
    select p.brand_id,
           pi.supplier_id,
           count(distinct pi.id)::integer as purchases,
           max(pi.date)::date as last_purchase
      from public.purchase_invoice_lines l
      join public.purchase_invoices pi
        on pi.id = l.purchase_invoice_id and pi.tenant_id = l.tenant_id
      join public.products p on p.id = l.product_id and p.tenant_id = l.tenant_id
     where l.tenant_id = p_tenant_id
       and p.brand_id is not null
       and pi.supplier_id is not null
       and pi.status in ('received', 'paid')
     group by p.brand_id, pi.supplier_id
  ),
  links as (
    select coalesce(c.brand_id, bo.brand_id) as brand_id,
           coalesce(c.supplier_id, bo.supplier_id) as supplier_id,
           coalesce(c.official, false) as official,
           coalesce(bo.purchases, 0) as purchases,
           bo.last_purchase
      from carriers c
      full join bought bo
        on bo.brand_id = c.brand_id and bo.supplier_id = c.supplier_id
  ),
  ranked_links as (
    select l.brand_id,
           l.supplier_id,
           l.official,
           s.name,
           s.image_url,
           row_number() over (
             partition by l.brand_id
             order by l.official desc, coalesce(s.is_active, true) desc,
                      l.purchases desc, l.last_purchase desc nulls last,
                      lower(s.name), l.supplier_id
           ) as position,
           count(*) over (partition by l.brand_id)::integer as total
      from links l
      join public.suppliers s on s.id = l.supplier_id and s.tenant_id = p_tenant_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id,
           'name', b.name,
           'logo_url', b.logo_url,
           'is_active', b.is_active,
           'shared', b.shared,
           'products', coalesce(pb.products, 0),
           'in_stock', coalesce(pb.in_stock, 0),
           'units', coalesce(pb.units, 0),
           'stock_cost', coalesce(pb.stock_cost, 0),
           'on_web', coalesce(pb.on_web, 0),
           'sold_12m', coalesce(pb.sold_12m, 0),
           'last_sale', pb.last_sale,
           'images', coalesce(ph.images, '[]'::jsonb),
           'supplier', case
             when rl.supplier_id is null then null
             else jsonb_build_object(
               'id', rl.supplier_id,
               'name', rl.name,
               'official', rl.official,
               'image_url', rl.image_url)
           end,
           'supplier_count', coalesce(rl.total, 0)
         ) order by lower(b.name), b.id), '[]'::jsonb)
    into v_result
    from brands b
    left join per_brand pb on pb.brand_id = b.id
    left join photos ph on ph.brand_id = b.id
    left join ranked_links rl on rl.brand_id = b.id and rl.position = 1;

  return v_result;
end;
$$;

revoke all on function public.brand_directory_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.brand_directory_v1(uuid)
  to authenticated, service_role;

comment on function public.brand_directory_v1(uuid) is
  'Las marcas que ve un taller (suyas y del catálogo compartido) con products (activos), in_stock, units, stock_cost, on_web, sold_12m (venta menos anulación, 12 meses), last_sale, images (hasta 3 fotos de lo más vendido), supplier (oficial, o al que más se le compró) y supplier_count.';

create or replace function public.brand_page_v1(
  p_tenant_id uuid,
  p_brand_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_brand public.product_brands%rowtype;
  v_words text;
  v_products jsonb;
  v_totals jsonb;
  v_suppliers jsonb;
  v_jobs jsonb;
  v_files jsonb;
begin
  if v_role <> 'service_role' and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required' using errcode = '42501';
  end if;

  select b.*
    into v_brand
    from public.product_brands b
   where b.id = p_brand_id
     and (b.tenant_id = p_tenant_id or b.tenant_id is null);
  if not found then
    return null;
  end if;

  with goods as (
    select p.id,
           p.name,
           p.sku,
           p.price,
           p.stock_quantity,
           greatest(coalesce(p.stock_quantity, 0), 0) as units,
           coalesce(p.cost, 0) as cost,
           coalesce(p.is_published, false) or coalesce(p.show_on_website, false) as on_web,
           coalesce(nullif(btrim(p.image_url_optimized), ''), nullif(btrim(p.image_url), '')) as image
      from public.products p
     where p.tenant_id = p_tenant_id
       and p.brand_id = p_brand_id
       and coalesce(p.is_service, false) = false
       and p.is_active
  ),
  sold as (
    select sm.product_id,
           greatest(
             coalesce(sum(abs(sm.quantity)) filter (
               where sm.movement_type in ('sale', 'sales_invoice')), 0)
             - coalesce(sum(abs(sm.quantity)) filter (
               where sm.movement_type = 'sales_invoice_reversal'), 0),
             0) as units,
           max(sm.created_at) filter (
             where sm.movement_type in ('sale', 'sales_invoice')) as last_sale
      from public.stock_movements sm
      join public.products p on p.id = sm.product_id and p.tenant_id = sm.tenant_id
     where sm.tenant_id = p_tenant_id
       and p.brand_id = p_brand_id
       and sm.created_at >= now() - interval '12 months'
       and sm.movement_type in ('sale', 'sales_invoice', 'sales_invoice_reversal')
     group by sm.product_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', g.id,
           'name', g.name,
           'sku', g.sku,
           'price', g.price,
           'stock_quantity', g.stock_quantity,
           'cost', g.cost,
           'on_web', g.on_web,
           'image', g.image,
           'sold_12m', coalesce(s.units, 0),
           'last_sale', s.last_sale
         ) order by coalesce(s.units, 0) desc, g.units desc, lower(g.name), g.id), '[]'::jsonb),
         jsonb_build_object(
           'products', count(*)::integer,
           'in_stock', (count(*) filter (where g.units > 0))::integer,
           'units', coalesce(sum(g.units), 0),
           'stock_cost', round(coalesce(sum(g.units * g.cost), 0)),
           'on_web', (count(*) filter (where g.on_web))::integer,
           -- Lo vendido cuenta también productos que después se archivaron.
           'sold_12m', (select coalesce(sum(x.units), 0) from sold x),
           'last_sale', (select max(x.last_sale) from sold x)
         )
    into v_products, v_totals
    from goods g
    left join sold s on s.product_id = g.id;

  with carriers as (
    select sb.supplier_id, sb.official
      from public.supplier_brands sb
     where sb.tenant_id = p_tenant_id
       and sb.brand_id = p_brand_id
       and sb.removed_at is null
  ),
  bought as (
    select pi.supplier_id,
           count(distinct pi.id)::integer as purchases,
           coalesce(sum(l.quantity), 0) as units,
           max(pi.date)::date as last_purchase
      from public.purchase_invoice_lines l
      join public.purchase_invoices pi
        on pi.id = l.purchase_invoice_id and pi.tenant_id = l.tenant_id
      join public.products p on p.id = l.product_id and p.tenant_id = l.tenant_id
     where l.tenant_id = p_tenant_id
       and p.brand_id = p_brand_id
       and pi.supplier_id is not null
       and pi.status in ('received', 'paid')
     group by pi.supplier_id
  ),
  links as (
    select coalesce(c.supplier_id, bo.supplier_id) as supplier_id,
           c.supplier_id is not null as carries,
           coalesce(c.official, false) as official,
           coalesce(bo.purchases, 0) as purchases,
           coalesce(bo.units, 0) as units,
           bo.last_purchase
      from carriers c
      full join bought bo on bo.supplier_id = c.supplier_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'supplier_id', l.supplier_id,
           'name', s.name,
           'image_url', s.image_url,
           'is_active', coalesce(s.is_active, true),
           'official', l.official,
           'carries', l.carries,
           'purchases', l.purchases,
           'units', l.units,
           'last_purchase', l.last_purchase
         ) order by l.official desc, coalesce(s.is_active, true) desc, l.purchases desc,
                    l.last_purchase desc nulls last, lower(s.name), l.supplier_id), '[]'::jsonb)
    into v_suppliers
    from links l
    join public.suppliers s on s.id = l.supplier_id and s.tenant_id = p_tenant_id;

  with used as (
    select i.job_id,
           count(*)::integer as lines,
           (array_agg(coalesce(nullif(btrim(i.product_name), ''), p.name)
                      order by i.created_at, i.id))[1] as first_item,
           (array_agg(i.job_bike_id order by i.created_at, i.id)
              filter (where i.job_bike_id is not null))[1] as job_bike_id
      from public.mechanic_job_items i
      join public.products p on p.id = i.product_id and p.tenant_id = i.tenant_id
     where i.tenant_id = p_tenant_id
       and p.brand_id = p_brand_id
     group by i.job_id
  ),
  jobs as (
    select j.id,
           j.job_number,
           j.status,
           j.arrival_date,
           j.delivered_at,
           j.updated_at,
           c.name as customer_name,
           nullif(btrim(concat_ws(' ', bk.brand, bk.model)), '') as bike,
           u.lines,
           u.first_item
      from used u
      join public.mechanic_jobs j on j.id = u.job_id and j.tenant_id = p_tenant_id
      left join public.mechanic_job_bikes jb
        on jb.id = u.job_bike_id and jb.tenant_id = p_tenant_id
      left join public.bikes bk
        on bk.id = coalesce(jb.bike_id, j.bike_id) and bk.tenant_id = p_tenant_id
      left join public.customers c on c.id = j.customer_id and c.tenant_id = p_tenant_id
     where j.deleted_at is null
  ),
  recent as (
    select *
      from jobs
     order by coalesce(delivered_at, arrival_date, updated_at) desc nulls last, id
     limit 50
  )
  select jsonb_build_object(
           'total', (select count(*) from jobs)::integer,
           'recent', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'id', r.id,
                      'job_number', r.job_number,
                      'status', r.status,
                      'arrival_date', r.arrival_date,
                      'delivered_at', r.delivered_at,
                      'customer_name', r.customer_name,
                      'bike', r.bike,
                      'lines', r.lines,
                      'first_item', r.first_item
                    ) order by coalesce(r.delivered_at, r.arrival_date, r.updated_at) desc nulls last, r.id)
               from recent r), '[]'::jsonb))
    into v_jobs;

  -- Un archivo nombra la marca cuando su nombre la contiene como palabra
  -- entera: «A_MAXXIS_OCT_2026.pdf» nombra a Maxxis y «VPN.pdf» no nombra a VP.
  v_words := btrim(regexp_replace(lower(v_brand.name), '[^a-z0-9]+', ' ', 'g'));
  if length(v_words) >= 2 then
    with named as (
      select a.id,
             a.conversation_id,
             a.storage_path,
             a.original_filename,
             a.extension,
             a.declared_mime_type,
             a.attached_at,
             a.size_bytes
        from public.messaging_attachments a
       where a.tenant_id = p_tenant_id
         and a.status = 'attached'
         and ' ' || btrim(regexp_replace(lower(coalesce(a.original_filename, '')),
                                         '[^a-z0-9]+', ' ', 'g')) || ' '
             like '% ' || v_words || ' %'
    ),
    recent as (
      select * from named order by attached_at desc nulls last, id limit 20
    )
    select jsonb_build_object(
             'total', (select count(*) from named)::integer,
             'recent', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'id', r.id,
                        'storage_path', r.storage_path,
                        'original_filename', r.original_filename,
                        'extension', r.extension,
                        'declared_mime_type', r.declared_mime_type,
                        'attached_at', r.attached_at,
                        'size_bytes', r.size_bytes,
                        -- La misma forma que el buscador recibe por PostgREST,
                        -- para que el archivo se nombre con las mismas palabras.
                        'conversations', (
                          select jsonb_build_object(
                                   'title', cv.title,
                                   'counterparty_type', cv.counterparty_type,
                                   'channel', cv.channel,
                                   'whatsapp_conversation_bindings', coalesce((
                                     select jsonb_agg(jsonb_build_object(
                                              'contact_name', w.contact_name,
                                              'supplier_contacts', (
                                                select jsonb_build_object('name', sc.name)
                                                  from public.supplier_contacts sc
                                                 where sc.id = w.supplier_contact_id
                                                   and sc.tenant_id = p_tenant_id)
                                            ) order by w.created_at, w.id)
                                       from public.whatsapp_conversation_bindings w
                                      where w.conversation_id = cv.id
                                        and w.tenant_id = p_tenant_id), '[]'::jsonb))
                            from public.conversations cv
                           where cv.id = r.conversation_id
                             and cv.tenant_id = p_tenant_id)
                      ) order by r.attached_at desc nulls last, r.id)
                 from recent r), '[]'::jsonb))
      into v_files;
  end if;

  return jsonb_build_object(
    'brand', jsonb_build_object(
      'id', v_brand.id,
      'tenant_id', v_brand.tenant_id,
      'name', v_brand.name,
      'description', v_brand.description,
      'website', v_brand.website,
      'country', v_brand.country,
      'logo_url', v_brand.logo_url,
      'is_active', v_brand.is_active,
      'shared', v_brand.tenant_id is null,
      'created_at', v_brand.created_at,
      'updated_at', v_brand.updated_at),
    'totals', v_totals,
    'products', v_products,
    'suppliers', v_suppliers,
    'jobs', v_jobs,
    'files', coalesce(v_files, jsonb_build_object('total', 0, 'recent', '[]'::jsonb)));
end;
$$;

revoke all on function public.brand_page_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.brand_page_v1(uuid, uuid)
  to authenticated, service_role;

comment on function public.brand_page_v1(uuid, uuid) is
  'Una marca que ve el taller: brand, totals, products (activos, lo más vendido primero), suppliers (los que la traen y a los que se les compró, el oficial primero), jobs (total y hasta 50 de los más recientes que usaron sus productos) y files (total y hasta 20 archivos recibidos que la nombran como palabra entera). null si el taller no la ve.';

commit;
