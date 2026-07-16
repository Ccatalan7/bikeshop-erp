-- Deployment status: DEPLOYED to production project xzdvtzdqjeyqxnkqprtf
-- on 2026-07-15. Operation workshop-inventory-fv00809-pedal-v1 appended one
-- OUT movement and changed SKU 4089 from 3 to 2 with zero journal change;
-- stock mirrors and every operation invariant passed.
-- FV-00809 is the one documented posted-edit gap with complete evidence:
-- the paid invoice owns one non-service pedal line, its UUID-owned journal
-- already includes that line's cost, and the invoice has no pedal movement.
-- Append exactly one traced OUT movement and reduce both stock mirrors once.
begin;

do $$
declare
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_invoice_id constant uuid := '08872f0b-1255-4560-b935-41bc640b43f8';
  v_product_id constant uuid := '374d7bb1-91d6-4ccc-bc6b-dbd1414f4f07';
  v_operation_key constant text := 'workshop-inventory-fv00809-pedal-v1';
  v_invoice public.sales_invoices%rowtype;
  v_product public.products%rowtype;
  v_operation public.inventory_accounting_operations%rowtype;
  v_line_count integer;
  v_line_quantity numeric;
  v_line_cost numeric;
  v_invoice_cost numeric;
  v_journal_inventory_credit numeric;
  v_net_moved numeric;
  v_movement_id uuid := gen_random_uuid();
