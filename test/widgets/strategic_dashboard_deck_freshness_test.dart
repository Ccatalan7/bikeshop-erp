import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/accounting/models/dashboard_metrics.dart';
import 'package:vinabike_erp/modules/accounting/services/financial_projection_refresh_coordinator.dart';
import 'package:vinabike_erp/modules/accounting/services/financial_reports_service.dart';
import 'package:vinabike_erp/modules/accounting/widgets/accounting_dashboard_section.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/widgets/strategic_dashboard_deck.dart';

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

  for (final panel in _strategicPanels) {
    testWidgets(
      '${panel.title} refreshes loaded metrics once for coalesced hints',
      (tester) async {
        _setDesktopViewport(tester);
        final database = _ControlledStrategicDatabaseService();
        final reports = _ImmediateFinancialReportsService(database);
        final coordinator = FinancialProjectionRefreshCoordinator(
          coalesceWindow: const Duration(milliseconds: 10),
        );
        addTearDown(database.dispose);
        addTearDown(reports.dispose);
        addTearDown(coordinator.dispose);

        await _pumpDeck(
          tester,
          database: database,
          reports: reports,
          coordinator: coordinator,
        );
        await _openLoadedPanel(
          tester,
          database: database,
          panel: panel,
          marker: 101,
        );

        coordinator
          ..recordCommitted(
            const FinancialProjectionChange(
              kind: FinancialProjectionChangeKind.salesInvoice,
              origin: FinancialProjectionChangeOrigin.localCommit,
              entityId: 'sale-coalesced',
            ),
          )
          ..recordCommitted(
            const FinancialProjectionChange(
              kind: FinancialProjectionChangeKind.expense,
              origin: FinancialProjectionChangeOrigin.localCommit,
              entityId: 'expense-coalesced',
            ),
          );
        await tester.pump(const Duration(milliseconds: 11));

        expect(database.requestCount, 2);
        expect(
          find.text(panel.markerText(101)),
          findsOneWidget,
          reason: 'The last valid snapshot stays visible during refresh.',
        );

        database.completeRequest(1, marker: 202);
        await tester.pumpAndSettle();

        expect(database.requestCount, 2);
        expect(find.text(panel.markerText(101)), findsNothing);
        expect(find.text(panel.markerText(202)), findsOneWidget);
        expect(find.text(panel.title), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${panel.title} clears the old tenant before loading the new scope',
      (tester) async {
        _setDesktopViewport(tester);
        final database = _ControlledStrategicDatabaseService();
        final reports = _ImmediateFinancialReportsService(database);
        final coordinator = FinancialProjectionRefreshCoordinator(
          coalesceWindow: const Duration(milliseconds: 10),
        );
        addTearDown(database.dispose);
        addTearDown(reports.dispose);
        addTearDown(coordinator.dispose);

        await coordinator.synchronizeTenant('tenant-a');
        await _pumpDeck(
          tester,
          database: database,
          reports: reports,
          coordinator: coordinator,
        );
        await _openLoadedPanel(
          tester,
          database: database,
          panel: panel,
          marker: 303,
        );

        await coordinator.synchronizeTenant('tenant-b');
        await tester.pump();

        expect(database.requestCount, 2);
        expect(
          find.text(panel.markerText(303)),
          findsNothing,
          reason: 'A tenant-scoped snapshot must never cross the scope switch.',
        );
        expect(
          find.text('Calculando indicadores con datos operacionales…'),
          findsOneWidget,
        );

        database.completeRequest(1, marker: 404);
        await tester.pumpAndSettle();

        expect(find.text(panel.markerText(404)), findsOneWidget);
        expect(find.text(panel.title), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a pending financial refresh runs when navigating panel 1 to panel 2',
    (tester) async {
      _setDesktopViewport(tester);
      final database = _ControlledStrategicDatabaseService();
      final reports = _ImmediateFinancialReportsService(database);
      final coordinator = FinancialProjectionRefreshCoordinator(
        coalesceWindow: const Duration(milliseconds: 10),
      );
      addTearDown(database.dispose);
      addTearDown(reports.dispose);
      addTearDown(coordinator.dispose);

      await _pumpDeck(
        tester,
        database: database,
        reports: reports,
        coordinator: coordinator,
      );
      await _openLoadedPanel(
        tester,
        database: database,
        panel: _strategicPanels.first,
        marker: 808,
      );

      await tester.tap(find.byTooltip('Panel anterior'));
      await tester.pumpAndSettle();
      expect(find.text('Panorama financiero'), findsOneWidget);

      coordinator.recordCommitted(
        const FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.salesInvoice,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: 'sale-while-panel-one',
          eventId: 'sale-while-panel-one-commit',
        ),
      );
      await tester.pump(const Duration(milliseconds: 11));
      expect(database.requestCount, 1);

      await tester.tap(find.byTooltip('Panel siguiente'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(database.requestCount, 2);
      expect(
        find.text('808'),
        findsOneWidget,
        reason: 'Navigation keeps the last snapshot while its refresh runs.',
      );

      database.completeRequest(1, marker: 909);
      await tester.pumpAndSettle();

      expect(find.text('808'), findsNothing);
      expect(find.text('909'), findsOneWidget);
      expect(find.text('Flujo del taller'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden work is deferred and disposed work cannot publish or race',
    (tester) async {
      _setDesktopViewport(tester);
      final database = _ControlledStrategicDatabaseService();
      final reports = _ImmediateFinancialReportsService(database);
      final coordinator = FinancialProjectionRefreshCoordinator(
        coalesceWindow: const Duration(milliseconds: 10),
      );
      final visible = ValueNotifier<bool>(true);
      addTearDown(database.dispose);
      addTearDown(reports.dispose);
      addTearDown(coordinator.dispose);
      addTearDown(visible.dispose);

      await _pumpDeck(
        tester,
        database: database,
        reports: reports,
        coordinator: coordinator,
        visible: visible,
      );
      await _openLoadedPanel(
        tester,
        database: database,
        panel: _strategicPanels.first,
        marker: 505,
      );

      visible.value = false;
      await tester.pump();
      coordinator.recordCommitted(
        const FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.salesPayment,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: 'payment-hidden',
        ),
      );
      await tester.pump(const Duration(milliseconds: 11));

      expect(database.requestCount, 1);

      visible.value = true;
      await tester.pump();
      await tester.pump();
      expect(database.requestCount, 2);

      database.completeRequest(1, marker: 606);
      await tester.pumpAndSettle();
      expect(find.text('606'), findsOneWidget);

      coordinator.recordCommitted(
        const FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.expensePayment,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: 'expense-payment-dispose',
        ),
      );
      await tester.pump(const Duration(milliseconds: 11));
      expect(database.requestCount, 3);

      await tester.pumpWidget(const SizedBox.shrink());
      database.completeRequest(2, marker: 707);
      await tester.pump();
      expect(tester.takeException(), isNull);

      coordinator.recordCommitted(
        const FinancialProjectionChange(
          kind: FinancialProjectionChangeKind.payroll,
          origin: FinancialProjectionChangeOrigin.localCommit,
          entityId: 'payroll-after-dispose',
        ),
      );
      await tester.pump(const Duration(milliseconds: 11));

      expect(database.requestCount, 3);
      expect(tester.takeException(), isNull);
    },
  );
}

const _strategicPanels = <_StrategicPanel>[
  _StrategicPanel(
    index: 1,
    title: 'Flujo del taller',
    markerText: _activeJobsMarker,
  ),
  _StrategicPanel(
    index: 2,
    title: 'Capacidad y servicio',
    markerText: _mechanicsMarker,
  ),
  _StrategicPanel(
    index: 3,
    title: 'Productos y rotación',
    markerText: _unitsMarker,
  ),
];

String _activeJobsMarker(int marker) => '$marker';
String _mechanicsMarker(int marker) =>
    '$marker mecánicos activos · presencia / horario abierto';
String _unitsMarker(int marker) => '$marker unidades vendidas';

class _StrategicPanel {
  const _StrategicPanel({
    required this.index,
    required this.title,
    required this.markerText,
  });

  final int index;
  final String title;
  final String Function(int) markerText;
}

void _setDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpDeck(
  WidgetTester tester, {
  required _ControlledStrategicDatabaseService database,
  required FinancialReportsService reports,
  required FinancialProjectionRefreshCoordinator coordinator,
  ValueListenable<bool>? visible,
}) async {
  final deck = StrategicDashboardDeck(
    financialProjectionRefresh: coordinator,
  );
  final child = visible == null
      ? deck
      : ValueListenableBuilder<bool>(
          valueListenable: visible,
          child: deck,
          builder: (context, enabled, child) => TickerMode(
            enabled: enabled,
            child: child!,
          ),
        );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<DatabaseService>.value(value: database),
        ChangeNotifierProvider<FinancialReportsService>.value(value: reports),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openLoadedPanel(
  WidgetTester tester, {
  required _ControlledStrategicDatabaseService database,
  required _StrategicPanel panel,
  required int marker,
}) async {
  await tester.tap(find.byTooltip('Panel siguiente'));
  await tester.pump();
  expect(database.requestCount, 1);

  database.completeRequest(0, marker: marker);
  await tester.pumpAndSettle();

  for (var index = 1; index < panel.index; index++) {
    await tester.tap(find.byTooltip('Panel siguiente'));
    await tester.pumpAndSettle();
  }

  expect(find.text(panel.title), findsOneWidget);
  expect(find.text(panel.markerText(marker)), findsOneWidget);
}

class _ImmediateFinancialReportsService extends FinancialReportsService {
  _ImmediateFinancialReportsService(super.databaseService);

  @override
  Future<List<MonthlyIncomeExpensePoint>> getIncomeExpenseTimeseries({
    int months = 12,
    bool isCashFlow = false,
  }) async {
    return [
      MonthlyIncomeExpensePoint(
        periodStart: DateTime(2026, 7, 1),
        periodEnd: DateTime(2026, 7, 31),
        income: 180000,
        expense: 90000,
      ),
    ];
  }

  @override
  Future<List<PeriodDetailItem>> getExpensePeriodDetails({
    required DateTime startDate,
    required DateTime endDate,
    bool isCashFlow = false,
  }) async {
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
}

class _ControlledStrategicDatabaseService extends DatabaseService {
  final List<Completer<dynamic>> _requests = [];

  int get requestCount => _requests.length;

  @override
  Future<dynamic> rpc(
    String functionName, {
    Map<String, dynamic>? params,
  }) {
    if (functionName != 'get_strategic_dashboard_metrics') {
      throw StateError('Unexpected dashboard RPC: $functionName');
    }
    final request = Completer<dynamic>();
    _requests.add(request);
    return request.future;
  }

  void completeRequest(int index, {required int marker}) {
    _requests[index].complete(_strategicMetrics(marker));
  }
}

Map<String, dynamic> _strategicMetrics(int marker) {
  return {
    'period': {
      'start': '2026-05-01',
      'end': '2026-07-31',
      'days': 92,
    },
    'flow': {
      'approvalMedianHours': 2,
      'approvalSamples': marker,
      'startMedianHours': 3,
      'startSamples': marker,
      'executionMedianHours': 5,
      'executionSamples': marker,
      'totalMedianHours': 10,
      'totalSamples': marker,
      'deliveredCount': marker,
      'onTimeRate': 0.8,
      'onTimeSamples': marker,
      'approvalRate': 0.75,
      'decisionSamples': marker,
    },
    'load': {
      'activeCount': marker,
      'overdueCount': 0,
      'ageBuckets': const <dynamic>[],
    },
    'value': {
      'netSales': marker * 1000,
      'averageTicket': 1000,
      'invoiceCount': marker,
      'serviceSales': marker * 400,
      'productSales': marker * 600,
      'unclassifiedSales': 0,
      'serviceSalesShare': 0.4,
      'productSalesShare': 0.6,
      'classificationCoverageRate': 1,
      'workshopServiceSales': marker * 300,
      'workshopProductSales': marker * 200,
      'workshopUnclassifiedSales': 0,
      'productCostCoverageRate': 1,
      'productCogs': marker * 200,
      'productGrossContribution': marker * 400,
      'productGrossMarginRate': 0.66,
      'actualHours': 8,
      'actualHoursJobs': marker,
      'laborHourCoverageRate': 1,
      'netSalesPerLaborHour': 1000,
      'estimateAccuracyRate': 0.9,
      'estimateSamples': marker,
      'businessOpenHours': 8,
      'mechanicAttendanceHours': 8,
      'mechanicCount': marker,
      'mechanicEquivalentCoverage': 1,
      'productiveUtilizationRate': 1,
      'netSalesPerAttendanceHour': 1000,
      'serviceSalesPerAttendanceHour': 500,
      'paidMechanicCost': 100,
      'pendingMechanicCost': 0,
      'attendanceEstimatedMechanicCost': 100,
      'mechanicCostSource': 'paid_payroll',
      'mechanicCostUsed': 100,
      'laborContribution': marker * 300,
      'laborContributionRate': 0.75,
      'jobAssignmentCoverageRate': 1,
    },
    'inventory': {
      'soldProducts': marker,
      'unitsSold': marker,
      'stockCoverDays': 10,
      'stagnantProductCount': 0,
      'stagnantStockValue': 0,
      'topProducts': const <dynamic>[],
    },
    'weekly': const <dynamic>[],
  };
}
