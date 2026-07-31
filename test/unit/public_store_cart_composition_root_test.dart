import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/services/cart_store.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_bootstrap.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/models/public_product_visibility_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
    'canonical restore injects one tenant-bound authoritative catalog loader',
    (tester) async {
      final store = _MemoryCartStore(
        PersistedCart(
          tenantId: 'tenant-a',
          savedAt: DateTime.now().toUtc(),
          lines: const [
            PersistedCartLine(productId: 'product-a', quantity: 2),
          ],
          revision: 'cart-revision-a',
        ),
      );
      final cart = CartProvider(store: store);
      final inventory = _ProbePublicInventoryService();
      addTearDown(cart.dispose);
      addTearDown(inventory.dispose);

      late BuildContext compositionContext;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CartProvider>.value(value: cart),
            ChangeNotifierProvider<PublicInventoryService>.value(
              value: inventory,
            ),
          ],
          child: Builder(
            builder: (context) {
              compositionContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await restorePublicStoreCart(
        compositionContext,
        tenantId: ' tenant-a ',
      );

      expect(store.readCount, 1);
      expect(inventory.loadCount, 1);
      expect(inventory.lastTenantId, 'tenant-a');
      expect(inventory.lastProductIds, const ['product-a']);
      expect(inventory.lastOnlyInStock, isFalse);
      expect(inventory.lastLimit, 1);
      expect(cart.items, hasLength(1));
      expect(cart.items.single.product.id, 'product-a');
      expect(cart.items.single.quantity, 2);

      // Both composition roots may converge on the same provider while routing.
      // CartProvider's tenant idempotency prevents a second read or catalog load.
      await restorePublicStoreCart(
        compositionContext,
        tenantId: 'tenant-a',
      );
      expect(store.readCount, 1);
      expect(inventory.loadCount, 1);
    },
  );

  test('standalone, ERP shell, and direct checkout use the scoped helper', () {
    final bootstrap = File(
      'lib/public_store/widgets/public_store_bootstrap.dart',
    ).readAsStringSync();
    final erpBoundary = File(
      'lib/public_store/widgets/erp_mounted_storefront_scope_boundary.dart',
    ).readAsStringSync();
    final router = File('lib/shared/routes/app_router.dart').readAsStringSync();

    final canonicalHelper = _section(
      bootstrap,
      start: 'Future<void> restorePublicStoreCartForTenant(',
      end: '/// SIMPLE bootstrap widget for public store',
    );
    expect(_occurrences(canonicalHelper, 'getProductPageForTenant('), 1);
    expect(canonicalHelper, contains('onlyInStock: false'));
    expect(canonicalHelper, contains('limit: productIds.length'));

    final standaloneRestore = _section(
      bootstrap,
      start: 'Future<void> _restoreSavedCart(String tenantId)',
      end: 'Future<void> _loadStoreDataInBackground(',
    );
    expect(_occurrences(standaloneRestore, 'restorePublicStoreCart('), 1);
    expect(standaloneRestore, isNot(contains('getProductPageForTenant(')));
    expect(standaloneRestore, isNot(contains('CartProvider>().restore(')));

    final erpScopeInitialization = _section(
      erpBoundary,
      start: 'Future<void> _synchronize(',
      end: '@override\n  void dispose()',
    );
    expect(
      _occurrences(
        erpScopeInitialization,
        'restorePublicStoreCartForTenant(',
      ),
      1,
    );
    expect(
      erpScopeInitialization,
      contains(
        RegExp(
          r'await Future\.wait\(\[[\s\S]*'
          r'restorePublicStoreCartForTenant\([\s\S]*'
          r'if \(onTenantReady != null\) onTenantReady\(authority\.tenantId\)',
        ),
      ),
    );
    expect(
      erpScopeInitialization,
      contains('_isReady = true'),
    );
    expect(
      erpScopeInitialization,
      isNot(contains('getProductPageForTenant(')),
    );
    expect(
      erpScopeInitialization,
      isNot(contains('CartProvider>().restore(')),
    );

    final erpShell = _section(
      router,
      start: 'class _PublicStoreShell extends StatelessWidget',
      end: 'class AppRouter',
    );
    expect(erpShell, contains('ErpMountedStorefrontScopeBoundary('));
    expect(erpShell, contains('getCategoriesForTenant('));

    final legacyCheckoutRoute = _section(
      router,
      start: "path: '/tienda/checkout',",
      end: '// Order Confirmation',
    );
    expect(
      legacyCheckoutRoute,
      contains('ErpMountedStorefrontScopeBoundary('),
    );
    expect(legacyCheckoutRoute, contains('child: const CheckoutPage()'));
  });
}

String _section(
  String source, {
  required String start,
  required String end,
}) {
  final match = RegExp(
    '${RegExp.escape(start)}([\\s\\S]*?)${RegExp.escape(end)}',
  ).firstMatch(source);
  expect(match, isNotNull, reason: 'Missing source section: $start ... $end');
  return match!.group(1)!;
}

int _occurrences(String source, String needle) =>
    RegExp(RegExp.escape(needle)).allMatches(source).length;

class _ProbePublicInventoryService extends PublicInventoryService {
  int loadCount = 0;
  String? lastTenantId;
  List<String>? lastProductIds;
  bool? lastOnlyInStock;
  int? lastLimit;

  @override
  Future<PublicProductPage> getProductPageForTenant({
    required String tenantId,
    List<String>? categoryIds,
    List<String>? productIds,
    String? sku,
    String? searchQuery,
    ProductType? productType,
    PublicProductVisibilityPolicy? policy,
    bool onlyInStock = true,
    bool applyAvailabilityFacet = false,
    List<String>? brandIds,
    double? minPrice,
    double? maxPrice,
    String sortBy = 'name',
    int limit = 20,
    int offset = 0,
  }) async {
    loadCount++;
    lastTenantId = tenantId;
    lastProductIds = List<String>.of(productIds ?? const []);
    lastOnlyInStock = onlyInStock;
    lastLimit = limit;
    return PublicProductPage(
      products: [_product()],
      totalCount: 1,
    );
  }
}

class _MemoryCartStore extends CartStore {
  _MemoryCartStore(this.document);

  PersistedCart? document;
  int readCount = 0;

  @override
  Future<void> clear() async {
    document = null;
  }

  @override
  Future<PersistedCart?> read() async {
    readCount++;
    return document;
  }

  @override
  Future<void> write(PersistedCart cart) async {
    document = cart;
  }
}

Product _product() {
  return Product(
    id: 'product-a',
    name: 'Producto A',
    sku: 'PRODUCT-A',
    price: 12990,
    cost: 0,
    stockQuantity: 10,
    description: 'Producto usado para validar el loader canónico.',
    category: ProductCategory.other,
    taxRate: 19,
    createdAt: DateTime.utc(2026, 7, 28),
    updatedAt: DateTime.utc(2026, 7, 28),
  );
}
