-- El pedido que se le manda al proveedor se guarda como pedido.
--
-- **No como documento de compra.** `purchase_invoices` guarda lo que el
-- proveedor NOS emitió: sus tipos son «Factura», «Boleta», «Ticket», y su flujo
-- contable asume una deuda ya contraída. Un pedido nuestro no es nada de eso —
-- todavía no existe factura, ni deuda, ni mercadería—. Meterlo ahí lo haría
-- aparecer en «Documentos de compra» como un documento recibido que nadie
-- emitió, y la contabilidad lo trataría como una compra.
--
-- `purchase_orders` ya existe con la forma correcta y está en cero: nadie la
-- usaba. Esta función es su puerta.
--
-- Guardar y enviar son dos estados distintos y a propósito: `draft` es lo que
-- el operador está armando, `ordered` es lo que ya salió. Si fuera uno solo, no
-- habría forma de saber si el proveedor vio el pedido.

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
  v_actor uuid := auth.uid();
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if jsonb_typeof(p_lines) <> 'array' then
    raise exception 'Invalid order lines' using errcode = '22023';
  end if;
  select jsonb_array_length(p_lines) into v_count;
  -- Un pedido vacío no se guarda: dejaría un folio reservado sobre nada, y el
  -- proveedor recibiría un número que no compra ni pide nada.
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

  select
    coalesce(sum((line->>'quantity')::numeric
      * (line->>'unitCostNet')::numeric), 0)
  into v_net
  from jsonb_array_elements(p_lines) line;
  v_iva := round(v_net * 0.19);
  v_total := v_net + v_iva;

  if v_order_id is null then
    -- El folio se arma en el servidor. Si lo propusiera el cliente, dos
    -- pestañas abiertas producirían el mismo número.
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
      -- Un pedido que ya salió no se reescribe por debajo: el proveedor tiene
      -- una copia y cambiarla en silencio deja dos verdades del mismo folio.
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

-- Marcar el pedido como enviado. Va aparte de guardar porque son dos hechos
-- distintos: uno es del taller y el otro involucra al proveedor.
create or replace function public.mark_purchase_order_sent_v1(
  p_order_id uuid,
  p_channel text default 'whatsapp'
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
  v_number text;
  v_note text;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if coalesce(btrim(p_channel), '') = '' or length(p_channel) > 40 then
    raise exception 'Invalid channel' using errcode = '22023';
  end if;

  update public.purchase_orders orders
  set status = 'ordered',
    notes = case
      when coalesce(btrim(orders.notes), '') = ''
        then 'Enviado por ' || p_channel
      else orders.notes || E'\n' || 'Enviado por ' || p_channel
    end
  where orders.id = p_order_id
    and orders.tenant_id = v_tenant_id
    and orders.status = 'draft'
  returning orders.order_number, orders.notes into v_number, v_note;

  if v_number is null then
    raise exception 'Order not found or not a draft' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'orderId', p_order_id,
    'orderNumber', v_number,
    'status', 'ordered',
    'sentAt', clock_timestamp()
  );
end;
$$;

revoke all on function public.save_purchase_order_draft_v1(uuid, jsonb, uuid, text, date)
  from public;
grant execute on function public.save_purchase_order_draft_v1(uuid, jsonb, uuid, text, date)
  to authenticated;
revoke all on function public.mark_purchase_order_sent_v1(uuid, text) from public;
grant execute on function public.mark_purchase_order_sent_v1(uuid, text)
  to authenticated;

commit;

-- Sonda de las compuertas, para poder comprobarlas desde una lectura.
--
-- Guardar un pedido escribe, y la verificación corre en sólo lectura. Sin
-- esto, lo único comprobable sería que la función existe. Acá se la llama con
-- los casos que DEBEN ser rechazados y se informa qué código devolvió cada
-- uno: si una compuerta dejara pasar el caso, el error sería el de la
-- transacción de sólo lectura y no el suyo, y se vería la diferencia.
begin;

create or replace function public.purchase_order_guard_probe_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_result jsonb := '{}'::jsonb;
  v_supplier uuid;
begin
  select id into v_supplier from public.suppliers
  where tenant_id = public.user_tenant_id() order by name limit 1;

  begin
    perform public.save_purchase_order_draft_v1(v_supplier, '[]'::jsonb);
    v_result := v_result || jsonb_build_object('sinLineas', 'NO RECHAZÓ');
  exception when others then
    v_result := v_result || jsonb_build_object('sinLineas', sqlstate);
  end;

  begin
    perform public.save_purchase_order_draft_v1(
      '00000000-0000-0000-0000-000000000000'::uuid,
      jsonb_build_array(jsonb_build_object(
        'name', 'x', 'quantity', 1, 'unitCostNet', 1))
    );
    v_result := v_result || jsonb_build_object('proveedorAjeno', 'NO RECHAZÓ');
  exception when others then
    v_result := v_result || jsonb_build_object('proveedorAjeno', sqlstate);
  end;

  begin
    perform public.mark_purchase_order_sent_v1(
      '00000000-0000-0000-0000-000000000000'::uuid);
    v_result := v_result || jsonb_build_object('pedidoAjeno', 'NO RECHAZÓ');
  exception when others then
    v_result := v_result || jsonb_build_object('pedidoAjeno', sqlstate);
  end;

  return v_result;
end;
$$;

revoke all on function public.purchase_order_guard_probe_v1() from public;
grant execute on function public.purchase_order_guard_probe_v1() to authenticated;

commit;
