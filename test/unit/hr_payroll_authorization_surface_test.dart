import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every protected HR route is gated before its body is constructed', () {
    final routes = File('lib/shared/routes/app_router.dart').readAsStringSync();

    expect(
      RegExp(r'area: ErpAuthorizationArea\.hrManagement')
          .allMatches(routes)
          .length,
      7,
    );
    expect(
      RegExp(r'area: ErpAuthorizationArea\.payroll').allMatches(routes).length,
      2,
    );
    expect(
      routes,
      contains('erp.PayrollRedesignRoute('),
      reason: 'Accounting authority must reach the real payroll workspace.',
    );
    expect(
      routes,
      contains('child: erp.PayrollReconciliationPage()'),
      reason: 'The reconciliation route must share accounting authority.',
    );
    for (final path in const [
      '/hr/employees',
      '/hr/employees/:id',
      '/hr/planning',
      '/hr/attendances',
      '/hr/kiosk',
      '/hr/medical-leaves',
      '/hr/contracts',
      '/hr/payroll',
      '/hr/payroll/reconcile',
    ]) {
      expect(routes, contains("path: '$path'"));
    }

    final profileRouteStart = routes.indexOf("path: '/profile'");
    final nextRouteStart = routes.indexOf('GoRoute(', profileRouteStart + 1);
    final profileRoute = routes.substring(profileRouteStart, nextRouteStart);
    expect(profileRoute, isNot(contains('ErpAuthorizationGate')));
  });

  test('ordinary coworker consumers use only the redacted directory', () {
    final newChat = File(
      'lib/modules/messaging/widgets/new_chat_dialog.dart',
    ).readAsStringSync();
    final notifications = File(
      'lib/shared/services/notification_service.dart',
    ).readAsStringSync();
    final preload = File(
      'lib/shared/services/data_preload_service.dart',
    ).readAsStringSync();
    final directory = File(
      'lib/shared/services/erp_employee_directory_service.dart',
    ).readAsStringSync();
    final chatPrincipalDirectory = File(
      'lib/shared/services/erp_chat_principal_directory_service.dart',
    ).readAsStringSync();

    expect(newChat, contains('ErpEmployeeDirectoryService'));
    expect(newChat, contains('ErpChatPrincipalDirectoryService'));
    expect(preload, contains('ErpEmployeeDirectoryService'));
    expect(notifications, contains('ErpEmployeeDirectoryService'));
    expect(directory, contains("rpc('get_erp_employee_directory')"));
    expect(
      chatPrincipalDirectory,
      contains("rpc('get_erp_chat_principal_directory')"),
    );

    expect(newChat, isNot(contains('getTenantUsers')));
    expect(newChat, isNot(contains('getEmployees(')));
    expect(chatPrincipalDirectory, isNot(contains(".from('auth.users')")));
    expect(chatPrincipalDirectory, isNot(contains(".from('user_profiles')")));
    expect(preload, isNot(contains('getEmployees(')));
    expect(notifications, isNot(contains(".from('employees')")));
    expect(notifications, isNot(contains(".from('user_profiles')")));
  });

  test('desktop, compact, and reorder menus share the permission split', () {
    final shell =
        File('lib/shared/widgets/main_layout.dart').readAsStringSync();

    expect(shell, contains('if (profile.canManageUsers)'));
    expect(shell, contains('if (profile.canAccessAccounting)'));
    expect(
      RegExp(r'resolveOrderedAppModules\(context\)').allMatches(shell).length,
      3,
      reason: 'Sidebar, rail, and compact drawer must consume one projection.',
    );
    expect(shell, contains('if (visibleHrItems.isNotEmpty)'));
    expect(
      shell,
      contains('items: visibleHrItems'),
    );
    expect(
      shell,
      contains(".where((moduleKey) => moduleKey != 'hr' || canSeeHr)"),
    );
  });

  test('embedded attendance and kiosk actions share route authority', () {
    final attendances = File(
      'lib/modules/hr/pages/attendances_page.dart',
    ).readAsStringSync();
    final toolbar =
        File('lib/shared/widgets/right_toolbar.dart').readAsStringSync();
    final compactShell =
        File('lib/shared/widgets/main_layout.dart').readAsStringSync();
    final toolProjection = File(
      'lib/shared/widgets/toolbar_tool_presentation.dart',
    ).readAsStringSync();
    final compactActions = File(
      'lib/modules/hr/widgets/attendance_compact_actions.dart',
    ).readAsStringSync();

    expect(attendances, contains('canAccessPayroll'));
    expect(attendances, contains('canAccessPayroll: canAccessPayroll'));
    expect(attendances, contains('PayrollGenerationSurface('));
    expect(attendances, contains('onGeneratePayroll: _openPayrollGeneration'));
    expect(
      attendances,
      contains('service.saveDraft('),
      reason: 'Attendance must persist the reviewed editable snapshot.',
    );
    expect(
      attendances,
      contains('applyPayrollGenerationPreviewToVoucher('),
      reason: 'The full voucher must retain payment/account metadata.',
    );
    expect(
      attendances,
      isNot(contains("widgets/payroll_voucher_dialog.dart")),
      reason: 'Attendance must not construct the legacy payroll writer.',
    );
    expect(compactActions, contains('if (canAccessPayroll)'));
    expect(compactActions, contains("text: 'Preparar nómina'"));
    expect(toolbar, contains('profileService.profile?.canManageUsers == true'));
    expect(toolbar, contains('resolveVisibleToolbarTools('));
    expect(compactShell, contains('resolveVisibleToolbarTools('));
    expect(
      toolProjection,
      contains('if (tool == ToolbarTool.kiosk) return canManageHr;'),
    );
  });
}
