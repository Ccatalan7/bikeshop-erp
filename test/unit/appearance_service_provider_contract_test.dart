import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('root binds AppearanceService to canonical Auth and Tenant providers',
      () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains(
        'ChangeNotifierProxyProvider2<AuthService, TenantService,\n'
        '            AppearanceService>',
      ),
    );
    expect(source, contains('service.synchronize('));
    expect(source, contains('userId: authService.currentUser?.id'));
    expect(source, contains('resolveTenantId: tenantService.getTenantId'));
    expect(
      source,
      isNot(contains(
        'ChangeNotifierProvider(create: (_) => AppearanceService())',
      )),
    );
  });

  test('AppearanceService does not own a second Supabase auth subscription',
      () {
    final source = File(
      'lib/modules/settings/services/appearance_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('onAuthStateChange.listen')));
    expect(source, isNot(contains('StreamSubscription<AuthState>')));
    expect(source, contains('final generation = ++_synchronizationGeneration'));
    expect(source, contains('ErpAuthorityScopeKey.from('));
  });
}
