-- Las marcas de cada proveedor (dueño, 2026-11-03): «en la ficha de
-- proveedores… todavía no le hemos asignado marcas. Y eso es grave… las
-- marcas son mucho de los proveedores, dicen mucho de ellos… un dato duro,
-- que sean universales, que se puedan ser paralelos dentro de los
-- proveedores. Obviamente, por ejemplo, Shimano lo puede tener Comercial
-- Ciclo y Andes Industrial… y que eso pueda servir para generar funciones».
--
-- Un proveedor trae marcas y una marca la traen varios proveedores: la
-- relación es (proveedor, marca), con la marca del catálogo (product_brands),
-- la misma de los productos, la tienda y las cotizaciones. Cada fila dice de
-- dónde salió —el catálogo del proveedor, nuestras compras o una persona—,
-- si el proveedor es el representante oficial de la marca, y se quita sin
-- borrarse (removed_at): queda lo que traía antes y lo que una persona quitó
-- no vuelve solo.
--
-- Lo que compramos se vuelve regla: cada noche, la marca de lo que se le
-- compró a un proveedor (facturas recibidas o pagadas) y la de los productos
-- que lo tienen como proveedor se le asigna si no la tenía. «Genérico» y las
-- marcas que nombran un país o una tienda no son una marca.
--
-- Sólo agrega: nada de la 1.0.45 lee esto.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------------------
-- 1. La relación
-- ---------------------------------------------------------------------------

create or replace function public.product_brand_is_placeholder_internal(p_name text)
returns boolean
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select lower(btrim(coalesce(p_name, ''))) in (
    '', 'genérico', 'generico', 'genérica', 'generica', 'sin marca',
    'china', 'taiwán', 'taiwan', 'aliexpress'
  );
$$;

revoke all on function public.product_brand_is_placeholder_internal(text)
  from public, anon, authenticated, service_role;

comment on function public.product_brand_is_placeholder_internal(text) is
  'Una «marca» que no nombra a un fabricante: Genérico, Sin marca, un país (China, Taiwán) o la tienda donde se compró (AliExpress). No se asigna a un proveedor.';

create table if not exists public.supplier_brands (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  brand_id uuid not null references public.product_brands(id) on delete cascade,
  official boolean not null default false,
  source text not null default 'manual'
    constraint supplier_brands_source_check
    check (source in ('catalog', 'records', 'manual')),
  evidence jsonb not null default '{}'::jsonb
    constraint supplier_brands_evidence_check
    check (
      jsonb_typeof(evidence) = 'object'
      and not public.jsonb_contains_sensitive_key(evidence)
    ),
  added_at timestamptz not null default clock_timestamp(),
  added_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  removed_at timestamptz,
  removed_by uuid references auth.users(id) on delete set null,
  constraint supplier_brands_pkey primary key (tenant_id, supplier_id, brand_id),
  constraint supplier_brands_supplier_fkey foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade
);

create index if not exists supplier_brands_by_brand
  on public.supplier_brands (tenant_id, brand_id)
  where removed_at is null;

comment on table public.supplier_brands is
  'Las marcas que trae cada proveedor (una marca la traen varios). source: catalog (su catálogo), records (nuestras compras o productos que lo tienen como proveedor), manual (una persona). official: representante oficial de la marca. removed_at: ya no la trae, o una persona la quitó; la noche no la vuelve a poner.';
comment on column public.supplier_brands.evidence is
  'De dónde salió: {"catalog": {"url", "checked_on"}} o {"records": {"purchase_lines", "products", "last_purchase"}}.';

create or replace function public.supplier_brands_guard()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_brand_tenant uuid;
  v_brand_name text;
  v_brand_active boolean;
  v_becomes_current boolean;
