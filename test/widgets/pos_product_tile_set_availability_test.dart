import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/pos/widgets/product_tile.dart';
import 'package:vinabike_erp/shared/models/product.dart';

void main() {
  testWidgets('POS enables a set from derived component availability',
      (tester) async {
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
    await tester.tap(find.byType(InkWell).first);
    expect(taps, 1);
  });

  testWidgets('POS blocks a set when no complete set can be assembled',
      (tester) async {
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
    await tester.tap(find.byType(InkWell).first);
    expect(taps, 0);
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
