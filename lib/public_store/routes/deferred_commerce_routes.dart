import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/website/services/mercadopago_service.dart';
import '../pages/checkout_page.dart';
import '../pages/order_confirmation_page.dart';
import '../services/address_autocomplete_service.dart';

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

  return ChangeNotifierProvider<MercadoPagoService>(
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
  );
}
