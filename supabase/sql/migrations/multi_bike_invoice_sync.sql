-- ============================================================================
-- Multi-Bike Invoice Sync Migration
-- Adds job_bike_id and bike_name metadata to invoice item JSON,
-- preserving bike assignment through the Invoice ↔ Job sync round-trip.
-- ============================================================================

-- 1. Update sync_job_to_invoice: Include bike metadata in the JSON items
CREATE OR REPLACE FUNCTION public.sync_job_to_invoice(p_job_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice_id uuid;
  v_job record;
  v_items jsonb := '[]'::jsonb;
  v_item record;
  v_parts_cost numeric(12,2) := 0;
  v_labor_cost numeric(12,2) := 0;
  v_subtotal numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_iva_amount numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
  v_syncing_flag text;
  v_bike_name text;
BEGIN
  -- Check if we're currently syncing invoice → job (prevent circular sync)
  v_syncing_flag := current_setting('app.syncing_invoice_to_job', true);
  IF v_syncing_flag = 'true' THEN
    RAISE NOTICE 'sync_job_to_invoice: skipping due to invoice→job sync in progress';
    RETURN;
  END IF;

  -- Get the job and its linked invoice
  SELECT * INTO v_job
  FROM mechanic_jobs
  WHERE id = p_job_id;
  
  IF NOT FOUND THEN
    RAISE NOTICE 'Job % not found', p_job_id;
    RETURN;
  END IF;
  
  v_invoice_id := v_job.invoice_id;
  
  IF v_invoice_id IS NULL THEN
    RAISE NOTICE 'Job % has no linked invoice', p_job_id;
    RETURN;
  END IF;
  
  SELECT coalesce(discount_amount, 0)
  INTO v_discount
  FROM mechanic_jobs
  WHERE id = p_job_id;
  
  -- Build invoice items array from mechanic_job_items (products + services)
  FOR v_item IN 
    SELECT * FROM mechanic_job_items WHERE job_id = p_job_id
  LOOP
    -- Resolve bike display name from job_bike_id
    v_bike_name := NULL;
    IF v_item.job_bike_id IS NOT NULL THEN
      SELECT COALESCE(
        NULLIF(CONCAT_WS(' ', b.brand, b.model), ''),
        'Bicicleta'
      )
      INTO v_bike_name
      FROM mechanic_job_bikes mjb
      JOIN bikes b ON b.id = mjb.bike_id
      WHERE mjb.id = v_item.job_bike_id;
    END IF;

    v_items := v_items || jsonb_build_object(
      'product_id', CASE WHEN coalesce(v_item.item_type, 'product') = 'service'
                         THEN coalesce(v_item.service_product_id::text, '')
                         ELSE v_item.product_id::text
                    END,
      'product_name', v_item.product_name,
      'product_sku', coalesce(v_item.product_sku, ''),
      'description', coalesce(v_item.notes, ''),
      'item_type', coalesce(v_item.item_type, 'product'),
      'is_catalog_product', CASE WHEN v_item.item_type = 'adhoc' THEN false ELSE true END,
      'quantity', v_item.quantity,
      'unit_price', v_item.unit_price,
      'line_total', coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0),
      'job_bike_id', v_item.job_bike_id,
      'bike_name', v_bike_name
    );

    IF coalesce(v_item.item_type, 'product') IN ('service', 'adhoc') THEN
      v_labor_cost := v_labor_cost + coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0);
    ELSE
      v_parts_cost := v_parts_cost + coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0);
    END IF;
  END LOOP;
  
  -- Calculate totals with FRESH data
  v_subtotal := v_parts_cost + v_labor_cost - v_discount;
  
  -- Calculate IVA based on job's tax treatment
  IF v_job.tax_treatment = 'tax_included' THEN
    v_iva_amount := round(v_subtotal - (v_subtotal / 1.19), 0);
  ELSE
    v_iva_amount := 0;
  END IF;
  
  v_total := v_subtotal;
  
  -- Update the invoice with fresh calculations
  PERFORM set_config('app.syncing_job_to_invoice', 'true', true);

  UPDATE sales_invoices
  SET
    items = v_items,
    subtotal = v_subtotal,
    iva_amount = v_iva_amount,
    net_amount = CASE 
      WHEN v_job.tax_treatment = 'tax_included' THEN v_subtotal / 1.19
      ELSE v_subtotal
    END,
    tax_treatment = v_job.tax_treatment,
    total = v_total,
    discount_amount = v_discount,
    updated_at = now()
  WHERE id = v_invoice_id;
  
  -- Let the payment recalculation function handle balance and status
  PERFORM public.recalculate_sales_invoice_payments(v_invoice_id);

  -- Clear job → invoice flag
  PERFORM set_config('app.syncing_job_to_invoice', '', true);
  
  RAISE NOTICE 'Synced job % to invoice % (% items, subtotal: $%, total: $%)', p_job_id, v_invoice_id, jsonb_array_length(v_items), v_subtotal, v_total;
