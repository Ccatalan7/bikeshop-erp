import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/user_management_service.dart';

void main() {
  test('employee detail owns the complete worker access lifecycle', () {
    final page = File(
      'lib/modules/hr/pages/employee_detail_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/shared/services/user_management_service.dart',
    ).readAsStringSync();

    for (final action in [
      'Crear acceso',
      'Restablecer contraseña',
      'Suspender acceso',
      'Reactivar acceso',
    ]) {
      expect(page, contains(action));
    }
    expect(page, contains('Acceso requiere reparación'));
    expect(page, contains('access.identityHealthy'));
    expect(page, contains('getWorkerPortalAccess'));
    expect(page, contains('resetWorkerPortalPassword'));
    expect(page, contains('setWorkerPortalAccess'));

    expect(service, contains("'action': 'get_worker_portal_access'"));
    expect(service, contains('identityHealthy is! bool'));
    expect(service, isNot(contains("'loginEmail'")));
    expect(service, isNot(contains("'authUserId'")));
  });

  test('worker access projection rejects corrupt operational evidence', () {
    final valid = <String, dynamic>{
      'employeeId': 'employee-1',
      'hasAccess': true,
      'username': 'mecanico',
      'isActive': true,
      'mustResetPassword': false,
      'lastLoginAt': '2026-07-26T12:00:00.000Z',
      'identityHealthy': true,
    };

    expect(
      WorkerPortalAccessState.fromJson(valid).lastLoginAt,
      DateTime.utc(2026, 7, 26, 12),
    );
    expect(
      () => WorkerPortalAccessState.fromJson({
        ...valid,
        'lastLoginAt': 'not-a-date',
      }),
      throwsFormatException,
    );
    expect(
      () => WorkerPortalAccessState.fromJson({
        ...valid,
        'identityHealthy': null,
      }),
      throwsFormatException,
    );
  });
}
