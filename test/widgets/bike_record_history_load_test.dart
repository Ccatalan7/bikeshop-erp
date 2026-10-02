import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/bike_record_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

final _parts = JobStatusCustom(
  id: 'status-parts',
  tenantId: 'tenant-1',
  name: 'REPUESTOS',
  code: 'ESPERANDO_REPUESTOS',
  color: '#F97316',
  phase: StatusPhase.inProgress,
);

final _delivered = JobStatusCustom(
  id: 'status-delivered',
  tenantId: 'tenant-1',
  name: 'Entregado',
  code: 'ENTREGADO',
  color: '#84CC16',
  phase: StatusPhase.complete,
  triggersDelivery: true,
);

class _HistoryService extends ChangeNotifier implements BikeshopService {
  bool fail = false;
  bool failJobBikes = false;
  bool hasJobs = false;
  int requests = 0;

  @override
  Future<List<BikeEvent>> getBikeEvents(String bikeId) async {
    requests++;
    return [];
  }

  @override
  Future<List<BikeObservation>> getBikeObservations(
    String bikeId, {
    String? systemKey,
    String? componentSlotKey,
  }) async {
    if (fail) throw StateError('internal database exception');
    return [];
  }

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
  }) async {
    if (!hasJobs) return [];
    return [
      MechanicJob(
        id: 'job-old',
        tenantId: 'tenant-1',
        jobNumber: 'PG-00257',
        customerId: 'customer-1',
        bikeId: 'bike-1',
        intakeKind: JobIntakeKind.bike,
        status: JobStatus.entregado,
        customStatus: _delivered,
        arrivalDate: DateTime(2026, 3, 6),
        deliveredAt: DateTime(2026, 3, 27),
        totalCost: 37000,
        clientRequest: 'Cambio de cassette 8v y cadena 8v',
      ),
      MechanicJob(
        id: 'job-now',
        tenantId: 'tenant-1',
        jobNumber: 'PG-00582',
        customerId: 'customer-1',
        bikeId: 'bike-1',
        intakeKind: JobIntakeKind.bike,
        status: JobStatus.esperandoRepuestos,
        customStatus: _parts,
        arrivalDate: DateTime(2026, 9, 25),
        totalCost: 79000,
      ),
    ];
  }

  @override
  Future<Map<String, List<MechanicJobBike>>> getAllJobBikes({
    bool forceRefresh = false,
    bool rethrowErrors = false,
  }) async {
    if (failJobBikes) {
      if (rethrowErrors) throw StateError('job bikes unavailable');
      return const {};
    }
    return const {};
  }

  @override
  Future<Map<String, List<MechanicJobItem>>> getJobItemsForJobs(
    Iterable<String> jobIds,
  ) async {
    if (!hasJobs) return const {};
    return {
      'job-old': [
        MechanicJobItem(
          tenantId: 'tenant-1',
          jobId: 'job-old',
          productName: 'SunRace piñón M680 8V 11-40T',
          totalPrice: 25000,
          systemKey: 'drivetrain',
        ),
        MechanicJobItem(
          tenantId: 'tenant-1',
          jobId: 'job-old',
          productName: 'Cadena KMC HV408',
          totalPrice: 12000,
          systemKey: 'drivetrain',
        ),
      ],
      'job-now': [
        MechanicJobItem(
          tenantId: 'tenant-1',
          jobId: 'job-now',
          productName: 'Disco freno Shimano RT56 160 mm',
          totalPrice: 25000,
          systemKey: 'brakes',
        ),
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BikeRecordSnapshot _snapshot() => BikeRecordSnapshot.fromBikeAndProfile(
      bike: Bike(
        id: 'bike-1',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        brand: 'Trek',
        model: 'Marlin',
        color: 'Naranja/Roja',
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  _HistoryService service,
  BikeRecordSnapshot snapshot,
  Brightness brightness, {
  bool settle = true,
}) async {
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
            snapshot: snapshot,
            ownerName: 'Cliente sintético',
            today: DateTime(2026, 10, 2),
            onEdit: () {},
            onNewJob: () {},
            onClose: () {},
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'history failure stays distinct from empty and retries in $brightness',
        (tester) async {
      _setSize(tester, const Size(390, 844));
      final service = _HistoryService()..fail = true;
      addTearDown(service.dispose);
      await _pump(tester, service, _snapshot(), brightness);
      expect(tester.takeException(), isNull);
      // The record opens on its history.
      expect(find.text('No pudimos cargar el historial.'), findsOneWidget);
      expect(find.text('Esta bici todavía no tiene trabajos.'), findsNothing);
      expect(find.textContaining('internal database exception'), findsNothing);
      service
        ..fail = false
        ..hasJobs = true;
      await tester.ensureVisible(find.text('Reintentar historial'));
      await tester.tap(find.text('Reintentar historial'));
      await tester.pumpAndSettle();
      expect(service.requests, 2);
      expect(find.text('No pudimos cargar el historial.'), findsNothing);
      expect(find.text('Cadena KMC HV408'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a new authoritative snapshot refreshes the same bike history',
      (tester) async {
    _setSize(tester, const Size(390, 844));
    final service = _HistoryService();
    addTearDown(service.dispose);
    await _pump(tester, service, _snapshot(), Brightness.light);
    expect(find.text('Esta bici todavía no tiene trabajos.'), findsOneWidget);
    service.hasJobs = true;
    await _pump(tester, service, _snapshot(), Brightness.light);
    expect(service.requests, 2);
    expect(find.text('Esta bici todavía no tiene trabajos.'), findsNothing);
    expect(find.text('Cadena KMC HV408'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the history shows each visit by system and the bike in the workshop',
      (tester) async {
    _setSize(tester, const Size(1400, 1100));
    final service = _HistoryService()..hasJobs = true;
    addTearDown(service.dispose);
    await _pump(tester, service, _snapshot(), Brightness.light);

    expect(find.text('Historial · 2'), findsOneWidget);
    expect(find.text('En el taller hace 7 días'), findsOneWidget);
    expect(find.text('Repuestos'), findsWidgets,
        reason: 'the shop status in capitals reads as a phrase');
    expect(find.text('Abrir trabajo'), findsOneWidget);
    expect(find.text('PG-00257'), findsOneWidget);
    expect(find.textContaining('Cambio de cassette 8v'), findsOneWidget);
    expect(find.text('Transmisión'), findsWidgets);
    expect(find.text(r'$37,000'), findsOneWidget);

    // «Por sistema» filters the visits.
    await tester.tap(find.text('Frenos').last);
    await tester.pumpAndSettle();
    expect(find.text('Disco freno Shimano RT56 160 mm'), findsOneWidget);
    expect(find.text('Cadena KMC HV408'), findsNothing);
    await tester.tap(find.text('Todo el historial'));
    await tester.pumpAndSettle();
    expect(find.text('Cadena KMC HV408'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a failed job-bike read is an error, never a history for the header bike',
      (tester) async {
    _setSize(tester, const Size(390, 844));
    final service = _HistoryService()
      ..hasJobs = true
      ..failJobBikes = true;
    addTearDown(service.dispose);
    await _pump(tester, service, _snapshot(), Brightness.light);
    expect(find.text('No pudimos cargar el historial.'), findsOneWidget);
    expect(find.text('Cadena KMC HV408'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone the job number is a 48 px named target',
      (tester) async {
    _setSize(tester, const Size(390, 844));
    final service = _HistoryService()..hasJobs = true;
    addTearDown(service.dispose);
    await _pump(tester, service, _snapshot(), Brightness.light);
    final link = find.bySemanticsLabel('Abrir trabajo PG-00257');
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    expect(link, findsOneWidget);
    expect(tester.getSize(link).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(link),
      containsSemantics(
        label: 'Abrir trabajo PG-00257',
        isButton: true,
        hasTapAction: true,
      ),
      reason: 'a screen reader can open the job too',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a catalog value is confirmed only by its explicit fact state',
      (tester) async {
    _setSize(tester, const Size(1400, 1100));
    final service = _HistoryService();
    addTearDown(service.dispose);
    final bike = Bike(
      id: 'bike-1',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      brand: 'Trek',
      model: 'Marlin',
      wheelSize: '29"',
    );
    BikeRecordSnapshot record(bool confirmed) =>
        BikeRecordSnapshot.fromBikeAndProfile(
          bike: bike,
          profile: BikeProfile(
            tenantId: 'tenant-1',
            bikeId: bike.id!,
            technicalProfile: {
              'sources': {'wheelSize': 'catalog'},
              'confirmed': {'wheelSize': confirmed},
            },
          ),
        );
    await _pump(tester, service, record(false), Brightness.dark);
    await tester.tap(find.text('Ficha técnica'));
    await tester.pumpAndSettle();
    expect(find.text('Ruedas'), findsOneWidget);
    expect(
        find.text('Del modelo en el catálogo · sin confirmar'), findsOneWidget);
    expect(find.byTooltip('Confirmado en el taller'), findsNothing);
    await _pump(tester, service, record(true), Brightness.dark, settle: false);
    expect(find.text('Del modelo en el catálogo'), findsOneWidget);
    expect(find.byTooltip('Confirmado en el taller'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
