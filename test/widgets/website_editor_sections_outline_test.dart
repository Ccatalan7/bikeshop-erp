import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/services/website_html_canvas_preference.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_website_editor_panel.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_command_scope.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_host_theme.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/public_store/widgets/persistent_editor_shell.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Inicio as it is in production (2026-10-06): a banner, featured products,
/// the brands and the reviews.
const _blocks = <Map<String, dynamic>>[
  {
    'id': 'hero-1',
    'block_type': 'hero',
    'block_data': {'title': 'Sobre Viñabike'},
    'is_visible': true,
    'order_index': 0,
  },
  {
    'id': 'products-1',
    'block_type': 'products',
    'block_data': {'title': 'Productos Destacados'},
    'is_visible': true,
    'order_index': 1,
  },
  {
    'id': 'brands-1',
    'block_type': 'brandLogos',
    'block_data': {'title': 'MARCAS'},
    'is_visible': false,
    'order_index': 2,
  },
  {
    'id': 'reviews-1',
    'block_type': 'googleReviews',
    'block_data': {'title': 'Reseñas'},
    'is_visible': true,
    'order_index': 3,
  },
];

final _page = Object();

WebsiteEditModeProvider _editor({bool onCanvas = true}) {
  final provider = WebsiteEditModeProvider()
    ..enterEditMode(
      [for (final block in _blocks) Map<String, dynamic>.from(block)],
      const <String, dynamic>{},
    );
  if (onCanvas) provider.publishBlockCanvas(publisher: _page);
  addTearDown(provider.dispose);
  return provider;
}

WebsiteEditorCapabilitySnapshot _lease(String identity) =>
    WebsiteEditorCapabilitySnapshot(
      identity: identity,
      activeTenantId: 'tenant-a',
      storefrontTenantId: 'tenant-a',
      hasAuthority: true,
    );

List<String> _ids(WebsiteEditModeProvider provider) =>
    [for (final block in provider.blocks) block['id'] as String];

WebsiteService _offlineService() => WebsiteService(
      supabase: SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode(<Object?>[]),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      ),
      tenantService: TenantService.testing(
        currentUserId: () => 'user-a',
        profileLookup: (_) async => const [],
      ),
    );

