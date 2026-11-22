import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/customer_account_service.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/services/public_store_scroll_state.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

/// The editor's canvas keeps the desktop menu only while it fits
/// (2026-11-21), as the HTML store's `menu-compact`: with «Bicicletas» and
/// «Marcas» the menu has eight entries and needs ~1310 px. The test font
/// draws every letter a full em wide, so here the same eight need ~1660 px.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previousHttpOverrides;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      (_) async => null,
    );
    SharedPreferences.setMockInitialValues({});
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _LoopbackHttpOverrides();
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      null,
    );
    HttpOverrides.global = previousHttpOverrides;
  });

  const tenantId = 'tenant-menu-fit-test';

  List<Map<String, Object?>> menu(List<String> labels) => [
        for (final (index, label) in labels.indexed)
          {
            'id': 'nav-$index',
            'tenant_id': tenantId,
            'menu_location': 'header',
            'label': label,
            'link_type': 'page',
            'link_value': '/${label.toLowerCase()}',
            'order_index': index,
            'is_visible': true,
            'show_on_desktop': true,
            'show_on_mobile': true,
            'open_in_new_tab': false,
            'highlight': false,
            'created_at': '2026-11-21T00:00:00Z',
            'updated_at': '2026-11-21T00:00:00Z',
          },
      ];

  const eight = [
    'Bicicletas',
    'Componentes',
    'Accesorios',
    'Marcas',
    'Productos',
    'Servicios',
    'Guías',
    'Contacto',
  ];

  Future<void> pumpStorefront(
    WidgetTester tester, {
    required double width,
    required List<String> labels,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'website_public_v2_settings_$tenantId': jsonEncode({
        'store_name': 'VINABIKE',
        'show_top_banner': 'false',
      }),
      'website_public_v2_blocks_$tenantId': '[]',
      'website_public_v2_navigation_$tenantId': jsonEncode(menu(labels)),
      'website_public_v2_last_refresh_$tenantId':
          DateTime.now().millisecondsSinceEpoch,
    });
    final preferences = await SharedPreferences.getInstance();
    WebsiteService.setSharedPreferences(preferences);
    final website = WebsiteService();
    expect(website.loadSettingsFromSynchronousCache(tenantId), isTrue);
    expect(website.loadNavigationFromSynchronousCache(tenantId), isTrue);
    final editMode = WebsiteEditModeProvider();
    final tenant = PublicStoreTenantProvider(TenantDetectionService())
      ..setTenant(
        Tenant(
          id: tenantId,
          shopName: 'VINABIKE',
          subdomain: 'vinabike',
          createdAt: DateTime.utc(2026, 11, 21),
          updatedAt: DateTime.utc(2026, 11, 21),
        ),
      );
    final cart = CartProvider();
    final inventory = PublicInventoryService();
    final scrollState = PublicStoreScrollState();
    final account = CustomerAccountService();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => MediaQuery(
            data: MediaQuery.of(context).copyWith(size: Size(width, 1000)),
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: website),
                ChangeNotifierProvider.value(value: editMode),
                ChangeNotifierProvider.value(value: tenant),
                ChangeNotifierProvider.value(value: cart),
                ChangeNotifierProvider.value(value: inventory),
                ChangeNotifierProvider.value(value: account),
                Provider.value(value: scrollState),
              ],
              child: const PublicStoreLayout(child: SizedBox(height: 120)),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(website.dispose);
    addTearDown(editMode.dispose);
    addTearDown(tenant.dispose);
    addTearDown(cart.dispose);
    addTearDown(inventory.dispose);
    addTearDown(account.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    // The menu is measured as laid out, and the bar follows on the next
    // frame.
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 16));
  }

  final menuButton = find.byKey(const ValueKey('public-store-header-menu'));
  Finder entry(String label) => find.textContaining(
        RegExp('^${RegExp.escape(label)}\$', caseSensitive: false),
      );

  testWidgets('eight entries on a wide enough screen keep the desktop menu',
      (tester) async {
    await pumpStorefront(tester, width: 1800, labels: eight);
    expect(menuButton, findsNothing);
    expect(entry('Bicicletas'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
      'eight entries at 1200 px turn the bar compact instead of running '
      'under the tools', (tester) async {
    await pumpStorefront(tester, width: 1200, labels: eight);
    expect(menuButton, findsOneWidget);
    expect(entry('Bicicletas'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('three entries at 1200 px keep the desktop menu', (tester) async {
    await pumpStorefront(
      tester,
      width: 1200,
      labels: const ['Componentes', 'Servicios', 'Contacto'],
    );
    expect(menuButton, findsNothing);
    expect(entry('Componentes'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}

class _LoopbackHttpOverrides extends HttpOverrides {}
