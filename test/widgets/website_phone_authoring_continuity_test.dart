import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_catalog.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_drag_payload.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_catalog_sheet.dart';
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

    testWidgets(
        'una hoja vieja no redirige su acción a otra página con el mismo id',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          tallPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: '/page-a',
        )
        ..selectBlock('hero-1');
      addTearDown(provider.dispose);

      await pumpHost(tester, host(provider));
      await openCtaEditor(tester);
      await tester.enterText(sheetLabelField(), 'Borrador de A');
      await tester.pump();

      final pageB = tallPage();
      pageB.first['block_data'] = <String, dynamic>{
        'title': 'Página B',
        'blockHeight': 620,
        'buttonText': 'Acción de B',
        'buttonLink': '/pagina-b',
      };
      provider
        ..enterEditMode(
          pageB,
          const <String, dynamic>{},
          pageId: 'page-b',
          pageSlug: '/page-b',
        )
        ..selectBlock('hero-1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      await tester.tap(find.byKey(WebsiteInlineActionEditor.sheetApplyKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(provider.getBlockData('hero-1')['title'], 'Página B');
      expect(provider.getBlockData('hero-1')['buttonText'], 'Acción de B');
      expect(provider.getBlockData('hero-1')['buttonLink'], '/pagina-b');
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(tester.takeException(), isNull);
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

  // ---------------------- reordenar bloques con el dedo, sin robar el scroll

  group('reordenar bloques desde el handle contextual', () {
    List<String> orderOf(WebsiteEditModeProvider provider) => provider.blocks
        .map((block) => block['id'].toString())
        .toList(growable: false);

    Finder handleFor(String blockId) =>
        find.byKey(websiteBlockReorderHandleKey(blockId));

    /// Long press on the block's handle and drop it on a seam addressed BY
    /// KEY — never by a guessed offset.
    Future<void> dragHandleToSeam(
      WidgetTester tester, {
      required String blockId,
      required int insertIndex,
    }) async {
      final gesture = await tester.startGesture(
        tester.getCenter(handleFor(blockId)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 40));
      // The report is a setState: the seams appear on the NEXT frame.
      await tester.pump(const Duration(milliseconds: 40));
      final seam = find.byKey(websiteReorderSeamKey(insertIndex));
      expect(seam, findsOneWidget, reason: 'seam $insertIndex');
      await gesture.moveTo(tester.getCenter(seam));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 120));
    }

    /// The canonical page scroller: the one the shell's body owns.
    ScrollableState scroller(WidgetTester tester) =>
        tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          ),
        );

    /// A page that really overflows 896: three exact-height blocks that the
    /// composition cannot shrink. Anything intrinsic renders one line tall and
    /// the page fits, which would make a scroll assertion vacuous.
    List<Map<String, dynamic>> overflowingPage() => <Map<String, dynamic>>[
          for (final id in const <String>['hero-1', 'hero-2', 'hero-3'])
            block(
              id: id,
              type: 'hero',
              order: const <String>['hero-1', 'hero-2', 'hero-3'].indexOf(id),
              data: <String, dynamic>{
                'title': 'Bloque $id',
                'blockHeight': 620,
              },
            ),
        ];

    /// Blocks short enough that the handle AND the destination gap fit on one
    /// 430×896 screen. Dragging past the fold needs edge autoscroll, which is
    /// not part of this contract and is not simulated here.
    List<Map<String, dynamic>> shortPage() => <Map<String, dynamic>>[
          block(
            id: 'hero-1',
            type: 'hero',
            order: 0,
            data: const <String, dynamic>{
              'title': 'Taller de bicicletas',
              'blockHeight': 200,
            },
          ),
          block(
            id: 'text-1',
            type: 'text',
            order: 1,
            data: const <String, dynamic>{
              'content': 'Productos destacados',
              'blockHeight': 200,
            },
          ),
          block(
            id: 'text-2',
            type: 'text',
            order: 2,
            data: const <String, dynamic>{
              'content': 'Servicios',
              'blockHeight': 200,
            },
          ),
        ];

    testWidgets('el handle es sólo del bloque seleccionado y cumple 48',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(tallPage(), const <String, dynamic>{})
        ..selectBlock('hero-1');
      await pumpHost(tester, host(provider));

      expect(handleFor('hero-1'), findsOneWidget);
      expect(handleFor('text-1'), findsNothing);
      expect(handleFor('text-2'), findsNothing);
      final size = tester.getSize(handleFor('hero-1'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(handleFor('hero-1')).label.contains('Reordenar'),
        isTrue,
      );

      // Y cambiar la selección mueve el handle, no lo duplica.
      provider.selectBlock('text-1');
      await tester.pump(const Duration(milliseconds: 40));
      expect(handleFor('hero-1'), findsNothing);
      expect(handleFor('text-1'), findsOneWidget);
    });

    testWidgets('un swipe desde el handle desplaza la página y NO reordena',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(overflowingPage(), const <String, dynamic>{})
        ..selectBlock('hero-1');
      await pumpHost(tester, host(provider));
      final before = orderOf(provider);

      final handle = tester.getRect(handleFor('hero-1'));
      expect(handle.height, greaterThanOrEqualTo(48));
      expect(scroller(tester).position.maxScrollExtent, greaterThan(300),
          reason: 'la página desborda de verdad');
      expect(scroller(tester).position.pixels, 0);

      // El dedo empieza EXACTAMENTE en el centro del handle y arrastra sin
      // esperar. Antes del long press el gesto es de la página: si el handle
      // no estuviera bajo el `Scrollable`, este offset no se movería.
      final gesture = await tester.startGesture(
        handle.center,
        kind: PointerDeviceKind.touch,
      );
      for (var step = 0; step < 10; step++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 40));

      expect(scroller(tester).position.pixels, greaterThan(200),
          reason: 'el swipe sobre el handle sigue siendo scroll');
      expect(orderOf(provider), before, reason: 'y no reordena');
      expect(
        find.byKey(websiteReorderSeamKey(0)),
        findsNothing,
        reason: 'sin long press la capa de costuras no existe',
      );
      expect(provider.canUndo, isFalse);
      expect(provider.hasUnsavedChanges, isFalse);
    });

    testWidgets('los marcadores de inserción siguen tocables fuera del cutout',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(shortPage(), const <String, dynamic>{})
        ..selectBlock('hero-1');
      await pumpHost(tester, host(provider));

      final handle = tester.getRect(handleFor('hero-1'));
      final marker = find.byType(WebsiteInsertBlockAffordance).first;
      final band = tester.getRect(marker);

      // El cutout es exactamente el ancho que el handle necesita, no la banda
      // entera: el resto sigue siendo un objetivo de inserción real.
      expect(band.left, greaterThanOrEqualTo(handle.right));
      expect(band.width, greaterThan(200));
      await tester.tap(marker);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(WebsiteBlockCatalogSheet), findsOneWidget);
    });

    testWidgets('long press en el handle + arrastre táctil reordena exacto',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(shortPage(), const <String, dynamic>{})
        ..selectBlock('hero-1');
      await pumpHost(tester, host(provider));
      final before = orderOf(provider);
      expect(before, <String>['hero-1', 'text-1', 'text-2']);

      // Antes del long press no existe ningún seam: el layer no puede tomar
      // un toque ni un swipe.
      expect(find.byKey(websiteReorderSeamKey(0)), findsNothing);

      await dragHandleToSeam(tester, blockId: 'hero-1', insertIndex: 2);

      expect(
        orderOf(provider),
        <String>['text-1', 'hero-1', 'text-2'],
        reason: 'el dedo movió el bloque un lugar hacia abajo',
      );
      // La selección la conserva el owner; el handle viaja con el bloque.
      expect(provider.selectedBlockId, 'hero-1');
      await tester.pump(const Duration(milliseconds: 40));
      expect(handleFor('hero-1'), findsOneWidget);
      // Y el reveal lo publica `reorderBlocks`, no este gesto.
      expect(provider.blockRevealRequest?.blockId, 'hero-1');

      // Un gesto, un undo.
      provider.undo();
      await tester.pump(const Duration(milliseconds: 40));
      expect(orderOf(provider), before);

      // Terminado el arrastre, el layer vuelve a no existir.
      expect(find.byKey(websiteReorderSeamKey(0)), findsNothing);
    });

    testWidgets('el último bloque puede volver al principio', (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(shortPage(), const <String, dynamic>{})
        ..selectBlock('text-2');
      await pumpHost(tester, host(provider));

      await dragHandleToSeam(tester, blockId: 'text-2', insertIndex: 0);

      expect(
        orderOf(provider),
        <String>['text-2', 'hero-1', 'text-1'],
      );
      expect(provider.selectedBlockId, 'text-2');
      provider.undo();
      await tester.pump(const Duration(milliseconds: 40));
      expect(orderOf(provider), <String>['hero-1', 'text-1', 'text-2']);
    });

    testWidgets('soltar sobre su propio borde no escribe nada', (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(shortPage(), const <String, dynamic>{})
        ..selectBlock('hero-1');
      await pumpHost(tester, host(provider));
      final before = orderOf(provider);

      // Sus dos propios bordes: el seam 0 (antes de él) y el 1 (después).
      for (final ownSeam in <int>[0, 1]) {
        final gesture = await tester.startGesture(
          tester.getCenter(handleFor('hero-1')),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 40));
        final seam = find.byKey(websiteReorderSeamKey(ownSeam));
        expect(seam, findsOneWidget);
        await gesture.moveTo(tester.getCenter(seam));
        await tester.pump(const Duration(milliseconds: 40));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 120));

        expect(orderOf(provider), before, reason: 'seam propio $ownSeam');
        expect(
          provider.hasUnsavedChanges,
          isFalse,
          reason: 'un no-movimiento no puede ensuciar el borrador',
        );
      }
    });

    testWidgets(
        'un drag viejo no escribe tras cambiar de página y volver al mismo id',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          shortPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'inicio',
        )
        ..selectBlock('hero-1');
      addTearDown(provider.dispose);
      await pumpHost(tester, host(provider));

      final context = tester.element(find.byType(PageComposition));
      final sourceDocument = provider.document;
      final payload = ExistingWebsiteBlockDragPayload(
        blockId: 'hero-1',
        sessionRevision: sourceDocument.sessionRevision,
        pageId: sourceDocument.pageId,
        pageSlug: sourceDocument.pageSlug,
      );
      final destination = websiteReorderIntent(
        context,
        anchorBlockId: 'text-1',
        side: WebsiteBlockInsertSide.after,
      );

      // ABA: el mismo pageId, slug y contenido reaparecen, pero pertenecen a
      // una sesión nueva. El pointer antiguo no puede adquirir esa sesión.
      provider.enterEditMode(
        shortPage(),
        const <String, dynamic>{},
        pageId: 'page-b',
        pageSlug: 'otra',
      );
      provider.enterEditMode(
        shortPage(),
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'inicio',
      );

      expect(provider.documentSessionRevision,
          isNot(sourceDocument.sessionRevision));
      expect(
        websiteReorderSeamMove(context, payload, destination),
        isFalse,
      );
      expect(orderOf(provider), <String>['hero-1', 'text-1', 'text-2']);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);
    });

    testWidgets('el destino se re-resuelve por identidad al soltar',
        (tester) async {
      useViewport(tester);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          shortPage(),
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'inicio',
        )
        ..selectBlock('hero-1');
      addTearDown(provider.dispose);
      await pumpHost(tester, host(provider));

      final context = tester.element(find.byType(PageComposition));
      final document = provider.document;
      final payload = ExistingWebsiteBlockDragPayload(
        blockId: 'hero-1',
        sessionRevision: document.sessionRevision,
        pageId: document.pageId,
        pageSlug: document.pageSlug,
      );
      final destination = websiteReorderIntent(
        context,
        anchorBlockId: 'text-2',
        side: WebsiteBlockInsertSide.after,
      );

      // Mueve el anchor mientras el feedback está vivo. El commit debe buscar
      // `text-2` otra vez, no usar el seam entero que existía al comenzar.
      provider.reorderBlocks(1, 3);
      expect(orderOf(provider), <String>['hero-1', 'text-2', 'text-1']);

      expect(websiteReorderSeamMove(context, payload, destination), isTrue);
      expect(orderOf(provider), <String>['text-2', 'hero-1', 'text-1']);
      expect(provider.selectedBlockId, 'hero-1');

      provider.undo();
      expect(orderOf(provider), <String>['hero-1', 'text-2', 'text-1']);
    });
  });
}
