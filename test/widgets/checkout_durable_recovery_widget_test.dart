import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/models/public_order_access.dart';
import 'package:vinabike_erp/modules/website/models/public_shipping_quote.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/mercadopago_service.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/models/public_checkout_capabilities.dart';
import 'package:vinabike_erp/public_store/pages/checkout_page.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/address_autocomplete_service.dart';
import 'package:vinabike_erp/public_store/services/checkout_exit_guard.dart';
import 'package:vinabike_erp/public_store/services/checkout_session_store.dart';
import 'package:vinabike_erp/public_store/services/customer_account_service.dart';
import 'package:vinabike_erp/public_store/theme/public_store_theme.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

const _tenantId = 'tenant-checkout-recovery';
const _idempotencyKey = '55555555-5555-4555-8555-555555555555';

Future<PublicCheckoutCapabilities> _loadAllPaymentCapabilities(String _) async {
  return PublicCheckoutCapabilities.fromRpc({
    'schemaVersion': 1,
    'methods': const [
      {
        'code': 'mercadopago',
        'available': true,
        'reasonCode': 'available',
      },
      {
        'code': 'transfer',
        'available': true,
        'reasonCode': 'available',
      },
    ],
  });
}

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
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      null,
    );
  });

  testWidgets(
    'restored Mercado Pago saves access before replayable handoff or navigation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1180, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
      final launcherCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        launcherChannel,
        (call) async {
          launcherCalls.add(call.method);
          return switch (call.method) {
            'canLaunch' => true,
            'launch' => false,
            _ => null,
          };
        },
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(launcherChannel, null),
      );

      final now = DateTime.now().toUtc();
      final checkoutStore = CheckoutSessionStore(
        storage: MemoryCheckoutSessionStorage(),
        now: () => now,
      );
      await checkoutStore.save(
        _snapshot(now).withReceipt(
          PublicOrderCheckoutAccess(
            orderId: 'order-frozen',
            accessToken:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            expiresAt: now.add(const Duration(hours: 1)),
            isReplay: true,
          ),
        ),
      );

      final cart = CartProvider();
      final exitGuard = CheckoutExitGuard();
      final website = WebsiteService();
      final editMode = WebsiteEditModeProvider();
      final account = CustomerAccountService();
      final autocomplete = _NoopAddressAutocompleteService();
      final mercadoPago = _ProbeMercadoPagoService();
      final tenant = PublicStoreTenantProvider(TenantDetectionService())
        ..setTenant(
          Tenant(
            id: _tenantId,
            shopName: 'VINABIKE',
            subdomain: 'vinabike',
            createdAt: DateTime.utc(2026, 7, 28),
            updatedAt: DateTime.utc(2026, 7, 28),
          ),
        );

      final router = GoRouter(
        initialLocation: '/checkout',
        routes: [
          GoRoute(
            path: '/checkout',
            builder: (_, __) => const Scaffold(
              body: CheckoutPage(
                capabilityLoader: _loadAllPaymentCapabilities,
              ),
            ),
          ),
          GoRoute(
            path: '/pedido/:id',
            builder: (_, state) => Scaffold(
              body: Text(
                'confirmation:${state.pathParameters['id']}',
              ),
            ),
          ),
        ],
      );

      addTearDown(router.dispose);
      addTearDown(cart.dispose);
      addTearDown(exitGuard.dispose);
      addTearDown(website.dispose);
      addTearDown(editMode.dispose);
      addTearDown(account.dispose);
      addTearDown(autocomplete.dispose);
      addTearDown(mercadoPago.dispose);
      addTearDown(tenant.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: cart),
            ChangeNotifierProvider.value(value: exitGuard),
            Provider.value(value: checkoutStore),
            ChangeNotifierProvider.value(value: website),
            ChangeNotifierProvider.value(value: editMode),
            ChangeNotifierProvider.value(value: account),
            ChangeNotifierProvider<AddressAutocompleteService>.value(
              value: autocomplete,
            ),
            ChangeNotifierProvider<MercadoPagoService>.value(
              value: mercadoPago,
            ),
            ChangeNotifierProvider.value(value: tenant),
          ],
          child: MaterialApp.router(
            theme: PublicStoreTheme.theme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('checkout-restored-session-notice')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('checkout-frozen-order-summary')),
        findsOneWidget,
      );
      expect(find.text('Producto del pedido guardado'), findsOneWidget);
      expect(find.textContaining('124.000'), findsOneWidget);

      // A basket created after the durable attempt must not leak into the
      // recovered order summary.
      cart.addProduct(_currentCartProduct());
      await tester.pump();

      expect(find.text('Producto del pedido guardado'), findsOneWidget);
      expect(find.text('Producto nuevo del carrito'), findsNothing);
      expect(find.textContaining('124.000'), findsOneWidget);

      await tester.tap(find.text('CONTINUAR CON PEDIDO'));
      await tester.pump();
      await mercadoPago.preferenceStarted.future;

      expect(mercadoPago.preferenceOrderId, 'order-frozen');
      expect(
        mercadoPago.preferenceAccessToken,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(
        (await checkoutStore.readOrderAccess(
          tenantId: _tenantId,
          orderId: 'order-frozen',
        ))
            ?.accessToken,
        mercadoPago.preferenceAccessToken,
      );
      expect(find.text('confirmation:order-frozen'), findsNothing);
      expect(cart.items.single.product.name, 'Producto nuevo del carrito');
      expect(
        (await checkoutStore.read(_tenantId))?.receipt?.orderId,
        'order-frozen',
      );
      expect(
        (await checkoutStore.read(_tenantId))?.cartConsumptionStatus,
        isNull,
      );

      mercadoPago.preferenceResult.complete({
        'init_point': 'https://www.mercadopago.cl/checkout',
      });
      await tester.pump();
      await tester.pump();
      expect(launcherCalls, containsAllInOrder(['canLaunch', 'launch']));
      expect(find.text('confirmation:order-frozen'), findsNothing);
      expect(cart.items.single.product.name, 'Producto nuevo del carrito');
      expect(
        (await checkoutStore.read(_tenantId))?.cartConsumptionStatus,
        isNull,
      );
    },
  );

  testWidgets(
    'a pre-RPC save failure rebuilds the retry from the latest payment choice',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 5000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = _FailFirstCheckoutSessionStorage();
      final checkoutStore = CheckoutSessionStore(storage: storage);
      final cart = CartProvider();
      await cart.restore(
        tenantId: _tenantId,
        loadProducts: (ids) async =>
            ids.map((_) => _currentCartProduct()).toList(growable: false),
      );
      cart.addProduct(_currentCartProduct());
      final exitGuard = CheckoutExitGuard();
      final website = _RetryWebsiteService();
      final editMode = WebsiteEditModeProvider();
      final account = CustomerAccountService();
      final autocomplete = _NoopAddressAutocompleteService();
      final mercadoPago = _ProbeMercadoPagoService();
      final tenant = PublicStoreTenantProvider(TenantDetectionService())
        ..setTenant(
          Tenant(
            id: _tenantId,
            shopName: 'VINABIKE',
            subdomain: 'vinabike',
            createdAt: DateTime.utc(2026, 7, 28),
            updatedAt: DateTime.utc(2026, 7, 28),
          ),
        );

      final router = GoRouter(
        initialLocation: '/checkout',
        routes: [
          GoRoute(
            path: '/checkout',
            builder: (_, __) => const Scaffold(
              body: CheckoutPage(
                capabilityLoader: _loadAllPaymentCapabilities,
              ),
            ),
          ),
          GoRoute(
            path: '/pedido/:id',
            builder: (_, state) => Scaffold(
              body: Text(
                'confirmation:${state.pathParameters['id']}',
              ),
            ),
          ),
        ],
      );

      addTearDown(router.dispose);
      addTearDown(cart.dispose);
      addTearDown(exitGuard.dispose);
      addTearDown(website.dispose);
      addTearDown(editMode.dispose);
      addTearDown(account.dispose);
      addTearDown(autocomplete.dispose);
      addTearDown(mercadoPago.dispose);
      addTearDown(tenant.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: cart),
            ChangeNotifierProvider.value(value: exitGuard),
            Provider.value(value: checkoutStore),
            ChangeNotifierProvider<WebsiteService>.value(value: website),
            ChangeNotifierProvider.value(value: editMode),
            ChangeNotifierProvider.value(value: account),
            ChangeNotifierProvider<AddressAutocompleteService>.value(
              value: autocomplete,
            ),
            ChangeNotifierProvider<MercadoPagoService>.value(
              value: mercadoPago,
            ),
            ChangeNotifierProvider.value(value: tenant),
          ],
          child: MaterialApp.router(
            theme: PublicStoreTheme.theme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final fields = find.byType(TextFormField);
      expect(fields, findsAtLeastNWidgets(3));
      await tester.enterText(fields.at(0), 'Cliente prueba');
      await tester.enterText(fields.at(1), 'cliente@example.com');
      await tester.enterText(fields.at(2), '+56 9 1111 1111');

      await tester.tap(find.text('Retiro en tienda'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('REALIZAR PEDIDO'));
      await tester.pump();
      await tester.pump();

      expect(storage.didFail, isTrue);
      expect(website.createOrderCalls, 0);
      expect(await checkoutStore.read(_tenantId), isNull);
      expect(exitGuard.isLocked, isFalse);
      expect(
        find.textContaining('El pedido no fue enviado'),
        findsAtLeastNWidgets(1),
      );

      // The failed durability boundary must leave these controls editable.
      // This choice is deliberately different from the failed attempt.
      await tester.tap(find.text('Transferencia bancaria'));
      await tester.pump();
      await tester.tap(find.text('REALIZAR PEDIDO'));

      await _pumpUntilFound(
        tester,
        find.text('confirmation:order-retry'),
      );

      expect(website.createOrderCalls, 1);
      expect(
        website.createdOrderData.single['payment_method'],
        'transfer',
      );
      expect(
        website.createdOrderData.single['delivery_type'],
        'pickup',
      );
      expect(mercadoPago.initializeCalls, 0);
      expect(find.text('confirmation:order-retry'), findsOneWidget);

      final saved = await checkoutStore.read(_tenantId);
      expect(saved, isNotNull);
      expect(saved!.handoff.paymentMethod, 'transfer');
      expect(saved.handoff.deliveryType, 'pickup');
      expect(saved.orderData['payment_method'], 'transfer');
      expect(saved.orderData['delivery_type'], 'pickup');
    },
  );

  testWidgets(
    'disposing during the pre-RPC save clears only that attempt and sends no order',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 5000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final storage = _BlockingCheckoutSessionStorage();
      final checkoutStore = CheckoutSessionStore(storage: storage);
      final cart = CartProvider();
      await cart.restore(
        tenantId: _tenantId,
        loadProducts: (ids) async =>
            ids.map((_) => _currentCartProduct()).toList(growable: false),
      );
      cart.addProduct(_currentCartProduct());
      final exitGuard = CheckoutExitGuard();
      final website = _RetryWebsiteService();
      final editMode = WebsiteEditModeProvider();
      final account = CustomerAccountService();
      final autocomplete = _NoopAddressAutocompleteService();
      final mercadoPago = _ProbeMercadoPagoService();
      final tenant = PublicStoreTenantProvider(TenantDetectionService())
        ..setTenant(
          Tenant(
            id: _tenantId,
            shopName: 'VINABIKE',
            subdomain: 'vinabike',
            createdAt: DateTime.utc(2026, 7, 28),
            updatedAt: DateTime.utc(2026, 7, 28),
          ),
        );
      final router = GoRouter(
        initialLocation: '/checkout',
        routes: [
          GoRoute(
            path: '/checkout',
            builder: (_, __) => const Scaffold(
              body: CheckoutPage(
                capabilityLoader: _loadAllPaymentCapabilities,
              ),
            ),
          ),
        ],
      );

      addTearDown(router.dispose);
      addTearDown(cart.dispose);
      addTearDown(exitGuard.dispose);
      addTearDown(website.dispose);
      addTearDown(editMode.dispose);
      addTearDown(account.dispose);
      addTearDown(autocomplete.dispose);
      addTearDown(mercadoPago.dispose);
      addTearDown(tenant.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: cart),
            ChangeNotifierProvider.value(value: exitGuard),
            Provider.value(value: checkoutStore),
            ChangeNotifierProvider<WebsiteService>.value(value: website),
            ChangeNotifierProvider.value(value: editMode),
            ChangeNotifierProvider.value(value: account),
            ChangeNotifierProvider<AddressAutocompleteService>.value(
              value: autocomplete,
            ),
            ChangeNotifierProvider<MercadoPagoService>.value(
              value: mercadoPago,
            ),
            ChangeNotifierProvider.value(value: tenant),
          ],
          child: MaterialApp.router(
            theme: PublicStoreTheme.theme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Cliente prueba');
      await tester.enterText(fields.at(1), 'cliente@example.com');
      await tester.enterText(fields.at(2), '+56 9 1111 1111');
      await tester.tap(find.text('Retiro en tienda'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('REALIZAR PEDIDO'));
      await tester.pump();
      await storage.writeStarted.future;

      expect(exitGuard.isLocked, isTrue);
      expect(exitGuard.phase, CheckoutExitPhase.preparingOrder);
      expect(website.createOrderCalls, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(exitGuard.isLocked, isFalse);
      storage.releaseWrite.complete();
      await tester.pump();
      await tester.pump();

      expect(website.createOrderCalls, 0);
      expect(await checkoutStore.read(_tenantId), isNull);
    },
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 10));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the expected widget.');
}

