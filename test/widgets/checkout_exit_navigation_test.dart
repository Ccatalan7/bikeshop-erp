import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/checkout_exit_guard.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/services/public_store_scroll_state.dart';
import 'package:vinabike_erp/public_store/theme/public_store_theme.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

const _paymentBadgeUrls = <String>[
  'https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/vinabike-assets/payment-icons/mercadopago.svg',
  'https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/vinabike-assets/payment-icons/visa.svg',
  'https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/vinabike-assets/payment-icons/mastercard.svg',
];

const _paymentBadgeFixture = '''
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"
  viewBox="0 0 16 16">
  <rect width="16" height="16" rx="2" fill="#ffffff"/>
</svg>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      (_) async => null,
    );
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
    final fixtureBytes =
        await const SvgStringLoader(_paymentBadgeFixture).loadBytes(null);
    for (final url in _paymentBadgeUrls) {
      await svg.cache.putIfAbsent(
        SvgNetworkLoader(url).cacheKey(null),
        () => Future.value(fixtureBytes),
      );
    }
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      null,
    );
    for (final url in _paymentBadgeUrls) {
      svg.cache.evict(SvgNetworkLoader(url).cacheKey(null));
    }
  });

  testWidgets(
    'real header blocks cart and confirms home while checkout is leased',
    (tester) async {
      final harness = await _pumpStorefront(tester);
      final lease = harness.guard.acquire(
        owner: Object(),
        phase: CheckoutExitPhase.recoveringOrder,
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('public-store-header-cart')),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('checkout-exit-cancel')),
        findsOneWidget,
      );
      expect(harness.currentPath, '/checkout');

      await tester.tap(
        find.byKey(const ValueKey('checkout-exit-cancel')),
      );
      await tester.pump();
      expect(harness.currentPath, '/checkout');

      await tester.tap(
        find.byKey(const ValueKey('public-store-header-home')),
      );
      await tester.pump();
      expect(harness.currentPath, '/checkout');

      await tester.tap(
        find.byKey(const ValueKey('checkout-exit-confirm')),
      );
      await tester.pump();
      await tester.pump();

      expect(harness.currentPath, '/');
      lease.release();
    },
  );

  testWidgets(
    'the same header navigation stays unchanged before the first attempt',
    (tester) async {
      final harness = await _pumpStorefront(tester);

      await tester.tap(
        find.byKey(const ValueKey('public-store-header-cart')),
      );
      await tester.pump();
      await tester.pump();

      expect(harness.currentPath, '/carrito');
      expect(
        find.byKey(const ValueKey('checkout-exit-confirm')),
        findsNothing,
      );
    },
  );
}

Future<_StorefrontHarness> _pumpStorefront(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(599, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final guard = CheckoutExitGuard();
  final website = WebsiteService();
  final editMode = WebsiteEditModeProvider();
  final cart = CartProvider();
  final inventory = PublicInventoryService();
  final scroll = PublicStoreScrollState();
  final tenant = PublicStoreTenantProvider(TenantDetectionService())
    ..setTenant(
      Tenant(
        id: 'tenant-exit-test',
        shopName: 'VINABIKE',
        subdomain: 'vinabike',
        createdAt: DateTime.utc(2026, 7, 28),
        updatedAt: DateTime.utc(2026, 7, 28),
      ),
    );

  late final GoRouter router;
  Widget routeBuilder(BuildContext context, GoRouterState state) {
    return PublicStoreLayout(
      routePath: state.uri.path,
      child: Center(child: Text('route:${state.uri.path}')),
    );
  }

  router = GoRouter(
    initialLocation: '/checkout',
    routes: [
      GoRoute(path: '/', builder: routeBuilder),
      GoRoute(path: '/checkout', builder: routeBuilder),
      GoRoute(path: '/carrito', builder: routeBuilder),
    ],
  );

  addTearDown(router.dispose);
  addTearDown(guard.dispose);
  addTearDown(website.dispose);
  addTearDown(editMode.dispose);
  addTearDown(cart.dispose);
  addTearDown(inventory.dispose);
  addTearDown(tenant.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: guard),
        ChangeNotifierProvider.value(value: website),
        ChangeNotifierProvider.value(value: editMode),
        ChangeNotifierProvider.value(value: cart),
        ChangeNotifierProvider.value(value: inventory),
        ChangeNotifierProvider.value(value: tenant),
        Provider.value(value: scroll),
      ],
      child: MaterialApp.router(
        theme: PublicStoreTheme.theme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();

  return _StorefrontHarness(guard: guard, router: router);
}

class _StorefrontHarness {
  const _StorefrontHarness({
    required this.guard,
    required this.router,
  });

  final CheckoutExitGuard guard;
  final GoRouter router;

  String get currentPath => router.routeInformationProvider.value.uri.path;
}
