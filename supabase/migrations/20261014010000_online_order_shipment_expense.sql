-- El costo del envío queda como gasto al registrar el despacho.
--
-- 2026-10-13, el dueño, mirando «Registrar despacho» de WEB-26-00021: «agrega
-- la opción de dejar el gasto registrado automáticamente, para no tener que
-- agregarlo de nuevo en los gastos rápidos». Y en la misma captura la IA leyó
-- «Admitido el 13/10/2020» en una boleta de ese día.
--
--   · `online_order_shipment_expense_plan` decide dónde cae el gasto de un
--     transportista: el proveedor (por nombre, razón social o alias), la
--     cuenta y la categoría (la plantilla de gasto del proveedor si existe;
--     si no, la categoría «Gastos por Transporte», como el gasto rápido), y
--     el medio de pago y el documento por defecto (la plantilla, o el último
--     gasto de ese proveedor; si no, efectivo y boleta).
--   · `online_order_shipment_create_expense` lo registra como el gasto rápido:
--     contabilizado y pagado con el medio elegido (un asiento: gasto e IVA
--     contra la caja), IVA sólo con factura, la foto de la boleta adjunta y el
--     número del pedido como referencia. El despacho guarda el gasto.
--   · `record_online_order_shipment` recibe `p_expense`: el despacho, el gasto
--     y el correo van en una sola transacción; si el gasto no se puede
--     registrar, no se registra nada.
--   · `record_online_order_shipment_expense` registra el gasto de un despacho
--     que se registró sin él (una sola vez por despacho).
--   · `online_order_shipment_expense_options` le muestra a la app el plan y
--     los medios de pago antes de registrar.
--   · La fecha de admisión no puede ser anterior al pedido ni futura (un día
--     de holgura): la revisan el registro y la vista previa del correo.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- 1. El despacho recuerda su gasto.
-- ---------------------------------------------------------------------------
alter table public.online_order_shipments
  add column if not exists expense_id uuid references public.expenses(id) on delete set null;

create unique index if not exists online_order_shipments_expense_key
  on public.online_order_shipments (expense_id)
  where expense_id is not null;

comment on column public.online_order_shipments.expense_id is
  'The expense that records what the carrier charged, created with the shipment or later from its card.';

comment on table public.online_order_shipments is
  'Shipping receipts of online orders: carrier, service, tracking code, admission, cost, the receipt photo in vinabike-files, what the AI read from it and the expense of its cost. Written only by record_online_order_shipment and record_online_order_shipment_expense.';

-- ---------------------------------------------------------------------------
-- 2. La fecha de admisión tiene que poder ser cierta.
-- ---------------------------------------------------------------------------
create or replace function public.online_order_shipment_check_admission(
  p_admitted_at timestamptz,
  p_order_created_at timestamptz
)
returns void
language plpgsql
stable
set search_path = public, pg_temp
as $function$
begin
  if p_admitted_at is null then
    return;
  end if;
  if p_admitted_at < p_order_created_at - interval '1 day'
     or p_admitted_at > now() + interval '1 day' then
    raise exception 'La fecha de admisión (%) no calza: es anterior al pedido o futura. Revísala en la boleta.',
      to_char(p_admitted_at at time zone 'America/Santiago', 'DD/MM/YYYY HH24:MI')
      using errcode = '22023';
  end if;
end;
$function$;