begin
  select b.tenant_id, b.name, b.is_active
    into v_brand_tenant, v_brand_name, v_brand_active
    from public.product_brands b
   where b.id = new.brand_id;
  if not found
     or (v_brand_tenant is not null and v_brand_tenant <> new.tenant_id) then
    raise exception 'Brand not found for this tenant'
      using errcode = '23503', hint = 'supplier_brand_not_found';
  end if;

  v_becomes_current := new.removed_at is null
    and (tg_op = 'INSERT' or old.removed_at is not null
         or old.brand_id is distinct from new.brand_id);
  if v_becomes_current and not v_brand_active then
    raise exception 'Brand is inactive'
      using errcode = '23514', hint = 'supplier_brand_inactive';
  end if;
  if v_becomes_current and public.product_brand_is_placeholder_internal(v_brand_name) then
    raise exception '% is not a manufacturer', v_brand_name
      using errcode = '23514', hint = 'supplier_brand_placeholder';
  end if;

  new.updated_at := clock_timestamp();
  return new;
end;
$$;

revoke all on function public.supplier_brands_guard()
  from public, anon, authenticated, service_role;

drop trigger if exists supplier_brands_guard on public.supplier_brands;
create trigger supplier_brands_guard
  before insert or update on public.supplier_brands
  for each row execute function public.supplier_brands_guard();

alter table public.supplier_brands enable row level security;
revoke all on public.supplier_brands from public, anon, authenticated;
grant select on public.supplier_brands to authenticated;
grant select, insert, update, delete on public.supplier_brands to service_role;
drop policy if exists supplier_brands_tenant_read on public.supplier_brands;
create policy supplier_brands_tenant_read on public.supplier_brands
  for select to authenticated using (public.is_active_tenant_member(tenant_id));

-- ---------------------------------------------------------------------------
-- 2. Lecturas
-- ---------------------------------------------------------------------------

-- Las marcas de un proveedor, con lo que dicen nuestros registros: cuántos
-- productos de la marca hay en el catálogo y cuántas líneas de factura se le
-- compraron a él. Primero el representante oficial, luego lo más comprado.
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
    select p.brand_id, count(*)::integer as lines, max(pi.date)::date as last_purchase
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
           'purchase_lines', coalesce(bo.lines, 0),
           'last_purchase', bo.last_purchase
         ) order by c.official desc, coalesce(bo.lines, 0) desc,
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
  'Las marcas que trae un proveedor: brand_id, name, official, source, evidence, added_at, products (de la marca en el catálogo), purchase_lines y last_purchase (lo que se le compró a él, facturas recibidas o pagadas).';

-- Quién trae una marca: primero el representante oficial, luego los activos
-- y lo último que se les compró.
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
    select pi.supplier_id, count(*)::integer as lines, max(pi.date)::date as last_purchase
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
  'Quién trae una marca: supplier_id, name, image_url, is_active, official, source, purchase_lines y last_purchase (de esa marca a ese proveedor).';

-- Para el buscador del directorio: las marcas de todos los proveedores en una
-- sola lectura, {supplier_id: {"brands": [...], "official": [...]}}.
create or replace function public.supplier_brand_index_v1(p_tenant_id uuid)
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

  select coalesce(jsonb_object_agg(x.supplier_id::text, jsonb_build_object(
           'brands', x.brands, 'official', x.official)), '{}'::jsonb)
    into v_result
    from (
      select sb.supplier_id,
             jsonb_agg(b.name order by lower(b.name)) as brands,
             coalesce(jsonb_agg(b.name order by lower(b.name))
               filter (where sb.official), '[]'::jsonb) as official
        from public.supplier_brands sb
        join public.product_brands b on b.id = sb.brand_id
       where sb.tenant_id = p_tenant_id
         and sb.removed_at is null
       group by sb.supplier_id
    ) x;

  return v_result;
end;
$$;

revoke all on function public.supplier_brand_index_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.supplier_brand_index_v1(uuid)
  to authenticated, service_role;

comment on function public.supplier_brand_index_v1(uuid) is
  'Las marcas de cada proveedor, para buscar proveedores por marca: {supplier_id: {"brands": [nombres], "official": [nombres]}}.';

-- ---------------------------------------------------------------------------
-- 3. Comandos: agregar (o marcar oficial) y quitar
-- ---------------------------------------------------------------------------