Future<void> _pumpRail(
  WidgetTester tester,
  WebsiteEditModeProvider provider, {
  Future<void> Function(BuildContext context)? onAddSection,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(264, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WebsiteEditModeProvider>.value(value: provider),
        ChangeNotifierProvider<WebsiteService>.value(value: _offlineService()),
      ],
      child: MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: Brightness.light,
        ),
        home: WebsiteEditorCommandScope(
          isSaving: false,
          onSave: () async {},
          onDiscard: () {},
          onRestoreComplete: () async {},
          onAddSection: onAddSection,
          child: Builder(
            builder: (hostContext) => Theme(
              data: WebsiteEditorInspectorTheme.resolveFrom(hostContext),
              child: const Scaffold(body: WebsiteEditorSectionsRail()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(String id) => find.byKey(ValueKey('website-sections-row-$id'));

void main() {
  // The Flutter canvas: widget tests run as Android, where the editor opens
  // on the «Vista HTML» since 2026-10-08.
  setUp(() => WebsiteHtmlCanvasPreference.chooseForTest(false));
  tearDown(WebsiteHtmlCanvasPreference.resetForTest);

  group('the rail only comes where the page still renders as desktop', () {
    test('its threshold is derived: pane + rail + the desktop canvas', () {
      expect(WebsiteEditorChromeGeometry.sectionsRailMinimumEditorWidth, 1584);
      expect(WebsiteEditorChromeGeometry.sectionsRailWidthFor(1583), isNull);
      expect(WebsiteEditorChromeGeometry.sectionsRailWidthFor(1440), isNull);
      expect(WebsiteEditorChromeGeometry.sectionsRailWidthFor(1584), 264);
      expect(WebsiteEditorChromeGeometry.sectionsRailWidthFor(1920), 264);
      // Without a pane there is no rail either.
      expect(WebsiteEditorChromeGeometry.sectionsRailWidthFor(820), isNull);
    });

    test('beside both columns the canvas keeps the desktop layout', () {
      final atThreshold = WebsiteEditorChromeGeometry.canvasWidthFor(1584);
      expect(atThreshold, 900);
      expect(
        WebsiteEditorChromeGeometry.viewportForCanvasWidth(atThreshold),
        WebsiteViewport.desktop,
      );
      expect(WebsiteEditorChromeGeometry.canvasWidthFor(1920), 1236);
      expect(WebsiteEditorChromeGeometry.canvasWidthFor(1440), 1020);
    });
  });

  group('the «Secciones» list', () {
    testWidgets(
        'lists the page in view between the header and the footer, each '
        'block by its kind and its own words', (tester) async {
      final provider = _editor();
      await _pumpRail(tester, provider, onAddSection: (_) async {});

      expect(find.text('Secciones'), findsOneWidget);
      expect(find.text('Inicio'), findsOneWidget);
      expect(_row('header'), findsOneWidget);
      expect(_row('footer'), findsOneWidget);
      expect(find.text('Sobre Viñabike'), findsOneWidget);
      expect(find.text('Productos Destacados'), findsOneWidget);
      expect(find.textContaining('oculta · MARCAS'), findsOneWidget);
      expect(find.text('Agregar sección'), findsOneWidget);

      final top = tester.getTopLeft(_row('header')).dy;
      final first = tester.getTopLeft(_row('hero-1')).dy;
      final last = tester.getTopLeft(_row('reviews-1')).dy;
      final footer = tester.getTopLeft(_row('footer')).dy;
      expect(top < first && first < last && last < footer, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('choosing a row selects it and asks the canvas to show it',
        (tester) async {
      final provider = _editor();
      await _pumpRail(tester, provider);

      await tester.tap(_row('products-1'));
      await tester.pumpAndSettle();
      expect(provider.selectedBlockId, 'products-1');
      expect(provider.blockRevealRequest?.blockId, 'products-1');

      await tester.tap(_row('footer'));
      await tester.pumpAndSettle();
      expect(provider.selectedBlockId, 'footer');
    });

    testWidgets('a hidden block is shown again from its row', (tester) async {
      final provider = _editor();
      await _pumpRail(tester, provider);

      await tester.tap(
        find.byKey(const ValueKey('website-sections-visibility-brands-1')),
      );
      await tester.pumpAndSettle();
      expect(provider.getBlock('brands-1')!['is_visible'], isTrue);
      expect(provider.hasUnsavedChanges, isTrue);
      expect(find.textContaining('oculta'), findsNothing);
    });

    testWidgets('the menu moves, duplicates and — confirmed — deletes',
        (tester) async {
      final provider = _editor();
      await _pumpRail(tester, provider);

      Future<void> choose(String id, String action) async {
        await tester.tap(find.byKey(ValueKey('website-sections-more-$id')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action).last);
        await tester.pumpAndSettle();
      }

      await choose('hero-1', 'Bajar');
      expect(_ids(provider).take(2), ['products-1', 'hero-1']);

      await choose('reviews-1', 'Duplicar');
      expect(provider.blocks, hasLength(5));

      // Delete asks first, and keeping the block is the safe default.
      await choose('products-1', 'Eliminar bloque');
      expect(find.text('¿Eliminar este bloque?'), findsOneWidget);
      await tester.tap(find.text('Conservar bloque'));
      await tester.pumpAndSettle();
      expect(provider.getBlock('products-1'), isNotNull);

      await choose('products-1', 'Eliminar bloque');
      await tester.tap(find.text('Eliminar bloque').last);
      await tester.pumpAndSettle();
      expect(provider.getBlock('products-1'), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a section copied on one page is pasted on another, as its own '
        'block', (tester) async {
      final provider = _editor();
      // The copy belongs to the editor session of this identity.
      provider.adoptEditorEntryLease(
        provider.editorEntryLeaseGeneration,
        _lease('owner-a'),
      );
      await _pumpRail(tester, provider);
      expect(
          find.byKey(const ValueKey('website-sections-paste')), findsNothing);

      await tester
          .tap(find.byKey(const ValueKey('website-sections-more-reviews-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar para otra página'));
      await tester.pumpAndSettle();
      expect(provider.hasSectionClipboard, isTrue);

      // Another page: «Contacto», with one block of its own.
      provider
        ..enterEditMode(
          [
            {
              'id': 'contact-1',
              'block_type': 'contact',
              'block_data': {'title': 'Contacto'},
              'is_visible': true,
              'order_index': 0,
            },
          ],
          const <String, dynamic>{},
        )
        ..publishBlockCanvas(publisher: _page);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('website-sections-paste')));
      await tester.pumpAndSettle();
      expect(provider.blocks, hasLength(2));
      final pasted = provider.blocks.last;
      expect(pasted['block_type'], 'googleReviews');
      expect(pasted['block_data'], {'title': 'Reseñas'});
      expect(pasted['id'], isNot('reviews-1'));
      expect(provider.selectedBlockId, pasted['id']);
      expect(provider.hasUnsavedChanges, isTrue);

      // Another identity never pastes what the first one copied.
      provider.adoptEditorEntryLease(
        provider.editorEntryLeaseGeneration,
        _lease('owner-b'),
      );
      expect(provider.hasSectionClipboard, isFalse);
      expect(provider.pasteSectionFromClipboard(), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a block is dragged to another place by its handle',
        (tester) async {
      final provider = _editor();
      await _pumpRail(tester, provider);

      final handle = find.byKey(const ValueKey('website-sections-drag-hero-1'));
      final rowHeight = tester.getSize(_row('hero-1')).height;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 20));
      for (var step = 0; step < 10; step++) {
        await gesture.moveBy(Offset(0, rowHeight * 0.25));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_ids(provider).first, isNot('hero-1'));
      expect(_ids(provider), containsAll(_blocks.map((b) => b['id'])));
      expect(provider.hasUnsavedChanges, isTrue);
    });

    testWidgets('«Agregar sección» runs the shell insertion command',
        (tester) async {
      final provider = _editor();
      var calls = 0;
      await _pumpRail(tester, provider, onAddSection: (_) async => calls++);

      await tester.tap(find.byKey(const ValueKey('website-sections-add')));
      await tester.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets(
        'a page with no document of its own never lists the previous '
        'page\'s blocks', (tester) async {
      // Inicio stays the open document while a cart or a product page is in
      // view: the list must not offer Inicio's blocks there.
      final provider = _editor(onCanvas: false);
      await _pumpRail(tester, provider, onAddSection: (_) async {});

      expect(_row('hero-1'), findsNothing);
      expect(find.text('Agregar sección'), findsNothing);
      expect(_row('header'), findsOneWidget);
      expect(_row('footer'), findsOneWidget);
      expect(find.textContaining('no tiene secciones propias'), findsOneWidget);
    });
  });

  group('with nothing selected the inspector', () {
    Future<void> pumpInspector(
      WidgetTester tester,
      WebsiteEditModeProvider provider, {
      required double railWidth,
      bool pane = false,
    }) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(420, 1200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<WebsiteEditModeProvider>.value(
              value: provider,
            ),
            ChangeNotifierProvider<WebsiteService>.value(
              value: _offlineService(),
            ),
          ],
          child: MaterialApp(
            home: WebsiteEditorChromeScope(
              editorWidth: 1600,
              canvasWidth: 900,
              sectionsRailWidth: railWidth,
              child: Builder(
                builder: (hostContext) => Theme(
                  data: WebsiteEditorInspectorTheme.resolveFrom(hostContext),
                  child: Scaffold(
                    body: pane
                        ? const WebsiteEditorPanel()
                        : WebsiteBlockEditSurface(
                            editProvider: provider,
                            section: WebsiteBlockEditSection.content,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists the sections where no rail is beside the canvas',
        (tester) async {
      final provider = _editor();
      await pumpInspector(tester, provider, railWidth: 0);
      expect(find.text('Secciones'), findsOneWidget);
      expect(_row('hero-1'), findsOneWidget);
    });

    testWidgets('without the rail, a chosen section leads back to the list',
        (tester) async {
      final provider = _editor()..selectBlock('products-1');
      await pumpInspector(tester, provider, railWidth: 0, pane: true);
      final back =
          find.byKey(const ValueKey('website-editor-back-to-sections'));
      expect(back, findsOneWidget);

      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(provider.selectedBlockId, isNull);
      expect(_row('products-1'), findsOneWidget);
    });

    testWidgets('with the rail there is no second way back', (tester) async {
      final provider = _editor()..selectBlock('products-1');
      await pumpInspector(tester, provider, railWidth: 264, pane: true);
      expect(find.text('Productos Destacados'), findsWidgets);
      expect(
        find.byKey(const ValueKey('website-editor-back-to-sections')),
        findsNothing,
      );
    });

    testWidgets('points to the rail instead of drawing the list twice',
        (tester) async {
      final provider = _editor();
      await pumpInspector(tester, provider, railWidth: 264);
      expect(find.text('Elige una sección'), findsOneWidget);
      expect(_row('hero-1'), findsNothing);
    });
  });

  group('the shell', () {
    Future<void> pumpShell(WidgetTester tester, double width) async {
      final provider = _editor();
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = Size(width, 900);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<WebsiteEditModeProvider>.value(
              value: provider,
            ),
            ChangeNotifierProvider<WebsiteService>.value(
              value: _offlineService(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.resolve(
              preset: AppearancePresets.pacific,
              brightness: Brightness.dark,
            ),
            home: const Scaffold(
              body: PersistentEditorShell(
                child: ColoredBox(
                  key: ValueKey('shell-canvas'),
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 60));
    }

    WebsiteEditorChromeScope scope(WidgetTester tester) =>
        WebsiteEditorChromeScope.maybeOf(
          tester.element(find.byKey(const ValueKey('shell-canvas'))),
        )!;

    testWidgets('mounts the rail at the left on a wide editor', (tester) async {
      await pumpShell(tester, 1600);
      final rail = find.byType(DeferredWebsiteEditorSectionsRail);
      expect(rail, findsOneWidget);
      expect(tester.getTopLeft(rail).dx, 0);
      expect(tester.getSize(rail).width, 264);
      expect(scope(tester).sectionsRailWidth, 264);
      expect(scope(tester).canvasWidth, 1600 - 420 - 264);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaves it out where the canvas would stop being desktop',
        (tester) async {
      await pumpShell(tester, 1440);
      expect(find.byType(DeferredWebsiteEditorSectionsRail), findsNothing);
      expect(scope(tester).sectionsRailWidth, 0);
      expect(scope(tester).canvasWidth, 1440 - 420);
      expect(tester.takeException(), isNull);
    });
  });
}
