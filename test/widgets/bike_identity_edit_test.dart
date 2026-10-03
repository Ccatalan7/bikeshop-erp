import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/bikeshop/services/workshop_command_outbox.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/bike_record_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/widgets/vb_button.dart';
import 'package:vinabike_erp/shared/widgets/vb_searchable_select.dart';

final _bikeUpdatedAt = DateTime.utc(2026, 9, 30, 12);
final _profileUpdatedAt = DateTime.utc(2026, 9, 30, 12, 5);

Bike _bike({bool isActive = true}) => Bike(
      id: 'bike-1',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      brandId: 'brand-trek',
      brand: 'Trek',
      modelId: 'model-marlin',
      model: 'Marlin 5',
      isActive: isActive,
      color: 'Naranja',
      bikeType: BikeType.mountainHardtail,
      wheelSize: '29"',
      updatedAt: _bikeUpdatedAt,
    );

BikeProfile _profile({String brakeType = 'rim'}) => BikeProfile(
      id: 'profile-1',
      tenantId: 'tenant-1',
      bikeId: 'bike-1',
      technicalProfile: {
        'values': {'brakeType': brakeType, 'rimBrakeFamily': 'v_brake'},
        'sources': {'brakeType': 'catalog'},
        'confirmed': {'brakeType': false},
      },
      updatedAt: _profileUpdatedAt,
    );

class _SpecService extends ChangeNotifier implements BikeshopService {
  BikeProfile profile = _profile();
  Bike bike = _bike();
  Object? failSaveWith;
  Completer<void>? holdSave;
  Completer<void>? holdCreate;
  int saves = 0;
  Bike? savedBike;
  BikeProfile? savedProfile;
  String? operationKey;
  DateTime? expectedBike;
  DateTime? expectedProfile;
  Set<String> cleared = const {};

  @override
  Future<List<BikeEvent>> getBikeEvents(String bikeId) async => [];

  @override
  Future<List<BikeObservation>> getBikeObservations(
    String bikeId, {
    String? systemKey,
    String? componentSlotKey,
  }) async =>
      [];

  @override
  Future<List<BikeSystemState>> getBikeSystemStates(String bikeId) async => [];

  @override
  Future<List<BikeIntervention>> getBikeInterventions(
    String bikeId, {
    String? systemKey,
    String? componentSlotKey,
  }) async =>
      [];

  @override
  Future<List<BikeComponentLifecycle>> getBikeComponentLifecycles(
    String bikeId, {
    bool activeOnly = false,
  }) async =>
      [];

  @override
  Future<List<MechanicJob>> getJobs({
    String? customerId,
    String? bikeId,
    JobStatus? status,
    String? searchTerm,
    bool includeCompleted = true,
    bool includeDeleted = false,
    bool forceRefresh = false,
  }) async =>
      [];

  @override
  Future<Map<String, List<MechanicJobBike>>> getAllJobBikes({
    bool forceRefresh = false,
    bool rethrowErrors = false,
  }) async =>
      const {};

  @override
  Future<Map<String, List<MechanicJobItem>>> getJobItemsForJobs(
    Iterable<String> jobIds,
  ) async =>
      const {};

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
  Future<BikeAggregate> getBikeAggregate(String bikeId) async =>
      BikeAggregate(bike: bike, profile: profile);

  @override
  Future<List<BikeBrand>> getBikeBrands({bool activeOnly = true}) async => [
        BikeBrand(id: 'brand-giant', tenantId: 'tenant-1', name: 'Giant'),
        BikeBrand(id: 'brand-trek', tenantId: 'tenant-1', name: 'Trek'),
      ];

  @override
  Future<List<BikeModel>> getBikeModels({
    String? brandId,
    bool activeOnly = true,
  }) async =>
      [
        if (brandId == 'brand-trek')
          BikeModel(
            id: 'model-marlin',
            tenantId: 'tenant-1',
            brandId: 'brand-trek',
            name: 'Marlin 5',
          ),
        if (brandId == 'brand-giant')
          BikeModel(
            id: 'model-talon',
            tenantId: 'tenant-1',
            brandId: 'brand-giant',
            name: 'Talon 2',
          ),
      ];

