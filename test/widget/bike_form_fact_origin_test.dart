// El formulario de la bici decía el valor sembrado sin decir de dónde venía ni
// que nadie lo había confirmado (C1/C4, 2026-09-30). Cada dato con origen
// conocido lo dice en palabras del taller; sin entrada de catálogo enlazada el
// origen es genérico, y un código que no se reconoce no se muestra.
//
// El aro, el tipo y los espaciados de maza viven en `bikes` y el modelo también
// los copia: la ficha de la bici los decía «Confirmado» sólo por existir. Su
// origen se anota al copiarlos, nunca por el mero vínculo con el modelo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/pages/bike_form_dialog.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/bikeshop/services/workshop_command_outbox.dart';
import 'package:vinabike_erp/shared/models/bike_catalog_models.dart';
import 'package:vinabike_erp/shared/services/bike_catalog_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('each seeded fact says where it came from and if it is confirmed',
      (tester) async {
    tester.view.physicalSize = const Size(384, 824);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bike = Bike(
      id: 'bike-origin',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      brandId: 'brand-1',
      modelId: 'model-1',
      brand: 'Trek',
      model: 'Marlin 7',
      wheelSize: '29"',
    );
    final service = _OriginService(
      bike,
      BikeProfile(
        tenantId: 'tenant-1',
        bikeId: bike.id!,
        technicalProfile: const {
          'values': {
            'suspensionLayout': 'front_suspension',
            'brakeType': 'hydraulic_disc',
            'frontRotorSizeMm': 160,
            'freehubType': 'shimano_hg',
            'rearWheelBsdMm': 622,
          },
          'sources': {
            'suspensionLayout': 'mechanic',
            'brakeType': 'catalog',
            'frontRotorSizeMm': 'catalog',
            'freehubType': 'job_diagnosis_sync',
            'rearWheelBsdMm': 'job_completion',
          },
          'confirmed': {
            'suspensionLayout': true,
            'brakeType': false,
            'frontRotorSizeMm': false,
          },
        },
      ),
    );
    addTearDown(service.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<BikeshopService>.value(
        value: service,
        child: MaterialApp(
          home: BikeFormDialog(customerId: bike.customerId, bike: bike),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bike-form-step-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bike-form-step-option-2')));
    await tester.pumpAndSettle();

    Future<void> openSystem(String key) async {
      await tester.tap(
        find.byKey(const ValueKey('bike-technical-system-picker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('bike-technical-system-option-$key')),
      );
      await tester.pumpAndSettle();
    }

    // Sin entrada de catálogo enlazada, la marca y el modelo editables de la
    // bici no prueban de qué modelo vino el dato: el origen es genérico.
    await openSystem('front_brake');
    expect(
      find.text('Del modelo en el catálogo · sin confirmar'),
      findsNWidgets(2),
      reason: 'the brake type and the front rotor came from the catalog',
    );
    expect(find.textContaining('Del modelo Trek'), findsNothing);

    // Anotar no es confirmar; confirmado, el origen se dice sin la marca.
    await openSystem('suspension');
    expect(find.text('Anotado en el taller'), findsOneWidget);

    // El neumático que instaló un trabajo: su ficha técnica no está
    // verificada, así que el BSD queda declarado (recorrido C1/C4, 2026-09-30).
    await openSystem('rear_wheel');
    expect(find.text('Instalado en un trabajo terminado · sin confirmar'),
        findsOneWidget);

    // Un código que no se reconoce no llega a la pantalla.
    await openSystem('drivetrain');
    expect(find.textContaining('job_diagnosis_sync'), findsNothing);
    expect(find.textContaining('Fuente:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the base facts the model copies say so until someone notes them',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _OriginService(
      Bike(
        id: 'bike-unused',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
      ),
      BikeProfile(tenantId: 'tenant-1', bikeId: 'bike-unused'),
    );
    addTearDown(service.dispose);
    final catalog = _OneModelCatalog(BikeCatalogEntry(
      id: 'catalog-marlin',
      brand: 'Trek',
      modelName: 'Marlin 7',
      modelYear: 2024,
      bikeType: 'mountain_hardtail',
      wheelSize: '29"',
      frontHubSpacingMm: 100,
      rearHubSpacingMm: 141,
      brakeType: 'hydraulic_disc',
      spokeCount: 32,
      dataSource: 'test',
    ));

    await tester.pumpWidget(
      ChangeNotifierProvider<BikeshopService>.value(
        value: service,
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: BikeFormDialog(
            customerId: 'customer-1',
            catalogService: catalog,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Marca *'), 'Tre');
    await tester.pump();
    await tester.tap(find.text('Trek').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Modelo *'), 'Mar');
    await tester.pump();
    await tester.tap(find.text('Marlin 7').last);
    await tester.pumpAndSettle();

    // Con marca y modelo escritos, nada dice todavía que vino del catálogo.
    expect(find.textContaining('Del modelo'), findsNothing);

    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trek Marlin 7 (2024)'));
    await tester.pumpAndSettle();

    // Aro y tipo, copiados: del modelo de la entrada enlazada, sin confirmar.
    expect(find.text('Del modelo Trek Marlin 7 2024 · sin confirmar'),
        findsNWidgets(2));
    // Aro, tipo, dos espaciados, dos perforaciones y el freno.
    expect(find.text('Trajo 7 datos sin confirmar: revísalos en la bici.'),
        findsOneWidget);

    // Elegir el aro lo anota el taller, con la regla de los datos técnicos.
    await tester.tap(find.text('29"').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('27.5"').last);
    await tester.pumpAndSettle();
    expect(find.text('Anotado en el taller'), findsOneWidget);
    expect(find.text('Del modelo Trek Marlin 7 2024 · sin confirmar'),
        findsOneWidget);
    expect(find.text('Trajo 6 datos sin confirmar: revísalos en la bici.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _OneModelCatalog extends BikeCatalogService {
  _OneModelCatalog(this.entry);

  final BikeCatalogEntry entry;

  @override
  Future<List<BikeCatalogEntry>> searchBikes({
    String? brand,
    String? model,
    int? year,
    String? bikeType,
  }) async =>
      [entry];

  @override
  Future<BikeCatalogEntry?> getBikeById(String id) async =>
      id == entry.id ? entry : null;
}

class _OriginService extends ChangeNotifier implements BikeshopService {
  _OriginService(this.bike, this.profile);

  final Bike bike;
  final BikeProfile profile;

  @override
  Future<BikeAggregate> getBikeAggregate(String bikeId) async =>
      BikeAggregate(bike: bike, profile: profile);

  @override
  Future<List<WorkshopCommandRun>> resumePendingBikeCommands({
    String? bikeId,
    String? jobId,
  }) async =>
      const [];

  @override
  Future<({String? pendingSaveKey, bool unreadable})> pendingBikeSaveState(
    String bikeId,
  ) async =>
      (pendingSaveKey: null, unreadable: false);

  @override
  Future<({List<({String bikeId, String label})> creations, bool unreadable})>
      pendingBikeCreations(String customerId) async => (
            creations: const <({String bikeId, String label})>[],
            unreadable: false
          );

  @override
  Future<List<BikeBrand>> getBikeBrands({bool activeOnly = true}) async =>
      [BikeBrand(id: 'brand-1', tenantId: bike.tenantId, name: 'Trek')];

  @override
  Future<BikeBrand?> getBikeBrandById(String id) async =>
      BikeBrand(id: 'brand-1', tenantId: bike.tenantId, name: 'Trek');

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
          name: 'Marlin 7',
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
