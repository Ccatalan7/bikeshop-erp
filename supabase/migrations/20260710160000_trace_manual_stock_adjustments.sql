-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-10
-- Adds a connected trace root to every structured manual/product-form/bulk stock adjustment.

begin;

create or replace function public.complete_inventory_accounting_operation(
  p_operation_id uuid,
  p_tenant_id uuid,
  p_completion_payload jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock_column_drift integer := 0;
  v_movement_arithmetic_errors integer := 0;
  v_unbalanced_journals integer := 0;
begin
  if not exists (
    select 1
      from inventory_accounting_operations operation
     where operation.id = p_operation_id
       and operation.tenant_id = p_tenant_id
  ) then
    raise exception 'Inventory/accounting operation % does not belong to tenant %',
      p_operation_id, p_tenant_id
      using errcode = 'foreign_key_violation';
  end if;

  select count(*)::integer
    into v_stock_column_drift
    from products product
   where product.tenant_id = p_tenant_id
     and product.id in (
       select movement.product_id
         from stock_movements movement
        where movement.operation_id = p_operation_id
     )
     and coalesce(product.inventory_qty, 0)
         <> coalesce(product.stock_quantity, 0);

  select count(*)::integer
    into v_movement_arithmetic_errors
    from stock_movements movement
   where movement.operation_id = p_operation_id
     and (
       movement.stock_before is null
       or movement.stock_after is null
       or round(
         movement.stock_before + case
           when movement.type in ('OUT', 'TRANSFER_OUT') then -abs(movement.quantity)
           when movement.type in ('IN', 'TRANSFER_IN') then abs(movement.quantity)
           else movement.quantity
         end,
         2
       ) <> round(movement.stock_after, 2)
     );

  select count(*)::integer
    into v_unbalanced_journals
    from (
      select entry.id
        from journal_entries entry
        left join journal_lines line
          on line.entry_id = entry.id
         and line.tenant_id = entry.tenant_id
       where entry.operation_id = p_operation_id
       group by entry.id
      having round(coalesce(sum(line.debit_amount), 0), 2)
          <> round(coalesce(sum(line.credit_amount), 0), 2)
    ) broken;

  perform public.append_inventory_accounting_checkpoint(
    p_operation_id,
    'invariants_verified',
    case
      when v_stock_column_drift = 0
       and v_movement_arithmetic_errors = 0
       and v_unbalanced_journals = 0 then 'completed'
      else 'failed'
    end,
    null,
    null,
    jsonb_build_object(
      'stock_column_drift', v_stock_column_drift,
      'movement_arithmetic_errors', v_movement_arithmetic_errors,
      'unbalanced_journals', v_unbalanced_journals
    )
  );

  if v_stock_column_drift > 0
     or v_movement_arithmetic_errors > 0
     or v_unbalanced_journals > 0 then
    raise exception
      'Inventory/accounting invariants failed for operation % (stock drift %, movement errors %, unbalanced journals %)',
      p_operation_id,
      v_stock_column_drift,
      v_movement_arithmetic_errors,
      v_unbalanced_journals
      using errcode = 'check_violation';
  end if;

  update inventory_accounting_operations
     set outcome = 'completed',
         completed_at = clock_timestamp()
   where id = p_operation_id
     and tenant_id = p_tenant_id;

  perform public.append_inventory_accounting_checkpoint(
    p_operation_id,
    'completed',
    'completed',
    null,
    null,
    coalesce(p_completion_payload, '{}'::jsonb)
  );
end;
$$;

revoke all on function public.complete_inventory_accounting_operation(uuid, uuid, jsonb)
  from public, anon, authenticated;

drop function if exists public.apply_inventory_stock_adjustment(uuid, integer, text, text, text, timestamp with time zone);

create or replace function public.apply_inventory_stock_adjustment(
  p_product_id uuid,
  p_quantity integer,
  p_type text,
  p_reason_type text,
  p_note text default null,
  p_effective_at timestamp with time zone default now(),
  p_adjustment_origin text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.products%rowtype;
  v_delta integer;
  v_stock_before integer;
  v_stock_after integer;
  v_reason_label text;
  v_reason text;
  v_adjustment_type text;
  v_reference text;
  v_adjustment_origin text;
  v_adjustment_origin_label text;
  v_adjustment_date timestamp with time zone := coalesce(p_effective_at, now());
  v_created_at timestamp with time zone := now();
  v_adjustment_id uuid;
  v_operation_id uuid;
  v_operation_key text;
  v_source_channel text;
  v_movement_id uuid;
  v_inventory_account_id uuid;
  v_counterpart_account_id uuid;
  v_counterpart_account_code text;
  v_counterpart_account_name text;
  v_inventory_value numeric(14,2) := 0;
  v_entry_id uuid;
  v_entry_number text;
  v_description text;
begin
  if p_type not in ('IN', 'OUT') then
    raise exception 'Invalid stock adjustment type: %', p_type
      using errcode = 'check_violation';
  end if;

  if p_quantity <= 0 then
    raise exception 'Stock adjustment quantity must be positive: %', p_quantity
      using errcode = 'check_violation';
  end if;

  if p_reason_type not in ('manual', 'count', 'loss', 'damage', 'theft', 'internal_use', 'found') then
    raise exception 'Invalid stock adjustment reason type: %', p_reason_type
      using errcode = 'check_violation';
  end if;

  if p_type = 'IN' and p_reason_type in ('loss', 'damage', 'theft', 'internal_use') then
    raise exception 'Reason % is only valid for stock decreases', p_reason_type
      using errcode = 'check_violation';
  end if;

  if p_type = 'OUT' and p_reason_type = 'found' then
    raise exception 'Reason % is only valid for stock increases', p_reason_type
      using errcode = 'check_violation';
  end if;

  v_adjustment_origin := nullif(trim(coalesce(p_adjustment_origin, '')), '');

  if v_adjustment_origin is not null
     and v_adjustment_origin not in ('product_form', 'mass_edit_panel', 'manual_service') then
    raise exception 'Invalid stock adjustment origin: %', v_adjustment_origin
      using errcode = 'check_violation';
  end if;

  select *
    into v_product
    from public.products
   where id = p_product_id
     and tenant_id = public.user_tenant_id()
   for update;

  if not found then
    raise exception 'Product % not found for current tenant', p_product_id
      using errcode = 'foreign_key_violation';
  end if;

  if coalesce(v_product.product_type, 'product') = 'service'
     or coalesce(v_product.track_stock, true) = false then
    raise exception 'Product % does not track stock', coalesce(v_product.name, p_product_id::text)
      using errcode = 'check_violation';
  end if;

  v_delta := case when p_type = 'IN' then p_quantity else -p_quantity end;
  v_stock_before := greatest(coalesce(v_product.inventory_qty, 0), coalesce(v_product.stock_quantity, 0));
  v_stock_after := v_stock_before + v_delta;

  if v_stock_after < 0 then
    raise exception 'Stock cannot go negative for product %', coalesce(v_product.name, p_product_id::text)
      using errcode = 'check_violation';
  end if;

  case p_reason_type
    when 'count' then
      v_adjustment_type := case when p_type = 'IN' then 'count_gain' else 'count_loss' end;
      v_reason_label := 'Regularización por conteo';
    when 'loss' then
      v_adjustment_type := 'loss';
      v_reason_label := 'Merma';
    when 'damage' then
      v_adjustment_type := 'damage';
      v_reason_label := 'Daño';
    when 'theft' then
      v_adjustment_type := 'theft';
      v_reason_label := 'Robo / extravío';
    when 'internal_use' then
      v_adjustment_type := 'internal_use';
      v_reason_label := 'Uso interno / taller';
    when 'found' then
      v_adjustment_type := 'found';
      v_reason_label := 'Hallazgo / recuperación';
    else
      v_adjustment_type := 'manual';
      v_reason_label := 'Ajuste Manual';
  end case;

  v_reason := case
    when nullif(trim(coalesce(p_note, '')), '') is null then v_reason_label
    else format('%s: %s', v_reason_label, trim(p_note))
  end;

  case v_adjustment_origin
    when 'product_form' then v_adjustment_origin_label := 'Formulario producto';
    when 'mass_edit_panel' then v_adjustment_origin_label := 'Edicion masiva';
    when 'manual_service' then v_adjustment_origin_label := 'Ajuste manual';
    else v_adjustment_origin_label := null;
  end case;

  v_reference := public.get_next_document_number(v_product.tenant_id, 'stock_adjustment');
  v_inventory_value := round(abs(v_delta) * greatest(coalesce(v_product.cost, 0), 0), 2);
  v_description := case
    when v_adjustment_origin_label is null then format('%s %s - %s', v_reason_label, v_reference, v_product.name)
    else format('%s [%s] %s - %s', v_reason_label, v_adjustment_origin_label, v_reference, v_product.name)
  end;

  v_adjustment_id := gen_random_uuid();
  v_source_channel := coalesce(v_adjustment_origin, 'manual_stock_adjustment');
  v_operation_key := format(
    'stock_adjustment:%s:adjust_stock:%s',
    v_adjustment_id,
    coalesce(
      nullif(current_setting('app.inventory_idempotency_key', true), ''),
      gen_random_uuid()::text
    )
  );

  insert into public.inventory_accounting_operations (
    tenant_id,
    operation_key,
    source_channel,
    action,
    document_type,
    document_id,
    actor_id,
    executor,
    before_snapshot,
    after_snapshot,
    context
  ) values (
    v_product.tenant_id,
    v_operation_key,
    v_source_channel,
    'adjust_stock',
    'stock_adjustment',
    v_adjustment_id,
    auth.uid(),
    'database_rpc',
    jsonb_build_object(
      'product_id', v_product.id,
      'stock', v_stock_before,
      'unit_cost', coalesce(v_product.cost, 0)
    ),
    jsonb_build_object(
      'product_id', v_product.id,
      'stock', v_stock_after,
      'unit_cost', coalesce(v_product.cost, 0)
    ),
    jsonb_build_object(
      'adjustment_type', v_adjustment_type,
      'adjustment_origin', v_adjustment_origin,
      'reason', v_reason,
      'effective_at', v_adjustment_date,
      'inventory_value', v_inventory_value,
      'transaction_id', txid_current()::text
    )
  )
  returning id into v_operation_id;

  perform set_config('app.inventory_operation_id', v_operation_id::text, true);
  perform set_config('app.inventory_source_document_type', 'stock_adjustment', true);
  perform set_config('app.inventory_source_document_id', v_adjustment_id::text, true);
  perform set_config('app.inventory_source_channel', v_source_channel, true);

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'accepted',
    'started',
    'stock_adjustment',
    v_adjustment_id,
    jsonb_build_object('action', 'adjust_stock', 'source_channel', v_source_channel)
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'source_snapshotted',
    'completed',
    'stock_adjustment',
    v_adjustment_id,
    jsonb_build_object(
      'product_id', v_product.id,
      'stock_before', v_stock_before,
      'stock_after', v_stock_after,
      'reason', v_reason
    )
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'inventory_planned',
    'completed',
    'product',
    v_product.id,
    jsonb_build_object(
      'signed_delta', v_delta,
      'stock_before', v_stock_before,
      'stock_after', v_stock_after
    )
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'accounting_planned',
    'completed',
    'stock_adjustment',
    v_adjustment_id,
    jsonb_build_object(
      'inventory_value', v_inventory_value,
      'journal_expected', v_inventory_value > 0
    )
  );

  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  update public.products
     set inventory_qty = v_stock_after,
         stock_quantity = v_stock_after,
         updated_at = v_created_at
   where id = v_product.id
     and tenant_id = v_product.tenant_id;

  insert into public.stock_adjustments (
    id,
    tenant_id,
    product_id,
    adjustment_type,
    quantity,
    stock_before,
    stock_after,
    reason,
    reference,
    adjustment_origin,
    adjustment_date,
    created_by,
    created_at
  ) values (
    v_adjustment_id,
    v_product.tenant_id,
    v_product.id,
    v_adjustment_type,
    v_delta,
    v_stock_before,
    v_stock_after,
    v_reason,
    v_reference,
    v_adjustment_origin,
    v_adjustment_date,
    auth.uid(),
    v_created_at
  )
  returning id into v_adjustment_id;

  if v_inventory_value > 0 then
    v_inventory_account_id := public.ensure_account(
      v_product.tenant_id,
      '1105',
      'Inventario de Productos',
      'asset',
      'currentAsset',
      'Valor de productos y repuestos en stock',
      null
    );

    if p_type = 'OUT' then
      case p_reason_type
        when 'internal_use' then
          v_counterpart_account_code := '5101';
          v_counterpart_account_name := 'Consumibles de Taller';
        when 'damage' then
          v_counterpart_account_code := '6196';
          v_counterpart_account_name := 'Pérdidas por Daño de Inventario';
        when 'theft' then
          v_counterpart_account_code := '6197';
          v_counterpart_account_name := 'Pérdidas por Robo de Inventario';
        when 'loss' then
          v_counterpart_account_code := '6195';
          v_counterpart_account_name := 'Mermas de Inventario';
        else
          v_counterpart_account_code := '6198';
          v_counterpart_account_name := 'Diferencias de Inventario';
      end case;

      v_counterpart_account_id := public.ensure_account(
        v_product.tenant_id,
        v_counterpart_account_code,
        v_counterpart_account_name,
        'expense',
        'operatingExpense',
        'Ajustes negativos de inventario registrados manualmente',
        null
      );
    else
      case p_reason_type
        when 'found' then
          v_counterpart_account_code := '4202';
          v_counterpart_account_name := 'Recuperaciones de Inventario';
        else
          v_counterpart_account_code := '4203';
          v_counterpart_account_name := 'Ajustes Positivos de Inventario';
      end case;

      v_counterpart_account_id := public.ensure_account(
        v_product.tenant_id,
        v_counterpart_account_code,
        v_counterpart_account_name,
        'income',
        'nonOperatingIncome',
        'Ingresos no operacionales derivados de ajustes positivos de inventario',
        null
      );
    end if;

    v_entry_id := gen_random_uuid();
    v_entry_number := public.get_next_document_number(v_product.tenant_id, 'journal_entry');

    insert into public.journal_entries (
      id,
      tenant_id,
      entry_number,
      entry_date,
      description,
      type,
      source_module,
      source_reference,
      status,
      total_debit,
      total_credit,
      created_at,
      updated_at
    ) values (
      v_entry_id,
      v_product.tenant_id,
      v_entry_number,
      v_adjustment_date,
      v_description,
      'adjustment',
      'stock_adjustment',
      v_adjustment_id::text,
      'posted',
      v_inventory_value,
      v_inventory_value,
      v_created_at,
      v_created_at
    );

    if p_type = 'OUT' then
      insert into public.journal_lines (
        id,
        entry_id,
        account_id,
        tenant_id,
        account_code,
        account_name,
        description,
        debit_amount,
        credit_amount,
        created_at,
        updated_at
      ) values (
        gen_random_uuid(),
        v_entry_id,
        v_counterpart_account_id,
        v_product.tenant_id,
        v_counterpart_account_code,
        v_counterpart_account_name,
        v_description,
        v_inventory_value,
        0,
        v_created_at,
        v_created_at
      );

      insert into public.journal_lines (
        id,
        entry_id,
        account_id,
        tenant_id,
        account_code,
        account_name,
        description,
        debit_amount,
        credit_amount,
        created_at,
        updated_at
      ) values (
        gen_random_uuid(),
        v_entry_id,
        v_inventory_account_id,
        v_product.tenant_id,
        '1105',
        'Inventario de Productos',
        v_description,
        0,
        v_inventory_value,
        v_created_at,
        v_created_at
      );
    else
      insert into public.journal_lines (
        id,
        entry_id,
        account_id,
        tenant_id,
        account_code,
        account_name,
        description,
        debit_amount,
        credit_amount,
        created_at,
        updated_at
      ) values (
        gen_random_uuid(),
        v_entry_id,
        v_inventory_account_id,
        v_product.tenant_id,
        '1105',
        'Inventario de Productos',
        v_description,
        v_inventory_value,
        0,
        v_created_at,
        v_created_at
      );

      insert into public.journal_lines (
        id,
        entry_id,
        account_id,
        tenant_id,
        account_code,
        account_name,
        description,
        debit_amount,
        credit_amount,
        created_at,
        updated_at
      ) values (
        gen_random_uuid(),
        v_entry_id,
        v_counterpart_account_id,
        v_product.tenant_id,
        v_counterpart_account_code,
        v_counterpart_account_name,
        v_description,
        0,
        v_inventory_value,
        v_created_at,
        v_created_at
      );
    end if;
  end if;

  perform set_config('app.skip_stock_adjustment_trigger', '', true);

  select sm.id
    into v_movement_id
    from public.stock_movements sm
   where sm.tenant_id = v_product.tenant_id
     and sm.product_id = v_product.id
     and sm.created_at = v_created_at
     and sm.movement_type = v_adjustment_type
   order by sm.id desc
   limit 1;

  perform public.complete_inventory_accounting_operation(
    v_operation_id,
    v_product.tenant_id,
    jsonb_build_object(
      'adjustment_id', v_adjustment_id,
      'movement_id', v_movement_id,
      'journal_entry_id', v_entry_id
    )
  );

  perform set_config('app.inventory_operation_id', '', true);
  perform set_config('app.inventory_source_document_type', '', true);
  perform set_config('app.inventory_source_document_id', '', true);
  perform set_config('app.inventory_source_channel', '', true);

  return jsonb_build_object(
    'operation_id', v_operation_id,
    'adjustment_id', v_adjustment_id,
    'movement_id', v_movement_id,
    'reference_number', v_reference,
    'product_id', v_product.id,
    'product_name', v_product.name,
    'product_sku', v_product.sku,
    'type', p_type,
    'adjustment_type', v_adjustment_type,
    'quantity', v_delta,
    'stock_before', v_stock_before,
    'stock_after', v_stock_after,
    'reason', v_reason,
    'adjustment_origin', v_adjustment_origin,
    'adjustment_date', v_adjustment_date,
    'created_at', v_created_at,
    'journal_entry_id', v_entry_id,
    'journal_entry_number', v_entry_number,
    'inventory_value', v_inventory_value
  );
exception
  when others then
    perform set_config('app.skip_stock_adjustment_trigger', '', true);
    perform set_config('app.inventory_operation_id', '', true);
    perform set_config('app.inventory_source_document_type', '', true);
    perform set_config('app.inventory_source_document_id', '', true);
    perform set_config('app.inventory_source_channel', '', true);
    raise;
end;
$$;

grant execute on function public.apply_inventory_stock_adjustment(uuid, integer, text, text, text, timestamp with time zone, text) to authenticated;

commit;
