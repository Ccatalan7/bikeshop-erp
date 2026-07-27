import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/workshop_mobile_bike_chooser.dart';

const _customerId = 'customer-1';

Bike _bike({
  required String id,
  required String brand,
  required String model,
  required String serialNumber,
  required String color,
}) {
  return Bike(
    id: id,
    tenantId: 'tenant-1',
    customerId: _customerId,
    brand: brand,
    model: model,
    serialNumber: serialNumber,
    color: color,
  );
}

Future<void> _pumpChooser(
  WidgetTester tester, {
  required Size viewport,
  required List<Bike> bikes,
  required ValueChanged<Bike> onSelected,
  required VoidCallback onClose,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        );
      },
      home: Scaffold(
        body: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: WorkshopMobileBikeChooser(
              jobLabel: 'PG-00479',
              linkedBikeCount: bikes.length,
              bikes: bikes,
              onSelected: onSelected,
              onClose: onClose,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final firstBike = _bike(
    id: 'bike-primary',
    brand: 'Polygon',
    model: 'Siskiu T8',
    serialNumber: 'POLYGON-001',
    color: 'Grafito',
  );
  final secondBike = _bike(
    id: 'bike-secondary',
    brand: 'Specialized',
    model: 'Turbo Levo Comp Carbon de prueba',
    serialNumber: 'SPECIALIZED-SECONDARY-002',
    color: 'Rojo',
  );
  final bikes = <Bike>[firstBike, secondBike];

  testWidgets(
    'chooser returns the exact bike with accessible targets across widths',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      const viewports = <Size>[
        Size(384, 824),
        Size(599, 824),
        Size(600, 824),
        Size(899, 824),
        Size(900, 824),
        Size(1440, 900),
      ];

      for (final viewport in viewports) {
        Bike? selectedBike;
        var closeCount = 0;
        await _pumpChooser(
          tester,
          viewport: viewport,
          bikes: bikes,
          onSelected: (bike) => selectedBike = bike,
          onClose: () => closeCount++,
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'Unexpected layout exception at ${viewport.width}px.',
        );

        final closeFinder = find.byKey(
          const ValueKey('workshop-mobile-bike-chooser-close'),
        );
        final secondBikeFinder = find.byKey(
          const ValueKey('workshop-mobile-bike-choice-bike-secondary'),
        );
        expect(closeFinder, findsOneWidget);
        expect(secondBikeFinder, findsOneWidget);

        final closeSize = tester.getSize(closeFinder);
        final bikeTargetSize = tester.getSize(secondBikeFinder);
        expect(closeSize.width, greaterThanOrEqualTo(48));
        expect(closeSize.height, greaterThanOrEqualTo(48));
        expect(bikeTargetSize.width, greaterThanOrEqualTo(48));
        expect(bikeTargetSize.height, greaterThanOrEqualTo(48));

        final closeSemantics = find.bySemanticsLabel(
          'Cerrar selector de bicicletas',
        );
        final secondBikeSemantics = find.bySemanticsLabel(
          'Abrir bicicleta ${secondBike.displayName}, Bicicleta 2 · Serie SPECIALIZED-SECONDARY-002 · Rojo',
        );
        expect(closeSemantics, findsOneWidget);
        expect(secondBikeSemantics, findsOneWidget);
        expect(
          tester
              .getSemantics(closeSemantics)
              .flagsCollection
              .isButton,
          isTrue,
        );
        expect(
          tester
              .getSemantics(secondBikeSemantics)
              .flagsCollection
              .isButton,
          isTrue,
        );

        await tester.tap(secondBikeFinder);
        await tester.pump();
        expect(selectedBike, same(secondBike));
        expect(closeCount, 0);
        expect(tester.takeException(), isNull);
      }
      semantics.dispose();
    },
  );

  testWidgets('close remains a separate non-selecting action', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    Bike? selectedBike;
    var closeCount = 0;
    await _pumpChooser(
      tester,
      viewport: const Size(384, 824),
      bikes: bikes,
      onSelected: (bike) => selectedBike = bike,
      onClose: () => closeCount++,
    );

    await tester.tap(
      find.byKey(
        const ValueKey('workshop-mobile-bike-chooser-close'),
      ),
    );
    await tester.pump();

    expect(closeCount, 1);
    expect(selectedBike, isNull);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
