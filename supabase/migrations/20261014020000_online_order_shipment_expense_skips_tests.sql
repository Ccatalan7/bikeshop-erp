-- Un pedido de prueba no registra el gasto de su envío.
--
-- 20261014010000 registra lo pagado al transportista como gasto al despachar
-- (o después, desde la sección ENVÍO). Un pedido marcado como prueba
-- (`online_orders.is_test`) se despacha con boletas de prueba: su costo no es
-- un gasto del taller y no debe llegar a la contabilidad. El mismo
-- `online_order_shipment_create_expense`, con ese control al principio.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

create or replace function public.online_order_shipment_create_expense(
  p_shipment public.online_order_shipments,
  p_order public.online_orders,
  p_expense jsonb,
  p_actor uuid
)
returns public.expenses
language plpgsql
set search_path = public, pg_temp
as $function$
declare
  v_plan jsonb;
  v_method public.payment_methods%rowtype;
  v_method_id uuid;
  v_document_type text;
  v_document_number text;
  v_total numeric;
  v_net numeric;
  v_tax numeric;
  v_expense public.expenses%rowtype;
  v_expense_id uuid := gen_random_uuid();
  v_issue_date timestamptz;
  v_description text;
  v_notes text;
  v_extension text;
begin
  if jsonb_typeof(coalesce(p_expense, 'null'::jsonb)) <> 'object'
     or exists (
       select 1 from jsonb_object_keys(p_expense) key
        where key not in ('payment_method_id', 'document_type', 'document_number')
     ) then
    raise exception 'Expense accepts payment_method_id, document_type and document_number'
      using errcode = '22023';
  end if;

  -- Un pedido de prueba no mueve la contabilidad (2026-10-13: WEB-26-00012
  -- se despachó con una boleta de prueba y su costo no es un gasto).
  if coalesce(p_order.is_test, false) then
    raise exception 'Un pedido de prueba no registra gastos.' using errcode = '23514';
  end if;

  v_total := round(coalesce(p_shipment.cost, 0));
  if v_total <= 0 then
    raise exception 'Escribe lo pagado al transportista para registrar el gasto.'
      using errcode = '23514';
  end if;

  v_plan := public.online_order_shipment_expense_plan(p_shipment.tenant_id, p_shipment.carrier);
  if v_plan->>'account_id' is null then
    raise exception 'No hay una cuenta de gastos de transporte. Créala en Contabilidad o registra el gasto en Gastos.'
      using errcode = '23514';
  end if;

  begin
    v_method_id := coalesce(
      nullif(btrim(coalesce(p_expense->>'payment_method_id', '')), ''),
      v_plan->>'payment_method_id'
    )::uuid;
  exception when others then
    raise exception 'Expense payment_method_id is not an id' using errcode = '22023';
  end;
  select method.* into v_method
    from public.payment_methods method
   where method.id = v_method_id
     and method.tenant_id = p_shipment.tenant_id
     and method.is_active
     and method.account_id is not null
     and coalesce(method.usage_scope, 'both') in ('outbound', 'both');
  if not found then
    raise exception 'Elige con qué se pagó el envío.' using errcode = '22023';
  end if;

  v_document_type := coalesce(
    nullif(btrim(coalesce(p_expense->>'document_type', '')), ''),
    v_plan->>'document_type'
  );
  if v_document_type not in ('receipt', 'invoice') then
    raise exception 'Expense document_type is receipt or invoice' using errcode = '22023';
  end if;
  v_document_number := nullif(btrim(coalesce(p_expense->>'document_number', '')), '');
  if char_length(coalesce(v_document_number, '')) > 40 then
    raise exception 'El número de la boleta o factura es demasiado largo.' using errcode = '22023';
  end if;

  -- Con factura, el IVA es crédito; con boleta, todo es gasto.
  if v_document_type = 'invoice' then
    v_net := round(v_total / 1.19);
    v_tax := v_total - v_net;
  else
    v_net := v_total;
    v_tax := 0;
  end if;

  v_issue_date := coalesce(p_shipment.admitted_at, now());
  v_description := format('Despacho %s · %s', p_order.order_number, p_shipment.carrier);
  v_notes := concat_ws(' · ',
    format('Envío del pedido web %s', p_order.order_number),
    p_shipment.carrier,
    case when p_shipment.tracking_number is not null
      then format('seguimiento %s', p_shipment.tracking_number) end
  );

  insert into public.expenses (
    id, tenant_id, expense_number, category_id, supplier_id, supplier_name,
    supplier_rut, document_type, document_number, issue_date, currency,
    exchange_rate, posting_status, payment_status, subtotal, tax_amount,
    total_amount, amount_paid, balance, notes, reference, approval_status,
    approved_by, approved_at, payment_account_id, payment_method_id,
    created_by
  ) values (
    v_expense_id, p_shipment.tenant_id, '',
    (v_plan->>'category_id')::uuid,
    (v_plan->>'supplier_id')::uuid,
    v_plan->>'supplier_name',
    v_plan->>'supplier_rut',
    v_document_type, v_document_number, v_issue_date, 'CLP',
    1, 'draft', 'paid', 0, 0,
    0, 0, 0, v_notes, p_order.order_number, 'approved',
    p_actor, now(), v_method.account_id, v_method.id,
    p_actor
  );
  insert into public.expense_lines (
    tenant_id, expense_id, line_index, account_id, account_code,
    account_name, description, quantity, unit_price, subtotal, tax_rate,
    tax_amount, total
  ) values (
    p_shipment.tenant_id, v_expense_id, 0,
    (v_plan->>'account_id')::uuid, v_plan->>'account_code', v_plan->>'account_name',
    v_description, 1, v_net, v_net,
    case when v_document_type = 'invoice' then 19 else 0 end,
    v_tax, v_total
  );
  -- Contabilizado y pagado como el gasto rápido: un asiento contra la caja.
  update public.expenses expense
     set posting_status = 'posted',
         posted_at = coalesce(expense.posted_at, v_issue_date),
         updated_at = now()
   where expense.id = v_expense_id;

  if p_shipment.receipt_path is not null then
    v_extension := lower(substring(p_shipment.receipt_path from '\.([A-Za-z0-9]+)$'));
    insert into public.expense_attachments (
      tenant_id, expense_id, file_name, file_url, file_type, uploaded_by
    ) values (
      p_shipment.tenant_id, v_expense_id,
      format('Boleta de envío %s.%s', p_order.order_number, coalesce(v_extension, 'jpg')),
      p_shipment.receipt_path,
      case v_extension
        when 'pdf' then 'application/pdf'
        when 'png' then 'image/png'
        when 'webp' then 'image/webp'
        when 'heic' then 'image/heic'
        when 'heif' then 'image/heif'
        else 'image/jpeg'
      end,
      p_actor
    );
  end if;

  update public.online_order_shipments shipment
     set expense_id = v_expense_id
   where shipment.id = p_shipment.id;

  select expense.* into v_expense
    from public.expenses expense
   where expense.id = v_expense_id;
  return v_expense;
end;
$function$;

revoke all on function public.online_order_shipment_create_expense(
  public.online_order_shipments, public.online_orders, jsonb, uuid
) from public, anon, authenticated, service_role;

commit;
