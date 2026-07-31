import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/pages/product_detail_page.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/cart_store.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/utils/product_url.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/models/public_product_visibility_policy.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

late HttpServer _origin;
late StreamSubscription<HttpRequest> _originRequests;
late String _originUrl;
HttpOverrides? _previousHttpOverrides;
var _aliasRequestCount = 0;

const _transparentPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    'YAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _LoopbackHttpOverrides();
    _origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _originUrl = 'http://${_origin.address.address}:${_origin.port}';
    _originRequests = _origin.listen(_serveOriginRequest);
    await Supabase.initialize(
      url: _originUrl,
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: false,
      ),
    );
  });

  setUp(() {
    _aliasRequestCount = 0;
  });

  tearDownAll(() async {
    await _originRequests.cancel();
    await _origin.close(force: true);
    HttpOverrides.global = _previousHttpOverrides;
  });

  testWidgets(
    'transport failure is retryable and never masquerades as not-found',
    (tester) async {
      final product = _product(
        imageUrls: ['$_originUrl/images/retry.png'],
      );
      final inventory = _FakePublicInventoryService(
        productsByTenant: {'tenant-a': product},
        transientFailures: 1,
      );
      final harness = await _pumpProductDetail(
        tester,
        inventory: inventory,
        initialTenant: _tenant('tenant-a'),
        canonicalProduct: product,
      );

      await _pumpUntilFound(
        tester,
        find.text('No se pudo cargar el producto'),
      );
      expect(find.text('Producto no encontrado'), findsNothing);
      expect(
          find.byKey(const ValueKey('product-detail-retry')), findsOneWidget);
      expect(inventory.productLoadCount, 1);

      await tester.tap(find.byKey(const ValueKey('product-detail-retry')));
      await _pumpUntilFound(tester, find.text('CADENA DEMO'));

      expect(find.text('No se pudo cargar el producto'), findsNothing);
      expect(find.text('Producto no encontrado'), findsNothing);
      expect(inventory.productLoadCount, 2);
      expect(_aliasRequestCount, 0);
      expect(tester.takeException(), isNull);

      harness.dispose();
    },
  );

  testWidgets(
    'missing tenant is retryable while an origin-confirmed miss is not-found',
    (tester) async {
      final canonicalProduct = _product(
        imageUrls: ['$_originUrl/images/missing.png'],
      );
      final inventory = _FakePublicInventoryService(productsByTenant: const {});
      final harness = await _pumpProductDetail(
        tester,
        inventory: inventory,
        canonicalProduct: canonicalProduct,
      );

      await _pumpUntilFound(
        tester,
        find.text('No se pudo cargar el producto'),
      );
      expect(find.text('Producto no encontrado'), findsNothing);
      expect(
          find.byKey(const ValueKey('product-detail-retry')), findsOneWidget);
      expect(inventory.productLoadCount, 0);

      await tester.tap(find.byKey(const ValueKey('product-detail-retry')));
      await tester.pump();
      await tester.pump();
      expect(find.text('No se pudo cargar el producto'), findsOneWidget);
      expect(inventory.productLoadCount, 0);

      harness.tenantProvider.setTenant(_tenant('tenant-missing'));
      await _pumpUntilFound(tester, find.text('Producto no encontrado'));

      expect(find.text('No se pudo cargar el producto'), findsNothing);
      expect(find.byKey(const ValueKey('product-detail-retry')), findsNothing);
      expect(inventory.productLoadCount, 1);
      expect(_aliasRequestCount, 1);
      expect(tester.takeException(), isNull);

      harness.dispose();
    },
  );

  testWidgets(
    'same SKU tenant switch clears gallery index and transient interaction state',
    (tester) async {
      final tenantAImages = [
        for (var index = 1; index <= 4; index++)
          '$_originUrl/images/tenant-a-$index.png',
      ];
      final tenantBImages = ['$_originUrl/images/tenant-b-1.png'];
      final productA = _product(imageUrls: tenantAImages);
      final productB = _product(imageUrls: tenantBImages);
      final inventory = _FakePublicInventoryService(
        productsByTenant: {
          'tenant-a': productA,
          'tenant-b': productB,
        },
      );
      final harness = await _pumpProductDetail(
        tester,
        inventory: inventory,
        initialTenant: _tenant('tenant-a'),
        canonicalProduct: productA,
      );

      await _pumpUntilFound(tester, _networkImage(tenantAImages.last));
      final fourthThumbnail = find.ancestor(
        of: _networkImage(tenantAImages.last),
        matching: find.byType(InkWell),
      );
      expect(fourthThumbnail, findsOneWidget);
      await tester.tap(fourthThumbnail);
      await tester.pump();
      expect(_networkImage(tenantAImages.last), findsNWidgets(2));

      final addToCart = find.text('Agregar al carrito');
      await tester.ensureVisible(addToCart);
      await tester.pump();
      await tester.tap(addToCart);
      await tester.pump();
      expect(find.text('Agregado al carrito'), findsOneWidget);
      expect(
        find.text('Cadena Demo agregado al carrito'),
        findsOneWidget,
      );

      final increaseQuantity = find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(InkWell),
      );
      expect(increaseQuantity, findsOneWidget);
      await tester.tap(increaseQuantity);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      harness.tenantProvider.setTenant(_tenant('tenant-b'));
      await _pumpUntilFound(tester, _networkImage(tenantBImages.single));

      expect(_networkImage(tenantBImages.single), findsOneWidget);
      for (final imageUrl in tenantAImages) {
        expect(_networkImage(imageUrl), findsNothing);
      }
      expect(find.text('2'), findsNothing);
      expect(find.text('1'), findsWidgets);
      expect(find.text('Agregado al carrito'), findsNothing);
      expect(
        find.text('Cadena Demo agregado al carrito'),
        findsNothing,
      );
      expect(inventory.productLoadsByTenant['tenant-a'], 1);
      expect(inventory.productLoadsByTenant['tenant-b'], 1);
      expect(
        tester.takeException(),
        isNull,
        reason: 'A 4 → 1 gallery switch must not index tenant A state.',
      );

      harness.dispose();
    },
  );
}

