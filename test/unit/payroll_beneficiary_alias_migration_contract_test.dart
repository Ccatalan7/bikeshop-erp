import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migrationPath =
      'supabase/migrations/20260729190000_learn_payroll_beneficiary_alias.sql';

  test('canonical schema includes the beneficiary alias learning migration',
      () {
    final canonicalSchema =
        File('supabase/sql/core_schema.sql').readAsStringSync();

    expect(
      canonicalSchema,
      contains(
        r'\ir ../migrations/20260729190000_learn_payroll_beneficiary_alias.sql',
      ),
    );
  });

  test('alias learning keeps one RPC writer and no authenticated table writer',
      () {
    final migration = File(migrationPath).readAsStringSync();

    expect(
      migration,
      matches(
        RegExp(
          r'create\s+function\s+public\.learn_payroll_beneficiary_alias'
          r'\s*\(\s*p_employee_id\s+uuid,\s*p_alias\s+text\s*\)'
          r'[\s\S]*?security\s+definer'
          r'[\s\S]*?set\s+search_path\s*=\s*pg_catalog,\s*public,\s*pg_temp',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      migration,
      matches(
        RegExp(
          r'grant\s+execute\s+on\s+function\s+'
          r'public\.learn_payroll_beneficiary_alias\s*\(\s*uuid,\s*text\s*\)'
          r'\s+to\s+authenticated',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      migration,
      matches(
        RegExp(
          r'revoke\s+insert,\s*update,\s*delete\s+on\s+table\s+'
          r'public\.payroll_beneficiary_aliases\s+from\s+authenticated',
          caseSensitive: false,
        ),
      ),
    );
  });
}
