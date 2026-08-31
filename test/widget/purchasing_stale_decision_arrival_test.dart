import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_agent_gateway_client.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_workspace_page.dart';
import 'package:vinabike_erp/modules/purchases/services/intelligent_purchasing_service.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/services/inventory_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **Una lectura en vuelo sobrevive a la edición que la dejó obsoleta.**
///
/// El id no alcanzaba para reconocerla —editar las palabras conserva el id— y
/// los sobres tampoco: tres respuestas viejas concuerdan perfectamente entre
/// sí, porque salieron del mismo momento. Comparadas contra el `need` que
/// capturó la consulta demuestran que nadie escribió *durante* esa lectura, no
/// que sigan describiendo la decisión que está en pantalla.
class _NoAI implements AIAgentGatewayTransport {
  @override
  Future<Object?> send(Map<String, Object?> body,
          {required Future<void> abortTrigger}) =>
      throw StateError('esta prueba no debe pedirle nada a la IA');
}

class _LateArrivalService extends IntelligentPurchasingService {
  _LateArrivalService({
    required this.laterStockFails,
    this.firstStockFails = false,
    this.criteriaGate,
    this.partialAnalysis = false,
  });

  final bool laterStockFails;
  final bool firstStockFails;

  /// Retiene la PRIMERA lectura de la ficha hasta que la prueba la suelte.
  final Completer<void>? criteriaGate;

  /// Deja el análisis a medias para que aparezca «Continuar análisis».
  final bool partialAnalysis;
  int criteriaCalls = 0;

  /// Retiene la PRIMERA lectura de bodega hasta que la prueba la suelte.
  final gate = Completer<void>();
  int stockCalls = 0;
  var need = _need('Pastillas de freno', version: 1, quantity: 6);

  static SupplyNeed _need(
    String description, {
    required int version,
    required double quantity,
  }) =>
      SupplyNeed.fromJson(<String, dynamic>{
        'id': 'same-need-id',
        'origin_kind': 'ad_hoc',
        'original_description': description,
        'quantity': quantity,
        'unit': 'unit',
        'identity_state': 'pending',
        'supply_state': 'open',
        'version': version,
        'created_at': '2026-08-30T12:00:00Z',
      });

  @override
  Future<List<SupplyNeed>> fetchOpenNeeds({String? mechanicJobId}) async =>
      <SupplyNeed>[need];

  @override
  Future<SupplyNeed?> fetchNeed(String needId) async => need;

  @override
  Future<List<PurchasePrioritySuggestion>> fetchPurchasePriority({
    int limit = 40,
    int rotationDays = 120,
  }) async =>
      const <PurchasePrioritySuggestion>[];

  @override
  Future<PurchasePlanDraft?> fetchOpenDraftPlan() async => null;

  @override
  Future<SupplyNeedCriteria> fetchNeedCriteria(String needId) async {
    final gate = criteriaGate;
    if (gate == null) return SupplyNeedCriteria.empty;
    criteriaCalls += 1;
    if (criteriaCalls == 1) await gate.future;
    // El rótulo es sólo un marcador para poder verla en pantalla.
    return const SupplyNeedCriteria(
      predicates: <SupplyNeedPredicate>[],
      commercialPreference: 'Ficha leída al abrir',
      revisionNo: 1,
    );
  }

