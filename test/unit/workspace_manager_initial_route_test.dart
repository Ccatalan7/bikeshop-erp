import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';

void main() {
  group('resolveInitialWorkspaceRoute', () {
    test('preserves a spreadsheet detail deep link and query string', () {
      expect(
        resolveInitialWorkspaceRoute(
          'http://127.0.0.1:54321/tools/spreadsheets/'
          '33478c36-91d7-4119-ac72-7db990cb23bb?view=compact',
        ),
        '/tools/spreadsheets/'
        '33478c36-91d7-4119-ac72-7db990cb23bb?view=compact',
      );
    });

    test('accepts relative workspace routes', () {
      expect(
        resolveInitialWorkspaceRoute('/tools/spreadsheets'),
        '/tools/spreadsheets',
      );
    });

    test('does not treat public or similarly prefixed paths as ERP routes', () {
      expect(
          resolveInitialWorkspaceRoute('https://vinabike.cl/productos'), null);
      expect(
        resolveInitialWorkspaceRoute('https://example.test/toolsmith'),
        null,
      );
    });
  });

  test('main injects the URL captured before authentication redirects', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(
      mainSource,
      contains('initialBrowserUrl: _initialBrowserUrl'),
    );
  });
}
