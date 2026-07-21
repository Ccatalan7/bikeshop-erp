import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/inventory/widgets/set_configuration_widget.dart';
import 'package:vinabike_erp/shared/models/product.dart';

void main() {
  testWidgets('component quantity is explicit and propagated', (tester) async {
    var components = const [
      SetComponentDraft(
        label: 'Delantero',
        name: 'Freno delantero',
        skuSuffix: 'FRONT',
        position: 1,
        quantityInSet: 1,
        cost: 5000,
        price: 10000,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SetConfigurationWidget(
              isSet: true,
              setType: SetType.custom,
              components: components,
              onIsSetChanged: (_) {},
              onSetTypeChanged: (_) {},
              onComponentsChanged: (value) => components = value,
              parentProductName: 'Juego de frenos',
              parentProductSku: 'SET-1',
              parentPrice: 10000,
              parentCost: 5000,
            ),
          ),
        ),
      ),
    );

    final quantityField = find.byKey(const ValueKey('quantity_0_1'));
    expect(quantityField, findsOneWidget);
    await tester.enterText(quantityField, '2');
    await tester.pump();

    expect(components.single.quantityInSet, 2);
  });

  testWidgets('existing ordinary product cannot promise unsupported conversion',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SetConfigurationWidget(
            isSet: false,
            canChangeSetStatus: false,
            components: const [],
            onIsSetChanged: (_) {},
            onSetTypeChanged: (_) {},
            onComponentsChanged: (_) {},
            parentProductName: 'Producto existente',
            parentProductSku: 'P-1',
            parentPrice: 1000,
            parentCost: 500,
          ),
        ),
      ),
    );

    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.onChanged, isNull);
    expect(find.textContaining('no se convierte en juego'), findsOneWidget);
  });
}
