import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer collection surfaces use inbound payment methods', () {
    for (final path in <String>[
      'lib/modules/sales/widgets/payment_form.dart',
      'lib/shared/widgets/quick_sale_panel.dart',
      'lib/modules/pos/pages/pos_cart_page.dart',
      'lib/modules/pos/pages/pos_dashboard_page.dart',
      'lib/modules/pos/pages/pos_payment_page.dart',
      'lib/modules/pos/widgets/invoice_payment_layout.dart',
      'lib/modules/sales/pages/payment_edit_page.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('incomingPaymentMethods'),
        reason: '$path must not offer outbound-only methods to customers',
      );
    }
  });

  test('disbursement surfaces use outbound payment methods', () {
    for (final path in <String>[
      'lib/modules/accounting/pages/expense_form_page.dart',
      'lib/shared/widgets/quick_access_expense_rail.dart',
      'lib/modules/purchases/pages/purchase_invoice_list_page.dart',
      'lib/modules/purchases/pages/purchase_payment_edit_page.dart',
      'lib/modules/purchases/pages/purchase_payment_form_page.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('outgoingPaymentMethods'),
        reason: '$path must not offer acquiring-terminal rails for payouts',
      );
    }
  });

  test('POS preserves the exact database method instead of collapsing cards',
      () {
    final dashboard = File('lib/modules/pos/pages/pos_dashboard_page.dart')
        .readAsStringSync();
    final service =
        File('lib/modules/pos/services/pos_service.dart').readAsStringSync();

    expect(dashboard, contains('id: newMethod.id'));
    expect(service, contains('payment.method.id'));
    expect(service, contains('getPaymentMethodById'));
    expect(service, isNot(contains("getPaymentMethodByCode('card')")));
  });

  test('refund and payroll queries keep their economic direction explicit', () {
    expect(
      File('lib/modules/sales/services/sales_credit_note_service.dart')
          .readAsStringSync(),
      contains("const ['outbound', 'both']"),
    );
    expect(
      File('lib/modules/purchases/services/purchase_credit_note_service.dart')
          .readAsStringSync(),
      contains("const ['inbound', 'both']"),
    );
    expect(
      File('lib/modules/hr/services/hr_service.dart').readAsStringSync(),
      contains("const ['outbound', 'both']"),
    );
    expect(
      File('lib/modules/hr/services/payroll_voucher_service.dart')
          .readAsStringSync(),
      contains("scope == 'outbound' || scope == 'both'"),
    );
  });
}
