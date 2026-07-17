import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NIC Chile OCR uses the dedicated digital expense classification', () {
    final rail = File(
      'lib/shared/widgets/quick_access_expense_rail.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260717070000_add_digital_services_expense_classification.sql',
    ).readAsStringSync();
    final collisionMigration = File(
      'supabase/migrations/20260717080000_prevent_expense_number_journal_collisions.sql',
    ).readAsStringSync();
    final coreSchema = File(
      'supabase/sql/core_schema.sql',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(
      rail,
      contains('QuickExpenseReceiptParser.domainExpenseAccountCode'),
    );
    expect(
      rail,
      contains('QuickExpenseReceiptParser.domainExpenseCategoryName'),
    );
    expect(migration, contains("'6207-01'"));
    expect(migration, contains("'Dominios y Hosting'"));
    expect(migration, contains("'Servicios Digitales'"));
    expect(
      migration,
      contains('from public, anon, authenticated'),
    );
    expect(
      collisionMigration,
      contains("entry.source_module = 'expenses'"),
    );
    expect(
      collisionMigration,
      contains('entry.source_document_id = p_expense_id'),
    );
    expect(
      collisionMigration,
      contains('Expected three legacy expense journal predicates'),
    );
    expect(
        coreSchema, contains('seed_digital_services_expense_classification'));
    expect(registry, contains('`6207-01 · Dominios y Hosting`'));
    expect(registry, contains('operational category `Servicios Digitales`'));
    expect(registry, contains('immutable expense UUID'));
  });
}
