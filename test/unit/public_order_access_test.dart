import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/public_order_access.dart';
import 'package:vinabike_erp/public_store/services/checkout_session_store.dart';
import 'package:vinabike_erp/public_store/services/public_order_access_token_store.dart';

void main() {
  const orderId = '97000000-0000-4000-8000-000000000010';
  const tenantId = '97000000-0000-4000-8000-000000000001';
  final accessToken = List.filled(43, 'a').join();

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
      'storefront': {
        'schemaVersion': 1,
        'displayName': 'Tienda Norte',
        'legalName': 'Tienda Norte SpA',
        'tagline': 'Ciclismo urbano',
      },
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
    expect(order.storefrontIdentity.displayName, 'Tienda Norte');
    expect(order.storefrontIdentity.legalName, 'Tienda Norte SpA');
    expect(order.storefrontIdentity.tagline, 'Ciclismo urbano');
  });

  test('uses a neutral identity for malformed or legacy token responses', () {
    final order = onlineOrderFromPublicAccessResponse({
      'order': {
        'id': orderId,
        'createdAt': '2026-07-18T12:00:00.000Z',
        'updatedAt': '2026-07-18T12:00:00.000Z',
      },
      'items': const [],
      'storefront': {
        'schemaVersion': 99,
        'displayName': 'Untrusted',
      },
    }, expectedOrderId: orderId);

    expect(order.storefrontIdentity.displayName, 'Tienda');
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

  test('retains the bearer in protected storage across store instances',
      () async {
    final now = DateTime.utc(2026, 7, 18, 12);
    final storage = MemoryCheckoutSessionStorage();
    final first = PublicOrderAccessTokenStore(
      CheckoutSessionStore(storage: storage, now: () => now),
    );
    final access = PublicOrderCheckoutAccess(
      orderId: orderId,
      accessToken: accessToken,
      expiresAt: now.add(const Duration(hours: 2)),
      isReplay: false,
    );
    await first.save(tenantId: tenantId, access: access);

    final remounted = PublicOrderAccessTokenStore(
      CheckoutSessionStore(storage: storage, now: () => now),
    );
    expect(
      (await remounted.read(tenantId: tenantId, orderId: orderId))?.accessToken,
      accessToken,
    );
    await remounted.forget(tenantId: tenantId, orderId: orderId);
    expect(
      await remounted.read(tenantId: tenantId, orderId: orderId),
      isNull,
    );
  });

  test('isolates order access by tenant and removes it after expiry', () async {
    var now = DateTime.utc(2026, 7, 18, 12);
    final storage = MemoryCheckoutSessionStorage();
    final sessions = CheckoutSessionStore(storage: storage, now: () => now);
    await sessions.saveOrderAccess(
      tenantId: tenantId,
      access: PublicOrderCheckoutAccess(
        orderId: orderId,
        accessToken: accessToken,
        expiresAt: now.add(const Duration(minutes: 5)),
        isReplay: false,
      ),
    );

    expect(
      await sessions.readOrderAccess(
        tenantId: 'another-tenant',
        orderId: orderId,
      ),
      isNull,
    );
    expect(
      await sessions.readOrderAccess(
        tenantId: tenantId,
        orderId: 'another-order',
      ),
      isNull,
    );

    now = now.add(const Duration(minutes: 6));
    expect(
      await sessions.readOrderAccess(
        tenantId: tenantId,
        orderId: orderId,
      ),
      isNull,
    );
  });

  test('rejects an already expired access before writing it', () async {
    final now = DateTime.utc(2026, 7, 18, 12);
    final storage = MemoryCheckoutSessionStorage();
    final sessions = CheckoutSessionStore(storage: storage, now: () => now);

    await expectLater(
      sessions.saveOrderAccess(
        tenantId: tenantId,
        access: PublicOrderCheckoutAccess(
          orderId: orderId,
          accessToken: accessToken,
          expiresAt: now,
          isReplay: false,
        ),
      ),
      throwsFormatException,
    );
    expect(
      await sessions.readOrderAccess(
        tenantId: tenantId,
        orderId: orderId,
      ),
      isNull,
    );
  });

  test('migrates a legacy raw bearer once before deleting its source',
      () async {
    final now = DateTime.utc(2026, 7, 18, 12);
    final storage = MemoryCheckoutSessionStorage();
    final sessions = CheckoutSessionStore(storage: storage, now: () => now);
    const legacyPrefix = 'vinabike.public-order-access.v1.';
    const legacyKey = '$legacyPrefix$orderId';
    await storage.write(legacyKey, accessToken);

    final migrated = await sessions.readOrderAccess(
      tenantId: tenantId,
      orderId: orderId,
    );

    expect(migrated?.accessToken, accessToken);
    expect(migrated?.expiresAt, now.add(const Duration(days: 30)));
    expect(migrated?.isReplay, isFalse);
    expect(await storage.read(legacyKey), isNull);

    final remounted = CheckoutSessionStore(storage: storage, now: () => now);
    expect(
      (await remounted.readOrderAccess(
        tenantId: tenantId,
        orderId: orderId,
      ))
          ?.accessToken,
      accessToken,
    );
  });

  test('keeps the legacy bearer when the verified migration write fails',
      () async {
    final now = DateTime.utc(2026, 7, 18, 12);
    const legacyKey = 'vinabike.public-order-access.v1.$orderId';
    final storage = _FailMigratedAccessStorage(legacyKey);
    final sessions = CheckoutSessionStore(storage: storage, now: () => now);
    await storage.write(legacyKey, accessToken);
    storage.failMigratedWrite = true;

    await expectLater(
      sessions.readOrderAccess(
        tenantId: tenantId,
        orderId: orderId,
      ),
      throwsStateError,
    );
    expect(await storage.read(legacyKey), accessToken);
  });
}

class _FailMigratedAccessStorage implements CheckoutSessionStorage {
  _FailMigratedAccessStorage(this.legacyKey);

  final String legacyKey;
  final Map<String, String> _values = <String, String>{};
  bool failMigratedWrite = false;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failMigratedWrite && key != legacyKey && value.isNotEmpty) {
      throw StateError('simulated migration write failure');
    }
    if (value.isEmpty) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}
