import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const routedPages = <String>[
    'website_management_page.dart',
    'page_management_page.dart',
    'navigation_management_page.dart',
    'website_destination_management_page.dart',
    'featured_products_page.dart',
    'product_website_visibility_page.dart',
    'online_orders_page.dart',
    'website_settings_page.dart',
    'integrations_page.dart',
    'seo_settings_page.dart',
  ];

  test('all routed website administration pages share the canonical shell', () {
    for (final fileName in routedPages) {
      final source =
          File('lib/modules/website/pages/$fileName').readAsStringSync();
      expect(
        source,
        contains('WebsiteAdminShell('),
        reason: '$fileName must remain inside the website administration shell',
      );
    }
  });

  test('website dashboard is a grouped control center, not a card grid', () {
    final source = File(
      'lib/modules/website/pages/website_management_page.dart',
    ).readAsStringSync();

    expect(source, contains("'Contenido y estructura'"));
    expect(source, contains("'Catálogo y ventas'"));
    expect(source, contains("'Configuración y alcance'"));
    expect(source, contains("'Tu vitrina digital, lista para vender'"));
    expect(source, contains('WebsiteAdminMetricStrip'));
    expect(source, contains('LinearGradient'));
    expect(source, contains('Color(0xFF1976D2)'));
    expect(source, isNot(contains('GridView.count')));
    expect(source, isNot(contains('_buildManagementCard')));
  });

  test('destination audit no longer owns a competing app scaffold', () {
    final source = File(
      'lib/modules/website/pages/website_destination_management_page.dart',
    ).readAsStringSync();

    expect(source, contains('WebsiteAdminShell('));
    expect(source, isNot(contains('return Scaffold(')));
    expect(source, isNot(contains('AppBar(')));
  });

  test('online orders uses a flat resizable sortable desktop table', () {
    final source = File(
      'lib/modules/website/pages/online_orders_page.dart',
    ).readAsStringSync();

    expect(source, contains("'Email',"));
    expect(source, contains('SystemMouseCursors.resizeColumn'));
    expect(source, contains('onHorizontalDragUpdate'));
    expect(source, contains('_compareOrders'));
    expect(source, contains('ListView.builder'));
    expect(source, contains('bottom: BorderSide'));
    expect(source, isNot(contains('ListView.separated')));
    expect(source, contains('_showOrderInspector'));
    expect(source, isNot(contains('Card(')));
    expect(source, isNot(contains('_buildOrderRow')));
  });

  test('canonical surface registry covers the administration hub and routes',
      () {
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(registry, contains('Website administration hub'));
    expect(registry, contains('Website administration pages'));
    expect(registry, contains('WebsiteAdminShell'));
    expect(registry, contains('/website/integrations'));
    expect(registry, contains('/website/seo'));
  });
}
