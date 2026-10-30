-- 20261030031500: purchase journal helpers stay inside their tenant.
--
-- Found on 2026-10-30 while fixing the TeknoBike invoices booked in 2014
-- (20261030010000). handle_purchase_invoice_change posts and removes a
-- purchase invoice's journal entry through two helpers that looked entries up
-- by invoice number alone:
-- - delete_purchase_invoice_journal_entry(text) deleted every tenant's
--   purchase entry with that number, and every tenant's legacy payment
--   entries referenced by it, when one invoice walked back to draft, changed
--   its amounts at the same status, or was deleted.
-- - create_purchase_invoice_journal_entry(purchase_invoices) skipped posting
--   when any tenant already had an entry with that number, so a second shop
--   with the same supplier folio would confirm a purchase with no entry.
-- Production had 10 tenants, 2 with purchases and no shared invoice number,
-- so nothing was lost yet. A supplier folio is not unique across shops: two
-- shops buying from the same distributor will collide.
--
-- What changes:
-- 1. delete_purchase_invoice_journal_entry(tenant, invoice_number) does the
--    same two deletes, scoped to the tenant. Only the trigger calls it.
-- 2. The one-argument text version refuses: it cannot know the tenant.
--    Nothing calls it (checked in pg_proc, cron.job, lib/ and the Edge
--    Functions on 2026-10-30).
-- 3. create_purchase_invoice_journal_entry(purchase_invoices) checks for an
--    existing entry in the invoice's own tenant. Production body otherwise
--    unchanged.
-- 4. handle_purchase_invoice_change calls the tenant-scoped delete in its
--    three places. Body otherwise identical to 20261030010000.
-- The uuid overloads match on the invoice's own id and stay as they are.
-- One transaction: the trigger switches before the old helper refuses.

begin;

