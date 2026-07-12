-- Deployment status: DEPLOYED 2026-07-11. Purchase receipt workflow remains disabled by default.
-- Physical supplier returns are independent from purchase credit notes and AP/tax changes.

begin;

create table if not exists public.purchase_supplier_returns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_receipt_id uuid not null,
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete restrict,
  return_number text not null,
  status text not null default 'posted' check (status in ('posted', 'voided')),
  returned_at timestamp with time zone not null,
  reason text not null,
  shipment_reference text,
  notes text,
  idempotency_key text not null,
  operation_id uuid not null,
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default clock_timestamp(),
  void_operation_id uuid,
  void_idempotency_key text,
  voided_at timestamp with time zone,
  voided_by uuid references auth.users(id),
  void_reason text,
  unique (tenant_id, return_number),
  unique (tenant_id, idempotency_key),
  unique (tenant_id, id),
  foreign key (tenant_id, purchase_receipt_id)
    references public.purchase_receipts(tenant_id, id) on delete restrict,
  foreign key (tenant_id, operation_id)
    references public.inventory_accounting_operations(tenant_id, id) on delete restrict
);

create unique index if not exists uq_purchase_supplier_returns_void_idempotency
  on public.purchase_supplier_returns(tenant_id, void_idempotency_key)
  where void_idempotency_key is not null;

create table if not exists public.purchase_supplier_return_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_return_id uuid not null,
  purchase_receipt_id uuid not null,
  purchase_receipt_line_id uuid not null references public.purchase_receipt_lines(id) on delete restrict,
  source_line_key text not null,
  product_id uuid references public.products(id) on delete restrict,
  product_name text not null,
  returned_quantity integer not null check (returned_quantity > 0),
  previously_returned_quantity integer not null check (previously_returned_quantity >= 0),
  returnable_quantity_before integer not null check (returnable_quantity_before > 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  reason text,
  receipt_line_snapshot jsonb not null,
  created_at timestamp with time zone not null default clock_timestamp(),
  unique (tenant_id, supplier_return_id, purchase_receipt_line_id),
  foreign key (tenant_id, supplier_return_id)
    references public.purchase_supplier_returns(tenant_id, id) on delete restrict,
  foreign key (tenant_id, purchase_receipt_id)
    references public.purchase_receipts(tenant_id, id) on delete restrict,
  check (returned_quantity <= returnable_quantity_before)
);

create table if not exists public.purchase_supplier_return_line_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_return_id uuid not null,
  supplier_return_line_id uuid not null references public.purchase_supplier_return_lines(id) on delete restrict,
  receipt_line_movement_id uuid not null references public.purchase_receipt_line_movements(id) on delete restrict,
  original_receipt_movement_id uuid not null references public.stock_movements(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  stock_movement_id uuid not null references public.stock_movements(id) on delete restrict,
  movement_role text not null check (movement_role in ('direct', 'set_component')),
  quantity integer not null check (quantity > 0),
  created_at timestamp with time zone not null default clock_timestamp(),
  unique (tenant_id, supplier_return_line_id, receipt_line_movement_id),
  foreign key (tenant_id, supplier_return_id)
    references public.purchase_supplier_returns(tenant_id, id) on delete restrict
);

create index if not exists idx_purchase_supplier_returns_receipt
  on public.purchase_supplier_returns(tenant_id, purchase_receipt_id, created_at desc);
create index if not exists idx_purchase_supplier_return_lines_receipt_line
  on public.purchase_supplier_return_lines(tenant_id, purchase_receipt_line_id, created_at desc);
create index if not exists idx_purchase_supplier_return_movements_product
  on public.purchase_supplier_return_line_movements(tenant_id, product_id, created_at desc);

alter table public.purchase_supplier_returns enable row level security;
alter table public.purchase_supplier_return_lines enable row level security;
alter table public.purchase_supplier_return_line_movements enable row level security;

