import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_agent_gateway_client.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_turn_contracts.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_surfaces.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_workspace_page.dart';
import 'package:vinabike_erp/modules/purchases/services/intelligent_purchasing_service.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/services/inventory_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Navega al paso pedido por su etiqueta.
///
/// En desktop/tablet la banda muestra los cuatro pasos; en teléfono el stepper
/// sólo muestra el activo, así que se avanza con sus controles anterior /
/// siguiente. Ambos caminos usan la navegación real del widget.
const _stepLabels = <String>[
  'Necesidad',
  'Stock interno',
  'Proveedores',
  'Plan',
];

/// Abre el composer, que se compacta a una línea reabrible después de analizar.
Future<void> _openComposer(WidgetTester tester) async {
  final reopen =
      find.byKey(const ValueKey('intelligent-purchasing-composer-reopen'));
  if (reopen.evaluate().isNotEmpty) {
    await tester.ensureVisible(reopen);
    await tester.tap(reopen);
    await tester.pumpAndSettle();
  }
}

/// Comprobaciones de legibilidad del oscuro (frames 22–25).
///
/// No se afirma un hex: se afirma el contrato del tema —ninguna superficie es
/// negro puro y el texto secundario conserva contraste frente a su fondo—.
void _expectDarkRolesAreLegible(WidgetTester tester) {
  // El elemento de `MaterialApp` está *encima* del `Theme` que ella misma
  // instala: `Theme.of` ahí devuelve el tema ancestro, no el de la app.
  final context = tester.element(find.byType(Scaffold).first);
  final scheme = Theme.of(context).colorScheme;
  expect(scheme.brightness, Brightness.dark);

  for (final entry in <String, Color>{
    'surface': scheme.surface,
    'surfaceContainerLow': scheme.surfaceContainerLow,
    'scaffold': Theme.of(context).scaffoldBackgroundColor,
  }.entries) {
    expect(
      entry.value.toARGB32() & 0x00FFFFFF,
      isNot(0x000000),
      reason: 'El rol ${entry.key} no puede ser negro puro en oscuro.',
    );
  }

  // El texto secundario es el que se apaga primero: debe seguir separándose de
  // su superficie lo suficiente para leerse.
  final distance = (scheme.onSurfaceVariant.computeLuminance() -
          scheme.surface.computeLuminance())
      .abs();
  expect(
    distance,
    greaterThan(0.12),
    reason: 'inkMuted quedó casi invisible sobre su superficie.',
  );
}

Future<void> _goToStep(WidgetTester tester, String label) async {
  final target = _stepLabels.indexOf(label);
  for (var hop = 0; hop < 6; hop++) {
    // Banda ancha: el paso está visible y se toca directamente.
    final direct = find.text(label);
    if (direct.evaluate().isNotEmpty) {
      // La banda ancha desplaza en horizontal: el paso puede estar fuera de
      // vista sin estar deshabilitado.
      await tester.ensureVisible(direct.first);
      await tester.pumpAndSettle();
      await tester.tap(direct.first);
      await tester.pumpAndSettle();
      return;
    }
    // Stepper compacto: sólo el activo se ve; hay que caminar hacia el destino.
    final current = _stepLabels.indexWhere(
      (candidate) => find.text(candidate).evaluate().isNotEmpty,
    );
    if (current < 0) return;
    final icon = current < target ? Icons.chevron_right : Icons.chevron_left;
    final control = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          widget.icon is Icon &&
          (widget.icon as Icon).icon == icon &&
          widget.onPressed != null,
    );
    if (control.evaluate().isEmpty) return;
    await tester.tap(control.first);
    await tester.pumpAndSettle();
  }
}