begin
  select * into v_invoice
  from public.sales_invoices
  where id = v_invoice_id and tenant_id = v_tenant_id
  for update;

  -- Fresh/local databases do not contain the production-specific row.
  if not found then
    return;
  end if;

  select * into v_operation
  from public.inventory_accounting_operations
  where tenant_id = v_tenant_id and operation_key = v_operation_key;
  if found and v_operation.outcome = 'completed' then
    return;
  elsif found then
    raise exception 'Existing FV-00809 repair operation is not completed.';
  end if;

  if lower(v_invoice.status) not in ('paid', 'pagado', 'pagada') then
    raise exception 'FV-00809 is no longer paid; refusing inventory repair.';
  end if;

  select
    count(*)::integer,
    coalesce(sum((line.value->>'quantity')::numeric), 0),
    coalesce(sum((line.value->>'cost')::numeric), 0)
  into v_line_count, v_line_quantity, v_line_cost
  from jsonb_array_elements(coalesce(v_invoice.items, '[]'::jsonb)) line(value)
  where nullif(line.value->>'product_id', '')::uuid = v_product_id
    and coalesce(nullif(line.value->>'is_service', '')::boolean, false) = false
    and coalesce(nullif(line.value->>'purchase_treatment', ''), 'inventory') = 'inventory';

  if v_line_count <> 1 or v_line_quantity <> 1 or v_line_cost <> 2950 then
    raise exception 'FV-00809 pedal evidence changed (lines %, quantity %, cost %).',
      v_line_count, v_line_quantity, v_line_cost;
  end if;

  select coalesce(sum(
    case
      when coalesce(nullif(line.value->>'is_service', '')::boolean, false) = false
        then coalesce(nullif(line.value->>'cost', '')::numeric, 0)
             * coalesce(nullif(line.value->>'quantity', '')::numeric, 0)
      else 0
    end
  ), 0)
  into v_invoice_cost
  from jsonb_array_elements(coalesce(v_invoice.items, '[]'::jsonb)) line(value);

  select coalesce(sum(journal_line.credit_amount), 0)
  into v_journal_inventory_credit
  from public.journal_entries entry
  join public.journal_lines journal_line
    on journal_line.entry_id = entry.id
   and journal_line.tenant_id = entry.tenant_id
  where entry.tenant_id = v_tenant_id
    and entry.source_module = 'sales_invoices'
    and entry.source_document_id = v_invoice_id
    and journal_line.account_code = '1105';

  if v_invoice_cost <> 25150
     or v_journal_inventory_credit <> v_invoice_cost then
    raise exception 'FV-00809 accounting cost evidence changed (invoice %, journal %).',
      v_invoice_cost, v_journal_inventory_credit;
  end if;

  select coalesce(-sum(movement.quantity), 0)
  into v_net_moved
  from public.stock_movements movement
  where movement.tenant_id = v_tenant_id
    and movement.product_id = v_product_id
    and movement.reference = 'sales_invoice:' || v_invoice_id::text;

  if v_net_moved = 1 then
    return;
  elsif v_net_moved <> 0 then
    raise exception 'FV-00809 pedal movement evidence changed (net %).', v_net_moved;
  end if;

  select * into v_product
  from public.products
  where id = v_product_id and tenant_id = v_tenant_id
  for update;

  if not found
     or coalesce(v_product.stock_quantity, 0)
        <> coalesce(v_product.inventory_qty, 0) then
    raise exception 'FV-00809 pedal stock mirrors are missing or disagree.';
  end if;

  insert into public.inventory_accounting_operations(
    tenant_id, operation_key, source_channel, action, document_type,
    document_id, actor_id, executor, old_status, new_status,
    before_snapshot, context, outcome
  ) values (
    v_tenant_id, v_operation_key, 'database_backfill', 'repair',
    'sales_invoice', v_invoice_id, null, 'database_migration',
    v_invoice.status, v_invoice.status,
    jsonb_build_object(
      'invoice', public.inventory_trace_document_snapshot(to_jsonb(v_invoice)),
      'product_id', v_product_id,
      'stock_before', v_product.stock_quantity,
      'invoice_product_quantity', v_line_quantity,
      'movement_quantity_before', v_net_moved,
      'invoice_cost', v_invoice_cost,
      'journal_inventory_credit', v_journal_inventory_credit
    ),
    jsonb_build_object(
      'reason', 'documented_posted_edit_gap',
      'migration', '20260715210000_repair_fv00809_missing_pedal_movement'
    ),
    'started'
  ) returning * into v_operation;

  perform public.append_inventory_accounting_checkpoint(
    v_operation.id, 'accepted', 'started', 'sales_invoice', v_invoice_id,
    jsonb_build_object('repair_key', v_operation_key)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation.id, 'source_snapshotted', 'completed', 'sales_invoice', v_invoice_id,
    v_operation.before_snapshot
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation.id, 'inventory_planned', 'completed', 'product', v_product_id,
    jsonb_build_object('quantity', -1, 'stock_before', v_product.stock_quantity)
  );

  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);
  perform set_config('app.inventory_operation_id', v_operation.id::text, true);
  perform set_config('app.inventory_source_document_type', 'sales_invoice', true);
  perform set_config('app.inventory_source_document_id', v_invoice_id::text, true);
  perform set_config('app.inventory_source_channel', 'database_backfill', true);

  update public.products
  set stock_quantity = coalesce(stock_quantity, inventory_qty, 0) - 1,
      inventory_qty = coalesce(stock_quantity, inventory_qty, 0) - 1,
      updated_at = clock_timestamp()
  where id = v_product_id and tenant_id = v_tenant_id;

  insert into public.stock_movements(
    id, tenant_id, product_id, type, movement_type, quantity,
    reference, notes, date, created_at, updated_at,
    operation_id, source_document_type, source_document_id,
    stock_before, stock_after
  ) values (
    v_movement_id, v_tenant_id, v_product_id, 'OUT',
    'sales_invoice_legacy_repair', -1,
    'sales_invoice:' || v_invoice_id::text,
    'Corrección auditada: salida faltante de pedal en factura FV-00809',
    v_invoice.date, clock_timestamp(), clock_timestamp(),
    v_operation.id, 'sales_invoice', v_invoice_id,
    v_product.stock_quantity, v_product.stock_quantity - 1
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation.id, 'accounting_planned', 'completed', 'journal_entry', null,
    jsonb_build_object(
      'journal_change', 0,
      'reason', 'existing_uuid_owned_journal_already_includes_exact_invoice_cost'
    )
  );

  update public.inventory_accounting_operations
  set after_snapshot = jsonb_build_object(
    'invoice_id', v_invoice_id,
    'product_id', v_product_id,
    'stock_after', v_product.stock_quantity - 1,
    'movement_id', v_movement_id,
    'invoice_product_quantity', v_line_quantity,
    'movement_quantity_after', 1,
    'journal_inventory_credit', v_journal_inventory_credit
  )
  where id = v_operation.id;

  perform public.complete_inventory_accounting_operation(
    v_operation.id,
    v_tenant_id,
    jsonb_build_object(
      'repair', 'fv00809_missing_pedal_movement',
      'movement_id', v_movement_id,
      'journal_change', 0
    )
  );
end;
$$;

commit;
