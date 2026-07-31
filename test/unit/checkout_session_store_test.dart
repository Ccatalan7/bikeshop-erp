import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/public_order_access.dart';
import 'package:vinabike_erp/public_store/services/checkout_session_store.dart';

void main() {
  group('CheckoutSessionStore', () {
    test('round-trips the exact pending payload and receipt', () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(
        storage: storage,
        now: () => now,
      );
      final pending = _snapshot(savedAt: now);

      await store.save(pending);
      final restoredPending = await store.read(_tenantA);

      expect(restoredPending, isNotNull);
      expect(restoredPending!.tenantId, _tenantA);
      expect(restoredPending.savedAt, now);
      expect(restoredPending.idempotencyKey, _idempotencyKey);
      expect(restoredPending.orderData, equals(_orderData(_tenantA)));
      expect(restoredPending.orderItems, equals(_orderItems(_tenantA)));
      expect(restoredPending.handoff.paymentMethod, 'transfer');
      expect(restoredPending.handoff.deliveryType, 'shipping');
      expect(restoredPending.receipt, isNull);

      final receipt = _receipt(
        orderId: 'order-123',
        expiresAt: now.add(const Duration(hours: 1)),
        replay: true,
      );
      await store.save(pending.withReceipt(receipt));
      final restoredReceipt = await store.read(_tenantA);

      expect(restoredReceipt, isNotNull);
      expect(restoredReceipt!.orderData, equals(_orderData(_tenantA)));
      expect(restoredReceipt.orderItems, equals(_orderItems(_tenantA)));
      expect(restoredReceipt.receipt?.orderId, receipt.orderId);
      expect(restoredReceipt.receipt?.accessToken, receipt.accessToken);
      expect(restoredReceipt.receipt?.expiresAt, receipt.expiresAt);
      expect(restoredReceipt.receipt?.isReplay, isTrue);
      expect(restoredReceipt.cartConsumptionClosedAt, isNull);
      expect(restoredReceipt.cartConsumptionStatus, isNull);

      expect(
        await store.clearReceiptIfMatches(
          tenantId: _tenantA,
          orderId: 'another-order',
        ),
        isFalse,
      );
      expect((await store.read(_tenantA))?.receipt?.orderId, 'order-123');
      expect(
        await store.clearReceiptIfMatches(
          tenantId: _tenantA,
          orderId: 'order-123',
        ),
        isTrue,
      );
      expect(await store.read(_tenantA), isNull);
    });

    test(
        'production transitions cannot overwrite an active attempt or attach a stale receipt',
        () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(storage: storage, now: () => now);
      final competingStore =
          CheckoutSessionStore(storage: storage, now: () => now);
      final first = _snapshot(savedAt: now);
      final newer = _snapshot(
        savedAt: now,
        idempotencyKey: _tenantBIdempotencyKey,
      );

      final firstCreation = store.createPendingIfAbsent(first);
      final conflictingCreation = competingStore.createPendingIfAbsent(newer);
      final conflictExpectation = expectLater(
        conflictingCreation,
        throwsStateError,
      );
      final created = await firstCreation;
      expect(created.idempotencyKey, _idempotencyKey);
      await conflictExpectation;
      expect((await store.read(_tenantA))?.idempotencyKey, _idempotencyKey);

      final receipt = _receipt(
        orderId: 'order-atomic-receipt',
        expiresAt: now.add(const Duration(hours: 1)),
      );
      await expectLater(
        store.attachReceiptIfMatches(
          tenantId: _tenantA,
          idempotencyKey: _tenantBIdempotencyKey,
          receipt: receipt,
        ),
        throwsStateError,
      );
      expect((await store.read(_tenantA))?.receipt, isNull);

      final attached = await store.attachReceiptIfMatches(
        tenantId: _tenantA,
        idempotencyKey: _idempotencyKey,
        receipt: receipt,
      );
      expect(attached.receipt?.orderId, receipt.orderId);
      expect(
        (await store.read(_tenantA))?.receipt?.accessToken,
        receipt.accessToken,
      );
    });

    test('idempotent receipt attachment preserves terminal cart fields',
        () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(storage: storage, now: () => now);
      final receipt = _receipt(
        orderId: 'order-terminal-attachment',
        expiresAt: now.add(const Duration(hours: 1)),
      );
      final terminal = _snapshot(savedAt: now)
          .withReceipt(receipt)
          .closeCartConsumption(now)
          .markCartConsumptionApplied();
      await store.save(terminal);

      final attached = await store.attachReceiptIfMatches(
        tenantId: _tenantA,
        idempotencyKey: _idempotencyKey,
        receipt: receipt,
      );

      expect(
        attached.cartConsumptionStatus,
        CheckoutCartConsumptionStatus.applied,
      );
      expect(attached.cartConsumptionClosedAt, now);
    });

    test('persists the one-shot cart outcome as preserved before applied',
        () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(
        storage: storage,
        now: () => now,
      );
      final withReceipt = _snapshot(savedAt: now).withReceipt(
        _receipt(
          orderId: 'order-cart-outcome',
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );

      final preserved = withReceipt.closeCartConsumption(
        now.add(const Duration(minutes: 1)),
      );
      await store.save(preserved);
      final restoredPreserved = await store.read(_tenantA);

      expect(
        restoredPreserved?.cartConsumptionStatus,
        CheckoutCartConsumptionStatus.preserved,
      );
      expect(
        restoredPreserved?.cartConsumptionClosedAt,
        now.add(const Duration(minutes: 1)),
      );

      await store.save(preserved.markCartConsumptionApplied());
      expect(
        (await store.read(_tenantA))?.cartConsumptionStatus,
        CheckoutCartConsumptionStatus.applied,
      );
    });

    test(
        'keeps the preserved-cart warning across remounts until exact acknowledgement',
        () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final firstStore = CheckoutSessionStore(
        storage: storage,
        now: () => now,
      );

      await firstStore.markCartPreservationWarning(
        tenantId: _tenantA,
        orderId: 'order-preserved',
      );

      final remountedStore = CheckoutSessionStore(
        storage: storage,
        now: () => now.add(const Duration(days: 1)),
      );
      expect(
        await remountedStore.hasCartPreservationWarning(
          tenantId: _tenantA,
          orderId: 'order-preserved',
        ),
        isTrue,
      );
      expect(
        await remountedStore.hasCartPreservationWarning(
          tenantId: _tenantA,
          orderId: 'another-order',
        ),
        isFalse,
      );
      expect(
        await remountedStore.hasCartPreservationWarning(
          tenantId: _tenantB,
          orderId: 'order-preserved',
        ),
        isFalse,
      );
      expect(
        await remountedStore.acknowledgeCartPreservationWarning(
          tenantId: _tenantA,
          orderId: 'another-order',
        ),
        isFalse,
      );
      expect(
        await remountedStore.hasCartPreservationWarning(
          tenantId: _tenantA,
          orderId: 'order-preserved',
        ),
        isTrue,
      );

      expect(
        await remountedStore.acknowledgeCartPreservationWarning(
          tenantId: _tenantA,
          orderId: 'order-preserved',
        ),
        isTrue,
      );
      expect(
        await remountedStore.hasCartPreservationWarning(
          tenantId: _tenantA,
          orderId: 'order-preserved',
        ),
        isFalse,
      );

      var consumeCalls = 0;
      final settled = await remountedStore.consumeCartOnce(
        tenantId: _tenantA,
        orderId: 'order-preserved',
        consume: (_) async {
          consumeCalls++;
          return true;
        },
      );
      expect(settled.showsWarning, isFalse);
      expect(consumeCalls, 0);
    });

    test('preserved-cart warning survives retirement of its checkout receipt',
        () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(
        storage: storage,
        now: () => now,
      );
      const orderId = 'order-warning-after-receipt';
      await store.save(
        _snapshot(savedAt: now)
            .withReceipt(
              _receipt(
                orderId: orderId,
                expiresAt: now.add(const Duration(hours: 1)),
              ),
            )
            .closeCartConsumption(now.add(const Duration(minutes: 1))),
      );
      await store.markCartPreservationWarning(
        tenantId: _tenantA,
        orderId: orderId,
      );

      expect(
        await store.clearReceiptIfMatches(
          tenantId: _tenantA,
          orderId: orderId,
        ),
        isTrue,
      );
      expect(await store.read(_tenantA), isNull);
      expect(
        await store.hasCartPreservationWarning(
          tenantId: _tenantA,
          orderId: orderId,
        ),
        isTrue,
      );
    });

    test('accepts the maximum age boundary and clears an older snapshot',
        () async {
      final storage = _InspectableCheckoutStorage();
      final savedAt = DateTime.utc(2026, 7, 28, 8);
      var now = savedAt.add(CheckoutSessionStore.maxAge);
      final store = CheckoutSessionStore(
        storage: storage,
        now: () => now,
      );

      await store.save(_snapshot(savedAt: savedAt));
      expect(await store.read(_tenantA), isNotNull);

      now = now.add(const Duration(microseconds: 1));
      expect(await store.read(_tenantA), isNull);
      expect(storage.values, isEmpty);
    });

    test('rejects excessive future skew and an expired receipt', () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(
        storage: storage,
        now: () => now,
      );

      await store.save(
        _snapshot(
          savedAt: now.add(
            const Duration(minutes: 5, microseconds: 1),
          ),
        ),
      );
      expect(await store.read(_tenantA), isNull);
      expect(storage.values, isEmpty);

      await store.save(
        _snapshot(savedAt: now).withReceipt(
          _receipt(orderId: 'expired-order', expiresAt: now),
        ),
      );
      expect(await store.read(_tenantA), isNull);
      expect(storage.values, isEmpty);
    });

    test('clears corrupt or structurally inconsistent stored data', () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(
        storage: storage,
        now: () => now,
      );
      final valid = _snapshot(savedAt: now);
      await store.save(valid);
      final storageKey = storage.lastWrittenKey!;

      final invalidVersion = _jsonCopy(valid.toJson())..['v'] = 999;
      final invalidQuantity = _jsonCopy(valid.toJson());
      (invalidQuantity['order_items'] as List<dynamic>).first['quantity'] = '1';
      final inconsistentHandoff = _jsonCopy(valid.toJson());
      (inconsistentHandoff['handoff']
          as Map<String, dynamic>)['payment_method'] = 'mercadopago';
      final invalidTotal = _jsonCopy(valid.toJson());
      (invalidTotal['order_data'] as Map<String, dynamic>)['total'] = '124000';
      final invalidReceipt = _jsonCopy(valid.toJson())
        ..['receipt'] = {
          'order_id': 'order-123',
          'access_token': 'short',
          'expires_at': now.add(const Duration(hours: 1)).toIso8601String(),
          'replay': false,
        };
      final receipt = _receipt(
        orderId: 'order-cart-corrupt',
        expiresAt: now.add(const Duration(hours: 1)),
      );
      final closed = valid
          .withReceipt(receipt)
          .closeCartConsumption(now.add(const Duration(minutes: 1)));
      final missingConsumptionStatus = _jsonCopy(closed.toJson())
        ..remove('cart_consumption_status');
      final invalidConsumptionStatus = _jsonCopy(closed.toJson())
        ..['cart_consumption_status'] = 'retry';

      for (final corruptValue in <String>[
        'not-json',
        jsonEncode(invalidVersion),
        jsonEncode(invalidQuantity),
        jsonEncode(inconsistentHandoff),
        jsonEncode(invalidTotal),
        jsonEncode(invalidReceipt),
        jsonEncode(missingConsumptionStatus),
        jsonEncode(invalidConsumptionStatus),
      ]) {
        storage.seed(storageKey, corruptValue);

        expect(await store.read(_tenantA), isNull, reason: corruptValue);
        expect(storage.values.containsKey(storageKey), isFalse);
      }
    });

    test('isolates tenants and rejects a snapshot stored under another tenant',
        () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(
        storage: storage,
        now: () => now,
      );
      final tenantASnapshot = _snapshot(savedAt: now);
      final tenantBSnapshot = _snapshot(
        tenantId: _tenantB,
        idempotencyKey: _tenantBIdempotencyKey,
        savedAt: now,
      );

      await store.save(tenantASnapshot);
      final tenantAKey = storage.lastWrittenKey!;
      await store.save(tenantBSnapshot);
      final tenantBKey = storage.lastWrittenKey!;

      expect(tenantAKey, isNot(tenantBKey));
      expect((await store.read(_tenantA))?.idempotencyKey, _idempotencyKey);
      expect(
        (await store.read(_tenantB))?.idempotencyKey,
        _tenantBIdempotencyKey,
      );

      storage.seed(tenantBKey, jsonEncode(tenantASnapshot.toJson()));

      expect(await store.read(_tenantB), isNull);
      expect(storage.values.containsKey(tenantBKey), isFalse);
      expect((await store.read(_tenantA))?.tenantId, _tenantA);
    });

    test('requires a UUID v4 idempotency key before any snapshot can save', () {
      final now = DateTime.utc(2026, 7, 28, 12);

      expect(
        () => _snapshot(
          idempotencyKey: 'not-a-v4-checkout-key',
          savedAt: now,
        ),
        throwsFormatException,
      );
      expect(
        () => _snapshot(
          idempotencyKey: '11111111-1111-5111-8111-111111111111',
          savedAt: now,
        ),
        throwsFormatException,
      );
    });

    test(
        'new snapshots require a cart revision, reject duplicate products, and decode legacy revisions',
        () {
      final now = DateTime.utc(2026, 7, 28, 12);
      final valid = _snapshot(savedAt: now);

      expect(
        () => CheckoutSessionSnapshot.create(
          tenantId: valid.tenantId,
          savedAt: valid.savedAt,
          idempotencyKey: valid.idempotencyKey,
          orderData: valid.orderData,
          orderItems: valid.orderItems,
          handoff: valid.handoff,
          cartRevision: '   ',
        ),
        throwsFormatException,
      );

      final duplicateItems = valid.orderItems
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      duplicateItems[1]['product_id'] = ' product-1 ';
      expect(
        () => CheckoutSessionSnapshot.create(
          tenantId: valid.tenantId,
          savedAt: valid.savedAt,
          idempotencyKey: valid.idempotencyKey,
          orderData: valid.orderData,
          orderItems: duplicateItems,
          handoff: valid.handoff,
          cartRevision: valid.cartRevision!,
        ),
        throwsFormatException,
      );

      final legacy = _jsonCopy(valid.toJson())..remove('cart_revision');
      expect(
        CheckoutSessionSnapshot.decode(
          jsonEncode(legacy),
          expectedTenantId: _tenantA,
        )?.cartRevision,
        isNull,
      );
    });

    test(
        'transfer confirmation takes only the same order and preserves its outcome across remount',
        () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final firstStore = CheckoutSessionStore(
        storage: storage,
        now: () => now,
      );
      final receipt = _receipt(
        orderId: 'transfer-order',
        expiresAt: now.add(const Duration(hours: 1)),
      );
      await firstStore.save(
        _snapshot(savedAt: now)
            .withReceipt(receipt)
            .closeCartConsumption(now.add(const Duration(minutes: 1))),
      );

      final remountedStore = CheckoutSessionStore(
        storage: storage,
        now: () => now.add(const Duration(minutes: 2)),
      );
      expect(
        await remountedStore.takeTransferReceiptIfMatches(
          tenantId: _tenantA,
          orderId: 'another-order',
        ),
        isNull,
      );
      expect(
        (await remountedStore.read(_tenantA))?.receipt?.orderId,
        'transfer-order',
      );

      final retired = await remountedStore.takeTransferReceiptIfMatches(
        tenantId: _tenantA,
        orderId: 'transfer-order',
      );
      expect(
        retired?.cartConsumptionStatus,
        CheckoutCartConsumptionStatus.preserved,
      );
      expect(await remountedStore.read(_tenantA), isNull);
    });

    test(
        'Mercado Pago stays durable until approved and only the exact order clears',
        () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(
        storage: storage,
        now: () => now,
      );
      await store.save(
        _snapshot(
          savedAt: now,
          paymentMethod: 'mercadopago',
        ).withReceipt(
          _receipt(
            orderId: 'mp-order',
            expiresAt: now.add(const Duration(hours: 1)),
          ),
        ),
      );

      // An unverified confirmation route is not a transfer completion and
      // cannot retire the Mercado Pago recovery receipt.
      expect(
        await store.takeTransferReceiptIfMatches(
          tenantId: _tenantA,
          orderId: 'mp-order',
        ),
        isNull,
      );
      expect((await store.read(_tenantA))?.receipt?.orderId, 'mp-order');

      // Even the verified-callback owner remains exact-order bound.
      expect(
        await store.clearReceiptIfMatches(
          tenantId: _tenantA,
          orderId: 'another-order',
        ),
        isFalse,
      );
      expect((await store.read(_tenantA))?.receipt?.orderId, 'mp-order');
      expect(
        await store.clearReceiptIfMatches(
          tenantId: _tenantA,
          orderId: 'mp-order',
        ),
        isTrue,
      );
      expect(await store.read(_tenantA), isNull);
    });

    test('shares one cart claim across checkout and confirmation stores',
        () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final checkoutStore = CheckoutSessionStore(
        storage: storage,
        now: () => now,
      );
      final confirmationStore = CheckoutSessionStore(
        storage: storage,
        now: () => now,
      );
      const orderId = 'order-single-flight';
      await checkoutStore.save(
        _snapshot(savedAt: now).withReceipt(
          _receipt(
            orderId: orderId,
            expiresAt: now.add(const Duration(hours: 1)),
          ),
        ),
      );

      final started = Completer<void>();
      final release = Completer<void>();
      var consumeCalls = 0;
      Future<bool> consume(CheckoutSessionSnapshot _) async {
        consumeCalls++;
        if (!started.isCompleted) started.complete();
        await release.future;
        return true;
      }

      final first = checkoutStore.consumeCartOnce(
        tenantId: _tenantA,
        orderId: orderId,
        consume: consume,
      );
      await started.future;
      final second = confirmationStore.consumeCartOnce(
        tenantId: _tenantA,
        orderId: orderId,
        consume: consume,
      );
      final presented = confirmationStore.settleCartOutcomeForPresentation(
        tenantId: _tenantA,
        orderId: orderId,
      );

      expect(consumeCalls, 1);
      expect(
        (await checkoutStore.read(_tenantA))?.cartConsumptionStatus,
        CheckoutCartConsumptionStatus.consuming,
      );

      release.complete();
      final outcomes = await Future.wait<CheckoutCartOutcome?>(
        [first, second, presented],
      );
      expect(
        outcomes.map((outcome) => outcome?.state),
        everyElement(CheckoutCartOutcomeState.applied),
      );
      expect(consumeCalls, 1);
      expect(
        (await checkoutStore.readCartOutcome(
          tenantId: _tenantA,
          orderId: orderId,
        ))
            ?.state,
        CheckoutCartOutcomeState.applied,
      );

      expect(
        await confirmationStore.clearReceiptIfMatches(
          tenantId: _tenantA,
          orderId: orderId,
          requireTerminalCartOutcome: true,
        ),
        isTrue,
      );
      expect(await confirmationStore.read(_tenantA), isNull);

      final remounted = CheckoutSessionStore(
        storage: storage,
        now: () => now.add(const Duration(minutes: 1)),
      );
      expect(
        (await remounted.readOrderAccess(
          tenantId: _tenantA,
          orderId: orderId,
        ))
            ?.accessToken,
        isNotEmpty,
      );
      final repeated = await remounted.consumeCartOnce(
        tenantId: _tenantA,
        orderId: orderId,
        consume: (_) async {
          consumeCalls++;
          return true;
        },
      );
      expect(repeated.state, CheckoutCartOutcomeState.applied);
      expect(consumeCalls, 1);
    });

    test('presentation settles an orphan consuming claim without retrying',
        () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final first = CheckoutSessionStore(storage: storage, now: () => now);
      const orderId = 'order-interrupted-consume';
      final claimed = _snapshot(savedAt: now)
          .withReceipt(
            _receipt(
              orderId: orderId,
              expiresAt: now.add(const Duration(hours: 1)),
            ),
          )
          .claimCartConsumption(
            claimId: 'lost-process-claim',
            startedAt: now,
          );
      await first.save(claimed);

      final remounted = CheckoutSessionStore(
        storage: storage,
        now: () => now.add(const Duration(minutes: 1)),
      );
      final outcome = await remounted.settleCartOutcomeForPresentation(
        tenantId: _tenantA,
        orderId: orderId,
      );

      expect(outcome?.state, CheckoutCartOutcomeState.preserved);
      expect(outcome?.reason, 'interrupted');
      expect(
        (await remounted.read(_tenantA))?.cartConsumptionStatus,
        CheckoutCartConsumptionStatus.preserved,
      );
      expect(
        await remounted.hasCartPreservationWarning(
          tenantId: _tenantA,
          orderId: orderId,
        ),
        isTrue,
      );
    });

    test('missing approved snapshot records a warning and keeps a newer one',
        () async {
      final storage = _InspectableCheckoutStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(storage: storage, now: () => now);
      const newerOrderId = 'order-newer-session';
      await store.save(
        _snapshot(
          savedAt: now,
          idempotencyKey: _tenantBIdempotencyKey,
        ).withReceipt(
          _receipt(
            orderId: newerOrderId,
            expiresAt: now.add(const Duration(hours: 1)),
          ),
        ),
      );

      var consumeCalls = 0;
      final outcome = await store.consumeCartOnce(
        tenantId: _tenantA,
        orderId: 'order-missing-snapshot',
        consume: (_) async {
          consumeCalls++;
          return true;
        },
      );

      expect(outcome.state, CheckoutCartOutcomeState.preserved);
      expect(outcome.reason, 'snapshot_missing');
      expect(consumeCalls, 0);
      expect(
        (await store.read(_tenantA))?.receipt?.orderId,
        newerOrderId,
      );
    });

    test('receipt retirement rechecks identity after credential persistence',
        () async {
      final storage = _BlockingOrderAccessStorage();
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(storage: storage, now: () => now);
      const oldOrderId = 'order-being-retired';
      const newOrderId = 'order-created-concurrently';
      final oldSnapshot = _snapshot(savedAt: now).withReceipt(
        _receipt(
          orderId: oldOrderId,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );
      await store.save(oldSnapshot);
      final sessionKey = storage.lastWrittenKey!;

      storage.blockOrderAccessWrites = true;
      final retiring = store.clearReceiptIfMatches(
        tenantId: _tenantA,
        orderId: oldOrderId,
      );
      await storage.orderAccessWriteStarted.future;

      final newSnapshot = _snapshot(
        savedAt: now,
        idempotencyKey: _tenantBIdempotencyKey,
      ).withReceipt(
        _receipt(
          orderId: newOrderId,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
      );
      storage.seed(sessionKey, jsonEncode(newSnapshot.toJson()));
      storage.releaseOrderAccessWrite.complete();

      expect(await retiring, isFalse);
      expect(
        (await store.read(_tenantA))?.receipt?.orderId,
        newOrderId,
      );
    });
  });
}

