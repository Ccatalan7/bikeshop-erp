-- Deployment status: DEPLOYED 2026-07-11. Receipt kernel remains disabled by default.

begin;

alter table public.purchase_receipts
  add column if not exists void_operation_id uuid,
  add column if not exists void_idempotency_key text,
  add column if not exists voided_at timestamp with time zone,
  add column if not exists voided_by uuid references auth.users(id),
  add column if not exists void_reason text;

create unique index if not exists uq_purchase_receipts_void_idempotency
  on public.purchase_receipts(tenant_id, void_idempotency_key)
  where void_idempotency_key is not null;

create or replace function public.void_purchase_goods_receipt(
  p_receipt_id uuid,
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
  v_receipt public.purchase_receipts%rowtype;
  v_line record;
  v_original public.stock_movements%rowtype;
  v_product public.products%rowtype;
  v_operation_id uuid := gen_random_uuid();
  v_reversal_id uuid;
  v_before integer;
  v_after integer;
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Authenticated employee tenant is required';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'Receipt void reason is required';
  end if;
  if nullif(btrim(p_idempotency_key), '') is null then
    raise exception 'Receipt void idempotency key is required';
  end if;

  select * into v_receipt from public.purchase_receipts receipt
  where receipt.id = p_receipt_id and receipt.tenant_id = v_tenant_id
  for update;
  if not found then raise exception 'Purchase receipt not found for current tenant'; end if;

  if v_receipt.status = 'voided' then
    if v_receipt.void_idempotency_key = btrim(p_idempotency_key) then
      return jsonb_build_object(
        'receipt_id', v_receipt.id,
        'operation_id', v_receipt.void_operation_id,
        'replayed', true
      );
    end if;
    raise exception 'Purchase receipt is already voided';
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
    format('purchase_receipt_void:%s:%s', p_receipt_id, btrim(p_idempotency_key)),
    'purchase_receipt', 'void', 'purchase_receipt', p_receipt_id,
    v_actor_id, 'database_command', 'posted', 'voided',
    jsonb_build_object('reason', btrim(p_reason), 'original_operation_id', v_receipt.operation_id)
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accepted', 'started', 'purchase_receipt', p_receipt_id,
    jsonb_build_object('reason', btrim(p_reason))
  );
  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  for v_line in
    select line.source_line_index, mapping.product_id,
           mapping.stock_movement_id, mapping.quantity as movement_quantity
    from public.purchase_receipt_lines line
    join public.purchase_receipt_line_movements mapping
      on mapping.receipt_line_id = line.id and mapping.tenant_id = line.tenant_id
    where line.receipt_id = p_receipt_id and line.tenant_id = v_tenant_id
    order by mapping.product_id, mapping.id
  loop
    select * into v_original from public.stock_movements movement
    where movement.id = v_line.stock_movement_id and movement.tenant_id = v_tenant_id;
    if not found then raise exception 'Original receipt movement is missing'; end if;

    select * into v_product from public.products product
    where product.id = v_line.product_id and product.tenant_id = v_tenant_id
    for update;
    if not found then raise exception 'Receipt product not found for current tenant'; end if;
    if coalesce(v_product.inventory_qty, 0)
       <> coalesce(v_product.stock_quantity, 0) then
      raise exception 'Product stock columns disagree; receipt void blocked';
    end if;
    v_before := coalesce(v_product.inventory_qty, 0);
    if v_before < v_line.movement_quantity then
      raise exception 'Insufficient current stock to void receipt line %', v_line.source_line_index;
    end if;
    v_after := v_before - v_line.movement_quantity;
    update public.products set inventory_qty = v_after, stock_quantity = v_after
    where id = v_product.id and tenant_id = v_tenant_id;

    v_reversal_id := gen_random_uuid();
    insert into public.stock_movements (
      id, tenant_id, product_id, type, movement_type, quantity, reference,
      notes, date, created_at, updated_at, operation_id, source_document_type,
      source_document_id, created_by, stock_before, stock_after, reversal_of_id
    ) values (
      v_reversal_id, v_tenant_id, v_product.id, 'OUT', 'purchase_receipt_reversal',
      -v_line.movement_quantity, format('purchase_receipt:%s:void', p_receipt_id),
      format('Anulación de recepción %s: %s', v_receipt.receipt_number, btrim(p_reason)),
      clock_timestamp(), clock_timestamp(), clock_timestamp(), v_operation_id,
      'purchase_receipt', p_receipt_id, v_actor_id, v_before, v_after, v_original.id
    );
  end loop;

  perform set_config('app.skip_stock_adjustment_trigger', '', true);
  update public.purchase_receipts
  set status = 'voided', void_operation_id = v_operation_id,
      void_idempotency_key = btrim(p_idempotency_key), voided_at = clock_timestamp(),
      voided_by = v_actor_id, void_reason = btrim(p_reason)
  where id = p_receipt_id and tenant_id = v_tenant_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'inventory_applied', 'completed', 'purchase_receipt', p_receipt_id,
    jsonb_build_object('reversal_count', (select count(*) from public.stock_movements where operation_id = v_operation_id))
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'invariants_verified', 'completed', 'purchase_receipt', p_receipt_id,
    jsonb_build_object('dual_stock_columns_match', true)
  );
  update public.inventory_accounting_operations
  set outcome = 'completed', completed_at = clock_timestamp(),
      after_snapshot = jsonb_build_object('receipt_id', p_receipt_id, 'status', 'voided')
  where id = v_operation_id and tenant_id = v_tenant_id;
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'completed', 'completed', 'purchase_receipt', p_receipt_id,
    jsonb_build_object('status', 'voided')
  );

  return jsonb_build_object('receipt_id', p_receipt_id, 'operation_id', v_operation_id, 'replayed', false);
exception when others then
  perform set_config('app.skip_stock_adjustment_trigger', '', true);
  raise;
end;
$$;

revoke all on function public.void_purchase_goods_receipt(uuid, text, text)
  from public, anon;
grant execute on function public.void_purchase_goods_receipt(uuid, text, text)
  to authenticated;

commit;
