// The order summary PDF has one drawing (`buildOrderSummaryPdf` in the
// shared core): the app reads the order into an `OnlineOrder` and the HTML
// store's server reads the same public answer directly. Both readings must
// state the same thing, or the two stores would hand out different PDFs.
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/public_order_access.dart';
import 'package:vinabike_erp/public_store/pages/order_confirmation_pdf.dart';
import 'package:vinabike_public_core/public_store/documents/order_summary_pdf.dart';

const _order = '0d000000-0000-4000-8000-000000000021';

Map<String, Object?> _envelope({
  String status = 'confirmed',
  String paymentStatus = 'pending',
  String deliveryType = 'shipping',
  Object? storefront = const {
    'schemaVersion': 1,
    'displayName': 'Viñabike',
    'tagline': 'Repuestos, accesorios y taller de bicicletas en Viña del Mar.',
  },
}) =>
    {
      'order': {
        'id': _order,
        'number': 'WEB-26-00021',
        'status': status,
        'paymentStatus': paymentStatus,
        'paymentMethod': 'mercadopago',
        'deliveryType': deliveryType,
        'createdAt': '2026-10-06T08:30:00.123456+00:00',
        'updatedAt': '2026-10-06T08:31:00+00:00',
        'subtotal': 74790,
        'taxAmount': 14210,
        'shippingCost': 8990,
        'discountAmount': 1000,
        'total': 96990,
      },
      'items': [
        {
          'name': 'CASSETTE ECLIPSE 8 VELOCIDADES 11-42T',
          'sku': '7274',
          'quantity': 1,
          'unitPrice': 35000,
          'subtotal': 35000,
          'taxRate': 19,
        },
        {
          'name': 'Candado sin IVA',
          'sku': null,
          'quantity': 2,
          'unitPrice': 27000.0,
          'subtotal': 54000.0,
          'taxRate': 0,
        },
      ],
      'storefront': storefront,
    };

Map<String, Object?> _stated(OrderSummaryPdfInput input) => {
      'storeName': input.storeName,
      'tagline': input.tagline,
      'orderNumber': input.orderNumber,
      'createdAt': input.createdAt.toUtc(),
      'statusLabel': input.statusLabel,
      'paymentStatusLabel': input.paymentStatusLabel,
      'deliveryLabel': input.deliveryLabel,
      'customerRows': [
        for (final row in input.customerRows) [row.key, row.value]
      ],
      'lines': [
        for (final line in input.lines)
          [
            line.name,
            line.quantity,
            line.unitPrice,
            line.subtotal,
            line.taxRate
          ],
      ],
      'amounts': [
        input.subtotal,
        input.taxAmount,
        input.shippingCost,
        input.discountAmount,
        input.total,
      ],
      'fileName': input.fileName,
    };

void main() {
  for (final (name, envelope) in [
    ('a paid shipment', _envelope(paymentStatus: 'paid')),
    (
      'a cancelled pickup',
      _envelope(status: 'cancelled', deliveryType: 'pickup')
    ),
    (
      'an unknown state',
      _envelope(status: 'on_hold', paymentStatus: 'refunded')
    ),
    ('an order without its identity', _envelope(storefront: null)),
  ]) {
    test('$name reads the same in the app and on the HTML store', () {
      final app = orderSummaryInputOf(
        onlineOrderFromPublicAccessResponse(envelope, expectedOrderId: _order),
      );
      final html = OrderSummaryPdfInput.fromPublicAccess(
        envelope,
        expectedOrderId: _order,
      );
      expect(html, isNotNull);
      expect(_stated(html!), _stated(app));
    });
  }

  test('another order\'s answer is no summary', () {
    expect(
      OrderSummaryPdfInput.fromPublicAccess(
        _envelope(),
        expectedOrderId: 'another-order',
      ),
      isNull,
    );
    expect(
      OrderSummaryPdfInput.fromPublicAccess(null, expectedOrderId: _order),
      isNull,
    );
  });
}
