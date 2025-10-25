-- ============================================================================
-- MIGRATE ALL EXISTING DATA TO VINABIKE TENANT
-- ============================================================================
-- Updates all rows with NULL or missing tenant_id to Vinabike's tenant

DO $$
DECLARE
  vinabike_tenant_id uuid := '97ef40bf-f58c-4f76-a629-c013fb3928cf';
  v_table text;
  v_updated integer;
  v_tables text[] := ARRAY[
    'analytics_snapshots', 'attendance_records', 'campaign_metrics', 'campaigns',
    'companies', 'company_settings', 'content_items', 'content_media',
    'employee_contracts', 'featured_products', 'inventory_adjustments', 'leave_requests',
    'online_order_items', 'payroll_entries', 'payroll_runs', 'purchase_order_items',
    'purchase_orders', 'sales_order_items', 'sales_orders', 'service_packages',
    'shifts', 'users_profiles', 'vehicles', 'website_banners', 'work_order_items',
    'work_schedules'
  ];
BEGIN
  RAISE NOTICE 'Starting data migration to Vinabike tenant...';
  
  FOREACH v_table IN ARRAY v_tables LOOP
    BEGIN
      -- Check if table exists
      IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = v_table AND table_schema = 'public'
      ) THEN
        -- Update rows with NULL tenant_id
        EXECUTE format('UPDATE %I SET tenant_id = $1 WHERE tenant_id IS NULL', v_table)
        USING vinabike_tenant_id;
        
        GET DIAGNOSTICS v_updated = ROW_COUNT;
        
        IF v_updated > 0 THEN
          RAISE NOTICE '✅ Migrated % rows in %', v_updated, v_table;
        ELSE
          RAISE NOTICE '⏭️  No rows to migrate in %', v_table;
        END IF;
      ELSE
        RAISE NOTICE '⚠️  Table % does not exist', v_table;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '❌ Error migrating %: %', v_table, SQLERRM;
    END;
  END LOOP;
  
  RAISE NOTICE '✅ Data migration complete!';
END $$;

-- ============================================================================
-- VERIFICATION: Check for any remaining NULL tenant_id values
-- ============================================================================

DO $$
DECLARE
  v_table text;
  v_null_count integer;
  v_tables text[] := ARRAY[
    'analytics_snapshots', 'attendance_records', 'campaign_metrics', 'campaigns',
    'companies', 'company_settings', 'content_items', 'content_media',
    'employee_contracts', 'featured_products', 'inventory_adjustments', 'leave_requests',
    'online_order_items', 'payroll_entries', 'payroll_runs', 'purchase_order_items',
    'purchase_orders', 'sales_order_items', 'sales_orders', 'service_packages',
    'shifts', 'users_profiles', 'vehicles', 'website_banners', 'work_order_items',
    'work_schedules'
  ];
BEGIN
  RAISE NOTICE 'Checking for NULL tenant_id values...';
  
  FOREACH v_table IN ARRAY v_tables LOOP
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = v_table AND table_schema = 'public'
      ) THEN
        EXECUTE format('SELECT COUNT(*) FROM %I WHERE tenant_id IS NULL', v_table)
        INTO v_null_count;
        
        IF v_null_count > 0 THEN
          RAISE WARNING '⚠️  % has % rows with NULL tenant_id!', v_table, v_null_count;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Ignore errors for tables that don't exist
    END;
  END LOOP;
  
  RAISE NOTICE '✅ Verification complete!';
END $$;
