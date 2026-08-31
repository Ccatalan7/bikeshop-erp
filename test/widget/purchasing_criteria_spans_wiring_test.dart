import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_agent_gateway_client.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_workspace_page.dart';
import 'package:vinabike_erp/modules/purchases/services/intelligent_purchasing_service.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/services/inventory_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **El cableado visto desde la app, sin base ni modelo.**
///
/// La lectura de tramos vive en el mismo lugar por donde pasan el plan del
/// proveedor, el catálogo y la previsualización. Lo que se fija acá es que la
/// app la llama de verdad, con qué la llama, qué hace cuando la respuesta llega
/// tarde, y que mover un criterio no sale a preguntarle nada a nadie.
class _NoAI implements AIAgentGatewayTransport {
  @override
  Future<Object?> send(Map<String, Object?> body,
          {required Future<void> abortTrigger}) =>
      throw StateError('esta prueba no debe pedirle nada al asistente');
}

SpecTemplate _template() => SpecTemplate(
      id: 'tpl-pastillas',
      key: 'brake_pad',
      name: 'Pastillas',
      technicalFamily: 'brake_pad',
      fields: <SpecTemplateField>[
        SpecTemplateField(
          specDefinitionId: 'def-compound',
          sectionKey: 'tecnica',
          sortOrder: 1,
          isRequired: false,
          visibilityRules: const <Map<String, dynamic>>[],
          optionRules: const <Map<String, dynamic>>[],
        )..definition = const SpecDefinition(
            id: 'def-compound',
            key: 'compound_type',
            label: 'Compuesto',
            dataType: 'single_select',
            options: <String>['Orgánico', 'Metálico'],
            validationRules: <String, dynamic>{},
            sortOrder: 1,
          ),
      ],
    );

class _SpansService extends IntelligentPurchasingService {
  var descripcion = 'Pastillas para frenos Shimano, de kevlar y sin aletas';
  var version = 1;

  SupplyNeed get need => SupplyNeed.fromJson(<String, dynamic>{
        'id': 'need-spans',
        'origin_kind': 'ad_hoc',
        'original_description': descripcion,
        'quantity': 6,
        'unit': 'juego',
        'identity_state': 'pending',
        'supply_state': 'open',
        'version': version,
        'created_at': '2026-08-31T12:00:00Z',
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
            'entityId': 'supplier-rbx',
            'supplierName': 'RBX',
            'spendSharePercent': 100,
            'purchaseLines': 2,
            'purchaseInvoices': 1,
            'distinctProducts': 1,
            'evidencePurchaseLines': 2,
            'evidenceSuppliers': 1,
          },
        ],
      });

  @override
  Future<SupplyStockResolution> stockResolution(String needId,
          {int limit = 20, int offset = 0}) async =>
      throw StateError('la bodega no es lo que esta prueba mide');

  @override
  Future<SupplyNeedCriteria> fetchNeedCriteria(String needId) async =>
      const SupplyNeedCriteria(
        predicates: <SupplyNeedPredicate>[
          SupplyNeedPredicate(
            field: 'compound_type',
            operator: 'eq',
            values: <Object>['Orgánico'],
          ),
        ],
        categoryId: 'cat-pastillas',
        categoryPath: 'Componentes / Frenos / Pastillas',
        revisionNo: 1,
      );

  @override
  Future<SupplyNeed> updateNeed(
    SupplyNeed current, {
    required String description,
    required String? productId,
    double? quantity,
    String? unit,
  }) async {
    descripcion = description;
    version += 1;
    return need;
  }
}

class _Lector {
  _Lector({this.gate, this.answer});

  final Completer<void>? gate;
  final Object? Function(String prompt)? answer;
  final prompts = <String>[];

  SupplierSpecExtractor get extractor => (prompt) async {
        prompts.add(prompt);
        if (prompts.length == 1 && gate != null) await gate!.future;
        final value = (answer ?? (_) => '{"rows":[]}')(prompt);
        if (value is StateError) throw value;
        return value;
      };
}

String _respuesta(String quote) => jsonEncode(<String, Object?>{
      'rows': <Object?>[
        <String, Object?>{
          'id': kSupplyNeedCriteriaSpansRowId,
          'facts': <Object?>[
            <String, Object?>{
              'field': 'compound_type',
              'value': 'Orgánico',
              'quote': quote,
              'relation': 'same',
            },
          ],
        },
      ],
    });

