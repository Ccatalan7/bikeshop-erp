import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all ERP profile entry points delegate to the adaptive owner', () {
    final helper = File(
      'lib/shared/services/current_user_profile_navigation.dart',
    ).readAsStringSync();
    final layout =
        File('lib/shared/widgets/main_layout.dart').readAsStringSync();
    final dashboard =
        File('lib/shared/screens/dashboard_screen.dart').readAsStringSync();
    final settings = File(
      'lib/modules/settings/pages/settings_page.dart',
    ).readAsStringSync();

    expect(
      helper,
      contains('ResponsiveViewport.usesCompactShell(context)'),
    );
    expect(helper, contains('context.push(route)'));
    expect(helper, contains('openRouteInWorkspace(route)'));

    expect(
      RegExp(r'CurrentUserProfileNavigation\.open\(context\)')
          .allMatches(layout),
      hasLength(2),
    );
    expect(
      RegExp(r'CurrentUserProfileNavigation\.open\(context\)')
          .allMatches(dashboard),
      hasLength(1),
    );
    expect(
      RegExp(r'CurrentUserProfileNavigation\.open\(context\)')
          .allMatches(settings),
      hasLength(1),
    );

    for (final source in [layout, dashboard, settings]) {
      expect(source, isNot(contains("context.push('/profile')")));
    }
  });
}
