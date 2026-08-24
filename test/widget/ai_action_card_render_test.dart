import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_destination.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_session_state.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_context_service.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_session_service.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_turn_engine.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/ai_assistant/widgets/ai_chat_bubble.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/crm/services/customer_service.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/modules/sales/services/sales_service.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

import '../support/ai_assistant_session_harness.dart';

/// Renders the real cards and measures the real colours.
///
/// The accent hues were chosen against a white card. `job` is `#6D4C41`, which
/// on the dark surface is roughly 1.8:1 — so as long as the eyebrow, the CTA,
/// the icon and the arrow were painted with it, the dark card was unreadable
/// no matter how correct the background became.
class _CardsEngine extends AIAssistantService
    implements AIAssistantApprovalTurnEngine {
  _CardsEngine(
    this.response, {
    this.approvalResolution,
    this.approvalCompleter,
  });

  final AIAssistantResponse response;
  final AIAssistantApprovalResolution? approvalResolution;
  final Completer<AIAssistantApprovalResolution>? approvalCompleter;
  final List<AIAssistantApprovalDecision> approvalDecisions =
      <AIAssistantApprovalDecision>[];

  @override
  Future<AIAssistantResponse> sendMessage(
    String message, {
    List<MechanicJob>? jobs,
    CustomerService? customerService,
    InventoryService? inventoryService,
    BikeshopService? bikeshopService,
    bool jobsAreCurrentView = false,
    String? jobSummaryScopeLabel,
    PurchaseService? purchaseService,
    SalesService? salesService,
    bool allowJobCacheFallback = true,
    bool visibleJobsSourceUnavailable = false,
    TaskService? taskService,
    required AIAssistantTurnAuthority authority,
  }) async =>
      response;

  @override
  Future<AIAssistantApprovalResolution> resolveApproval(
    AIAssistantApprovalRef approval,
    AIAssistantApprovalDecision decision, {
    required AIAssistantTurnAuthority authority,
  }) {
    approvalDecisions.add(decision);
    final pending = approvalCompleter;
    if (pending != null) return pending.future;
    final result = approvalResolution;
    if (result == null) {
      return Future<AIAssistantApprovalResolution>.error(
        StateError('No approval result configured'),
      );
    }
    return Future<AIAssistantApprovalResolution>.value(result);
  }
}

class _RecordingWorkspace extends WorkspaceManager {
  final routes = <String>[];
  final browserUrls = <String>[];

  @override
  void navigateActiveWorkspace(String route) => routes.add(route);

  @override
  void openRouteInWorkspace(String route, {String? returnRoute}) =>
      routes.add(route);

  @override
  String? openBrowserWorkspace(String url, {String? title}) {
    browserUrls.add(url);
    return 'browser-${browserUrls.length}';
  }
}

class _RecordingToolbar extends RightToolbarService {
  final opened = <ToolbarTool>[];

