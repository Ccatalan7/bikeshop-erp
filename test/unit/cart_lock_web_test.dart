@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:vinabike_erp/public_store/services/cart_lock.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('web lock remains exclusive until the full async callback completes',
      () async {
    final firstCoordinator = createCartLockCoordinator();
    final secondCoordinator = createCartLockCoordinator();
    final resource = 'cart-lock-test-${const Uuid().v4()}';
    final firstEntered = Completer<void>();
    final releaseFirst = Completer<void>();
    var secondEntered = false;
    var activeCallbacks = 0;
    var maximumActiveCallbacks = 0;

    final first = firstCoordinator.synchronized(resource, () async {
      activeCallbacks++;
      maximumActiveCallbacks = activeCallbacks > maximumActiveCallbacks
          ? activeCallbacks
          : maximumActiveCallbacks;
      firstEntered.complete();
      await releaseFirst.future;
      activeCallbacks--;
    });
    await firstEntered.future;

    final second = secondCoordinator.synchronized(resource, () async {
      secondEntered = true;
      activeCallbacks++;
      maximumActiveCallbacks = activeCallbacks > maximumActiveCallbacks
          ? activeCallbacks
          : maximumActiveCallbacks;
      activeCallbacks--;
    });
    await Future<void>.delayed(Duration.zero);
    expect(secondEntered, isFalse);

    releaseFirst.complete();
    await Future.wait([first, second]);

    expect(secondEntered, isTrue);
    expect(maximumActiveCallbacks, 1);
  });

  test('the coordinator participates in the real navigator.locks domain',
      () async {
    final coordinator = createCartLockCoordinator();
    final resource = 'cart-lock-native-domain-test-${const Uuid().v4()}';
    final directEntered = Completer<void>();
    final releaseDirect = Completer<void>();
    var coordinatorEntered = false;

    final directCallback = ((JSAny? _) {
      return (() async {
        directEntered.complete();
        await releaseDirect.future;
      }())
          .toJS;
    }).toJS;
    final directLock =
        web.window.navigator.locks.request(resource, directCallback).toDart;
    await directEntered.future;

    final coordinated = coordinator.synchronized(resource, () async {
      coordinatorEntered = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(coordinatorEntered, isFalse);

    releaseDirect.complete();
    await directLock;
    await coordinated;
    expect(coordinatorEntered, isTrue);
  });

  test('a throwing callback releases the lock for the next waiter', () async {
    final coordinator = createCartLockCoordinator();
    final resource = 'cart-lock-error-test-${const Uuid().v4()}';

    await expectLater(
      coordinator.synchronized(
        resource,
        () async => throw StateError('simulated action failure'),
      ),
      throwsStateError,
    );

    var entered = false;
    await coordinator.synchronized(resource, () async {
      entered = true;
    });
    expect(entered, isTrue);
  });
}