Future<void> _serveOriginRequest(HttpRequest request) async {
  await request.drain<void>();
  request.response.headers.set(HttpHeaders.connectionHeader, 'close');
  if (request.uri.path.startsWith('/images/')) {
    final bytes = base64Decode(_transparentPng);
    request.response.headers.contentType = ContentType('image', 'png');
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
    return;
  }

  // This isolated origin exists only for the product alias RPC used by the
  // page after a direct lookup returns null. An empty scalar is PostgREST's
  // confirmed "no alias" result and is deliberately different from a broken
  // transport.
  _aliasRequestCount++;
  request.response.statusCode = HttpStatus.ok;
  request.response.headers.contentType = ContentType.json;
  request.response.write('""');
  await request.response.close();
}

class _LoopbackHttpOverrides extends HttpOverrides {}

class _ProductDetailHarness {
  const _ProductDetailHarness({
    required this.tenantProvider,
    required this.dispose,
  });

  final PublicStoreTenantProvider tenantProvider;
  final VoidCallback dispose;
}

Future<_ProductDetailHarness> _pumpProductDetail(
  WidgetTester tester, {
  required _FakePublicInventoryService inventory,
  required Product canonicalProduct,
  Tenant? initialTenant,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final tenantProvider = PublicStoreTenantProvider(TenantDetectionService());
  if (initialTenant != null) {
    tenantProvider.setTenant(initialTenant);
  }
  final website = WebsiteService();
  final editMode = WebsiteEditModeProvider();
  final cart = CartProvider(store: _MemoryCartStore());
  final canonicalPath = publicProductPath(canonicalProduct);
  final router = GoRouter(
    initialLocation: canonicalPath,
    overridePlatformDefaultLocation: true,
    routes: [
      GoRoute(
        path: '/productos/:slug/:sku',
        builder: (context, state) => const Scaffold(
          body: SingleChildScrollView(
            child: ProductDetailPage(productId: 'sku:SAME'),
          ),
        ),
      ),
      GoRoute(
        path: '/productos',
        builder: (context, state) => const SizedBox.shrink(),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PublicStoreTenantProvider>.value(
          value: tenantProvider,
        ),
        ChangeNotifierProvider<PublicInventoryService>.value(value: inventory),
        ChangeNotifierProvider<WebsiteService>.value(value: website),
        ChangeNotifierProvider<WebsiteEditModeProvider>.value(value: editMode),
        ChangeNotifierProvider<CartProvider>.value(value: cart),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();

  return _ProductDetailHarness(
    tenantProvider: tenantProvider,
    dispose: () {
      router.dispose();
      tenantProvider.dispose();
      inventory.dispose();
      website.dispose();
      editMode.dispose();
      cart.dispose();
    },
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
}) async {
  for (var pump = 0; pump < maxPumps; pump++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail(
    'Did not find the requested widget after $maxPumps pumps '
    '(alias requests: $_aliasRequestCount).',
  );
}

Finder _networkImage(String url) {
  return find.byWidgetPredicate((widget) {
    if (widget is! Image || widget.image is! NetworkImage) return false;
    return (widget.image as NetworkImage).url == url;
  });
}

Product _product({required List<String> imageUrls}) {
  return Product(
    id: 'shared-product-id',
    name: 'Cadena Demo',
    sku: 'SAME',
    price: 12990,
    cost: 0,
    stockQuantity: 10,
    imageUrls: imageUrls,
    description: 'Cadena de prueba para la tienda pública.',
    brand: 'Marca Demo',
    category: ProductCategory.other,
    taxRate: 19,
    createdAt: DateTime.utc(2026, 7, 28),
    updatedAt: DateTime.utc(2026, 7, 28),
  );
}

Tenant _tenant(String id) {
  return Tenant(
    id: id,
    shopName: id,
    createdAt: DateTime.utc(2026, 7, 28),
    updatedAt: DateTime.utc(2026, 7, 28),
  );
}

class _FakePublicInventoryService extends PublicInventoryService {
  _FakePublicInventoryService({
    required this.productsByTenant,
    this.transientFailures = 0,
  });

  final Map<String, Product> productsByTenant;
  int transientFailures;
  int productLoadCount = 0;
  final Map<String, int> productLoadsByTenant = {};

  @override
  Future<Product?> getProductBySku({
    required String sku,
    required String tenantId,
    PublicProductVisibilityPolicy? policy,
    bool rethrowErrors = false,
  }) async {
    productLoadCount++;
    productLoadsByTenant.update(
      tenantId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    if (transientFailures > 0) {
      transientFailures--;
      throw const SocketException('simulated transport failure');
    }
    return productsByTenant[tenantId];
  }
}

class _MemoryCartStore implements CartStore {
  @override
  Future<void> clear() async {}

  @override
  Future<CartConsumptionResult> consumeOrderedLines({
    required String tenantId,
    required List<PersistedCartLine> orderedLines,
    required String expectedRevision,
    CartConsumptionPreparation? prepare,
  }) async {
    return const CartConsumptionResult(
      status: CartConsumptionStatus.unavailable,
      document: null,
    );
  }

  @override
  Future<PersistedCart?> read() async => null;

  @override
  Future<void> write(PersistedCart cart) async {}
}
