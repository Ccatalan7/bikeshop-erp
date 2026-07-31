import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/website/services/mercadopago_service.dart';
import '../pages/checkout_page.dart';
import '../pages/order_confirmation_page.dart';
import '../services/address_autocomplete_service.dart';
import '../services/checkout_session_store.dart';

final CheckoutSessionStore _checkoutSessionStore =
    CheckoutSessionStore.platform();

Widget buildCommerceRoutePage({
  required String routeKey,
  required String? tenantId,
  String? orderId,
  String? paymentStatus,
}) {
  final page = switch (routeKey) {
    'checkout' => const CheckoutPage(),
    'orderConfirmation' => OrderConfirmationPage(
        orderId: orderId ?? '',
        paymentStatus: paymentStatus,
      ),
    _ => const SizedBox.shrink(),
  };

  return Provider<CheckoutSessionStore>.value(
    // Checkout and confirmation live in this one deferred library and share
    // the same durable single-flight store without pulling its implementation
    // into the storefront's critical JavaScript unit.
    value: _checkoutSessionStore,
    child: ChangeNotifierProvider<MercadoPagoService>(
      // Tenant detection may finish after a direct checkout deep-link mounts.
      // Recreate the route-scoped service when that identity becomes available,
      // matching the update behavior of the former root ProxyProvider.
      key: ValueKey<String?>(tenantId),
      create: (_) {
        final service = MercadoPagoService();
        if (tenantId != null && tenantId.isNotEmpty) {
          service.setTenantId(tenantId);
        }
        return service;
      },
      child: routeKey == 'checkout'
          ? ChangeNotifierProvider<AddressAutocompleteService>(
              create: (_) => AddressAutocompleteService(),
              child: page,
            )
          : page,
    ),
  );
}
