import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/bikeshop/services/workshop_command_outbox.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/bike_record_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

final _bikeUpdatedAt = DateTime.utc(2026, 9, 30, 12);
final _profileUpdatedAt = DateTime.utc(2026, 9, 30, 12, 5);

Bike _bike() => Bike(
      id: 'bike-1',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      brand: 'Trek',
      model: 'Marlin 5',
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
  Object? failSaveWith;
  int saves = 0;
  Bike? savedBike;
  BikeProfile? savedProfile;
  String? operationKey;
  DateTime? expectedBike;
  DateTime? expectedProfile;

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
      BikeAggregate(bike: _bike(), profile: profile);

  @override
  Future<BikeAggregateSaveResult> saveBikeAggregate({
    required Bike bike,
    required BikeProfile? profile,
    required String operationKey,
    DateTime? expectedBikeUpdatedAt,
    DateTime? expectedProfileUpdatedAt,
    WorkshopCommandTrigger trigger = WorkshopCommandTrigger.save,
    Set<String>? acknowledgedPendingCreations,
  }) async {
    saves++;
    savedBike = bike;
    savedProfile = profile;
    this.operationKey = operationKey;
    expectedBike = expectedBikeUpdatedAt;
    expectedProfile = expectedProfileUpdatedAt;
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
    ChangeNotifierProvider<BikeshopService>.value(
      value: service,
      child: MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: brightness,
        ),
        home: Scaffold(
          body: BikeRecordPanel(
            key: panelKey,
            snapshot: BikeRecordSnapshot.fromBikeAndProfile(
              bike: _bike(),
              profile: _profile(),
            ),
            ownerName: 'Cliente sintético',
            today: DateTime(2026, 10, 2),
            onEdit: () => fail('the sheet edits in place, not in the dialog'),
            onNewJob: () {},
            onClose: () {},
            onSpecSaved: () async => reloads++,
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

Future<void> _openEditor(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Ficha técnica'));
  await tester.tap(find.text('Ficha técnica'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Editar ficha'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Editar ficha'));
  await tester.pumpAndSettle();
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

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        '«Editar ficha» opens the same sheet with every field and saves '
        'in place ($brightness)', (tester) async {
      _setSize(tester, const Size(1920, 1080));
      final service = _SpecService();
      addTearDown(service.dispose);
      final reloads = await _pump(tester, service, brightness);

      await _openEditor(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Editando la ficha técnica'), findsOneWidget);
      // Lo que falta se ve, listo para elegir; lo que la regla esconde, no.
      expect(_select('Válvula'), findsOneWidget);
      expect(_select('Llanta delantera (BSD)'), findsOneWidget);
      expect(_select('Freno de llanta'), findsOneWidget);
      expect(_select('Rotor delantero'), findsNothing);
      expect(find.text('Sin cambios todavía'), findsOneWidget);

      await _choose(tester, 'Válvula', 'Presta');
      expect(find.text('1 cambio sin guardar'), findsOneWidget);
      expect(find.text('Nuevo'), findsOneWidget);

      // Disco hidráulico: aparecen rotores y fluido, se va la familia de
      // llanta.
      await _choose(tester, 'Tipo de freno', 'Disco hidráulico');
      expect(_select('Rotor delantero'), findsOneWidget);
      expect(_select('Fluido delantero'), findsOneWidget);
      expect(_select('Freno de llanta'), findsNothing);
      expect(find.text('Antes: Llanta (rim)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.bySemanticsLabel('Guardar ficha técnica'));
      await tester.pumpAndSettle();

      expect(service.saves, 1);
      expect(service.operationKey, isNotEmpty);
      expect(service.expectedBike, _bikeUpdatedAt);
      expect(service.expectedProfile, _profileUpdatedAt);
      final values = service.savedProfile!.technicalValues;
      expect(values['valveType'], 'presta');
      expect(values['brakeType'], 'hydraulic_disc');
      expect(values.containsKey('rimBrakeFamily'), isFalse);
      expect(service.savedProfile!.technicalSources['brakeType'], 'mechanic');
      expect(service.savedProfile!.technicalConfirmed['brakeType'], isTrue);
      expect(service.savedBike!.brand, 'Trek');
      expect(find.text('Editando la ficha técnica'), findsNothing);
      expect(reloads(), 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a catalog fact is confirmed in place without changing it',
      (tester) async {
    _setSize(tester, const Size(1920, 1080));
    final service = _SpecService();
    addTearDown(service.dispose);
    await _pump(tester, service, Brightness.light);
    await _openEditor(tester);

    expect(find.textContaining('sin confirmar'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Confirmar Tipo de freno'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmado'), findsOneWidget);
    expect(find.text('1 cambio sin guardar'), findsOneWidget);
    expect(find.byTooltip('Deshacer cambio de Tipo de freno'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Guardar ficha técnica'));
    await tester.pumpAndSettle();
    final profile = service.savedProfile!;
    expect(profile.technicalValues['brakeType'], 'rim');
    expect(profile.technicalValues['rimBrakeFamily'], 'v_brake');
    expect(profile.technicalSources['brakeType'], 'mechanic');
    expect(profile.technicalConfirmed['brakeType'], isTrue);
  });

  testWidgets('a save rejected by a newer version keeps the changes on top',
      (tester) async {
    _setSize(tester, const Size(1920, 1080));
    final service = _SpecService();
    addTearDown(service.dispose);
    await _pump(tester, service, Brightness.light);
    await _openEditor(tester);
    await _choose(tester, 'Válvula', 'Schrader');

    service
      ..failSaveWith = const PostgrestException(
        message: 'bike changed since it was loaded',
        code: 'PT409',
      )
      ..profile = _profile(brakeType: 'mechanical_disc');
    await tester.tap(find.bySemanticsLabel('Guardar ficha técnica'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Alguien guardó esta bici'), findsOneWidget);
    expect(find.text('1 cambio sin guardar'), findsOneWidget);
    // Lo último del servidor (disco mecánico) quedó debajo del cambio.
    expect(_select('Rotor delantero'), findsOneWidget);
    final firstKey = service.operationKey;

    await tester.tap(find.bySemanticsLabel('Guardar ficha técnica'));
    await tester.pumpAndSettle();
    expect(service.saves, 2);
    expect(service.operationKey, isNot(firstKey));
    expect(service.savedProfile!.technicalValues['valveType'], 'schrader');
    expect(
        service.savedProfile!.technicalValues['brakeType'], 'mechanical_disc');
  });

  testWidgets('on a phone the sheet edits as cards and asks before discarding',
      (tester) async {
    _setSize(tester, const Size(390, 844));
    final service = _SpecService();
    addTearDown(service.dispose);
    final panelKey = GlobalKey();
    await _pump(tester, service, Brightness.dark, panelKey: panelKey);
    await _openEditor(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Editando la ficha técnica'), findsOneWidget);
    expect(find.text('Sin cambios'), findsOneWidget);

    // En el teléfono el selector abre una hoja desde abajo.
    await _choose(tester, 'Válvula', 'Presta');
    expect(find.text('1 cambio'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar los cambios?'), findsOneWidget);
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(find.text('Editando la ficha técnica'), findsOneWidget);

    // El regreso de la página (la barra del teléfono) también pregunta.
    final guard = panelKey.currentState! as BikeRecordPanelLeaveGuard;
    final stay = guard.confirmLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(await stay, isFalse);
    expect(find.text('Editando la ficha técnica'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('Editando la ficha técnica'), findsNothing);
    expect(await guard.confirmLeave(), isTrue);
    expect(service.saves, 0);
  });
}