drop policy if exists purchase_supplier_returns_select on public.purchase_supplier_returns;
create policy purchase_supplier_returns_select
  on public.purchase_supplier_returns for select to authenticated
  using (tenant_id = public.user_tenant_id());
drop policy if exists purchase_supplier_return_lines_select on public.purchase_supplier_return_lines;
create policy purchase_supplier_return_lines_select
  on public.purchase_supplier_return_lines for select to authenticated
  using (tenant_id = public.user_tenant_id());
drop policy if exists purchase_supplier_return_line_movements_select
  on public.purchase_supplier_return_line_movements;
create policy purchase_supplier_return_line_movements_select
  on public.purchase_supplier_return_line_movements for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke insert, update, delete on public.purchase_supplier_returns from public, anon, authenticated;
revoke insert, update, delete on public.purchase_supplier_return_lines from public, anon, authenticated;
revoke insert, update, delete on public.purchase_supplier_return_line_movements from public, anon, authenticated;
grant select on public.purchase_supplier_returns to authenticated;
grant select on public.purchase_supplier_return_lines to authenticated;
grant select on public.purchase_supplier_return_line_movements to authenticated;

create or replace function public.create_purchase_supplier_return(
  p_purchase_receipt_id uuid,
  p_lines jsonb,
  p_returned_at timestamp with time zone,
  p_reason text,
  p_shipment_reference text default null,
  p_notes text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_mode text := 'disabled';
  v_receipt public.purchase_receipts%rowtype;
  v_existing public.purchase_supplier_returns%rowtype;
  v_return_id uuid := gen_random_uuid();
  v_operation_id uuid := gen_random_uuid();
  v_return_number text;
  v_request jsonb;
  v_receipt_line public.purchase_receipt_lines%rowtype;
  v_return_line_id uuid;
  v_requested integer;
  v_previous integer;
  v_returnable integer;
  v_mapping record;
  v_product public.products%rowtype;
  v_per_unit integer;
  v_movement_quantity integer;
  v_before integer;
  v_after integer;
  v_movement_id uuid;
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Authenticated employee tenant is required';
  end if;
  if p_returned_at is null then
    raise exception 'Supplier return date is required';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'Supplier return reason is required';
  end if;
  if nullif(btrim(p_idempotency_key), '') is null then
    raise exception 'Supplier return idempotency key is required';
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Supplier return requires at least one line';
  end if;

  select * into v_existing
  from public.purchase_supplier_returns supplier_return
  where supplier_return.tenant_id = v_tenant_id
    and supplier_return.idempotency_key = btrim(p_idempotency_key);
  if found then
    if v_existing.purchase_receipt_id <> p_purchase_receipt_id then
      raise exception 'Idempotency key belongs to a different purchase receipt';
    end if;
    return jsonb_build_object(
      'supplier_return_id', v_existing.id,
      'operation_id', v_existing.operation_id,
      'return_number', v_existing.return_number,
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

  select * into v_receipt
  from public.purchase_receipts receipt
  where receipt.id = p_purchase_receipt_id
    and receipt.tenant_id = v_tenant_id
  for update;
  if not found then raise exception 'Purchase receipt not found for current tenant'; end if;
  if v_receipt.status <> 'posted' then
    raise exception 'Only a posted purchase receipt can be returned';
  end if;

  insert into public.inventory_accounting_operations (
    id, tenant_id, operation_key, source_channel, action, document_type,
    document_id, actor_id, executor, old_status, new_status, context
  ) values (
    v_operation_id, v_tenant_id,
    format('purchase_supplier_return:%s:%s', p_purchase_receipt_id, btrim(p_idempotency_key)),
    'purchase_supplier_return', 'create', 'purchase_supplier_return', v_return_id,
    v_actor_id, 'database_command', 'posted', 'posted',
    jsonb_build_object(
      'purchase_receipt_id', p_purchase_receipt_id,
      'purchase_invoice_id', v_receipt.purchase_invoice_id,
      'idempotency_key', btrim(p_idempotency_key),
      'financial_effect', 'none_pending_purchase_credit_note'
    )
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accepted', 'started', 'purchase_receipt', p_purchase_receipt_id,
    jsonb_build_object('line_count', jsonb_array_length(p_lines))
  );

  v_return_number := public.get_next_document_number(v_tenant_id, 'purchase_supplier_return', 'DVP');
  insert into public.purchase_supplier_returns (
    id, tenant_id, purchase_receipt_id, purchase_invoice_id, return_number,
    returned_at, reason, shipment_reference, notes, idempotency_key,
    operation_id, created_by
  ) values (
    v_return_id, v_tenant_id, p_purchase_receipt_id, v_receipt.purchase_invoice_id,
    v_return_number, p_returned_at, btrim(p_reason),
    nullif(btrim(p_shipment_reference), ''), nullif(btrim(p_notes), ''),
    btrim(p_idempotency_key), v_operation_id, v_actor_id
  );

  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  for v_request in select value from jsonb_array_elements(p_lines)
  loop
    if nullif(v_request->>'receipt_line_id', '') is null then
      raise exception 'Supplier return receipt_line_id is required';
    end if;
    select * into v_receipt_line
    from public.purchase_receipt_lines receipt_line
    where receipt_line.id = (v_request->>'receipt_line_id')::uuid
      and receipt_line.receipt_id = p_purchase_receipt_id
      and receipt_line.tenant_id = v_tenant_id
    for update;
    if not found then raise exception 'Purchase receipt line not found for current receipt'; end if;
    if exists (
      select 1 from public.purchase_supplier_return_lines return_line
      where return_line.tenant_id = v_tenant_id
        and return_line.supplier_return_id = v_return_id
        and return_line.purchase_receipt_line_id = v_receipt_line.id
    ) then
      raise exception 'Duplicate receipt line in supplier return request';
    end if;

    v_requested := coalesce(nullif(v_request->>'returned_quantity', '')::integer, 0);
    if v_requested <= 0 then raise exception 'Supplier return quantity must be positive'; end if;
    select coalesce(sum(return_line.returned_quantity), 0)::integer into v_previous
    from public.purchase_supplier_return_lines return_line
    join public.purchase_supplier_returns supplier_return
      on supplier_return.id = return_line.supplier_return_id
    where return_line.tenant_id = v_tenant_id
      and return_line.purchase_receipt_line_id = v_receipt_line.id
      and supplier_return.status = 'posted';
    v_returnable := v_receipt_line.accepted_quantity - v_previous;
    if v_requested > v_returnable then
      raise exception 'Supplier return exceeds remaining received quantity';
    end if;
    if not exists (
      select 1 from public.purchase_receipt_line_movements mapping
      where mapping.receipt_line_id = v_receipt_line.id
        and mapping.tenant_id = v_tenant_id
    ) then
      raise exception 'Receipt line has no stock movement to return';
    end if;

    insert into public.purchase_supplier_return_lines (
      tenant_id, supplier_return_id, purchase_receipt_id,
      purchase_receipt_line_id, source_line_key, product_id, product_name,
      returned_quantity, previously_returned_quantity, returnable_quantity_before,
      unit_cost, reason, receipt_line_snapshot
    ) values (
      v_tenant_id, v_return_id, p_purchase_receipt_id,
      v_receipt_line.id, v_receipt_line.source_line_key,
      v_receipt_line.product_id, v_receipt_line.product_name,
      v_requested, v_previous, v_returnable, v_receipt_line.unit_cost,
      nullif(btrim(v_request->>'reason'), ''), to_jsonb(v_receipt_line)
    ) returning id into v_return_line_id;

    for v_mapping in
      select mapping.*
      from public.purchase_receipt_line_movements mapping
      where mapping.receipt_line_id = v_receipt_line.id
        and mapping.tenant_id = v_tenant_id
      order by mapping.product_id, mapping.id
    loop
      if v_receipt_line.accepted_quantity <= 0
         or mod(v_mapping.quantity, v_receipt_line.accepted_quantity) <> 0 then
        raise exception 'Receipt movement cannot be allocated to commercial return units';
      end if;
      v_per_unit := v_mapping.quantity / v_receipt_line.accepted_quantity;
      v_movement_quantity := v_requested * v_per_unit;

      select * into v_product from public.products product
      where product.id = v_mapping.product_id
        and product.tenant_id = v_tenant_id
      for update;
      if not found then raise exception 'Supplier return product not found for current tenant'; end if;
      if coalesce(v_product.inventory_qty, 0) <> coalesce(v_product.stock_quantity, 0) then
        raise exception 'Product stock columns disagree; supplier return blocked';
      end if;
      v_before := coalesce(v_product.inventory_qty, 0);
      if v_before < v_movement_quantity then
        raise exception 'Insufficient current stock for supplier return';
      end if;
      v_after := v_before - v_movement_quantity;
      update public.products set inventory_qty = v_after, stock_quantity = v_after
      where id = v_product.id and tenant_id = v_tenant_id;

      v_movement_id := gen_random_uuid();
      insert into public.stock_movements (
        id, tenant_id, product_id, type, movement_type, quantity, reference,
        notes, date, created_at, updated_at, operation_id,
        source_document_type, source_document_id, created_by,
        stock_before, stock_after, reversal_of_id
      ) values (
        v_movement_id, v_tenant_id, v_product.id, 'OUT', 'purchase_supplier_return',
        -v_movement_quantity, format('purchase_supplier_return:%s', v_return_id),
        format('Devolución %s vinculada a recepción %s', v_return_number, v_receipt.receipt_number),
        p_returned_at, clock_timestamp(), clock_timestamp(), v_operation_id,
        'purchase_supplier_return', v_return_id, v_actor_id,
        v_before, v_after, v_mapping.stock_movement_id
      );
      insert into public.purchase_supplier_return_line_movements (
        tenant_id, supplier_return_id, supplier_return_line_id,
        receipt_line_movement_id, original_receipt_movement_id,
        product_id, stock_movement_id, movement_role, quantity
      ) values (
        v_tenant_id, v_return_id, v_return_line_id,
        v_mapping.id, v_mapping.stock_movement_id,
        v_product.id, v_movement_id, v_mapping.movement_role, v_movement_quantity
      );
    end loop;
  end loop;

  perform set_config('app.skip_stock_adjustment_trigger', '', true);
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'inventory_applied', 'completed', 'purchase_supplier_return', v_return_id,
    jsonb_build_object(
      'commercial_quantity', (select sum(returned_quantity) from public.purchase_supplier_return_lines where supplier_return_id = v_return_id),
      'stock_movement_count', (select count(*) from public.purchase_supplier_return_line_movements where supplier_return_id = v_return_id)
    )
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accounting_planned', 'warning', 'purchase_supplier_return', v_return_id,
    jsonb_build_object('journal_posted', false, 'reason', 'awaiting_explicit_purchase_credit_note')
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'invariants_verified', 'completed', 'purchase_supplier_return', v_return_id,
    jsonb_build_object('dual_stock_columns_match', true, 'invoice_and_payments_unchanged', true)
  );
  update public.inventory_accounting_operations
  set outcome = 'completed', completed_at = clock_timestamp(),
      after_snapshot = jsonb_build_object(
        'supplier_return_id', v_return_id,
        'return_number', v_return_number,
        'financial_effect', 'none_pending_purchase_credit_note'
      )
  where id = v_operation_id and tenant_id = v_tenant_id;
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'completed', 'completed', 'purchase_supplier_return', v_return_id,
    jsonb_build_object('return_number', v_return_number)
  );

  return jsonb_build_object(
    'supplier_return_id', v_return_id,
    'operation_id', v_operation_id,
    'return_number', v_return_number,
    'replayed', false
  );
