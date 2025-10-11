-- TEST SCRIPT: Verify Inventory Reduction Works
-- Run this AFTER applying complete_inventory_fix.sql

-- ============================================================================
-- SETUP: Create a test product if needed
-- ============================================================================

do $$
declare
  v_test_product_id uuid;
  v_test_customer_id uuid;
  v_test_invoice_id uuid;
  v_initial_qty integer;
  v_final_qty integer;
  v_movement_count integer;
begin
  raise notice '';
  raise notice '═══════════════════════════════════════════════════════════════';
  raise notice '  INVENTORY REDUCTION TEST';
  raise notice '═══════════════════════════════════════════════════════════════';
  raise notice '';

  -- Step 1: Create or find a test product
  raise notice '1️⃣  Setting up test product...';
  
  select id into v_test_product_id
  from products
  where sku = 'TEST-BIKE-001'
  limit 1;
  
  if v_test_product_id is null then
    insert into products (name, sku, price, cost, inventory_qty, is_service)
    values ('Test Bike for Inventory Fix', 'TEST-BIKE-001', 100000, 60000, 100, false)
    returning id into v_test_product_id;
    raise notice '   ✓ Created test product: %', v_test_product_id;
  else
    update products set inventory_qty = 100 where id = v_test_product_id;
    raise notice '   ✓ Using existing product: %', v_test_product_id;
  end if;

  -- Get initial quantity
  select inventory_qty into v_initial_qty
  from products
  where id = v_test_product_id;
  
  raise notice '   ✓ Initial inventory: %', v_initial_qty;

  -- Step 2: Create or find a test customer
  raise notice '2️⃣  Setting up test customer...';
  
  select id into v_test_customer_id
  from customers
  where email = 'test@inventoryfix.com'
  limit 1;
  
  if v_test_customer_id is null then
    insert into customers (name, email)
    values ('Test Customer', 'test@inventoryfix.com')
    returning id into v_test_customer_id;
    raise notice '   ✓ Created test customer: %', v_test_customer_id;
  else
    raise notice '   ✓ Using existing customer: %', v_test_customer_id;
  end if;

  -- Step 3: Create a draft invoice
  raise notice '3️⃣  Creating draft invoice...';
  
  insert into sales_invoices (
    invoice_number,
    customer_id,
    customer_name,
    date,
    status,
    subtotal,
    iva_amount,
    total,
    items
  ) values (
    'TEST-' || to_char(now(), 'YYYYMMDD-HH24MISS'),
    v_test_customer_id,
    'Test Customer',
    now(),
    'draft',
    84034,  -- 100000 / 1.19
    15966,  -- IVA 19%
    100000,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', v_test_product_id::text,
        'product_sku', 'TEST-BIKE-001',
        'product_name', 'Test Bike for Inventory Fix',
        'quantity', 5,
        'unit_price', 16807,
        'line_total', 84034
      )
    )
  )
  returning id into v_test_invoice_id;
  
  raise notice '   ✓ Created invoice: %', v_test_invoice_id;
  raise notice '   ✓ Status: draft';
  raise notice '   ✓ Items: 1 product, qty 5';

  -- Verify inventory hasn't changed yet
  select inventory_qty into v_final_qty
  from products
  where id = v_test_product_id;
  
  raise notice '   ✓ Inventory after draft creation: % (should be same as initial)', v_final_qty;

  -- Step 4: Mark as sent (this should trigger inventory reduction)
  raise notice '4️⃣  Marking invoice as SENT...';
  
  update sales_invoices
  set status = 'sent'
  where id = v_test_invoice_id;
  
  raise notice '   ✓ Invoice marked as sent';

  -- Step 5: Verify inventory was reduced
  raise notice '5️⃣  Verifying results...';
  
  select inventory_qty into v_final_qty
  from products
  where id = v_test_product_id;
  
  raise notice '   Initial qty: %', v_initial_qty;
  raise notice '   Final qty:   %', v_final_qty;
  raise notice '   Difference:  %', (v_initial_qty - v_final_qty);

  if (v_initial_qty - v_final_qty) = 5 then
    raise notice '   ✅ SUCCESS: Inventory reduced by 5 as expected!';
  else
    raise notice '   ❌ FAILED: Inventory should have reduced by 5';
    raise exception 'Test failed: inventory not reduced correctly';
  end if;

  -- Step 6: Verify stock movement was created
  select count(*) into v_movement_count
  from stock_movements
  where reference = 'sales_invoice:' || v_test_invoice_id::text
    and type = 'OUT'
    and movement_type = 'sales_invoice';
  
  if v_movement_count > 0 then
    raise notice '   ✅ Stock movement record created';
  else
    raise notice '   ❌ FAILED: No stock movement record found';
    raise exception 'Test failed: no stock movement created';
  end if;

  raise notice '';
  raise notice '═══════════════════════════════════════════════════════════════';
  raise notice '  ✅ ALL TESTS PASSED! Inventory fix is working correctly.';
  raise notice '═══════════════════════════════════════════════════════════════';
  raise notice '';
  raise notice 'Test invoice ID: %', v_test_invoice_id;
  raise notice 'You can now delete this test data if you want.';
  raise notice '';

exception
  when others then
    raise notice '';
    raise notice '═══════════════════════════════════════════════════════════════';
    raise notice '  ❌ TEST FAILED';
    raise notice '═══════════════════════════════════════════════════════════════';
    raise notice '';
    raise notice 'Error: %', SQLERRM;
    raise notice '';
    raise notice 'Please check:';
    raise notice '1. Did you run complete_inventory_fix.sql first?';
    raise notice '2. Check the Supabase logs for detailed error messages';
    raise notice '3. Verify movement_type is TEXT not ENUM';
    raise notice '';
    raise;
end $$;

-- Show recent stock movements for verification
select 
  sm.id,
  sm.type,
  sm.movement_type,
  sm.quantity,
  sm.reference,
  p.sku,
  p.name as product_name,
  sm.created_at
from stock_movements sm
join products p on p.id = sm.product_id
where sm.movement_type = 'sales_invoice'
order by sm.created_at desc
limit 5;