CheckoutSessionSnapshot _snapshot(DateTime savedAt) {
  return CheckoutSessionSnapshot.create(
    tenantId: _tenantId,
    savedAt: savedAt,
    idempotencyKey: _idempotencyKey,
    orderData: const {
      'tenant_id': _tenantId,
      'checkout_idempotency_key': _idempotencyKey,
      'customer_email': 'cliente@example.com',
      'customer_name': 'Cliente',
      'customer_phone': '+56911111111',
      'customer_address': 'Calle Uno 123',
      'delivery_type': 'shipping',
      'shipping_address_line1': 'Calle Uno 123',
      'shipping_address_line2': null,
      'shipping_city': 'Viña del Mar',
      'shipping_state': 'Valparaíso',
      'shipping_postal_code': '2520000',
      'shipping_country': 'Chile',
      'subtotal': 100000,
      'tax_amount': 19000,
      'shipping_quote_cost': 5000,
      'shipping_cost': 5000,
      'discount_amount': 0,
      'total': 124000,
      'status': 'pending',
      'payment_status': 'pending',
      'payment_method': 'mercadopago',
      'customer_notes': null,
    },
    orderItems: const [
      {
        'tenant_id': _tenantId,
        'product_id': 'ordered-product',
        'product_name': 'Producto del pedido guardado',
        'product_sku': 'ORDERED-1',
        'quantity': 1,
        'unit_price': 119000,
        'subtotal': 119000,
      },
    ],
    handoff: const CheckoutHandoffSnapshot(
      paymentMethod: 'mercadopago',
      deliveryType: 'shipping',
    ),
    cartRevision: 'cart-revision-$_idempotencyKey',
  );
}

