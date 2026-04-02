-- Purchase treatment for mixed supplier invoices:
-- inventory items increase stock/assets, workshop consumables go direct to cost.

alter table public.products
  add column if not exists purchase_treatment text not null default 'inventory';

update public.products
   set purchase_treatment = 'inventory'
 where purchase_treatment is null
    or purchase_treatment not in ('inventory', 'workshop_consumable');

update public.products
   set purchase_treatment = 'inventory',
       track_stock = false,
       inventory_qty = 0,
       stock_quantity = 0,
       min_stock_level = 0,
       max_stock_level = 0
 where product_type = 'service';

update public.products
   set purchase_treatment = 'workshop_consumable'
 where product_type = 'product'
   and coalesce(track_stock, true) = false
  and greatest(coalesce(inventory_qty, 0), coalesce(stock_quantity, 0)) = 0
   and coalesce(purchase_treatment, 'inventory') = 'inventory';

update public.products
   set track_stock = false,
       inventory_qty = 0,
       stock_quantity = 0,
       min_stock_level = 0,
       max_stock_level = 0
 where product_type = 'product'
  and purchase_treatment = 'workshop_consumable'
  and greatest(coalesce(inventory_qty, 0), coalesce(stock_quantity, 0)) = 0;

create or replace function public.sync_product_service_flags()
returns trigger
language plpgsql
as $$
declare
  v_old_tracks_inventory boolean := false;
  v_new_tracks_inventory boolean := false;
  v_existing_stock integer := 0;
begin
  if NEW.product_type is null then
    NEW.product_type := 'product';
  end if;

  if NEW.purchase_treatment is null or
     NEW.purchase_treatment not in ('inventory', 'workshop_consumable') then
    NEW.purchase_treatment := 'inventory';
  end if;

  NEW.is_service := (NEW.product_type = 'service');

  if TG_OP = 'UPDATE' then
    v_old_tracks_inventory :=
      coalesce(OLD.product_type, 'product') <> 'service'
      and coalesce(OLD.purchase_treatment, 'inventory') = 'inventory'
      and coalesce(OLD.track_stock, true) = true;

    v_new_tracks_inventory :=
      NEW.product_type <> 'service'
      and NEW.purchase_treatment = 'inventory'
      and coalesce(NEW.track_stock, true) = true;

    v_existing_stock := greatest(
      coalesce(OLD.inventory_qty, 0),
      coalesce(OLD.stock_quantity, 0)
    );

    if v_old_tracks_inventory
       and not v_new_tracks_inventory
       and v_existing_stock > 0 then
      raise exception
        'No se puede desactivar el control de inventario para el producto % mientras tenga stock (% unidades).',
        coalesce(NEW.name, OLD.name, 'sin nombre'),
        v_existing_stock
        using errcode = 'check_violation',
              hint = 'Primero deja el stock en 0 y reclasifica el valor contable antes de cambiarlo a consumible de taller o servicio.';
    end if;
  end if;

  if NEW.is_service then
    NEW.purchase_treatment := 'inventory';
    NEW.track_stock := false;
    NEW.inventory_qty := 0;
    NEW.stock_quantity := 0;
    NEW.min_stock_level := 0;
    NEW.max_stock_level := 0;
  elsif NEW.purchase_treatment = 'workshop_consumable' then
    NEW.track_stock := false;
    NEW.inventory_qty := 0;
    NEW.stock_quantity := 0;
    NEW.min_stock_level := 0;
    NEW.max_stock_level := 0;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_sync_product_service_flags on public.products;
create trigger trg_sync_product_service_flags
  before insert or update of product_type, purchase_treatment, is_service, track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
  on public.products
  for each row
  execute function public.sync_product_service_flags();

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
      'Materiales y consumibles de uso rapido aplicados directamente en el taller',
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

insert into public.accounts (tenant_id, code, name, type, category, description, is_active)
select t.id,
       '5101',
       'Consumibles de Taller',
       'expense',
       'costOfGoodsSold',
       'Materiales y consumibles de uso rapido aplicados directamente en el taller',
       true
  from public.tenants t
 where not exists (
   select 1
     from public.accounts a
    where a.tenant_id = t.id
      and a.code = '5101'
 );

