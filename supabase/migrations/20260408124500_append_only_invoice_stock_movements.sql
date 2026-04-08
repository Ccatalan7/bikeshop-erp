-- Make invoice-driven stock movements append-only by writing explicit reversal rows
-- instead of deleting historical movement records.

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
  v_net_quantity integer;
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
  select coalesce(sum(quantity), 0)::integer
    into v_net_quantity
    from public.stock_movements
   where reference = v_reference;

  if v_net_quantity < 0 then
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
        select component_product_id, quantity_in_set
          from public.product_set_components
         where set_product_id = v_resolved_product_id
      loop
        v_qty_to_deduct := v_quantity_int * v_component.quantity_in_set;

        update public.products
           set inventory_qty = coalesce(inventory_qty, 0) - v_qty_to_deduct,
               stock_quantity = greatest(coalesce(stock_quantity, 0) - v_qty_to_deduct, 0),
               updated_at = now()
         where id = v_component.component_product_id;

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
            format(
              'Salida por venta de Set "%s" (Factura %s)',
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

create or replace function public.restore_sales_invoice_inventory(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_movement record;
  v_has_inventory_qty boolean := false;
  v_has_stock_quantity boolean := false;
  v_has_is_service boolean := false;
  v_has_track_stock boolean := false;
  v_has_updated_at boolean := false;
  v_update_assignments text := '';
  v_update_sql text;
  v_quantity_int integer;
begin
  if p_invoice.id is null then
    return;
  end if;

  perform set_config('app.skip_stock_adjustment_trigger', 'true', true);

  v_reference := concat('sales_invoice:', p_invoice.id::text);

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'inventory_qty'
         )
    into v_has_inventory_qty;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'stock_quantity'
         )
    into v_has_stock_quantity;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'is_service'
         )
    into v_has_is_service;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'track_stock'
         )
    into v_has_track_stock;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'updated_at'
         )
    into v_has_updated_at;

  if not v_has_inventory_qty and not v_has_stock_quantity then
    perform set_config('app.skip_stock_adjustment_trigger', '', true);
    return;
  end if;

  if v_has_inventory_qty then
    v_update_assignments := v_update_assignments || 'inventory_qty = coalesce(inventory_qty, 0) + $1';
  end if;

  if v_has_stock_quantity then
    if v_update_assignments <> '' then
      v_update_assignments := v_update_assignments || ', ';
    end if;
    v_update_assignments := v_update_assignments || 'stock_quantity = coalesce(stock_quantity, 0) + $1';
  end if;

  if v_has_updated_at then
    if v_update_assignments <> '' then
      v_update_assignments := v_update_assignments || ', ';
    end if;
    v_update_assignments := v_update_assignments || 'updated_at = now()';
  end if;

  if v_update_assignments = '' then
    perform set_config('app.skip_stock_adjustment_trigger', '', true);
    return;
  end if;

  v_update_sql := 'update public.products set ' || v_update_assignments || ' where id = $2';

  if v_has_is_service then
    v_update_sql := v_update_sql || ' and coalesce(is_service, false) = false';
  end if;

  if v_has_track_stock then
    v_update_sql := v_update_sql || ' and coalesce(track_stock, true) = true';
  end if;

  for v_movement in
    select product_id, abs(sum(quantity))::integer as quantity
      from public.stock_movements
     where reference = v_reference
     group by product_id
    having sum(quantity) < 0
  loop
    if v_movement.product_id is null or v_movement.quantity = 0 then
      continue;
    end if;

    v_quantity_int := abs(coalesce(v_movement.quantity::int, 0));

    if v_quantity_int = 0 then
      continue;
    end if;

    execute v_update_sql using v_quantity_int, v_movement.product_id;

    insert into public.stock_movements (
      tenant_id,
      id,
      product_id,
      warehouse_id,
      type,
      movement_type,
      quantity,
      reference,
      notes,
      date,
      created_at,
      updated_at
    ) values (
      p_invoice.tenant_id,
      gen_random_uuid(),
      v_movement.product_id,
      null,
      'IN',
      'sales_invoice_reversal',
      v_quantity_int,
      v_reference,
      concat(
        'Reversión de salida por factura ',
        coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text)
      ),
      coalesce(p_invoice.date, now()),
      now(),
      now()
    );
  end loop;

  perform set_config('app.skip_stock_adjustment_trigger', '', true);
