import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/public_order_access.dart';
import 'package:vinabike_erp/public_store/services/public_order_access_token_store.dart';

void main() {
  const orderId = '97000000-0000-4000-8000-000000000010';
  final accessToken = List.filled(43, 'a').join();

  tearDown(PublicOrderAccessTokenStore.clearMemoryForTesting);

  test('parses the one-time checkout access result', () {
    final result = PublicOrderCheckoutAccess.fromRpc({
      'order_id': orderId,
      'access_token': accessToken,
      'expires_at': '2026-08-17T12:00:00.000Z',
      'replay': false,
    });

    expect(result.orderId, orderId);
    expect(result.accessToken, accessToken);
    expect(result.isReplay, isFalse);
    expect(result.expiresAt.isUtc, isTrue);
  });

  test('refuses incomplete checkout credentials', () {
    expect(
      () => PublicOrderCheckoutAccess.fromRpc({
        'order_id': orderId,
        'access_token': 'short',
        'expires_at': '2026-08-17T12:00:00.000Z',
      }),
      throwsFormatException,
    );
  });

  test('maps only the redacted public projection', () {
    final order = onlineOrderFromPublicAccessResponse({
      'order': {
        'id': orderId,
        'number': 'WEB-26-00001',
        'status': 'pending',
        'paymentStatus': 'pending',
        'paymentMethod': 'mercadopago',
        'deliveryType': 'pickup',
        'createdAt': '2026-07-18T12:00:00.000Z',
        'updatedAt': '2026-07-18T12:01:00.000Z',
        'subtotal': 832,
        'taxAmount': 158,
        'shippingCost': 0,
        'discountAmount': 0,
        'total': 990,
      },
      'items': [
        {
          'name': 'Producto seguro',
          'sku': 'SAFE-001',
          'quantity': 1,
          'unitPrice': 990,
          'subtotal': 990,
          'taxRate': 19,
        },
      ],
      'access': {
        'scopes': ['view_order'],
        'expiresAt': '2026-08-17T12:00:00.000Z',
      },
    }, expectedOrderId: orderId);

    expect(order.id, orderId);
    expect(order.orderNumber, 'WEB-26-00001');
    expect(order.paymentMethod, 'mercadopago');
    expect(order.customerEmail, isEmpty);
    expect(order.customerName, isEmpty);
    expect(order.customerAddress, isNull);
    expect(order.internalNotes, isNull);
    expect(order.taxAmount, 158);
    expect(order.items.single.productName, 'Producto seguro');
    expect(order.items.single.productId, isNull);
    expect(order.items.single.taxRate, 19);
  });

  test('rejects a token projection for another order', () {
    expect(
      () => onlineOrderFromPublicAccessResponse({
        'order': {
          'id': '97000000-0000-4000-8000-000000000011',
          'createdAt': '2026-07-18T12:00:00.000Z',
          'updatedAt': '2026-07-18T12:00:00.000Z',
        },
        'items': const [],
      }, expectedOrderId: orderId),
      throwsFormatException,
    );
  });

  test('retains the bearer token in session memory without using a URL', () {
    PublicOrderAccessTokenStore.save(
      orderId: orderId,
      accessToken: accessToken,
    );

    expect(PublicOrderAccessTokenStore.read(orderId), accessToken);
    PublicOrderAccessTokenStore.forget(orderId);
    expect(PublicOrderAccessTokenStore.read(orderId), isNull);
  });
}