Future<void> _settle(WidgetTester tester, {int frames = 14}) async {
  for (var frame = 0; frame < frames; frame += 1) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _mount(
  WidgetTester tester,
  IntelligentPurchasingService service,
  SupplierSpecExtractor extractor,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final navigation = NavigationService();
  final workspaces = WorkspaceManager(sessionIdentity: 'spans-wiring');
  final appearance = AppearanceService();
  final chat = ChatProvider();
  final profile = CurrentUserProfileService();
  final inventory = InventoryService();
  addTearDown(navigation.dispose);
  addTearDown(workspaces.dispose);
  addTearDown(appearance.dispose);
  addTearDown(chat.dispose);
  addTearDown(profile.dispose);
  addTearDown(inventory.dispose);
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
        initialNeedId: 'need-spans',
        service: service,
        gatewayClient: AIAgentGatewayClient(transport: _NoAI()),
        specExtractor: extractor,
        templateLoader: (categoryId) async =>
            categoryId == 'cat-pastillas' ? _template() : null,
      ),
    ),
  ));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetSupplyNeedCriteriaSpansCache();
    resetSupplyNeedRequirementDiscoveryCache();
  });

  testWidgets('la app pregunta con la petición y el valor que el taller pidió',
      (tester) async {
    final lector = _Lector(answer: (_) => _respuesta('de kevlar'));
    await _mount(tester, _SpansService(), lector.extractor);

    expect(lector.prompts, isNotEmpty,
        reason: 'la lectura de tramos no está cableada a la app');
    expect(lector.prompts.first, contains('de kevlar'));
    expect(lector.prompts.first, contains('compound_type'));
    expect(lector.prompts.first, contains('Orgánico'));
    expect(lector.prompts.first, contains('relation'));
  });

  testWidgets('cambiar un criterio recalcula la lista sin preguntarle al modelo',
      (tester) async {
    final lector = _Lector(answer: (_) => _respuesta('de kevlar'));
    final service = _SpansService();
    await _mount(tester, service, lector.extractor);
    final antes = lector.prompts.length;

    await tester.tap(find.byKey(const ValueKey('open-need-criteria')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('need-criteria-editor')), findsOneWidget);

    // **Cambiar de verdad el valor**, no sólo abrir: es el momento en que la
    // previsualización tiene que rejuzgar el feed ya traído.
    await tester.tap(
      find.byKey(const ValueKey('need-refinement-value-compound_type')),
    );
    await _settle(tester);
    await tester.tap(find.text('Metálico').last);
    await _settle(tester);

    // La consecuencia del cambio se dice, con su contador, y aparece **por**
    // el cambio: antes de tocar nada no había ninguna.
    final consecuencia = find.byKey(const ValueKey('need-criteria-consequence'));
    expect(consecuencia, findsOneWidget);
    expect(
      tester.widget<Text>(consecuencia).data,
      contains('No se consulta al proveedor otra vez'),
      reason: 'la propia superficie promete que el cambio se resuelve sin red; '
          'la cuenta de filas aparece cuando hay recibo en memoria',
    );
    // La lista de filas necesita un recibo del portal en memoria, que este
    // arnés no puede traer; su composición está cubierta en
    // `supply_need_criteria_preview_rows_test.dart`.

    await tester.tap(find.text('Cancelar').first);
    await _settle(tester);
    expect(find.byKey(const ValueKey('need-criteria-editor')), findsNothing);

    expect(lector.prompts, hasLength(antes),
        reason: 'la previsualización se calcula sin red: cambiar un criterio y '
            'cancelar no puede salir a preguntarle nada a nadie');
  });

  testWidgets('una lectura de la petición anterior no se queda pegada',
      (tester) async {
    // La primera lectura queda retenida; se edita la descripción, que conserva
    // el id; y recién entonces vuelve la vieja. No puede publicarse: responde
    // un texto que ya nadie está preguntando.
    final gate = Completer<void>();
    final service = _SpansService();
    final lector = _Lector(gate: gate, answer: (_) => _respuesta('de kevlar'));
    await _mount(tester, service, lector.extractor);

    await tester.tap(find.byKey(const ValueKey('edit-supply-need-inline')));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('need-inline-description')),
      'Rodamientos sellados para maza',
    );
    await tester.tap(find.byKey(const ValueKey('need-inline-save')));
    await _settle(tester);
    expect(service.descripcion, 'Rodamientos sellados para maza');

    gate.complete();
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('RBX'), findsWidgets,
        reason: 'la pantalla sigue en pie y con su evidencia');
  });

  testWidgets('un lector caído degrada en silencio', (tester) async {
    final lector = _Lector(answer: (_) => StateError('sin cuota'));
    await _mount(tester, _SpansService(), lector.extractor);
    expect(lector.prompts, isNotEmpty);
    expect(tester.takeException(), isNull);
    expect(find.text('RBX'), findsWidgets);
    expect(find.byKey(const ValueKey('decision-load-failed')), findsOneWidget,
        reason: 'lo que falló es la bodega, no el lector');
  });

  testWidgets('también se le pregunta qué exige la petición que la ficha no '
      'representa', (tester) async {
    final lector = _Lector(answer: (prompt) => prompt.contains(
            'YA REPRESENTADO')
        ? jsonEncode(<String, Object?>{
            'requirements': <Object?>[
              <String, Object?>{
                'quote': 'de kevlar',
                'required': true,
                'scope': <String>[],
              },
            ],
          })
        : _respuesta('de kevlar'));
    await _mount(tester, _SpansService(), lector.extractor);

    // Dos preguntas al mismo lector sobre el mismo texto, y la segunda lleva
    // la petición entera y lo que la ficha ya cubre.
    expect(lector.prompts, hasLength(2));
    final descubrimiento = lector.prompts.firstWhere(
      (prompt) => prompt.contains('YA REPRESENTADO'),
    );
    expect(descubrimiento, contains('de kevlar y sin aletas'),
        reason: 'el texto original completo, sin filtrar ni acortar');
    expect(descubrimiento, contains('Compuesto'));
    expect(descubrimiento, contains('Orgánico'),
        reason: 'y lo ya representado, para que no lo repita');
    expect(tester.takeException(), isNull);
  });
}
