import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/accounting/services/financial_projection_realtime_transport.dart';
import 'package:vinabike_erp/modules/accounting/services/financial_projection_refresh_coordinator.dart';

void main() {
  test('tenant switch cancels the old channel and ignores stale callbacks',
      () async {
    final transport = _FakeRealtimeTransport();
    final coordinator = FinancialProjectionRefreshCoordinator(
      realtimeTransport: transport,
      coalesceWindow: const Duration(milliseconds: 2),
    );
    final signals = <FinancialProjectionRefreshSignal>[];
    final signalSubscription = coordinator.signals.listen(signals.add);
    addTearDown(signalSubscription.cancel);
    addTearDown(coordinator.dispose);

    await coordinator.synchronizeTenant('tenant-a');
    final tenantA = transport.attempts.single;
    await coordinator.synchronizeTenant('tenant-b');
    final tenantB = transport.attempts.last;
    signals.clear();

    expect(tenantA.subscription.cancelled, isTrue);
    expect(tenantB.tenantId, 'tenant-b');

    tenantA.emit(kind: 'salesPayment', eventId: 'stale-a');
    tenantB.emit(kind: 'purchasePayment', eventId: 'current-b');
    await Future<void>.delayed(const Duration(milliseconds: 8));

    expect(signals, hasLength(1));
    expect(
      signals.single.changes,
      const {FinancialProjectionChangeKind.purchasePayment},
    );
  });

  test('a stale async subscription cannot replace the newer tenant', () async {
    final transport = _FakeRealtimeTransport()..delayNextSubscription = true;
    final coordinator = FinancialProjectionRefreshCoordinator(
      realtimeTransport: transport,
    );
    addTearDown(coordinator.dispose);

    final tenantAFuture = coordinator.synchronizeTenant('tenant-a');
    await Future<void>.delayed(Duration.zero);
    expect(transport.attempts, hasLength(1));
    final tenantA = transport.attempts.single;

    await coordinator.synchronizeTenant('tenant-b');
    final tenantB = transport.attempts.last;
    tenantA.release();
    await tenantAFuture;

    expect(coordinator.tenantId, 'tenant-b');
    expect(tenantA.subscription.cancelled, isTrue);
    expect(tenantB.subscription.cancelled, isFalse);
  });

  test('tenant data clears before a stalled old-channel cancellation',
      () async {
    final transport = _FakeRealtimeTransport();
    final coordinator = FinancialProjectionRefreshCoordinator(
      realtimeTransport: transport,
    );
    final signals = <FinancialProjectionRefreshSignal>[];
    final signalSubscription = coordinator.signals.listen(signals.add);
    addTearDown(signalSubscription.cancel);
    addTearDown(coordinator.dispose);

    await coordinator.synchronizeTenant('tenant-a');
    final tenantA = transport.attempts.single;
    tenantA.subscription.delayCancellation();
    signals.clear();

    var switchCompleted = false;
    final switchFuture = coordinator.synchronizeTenant('tenant-b').then((_) {
      switchCompleted = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.tenantId, 'tenant-b');
    expect(switchCompleted, isFalse);
    expect(signals, hasLength(1));
    expect(
      signals.single.changes,
      const {FinancialProjectionChangeKind.tenantScope},
    );

    tenantA.subscription.releaseCancellation();
    await switchFuture;
    expect(transport.attempts.last.tenantId, 'tenant-b');
  });

  test('broadcast envelopes map all financial kinds and coalesce row fanout',
      () async {
    final transport = _FakeRealtimeTransport();
    final coordinator = FinancialProjectionRefreshCoordinator(
      realtimeTransport: transport,
      coalesceWindow: const Duration(milliseconds: 2),
    );
    final signals = <FinancialProjectionRefreshSignal>[];
    final signalSubscription = coordinator.signals.listen(signals.add);
    addTearDown(signalSubscription.cancel);
    addTearDown(coordinator.dispose);

    await coordinator.synchronizeTenant('tenant-a');
    signals.clear();
    final attempt = transport.attempts.single;
    attempt
      ..emit(kind: 'salesPayment', eventId: 'sale-payment-1')
      ..emit(kind: 'expense', eventId: 'expense-line-1')
      ..emit(kind: 'journalEntry', eventId: 'journal-line-1')
      ..emit(kind: 'account', eventId: 'account-1');
    await Future<void>.delayed(const Duration(milliseconds: 8));

    expect(signals, hasLength(1));
    expect(
      signals.single.changes,
      const {
        FinancialProjectionChangeKind.salesPayment,
        FinancialProjectionChangeKind.expense,
        FinancialProjectionChangeKind.journalEntry,
        FinancialProjectionChangeKind.account,
      },
    );
  });

  test('event ids deduplicate retries but not two real commits on one entity',
      () async {
    final transport = _FakeRealtimeTransport();
    final coordinator = FinancialProjectionRefreshCoordinator(
      realtimeTransport: transport,
      coalesceWindow: const Duration(milliseconds: 2),
      duplicateWindow: const Duration(milliseconds: 100),
    );
    final signals = <FinancialProjectionRefreshSignal>[];
    final signalSubscription = coordinator.signals.listen(signals.add);
    addTearDown(signalSubscription.cancel);
    addTearDown(coordinator.dispose);

    await coordinator.synchronizeTenant('tenant-a');
    signals.clear();
    final attempt = transport.attempts.single;

    attempt
      ..emit(
        kind: 'salesInvoice',
        eventId: 'event-1',
        entityId: 'invoice-1',
      )
      ..emit(
        kind: 'salesInvoice',
        eventId: 'event-1',
        entityId: 'invoice-1',
      );
    await Future<void>.delayed(const Duration(milliseconds: 8));

    attempt.emit(
      kind: 'salesInvoice',
      eventId: 'event-2',
      entityId: 'invoice-1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 8));

    expect(signals.map((signal) => signal.revision), <int>[2, 3]);
  });

  test('background events wait and resume produces one process revalidation',
      () async {
    final transport = _FakeRealtimeTransport();
    final coordinator = FinancialProjectionRefreshCoordinator(
      realtimeTransport: transport,
      coalesceWindow: const Duration(milliseconds: 2),
    );
    final signals = <FinancialProjectionRefreshSignal>[];
    final signalSubscription = coordinator.signals.listen(signals.add);
    addTearDown(signalSubscription.cancel);
    addTearDown(coordinator.dispose);

    await coordinator.synchronizeTenant('tenant-a');
    signals.clear();
    coordinator.setApplicationActive(false);
    transport.attempts.single
      ..emit(kind: 'expensePayment', eventId: 'background-1')
      ..status(FinancialProjectionRealtimeStatus.subscribed);
    await Future<void>.delayed(const Duration(milliseconds: 8));
    expect(signals, isEmpty);

    coordinator
      ..setApplicationActive(true)
      ..setApplicationActive(true);
    await Future<void>.delayed(const Duration(milliseconds: 8));

    expect(signals, hasLength(1));
    expect(
      signals.single.changes,
      const {FinancialProjectionChangeKind.revalidation},
    );
  });

  test('foreground resume retries setup that failed before channel creation',
      () async {
    final transport = _FakeRealtimeTransport()..failuresRemaining = 1;
    final coordinator = FinancialProjectionRefreshCoordinator(
      realtimeTransport: transport,
      coalesceWindow: const Duration(milliseconds: 2),
    );
    final signals = <FinancialProjectionRefreshSignal>[];
    final signalSubscription = coordinator.signals.listen(signals.add);
    addTearDown(signalSubscription.cancel);
    addTearDown(coordinator.dispose);

    await coordinator.synchronizeTenant('tenant-a');
    expect(transport.subscribeCalls, 1);
    expect(transport.attempts, isEmpty);
    signals.clear();

    coordinator
      ..setApplicationActive(false)
      ..setApplicationActive(true);
    await Future<void>.delayed(const Duration(milliseconds: 8));

    expect(transport.subscribeCalls, 2);
    expect(transport.attempts.single.tenantId, 'tenant-a');
    expect(signals, hasLength(1));
    expect(
      signals.single.changes,
      const {FinancialProjectionChangeKind.revalidation},
    );

    final retriedAttempt = transport.attempts.single;
    retriedAttempt.status(FinancialProjectionRealtimeStatus.subscribed);
    await Future<void>.delayed(const Duration(milliseconds: 8));
    expect(signals, hasLength(1));

    retriedAttempt.status(FinancialProjectionRealtimeStatus.subscribed);
    await Future<void>.delayed(const Duration(milliseconds: 8));
    expect(signals, hasLength(2));
    expect(
      signals.last.changes,
      const {FinancialProjectionChangeKind.revalidation},
    );
  });

  test('foreground retry cannot supersede an in-flight tenant resolution',
      () async {
    final transport = _FakeRealtimeTransport()..failuresRemaining = 1;
    final coordinator = FinancialProjectionRefreshCoordinator(
      realtimeTransport: transport,
      coalesceWindow: const Duration(milliseconds: 2),
    );
    addTearDown(coordinator.dispose);

    await coordinator.synchronizeTenant('tenant-a');
    expect(transport.attempts, isEmpty);

    final tenantResolution = Completer<String?>();
    final switchFuture = coordinator.synchronizeTenantFromResolver(
      () => tenantResolution.future,
    );

    coordinator
      ..setApplicationActive(false)
      ..setApplicationActive(true);
    await Future<void>.delayed(Duration.zero);

    expect(transport.attempts.single.tenantId, 'tenant-a');
    final resumedTenantA = transport.attempts.single;

    tenantResolution.complete('tenant-b');
    await switchFuture;

    expect(coordinator.tenantId, 'tenant-b');
    expect(resumedTenantA.subscription.cancelled, isTrue);
    expect(
      transport.attempts.map((attempt) => attempt.tenantId),
      <String>['tenant-a', 'tenant-b'],
    );
  });

  test('logout and dispose tear down channels; malformed events fail closed',
      () async {
    final transport = _FakeRealtimeTransport();
    final coordinator = FinancialProjectionRefreshCoordinator(
      realtimeTransport: transport,
      coalesceWindow: const Duration(milliseconds: 2),
    );
    final signals = <FinancialProjectionRefreshSignal>[];
    final signalSubscription = coordinator.signals.listen(signals.add);
    addTearDown(signalSubscription.cancel);

    await coordinator.synchronizeTenant('tenant-a');
    final attempt = transport.attempts.single;
    signals.clear();
    attempt
      ..emitEnvelope(const {'payload': 'not-a-map'})
      ..emit(kind: 'futureUnknownKind', eventId: 'unknown');
    await Future<void>.delayed(const Duration(milliseconds: 8));
    expect(signals, isEmpty);

    await coordinator.synchronizeTenant(null);
    expect(attempt.subscription.cancelled, isTrue);

    await coordinator.synchronizeTenant('tenant-b');
    final tenantB = transport.attempts.last;
    tenantB.subscription.cancelError = StateError('teardown failed');
    coordinator.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(tenantB.subscription.cancelled, isTrue);
  });
}

class _FakeRealtimeTransport implements FinancialProjectionRealtimeTransport {
  final List<_FakeSubscriptionAttempt> attempts = [];
  bool delayNextSubscription = false;
  int failuresRemaining = 0;
  int subscribeCalls = 0;

  @override
  Future<FinancialProjectionRealtimeSubscription> subscribe({
    required String tenantId,
    required void Function(Map<String, dynamic> value) onEvent,
    required void Function(
      FinancialProjectionRealtimeStatus status,
      Object? error,
    ) onStatus,
  }) {
    subscribeCalls++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      return Future<FinancialProjectionRealtimeSubscription>.error(
        StateError('subscription setup failed'),
      );
    }
    final attempt = _FakeSubscriptionAttempt(
      tenantId: tenantId,
      onEvent: onEvent,
      onStatus: onStatus,
      delayed: delayNextSubscription,
    );
    delayNextSubscription = false;
    attempts.add(attempt);
    return attempt.ready;
  }
}

class _FakeSubscriptionAttempt {
  _FakeSubscriptionAttempt({
    required this.tenantId,
    required this.onEvent,
    required this.onStatus,
    required bool delayed,
  }) : _readyCompleter = delayed
            ? Completer<FinancialProjectionRealtimeSubscription>()
            : null {
    if (!delayed) {
      _immediateReady =
          Future<FinancialProjectionRealtimeSubscription>.value(subscription);
    }
  }

  final String tenantId;
  final void Function(Map<String, dynamic> value) onEvent;
  final void Function(
    FinancialProjectionRealtimeStatus status,
    Object? error,
  ) onStatus;
  final _FakeRealtimeSubscription subscription = _FakeRealtimeSubscription();
  final Completer<FinancialProjectionRealtimeSubscription>? _readyCompleter;
  late final Future<FinancialProjectionRealtimeSubscription>? _immediateReady;

  Future<FinancialProjectionRealtimeSubscription> get ready =>
      _readyCompleter?.future ?? _immediateReady!;

  void release() {
    final completer = _readyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(subscription);
    }
  }

  void emit({
    required String kind,
    required String eventId,
    String entityId = 'entity-1',
  }) {
    emitEnvelope({
      'event': 'changed',
      'type': 'broadcast',
      'payload': {
        'kind': kind,
        'event_id': eventId,
        'entity_id': entityId,
        'operation': 'update',
      },
    });
  }

  void emitEnvelope(Map<String, dynamic> envelope) {
    onEvent(envelope);
  }

  void status(
    FinancialProjectionRealtimeStatus status, [
    Object? error,
  ]) {
    onStatus(status, error);
  }
}

class _FakeRealtimeSubscription
    implements FinancialProjectionRealtimeSubscription {
  bool cancelled = false;
  Object? cancelError;
  Completer<void>? _cancelGate;

  void delayCancellation() {
    _cancelGate ??= Completer<void>();
  }

  void releaseCancellation() {
    final gate = _cancelGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    await _cancelGate?.future;
    final error = cancelError;
    if (error != null) throw error;
  }
}