end;
$$;

drop view if exists stock_movements_view cascade;

create view stock_movements_view as
with movement_documents as (
  select
    sm.id,
    sm.product_id,
    p.name as product_name,
    p.sku as product_sku,
    sm.date as transaction_date,
    sm.type,
    sm.movement_type as raw_movement_type,
    sm.reference,
    case
      when sm.type = 'OUT' then -abs(sm.quantity)
      when sm.type = 'IN' then abs(sm.quantity)
      else sm.quantity
    end as quantity,
    sm.notes,
    null::uuid as created_by,
    sm.created_at,
    sm.tenant_id,
    case
      when coalesce(sm.reference, '') ~ '^sales_invoice:[0-9a-fA-F-]{36}$'
        then split_part(sm.reference, ':', 2)::uuid
      when coalesce(sm.reference, '') ~ '^purchase_invoice:[0-9a-fA-F-]{36}$'
        then split_part(sm.reference, ':', 2)::uuid
      when coalesce(sm.reference, '') ~ '^mechanic_job:[0-9a-fA-F-]{36}$'
        then split_part(sm.reference, ':', 2)::uuid
      else null::uuid
    end as document_id,
    case
      when coalesce(sm.reference, '') like 'sales_invoice:%' then 'sales_invoice'
      when coalesce(sm.reference, '') like 'purchase_invoice:%' then 'purchase_invoice'
      when coalesce(sm.reference, '') like 'mechanic_job:%' then 'mechanic_job'
      else null::text
    end as document_type
  from stock_movements sm
  left join products p
    on nullif(sm.product_id::text, '')::uuid = p.id
   and sm.tenant_id = p.tenant_id
),
movements_with_resolution as (
  select
    md.id,
    md.product_id,
    md.product_name,
    md.product_sku,
    md.transaction_date,
    case
      when md.document_type = 'sales_invoice' then 'sale'
      when md.document_type = 'purchase_invoice' then 'purchase'
      when md.document_type = 'mechanic_job' then 'sale'
      when coalesce(md.raw_movement_type, '') in ('purchase', 'purchase_invoice', 'purchase_invoice_reversal', 'manual_purchase') then 'purchase'
      when coalesce(md.raw_movement_type, '') in ('sale', 'sales_invoice', 'sales_invoice_component', 'sales_invoice_reversal', 'manual_sale') then 'sale'
      when coalesce(md.raw_movement_type, '') in ('transfer', 'transfer_in', 'transfer_out') then 'transfer'
      when coalesce(md.raw_movement_type, '') in ('manual', 'correction', 'initial', 'damage', 'loss', 'found', 'import', 'adjustment', 'inventory_adjust', 'inventory_adjustment', 'count_gain', 'count_loss', 'theft', 'internal_use') then 'adjustment'
      else 'adjustment'
    end as movement_type,
    case
      when md.document_type = 'sales_invoice' and coalesce(md.raw_movement_type, '') = 'sales_invoice_reversal' then 'sales_invoice_reversal'
      when md.document_type = 'sales_invoice' then coalesce(si.source, 'sale')
      when md.document_type = 'purchase_invoice' and coalesce(md.raw_movement_type, '') = 'purchase_invoice_reversal' then 'purchase_invoice_reversal'
      when md.document_type = 'purchase_invoice' then 'purchase_invoice'
      when md.document_type = 'mechanic_job' then 'mechanic_job'
      when nullif(trim(coalesce(md.raw_movement_type, '')), '') is not null then md.raw_movement_type
      else 'manual'
    end as source,
    case
      when md.document_type in ('sales_invoice', 'purchase_invoice', 'mechanic_job') then md.document_id
      when sa.id is not null then sa.id
      else null::uuid
    end as reference_id,
    case
      when md.document_type = 'sales_invoice' then coalesce(nullif(si.invoice_number, ''), md.reference)
      when md.document_type = 'purchase_invoice' then coalesce(nullif(pi.invoice_number, ''), md.reference)
      when md.document_type = 'mechanic_job' then coalesce(nullif(mj.job_number, ''), md.reference)
      when sa.id is not null then coalesce(
        nullif(sa.reference, ''),
        nullif(trim(coalesce(md.reference, '')), ''),
        nullif(trim(coalesce(md.notes, '')), ''),
        null::text
      )
      when nullif(trim(coalesce(md.reference, '')), '') is not null then md.reference
      when nullif(trim(coalesce(md.notes, '')), '') is not null then md.notes
      else null::text
    end as reference_number,
    md.quantity,
    md.notes,
    coalesce(md.created_by, sa.created_by) as created_by,
    md.created_at,
    md.tenant_id
  from movement_documents md
  left join sales_invoices si
    on md.document_type = 'sales_invoice'
   and md.document_id = si.id
   and md.tenant_id = si.tenant_id
  left join purchase_invoices pi
    on md.document_type = 'purchase_invoice'
   and md.document_id = pi.id
   and md.tenant_id = pi.tenant_id
  left join mechanic_jobs mj
    on md.document_type = 'mechanic_job'
   and md.document_id = mj.id
   and md.tenant_id = mj.tenant_id
  left join stock_adjustments sa
    on md.document_type is null
   and md.tenant_id = sa.tenant_id
   and md.product_id = sa.product_id
   and md.created_at = sa.created_at
   and md.quantity = sa.quantity
   and coalesce(md.raw_movement_type, '') = sa.adjustment_type
),
movements_with_running_stock as (
  select
    m.*,
    greatest(coalesce(p.stock_quantity, 0), coalesce(p.inventory_qty, 0)) as current_stock,
    greatest(coalesce(p.stock_quantity, 0), coalesce(p.inventory_qty, 0)) - coalesce(
      sum(m.quantity) over (
        partition by m.product_id, m.tenant_id
        order by m.transaction_date desc nulls last, m.created_at desc, m.id desc
        rows between unbounded preceding and 1 preceding
      ),
      0
    )::integer as calculated_stock_after
  from movements_with_resolution m
  left join products p
    on nullif(m.product_id::text, '')::uuid = p.id
   and m.tenant_id = p.tenant_id
)
select
  id,
  product_id,
  product_name,
  product_sku,
  transaction_date,
  movement_type,
  source,
  reference_id,
  reference_number,
  quantity,
  (calculated_stock_after - quantity)::integer as stock_before,
  calculated_stock_after as stock_after,
  notes,
  created_by,
  created_at,
  tenant_id
