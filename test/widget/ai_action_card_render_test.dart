import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_destination.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_session_state.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_context_service.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_session_service.dart';
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
class _CardsEngine extends AIAssistantService {
  _CardsEngine(this.response);

  final AIAssistantResponse response;

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
}

class _RecordingWorkspace extends WorkspaceManager {
  final routes = <String>[];

  @override
  void navigateActiveWorkspace(String route) => routes.add(route);
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

void main() {
  Future<({_RecordingWorkspace workspace, _RecordingToolbar toolbar})> pump(
    WidgetTester tester, {
    required Brightness brightness,
    AIAssistantResponse response = _briefing,
  }) async {
    final session =
        await boundAiSession(engineFactory: () => _CardsEngine(response));
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
          home: const Scaffold(
            body: SizedBox(
              width: 520,
              height: 900,
              child: AIChatPanel(jobs: [], embedded: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

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

    return (workspace: workspace, toolbar: toolbar);
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
}
