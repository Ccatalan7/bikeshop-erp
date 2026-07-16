import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/bike_diagram_illustration.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/bike_system_controller.dart';

void main() {
  Widget buildController(
    Key controllerKey,
    ValueChanged<String> onSelected,
  ) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.square(
            dimension: 520,
            child: BikeSystemController(
              key: controllerKey,
              variant: BikeDiagramVariant.mountainFullSuspension,
              bike: null,
              entries: kBikeSystemControllerSpecs
                  .map(
                    (spec) => BikeSystemControllerEntry(
                      spec: spec,
                      status: BikeSystemOverallStatus.unknown,
                    ),
                  )
                  .toList(growable: false),
              selectedSystemKey: null,
              onSystemSelected: onSelected,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('labels on both sides are part of each map hit target',
      (tester) async {
    String? selected;
    await tester.pumpWidget(
      buildController(
          const ValueKey('right-label'), (value) => selected = value),
    );

    await tester.tap(find.text('Cockpit / dirección'));
    expect(selected, 'cockpit');

    selected = null;
    await tester.pumpWidget(
      buildController(
          const ValueKey('left-label'), (value) => selected = value),
    );
    await tester.tap(find.text('Transmisión'));
    expect(selected, 'drivetrain');
  });
}
