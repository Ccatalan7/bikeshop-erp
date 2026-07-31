import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/library_source.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  test('public checkout and confirmation share the opaque token contract', () {
    final service = readLibrarySource(
      'lib/modules/website/services/website_service.dart',
    );
    final checkout = source('lib/public_store/pages/checkout_page.dart');
    final confirmation = source(
      'lib/public_store/pages/order_confirmation_page.dart',
    );

    expect(service, contains('create_public_online_order_with_access'));
    expect(service, contains('get_public_online_order_by_access_token'));
    expect(service, isNot(contains("rpc('get_public_online_order',")));

    // Whitespace-normalized so the ordering contract never depends on
    // formatter line breaks.
    final normalizedCheckout = checkout.replaceAll(RegExp(r'\s+'), ' ');
    final saveToken =
        normalizedCheckout.indexOf('await store.saveOrderAccess(');
    final createPreference = normalizedCheckout.indexOf(
      'mercadopagoService.createPreference(',
    );
    // Confirmation navigation goes through the canonical storefront
    // navigation boundary, not a raw context.go.
    final confirmationNavigation = normalizedCheckout.indexOf(
      'await PublicStoreLayout.navigateToHref( context, '
      "'/tienda/pedido/\${checkoutAccess.orderId}',",
    );
    expect(saveToken, greaterThan(0));
    expect(createPreference, greaterThan(saveToken));
    expect(confirmationNavigation, greaterThan(saveToken));

    expect(confirmation, contains('readOrderAccess('));
    expect(confirmation, contains('saveOrderAccess('));
    expect(confirmation, contains('orderAccessToken:'));
  });

  test('order confirmation delegates scrolling to the public store shell', () {
    final confirmation = source(
      'lib/public_store/pages/order_confirmation_page.dart',
    );
    final layout = readLibrarySource(
      'lib/public_store/widgets/public_store_layout.dart',
    );

    expect(layout, contains("path.startsWith('/pedido/')"));
    expect(layout, contains('_PublicStoreScrollView('));
    expect(
      confirmation,
      isNot(contains('SingleChildScrollView(')),
      reason: 'A nested vertical viewport receives unbounded height inside '
          'PublicStoreLayout and breaks the confirmation page on Flutter Web.',
    );
  });

  test('Mercado Pago authorizes token before every service-role order read',
      () {
    final preference = source(
      'supabase/functions/mercadopago-create-preference/index.ts',
    );
    final payment = source(
      'supabase/functions/mercadopago-get-payment/index.ts',
    );
    final service = source(
      'lib/modules/website/services/mercadopago_service.dart',
    );

    for (final edgeSource in [preference, payment]) {
      final authorize = edgeSource.indexOf(
        'await authorizePublicOrderAccess(supabase, requestBody)',
      );
      final privilegedRead = edgeSource.indexOf('.from("online_orders")');
      expect(authorize, greaterThan(0));
      expect(privilegedRead, greaterThan(authorize));
      expect(edgeSource, isNot(contains('console.log(order_access_token')));
      expect(edgeSource, isNot(contains('console.error(order_access_token')));
    }

    expect(service, contains("'order_access_token': orderAccessToken"));
    final preferenceMethod = service.indexOf(
      'Future<Map<String, dynamic>> createPreference(',
    );
    final paymentMethod = service.indexOf(
      'Future<Map<String, dynamic>?> getPaymentStatus(',
    );
    final callbackMethod = service.indexOf(
      'Future<void> processPaymentCallback(',
    );
    expect(
      service.substring(preferenceMethod, paymentMethod),
      isNot(contains("'tenant_id'")),
    );
    expect(
      service.substring(paymentMethod, callbackMethod),
      isNot(contains("'tenant_id'")),
    );
  });

  test('Mercado Pago preference lifecycle is replayable and server-owned', () {
    final preference = source(
      'supabase/functions/mercadopago-create-preference/index.ts',
    );
    final worker = source(
      'supabase/functions/mercadopago-expire-preferences/index.ts',
    );
    final payment = source(
      'supabase/functions/mercadopago-get-payment/index.ts',
    );
    final service = source(
      'lib/modules/website/services/mercadopago_service.dart',
    );

    expect(preference, contains('begin_mercadopago_preference_creation'));
    expect(preference, contains('/checkout/preferences/search'));
    expect(preference, contains('parseRecoverableMercadoPagoPreference'));
    expect(preference, contains('expiration_date_to: expiresAt'));
    expect(preference, contains('finalize_mercadopago_preference_creation'));
    expect(preference, contains('notification_url: notificationUrl'));
    expect(preference, isNot(contains('X-Idempotency-Key')));

    expect(worker, contains('x-mercadopago-preference-worker-secret'));
    expect(worker, contains('claim_mercadopago_preference_expirations'));
    expect(worker, contains('expireMercadoPagoPreferencePayload'));
    expect(worker, contains('complete_mercadopago_preference_expiration'));
    expect(payment, contains('order_id: paymentIdentity.orderId'));
    expect(payment, isNot(contains('external_reference: externalReference')));

    final preferenceMethod = service.indexOf(
      'Future<Map<String, dynamic>> createPreference(',
    );
    final paymentMethod = service.indexOf(
      'Future<Map<String, dynamic>?> getPaymentStatus(',
    );
    final preferenceClient = service.substring(preferenceMethod, paymentMethod);
    expect(preferenceClient, contains("'order_id': orderId"));
    expect(
        preferenceClient, contains("'order_access_token': orderAccessToken"));
    expect(preferenceClient, isNot(contains("'amount'")));
    expect(preferenceClient, isNot(contains("'shipping_cost'")));
    expect(preferenceClient, isNot(contains("'notification_url'")));
    expect(
      preferenceClient,
      isNot(contains('Error creating payment preference: \${response.data}')),
    );

    final checkout = source('lib/public_store/pages/checkout_page.dart');
    expect(checkout, isNot(contains('init_point: \$initPoint')));
    expect(
      checkout,
      isNot(contains('Redirecting to MercadoPago: \$initPoint')),
    );
  });

  test('router keeps bearer credentials out of query parameters', () {
    final publicRouter = source(
      'lib/public_store/routes/public_store_router.dart',
    );
    final appRouter = source('lib/shared/routes/app_router.dart');

    expect(publicRouter, isNot(contains("queryParameters['access_token']")));
    expect(publicRouter, isNot(contains("queryParameters['order_token']")));
    expect(appRouter, isNot(contains("queryParameters['access_token']")));
    expect(appRouter, isNot(contains("queryParameters['order_token']")));
  });

  test('canonical surface registry records checkout, confirmation and payment',
      () {
    final registry = source('docs/architecture/canonical-ui-surfaces.md');

    expect(registry, contains('| Public checkout access |'));
    expect(registry, contains('| Public order confirmation |'));
    expect(registry, contains('| Public Mercado Pago authorization |'));
    expect(
      registry,
      matches(
        RegExp(
          r'bearer token[^.\n]*never enters route/query',
          caseSensitive: false,
        ),
      ),
    );
  });

  test('cancelled public orders cannot masquerade as pending payments', () {
    final confirmation = source(
      'lib/public_store/pages/order_confirmation_page.dart',
    );
    final policy = source(
      'lib/public_store/models/order_confirmation_policy.dart',
    );
    final pdf = source(
      'lib/public_store/pages/order_confirmation_pdf.dart',
    );

    expect(policy, contains('if (order.isCancelled)'));
    expect(
      policy.indexOf('if (order.isCancelled)'),
      lessThan(policy.indexOf('if (order.hasRecordedPayment)')),
    );
    expect(confirmation, contains("return 'PEDIDO CANCELADO';"));
    expect(
      confirmation,
      contains('DESCARGAR RESUMEN DEL PEDIDO'),
    );
    expect(confirmation, isNot(contains('DESCARGAR COMPROBANTE')));
    expect(pdf, contains('No acredita pago'));
    expect(pdf, isNot(contains("title: 'Comprobante de pedido")));
  });

  test('official document manifests are validated before dry-run and send', () {
    final worker = source(
      'supabase/functions/send-transactional-order-email/index.ts',
    );
    final validation = worker.indexOf('validateAttachmentDeliveryPolicy(');
    final dryRun = worker.indexOf('requestedMode === "dry_run"');
    final send = worker.indexOf('sendWithResend({');

    expect(validation, greaterThan(0));
    expect(dryRun, greaterThan(validation));
    expect(send, greaterThan(dryRun));
    expect(worker, isNot(contains('unsupported_attachment_manifest')));
    expect(worker, contains('attachment_policy: attachmentPolicy'));
  });
}
