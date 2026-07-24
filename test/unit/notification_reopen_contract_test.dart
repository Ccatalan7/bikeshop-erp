import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('repeatable notification requests reach every modal or selected host',
      () {
    final router = _read('lib/shared/routes/app_router.dart');
    final mail = _read('lib/modules/mail/pages/mail_inbox_page.dart');
    final files = _read(
      'lib/modules/storage/widgets/app_files_panel.dart',
    );
    final attendances = _read(
      'lib/modules/hr/pages/attendances_page.dart',
    );
    final orders = _read(
      'lib/modules/website/pages/online_orders_page.dart',
    );
    final payments = _read(
      'lib/modules/sales/pages/payment_form_page.dart',
    );

    expect(
      RegExp("state\\.uri\\.queryParameters\\['openRequest'\\]")
          .allMatches(router)
          .length,
      greaterThanOrEqualTo(5),
    );

    for (final source in [mail, files, attendances, orders, payments]) {
      expect(source, contains('initialOpenRequestId'));
      expect(source, contains('oldWidget.initialOpenRequestId'));
    }

    expect(mail, contains('_quickFilter = _InboxQuickFilter.all'));
    expect(mail, contains('_manager.clearSearch()'));
    expect(files, contains('_currentInitialFileRequestKey()'));
    expect(files, contains("Text('No se pudo abrir ese archivo.')"));
    expect(attendances, contains('_currentInitialAttendanceRequestKey()'));
    expect(orders, contains('_currentInitialOrderRequestKey()'));
  });
}
