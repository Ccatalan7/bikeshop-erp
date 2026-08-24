-- El autor del pedido se anota sólo si existe.
--
-- `purchase_orders.created_by` apunta a `users_profiles`, una tabla **legada y
-- vacía**: la app mantiene `user_profiles` (singular), que es otra. Poner ahí
-- el `auth.uid()` viola la clave foránea y el pedido no se guarda nunca —
-- fallaba en el primer intento real, con el mensaje tapado por un «no se pudo
-- guardar» de la pantalla.
--
-- Dejarlo nulo no pierde trazabilidad: la fila ya lleva tenant, proveedor y
-- fecha, y el registro de quién hizo qué vive en otra parte. Anotar un id que
-- no resuelve a ninguna persona sería peor que no anotar nada. Si algún día esa
-- tabla se puebla, la anotación empieza a funcionar sola.

begin;

create or replace function public.save_purchase_order_draft_v1(
  p_supplier_id uuid,
  p_lines jsonb,
  p_order_id uuid default null,
  p_note text default null,
  p_expected_date date default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '9000ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_company_id uuid;
  v_order_id uuid := p_order_id;
  v_order_number text;
  v_status public.purchase_status;
  v_net numeric := 0;
  v_iva numeric := 0;
  v_total numeric := 0;
  v_count integer;
  v_actor uuid;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Invalid order lines' using errcode = '22023';
  end if;
  select jsonb_array_length(p_lines) into v_count;
  if v_count < 1 or v_count > 200 then
    raise exception 'A purchase order needs between 1 and 200 lines'
      using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.suppliers supplier
    where supplier.id = p_supplier_id and supplier.tenant_id = v_tenant_id
  ) then
    raise exception 'Supplier not found' using errcode = 'P0002';
  end if;

  select company.id into v_company_id
  from public.companies company
  where company.tenant_id = v_tenant_id
  order by company.created_at asc nulls last
  limit 1;
  if v_company_id is null then
    raise exception 'No company for tenant' using errcode = 'P0002';
  end if;

  -- Sólo si resuelve a una persona de verdad en la tabla a la que apunta la
  -- clave foránea.
  select profile.id into v_actor
  from public.users_profiles profile
  where profile.id = auth.uid();

  select
    coalesce(sum((line->>'quantity')::numeric
      * (line->>'unitCostNet')::numeric), 0)
  into v_net
  from jsonb_array_elements(p_lines) line;
  v_iva := round(v_net * 0.19);
  v_total := v_net + v_iva;

  if v_order_id is null then
    select 'PED-' || to_char(now() at time zone 'America/Santiago', 'YYYYMM')
      || '-' || lpad((
        coalesce(max(nullif(regexp_replace(orders.order_number,
          '^PED-\d{6}-', ''), '')::integer), 0) + 1)::text, 4, '0')
    into v_order_number
    from public.purchase_orders orders
    where orders.tenant_id = v_tenant_id
      and orders.order_number ~ ('^PED-' ||
        to_char(now() at time zone 'America/Santiago', 'YYYYMM') || '-\d{4}$');

    insert into public.purchase_orders (
      company_id, tenant_id, supplier_id, status, order_number, order_date,
      expected_date, subtotal, tax_amount, total, notes, created_by
    ) values (
      v_company_id, v_tenant_id, p_supplier_id, 'draft', v_order_number,
      (now() at time zone 'America/Santiago')::date, p_expected_date,
      v_net, v_iva, v_total, p_note, v_actor
    )
    returning id, order_number, status
    into v_order_id, v_order_number, v_status;
  else
    update public.purchase_orders orders
    set supplier_id = p_supplier_id,
      subtotal = v_net,
      tax_amount = v_iva,
      total = v_total,
      notes = p_note,
      expected_date = p_expected_date
    where orders.id = v_order_id
      and orders.tenant_id = v_tenant_id
      and orders.status = 'draft'
    returning orders.order_number, orders.status
    into v_order_number, v_status;
    if v_order_number is null then
      raise exception 'Order not found or already sent' using errcode = 'P0002';
    end if;
    delete from public.purchase_order_items item
    where item.purchase_order_id = v_order_id
      and item.tenant_id = v_tenant_id;
  end if;

  insert into public.purchase_order_items (
    purchase_order_id, tenant_id, product_id, description, quantity,
    unit_cost, tax_rate, total
  )
  select v_order_id,
    v_tenant_id,
    nullif(line->>'productId', '')::uuid,
    coalesce(nullif(btrim(line->>'name'), ''), 'Sin descripción'),
    (line->>'quantity')::numeric,
    (line->>'unitCostNet')::numeric,
    0.19,
    (line->>'quantity')::numeric * (line->>'unitCostNet')::numeric
  from jsonb_array_elements(p_lines) line;

  return jsonb_build_object(
    'orderId', v_order_id,
    'orderNumber', v_order_number,
    'status', v_status,
    'netTotal', v_net,
    'ivaAmount', v_iva,
    'total', v_total,
    'lineCount', v_count,
    'savedAt', clock_timestamp()
  );
end;
$$;

commit;
