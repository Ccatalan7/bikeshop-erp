-- ====================================================================================================
-- FACTORY RESET - VINABIKE ERP
-- ====================================================================================================
-- This script deletes ALL transactional data while preserving:
--   ✅ Chart of Accounts
--   ✅ Payment Methods
--   ✅ Company Settings
--   ✅ Website Settings
--   ✅ Tenant record
--   ✅ User profiles
--   ✅ Database schema (tables, functions, triggers)
--
-- ⚠️  WARNING: This is IRREVERSIBLE. All invoices, customers, products, etc. will be deleted.
-- ====================================================================================================

-- Tenant: vinabike (subdomain: vinabike)
-- Tenant ID: 5443b130-cc28-45af-a420-cd500b288890

DO $$
DECLARE
  v_tenant_id uuid := '5443b130-cc28-45af-a420-cd500b288890'; -- vinabike tenant
BEGIN

  RAISE NOTICE '====================================================================================================';
  RAISE NOTICE 'FACTORY RESET STARTING FOR TENANT: %', v_tenant_id;
  RAISE NOTICE '====================================================================================================';

  -- ================================================================================================
  -- 1. SALES MODULE
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Cleaning SALES data...';
  
  DELETE FROM sales_payments WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted sales_payments';
  
  DELETE FROM sales_invoices WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted sales_invoices (includes line items in jsonb)';

  -- ================================================================================================
  -- 2. PURCHASES MODULE
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Cleaning PURCHASES data...';
  
  DELETE FROM purchase_payments WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted purchase_payments';
  
  DELETE FROM purchase_invoices WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted purchase_invoices (includes line items in jsonb)';

  -- ================================================================================================
  -- 3. INVENTORY MODULE
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Cleaning INVENTORY data...';
  
  DELETE FROM stock_adjustments WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted stock_adjustments';
  
  DELETE FROM inventory_adjustments WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted inventory_adjustments';
  
  DELETE FROM stock_movements WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted stock_movements';
  
  DELETE FROM smart_purchase_list WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted smart_purchase_list';
  
  DELETE FROM products WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted products';
  
  DELETE FROM product_categories WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted product_categories';
  
  DELETE FROM product_brands WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted product_brands';

  -- ================================================================================================
  -- 4. CRM MODULE
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Cleaning CRM data...';
  
  DELETE FROM customer_addresses WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted customer_addresses';
  
  DELETE FROM loyalty WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted loyalty';
  
  DELETE FROM customers WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted customers';
  
  DELETE FROM suppliers WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted suppliers';

  -- ================================================================================================
  -- 5. BIKESHOP MODULE (PEGAS/MAINTENANCE)
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Cleaning BIKESHOP data...';
  
  DELETE FROM mechanic_job_items WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted mechanic_job_items';
  
  DELETE FROM mechanic_job_labor WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted mechanic_job_labor';
  
  DELETE FROM mechanic_job_timeline WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted mechanic_job_timeline';
  
  DELETE FROM mechanic_jobs WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted mechanic_jobs';
  
  DELETE FROM service_packages WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted service_packages';
  
  DELETE FROM bikes WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted bikes';
  
  DELETE FROM bike_models WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted bike_models';
  
  DELETE FROM bike_brands WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted bike_brands';
  
  -- ⚠️ bike_catalog is GLOBAL (no tenant_id) - encyclopedia shared across all shops
  RAISE NOTICE '   ⚠️  Preserved bike_catalog (global encyclopedia)';

  -- ================================================================================================
  -- 6. ACCOUNTING MODULE
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Cleaning ACCOUNTING data...';
  
  DELETE FROM journal_lines WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted journal_lines';
  
  DELETE FROM journal_entries WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted journal_entries';
  
  DELETE FROM f29_declarations WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted f29_declarations';
  
  DELETE FROM expense_attachments WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted expense_attachments';
  
  DELETE FROM expense_payments WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted expense_payments';
  
  DELETE FROM expense_lines WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted expense_lines';
  
  DELETE FROM expenses WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted expenses';
  
  DELETE FROM expense_categories WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted expense_categories';
  
  -- ⚠️ DELETE DUPLICATE/MANUAL ACCOUNTS (not part of seed)
  -- Keep only the 30 official accounts from seed_chart_of_accounts()
  DELETE FROM accounts 
  WHERE tenant_id = v_tenant_id 
    AND code NOT IN (
      '1101', '1105', '1110', '1130', '1190',  -- Assets (5)
      '2101', '2105', '2120', '2150',          -- Liabilities & Tax (4)
      '3101', '3201',                          -- Equity (2)
      '4100', '4102', '4201',                  -- Income (3)
      '5100',                                  -- Cost of Sales (1)
      '6101', '6102', '6103',                  -- Personnel expenses (3)
      '6201', '6202', '6203', '6204', '6205',  -- Operating expenses (5)
      '6301', '6302',                          -- Marketing (2)
      '6401',                                  -- Rent (1)
      '6501', '6502',                          -- Utilities (2)
      '6601',                                  -- Insurance (1)
      '6701',                                  -- Depreciation (1)
      '6801'                                   -- Other expenses (1)
    );
  RAISE NOTICE '   ✅ Deleted duplicate/manual accounts (kept only 31 seed accounts)';
  
  -- ⚠️ DO NOT DELETE: Official Chart of Accounts (31 accounts from seed)
  -- ⚠️ DO NOT DELETE: payment_methods (keep seed data)
  RAISE NOTICE '   ⚠️  Preserved accounts (chart of accounts)';
  RAISE NOTICE '   ⚠️  Preserved payment_methods (seed data)';

  -- ================================================================================================
  -- 7. HR MODULE
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Cleaning HR data...';
  
  DELETE FROM attendance_records WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted attendance_records';
  
  DELETE FROM attendances WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted attendances';
  
  DELETE FROM payroll_records WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted payroll_records';
  
  DELETE FROM payroll_entries WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted payroll_entries';
  
  DELETE FROM payroll_runs WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted payroll_runs';
  
  DELETE FROM medical_leaves WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted medical_leaves';
  
  DELETE FROM leave_requests WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted leave_requests';
  
  DELETE FROM employment_contracts WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted employment_contracts';
  
  DELETE FROM employee_contracts WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted employee_contracts';
  
  DELETE FROM work_schedules WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted work_schedules';
  
  DELETE FROM shifts WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted shifts';
  
  DELETE FROM employees WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted employees';
  
  DELETE FROM job_roles WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted job_roles';
  
  DELETE FROM departments WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted departments';

  -- ================================================================================================
  -- 8. WEBSITE/ECOMMERCE MODULE
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Cleaning WEBSITE/ECOMMERCE data...';
  
  DELETE FROM online_order_items WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted online_order_items';
  
  DELETE FROM online_orders WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted online_orders';
  
  DELETE FROM order_items WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted order_items';
  
  DELETE FROM orders WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted orders';
  
  DELETE FROM featured_products WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted featured_products';
  
  DELETE FROM website_banners WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted website_banners';
  
  DELETE FROM website_blocks WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted website_blocks';
  
  DELETE FROM website_content WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted website_content';
  
  DELETE FROM content_media WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted content_media';
  
  DELETE FROM content_items WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted content_items';
  
  -- ⚠️ DO NOT DELETE: website_settings (keep configuration)
  RAISE NOTICE '   ⚠️  Preserved website_settings (configuration data)';

  -- ================================================================================================
  -- 9. WHEEL BUILDING MODULE
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Cleaning WHEEL BUILDING data...';
  
  DELETE FROM wheel_builds WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted wheel_builds';
  
  DELETE FROM wheel_spokes WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted wheel_spokes';
  
  DELETE FROM wheel_rims WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted wheel_rims';
  
  DELETE FROM wheel_hubs WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted wheel_hubs';

  -- ================================================================================================
  -- 10. MARKETING MODULE
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Cleaning MARKETING data...';
  
  DELETE FROM campaign_metrics WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted campaign_metrics';
  
  DELETE FROM campaigns WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted campaigns';

  -- ================================================================================================
  -- 11. PURCHASE/SALES ORDERS
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Cleaning ORDERS data...';
  
  DELETE FROM purchase_order_items WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted purchase_order_items';
  
  DELETE FROM purchase_orders WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted purchase_orders';
  
  DELETE FROM sales_order_items WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted sales_order_items';
  
  DELETE FROM sales_orders WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted sales_orders';
  
  DELETE FROM work_order_items WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted work_order_items';

  -- ================================================================================================
  -- 12. ANALYTICS & MISC
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '🧹 Cleaning ANALYTICS data...';
  
  DELETE FROM analytics_snapshots WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted analytics_snapshots';
  
  DELETE FROM vehicles WHERE tenant_id = v_tenant_id;
  RAISE NOTICE '   ✅ Deleted vehicles';

  -- ================================================================================================
  -- 13. SETTINGS
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '⚠️  Preserving SETTINGS...';
  
  -- ⚠️ DO NOT DELETE: company_settings (keep configuration)
  -- ⚠️ DO NOT DELETE: user_profiles (keep users)
  -- ⚠️ DO NOT DELETE: tenants (keep tenant record)
  RAISE NOTICE '   ⚠️  Preserved company_settings';
  RAISE NOTICE '   ⚠️  Preserved user_profiles';
  RAISE NOTICE '   ⚠️  Preserved tenants';

  -- ================================================================================================
  -- SUMMARY
  -- ================================================================================================
  RAISE NOTICE '';
  RAISE NOTICE '====================================================================================================';
  RAISE NOTICE '✅ FACTORY RESET COMPLETE';
  RAISE NOTICE '====================================================================================================';
  RAISE NOTICE '';
  RAISE NOTICE '✅ DELETED:';
  RAISE NOTICE '   - All sales invoices, payments, items';
  RAISE NOTICE '   - All purchase invoices, payments, items';
  RAISE NOTICE '   - All products, categories, stock adjustments';
  RAISE NOTICE '   - All customers and suppliers';
  RAISE NOTICE '   - All bikes, mechanic jobs (pegas)';
  RAISE NOTICE '   - All journal entries';
  RAISE NOTICE '   - All employees, contracts, attendance';
  RAISE NOTICE '   - All website orders';
  RAISE NOTICE '   - All wheel builds';
  RAISE NOTICE '   - All marketing campaigns';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️  PRESERVED:';
  RAISE NOTICE '   - Chart of Accounts (30 accounts)';
  RAISE NOTICE '   - Payment Methods (4 methods)';
  RAISE NOTICE '   - Company Settings (8 settings)';
  RAISE NOTICE '   - Website Settings (7 settings)';
  RAISE NOTICE '   - Tenant record';
  RAISE NOTICE '   - User profiles';
  RAISE NOTICE '';
  RAISE NOTICE '🚀 Your database is now CLEAN and ready for production data import!';
  RAISE NOTICE '====================================================================================================';

END $$;

-- ====================================================================================================
-- VERIFICATION QUERIES (Run these after factory reset to confirm)
-- ====================================================================================================

-- Check counts (should all be 0 except preserved data)
SELECT 'products' as table_name, COUNT(*) as count FROM products WHERE tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
UNION ALL
SELECT 'customers', COUNT(*) FROM customers WHERE tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
UNION ALL
SELECT 'sales_invoices', COUNT(*) FROM sales_invoices WHERE tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
UNION ALL
SELECT 'purchase_invoices', COUNT(*) FROM purchase_invoices WHERE tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
UNION ALL
SELECT 'journal_entries', COUNT(*) FROM journal_entries WHERE tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
UNION ALL
SELECT 'accounts', COUNT(*) FROM accounts WHERE tenant_id = '5443b130-cc28-45af-a420-cd500b288890' -- Should be 30
UNION ALL
SELECT 'payment_methods', COUNT(*) FROM payment_methods WHERE tenant_id = '5443b130-cc28-45af-a420-cd500b288890'; -- Should be 4