  @override
  Future<BikeAggregateSaveResult> saveBikeAggregate({
    required Bike bike,
    required BikeProfile? profile,
    required String operationKey,
    DateTime? expectedBikeUpdatedAt,
    DateTime? expectedProfileUpdatedAt,
    WorkshopCommandTrigger trigger = WorkshopCommandTrigger.save,
    Set<String>? acknowledgedPendingCreations,
    Set<String> clearCatalogLinks = const {},
  }) async {
    saves++;
    cleared = clearCatalogLinks;
    savedBike = bike;
    savedProfile = profile;
    this.operationKey = operationKey;
    expectedBike = expectedBikeUpdatedAt;
    expectedProfile = expectedProfileUpdatedAt;
    await holdSave?.future;
    final failure = failSaveWith;
    if (failure != null) {
      failSaveWith = null;
      throw failure;
    }
    return BikeAggregateSaveResult(
      bike: bike,
      profile: profile,
      operationId: 'op-1',
      replayed: false,
    );
  }

  @override
  Future<BikeModel> createBikeModel(BikeModel model) async {
    await holdCreate?.future;
    return BikeModel(
      id: 'model-new',
      tenantId: model.tenantId,
      brandId: model.brandId,
      name: model.name,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<int Function()> _pump(
  WidgetTester tester,
  _SpecService service,
  Brightness brightness, {
  Key? panelKey,
}) async {
  var reloads = 0;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<BikeshopService>.value(value: service),
        ChangeNotifierProvider<TenantService>.value(
          value: TenantService.testing(
            currentUserId: () => 'user-1',
            profileLookup: (_) async => const [
              {'tenant_id': 'tenant-1'},
            ],
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: brightness,
        ),
        home: Scaffold(
          body: BikeRecordPanel(
            key: panelKey,
            snapshot: BikeRecordSnapshot.fromBikeAndProfile(
              bike: service.bike,
              profile: _profile(),
            ),
            ownerName: 'Cliente sintético',
            today: DateTime(2026, 10, 2),
            onEdit: () => fail('the bike edits in place, not in the dialog'),
            onNewJob: () {},
            onClose: () {},
            onRecordSaved: () async => reloads++,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return () => reloads;
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// El selector de un dato (el rótulo visible también lleva su nombre).
Finder _select(String field) => find.byWidgetPredicate((widget) =>
    widget is Semantics &&
    widget.properties.button == true &&
    widget.properties.label == field);

Future<void> _choose(WidgetTester tester, String field, String option) async {
  final select = _select(field);
  await tester.ensureVisible(select);
  await tester.pumpAndSettle();
  await tester.tap(select);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// El campo de texto de un dato de la bici.
Finder _input(String field) => find.descendant(
      of: find.byWidgetPredicate((widget) =>
          widget is Semantics &&
          widget.properties.textField == true &&
          widget.properties.label == field),
      matching: find.byType(TextField),
    );

Future<void> _type(WidgetTester tester, String field, String text) async {
  final input = _input(field);
  await tester.ensureVisible(input);
  await tester.pumpAndSettle();
  await tester.enterText(input, text);
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        '«Editar» edits the bike in its column and in Notas, and saves only '
        'the bike ($brightness)', (tester) async {
      _setSize(tester, const Size(1920, 1080));
      final service = _SpecService();
      addTearDown(service.dispose);
      final reloads = await _pump(tester, service, brightness);

      await tester.tap(find.bySemanticsLabel('Editar bicicleta'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Editando la bici'), findsOneWidget);
      expect(_select('Marca'), findsOneWidget);
      expect(_select('Modelo'), findsOneWidget);
      expect(find.text('Sin cambios todavía'), findsOneWidget);
      expect(find.text('Agregar foto'), findsOneWidget);

      await _type(tester, 'Color', 'Azul');
      expect(find.text('1 cambio sin guardar'), findsOneWidget);
      expect(find.text('Antes: Naranja'), findsOneWidget);
      // El dibujo sigue el color escrito.
      expect(find.bySemanticsLabel(RegExp('azul')), findsWidgets);

      await tester.tap(find.text('Notas'));
      await tester.pumpAndSettle();
      expect(find.text('Editando las notas'), findsOneWidget);
      await _type(tester, 'Notas de la bici', 'Cliente pide revisar el cambio');
      await _type(tester, 'Precio de compra', '450000');
      expect(find.text('3 cambios sin guardar'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.bySemanticsLabel('Guardar bicicleta'));
      await tester.pumpAndSettle();
      expect(service.saves, 1);
      expect(service.savedProfile, isNull,
          reason: 'la ficha técnica no viaja en un guardado de la bici');
      expect(service.savedBike?.color, 'Azul');
      expect(service.savedBike?.notes, 'Cliente pide revisar el cambio');
      expect(service.savedBike?.purchasePrice, 450000);
      expect(service.savedBike?.brandId, 'brand-trek');
      expect(service.savedBike?.modelId, 'model-marlin');
      expect(service.expectedBike, _bikeUpdatedAt);
      expect(service.cleared, isEmpty);
      expect(find.text('Editando la bici'), findsNothing);
      expect(reloads(), 1);
    });
  }

  testWidgets('another brand drops the model and the save says so',
      (tester) async {
    _setSize(tester, const Size(1920, 1080));
    final service = _SpecService();
    addTearDown(service.dispose);
    await _pump(tester, service, Brightness.light);

    await tester.tap(find.bySemanticsLabel('Editar bicicleta'));
    await tester.pumpAndSettle();
    await _choose(tester, 'Marca', 'Giant');
    expect(find.text('Antes: Trek'), findsOneWidget);
    expect(find.text('Antes: Marlin 5'), findsOneWidget);
    expect(find.text('2 cambios sin guardar'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Guardar bicicleta'));
    await tester.pumpAndSettle();
    expect(service.savedBike?.brandId, 'brand-giant');
    expect(service.savedBike?.modelId, isNull);
    expect(service.cleared, {'model_id'});
  });

  testWidgets('a phone edits from the pencil and asks before discarding',
      (tester) async {
    _setSize(tester, const Size(400, 860));
    final service = _SpecService();
    addTearDown(service.dispose);
    await _pump(tester, service, Brightness.dark);

    await tester.tap(find.byTooltip('Editar bicicleta'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Editando la bici'), findsOneWidget);
    await _type(tester, 'N° de serie', 'WTU 123');
    expect(find.text('1 cambio'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar los cambios?'), findsOneWidget);
    expect(find.textContaining('en la bici'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('Editando la bici'), findsNothing);
    expect(service.saves, 0);
  });

  testWidgets('archiving saves only that, and an archived bike reactivates',
      (tester) async {
    _setSize(tester, const Size(1920, 1080));
    final service = _SpecService();
    addTearDown(service.dispose);
    await _pump(tester, service, Brightness.light);

    await tester.tap(find.bySemanticsLabel('Editar bicicleta'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Archivar bici'));
    await tester.tap(find.text('Archivar bici'));
    await tester.pumpAndSettle();
    expect(find.text('¿Archivar esta bici?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Archivar'));
    await tester.pumpAndSettle();
    expect(service.saves, 1);
    expect(service.savedBike?.isActive, isFalse);
    expect(service.savedBike?.color, 'Naranja');
    expect(service.savedProfile, isNull);
    expect(find.text('Editando la bici'), findsNothing);

    final archived = _SpecService()..bike = _bike(isActive: false);
    addTearDown(archived.dispose);
    await _pump(tester, archived, Brightness.light);
    expect(find.text('Archivada'), findsOneWidget);
    expect(find.text('Nuevo trabajo'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Reactivar bicicleta'));
    await tester.pumpAndSettle();
    expect(archived.saves, 1);
    expect(archived.savedBike?.isActive, isTrue);
  });

  testWidgets('a model being added holds the save and lands on its brand',
      (tester) async {
    _setSize(tester, const Size(1920, 1080));
    final service = _SpecService()..holdCreate = Completer<void>();
    addTearDown(service.dispose);
    await _pump(tester, service, Brightness.light);

    await tester.tap(find.bySemanticsLabel('Editar bicicleta'));
    await tester.pumpAndSettle();
    await _type(tester, 'Color', 'Azul');
    final model = _select('Modelo');
    await tester.ensureVisible(model);
    await tester.pumpAndSettle();
    await tester.tap(model);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Fathom');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar el modelo «Fathom»'));
    await tester.pump();

    VbButton save() =>
        tester.widget<VbButton>(find.byWidgetPredicate((widget) =>
            widget is VbButton && widget.semanticLabel == 'Guardar bicicleta'));
    // dynamic: el campo es de tipo ValueChanged<BikeCatalogPick?>.
    dynamic brand() => tester.widget(find.byWidgetPredicate(
        (widget) => widget is VbSearchableSelect && widget.label == 'Marca'));
    // Mientras el catálogo responde no se guarda ni se cambia la marca.
    expect(save().onPressed, isNull);
    expect(brand().onChanged, isNull);

    service.holdCreate!.complete();
    await tester.pumpAndSettle();
    expect(save().onPressed, isNotNull);
    await tester.tap(find.bySemanticsLabel('Guardar bicicleta'));
    await tester.pumpAndSettle();
    expect(service.savedBike?.brandId, 'brand-trek');
    expect(service.savedBike?.modelId, 'model-new');
    expect(service.savedBike?.color, 'Azul');
  });
}
