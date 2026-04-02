-- Preserve reversible product conversion snapshots and add a safe restore RPC.

create or replace function public.convert_product_inventory_to_non_stock(
  p_product_id uuid,
  p_target_purchase_treatment text default 'workshop_consumable',
  p_target_product_type text default 'product',
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.products;
  v_target_purchase_treatment text := coalesce(nullif(p_target_purchase_treatment, ''), 'inventory');
  v_target_product_type text := coalesce(nullif(p_target_product_type, ''), 'product');
  v_existing_stock integer := 0;
  v_inventory_value numeric(14,2) := 0;
  v_effective_reason text;
  v_description text;
  v_reference text;
  v_inventory_account_id uuid;
  v_workshop_consumables_account_id uuid;
  v_entry_id uuid;
  v_original_state jsonb;
  v_original_product_snapshot jsonb;
begin
  if p_product_id is null then
    raise exception 'Product ID is required';
  end if;

  if v_target_purchase_treatment not in ('inventory', 'workshop_consumable') then
    raise exception 'Invalid target purchase_treatment: %', v_target_purchase_treatment;
  end if;

  if v_target_product_type not in ('product', 'service') then
    raise exception 'Invalid target product_type: %', v_target_product_type;
  end if;

  select *
    into v_product
    from public.products
   where id = p_product_id
     and tenant_id = public.user_tenant_id()
   for update;

  if not found then
    raise exception 'Product not found or not accessible';
  end if;

  if coalesce(v_product.product_type, 'product') = 'service'
     or coalesce(v_product.purchase_treatment, 'inventory') <> 'inventory'
     or coalesce(v_product.track_stock, true) = false then
    raise exception 'Product % is not currently a stock-tracked inventory item', v_product.name;
  end if;

  if v_target_product_type = 'product'
     and v_target_purchase_treatment = 'inventory' then
    raise exception 'Target state still tracks inventory; conversion is not required';
  end if;

  v_existing_stock := greatest(
    coalesce(v_product.inventory_qty, 0),
    coalesce(v_product.stock_quantity, 0)
  );

  if v_existing_stock <= 0 then
    raise exception 'Product % has no stock to convert', v_product.name;
  end if;

  v_inventory_value := round(v_existing_stock * greatest(coalesce(v_product.cost, 0), 0), 2);
  v_effective_reason := coalesce(
    nullif(trim(p_reason), ''),
    case
      when v_target_product_type = 'service' then 'Conversión de inventario a servicio'
      else 'Conversión de inventario a consumible de taller'
    end
  );
  v_description := format('%s - %s', v_effective_reason, v_product.name);
  v_reference := format('product_conversion:%s:%s', v_product.id, extract(epoch from clock_timestamp())::bigint);
  v_original_state := jsonb_build_object(
    'purchase_treatment', coalesce(v_product.purchase_treatment, 'inventory'),
    'product_type', coalesce(v_product.product_type, 'product'),
    'track_stock', coalesce(v_product.track_stock, true),
    'inventory_qty', coalesce(v_product.inventory_qty, 0),
    'stock_quantity', coalesce(v_product.stock_quantity, 0),
    'min_stock_level', coalesce(v_product.min_stock_level, 0),
    'max_stock_level', coalesce(v_product.max_stock_level, 0)
  );
  v_original_product_snapshot := to_jsonb(v_product);

  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  update public.products
     set inventory_qty = 0,
         stock_quantity = 0,
         updated_at = now()
   where id = v_product.id;

  insert into public.stock_adjustments (
    tenant_id,
    product_id,
    adjustment_type,
    quantity,
    stock_before,
    stock_after,
    reason,
    reference,
    created_by,
    created_at
  ) values (
    v_product.tenant_id,
    v_product.id,
    'correction',
    -v_existing_stock,
    v_existing_stock,
    0,
    v_effective_reason,
    v_reference,
    auth.uid(),
    now()
  );

  if v_inventory_value > 0 then
    v_inventory_account_id := public.ensure_account(
      v_product.tenant_id,
      '1105',
      'Inventarios',
      'asset',
      'currentAsset',
      'Valor del inventario de productos',
      null
    );

    v_workshop_consumables_account_id := public.ensure_account(
      v_product.tenant_id,
      '5101',
      'Consumibles de Taller',
      'expense',
      'costOfGoodsSold',
      'Materiales y consumibles de uso rápido aplicados directamente en el taller',
      null
    );

    v_entry_id := gen_random_uuid();

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
      public.get_next_document_number(v_product.tenant_id, 'journal_entry'),
      now(),
      v_description,
      'adjustment',
      'product_conversion',
      v_product.id::text,
      'posted',
      v_inventory_value,
      v_inventory_value,
      now(),
      now()
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
      v_workshop_consumables_account_id,
      v_product.tenant_id,
      '5101',
      'Consumibles de Taller',
      v_description,
      v_inventory_value,
      0,
      now(),
      now()
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
      'Inventarios',
      v_description,
      0,
      v_inventory_value,
      now(),
      now()
    );
  end if;

  update public.products
     set purchase_treatment = v_target_purchase_treatment,
         product_type = v_target_product_type,
         updated_at = now()
   where id = v_product.id
   returning * into v_product;

  insert into public.user_activity_log (
    tenant_id,
    user_id,
    action,
    details,
    performed_by,
    created_at
  ) values (
    v_product.tenant_id,
    auth.uid(),
    'product_conversion',
    jsonb_build_object(
      'product_id', v_product.id,
      'product_name', v_product.name,
      'conversion_reference', v_reference,
      'conversion_reason', v_effective_reason,
      'target_purchase_treatment', v_target_purchase_treatment,
      'target_product_type', v_target_product_type,
      'converted_quantity', v_existing_stock,
      'inventory_value', v_inventory_value,
      'journal_entry_id', v_entry_id,
      'original_state', v_original_state,
      'original_product_snapshot', v_original_product_snapshot,
      'converted_state', jsonb_build_object(
        'purchase_treatment', coalesce(v_product.purchase_treatment, 'inventory'),
        'product_type', coalesce(v_product.product_type, 'product'),
        'track_stock', coalesce(v_product.track_stock, true),
        'inventory_qty', coalesce(v_product.inventory_qty, 0),
        'stock_quantity', coalesce(v_product.stock_quantity, 0),
        'min_stock_level', coalesce(v_product.min_stock_level, 0),
        'max_stock_level', coalesce(v_product.max_stock_level, 0)
      ),
      'restored', false
    ),
    auth.uid(),
    now()
  );

  perform set_config('app.skip_stock_adjustment_trigger', '', true);

  return jsonb_build_object(
    'product', to_jsonb(v_product),
    'converted_quantity', v_existing_stock,
    'inventory_value', v_inventory_value,
    'reference', v_reference,
    'journal_entry_id', v_entry_id
  );
