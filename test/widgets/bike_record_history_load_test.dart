import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/bike_record_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

class _HistoryService extends ChangeNotifier implements BikeshopService {
  bool fail = false;
  bool hasEvent = false;
  int requests = 0;

  @override
  Future<List<BikeEvent>> getBikeEvents(String bikeId) async {
    requests++;
    if (!hasEvent) return [];
    return [
      BikeEvent(
        id: 'event-1',
        tenantId: 'tenant-1',
        bikeId: bikeId,
        eventType: BikeEventType.jobCompleted,
        eventCategory: BikeEventCategory.visit,
        title: 'Trabajo completado: freno trasero',
        eventDate: DateTime.utc(2026, 9, 30),
      ),
    ];
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BikeRecordSnapshot _snapshot() => BikeRecordSnapshot.fromBikeAndProfile(
      bike: Bike(
        id: 'bike-1',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        brand: 'Trek',
        model: 'Marlin',
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

Future<void> _openHistory(WidgetTester tester) async {
  final tabs = find.byWidgetPredicate((widget) =>
      widget is ListView && widget.scrollDirection == Axis.horizontal);
  await tester.drag(tabs, const Offset(-350, 0));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Historial'));
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'history failure stays distinct from empty and retries in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _HistoryService()..fail = true;
      addTearDown(service.dispose);
      await _pump(tester, service, _snapshot(), brightness);
      // The request failed while this tab was offscreen; no unhandled error.
      expect(tester.takeException(), isNull);
      await _openHistory(tester);
      expect(find.text('No pudimos cargar el historial.'), findsOneWidget);
      expect(
          find.text('Aún no existen eventos en el historial.'), findsNothing);
      expect(find.textContaining('internal database exception'), findsNothing);
      service
        ..fail = false
        ..hasEvent = true;
      await tester.tap(find.text('Reintentar historial'));
      await tester.pumpAndSettle();
      expect(service.requests, 2);
      expect(find.text('Trabajo completado: freno trasero'), findsOneWidget);
      expect(find.text('No pudimos cargar el historial.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a new authoritative snapshot refreshes the same bike history',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _HistoryService();
    addTearDown(service.dispose);
    await _pump(tester, service, _snapshot(), Brightness.light);
    await _openHistory(tester);
    expect(
        find.text('Aún no existen eventos en el historial.'), findsOneWidget);
    service.hasEvent = true;
    await _pump(tester, service, _snapshot(), Brightness.light);
    expect(service.requests, 2);
    expect(find.text('Trabajo completado: freno trasero'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a catalog value is confirmed only by its explicit fact state',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    await tester.tap(find.text('Ficha Técnica'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Rueda trasera'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find.text('Del modelo en el catálogo · sin confirmar'), findsOneWidget);
    expect(find.text('Confirmado'), findsNothing);
    await _pump(tester, service, record(true), Brightness.dark, settle: false);
    expect(find.text('Del modelo en el catálogo'), findsOneWidget);
    expect(find.text('Confirmado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