exception when others then
  perform set_config('app.skip_stock_adjustment_trigger', '', true);
  raise;
end;
$$;

create or replace function public.void_purchase_supplier_return(
  p_supplier_return_id uuid,
  p_reason text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_mode text := 'disabled';
  v_return public.purchase_supplier_returns%rowtype;
  v_mapping record;
  v_product public.products%rowtype;
  v_operation_id uuid := gen_random_uuid();
  v_movement_id uuid;
  v_before integer;
  v_after integer;
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Authenticated employee tenant is required';
  end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'Supplier return void reason is required'; end if;
  if nullif(btrim(p_idempotency_key), '') is null then raise exception 'Supplier return void idempotency key is required'; end if;

  select * into v_return from public.purchase_supplier_returns supplier_return
  where supplier_return.id = p_supplier_return_id
    and supplier_return.tenant_id = v_tenant_id
  for update;
  if not found then raise exception 'Supplier return not found for current tenant'; end if;
  if v_return.status = 'voided' then
    if v_return.void_idempotency_key = btrim(p_idempotency_key) then
      return jsonb_build_object(
        'supplier_return_id', v_return.id,
        'operation_id', v_return.void_operation_id,
        'replayed', true
      );
    end if;
    raise exception 'Supplier return is already voided';
  end if;

  select coalesce(setting.control_mode, 'disabled') into v_mode
  from (select 1) seed
  left join public.purchase_receipt_control_settings setting
    on setting.tenant_id = v_tenant_id;
  if v_mode <> 'enforce' then
    raise exception 'Purchase receipt workflow is not active for this tenant';
  end if;

  insert into public.inventory_accounting_operations (
    id, tenant_id, operation_key, source_channel, action, document_type,
    document_id, actor_id, executor, old_status, new_status, context
  ) values (
    v_operation_id, v_tenant_id,
    format('purchase_supplier_return_void:%s:%s', p_supplier_return_id, btrim(p_idempotency_key)),
    'purchase_supplier_return', 'void', 'purchase_supplier_return', p_supplier_return_id,
    v_actor_id, 'database_command', 'posted', 'voided',
    jsonb_build_object('reason', btrim(p_reason), 'original_operation_id', v_return.operation_id)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accepted', 'started', 'purchase_supplier_return', p_supplier_return_id,
    jsonb_build_object('reason', btrim(p_reason))
  );
  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  for v_mapping in
    select mapping.*
    from public.purchase_supplier_return_line_movements mapping
    where mapping.supplier_return_id = p_supplier_return_id
      and mapping.tenant_id = v_tenant_id
    order by mapping.product_id, mapping.id
  loop
    select * into v_product from public.products product
    where product.id = v_mapping.product_id
      and product.tenant_id = v_tenant_id
    for update;
    if not found then raise exception 'Supplier return product not found for current tenant'; end if;
    if coalesce(v_product.inventory_qty, 0) <> coalesce(v_product.stock_quantity, 0) then
      raise exception 'Product stock columns disagree; supplier return void blocked';
    end if;
    v_before := coalesce(v_product.inventory_qty, 0);
    v_after := v_before + v_mapping.quantity;
    update public.products set inventory_qty = v_after, stock_quantity = v_after
    where id = v_product.id and tenant_id = v_tenant_id;

    v_movement_id := gen_random_uuid();
    insert into public.stock_movements (
      id, tenant_id, product_id, type, movement_type, quantity, reference,
      notes, date, created_at, updated_at, operation_id,
      source_document_type, source_document_id, created_by,
      stock_before, stock_after, reversal_of_id
    ) values (
      v_movement_id, v_tenant_id, v_product.id, 'IN', 'purchase_supplier_return_reversal',
      v_mapping.quantity, format('purchase_supplier_return:%s:void', p_supplier_return_id),
      format('Anulación de devolución %s: %s', v_return.return_number, btrim(p_reason)),
      clock_timestamp(), clock_timestamp(), clock_timestamp(), v_operation_id,
      'purchase_supplier_return', p_supplier_return_id, v_actor_id,
      v_before, v_after, v_mapping.stock_movement_id
    );
  end loop;

  perform set_config('app.skip_stock_adjustment_trigger', '', true);
  update public.purchase_supplier_returns
  set status = 'voided', void_operation_id = v_operation_id,
      void_idempotency_key = btrim(p_idempotency_key), voided_at = clock_timestamp(),
      voided_by = v_actor_id, void_reason = btrim(p_reason)
  where id = p_supplier_return_id and tenant_id = v_tenant_id;
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'inventory_applied', 'completed', 'purchase_supplier_return', p_supplier_return_id,
    jsonb_build_object('reversal_count', (select count(*) from public.stock_movements where operation_id = v_operation_id))
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accounting_planned', 'warning', 'purchase_supplier_return', p_supplier_return_id,
    jsonb_build_object('journal_posted', false, 'reason', 'physical_return_void_only')
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'invariants_verified', 'completed', 'purchase_supplier_return', p_supplier_return_id,
    jsonb_build_object('dual_stock_columns_match', true, 'invoice_and_payments_unchanged', true)
  );
  update public.inventory_accounting_operations
  set outcome = 'completed', completed_at = clock_timestamp(),
      after_snapshot = jsonb_build_object('supplier_return_id', p_supplier_return_id, 'status', 'voided')
  where id = v_operation_id and tenant_id = v_tenant_id;
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'completed', 'completed', 'purchase_supplier_return', p_supplier_return_id,
    jsonb_build_object('status', 'voided')
  );

  return jsonb_build_object(
    'supplier_return_id', p_supplier_return_id,
    'operation_id', v_operation_id,
    'replayed', false
  );