void main() {
  // La escala del asistente resuelve sus familias con `google_fonts`. En las
  // pruebas se prohíbe la descarga en tiempo de ejecución: sin esto el
  // resultado dependería de la red y del caché de la máquina, que es
  // exactamente lo contrario de una regresión.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Un tap que no alcanza a su objetivo es un fallo, no un aviso.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in const <double>[599, 600, 899, 900]) {
    testWidgets('keeps one guided decision at ${width.toInt()} px',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 820);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final navigation = NavigationService();
      final workspaces = WorkspaceManager(
        sessionIdentity: 'intelligent-purchasing-${width.toInt()}',
      );
      final appearance = AppearanceService();
      final chat = ChatProvider();
      final profile = CurrentUserProfileService();
      final workspace = workspaces.activeWorkspace!;
      addTearDown(navigation.dispose);
      addTearDown(workspaces.dispose);
      addTearDown(appearance.dispose);
      addTearDown(chat.dispose);
      addTearDown(profile.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NavigationService>.value(value: navigation),
            ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
            ChangeNotifierProvider<AppearanceService>.value(value: appearance),
            ChangeNotifierProvider<ChatProvider>.value(value: chat),
            ChangeNotifierProvider<CurrentUserProfileService>.value(
              value: profile,
            ),
            Provider<Workspace>.value(value: workspace),
          ],
          child: MaterialApp(
            theme: AppTheme.resolve(
              preset: AppearancePresets.all.first,
              brightness: Brightness.light,
            ),
            home: IntelligentPurchasingWorkspacePage(
              initialNeedId: _FakeIntelligentPurchasingService.need.id,
              service: _FakeIntelligentPurchasingService(),
              gatewayClient: AIAgentGatewayClient(
                transport: _NeverGatewayTransport(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('intelligent-purchasing-sections')),
        findsOneWidget,
      );
      expect(
        find.textContaining('disponibilidad por confirmar'),
        findsOneWidget,
      );
      expect(find.text('Kenda Kwick 27,5 × 2,10'), findsOneWidget);

      // La comparación se recompone: tabla en anchos útiles, cards en teléfono.
      if (width < 600) {
        expect(
          find.byKey(const ValueKey('provider-candidates-table')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('purchase-process-stepper')),
            findsOneWidget);
      } else {
        expect(
          find.byKey(const ValueKey('provider-candidates-table')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('purchase-process-steps')),
          findsOneWidget,
        );
      }
      // Ningún diálogo centrado: el módulo no monta superficies con velo.
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await _goToStep(tester, 'Necesidad');
      await _openComposer(tester);
      expect(
        find.byKey(const ValueKey('intelligent-purchasing-composer')),
        findsOneWidget,
      );
      await _goToStep(tester, 'Proveedores');
      expect(find.text('Kenda Kwick 27,5 × 2,10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'opens deterministic purchasing tools when the AI rollout is unavailable',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 820);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigation = NavigationService();
    final workspaces = WorkspaceManager(
      sessionIdentity: 'intelligent-purchasing-without-gateway',
    );
    final appearance = AppearanceService();
    final chat = ChatProvider();
    final profile = CurrentUserProfileService();
    final workspace = workspaces.activeWorkspace!;
    addTearDown(navigation.dispose);
    addTearDown(workspaces.dispose);
    addTearDown(appearance.dispose);
    addTearDown(chat.dispose);
    addTearDown(profile.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NavigationService>.value(value: navigation),
          ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
          ChangeNotifierProvider<AppearanceService>.value(value: appearance),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider<CurrentUserProfileService>.value(
            value: profile,
          ),
          Provider<Workspace>.value(value: workspace),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: IntelligentPurchasingWorkspacePage(
            initialNeedId: _FakeIntelligentPurchasingService.need.id,
            service: _FakeIntelligentPurchasingService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kenda Kwick 27,5 × 2,10'), findsOneWidget);
    await _goToStep(tester, 'Necesidad');
    await tester.enterText(
      find.byKey(const ValueKey('intelligent-purchasing-composer')),
      'neumáticos económicos',
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('intelligent-purchasing-analyze')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('La conversación con IA no está disponible'),
      findsOneWidget,
    );
    expect(find.text('Kenda Kwick 27,5 × 2,10'), findsNothing);
    await _goToStep(tester, 'Proveedores');
    expect(find.text('Kenda Kwick 27,5 × 2,10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a terminal AI failure retries as a fresh request',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 820);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigation = NavigationService();
    final workspaces = WorkspaceManager(
      sessionIdentity: 'intelligent-purchasing-terminal-retry',
    );
    final appearance = AppearanceService();
    final chat = ChatProvider();
    final profile = CurrentUserProfileService();
    final workspace = workspaces.activeWorkspace!;
    final transport = _TerminalFailureGatewayTransport();
    addTearDown(navigation.dispose);
    addTearDown(workspaces.dispose);
    addTearDown(appearance.dispose);
    addTearDown(chat.dispose);
    addTearDown(profile.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NavigationService>.value(value: navigation),
          ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
          ChangeNotifierProvider<AppearanceService>.value(value: appearance),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider<CurrentUserProfileService>.value(
            value: profile,
          ),
          Provider<Workspace>.value(value: workspace),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: IntelligentPurchasingWorkspacePage(
            service: _FakeIntelligentPurchasingService(),
            gatewayClient: AIAgentGatewayClient(transport: transport),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('intelligent-purchasing-composer')),
      'neumáticos económicos',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('intelligent-purchasing-analyze')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('evidencia suficiente'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(transport.requestIds, hasLength(2));
    expect(transport.requestIds[1], isNot(transport.requestIds[0]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an AI inventory result as one compact action',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigation = NavigationService();
    final workspaces = WorkspaceManager(
      sessionIdentity: 'intelligent-purchasing-action-card',
    );
    final appearance = AppearanceService();
    final chat = ChatProvider();
    final profile = CurrentUserProfileService();
    final workspace = workspaces.activeWorkspace!;
    addTearDown(navigation.dispose);
    addTearDown(workspaces.dispose);
    addTearDown(appearance.dispose);
    addTearDown(chat.dispose);
    addTearDown(profile.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NavigationService>.value(value: navigation),
          ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
          ChangeNotifierProvider<AppearanceService>.value(value: appearance),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider<CurrentUserProfileService>.value(
            value: profile,
          ),
          Provider<Workspace>.value(value: workspace),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: IntelligentPurchasingWorkspacePage(
            service: _FakeIntelligentPurchasingService(),
            gatewayClient: AIAgentGatewayClient(
              transport: _ActionCardGatewayTransport(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('intelligent-purchasing-composer')),
      'busca el pedal exacto',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('intelligent-purchasing-analyze')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hay una coincidencia exacta en stock.'), findsOneWidget);
    expect(find.text('1 resultado'), findsOneWidget);
    expect(find.text('Pedal ENLEE CR-2'), findsOneWidget);
    expect(find.text('En stock'), findsNothing);
    expect(find.text('Top 5'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('ai-action-card-inventory-inventoryProducts'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reviews and atomically saves a decomposed supply request',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1100);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigation = NavigationService();
    final workspaces = WorkspaceManager(
      sessionIdentity: 'intelligent-purchasing-supply-draft',
    );
    final appearance = AppearanceService();
    final chat = ChatProvider();
    final profile = CurrentUserProfileService();
    final workspace = workspaces.activeWorkspace!;
    final service = _BatchIntelligentPurchasingService();
    final transport = _SupplyDraftGatewayTransport();
    addTearDown(navigation.dispose);
    addTearDown(workspaces.dispose);
    addTearDown(appearance.dispose);
    addTearDown(chat.dispose);
    addTearDown(profile.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NavigationService>.value(value: navigation),
          ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
          ChangeNotifierProvider<AppearanceService>.value(value: appearance),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider<CurrentUserProfileService>.value(
            value: profile,
          ),
          Provider<Workspace>.value(value: workspace),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: IntelligentPurchasingWorkspacePage(
            service: service,
            gatewayClient: AIAgentGatewayClient(transport: transport),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('intelligent-purchasing-composer')),
      'necesito dos neumáticos y un juego de rayos 27,5',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('intelligent-purchasing-analyze')),
    );
    await tester.pumpAndSettle();

    expect(
      transport.lastBody?['viewContext'],
      <String, Object?>{
        'kind': 'intelligent_purchasing',
        'jobIds': <String>[],
        'truncated': false,
      },
    );
    // Una sola salida al final de la decisión, con su microcopia honesta.
    // El borrador trae una línea sin producto confirmado, así que la CTA no
    // puede prometer bodega ni comparación: guarda pendiente.
    expect(find.text('Guardar pendiente y continuar'), findsOneWidget);
    expect(find.text('Guardar y revisar stock'), findsNothing);
    expect(
      find.textContaining('Se guarda con la identidad pendiente'),
      findsOneWidget,
    );
    expect(
      find.textContaining('no compra, no reserva stock'),
      findsOneWidget,
    );
    expect(find.textContaining('Producto confirmado ·'), findsOneWidget);
    expect(find.text('Producto por precisar'), findsOneWidget);
    // Esta fixture bloquea sin prompts tipados: es el camino legacy y conserva
    // la salida anterior tal cual, sin abrir ningún control.
    expect(
      find.byKey(const ValueKey('material-clarification-legacy')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('material-clarification')), findsNothing);
    expect(find.text('Antes de comparar hace falta una precisión'),
        findsOneWidget);
    expect(find.text('Corregir la petición'), findsOneWidget);
    expect(find.byKey(const ValueKey('clarification-continue')), findsNothing);
    expect(
      find.byKey(const ValueKey('supply-draft-review-surface')),
      findsOneWidget,
    );
    expect(find.text('Todavía no hay necesidades por resolver'), findsNothing);
    expect(
      find.byKey(
        const ValueKey('ai-action-card-supply_need_draft-purchases'),
      ),
      findsNothing,
    );
    expect(find.text('Guardar necesidad'), findsNothing);

    await _goToStep(tester, 'Proveedores');
    expect(find.text('Kenda Kwick 27,5 × 2,10'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('supply-draft-review-surface')),
      findsNothing,
    );

    await _goToStep(tester, 'Necesidad');
    await _openComposer(tester);
    expect(
      find.byKey(const ValueKey('supply-draft-review-surface')),
      findsOneWidget,
    );
    // El paso ya no rotula la CTA con el recuento: es una sola acción estable
    // («Guardar y revisar stock» / «Guardar y comparar») sobre el borrador
    // completo. Lo que debe seguir en pie es que las dos líneas sobrevivieron
    // al ida y vuelta y que la CTA sigue disponible.
    expect(
      find.byKey(const ValueKey('save-supply-need-draft')),
      findsOneWidget,
    );
    // Los `lineRef` del borrador son 1-based: `line-1`, `line-2`…
    expect(
      find.byKey(const ValueKey('supply-draft-edit-line-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('supply-draft-edit-line-2')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('supply-draft-edit-line-1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('supply-draft-quantity-field-line-1')),
      '3',
    );
    await tester.tap(find.byKey(const ValueKey('supply-draft-save-line-1')));
    await tester.pumpAndSettle();
    // La cantidad editada aparece en dos lugares legítimos: la propia línea y
    // el resumen derivado de la interpretación, que ahora sustituye a la prosa
    // del modelo como texto primario.
    expect(find.textContaining('3 unidades'), findsNWidgets(2));
    // El resumen derivado lleva su propia key y refleja la cantidad editada.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('assistant-interpretation')))
          .data,
      contains('3 unidades'),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('save-supply-need-draft')),
    );
    await tester.tap(
      find.byKey(const ValueKey('save-supply-need-draft')),
    );
    await tester.pumpAndSettle();

    expect(service.savedDraft?.lines, hasLength(2));
    expect(service.savedDraft?.lines.first.quantity, 3);
    expect(service.savedDraft?.lines.last.description, 'Rayos 27,5');
    expect(service.operationKeys, hasLength(1));
    expect(find.text('Guardar 2 necesidades'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a candidate becomes a persistent review-only draft',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigation = NavigationService();
    final workspaces = WorkspaceManager(
      sessionIdentity: 'intelligent-purchasing-plan-test',
    );
    final appearance = AppearanceService();
    final chat = ChatProvider();
    final profile = CurrentUserProfileService();
    final workspace = workspaces.activeWorkspace!;
    addTearDown(navigation.dispose);
    addTearDown(workspaces.dispose);
    addTearDown(appearance.dispose);
    addTearDown(chat.dispose);
    addTearDown(profile.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NavigationService>.value(value: navigation),
          ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
          ChangeNotifierProvider<AppearanceService>.value(value: appearance),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider<CurrentUserProfileService>.value(
            value: profile,
          ),
          Provider<Workspace>.value(value: workspace),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: IntelligentPurchasingWorkspacePage(
            initialNeedId: _FakeIntelligentPurchasingService.need.id,
            service: _FakeIntelligentPurchasingService(),
            gatewayClient: AIAgentGatewayClient(
              transport: _NeverGatewayTransport(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Seleccionar la fila abre el inspector anclado, no un modal.
    await tester.ensureVisible(find.text('Kenda Kwick 27,5 × 2,10'));
    await tester.tap(find.text('Kenda Kwick 27,5 × 2,10'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('candidate-inspector')), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    final addToPlan = find.byKey(const ValueKey('add-candidate-to-plan'));
    await tester.ensureVisible(addToPlan);
    await tester.pumpAndSettle();
    await tester.tap(addToPlan);
    await tester.pumpAndSettle();

    await _goToStep(tester, 'Plan');
    expect(find.byKey(const ValueKey('plan-draft-header')), findsOneWidget);
    expect(find.text('Plan borrador'), findsOneWidget);
    expect(find.text('Andes Industrial'), findsWidgets);
    // La garantía de que no se compró nada vive en la meta de la cabecera.
    expect(find.textContaining('nada comprado'), findsOneWidget);
    expect(find.text('Volver a comparar'), findsOneWidget);
    expect(find.text('evidencia completa'), findsWidgets);
    // El control se alcanza por su `key`, que lleva el id de la línea. Antes
    // se buscaba por el tooltip «Editar cantidad», idéntico en todas las
    // líneas: con dos productos en el plan no identificaba ninguno.
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('plan-line-edit-quantity-'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('purchase-plan-quantity-field')),
      '1',
    );
    await tester.tap(
      find.byKey(const ValueKey('save-purchase-plan-quantity')),
    );
    await tester.pumpAndSettle();
    // Frame 24: la cantidad ya no es un subtítulo de texto, vive en el stepper
    // `− n +` de la línea, con la unidad al lado.
    final stepper = find.descendant(
      of: find.byType(PurchaseQuantityStepper),
      matching: find.text('1'),
    );
    expect(stepper, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PurchaseQuantityStepper),
        matching: find.text('unidad'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('plan-line-remove-'),
      ),
    );
    await tester.pumpAndSettle();
    // El vacío del plan es inline: sin isla centrada ni borde punteado.
    expect(find.byKey(const ValueKey('plan-empty-inline')), findsOneWidget);
    expect(find.text('Todavía no hay productos elegidos'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple needs produce an actionable stock-first scenario',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigation = NavigationService();
    final workspaces = WorkspaceManager(
      sessionIdentity: 'intelligent-purchasing-basket-test',
    );
    final appearance = AppearanceService();
    final chat = ChatProvider();
    final profile = CurrentUserProfileService();
    final workspace = workspaces.activeWorkspace!;
    addTearDown(navigation.dispose);
    addTearDown(workspaces.dispose);
    addTearDown(appearance.dispose);
    addTearDown(chat.dispose);
    addTearDown(profile.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NavigationService>.value(value: navigation),
          ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
          ChangeNotifierProvider<AppearanceService>.value(value: appearance),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider<CurrentUserProfileService>.value(
            value: profile,
          ),
          Provider<Workspace>.value(value: workspace),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: IntelligentPurchasingWorkspacePage(
            service: _FakeIntelligentPurchasingService(),
            gatewayClient: AIAgentGatewayClient(
              transport: _NeverGatewayTransport(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _goToStep(tester, 'Necesidad');
    await tester.tap(find.text('Armar canasta'));
    await tester.pumpAndSettle();
    final needA = find.byKey(const ValueKey('supply-need-need-a'));
    final needB = find.byKey(const ValueKey('supply-need-need-b'));
    await tester.ensureVisible(needA);
    await tester.tap(needA);
    await tester.pumpAndSettle();
    await tester.ensureVisible(needB);
    await tester.tap(needB);
    await tester.pumpAndSettle();
    expect(find.text('Comparar canasta (2)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('compare-basket')));
    await tester.pumpAndSettle();
    expect(find.text('Comparación de la canasta'), findsOneWidget);
    expect(find.text('Mejor equilibrio'), findsOneWidget);
    expect(find.textContaining('2 de 2 cubiertos'), findsOneWidget);
    expect(find.text('Stock interno · ATP 2 para 2'), findsOneWidget);
    expect(find.textContaining('disponibilidad por confirmar'), findsWidgets);

    final prepareScenario =
        find.byKey(const ValueKey('prepare-scenario-recommended:test'));
    await tester.ensureVisible(prepareScenario);
    await tester.pumpAndSettle();
    await tester.tap(prepareScenario);
    await tester.pumpAndSettle();
    expect(find.text('Plan borrador'), findsOneWidget);
    expect(find.textContaining('nada comprado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ───────────────────────────────────────────────────────────────────────
  // Frames 08/19 · aclaración progresiva tipada.
  // ───────────────────────────────────────────────────────────────────────
  Future<void> mountWithGateway(
    WidgetTester tester,
    double width,
    AIAgentGatewayTransport transport,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1400);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigation = NavigationService();
    final workspaces = WorkspaceManager(sessionIdentity: 't23-clarification');
    final appearance = AppearanceService();
    final chat = ChatProvider();
    final profile = CurrentUserProfileService();
    final workspace = workspaces.activeWorkspace!;
    addTearDown(navigation.dispose);
    addTearDown(workspaces.dispose);
    addTearDown(appearance.dispose);
    addTearDown(chat.dispose);
    addTearDown(profile.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NavigationService>.value(value: navigation),
          ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
          ChangeNotifierProvider<AppearanceService>.value(value: appearance),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider<CurrentUserProfileService>.value(
            value: profile,
          ),
          Provider<Workspace>.value(value: workspace),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: IntelligentPurchasingWorkspacePage(
            service: _FakeIntelligentPurchasingService(),
            gatewayClient: AIAgentGatewayClient(transport: transport),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> askFor(WidgetTester tester, String utterance) async {
    await _openComposer(tester);
    await tester.enterText(
      find.byKey(const ValueKey('intelligent-purchasing-composer')),
      utterance,
    );
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('intelligent-purchasing-analyze')));
    await tester.pumpAndSettle();
  }

  for (final width in const <double>[390, 834, 1440]) {
    final label = width.toInt();

    testWidgets('aclaración: una sola pregunta activa a $label px',
        (tester) async {
      final transport = _ClarificationGatewayTransport();
      await mountWithGateway(tester, width, transport);
      await askFor(tester, 'Necesito rayos para una rueda 29');

      // Una pregunta, no las dos.
      expect(
        find.byKey(const ValueKey('clarification-prompt-rim_kind')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('clarification-prompt-erd')),
        findsNothing,
      );
      expect(find.text('Pregunta 1 de 2'), findsOneWidget);
      // Filas de radio reales, no chips.
      expect(find.byType(RadioListTile<String>), findsNWidgets(2));
      expect(find.byType(ChoiceChip), findsNothing);
      // La petición original queda visible en su burbuja —una sola vez— y
      // editable desde el bloque de la pregunta.
      expect(find.byKey(const ValueKey('purchase-utterance')), findsOneWidget);
      expect(
        find.textContaining('Necesito rayos para una rueda 29'),
        findsOneWidget,
        reason: 'La petición no puede transcribirse dos veces en la columna.',
      );
      expect(
        find.byKey(const ValueKey('clarification-edit-original-request')),
        findsOneWidget,
      );
      // Nada modal ni centrado nuestro.
      expect(find.byType(Dialog), findsNothing);
      // Continuar está apagado hasta que haya respuesta.
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('clarification-continue')),
            )
            .onPressed,
        isNull,
      );
      // **Los dos caminos, en el punto de la decisión.** Con sólo el primario
      // apagado y su motivo, la pregunta se lee como un muro: la salida existía
      // pero vivía al final del borrador, pasada la evidencia consultada y
      // fuera de pantalla en teléfono. El contrato del frame 08 declara esta
      // secundaria desde el principio.
      expect(
        find.byKey(const ValueKey('clarification-answer-later')),
        findsOneWidget,
        reason: 'Seguir con lo entendido es la segunda vía del frame 08.',
      );
      expect(
        find.byKey(const ValueKey('clarification-answer-later-hint')),
        findsOneWidget,
        reason: 'Una salida que no dice qué deja pendiente no es una salida.',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'aclaración: elegir opción y continuar en el mismo hilo a '
        '$label px', (tester) async {
      final transport = _ClarificationGatewayTransport();
      await mountWithGateway(tester, width, transport);
      await askFor(tester, 'Necesito rayos para una rueda 29');

      await tester.tap(
        find.byKey(const ValueKey('clarification-option-rim_kind-r29')),
      );
      await tester.pumpAndSettle();
      // Responder avanza a la siguiente pregunta y deja la anterior resumida.
      expect(
        find.byKey(const ValueKey('clarification-answered-rim_kind')),
        findsOneWidget,
      );
      expect(find.text('Pregunta 2 de 2'), findsOneWidget);
      // Continuar sigue apagado y dice por qué.
      expect(
        find.byKey(const ValueKey('clarification-continue-hint')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('clarification-input-erd')),
        '584',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clarification-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clarification-continue')));
      await tester.pumpAndSettle();

      // Mismo hilo, y el mensaje es autocontenido con la petición original.
      expect(transport.bodies.length, 2);
      expect(
        transport.bodies.last['threadId'],
        '11111111-1111-4111-8111-111111111111',
      );
      final payload = jsonDecode(transport.bodies.last['message'] as String)
          as Map<String, Object?>;
      expect(payload['kind'], 'supply_need_clarification_answers');
      expect(payload['originalRequest'], 'Necesito rayos para una rueda 29');
      final answers = (payload['answers'] as List).cast<Map<String, Object?>>();
      expect(answers, hasLength(2));
      // Sólo lo acordado viaja: nada de estado interno del cliente.
      expect(
        answers.first.keys.toSet(),
        {'lineRef', 'promptId', 'question', 'answer'},
      );
      expect(answers.first['promptId'], 'rim_kind');
      expect(answers.first['answer'], 'r29');
      expect(answers.first['lineRef'], 'line-1');

      // Resuelto: ya no pregunta y la CTA deja de prometer pendiente.
      expect(
          find.byKey(const ValueKey('material-clarification')), findsNothing);
      expect(find.text('Guardar y revisar stock'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('aclaración: «No lo sé» viaja como unknown a $label px',
        (tester) async {
      final transport = _ClarificationGatewayTransport();
      await mountWithGateway(tester, width, transport);
      await askFor(tester, 'Necesito rayos para una rueda 29');

      await tester.tap(find.byKey(const ValueKey('clarification-unknown')));
      await tester.pumpAndSettle();
      // Queda dicho en pantalla, y se puede corregir antes de enviar.
      expect(
        find.textContaining('— No lo sé'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('clarification-change-rim_kind')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('clarification-input-erd')),
        '584',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clarification-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clarification-continue')));
      await tester.pumpAndSettle();

      final payload = jsonDecode(transport.bodies.last['message'] as String)
          as Map<String, Object?>;
      final answers = (payload['answers'] as List).cast<Map<String, Object?>>();
      final unknownAnswer =
          answers.firstWhere((a) => a['promptId'] == 'rim_kind');
      expect(unknownAnswer['unknown'], isTrue);
      expect(unknownAnswer.containsKey('answer'), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('aclaración: el número lleva su unidad como sufijo',
      (tester) async {
    final transport = _ClarificationGatewayTransport(alwaysBlocking: true);
    await mountWithGateway(tester, 1440, transport);
    await askFor(tester, 'Necesito rayos para una rueda 29');

    await tester
        .tap(find.byKey(const ValueKey('clarification-option-rim_kind-r29')));
    await tester.pumpAndSettle();

    // La siguiente pregunta es la numérica, con su unidad en el campo.
    final field = find.byKey(const ValueKey('clarification-input-erd'));
    expect(field, findsOneWidget);
    expect(
      tester.widget<TextField>(field).decoration?.suffixText,
      'mm',
    );
    // Sin `allowUnknown` no se ofrece la salida.
    expect(find.byKey(const ValueKey('clarification-unknown')), findsNothing);

    await tester.enterText(field, '584');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();

    final payload = jsonDecode(transport.bodies.last['message'] as String)
        as Map<String, Object?>;
    final answers = (payload['answers'] as List).cast<Map<String, Object?>>();
    expect(answers.map((a) => a['promptId']), containsAll(['rim_kind', 'erd']));
    expect(
      answers.firstWhere((a) => a['promptId'] == 'erd')['answer'],
      '584',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('aclaración: tope de tres rondas, sin cuarto interrogatorio',
      (tester) async {
    final transport = _ClarificationGatewayTransport(alwaysBlocking: true);
    await mountWithGateway(tester, 1440, transport);
    await askFor(tester, 'Necesito rayos para una rueda 29');

    for (var round = 0; round < 3; round++) {
      await tester.tap(
        find.byKey(const ValueKey('clarification-option-rim_kind-r29')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('clarification-input-erd')),
        '584',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clarification-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clarification-continue')));
      await tester.pumpAndSettle();
    }

    expect(
      find.byKey(const ValueKey('clarification-round-cap')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('clarification-continue')), findsNothing);
    expect(find.text('Corregir la petición'), findsOneWidget);
    // Y la salida de guardar pendiente sigue disponible.
    expect(find.text('Guardar pendiente y continuar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aclaración: un fallo no pierde la respuesta ni gasta la ronda',
      (tester) async {
    final transport = _ClarificationGatewayTransport(alwaysBlocking: true);
    await mountWithGateway(tester, 1440, transport);
    await askFor(tester, 'Necesito rayos para una rueda 29');

    await tester
        .tap(find.byKey(const ValueKey('clarification-option-rim_kind-r29')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('clarification-input-erd')),
      '584',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();
    transport.failures = 1;
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();

    // La respuesta dada sobrevive al fallo y sigue visible para reenviarla.
    expect(
      find.byKey(const ValueKey('clarification-answered-rim_kind')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('clarification-send-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el tope cuenta respuestas confirmadas, no envíos',
      (tester) async {
    final transport = _ClarificationGatewayTransport(alwaysBlocking: true);
    await mountWithGateway(tester, 1440, transport);
    await askFor(tester, 'Necesito rayos para una rueda 29');

    Future<void> answerRound() async {
      await tester.tap(
        find.byKey(const ValueKey('clarification-option-rim_kind-r29')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('clarification-input-erd')),
        '584',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clarification-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clarification-continue')));
      await tester.pumpAndSettle();
    }

    // Ronda 1 falla: no puede consumir cupo.
    await tester.tap(
      find.byKey(const ValueKey('clarification-option-rim_kind-r29')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('clarification-input-erd')),
      '584',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();
    transport.failures = 1;
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('clarification-send-error')), findsOneWidget);

    // Reintentar vive junto al error, no en Continuar: reusa el mismo
    // `clientRequestId` en vez de abrir una petición nueva.
    final retry = find.byKey(const ValueKey('clarification-retry'));
    expect(retry, findsOneWidget);
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    // Ese reintento SÍ es una respuesta confirmada: cuenta como ronda 1.
    expect(find.byKey(const ValueKey('clarification-round-cap')), findsNothing);

    await answerRound(); // 2
    expect(find.byKey(const ValueKey('clarification-round-cap')), findsNothing);
    await answerRound(); // 3 → tope
    expect(
      find.byKey(const ValueKey('clarification-round-cap')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dos entradas seguidas no comparten borrador', (tester) async {
    final transport = _ClarificationGatewayTransport(
        alwaysBlocking: true, consecutiveInputs: true);
    await mountWithGateway(tester, 1440, transport);
    await askFor(tester, 'Necesito rayos para una rueda 29');

    await tester.enterText(
      find.byKey(const ValueKey('clarification-input-erd')),
      '584',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();

    // La segunda entrada empieza vacía: nada se filtra de la primera.
    final second = find.byKey(const ValueKey('clarification-input-hub_note'));
    expect(second, findsOneWidget);
    expect(tester.widget<TextField>(second).controller?.text, '');

    await tester.enterText(second, 'maza vieja');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();

    // «Cambiar» sobre la primera no toca el borrador de la segunda.
    await tester.tap(find.byKey(const ValueKey('clarification-change-erd')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
              find.byKey(const ValueKey('clarification-input-erd')))
          .controller
          ?.text,
      '',
    );
    expect(
      find.byKey(const ValueKey('clarification-answered-hub_note')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('el número rechaza texto y acepta coma o punto', (tester) async {
    final transport = _ClarificationGatewayTransport(
        alwaysBlocking: true, consecutiveInputs: true);
    await mountWithGateway(tester, 1440, transport);
    await askFor(tester, 'Necesito rayos para una rueda 29');

    final field = find.byKey(const ValueKey('clarification-input-erd'));
    await tester.enterText(field, 'quinientos');
    await tester.pumpAndSettle();
    // Error compacto en el propio campo, sin modal, y sin respuesta guardada.
    expect(
      find.textContaining('Escribe sólo un número'),
      findsOneWidget,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(
      find.byKey(const ValueKey('clarification-answered-erd')),
      findsNothing,
    );

    // La coma se acepta y se normaliza antes de viajar.
    await tester.enterText(field, '584,5');
    await tester.pumpAndSettle();
    expect(find.textContaining('Escribe sólo un número'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('clarification-input-hub_note')),
      'ok',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();

    final payload = jsonDecode(transport.bodies.last['message'] as String)
        as Map<String, Object?>;
    final answers = (payload['answers'] as List).cast<Map<String, Object?>>();
    expect(
      answers.firstWhere((a) => a['promptId'] == 'erd')['answer'],
      '584.5',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('con todo respondido no se repite el último control',
      (tester) async {
    final transport = _ClarificationGatewayTransport(alwaysBlocking: true);
    await mountWithGateway(tester, 1440, transport);
    await askFor(tester, 'Necesito rayos para una rueda 29');

    await tester
        .tap(find.byKey(const ValueKey('clarification-option-rim_kind-r29')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('clarification-input-erd')),
      '584',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();

    // Queda el resumen corregible y una sola salida; ningún control repetido.
    expect(find.byKey(const ValueKey('clarification-submit')), findsOneWidget);
    expect(find.byKey(const ValueKey('clarification-input-erd')), findsNothing);
    expect(find.byType(RadioListTile<String>), findsNothing);
    expect(find.byKey(const ValueKey('clarification-progress')), findsNothing);
    expect(
      find.byKey(const ValueKey('clarification-answered-rim_kind')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('clarification-answered-erd')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('clarification-continue')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un campo numérico permanece mientras se escribe cada dígito',
      (tester) async {
    final transport = _ClarificationGatewayTransport(alwaysBlocking: true);
    await mountWithGateway(tester, 1440, transport);
    await askFor(tester, 'Necesito rayos para una rueda 29');

    await tester
        .tap(find.byKey(const ValueKey('clarification-option-rim_kind-r29')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('clarification-input-erd'));

    await tester.enterText(field, '2');
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    await tester.enterText(field, '27');
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    await tester.enterText(field, '274');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller?.text, '274');
    expect(
      find.byKey(const ValueKey('clarification-answered-erd')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(
      find.byKey(const ValueKey('clarification-answered-erd')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('un envío de respuesta muestra un solo estado de carga',
      (tester) async {
    final transport = _ClarificationGatewayTransport(alwaysBlocking: true);
    await mountWithGateway(tester, 1440, transport);
    await askFor(tester, 'Necesito rayos para una rueda 29');

    // Interpretar una petición nueva sí tiene su fila propia…
    await tester.tap(
      find.byKey(const ValueKey('clarification-option-rim_kind-r29')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('clarification-input-erd')),
      '584',
    );
    await tester.pumpAndSettle();
    // El primer gesto confirma la entrada; el segundo envía la ronda.
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('clarification-submit')), findsOneWidget);
    final gate = Completer<void>();
    transport.gate = gate;
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pump();

    // …pero al responder, el estado vive en el botón y no se duplica arriba.
    expect(find.byKey(const ValueKey('purchase-interpreting')), findsNothing);
    expect(find.text('Interpretando tu petición…'), findsNothing);
    expect(find.text('Enviando…'), findsOneWidget);
    transport.gate = null;
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('un fallo terminal deja una sola banda con Reintentar',
      (tester) async {
    final transport = _ClarificationGatewayTransport(alwaysBlocking: true);
    await mountWithGateway(tester, 1440, transport);
    await askFor(tester, 'Necesito rayos para una rueda 29');

    await tester.tap(
      find.byKey(const ValueKey('clarification-option-rim_kind-r29')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('clarification-input-erd')),
      '584',
    );
    await tester.pumpAndSettle();
    // Confirmar la entrada primero; el envío es el segundo gesto.
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();
    transport.failures = 1;
    await tester.tap(find.byKey(const ValueKey('clarification-continue')));
    await tester.pumpAndSettle();

    // Una sola banda de error y un solo Reintentar en toda la pantalla.
    expect(
      find.byKey(const ValueKey('clarification-send-error')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('assistant-retry')), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la limitación del ERP avisa junto a la línea y no bloquea',
      (tester) async {
    await mountWithGateway(tester, 1440, _CoverageNoticeGatewayTransport());
    await askFor(tester, 'Necesito 36 rayos negros de 274 mm');

    // Ni pregunta, ni encabezado de precisión, ni controles.
    expect(find.byKey(const ValueKey('material-clarification')), findsNothing);
    expect(
      find.byKey(const ValueKey('material-clarification-legacy')),
      findsNothing,
    );
    expect(
      find.text('Antes de comparar hace falta una precisión'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('clarification-continue')), findsNothing);
    // La advertencia vive junto a su línea, en secundario.
    expect(
      find.byKey(const ValueKey('supply-draft-coverage-note-line-1')),
      findsOneWidget,
    );
    // Producto confirmado ⇒ la CTA sí puede prometer bodega.
    expect(find.text('Guardar y revisar stock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la prosa larga no domina: resumen breve y explicación plegada',
      (tester) async {
    final prose = 'Analicé la petición ${'y consideré varias rutas ' * 40}';
    final transport = _ClarificationGatewayTransport(prose: prose);
    await mountWithGateway(tester, 1440, transport);
    await askFor(tester, 'Necesito rayos para una rueda 29');

    // El texto primario es el resumen derivado, corto y predecible.
    final summary = tester
        .widget<Text>(find.byKey(const ValueKey('assistant-interpretation')))
        .data!;
    expect(summary, startsWith('Entendí '));
    expect(summary.length, lessThan(prose.length));
    // La prosa está plegada.
    expect(
      find.byKey(const ValueKey('assistant-explanation-body')),
      findsNothing,
    );
    await tester
        .tap(find.byKey(const ValueKey('assistant-explanation-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('assistant-explanation-body')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  // ───────────────────────────────────────────────────────────────────────
  // Transiciones del handoff-t23 cableadas a estado real.
  // ───────────────────────────────────────────────────────────────────────
  Future<void> mountWorkspace(
    WidgetTester tester,
    double width, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1200);
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigation = NavigationService();
    final workspaces = WorkspaceManager(sessionIdentity: 't23-transitions');
    final appearance = AppearanceService();
    final chat = ChatProvider();
    final profile = CurrentUserProfileService();
    final workspace = workspaces.activeWorkspace!;
    addTearDown(navigation.dispose);
    addTearDown(workspaces.dispose);
    addTearDown(appearance.dispose);
    addTearDown(chat.dispose);
    addTearDown(profile.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NavigationService>.value(value: navigation),
          ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
          ChangeNotifierProvider<AppearanceService>.value(value: appearance),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider<CurrentUserProfileService>.value(
            value: profile,
          ),
          Provider<Workspace>.value(value: workspace),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: brightness,
          ),
          home: IntelligentPurchasingWorkspacePage(
            initialNeedId: _FakeIntelligentPurchasingService.need.id,
            service: _FakeIntelligentPurchasingService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ───────────────────────────────────────────────────────────────────────
  // Frames 22–25 · oscuro. Misma composición, roles de tema, sin negro puro.
  // ───────────────────────────────────────────────────────────────────────
  for (final width in const <double>[390, 1440]) {
    final label = width.toInt();

    testWidgets('frames 22/25 · stock en oscuro a $label px', (tester) async {
      _FakeIntelligentPurchasingService.overrideCandidates = null;
      await mountWorkspace(tester, width, brightness: Brightness.dark);
      await _goToStep(tester, 'Stock interno');

      expect(
          find.byKey(const ValueKey('internal-stock-surface')), findsOneWidget);
      expect(find.text('Stock interno primero'), findsOneWidget);
      _expectDarkRolesAreLegible(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('frames 22/23 · resultados e inspector en oscuro a $label px',
        (tester) async {
      _FakeIntelligentPurchasingService.overrideCandidates = null;
      await mountWorkspace(tester, width, brightness: Brightness.dark);
      await _goToStep(tester, 'Proveedores');

      expect(find.byKey(const ValueKey('provider-results')), findsOneWidget);
      await tester.tap(find.text('Kenda Kwick 27,5 × 2,10').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('candidate-inspector')),
        findsOneWidget,
      );
      // El detalle no atenúa la comparación en ninguna talla.
      expect(find.byType(Dialog), findsNothing);
      _expectDarkRolesAreLegible(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('frame 24 · plan en oscuro a $label px', (tester) async {
      _FakeIntelligentPurchasingService.overrideCandidates = null;
      await mountWorkspace(tester, width, brightness: Brightness.dark);
      await _goToStep(tester, 'Proveedores');
      await tester.tap(find.text('Kenda Kwick 27,5 × 2,10').first);
      await tester.pumpAndSettle();
      final addToPlan = find.byKey(const ValueKey('add-candidate-to-plan'));
      await tester.ensureVisible(addToPlan);
      await tester.pumpAndSettle();
      await tester.tap(addToPlan);
      await tester.pumpAndSettle();
      await _goToStep(tester, 'Plan');

      expect(find.byKey(const ValueKey('plan-draft-header')), findsOneWidget);
      expect(find.text('Plan borrador'), findsOneWidget);
      expect(find.text('evidencia completa'), findsWidgets);
      _expectDarkRolesAreLegible(tester);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in const <double>[390, 834, 1440]) {
    final label = width.toInt();

    testWidgets('frame 09 · análisis parcial y su retorno a $label px',
        (tester) async {
      // Señal real: el servidor devuelve un candidato sin evaluar.
      _FakeIntelligentPurchasingService.extraCandidates = [
        {
          'candidateId': 'candidate-b',
          'rank': 2,
          'productId': 'product-b',
          'productName': 'Ralco Spectre 27,5 × 2,25',
          'supplierName': 'Bicicletas del Sur',
          'supplierAvailability': 'unverified',
          'purchaseCount': 0,
          'evidenceAgeDays': 0,
          'evidenceQuality': 'unevaluated',
        },
      ];
      addTearDown(
        () => _FakeIntelligentPurchasingService.extraCandidates = [],
      );
      _FakeIntelligentPurchasingService.lastRankLimit = 0;

      await mountWorkspace(tester, width);
      await _goToStep(tester, 'Proveedores');

      final notice = find.byKey(const ValueKey('partial-analysis-notice'));
      expect(notice, findsOneWidget);
      expect(find.textContaining('Evaluamos 1 de 2 opciones'), findsOneWidget);
      expect(
        find.textContaining('Falta Bicicletas del Sur'),
        findsOneWidget,
      );
      expect(_FakeIntelligentPurchasingService.lastRankLimit, 10);

      // Continuar relanza con el corte ampliado y no saca del paso.
      final go = find.byKey(const ValueKey('continue-partial-analysis'));
      await tester.ensureVisible(go);
      await tester.pumpAndSettle();
      await tester.tap(go);
      await tester.pumpAndSettle();
      expect(_FakeIntelligentPurchasingService.lastRankLimit, 25);
      expect(find.byKey(const ValueKey('provider-results')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('frame 10 · el filtro esconde todo y se revierte a $label px',
        (tester) async {
      // Ningún candidato tiene evidencia suficiente: el filtro puede
      // esconderlos a todos y el estado del frame 10 es alcanzable de verdad.
      _FakeIntelligentPurchasingService.overrideCandidates = [
        {
          'candidateId': 'candidate-review',
          'rank': 1,
          'productId': 'product-a',
          'productName': 'Ralco Explorer 27,5 × 2,10',
          'supplierName': 'Andes Industrial',
          'supplierAvailability': 'unverified',
          'latestLandedUnitCostNet': 10100,
          'purchaseCount': 3,
          'evidenceAgeDays': 40,
          'evidenceQuality': 'partial',
        },
        {
          'candidateId': 'candidate-weak',
          'rank': 2,
          'productId': 'product-b',
          'productName': 'Ralco Spectre 27,5 × 2,25',
          'supplierName': 'Bicicletas del Sur',
          'supplierAvailability': 'unverified',
          'purchaseCount': 0,
          'evidenceAgeDays': 0,
          'evidenceQuality': 'weak',
        },
      ];
      addTearDown(
        () => _FakeIntelligentPurchasingService.overrideCandidates = null,
      );

      await mountWorkspace(tester, width);
      await _goToStep(tester, 'Proveedores');

      final noMatch = find.byKey(const ValueKey('no-match-surface'));
      final phone = width < 600;
      final menuId = phone ? 'provider-sort-and-filters' : 'provider-view-menu';

      // Punto de partida: sin filtro, los dos candidatos se ven.
      expect(noMatch, findsNothing);
      expect(find.textContaining('2 candidatos'), findsOneWidget);

      // 1. Se enciende el filtro real desde el control que existe en esta
      //    talla. En teléfono es el compacto, que ahora también lo ofrece.
      Future<void> pickOption(String option) async {
        final menu = find.byKey(ValueKey<String>(menuId));
        await tester.ensureVisible(menu);
        await tester.pumpAndSettle();
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(ValueKey<String>('$menuId-option-$option')));
        await tester.pumpAndSettle();
      }

      await pickOption('confirmed_only');
      expect(noMatch, findsOneWidget);
      expect(
        find.text('Ninguna opción cumple todos los filtros'),
        findsOneWidget,
      );
      // La causa dice el número real de opciones existentes.
      expect(find.textContaining('Existen 2 opciones'), findsOneWidget);
      expect(find.textContaining('0 visibles con el filtro activo'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('provider-candidates-table')),
          findsNothing);

      // 2. «Incluir opciones con compatibilidad por confirmar» devuelve los
      //    candidatos: la acción muta estado real, no es texto muerto.
      final include =
          find.byKey(const ValueKey('include-unconfirmed-compatibility'));
      await tester.ensureVisible(include);
      await tester.pumpAndSettle();
      await tester.tap(include);
      await tester.pumpAndSettle();
      expect(noMatch, findsNothing);
      expect(find.textContaining('2 candidatos'), findsOneWidget);

      // 3. El filtro se vuelve a aplicar y ahora se revierte con «Quitar
      //    filtros»: la reversibilidad vale por los dos caminos.
      await pickOption('confirmed_only');
      expect(noMatch, findsOneWidget);
      final clear = find.byKey(const ValueKey('clear-provider-filters'));
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(noMatch, findsNothing);
      expect(find.textContaining('2 candidatos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('frame 13 · compra local se ancla y cierra a $label px',
        (tester) async {
      _FakeIntelligentPurchasingService.extraCandidates = [];
      await mountWorkspace(tester, width);
      await _goToStep(tester, 'Proveedores');

      // El plan se habilita recién con una línea: se agrega una de verdad.
      await tester.tap(find.text('Kenda Kwick 27,5 × 2,10').first);
      await tester.pumpAndSettle();
      final addToPlan = find.byKey(const ValueKey('add-candidate-to-plan'));
      await tester.ensureVisible(addToPlan);
      await tester.pumpAndSettle();
      await tester.tap(addToPlan);
      await tester.pumpAndSettle();
      await _goToStep(tester, 'Plan');

      final open = find.byKey(const ValueKey('plan-register-local-purchase'));
      await tester.ensureVisible(open);
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('local-purchase-sheet')),
        findsOneWidget,
      );
      // Anclada de verdad: no es una isla centrada. En ancho toca el borde
      // derecho; en teléfono, el inferior. (`ModalBarrier` no sirve como
      // aserción aquí: el propio `Scaffold` del shell inserta uno para su
      // drawer, esté o no visible.)
      expect(find.byType(Dialog), findsNothing);
      final sheetRect =
          tester.getRect(find.byKey(const ValueKey('local-purchase-sheet')));
      final screen = tester.getRect(find.byType(MaterialApp));
      if (width < 600) {
        expect(sheetRect.bottom, moreOrLessEquals(screen.bottom, epsilon: 1));
      } else {
        expect(sheetRect.right, moreOrLessEquals(screen.right, epsilon: 1));
        expect(sheetRect.left, greaterThan(screen.left));
      }
      // Los dos tratamientos reales, ninguno inventado. Se busca dentro de la
      // hoja: «Inventario» también es un ítem del menú lateral.
      final sheet = find.byKey(const ValueKey('local-purchase-sheet'));
      expect(
        find.descendant(of: sheet, matching: find.text('Inventario')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Consumible Taller')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('local-purchase-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('local-purchase-sheet')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  // Anchos de diseño del handoff-t23 (1440 / 1116 / 834 / 390) más los bordes.
  for (final width in const <double>[390, 834, 1116, 1440]) {
    testWidgets('handoff composition holds at ${width.toInt()} px',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final navigation = NavigationService();
      final workspaces = WorkspaceManager(
        sessionIdentity: 'intelligent-purchasing-handoff-${width.toInt()}',
      );
      final appearance = AppearanceService();
      final chat = ChatProvider();
      final profile = CurrentUserProfileService();
      final workspace = workspaces.activeWorkspace!;
      addTearDown(navigation.dispose);
      addTearDown(workspaces.dispose);
      addTearDown(appearance.dispose);
      addTearDown(chat.dispose);
      addTearDown(profile.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NavigationService>.value(value: navigation),
            ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
            ChangeNotifierProvider<AppearanceService>.value(value: appearance),
            ChangeNotifierProvider<ChatProvider>.value(value: chat),
            ChangeNotifierProvider<CurrentUserProfileService>.value(
              value: profile,
            ),
            Provider<Workspace>.value(value: workspace),
          ],
          child: MaterialApp(
            theme: AppTheme.resolve(
              preset: AppearancePresets.all.first,
              brightness: Brightness.light,
            ),
            home: IntelligentPurchasingWorkspacePage(
              initialNeedId: _FakeIntelligentPurchasingService.need.id,
              service: _FakeIntelligentPurchasingService(),
              gatewayClient: AIAgentGatewayClient(
                transport: _NeverGatewayTransport(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // El stock precede a proveedores en el propio proceso.
      await _goToStep(tester, 'Stock interno');
      expect(
        find.byKey(const ValueKey('internal-stock-surface')),
        findsOneWidget,
      );
      expect(
        find.textContaining('La bodega se consulta antes de cotizar'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await _goToStep(tester, 'Proveedores');
      // Sin foto en la ficha, el fallback conserva la misma geometría.
      final tiles = tester.widgetList<ProductMediaTile>(
        find.byType(ProductMediaTile),
      );
      expect(tiles, isNotEmpty);
      for (final tile in tiles) {
        expect(tile.size, greaterThan(0));
      }
      expect(find.text('KK'), findsWidgets);

      // Abrir el detalle no monta un modal ni atenúa el host.
      await tester.ensureVisible(find.text('Kenda Kwick 27,5 × 2,10'));
      await tester.tap(find.text('Kenda Kwick 27,5 × 2,10'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('candidate-inspector')), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);

      // Ir y volver conserva la selección del candidato.
      await _goToStep(tester, 'Stock interno');
      await _goToStep(tester, 'Proveedores');
      expect(find.byKey(const ValueKey('candidate-inspector')), findsOneWidget);

      // Toda talla ofrece una salida visible del detalle: nunca un callejón.
      final closeInspector = width < 600
          ? find.byKey(const ValueKey('back-to-candidates'))
          : find.byKey(const ValueKey('close-candidate-inspector'));
      await tester.ensureVisible(closeInspector);
      await tester.pumpAndSettle();
      await tester.tap(closeInspector);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('candidate-inspector')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  // Ningún editor puede volver a ser una isla centrada. Se prueba por
  // geometría: el editor debe ocupar el ancho de su columna y quedar anclado a
  // la izquierda, no flotar con márgenes simétricos sobre la página.
  for (final width in const <double>[390, 834, 1116, 1440]) {
    testWidgets('no editor floats as a centred island at ${width.toInt()} px',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 950);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final navigation = NavigationService();
      final workspaces = WorkspaceManager(
        sessionIdentity: 'intelligent-purchasing-island-${width.toInt()}',
      );
      final appearance = AppearanceService();
      final chat = ChatProvider();
      final profile = CurrentUserProfileService();
      final workspace = workspaces.activeWorkspace!;
      addTearDown(navigation.dispose);
      addTearDown(workspaces.dispose);
      addTearDown(appearance.dispose);
      addTearDown(chat.dispose);
      addTearDown(profile.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NavigationService>.value(value: navigation),
            ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
            ChangeNotifierProvider<AppearanceService>.value(value: appearance),
            ChangeNotifierProvider<ChatProvider>.value(value: chat),
            ChangeNotifierProvider<CurrentUserProfileService>.value(
              value: profile,
            ),
            Provider<Workspace>.value(value: workspace),
          ],
          child: MaterialApp(
            theme: AppTheme.resolve(
              preset: AppearancePresets.all.first,
              brightness: Brightness.light,
            ),
            home: IntelligentPurchasingWorkspacePage(
              service: _FakeIntelligentPurchasingService(),
              gatewayClient: AIAgentGatewayClient(
                transport: _SupplyDraftGatewayTransport(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _goToStep(tester, 'Necesidad');
      await _openComposer(tester);
      await tester.enterText(
        find.byKey(const ValueKey('intelligent-purchasing-composer')),
        'neumáticos 27,5 de ancho mayor a 2,0',
      );
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('intelligent-purchasing-analyze')));
      await tester.pumpAndSettle();

      final editButton = find.byKey(const ValueKey('supply-draft-edit-line-1'));
      await tester.ensureVisible(editButton);
      await tester.tap(editButton);
      await tester.pumpAndSettle();

      final editor =
          find.byKey(const ValueKey('supply-draft-inline-editor-line-1'));
      expect(editor, findsOneWidget);

      // Ninguna ruta modal: el editor vive en el árbol de la página.
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);

      // Geometría: mismo ancho que su sección y sin centrado simétrico.
      final editorRect = tester.getRect(editor);
      final scroll = tester.getRect(
        find.byKey(const ValueKey('intelligent-purchasing-request-scroll')),
      );
      expect(
        editorRect.width,
        closeTo(scroll.width, 1),
        reason: 'El editor debe ocupar el ancho de su columna, no flotar.',
      );
      final leftGap = editorRect.left - scroll.left;
      final rightGap = scroll.right - editorRect.right;
      expect(
        leftGap,
        lessThan(2),
        reason: 'Un editor anclado no deja margen de isla a la izquierda.',
      );
      expect((leftGap - rightGap).abs(), lessThan(2));

      // Salida clara y borrador preservado al cancelar.
      await tester.enterText(
        find.byKey(const ValueKey('supply-draft-quantity-field-line-1')),
        '5',
      );
      await tester.tap(
        find.byKey(const ValueKey('supply-draft-cancel-line-1')),
      );
      await tester.pumpAndSettle();
      expect(editor, findsNothing);
      expect(find.byKey(const ValueKey('supply-draft-edit-line-1')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('Fase B1/B2 — carril familia, stock-first y evidencia', () {
    setUp(_FakeIntelligentPurchasingService.resetSupplyState);
    tearDown(_FakeIntelligentPurchasingService.resetSupplyState);

    Future<void> mount(
      WidgetTester tester,
      IntelligentPurchasingService service, {
      required String needId,
    }) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final navigation = NavigationService();
      final workspaces = WorkspaceManager(sessionIdentity: 'b2-cut1-$needId');
      final appearance = AppearanceService();
      final chat = ChatProvider();
      final profile = CurrentUserProfileService();
      final workspace = workspaces.activeWorkspace!;
      addTearDown(navigation.dispose);
      addTearDown(workspaces.dispose);
      addTearDown(appearance.dispose);
      addTearDown(chat.dispose);
      addTearDown(profile.dispose);
      // El carril familia muestra el selector de identidad del producto, y ese
      // control exige el `InventoryService` **compartido** en el árbol —no el
      // del módulo de inventario, que es otra clase con el mismo nombre—.
      final inventory = InventoryService();
      addTearDown(inventory.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NavigationService>.value(value: navigation),
            ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
            ChangeNotifierProvider<AppearanceService>.value(value: appearance),
            ChangeNotifierProvider<ChatProvider>.value(value: chat),
            ChangeNotifierProvider<CurrentUserProfileService>.value(
              value: profile,
            ),
            ChangeNotifierProvider<InventoryService>.value(value: inventory),
            Provider<Workspace>.value(value: workspace),
          ],
          child: MaterialApp(
            theme: AppTheme.resolve(
              preset: AppearancePresets.all.first,
              brightness: Brightness.light,
            ),
            home: IntelligentPurchasingWorkspacePage(
              initialNeedId: needId,
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'una necesidad sin producto confirmado llega a proveedores',
      (tester) async {
        // El gate `hasConfirmedProduct` dejaba al carril familia sin ninguna
        // superficie: ni stock ni candidatos.
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsOneWidget);
        expect(
            find.byKey(const ValueKey('stock-first-required')), findsNothing);
      },
    );

    testWidgets(
      'stock_first_required es un estado con acción, no un error genérico',
      (tester) async {
        _FakeIntelligentPurchasingService.stockFirstRequired = true;
        // La resolución que la pantalla va a mostrar tiene que sustentar el
        // P0001: una bodega que no bloquea y un «primero decide el stock» son
        // dos momentos distintos, no una pantalla.
        _FakeIntelligentPurchasingService.overrideStockResolution = {
          'needId': 'need-family',
          'needVersion': 1,
          'revisionNo': 1,
          'quantity': 2,
          'unit': 'unit',
          'lane': 'family',
          'status': 'ok',
          'coverage': 'full',
          'blocksExternal': true,
          'items': const [],
          'counts': const {'eligible': 1, 'full': 1},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('stock-first-required')),
          findsOneWidget,
        );
        // El paso externo está cerrado: no se muestran candidatos.
        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsNothing);
        // Y no se presenta como una caída que se arregla reintentando.
        expect(
          find.text(
            'No se pudo completar el análisis. Puedes reintentar sin perder la necesidad.',
          ),
          findsNothing,
        );

        // La única acción que abre el paso está en la propia superficie.
        await tester.tap(find.byKey(const ValueKey('stock-first-explain')));
        await tester.pumpAndSettle();
        expect(
          find.text('¿Por qué no sirve el stock disponible?'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'el rechazo viaja con la revisión que gobierna, no con supply_needs',
      (tester) async {
        _FakeIntelligentPurchasingService.stockFirstRequired = true;
        // La necesidad va en su versión 9 y su revisión 4: los tres envelopes
        // dicen lo mismo, que es la única forma de que la pantalla sea real.
        _FakeIntelligentPurchasingService.supplyNeedVersion = 9;
        _FakeIntelligentPurchasingService.supplyRevisionNo = 4;
        _FakeIntelligentPurchasingService.overrideStockResolution = {
          'needId': 'need-family',
          'needVersion': 9,
          'revisionNo': 4,
          'quantity': 2,
          'unit': 'unit',
          'lane': 'family',
          'status': 'ok',
          'coverage': 'full',
          'blocksExternal': true,
          'items': const [],
          'counts': const {'eligible': 1, 'full': 1},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        await tester.tap(find.byKey(const ValueKey('stock-first-explain')));
        await tester.pumpAndSettle();
        // El campo se busca por su rótulo: la columna también trae el
        // buscador de identidad, y `.last` escribiría en el control
        // equivocado sin que la prueba lo note.
        await tester.enterText(
          find.ancestor(
            of: find.text('¿Por qué no sirve el stock disponible?'),
            matching: find.byType(TextField),
          ),
          'Reservado para otro trabajo',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Guardar motivo y comparar'));
        await tester.pumpAndSettle();

        // La revisión sale del envelope de la lectura, no de la necesidad.
        expect(
          _FakeIntelligentPurchasingService.commands,
          contains('reject:need-family:4'),
        );
      },
    );

    testWidgets(
      'analysis_too_broad no se confunde con «sin compras comparables»',
      (tester) async {
        _FakeIntelligentPurchasingService.overrideExternalEnvelope = {
          'needId': 'need-family',
          'needVersion': 1,
          'revisionNo': 1,
          'status': 'analysis_too_broad',
          'lane': 'family',
          'candidateUniverseSize': 900,
          'candidateSafeLimit': 600,
          'items': const [],
          'unverifiedItems': const [],
          'counts': const {},
          'page': const {},
          'unverifiedPage': const {},
          'target': const <String, dynamic>{},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('external-state-analysis_too_broad')),
          findsOneWidget,
        );
        expect(find.textContaining('900'), findsOneWidget);
        expect(
          find.text('No hay compras históricas comparables'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'no_historical_candidates ofrece registrar la compra local',
      (tester) async {
        _FakeIntelligentPurchasingService.overrideExternalEnvelope = {
          'needId': 'need-family',
          'needVersion': 1,
          'revisionNo': 1,
          'status': 'no_historical_candidates',
          'lane': 'family',
          'items': const [],
          'unverifiedItems': const [],
          'counts': const {},
          'page': const {},
          'unverifiedPage': const {},
          'target': const <String, dynamic>{},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(
            const ValueKey('external-state-action-no_historical_candidates'),
          ),
          findsOneWidget,
        );
        expect(find.text('Registrar una compra local'), findsOneWidget);
      },
    );

    testWidgets(
      'los no verificados van en su propio grupo, rotulados',
      (tester) async {
        _FakeIntelligentPurchasingService.unverifiedCandidates = [
          {
            'candidateId': 'candidate-unverified',
            'rank': 1,
            'group': 'unverified',
            'matchState': 'unverified',
            'productId': 'product-u',
            'productName': 'Cadena genérica reforzada',
            'supplierName': 'Andes Industrial',
            'supplierAvailability': 'unverified',
            'evidenceQuality': 'weak',
            'purchaseCount': 2,
            'evidenceAgeDays': 40,
          },
        ];
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('unverified-candidates-band')),
          findsOneWidget,
        );
        expect(find.text('1 opción sin verificar'), findsOneWidget);
        // Se muestra, no se esconde: no saber no es no calzar.
        expect(find.text('Cadena genérica reforzada'), findsOneWidget);
        // Y sigue siendo un grupo aparte del accionable.
        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsOneWidget);
      },
    );

    testWidgets(
      'una señal sin evidencia se dice «No verificable», nunca como cero',
      (tester) async {
        _FakeIntelligentPurchasingService.overrideCandidates = [
          {
            ..._FakeIntelligentPurchasingService.baseCandidateForTests,
            'requestMatch': {
              'state': 'strong',
              'group': 'actionable',
              'knownSignalCount': 0,
              'blendApplied': false,
              'signals': {
                'maxLandedUnitCostNet': {
                  'status': 'unknown',
                  'reason': 'currency_mismatch_no_fx',
                  'score': null,
                },
                'minGrossMarginRatio': {
                  'status': 'unknown',
                  'reason': 'incomplete_landed_cost',
                  'score': null,
                },
              },
            },
          },
        ];
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(find.text('Kenda Kwick 27,5 × 2,10').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kenda Kwick 27,5 × 2,10').first);
        await tester.pumpAndSettle();

        // El cuerpo del inspector es una lista: la sección de objetivo vive
        // al final y hay que traerla a vista antes de afirmarla.
        expect(
          find.byKey(const ValueKey('candidate-inspector')),
          findsOneWidget,
        );
        // La sección resume en la cabecera y despliega la evidencia: con cero
        // señales verificadas el resumen ya lo dice.
        expect(find.text('Objetivo comercial'), findsOneWidget);
        expect(find.text('sin verificar'), findsOneWidget);
        await tester.tap(find.text('Objetivo comercial'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('request-match-evidence')),
          findsOneWidget,
        );
        expect(
          find.text('Tope de costo · No verificable'),
          findsOneWidget,
        );
        expect(
          find.text('Están en monedas distintas y el sistema no convierte.'),
          findsOneWidget,
        );
        expect(
          find.text('Margen mínimo · No verificable'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Ninguna señal pudo verificarse: el puntaje es el del ranking, sin '
            'cambios.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'un estado técnico llega a su copy y NO al aviso de stock interno',
      (tester) async {
        // `needs_refinement` no es un bloqueo de bodega. Rotularlo «el stock
        // interno todavía puede cubrir esta necesidad» afirmaba algo falso
        // sobre el inventario y ofrecía la acción equivocada.
        _FakeIntelligentPurchasingService.overrideStockResolution = {
          'needId': 'need-family',
          'needVersion': 1,
          'revisionNo': 1,
          'quantity': 2,
          'unit': 'unit',
          'lane': 'family',
          'status': 'needs_refinement',
          'universeSize': 700,
          'safeLimit': 400,
          'availableFields': const ['chain_speeds'],
          'coverage': 'none',
          'blocksExternal': false,
          'items': const [],
          'counts': const {},
        };
        _FakeIntelligentPurchasingService.overrideExternalEnvelope = {
          'needId': 'need-family',
          'needVersion': 1,
          'revisionNo': 1,
          'status': 'needs_refinement',
          'lane': 'family',
          'universeSize': 700,
          'safeLimit': 400,
          'availableFields': const ['chain_speeds'],
          'items': const [],
          'unverifiedItems': const [],
          'counts': const {},
          'page': const {},
          'unverifiedPage': const {},
          'target': const <String, dynamic>{},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('external-state-needs_refinement')),
          findsOneWidget,
        );
        expect(find.textContaining('chain_speeds'), findsOneWidget);
        expect(
          find.text('El stock interno todavía puede cubrir esta necesidad'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'una necesidad cerrada llega a supply_closed, no a una lista vacía',
      (tester) async {
        // La lectura externa es dueña de este estado: condicionar la llamada a
        // `supplyState == open` lo hacía inalcanzable.
        _FakeIntelligentPurchasingService.overrideExternalEnvelope = {
          'needId': 'need-family',
          'needVersion': 1,
          'revisionNo': 1,
          'needSupplyState': 'covered',
          'status': 'supply_closed',
          'lane': 'family',
          'items': const [],
          'unverifiedItems': const [],
          'counts': const {},
          'page': const {},
          'unverifiedPage': const {},
          'target': const <String, dynamic>{},
        };
        await mount(
          tester,
          _FamilyLaneService(supplyState: 'covered'),
          needId: 'need-family',
        );
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('external-state-supply_closed')),
          findsOneWidget,
        );
        expect(
          find.text('No hay compras históricas comparables'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'el paso de stock del carril familia muestra sus alternativas',
      (tester) async {
        _FakeIntelligentPurchasingService.supplyNeedVersion = 3;
        _FakeIntelligentPurchasingService.supplyRevisionNo = 2;
        _FakeIntelligentPurchasingService.overrideStockResolution = {
          'needId': 'need-family',
          'needVersion': 3,
          'revisionNo': 2,
          'quantity': 2,
          'unit': 'unit',
          'lane': 'family',
          'status': 'ok',
          'coverage': 'partial',
          'blocksExternal': false,
          'items': [
            {
              'productId': 'product-stock',
              'name': 'Cadena X10 en bodega',
              'sku': 'CAD-STK',
              'atp': 1,
              'coverage': 'partial',
              'matchState': 'strong',
              'blocksExternal': false,
            },
          ],
          'counts': const {'eligible': 1, 'partial': 1},
        };
        final service = _FamilyLaneService();
        await mount(tester, service, needId: 'need-family');
        await _goToStep(tester, 'Stock interno');

        // Antes esto decía «No fue posible verificar el stock interno» aunque
        // el servidor había respondido: el snapshot exacto no existe en este
        // carril y la pantalla dependía de él.
        expect(
          find.text('No fue posible verificar el stock interno'),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('family-stock-options')),
          findsOneWidget,
        );
        expect(find.text('Cadena X10 en bodega'), findsOneWidget);
        expect(find.textContaining('cubre 1 de 2'), findsOneWidget);
        expect(
          find.textContaining('cumple los criterios según la ficha'),
          findsOneWidget,
        );

        final reloadsBefore = service.reloadCount;
        await tester.tap(
          find.byKey(const ValueKey('choose-stock-product-product-stock')),
        );
        await tester.pumpAndSettle();

        // Fija identidad con la revisión de la lectura y vuelve a leer.
        expect(
          _FakeIntelligentPurchasingService.commands,
          contains('confirm:need-family:product-stock:2'),
        );
        expect(service.reloadCount, greaterThan(reloadsBefore));
      },
    );

    testWidgets(
      'un candidato sin verificar abre el inspector',
      (tester) async {
        _FakeIntelligentPurchasingService.unverifiedCandidates = [
          {
            'candidateId': 'candidate-unverified',
            'rank': 1,
            'group': 'unverified',
            'matchState': 'unverified',
            'productId': 'product-u',
            'productName': 'Cadena genérica reforzada',
            'supplierName': 'Andes Industrial',
            'supplierAvailability': 'unverified',
            'evidenceQuality': 'weak',
            'purchaseCount': 2,
            'evidenceAgeDays': 40,
          },
        ];
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        await tester.ensureVisible(find.text('Cadena genérica reforzada'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cadena genérica reforzada'));
        await tester.pumpAndSettle();

        // Un grupo que se muestra y no se puede abrir es peor que no
        // mostrarlo: el inspector buscaba sólo en el grupo accionable.
        expect(
          find.byKey(const ValueKey('candidate-inspector')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('candidate-inspector')),
            matching: find.text('Cadena genérica reforzada'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '«ver más sin verificar» pide el segundo corte de ESE grupo',
      (tester) async {
        _FakeIntelligentPurchasingService.overrideExternalEnvelope = {
          'needId': 'need-family',
          'needVersion': 1,
          'revisionNo': 1,
          'status': 'success',
          'lane': 'family',
          'items': [_FakeIntelligentPurchasingService.baseCandidateForTests],
          'unverifiedItems': [
            {
              'candidateId': 'candidate-unverified',
              'rank': 1,
              'group': 'unverified',
              'matchState': 'unverified',
              'productId': 'product-u',
              'productName': 'Cadena genérica reforzada',
              'supplierName': 'Andes Industrial',
              'supplierAvailability': 'unverified',
              'evidenceQuality': 'weak',
              'purchaseCount': 2,
              'evidenceAgeDays': 40,
            },
          ],
          'counts': const {'actionable': 1, 'unverified': 4},
          'page': const {
            'limit': 10,
            'offset': 0,
            'total': 1,
            'returned': 1,
            'hasMore': false,
          },
          'unverifiedPage': const {
            'limit': 5,
            'offset': 0,
            'total': 4,
            'returned': 1,
            'hasMore': true,
            'nextOffset': 5,
          },
          'target': const <String, dynamic>{},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(find.textContaining('Mostrando 1 de 4'), findsOneWidget);
        _FakeIntelligentPurchasingService.commands.clear();
        await tester.ensureVisible(
          find.byKey(const ValueKey('show-more-unverified')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('show-more-unverified')));
        await tester.pumpAndSettle();

        // El corte ampliado es el del grupo sin verificar; el accionable
        // conserva el suyo, igual que las dos páginas del servidor.
        expect(
          _FakeIntelligentPurchasingService.commands,
          contains('external:10:0:10:0'),
        );
      },
    );

    testWidgets(
      'guardar el objetivo llama al comando y muestra la moneda resuelta',
      (tester) async {
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-commercial-target')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-commercial-target')));
        await tester.pumpAndSettle();

        // La moneda se enseña antes de guardar: es del servidor y no viaja.
        expect(
          find.byKey(const ValueKey('commercial-target-editor')),
          findsOneWidget,
        );
        expect(
          find.text('Tope de costo aterrizado (CLP)'),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const ValueKey('commercial-target-cost')),
          '12000',
        );
        // La gama es un desplegable anclado, el control del módulo para un
        // valor excluyente. Los chips salieron: no pertenecen a su vocabulario.
        await tester.tap(find.byKey(const ValueKey('commercial-target-gama')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('commercial-target-gama-option-media')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('commercial-target-save')));
        await tester.pumpAndSettle();

        expect(
          _FakeIntelligentPurchasingService.commands,
          contains('target:need-family:0:media:12000.0:null'),
        );
      },
    );

    testWidgets(
      'el perfil del servidor es un dato, no un menú que finge cambiarlo',
      (tester) async {
        _FakeIntelligentPurchasingService.overrideExternalEnvelope = {
          'needId': 'need-family',
          'needVersion': 1,
          'revisionNo': 1,
          'status': 'success',
          'lane': 'family',
          'rankingProfile': 'profitability',
          'rankingProfileSource': 'revision',
          'items': [_FakeIntelligentPurchasingService.baseCandidateForTests],
          'unverifiedItems': const [],
          'counts': const {'actionable': 1},
          'page': const {
            'limit': 10,
            'offset': 0,
            'total': 1,
            'returned': 1,
            'hasMore': false,
          },
          'unverifiedPage': const {},
          'target': const <String, dynamic>{},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        // Se muestra lo que el servidor resolvió…
        expect(
          find.byKey(const ValueKey('server-ranking-profile')),
          findsOneWidget,
        );
        expect(find.text('Prioridad · Mayor rentabilidad'), findsOneWidget);
        // …y ya no hay un menú que prometa cambiarlo sin tocar el backend.
        expect(
          find.byKey(const ValueKey('provider-profile-menu')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'un sin verificar con factura completa NO se muestra como «Cumple»',
      (tester) async {
        // `evidenceQuality` mide la calidad del historial económico, no la
        // compatibilidad técnica. Mezclarlas dejaba pasar la peor afirmación
        // posible: «Cumple» sobre algo que el ERP no pudo verificar.
        _FakeIntelligentPurchasingService.unverifiedCandidates = [
          {
            'candidateId': 'candidate-unverified',
            'rank': 1,
            'group': 'unverified',
            'matchState': 'unverified',
            'productId': 'product-u',
            'productName': 'Cadena genérica reforzada',
            'supplierName': 'Andes Industrial',
            'supplierAvailability': 'unverified',
            'evidenceQuality': 'complete',
            'freightEvidence': 'complete',
            'purchaseCount': 12,
            'evidenceAgeDays': 5,
          },
        ];
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        await tester.ensureVisible(find.text('Cadena genérica reforzada'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cadena genérica reforzada'));
        await tester.pumpAndSettle();

        final inspector = find.byKey(const ValueKey('candidate-inspector'));
        expect(inspector, findsOneWidget);
        expect(
          find.descendant(of: inspector, matching: find.text('Cumple')),
          findsNothing,
        );
        // El veredicto técnico vive en su sección; se despliega para leerlo.
        await tester.tap(find.text('Cumplimiento y compatibilidad'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: inspector,
            matching: find.text('no se pudo verificar'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'un candidato strong sí dice que cumple según la ficha',
      (tester) async {
        _FakeIntelligentPurchasingService.overrideCandidates = [
          {
            ..._FakeIntelligentPurchasingService.baseCandidateForTests,
            'matchState': 'strong',
            'group': 'actionable',
            // Evidencia económica débil: no debe cambiar el veredicto técnico.
            'evidenceQuality': 'weak',
          },
        ];
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(find.text('Kenda Kwick 27,5 × 2,10').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kenda Kwick 27,5 × 2,10').first);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cumplimiento y compatibilidad'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('candidate-inspector')),
            matching: find.text('sí, según la ficha'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'cambiar de necesidad cierra el editor y no arrastra sus números',
      (tester) async {
        await mount(tester, _FakeIntelligentPurchasingService(),
            needId: 'need-a');
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-commercial-target')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-commercial-target')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('commercial-target-cost')),
          '77777',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('commercial-target-editor')),
          findsOneWidget,
        );

        // Otra necesidad es otro objetivo: el editor abierto con los números
        // de la primera podía guardarse sobre la segunda.
        // La lista de necesidades vive en el primer paso; seleccionar otra
        // fila es lo que reproduce el arrastre de estado.
        await _goToStep(tester, 'Necesidad');
        final otherNeed = find.byKey(const ValueKey('supply-need-need-b'));
        await tester.ensureVisible(otherNeed);
        await tester.pumpAndSettle();
        await tester.tap(otherNeed);
        await tester.pumpAndSettle();
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('commercial-target-editor')),
          findsNothing,
        );
        expect(find.text('77777'), findsNothing);
      },
    );

    testWidgets(
      'un tope ilegible no se guarda ni borra el objetivo en silencio',
      (tester) async {
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-commercial-target')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-commercial-target')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('commercial-target-cost')),
          'doce mil',
        );
        await tester.tap(find.byKey(const ValueKey('commercial-target-save')));
        await tester.pumpAndSettle();

        // Ni comando, ni limpieza muda: el error se dice y el editor sigue.
        expect(
          _FakeIntelligentPurchasingService.commands
              .where((entry) => entry.startsWith('target:')),
          isEmpty,
        );
        expect(
            find.text('Escribe un número, con coma o punto.'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('commercial-target-editor')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'un margen fuera de rango se rechaza en vez de caer a cero',
      (tester) async {
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-commercial-target')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-commercial-target')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('commercial-target-margin')),
          '180',
        );
        await tester.tap(find.byKey(const ValueKey('commercial-target-save')));
        await tester.pumpAndSettle();

        expect(
          _FakeIntelligentPurchasingService.commands
              .where((entry) => entry.startsWith('target:')),
          isEmpty,
        );
        expect(find.text('El margen va entre 0 y 100.'), findsOneWidget);
      },
    );

    testWidgets(
      'la coma decimal es un número válido, no un error del taller',
      (tester) async {
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-commercial-target')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-commercial-target')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('commercial-target-margin')),
          '12,5',
        );
        await tester.tap(find.byKey(const ValueKey('commercial-target-save')));
        await tester.pumpAndSettle();

        expect(
          _FakeIntelligentPurchasingService.commands,
          contains('target:need-family:0:null:null:0.125'),
        );
      },
    );

    testWidgets(
      'la gama se elige en el desplegable anclado, no en chips',
      (tester) async {
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-commercial-target')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-commercial-target')));
        await tester.pumpAndSettle();

        expect(find.byType(ChoiceChip), findsNothing);
        expect(
          find.byKey(const ValueKey('commercial-target-gama')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('commercial-target-gama')));
        await tester.pumpAndSettle();
        // «Sin preferencia» es un valor del control: sin él no habría forma de
        // quitar una gama ya fijada.
        expect(find.text('Sin preferencia'), findsWidgets);
        expect(find.text('Económica'), findsWidgets);
      },
    );

    testWidgets(
      'stock viejo con candidatos de otra versión no se presenta mezclado',
      (tester) async {
        // Tres lecturas separadas pueden describir tres momentos. Montarlas
        // juntas dibuja una pantalla que no existió nunca.
        _FakeIntelligentPurchasingService.overrideStockResolution = {
          'needId': 'need-family',
          'needVersion': 5,
          'revisionNo': 3,
          'quantity': 2,
          'unit': 'unit',
          'lane': 'family',
          'status': 'ok',
          'coverage': 'none',
          'blocksExternal': false,
          'items': const [],
          'counts': const {'eligible': 1},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('reload-after-conflict')),
          findsOneWidget,
        );
        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsNothing);
      },
    );

    testWidgets(
      'un objetivo de otra revisión tampoco se mezcla con los candidatos',
      (tester) async {
        _FakeIntelligentPurchasingService.overrideCommercialTarget = {
          'needId': 'need-family',
          'needVersion': 1,
          'needSupplyState': 'open',
          'currencyCode': 'CLP',
          'tenantCurrencyCode': 'CLP',
          // El objetivo va una revisión adelante de la que rankeó.
          'targetRevisionNo': 4,
          'target': const {'gama': 'alta'},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('reload-after-conflict')),
          findsOneWidget,
        );
        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsNothing);
      },
    );

    testWidgets(
      'una necesidad cerrada no ofrece además confirmar producto',
      (tester) async {
        _FakeIntelligentPurchasingService.overrideExternalEnvelope = {
          'needId': 'need-family',
          'needVersion': 1,
          'revisionNo': 1,
          'needSupplyState': 'covered',
          'status': 'supply_closed',
          'lane': 'family',
          'items': const [],
          'unverifiedItems': const [],
          'counts': const {},
          'page': const {},
          'unverifiedPage': const {},
          'target': const <String, dynamic>{},
        };
        await mount(
          tester,
          _FamilyLaneService(supplyState: 'covered'),
          needId: 'need-family',
        );
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('external-state-supply_closed')),
          findsOneWidget,
        );
        // Dos afirmaciones que se contradicen en la misma pantalla.
        expect(find.text('Falta confirmar qué producto es'), findsNothing);
      },
    );

    testWidgets(
      'con identidad sin resolver el panel de identidad sigue siendo la salida',
      (tester) async {
        _FakeIntelligentPurchasingService.overrideExternalEnvelope = {
          'needId': 'need-family',
          'needVersion': 1,
          'revisionNo': 1,
          'needSupplyState': 'open',
          'status': 'identity_unresolved',
          'lane': 'family',
          'items': const [],
          'unverifiedItems': const [],
          'counts': const {},
          'page': const {},
          'unverifiedPage': const {},
          'target': const <String, dynamic>{},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('external-state-identity_unresolved')),
          findsOneWidget,
        );
        expect(find.text('Falta confirmar qué producto es'), findsOneWidget);
      },
    );

    testWidgets(
      'ampliar el corte conserva la tabla y el inspector montados',
      (tester) async {
        _FakeIntelligentPurchasingService.unverifiedCandidates = [
          {
            'candidateId': 'candidate-unverified',
            'rank': 1,
            'group': 'unverified',
            'matchState': 'unverified',
            'productId': 'product-u',
            'productName': 'Cadena genérica reforzada',
            'supplierName': 'Andes Industrial',
            'supplierAvailability': 'unverified',
            'evidenceQuality': 'weak',
            'purchaseCount': 2,
            'evidenceAgeDays': 40,
          },
        ];
        // El corte quedó truncado: por eso existe «Continuar análisis».
        _FakeIntelligentPurchasingService.actionablePageHasMore = true;
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(find.text('Kenda Kwick 27,5 × 2,10').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kenda Kwick 27,5 × 2,10').first);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('candidate-inspector')),
          findsOneWidget,
        );

        // La recarga incremental tarda: durante ese rato la pantalla no puede
        // quedar en blanco ni cerrar el inspector abierto.
        _FakeIntelligentPurchasingService.externalDelay =
            const Duration(milliseconds: 400);
        await tester
            .tap(find.byKey(const ValueKey('continue-partial-analysis')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsWidgets);
        expect(
          find.byKey(const ValueKey('candidate-inspector')),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('candidate-inspector')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'si ampliar falla, lo comparado sigue y se ofrece reintentar',
      (tester) async {
        _FakeIntelligentPurchasingService.actionablePageHasMore = true;
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsWidgets);

        _FakeIntelligentPurchasingService.failNextExternal = true;
        await tester
            .tap(find.byKey(const ValueKey('continue-partial-analysis')));
        await tester.pumpAndSettle();

        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsWidgets);
        expect(
          find.byKey(const ValueKey('retry-incremental-load')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'la bodega del carril familia también dice cuánto falta y lo ofrece',
      (tester) async {
        _FakeIntelligentPurchasingService.supplyNeedVersion = 3;
        _FakeIntelligentPurchasingService.supplyRevisionNo = 2;
        _FakeIntelligentPurchasingService.overrideStockResolution = {
          'needId': 'need-family',
          'needVersion': 3,
          'revisionNo': 2,
          'quantity': 2,
          'unit': 'unit',
          'lane': 'family',
          'status': 'ok',
          'coverage': 'partial',
          'blocksExternal': false,
          'items': [
            {
              'productId': 'product-stock',
              'name': 'Cadena X10 en bodega',
              'atp': 1,
              'coverage': 'partial',
              'matchState': 'strong',
              'blocksExternal': false,
            },
          ],
          'counts': const {'eligible': 30, 'partial': 30},
          'page': const {
            'limit': 12,
            'offset': 0,
            'total': 30,
            'returned': 12,
            'hasMore': true,
            'nextOffset': 12,
          },
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Stock interno');

        expect(
          find.textContaining('Mostrando 12 de 30 alternativas en bodega'),
          findsOneWidget,
        );
        _FakeIntelligentPurchasingService.commands.clear();
        await tester.tap(find.byKey(const ValueKey('show-more-family-stock')));
        await tester.pumpAndSettle();

        // Amplía su propia página: el corte externo no se toca.
        expect(
          _FakeIntelligentPurchasingService.commands,
          contains('stock:24'),
        );
        expect(
          _FakeIntelligentPurchasingService.commands,
          contains('external:10:0:5:0'),
        );
      },
    );

    testWidgets(
      'si el objetivo cambia de revisión con el editor abierto, se reconstruye',
      (tester) async {
        // Camino real: el editor queda abierto y una recarga incremental trae
        // un objetivo de otra revisión —alguien lo guardó desde otra parte—.
        // Seguir mostrando lo tecleado sobre la revisión anterior guardaría
        // números que ya no pertenecen a este objetivo.
        _FakeIntelligentPurchasingService.actionablePageHasMore = true;
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-commercial-target')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-commercial-target')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('commercial-target-cost')),
          '55555',
        );
        await tester.pumpAndSettle();
        expect(find.text('55555'), findsOneWidget);

        // La recarga incremental conserva el editor abierto…
        _FakeIntelligentPurchasingService.supplyTargetRevisionNo = 7;
        await tester.tap(
          find.byKey(const ValueKey('continue-partial-analysis')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('commercial-target-editor')),
          findsOneWidget,
        );
        // …y el formulario habla del objetivo nuevo, no del anterior.
        expect(find.text('55555'), findsNothing);
      },
    );

    testWidgets(
      'una necesidad cerrada tampoco ofrece confirmar producto si falla la lectura',
      (tester) async {
        // Sin envelope externo no hay `status` que consultar: la guarda que
        // queda es el estado de la propia necesidad.
        _FakeIntelligentPurchasingService.failNextExternal = true;
        await mount(
          tester,
          _FamilyLaneService(supplyState: 'covered'),
          needId: 'need-family',
        );
        await _goToStep(tester, 'Proveedores');

        expect(find.text('Falta confirmar qué producto es'), findsNothing);
      },
    );

    testWidgets(
      'una lectura inicial fallida se dice, y no concluye nada',
      (tester) async {
        // Un fallo de red no autoriza «no hay compras históricas comparables»
        // ni «falta confirmar qué producto es»: son conclusiones sobre datos
        // que nunca llegaron.
        _FakeIntelligentPurchasingService.failNextExternal = true;
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('decision-load-failed')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('retry-decision-load')),
          findsOneWidget,
        );
        expect(
          find.text('No hay compras históricas comparables'),
          findsNothing,
        );
        expect(find.text('Falta confirmar qué producto es'), findsNothing);

        // Y reintentar recupera la decisión de verdad.
        await tester.tap(find.byKey(const ValueKey('retry-decision-load')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('decision-load-failed')),
          findsNothing,
        );
        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsWidgets);
      },
    );

    testWidgets(
      'un comando fallido en Proveedores se ve junto a la decisión',
      (tester) async {
        final service = _FamilyLaneService(failCommercialTarget: true);
        await mount(tester, service, needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-commercial-target')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-commercial-target')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('commercial-target-cost')),
          '12000',
        );
        await tester.tap(find.byKey(const ValueKey('commercial-target-save')));
        await tester.pumpAndSettle();

        // El mensaje existía y ninguna pantalla lo mostraba: el operador veía
        // la decisión intacta y creía que su acción había pasado.
        expect(
          find.byKey(const ValueKey('decision-recoverable-error')),
          findsOneWidget,
        );
        // Una sola vez, y la decisión sigue disponible debajo.
        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsWidgets);
      },
    );

    testWidgets(
      'reservar stock que falla también se ve en el paso de Stock',
      (tester) async {
        _FakeIntelligentPurchasingService.overrideInventorySnapshot = {
          'need_id': 'need-a',
          'need_version': 1,
          'source_product_id': 'product-a',
          'source_product_name': 'Neumático 27,5',
          'requested_quantity': 2,
          'available_to_promise': 4,
          'assignable': true,
          'components': [
            {
              'product_id': 'product-a',
              'name': 'Neumático 27,5',
              'required_quantity': 2,
              'on_hand': 4,
              'online_committed': 0,
              'workshop_committed': 0,
              'atp': 4,
            },
          ],
        };
        final service = _FakeIntelligentPurchasingService(failAssign: true);
        await mount(tester, service, needId: 'need-a');
        await _goToStep(tester, 'Stock interno');

        final assign = find.text('Usar 2 de bodega');
        await tester.ensureVisible(assign);
        await tester.pumpAndSettle();
        await tester.tap(assign);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('decision-recoverable-error')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'el filtro de compatibilidad usa la ficha, no la factura',
      (tester) async {
        // Señales invertidas a propósito: la evidencia económica dice lo
        // contrario que la técnica en cada fila.
        _FakeIntelligentPurchasingService.overrideCandidates = [
          {
            ..._FakeIntelligentPurchasingService.baseCandidateForTests,
            'candidateId': 'strong-weak-evidence',
            'productName': 'Confirmada por ficha',
            'matchState': 'strong',
            'group': 'actionable',
            'evidenceQuality': 'weak',
          },
          {
            ..._FakeIntelligentPurchasingService.baseCandidateForTests,
            'candidateId': 'weak-complete-evidence',
            'productName': 'Sólo coincide el nombre',
            'matchState': 'weak',
            'group': 'actionable',
            'evidenceQuality': 'complete',
          },
        ];
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(find.text('Confirmada por ficha'), findsWidgets);
        expect(find.text('Sólo coincide el nombre'), findsWidgets);

        // «Sólo compatibilidad confirmada»: pasa lo que la ficha confirma.
        await tester.tap(find.byKey(const ValueKey('provider-view-menu')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
              const ValueKey('provider-view-menu-option-confirmed_only')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Confirmada por ficha'), findsWidgets);
        expect(find.text('Sólo coincide el nombre'), findsNothing);
      },
    );

    testWidgets(
      'la causa de ocultamiento es técnica, no económica',
      (tester) async {
        _FakeIntelligentPurchasingService.overrideCandidates = [
          {
            ..._FakeIntelligentPurchasingService.baseCandidateForTests,
            'candidateId': 'weak-complete-evidence',
            'productName': 'Sólo coincide el nombre',
            'matchState': 'weak',
            'group': 'actionable',
            'evidenceQuality': 'complete',
          },
        ];
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        await tester.tap(find.byKey(const ValueKey('provider-view-menu')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
              const ValueKey('provider-view-menu-option-confirmed_only')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('no-match-surface')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('which-filter-hides-each')));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Sólo coincide el nombre — coincide por el nombre, no por la ficha',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('evidencia débil'), findsNothing);
      },
    );

    testWidgets(
      'un P0001 que la resolución no sustenta es conflicto, no stock-first',
      (tester) async {
        // El servidor cerró el paso externo, pero la bodega que esta pantalla
        // va a mostrar dice que está abierto: son dos momentos distintos.
        _FakeIntelligentPurchasingService.stockFirstRequired = true;
        _FakeIntelligentPurchasingService.overrideStockResolution = {
          'needId': 'need-family',
          'needVersion': 1,
          'revisionNo': 1,
          'quantity': 2,
          'unit': 'unit',
          'lane': 'family',
          'status': 'ok',
          'coverage': 'none',
          'blocksExternal': false,
          'items': const [],
          'counts': const {'eligible': 1},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('stock-first-required')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('reload-after-conflict')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'un fallo inicial genérico muestra UNA banda, no dos',
      (tester) async {
        _FakeIntelligentPurchasingService.failNextExternal = true;
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        // La superficie es dueña del caso; el aviso genérico repetiría el
        // mismo problema en la misma columna.
        expect(
          find.byKey(const ValueKey('decision-load-failed')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('decision-recoverable-error')),
          findsNothing,
        );
        // Y un solo botón de reintento, no dos.
        expect(
          find.byKey(const ValueKey('retry-decision-load')),
          findsOneWidget,
        );
        expect(find.widgetWithText(TextButton, 'Reintentar'), findsNothing);
      },
    );

    testWidgets(
      'un conflicto inicial sin datos no concluye nada sobre el conjunto',
      (tester) async {
        // Coherence mismatch en la primera lectura: hay aviso de recargar,
        // pero ninguna lectura se comprometió.
        _FakeIntelligentPurchasingService.overrideStockResolution = {
          'needId': 'need-family',
          'needVersion': 5,
          'revisionNo': 3,
          'quantity': 2,
          'unit': 'unit',
          'lane': 'family',
          'status': 'ok',
          'coverage': 'none',
          'blocksExternal': false,
          'items': const [],
          'counts': const {'eligible': 1},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');

        expect(
          find.byKey(const ValueKey('reload-after-conflict')),
          findsOneWidget,
        );
        // Ninguna conclusión sobre datos que nunca llegaron…
        expect(
          find.text('No hay compras históricas comparables'),
          findsNothing,
        );
        expect(find.text('Falta confirmar qué producto es'), findsNothing);
        // …y tampoco la superficie de fallo genérico: este caso ya tiene dueño.
        expect(
          find.byKey(const ValueKey('decision-load-failed')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'ese mismo conflicto conserva «Recargar» también en el paso de Stock',
      (tester) async {
        _FakeIntelligentPurchasingService.overrideStockResolution = {
          'needId': 'need-family',
          'needVersion': 5,
          'revisionNo': 3,
          'quantity': 2,
          'unit': 'unit',
          'lane': 'family',
          'status': 'ok',
          'coverage': 'none',
          'blocksExternal': false,
          'items': const [],
          'counts': const {'eligible': 1},
        };
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Stock interno');

        expect(
          find.byKey(const ValueKey('reload-after-conflict')),
          findsOneWidget,
        );
        // El genérico culpaba a la bodega de un fallo que no era suyo y pisaba
        // la única acción correcta.
        expect(
          find.text('No fue posible verificar el stock interno'),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('decision-load-failed')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'un fallo inicial genérico en Stock también tiene un solo dueño',
      (tester) async {
        _FakeIntelligentPurchasingService.failNextExternal = true;
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Stock interno');

        expect(
          find.byKey(const ValueKey('decision-load-failed')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('decision-recoverable-error')),
          findsNothing,
        );
        expect(
          find.text('No fue posible verificar el stock interno'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'un conflicto incremental conserva los resultados ya comparados',
      (tester) async {
        _FakeIntelligentPurchasingService.actionablePageHasMore = true;
        await mount(tester, _FamilyLaneService(), needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsWidgets);

        // La ampliación choca con una escritura ajena: hay conflicto, pero lo
        // ya comparado sigue siendo cierto y no desaparece.
        _FakeIntelligentPurchasingService.supplyNeedVersion = 9;
        await tester.tap(
          find.byKey(const ValueKey('continue-partial-analysis')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('reload-after-conflict')),
          findsOneWidget,
        );
        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsWidgets);
        expect(
          find.byKey(const ValueKey('decision-load-failed')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'un comando fallido conserva la decisión y no inventa una lectura rota',
      (tester) async {
        final service = _FamilyLaneService(failCommercialTarget: true);
        await mount(tester, service, needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(
          find.byKey(const ValueKey('edit-commercial-target')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('edit-commercial-target')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('commercial-target-cost')),
          '12000',
        );
        await tester.tap(find.byKey(const ValueKey('commercial-target-save')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('decision-recoverable-error')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('decision-load-failed')),
          findsNothing,
        );
        expect(find.text('Kenda Kwick 27,5 × 2,10'), findsWidgets);
      },
    );

    testWidgets(
      'en familia se elige producto, se relee, y recién después se agrega',
      (tester) async {
        final service = _FamilyLaneService();
        await mount(tester, service, needId: 'need-family');
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(find.text('Kenda Kwick 27,5 × 2,10').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kenda Kwick 27,5 × 2,10').first);
        await tester.pumpAndSettle();

        // Primera acción: fijar la identidad. «Agregar al plan» todavía no
        // existe, porque el plan exige un producto confirmado.
        expect(
          find.byKey(const ValueKey('choose-family-product')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('add-candidate-to-plan')),
          findsNothing,
        );

        final reloadsBefore = service.reloadCount;
        await tester.tap(find.byKey(const ValueKey('choose-family-product')));
        await tester.pumpAndSettle();

        // Confirmó con la revisión vigente y volvió a leer.
        expect(
          _FakeIntelligentPurchasingService.commands,
          contains('confirm:need-family:product-a:1'),
        );
        expect(service.reloadCount, greaterThan(reloadsBefore));
        // Y no agregó nada al plan por su cuenta.
        expect(
          _FakeIntelligentPurchasingService.commands
              .where((entry) => entry.startsWith('plan:')),
          isEmpty,
        );

        // Segunda acción, explícita, ya con la identidad fijada.
        await _goToStep(tester, 'Proveedores');
        await tester.ensureVisible(find.text('Kenda Kwick 27,5 × 2,10').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kenda Kwick 27,5 × 2,10').first);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('add-candidate-to-plan')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('choose-family-product')),
          findsNothing,
        );
      },
    );
  });
}

class _NeverGatewayTransport implements AIAgentGatewayTransport {
  @override
  Future<Object?> send(
    Map<String, Object?> body, {
    required Future<void> abortTrigger,
  }) {
    throw StateError(
        'The responsive render test must not call the AI gateway.');
  }
}

class _TerminalFailureGatewayTransport implements AIAgentGatewayTransport {
  final List<String> requestIds = <String>[];

  @override
  Future<Object?> send(
    Map<String, Object?> body, {
    required Future<void> abortTrigger,
  }) {
    requestIds.add(body['clientRequestId']! as String);
    throw const AIAgentGatewayException(
      code: 'agent_budget_exhausted',
      statusCode: 409,
    );
  }
}

class _ActionCardGatewayTransport implements AIAgentGatewayTransport {
  @override
  Future<Object?> send(
    Map<String, Object?> body, {
    required Future<void> abortTrigger,
  }) async {
    return <String, Object?>{
      'version': 1,
      'threadId': '11111111-1111-4111-8111-111111111111',
      'runId': '22222222-2222-4222-8222-222222222222',
      'text': 'Hay una coincidencia exacta en stock.',
      'cards': <Object?>[
        <String, Object?>{
          'kind': 'inventory',
          'title': '1 resultado',
          'subtitle': 'Pedal ENLEE CR-2',
          'destination': 'inventory_products',
          'chips': <String>['En stock', 'Top 5'],
          'listRef': <String, Object?>{
            'kind': 'inventory',
            'query': 'Pedal ENLEE CR-2',
            'availability': 'in_stock',
            'resultCount': 1,
            'hasMore': false,
            'entityIds': <String>[
              '33333333-3333-4333-8333-333333333333',
            ],
            'autoOpen': false,
          },
        },
      ],
      'status': 'completed',
    };
  }
}

class _SupplyDraftGatewayTransport implements AIAgentGatewayTransport {
  Map<String, Object?>? lastBody;

  @override
  Future<Object?> send(
    Map<String, Object?> body, {
    required Future<void> abortTrigger,
  }) async {
    lastBody = body;
    return <String, Object?>{
      'version': 1,
      'threadId': '11111111-1111-4111-8111-111111111111',
      'runId': '22222222-2222-4222-8222-222222222222',
      'text': 'Separé la petición en dos necesidades para que la revises.',
      'cards': <Object?>[
        <String, Object?>{
          'kind': 'supply_need_draft',
          'title': '2 necesidades para revisar',
          'destination': 'purchases',
          'chips': <String>['Equilibrio', '1 por precisar'],
          'supplyNeedDraft': <String, Object?>{
            'profile': 'balanced',
            'lines': <Object?>[
              <String, Object?>{
                'lineRef': 'line-1',
                'description': 'Neumáticos 27,5',
                'productId': '33333333-3333-4333-8333-333333333333',
                'productName': 'Kenda Kwick 27,5 × 2,10',
                'productSku': 'KEN-275-210',
                'identityState': 'confirmed',
                'categoryId': null,
                'categoryPath': null,
                'technicalFamily': null,
                'quantity': 2,
                'unit': 'unit',
                'technicalPredicates': <Object?>[],
                'preference': 'gama económica',
                'clarification': null,
                'clarificationRequired': false,
              },
              <String, Object?>{
                'lineRef': 'line-2',
                'description': 'Rayos 27,5',
                'productId': null,
                'productName': null,
                'productSku': null,
                'identityState': 'unresolved',
                'categoryId': null,
                'categoryPath': null,
                'technicalFamily': null,
                'quantity': 1,
                'unit': 'set',
                'technicalPredicates': <Object?>[],
                'preference': null,
                'clarification':
                    '¿Te refieres a rayos de medida 27,5 o para rueda 27,5?',
                'clarificationRequired': true,
              },
            ],
          },
        },
      ],
      'status': 'completed',
    };
  }
}

/// Transporte con aclaración progresiva tipada.
///
/// Turno 0 devuelve una línea que bloquea con dos prompts (elección con
/// «No lo sé» y número con unidad). Los turnos siguientes resuelven, salvo que
/// `alwaysBlocking` mantenga la pregunta para ejercitar el tope de rondas.
class _ClarificationGatewayTransport implements AIAgentGatewayTransport {
  _ClarificationGatewayTransport({
    this.alwaysBlocking = false,
    this.prose,
    this.consecutiveInputs = false,
  });

  final bool alwaysBlocking;
  final String? prose;

  /// Dos prompts de entrada seguidos: el caso donde un controlador compartido
  /// filtraba el texto de uno al siguiente.
  final bool consecutiveInputs;

  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
  int failures = 0;

  /// Retiene la respuesta para poder observar el estado en vuelo: sin esto el
  /// transporte resuelve en el mismo microtask y «Enviando…» nunca se ve.
  Completer<void>? gate;

  Map<String, Object?>? get lastBody => bodies.isEmpty ? null : bodies.last;

  Map<String, Object?> _line({
    required bool blocking,
  }) =>
      <String, Object?>{
        'lineRef': 'line-1',
        'description': 'Rayos',
        'productId': blocking ? null : '44444444-4444-4444-8444-444444444444',
        'productName': blocking ? null : 'Rayo 274 mm negro',
        'productSku': blocking ? null : 'RAY-274',
        'identityState': blocking ? 'unresolved' : 'confirmed',
        'categoryId': null,
        'categoryPath': null,
        'technicalFamily': null,
        'quantity': 36,
        'unit': 'unit',
        'technicalPredicates': <Object?>[],
        'preference': null,
        'clarification':
            blocking ? 'Falta el aro para calcular el largo.' : null,
        'clarificationRequired': blocking,
        if (blocking && consecutiveInputs)
          'clarificationPrompts': <Object?>[
            <String, Object?>{
              'id': 'erd',
              'question': '¿Cuál es el ERD del aro?',
              'inputKind': 'number',
              'options': <Object?>[],
              'unit': 'mm',
              'allowUnknown': false,
            },
            <String, Object?>{
              'id': 'hub_note',
              'question': '¿Alguna nota sobre la maza?',
              'inputKind': 'text',
              'options': <Object?>[],
              'unit': null,
              'allowUnknown': false,
            },
          ]
        else if (blocking)
          'clarificationPrompts': <Object?>[
            <String, Object?>{
              'id': 'rim_kind',
              'question': '¿Para qué aro son?',
              'inputKind': 'single_choice',
              'options': <Object?>[
                <String, Object?>{'value': 'r27_5', 'label': 'Aro 27,5'},
                <String, Object?>{'value': 'r29', 'label': 'Aro 29'},
              ],
              'unit': null,
              'allowUnknown': true,
            },
            <String, Object?>{
              'id': 'erd',
              'question': '¿Cuál es el ERD del aro?',
              'inputKind': 'number',
              'options': <Object?>[],
              'unit': 'mm',
              'allowUnknown': false,
            },
          ],
      };

  @override
  Future<Object?> send(
    Map<String, Object?> body, {
    required Future<void> abortTrigger,
  }) async {
    bodies.add(body);
    final pending = gate;
    if (pending != null) await pending.future;
    if (failures > 0) {
      failures -= 1;
      throw StateError('transport down');
    }
    final blocking = alwaysBlocking || bodies.length == 1;
    return <String, Object?>{
      'version': 1,
      'threadId': '11111111-1111-4111-8111-111111111111',
      'runId': '22222222-2222-4222-8222-222222222222',
      'text': prose ?? 'Listo.',
      'cards': <Object?>[
        <String, Object?>{
          'kind': 'supply_need_draft',
          'title': '1 necesidad para revisar',
          'destination': 'purchases',
          'chips': <String>['Equilibrio'],
          'supplyNeedDraft': <String, Object?>{
            'profile': 'balanced',
            'lines': <Object?>[_line(blocking: blocking)],
          },
        },
      ],
      'status': 'completed',
    };
  }
}

/// Línea que **no** bloquea pero trae una limitación del ERP.
class _CoverageNoticeGatewayTransport implements AIAgentGatewayTransport {
  @override
  Future<Object?> send(
    Map<String, Object?> body, {
    required Future<void> abortTrigger,
  }) async =>
      <String, Object?>{
        'version': 1,
        'threadId': '11111111-1111-4111-8111-111111111111',
        'runId': '22222222-2222-4222-8222-222222222222',
        'text': 'Listo.',
        'cards': <Object?>[
          <String, Object?>{
            'kind': 'supply_need_draft',
            'title': '1 necesidad para revisar',
            'destination': 'purchases',
            'chips': <String>['Equilibrio'],
            'supplyNeedDraft': <String, Object?>{
              'profile': 'balanced',
              'lines': <Object?>[
                <String, Object?>{
                  'lineRef': 'line-1',
                  'description': 'Rayos negros 274 mm',
                  'productId': '44444444-4444-4444-8444-444444444444',
                  'productName': 'Rayo 274 mm',
                  'productSku': 'RAY-274',
                  'identityState': 'confirmed',
                  'categoryId': null,
                  'categoryPath': null,
                  'technicalFamily': null,
                  'quantity': 36,
                  'unit': 'unit',
                  'technicalPredicates': <Object?>[],
                  'preference': null,
                  'clarification':
                      'El catálogo no guarda largo ni color como campos: se comparará por descripción.',
                  'clarificationRequired': false,
                },
              ],
            },
          },
        ],
        'status': 'completed',
      };
}

class _FakeIntelligentPurchasingService extends IntelligentPurchasingService {
  _FakeIntelligentPurchasingService({
    this.failAssign = false,
    this.failCommercialTarget = false,
  }) : super();

  static final need = SupplyNeed.fromJson({
    'id': 'need-a',
    'origin_kind': 'mechanic_job',
    'mechanic_job_id': 'job-a',
    'original_description': 'neumático económico 27,5 ancho mayor a 2,0',
    'product_id': 'product-a',
    'product_name': 'Neumático 27,5',
    'quantity': 2,
    'unit': 'unit',
    'identity_state': 'confirmed',
    'supply_state': 'open',
    'version': 1,
    'created_at': '2026-08-16T12:00:00Z',
  });

  static final secondNeed = SupplyNeed.fromJson({
    'id': 'need-b',
    'origin_kind': 'ad_hoc',
    'original_description': 'piñón 9 velocidades',
    'product_id': 'product-b',
    'product_name': 'Piñón 9 velocidades',
    'quantity': 1,
    'unit': 'unit',
    'identity_state': 'confirmed',
    'supply_state': 'open',
    'version': 1,
    'created_at': '2026-08-16T12:01:00Z',
  });

  @override
  Future<List<SupplyNeed>> fetchOpenNeeds({String? mechanicJobId}) async =>
      [need, secondNeed];

  @override
  Future<SupplyNeed?> fetchNeed(String needId) async => need;

  @override
  Future<SupplyInventorySnapshot> inventorySnapshot(String needId) async =>
      SupplyInventorySnapshot.fromJson(
        overrideInventorySnapshot ??
            {
              'need_id': needId,
              'need_version': 1,
              'source_product_id': 'product-a',
              'source_product_name': 'Neumático 27,5',
              'requested_quantity': 2,
              'available_to_promise': 0,
              'assignable': false,
              'components': const [],
            },
      );

  @override
  Future<SupplyNeed> assignFromStock(SupplyNeed need) async {
    if (failAssign) throw StateError('assign failed');
    return need;
  }

  @override
  Future<void> setCommercialTarget({
    required SupplyCommercialTarget current,
    required Map<String, Object?>? values,
  }) async {
    if (failCommercialTarget) throw StateError('target save failed');
    commands.add(
      'target:${current.needId}:${current.targetRevisionNo}:'
      '${values?['gama']}:${values?['maxLandedUnitCostNet']}:'
      '${values?['minGrossMarginRatio']}',
    );
  }

  /// Candidatos extra que un caso concreto quiera inyectar (sin evaluar,
  /// evidencia débil…). Por omisión la lista es la de siempre.
  static List<Map<String, dynamic>> extraCandidates = [];

  /// Reemplaza por completo la lista. Sirve para el caso en que **ningún**
  /// candidato tiene evidencia suficiente y el filtro puede esconderlos todos.
  static List<Map<String, dynamic>>? overrideCandidates;

  /// Último límite con el que se pidió el ranking: prueba que «Continuar
  /// análisis» relanza de verdad con el corte ampliado.
  static int lastRankLimit = 0;

  /// El candidato base, visible para los casos que lo extienden.
  static Map<String, dynamic> get baseCandidateForTests => _baseCandidate;

  static Map<String, dynamic> get _baseCandidate => {
        'candidateId': 'candidate-a',
        'rank': 1,
        'productId': 'product-a',
        'productName': 'Kenda Kwick 27,5 × 2,10',
        'brand': 'Kenda',
        'supplierName': 'Andes Industrial',
        'supplierAvailability': 'unverified',
        'latestLandedUnitCostNet': 10100,
        'projectedGrossMarginRatio': 0.541,
        'purchaseCount': 12,
        'evidenceAgeDays': 18,
        'evidenceQuality': 'complete',
        'freightEvidence': 'complete',
      };

  @override
  Future<PurchaseRanking> rankCandidates({
    String? query,
    String? productId,
    String? categoryId,
    String profile = 'balanced',
    int limit = 10,
    String? gama,
  }) async {
    lastRankLimit = limit;
    return PurchaseRanking.fromJson({
      'status': 'success',
      'hasMore': false,
      'supplierAvailabilitySemantics': 'historical_only_unverified',
      'items': overrideCandidates ??
          [
            _baseCandidate,
            ...extraCandidates,
          ],
    });
  }

  /// Estado del carril que el caso quiera simular. Por omisión: carril
  /// exacto, sin stock que bloquee, así que el paso externo está abierto.
  static Map<String, dynamic>? overrideStockResolution;

  /// Envelope externo completo cuando el caso prueba un estado que no es
  /// `success` (conflicto técnico, fanout, sin historial…).
  static Map<String, dynamic>? overrideExternalEnvelope;

  /// Grupo sin verificar. Va en su propia lista y su propia página.
  static List<Map<String, dynamic>> unverifiedCandidates = [];

  /// El servidor cerró el paso externo hasta decidir el stock.
  static bool stockFirstRequired = false;

  /// Objetivo comercial vigente que devuelve la lectura.
  static Map<String, dynamic>? overrideCommercialTarget;

  /// Comandos observados, para afirmar la secuencia elegir → releer → agregar.
  static final List<String> commands = <String>[];

  /// **Un solo origen de la versión, la revisión y el estado**, igual que el
  /// servidor. Los tres envelopes salen de acá, así que una prueba no puede
  /// montar por descuido un stock de una versión con candidatos de otra: si
  /// quiere probar ese desacuerdo, lo declara explícitamente.
  static int supplyNeedVersion = 1;
  static int supplyRevisionNo = 1;
  static int supplyTargetRevisionNo = 0;
  static String supplyNeedState = 'open';
  static String supplyLane = 'exact';

  /// Retardo artificial de la lectura externa: sirve para mirar la pantalla
  /// **mientras** una recarga incremental está en vuelo.
  static Duration externalDelay = Duration.zero;

  /// La próxima lectura externa falla una vez.
  static bool failNextExternal = false;

  /// El corte accionable quedó truncado: es lo que hace aparecer «Continuar
  /// análisis», que es el control de recarga incremental del grupo principal.
  static bool actionablePageHasMore = false;

  /// Snapshot del carril exacto, cuando un caso necesita bodega asignable.
  static Map<String, dynamic>? overrideInventorySnapshot;

  /// Comandos que fallan, para comprobar que su error se ve.
  final bool failAssign;
  final bool failCommercialTarget;

  static void resetSupplyState() {
    overrideStockResolution = null;
    overrideExternalEnvelope = null;
    overrideCommercialTarget = null;
    overrideCandidates = null;
    extraCandidates = [];
    unverifiedCandidates = [];
    stockFirstRequired = false;
    supplyNeedVersion = 1;
    supplyRevisionNo = 1;
    supplyTargetRevisionNo = 0;
    supplyNeedState = 'open';
    supplyLane = 'exact';
    externalDelay = Duration.zero;
    failNextExternal = false;
    actionablePageHasMore = false;
    overrideInventorySnapshot = null;
    commands.clear();
  }

  @override
  Future<SupplyStockResolution> stockResolution(
    String needId, {
    int limit = 12,
    int offset = 0,
  }) async {
    commands.add('stock:$limit');
    return SupplyStockResolution.fromJson(
      overrideStockResolution ??
          <String, dynamic>{
            'needId': needId,
            'needVersion': supplyNeedVersion,
            'revisionNo': supplyRevisionNo,
            'quantity': 2,
            'unit': 'unit',
            'lane': supplyLane,
            'status': 'ok',
            'coverage': 'none',
            'blocksExternal': false,
            'items': const [],
            'counts': const {'eligible': 1},
            'page': {
              'limit': limit,
              'offset': offset,
              'total': 0,
              'returned': 0,
              'hasMore': false,
            },
          },
    );
  }

  @override
  Future<SupplyCommercialTarget> commercialTarget(String needId) async {
    return SupplyCommercialTarget.fromJson(
      overrideCommercialTarget ??
          <String, dynamic>{
            'needId': needId,
            'needVersion': supplyNeedVersion,
            'needSupplyState': supplyNeedState,
            'currencyCode': 'CLP',
            'tenantCurrencyCode': 'CLP',
            'targetRevisionNo': supplyTargetRevisionNo,
            'target': const <String, dynamic>{},
          },
    );
  }

  @override
  Future<SupplyExternalCandidates> externalCandidates(
    String needId, {
    int limit = 10,
    int offset = 0,
    int unverifiedLimit = 5,
    int unverifiedOffset = 0,
  }) async {
    lastRankLimit = limit;
    commands.add('external:$limit:$offset:$unverifiedLimit:$unverifiedOffset');
    if (externalDelay > Duration.zero) {
      await Future<void>.delayed(externalDelay);
    }
    if (failNextExternal) {
      failNextExternal = false;
      throw StateError('external read failed');
    }
    if (stockFirstRequired) throw SupplyStockFirstRequired(needId);
    if (overrideExternalEnvelope != null) {
      return SupplyExternalCandidates.fromJson(overrideExternalEnvelope!);
    }
    final actionable =
        overrideCandidates ?? [_baseCandidate, ...extraCandidates];
    return SupplyExternalCandidates.fromJson(<String, dynamic>{
      'needId': needId,
      'needVersion': supplyNeedVersion,
      'revisionNo': supplyRevisionNo,
      'needSupplyState': supplyNeedState,
      'quantity': 2,
      'unit': 'unit',
      'status': 'success',
      'lane': supplyLane,
      'rankingProfile': 'balanced',
      'rankingProfileSource': 'revision',
      'items': actionable,
      'unverifiedItems': unverifiedCandidates,
      'counts': {
        'candidates': actionable.length + unverifiedCandidates.length,
        'actionable': actionable.length,
        'unverified': unverifiedCandidates.length,
      },
      'page': {
        'limit': limit,
        'offset': offset,
        'total': actionable.length + (actionablePageHasMore ? 5 : 0),
        'returned': actionable.length,
        'hasMore': actionablePageHasMore,
      },
      'unverifiedPage': {
        'limit': unverifiedLimit,
        'offset': unverifiedOffset,
        'total': unverifiedCandidates.length,
        'returned': unverifiedCandidates.length,
        'hasMore': false,
      },
      'targetRevisionNo': supplyTargetRevisionNo,
      'target': const <String, dynamic>{},
      'targetCurrencyCode': 'CLP',
      'tenantCurrencyCode': 'CLP',
      'supplierAvailabilitySemantics': 'historical_only_unverified',
    });
  }

  @override
  Future<void> rejectInternalStockForLane({
    required SupplyStockResolution resolution,
    required String reason,
  }) async {
    commands.add('reject:${resolution.needId}:${resolution.revisionNo}');
    stockFirstRequired = false;
  }

  @override
  Future<void> confirmFamilyChoice({
    required String needId,
    required int expectedVersion,
    required int expectedRevisionNo,
    required String productId,
  }) async {
    commands.add('confirm:$needId:$productId:$expectedRevisionNo');
  }

  @override
  Future<PurchaseScenarioResult> buildScenarios({
    required List<SupplyNeed> needs,
    String profile = 'balanced',
    int maxSuppliers = 2,
    int limit = 3,
  }) async =>
      PurchaseScenarioResult.fromJson({
        'status': 'success',
        'profile': profile,
        'inputCount': 2,
        'internalLineCount': 1,
        'externalLineCount': 1,
        'boundedSupplierCount': 1,
        'hasMore': false,
        'supplierAvailabilitySemantics': 'historical_only_unverified',
        'scenarios': [
          {
            'scenarioKey': 'recommended:test',
            'kind': 'recommended',
            'label': 'Mejor equilibrio',
            'coverageLineCount': 2,
            'externalCoverageLineCount': 1,
            'totalLineCount': 2,
            'externalLineCount': 1,
            'complete': true,
            'supplierCount': 1,
            'historicalSubtotals': [
              {
                'currency': 'CLP',
                'historicalLandedSubtotalNet': 10100,
              },
            ],
            'supplierAvailability': 'historical_only_unverified',
            'freightAssumption':
                'sum_historical_landed_line_costs_no_consolidation_saving',
            'lines': [
              {
                'lineRef': 'need-a',
                'productId': 'product-a',
                'productName': 'Neumático 27,5',
                'requestedQuantity': 2,
                'availableToPromise': 2,
                'sourcing': 'internal',
                'covered': true,
              },
              {
                'lineRef': 'need-b',
                'productId': 'product-b',
                'productName': 'Piñón 9 velocidades',
                'requestedQuantity': 1,
                'availableToPromise': 0,
                'sourcing': 'external',
                'covered': true,
                'candidateId': 'candidate-b',
                'supplierId': 'supplier-a',
                'supplierName': 'Andes Industrial',
                'supplierAvailability': 'unverified',
                'currency': 'CLP',
                'latestLandedUnitCostNet': 10100,
                'projectedGrossMarginRatio': 0.541,
                'purchaseCount': 12,
                'evidenceAgeDays': 18,
                'evidenceQuality': 'complete',
                'freightEvidence': 'complete',
              },
            ],
            'explanationCodes': [
              'stock_first',
              'complete_external_coverage',
            ],
          },
        ],
      });

  @override
  Future<PurchasePlanDraft> prepareScenario({
    required PurchaseScenario scenario,
    required Iterable<SupplyNeed> needs,
    required String profile,
    PurchasePlanDraft? plan,
  }) async {
    return PurchasePlanDraft(
      id: 'plan-basket',
      title: 'Plan de compra 2026-08-16',
      state: 'draft',
      objectiveProfile: profile,
      version: 2,
      lines: const [
        PurchasePlanLine(
          id: 'line-b',
          sourceNeedId: 'need-b',
          candidateId: 'candidate-b',
          productId: 'product-b',
          productName: 'Piñón 9 velocidades',
          supplierName: 'Andes Industrial',
          quantity: 1,
          unit: 'unit',
          currency: 'CLP',
          landedUnitCostNet: 10100,
          projectedGrossMarginRatio: 0.541,
          supplierAvailability: 'unverified',
        ),
      ],
      supplierGroups: const [
        PurchasePlanSupplierGroup(
          supplierId: 'supplier-a',
          supplierName: 'Andes Industrial',
          currency: 'CLP',
          lineCount: 1,
          totalUnits: 1,
          historicalLandedSubtotalNet: 10100,
          supplierAvailability: 'unverified',
          freightAssumption:
              'sum_frozen_line_landed_costs_no_consolidation_saving',
        ),
      ],
    );
  }

  @override
  Future<PurchasePlanDraft> preparePlanLine({
    required SupplyNeed need,
    required PurchaseCandidate candidate,
    required String profile,
    PurchasePlanDraft? plan,
  }) async {
    return PurchasePlanDraft(
      id: 'plan-a',
      title: 'Plan de compra 2026-08-16',
      state: 'draft',
      objectiveProfile: profile,
      version: 1,
      lines: [
        PurchasePlanLine(
          id: 'line-a',
          sourceNeedId: need.id,
          candidateId: candidate.candidateId,
          productId: candidate.productId,
          productName: candidate.productName,
          supplierName: candidate.supplierName,
          quantity: need.quantity,
          unit: need.unit,
          currency: candidate.currency,
          landedUnitCostNet: candidate.latestLandedUnitCostNet,
          projectedGrossMarginRatio: candidate.projectedGrossMarginRatio,
          supplierAvailability: 'unverified',
        ),
      ],
      supplierGroups: const [
        PurchasePlanSupplierGroup(
          supplierId: 'supplier-a',
          supplierName: 'Andes Industrial',
          currency: 'CLP',
          lineCount: 1,
          totalUnits: 2,
          historicalLandedSubtotalNet: 20200,
          supplierAvailability: 'unverified',
          freightAssumption:
              'sum_frozen_line_landed_costs_no_consolidation_saving',
        ),
      ],
    );
  }

  @override
  Future<PurchasePlanDraft> removePlanLine({
    required PurchasePlanDraft plan,
    required PurchasePlanLine line,
  }) async {
    return PurchasePlanDraft(
      id: plan.id,
      title: plan.title,
      state: plan.state,
      objectiveProfile: plan.objectiveProfile,
      version: plan.version + 1,
      lines: const [],
      supplierGroups: const [],
    );
  }

  @override
  Future<PurchasePlanDraft> updatePlanLineQuantity({
    required PurchasePlanDraft plan,
    required PurchasePlanLine line,
    required double quantity,
  }) async {
    return PurchasePlanDraft(
      id: plan.id,
      title: plan.title,
      state: plan.state,
      objectiveProfile: plan.objectiveProfile,
      version: plan.version + 1,
      lines: [
        PurchasePlanLine(
          id: line.id,
          sourceNeedId: line.sourceNeedId,
          candidateId: line.candidateId,
          productId: line.productId,
          productName: line.productName,
          supplierName: line.supplierName,
          quantity: quantity,
          unit: line.unit,
          currency: line.currency,
          landedUnitCostNet: line.landedUnitCostNet,
          projectedGrossMarginRatio: line.projectedGrossMarginRatio,
          supplierAvailability: line.supplierAvailability,
        ),
      ],
      supplierGroups: [
        PurchasePlanSupplierGroup(
          supplierId: 'supplier-a',
          supplierName: line.supplierName,
          currency: line.currency,
          lineCount: 1,
          totalUnits: quantity,
          historicalLandedSubtotalNet: line.landedUnitCostNet == null
              ? null
              : line.landedUnitCostNet! * quantity,
          supplierAvailability: 'unverified',
          freightAssumption:
              'sum_frozen_line_landed_costs_no_consolidation_saving',
        ),
      ],
    );
  }
}

/// Carril familia: la necesidad no tiene producto confirmado, y sólo lo fija
/// `confirm_supply_need_family_choice_v1`.
class _FamilyLaneService extends _FakeIntelligentPurchasingService {
  _FamilyLaneService({
    this.supplyState = 'open',
    super.failCommercialTarget,
  }) {
    _FakeIntelligentPurchasingService.supplyLane = 'family';
    _FakeIntelligentPurchasingService.supplyNeedState = supplyState;
  }

  /// Estado de la necesidad. Una cubierta o cancelada sigue siendo legible: es
  /// la lectura externa la que dice que no corresponde comprar.
  final String supplyState;

  bool confirmed = false;
  int reloadCount = 0;

  SupplyNeed get _need => SupplyNeed.fromJson({
        'id': 'need-family',
        'origin_kind': 'ad_hoc',
        'original_description': 'cadena de 10 velocidades',
        'product_id': confirmed ? 'product-fam' : null,
        'product_name': confirmed ? 'Cadena X10 Pro' : null,
        'quantity': 2,
        'unit': 'unit',
        'identity_state': confirmed ? 'confirmed' : 'unresolved',
        'supply_state': supplyState,
        // La versión sale del mismo sitio que los tres envelopes: el servidor
        // no tiene dos verdades y el doble tampoco.
        'version': _FakeIntelligentPurchasingService.supplyNeedVersion,
        'created_at': '2026-08-17T12:00:00Z',
      });

  @override
  Future<List<SupplyNeed>> fetchOpenNeeds({String? mechanicJobId}) async {
    reloadCount += 1;
    return [_need];
  }

  @override
  Future<SupplyNeed?> fetchNeed(String needId) async => _need;

  @override
  Future<void> confirmFamilyChoice({
    required String needId,
    required int expectedVersion,
    required int expectedRevisionNo,
    required String productId,
  }) async {
    _FakeIntelligentPurchasingService.commands
        .add('confirm:$needId:$productId:$expectedRevisionNo');
    confirmed = true;
    // Converger sube versión y revisión, y cambia de carril: los tres
    // envelopes siguientes tienen que decir lo mismo.
    _FakeIntelligentPurchasingService.supplyNeedVersion += 1;
    _FakeIntelligentPurchasingService.supplyRevisionNo += 1;
    _FakeIntelligentPurchasingService.supplyLane = 'exact';
  }

  @override
  Future<PurchasePlanDraft> preparePlanLine({
    required SupplyNeed need,
    required PurchaseCandidate candidate,
    required String profile,
    PurchasePlanDraft? plan,
  }) async {
    _FakeIntelligentPurchasingService.commands
        .add('plan:${need.id}:${candidate.candidateId}');
    return super.preparePlanLine(
      need: need,
      candidate: candidate,
      profile: profile,
      plan: plan,
    );
  }
}

class _BatchIntelligentPurchasingService
    extends _FakeIntelligentPurchasingService {
  AIAssistantSupplyNeedDraft? savedDraft;
  final List<String> operationKeys = <String>[];
  List<SupplyNeed> createdNeeds = const <SupplyNeed>[];

  @override
  Future<List<SupplyNeed>> createNeedBatch({
    required String originalRequest,
    required AIAssistantSupplyNeedDraft draft,
    required String operationKey,
    String? assistantThreadId,
  }) async {
    savedDraft = draft;
    operationKeys.add(operationKey);
    createdNeeds = <SupplyNeed>[
      for (var index = 0; index < draft.lines.length; index++)
        SupplyNeed.fromJson(<String, Object?>{
          'id': 'batch-need-$index',
          'origin_kind': 'ad_hoc',
          'original_description': draft.lines[index].description,
          'product_id': draft.lines[index].productId,
          'product_name': draft.lines[index].productName,
          'quantity': draft.lines[index].quantity,
          'unit': draft.lines[index].unit,
          'identity_state': draft.lines[index].identityState,
          'supply_state': 'open',
          'version': 1,
          'created_at': '2026-08-16T12:02:00Z',
        }),
    ];
    return createdNeeds;
  }

  @override
  Future<List<SupplyNeed>> fetchOpenNeeds({String? mechanicJobId}) async =>
      <SupplyNeed>[
        ...createdNeeds,
        _FakeIntelligentPurchasingService.need,
        _FakeIntelligentPurchasingService.secondNeed,
      ];

  @override
  Future<SupplyNeed?> fetchNeed(String needId) async {
    final created = _firstNeedOrNull(createdNeeds, needId);
    if (created != null) return created;
    return super.fetchNeed(needId);
  }
}

SupplyNeed? _firstNeedOrNull(List<SupplyNeed> needs, String id) {
  for (final need in needs) {
    if (need.id == id) return need;
  }
  return null;
}