create or replace function public.consume_purchase_invoice_inventory(p_invoice public.purchase_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_item record;
  v_items jsonb;
  v_resolved_product_id uuid;
  v_quantity_numeric numeric;
  v_quantity_int integer;
  v_is_set boolean;
  v_child record;
  v_child_qty integer;
begin
  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  if p_invoice.id is null then
    raise notice 'consume_purchase_invoice_inventory: invoice ID is null, returning';
    return;
  end if;

  v_items := p_invoice.items;
  if v_items is null or jsonb_array_length(v_items) = 0 then
    raise notice 'consume_purchase_invoice_inventory: no items for invoice %', p_invoice.id;
    return;
  end if;

  v_reference := format('purchase_invoice:%s', p_invoice.id);

  for v_item in
    select
      nullif(item->>'product_id', '')::uuid as product_id,
      (item->>'product_name')::text as product_name,
      coalesce(nullif(item->>'purchase_treatment', ''), 'inventory')::text as purchase_treatment,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(v_items) as item
  loop
    v_resolved_product_id := v_item.product_id;
    if v_resolved_product_id is null then
      raise notice 'consume_purchase_invoice_inventory: skipping item with null product_id';
      continue;
    end if;

    v_quantity_numeric := coalesce(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);

    if v_quantity_int = 0 then
      raise notice 'consume_purchase_invoice_inventory: skipping item % with zero quantity', v_resolved_product_id;
      continue;
    end if;

    if v_item.purchase_treatment = 'workshop_consumable' then
      raise notice 'consume_purchase_invoice_inventory: skipping workshop consumable item %', v_resolved_product_id;
      continue;
    end if;

    select is_set into v_is_set from public.products where id = v_resolved_product_id;

    if v_is_set then
      raise notice 'consume_purchase_invoice_inventory: exploding set % into components', v_resolved_product_id;

      for v_child in
        select component_product_id, quantity_in_set
          from public.product_set_components
         where set_product_id = v_resolved_product_id
      loop
        v_child_qty := v_quantity_int * v_child.quantity_in_set;

        update public.products
           set inventory_qty = inventory_qty + v_child_qty,
               stock_quantity = stock_quantity + v_child_qty
         where id = v_child.component_product_id;

        insert into public.stock_movements (
          tenant_id,
          product_id,
          quantity,
          movement_type,
          type,
          reference,
          notes,
          date,
          created_at,
          updated_at
        ) values (
          p_invoice.tenant_id,
          v_child.component_product_id,
          v_child_qty,
          'purchase_invoice',
          'IN',
          v_reference,
          format('Entrada por compra de set %s (Factura %s)', v_item.product_name, p_invoice.invoice_number),
          p_invoice.date,
          now(),
          now()
        );
      end loop;
    else
      update public.products
         set inventory_qty = inventory_qty + v_quantity_int,
             stock_quantity = stock_quantity + v_quantity_int
       where id = v_resolved_product_id;

      insert into public.stock_movements (
        tenant_id,
        product_id,
        quantity,
        movement_type,
        type,
        reference,
        notes,
        date,
        created_at,
        updated_at
      ) values (
        p_invoice.tenant_id,
        v_resolved_product_id,
        v_quantity_int,
        'purchase_invoice',
        'IN',
        v_reference,
        format('Entrada segun factura compra %s', p_invoice.invoice_number),
        p_invoice.date,
        now(),
        now()
      );
    end if;
  end loop;

  raise notice 'consume_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;

create or replace function public.restore_purchase_invoice_inventory(p_invoice public.purchase_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_item record;
  v_items jsonb;
  v_resolved_product_id uuid;
  v_quantity_numeric numeric;
  v_quantity_int integer;
  v_is_set boolean;
  v_child record;
  v_child_qty integer;
begin
  if p_invoice.id is null then
    raise notice 'restore_purchase_invoice_inventory: invoice ID is null, returning';
    return;
  end if;

  v_items := p_invoice.items;
  if v_items is null or jsonb_array_length(v_items) = 0 then
    raise notice 'restore_purchase_invoice_inventory: no items for invoice %', p_invoice.id;
    return;
  end if;

  v_reference := format('purchase_invoice:%s', p_invoice.id);

  delete from public.stock_movements
   where reference = v_reference;

  for v_item in
    select
      nullif(item->>'product_id', '')::uuid as product_id,
      coalesce(nullif(item->>'purchase_treatment', ''), 'inventory')::text as purchase_treatment,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(v_items) as item
  loop
    v_resolved_product_id := v_item.product_id;
    if v_resolved_product_id is null then
      continue;
    end if;

    v_quantity_numeric := coalesce(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);

    if v_quantity_int = 0 then
      continue;
    end if;

    if v_item.purchase_treatment = 'workshop_consumable' then
      continue;
    end if;

    select is_set into v_is_set from public.products where id = v_resolved_product_id;

    if v_is_set then
      for v_child in
        select component_product_id, quantity_in_set
          from public.product_set_components
         where set_product_id = v_resolved_product_id
      loop
        v_child_qty := v_quantity_int * v_child.quantity_in_set;

        update public.products
           set inventory_qty = greatest(inventory_qty - v_child_qty, 0),
               stock_quantity = greatest(stock_quantity - v_child_qty, 0)
         where id = v_child.component_product_id;
      end loop;
    else
      update public.products
         set inventory_qty = greatest(inventory_qty - v_quantity_int, 0),
             stock_quantity = greatest(stock_quantity - v_quantity_int, 0)
       where id = v_resolved_product_id;
    end if;
  end loop;

  raise notice 'restore_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;

create or replace function public.create_purchase_invoice_journal_entry(p_invoice public.purchase_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_inventory_account_id uuid;
  v_workshop_consumables_account_id uuid;
  v_iva_account_id uuid;
  v_payable_account_id uuid;
  v_description text;
  v_items jsonb := '[]'::jsonb;
  v_item record;
  v_inventory_subtotal numeric(12,2) := 0;
  v_workshop_subtotal numeric(12,2) := 0;
  v_total_item_subtotal numeric(12,2) := 0;
  v_scaled_subtotal numeric(12,2) := 0;
  v_subtotal_delta numeric(12,2) := 0;
begin
  raise notice 'START create_purchase_invoice_journal_entry for invoice %', p_invoice.id;

  if p_invoice.id is null then
    raise notice 'Invoice ID is null, returning';
    return;
  end if;

  select exists (
    select 1
      from public.journal_entries
     where source_module = 'purchase_invoices'
       and source_reference = p_invoice.id::text
  ) into v_exists;

  if v_exists then
    raise notice 'Entry already exists for invoice %, skipping', p_invoice.id;
    return;
  end if;

  v_inventory_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '1105',
    'Inventarios',
    'asset',
    'currentAsset',
    'Valor del inventario de productos',
    null
  );

  v_workshop_consumables_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '5101',
    'Consumibles de Taller',
    'expense',
    'costOfGoodsSold',
    'Materiales y consumibles de uso rapido aplicados directamente en el taller',
    null
  );

  v_iva_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '2120',
    'IVA Credito Fiscal',
    'asset',
    'currentAsset',
    'IVA pagado en compras, recuperable',
    null
  );

  v_payable_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '2101',
    'Cuentas por Pagar Proveedores',
    'liability',
    'currentLiability',
    'Obligaciones con proveedores',
    null
  );

  v_description := format(
    'Factura compra %s - %s',
    p_invoice.invoice_number,
    coalesce(p_invoice.supplier_name, 'Proveedor')
  );

  v_items := coalesce(p_invoice.items, '[]'::jsonb);

  for v_item in
    select
      coalesce(nullif(item->>'purchase_treatment', ''), 'inventory')::text as purchase_treatment,
      greatest(
        (coalesce((item->>'quantity')::numeric, 0) *
         coalesce((item->>'unit_cost')::numeric, 0)) -
        coalesce((item->>'discount')::numeric, 0),
        0
      )::numeric(12,2) as line_subtotal
    from jsonb_array_elements(v_items) as item
  loop
    if coalesce(v_item.line_subtotal, 0) <= 0 then
      continue;
    end if;

    v_total_item_subtotal := v_total_item_subtotal + v_item.line_subtotal;

    if v_item.purchase_treatment = 'workshop_consumable' then
      v_workshop_subtotal := v_workshop_subtotal + v_item.line_subtotal;
    else
      v_inventory_subtotal := v_inventory_subtotal + v_item.line_subtotal;
    end if;
  end loop;

  v_scaled_subtotal := coalesce(p_invoice.subtotal, 0);

  if v_total_item_subtotal <= 0 then
    v_inventory_subtotal := v_scaled_subtotal;
    v_workshop_subtotal := 0;
  elsif abs(v_total_item_subtotal - v_scaled_subtotal) > 0.01 then
    v_inventory_subtotal := round((v_inventory_subtotal / v_total_item_subtotal) * v_scaled_subtotal, 2);
    v_workshop_subtotal := round((v_workshop_subtotal / v_total_item_subtotal) * v_scaled_subtotal, 2);
    v_subtotal_delta := round(v_scaled_subtotal - v_inventory_subtotal - v_workshop_subtotal, 2);

    if v_subtotal_delta <> 0 then
      if v_inventory_subtotal >= v_workshop_subtotal then
        v_inventory_subtotal := v_inventory_subtotal + v_subtotal_delta;
      else
        v_workshop_subtotal := v_workshop_subtotal + v_subtotal_delta;
      end if;
    end if;
  end if;

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
    p_invoice.tenant_id,
    public.get_next_document_number(p_invoice.tenant_id, 'journal_entry'),
    coalesce(p_invoice.date, now()),
    v_description,
    'purchase',
    'purchase_invoices',
    p_invoice.invoice_number,
    'posted',
    p_invoice.total,
    p_invoice.total,
    now(),
    now()
  );

  if v_inventory_subtotal > 0 then
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
      p_invoice.tenant_id,
      '1105',
      'Inventarios',
      v_description,
      v_inventory_subtotal,
      0,
      now(),
      now()
    );
  end if;

  if v_workshop_subtotal > 0 then
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
      p_invoice.tenant_id,
      '5101',
      'Consumibles de Taller',
      v_description,
      v_workshop_subtotal,
      0,
      now(),
      now()
    );
  end if;

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
    v_iva_account_id,
    p_invoice.tenant_id,
    '2120',
    'IVA Credito Fiscal',
    v_description,
    p_invoice.tax,
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
    v_payable_account_id,
    p_invoice.tenant_id,
    '2101',
    'Cuentas por Pagar Proveedores',
    v_description,
    0,
    p_invoice.total,
    now(),
    now()
  );

  raise notice 'Journal entry created successfully for invoice %', p_invoice.id;
