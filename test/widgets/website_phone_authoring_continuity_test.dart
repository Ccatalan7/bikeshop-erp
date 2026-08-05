import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_block_sheet.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_contextual_dock.dart';
import 'package:vinabike_erp/modules/website/widgets/website_inline_action_editor.dart';
import 'package:vinabike_erp/public_store/widgets/page_composition.dart';
import 'package:vinabike_erp/public_store/widgets/persistent_editor_shell.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Phone authoring on the real shell: dock, canvas and sheet together.
///
/// Everything here is asserted against the composed tree — the shell measures
/// its own dock, the canvas reserves that band and the sheet is the route the
/// contextual host actually opens. Each defect this file guards was reproduced
/// on the running app at 430×896 and could not be seen from a unit test: the
/// state was correct in all three cases and the geometry was not.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 — frames **10e** (dock),
/// **10f**/**10h** (`O-05`, 60% cap) and **10g** (keyboard), plus
/// `handoff-t10/spec.json` `surface_component_map`.
void main() {
  Map<String, dynamic> block({
    required String id,
    required String type,
    required int order,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) {
    return <String, dynamic>{
      'id': id,
      'block_type': type,
      'order_index': order,
      'is_visible': true,
      'block_data': data,
    };
  }

  /// Three blocks tall enough that a move pushes one off a 430×896 phone —
  /// the condition under which the reported defect is visible at all.
  List<Map<String, dynamic>> tallPage() => <Map<String, dynamic>>[
        block(
          id: 'hero-1',
          type: 'hero',
          order: 0,
          data: const <String, dynamic>{
            'title': 'Taller de bicicletas',
            'blockHeight': 620,
            'buttonText': 'Ver catálogo',
            'buttonLink': '/productos',
          },
        ),
        block(
          id: 'text-1',
          type: 'text',
          order: 1,
          data: const <String, dynamic>{
            'content': 'Productos destacados',
            'blockHeight': 620,
          },
        ),
        block(
          id: 'text-2',
          type: 'text',
          order: 2,
          data: const <String, dynamic>{
            'content': 'Servicios',
            'blockHeight': 620,
          },
        ),
      ];

  void useViewport(
    WidgetTester tester, {
    double width = 430,
    double height = 896,
    double bottomViewInset = 0,
    double bottomPadding = 20,
  }) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    tester.view.viewInsets = FakeViewPadding(bottom: bottomViewInset);
    tester.view.viewPadding = FakeViewPadding(bottom: bottomPadding);
    tester.view.padding = FakeViewPadding(
      bottom: bottomViewInset > 0 ? 0 : bottomPadding,
    );
    addTearDown(tester.view.reset);
  }

  /// The production shape: the shell owns the chrome scope and the dock, and
  /// the canvas is its child. Nothing about the dock band is restated here —
  /// if the shell stopped publishing it, these tests would fail.
  Widget host(WebsiteEditModeProvider provider) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: Brightness.light,
      ),
      home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: Scaffold(
          body: PersistentEditorShell(
            child: Consumer<WebsiteEditModeProvider>(
              builder: (context, live, _) => SingleChildScrollView(
                child: PageComposition(
                  composition: WebsitePageComposition.project(
                    blocks: live.blocks,
                    mode: live.isEditMode
                        ? WebsitePageCompositionMode.edit
                        : WebsitePageCompositionMode.preview,
                    breakpoint: 'mobile',
                  ),
                  primaryColor: Colors.blue,
                  accentColor: Colors.teal,
                  textColor: Colors.black,
                  containerPadding: 16,
                  onAddBlock: (type, {atIndex}) {},
                  onSpacingChanged: (blockId, spacing) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpHost(WidgetTester tester, Widget widget) async {
    await tester.runAsync(DeferredEditableBlockRenderer.preload);
    await tester.pumpWidget(widget);
    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
  }

  /// Settles the reveal: the request is served post-frame and then animates.
  Future<void> settleReveal(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Rect rectOf(WidgetTester tester, Finder finder) {
    final box = tester.renderObject<RenderBox>(finder);
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Finder blockFinder(String id) =>
      find.byKey(ValueKey<String>('page-composition-block-$id'));

  group('reorden: el bloque movido queda a la vista y fuera del dock', () {
    testWidgets('mover abajo revela el bloque en su nueva posición',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          tallPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..selectBlock('hero-1');
      addTearDown(provider.dispose);

      await pumpHost(tester, host(provider));
      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsOneWidget);

      await tester.tap(find.byKey(WebsiteEditorContextualDock.moveDownKey));
      await settleReveal(tester);

      expect(provider.blocks[1]['id'], 'hero-1');

      final dock = rectOf(
        tester,
        find.byKey(WebsiteEditorContextualDock.dockKey),
      );
      final moved = rectOf(tester, blockFinder('hero-1'));
      const viewport = Rect.fromLTWH(0, 0, 430, 896);

      // Visible, y no bajo el dock: el dock es la única otra señal que tiene
      // el operador y sigue nombrando el mismo bloque.
      expect(moved.overlaps(viewport), isTrue);
      expect(moved.bottom, lessThanOrEqualTo(dock.top + 0.5));
    });

    testWidgets('el penúltimo movido al final no queda detrás del dock',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          tallPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..selectBlock('text-1');
      addTearDown(provider.dispose);

      await pumpHost(tester, host(provider));
      await tester.tap(find.byKey(WebsiteEditorContextualDock.moveDownKey));
      await settleReveal(tester);

      expect(provider.blocks.last['id'], 'text-1');

      final dock = rectOf(
        tester,
        find.byKey(WebsiteEditorContextualDock.dockKey),
      );
      final moved = rectOf(tester, blockFinder('text-1'));

      // Éste es el caso que obliga a reservar la banda: al final del documento
      // el scroll ya no da más, así que sin inset el bloque revelado aterriza
      // justo donde el dock pinta.
      expect(moved.bottom, lessThanOrEqualTo(dock.top + 0.5));
      expect(moved.top, greaterThanOrEqualTo(0));
    });

    testWidgets('deshacer restaura el orden y vuelve a revelar',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          tallPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..selectBlock('hero-1');
      addTearDown(provider.dispose);

      await pumpHost(tester, host(provider));
      await tester.tap(find.byKey(WebsiteEditorContextualDock.moveDownKey));
      await settleReveal(tester);

      provider.undo();
      await settleReveal(tester);

      expect(provider.blocks.first['id'], 'hero-1');

      final dock = rectOf(
        tester,
        find.byKey(WebsiteEditorContextualDock.dockKey),
      );
      final restored = rectOf(tester, blockFinder('hero-1'));
      expect(restored.bottom, lessThanOrEqualTo(dock.top + 0.5));
    });

    testWidgets('la banda del dock la publica el shell, no el lienzo',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          tallPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
        );
      addTearDown(provider.dispose);

      await pumpHost(tester, host(provider));

      double publishedBand() {
        final context = tester.element(find.byType(PageComposition));
        return WebsiteEditorChromeScope.maybeOf(context)!.contextualDockHeight;
      }

      // Sin selección no hay dock, y por lo tanto no hay banda que reservar.
      expect(publishedBand(), 0);

      provider.selectBlock('hero-1');
      await tester.pump();
      await tester.pump();

      final dockHeight = tester
          .getSize(find.byKey(WebsiteEditorContextualDock.dockKey))
          .height;
      expect(publishedBand(), moreOrLessEquals(dockHeight, epsilon: 0.5));
    });
  });

  group('CTA inline: el host contextual usa O-05, no la tarjeta anclada', () {
    /// `Texto del botón`, scoped to the sheet: the canvas behind it keeps its
    /// own inline text fields mounted.
    Finder sheetLabelField() => find
        .descendant(
          of: find.byKey(WebsiteInlineActionEditor.sheetFieldsKey),
          matching: find.byType(TextField),
        )
        .first;

    Future<void> openCtaEditor(WidgetTester tester) async {
      final cta = find.byKey(
        const ValueKey<String>('website-inline-action-hero-1-hero.action'),
      );
      expect(cta, findsOneWidget);
      // Primer toque selecciona, segundo abre: la semántica vigente.
      await tester.tap(cta, warnIfMissed: false);
      await tester.pump();
      await tester.tap(cta, warnIfMissed: false);
      // Pumps acotados en vez de `pumpAndSettle`: con pane el inspector
      // diferido puede quedarse cargando en el harness, y esperar a que el
      // árbol entero quede quieto sería esperar por otra cosa.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('segundo toque abre la hoja con los tres campos',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          tallPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..selectBlock('hero-1');
      addTearDown(provider.dispose);

      await pumpHost(tester, host(provider));
      await openCtaEditor(tester);

      expect(find.byKey(WebsiteInlineActionEditor.sheetKey), findsOneWidget);
      // La tarjeta anclada es chrome de puntero y aquí no existe.
      expect(find.text('Editar acción'), findsNothing);

      // Los tres campos del botón, sin pasar por el inspector genérico.
      expect(
        find.byKey(WebsiteInlineActionEditor.sheetFieldsKey),
        findsOneWidget,
      );
      expect(find.text('Texto del botón'), findsOneWidget);
      expect(find.text('Destino'), findsOneWidget);
      expect(find.text('Presentación'), findsOneWidget);
    });

    testWidgets(
        'la hoja respeta el tope del 60% y deja la acción fuera '
        'del dock', (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          tallPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..selectBlock('hero-1');
      addTearDown(provider.dispose);

      await pumpHost(tester, host(provider));
      await openCtaEditor(tester);

      final sheet = rectOf(
        tester,
        find.byKey(WebsiteInlineActionEditor.sheetKey),
      );
      expect(
        sheet.height,
        lessThanOrEqualTo(
          WebsiteBlockEditSheetGeometry.maxHeightFor(896) + 0.5,
        ),
      );

      // La hoja se abre sobre el dock, así que la acción principal y el
      // control de presentación quedan alcanzables — que es exactamente lo
      // que la tarjeta anclada no conseguía.
      final apply = rectOf(
        tester,
        find.byKey(WebsiteInlineActionEditor.sheetApplyKey),
      );
      expect(apply.bottom, lessThanOrEqualTo(896));
      expect(apply.height, WebsiteBlockEditSheetGeometry.ctaHeight);
      expect(find.text('Presentación'), findsOneWidget);
    });

    testWidgets('con el teclado arriba la acción principal sigue accesible',
        (tester) async {
      useViewport(tester, bottomViewInset: 292);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          tallPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..selectBlock('hero-1');
      addTearDown(provider.dispose);

      await pumpHost(tester, host(provider));
      await openCtaEditor(tester);

      final sheet = rectOf(
        tester,
        find.byKey(WebsiteInlineActionEditor.sheetKey),
      );
      final apply = rectOf(
        tester,
        find.byKey(WebsiteInlineActionEditor.sheetApplyKey),
      );

      // t10 10g: el teclado es parte de la geometría. La hoja se mide contra
      // el alto que el teclado deja, y nada queda debajo de él.
      expect(sheet.bottom, lessThanOrEqualTo(896 - 292 + 0.5));
      expect(
        sheet.height,
        lessThanOrEqualTo(
          WebsiteBlockEditSheetGeometry.maxHeightFor(896 - 292) + 0.5,
        ),
      );
      expect(apply.bottom, lessThanOrEqualTo(896 - 292 + 0.5));
    });

    testWidgets('Listo escribe una sola vez y en un solo paso de historial',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          tallPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..selectBlock('hero-1');
      addTearDown(provider.dispose);

      await pumpHost(tester, host(provider));
      await openCtaEditor(tester);

      await tester.enterText(sheetLabelField(), 'Ver el catálogo');
      await tester.pump();
      // Nada se ha escrito todavía: el borrador vive en la hoja.
      expect(provider.getBlockData('hero-1')['buttonText'], 'Ver catálogo');
      expect(provider.canUndo, isFalse);

      await tester.tap(find.byKey(WebsiteInlineActionEditor.sheetApplyKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(provider.getBlockData('hero-1')['buttonText'], 'Ver el catálogo');
      expect(provider.canUndo, isTrue);
      // Rótulo, destino y presentación son UNA operación: un solo deshacer
      // devuelve el valor anterior.
      provider.undo();
      expect(provider.getBlockData('hero-1')['buttonText'], 'Ver catálogo');
      expect(provider.canUndo, isFalse);
    });

    testWidgets('Cancelar descarta el borrador de la hoja', (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          tallPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..selectBlock('hero-1');
      addTearDown(provider.dispose);

      await pumpHost(tester, host(provider));
      await openCtaEditor(tester);

      await tester.enterText(sheetLabelField(), 'Descartado');
      await tester.pump();
      await tester.tap(find.byKey(WebsiteInlineActionEditor.sheetCancelKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(provider.getBlockData('hero-1')['buttonText'], 'Ver catálogo');
      expect(provider.canUndo, isFalse);
    });

    testWidgets('el host con pane conserva la tarjeta anclada', (tester) async {
      useViewport(tester, width: 1200, height: 900);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          tallPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..selectBlock('hero-1');
      addTearDown(provider.dispose);

      await pumpHost(tester, host(provider));
      await openCtaEditor(tester);

      // `O-05` nunca aparece en desktop pointer (t10 surface_component_map).
      expect(find.byKey(WebsiteInlineActionEditor.sheetKey), findsNothing);
      expect(find.text('Editar acción'), findsOneWidget);
    });
  });
}
