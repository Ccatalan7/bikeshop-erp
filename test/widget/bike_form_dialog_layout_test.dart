import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/pages/bike_form_dialog.dart';

void main() {
  testWidgets(
    'technical navigator yields map height when desktop preview is constrained',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 380,
                height: 500,
                child: Column(
                  children: [
                    SizedBox(height: 90),
                    SizedBox(height: 14),
                    BikeTechnicalNavigatorController(
                      fitControllerToAvailableHeight: true,
                      child: ColoredBox(
                        key: Key('technical-map'),
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 12),
                    // Models the extra wrapped metadata row that appears after
                    // the mechanic confirms a front brake type.
                    SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final mapSize = tester.getSize(find.byKey(const Key('technical-map')));
      expect(mapSize.height, lessThan(380));
      expect(mapSize.width, mapSize.height);
    },
  );
}
