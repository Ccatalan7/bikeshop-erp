import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/pages/order_confirmation_page.dart';
import 'package:vinabike_erp/public_store/services/public_order_access_token_store.dart';

void main() {
  const orderId = '97000000-0000-4000-8000-000000000020';

  tearDown(PublicOrderAccessTokenStore.clearMemoryForTesting);

  testWidgets(
    'renders its state inside the unbounded public-store scroll column',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
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
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('NO PUDIMOS CARGAR TU PEDIDO'), findsOneWidget);
      expect(
        find.textContaining('Esta sesión no tiene acceso a ese pedido'),
        findsOneWidget,
      );
    },
  );
}
