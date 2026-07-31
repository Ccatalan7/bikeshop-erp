import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer portal screens stay outside the storefront initial unit', () {
    final router = File('lib/public_store/routes/public_store_router.dart')
        .readAsStringSync();
    final deferredRoutes = File(
      'lib/public_store/routes/deferred_customer_routes.dart',
    ).readAsStringSync();
    final deferredCommerce = File(
      'lib/public_store/routes/deferred_commerce_routes.dart',
    ).readAsStringSync();
    final standaloneMain = File('lib/main_store.dart').readAsStringSync();

    expect(router, contains("import 'deferred_customer_route_page.dart';"));
    expect(
      router,
      isNot(contains("import '../pages/customer_dashboard_page.dart';")),
    );
    expect(
      router,
      isNot(contains("import '../pages/customer_chat_hub_page.dart';")),
    );
    expect(
      router,
      contains("path: '/cuenta'"),
    );
    expect(
      router,
      contains("DeferredCustomerRoutePage(routeKey: 'dashboard')"),
    );
    expect(deferredRoutes, contains('CustomerDashboardPage'));
    expect(deferredRoutes, contains('CustomerChatHubPage'));
    expect(router, isNot(contains("import '../pages/checkout_page.dart';")));
    expect(
      router,
      contains("DeferredCommerceRoutePage(routeKey: 'checkout')"),
    );
    expect(deferredCommerce, contains('CheckoutPage'));
    expect(deferredCommerce, contains('MercadoPagoService'));
    expect(deferredCommerce, contains('CheckoutSessionStore.platform()'));
    expect(
      standaloneMain,
      isNot(contains("services/checkout_session_store.dart")),
    );
    expect(
      standaloneMain,
      isNot(contains('CheckoutSessionStore.platform()')),
    );
  });
}