const _tenantA = 'tenant-a';
const _tenantB = 'tenant-b';
const _idempotencyKey = '11111111-1111-4111-8111-111111111111';
const _tenantBIdempotencyKey = '22222222-2222-4222-8222-222222222222';

CheckoutSessionSnapshot _snapshot({
  String tenantId = _tenantA,
  String idempotencyKey = _idempotencyKey,
  String paymentMethod = 'transfer',
  required DateTime savedAt,
}) {
  return CheckoutSessionSnapshot.create(
    tenantId: tenantId,
    savedAt: savedAt,
    idempotencyKey: idempotencyKey,
    orderData: _orderData(
      tenantId,
      idempotencyKey: idempotencyKey,
      paymentMethod: paymentMethod,
    ),
    orderItems: _orderItems(tenantId),
    handoff: CheckoutHandoffSnapshot(
      paymentMethod: paymentMethod,
      deliveryType: 'shipping',
    ),
    cartRevision: 'cart-revision-$idempotencyKey',
  );
}

Map<String, dynamic> _orderData(
  String tenantId, {
  String idempotencyKey = _idempotencyKey,
  String paymentMethod = 'transfer',
}) {
  return {
    'tenant_id': tenantId,
    'checkout_idempotency_key': idempotencyKey,
    'customer_email': 'cliente@example.com',
    'customer_name': 'Cliente Prueba',
    'customer_phone': '+56911111111',
    'customer_address': 'Calle Uno 123, Viña del Mar',
    'delivery_type': 'shipping',
    'shipping_address_line1': 'Calle Uno 123',
    'shipping_address_line2': 'Depto 4',
    'shipping_city': 'Viña del Mar',
    'shipping_state': 'Valparaíso',
    'shipping_postal_code': '2520000',
    'shipping_country': 'Chile',
    'subtotal': 100000,
    'tax_amount': 19000,
    'shipping_quote_cost': 5000,
    'shipping_cost': 5000,
    'discount_amount': 0,
    'total': 124000,
    'status': 'pending',
    'payment_status': 'pending',
    'payment_method': paymentMethod,
    'customer_notes': 'Entregar por conserjería',
  };
}

