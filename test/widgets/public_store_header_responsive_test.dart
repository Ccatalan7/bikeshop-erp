import 'dart:async';
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
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/services/public_store_scroll_state.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

late HttpServer _origin;
late StreamSubscription<HttpRequest> _originRequests;
late String _wideLogoUrl;
HttpOverrides? _previousHttpOverrides;

const _wideLogoPng =
    'iVBORw0KGgoAAAANSUhEUgAAA+gAAABkCAYAAAAVORraAAACL0lEQVR42u3XMQ0A'
    'AAjAMLQgDnGYBBMkPD1qYN8iqwcAAAD4FSIAAACAQQcAAAAMOgAAABh0AAAAwKADAACA'
    'QQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAA'
    'ABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKAD'
    'AACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAM'
    'OgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAA'
    'wKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcA'
    'AAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0'
    'AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACA'
    'QQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAA'
    'ABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKAD'
    'AACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAM'
    'OgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAA'
    'wKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcA'
    'AAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0AAAAwKADAACAQQcAAAAMOgAAABh0'
    'IQAAAMCgAwAAAAYdAAAADDoAAABg0AEAAMCgAwAAAAYdAAAADDoAAABg0AEAAMCgAwAA'
    'AAYdAAAADDoAAABg0AEAAMCgAwAAAAYdAAAADDoAAABg0AEAAMCgAwAAAAYdAAAADDoA'
    'AABg0AEAAMCgAwAAAAYdAAAADDoAAABg0AEAAMCgAwAAAAYdAAAADDoAAABg0AEAAMCg'
    'AwAAAAYdAAAADDoAAABg0AEAAMCgAwAAAAYdAAAADDoAAABg0AEAAMCgAwAAAAYdAAAA'
    'DDoAAABg0AEAAMCgAwAAAAYdAAAADDoAAABg0AEAAMCgAwAAAAYdAAAADDoAAABwYQGf'
    'CjbJeA3lsAAAAABJRU5ErkJggg==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      (_) async => null,
    );
    SharedPreferences.setMockInitialValues({});
    _previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _LoopbackHttpOverrides();
    _origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _wideLogoUrl = 'http://${_origin.address.address}:${_origin.port}/wide.png';
    _originRequests = _origin.listen((request) async {
      await request.drain<void>();
      final bytes = base64Decode(_wideLogoPng);
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      null,
    );
    await _originRequests.cancel();
    await _origin.close(force: true);
    HttpOverrides.global = _previousHttpOverrides;
  });

  for (final width in <double>[320, 375, 599]) {
    testWidgets(
      'actual compact header fits a decoded wide wordmark at ${width.toInt()}',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        const tenantId = 'tenant-header-test';
        SharedPreferences.setMockInitialValues({
          'website_public_v2_settings_$tenantId': jsonEncode({
            'logo_url': _wideLogoUrl,
            'store_name': 'VINABIKE',
            'show_top_banner': 'false',
          }),
          'website_public_v2_blocks_$tenantId': '[]',
          'website_public_v2_last_refresh_$tenantId':
              DateTime.now().millisecondsSinceEpoch,
        });
        final preferences = await SharedPreferences.getInstance();
        WebsiteService.setSharedPreferences(preferences);

        final website = WebsiteService();
        expect(website.loadSettingsFromSynchronousCache(tenantId), isTrue);
        final editMode = WebsiteEditModeProvider();
        final tenant = PublicStoreTenantProvider(TenantDetectionService())
          ..setTenant(
            Tenant(
              id: tenantId,
              shopName: 'VINABIKE',
              subdomain: 'vinabike',
              createdAt: DateTime.utc(2026, 7, 28),
              updatedAt: DateTime.utc(2026, 7, 28),
            ),
          );
        final cart = CartProvider();
        final inventory = PublicInventoryService();
        final scrollState = PublicStoreScrollState();
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: Size(width, 1000),
                ),
                child: MultiProvider(
                  providers: [
                    ChangeNotifierProvider.value(value: website),
                    ChangeNotifierProvider.value(value: editMode),
                    ChangeNotifierProvider.value(value: tenant),
                    ChangeNotifierProvider.value(value: cart),
                    ChangeNotifierProvider.value(value: inventory),
                    Provider.value(value: scrollState),
                  ],
                  child: const PublicStoreLayout(
                    child: SizedBox(height: 120),
                  ),
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

        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();

        final home = find.byKey(
          const ValueKey('public-store-header-home'),
        );
        final search = find.byKey(
          const ValueKey('public-store-header-search'),
        );
        final cartAction = find.byKey(
          const ValueKey('public-store-header-cart'),
        );
        final menu = find.byKey(
          const ValueKey('public-store-header-menu'),
        );

        expect(home, findsOneWidget);
        expect(search, findsOneWidget);
        expect(cartAction, findsOneWidget);
        expect(menu, findsOneWidget);
        for (final action in [home, search, cartAction, menu]) {
          final size = tester.getSize(action);
          expect(size.height, greaterThanOrEqualTo(48), reason: '$action');
        }
        expect(tester.getSize(search), const Size(48, 48));
        expect(tester.getSize(cartAction), const Size(48, 48));
        expect(tester.getSize(menu), const Size(48, 48));

        final geometry = PublicStoreHeaderGeometry.resolve(width);
        expect(
          tester.getSize(home).width,
          lessThanOrEqualTo(geometry.logoMaxWidth!),
        );
        expect(tester.getRect(home).right, lessThanOrEqualTo(width));
        expect(tester.getRect(menu).right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}

class _LoopbackHttpOverrides extends HttpOverrides {}
