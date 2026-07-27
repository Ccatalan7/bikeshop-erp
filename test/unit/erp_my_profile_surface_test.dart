import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ERP self profile is one canonical scoped surface', () {
    final router = File('lib/shared/routes/app_router.dart').readAsStringSync();
    final barrel =
        File('lib/shared/routes/erp_routes_barrel.dart').readAsStringSync();
    final layout =
        File('lib/shared/widgets/main_layout.dart').readAsStringSync();
    final settings = File('lib/modules/settings/pages/settings_page.dart')
        .readAsStringSync();
    final dashboard =
        File('lib/shared/screens/dashboard_screen.dart').readAsStringSync();
    final service = File(
      'lib/shared/services/current_user_profile_service.dart',
    ).readAsStringSync();
    final password = File('lib/shared/services/self_password_service.dart')
        .readAsStringSync();

    expect(router, contains("path: '/profile'"));
    expect(router, contains('erp.MyProfilePage()'));
    expect(barrel, contains("export '../pages/my_profile_page.dart';"));
    expect(layout, contains('CurrentUserProfileTile'));
    expect(layout, contains("'/profile'"));
    expect(settings, contains('CurrentUserProfileService'));
    expect(settings, isNot(contains(".from('user_profiles')")));
    expect(dashboard, contains('profile.displayName'));
    expect(service, contains("rpc('get_my_erp_profile')"));
    expect(service, contains("'update_my_employee_contact'"));
    expect(service, contains("'emergency_contact_phone'"));
    expect(password, contains('reauthenticate()'));
    expect(password, contains('nonce:'));
    expect(password, contains('SignOutScope.others'));
  });
}