-- Agrega una marca a un proveedor, o la vuelve a poner si se había quitado;
-- p_official cambia «representante oficial» (null lo deja como estaba).
-- Devuelve sus marcas, como supplier_brands_v1.
create or replace function public.save_supplier_brand_v1(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_brand_id uuid,
  p_official boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_actor uuid := auth.uid();
begin
  if v_role <> 'service_role' and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required' using errcode = '42501';
  end if;
  if p_supplier_id is null or not exists (
    select 1 from public.suppliers s
     where s.tenant_id = p_tenant_id and s.id = p_supplier_id
  ) then
    raise exception 'Supplier not found in tenant'
      using errcode = 'P0002', hint = 'supplier_not_found';
  end if;
  if p_brand_id is null then
    raise exception 'Brand is required'
      using errcode = '22023', hint = 'supplier_brand_not_found';
  end if;

  insert into public.supplier_brands as sb (
    tenant_id, supplier_id, brand_id, official, source, added_by
  ) values (
    p_tenant_id, p_supplier_id, p_brand_id, coalesce(p_official, false), 'manual', v_actor
  )
  on conflict (tenant_id, supplier_id, brand_id) do update
     set official = case when sb.removed_at is null
                         then coalesce(p_official, sb.official)
                         else coalesce(p_official, false) end,
         source = case when sb.removed_at is null then sb.source else 'manual' end,
         evidence = case when sb.removed_at is null then sb.evidence else '{}'::jsonb end,
         added_at = case when sb.removed_at is null then sb.added_at else clock_timestamp() end,
         added_by = case when sb.removed_at is null then sb.added_by else v_actor end,
         removed_at = null,
         removed_by = null;

  return public.supplier_brands_v1(p_tenant_id, p_supplier_id);
end;
$$;

revoke all on function public.save_supplier_brand_v1(uuid, uuid, uuid, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.save_supplier_brand_v1(uuid, uuid, uuid, boolean)
  to authenticated, service_role;

comment on function public.save_supplier_brand_v1(uuid, uuid, uuid, boolean) is
  'Agrega una marca a un proveedor (o la repone) y cambia «representante oficial» si p_official no es null. Lo puede hacer cualquier miembro activo del taller, como el perfil del proveedor. Devuelve supplier_brands_v1.';

-- Quita una marca: la fila queda con removed_at y la noche no la repone.
create or replace function public.remove_supplier_brand_v1(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_brand_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
begin
  if v_role <> 'service_role' and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required' using errcode = '42501';
  end if;
  if p_supplier_id is null or not exists (
    select 1 from public.suppliers s
     where s.tenant_id = p_tenant_id and s.id = p_supplier_id
  ) then
    raise exception 'Supplier not found in tenant'
      using errcode = 'P0002', hint = 'supplier_not_found';
  end if;

  update public.supplier_brands sb
     set removed_at = clock_timestamp(),
         removed_by = auth.uid(),
         official = false
   where sb.tenant_id = p_tenant_id
     and sb.supplier_id = p_supplier_id
     and sb.brand_id = p_brand_id
     and sb.removed_at is null;

  return public.supplier_brands_v1(p_tenant_id, p_supplier_id);
end;
$$;

revoke all on function public.remove_supplier_brand_v1(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.remove_supplier_brand_v1(uuid, uuid, uuid)
  to authenticated, service_role;

comment on function public.remove_supplier_brand_v1(uuid, uuid, uuid) is
  'Quita una marca de un proveedor sin borrarla (removed_at): la asignación nocturna no la repone. Devuelve supplier_brands_v1.';

-- ---------------------------------------------------------------------------
-- 4. Lo que compramos se vuelve regla
-- ---------------------------------------------------------------------------

-- Asigna a cada proveedor la marca de lo que se le compró (facturas recibidas
-- o pagadas) y la de los productos que lo tienen como proveedor, si no tenía
-- esa fila. Nunca repone lo que una persona quitó. Devuelve cuántas agregó.
create or replace function public.refresh_supplier_brands_from_records_internal(
  p_tenant_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_added integer;
begin
  with bought as (
    select pi.supplier_id, p.brand_id,
           count(*)::integer as lines, max(pi.date)::date as last_purchase
      from public.purchase_invoice_lines l
      join public.purchase_invoices pi
        on pi.id = l.purchase_invoice_id and pi.tenant_id = l.tenant_id
      join public.products p on p.id = l.product_id and p.tenant_id = l.tenant_id
     where l.tenant_id = p_tenant_id
       and pi.status in ('received', 'paid')
       and pi.supplier_id is not null
       and p.brand_id is not null
     group by pi.supplier_id, p.brand_id
  ),
  listed as (
    select p.supplier_id, p.brand_id, count(*)::integer as products
      from public.products p
     where p.tenant_id = p_tenant_id
       and p.supplier_id is not null
       and p.brand_id is not null
       and coalesce(p.product_type, 'product') <> 'service'
     group by p.supplier_id, p.brand_id
  ),
  pairs as (
    select coalesce(bo.supplier_id, li.supplier_id) as supplier_id,
           coalesce(bo.brand_id, li.brand_id) as brand_id,
           coalesce(bo.lines, 0) as lines,
           bo.last_purchase,
           coalesce(li.products, 0) as products
      from bought bo
      full join listed li
        on li.supplier_id = bo.supplier_id and li.brand_id = bo.brand_id
  ),
  inserted as (
    insert into public.supplier_brands (tenant_id, supplier_id, brand_id, source, evidence)
    select p_tenant_id, x.supplier_id, x.brand_id, 'records',
           jsonb_build_object('records', jsonb_strip_nulls(jsonb_build_object(
             'purchase_lines', x.lines,
             'products', x.products,
             'last_purchase', x.last_purchase
           )))
      from pairs x
      join public.suppliers s on s.tenant_id = p_tenant_id and s.id = x.supplier_id
      join public.product_brands b on b.id = x.brand_id
     where (b.tenant_id is null or b.tenant_id = p_tenant_id)
       and b.is_active
       and not public.product_brand_is_placeholder_internal(b.name)
    on conflict (tenant_id, supplier_id, brand_id) do nothing
    returning 1
  )
  select count(*)::integer into v_added from inserted;

  return v_added;
end;
$$;

revoke all on function public.refresh_supplier_brands_from_records_internal(uuid)
  from public, anon, authenticated, service_role;

comment on function public.refresh_supplier_brands_from_records_internal(uuid) is
  'Asigna a cada proveedor las marcas de lo que se le compró (facturas recibidas o pagadas) y de los productos que lo tienen como proveedor, como source = records. No toca las filas que existen (tampoco las quitadas). Devuelve cuántas agregó.';

create or replace function public.refresh_supplier_brands_from_records_all_internal()
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant record;
  v_added integer := 0;
begin
  for v_tenant in select t.id from public.tenants t loop
    v_added := v_added + public.refresh_supplier_brands_from_records_internal(v_tenant.id);
  end loop;
  return v_added;
end;
$$;

revoke all on function public.refresh_supplier_brands_from_records_all_internal()
  from public, anon, authenticated, service_role;

comment on function public.refresh_supplier_brands_from_records_all_internal() is
  'La asignación nocturna de marcas por compras, para todos los talleres (cron vinabike_supplier_brands_from_records).';

select public.refresh_supplier_brands_from_records_all_internal();

do $$
declare
  v_job record;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron unavailable; supplier brands from records were not scheduled';
    return;
  end if;
  for v_job in select jobid from cron.job where jobname = 'vinabike_supplier_brands_from_records' loop
    perform cron.unschedule(v_job.jobid);
  end loop;
  -- 07:17 UTC: 04:17 en Chile continental en verano, 03:17 en invierno.
  perform cron.schedule(
    'vinabike_supplier_brands_from_records',
    '17 7 * * *',
    $job$select public.refresh_supplier_brands_from_records_all_internal()$job$
  );
end;
$$;

commit;