Product _currentCartProduct() {
  return Product(
    id: 'new-cart-product',
    name: 'Producto nuevo del carrito',
    sku: 'NEW-1',
    price: 25000,
    cost: 0,
    stockQuantity: 10,
    trackStock: true,
    productType: ProductType.product,
    category: ProductCategory.other,
    taxRate: 19,
    createdAt: DateTime.utc(2026, 7, 28),
    updatedAt: DateTime.utc(2026, 7, 28),
  );
}

class _NoopAddressAutocompleteService extends AddressAutocompleteService {
  @override
  Future<void> initialize({String? tenantId}) async {}
}

class _FailFirstCheckoutSessionStorage implements CheckoutSessionStorage {
  final Map<String, String> _values = <String, String>{};
  bool didFail = false;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (!didFail && value.isNotEmpty) {
      didFail = true;
      throw StateError('simulated durable save failure');
    }
    if (value.isEmpty) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

class _BlockingCheckoutSessionStorage implements CheckoutSessionStorage {
  final Map<String, String> _values = <String, String>{};
  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> releaseWrite = Completer<void>();
  bool _blocked = false;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (!_blocked &&
        value.isNotEmpty &&
        key.startsWith('vinabike.public-checkout.v1.')) {
      _blocked = true;
      writeStarted.complete();
      await releaseWrite.future;
    }
    if (value.isEmpty) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

class _RetryWebsiteService extends WebsiteService {
  int createOrderCalls = 0;
  final List<Map<String, dynamic>> createdOrderData = [];