  @override
  void openTool(ToolbarTool tool) => opened.add(tool);
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

const _briefing = AIAssistantResponse(
  text: 'Para hoy hay 2 cosas que necesitan atención. Revisé Taller 3, '
      'Tareas 1 registros.\n\n'
      '- Entrega atrasada · PG-00484 — En curso\n'
      '- Tarea del día · Llamar al cliente — Pendiente\n\n'
      'Al 03/08/2026 14:05, hora de Chile.',
  cards: [
    AIAssistantActionCard(
      kind: 'job',
      eyebrow: 'Taller',
      title: 'Entregas y trabajos abiertos',
      description: 'PG-00484',
      destination: AIAssistantDestination.workshopJobs,
      chips: ['Atrasado'],
    ),
    AIAssistantActionCard(
      kind: 'task',
      eyebrow: 'Tareas',
      title: 'Tareas pendientes',
      description: 'Llamar al cliente',
      destination: AIAssistantDestination.tasks,
      chips: ['Pendiente'],
    ),
  ],
);

const _approvalId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

/// **Una expiración absoluta se pudre sola.** Esta fixture vencía el
/// 2026-08-12: el día que el calendario lo pasó, la tarjeta empezó a decir
/// «Propuesta vencida» y la prueba falló sin que nadie tocara el código.
/// Lo que se afirma es la cuenta regresiva, así que la fecha es relativa.
final DateTime _approvalExpiry =
    DateTime.now().toUtc().add(const Duration(hours: 2, minutes: 1));
const _actionId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

final _taskPreviewResponse = AIAssistantResponse(
  text: 'Preparé esta tarea para tu revisión.',
  cards: <AIAssistantActionCard>[
    AIAssistantActionCard(
      kind: 'task_preview',
      eyebrow: 'Tarea propuesta',
      title: 'Llamar a Claudia',
      subtitle: 'Mañana · Prioridad alta',
      description: 'Confirmar repuesto antes de comenzar PG-00484.',
      destination: AIAssistantDestination.tasks,
      chips: const <String>['Mañana', 'Alta'],
      approvalRef: AIAssistantApprovalRef(
        id: _approvalId,
        action: AIAssistantApprovalAction.createTask,
        expiresAt: _approvalExpiry,
        state: AIAssistantApprovalState.pending,
      ),
    ),
  ],
);

const _approvedTaskResolution = AIAssistantApprovalResolution(
  approvalId: _approvalId,
  clientActionId: _actionId,
  state: AIAssistantApprovalState.approved,
  text: 'Tarea creada correctamente.',
  cards: <AIAssistantActionCard>[
    AIAssistantActionCard(
      kind: 'task',
      title: 'Tareas pendientes',
      description: 'Llamar a Claudia',
      destination: AIAssistantDestination.tasks,
      chips: <String>['1 creada'],
    ),
  ],
);

const _discardedTaskResolution = AIAssistantApprovalResolution(
  approvalId: _approvalId,
  clientActionId: _actionId,
  state: AIAssistantApprovalState.discarded,
  text: 'Propuesta descartada.',
  cards: <AIAssistantActionCard>[],
);

final _diagnosisPreviewResponse = AIAssistantResponse(
  text: 'Preparé este cambio de diagnóstico para tu revisión.',
  cards: <AIAssistantActionCard>[
    AIAssistantActionCard(
      kind: 'diagnosis_preview',
      eyebrow: 'Diagnóstico por confirmar',
      title: 'Desgaste de cadena',
      subtitle: 'PG-00420 · Trek Marlin 7',
      description: 'Sin valor anterior · Nuevo: 0.60',
      destination: AIAssistantDestination.workshopJobs,
      chips: const <String>['Requiere confirmación'],
      approvalRef: AIAssistantApprovalRef(
        id: _approvalId,
        action: AIAssistantApprovalAction.updateDiagnosis,
        expiresAt: _approvalExpiry,
        state: AIAssistantApprovalState.pending,
      ),
    ),
  ],
);

final _approvedDiagnosisResolution = AIAssistantApprovalResolution(
  approvalId: _approvalId,
  clientActionId: _actionId,
  state: AIAssistantApprovalState.approved,
  text: 'Diagnóstico actualizado.',
  cards: <AIAssistantActionCard>[
    AIAssistantActionCard(
      kind: 'job',
      title: 'PG-00420',
      description: 'Desgaste de cadena · 0.60',
      destination: AIAssistantDestination.workshopJobs,
      entityRef: AIAssistantEntityRef.verified(
        kind: AIAssistantEntityKind.workshopJob,
        id: '11111111-1111-4111-8111-111111111111',
      ),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  Future<
      ({
        _RecordingWorkspace workspace,
        _RecordingToolbar toolbar,
        _CardsEngine engine,
        AIAssistantSessionService session,
      })> pump(
    WidgetTester tester, {
    required Brightness brightness,
    AIAssistantResponse response = _briefing,
    _CardsEngine? engine,
    AIAssistantTurnServices? turnServicesOverride,
    bool seedResponse = true,
  }) async {
    final activeEngine = engine ?? _CardsEngine(response);
    final session = await boundAiSession(engineFactory: () => activeEngine);
    addTearDown(session.dispose);
    final workspace = _RecordingWorkspace();
    final toolbar = _RecordingToolbar();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AIAssistantSessionService>.value(
              value: session),
          ChangeNotifierProvider<AIAssistantContextService>(
              create: (_) => AIAssistantContextService()),
          ChangeNotifierProvider<WorkspaceManager>.value(value: workspace),
          ChangeNotifierProvider<RightToolbarService>.value(value: toolbar),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: brightness,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 900,
              child: AIChatPanel(
                jobs: const [],
                embedded: true,
                turnServicesOverride: turnServicesOverride,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    if (seedResponse) {
      unawaited(
        session.send(
          'qué necesita atención hoy',
          services: const AIAssistantTurnServices(),
          visibleJobs: const [],
          hasVisibleJobsContext: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    return (
      workspace: workspace,
      toolbar: toolbar,
      engine: activeEngine,
      session: session,
    );
  }

  /// Both real stops of the card's gradient, read off the rendered widget.
  List<Color> gradientStops(WidgetTester tester, String key) {
    final ink = tester.widget<Ink>(find.byKey(ValueKey('$key-ink')));
    final decoration = ink.decoration! as BoxDecoration;
    return (decoration.gradient! as LinearGradient).colors;
  }

  for (final brightness in Brightness.values) {
    for (final spec in const [
      ('job', 'ai-action-card-job-workshopJobs', 'Taller', 'Abrir Taller'),
      ('task', 'ai-action-card-task-tasks', 'Tareas', 'Abrir Tareas'),
    ]) {
      final (kind, key, eyebrow, cta) = spec;

      testWidgets(
          '$kind card foregrounds are readable on both gradient stops '
          'in $brightness', (tester) async {
        await pump(tester, brightness: brightness);

        expect(find.byKey(ValueKey(key)), findsOneWidget,
            reason: 'the $kind card did not render');
        final stops = gradientStops(tester, key);
        expect(stops, hasLength(2));

        final eyebrowText =
            tester.widget<Text>(find.text(eyebrow.toUpperCase()));
        final ctaText = tester.widget<Text>(find.text(cta));
        final arrow = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byIcon(Icons.arrow_outward_rounded),
          ),
        );

        for (final stop in stops) {
          expect(
            _contrast(ctaText.style!.color!, stop),
            greaterThanOrEqualTo(4.5),
            reason: '$kind CTA on $stop in $brightness',
          );
          expect(
            _contrast(eyebrowText.style!.color!, stop),
            greaterThanOrEqualTo(4.5),
            reason: '$kind eyebrow on $stop in $brightness',
          );
          expect(
            _contrast(arrow.color!, stop),
            greaterThanOrEqualTo(3.0),
            reason: '$kind arrow on $stop in $brightness',
          );
        }
      });
    }
  }

  testWidgets('the dark card is actually dark', (tester) async {
    await pump(tester, brightness: Brightness.dark);
    for (final key in const [
      'ai-action-card-job-workshopJobs',
      'ai-action-card-task-tasks',
    ]) {
      for (final stop in gradientStops(tester, key)) {
        expect(stop.computeLuminance(), lessThan(0.5), reason: key);
      }
    }
  });

  testWidgets('the briefing renders as a list and separate paragraphs',
      (tester) async {
    // `MarkdownBody` collapses soft line breaks, so a briefing joined with
    // single newlines arrives as one run-on paragraph and the bullets become
    // inline dots. The rendered widget is the only place that shows it.
    await pump(tester, brightness: Brightness.light);

    expect(find.byType(MarkdownBody), findsWidgets);
    expect(
      find.textContaining('Entrega atrasada · PG-00484', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('Tarea del día · Llamar al cliente',
          findRichText: true),
      findsWidgets,
    );
    // Two list items rendered as separate blocks, not one paragraph holding
    // both sentences.
    expect(
      find.textContaining(
        'En curso - Tarea del día',
        findRichText: true,
      ),
      findsNothing,
      reason: 'the list collapsed into a single paragraph',
    );
    expect(
      find.textContaining(
        'registros. - Entrega atrasada',
        findRichText: true,
      ),
      findsNothing,
      reason: 'the headline and the list ran together',
    );
  });

  testWidgets('assistant HTTPS links open in the embedded browser workspace',
      (tester) async {
    const sourceUrl =
        'https://www.reddit.com/r/bikewrench/comments/example/punctures/';
    final recorded = await pump(
      tester,
      brightness: Brightness.light,
      response: const AIAssistantResponse(
        text: 'Fuentes consultadas:\n\n- [Fuente Reddit]($sourceUrl)',
      ),
    );

    final link = find.text('Fuente Reddit');
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pump();

    expect(recorded.workspace.browserUrls, <String>[sourceUrl]);
    expect(recorded.workspace.routes, isEmpty);
  });

  testWidgets('assistant links reject non-HTTPS and credential-bearing URLs',
      (tester) async {
    final recorded = await pump(
      tester,
      brightness: Brightness.light,
      response: const AIAssistantResponse(
        text: '[HTTP](http://example.com) · '
            '[Credenciales](https://user:secret@example.com)',
      ),
    );

    final markdown =
        tester.widgetList<MarkdownBody>(find.byType(MarkdownBody)).last;
    markdown.onTapLink!('HTTP', 'http://example.com', '');
    markdown.onTapLink!(
      'Credenciales',
      'https://user:secret@example.com',
      '',
    );
    await tester.pump();

    expect(recorded.workspace.browserUrls, isEmpty);
    expect(recorded.workspace.routes, isEmpty);
  });

  testWidgets('both sources are offered and tapping picks the right effect',
      (tester) async {
    final recorded = await pump(tester, brightness: Brightness.light);

    expect(recorded.workspace.routes, isEmpty);
    expect(recorded.toolbar.opened, isEmpty);

    final taskCard = find.byKey(const ValueKey('ai-action-card-task-tasks'));
    await tester.ensureVisible(taskCard);
    await tester.pumpAndSettle();
    await tester.tap(taskCard);
    await tester.pump();
    expect(recorded.toolbar.opened, [ToolbarTool.tasks]);
    expect(recorded.workspace.routes, isEmpty);

    final jobCard =
        find.byKey(const ValueKey('ai-action-card-job-workshopJobs'));
    await tester.ensureVisible(jobCard);
    await tester.pumpAndSettle();
    await tester.tap(jobCard);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(recorded.workspace.routes, ['/taller/pegas']);
  });

  testWidgets('the transcript keeps both cards on the assistant turn',
      (tester) async {
    await pump(tester, brightness: Brightness.light);

    final session = Provider.of<AIAssistantSessionService>(
      tester.element(find.byType(AIChatPanel)),
      listen: false,
    );
    final assistantTurns = session.transcript
        .where((e) => e.role == AIAssistantTranscriptRole.assistant)
        .toList();
    expect(assistantTurns.last.cards, hasLength(2));
  });

  testWidgets('inventory results render as one compact list action',
      (tester) async {
    const response = AIAssistantResponse(
      text: 'Encontré resultados verificados.',
      cards: <AIAssistantActionCard>[
        AIAssistantActionCard(
          kind: 'inventory',
          title: '4 resultados',
          subtitle: 'Coincidencias para “camara 29”',
          destination: AIAssistantDestination.inventoryProducts,
          chips: <String>['En stock'],
          inventoryListRef: AIAssistantInventoryListRef(
            query: 'camara 29',
            availability: AIAssistantInventoryAvailability.inStock,
            resultCount: 4,
            hasMore: true,
            entityIds: null,
            autoOpen: false,
          ),
        ),
      ],
    );
    await pump(
      tester,
      brightness: Brightness.light,
      response: response,
    );

    final action = find.byKey(
      const ValueKey('ai-action-card-inventory-inventoryProducts'),
    );
    expect(action, findsOneWidget);
    expect(tester.widget(action), isA<ListTile>());
    expect(
        find.descendant(of: action, matching: find.byType(Wrap)), findsNothing);
    expect(find.text('Abrir Inventario'), findsNothing);
    expect(find.textContaining('En stock'), findsOneWidget);
  });

  testWidgets(
      'explicit inventory list applies the exact filter then auto-opens',
      (tester) async {
    final inventory = InventoryService(
      DatabaseService(),
      TenantService.testing(
        currentUserId: () => 'user-test',
        profileLookup: (_) async => const <Map<String, dynamic>>[],
      ),
    );
    addTearDown(inventory.dispose);
    const productA = '11111111-1111-4111-8111-111111111111';
    const productB = '22222222-2222-4222-8222-222222222222';
    const response = AIAssistantResponse(
      text: 'Abrí 2 resultados coincidentes en Inventario.',
      cards: <AIAssistantActionCard>[
        AIAssistantActionCard(
          kind: 'inventory',
          title: '2 resultados',
          destination: AIAssistantDestination.inventoryProducts,
          chips: <String>['En stock'],
          inventoryListRef: AIAssistantInventoryListRef(
            query: 'camara 29',
            availability: AIAssistantInventoryAvailability.inStock,
            resultCount: 2,
            hasMore: false,
            entityIds: <String>[productA, productB],
            autoOpen: true,
          ),
        ),
      ],
    );
    final recorded = await pump(
      tester,
      brightness: Brightness.light,
      response: response,
      turnServicesOverride: AIAssistantTurnServices(
        inventoryService: inventory,
      ),
      seedResponse: false,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-assistant-message-input')),
      'buscame camaras 29 que tengamos en stock',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('ai-assistant-send-message')),
    );
    await tester.pumpAndSettle();

    expect(recorded.workspace.routes, <String>['/inventory/products']);
    expect(
      inventory.savedSearchTerm,
      isEmpty,
      reason: 'an exact server ID projection is not shown as a manual search',
    );
    expect(inventory.savedStockFilterIndex,
        InventoryExternalStockFilter.inStock.productListIndex);
    expect(inventory.aiMatchedProductIds, <String>[productA, productB]);
  });

  testWidgets('informational inventory answer waits for a deliberate card tap',
      (tester) async {
    final inventory = InventoryService(
      DatabaseService(),
      TenantService.testing(
        currentUserId: () => 'user-test',
        profileLookup: (_) async => const <Map<String, dynamic>>[],
      ),
    );
    addTearDown(inventory.dispose);
    const response = AIAssistantResponse(
      text: 'Hay 4 cámaras con stock.',
      cards: <AIAssistantActionCard>[
        AIAssistantActionCard(
          kind: 'inventory',
          title: '4 resultados',
          destination: AIAssistantDestination.inventoryProducts,
          chips: <String>['En stock'],
          inventoryListRef: AIAssistantInventoryListRef(
            query: 'camara 29',
            availability: AIAssistantInventoryAvailability.inStock,
            resultCount: 4,
            hasMore: true,
            entityIds: null,
            autoOpen: false,
          ),
        ),
      ],
    );
    final recorded = await pump(
      tester,
      brightness: Brightness.light,
      response: response,
      turnServicesOverride: AIAssistantTurnServices(
        inventoryService: inventory,
      ),
      seedResponse: false,
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('ai-assistant-message-input')),
      'cuantas camaras 29 hay en stock?',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('ai-assistant-send-message')),
    );
    await tester.pumpAndSettle();
    expect(recorded.workspace.routes, isEmpty);

    final action = find.byKey(
      const ValueKey('ai-action-card-inventory-inventoryProducts'),
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(recorded.workspace.routes, <String>['/inventory/products']);
  });

  testWidgets('a verified result card opens its exact canonical record',
      (tester) async {
    final response = AIAssistantResponse(
      text: 'Encontré el trabajo exacto.',
      cards: <AIAssistantActionCard>[
        AIAssistantActionCard(
          kind: 'job',
          title: 'PG-00484',
          destination: AIAssistantDestination.workshopJobs,
          entityRef: AIAssistantEntityRef.verified(
            kind: AIAssistantEntityKind.workshopJob,
            id: '11111111-1111-4111-8111-111111111111',
          ),
        ),
      ],
    );
    final recorded = await pump(
      tester,
      brightness: Brightness.light,
      response: response,
    );

    expect(find.text('Abrir trabajo'), findsOneWidget);
    final card = find.byKey(
      const ValueKey('ai-action-card-job-workshopJobs'),
    );
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pump();

    expect(
      recorded.workspace.routes,
      <String>['/taller/pegas/11111111-1111-4111-8111-111111111111'],
    );
    expect(recorded.toolbar.opened, isEmpty);
  });

  testWidgets('expense and conversation cards open their exact read surfaces',
      (tester) async {
    final response = AIAssistantResponse(
      text: 'Encontré un gasto y una conversación que requieren revisión.',
      cards: <AIAssistantActionCard>[
        AIAssistantActionCard(
          kind: 'expense',
          title: 'GA-00042',
          destination: AIAssistantDestination.expenses,
          entityRef: AIAssistantEntityRef.verified(
            kind: AIAssistantEntityKind.expense,
            id: '88888888-8888-4888-8888-888888888888',
          ),
        ),
        AIAssistantActionCard(
          kind: 'conversation',
          title: 'WhatsApp sin responder',
          destination: AIAssistantDestination.conversations,
          entityRef: AIAssistantEntityRef.verified(
            kind: AIAssistantEntityKind.conversation,
            id: '99999999-9999-4999-8999-999999999999',
          ),
        ),
      ],
    );
    final recorded = await pump(
      tester,
      brightness: Brightness.light,
      response: response,
    );

    expect(find.text('Abrir gasto'), findsOneWidget);
    final expenseCard = find.byKey(
      const ValueKey('ai-action-card-expense-expenses'),
    );
    await tester.ensureVisible(expenseCard);
    await tester.tap(expenseCard);
    await tester.pump();

    expect(find.text('Abrir conversación'), findsOneWidget);
    final conversationCard = find.byKey(
      const ValueKey('ai-action-card-conversation-conversations'),
    );
    await tester.ensureVisible(conversationCard);
    await tester.tap(conversationCard);
    await tester.pump();

    expect(
      recorded.workspace.routes,
      <String>[
        '/accounting/expenses/88888888-8888-4888-8888-888888888888',
        '/chat?conversation=99999999-9999-4999-8999-999999999999',
      ],
    );
    expect(recorded.toolbar.opened, isEmpty);
  });

  testWidgets('a mismatched direct card fails closed without list fallback',
      (tester) async {
    final response = AIAssistantResponse(
      text: 'Referencia incompatible.',
      cards: <AIAssistantActionCard>[
        AIAssistantActionCard(
          kind: 'job',
          title: 'Resultado incompatible',
          destination: AIAssistantDestination.workshopJobs,
          entityRef: AIAssistantEntityRef.verified(
            kind: AIAssistantEntityKind.customer,
            id: '22222222-2222-4222-8222-222222222222',
          ),
        ),
      ],
    );
    final recorded = await pump(
      tester,
      brightness: Brightness.light,
      response: response,
    );

    final card = find.byKey(
      const ValueKey('ai-action-card-job-workshopJobs'),
    );
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pump();

    expect(recorded.workspace.routes, isEmpty);
    expect(recorded.toolbar.opened, isEmpty);
  });

  testWidgets('task preview renders the frozen details and explicit decisions',
      (tester) async {
    await pump(
      tester,
      brightness: Brightness.light,
      response: _taskPreviewResponse,
    );

    expect(find.text('TAREA PROPUESTA'), findsOneWidget);
    expect(find.text('Llamar a Claudia'), findsOneWidget);
    expect(find.text('Mañana · Prioridad alta'), findsOneWidget);
    expect(find.textContaining('PG-00484'), findsOneWidget);
    expect(find.text('Mañana'), findsOneWidget);
    expect(find.text('Alta'), findsOneWidget);
    // La cuenta regresiva reemplazó al sello UTC: «03:45 UTC» obligaba al
    // operador a convertir la hora para saber si alcanzaba a confirmar.
    expect(find.text('Confirma en 2 horas'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-approval-$_approvalId-approve')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ai-approval-$_approvalId-discard')),
      findsOneWidget,
    );
    expect(find.text('Abrir Tareas'), findsNothing);
  });

  testWidgets(
      'approval creates the task card without model turn or automatic navigation',
      (tester) async {
    final engine = _CardsEngine(
      _taskPreviewResponse,
      approvalResolution: _approvedTaskResolution,
    );
    final recorded = await pump(
      tester,
      brightness: Brightness.light,
      response: _taskPreviewResponse,
      engine: engine,
    );

    final approveAction =
        find.byKey(const ValueKey('ai-approval-$_approvalId-approve'));
    await tester.ensureVisible(approveAction);
    await tester.pumpAndSettle();
    await tester.tap(approveAction);
    await tester.pumpAndSettle();

    expect(engine.approvalDecisions, <AIAssistantApprovalDecision>[
      AIAssistantApprovalDecision.approve,
    ]);
    expect(recorded.workspace.routes, isEmpty);
    expect(recorded.toolbar.opened, isEmpty);
    expect(find.text('Tarea creada correctamente.'), findsOneWidget);
    expect(find.text('Crear tarea'), findsNothing);
    expect(find.text('Descartar'), findsNothing);

    final resultCard = find.byKey(const ValueKey('ai-action-card-task-tasks'));
    await tester.ensureVisible(resultCard);
    await tester.tap(resultCard);
    await tester.pump();

    expect(recorded.toolbar.opened, <ToolbarTool>[ToolbarTool.tasks]);
    expect(recorded.workspace.routes, isEmpty);
  });

  testWidgets(
      'diagnosis preview confirms the typed change then exposes the exact job',
      (tester) async {
    final engine = _CardsEngine(
      _diagnosisPreviewResponse,
      approvalResolution: _approvedDiagnosisResolution,
    );
    final recorded = await pump(
      tester,
      brightness: Brightness.light,
      response: _diagnosisPreviewResponse,
      engine: engine,
    );

    expect(find.text('Actualizar diagnóstico'), findsOneWidget);
    expect(find.text('Abrir Taller'), findsNothing);
    final approveAction =
        find.byKey(const ValueKey('ai-approval-$_approvalId-approve'));
    await tester.ensureVisible(approveAction);
    await tester.pumpAndSettle();
    await tester.tap(approveAction);
    await tester.pumpAndSettle();

    expect(find.text('Diagnóstico actualizado.'), findsOneWidget);
    expect(engine.approvalDecisions, <AIAssistantApprovalDecision>[
      AIAssistantApprovalDecision.approve,
    ]);
    expect(recorded.workspace.routes, isEmpty);

    final resultCard =
        find.byKey(const ValueKey('ai-action-card-job-workshopJobs'));
    await tester.ensureVisible(resultCard);
    await tester.tap(resultCard);
    await tester.pump();
    expect(
      recorded.workspace.routes,
      <String>['/taller/pegas/11111111-1111-4111-8111-111111111111'],
    );
  });

  testWidgets('discard terminalizes the preview and exposes no action buttons',
      (tester) async {
    final engine = _CardsEngine(
      _taskPreviewResponse,
      approvalResolution: _discardedTaskResolution,
    );
    final recorded = await pump(
      tester,
      brightness: Brightness.light,
      response: _taskPreviewResponse,
      engine: engine,
    );

    final discardAction =
        find.byKey(const ValueKey('ai-approval-$_approvalId-discard'));
    await tester.ensureVisible(discardAction);
    await tester.pumpAndSettle();
    await tester.tap(discardAction);
    await tester.pumpAndSettle();

    expect(find.text('Propuesta descartada'), findsOneWidget);
    expect(find.text('Crear tarea'), findsNothing);
    expect(find.text('Descartar'), findsNothing);
    expect(engine.approvalDecisions, <AIAssistantApprovalDecision>[
      AIAssistantApprovalDecision.discard,
    ]);
    expect(recorded.workspace.routes, isEmpty);
    expect(recorded.toolbar.opened, isEmpty);
  });

  testWidgets('terminal preview replay is read-only', (tester) async {
    final terminalResponse = AIAssistantResponse(
      text: _taskPreviewResponse.text,
      cards: <AIAssistantActionCard>[
        _taskPreviewResponse.cards.single.withApprovalState(
          AIAssistantApprovalState.discarded,
        ),
      ],
    );
    await pump(
      tester,
      brightness: Brightness.light,
      response: terminalResponse,
    );

    expect(find.text('Propuesta descartada'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-approval-$_approvalId-approve')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ai-approval-$_approvalId-discard')),
      findsNothing,
    );
  });

  testWidgets('approval is single-flight and late logout result is discarded',
      (tester) async {
    final completer = Completer<AIAssistantApprovalResolution>();
    final engine = _CardsEngine(
      _taskPreviewResponse,
      approvalCompleter: completer,
    );
    final recorded = await pump(
      tester,
      brightness: Brightness.light,
      response: _taskPreviewResponse,
      engine: engine,
    );

    final approveAction =
        find.byKey(const ValueKey('ai-approval-$_approvalId-approve'));
    await tester.ensureVisible(approveAction);
    await tester.pumpAndSettle();
    await tester.tap(approveAction);
    await tester.pump();

    final approve = tester.widget<FilledButton>(
      find.byKey(const ValueKey('ai-approval-$_approvalId-approve')),
    );
    final discard = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('ai-approval-$_approvalId-discard')),
    );
    expect(approve.onPressed, isNull);
    expect(discard.onPressed, isNull);
    expect(engine.approvalDecisions, hasLength(1));

    await recorded.session.synchronize(
      authUserId: null,
      profile: null,
      profileIsLoading: false,
      profileLoadIssue: null,
      cachedTenantId: null,
      resolveTenantId: () async => null,
    );
    completer.complete(_approvedTaskResolution);
    await tester.pumpAndSettle();

    expect(recorded.session.transcript, isEmpty);
    expect(find.text('Tarea creada correctamente.'), findsNothing);
    expect(recorded.workspace.routes, isEmpty);
    expect(recorded.toolbar.opened, isEmpty);
  });
}