  @override
  Future<SupplierConcentrationReport> rankSuppliers({
    String? query,
    String? category,
    String? brand,
    int limit = 4,
  }) async =>
      SupplierConcentrationReport.fromJson(<String, dynamic>{
        'hasMore': false,
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'entityId': 'supplier-test',
            'supplierName': 'RBX',
            'spendSharePercent': 100,
            'purchaseLines': 3,
            'purchaseInvoices': 2,
            'distinctProducts': 2,
            'evidencePurchaseLines': 3,
            'evidenceSuppliers': 1,
          },
        ],
      });

  @override
  Future<SupplyNeed> updateNeed(
    SupplyNeed current, {
    required String description,
    required String? productId,
    double? quantity,
    String? unit,
  }) async {
    need = _need(
      description,
      version: current.version + 1,
      quantity: quantity ?? current.quantity,
    );
    return need;
  }

  @override
  Future<SupplyStockResolution> stockResolution(
    String needId, {
    int limit = 20,
    int offset = 0,
  }) async {
    stockCalls += 1;
    final primera = stockCalls == 1;
    // El sobre se estampa con la versión que había **al pedir**, como el
    // servidor real.
    final version = need.version;
    if (primera) await gate.future;
    if (primera ? firstStockFails : laterStockFails) {
      throw StateError('canceling statement due to statement timeout');
    }
    return SupplyStockResolution.fromJson(<String, dynamic>{
      'needId': needId,
      'needVersion': version,
      'revisionNo': 1,
      'quantity': 6,
      'unit': 'unit',
      'lane': 'family',
      'status': 'ok',
      'coverage': 'none',
      'blocksExternal': false,
      'items': const <Map<String, dynamic>>[],
      'counts': const <String, dynamic>{'eligible': 0},
      'page': <String, dynamic>{
        'limit': limit,
        'offset': offset,
        'total': 0,
        'returned': 0,
        'hasMore': false,
      },
    });
  }

  @override
  Future<SupplyCommercialTarget> commercialTarget(String needId) async =>
      SupplyCommercialTarget.fromJson(<String, dynamic>{
        'needId': needId,
        'needVersion': need.version,
        'needSupplyState': need.supplyState,
        'currencyCode': 'CLP',
        'tenantCurrencyCode': 'CLP',
        'targetRevisionNo': 1,
        'target': const <String, dynamic>{},
      });

  @override
  Future<SupplyExternalCandidates> externalCandidates(
    String needId, {
    int limit = 10,
    int offset = 0,
    int unverifiedLimit = 5,
    int unverifiedOffset = 0,
  }) async =>
      SupplyExternalCandidates.fromJson(<String, dynamic>{
        'needId': needId,
        'needVersion': need.version,
        'revisionNo': 1,
        'needSupplyState': need.supplyState,
        'quantity': 6,
        'unit': 'unit',
        'targetRevisionNo': 1,
        'state': 'ok',
        'items': const <Map<String, dynamic>>[],
        'unverifiedItems': const <Map<String, dynamic>>[],
        'page': <String, dynamic>{
          'limit': limit,
          'offset': offset,
          'total': partialAnalysis ? 40 : 0,
          'returned': 0,
          'hasMore': partialAnalysis,
        },
      });
}

/// **Acá no se puede `pumpAndSettle`.** La primera lectura queda retenida a
/// propósito, así que la pantalla nunca queda quieta: se bombea un número
/// acotado de frames, que es lo que esta prueba necesita.
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame += 1) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _mount(WidgetTester tester, _LateArrivalService service) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final navigation = NavigationService();
  final workspaces = WorkspaceManager(sessionIdentity: 'late-arrival');
  final appearance = AppearanceService();
  final chat = ChatProvider();
  final profile = CurrentUserProfileService();
  // La identidad pendiente monta el autocompletado de producto en cuanto la
  // decisión sí carga.
  final inventory = InventoryService();
  addTearDown(inventory.dispose);
  addTearDown(navigation.dispose);
  addTearDown(workspaces.dispose);
  addTearDown(appearance.dispose);
  addTearDown(chat.dispose);
  addTearDown(profile.dispose);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<NavigationService>.value(value: navigation),
      ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
      ChangeNotifierProvider<AppearanceService>.value(value: appearance),
      ChangeNotifierProvider<ChatProvider>.value(value: chat),
      ChangeNotifierProvider<CurrentUserProfileService>.value(value: profile),
      ChangeNotifierProvider<InventoryService>.value(value: inventory),
      Provider<Workspace>.value(value: workspaces.activeWorkspace!),
    ],
    child: MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: IntelligentPurchasingWorkspacePage(
        initialNeedId: service.need.id,
        service: service,
        gatewayClient: AIAgentGatewayClient(transport: _NoAI()),
      ),
    ),
  ));
  await _settle(tester);
}

Future<void> _editDescription(WidgetTester tester, String value) async {
  await tester.tap(find.byKey(const ValueKey('edit-supply-need-inline')));
  await _settle(tester);
  await tester.enterText(
    find.byKey(const ValueKey('need-inline-description')),
    value,
  );
  await tester.tap(find.byKey(const ValueKey('need-inline-save')));
  await _settle(tester);
}