end;
$$;

create or replace function public.consume_sales_invoice_inventory(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
  v_resolved_product_id uuid;
  v_quantity_int integer;
  v_status text;
  v_reference text;
  v_items_count integer;
  v_is_set boolean;
  v_component record;
  v_qty_to_deduct integer;
  v_set_name text;
begin
  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  if p_invoice.id is null then
    raise notice 'consume_sales_invoice_inventory: invoice ID is null';
    return;
  end if;

  v_status := lower(coalesce(p_invoice.status, 'draft'));

  if v_status = any (array['draft','borrador','cancelled','cancelado','cancelada','anulado','anulada']) then
    return;
  end if;

  v_reference := concat('sales_invoice:', p_invoice.id::text);
  if exists (
       select 1
         from public.stock_movements
        where reference = v_reference
          and type = 'OUT'
     ) then
    return;
  end if;

  select jsonb_array_length(coalesce(p_invoice.items, '[]'::jsonb))
    into v_items_count;

  for v_item in
    select
      nullif(item->>'product_id', '')::uuid as product_id,
      (item->>'product_sku')::text as product_sku,
      coalesce(nullif(item->>'purchase_treatment', ''), 'inventory')::text as purchase_treatment,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(coalesce(p_invoice.items, '[]'::jsonb)) item
  loop
    v_resolved_product_id := v_item.product_id;

    if v_resolved_product_id is null and v_item.product_sku is not null and v_item.product_sku != '' then
      select id
        into v_resolved_product_id
        from public.products
       where sku = v_item.product_sku
       limit 1;
    end if;

    v_quantity_int := coalesce(v_item.quantity::int, 0);

    if v_resolved_product_id is null or v_quantity_int <= 0 then
      continue;
    end if;

    if v_item.purchase_treatment = 'workshop_consumable' then
      continue;
    end if;

    select is_set, name
      into v_is_set, v_set_name
      from public.products
     where id = v_resolved_product_id
       and coalesce(track_stock, true) = true;

    if not found then
      continue;
    end if;

    if v_is_set then
       for v_component in
         select
           component_product_id,
           quantity_in_set
         from public.product_set_components
         where set_product_id = v_resolved_product_id
       loop
          v_qty_to_deduct := v_quantity_int * v_component.quantity_in_set;

          update public.products
             set inventory_qty = coalesce(inventory_qty, 0) - v_qty_to_deduct,
                 stock_quantity = greatest(coalesce(stock_quantity, 0) - v_qty_to_deduct, 0),
                 updated_at = now()
           where id = v_component.component_product_id
             and coalesce(track_stock, true) = true;

          if found then
            insert into public.stock_movements (
              tenant_id, id, product_id, warehouse_id, type, movement_type, quantity,
              reference, notes, date, created_at, updated_at
            ) values (
              p_invoice.tenant_id,
              gen_random_uuid(),
              v_component.component_product_id,
              null,
              'OUT',
              'sales_invoice_component',
              -v_qty_to_deduct,
              v_reference,
              format('Salida por venta de Set "%s" (Factura %s)',
                     v_set_name,
                     coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text)
              ),
              coalesce(p_invoice.date, now()),
              now(),
              now()
            );
          end if;
       end loop;

    else
      update public.products
         set inventory_qty = coalesce(inventory_qty, 0) - v_quantity_int,
             stock_quantity = greatest(coalesce(stock_quantity, 0) - v_quantity_int, 0),
             updated_at = now()
       where id = v_resolved_product_id
         and coalesce(is_service, false) = false
         and coalesce(track_stock, true) = true;

      if found then
        insert into public.stock_movements (
          tenant_id, id, product_id, warehouse_id, type, movement_type, quantity,
          reference, notes, date, created_at, updated_at
        ) values (
          p_invoice.tenant_id,
          gen_random_uuid(),
          v_resolved_product_id,
          null,
          'OUT',
          'sale',
          -v_quantity_int,
          v_reference,
          concat('Salida por venta (Factura ', coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text), ')'),
          coalesce(p_invoice.date, now()),
          now(),
          now()
        );
      end if;
    end if;
  end loop;

  raise notice 'consume_sales_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;

