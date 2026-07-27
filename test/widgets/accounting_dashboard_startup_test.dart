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

  for (final viewport in <({double width, double height, double textScale})>[
    (width: 384, height: 824, textScale: 1),
    (width: 599, height: 900, textScale: 1),
    (width: 600, height: 900, textScale: 1),
    (width: 899, height: 900, textScale: 1),
    (width: 900, height: 900, textScale: 1),
    (width: 1440, height: 900, textScale: 1),
    (width: 384, height: 824, textScale: 1.3),
  ]) {
    testWidgets(
      'starts both chart reads and renders at '
      '${viewport.width.toInt()}x${viewport.height.toInt()} '
      'with ${viewport.textScale}x text',
      (tester) async {
        tester.view.physicalSize = Size(viewport.width, viewport.height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final database = DatabaseService();
        final reports = _ControlledFinancialReportsService(database);
        addTearDown(reports.dispose);
        addTearDown(database.dispose);

        await tester.pumpWidget(
          ChangeNotifierProvider<FinancialReportsService>.value(
            value: reports,
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(viewport.width, viewport.height),
                  textScaler: TextScaler.linear(viewport.textScale),
                ),
                child: const Scaffold(
                  body: SingleChildScrollView(
                    child: AccountingDashboardSection(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(reports.seriesRequests, 1);
        expect(reports.breakdownRequests, 1);
        expect(find.text('Ingresos vs gastos'), findsNothing);

        reports.completeSeries();
        await tester.pump();
        expect(
          find.text('Ingresos vs gastos'),
          findsNothing,
          reason: 'Both independent projections must be ready before publish.',
        );

        reports.completeBreakdown();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Ingresos vs gastos'), findsOneWidget);
        expect(find.text('Principales egresos de caja'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'does not compete with the first charts for hidden strategic metrics',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final database = _RecordingDatabaseService();
      final reports = _ImmediateFinancialReportsService(database);
      addTearDown(reports.dispose);
      addTearDown(database.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DatabaseService>.value(value: database),
            ChangeNotifierProvider<FinancialReportsService>.value(
              value: reports,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: StrategicDashboardDeck(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(database.strategicMetricsRequests, 0);
      expect(find.text('Ingresos vs gastos'), findsOneWidget);

      await tester.tap(find.byTooltip('Panel siguiente'));
      await tester.pump();

      expect(database.strategicMetricsRequests, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ControlledFinancialReportsService extends FinancialReportsService {
  _ControlledFinancialReportsService(super.databaseService);

  final Completer<List<MonthlyIncomeExpensePoint>> _seriesCompleter =
      Completer<List<MonthlyIncomeExpensePoint>>();
  final Completer<List<PeriodDetailItem>> _breakdownCompleter =
      Completer<List<PeriodDetailItem>>();

  int seriesRequests = 0;
  int breakdownRequests = 0;

  @override
  Future<List<MonthlyIncomeExpensePoint>> getIncomeExpenseTimeseries({
    int months = 12,
    bool isCashFlow = false,
  }) {
    seriesRequests++;
    return _seriesCompleter.future;
  }

  @override
  Future<List<PeriodDetailItem>> getExpensePeriodDetails({
    required DateTime startDate,
    required DateTime endDate,
    bool isCashFlow = false,
  }) {
    breakdownRequests++;
    return _breakdownCompleter.future;
  }

  void completeSeries() {
    _seriesCompleter.complete(_sampleSeries());
  }

  void completeBreakdown() {
    _breakdownCompleter.complete(_sampleExpenses());
  }
}

class _ImmediateFinancialReportsService extends FinancialReportsService {
  _ImmediateFinancialReportsService(super.databaseService);

  @override
  Future<List<MonthlyIncomeExpensePoint>> getIncomeExpenseTimeseries({
    int months = 12,
    bool isCashFlow = false,
  }) async {
    return _sampleSeries();
  }

  @override
  Future<List<PeriodDetailItem>> getExpensePeriodDetails({
    required DateTime startDate,
    required DateTime endDate,
    bool isCashFlow = false,
  }) async {
    return _sampleExpenses();
  }
}

class _RecordingDatabaseService extends DatabaseService {
  int strategicMetricsRequests = 0;

  @override
  Future<dynamic> rpc(
    String functionName, {
    Map<String, dynamic>? params,
  }) async {
    if (functionName != 'get_strategic_dashboard_metrics') {
      throw StateError('Unexpected dashboard RPC: $functionName');
    }
    strategicMetricsRequests++;
    return const <String, dynamic>{};
  }
}

List<MonthlyIncomeExpensePoint> _sampleSeries() {
  return [
    MonthlyIncomeExpensePoint(
      periodStart: DateTime(2026, 7, 1),
      periodEnd: DateTime(2026, 7, 31),
      income: 180000,
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
