-- «Compras» de una marca a un proveedor son documentos, no líneas
-- (20261103090000).
--
-- La ficha decía «Shimano · 6 compras» contando líneas de factura: tres
-- pastillas y un cable en un mismo documento eran «4 compras». El taller
-- cuenta compras como documentos —el Resumen de la misma ficha dice «6
-- documentos»—, así que las dos lecturas agregan `purchases` (documentos de
-- compra recibidos o pagados con la marca) y ordenan por él. `purchase_lines`
-- sigue para quien lo lea.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.supplier_brands_v1(
  p_tenant_id uuid,
  p_supplier_id uuid
)
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

  with current_brands as (
    select sb.*, b.name
      from public.supplier_brands sb
      join public.product_brands b on b.id = sb.brand_id
     where sb.tenant_id = p_tenant_id
       and sb.supplier_id = p_supplier_id
       and sb.removed_at is null
  ),
  bought as (
    select p.brand_id,
           count(distinct pi.id)::integer as purchases,
           count(*)::integer as lines,
           max(pi.date)::date as last_purchase
      from public.purchase_invoice_lines l
      join public.purchase_invoices pi
        on pi.id = l.purchase_invoice_id and pi.tenant_id = l.tenant_id
      join public.products p on p.id = l.product_id and p.tenant_id = l.tenant_id
     where l.tenant_id = p_tenant_id
       and pi.supplier_id = p_supplier_id
       and pi.status in ('received', 'paid')
       and p.brand_id in (select brand_id from current_brands)
     group by p.brand_id
  ),
  listed as (
    select p.brand_id, count(*)::integer as products
      from public.products p
     where p.tenant_id = p_tenant_id
       and coalesce(p.is_active, true)
       and coalesce(p.product_type, 'product') <> 'service'
       and p.brand_id in (select brand_id from current_brands)
     group by p.brand_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'brand_id', c.brand_id,
           'name', c.name,
           'official', c.official,
           'source', c.source,
           'evidence', c.evidence,
           'added_at', c.added_at,
           'products', coalesce(l.products, 0),
           'purchases', coalesce(bo.purchases, 0),
           'purchase_lines', coalesce(bo.lines, 0),
           'last_purchase', bo.last_purchase
         ) order by c.official desc, coalesce(bo.purchases, 0) desc,
                    bo.last_purchase desc nulls last,
                    coalesce(l.products, 0) desc, lower(c.name)), '[]'::jsonb)
    into v_result
    from current_brands c
    left join bought bo on bo.brand_id = c.brand_id
    left join listed l on l.brand_id = c.brand_id;

  return v_result;
end;
$$;

revoke all on function public.supplier_brands_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.supplier_brands_v1(uuid, uuid)
  to authenticated, service_role;

comment on function public.supplier_brands_v1(uuid, uuid) is
  'Las marcas que trae un proveedor: brand_id, name, official, source, evidence, added_at, products (de la marca en el catálogo), purchases (documentos de compra recibidos o pagados con la marca), purchase_lines y last_purchase.';

create or replace function public.brand_suppliers_v1(
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
  v_result jsonb;
begin
  if v_role <> 'service_role' and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required' using errcode = '42501';
  end if;

  with carriers as (
    select sb.supplier_id, sb.official, sb.source, s.name, s.image_url, s.is_active
      from public.supplier_brands sb
      join public.suppliers s on s.tenant_id = sb.tenant_id and s.id = sb.supplier_id
     where sb.tenant_id = p_tenant_id
       and sb.brand_id = p_brand_id
       and sb.removed_at is null
  ),
  bought as (
    select pi.supplier_id,
           count(distinct pi.id)::integer as purchases,
           count(*)::integer as lines,
           max(pi.date)::date as last_purchase
      from public.purchase_invoice_lines l
      join public.purchase_invoices pi
        on pi.id = l.purchase_invoice_id and pi.tenant_id = l.tenant_id
      join public.products p on p.id = l.product_id and p.tenant_id = l.tenant_id
     where l.tenant_id = p_tenant_id
       and p.brand_id = p_brand_id
       and pi.status in ('received', 'paid')
       and pi.supplier_id in (select supplier_id from carriers)
     group by pi.supplier_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'supplier_id', c.supplier_id,
           'name', c.name,
           'image_url', c.image_url,
           'is_active', coalesce(c.is_active, true),
           'official', c.official,
           'source', c.source,
           'purchases', coalesce(bo.purchases, 0),
           'purchase_lines', coalesce(bo.lines, 0),
           'last_purchase', bo.last_purchase
         ) order by c.official desc, coalesce(c.is_active, true) desc,
                    bo.last_purchase desc nulls last, lower(c.name)), '[]'::jsonb)
    into v_result
    from carriers c
    left join bought bo on bo.supplier_id = c.supplier_id;

  return v_result;
end;
$$;

revoke all on function public.brand_suppliers_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.brand_suppliers_v1(uuid, uuid)
  to authenticated, service_role;

comment on function public.brand_suppliers_v1(uuid, uuid) is
  'Quién trae una marca: supplier_id, name, image_url, is_active, official, source, purchases (documentos de compra de esa marca a ese proveedor), purchase_lines y last_purchase.';

commit;