create or replace function public.create_sales_invoice_journal_entry(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_receivable_account_code text := '1130';
  v_receivable_account_name text := 'Cuentas por Cobrar Comerciales';
  v_receivable_account_id uuid;
  v_revenue_account_code text := '4100';
  v_revenue_account_name text := 'Ingresos Operacionales';
  v_revenue_account_id uuid;
  v_iva_account_code text := '2150';
  v_iva_account_name text := 'IVA Débito Fiscal';
  v_iva_account_id uuid;
  v_inventory_account_code text := '1105';
  v_inventory_account_name text := 'Inventarios';
  v_inventory_account_id uuid;
  v_cogs_account_code text := '5100';
  v_cogs_account_name text := 'Costo de Ventas';
  v_cogs_account_id uuid;
  v_invoice_number text;
  v_customer_name text;
  v_description text;
  v_subtotal numeric(12,2);
  v_iva numeric(12,2);
  v_total numeric(12,2);
  v_total_cost numeric(12,2);
  v_tenant_id uuid;
begin
  if p_invoice.id is null then
    return;
  end if;

  if coalesce(p_invoice.status, 'draft') in ('draft', 'cancelled') then
    return;
  end if;

  v_tenant_id := p_invoice.tenant_id;

  if v_tenant_id is null then
    raise warning 'create_sales_invoice_journal_entry: No tenant_id on invoice %, skipping', p_invoice.id;
    return;
  end if;

  select exists (
           select 1
             from public.journal_entries
            where source_module = 'sales_invoices'
              and source_reference = p_invoice.invoice_number
              and tenant_id = v_tenant_id
       )
    into v_exists;

  if v_exists then
    raise notice 'create_sales_invoice_journal_entry: Entry already exists for invoice %, skipping', p_invoice.invoice_number;
    return;
  end if;

  raise notice 'create_sales_invoice_journal_entry: Creating entry for invoice % (status: %)', p_invoice.invoice_number, p_invoice.status;

  v_subtotal := coalesce(nullif(p_invoice.net_amount, 0), p_invoice.subtotal, 0);
  v_iva := coalesce(nullif(p_invoice.iva_amount, 0), 0);

  if p_invoice.tax_treatment = 'tax_included' and (v_iva = 0 or v_subtotal = p_invoice.total) then
    v_subtotal := round(p_invoice.total / 1.19, 2);
    v_iva := p_invoice.total - v_subtotal;
  end if;

  v_total := coalesce(p_invoice.total, v_subtotal + v_iva);

  if v_total = 0 then
    return;
  end if;

  v_receivable_account_id := public.ensure_account(
    v_tenant_id,
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_revenue_account_id := public.ensure_account(
    v_tenant_id,
    v_revenue_account_code,
    v_revenue_account_name,
    'income',
    'operatingIncome',
    'Ingresos operacionales por ventas',
    null
  );

  v_iva_account_id := public.ensure_account(
    v_tenant_id,
    v_iva_account_code,
    v_iva_account_name,
    'liability',
    'currentLiability',
    'IVA generado en ventas',
    null
  );

  select coalesce(
           sum(
             case
               when coalesce((item->>'is_service')::boolean, false) then 0
               when coalesce(nullif(item->>'purchase_treatment', ''), 'inventory') = 'workshop_consumable' then 0
               else coalesce((item->>'quantity')::numeric, 0) * coalesce((item->>'cost')::numeric, 0)
             end
           ),
           0
         )
    into v_total_cost
    from jsonb_array_elements(coalesce(p_invoice.items, '[]'::jsonb)) item
   where (item->>'cost') is not null
     and (item->>'cost') <> '';

  if v_total_cost > 0 then
    v_inventory_account_id := public.ensure_account(
      v_tenant_id,
      v_inventory_account_code,
      v_inventory_account_name,
      'asset',
      'currentAsset',
      'Inventario disponible para la venta',
      null
    );

    v_cogs_account_id := public.ensure_account(
      v_tenant_id,
      v_cogs_account_code,
      v_cogs_account_name,
      'expense',
      'costOfGoodsSold',
      'Costo de ventas',
      null
    );
  end if;

  v_invoice_number := coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text);
  v_customer_name := coalesce(nullif(p_invoice.customer_name, ''), 'Cliente');
  v_description := format('Factura %s - %s', v_invoice_number, v_customer_name);

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
    v_tenant_id,
    public.get_next_document_number(v_tenant_id, 'journal_entry'),
    coalesce(p_invoice.date, now()),
    v_description,
    'sales',
    'sales_invoices',
    p_invoice.invoice_number,
    'posted',
    v_total,
    v_total,
    now(),
    now()
  );

  insert into public.journal_lines (
    id,
    tenant_id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_tenant_id,
    v_entry_id,
    v_receivable_account_id,
    v_receivable_account_code,
    v_receivable_account_name,
    v_description,
    v_total,
    0,
    now(),
    now()
  );

  if v_total - v_iva <> 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_revenue_account_id,
      v_revenue_account_code,
      v_revenue_account_name,
      format('Ingreso por venta %s', v_invoice_number),
      0,
      v_total - v_iva,
      now(),
      now()
    );
  end if;

  if v_iva <> 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_iva_account_id,
      v_iva_account_code,
      v_iva_account_name,
      format('IVA débito factura %s', v_invoice_number),
      0,
      v_iva,
      now(),
      now()
    );
  end if;

  if v_total_cost > 0 then
    insert into public.journal_lines (
      id,
      tenant_id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_cogs_account_id,
      v_cogs_account_code,
      v_cogs_account_name,
      format('Costo de ventas %s', v_invoice_number),
      v_total_cost,
      0,
      now(),
      now()
    ), (
      gen_random_uuid(),
      v_tenant_id,
      v_entry_id,
      v_inventory_account_id,
      v_inventory_account_code,
      v_inventory_account_name,
      format('Salida inventario factura %s', v_invoice_number),
      0,
      v_total_cost,
      now(),
      now()
    );
  end if;
end;
$$;
