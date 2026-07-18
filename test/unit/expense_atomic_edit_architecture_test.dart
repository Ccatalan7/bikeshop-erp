import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('existing expenses use the atomic idempotent aggregate command', () {
    final service = File(
      'lib/modules/accounting/services/expense_service.dart',
    ).readAsStringSync();
    final form = File(
      'lib/modules/accounting/pages/expense_form_page.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260718090000_add_atomic_expense_edit.sql',
    ).readAsStringSync();
    final timestampMigration = File(
      'supabase/migrations/20260718091000_preserve_expense_posted_at_on_atomic_edit.sql',
    ).readAsStringSync();
    final coreSchema = File(
      'supabase/sql/core_schema.sql',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(service, contains("'save_expense_aggregate'"));
    expect(service, contains("'get_expense_aggregate_save_operation'"));
    expect(service, contains("'p_expected_updated_at'"));
    expect(service, contains("'total_amount': expense.totalAmount.round()"));
    expect(form, contains('categoryId: _existingExpense?.categoryId'));
    expect(form, contains('updatedAt: _existingExpense?.updatedAt'));
    expect(form, contains('(_totalPaid / 1.19).roundToDouble()'));

    expect(migration, contains('expense_aggregate_save_operations'));
    expect(
        migration, contains('Expense was modified after this form was loaded'));
    expect(migration, contains("'expense_atomic_edit'"));
    expect(migration, contains('v_net := round(v_total / 1.19, 0)'));
    expect(migration, contains('v_tax := v_total - v_net'));
    expect(migration, contains('Only the owning trigger depth may finalize'));
    expect(migration, contains('complete_expense_accounting_operation'));
    expect(timestampMigration, contains('v_before.posted_at'));
    expect(
      timestampMigration,
      contains('Preserve the original accounting timestamp'),
    );
    expect(
      coreSchema,
      contains('20260718090000_add_atomic_expense_edit.sql'),
    );
    expect(
      coreSchema,
      contains('20260718091000_preserve_expense_posted_at_on_atomic_edit.sql'),
    );
    expect(registry, contains('| Simple expense edit |'));
    expect(registry, contains('durable idempotency receipt'));
  });
}
