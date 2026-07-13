-- Create test data for tenant 5443b130-cc28-45af-a420-cd500b288890
-- This replicates the same structure as tenant 46e169a4-ba62-4f86-92cd-778ece1b0afa
-- Run this in Supabase SQL Editor

-- STEP 1: Get a user_id from this tenant first
-- Run this query first to find a user:
-- SELECT u.id, u.email, up.role FROM auth.users u 
-- JOIN user_profiles up ON up.user_id = u.id 
-- WHERE up.tenant_id = '5443b130-cc28-45af-a420-cd500b288890';

-- STEP 2: Replace 'YOUR_USER_ID_HERE' below with actual user_id from step 1
-- Then run this script

DO $$
DECLARE
  v_user_id uuid := '7bb76d88-5455-462e-a838-5f78af922914'; -- vinabikechile@gmail.com
  v_tenant_id uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_customer_id uuid;
  v_bike_brand_id uuid;
  v_bike_model_id uuid;
  v_bike_id uuid;
  v_mechanic_job_id uuid;
  v_sales_invoice_id uuid;
  v_payment_method_id uuid;
BEGIN
  -- Set auth context to simulate authenticated user
  PERFORM set_config('request.jwt.claims', 
    json_build_object('sub', v_user_id::text, 'role', 'authenticated')::text, 
    true);
  -- 1. Create Customer (Alan Castro)
  INSERT INTO customers (
    tenant_id, 
    name, 
    email, 
    phone, 
    rut,
    created_at
  ) VALUES (
    v_tenant_id,
    'Alan Castro',
    'alan.castro@example.com',
    '+56912345678',
    '12345678-9',
    now()
  ) RETURNING id INTO v_customer_id;
  
  RAISE NOTICE '✅ Created customer: %', v_customer_id;

  -- 2. Create Bike Brand (Flow)
  INSERT INTO bike_brands (
    tenant_id,
    name,
    country,
    is_active,
    created_at
  ) VALUES (
    v_tenant_id,
    'Flow',
    'Chile',
    true,
    now()
  ) RETURNING id INTO v_bike_brand_id;
  
  RAISE NOTICE '✅ Created bike brand: %', v_bike_brand_id;

  -- 3. Create Bike Model (Oxygen 260)
  INSERT INTO bike_models (
    tenant_id,
    brand_id,
    name,
    year,
    is_active,
    created_at
  ) VALUES (
    v_tenant_id,
    v_bike_brand_id,
    'Oxygen 260',
    2024,
    true,
    now()
  ) RETURNING id INTO v_bike_model_id;
  
  RAISE NOTICE '✅ Created bike model: %', v_bike_model_id;

  -- 4. Create Bike (Customer's Flow Oxygen 260)
  INSERT INTO bikes (
    tenant_id,
    customer_id,
    brand_id,
    model_id,
    brand,
    model,
    serial_number,
    year,
    color,
    bike_type,
    is_active,
    created_at
  ) VALUES (
    v_tenant_id,
    v_customer_id,
    v_bike_brand_id,
    v_bike_model_id,
    'Flow',
    'Oxygen 260',
    'FLOW-OXY260-2024-001',
    2024,
    'Black',
    'mountain',
    true,
    now()
  ) RETURNING id INTO v_bike_id;
  
  RAISE NOTICE '✅ Created bike: %', v_bike_id;

  -- 5. Get a payment method (Efectivo)
  SELECT id INTO v_payment_method_id
  FROM payment_methods
  WHERE tenant_id = v_tenant_id
    AND name ILIKE '%efectivo%'
  LIMIT 1;
  
  IF v_payment_method_id IS NULL THEN
    RAISE EXCEPTION '❌ No payment method found for tenant. Run seed_payment_methods_for_tenant() first.';
  END IF;

  -- 6. Create Mechanic Job (Pega) with unique job number
  INSERT INTO mechanic_jobs (
    tenant_id,
    customer_id,
    bike_id,
    job_number,
    client_request,
    diagnosis,
    work_performed,
    status,
    priority,
    labor_cost,
    total_cost,
    deadline,
    created_at
  ) VALUES (
    v_tenant_id,
    v_customer_id,
    v_bike_id,
    'MJ-' || to_char(now(), 'YYYYMMDD') || '-' || floor(random() * 1000 + 1)::text,
    'Brake adjustment and wheel truing',
    'Brake pads worn, rear wheel out of true',
    'Replaced brake pads and trued rear wheel',
    'FINALIZADO',
    'NORMAL',
    15000,
    15000,
    now() + interval '1 day',
    now()
  ) RETURNING id INTO v_mechanic_job_id;
  
  RAISE NOTICE '✅ Created mechanic job: %', v_mechanic_job_id;

  -- 7. Create Sales Invoice (without journal entries)
  -- Note: Journal entries won't be created because we're running as service role
  -- In production, these are created automatically via triggers when authenticated users create invoices
  
  INSERT INTO sales_invoices (
    tenant_id,
    customer_id,
    invoice_number,
    date,
    due_date,
    subtotal,
    net_amount,
    iva_amount,
    total,
    paid_amount,
    balance,
    status,
    tax_treatment,
    reference,
    created_at
  ) VALUES (
    v_tenant_id,
    v_customer_id,
    'FV-00001',
    now(),
    now() + interval '30 days',
    15000,
    12605.04,
    2394.96,
    15000,
    15000,
    0,
    'paid',
    'tax_included',
    'Invoice for mechanic job: Brake adjustment and wheel truing',
    now()
  ) RETURNING id INTO v_sales_invoice_id;
  
  RAISE NOTICE '✅ Created sales invoice: %', v_sales_invoice_id;

  -- 8. Link invoice to mechanic job
  UPDATE mechanic_jobs
  SET invoice_id = v_sales_invoice_id
  WHERE id = v_mechanic_job_id;

  RAISE NOTICE '✅ Linked invoice to mechanic job';

  -- Summary
  RAISE NOTICE '
  ========================================
  ✅ Test data created successfully!
  ========================================
  Tenant ID:       %
  Customer:        % (Alan Castro)
  Bike Brand:      % (Flow)
  Bike Model:      % (Oxygen 260)
  Bike:            %
  Mechanic Job:    %
  Sales Invoice:   % (FV-00001)
  ========================================
  ', v_tenant_id, v_customer_id, v_bike_brand_id, v_bike_model_id, v_bike_id, v_mechanic_job_id, v_sales_invoice_id;

END $$;
