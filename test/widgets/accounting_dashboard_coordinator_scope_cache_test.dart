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

  testWidgets(
    'a new coordinator and tenant cannot reuse the prior static cache',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final database = DatabaseService();
      final reports = _ScopeSwapFinancialReportsService(database);
      final tenantA = FinancialProjectionRefreshCoordinator();
      final tenantB = FinancialProjectionRefreshCoordinator();
      addTearDown(database.dispose);
      addTearDown(reports.dispose);
      addTearDown(tenantA.dispose);
      addTearDown(tenantB.dispose);

      await tenantA.synchronizeTenant('tenant-a');
      await tenantB.synchronizeTenant('tenant-b');

      await _pumpDashboard(
        tester,
        reports: reports,
        coordinator: tenantA,
      );
      await tester.pumpAndSettle();

      expect(reports.seriesRequests, 1);
      expect(reports.breakdownRequests, 1);
      expect(find.text('Ingresos vs gastos'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpDashboard(
        tester,
        reports: reports,
        coordinator: tenantB,
      );
      await tester.pump();

      expect(reports.seriesRequests, 2);
      expect(reports.breakdownRequests, 2);
      expect(
        find.text('Ingresos vs gastos'),
        findsNothing,
        reason: 'Equal revision numbers do not make different scopes reusable.',
      );

      reports.completeTenantB();
      await tester.pumpAndSettle();

      expect(find.text('Ingresos vs gastos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required FinancialReportsService reports,
  required FinancialProjectionRefreshCoordinator coordinator,
}) {
  return tester.pumpWidget(
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
}

class _ScopeSwapFinancialReportsService extends FinancialReportsService {
  _ScopeSwapFinancialReportsService(super.databaseService);

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
      return Future.value(_series(100000));
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
      return Future.value(_expenses);
    }
    return _tenantBExpenses.future;
  }

  void completeTenantB() {
    _tenantBSeries.complete(_series(200000));
    _tenantBExpenses.complete(_expenses);
  }
}

List<MonthlyIncomeExpensePoint> _series(double income) {
  return [
    MonthlyIncomeExpensePoint(
      periodStart: DateTime(2026, 7, 1),
      periodEnd: DateTime(2026, 7, 31),
      income: income,
      expense: 90000,
    ),
  ];
}

final _expenses = [
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
