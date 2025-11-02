import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/tenant_service.dart';

class FactoryResetService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TenantService _tenantService = TenantService();

  /// Performs a complete factory reset by deleting all data from CURRENT TENANT ONLY
  /// WARNING: This is irreversible!
  Future<void> performFactoryReset() async {
    try {
      // CRITICAL: Get current user's tenant_id to ensure we ONLY delete THIS tenant's data
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated - cannot perform reset');
      }

      // Get tenant_id from user_profiles table (single source of truth)
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null || tenantId.isEmpty) {
        throw Exception('User has no tenant_id - cannot perform reset');
      }

      print('🔒 Factory reset will delete data ONLY for tenant: $tenantId');

      // Helper function to safely delete from table WITH TENANT FILTER
      Future<void> safeDelete(String table) async {
        try {
          // CRITICAL: Always filter by tenant_id to prevent cross-tenant deletion!
          await _supabase
              .from(table)
              .delete()
              .eq('tenant_id', tenantId); // ← TENANT FILTER - DO NOT REMOVE!
          
          print('✅ Deleted tenant data from $table');
        } catch (e) {
          print('⚠️ Could not delete from $table: $e');
          // Continue with other tables even if this one fails
        }
      }

      // Delete in order to respect foreign key constraints
      // Start with child tables, end with parent tables

      // 1. Delete journal lines (depends on journal entries)
      await safeDelete('journal_lines');

      // 2. Delete journal entries
      await safeDelete('journal_entries');

      // 3. Delete sales payments
      await safeDelete('sales_payments');

      // 4. Delete purchase payments
      await safeDelete('purchase_payments');

      // 5. Delete sales invoices
      await safeDelete('sales_invoices');

      // 6. Delete purchase invoices
      await safeDelete('purchase_invoices');

      // 7. Delete sales orders (before customers due to FK)
      await safeDelete('sales_orders');

      // 8. Delete stock movements
      await safeDelete('stock_movements');

      // 9. Delete products
      await safeDelete('products');

      // 10. Delete categories
      await safeDelete('categories');

      // 11. Delete product categories junction
      await safeDelete('product_categories');

      // 12. Delete product brands
      await safeDelete('product_brands');

      // 13. Delete customers
      await safeDelete('customers');

      // 14. Delete suppliers
      await safeDelete('suppliers');

      // 15. Delete work orders (maintenance)
      await safeDelete('work_orders');

      // 16. Delete mechanic jobs
      await safeDelete('mechanic_jobs');

      // 17. Delete bikes
      await safeDelete('bikes');

      // 18. Delete employees
      await safeDelete('employees');

      // 19. Delete attendances
      await safeDelete('attendances');

      // 20. Delete contracts
      await safeDelete('contracts');

      // 21. Delete departments
      await safeDelete('departments');

      // 22. Delete warehouses
      await safeDelete('warehouses');

      // 23. Delete accounts (chart of accounts)
      await safeDelete('accounts');

      // 24. Delete expenses
      await safeDelete('expenses');

      // 25. Delete online orders
      await safeDelete('online_orders');

      // 26. Delete website blocks
      await safeDelete('website_blocks');

      // 27. Delete website settings
      await safeDelete('website_settings');

      // 28. Delete payment methods
      await safeDelete('payment_methods');

      print('✅ Factory reset completed successfully for tenant: $tenantId');
      print('🔒 Other tenants\' data was NOT affected');
    } catch (e) {
      print('❌ Error during factory reset: $e');
      rethrow;
    }
  }

  /// Alternative: Reset specific module data only (TENANT-SAFE)
  Future<void> resetModule(String moduleName) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw Exception('User has no tenant_id');
    }

    print('🔒 Resetting module "$moduleName" for tenant: $tenantId');

    switch (moduleName) {
      case 'sales':
        await _supabase.from('sales_payments').delete().eq('tenant_id', tenantId);
        await _supabase.from('sales_invoices').delete().eq('tenant_id', tenantId);
        break;

      case 'purchases':
        await _supabase.from('purchase_payments').delete().eq('tenant_id', tenantId);
        await _supabase.from('purchase_invoices').delete().eq('tenant_id', tenantId);
        break;

      case 'inventory':
        await _supabase.from('stock_movements').delete().eq('tenant_id', tenantId);
        await _supabase.from('products').delete().eq('tenant_id', tenantId);
        await _supabase.from('categories').delete().eq('tenant_id', tenantId);
        break;

      case 'accounting':
        await _supabase.from('journal_lines').delete().eq('tenant_id', tenantId);
        await _supabase.from('journal_entries').delete().eq('tenant_id', tenantId);
        break;

      case 'crm':
        await _supabase.from('customers').delete().eq('tenant_id', tenantId);
        break;

      case 'hr':
        await _supabase.from('attendances').delete().eq('tenant_id', tenantId);
        await _supabase.from('contracts').delete().eq('tenant_id', tenantId);
        await _supabase.from('employees').delete().eq('tenant_id', tenantId);
        await _supabase.from('departments').delete().eq('tenant_id', tenantId);
        break;

      default:
        throw Exception('Unknown module: $moduleName');
    }

    print('✅ Module "$moduleName" reset completed for tenant: $tenantId');
  }

  /// Get data statistics before reset (for confirmation) - TENANT-SAFE
  Future<Map<String, int>> getDataStatistics() async {
    final stats = <String, int>{};

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return stats;

      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null || tenantId.isEmpty) return stats;

      // Count records in each table FOR THIS TENANT ONLY
      final tables = [
        'sales_invoices',
        'purchase_invoices',
        'products',
        'customers',
        'suppliers',
        'employees',
        'journal_entries',
        'stock_movements',
        'work_orders',
        'mechanic_jobs',
      ];

      for (final table in tables) {
        try {
          final response = await _supabase
              .from(table)
              .select()
              .eq('tenant_id', tenantId)
              .count();
          stats[table] = response.count;
        } catch (e) {
          // Table might not exist or RLS might prevent access
          stats[table] = 0;
        }
      }
    } catch (e) {
      print('Error getting statistics: $e');
    }

    return stats;
  }
  
  /// Performs selective deletion based on user choices
  Future<void> performSelectiveReset({
    required bool deleteSales,
    required bool deletePurchases,
    required bool deleteInventory,
    required bool deleteStockMovements,
    required bool deleteCustomers,
    required bool deleteSuppliers,
    required bool deleteAccounting,
    required bool deleteEmployees,
    required bool deleteMechanic,
    required bool deleteEcommerce,
  }) async {
    try {
      // Get current user's tenant_id
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated - cannot perform reset');
      }

      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null || tenantId.isEmpty) {
        throw Exception('User has no tenant_id - cannot perform reset');
      }

      print('🔒 Selective reset for tenant: $tenantId');

      // Helper function to safely delete from table WITH TENANT FILTER
      Future<void> safeDelete(String table) async {
        try {
          await _supabase
              .from(table)
              .delete()
              .eq('tenant_id', tenantId);
          print('✅ Deleted tenant data from $table');
        } catch (e) {
          print('⚠️ Could not delete from $table: $e');
        }
      }

      // Delete sales data
      if (deleteSales) {
        await safeDelete('sales_payments');
        await safeDelete('sales_invoices');
        await safeDelete('sales_orders');
        print('✅ Sales data deleted');
      }

      // Delete purchases data
      if (deletePurchases) {
        await safeDelete('purchase_payments');
        await safeDelete('purchase_invoices');
        await safeDelete('smart_purchase_list');
        print('✅ Purchases data deleted');
      }

      // Delete inventory data
      if (deleteInventory) {
        await safeDelete('stock_movements');
        await safeDelete('stock_adjustments');
        await safeDelete('products');
        await safeDelete('product_categories');
        await safeDelete('product_brands');
        await safeDelete('warehouses');
        print('✅ Inventory data deleted');
      }

      // Delete stock movements only (without deleting products)
      // BUT revert the stock adjustments first to restore original quantities
      // ONLY if we're NOT also deleting inventory (if deleting inventory, products will be deleted anyway)
      if (deleteStockMovements && !deleteInventory) {
        // Step 1: Revert all stock adjustments by reading them and updating products
        try {
          final adjustmentsResponse = await _supabase
              .from('stock_adjustments')
              .select('product_id, quantity')
              .eq('tenant_id', tenantId);
          
          final adjustments = adjustmentsResponse as List<dynamic>;
          
          if (adjustments.isNotEmpty) {
            print('🔄 Reverting ${adjustments.length} stock adjustments...');
            
            // Group adjustments by product_id to calculate total adjustment per product
            final Map<String, int> productAdjustments = {};
            for (final adj in adjustments) {
              final productId = adj['product_id'] as String;
              final quantity = adj['quantity'] as int;
              productAdjustments[productId] = (productAdjustments[productId] ?? 0) + quantity;
            }
            
            // Update each product's inventory by reversing the adjustments
            for (final entry in productAdjustments.entries) {
              final productId = entry.key;
              final totalAdjustment = entry.value;
              
              try {
                // Fetch current inventory
                final productData = await _supabase
                    .from('products')
                    .select('inventory_qty')
                    .eq('id', productId)
                    .eq('tenant_id', tenantId)
                    .maybeSingle();
                
                if (productData == null) {
                  print('  ⚠️ Product $productId not found, skipping revert');
                  continue;
                }
                
                final currentQty = productData['inventory_qty'] as int;
                final revertedQty = currentQty - totalAdjustment; // Subtract the adjustment
                
                // Update product with reverted quantity
                await _supabase
                    .from('products')
                    .update({'inventory_qty': revertedQty})
                    .eq('id', productId)
                    .eq('tenant_id', tenantId);
                
                print('  ↩️ Product $productId: $currentQty → $revertedQty (reverted $totalAdjustment)');
              } catch (e) {
                print('  ⚠️ Error reverting product $productId: $e');
                // Continue with next product
              }
            }
            
            print('✅ Stock adjustments reverted for ${productAdjustments.length} products');
          } else {
            print('ℹ️ No stock adjustments to revert (history already deleted?)');
          }
        } catch (e) {
          print('⚠️ Error reverting stock adjustments: $e');
          // Continue with deletion even if revert fails
        }
        
        // Step 2: Now delete the records (even if there's no history, clean up what's left)
        await safeDelete('stock_movements');
        await safeDelete('stock_adjustments');
        print('✅ Stock movements data deleted');
      } else if (deleteStockMovements && deleteInventory) {
        // If deleting both, no need to revert - products will be deleted anyway
        print('ℹ️ Skipping stock revert (products will be deleted)');
        await safeDelete('stock_movements');
        await safeDelete('stock_adjustments');
        print('✅ Stock movements data deleted');
      }

      // Delete customers
      if (deleteCustomers) {
        await safeDelete('customer_addresses');
        await safeDelete('loyalty');
        await safeDelete('customers');
        print('✅ Customers deleted');
      }

      // Delete suppliers
      if (deleteSuppliers) {
        await safeDelete('suppliers');
        print('✅ Suppliers deleted');
      }

      // Delete accounting data
      if (deleteAccounting) {
        await safeDelete('journal_lines');
        await safeDelete('journal_entries');
        await safeDelete('expenses');
        // Note: We keep chart of accounts as it's structural
        print('✅ Accounting data deleted');
      }

      // Delete HR data
      if (deleteEmployees) {
        await safeDelete('attendances');
        await safeDelete('contracts');
        await safeDelete('employees');
        await safeDelete('departments');
        print('✅ HR data deleted');
      }

      // Delete mechanic/workshop data
      if (deleteMechanic) {
        await safeDelete('mechanic_job_parts');
        await safeDelete('mechanic_jobs');
        await safeDelete('work_orders');
        await safeDelete('bikes');
        print('✅ Mechanic data deleted');
      }

      // Delete e-commerce data
      if (deleteEcommerce) {
        await safeDelete('online_orders');
        await safeDelete('website_blocks');
        // Note: website_settings kept as they're configuration
        print('✅ E-commerce data deleted');
      }

      print('✅ Selective reset completed for tenant: $tenantId');
    } catch (e) {
      print('❌ Error during selective reset: $e');
      rethrow;
    }
  }
}

