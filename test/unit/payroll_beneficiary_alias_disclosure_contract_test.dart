import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payroll beneficiary aliases are guarded as sensitive personal data',
      () {
    final guardedTables = File('scripts/db/sensitive_tables.txt')
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toSet();

    expect(
      guardedTables,
      contains('payroll_beneficiary_aliases'),
      reason: 'Bank beneficiary aliases contain employee-identifying names and '
          'must reject hosted `select *` disclosure by default.',
    );
  });
}