Future<void> _editQuantity(WidgetTester tester, String value) async {
  await tester.tap(find.byKey(const ValueKey('edit-supply-need-inline')));
  await _settle(tester);
  await tester.enterText(
    find.byKey(const ValueKey('need-inline-quantity')),
    value,
  );
  await tester.tap(find.byKey(const ValueKey('need-inline-save')));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    WidgetController.hitTestWarningShouldBeFatal = true;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('una respuesta buena de la petición anterior no publica nada',
      (tester) async {
    final service = _LateArrivalService(laterStockFails: true);
    await _mount(tester, service);
    await _editDescription(tester, 'Rodamientos para maza');
    expect(
      find.byKey(const ValueKey('decision-load-failed')),
      findsOneWidget,
      reason: 'la lectura vigente falló y se dice',
    );

    service.gate.complete();
    await _settle(tester);

    expect(
      find.byKey(const ValueKey('decision-load-failed')),
      findsOneWidget,
      reason: 'la respuesta vieja no puede tapar el fallo de la petición nueva',
    );
    expect(
      find.byKey(const ValueKey('reload-after-conflict')),
      findsNothing,
      reason: 'llegar tarde no es que alguien más haya escrito',
    );
  });

  testWidgets('tres sobres viejos que concuerdan entre sí siguen siendo viejos',
      (tester) async {
    // La cantidad sube `version` **sin** cambiar las palabras, así que la
    // pregunta es la misma y sólo la versión delata que la respuesta es de
    // antes. Es el caso que el id y la coherencia entre sobres no ven.
    final service = _LateArrivalService(laterStockFails: false);
    await _mount(tester, service);
    await _editQuantity(tester, '9');
    expect(service.need.version, 2);

    service.gate.complete();
    await _settle(tester);

    expect(
      find.byKey(const ValueKey('reload-after-conflict')),
      findsNothing,
      reason: 'una respuesta de la versión anterior llega tarde; no es un '
          'conflicto que el operador tenga que resolver',
    );
    expect(find.byKey(const ValueKey('decision-load-failed')), findsNothing);
  });

  testWidgets('el fallo de la bodega encabeza, sobre la tabla que sí llegó',
      (tester) async {
    // **En la captura real del corte anterior no se veía ningún aviso.** La
    // superficie quedaba al final de la lista, debajo del feed expandido de
    // RBX, mientras su propio texto decía «los proveedores siguen abajo». El
    // fallo y su reintento se deciden antes de elegir, así que encabezan; la
    // tabla no se reemplaza ni se esconde.
    final service = _LateArrivalService(
      firstStockFails: true,
      laterStockFails: true,
    );
    service.gate.complete();
    await _mount(tester, service);

    final aviso = find.byKey(const ValueKey('decision-load-failed'));
    expect(aviso, findsOneWidget);
    expect(find.byKey(const ValueKey('retry-decision-load')), findsOneWidget);
    final tabla = find.text('RBX');
    expect(tabla, findsWidgets);
    expect(
      tester.getTopLeft(aviso).dy,
      lessThan(tester.getTopLeft(tabla.first).dy),
      reason: 'la causa y su reintento van antes de elegir, no bajo el feed',
    );
  });

  testWidgets('ampliar el corte no cancela la ficha que sigue en vuelo',
      (tester) async {
    // **Paginar no es preguntar otra ficha.** `Continuar análisis` es una
    // recarga incremental y **no** vuelve a pedir criterios; con una sola
    // cuenta de vigencia compartida, subirla ahí descartaba la lectura de
    // ficha que seguía en vuelo y ninguna la reemplazaba: la necesidad se
    // quedaba sin ficha hasta cambiar de necesidad y volver.
    final criteria = Completer<void>();
    final service = _LateArrivalService(
      laterStockFails: false,
      criteriaGate: criteria,
      partialAnalysis: true,
    );
    service.gate.complete();
    await _mount(tester, service);

    final continuar = find.byKey(const ValueKey('continue-partial-analysis'));
    expect(continuar, findsOneWidget);
    await tester.tap(continuar);
    await _settle(tester);

    criteria.complete();
    await _settle(tester);

    expect(
      find.textContaining('Ficha leída al abrir'),
      findsWidgets,
      reason: 'la ficha de esta misma necesidad sigue siendo válida: ampliar '
          'la comparación no la invalida ni la vuelve a pedir',
    );
    expect(
      service.criteriaCalls,
      1,
      reason: 'y no se pidió de nuevo, que es lo que la haría parecer viva',
    );
  });
}