List<Map<String, dynamic>> _orderItems(String tenantId) {
  return [
    {
      'tenant_id': tenantId,
      'product_id': 'product-1',
      'product_name': 'Producto Uno',
      'product_sku': 'SKU-1',
      'quantity': 2,
      'unit_price': 50000,
      'subtotal': 100000,
    },
    {
      'tenant_id': tenantId,
      'product_id': 'product-2',
      'product_name': 'Producto Dos',
      'product_sku': 'SKU-2',
      'quantity': 1,
      'unit_price': 19000,
      'subtotal': 19000,
    },
  ];
}

PublicOrderCheckoutAccess _receipt({
  required String orderId,
  required DateTime expiresAt,
  bool replay = false,
}) {
  return PublicOrderCheckoutAccess(
    orderId: orderId,
    accessToken:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    expiresAt: expiresAt,
    isReplay: replay,
  );
}

Map<String, dynamic> _jsonCopy(Map<String, dynamic> value) {
  return Map<String, dynamic>.from(
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>,
  );
}

class _InspectableCheckoutStorage implements CheckoutSessionStorage {
  final Map<String, String> values = <String, String>{};
  String? lastWrittenKey;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    lastWrittenKey = key;
    if (value.isEmpty) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  void seed(String key, String value) {
    values[key] = value;
  }
}

class _BlockingOrderAccessStorage extends _InspectableCheckoutStorage {
  bool blockOrderAccessWrites = false;
  final Completer<void> orderAccessWriteStarted = Completer<void>();
  final Completer<void> releaseOrderAccessWrite = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    if (blockOrderAccessWrites &&
        key.startsWith('vinabike.public-order-access.v1.')) {
      if (!orderAccessWriteStarted.isCompleted) {
        orderAccessWriteStarted.complete();
      }
      await releaseOrderAccessWrite.future;
    }
    await super.write(key, value);
  }
}
