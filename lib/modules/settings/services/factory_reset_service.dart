import 'package:supabase_flutter/supabase_flutter.dart';

class FactoryResetService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Performs a complete factory reset by deleting all data from all tables
  /// WARNING: This is irreversible!
  Future<void> performFactoryReset() async {
    try {
      // Delete in order to respect foreign key constraints
      // Start with child tables, end with parent tables

      // Helper function to safely delete from table
      Future<void> safeDelete(String table) async {
        try {
          await _supabase.from(table).delete().neq('id', '00000000-0000-0000-0000-000000000000');
          print('✅ Deleted data from $table');
        } catch (e) {
          print('⚠️ Could not delete from $table: $e');
          // Continue with other tables even if this one fails
        }
      }

      // 1. Delete journal lines (depends on journal entries)
      await safeDelete('journal_lines');

      // 2. Delete journal entries
      await safeDelete('journal_entries');

      // 3. Delete sales payments
      await safeDelete('sales_payments');

      // 4. Delete purchase payments (might not exist yet)
      await safeDelete('purchase_payments');

      // 5. Delete sales invoices
      await safeDelete('sales_invoices');

      // 6. Delete purchase invoices
      await safeDelete('purchase_invoices');

      // 7. Delete POS transactions
      await safeDelete('pos_transactions');

      // 8. Delete stock movements
      await safeDelete('stock_movements');

      // 9. Delete products
      await safeDelete('products');

      // 10. Delete categories
      await safeDelete('categories');

      // 11. Delete customers
      await safeDelete('customers');

      // 12. Delete suppliers
      await safeDelete('suppliers');

      // 13. Delete work orders (maintenance)
      await safeDelete('work_orders');

      // 14. Delete employees
      await safeDelete('employees');

      // 15. Delete contracts
      await safeDelete('contracts');

      // 16. Delete attendance records
      await safeDelete('attendance');

      // 17. Delete payroll
      await safeDelete('payroll');

      // 18. Delete warehouses (if exists)
      await safeDelete('warehouses');

      // 19. Delete accounts (chart of accounts) - only user-created ones
      try {
        await _supabase.from('accounts').delete().eq('is_active', true);
        print('✅ Deleted user accounts');
      } catch (e) {
        print('⚠️ Could not delete accounts: $e');
      }

      // NOTE: We don't delete users/profiles as they're authentication-related
      // Users should remain to allow re-login after reset

      print('✅ Factory reset completed successfully');
    } catch (e) {
      print('❌ Error during factory reset: $e');
      rethrow;
    }
  }

  /// Alternative: Reset specific module data only
  Future<void> resetModule(String moduleName) async {
    switch (moduleName) {
      case 'sales':
        await _supabase.from('sales_payments').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        await _supabase.from('sales_invoices').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        break;

      case 'purchases':
        await _supabase.from('purchase_payments').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        await _supabase.from('purchase_invoices').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        break;

      case 'inventory':
        await _supabase.from('stock_movements').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        await _supabase.from('products').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        await _supabase.from('categories').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        break;

      case 'accounting':
        await _supabase.from('journal_lines').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        await _supabase.from('journal_entries').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        break;

      case 'crm':
        await _supabase.from('customers').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        break;

      case 'hr':
        await _supabase.from('attendance').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        await _supabase.from('payroll').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        await _supabase.from('contracts').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        await _supabase.from('employees').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        break;

      default:
        throw Exception('Unknown module: $moduleName');
    }
  }

  /// Get data statistics before reset (for confirmation)
  Future<Map<String, int>> getDataStatistics() async {
    final stats = <String, int>{};

    try {
      // Count records in each table
      final tables = [
        'sales_invoices',
        'purchase_invoices',
        'products',
        'customers',
        'suppliers',
        'employees',
        'journal_entries',
        'stock_movements',
        'pos_transactions',
        'work_orders',
      ];

      for (final table in tables) {
        try {
          final response = await _supabase
              .from(table)
              .select()
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
