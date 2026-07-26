import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/pos/widgets/product_tile.dart';
import 'package:vinabike_erp/shared/models/product.dart';

void main() {
  testWidgets('POS enables a set from derived component availability',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 300,
            child: ProductTile(
              product: _setProduct(fullSetsAvailable: 2),
              onTap: () => taps += 1,
            ),
          ),
        ),
      ),
    );

    expect(find.text('2 un.'), findsOneWidget);
    expect(find.text('Agotado'), findsNothing);
    final addAction = find.bySemanticsLabel(
      'Agregar Juego de frenos al carrito, \$ 48.000, 2 disponibles',
    );
    expect(addAction, findsOneWidget);
    final addSemantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Agregar Juego de frenos al carrito, '
                    '\$ 48.000, 2 disponibles',
      ),
    );
    expect(addSemantics.properties.button, isTrue);
    expect(addSemantics.properties.enabled, isTrue);
    expect(addSemantics.properties.onTap, isNotNull);

    await tester.tap(addAction);
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('POS blocks a set when no complete set can be assembled',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 300,
            child: ProductTile(
              product: _setProduct(fullSetsAvailable: 0),
              onTap: () => taps += 1,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Agotado'), findsOneWidget);
    final unavailableAction = find.bySemanticsLabel('Juego de frenos, agotado');
    expect(unavailableAction, findsOneWidget);
    final unavailableSemantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Juego de frenos, agotado',
      ),
    );
    expect(unavailableSemantics.properties.button, isTrue);
    expect(unavailableSemantics.properties.enabled, isFalse);
    expect(unavailableSemantics.properties.onTap, isNull);

    await tester.tap(unavailableAction);
    expect(taps, 0);
    await tester.tap(find.byType(InkWell).first);
    expect(taps, 0);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

Product _setProduct({required int fullSetsAvailable}) {
  final now = DateTime(2026, 7, 21);
  return Product(
    id: 'set-1',
    name: 'Juego de frenos',
    sku: 'SET-1',
    price: 48000,
    cost: 22520,
    // A set header deliberately has no independent physical stock.
    stockQuantity: 0,
    fullSetsAvailable: fullSetsAvailable,
    category: ProductCategory.parts,
    isSet: true,
    createdAt: now,
    updatedAt: now,
  );
}