from movements_with_running_stock;

alter view stock_movements_view set (security_invoker = on);

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
  v_net_quantity integer;
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

  select coalesce(sum(quantity), 0)::integer
    into v_net_quantity
    from public.stock_movements
   where reference = v_reference;

  if v_net_quantity > 0 then
    raise notice 'consume_purchase_invoice_inventory: inventory already applied for invoice %', p_invoice.id;
    return;
  end if;

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

    select is_set into v_is_set from products where id = v_resolved_product_id;

    if v_is_set then
      raise notice 'consume_purchase_invoice_inventory: exploding set % into components', v_resolved_product_id;

      for v_child in
        select component_product_id, quantity_in_set
          from product_set_components
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
        format('Entrada según factura compra %s', p_invoice.invoice_number),
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

  v_reference := format('purchase_invoice:%s', p_invoice.id);

  for v_item in
    select product_id, sum(quantity)::numeric as quantity
      from public.stock_movements
     where reference = v_reference
     group by product_id
    having sum(quantity) > 0
  loop
    if v_item.product_id is null then
      continue;
    end if;

    v_quantity_numeric := coalesce(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);

    if v_quantity_int = 0 then
      continue;
    end if;

    update public.products
       set inventory_qty = greatest(inventory_qty - v_quantity_int, 0),
           stock_quantity = greatest(stock_quantity - v_quantity_int, 0)
     where id = v_item.product_id;

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
      v_item.product_id,
      -v_quantity_int,
      'purchase_invoice_reversal',
      'OUT',
      v_reference,
      concat(
        'Reversión de entrada por factura de compra ',
        coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text)
      ),
      coalesce(p_invoice.date, now()),
      now(),
      now()
    );
  end loop;

  raise notice 'restore_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;
