import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/bike_diagram_illustration.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/bike_system_controller.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  Widget buildController(
    Key controllerKey,
    ValueChanged<String> onSelected, {
    Size size = const Size.square(520),
    Brightness brightness = Brightness.light,
  }) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: size,
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

  testWidgets('phone and desktop map labels stay inside and remain selectable',
      (tester) async {
    for (final (size, brightness) in [
      (const Size(430, 560), Brightness.dark),
      (const Size(320, 260), Brightness.light),
    ]) {
      String? selected;
      await tester.pumpWidget(buildController(
        ValueKey(size),
        (value) => selected = value,
        size: size,
        brightness: brightness,
      ));
      final bounds = tester.getRect(find.byType(BikeSystemController));
      for (final spec in kBikeSystemControllerSpecs) {
        final label = tester.getRect(find.text(spec.label));
        expect(label.left, greaterThanOrEqualTo(bounds.left));
        expect(label.right, lessThanOrEqualTo(bounds.right));
        expect(label.top, greaterThanOrEqualTo(bounds.top));
        expect(label.bottom, lessThanOrEqualTo(bounds.bottom));
      }
      await tester.tap(find.text('Rueda delantera'));
      expect(selected, 'front_wheel');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Vista general'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Rueda trasera'));
      expect(selected, 'rear_wheel');
      expect(tester.takeException(), isNull);
    }
  });
}
