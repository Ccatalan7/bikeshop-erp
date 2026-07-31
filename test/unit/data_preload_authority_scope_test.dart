import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/data_preload_service.dart';

void main() {
  test('batch evidence requires seven exact authority publications', () {
    const authorityA = ErpAuthorityScopeKey(
      userId: 'user-a',
      tenantId: 'tenant-a',
    );
    const authorityB = ErpAuthorityScopeKey(
      userId: 'user-a',
      tenantId: 'tenant-b',
    );

    expect(
      DataPreloadBatchEvidence.isComplete(
        expectedScope: authorityA,
        outcomes: List<ErpAuthorityScopeKey?>.filled(7, authorityA),
      ),
      isTrue,
      reason: 'Each successful owner may legitimately publish an empty list.',
    );
    expect(
      DataPreloadBatchEvidence.isComplete(
        expectedScope: authorityA,
        outcomes: const [
          authorityA,
          authorityA,
          authorityA,
          null,
          authorityA,
          authorityA,
          authorityA,
        ],
      ),
      isFalse,
    );
    expect(
      DataPreloadBatchEvidence.isComplete(
        expectedScope: authorityA,
        outcomes: const [],
      ),
      isFalse,
    );
    expect(
      DataPreloadBatchEvidence.isComplete(
        expectedScope: authorityA,
        outcomes: const [
          authorityA,
          authorityA,
          authorityA,
          authorityB,
          authorityA,
          authorityA,
          authorityA,
        ],
      ),
      isFalse,
      reason: 'A mixed A+B batch must never be declared complete.',
    );
  });

  test('retry budget is bounded to the initial attempt plus configured delays',
      () {
    final timers = <_ManualTimer>[];
    final controller = DataPreloadRetryController(
      retryDelays: const [
        Duration(milliseconds: 10),
        Duration(milliseconds: 20),
      ],
      timerFactory: (delay, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    var retries = 0;

    expect(controller.beginAttempt(), isTrue);
    expect(controller.attemptCount, 1);
    expect(
      controller.scheduleRetry(
        canRun: () => true,
        retry: () {
          retries++;
          expect(controller.beginAttempt(), isTrue);
        },
      ),
      isTrue,
    );
    timers.last.fire();

    expect(controller.attemptCount, 2);
    expect(
      controller.scheduleRetry(
        canRun: () => true,
        retry: () {
          retries++;
          expect(controller.beginAttempt(), isTrue);
        },
      ),
      isTrue,
    );
    timers.last.fire();

    expect(retries, 2);
    expect(controller.attemptCount, controller.maxAttempts);
    expect(
      controller.scheduleRetry(canRun: () => true, retry: () {}),
      isFalse,
    );
    expect(controller.beginAttempt(), isFalse);
  });

  test('cancel and reset suppress a scheduled retry from an obsolete scope',
      () {
    late _ManualTimer timer;
    final controller = DataPreloadRetryController(
      retryDelays: const [Duration(milliseconds: 10)],
      timerFactory: (delay, callback) => timer = _ManualTimer(callback),
    );
    var retries = 0;

    expect(controller.beginAttempt(), isTrue);
    expect(
      controller.scheduleRetry(
        canRun: () => true,
        retry: () => retries++,
      ),
      isTrue,
    );
    controller.reset();
    timer.fire();

    expect(retries, 0);
    expect(controller.attemptCount, 0);
    expect(controller.hasScheduledRetry, isFalse);
    expect(controller.beginAttempt(), isTrue);
  });

  test('preload authority invalidates every prior user and tenant generation',
      () {
    final scope = DataPreloadAuthorityScope();

    expect(
      scope.bind(userId: ' user-a ', tenantId: ' tenant-a '),
      isTrue,
    );
    final tenantAGeneration = scope.generation;
    expect(scope.userId, 'user-a');
    expect(scope.tenantId, 'tenant-a');
    expect(
      scope.owns(
        generation: tenantAGeneration,
        userId: 'user-a',
        tenantId: 'tenant-a',
      ),
      isTrue,
    );

    expect(
      scope.bind(userId: 'user-a', tenantId: 'tenant-a'),
      isFalse,
    );
    expect(scope.generation, tenantAGeneration);

    expect(
      scope.bind(userId: 'user-b', tenantId: 'tenant-a'),
      isTrue,
    );
    expect(
      scope.owns(
        generation: tenantAGeneration,
        userId: 'user-a',
        tenantId: 'tenant-a',
      ),
      isFalse,
    );
    expect(
      scope.owns(
        generation: scope.generation,
        userId: 'user-b',
        tenantId: 'tenant-a',
      ),
      isTrue,
    );

    scope.bind(userId: null, tenantId: null);
    expect(scope.userId, isNull);
    expect(scope.tenantId, isNull);
    expect(
      scope.owns(
        generation: scope.generation,
        userId: 'user-b',
        tenantId: 'tenant-a',
      ),
      isFalse,
    );
  });

  test('authority B starts every preload before pending authority A completes',
      () async {
    final authority = DataPreloadAuthorityScope();
    final coordinator = DataPreloadRunCoordinator(authority);
    final gatesA = List.generate(7, (_) => Completer<void>());
    final gatesB = List.generate(7, (_) => Completer<void>());
    var startsA = 0;
    var startsB = 0;

    Future<void> startBatch(AuthorityCacheLease lease) async {
      final isA = lease.scope.userId == 'user-a';
      final gates = isA ? gatesA : gatesB;
      await Future.wait(
        List.generate(gates.length, (index) {
          if (isA) {
            startsA++;
          } else {
            startsB++;
          }
          return gates[index].future;
        }),
      );
    }

    coordinator.bind(userId: 'user-a', tenantId: 'tenant-a');
    final requestA = coordinator.run(startBatch);
    expect(startsA, 7);

    coordinator.bind(userId: 'user-b', tenantId: 'tenant-b');
    final requestB = coordinator.run(startBatch);
    expect(startsB, 7);
    expect(coordinator.isRunning, isTrue);

    for (final gate in gatesA) {
      gate.complete();
    }
    await requestA;
    expect(
      coordinator.isRunning,
      isTrue,
      reason: 'A completion must not clear B from the current in-flight slot',
    );

    for (final gate in gatesB) {
      gate.complete();
    }
    await requestB;
    expect(coordinator.isRunning, isFalse);
  });

  test('same authority shares one preload future', () async {
    final authority = DataPreloadAuthorityScope();
    final coordinator = DataPreloadRunCoordinator(authority);
    final pending = Completer<void>();
    var starts = 0;

    coordinator.bind(userId: 'user-a', tenantId: 'tenant-a');
    final first = coordinator.run((_) {
      starts++;
      return pending.future;
    });
    final second = coordinator.run((_) {
      starts++;
      return pending.future;
    });

    expect(identical(first, second), isTrue);
    expect(starts, 1);
    pending.complete();
    await first;
    expect(coordinator.isRunning, isFalse);
  });

  test('sign-out detaches a pending preload synchronously', () async {
    final authority = DataPreloadAuthorityScope();
    final coordinator = DataPreloadRunCoordinator(authority);
    final pending = Completer<void>();
    var currentFinishes = 0;

    coordinator.bind(userId: 'user-a', tenantId: 'tenant-a');
    final request = coordinator.run(
      (_) => pending.future,
      onCurrentFinish: () => currentFinishes++,
    );
    expect(coordinator.isRunning, isTrue);

    coordinator.bind(userId: null, tenantId: null);
    expect(coordinator.isRunning, isFalse);
    pending.complete();
    await request;
    expect(currentFinishes, 0);
  });
}

class _ManualTimer implements Timer {
  _ManualTimer(this._callback);

  final void Function() _callback;
  bool _isActive = true;
  int _tick = 0;

  void fire() {
    if (!_isActive) return;
    _isActive = false;
    _tick++;
    _callback();
  }

  @override
  void cancel() {
    _isActive = false;
  }

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;
}
