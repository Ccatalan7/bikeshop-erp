import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/public_store/pages/cart_page.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/shared/models/product.dart';

Product _product(String id, String name, double price) => Product(
      id: id,
      name: name,
      sku: id.toUpperCase(),
      price: price,
      cost: 0,
      stockQuantity: 5,
      category: ProductCategory.other,
      taxRate: 19,
      createdAt: DateTime.utc(2026, 10, 24),
      updatedAt: DateTime.utc(2026, 10, 24),
    );

void main() {
  // The cart as the HTML `/carrito` draws it (2026-10-24): titles as written,
  // no overflow from a phone to a desktop, in light and dark.
  for (final brightness in Brightness.values) {
    for (final size in const [Size(1440, 1200), Size(390, 1600)]) {
      testWidgets(
        'cart at ${size.width.toInt()} in $brightness keeps its words',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final cart = CartProvider()
            ..addProduct(
              _product('k29', 'Neumático Kenda Small Block 8 29 x 2.10', 18990),
            )
            ..addProduct(
              _product('c29', 'Cámara Kenda 29 x 1.9-2.3 válvula auto', 4990),
              quantity: 2,
            );
          addTearDown(cart.dispose);

          await tester.pumpWidget(
            ChangeNotifierProvider<CartProvider>.value(
              value: cart,
              child: MaterialApp(
                theme: ThemeData(useMaterial3: true, brightness: brightness),
                home: const Scaffold(
                  body: SingleChildScrollView(child: CartPage()),
                ),
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.text('Carrito de compras'), findsOneWidget);
          expect(find.text('3 unidades en revisión'), findsOneWidget);
          expect(
            find.text('Neumático Kenda Small Block 8 29 x 2.10'),
            findsOneWidget,
          );
          expect(find.text('Resumen del pedido'), findsOneWidget);
          expect(find.text('Proceder al pago'), findsOneWidget);
          expect(find.text('Seguir comprando'), findsOneWidget);
          // 18.990 + 2 × 4.990, IVA included.
          expect(find.text(r'$ 28.970'), findsOneWidget);
          expect(find.bySemanticsLabel('Agregar una unidad'), findsNWidgets(2));
          // Without a store tenant there is nothing to suggest.
          expect(find.text('Te puede faltar'.toUpperCase()), findsNothing);
        },
      );
    }
  }
}
