import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/public_order_access.dart';
import 'package:vinabike_erp/public_store/models/checkout_submission_session.dart';

void main() {
  final receipt = PublicOrderCheckoutAccess(
    orderId: 'order-123',
    accessToken:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    expiresAt: _expiresAt,
    isReplay: false,
  );

  test('post-receipt handoff retry never creates a second order', () async {
    var createCalls = 0;
    var handoffCalls = 0;
    final seenKeys = <String>[];
    final session = CheckoutSubmissionSession(idempotencyKey: 'checkout-key');

    Future<PublicOrderCheckoutAccess> create(String key) async {
      createCalls++;
      seenKeys.add(key);
      return receipt;
    }

    final created = await session.ensureOrderCreated(create);
    expect(created.orderId, 'order-123');

    await expectLater(
      session.handOff((_) async {
        handoffCalls++;
        throw StateError('navigation failed');
      }),
      throwsStateError,
    );
    expect(session.phase, CheckoutSubmissionPhase.handoffFailed);

    final recovered = await session.ensureOrderCreated(create);
    await session.handOff((value) async {
      handoffCalls++;
      expect(value.orderId, created.orderId);
    });

    expect(recovered, same(created));
    expect(createCalls, 1);
    expect(handoffCalls, 2);
    expect(seenKeys, ['checkout-key']);
    expect(session.phase, CheckoutSubmissionPhase.handedOff);
  });

  test('outcome-unknown retry reuses the same idempotency key', () async {
    var originalCreatorCalls = 0;
    var replacementCreatorCalls = 0;
    final seenKeys = <String>[];
    final session = CheckoutSubmissionSession(idempotencyKey: 'stable-key');

    Future<PublicOrderCheckoutAccess> originalCreator(String key) async {
      originalCreatorCalls++;
      seenKeys.add(key);
      if (originalCreatorCalls == 1) throw Exception('response lost');
      return PublicOrderCheckoutAccess(
        orderId: 'order-replayed',
        accessToken:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        expiresAt: _expiresAt,
        isReplay: true,
      );
    }

    Future<PublicOrderCheckoutAccess> replacementCreator(String _) async {
      replacementCreatorCalls++;
      throw StateError('A changed payload must never run.');
    }

    await expectLater(
      session.ensureOrderCreated(originalCreator),
      throwsException,
    );
    expect(session.phase, CheckoutSubmissionPhase.outcomeUnknown);
    expect(session.receipt, isNull);

    final replay = await session.ensureOrderCreated(replacementCreator);

    expect(replay.orderId, 'order-replayed');
    expect(replay.isReplay, isTrue);
    expect(originalCreatorCalls, 2);
    expect(replacementCreatorCalls, 0);
    expect(seenKeys, ['stable-key', 'stable-key']);
  });

  test('concurrent submit attempts share one creation in flight', () async {
    var createCalls = 0;
    final session = CheckoutSubmissionSession(idempotencyKey: 'stable-key');

    Future<PublicOrderCheckoutAccess> create(String _) async {
      createCalls++;
      await Future<void>.delayed(Duration.zero);
      return receipt;
    }

    final first = session.ensureOrderCreated(create);
    final second = session.ensureOrderCreated(create);
    final results = await Future.wait([first, second]);

    expect(createCalls, 1);
    expect(results[0], same(results[1]));
  });

  test('restored pending session replays the exact persisted payload',
      () async {
    const persistedKey = '33333333-3333-4333-8333-333333333333';
    const persistedOrderData = <String, dynamic>{
      'tenant_id': 'tenant-a',
      'checkout_idempotency_key': persistedKey,
      'customer_email': 'original@example.com',
      'delivery_type': 'shipping',
      'payment_method': 'transfer',
      'total': 124000,
    };
    const persistedOrderItems = <Map<String, dynamic>>[
      {
        'tenant_id': 'tenant-a',
        'product_id': 'product-1',
        'quantity': 2,
        'unit_price': 50000,
      },
    ];
    const changedOrderData = <String, dynamic>{
      'customer_email': 'changed@example.com',
      'total': 1,
    };
    var restoredCreatorCalls = 0;
    var replacementCreatorCalls = 0;
    String? seenKey;
    Map<String, dynamic>? seenOrderData;
    List<Map<String, dynamic>>? seenOrderItems;

    Future<PublicOrderCheckoutAccess> restoredCreator(String key) async {
      restoredCreatorCalls++;
      seenKey = key;
      seenOrderData = persistedOrderData;
      seenOrderItems = persistedOrderItems;
      return receipt;
    }

    final restored = CheckoutSubmissionSession.restorePending(
      idempotencyKey: persistedKey,
      creator: restoredCreator,
    );

    expect(restored.phase, CheckoutSubmissionPhase.outcomeUnknown);
    expect(restored.hasCreationAttempt, isTrue);
    expect(restored.hasReceipt, isFalse);

    final recovered = await restored.ensureOrderCreated((_) async {
      replacementCreatorCalls++;
      seenOrderData = changedOrderData;
      throw StateError('A changed form payload must never replace the lease.');
    });

    expect(recovered, same(receipt));
    expect(restoredCreatorCalls, 1);
    expect(replacementCreatorCalls, 0);
    expect(seenKey, persistedKey);
    expect(seenOrderData, equals(persistedOrderData));
    expect(seenOrderItems, equals(persistedOrderItems));
    expect(restored.phase, CheckoutSubmissionPhase.orderCreated);
  });

  test('restored receipt never invokes another order creator', () async {
    var creatorCalls = 0;
    final restored = CheckoutSubmissionSession.restoreReceipt(
      idempotencyKey: '44444444-4444-4444-8444-444444444444',
      receipt: receipt,
    );

    Future<PublicOrderCheckoutAccess> unexpectedCreator(String _) async {
      creatorCalls++;
      throw StateError('A restored receipt must not create another order.');
    }

    final ensured = await restored.ensureOrderCreated(unexpectedCreator);
    final retried = await restored.retryOriginalOrder();

    expect(ensured, same(receipt));
    expect(retried, same(receipt));
    expect(creatorCalls, 0);
    expect(restored.hasReceipt, isTrue);
    expect(restored.hasCreationAttempt, isFalse);
    expect(restored.phase, CheckoutSubmissionPhase.orderCreated);
  });
}

final _expiresAt = DateTime.utc(2026, 7, 29);
