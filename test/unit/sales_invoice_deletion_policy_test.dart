import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';

void main() {
  test('only draft sales invoices may be physically deleted', () {
    expect(InvoiceStatus.draft.canBeDeleted, isTrue);

    for (final status in <InvoiceStatus>[
      InvoiceStatus.sent,
      InvoiceStatus.confirmed,
      InvoiceStatus.paid,
      InvoiceStatus.overdue,
      InvoiceStatus.cancelled,
    ]) {
      expect(status.canBeDeleted, isFalse, reason: status.name);
      expect(
        status.deletionBlockedMessage('FV-TEST'),
        contains('FV-TEST'),
        reason: status.name,
      );
    }
  });

  test('blocked messages direct staff to the appropriate workflow', () {
    expect(
      InvoiceStatus.sent.deletionBlockedMessage('FV-1'),
      contains('Descartar factura'),
    );
    expect(
      InvoiceStatus.confirmed.deletionBlockedMessage('FV-2'),
      contains('stock y la contabilidad'),
    );
    expect(
      InvoiceStatus.paid.deletionBlockedMessage('FV-3'),
      contains('devolución'),
    );
    expect(
      InvoiceStatus.cancelled.deletionBlockedMessage('FV-4'),
      contains('respaldo auditable'),
    );
  });
}
