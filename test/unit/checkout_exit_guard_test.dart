import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/services/checkout_exit_guard.dart';

void main() {
  group('CheckoutExitGuard', () {
    test('allows ordinary exits without invoking confirmation', () async {
      final guard = CheckoutExitGuard();
      var confirmationCalls = 0;

      final allowed = await guard.requestExitAuthorization((_) async {
        confirmationCalls++;
        return false;
      });

      expect(allowed, isTrue);
      expect(confirmationCalls, 0);
      expect(guard.isLocked, isFalse);
    });

    test('current lease updates phase and release unlocks the guard', () {
      final guard = CheckoutExitGuard();
      final owner = Object();
      final lease = guard.acquire(
        owner: owner,
        phase: CheckoutExitPhase.recoveringOrder,
      );

      expect(lease.isCurrent, isTrue);
      expect(guard.isLocked, isTrue);
      expect(guard.phase, CheckoutExitPhase.recoveringOrder);

      lease.updatePhase(CheckoutExitPhase.orderCreated);
      expect(guard.phase, CheckoutExitPhase.orderCreated);

      lease.release();
      expect(lease.isCurrent, isFalse);
      expect(guard.isLocked, isFalse);
      expect(guard.phase, isNull);
    });

    test('a stale lease cannot update or release a newer owner', () {
      final guard = CheckoutExitGuard();
      final staleLease = guard.acquire(
        owner: Object(),
        phase: CheckoutExitPhase.recoveringOrder,
      );
      final currentLease = guard.acquire(
        owner: Object(),
        phase: CheckoutExitPhase.orderCreated,
      );

      expect(staleLease.isCurrent, isFalse);
      expect(currentLease.isCurrent, isTrue);

      staleLease.updatePhase(CheckoutExitPhase.recoveringOrder);
      staleLease.release();

      expect(guard.isLocked, isTrue);
      expect(guard.phase, CheckoutExitPhase.orderCreated);
      expect(currentLease.isCurrent, isTrue);
    });

    test('coalesces concurrent confirmations into one decision', () async {
      final guard = CheckoutExitGuard();
      guard.acquire(
        owner: Object(),
        phase: CheckoutExitPhase.recoveringOrder,
      );
      final confirmation = Completer<bool>();
      var confirmationCalls = 0;

      Future<bool> confirm(CheckoutExitPhase phase) {
        confirmationCalls++;
        expect(phase, CheckoutExitPhase.recoveringOrder);
        return confirmation.future;
      }

      final first = guard.requestExitAuthorization(confirm);
      final second = guard.requestExitAuthorization(confirm);

      expect(identical(first, second), isTrue);
      expect(confirmationCalls, 1);

      confirmation.complete(true);
      expect(await first, isTrue);
      expect(await second, isTrue);
    });

    test('rejects a completed confirmation when its lease became stale',
        () async {
      final guard = CheckoutExitGuard();
      guard.acquire(
        owner: Object(),
        phase: CheckoutExitPhase.recoveringOrder,
      );
      final confirmation = Completer<bool>();

      final pending = guard.requestExitAuthorization(
        (_) => confirmation.future,
        permitNextNavigation: true,
      );
      final currentLease = guard.acquire(
        owner: Object(),
        phase: CheckoutExitPhase.orderCreated,
      );
      confirmation.complete(true);

      expect(await pending, isFalse);
      expect(guard.consumeNavigationPermit(), isFalse);
      expect(currentLease.isCurrent, isTrue);
      expect(guard.phase, CheckoutExitPhase.orderCreated);
    });

    test('navigation permit is generation-bound, one-shot, and revocable',
        () async {
      final guard = CheckoutExitGuard();
      final lease = guard.acquire(
        owner: Object(),
        phase: CheckoutExitPhase.orderCreated,
      );

      expect(
        await guard.requestExitAuthorization(
          (_) async => true,
          permitNextNavigation: true,
        ),
        isTrue,
      );
      expect(guard.consumeNavigationPermit(), isTrue);
      expect(guard.consumeNavigationPermit(), isFalse);

      expect(
        await guard.requestExitAuthorization(
          (_) async => true,
          permitNextNavigation: true,
        ),
        isTrue,
      );
      guard.revokeNavigationPermit();
      expect(guard.consumeNavigationPermit(), isFalse);

      expect(
        await guard.requestExitAuthorization((_) async => false),
        isFalse,
      );
      expect(lease.isCurrent, isTrue);
      expect(guard.isLocked, isTrue);
    });
  });
}