revoke all on function public.online_order_shipment_check_admission(timestamptz, timestamptz)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Dónde cae el gasto de un transportista.
-- ---------------------------------------------------------------------------
create or replace function public.online_order_shipment_plain(p_text text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $function$
  select regexp_replace(
    lower(translate(coalesce(p_text, ''), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')),
    '[^a-z0-9]', '', 'g'
  );
$function$;

revoke all on function public.online_order_shipment_plain(text)
  from public, anon, authenticated, service_role;

create or replace function public.online_order_shipment_expense_plan(
  p_tenant_id uuid,
  p_carrier text
)
returns jsonb
language plpgsql
stable
set search_path = public, pg_temp
as $function$
declare
  v_carrier text := public.online_order_shipment_plain(p_carrier);
  v_supplier public.suppliers%rowtype;
  v_template public.expense_templates%rowtype;
  v_last public.expenses%rowtype;
  v_last_account_id uuid;
  v_account public.accounts%rowtype;
  v_category public.expense_categories%rowtype;
  v_method_id uuid;
  v_document_type text;
begin
  -- El proveedor: el mismo nombre, razón social, nombre de fantasía o alias;
  -- si no, uno que contenga al otro («Correos» y «Correos de Chile»).
  if v_carrier <> '' then
    select supplier.* into v_supplier
      from public.suppliers supplier
      cross join lateral (
        select public.online_order_shipment_plain(candidate) as plain
          from unnest(
            array[supplier.name, supplier.legal_name, supplier.trade_name]
              || coalesce(supplier.aliases, array[]::text[])
          ) candidate
         where nullif(btrim(coalesce(candidate, '')), '') is not null
      ) names
     where supplier.tenant_id = p_tenant_id
       and coalesce(supplier.is_active, true)
       and names.plain <> ''
       and (names.plain = v_carrier
            or strpos(names.plain, v_carrier) > 0
            or strpos(v_carrier, names.plain) > 0)
     order by (names.plain = v_carrier) desc, length(names.plain), supplier.created_at
     limit 1;
  end if;

  if v_supplier.id is not null then
    select template.* into v_template
      from public.expense_templates template
     where template.tenant_id = p_tenant_id
       and template.is_active
       and v_supplier.id in (template.default_supplier_id, template.trigger_supplier_id)
     order by template.priority, template.created_at
     limit 1;

    select expense.* into v_last
      from public.expenses expense
     where expense.tenant_id = p_tenant_id
       and expense.supplier_id = v_supplier.id
       and expense.posting_status = 'posted'
     order by expense.issue_date desc, expense.created_at desc
     limit 1;
  end if;

  -- La cuenta y la categoría: la plantilla del proveedor; si no, «Gastos por
  -- Transporte», la que elige el gasto rápido para un flete.
  if v_template.default_account_id is not null then
    select account.* into v_account
      from public.accounts account
     where account.id = v_template.default_account_id
       and account.tenant_id = p_tenant_id
       and coalesce(account.is_active, true);
    select category.* into v_category
      from public.expense_categories category
     where category.tenant_id = p_tenant_id
       and category.id = coalesce(v_template.default_category_id, v_template.trigger_category_id);
  end if;

  if v_account.id is null then
    select category.* into v_category
      from public.expense_categories category
      join public.accounts account
        on account.id = category.default_account_id
       and account.tenant_id = p_tenant_id
       and coalesce(account.is_active, true)
     where category.tenant_id = p_tenant_id
       and public.online_order_shipment_plain(category.name) = 'gastosportransporte'
     order by category.created_at
     limit 1;
    if v_category.id is not null then
      select account.* into v_account
        from public.accounts account
       where account.id = v_category.default_account_id;
    end if;
  end if;

  if v_account.id is null then
    select account.* into v_account
      from public.accounts account
     where account.tenant_id = p_tenant_id
       and coalesce(account.is_active, true)
       and account.type = 'expense'
       and public.online_order_shipment_plain(account.name) like '%transporte%'
     order by account.code
     limit 1;
  end if;

  if v_account.id is not null and v_category.id is null then
    select category.* into v_category
      from public.expense_categories category
     where category.tenant_id = p_tenant_id
       and category.default_account_id = v_account.id
     order by category.created_at
     limit 1;
  end if;

  -- El medio de pago y el documento: los de la plantilla o los de la última
  -- vez con este proveedor.
  v_method_id := coalesce(v_template.default_payment_method_id, v_last.payment_method_id);
  if v_method_id is not null and not exists (
    select 1 from public.payment_methods method
     where method.id = v_method_id
       and method.tenant_id = p_tenant_id
       and method.is_active
       and method.account_id is not null
       and coalesce(method.usage_scope, 'both') in ('outbound', 'both')
  ) then
    v_method_id := null;
  end if;
  if v_method_id is null then
    select method.id into v_method_id
      from public.payment_methods method
     where method.tenant_id = p_tenant_id
       and method.is_active
       and method.account_id is not null
       and coalesce(method.usage_scope, 'both') in ('outbound', 'both')
     order by (method.code = 'cash') desc, method.sort_order nulls last, method.name
     limit 1;
  end if;

  v_document_type := coalesce(
    nullif(v_template.default_document_type, ''),
    nullif(v_last.document_type, '')
  );
  if v_document_type is null or v_document_type not in ('receipt', 'invoice') then
    v_document_type := 'receipt';
  end if;

  return jsonb_build_object(
    'supplier_id', v_supplier.id,
    'supplier_name', coalesce(nullif(btrim(v_supplier.name), ''), nullif(btrim(p_carrier), '')),
    'supplier_rut', nullif(btrim(coalesce(v_supplier.rut, '')), ''),
    'account_id', v_account.id,
    'account_code', v_account.code,
    'account_name', v_account.name,
    'category_id', v_category.id,
    'category_name', v_category.name,
    'payment_method_id', v_method_id,
    'document_type', v_document_type
  );
end;
$function$;

revoke all on function public.online_order_shipment_expense_plan(uuid, text)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Registrar el gasto de un despacho, como el gasto rápido.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 5. Lo que la app muestra antes de registrar.
-- ---------------------------------------------------------------------------
create or replace function public.online_order_shipment_expense_options(p_carrier text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
begin
  if auth.uid() is null or v_tenant_id is null
     or not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Authenticated tenant context is required' using errcode = '42501';
  end if;

  return public.online_order_shipment_expense_plan(v_tenant_id, p_carrier)
    || jsonb_build_object(
      'payment_methods', coalesce((
        select jsonb_agg(
                 jsonb_build_object('id', method.id, 'code', method.code, 'name', method.name)
                 order by method.sort_order nulls last, method.name
               )
          from public.payment_methods method
         where method.tenant_id = v_tenant_id
           and method.is_active
           and method.account_id is not null
           and coalesce(method.usage_scope, 'both') in ('outbound', 'both')
      ), '[]'::jsonb)
    );
end;
$function$;

comment on function public.online_order_shipment_expense_options(text) is
  'Where the expense of a carrier''s shipping cost would go (supplier, account, category, default payment method and document) and the payment methods to choose from. Writes nothing.';

revoke all on function public.online_order_shipment_expense_options(text)
  from public, anon, authenticated, service_role;
grant execute on function public.online_order_shipment_expense_options(text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Registrar el despacho, ahora con su gasto y la fecha revisada.
-- ---------------------------------------------------------------------------
drop function if exists public.record_online_order_shipment(uuid, bigint, text, jsonb);

create or replace function public.record_online_order_shipment(
  p_order_id uuid,
  p_expected_version bigint,
  p_operation_key text,
  p_shipment jsonb,
  p_expense jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_existing public.online_order_shipments%rowtype;
  v_order public.online_orders%rowtype;
  v_shipment public.online_order_shipments%rowtype;
  v_draft public.online_order_shipments%rowtype;
  v_expense public.expenses%rowtype;
  v_transition jsonb;
begin
  if v_actor_id is null or v_tenant_id is null
     or not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Authenticated tenant context is required' using errcode = '42501';
  end if;
  if p_order_id is null or p_expected_version is null then
    raise exception 'Order and expected version are required' using errcode = '22023';
  end if;
  if v_operation_key = '' or char_length(v_operation_key) > 160 then
    raise exception 'A valid operation key is required' using errcode = '22023';
  end if;
  -- Reintento con la misma clave: el mismo recibo (y su gasto).
  select shipment.* into v_existing
    from public.online_order_shipments shipment
   where shipment.tenant_id = v_tenant_id
     and shipment.operation_key = v_operation_key;
  if found then
    if v_existing.order_id <> p_order_id then
      raise exception 'Operation key already belongs to another order' using errcode = '23505';
    end if;
    return to_jsonb(v_existing) || jsonb_build_object(
      'expense_number', (select expense_number from public.expenses
                          where id = v_existing.expense_id and tenant_id = v_tenant_id),
      'order_status', (select status from public.online_orders where id = p_order_id),
      'order_version', (select version from public.online_orders where id = p_order_id),
      'replay', true
    );
  end if;

  -- La boleta se lee igual aquí y en la vista previa del correo.
  v_draft := public.online_order_shipment_from_input(p_shipment);

  select orders.* into v_order
    from public.online_orders orders
   where orders.id = p_order_id
     and orders.tenant_id = v_tenant_id
   for update;
  if not found then
    raise exception 'Order not found or access denied: %', p_order_id using errcode = '42501';
  end if;
  if coalesce(v_order.delivery_type, '') <> 'shipping' then
    raise exception 'Sólo un pedido con despacho a domicilio se despacha.' using errcode = '23514';
  end if;
  if v_order.status not in ('confirmed', 'processing') then
    raise exception 'El pedido ya no espera despacho (está %).', v_order.status using errcode = '23514';
  end if;
  perform public.online_order_shipment_check_admission(v_draft.admitted_at, v_order.created_at);

  -- La foto tiene que estar en la carpeta de este pedido, y subida.
  if v_draft.receipt_path is not null then
    if v_draft.receipt_path !~ ('^' || v_tenant_id::text || '/evidence/online_order_shipment/'
                                || p_order_id::text || '/[A-Za-z0-9._-]+$') then
      raise exception 'The receipt must live in this order''s evidence folder' using errcode = '22023';
    end if;
    if not exists (
      select 1 from storage.objects object
       where object.bucket_id = 'vinabike-files'
         and object.name = v_draft.receipt_path
    ) then
      raise exception 'The receipt photo was not uploaded' using errcode = '22023';
    end if;
  end if;

  insert into public.online_order_shipments (
    tenant_id, order_id, carrier, carrier_code, service, tracking_number,
    tracking_url, admitted_at, branch, cost, receipt_path, extracted, checks,
    operation_key, created_by
  ) values (
    v_tenant_id, p_order_id, v_draft.carrier, v_draft.carrier_code, v_draft.service,
    v_draft.tracking_number, v_draft.tracking_url, v_draft.admitted_at, v_draft.branch,
    v_draft.cost, v_draft.receipt_path, v_draft.extracted, v_draft.checks,
    v_operation_key, v_actor_id
  ) returning * into v_shipment;

  -- El gasto del envío, en la misma transacción: o queda todo o nada.
  if p_expense is not null and jsonb_typeof(p_expense) <> 'null' then
    v_expense := public.online_order_shipment_create_expense(
      v_shipment, v_order, p_expense, v_actor_id
    );
    v_shipment.expense_id := v_expense.id;
  end if;

  -- El cambio de estado y su correo, por el comando de siempre.
  v_transition := public.transition_online_order_status(
    p_order_id,
    'shipped',
    p_expected_version,
    v_operation_key,
    v_draft.tracking_number,
    v_draft.tracking_url,
    v_draft.carrier,
    null
  );

  return to_jsonb(v_shipment) || jsonb_build_object(
    'expense_number', v_expense.expense_number,
    'order_status', (select status from public.online_orders where id = p_order_id),
    'order_version', (select version from public.online_orders where id = p_order_id),
    'replay', false
  );
end;
$$;

comment on function public.record_online_order_shipment(uuid, bigint, text, jsonb, jsonb) is
  'Records a shipping receipt for an online order, optionally the expense of its cost, and moves the order to shipped in one transaction; the shipped email follows from the status event. Idempotent per operation key.';

revoke all on function public.record_online_order_shipment(uuid, bigint, text, jsonb, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.record_online_order_shipment(uuid, bigint, text, jsonb, jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 7. El gasto de un despacho registrado sin él.
-- ---------------------------------------------------------------------------
create or replace function public.record_online_order_shipment_expense(
  p_shipment_id uuid,
  p_expense jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_shipment public.online_order_shipments%rowtype;
  v_order public.online_orders%rowtype;
  v_expense public.expenses%rowtype;
begin
  if v_actor_id is null or v_tenant_id is null
     or not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Authenticated tenant context is required' using errcode = '42501';
  end if;

  select shipment.* into v_shipment
    from public.online_order_shipments shipment
   where shipment.id = p_shipment_id
     and shipment.tenant_id = v_tenant_id
   for update;
  if not found then
    raise exception 'Shipment not found or access denied: %', p_shipment_id using errcode = '42501';
  end if;
  -- Un gasto por despacho: el segundo intento devuelve el primero.
  if v_shipment.expense_id is not null then
    return to_jsonb(v_shipment) || jsonb_build_object(
      'expense_number', (select expense_number from public.expenses
                          where id = v_shipment.expense_id and tenant_id = v_tenant_id),
      'replay', true
    );
  end if;

  select orders.* into v_order
    from public.online_orders orders
   where orders.id = v_shipment.order_id
     and orders.tenant_id = v_tenant_id;

  v_expense := public.online_order_shipment_create_expense(
    v_shipment, v_order, p_expense, v_actor_id
  );
  v_shipment.expense_id := v_expense.id;

  return to_jsonb(v_shipment) || jsonb_build_object(
    'expense_number', v_expense.expense_number,
    'replay', false
  );
end;
$function$;

comment on function public.record_online_order_shipment_expense(uuid, jsonb) is
  'Records the expense of a shipment registered without one, once per shipment (a repeat returns the first).';

revoke all on function public.record_online_order_shipment_expense(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.record_online_order_shipment_expense(uuid, jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 8. La vista previa del correo revisa la fecha igual que el registro.
-- ---------------------------------------------------------------------------
create or replace function public.preview_online_order_shipment_email(
  p_order_id uuid,
  p_shipment jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_order public.online_orders%rowtype;
  v_shipment public.online_order_shipments%rowtype;
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_recipient text;
  v_valid_recipient boolean;
  v_delivery_mode text := 'dry_run';
  v_suppression_reason text;
begin
  if auth.uid() is null or v_tenant_id is null
     or not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Authenticated tenant context is required' using errcode = '42501';
  end if;

  select orders.* into v_order
    from public.online_orders orders
   where orders.id = p_order_id
     and orders.tenant_id = v_tenant_id;
  if not found then
    raise exception 'Order not found or access denied: %', p_order_id using errcode = '42501';
  end if;
  if coalesce(v_order.delivery_type, '') <> 'shipping' then
    raise exception 'Sólo un pedido con despacho a domicilio se despacha.' using errcode = '23514';
  end if;
  if v_order.status not in ('confirmed', 'processing') then
    raise exception 'El pedido ya no espera despacho (está %).', v_order.status using errcode = '23514';
  end if;

  v_shipment := public.online_order_shipment_from_input(p_shipment);
  perform public.online_order_shipment_check_admission(v_shipment.admitted_at, v_order.created_at);
  v_shipment.tenant_id := v_tenant_id;
  v_shipment.order_id := v_order.id;

  -- El pedido como lo deja el despacho (transition_online_order_status).
  v_order.status := 'shipped';
  v_order.tracking_number := coalesce(v_shipment.tracking_number, v_order.tracking_number);
  v_order.tracking_url := coalesce(v_shipment.tracking_url, v_order.tracking_url);
  v_order.shipping_carrier := coalesce(v_shipment.carrier, v_order.shipping_carrier);

  select * into v_tenant
    from public.tenants
   where id = v_order.tenant_id;

  select * into v_settings
    from public.transactional_email_settings
   where tenant_id = v_order.tenant_id;
  if found and v_settings.enabled and v_settings.delivery_mode = 'send' then
    v_delivery_mode := 'send';
  end if;

  v_recipient := lower(btrim(coalesce(v_order.customer_email, '')));
  v_valid_recipient := v_recipient ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$';
  if v_valid_recipient then
    select suppression.reason into v_suppression_reason
      from public.transactional_email_suppressions suppression
     where suppression.tenant_id = v_order.tenant_id
       and suppression.email_sha256 = encode(
         extensions.digest(convert_to(v_recipient, 'UTF8'), 'sha256'),
         'hex'
       )
       and suppression.lifted_at is null
     order by suppression.suppressed_at desc
     limit 1;
  end if;

  return jsonb_build_object(
    'templateKey', 'shipped',
    'templateVersion', 1,
    'recipient', case when v_valid_recipient then v_recipient end,
    'recipientName', nullif(btrim(v_order.customer_name), ''),
    'senderName', nullif(btrim(coalesce(v_settings.from_name, v_tenant.shop_name)), ''),
    'senderEmail', nullif(lower(btrim(v_settings.from_email)), ''),
    'replyTo', nullif(lower(btrim(v_settings.reply_to_email)), ''),
    'subject', public.transactional_email_subject('shipped', v_order.order_number),
    'deliveryMode', v_delivery_mode,
    'suppressed', v_suppression_reason,
    'payload', public.transactional_email_render_payload(v_order, 'shipped', v_shipment)
  );
end;
$function$;

notify pgrst, 'reload schema';

commit;
