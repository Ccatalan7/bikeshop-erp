// C1 (2026-09-30): el dashboard de un mecánico mostraba el panorama
// financiero como error crudo — «PostgrestException(message: Accounting access
// denied, code: 42501…)» — con un «Reintentar» que nunca funciona. La base
// niega bien (can_manage_tenant_accounting); el panel no debe pedir lo que el
// rol no ve ni mostrar la excepción. La caché estática es de un actor: lo que
// cargó un administrador no se le sirve a un mecánico en el mismo equipo, y
// una negativa se reabre cuando el panel recibe autoridad.
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
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
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
        (request) async => http.Response('[]', 200,
            headers: const {'content-type': 'application/json'},
            request: request),
      ),
    );
  });

  setUp(AccountingDashboardSection.invalidateCache);

  _ReportsService newReports({bool allow = false}) {
    final database = DatabaseService();
    final reports = _ReportsService(database, allow: allow);
    addTearDown(reports.dispose);
    addTearDown(database.dispose);
    return reports;
  }

  Future<_ReportsService> pumpSection(
    WidgetTester tester, {
    CurrentUserProfileService? profiles,
    _ReportsService? reports,
  }) async {
    reports ??= newReports();
    Widget child = ChangeNotifierProvider<FinancialReportsService>.value(
      value: reports,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AccountingDashboardSection()),
        ),
      ),
    );
    if (profiles != null) {
      child = ChangeNotifierProvider<CurrentUserProfileService>.value(
          value: profiles, child: child);
    }
    await tester.pumpWidget(child);
    await tester.pumpAndSettle();
    return reports;
  }

  void expectNoAccessState() {
    expect(find.byKey(const ValueKey('accounting-dashboard-no-access')),
        findsOneWidget);
    expect(find.textContaining('PostgrestException'), findsNothing);
    expect(find.textContaining('42501'), findsNothing);
    expect(find.text('Reintentar'), findsNothing);
  }

  testWidgets('a mechanic is told who sees it and nothing is requested',
      (tester) async {
    final profiles = _ProfileService(_mechanic);
    addTearDown(profiles.dispose);

    final reports = await pumpSection(tester, profiles: profiles);

    expectNoAccessState();
    expect(reports.requests, 0);
  });

  testWidgets('a server 42501 without a known profile ends the same way',
      (tester) async {
    final reports = await pumpSection(tester);

    expectNoAccessState();
    expect(reports.requests, greaterThan(0));
  });

  testWidgets('an admin cache is not served to a mechanic on the same device',
      (tester) async {
    final reports = newReports(allow: true);
    final admin = _ProfileService(_admin);
    addTearDown(admin.dispose);
    await pumpSection(tester, profiles: admin, reports: reports);
    expect(find.text('Ingresos vs gastos'), findsOneWidget);
    final adminRequests = reports.requests;

    await tester.pumpWidget(const SizedBox.shrink());
    final mechanic = _ProfileService(_mechanic);
    addTearDown(mechanic.dispose);
    await pumpSection(tester, profiles: mechanic, reports: reports);

    expectNoAccessState();
    expect(find.text('Ingresos vs gastos'), findsNothing);
    expect(reports.requests, adminRequests);
  });

  testWidgets('a denial reopens when the panel gets accounting authority',
      (tester) async {
    final reports = newReports();
    final profiles = _ProfileService(null);
    addTearDown(profiles.dispose);
    await pumpSection(tester, profiles: profiles, reports: reports);
    expectNoAccessState();

    reports.allow = true;
    profiles.become(_admin);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('accounting-dashboard-no-access')),
        findsNothing);
    expect(find.text('Ingresos vs gastos'), findsOneWidget);
  });
}

CurrentUserProfile _profile(String userId, String role) => CurrentUserProfile(
      userId: userId,
      email: '$userId@example.invalid',
      emailVerified: true,
      displayName: userId,
      tenantId: 'tenant-test',
      tenantName: 'Taller',
      tenantSubdomain: null,
      role: role,
      permissions: const {},
      employeeLinkState: EmployeeLinkState.unlinked,
      employee: null,
    );

final _admin = _profile('user-admin', 'admin');
final _mechanic = _profile('user-mechanic', 'mechanic');

class _ProfileService extends CurrentUserProfileService {
  _ProfileService(this._current);

  CurrentUserProfile? _current;

  @override
  CurrentUserProfile? get profile => _current;

  void become(CurrentUserProfile next) {
    _current = next;
    notifyListeners();
  }
}

/// Niega como la base (42501) hasta que `allow` la deja responder.
class _ReportsService extends FinancialReportsService {
  _ReportsService(super.databaseService, {required this.allow});

  bool allow;
  int requests = 0;

  void _check() {
    requests++;
    if (allow) return;
    throw const PostgrestException(
      message: 'Accounting access denied',
      code: '42501',
      details: 'Forbidden',
    );
  }

  @override
  Future<List<MonthlyIncomeExpensePoint>> getIncomeExpenseTimeseries({
    int months = 12,
    bool isCashFlow = false,
  }) async {
    _check();
    return [
      MonthlyIncomeExpensePoint(
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 30),
        income: 1250000,
        expense: 480000,
      ),
    ];
  }

  @override
  Future<List<PeriodDetailItem>> getExpensePeriodDetails({
    required DateTime startDate,
    required DateTime endDate,
    bool isCashFlow = false,
  }) async {
    _check();
    return [
      PeriodDetailItem(
        id: 'expense-1',
        documentNumber: 'GTO-1',
        description: 'Arriendo',
        secondaryText: 'Arriendo de Locales',
        amount: 480000,
        transactionDate: DateTime(2026, 9, 5),
        sourceType: 'expense',
        accountId: 'account-1',
        accountCode: '6201',
      ),
    ];
  }
}
