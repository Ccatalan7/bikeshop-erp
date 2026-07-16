import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public customer service has no direct mechanic-job status writer', () {
    final source = File(
      'lib/public_store/services/customer_account_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('approveServiceEstimate')));
    expect(source, isNot(contains('rejectServiceEstimate')));
    expect(
      source,
      isNot(
        contains("_supabase.from('mechanic_jobs').update({"),
      ),
    );
  });
}
