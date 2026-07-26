import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/bikeshop/pages/bike_form_dialog.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

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

  testWidgets(
    'phone bike editor uses the available width without action overflow',
    (tester) async {
      tester.view.physicalSize = const Size(384, 824);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      final bike = Bike(
        id: 'bike-1',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        brandId: 'brand-1',
        modelId: 'model-1',
        brand: 'Polygon',
        model: 'Siskiu T8',
        wheelSize: '29"',
      );
      final service = _BikeFormLayoutService(bike);
      addTearDown(service.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<BikeshopService>.value(
          value: service,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: BikeFormDialog(
              customerId: bike.customerId,
              bike: bike,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surface = find.byKey(const ValueKey('bike-form-dialog-surface'));
      final actions = find.byKey(const ValueKey('bike-form-mobile-actions'));
      expect(surface, findsOneWidget);
      expect(actions, findsOneWidget);
      expect(
        tester.getSize(surface).width,
        greaterThanOrEqualTo(368),
      );
      expect(
        tester.getSize(actions).width,
        lessThanOrEqualTo(tester.getSize(surface).width),
      );

      final moreActions = find.byTooltip('Más acciones de bicicleta');
      final semanticMoreActions =
          find.bySemanticsLabel('Más acciones de bicicleta');
      final next = find.widgetWithText(FilledButton, 'Siguiente');
      final cancel = find.widgetWithText(TextButton, 'Cancelar');
      expect(moreActions, findsOneWidget);
      expect(semanticMoreActions, findsOneWidget);
      expect(next, findsOneWidget);
      expect(cancel, findsOneWidget);
      expect(tester.getSize(moreActions).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(next).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(cancel).height, greaterThanOrEqualTo(48));

      await tester.tap(moreActions);
      await tester.pumpAndSettle();
      expect(find.text('Guardar rápido'), findsOneWidget);
      expect(find.text('Eliminar bicicleta'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}

class _BikeFormLayoutService extends ChangeNotifier implements BikeshopService {
  _BikeFormLayoutService(this.bike);

  final Bike bike;

  @override
  Future<BikeAggregate> getBikeAggregate(String bikeId) async =>
      BikeAggregate(bike: bike, profile: null);

  @override
  Future<List<BikeBrand>> getBikeBrands({bool activeOnly = true}) async => [
        BikeBrand(
          id: 'brand-1',
          tenantId: bike.tenantId,
          name: 'Polygon',
        ),
      ];

  @override
  Future<BikeBrand?> getBikeBrandById(String id) async => BikeBrand(
        id: 'brand-1',
        tenantId: bike.tenantId,
        name: 'Polygon',
      );

  @override
  Future<List<BikeModel>> getBikeModels({
    String? brandId,
    bool activeOnly = true,
  }) async =>
      [
        BikeModel(
          id: 'model-1',
          tenantId: bike.tenantId,
          brandId: 'brand-1',
          name: 'Siskiu T8',
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
