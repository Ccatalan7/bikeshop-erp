import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const canonicalSchema = 'supabase/sql/core_schema.sql';
  const forwardMigration =
      'supabase/migrations/20260801173000_report_payroll_reconciliation_replay.sql';
  const servicePath =
      'lib/modules/hr/services/payroll_reconciliation_service.dart';

  test('first apply and exact retry expose distinct replay receipts', () {
    final schema = File(canonicalSchema).readAsStringSync();
    final migration = File(forwardMigration).readAsStringSync();
    final service = File(servicePath).readAsStringSync();

    expect(
      schema,
      contains(
        "return import_row.apply_receipt\n"
        "          || jsonb_build_object('replayed', true);",
      ),
    );
    expect(schema, contains("'replayed',\n    false,\n    'import_id'"));
    expect(
      migration,
      contains(
        "'return import_row.apply_receipt || "
        "jsonb_build_object(''replayed'', true);'",
      ),
    );
    expect(
      migration,
      contains(
        "'apply_payroll_statement_reconciliation baseline does not match "
        "the reviewed definition'",
      ),
      reason: 'the forward patch must fail closed on an unknown live body',
    );
    expect(
      service,
      contains(
        "wasReplay: response['replayed'] == true || "
        "response['was_replay'] == true",
      ),
    );
  });
}
