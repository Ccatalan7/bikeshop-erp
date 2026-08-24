-- Qué confirmar con un proveedor, y cómo se anota lo que dijo.
--
-- Dos funciones que el chequeo necesita y que no pueden vivir en el navegador:
-- QUÉ códigos vale la pena preguntar, y cómo se guarda la respuesta.
--
-- **Qué se pregunta.** No todo el catálogo: los productos de ESE proveedor que
-- están en cero o bajo su mínimo, ordenados por lo que de verdad se movió. Un
-- chequeo es lento —una navegación por código— y preguntar por lo que no se
-- vende gasta minutos del operador para confirmar algo que no va a comprar.
--
-- **Cómo se anota.** Los cuatro estados no se mezclan nunca:
--
--   available       el portal lo mostró y hay unidades, o lo mostró y ese
--                   portal no publica cantidad (RBX): presencia y precio.
--   out_of_stock    el portal lo mostró y dijo cero. Es un cero DEMOSTRADO.
--   not_found       el portal no lo mostró. No prueba que no lo venda.
--   session_expired no había sesión. Jamás se cuenta como cero.
--   unreadable      la página respondió algo que la sonda no supo leer.

begin;

create or replace function public.supplier_availability_targets_v1(
  p_supplier_id uuid,
  p_limit integer default 12
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '9000ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_items jsonb;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_limit not between 1 and 40 then
    raise exception 'Invalid target arguments' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.suppliers supplier
    where supplier.id = p_supplier_id and supplier.tenant_id = v_tenant_id
  ) then
    raise exception 'Supplier not found' using errcode = 'P0002';
  end if;

  with candidates as (
    select product.id,
      product.name,
      product.supplier_code,
      public.inventory_available_quantity_v1(product.tenant_id, product.id)
        available,
      greatest(coalesce(product.min_stock_level, 0), 0) minimum,
      -- Lo que se movió en 90 días: sin esto el chequeo gasta minutos en
      -- productos que nadie pide.
      coalesce((
        select sum(line.quantity)
        from public.sales_invoice_lines line
        join public.sales_invoices invoice on invoice.id = line.invoice_id
        where invoice.tenant_id = product.tenant_id
          and line.product_id = product.id
          and invoice.date >= now() - interval '90 days'
      ), 0) sold_recently
    from public.products product
    where product.tenant_id = v_tenant_id
      and product.supplier_id = p_supplier_id
      and product.is_active is true
      and nullif(btrim(coalesce(product.supplier_code, '')), '') is not null
  ), ranked as (
    select candidates.*,
      row_number() over (
        order by (case when available <= 0 then 0 else 1 end),
          sold_recently desc, available, name
      ) rank
    from candidates
    where available <= greatest(minimum, 0)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'productId', id,
      'name', name,
      'supplierCode', supplier_code,
      'available', available,
      'minimumStock', minimum,
      'soldRecently', sold_recently
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb)
  into v_items
  from ranked;

  return jsonb_build_object(
    'asOf', clock_timestamp(),
    'supplierId', p_supplier_id,
    'items', v_items,
    'resultCount', jsonb_array_length(v_items)
  );
end;
$$;

revoke all on function public.supplier_availability_targets_v1(uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.supplier_availability_targets_v1(uuid, integer)
  to authenticated;

create or replace function public.record_supplier_availability_check_v1(
  p_supplier_id uuid,
  p_product_id uuid,
  p_supplier_code text,
  p_status text,
  p_price_net numeric default null,
  p_stock_quantity numeric default null,
  p_source_url text default null,
  p_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_id uuid;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_status not in (
      'available', 'out_of_stock', 'not_found',
      'session_expired', 'unreadable', 'probe_missing'
    )
     or octet_length(coalesce(p_source_url, '')) > 400
     or octet_length(coalesce(p_supplier_code, '')) > 80
     or jsonb_typeof(coalesce(p_evidence, 'null'::jsonb)) <> 'object'
     or octet_length(coalesce(p_evidence, '{}'::jsonb)::text) > 8192 then
    raise exception 'Invalid availability check' using errcode = '22023';
  end if;
  -- **Una sesión caída no trae números.** Aceptar precio o cantidad junto a
  -- `session_expired` dejaría entrar un cero que nadie demostró.
  if p_status in ('session_expired', 'not_found', 'unreadable')
     and (p_price_net is not null or p_stock_quantity is not null) then
    raise exception 'Invalid availability check' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.suppliers supplier
    where supplier.id = p_supplier_id and supplier.tenant_id = v_tenant_id
  ) then
    raise exception 'Supplier not found' using errcode = 'P0002';
  end if;
  if p_product_id is not null and not exists (
    select 1 from public.products product
    where product.id = p_product_id and product.tenant_id = v_tenant_id
  ) then
    raise exception 'Product not found' using errcode = 'P0002';
  end if;

  insert into public.supplier_availability_checks (
    tenant_id, supplier_id, product_id, supplier_code, status,
    price_net, stock_quantity, source_url, evidence, created_by
  ) values (
    v_tenant_id, p_supplier_id, p_product_id,
    nullif(btrim(coalesce(p_supplier_code, '')), ''),
    p_status, p_price_net, p_stock_quantity,
    nullif(btrim(coalesce(p_source_url, '')), ''),
    coalesce(p_evidence, '{}'::jsonb), auth.uid()
  )
  returning id into v_id;

  return jsonb_build_object('status', 'recorded', 'checkId', v_id);
end;
$$;

revoke all on function public.record_supplier_availability_check_v1(
  uuid, uuid, text, text, numeric, numeric, text, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.record_supplier_availability_check_v1(
  uuid, uuid, text, text, numeric, numeric, text, jsonb
) to authenticated;

commit;
