-- ============================================================================
-- DATA MIGRATION: Assign all existing data to Vinabike tenant
-- ============================================================================
-- Run this IMMEDIATELY after deploying core_schema.sql
-- This assigns all existing records to the Vinabike tenant
-- ============================================================================

DO $$
DECLARE
  v_vinabike_tenant uuid := '97ef40bf-f58c-4f76-a629-c013fb3928cf';
  v_count integer;
  v_table_exists boolean;
  v_column_exists boolean;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'TENANT DATA MIGRATION STARTING';
  RAISE NOTICE 'Target Tenant: Vinabike (%)', v_vinabike_tenant;
  RAISE NOTICE '========================================';
  
  -- ============================================================================
  -- Configuration & Settings
  -- ============================================================================
  
  -- company_settings
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'company_settings' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE company_settings SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ company_settings: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ company_settings: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ company_settings: table does not exist, skipping';
  END;
  
  -- product_brands
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'product_brands' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE product_brands SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ product_brands: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ product_brands: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ product_brands: table does not exist, skipping';
  END;
  
  -- payment_methods
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'payment_methods' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE payment_methods SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ payment_methods: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ payment_methods: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ payment_methods: table does not exist, skipping';
  END;
  
  -- expense_categories
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'expense_categories' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE expense_categories SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ expense_categories: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ expense_categories: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ expense_categories: table does not exist, skipping';
  END;
  
  -- departments
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'departments' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE departments SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ departments: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ departments: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ departments: table does not exist, skipping';
  END;
  
  -- service_packages
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'service_packages' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE service_packages SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ service_packages: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ service_packages: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ service_packages: table does not exist, skipping';
  END;
  
  RAISE NOTICE '----------------------------------------';
  
  -- ============================================================================
  -- HR & Scheduling
  -- ============================================================================
  
  -- work_schedules
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'work_schedules' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE work_schedules SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ work_schedules: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ work_schedules: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ work_schedules: table does not exist, skipping';
  END;
  
  -- employee_contracts
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'employee_contracts' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE employee_contracts SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ employee_contracts: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ employee_contracts: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ employee_contracts: table does not exist, skipping';
  END;
  
  RAISE NOTICE '----------------------------------------';
  
  -- ============================================================================
  -- Expenses & Attachments
  -- ============================================================================
  
  -- expense_attachments
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'expense_attachments' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE expense_attachments SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ expense_attachments: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ expense_attachments: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ expense_attachments: table does not exist, skipping';
  END;
  
  RAISE NOTICE '----------------------------------------';
  
  -- ============================================================================
  -- Website & Ecommerce
  -- ============================================================================
  
  -- website_banners
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'website_banners' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE website_banners SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ website_banners: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ website_banners: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ website_banners: table does not exist, skipping';
  END;
  
  -- website_content
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'website_content' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE website_content SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ website_content: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ website_content: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ website_content: table does not exist, skipping';
  END;
  
  -- website_blocks
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'website_blocks' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE website_blocks SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ website_blocks: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ website_blocks: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ website_blocks: table does not exist, skipping';
  END;
  
  -- website_settings
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'website_settings' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE website_settings SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ website_settings: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ website_settings: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ website_settings: table does not exist, skipping';
  END;
  
  -- featured_products
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'featured_products' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE featured_products SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ featured_products: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ featured_products: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ featured_products: table does not exist, skipping';
  END;
  
  -- online_orders
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'online_orders' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE online_orders SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ online_orders: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ online_orders: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ online_orders: table does not exist, skipping';
  END;
  
  -- online_order_items
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'online_order_items' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE online_order_items SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ online_order_items: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ online_order_items: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ online_order_items: table does not exist, skipping';
  END;
  
  RAISE NOTICE '----------------------------------------';
  
  -- ============================================================================
  -- POS & Orders
  -- ============================================================================
  
  -- orders
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'orders' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE orders SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ orders: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ orders: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ orders: table does not exist, skipping';
  END;
  
  -- order_items
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'order_items' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE order_items SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ order_items: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ order_items: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ order_items: table does not exist, skipping';
  END;
  
  RAISE NOTICE '----------------------------------------';
  
  -- ============================================================================
  -- Bikeshop/Maintenance
  -- ============================================================================
  
  -- mechanic_jobs
  BEGIN
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'mechanic_jobs' AND column_name = 'tenant_id') INTO v_column_exists;
    IF v_column_exists THEN
      UPDATE mechanic_jobs SET tenant_id = v_vinabike_tenant WHERE tenant_id IS NULL;
      GET DIAGNOSTICS v_count = ROW_COUNT;
      RAISE NOTICE '✓ mechanic_jobs: % records migrated', v_count;
    ELSE
      RAISE NOTICE '⚠ mechanic_jobs: tenant_id column not found, skipping';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE NOTICE '⚠ mechanic_jobs: table does not exist, skipping';
  END;
  
  RAISE NOTICE '========================================';
  RAISE NOTICE 'DATA MIGRATION COMPLETE';
  RAISE NOTICE 'All existing data assigned to Vinabike';
  RAISE NOTICE '========================================';
  
END $$;
