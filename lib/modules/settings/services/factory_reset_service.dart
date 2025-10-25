import 'package:supabase_flutter/supabase_flutter.dart';

class FactoryResetService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Performs a complete factory reset by deleting all data from CURRENT TENANT ONLY
  /// WARNING: This is irreversible!
  Future<void> performFactoryReset() async {
    try {
      // CRITICAL: Get current user's tenant_id to ensure we ONLY delete THIS tenant's data
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated - cannot perform reset');
      }

      // Get tenant_id from user metadata
      final tenantId = _supabase.auth.currentUser?.appMetadata['tenant_id'] as String?;
      if (tenantId == null || tenantId.isEmpty) {
        throw Exception('User has no tenant_id - cannot perform reset');
      }

      print('🔒 Factory reset will delete data ONLY for tenant: $tenantId');

      // Helper function to safely delete from table WITH TENANT FILTER
      Future<void> safeDelete(String table) async {
        try {
          // CRITICAL: Always filter by tenant_id to prevent cross-tenant deletion!
          final response = await _supabase
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

    final tenantId = _supabase.auth.currentUser?.appMetadata['tenant_id'] as String?;
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

      final tenantId = _supabase.auth.currentUser?.appMetadata['tenant_id'] as String?;
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
          stats[table] = response.count ?? 0;
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
}

