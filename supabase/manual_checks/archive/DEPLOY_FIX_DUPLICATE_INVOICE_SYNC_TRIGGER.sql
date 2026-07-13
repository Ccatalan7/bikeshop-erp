-- ============================================================================
-- FIX: Remove duplicate sync trigger that caused flag conflict
-- ============================================================================
-- 
-- PROBLEM IDENTIFIED:
-- Two triggers were both trying to call sync_invoice_items_to_job on sales_invoices UPDATE:
--
--   1. trg_sales_invoices_change → handle_sales_invoice_change()
--      → calls sync_invoice_items_to_job(NEW.id)  ← NO flag set before call
--
--   2. trg_sync_invoice_to_job → sync_invoice_to_job_on_change()
--      → sets syncing_invoice_to_job='true'
--      → calls sync_invoice_items_to_job(NEW.id)
--      → clears syncing_invoice_to_job=''
--
-- Both triggers fire on the same UPDATE transaction.
-- The order of trigger execution caused one to set syncing_invoice_to_job='true' FIRST,
-- then the other called sync_invoice_items_to_job which found the flag = 'true' and SKIPPED.
-- Net result: sync_invoice_items_to_job ran 0 times effectively (or skipped on the important call).
--
-- FIX: Remove trg_sync_invoice_to_job. The trg_sales_invoices_change trigger already handles
-- the sync correctly via handle_sales_invoice_change → sync_invoice_items_to_job.
-- Additionally, the Flutter SalesService now explicitly calls sync_invoice_items_to_job
-- as a reliable fallback after every saveInvoice().
-- ============================================================================

-- Remove the duplicate trigger
drop trigger if exists trg_sync_invoice_to_job on public.sales_invoices;

-- ============================================================================
-- FIX #2: General items (no bike assigned) now stay as NULL in mechanic_job_items
-- ============================================================================
--
-- PROBLEM:
-- sync_invoice_items_to_job used a v_default_bike_id fallback:
-- when an invoice item had no bike (job_bike_id = null), it was forced to
-- use the FIRST bike of the job as the assigned bike.
--
-- FIX:
-- Removed v_default_bike_id entirely. NULL job_bike_id passes through as NULL
-- to mechanic_job_items, keeping the item as "General" (no bike assigned).
-- If the bike ID exists on the item but is invalid for this job → also set to NULL.
-- ============================================================================

