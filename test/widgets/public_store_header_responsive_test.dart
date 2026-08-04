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
import 'package:vinabike_erp/public_store/services/customer_account_service.dart';
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

  // ---- Tenant-safe logo owner (StorefrontLogoResolution) ----------------

  group('StorefrontLogoResolution owner', () {
    test('canonical tenant identity has ONE named owner', () {
      expect(
        VinabikeCanonicalTenant.owns(VinabikeCanonicalTenant.id),
        isTrue,
      );
      expect(
        VinabikeCanonicalTenant.owns(' ${VinabikeCanonicalTenant.id} '),
        isTrue,
        reason: 'trimmed comparison',
      );
      expect(VinabikeCanonicalTenant.owns('tenant-foreign'), isFalse);
      expect(VinabikeCanonicalTenant.owns(null), isFalse);
    });

    test('full precedence: configured, tenant, canonical asset, wordmark', () {
      final full = StorefrontLogoResolution.resolve(
        configuredUrl: 'https://a/logo.png',
        tenantLogoUrl: 'https://b/tenant.png',
        tenantId: VinabikeCanonicalTenant.id,
      );
      expect(
        full.networkCandidates,
        ['https://a/logo.png', 'https://b/tenant.png'],
        reason: 'configured URL always wins; tenant logo is the remainder',
      );
      expect(full.allowsBundledAsset, isTrue);

      final deduped = StorefrontLogoResolution.resolve(
        configuredUrl: ' https://a/logo.png ',
        tenantLogoUrl: 'https://a/logo.png',
        tenantId: 'tenant-foreign',
      );
      expect(deduped.networkCandidates, ['https://a/logo.png']);
      expect(deduped.allowsBundledAsset, isFalse,
          reason: 'the bundled asset belongs to ONE tenant only');

      final empty = StorefrontLogoResolution.resolve(
        configuredUrl: '',
        tenantLogoUrl: null,
        tenantId: 'tenant-foreign',
      );
      expect(empty.networkCandidates, isEmpty);
      expect(empty.allowsBundledAsset, isFalse);

      final canonicalEmpty = StorefrontLogoResolution.resolve(
        configuredUrl: '',
        tenantLogoUrl: '  ',
        tenantId: VinabikeCanonicalTenant.id,
      );
      expect(canonicalEmpty.networkCandidates, isEmpty);
      expect(canonicalEmpty.allowsBundledAsset, isTrue);
    });
  });

  Finder bundledAssetLogo() => find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                StorefrontLogoResolution.bundledAssetPath,
      );

  Finder networkLogo(String url) => find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url == url,
      );

  Future<void> pumpStorefront(
    WidgetTester tester, {
    required String tenantId,
    double width = 1200,
    Map<String, Object?> settings = const <String, Object?>{},
    String? tenantLogoUrl,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      'website_public_v2_settings_$tenantId': jsonEncode({
        'store_name': 'VINABIKE',
        'show_top_banner': 'false',
        ...settings,
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
          logoUrl: tenantLogoUrl,
          createdAt: DateTime.utc(2026, 8, 3),
          updatedAt: DateTime.utc(2026, 8, 3),
        ),
      );
    final cart = CartProvider();
    final inventory = PublicInventoryService();
    final scrollState = PublicStoreScrollState();
    // The desktop header renders CustomerAccountMenu, which the narrow
    // canary tests never mount.
    final account = CustomerAccountService();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => MediaQuery(
            data: MediaQuery.of(context).copyWith(size: Size(width, 1400)),
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
    addTearDown(account.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // Image loads over the loopback origin park a 15 s idle keep-alive
    // timer on the shared HttpClient; advance fake time so no test ends
    // with timers pending.
    await tester.pump(const Duration(seconds: 16));
  }

  const brokenLogoUrl = 'http://127.0.0.1:1/broken.png';

  testWidgets(
      'canonical tenant without any configured logo renders the bundled '
      'asset through the SAME owner in header, desktop footer and mobile '
      'footer', (tester) async {
    await pumpStorefront(tester, tenantId: VinabikeCanonicalTenant.id);
    expect(
      bundledAssetLogo(),
      findsAtLeastNWidgets(2),
      reason: 'desktop: header AND desktop footer resolve the same asset',
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);

    await pumpStorefront(
      tester,
      tenantId: VinabikeCanonicalTenant.id,
      width: 375,
    );
    expect(
      bundledAssetLogo(),
      findsAtLeastNWidgets(2),
      reason: 'mobile: header AND mobile footer resolve the same asset '
          '(the duplicated mobile Stack is gone)',
    );
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
      'a foreign tenant NEVER renders the Viñabike asset — with no logo and '
      'with a broken configured URL it ends in its own wordmark',
      (tester) async {
    await pumpStorefront(tester, tenantId: 'tenant-foreign');
    expect(bundledAssetLogo(), findsNothing);
    await unmount(tester);

    await pumpStorefront(
      tester,
      tenantId: 'tenant-foreign',
      settings: {'logo_url': brokenLogoUrl},
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump();
    expect(bundledAssetLogo(), findsNothing,
        reason: 'a broken URL must never fall into a foreign tenant asset');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a configured URL is preserved as the primary source',
      (tester) async {
    await pumpStorefront(
      tester,
      tenantId: VinabikeCanonicalTenant.id,
      settings: {'logo_url': _wideLogoUrl},
    );
    expect(networkLogo(_wideLogoUrl), findsAtLeastNWidgets(2),
        reason: 'header and footer render the configured network logo');
    expect(bundledAssetLogo(), findsNothing,
        reason: 'the asset is a fallback, never a replacement');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
      'a broken configured URL falls through the tenant-safe remainder: '
      'tenant logo first, canonical asset when nothing else remains',
      (tester) async {
    await pumpStorefront(
      tester,
      tenantId: VinabikeCanonicalTenant.id,
      settings: {'logo_url': brokenLogoUrl},
      tenantLogoUrl: _wideLogoUrl,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
    await tester.pump();
    expect(networkLogo(_wideLogoUrl), findsAtLeastNWidgets(1),
        reason: 'the hydrated tenant logo is the next candidate');
    await unmount(tester);

    await pumpStorefront(
      tester,
      tenantId: VinabikeCanonicalTenant.id,
      settings: {'logo_url': brokenLogoUrl},
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
    await tester.pump();
    expect(bundledAssetLogo(), findsAtLeastNWidgets(1),
        reason: 'with no network remainder the canonical asset closes the '
            'chain');
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

}

class _LoopbackHttpOverrides extends HttpOverrides {}