END;
$$;


-- 2. Update sync_invoice_items_to_job: Read job_bike_id from JSON to assign items to correct bike
CREATE OR REPLACE FUNCTION public.sync_invoice_items_to_job(p_invoice_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
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
  v_default_bike_id uuid;
BEGIN
  -- Prevent circular sync
  IF pg_trigger_depth() > 2 THEN
    RAISE NOTICE 'sync_invoice_items_to_job: trigger depth too deep (%), skipping', pg_trigger_depth();
    RETURN;
  END IF;

  -- Find the job linked to this invoice
  SELECT id INTO v_job_id
  FROM mechanic_jobs
  WHERE invoice_id = p_invoice_id;
  
  IF v_job_id IS NULL THEN
    RAISE NOTICE 'No job linked to invoice %', p_invoice_id;
    RETURN;
  END IF;
  
  -- Get invoice details
  SELECT * INTO v_invoice
  FROM sales_invoices
  WHERE id = p_invoice_id;
  
  IF NOT FOUND THEN
    RAISE NOTICE 'Invoice % not found', p_invoice_id;
    RETURN;
  END IF;
  
  v_tenant_id := v_invoice.tenant_id;
  
  -- Get the default (first) bike for items without a specific bike assignment
  SELECT id INTO v_default_bike_id
  FROM mechanic_job_bikes
  WHERE job_id = v_job_id
  ORDER BY order_index
  LIMIT 1;
  
  -- Set flag to prevent reverse sync
  PERFORM set_config('app.syncing_invoice_to_job', 'true', true);
  
  -- Delete existing job items (we'll recreate them from invoice)
  DELETE FROM mechanic_job_items WHERE job_id = v_job_id;
  
  -- Process each invoice item
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_invoice.items)
  LOOP
    v_product_id := nullif(v_item->>'product_id', '')::uuid;
    v_quantity := coalesce((v_item->>'quantity')::numeric, 1);
    v_unit_price := coalesce((v_item->>'unit_price')::numeric, 0);
    v_line_total := coalesce((v_item->>'line_total')::numeric, v_quantity * v_unit_price, 0);
    v_product_name := v_item->>'product_name';

    -- Resolve job_bike_id from item JSON, fallback to default bike
    v_job_bike_id := nullif(v_item->>'job_bike_id', '')::uuid;
    IF v_job_bike_id IS NULL THEN
      v_job_bike_id := v_default_bike_id;
    ELSE
      -- Validate the bike still exists for this job
      IF NOT EXISTS (
        SELECT 1 FROM mechanic_job_bikes 
        WHERE id = v_job_bike_id AND job_id = v_job_id
      ) THEN
        v_job_bike_id := v_default_bike_id;
      END IF;
    END IF;

    -- Determine product info (if exists)
    v_product_type := NULL;
    v_product_name := NULL;
    IF v_product_id IS NOT NULL THEN
      SELECT product_type, name
      INTO v_product_type, v_product_name
      FROM products
      WHERE id = v_product_id;
      IF NOT FOUND THEN
        v_product_type := NULL;
        v_product_name := NULL;
      END IF;
    END IF;

    IF v_product_id IS NULL OR v_product_type = 'service' THEN
      v_labor_cost := v_labor_cost + v_line_total;
    ELSE
      v_parts_cost := v_parts_cost + v_line_total;
    END IF;

    INSERT INTO mechanic_job_items (
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
    ) VALUES (
      v_tenant_id,
      v_job_id,
      v_job_bike_id,
      CASE WHEN v_product_type = 'service' THEN NULL ELSE v_product_id END,
      coalesce(v_product_name, v_item->>'product_name'),
      coalesce(v_item->>'product_sku', ''),
      CASE WHEN v_quantity IS NULL OR v_quantity = 0 THEN 1 ELSE v_quantity END,
      v_unit_price,
      v_line_total,
      coalesce(v_item->>'description', ''),
      coalesce(v_item->>'description', ''),
      CASE WHEN v_product_id IS NULL OR v_product_type = 'service' THEN 'service' ELSE 'product' END,
      CASE WHEN v_product_id IS NULL OR v_product_type = 'service' THEN v_product_id ELSE NULL END,
      now(),
      now()
    );
  END LOOP;
  
  v_subtotal := v_parts_cost + v_labor_cost;
  
  -- Update job costs
  UPDATE mechanic_jobs
  SET 
    labor_cost = v_labor_cost,
    parts_cost = v_parts_cost,
    final_cost = v_subtotal,
    estimated_cost = v_subtotal,
    total_cost = v_invoice.total,
    tax_amount = v_invoice.iva_amount,
    updated_at = now()
  WHERE id = v_job_id;
  
  -- Clear the sync flag
  PERFORM set_config('app.syncing_invoice_to_job', '', true);
  
  RAISE NOTICE 'Synced invoice % items to job % (parts: $%, labor: $%)', 
    p_invoice_id, v_job_id, v_parts_cost, v_labor_cost;
END;
$$;
