-- Deployment status: DEPLOYED 2026-07-11. Disabled-by-default purchase receipt kernel.
-- No tenant is activated and existing invoice/status inventory behavior is untouched.

begin;

create table if not exists public.purchase_receipt_control_settings (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  control_mode text not null default 'disabled'
    check (control_mode in ('disabled', 'shadow', 'enforce')),
  activated_at timestamp with time zone,
  activated_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.purchase_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete restrict,
  receipt_number text not null,
  status text not null default 'posted' check (status in ('posted', 'voided')),
  received_at timestamp with time zone not null,
  delivery_reference text,
  location_label text,
  notes text,
  idempotency_key text not null,
  operation_id uuid not null,
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default clock_timestamp(),
  unique (tenant_id, receipt_number),
  unique (tenant_id, idempotency_key),
  unique (tenant_id, id),
  foreign key (tenant_id, operation_id)
    references public.inventory_accounting_operations(tenant_id, id) on delete restrict
);

create table if not exists public.purchase_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  receipt_id uuid not null,
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete restrict,
  source_line_key text not null,
  source_line_index integer not null check (source_line_index >= 0),
  product_id uuid references public.products(id) on delete restrict,
  product_name text not null,
  product_sku text,
  purchase_treatment text not null default 'inventory',
  expected_quantity integer not null check (expected_quantity >= 0),
  previously_received_quantity integer not null check (previously_received_quantity >= 0),
  accepted_quantity integer not null check (accepted_quantity >= 0),
  damaged_quantity integer not null default 0 check (damaged_quantity >= 0),
  rejected_quantity integer not null default 0 check (rejected_quantity >= 0),
  shortage_quantity integer not null default 0 check (shortage_quantity >= 0),
  remaining_quantity integer not null check (remaining_quantity >= 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  line_snapshot jsonb not null,
  stock_movement_id uuid references public.stock_movements(id) on delete restrict,
  discrepancy_reason text,
  created_at timestamp with time zone not null default clock_timestamp(),
  unique (tenant_id, receipt_id, source_line_key),
  foreign key (tenant_id, receipt_id)
    references public.purchase_receipts(tenant_id, id) on delete restrict,
  check (
    accepted_quantity + damaged_quantity + rejected_quantity + shortage_quantity
      <= expected_quantity - previously_received_quantity
  )
);

create table if not exists public.purchase_receipt_line_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  receipt_id uuid not null,
  receipt_line_id uuid not null references public.purchase_receipt_lines(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  stock_movement_id uuid not null references public.stock_movements(id) on delete restrict,
  movement_role text not null check (movement_role in ('direct', 'set_component')),
  quantity integer not null check (quantity > 0),
  created_at timestamp with time zone not null default clock_timestamp(),
  unique (tenant_id, receipt_line_id, stock_movement_id),
  foreign key (tenant_id, receipt_id)
    references public.purchase_receipts(tenant_id, id) on delete restrict
);

create index if not exists idx_purchase_receipts_invoice_created
  on public.purchase_receipts(tenant_id, purchase_invoice_id, created_at desc);
create index if not exists idx_purchase_receipt_lines_invoice_line
  on public.purchase_receipt_lines(tenant_id, purchase_invoice_id, source_line_key);
create index if not exists idx_purchase_receipt_lines_product
  on public.purchase_receipt_lines(tenant_id, product_id, created_at desc)
  where product_id is not null;

alter table public.purchase_receipt_control_settings enable row level security;
alter table public.purchase_receipts enable row level security;
alter table public.purchase_receipt_lines enable row level security;
alter table public.purchase_receipt_line_movements enable row level security;

drop policy if exists purchase_receipt_control_settings_select
  on public.purchase_receipt_control_settings;
create policy purchase_receipt_control_settings_select
  on public.purchase_receipt_control_settings for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists purchase_receipts_select on public.purchase_receipts;
create policy purchase_receipts_select
  on public.purchase_receipts for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists purchase_receipt_lines_select on public.purchase_receipt_lines;
create policy purchase_receipt_lines_select
  on public.purchase_receipt_lines for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists purchase_receipt_line_movements_select
  on public.purchase_receipt_line_movements;