create or replace function public.sync_invoice_items_to_job(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_id uuid;
  v_invoice record;
  v_item jsonb;
  v_subtotal numeric(12,2) := 0;
  v_labor_cost numeric(12,2) := 0;
  v_parts_cost numeric(12,2) := 0;
  v_product_id uuid;
  v_product_type text;
  v_product_name text;
  v_quantity numeric(12,2);
  v_unit_price numeric(12,2);
  v_line_total numeric(12,2);
  v_tenant_id uuid;
  v_job_bike_id uuid;
  v_item_count integer := 0;
begin
  -- Prevent circular sync in either direction
  if current_setting('app.syncing_invoice_to_job', true) = 'true' or
     current_setting('app.syncing_job_to_invoice', true) = 'true' then
    raise notice 'sync_invoice_items_to_job: skipping due to active sync flag';
    return;
  end if;

  -- Prevent circular sync: if we're already deep in triggers, skip
  if pg_trigger_depth() > 2 then
    raise notice 'sync_invoice_items_to_job: trigger depth too deep (%), skipping to prevent circular sync', pg_trigger_depth();
    return;
  end if;

  -- Find the job linked to this invoice
  select id into v_job_id
  from mechanic_jobs
  where invoice_id = p_invoice_id;
  
  if v_job_id is null then
    raise notice 'No job linked to invoice %', p_invoice_id;
    return;
  end if;
  
  -- Get invoice details
  select * into v_invoice
  from sales_invoices
  where id = p_invoice_id;
  
  if not found then
    raise notice 'Invoice % not found', p_invoice_id;
    return;
  end if;
  
  -- Get tenant_id from invoice
  v_tenant_id := v_invoice.tenant_id;
  
  -- ============================================================
  -- CRITICAL FIX (Mar 19, 2026): Disable row triggers on mechanic_job_items
  -- during the sync to prevent:
  --   1) Cascading trigger chains (5+ triggers per INSERT) that cause
  --      savepoint/set_config interactions to lose the sync guard flag
  --   2) Redundant cost recalculations (we calculate costs ourselves below)
  --   3) auto_parse_item_description side-effects during sync
  --   4) Back-sync attempts to invoice via statement-level triggers
  -- We re-enable triggers in a finally-style block to guarantee cleanup.
  -- This function is SECURITY DEFINER so it has permission to alter triggers.
  -- ============================================================
  alter table mechanic_job_items disable trigger user;
  
  -- Set sync flag (transaction-scoped, NOT savepoint-scoped)
  perform set_config('app.syncing_invoice_to_job', 'true', true);
  
  -- Delete existing job items (no triggers fire — they are disabled)
  delete from mechanic_job_items where job_id = v_job_id;
  
  -- Process each invoice item
  for v_item in select * from jsonb_array_elements(v_invoice.items)
  loop
    v_product_id := nullif(v_item->>'product_id', '')::uuid;
    v_quantity := coalesce((v_item->>'quantity')::numeric, 1);
    v_unit_price := coalesce((v_item->>'unit_price')::numeric, 0);
    v_line_total := coalesce((v_item->>'line_total')::numeric, v_quantity * v_unit_price, 0);
    v_product_name := v_item->>'product_name';

    -- Resolve job_bike_id from item JSON.
    -- If the invoice item has no bike assigned (null / empty), keep it NULL in mechanic_job_items
    -- so the item appears as "General" (not forcibly assigned to the first bike).
    v_job_bike_id := nullif(v_item->>'job_bike_id', '')::uuid;
    if v_job_bike_id is not null then
      -- Validate the bike still exists for this job; if not, clear it (don't fallback to default)
      if not exists (
        select 1 from mechanic_job_bikes 
        where id = v_job_bike_id and job_id = v_job_id
      ) then
        v_job_bike_id := null;
      end if;
    end if;
    -- v_job_bike_id remains NULL for "General / no bike" items — this is intentional.

    -- Determine product info (if exists)
    v_product_type := null;
    v_product_name := null;
    if v_product_id is not null then
      select product_type, name
      into v_product_type, v_product_name
      from products
      where id = v_product_id;
      if not found then
        v_product_type := null;
        v_product_name := null;
      end if;
    end if;

    if v_product_id is null or v_product_type = 'service' then
      v_labor_cost := v_labor_cost + v_line_total;
    else
      v_parts_cost := v_parts_cost + v_line_total;
    end if;

    -- Calculate total_price inline (BEFORE trigger trg_calculate_mechanic_job_item_total is disabled)
    if v_quantity is null or v_quantity = 0 then
      v_quantity := 1;
    end if;

    insert into mechanic_job_items (
      tenant_id,
      job_id,
      job_bike_id,
      product_id,
      product_name,
      product_sku,
      quantity,
      unit_price,
      total_price,
      notes,
      description,
      item_type,
      service_product_id,
      created_at,
      updated_at
    ) values (
      v_tenant_id,
      v_job_id,
      v_job_bike_id,
      case when v_product_type = 'service' then null else v_product_id end,
      coalesce(v_product_name, v_item->>'product_name'),
      coalesce(v_item->>'product_sku', ''),
      v_quantity,
      v_unit_price,
      v_line_total,
      coalesce(v_item->>'description', ''),
      coalesce(v_item->>'description', ''),
      case when v_product_id is null or v_product_type = 'service' then 'service' else 'product' end,
      case when v_product_id is null or v_product_type = 'service' then v_product_id else null end,
      now(),
      now()
    );
    
    v_item_count := v_item_count + 1;
  end loop;
  
  v_subtotal := v_parts_cost + v_labor_cost;
  
  -- Update job costs directly (no trigger cascades since we calculated everything)
  update mechanic_jobs
  set 
    labor_cost = v_labor_cost,
    parts_cost = v_parts_cost,
    final_cost = v_subtotal,
    estimated_cost = v_subtotal,
    total_cost = v_invoice.total,
    tax_amount = v_invoice.iva_amount,
    updated_at = now()
  where id = v_job_id;

  -- Update per-bike costs if multi-bike job
  update mechanic_job_bikes mjb
  set 
    parts_cost = coalesce(sub.parts_cost, 0),
    labor_cost = coalesce(sub.labor_cost, 0),
    subtotal = coalesce(sub.parts_cost, 0) + coalesce(sub.labor_cost, 0),
    updated_at = now()
  from (
    select 
      mji.job_bike_id,
      sum(case when coalesce(mji.item_type, 'product') <> 'service' then mji.total_price else 0 end) as parts_cost,
      sum(case when coalesce(mji.item_type, 'product') = 'service' then mji.total_price else 0 end) as labor_cost
    from mechanic_job_items mji
    where mji.job_id = v_job_id
      and mji.job_bike_id is not null
    group by mji.job_bike_id
  ) sub
  where mjb.id = sub.job_bike_id
    and mjb.job_id = v_job_id;

  -- Re-enable triggers (ALWAYS runs, even if error above would propagate)
  alter table mechanic_job_items enable trigger user;
  
  -- Clear the sync flag
  perform set_config('app.syncing_invoice_to_job', '', true);
  
  raise notice 'Synced invoice % items to job %: % items (parts: $%, labor: $%)', 
    p_invoice_id, v_job_id, v_item_count, v_parts_cost, v_labor_cost;
    
exception
  when others then
    -- CRITICAL: Re-enable triggers even on error to prevent table being stuck
    alter table mechanic_job_items enable trigger user;
    perform set_config('app.syncing_invoice_to_job', '', true);
    raise;
end;
$$;

-- ============================================================================
-- VERIFICATION QUERIES (run after deploying)
-- ============================================================================
-- 1. Confirm trg_sync_invoice_to_job is gone:
--    SELECT trigger_name FROM information_schema.triggers
--    WHERE event_object_table = 'sales_invoices' ORDER BY trigger_name;
--
-- 2. Test NULL bike fix:
--    Add a "General" item (no bike assigned) to an invoice → save →
--    Check mechanic_job_items: job_bike_id should be NULL, not a specific bike UUID.
-- ============================================================================