exception when others then
  perform set_config('app.skip_stock_adjustment_trigger', '', true);
  raise;
end;
$$;

create or replace function public.prevent_void_receipt_with_posted_supplier_returns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.status = 'posted' and new.status = 'voided'
     and exists (
       select 1 from public.purchase_supplier_returns supplier_return
       where supplier_return.tenant_id = old.tenant_id
         and supplier_return.purchase_receipt_id = old.id
         and supplier_return.status = 'posted'
     ) then
    raise exception 'Void posted supplier returns before voiding this purchase receipt';
  end if;
  return new;
end;
$$;

create or replace function public.prevent_receipt_void_operation_with_posted_supplier_returns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.document_type = 'purchase_receipt' and new.action = 'void'
     and exists (
       select 1 from public.purchase_supplier_returns supplier_return
       where supplier_return.tenant_id = new.tenant_id
         and supplier_return.purchase_receipt_id = new.document_id
         and supplier_return.status = 'posted'
     ) then
    raise exception 'Void posted supplier returns before voiding this purchase receipt';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_void_receipt_with_supplier_returns
  on public.purchase_receipts;
create trigger trg_prevent_void_receipt_with_supplier_returns
before update of status on public.purchase_receipts
for each row execute function public.prevent_void_receipt_with_posted_supplier_returns();

drop trigger if exists trg_prevent_receipt_void_operation_with_supplier_returns
  on public.inventory_accounting_operations;
create trigger trg_prevent_receipt_void_operation_with_supplier_returns
before insert on public.inventory_accounting_operations
for each row execute function public.prevent_receipt_void_operation_with_posted_supplier_returns();

revoke all on function public.create_purchase_supplier_return(
  uuid, jsonb, timestamp with time zone, text, text, text, text
) from public, anon;
grant execute on function public.create_purchase_supplier_return(
  uuid, jsonb, timestamp with time zone, text, text, text, text
) to authenticated;
revoke all on function public.void_purchase_supplier_return(uuid, text, text)
  from public, anon;
grant execute on function public.void_purchase_supplier_return(uuid, text, text)
  to authenticated;

comment on table public.purchase_supplier_returns is
  'Immutable physical returns to suppliers; financial credit requires a separate purchase credit note.';
comment on function public.create_purchase_supplier_return(
  uuid, jsonb, timestamp with time zone, text, text, text, text
) is 'Idempotent physical supplier-return command linked to exact receipt movements; no AP/tax effect.';

commit;
