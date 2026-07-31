import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/models/public_order_access.dart';
import 'package:vinabike_erp/modules/website/models/website_models.dart';
import 'package:vinabike_erp/modules/website/services/mercadopago_service.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/pages/order_confirmation_page.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/checkout_session_store.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

void main() {
  const orderId = '97000000-0000-4000-8000-000000000020';

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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OrderConfirmationPage.clearCachesForTesting();
  });

  tearDown(() {
    OrderConfirmationPage.clearCachesForTesting();
  });

  testWidgets(
    'renders its state inside the unbounded public-store scroll column',
    (tester) async {
      final tenant = _tenantProvider();
      addTearDown(tenant.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider(
              create: (_) => CheckoutSessionStore(
                storage: MemoryCheckoutSessionStorage(),
              ),
            ),
            ChangeNotifierProvider.value(value: tenant),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    OrderConfirmationPage(orderId: orderId),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('NO PUDIMOS CARGAR TU PEDIDO'), findsOneWidget);
      expect(
        find.textContaining('Esta sesión no tiene acceso a ese pedido'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'transfer confirmation recovers a preserved warning and clears only its own receipt',
    (tester) async {
      final now = DateTime.utc(2026, 7, 28, 12);
      final storage = MemoryCheckoutSessionStorage();
      final store = CheckoutSessionStore(storage: storage, now: () => now);
      final snapshot =
          _transferSnapshot(now, orderId: orderId).closeCartConsumption(now);
      await store.save(snapshot);
      await store.saveOrderAccess(
        tenantId: _tenantId,
        access: snapshot.receipt!,
      );
      final tenant = _tenantProvider();
      final cart = CartProvider();
      addTearDown(tenant.dispose);
      addTearDown(cart.dispose);

      Widget confirmation() => MultiProvider(
            providers: [
              Provider.value(value: store),
              ChangeNotifierProvider.value(value: tenant),
              ChangeNotifierProvider.value(value: cart),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: OrderConfirmationPage(orderId: orderId),
                ),
              ),
            ),
          );

      await tester.pumpWidget(confirmation());
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(
          const ValueKey('checkout-cart-preservation-warning'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Tu pedido se completó. Revisa tu carrito: puede que aún contenga '
          'artículos comprados.',
        ),
        findsOneWidget,
      );
      expect(await store.read(_tenantId), isNull);
      expect(
        await store.hasCartPreservationWarning(
          tenantId: _tenantId,
          orderId: orderId,
        ),
        isTrue,
      );
      expect(find.text('VER CARRITO'), findsOneWidget);
      expect(find.text('ENTENDIDO'), findsOneWidget);
      expect(
        tester
            .getSize(find.widgetWithText(OutlinedButton, 'VER CARRITO'))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'ENTENDIDO')).height,
        greaterThanOrEqualTo(48),
      );

      // The receipt has already been retired. A new State must reconstruct the
      // warning from its independent durable marker, not from process memory.
      await tester.pumpWidget(const SizedBox.shrink());
      OrderConfirmationPage.clearCachesForTesting();
      await tester.pumpWidget(confirmation());
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(
          const ValueKey('checkout-cart-preservation-warning'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('ENTENDIDO'));
      await tester.pumpAndSettle();
      expect(
        await store.hasCartPreservationWarning(
          tenantId: _tenantId,
          orderId: orderId,
        ),
        isFalse,
      );
      expect(
        find.byKey(
          const ValueKey('checkout-cart-preservation-warning'),
        ),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      OrderConfirmationPage.clearCachesForTesting();
      await tester.pumpWidget(confirmation());
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(
          const ValueKey('checkout-cart-preservation-warning'),
        ),
        findsNothing,
      );

      // Let the intentionally provider-less order load fail and release its
      // delayed work before disposing the widget.
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'durable cart warning remains visible during a pending callback after receipt retirement',
    (tester) async {
      final store = CheckoutSessionStore(
        storage: MemoryCheckoutSessionStorage(),
      );
      await store.markCartPreservationWarning(
        tenantId: _tenantId,
        orderId: orderId,
      );
      final website = _FakeWebsiteService(
        responder: (_) async => _order(
          orderId: orderId,
          paymentStatus: 'pending',
        ),
      );
      final mercadoPago = _FakeMercadoPagoService(
        responder: (_, __) async => null,
      );

      await _pumpCallbackHarness(
        tester,
        orderId: orderId,
        initialStatus: 'pending',
        initialPaymentId: 'payment-pending',
        store: store,
        website: website,
        mercadoPago: mercadoPago,
      );

      expect(
        find.byKey(
          const ValueKey('checkout-cart-preservation-warning'),
        ),
        findsOneWidget,
      );
      expect(mercadoPago.verificationCalls, 0);
      expect(
        await store.hasCartPreservationWarning(
          tenantId: _tenantId,
          orderId: orderId,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'confirmation for another order leaves a transfer receipt untouched',
    (tester) async {
      const otherOrderId = '97000000-0000-4000-8000-000000000021';
      final now = DateTime.utc(2026, 7, 28, 12);
      final storage = MemoryCheckoutSessionStorage();
      final store = CheckoutSessionStore(storage: storage, now: () => now);
      final snapshot =
          _transferSnapshot(now, orderId: orderId).closeCartConsumption(now);
      await store.save(snapshot);
      await store.saveOrderAccess(
        tenantId: _tenantId,
        access: PublicOrderCheckoutAccess(
          orderId: otherOrderId,
          accessToken:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          expiresAt: now.add(const Duration(hours: 1)),
          isReplay: false,
        ),
      );
      final tenant = _tenantProvider();
      addTearDown(tenant.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider.value(value: store),
            ChangeNotifierProvider.value(value: tenant),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: OrderConfirmationPage(orderId: otherOrderId),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(
          const ValueKey('checkout-cart-preservation-warning'),
        ),
        findsNothing,
      );
      expect((await store.read(_tenantId))?.receipt?.orderId, orderId);

      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'pending Mercado Pago without callback exposes the replayable CTA',
    (tester) async {
      final website = _FakeWebsiteService(
        responder: (_) async => _order(
          orderId: orderId,
          paymentStatus: 'pending',
        ),
      );
      final mercadoPago = _FakeMercadoPagoService(
        responder: (_, __) async => null,
      );

      await _pumpCallbackHarness(
        tester,
        orderId: orderId,
        initialStatus: null,
        initialPaymentId: '',
        store: CheckoutSessionStore(
          storage: MemoryCheckoutSessionStorage(),
        ),
        website: website,
        mercadoPago: mercadoPago,
      );

      expect(find.text('REINTENTAR PAGO'), findsOneWidget);
      expect(mercadoPago.verificationCalls, 0);
    },
  );

  testWidgets(
    'native Mercado Pago retry treats a false launcher result as failure',
    (tester) async {
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

      final website = _FakeWebsiteService(
        responder: (_) async => _order(
          orderId: orderId,
          paymentStatus: 'pending',
        ),
      );
      final mercadoPago = _FakeMercadoPagoService(
        responder: (_, __) async => null,
        preference: const {
          'init_point': 'https://www.mercadopago.cl/checkout',
        },
      );
      await _pumpCallbackHarness(
        tester,
        orderId: orderId,
        initialStatus: null,
        initialPaymentId: '',
        store: CheckoutSessionStore(
          storage: MemoryCheckoutSessionStorage(),
        ),
        website: website,
        mercadoPago: mercadoPago,
      );

      final retryAction = find.text('REINTENTAR PAGO');
      await tester.ensureVisible(retryAction);
      await tester.pump();
      await tester.tap(retryAction);
      await tester.pump();
      await tester.pump();

      expect(launcherCalls, containsAllInOrder(['canLaunch', 'launch']));
      expect(
        find.text(
          'No pudimos reintentar el pago. '
          'Inténtalo nuevamente en unos minutos.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'no-status to approved in the same State refreshes stale order and clears exact snapshot',
    (tester) async {
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(
        storage: MemoryCheckoutSessionStorage(),
        now: () => now,
      );
      await store.save(_mercadoPagoAppliedSnapshot(now, orderId: orderId));
      final website = _FakeWebsiteService(
        responder: (call) async => _order(
          orderId: orderId,
          paymentStatus: call == 1 ? 'pending' : 'paid',
        ),
      );
      final mercadoPago = _FakeMercadoPagoService(
        responder: (_, __) async => {
          'status': 'approved',
          'order_id': orderId,
        },
      );
      final harness = await _pumpCallbackHarness(
        tester,
        orderId: orderId,
        initialStatus: null,
        initialPaymentId: '',
        store: store,
        website: website,
        mercadoPago: mercadoPago,
      );

      expect(website.orderLoadCalls, 1);
      expect(mercadoPago.verificationCalls, 0);
      expect(await store.read(_tenantId), isNotNull);

      harness.update(status: 'approved', paymentId: 'payment-1');
      await tester.pumpAndSettle();

      expect(mercadoPago.verificationCalls, 1);
      expect(website.orderLoadCalls, 2);
      expect(await store.read(_tenantId), isNull);
      expect(
        find.text('¡Pago exitoso! Tu pedido está siendo procesado.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'pending to approved processes the new callback and retains receipt until verification',
    (tester) async {
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(
        storage: MemoryCheckoutSessionStorage(),
        now: () => now,
      );
      await store.save(_mercadoPagoAppliedSnapshot(now, orderId: orderId));
      final website = _FakeWebsiteService(
        responder: (_) async => _order(
          orderId: orderId,
          paymentStatus: 'pending',
        ),
      );
      final mercadoPago = _FakeMercadoPagoService(
        responder: (_, __) async => {
          'status': 'approved',
          'order_id': orderId,
        },
      );
      final harness = await _pumpCallbackHarness(
        tester,
        orderId: orderId,
        initialStatus: 'pending',
        initialPaymentId: 'payment-2',
        store: store,
        website: website,
        mercadoPago: mercadoPago,
      );

      expect(mercadoPago.verificationCalls, 0);
      expect(await store.read(_tenantId), isNotNull);

      harness.update(status: 'approved', paymentId: 'payment-2');
      await tester.pumpAndSettle();

      expect(mercadoPago.verificationCalls, 1);
      expect(await store.read(_tenantId), isNull);
    },
  );

  testWidgets(
    'concurrent identical callback States claim one provider verification',
    (tester) async {
      final verification = Completer<Map<String, dynamic>?>();
      final website = _FakeWebsiteService(
        responder: (_) async => _order(
          orderId: orderId,
          paymentStatus: 'paid',
        ),
      );
      final mercadoPago = _FakeMercadoPagoService(
        responder: (_, __) => verification.future,
      );
      await _pumpCallbackHarness(
        tester,
        orderId: orderId,
        initialStatus: 'success',
        initialPaymentId: 'payment-shared',
        store: CheckoutSessionStore(
          storage: MemoryCheckoutSessionStorage(),
        ),
        website: website,
        mercadoPago: mercadoPago,
        pageCount: 2,
        settle: false,
      );
      await tester.pump();
      await tester.pump();

      expect(mercadoPago.verificationCalls, 1);
      verification.complete({
        'status': 'approved',
        'order_id': orderId,
      });
      await tester.pumpAndSettle();
      expect(mercadoPago.verificationCalls, 1);
    },
  );

  testWidgets(
    'changed payment id creates a distinct approved callback identity',
    (tester) async {
      final website = _FakeWebsiteService(
        responder: (_) async => _order(
          orderId: orderId,
          paymentStatus: 'paid',
        ),
      );
      final mercadoPago = _FakeMercadoPagoService(
        responder: (_, __) async => {
          'status': 'approved',
          'order_id': orderId,
        },
      );
      final harness = await _pumpCallbackHarness(
        tester,
        orderId: orderId,
        initialStatus: 'approved',
        initialPaymentId: 'payment-a',
        store: CheckoutSessionStore(
          storage: MemoryCheckoutSessionStorage(),
        ),
        website: website,
        mercadoPago: mercadoPago,
      );
      expect(mercadoPago.paymentIds, ['payment-a']);

      harness.update(status: 'approved', paymentId: 'payment-b');
      await tester.pumpAndSettle();

      expect(mercadoPago.paymentIds, ['payment-a', 'payment-b']);
    },
  );

  testWidgets(
    'null and exception verification attempts release the identical callback for retry',
    (tester) async {
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = CheckoutSessionStore(
        storage: MemoryCheckoutSessionStorage(),
        now: () => now,
      );
      await store.save(_mercadoPagoAppliedSnapshot(now, orderId: orderId));
      final website = _FakeWebsiteService(
        responder: (_) async => _order(
          orderId: orderId,
          paymentStatus: 'pending',
        ),
      );
      final mercadoPago = _FakeMercadoPagoService(
        responder: (call, _) async {
          if (call == 1) return null;
          if (call == 2) throw StateError('temporary provider error');
          return {
            'status': 'approved',
            'order_id': orderId,
          };
        },
      );
      final harness = await _pumpCallbackHarness(
        tester,
        orderId: orderId,
        initialStatus: 'approved',
        initialPaymentId: 'payment-retry',
        store: store,
        website: website,
        mercadoPago: mercadoPago,
      );
      expect(mercadoPago.verificationCalls, 1);
      expect(await store.read(_tenantId), isNotNull);

      harness.update(status: 'approved', paymentId: 'payment-retry');
      await tester.pumpAndSettle();
      expect(mercadoPago.verificationCalls, 2);
      expect(await store.read(_tenantId), isNotNull);

      harness.update(status: 'approved', paymentId: 'payment-retry');
      await tester.pumpAndSettle();
      expect(mercadoPago.verificationCalls, 3);
      expect(await store.read(_tenantId), isNull);
    },
  );

  testWidgets(
    'a stale no-status load cannot overwrite the callback-owned fresh generation',
    (tester) async {
      final staleLoad = Completer<OnlineOrder?>();
      final website = _FakeWebsiteService(
        responder: (call) {
          if (call == 1) return staleLoad.future;
          return Future.value(
            _order(orderId: orderId, paymentStatus: 'paid'),
          );
        },
      );
      final mercadoPago = _FakeMercadoPagoService(
        responder: (_, __) async => {
          'status': 'approved',
          'order_id': orderId,
        },
      );
      final harness = await _pumpCallbackHarness(
        tester,
        orderId: orderId,
        initialStatus: null,
        initialPaymentId: '',
        store: CheckoutSessionStore(
          storage: MemoryCheckoutSessionStorage(),
        ),
        website: website,
        mercadoPago: mercadoPago,
        settle: false,
      );
      await tester.pump();
      expect(website.orderLoadCalls, 1);

      harness.update(status: 'approved', paymentId: 'payment-fresh');
      await tester.pumpAndSettle();
      expect(website.orderLoadCalls, 2);
      expect(
        find.text('¡Pago exitoso! Tu pedido está siendo procesado.'),
        findsOneWidget,
      );

      staleLoad.complete(
        _order(orderId: orderId, paymentStatus: 'pending'),
      );
      await tester.pumpAndSettle();
      expect(website.orderLoadCalls, 2);
      expect(
        find.text('¡Pago exitoso! Tu pedido está siendo procesado.'),
        findsOneWidget,
      );
    },
  );
}

const _tenantId = 'tenant-order-confirmation';
const _idempotencyKey = '77777777-7777-4777-8777-777777777777';

PublicStoreTenantProvider _tenantProvider() {
  return PublicStoreTenantProvider(TenantDetectionService())
    ..setTenant(
      Tenant(
        id: _tenantId,
        shopName: 'VINABIKE',
        subdomain: 'vinabike',
        createdAt: DateTime.utc(2026, 7, 28),
        updatedAt: DateTime.utc(2026, 7, 28),
      ),
    );
}

CheckoutSessionSnapshot _transferSnapshot(
  DateTime now, {
  required String orderId,
}) =>
    _checkoutSnapshot(
      now,
      orderId: orderId,
      paymentMethod: 'transfer',
    );

CheckoutSessionSnapshot _mercadoPagoAppliedSnapshot(
  DateTime now, {
  required String orderId,
}) =>
    _checkoutSnapshot(
      now,
      orderId: orderId,
      paymentMethod: 'mercadopago',
    ).closeCartConsumption(now).markCartConsumptionApplied();

CheckoutSessionSnapshot _checkoutSnapshot(
  DateTime now, {
  required String orderId,
  required String paymentMethod,
}) {
  return CheckoutSessionSnapshot.create(
    tenantId: _tenantId,
    savedAt: now,
    idempotencyKey: _idempotencyKey,
    orderData: {
      'tenant_id': _tenantId,
      'checkout_idempotency_key': _idempotencyKey,
      'customer_email': 'cliente@example.com',
      'customer_name': 'Cliente',
      'customer_address': 'Calle Uno 123',
      'delivery_type': 'shipping',
      'subtotal': 1000,
      'tax_amount': 190,
      'shipping_quote_cost': 0,
      'shipping_cost': 0,
      'discount_amount': 0,
      'total': 1190,
      'status': 'pending',
      'payment_status': 'pending',
      'payment_method': paymentMethod,
    },
    orderItems: const [
      {
        'tenant_id': _tenantId,
        'product_id': 'product-1',
        'product_name': 'Producto Uno',
        'quantity': 1,
        'unit_price': 1190,
        'subtotal': 1190,
      },
    ],
    handoff: CheckoutHandoffSnapshot(
      paymentMethod: paymentMethod,
      deliveryType: 'shipping',
    ),
    cartRevision: 'cart-revision-$_idempotencyKey',
  ).withReceipt(
    PublicOrderCheckoutAccess(
      orderId: orderId,
      accessToken:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      expiresAt: now.add(const Duration(hours: 1)),
      isReplay: false,
    ),
  );
}

typedef _OrderResponder = FutureOr<OnlineOrder?> Function(int call);
typedef _PaymentResponder = FutureOr<Map<String, dynamic>?> Function(
  int call,
  String paymentId,
);

class _FakeWebsiteService extends WebsiteService {
  _FakeWebsiteService({required this.responder});

  final _OrderResponder responder;
  int orderLoadCalls = 0;

  @override
  Future<Map<String, String>> loadSettingsForTenant(
    String tenantId, {
    bool rethrowErrors = false,
  }) async =>
      const {};

  @override
  Future<OnlineOrder?> getPublicOrderById({
    required String orderId,
    required String accessToken,
  }) async {
    orderLoadCalls++;
    return await responder(orderLoadCalls);
  }
}

class _FakeMercadoPagoService extends MercadoPagoService {
  _FakeMercadoPagoService({
    required this.responder,
    this.preference,
  });

  final _PaymentResponder responder;
  final Map<String, dynamic>? preference;
  int verificationCalls = 0;
  final List<String> paymentIds = [];

  @override
  bool get isConfigured => true;

  @override
  Future<void> initialize({String? tenantId}) async {}

  @override
  Future<Map<String, dynamic>> createPreference({
    required String orderId,
    required String orderAccessToken,
  }) async {
    final value = preference;
    if (value == null) {
      throw StateError('Unexpected preference creation.');
    }
    return value;
  }

  @override
  Future<Map<String, dynamic>?> getPaymentStatus(
    String paymentId, {
    required String orderId,
    required String orderAccessToken,
  }) async {
    verificationCalls++;
    paymentIds.add(paymentId);
    return await responder(verificationCalls, paymentId);
  }
}

class _CallbackRouteState {
  const _CallbackRouteState({
    required this.status,
    required this.paymentId,
  });

  final String? status;
  final String paymentId;
}

class _CallbackHarness {
  const _CallbackHarness(this.route);

  final ValueNotifier<_CallbackRouteState> route;

  void update({
    required String? status,
    required String paymentId,
  }) {
    route.value = _CallbackRouteState(
      status: status,
      paymentId: paymentId,
    );
  }
}

Future<_CallbackHarness> _pumpCallbackHarness(
  WidgetTester tester, {
  required String orderId,
  required String? initialStatus,
  required String initialPaymentId,
  required CheckoutSessionStore store,
  required _FakeWebsiteService website,
  required _FakeMercadoPagoService mercadoPago,
  int pageCount = 1,
  bool settle = true,
}) async {
  final route = ValueNotifier(
    _CallbackRouteState(
      status: initialStatus,
      paymentId: initialPaymentId,
    ),
  );
  final tenant = _tenantProvider();
  final cart = CartProvider();
  await store.saveOrderAccess(
    tenantId: _tenantId,
    access: PublicOrderCheckoutAccess(
      orderId: orderId,
      accessToken:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      expiresAt: DateTime.utc(2026, 8, 28, 13),
      isReplay: false,
    ),
  );

  addTearDown(route.dispose);
  addTearDown(tenant.dispose);
  addTearDown(cart.dispose);
  addTearDown(website.dispose);
  addTearDown(mercadoPago.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider.value(value: store),
        ChangeNotifierProvider<PublicStoreTenantProvider>.value(
          value: tenant,
        ),
        ChangeNotifierProvider<WebsiteService>.value(value: website),
        ChangeNotifierProvider<MercadoPagoService>.value(
          value: mercadoPago,
        ),
        ChangeNotifierProvider<CartProvider>.value(value: cart),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<_CallbackRouteState>(
              valueListenable: route,
              builder: (context, value, _) {
                return Column(
                  children: [
                    for (var index = 0; index < pageCount; index++)
                      OrderConfirmationPage(
                        key: ValueKey('callback-page-$index'),
                        orderId: orderId,
                        paymentStatus: value.status,
                        callbackUriProvider: () => Uri(
                          path: '/pedido/$orderId',
                          queryParameters: value.paymentId.isEmpty
                              ? null
                              : {'payment_id': value.paymentId},
                        ),
                        orderLoadDelay: Duration.zero,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
  return _CallbackHarness(route);
}

OnlineOrder _order({
  required String orderId,
  required String paymentStatus,
}) {
  final now = DateTime.utc(2026, 7, 28, 12);
  return OnlineOrder(
    id: orderId,
    tenantId: _tenantId,
    orderNumber: 'WEB-100',
    customerEmail: 'cliente@example.com',
    customerName: 'Cliente',
    deliveryType: 'shipping',
    subtotal: 1000,
    taxAmount: 190,
    shippingCost: 0,
    discountAmount: 0,
    total: 1190,
    status: 'pending',
    paymentStatus: paymentStatus,
    paymentMethod: 'mercadopago',
    createdAt: now,
    updatedAt: now,
  );
}