create or replace function public.delete_purchase_invoice_journal_entry(
  p_tenant_id uuid,
  p_invoice_number text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_tenant_id is null or p_invoice_number is null then
    return;
  end if;

  delete from public.journal_entries
   where tenant_id = p_tenant_id
     and source_module = 'purchase_invoices'
     and source_reference = p_invoice_number;

  -- Legacy payment entries referenced the invoice number instead of the
  -- payment id.
  delete from public.journal_entries
   where tenant_id = p_tenant_id
     and source_module = 'purchase_payments'
     and source_reference = p_invoice_number;
end;
$$;

revoke all on function public.delete_purchase_invoice_journal_entry(uuid, text)
  from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_purchase_invoice_journal_entry(p_invoice purchase_invoices)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      and tenant_id = p_invoice.tenant_id
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
$function$;

CREATE OR REPLACE FUNCTION public.handle_purchase_invoice_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_old_status text;
  v_new_status text;
  v_timezone text;
  v_new_day date;
begin
  raise notice 'handle_purchase_invoice_change: TG_OP=%', TG_OP;

  if TG_OP = 'INSERT' then
    v_new_status := NEW.status;
    raise notice 'handle_purchase_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;

    -- Inventory: ONLY if inserted directly as 'received' (rare case)
    if v_new_status = 'received' then
      raise notice 'handle_purchase_invoice_change: INSERT at received, consuming inventory';
      perform public.consume_purchase_invoice_inventory(NEW);
    end if;

    -- Journal: If inserted at 'confirmed' or later
    if v_new_status IN ('confirmed', 'received', 'paid') then
      raise notice 'handle_purchase_invoice_change: INSERT at confirmed/received/paid, creating journal entry';
      perform public.create_purchase_invoice_journal_entry(NEW);
    end if;

    perform public.recalculate_purchase_invoice_payments(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := OLD.status;
    v_new_status := NEW.status;

    raise notice 'handle_purchase_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    -- INVENTORY HANDLING: ONLY at 'received' status
    -- Different logic for standard vs prepayment models:
    --
    -- STANDARD MODEL: Draft→Confirmed→RECEIVED→Paid
    --   Inventory added at 'received', stays through 'paid'
    --   So: received<->paid transitions do NOT change inventory
    --
    -- PREPAYMENT MODEL: Draft→Confirmed→Paid→RECEIVED
    --   Inventory added at 'received' (after payment)
    --   So: received<->paid transitions DO change inventory

    if NEW.prepayment_model then
      -- PREPAYMENT MODEL: Inventory changes whenever entering/leaving 'received'
      if v_old_status != 'received' AND v_new_status = 'received' then
        -- Transitioning TO received (from any status): add inventory
        raise notice 'handle_purchase_invoice_change: [PREPAYMENT] transitioning TO received from %, consuming inventory', v_old_status;
        perform public.consume_purchase_invoice_inventory(NEW);

      elsif v_old_status = 'received' AND v_new_status != 'received' then
        -- Transitioning FROM received (to any status): remove inventory
        raise notice 'handle_purchase_invoice_change: [PREPAYMENT] transitioning FROM received to %, restoring inventory', v_new_status;
        perform public.restore_purchase_invoice_inventory(OLD);

      elsif v_old_status = 'received' AND v_new_status = 'received' then
        -- Only physical item changes may replace the received stock snapshot.
        if public.invoice_inventory_signature(OLD.items)
             is distinct from public.invoice_inventory_signature(NEW.items) then
          raise notice 'handle_purchase_invoice_change: [PREPAYMENT] received items changed, updating inventory';
          perform public.restore_purchase_invoice_inventory(OLD);
          perform public.consume_purchase_invoice_inventory(NEW);
        else
          raise notice 'handle_purchase_invoice_change: [PREPAYMENT] received without item changes, no inventory change';
        end if;
      end if;

    else
      -- STANDARD MODEL: Inventory changes only when entering/leaving 'received' from/to non-paid statuses
      if v_old_status <> 'received' AND v_new_status = 'received' then
        -- Transitioning TO received from confirmed/sent/draft: add inventory
        raise notice 'handle_purchase_invoice_change: [STANDARD] transitioning TO received from %, consuming inventory', v_old_status;
        perform public.consume_purchase_invoice_inventory(NEW);

      elsif v_old_status = 'received' AND v_new_status NOT IN ('received', 'paid') then
        -- Transitioning FROM received to confirmed/sent/draft: remove inventory
        -- Note: received→paid does NOT remove (goods stay in standard flow)
        raise notice 'handle_purchase_invoice_change: [STANDARD] transitioning FROM received to %, restoring inventory', v_new_status;
        perform public.restore_purchase_invoice_inventory(OLD);

      elsif v_old_status = 'received' AND v_new_status = 'received' then
        -- Only physical item changes may replace the received stock snapshot.
        if public.invoice_inventory_signature(OLD.items)
             is distinct from public.invoice_inventory_signature(NEW.items) then
          raise notice 'handle_purchase_invoice_change: [STANDARD] received items changed, updating inventory';
          perform public.restore_purchase_invoice_inventory(OLD);
          perform public.consume_purchase_invoice_inventory(NEW);
        else
          raise notice 'handle_purchase_invoice_change: [STANDARD] received without item changes, no inventory change';
        end if;
      end if;
    end if;

    -- JOURNAL ENTRY HANDLING: Create ONCE at 'confirmed', delete when reverting
    -- The journal entry represents the purchase transaction (Dr Inventory / Cr Accounts Payable)
    -- It should NOT be recreated when moving between confirmed→received→paid
    -- It should ONLY be recreated if staying at same status but amounts changed

    if v_old_status IN ('draft', 'sent', 'cancelled') AND v_new_status IN ('confirmed', 'received', 'paid') then
      -- Transitioning TO confirmed/received/paid: create journal entry
      raise notice 'handle_purchase_invoice_change: transitioning TO confirmed/received/paid, creating journal entry';
      perform public.create_purchase_invoice_journal_entry(NEW);

    elsif v_old_status IN ('confirmed', 'received', 'paid') AND v_new_status IN ('draft', 'sent', 'cancelled') then
      -- Transitioning FROM confirmed/received/paid to draft/sent/cancelled: delete journal entry
      raise notice 'handle_purchase_invoice_change: transitioning FROM confirmed/received/paid, deleting journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.tenant_id, OLD.invoice_number);

    elsif v_old_status = v_new_status AND v_old_status IN ('confirmed', 'received', 'paid') then
      -- Staying at same confirmed+ status but invoice data might have changed
      -- Only recreate journal if amounts changed (not just status transition)
      if OLD.subtotal IS DISTINCT FROM NEW.subtotal OR
         OLD.tax IS DISTINCT FROM NEW.tax OR
         OLD.total IS DISTINCT FROM NEW.total OR
         OLD.supplier_id IS DISTINCT FROM NEW.supplier_id then
        raise notice 'handle_purchase_invoice_change: amounts changed at same status, recreating journal entry';
        perform public.delete_purchase_invoice_journal_entry(OLD.tenant_id, OLD.invoice_number);
        perform public.create_purchase_invoice_journal_entry(NEW);
      elsif OLD.date IS DISTINCT FROM NEW.date then
        -- The entry belongs to the document: a corrected emission date moves
        -- it to that day, keeping its number and lines (2026-10-30).
        select coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago')
          into v_timezone
          from public.tenants tenant
         where tenant.id = NEW.tenant_id;
        v_new_day := (NEW.date at time zone coalesce(v_timezone, 'America/Santiago'))::date;

        update public.journal_entries entry
           set entry_date = v_new_day
         where entry.tenant_id = NEW.tenant_id
           and entry.source_module = 'purchase_invoices'
           and (
             entry.source_document_id = NEW.id
             or (
               entry.source_document_id is null
               and entry.source_reference = OLD.invoice_number
             )
           )
           and entry.entry_date is distinct from v_new_day;
      end if;
    end if;

    -- Only recalculate if this is NOT a payment-only update (prevents infinite recursion)
    -- If only paid_amount, balance, or status changed → skip recalculate (it's from recalculate itself)
    -- If items, total, subtotal, tax, or other fields changed → call recalculate
    if OLD.items IS DISTINCT FROM NEW.items OR
       OLD.subtotal IS DISTINCT FROM NEW.subtotal OR
       OLD.tax IS DISTINCT FROM NEW.tax OR
       OLD.total IS DISTINCT FROM NEW.total OR
       OLD.supplier_id IS DISTINCT FROM NEW.supplier_id OR
       OLD.prepayment_model IS DISTINCT FROM NEW.prepayment_model then
      raise notice 'handle_purchase_invoice_change: invoice data changed, recalculating payments';
      perform public.recalculate_purchase_invoice_payments(NEW.id);
    else
      raise notice 'handle_purchase_invoice_change: only payment fields changed, skipping recalculate to avoid recursion';
    end if;

    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := OLD.status;
    raise notice 'handle_purchase_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;

    -- Restore inventory if was received
    if v_old_status = 'received' then
      raise notice 'handle_purchase_invoice_change: deleting received invoice, restoring inventory';
      perform public.restore_purchase_invoice_inventory(OLD);
    end if;

    -- Delete journal entry if was confirmed or later
    if v_old_status IN ('confirmed', 'received', 'paid') then
      raise notice 'handle_purchase_invoice_change: deleting confirmed/received/paid invoice, deleting journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.tenant_id, OLD.invoice_number);
    end if;

    return OLD;
  end if;

  return NULL;
end;
$function$;

create or replace function public.delete_purchase_invoice_journal_entry(
  p_invoice_number text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception
    'delete_purchase_invoice_journal_entry(text) no distingue el taller: usa delete_purchase_invoice_journal_entry(tenant_id, invoice_number)'
    using errcode = '42883';
end;
$$;

commit;