create policy purchase_receipt_line_movements_select
  on public.purchase_receipt_line_movements for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke insert, update, delete on public.purchase_receipt_control_settings
  from public, anon, authenticated;
revoke insert, update, delete on public.purchase_receipts
  from public, anon, authenticated;
revoke insert, update, delete on public.purchase_receipt_lines
  from public, anon, authenticated;
revoke insert, update, delete on public.purchase_receipt_line_movements
  from public, anon, authenticated;
grant select on public.purchase_receipt_control_settings to authenticated;
grant select on public.purchase_receipts to authenticated;
grant select on public.purchase_receipt_lines to authenticated;
grant select on public.purchase_receipt_line_movements to authenticated;

create or replace function public.create_purchase_goods_receipt(
  p_purchase_invoice_id uuid,
  p_lines jsonb,
  p_received_at timestamp with time zone,
  p_delivery_reference text default null,
  p_location_label text default null,
  p_notes text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_actor_id uuid := auth.uid();
  v_invoice public.purchase_invoices%rowtype;
  v_mode text := 'disabled';
  v_receipt_id uuid := gen_random_uuid();
  v_operation_id uuid := gen_random_uuid();
  v_receipt_number text;
  v_request jsonb;
  v_item jsonb;
  v_index integer;
  v_source_line_key text;
  v_product_id uuid;
  v_product public.products%rowtype;
  v_expected integer;
  v_previous integer;
  v_accepted integer;
  v_damaged integer;
  v_rejected integer;
  v_shortage integer;
  v_remaining integer;
  v_movement_id uuid;
  v_receipt_line_id uuid;
  v_movement_ids uuid[];
  v_movement_product_ids uuid[];
  v_movement_quantities integer[];
  v_movement_roles text[];
  v_child record;
  v_child_product public.products%rowtype;
  v_component_quantity integer;
  v_i integer;
  v_stock_before integer;
  v_stock_after integer;
  v_existing public.purchase_receipts%rowtype;
begin
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'Purchase receipt idempotency key is required';
  end if;
  if p_received_at is null then
    raise exception 'Purchase receipt date is required';
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Purchase receipt requires at least one line';
  end if;

  v_tenant_id := public.user_tenant_id();
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Authenticated employee tenant is required';
  end if;

  select * into v_existing
  from public.purchase_receipts receipt
  where receipt.tenant_id = v_tenant_id
    and receipt.idempotency_key = btrim(p_idempotency_key);
  if found then
    if v_existing.purchase_invoice_id <> p_purchase_invoice_id then
      raise exception 'Idempotency key belongs to a different purchase invoice';
    end if;
    return jsonb_build_object(
      'receipt_id', v_existing.id,
      'operation_id', v_existing.operation_id,
      'receipt_number', v_existing.receipt_number,
      'replayed', true
    );
  end if;

  select coalesce(setting.control_mode, 'disabled') into v_mode
  from (select 1) seed
  left join public.purchase_receipt_control_settings setting
    on setting.tenant_id = v_tenant_id;
  if v_mode <> 'enforce' then
    raise exception 'Purchase receipt workflow is not active for this tenant';
  end if;

  select * into v_invoice
  from public.purchase_invoices invoice
  where invoice.id = p_purchase_invoice_id
    and invoice.tenant_id = v_tenant_id
  for update;
  if not found then
    raise exception 'Purchase invoice not found for current tenant';
  end if;
  if v_invoice.status not in ('confirmed', 'paid') then
    raise exception 'Purchase invoice must be confirmed or paid before receiving';
  end if;

  insert into public.inventory_accounting_operations (
    id, tenant_id, operation_key, source_channel, action, document_type,
    document_id, actor_id, executor, old_status, new_status,
    before_snapshot, after_snapshot, context
  ) values (
    v_operation_id, v_tenant_id,
    format('purchase_receipt:%s:%s', p_purchase_invoice_id, btrim(p_idempotency_key)),
    'purchase_receipt', 'create', 'purchase_receipt', v_receipt_id,
    v_actor_id, 'database_command', v_invoice.status, v_invoice.status,
    jsonb_build_object('invoice_id', v_invoice.id, 'status', v_invoice.status, 'items', v_invoice.items),
    null,
    jsonb_build_object('purchase_invoice_id', v_invoice.id, 'idempotency_key', btrim(p_idempotency_key))
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accepted', 'started', 'purchase_invoice', v_invoice.id,
    jsonb_build_object('line_count', jsonb_array_length(p_lines))
  );

  v_receipt_number := public.get_next_document_number(v_tenant_id, 'purchase_receipt', 'REC');
  insert into public.purchase_receipts (
    id, tenant_id, purchase_invoice_id, receipt_number, received_at,
    delivery_reference, location_label, notes, idempotency_key,
    operation_id, created_by
  ) values (
    v_receipt_id, v_tenant_id, v_invoice.id, v_receipt_number, p_received_at,
    nullif(btrim(p_delivery_reference), ''), nullif(btrim(p_location_label), ''),
    nullif(btrim(p_notes), ''), btrim(p_idempotency_key), v_operation_id, v_actor_id
  );

  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  for v_request in select value from jsonb_array_elements(p_lines)
  loop
    v_index := nullif(v_request->>'line_index', '')::integer;
    if v_index is null or v_index < 0 or v_index >= jsonb_array_length(v_invoice.items) then
      raise exception 'Invalid purchase invoice line index %', v_index;
    end if;
    v_item := v_invoice.items->v_index;
    v_source_line_key := coalesce(
      nullif(v_item->>'line_id', ''),
      nullif(v_item->>'id', ''),
      md5(v_invoice.id::text || ':' || v_index::text || ':' || coalesce(v_item->>'product_id', ''))
    );
    if exists (
      select 1 from public.purchase_receipt_lines line
      where line.tenant_id = v_tenant_id
        and line.purchase_invoice_id = v_invoice.id
        and line.source_line_key = v_source_line_key
        and line.receipt_id = v_receipt_id
    ) then
      raise exception 'Duplicate line % in receipt request', v_index;
    end if;

    v_expected := coalesce(nullif(v_item->>'quantity', '')::numeric, 0)::integer;
    if v_expected < 0 or v_expected::numeric <> coalesce(nullif(v_item->>'quantity', '')::numeric, 0) then
      raise exception 'Receipt quantities must be non-negative whole units';
    end if;
    select coalesce(sum(line.accepted_quantity), 0)::integer into v_previous
    from public.purchase_receipt_lines line
    join public.purchase_receipts receipt on receipt.id = line.receipt_id
    where line.tenant_id = v_tenant_id
      and line.purchase_invoice_id = v_invoice.id
      and line.source_line_key = v_source_line_key
      and receipt.status = 'posted';

    v_accepted := coalesce(nullif(v_request->>'accepted_quantity', '')::integer, 0);
    v_damaged := coalesce(nullif(v_request->>'damaged_quantity', '')::integer, 0);
    v_rejected := coalesce(nullif(v_request->>'rejected_quantity', '')::integer, 0);
    v_shortage := coalesce(nullif(v_request->>'shortage_quantity', '')::integer, 0);
    if least(v_accepted, v_damaged, v_rejected, v_shortage) < 0 then
      raise exception 'Receipt quantities cannot be negative';
    end if;
    if v_accepted + v_damaged + v_rejected + v_shortage = 0 then
      raise exception 'Receipt line must record a received or discrepancy quantity';
    end if;
    if v_damaged + v_rejected + v_shortage > 0
       and nullif(btrim(v_request->>'discrepancy_reason'), '') is null then
      raise exception 'Receipt discrepancy reason is required';
    end if;
    if v_accepted + v_damaged + v_rejected + v_shortage > v_expected - v_previous then
      raise exception 'Receipt line % exceeds remaining quantity', v_index;
    end if;
    v_remaining := v_expected - v_previous - v_accepted;
    v_product_id := nullif(v_item->>'product_id', '')::uuid;
    v_movement_id := null;
    v_movement_ids := array[]::uuid[];
    v_movement_product_ids := array[]::uuid[];
    v_movement_quantities := array[]::integer[];
    v_movement_roles := array[]::text[];

    if v_accepted > 0
       and coalesce(nullif(v_item->>'purchase_treatment', ''), 'inventory') = 'inventory'
       and not coalesce(nullif(v_item->>'is_service', '')::boolean, false) then
      select * into v_product from public.products product
      where product.id = v_product_id and product.tenant_id = v_tenant_id
      for update;
      if not found then
        raise exception 'Receipt product not found for current tenant';
      end if;
      if coalesce(v_product.product_type, 'product') = 'service'
         or not coalesce(v_product.track_stock, true) then
        raise exception 'Non-stock products cannot create receipt stock movements';
      end if;
      if coalesce(v_product.is_set, false) then
        if not exists (
          select 1 from public.product_set_components component
          where component.set_product_id = v_product.id
            and component.tenant_id = v_tenant_id
        ) then
          raise exception 'Set product has no configured components';
        end if;

        for v_child in
          select component.component_product_id, component.quantity_in_set
          from public.product_set_components component
          where component.set_product_id = v_product.id
            and component.tenant_id = v_tenant_id
          order by component.component_product_id
        loop
          select * into v_child_product from public.products product
          where product.id = v_child.component_product_id
            and product.tenant_id = v_tenant_id
          for update;
          if not found or not coalesce(v_child_product.track_stock, true)
             or coalesce(v_child_product.product_type, 'product') = 'service' then
            raise exception 'Set component is missing or is not stock tracked';
          end if;
          if coalesce(v_child_product.inventory_qty, 0)
             <> coalesce(v_child_product.stock_quantity, 0) then
            raise exception 'Product stock columns disagree; purchase receipt blocked';
          end if;
          v_component_quantity := v_accepted * v_child.quantity_in_set;
          v_stock_before := coalesce(v_child_product.inventory_qty, 0);
          v_stock_after := v_stock_before + v_component_quantity;
          update public.products set inventory_qty = v_stock_after, stock_quantity = v_stock_after
          where id = v_child_product.id and tenant_id = v_tenant_id;

          v_movement_id := gen_random_uuid();
          insert into public.stock_movements (
            id, tenant_id, product_id, type, movement_type, quantity, reference,
            notes, date, created_at, updated_at, operation_id,
            source_document_type, source_document_id, created_by, stock_before, stock_after
          ) values (
            v_movement_id, v_tenant_id, v_child_product.id, 'IN',
            'purchase_receipt_component', v_component_quantity,
            format('purchase_receipt:%s', v_receipt_id),
            format('Componente de set recibido en %s', v_receipt_number),
            p_received_at, clock_timestamp(), clock_timestamp(), v_operation_id,
            'purchase_receipt', v_receipt_id, v_actor_id, v_stock_before, v_stock_after
          );
          v_movement_ids := array_append(v_movement_ids, v_movement_id);
          v_movement_product_ids := array_append(v_movement_product_ids, v_child_product.id);
          v_movement_quantities := array_append(v_movement_quantities, v_component_quantity);
          v_movement_roles := array_append(v_movement_roles, 'set_component');
        end loop;
      else
        if coalesce(v_product.inventory_qty, 0)
           <> coalesce(v_product.stock_quantity, 0) then
          raise exception 'Product stock columns disagree; purchase receipt blocked';
        end if;
        v_stock_before := coalesce(v_product.inventory_qty, 0);
        v_stock_after := v_stock_before + v_accepted;
        update public.products set inventory_qty = v_stock_after, stock_quantity = v_stock_after
        where id = v_product.id and tenant_id = v_tenant_id;

        v_movement_id := gen_random_uuid();
        insert into public.stock_movements (
        id, tenant_id, product_id, type, movement_type, quantity, reference,
        notes, date, created_at, updated_at, operation_id,
        source_document_type, source_document_id, created_by, stock_before, stock_after
      ) values (
        v_movement_id, v_tenant_id, v_product.id, 'IN', 'purchase_receipt', v_accepted,
        format('purchase_receipt:%s', v_receipt_id),
        format('Recepción %s de factura %s', v_receipt_number, v_invoice.invoice_number),
        p_received_at, clock_timestamp(), clock_timestamp(), v_operation_id,
        'purchase_receipt', v_receipt_id, v_actor_id, v_stock_before, v_stock_after
      );
        v_movement_ids := array_append(v_movement_ids, v_movement_id);
        v_movement_product_ids := array_append(v_movement_product_ids, v_product.id);
        v_movement_quantities := array_append(v_movement_quantities, v_accepted);
        v_movement_roles := array_append(v_movement_roles, 'direct');
      end if;
    end if;

    insert into public.purchase_receipt_lines (
      tenant_id, receipt_id, purchase_invoice_id, source_line_key,
      source_line_index, product_id, product_name, product_sku, purchase_treatment,
      expected_quantity, previously_received_quantity, accepted_quantity,
      damaged_quantity, rejected_quantity, shortage_quantity, remaining_quantity,
      unit_cost, line_snapshot, stock_movement_id, discrepancy_reason
    ) values (
      v_tenant_id, v_receipt_id, v_invoice.id, v_source_line_key,
      v_index, v_product_id, coalesce(v_item->>'product_name', 'Producto'),
      v_item->>'product_sku', coalesce(nullif(v_item->>'purchase_treatment', ''), 'inventory'),
      v_expected, v_previous, v_accepted, v_damaged, v_rejected, v_shortage,
      v_remaining, coalesce(nullif(v_item->>'unit_cost', '')::numeric, 0),
      v_item, case when cardinality(v_movement_ids) = 1 then v_movement_ids[1] else null end,
      nullif(btrim(v_request->>'discrepancy_reason'), '')
    ) returning id into v_receipt_line_id;

    if cardinality(v_movement_ids) > 0 then
      for v_i in 1..cardinality(v_movement_ids) loop
        insert into public.purchase_receipt_line_movements (
          tenant_id, receipt_id, receipt_line_id, product_id,
          stock_movement_id, movement_role, quantity
        ) values (
          v_tenant_id, v_receipt_id, v_receipt_line_id,
          v_movement_product_ids[v_i], v_movement_ids[v_i],
          v_movement_roles[v_i], v_movement_quantities[v_i]
        );
      end loop;
    end if;
  end loop;

  perform set_config('app.skip_stock_adjustment_trigger', '', true);
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'inventory_applied', 'completed', 'purchase_receipt', v_receipt_id,
    jsonb_build_object('accepted_quantity', (select coalesce(sum(accepted_quantity), 0) from public.purchase_receipt_lines where receipt_id = v_receipt_id))
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'movement_recorded', 'completed', 'purchase_receipt', v_receipt_id,
    jsonb_build_object('movement_count', (select count(*) from public.purchase_receipt_line_movements where receipt_id = v_receipt_id))
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'invariants_verified', 'completed', 'purchase_receipt', v_receipt_id,
    jsonb_build_object('dual_stock_columns_match', true)
  );
  update public.inventory_accounting_operations
  set outcome = 'completed', completed_at = clock_timestamp(),
      after_snapshot = jsonb_build_object('receipt_id', v_receipt_id, 'receipt_number', v_receipt_number)
  where id = v_operation_id and tenant_id = v_tenant_id;
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'completed', 'completed', 'purchase_receipt', v_receipt_id,
    jsonb_build_object('receipt_number', v_receipt_number)
  );

  return jsonb_build_object(
    'receipt_id', v_receipt_id,
    'operation_id', v_operation_id,
    'receipt_number', v_receipt_number,
    'replayed', false
  );
exception when others then
  perform set_config('app.skip_stock_adjustment_trigger', '', true);
  raise;
end;
$$;

revoke all on function public.create_purchase_goods_receipt(
  uuid, jsonb, timestamp with time zone, text, text, text, text
) from public, anon;
grant execute on function public.create_purchase_goods_receipt(
  uuid, jsonb, timestamp with time zone, text, text, text, text
) to authenticated;

comment on table public.purchase_receipts is
  'Immutable physical receipt documents. Disabled until tenant control_mode=enforce.';
comment on function public.create_purchase_goods_receipt(
  uuid, jsonb, timestamp with time zone, text, text, text, text
) is 'Idempotent physical receipt command; independent from invoice payment status.';

commit;
