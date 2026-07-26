import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String authServiceSource;
  late String routerSource;
  late String resetPageSource;
  late String loginPageSource;

  setUpAll(() {
    authServiceSource =
        File('lib/shared/services/auth_service.dart').readAsStringSync();
    routerSource = File('lib/shared/routes/app_router.dart').readAsStringSync();
    resetPageSource = File(
      'lib/modules/worker_portal/pages/worker_password_reset_page.dart',
    ).readAsStringSync();
    loginPageSource = File(
      'lib/modules/worker_portal/pages/worker_login_page.dart',
    ).readAsStringSync();
  });

  test('worker context exposes and enforces the mandatory reset flag', () {
    expect(authServiceSource, contains("account['mustResetPassword'] == true"));
    expect(routerSource, contains("path: '/worker/password-reset'"));
    expect(routerSource, contains('authService.workerMustResetPassword'));
    expect(
      routerSource,
      contains("return '/worker/password-reset';"),
    );
  });

  test('worker login delegates synthetic identity resolution to the edge', () {
    final methodStart =
        authServiceSource.indexOf('Future<User> signInWorkerWithUsername');
    final methodEnd =
        authServiceSource.indexOf('Future<AuthResponse> signUpTenantOwner');
    expect(methodStart, greaterThanOrEqualTo(0));
    expect(methodEnd, greaterThan(methodStart));
    final workerLoginSource =
        authServiceSource.substring(methodStart, methodEnd);

    expect(workerLoginSource, contains("'worker-login'"));
    expect(workerLoginSource, contains("'tenant': tenant.trim()"));
    expect(workerLoginSource, contains("'username': username.trim()"));
    expect(workerLoginSource, contains("'password': password"));
    expect(workerLoginSource, contains("data['success'] != true"));
    expect(workerLoginSource, contains("data['refreshToken']"));
    expect(workerLoginSource, contains('auth.setSession(refreshToken)'));
    expect(workerLoginSource, contains('await _loadAccessProfiles()'));
    expect(workerLoginSource, isNot(contains('resolve_worker_login')));
    expect(workerLoginSource, isNot(contains('signInWithPassword')));
    expect(workerLoginSource, isNot(contains('loginEmail')));
    expect(workerLoginSource, isNot(contains('debugPrint')));
    expect(workerLoginSource, isNot(contains(r'$password')));
    expect(workerLoginSource, isNot(contains(r'$username')));
  });

  test('worker password rotation uses strong policy and server completion RPC',
      () {
    expect(
      resetPageSource,
      contains('validateAdminManagedPassword'),
    );
    expect(
      resetPageSource,
      contains('authService.completeWorkerPasswordReset('),
    );
    expect(resetPageSource, contains('await authService.signOut()'));
    expect(
      resetPageSource,
      contains("context.go('/worker/login?password_reset=complete')"),
    );

    final beginIndex = authServiceSource.indexOf(
      "'begin_my_worker_password_reset'",
    );
    final updateIndex =
        authServiceSource.indexOf('UserAttributes(password: newPassword)');
    final completionIndex = authServiceSource.indexOf(
      "'complete_my_worker_password_reset'",
    );
    expect(beginIndex, greaterThanOrEqualTo(0));
    expect(updateIndex, greaterThan(beginIndex));
    expect(completionIndex, greaterThan(updateIndex));
    expect(loginPageSource, isNot(contains(r'$error')));
  });
}