  @override
  Future<PublicShippingQuote> quotePublicShipping({
    required String tenantId,
    required String deliveryType,
    required int itemGross,
  }) async {
    if (deliveryType == 'pickup') {
      return PublicShippingQuote(
        deliveryType: deliveryType,
        itemGross: itemGross,
        shippingGross: 0,
        shippingNet: 0,
        shippingTax: 0,
        taxRate: 19,
        estimatedMinBusinessDays: 0,
        estimatedMaxBusinessDays: 0,
      );
    }
    return PublicShippingQuote(
      deliveryType: deliveryType,
      itemGross: itemGross,
      shippingGross: 5000,
      shippingNet: 4202,
      shippingTax: 798,
      taxRate: 19,
      estimatedMinBusinessDays: 3,
      estimatedMaxBusinessDays: 12,
    );
  }

  @override
  Future<PublicOrderCheckoutAccess> createOrder(
    Map<String, dynamic> orderData,
    List<Map<String, dynamic>> orderItems,
  ) async {
    createOrderCalls += 1;
    createdOrderData.add(Map<String, dynamic>.from(orderData));
    return PublicOrderCheckoutAccess(
      orderId: 'order-retry',
      accessToken:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      isReplay: false,
    );
  }
}

class _ProbeMercadoPagoService extends MercadoPagoService {
  int initializeCalls = 0;
  final Completer<void> preferenceStarted = Completer<void>();
  final Completer<Map<String, dynamic>> preferenceResult =
      Completer<Map<String, dynamic>>();
  String? preferenceOrderId;
  String? preferenceAccessToken;

  @override
  bool get isConfigured => true;

  @override
  Future<void> initialize({String? tenantId}) async {
    initializeCalls += 1;
  }

  @override
  Future<Map<String, dynamic>> createPreference({
    required String orderId,
    required String orderAccessToken,
  }) {
    preferenceOrderId = orderId;
    preferenceAccessToken = orderAccessToken;
    if (!preferenceStarted.isCompleted) preferenceStarted.complete();
    return preferenceResult.future;
  }
}
