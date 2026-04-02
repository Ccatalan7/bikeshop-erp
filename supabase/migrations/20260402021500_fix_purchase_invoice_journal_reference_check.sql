-- Fix purchase invoice journal duplicate detection to use the same
-- source_reference value as the inserted journal entry.

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
  raise notice '🔵 START create_purchase_invoice_journal_entry for invoice %', p_invoice.id;

  if p_invoice.id is null then
    raise notice '❌ Invoice ID is null, returning';
    return;
  end if;

  raise notice '✅ Invoice ID: %, tenant_id: %', p_invoice.id, p_invoice.tenant_id;

  select exists (
    select 1
    from public.journal_entries
    where source_module = 'purchase_invoices'
      and source_reference = p_invoice.invoice_number
  ) into v_exists;

  if v_exists then
    raise notice '⚠️ Entry already exists for invoice %, skipping', p_invoice.id;
    return;
  end if;

  raise notice '✅ No existing entry found, proceeding...';

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
    'Materiales y consumibles de uso rápido aplicados directamente en el taller',
    null
  );

  v_iva_account_id := public.ensure_account(
    p_invoice.tenant_id,
    '2120',
    'IVA Crédito Fiscal',
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

  v_description := format('Factura compra %s - %s',
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
    v_inventory_subtotal := round(
      (v_inventory_subtotal / v_total_item_subtotal) * v_scaled_subtotal,
      2
    );
    v_workshop_subtotal := round(
      (v_workshop_subtotal / v_total_item_subtotal) * v_scaled_subtotal,
      2
    );

    v_subtotal_delta := round(
      v_scaled_subtotal - v_inventory_subtotal - v_workshop_subtotal,
      2
    );

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
    'IVA Crédito Fiscal',
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

  raise notice '✅ Journal entry created successfully for invoice %', p_invoice.id;
  raise notice '🎉 DONE - Entry ID: %, Total: %', v_entry_id, p_invoice.total;
end;
$$;