exception
  when others then
    perform set_config('app.skip_stock_adjustment_trigger', '', true);
    raise;
end;
$$;

grant execute on function public.convert_product_inventory_to_non_stock(uuid, text, text, text) to authenticated;

create or replace function public.restore_product_conversion_state(
  p_product_id uuid,
  p_reason text default null,
  p_restore_inventory boolean default false,
  p_conversion_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.products;
  v_log public.user_activity_log;
  v_original_state jsonb;
  v_restore_reason text;
  v_restore_reference text;
  v_original_purchase_treatment text;
  v_original_product_type text;
  v_original_track_stock boolean;
  v_original_inventory_qty integer := 0;
  v_original_stock_qty integer := 0;
  v_original_min_stock integer := 0;
  v_original_max_stock integer := 0;
  v_inventory_value numeric(14,2) := 0;
  v_blocking_activity_count integer := 0;
  v_inventory_account_id uuid;
  v_workshop_consumables_account_id uuid;
  v_entry_id uuid;
  v_restored_inventory_qty integer := 0;
  v_restored_stock_qty integer := 0;
begin
  if p_product_id is null then
    raise exception 'Product ID is required';
  end if;

  select *
    into v_product
    from public.products
   where id = p_product_id
     and tenant_id = public.user_tenant_id()
   for update;

  if not found then
    raise exception 'Product not found or not accessible';
  end if;

  select *
    into v_log
    from public.user_activity_log
   where tenant_id = v_product.tenant_id
     and action = 'product_conversion'
     and details->>'product_id' = v_product.id::text
     and coalesce((details->>'restored')::boolean, false) = false
     and (
       p_conversion_reference is null
       or details->>'conversion_reference' = p_conversion_reference
     )
   order by created_at desc
   limit 1
   for update;

  if not found then
    raise exception 'No unreversed product conversion snapshot found for product %', v_product.name;
  end if;

  v_original_state := v_log.details->'original_state';

  if v_original_state is null then
    raise exception 'The selected conversion does not contain a reversible snapshot';
  end if;

  v_original_purchase_treatment := coalesce(v_original_state->>'purchase_treatment', 'inventory');
  v_original_product_type := coalesce(v_original_state->>'product_type', 'product');
  v_original_track_stock := coalesce((v_original_state->>'track_stock')::boolean, true);
  v_original_inventory_qty := coalesce((v_original_state->>'inventory_qty')::integer, 0);
  v_original_stock_qty := coalesce((v_original_state->>'stock_quantity')::integer, 0);
  v_original_min_stock := coalesce((v_original_state->>'min_stock_level')::integer, 0);
  v_original_max_stock := coalesce((v_original_state->>'max_stock_level')::integer, 0);
  v_inventory_value := coalesce((v_log.details->>'inventory_value')::numeric, 0);
  v_restore_reason := coalesce(
    nullif(trim(p_reason), ''),
    'Restauración de estado original del producto'
  );
  v_restore_reference := format(
    'product_restore:%s:%s',
    v_product.id,
    extract(epoch from clock_timestamp())::bigint
  );

  if p_restore_inventory then
    select case
             when exists (
               select 1
                 from public.stock_adjustments sa
                where sa.tenant_id = v_product.tenant_id
                  and sa.product_id = v_product.id
                  and sa.created_at > v_log.created_at
                  and coalesce(sa.reference, '') <> coalesce(v_log.details->>'conversion_reference', '')
             ) then 1
             when exists (
               select 1
                 from public.stock_movements sm
                where sm.tenant_id = v_product.tenant_id
                  and sm.product_id = v_product.id
                  and sm.created_at > v_log.created_at
             ) then 1
             when exists (
               select 1
                 from public.sales_invoices si
                 cross join lateral jsonb_array_elements(coalesce(si.items, '[]'::jsonb)) item
                where si.tenant_id = v_product.tenant_id
                  and si.created_at > v_log.created_at
                  and lower(coalesce(si.status, 'draft')) not in (
                    'draft','borrador',
                    'sent','enviado','enviada','issued','emitido','emitida',
                    'cancelled','cancelado','cancelada','anulado','anulada'
                  )
                  and nullif(item->>'product_id', '')::uuid = v_product.id
             ) then 1
             when exists (
               select 1
                 from public.purchase_invoices pi
                 cross join lateral jsonb_array_elements(coalesce(pi.items, '[]'::jsonb)) item
                where pi.tenant_id = v_product.tenant_id
                  and pi.created_at > v_log.created_at
                  and pi.status not in ('draft', 'cancelled')
                  and nullif(item->>'product_id', '')::uuid = v_product.id
             ) then 1
             else 0
           end
      into v_blocking_activity_count;

    if v_blocking_activity_count > 0 then
      raise exception
        'No es seguro restaurar stock/valor para el producto % porque hubo actividad después de la conversión.',
        v_product.name
        using errcode = 'check_violation',
              hint = 'Restaura solo la configuración con p_restore_inventory = false, o revisa manualmente compras/ventas posteriores.';
    end if;
  end if;

  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  v_restored_inventory_qty := case when p_restore_inventory then v_original_inventory_qty else 0 end;
  v_restored_stock_qty := case when p_restore_inventory then v_original_stock_qty else 0 end;

  update public.products
     set purchase_treatment = v_original_purchase_treatment,
         product_type = v_original_product_type,
         track_stock = v_original_track_stock,
         inventory_qty = v_restored_inventory_qty,
         stock_quantity = v_restored_stock_qty,
         min_stock_level = v_original_min_stock,
         max_stock_level = v_original_max_stock,
         updated_at = now()
   where id = v_product.id
   returning * into v_product;

  if p_restore_inventory and v_original_inventory_qty > 0 then
    insert into public.stock_adjustments (
      tenant_id,
      product_id,
      adjustment_type,
      quantity,
      stock_before,
      stock_after,
      reason,
      reference,
      created_by,
      created_at
    ) values (
      v_product.tenant_id,
      v_product.id,
      'correction',
      v_original_inventory_qty,
      0,
      v_original_inventory_qty,
      v_restore_reason,
      v_restore_reference,
      auth.uid(),
      now()
    );

    if v_inventory_value > 0 then
      v_inventory_account_id := public.ensure_account(
        v_product.tenant_id,
        '1105',
        'Inventarios',
        'asset',
        'currentAsset',
        'Valor del inventario de productos',
        null
      );

      v_workshop_consumables_account_id := public.ensure_account(
        v_product.tenant_id,
        '5101',
        'Consumibles de Taller',
        'expense',
        'costOfGoodsSold',
        'Materiales y consumibles de uso rápido aplicados directamente en el taller',
        null
      );

      v_entry_id := gen_random_uuid();

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
        public.get_next_document_number(v_product.tenant_id, 'journal_entry'),
        now(),
        format('%s - %s', v_restore_reason, v_product.name),
        'adjustment',
        'product_restore',
        v_product.id::text,
        'posted',
        v_inventory_value,
        v_inventory_value,
        now(),
        now()
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
        'Inventarios',
        format('%s - %s', v_restore_reason, v_product.name),
        v_inventory_value,
        0,
        now(),
        now()
      ), (
        gen_random_uuid(),
        v_entry_id,
        v_workshop_consumables_account_id,
        v_product.tenant_id,
        '5101',
        'Consumibles de Taller',
        format('%s - %s', v_restore_reason, v_product.name),
        0,
        v_inventory_value,
        now(),
        now()
      );
    end if;
  end if;

  update public.user_activity_log
     set details = coalesce(details, '{}'::jsonb) || jsonb_build_object(
       'restored', true,
       'restored_at', now(),
       'restored_by', auth.uid(),
       'restore_reference', v_restore_reference,
       'restored_inventory', p_restore_inventory,
       'restore_journal_entry_id', v_entry_id,
       'restore_reason', v_restore_reason
     )
   where id = v_log.id;

  insert into public.user_activity_log (
    tenant_id,
    user_id,
    action,
    details,
    performed_by,
    created_at
  ) values (
    v_product.tenant_id,
    auth.uid(),
    'product_conversion_restore',
    jsonb_build_object(
      'product_id', v_product.id,
      'product_name', v_product.name,
      'source_conversion_reference', v_log.details->>'conversion_reference',
      'restore_reference', v_restore_reference,
      'restore_reason', v_restore_reason,
      'restored_inventory', p_restore_inventory,
      'restored_inventory_qty', v_restored_inventory_qty,
      'restored_stock_qty', v_restored_stock_qty,
      'journal_entry_id', v_entry_id,
      'product_state_after_restore', jsonb_build_object(
        'purchase_treatment', coalesce(v_product.purchase_treatment, 'inventory'),
        'product_type', coalesce(v_product.product_type, 'product'),
        'track_stock', coalesce(v_product.track_stock, true),
        'inventory_qty', coalesce(v_product.inventory_qty, 0),
        'stock_quantity', coalesce(v_product.stock_quantity, 0),
        'min_stock_level', coalesce(v_product.min_stock_level, 0),
        'max_stock_level', coalesce(v_product.max_stock_level, 0)
      )
    ),
    auth.uid(),
    now()
  );

  perform set_config('app.skip_stock_adjustment_trigger', '', true);

  return jsonb_build_object(
    'product', to_jsonb(v_product),
    'source_conversion_reference', v_log.details->>'conversion_reference',
    'restore_reference', v_restore_reference,
    'restored_inventory', p_restore_inventory,
    'blocking_activity_count', v_blocking_activity_count,
    'journal_entry_id', v_entry_id
  );
exception
  when others then
    perform set_config('app.skip_stock_adjustment_trigger', '', true);
    raise;
end;
$$;

grant execute on function public.restore_product_conversion_state(uuid, text, boolean, text) to authenticated;
