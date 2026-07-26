import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/pos/widgets/pos_quantity_stepper.dart';

void main() {
  testWidgets(
    'phone quantity stepper keeps exact touch targets and labelled callbacks',
    (tester) async {
      tester.view.physicalSize = const Size(384, 824);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      var decrements = 0;
      var increments = 0;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: PosQuantityStepper(
                itemName: 'Cubre cámara',
                quantity: 25,
                onDecrement: () => decrements++,
                onIncrement: () => increments++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final decrement =
          find.bySemanticsLabel('Disminuir cantidad de Cubre cámara');
      final increment =
          find.bySemanticsLabel('Aumentar cantidad de Cubre cámara');

      expect(decrement, findsOneWidget);
      expect(increment, findsOneWidget);
      expect(find.bySemanticsLabel('Cantidad 25'), findsOneWidget);
      expect(tester.getSize(decrement), const Size(48, 48));
      expect(tester.getSize(increment), const Size(48, 48));
      expect(
        tester.getSize(find.byType(PosQuantityStepper)),
        const Size(144, 48),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(decrement);
      await tester.tap(increment);
      await tester.pump();

      expect(decrements, 1);
      expect(increments, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
