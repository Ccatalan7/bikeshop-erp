import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/accounting/models/dashboard_metrics.dart';
import 'package:vinabike_erp/modules/accounting/services/financial_projection_realtime_transport.dart';
import 'package:vinabike_erp/modules/accounting/services/financial_projection_refresh_coordinator.dart';
import 'package:vinabike_erp/modules/accounting/services/financial_reports_service.dart';
import 'package:vinabike_erp/modules/accounting/widgets/accounting_dashboard_section.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('es');
    await initializeDateFormatting('es_CL');
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
  });

  setUp(AccountingDashboardSection.invalidateCache);

  for (final width in <double>[384, 1200]) {
    testWidgets(
      'a confirmed financial change refreshes once at ${width.toInt()} px',
      (tester) async {
        _setViewport(tester, width);
        final database = DatabaseService();
        final reports = _SequencedFinancialReportsService(database);
        final coordinator = FinancialProjectionRefreshCoordinator(
          coalesceWindow: const Duration(milliseconds: 10),
          duplicateWindow: const Duration(milliseconds: 100),
        );
        addTearDown(reports.dispose);
        addTearDown(database.dispose);
        addTearDown(coordinator.dispose);

        await _pumpDashboard(
          tester,
          reports: reports,
          coordinator: coordinator,
        );
        expect(reports.seriesRequests, 1);
        expect(reports.breakdownRequests, 1);

        const change = FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.salesInvoice,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: 'sale-1',
        );
        coordinator
          ..recordCommitted(change)
          ..recordCommitted(change);
        await tester.pump(const Duration(milliseconds: 11));
        await tester.pumpAndSettle();

        expect(reports.seriesRequests, 2);
        expect(reports.breakdownRequests, 2);
        expect(find.text('Ingresos vs gastos'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a remote tenant Broadcast refreshes in place at ${width.toInt()} px',
      (tester) async {
        _setViewport(tester, width);
        final database = DatabaseService();
        final reports = _SequencedFinancialReportsService(database);
        final transport = _WidgetFakeRealtimeTransport();
        final coordinator = FinancialProjectionRefreshCoordinator(
          realtimeTransport: transport,
          coalesceWindow: const Duration(milliseconds: 10),
        );
        addTearDown(reports.dispose);
        addTearDown(database.dispose);
        addTearDown(coordinator.dispose);

        await coordinator.synchronizeTenant('tenant-a');
        await _pumpDashboard(
          tester,
          reports: reports,
          coordinator: coordinator,
        );
        final stateBefore = tester.state(
          find.byType(AccountingDashboardSection),
        );

        transport.emit({
          'event': 'changed',
          'type': 'broadcast',
          'payload': {
            'event_id': 'remote-sale-1',
            'kind': 'salesPayment',
            'entity_id': 'payment-1',
            'operation': 'insert',
          },
        });
        await tester.pump(const Duration(milliseconds: 11));
        await tester.pumpAndSettle();

        expect(reports.seriesRequests, 2);
        expect(reports.breakdownRequests, 2);
        expect(
          tester.state(find.byType(AccountingDashboardSection)),
          same(stateBefore),
          reason: 'Realtime must update projections, not replace the route.',
        );
        expect(find.text('Ingresos vs gastos'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a hidden or disposed dashboard defers work without a state race',
    (tester) async {
      _setViewport(tester, 1200);
      final database = DatabaseService();
      final reports = _SequencedFinancialReportsService(database);
      final coordinator = FinancialProjectionRefreshCoordinator(
        coalesceWindow: const Duration(milliseconds: 10),
      );
      final visible = ValueNotifier<bool>(true);
      addTearDown(reports.dispose);
      addTearDown(database.dispose);
      addTearDown(coordinator.dispose);
      addTearDown(visible.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<FinancialReportsService>.value(
          value: reports,
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: visible,
                child: AccountingDashboardSection(
                  refreshCoordinator: coordinator,
                ),
                builder: (context, enabled, child) => TickerMode(
                  enabled: enabled,
                  child: child!,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reports.seriesRequests, 1);

      visible.value = false;
      await tester.pump();
      coordinator.recordCommitted(
        const FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.expense,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: 'expense-hidden',
        ),
      );
      await tester.pump(const Duration(milliseconds: 11));
      await tester.pump();
      expect(reports.seriesRequests, 1);

      visible.value = true;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(reports.seriesRequests, 2);
      expect(reports.breakdownRequests, 2);

      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.recordCommitted(
        const FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.expense,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: 'expense-after-dispose',
        ),
      );
      await tester.pump(const Duration(milliseconds: 11));
      await tester.pump();
      expect(reports.seriesRequests, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh failure preserves last good data and an explicit retry recovers',
    (tester) async {
      _setViewport(tester, 1200);
      final database = DatabaseService();
      final reports = _SequencedFinancialReportsService(
        database,
        failingSeriesRequests: {2},
      );
      final coordinator = FinancialProjectionRefreshCoordinator(
        coalesceWindow: const Duration(milliseconds: 10),
      );
      addTearDown(reports.dispose);
      addTearDown(database.dispose);
      addTearDown(coordinator.dispose);

      await _pumpDashboard(
        tester,
        reports: reports,
        coordinator: coordinator,
      );
      expect(find.text('Ingresos vs gastos'), findsOneWidget);

      coordinator.recordCommitted(
        const FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.expensePayment,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: 'expense-payment-1',
        ),
      );
      await tester.pump(const Duration(milliseconds: 11));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Datos sin actualizar. Conservamos la última lectura válida.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ingresos vs gastos'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(reports.seriesRequests, 3);
      expect(reports.breakdownRequests, 3);
      expect(
        find.text(
          'Datos sin actualizar. Conservamos la última lectura válida.',
        ),
        findsNothing,
      );
      expect(find.text('Ingresos vs gastos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tenant scope switch clears the prior projection before reloading',
    (tester) async {
      _setViewport(tester, 1200);
      final database = DatabaseService();
      final reports = _TenantSwitchFinancialReportsService(database);
      final transport = _DelayedCancellationRealtimeTransport();
      final coordinator = FinancialProjectionRefreshCoordinator(
        realtimeTransport: transport,
        coalesceWindow: const Duration(milliseconds: 10),
      );
      addTearDown(reports.dispose);
      addTearDown(database.dispose);
      addTearDown(coordinator.dispose);

      await coordinator.synchronizeTenant('tenant-a');
      await _pumpDashboard(
        tester,
        reports: reports,
        coordinator: coordinator,
      );
      expect(find.text('Ingresos vs gastos'), findsOneWidget);

      final tenantAChannel = transport.subscriptions.single
        ..delayCancellation();
      var scopeSwitchCompleted = false;
      final scopeSwitch = coordinator.synchronizeTenant('tenant-b').then((_) {
        scopeSwitchCompleted = true;
      });
      await tester.pump();
      await tester.pump();

      expect(scopeSwitchCompleted, isFalse);
      expect(
        find.text('Ingresos vs gastos'),
        findsNothing,
        reason: 'A stalled channel teardown must not retain prior-tenant data.',
      );
      expect(reports.seriesRequests, 2);
      expect(reports.breakdownRequests, 2);

      tenantAChannel.releaseCancellation();
      await scopeSwitch;
      reports.completeTenantB();
      await tester.pumpAndSettle();
      expect(find.text('Ingresos vs gastos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

void _setViewport(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required FinancialReportsService reports,
  required FinancialProjectionRefreshCoordinator coordinator,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<FinancialReportsService>.value(
      value: reports,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountingDashboardSection(
              refreshCoordinator: coordinator,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _SequencedFinancialReportsService extends FinancialReportsService {
  _SequencedFinancialReportsService(
    super.databaseService, {
    this.failingSeriesRequests = const {},
  });

  final Set<int> failingSeriesRequests;
  int seriesRequests = 0;
  int breakdownRequests = 0;

  @override
  Future<List<MonthlyIncomeExpensePoint>> getIncomeExpenseTimeseries({
    int months = 12,
    bool isCashFlow = false,
  }) async {
    final request = ++seriesRequests;
    if (failingSeriesRequests.contains(request)) {
      throw StateError('simulated refresh failure');
    }
    return _sampleSeries(income: request * 100000);
  }

  @override
  Future<List<PeriodDetailItem>> getExpensePeriodDetails({
    required DateTime startDate,
    required DateTime endDate,
    bool isCashFlow = false,
  }) async {
    breakdownRequests++;
    return _sampleExpenses();
  }
}

class _TenantSwitchFinancialReportsService extends FinancialReportsService {
  _TenantSwitchFinancialReportsService(super.databaseService);

  final Completer<List<MonthlyIncomeExpensePoint>> _tenantBSeries =
      Completer<List<MonthlyIncomeExpensePoint>>();
  final Completer<List<PeriodDetailItem>> _tenantBExpenses =
      Completer<List<PeriodDetailItem>>();
  int seriesRequests = 0;
  int breakdownRequests = 0;

  @override
  Future<List<MonthlyIncomeExpensePoint>> getIncomeExpenseTimeseries({
    int months = 12,
    bool isCashFlow = false,
  }) {
    seriesRequests++;
    if (seriesRequests == 1) {
      return Future.value(_sampleSeries(income: 100000));
    }
    return _tenantBSeries.future;
  }

  @override
  Future<List<PeriodDetailItem>> getExpensePeriodDetails({
    required DateTime startDate,
    required DateTime endDate,
    bool isCashFlow = false,
  }) {
    breakdownRequests++;
    if (breakdownRequests == 1) {
      return Future.value(_sampleExpenses());
    }
    return _tenantBExpenses.future;
  }

  void completeTenantB() {
    _tenantBSeries.complete(_sampleSeries(income: 200000));
    _tenantBExpenses.complete(_sampleExpenses());
  }
}

List<MonthlyIncomeExpensePoint> _sampleSeries({required double income}) {
  return [
    MonthlyIncomeExpensePoint(
      periodStart: DateTime(2026, 7, 1),
      periodEnd: DateTime(2026, 7, 31),
      income: income,
      expense: 90000,
    ),
  ];
}

List<PeriodDetailItem> _sampleExpenses() {
  return [
    PeriodDetailItem(
      id: 'expense-1',
      documentNumber: 'GTO-1',
      description: 'Arriendo',
      secondaryText: 'Arriendo de Locales',
      amount: 90000,
      transactionDate: DateTime(2026, 7, 10),
      sourceType: 'expense',
      accountId: 'account-1',
      accountCode: '6201',
    ),
  ];
}

class _WidgetFakeRealtimeTransport
    implements FinancialProjectionRealtimeTransport {
  void Function(Map<String, dynamic> value)? _onEvent;

  @override
  Future<FinancialProjectionRealtimeSubscription> subscribe({
    required String tenantId,
    required void Function(Map<String, dynamic> value) onEvent,
    required void Function(
      FinancialProjectionRealtimeStatus status,
      Object? error,
    ) onStatus,
  }) async {
    _onEvent = onEvent;
    return _WidgetFakeRealtimeSubscription();
  }

  void emit(Map<String, dynamic> envelope) {
    final onEvent = _onEvent;
    if (onEvent == null) {
      throw StateError('Realtime transport has no active subscription');
    }
    onEvent(envelope);
  }
}

class _WidgetFakeRealtimeSubscription
    implements FinancialProjectionRealtimeSubscription {
  @override
  Future<void> cancel() async {}
}

class _DelayedCancellationRealtimeTransport
    implements FinancialProjectionRealtimeTransport {
  final List<_DelayedCancellationRealtimeSubscription> subscriptions = [];

  @override
  Future<FinancialProjectionRealtimeSubscription> subscribe({
    required String tenantId,
    required void Function(Map<String, dynamic> value) onEvent,
    required void Function(
      FinancialProjectionRealtimeStatus status,
      Object? error,
    ) onStatus,
  }) async {
    final subscription = _DelayedCancellationRealtimeSubscription();
    subscriptions.add(subscription);
    return subscription;
  }
}

class _DelayedCancellationRealtimeSubscription
    implements FinancialProjectionRealtimeSubscription {
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
    await _cancelGate?.future;
  }
}
