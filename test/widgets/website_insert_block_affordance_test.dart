import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_block_catalog.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_catalog_sheet.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_block_sheet.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_contextual_operation_scope.dart';
import 'package:vinabike_erp/public_store/widgets/page_composition.dart';
import 'package:vinabike_erp/public_store/widgets/website_insertion_host.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/workspace_shell_scope.dart';

/// In-page block insertion on the contextual host.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t11 frames **11a** (afordancia de 48
/// en el hueco + hoja `O-05` con búsqueda, categorías y posición) and **11b**
/// (`preservation_contract` de insertar y de cancelar).
void main() {
  Map<String, dynamic> block({
    required String id,
    required String type,
    required int order,
  }) {
    return <String, dynamic>{
      'id': id,
      'block_type': type,
      'order_index': order,
      'sort_order': order,
      'is_visible': true,
      'block_data': const <String, dynamic>{},
    };
  }

  final pageBlocks = <Map<String, dynamic>>[
    block(id: 'b-hero', type: 'hero', order: 0),
    block(id: 'b-products', type: 'products', order: 1),
    block(id: 'b-contact', type: 'contact', order: 2),
  ];

  WebsitePageComposition compositionOf(
    List<Map<String, dynamic>> blocks, {
    WebsitePageCompositionMode mode = WebsitePageCompositionMode.edit,
  }) {
    return WebsitePageComposition.project(
      blocks: blocks,
      mode: mode,
      breakpoint: 'mobile',
    );
  }

  void useViewport(
    WidgetTester tester, {
    required double width,
    double height = 844,
    double bottomViewInset = 0,
  }) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    tester.view.viewInsets = FakeViewPadding(bottom: bottomViewInset);
    tester.view.viewPadding = const FakeViewPadding(bottom: 20);
    tester.view.padding = FakeViewPadding(
      bottom: bottomViewInset > 0 ? 0 : 20,
    );
    addTearDown(tester.view.reset);
  }

  Widget host({
    required WebsitePageComposition composition,
    required double editorWidth,
    void Function(String type, {int? atIndex})? onAddBlock,
    WebsiteEditModeProvider? provider,
    Brightness brightness = Brightness.light,
    double canvasTopInset = 0,
    double contextualDockHeight = 0,
    double nestedNavigatorTopInset = 0,
    ScrollController? outerScrollController,
    double outerEditorTop = 0,
    double outerEditorHeight = 0,
    WebsiteEditorContextualOperationController? contextualOperations,
  }) {
    final canvas = SingleChildScrollView(
      child: PageComposition(
        composition: composition,
        primaryColor: Colors.blue,
        accentColor: Colors.green,
        textColor: Colors.black,
        containerPadding: 16,
        onAddBlock: onAddBlock,
      ),
    );
    final chrome = WebsiteEditorChromeScope(
      editorWidth: editorWidth,
      canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(editorWidth),
      contextualDockHeight: contextualDockHeight,
      child: canvasTopInset == 0
          ? canvas
          : Column(
              children: [
                SizedBox(height: canvasTopInset),
                Expanded(child: canvas),
              ],
            ),
    );
    final nestedEditor = nestedNavigatorTopInset == 0
        ? chrome
        : Padding(
            padding: EdgeInsets.only(top: nestedNavigatorTopInset),
            child: Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
                pageBuilder: (_, __, ___) => chrome,
              ),
            ),
          );
    final body = outerScrollController == null
        ? nestedEditor
        : SingleChildScrollView(
            controller: outerScrollController,
            child: Column(
              children: [
                SizedBox(height: outerEditorTop),
                SizedBox(height: outerEditorHeight, child: nestedEditor),
                const SizedBox(height: 844),
              ],
            ),
          );
    final content = MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: brightness,
      ),
      home: Scaffold(body: body),
    );
    Widget result = provider == null
        ? content
        : ChangeNotifierProvider<WebsiteEditModeProvider>.value(
            value: provider,
            child: content,
          );
    if (contextualOperations != null) {
      result = WebsiteEditorContextualOperationScope(
        controller: contextualOperations,
        child: result,
      );
    }
    return result;
  }

  Future<void> pumpHost(WidgetTester tester, Widget widget) async {
    await tester.runAsync(DeferredEditableBlockRenderer.preload);
    await tester.pumpWidget(widget);
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Finder affordances() => find.byType(WebsiteInsertBlockAffordance);

  /// Bounded pumps instead of `pumpAndSettle`: the block renderer below the
  /// sheet keeps a progress indicator alive while its deferred library and its
  /// images resolve, so "settled" never arrives and the timeout would say
  /// nothing about the surface under test.
  Future<void> settle(WidgetTester tester) async {
    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> openSheet(WidgetTester tester, int affordanceIndex) async {
    final target = affordances().at(affordanceIndex);
    // NO `ensureVisible` here. A marker is chrome in the host's overlay: its
    // layout box sits at that layer's origin while it PAINTS on the seam, so
    // asking the framework to scroll it into view scrolls the canvas back to
    // the top and takes the seam with it. The marker is tapped where it is
    // painted, which is what `getCenter` reports; a caller that needs a seam
    // further down scrolls the canvas itself, like the operator does.
    //
    // Two pumps first: a follower's transform is written during paint, so
    // right after a scroll `getCenter` would still report the previous frame's
    // position and the tap would land on the seam's old place.
    await tester.pump();
    await tester.pump();
    await tester.tap(target, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(WebsiteBlockCatalogSheet.sheetKey),
      findsOneWidget,
      reason: 'la afordancia $affordanceIndex no abrió la hoja',
    );
  }

  /// Picks a family the way an operator does with 24 of them: search first,
  /// then tap. The list is lazy and capped at 60% of the height, so a row
  /// further down is simply not built until it is filtered in.
  Future<void> chooseBlock(
    WidgetTester tester,
    WebsiteBlockType type,
    String query,
  ) async {
    await tester.enterText(
      find.byKey(WebsiteBlockCatalogSheet.searchKey),
      query,
    );
    await tester.pump();
    final row = find.byKey(WebsiteBlockCatalogSheet.rowKeyFor(type));
    expect(row, findsOneWidget);
    await tester.tap(row);
    await settle(tester);
  }

  group('dónde vive la afordancia', () {
    testWidgets('390: contextual a la selección, NO una banda por costura',
        (tester) async {
      useViewport(tester, width: 390);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{});
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          onAddBlock: (type, {atIndex}) {},
        ),
      );

      // Sin selección la página ofrece su final, y NADA más. Tres bloques
      // solían producir cuatro bandas permanentes de 48: un riel a lo largo de
      // la página que además era layout real.
      expect(affordances(), findsOneWidget);

      // Con un bloque seleccionado, sus dos costuras: antes y después de ÉL.
      provider.selectBlock('b-products');
      await tester.pump();
      expect(affordances(), findsNWidgets(2));

      for (final element in affordances().evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(
          size.height,
          WebsiteInsertBlockAffordance.height,
          reason: 'la afordancia debe medir 48 (t11a)',
        );
      }
    });

    testWidgets('834 contextual mantiene la misma composición', (tester) async {
      useViewport(tester, width: 834, height: 700);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-products');
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 834,
          provider: provider,
          onAddBlock: (type, {atIndex}) {},
        ),
      );

      expect(affordances(), findsNWidgets(2));
      expect(
        tester.getSize(affordances().first).height,
        WebsiteInsertBlockAffordance.height,
      );
    });

    testWidgets('página vacía: exactamente UNA', (tester) async {
      useViewport(tester, width: 390);
      // La inserción pasa por el host único, que consulta la identidad del
      // documento para sus guardas; el harness la provee como en producción.
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(const <Map<String, dynamic>>[], const {});
      await pumpHost(
        tester,
        host(
          composition: compositionOf(const <Map<String, dynamic>>[]),
          editorWidth: 390,
          provider: provider,
          onAddBlock: (type, {atIndex}) {},
        ),
      );

      expect(affordances(), findsOneWidget);
    });

    testWidgets('1440 con pane: ninguna, el flujo de arrastre se conserva',
        (tester) async {
      useViewport(tester, width: 1440, height: 900);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-hero');
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 1440,
          provider: provider,
          onAddBlock: (type, {atIndex}) {},
        ),
      );

      expect(affordances(), findsNothing);
      // El botón grande de fin de página del host puntero sigue ahí.
      expect(find.text('Agregar nuevo bloque'), findsOneWidget);
    });

    testWidgets('Preview y Público no muestran ninguna', (tester) async {
      for (final mode in const [
        WebsitePageCompositionMode.preview,
        WebsitePageCompositionMode.public,
      ]) {
        useViewport(tester, width: 390);
        await pumpHost(
          tester,
          host(
            composition: compositionOf(pageBlocks, mode: mode),
            editorWidth: 390,
            onAddBlock: (type, {atIndex}) {},
          ),
        );
        expect(affordances(), findsNothing, reason: '$mode no es Edit');
      }
    });
  });

  group('la hoja y la exactitud del índice', () {
    testWidgets('la primera afordancia inserta ANTES del primer bloque',
        (tester) async {
      useViewport(tester, width: 390);
      final calls = <(String, int?)>[];
      // La costura de "antes del primer bloque" pertenece a ese bloque, así
      // que se ofrece cuando ese bloque está seleccionado.
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-hero');
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          onAddBlock: (type, {atIndex}) => calls.add((type, atIndex)),
        ),
      );

      await openSheet(tester, 0);
      expect(find.byKey(WebsiteBlockCatalogSheet.sheetKey), findsOneWidget);
      expect(find.text('Antes de'), findsOneWidget);

      await chooseBlock(tester, WebsiteBlockType.text, 'text');

      expect(calls, [('text', 0)]);
    });

    testWidgets('la afordancia del hueco N inserta DESPUÉS del bloque N',
        (tester) async {
      useViewport(tester, width: 390);
      final calls = <(String, int?)>[];
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-hero');
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          onAddBlock: (type, {atIndex}) => calls.add((type, atIndex)),
        ),
      );

      // Con el primer bloque seleccionado, el marcador 1 es su costura
      // `Después de`: el hueco inmediatamente bajo ese bloque.
      await openSheet(tester, 1);
      await chooseBlock(tester, WebsiteBlockType.text, 'text');

      expect(calls, [('text', 1)]);
    });

    testWidgets('la última inserta al final', (tester) async {
      useViewport(tester, width: 390);
      final calls = <(String, int?)>[];
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{});
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          onAddBlock: (type, {atIndex}) => calls.add((type, atIndex)),
        ),
      );

      // Sin selección la página ofrece exactamente su final. El marcador sigue
      // a la costura final, así que se alcanza llegando al final de la página
      // — que es exactamente lo que hace el operador para agregar al final.
      expect(affordances(), findsOneWidget);
      // El scroll del LIENZO, no el de un bloque: un `first` genérico puede
      // encontrar un scroll interno y no mover la página.
      await tester.drag(
        find
            .ancestor(
              of: find.byType(PageComposition),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
        const Offset(0, -4000),
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      // El marcador de cierre queda ENTERO sobre el borde de la página.
      expect(
          tester.getRect(affordances().first).bottom, lessThanOrEqualTo(844));
      await openSheet(tester, 0);
      await chooseBlock(tester, WebsiteBlockType.text, 'text');

      expect(calls, [('text', 3)]);
    });

    testWidgets('cambiar la posición cambia el índice, y elegir llama UNA vez',
        (tester) async {
      useViewport(tester, width: 390);
      final calls = <(String, int?)>[];
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{});
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          onAddBlock: (type, {atIndex}) => calls.add((type, atIndex)),
        ),
      );

      // La costura «Después de» pertenece al bloque seleccionado.
      provider.selectBlock('b-hero');
      await tester.pump();
      await tester.pump();

      await openSheet(tester, 1);
      // Nace en «Después de» el primer bloque ⇒ 1. Al pasar a «Antes de» ⇒ 0.
      await tester.tap(find.text('Antes de'));
      await tester.pump();
      await chooseBlock(tester, WebsiteBlockType.text, 'text');

      expect(calls, hasLength(1));
      expect(calls.single, ('text', 0));
    });

    testWidgets('cancelar es un no-op exacto', (tester) async {
      useViewport(tester, width: 390);
      final calls = <(String, int?)>[];
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-hero');
      final blocksBefore = provider.blocks;
      final dirtyBefore = provider.hasUnsavedChanges;
      final canUndoBefore = provider.canUndo;
      final selectionBefore = provider.selectedBlockId;

      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          onAddBlock: (type, {atIndex}) => calls.add((type, atIndex)),
        ),
      );

      await openSheet(tester, 1);
      await tester.tap(find.byKey(WebsiteBlockCatalogSheet.cancelKey));
      await settle(tester);

      expect(calls, isEmpty);
      expect(provider.blocks, blocksBefore);
      expect(provider.hasUnsavedChanges, dirtyBefore);
      expect(provider.canUndo, canUndoBefore);
      expect(provider.selectedBlockId, selectionBefore);
    });

    testWidgets('una familia inerte no puede elegirse y explica por qué',
        (tester) async {
      useViewport(tester, width: 390);
      final calls = <(String, int?)>[];
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-hero');
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          onAddBlock: (type, {atIndex}) => calls.add((type, atIndex)),
        ),
      );

      await openSheet(tester, 1);
      await tester.enterText(
        find.byKey(WebsiteBlockCatalogSheet.searchKey),
        'footer',
      );
      await tester.pump();

      final footerRow = find
          .byKey(WebsiteBlockCatalogSheet.rowKeyFor(WebsiteBlockType.footer));
      expect(footerRow, findsOneWidget);
      expect(tester.widget<InkWell>(footerRow).onTap, isNull);
      expect(
        find.textContaining('pie de página', findRichText: true),
        findsWidgets,
      );

      await tester.tap(footerRow, warnIfMissed: false);
      await settle(tester);
      expect(calls, isEmpty);
    });

    testWidgets('buscar filtra y el vacío se nombra', (tester) async {
      useViewport(tester, width: 390);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-hero');
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          onAddBlock: (type, {atIndex}) {},
        ),
      );

      await openSheet(tester, 1);
      await tester.enterText(
        find.byKey(WebsiteBlockCatalogSheet.searchKey),
        'zzzz-no-existe',
      );
      await tester.pump();

      expect(find.byKey(WebsiteBlockCatalogSheet.emptyKey), findsOneWidget);
    });

    testWidgets('E-02: el target real mide 48 aunque la píldora pinte 36',
        (tester) async {
      // Regresión del defecto: el chip vivía dentro de un `SizedBox(height:36)`
      // y ese recorte se comía su redirector de toque. El 48 exterior era
      // espacio vacío, no área tocable. Envolver un control por fuera nunca
      // agranda su target; sólo el control puede.
      for (final brightness in Brightness.values) {
        var taps = 0;
        String? lastCategory;
        useViewport(tester, width: 390);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.resolve(
              preset: AppearancePresets.pacific,
              brightness: brightness,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: WebsiteBlockCategoryChips(
                  categories: const ['Todos', 'Estructura'],
                  selected: 'Todos',
                  onSelected: (category) {
                    taps++;
                    lastCategory = category;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final chip =
            find.byKey(WebsiteBlockCatalogSheet.chipKeyFor('Estructura'));
        final target = tester.getRect(chip);

        // 1) El target interactivo y semántico real llega a 48.
        expect(
          target.height,
          WebsiteBlockCatalogSheetGeometry.chipHitHeight,
          reason: 'target real en $brightness',
        );

        // 2) La píldora pintada sigue en 36.
        final painted = tester.getSize(
          find.descendant(of: chip, matching: find.byType(Material)).first,
        );
        expect(
          painted.height,
          WebsiteBlockCatalogSheetGeometry.chipHeight,
          reason: 'píldora pintada en $brightness',
        );

        // 3) Un toque DENTRO de los 48 y FUERA de la banda de 36 responde, y
        //    responde exactamente una vez: hay un solo owner del tap.
        final bandTop = target.center.dy - painted.height / 2;
        final outsideBand = target.top + (bandTop - target.top) / 2;
        expect(
          outsideBand,
          lessThan(bandTop),
          reason: 'el punto de toque debe quedar fuera de lo pintado',
        );
        await tester.tapAt(Offset(target.center.dx, outsideBand));
        await tester.pump();

        expect(taps, 1, reason: 'un tap ⇒ una acción en $brightness');
        expect(lastCategory, 'Estructura');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('las categorías están y filtran', (tester) async {
      useViewport(tester, width: 390);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-hero');
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          onAddBlock: (type, {atIndex}) {},
        ),
      );

      await openSheet(tester, 1);
      expect(
        find.byKey(
          WebsiteBlockCatalogSheet.chipKeyFor(WebsiteBlockCatalog.allCategory),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(WebsiteBlockCatalogSheet.chipKeyFor('Estructura')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(WebsiteBlockCatalogSheet.chipKeyFor('Estructura')),
      );
      await tester.pump();

      expect(
        find.byKey(WebsiteBlockCatalogSheet.rowKeyFor(WebsiteBlockType.hero)),
        findsOneWidget,
      );
      expect(
        find.byKey(WebsiteBlockCatalogSheet.rowKeyFor(WebsiteBlockType.text)),
        findsNothing,
      );
    });

    testWidgets('la hoja no supera el 60% ni con el teclado abierto',
        (tester) async {
      for (final inset in const <double>[0, 292]) {
        useViewport(tester, width: 390, bottomViewInset: inset);
        final provider = WebsiteEditModeProvider()
          ..enterEditMode(pageBlocks, const <String, dynamic>{})
          ..selectBlock('b-hero');
        await pumpHost(
          tester,
          host(
            composition: compositionOf(pageBlocks),
            editorWidth: 390,
            provider: provider,
            onAddBlock: (type, {atIndex}) {},
          ),
        );

        await openSheet(tester, 1);
        final cap = tester
            .widget<ConstrainedBox>(
              find
                  .ancestor(
                    of: find.byKey(WebsiteBlockCatalogSheet.sheetKey),
                    matching: find.byType(ConstrainedBox),
                  )
                  .first,
            )
            .constraints
            .maxHeight;
        expect(
          cap,
          closeTo(
            WebsiteBlockCatalogSheetGeometry.maxHeightFor(844 - inset),
            0.5,
          ),
          reason: 'con viewInsets $inset',
        );
        expect(
          tester.getSize(find.byKey(WebsiteBlockCatalogSheet.sheetKey)).height,
          lessThanOrEqualTo(cap + 0.5),
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(WebsiteBlockCatalogSheet.cancelKey));
        await settle(tester);
      }
    });

    testWidgets('claro y oscuro montan la misma hoja sin desbordar',
        (tester) async {
      for (final brightness in Brightness.values) {
        useViewport(tester, width: 390);
        final provider = WebsiteEditModeProvider()
          ..enterEditMode(pageBlocks, const <String, dynamic>{})
          ..selectBlock('b-hero');
        await pumpHost(
          tester,
          host(
            composition: compositionOf(pageBlocks),
            editorWidth: 390,
            provider: provider,
            brightness: brightness,
            onAddBlock: (type, {atIndex}) {},
          ),
        );

        await openSheet(tester, 1);
        expect(find.byKey(WebsiteBlockCatalogSheet.sheetKey), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'desborda en $brightness',
        );

        await tester.tap(find.byKey(WebsiteBlockCatalogSheet.cancelKey));
        await settle(tester);
      }
    });
  });

  group('integración con el provider canónico', () {
    testWidgets(
        'insertar selecciona el bloque nuevo, reordena sort_order y '
        'deja EXACTAMENTE un paso de deshacer', (tester) async {
      useViewport(tester, width: 390);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-hero');
      expect(provider.canUndo, isFalse);

      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          // El callback canónico, tal como lo cablea el host real.
          onAddBlock: (type, {atIndex}) =>
              provider.addBlock(type, atIndex: atIndex),
        ),
      );

      await tester.tap(affordances().at(1), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await chooseBlock(tester, WebsiteBlockType.text, 'text');

      final ids = provider.blocks.map((block) => block['id']).toList();
      expect(ids, hasLength(4));
      expect(ids[0], 'b-hero');
      expect(ids[2], 'b-products');
      // El nuevo quedó en la posición pedida y seleccionado.
      expect(provider.selectedBlockId, ids[1]);
      expect(provider.blocks[1]['block_type'], 'text');
      // sort_order reindexado sin huecos.
      expect(
        provider.blocks.map((block) => block['sort_order']).toList(),
        [0, 1, 2, 3],
      );

      // Un solo paso: deshacer devuelve la página exacta de antes.
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(
        provider.blocks.map((block) => block['id']).toList(),
        ['b-hero', 'b-products', 'b-contact'],
      );
      expect(provider.canUndo, isFalse);
    });
  });
  group('el host es el único owner de la operación', () {
    test('las leases anidadas liberan el chrome sólo al final', () {
      final controller = WebsiteEditorContextualOperationController();
      addTearDown(controller.dispose);
      final first = controller.acquire();
      final second = controller.acquire();

      expect(controller.isActive, isTrue);
      expect(controller.depth, 2);
      first.release();
      first.release();
      expect(controller.isActive, isTrue);
      expect(controller.depth, 1);
      second.release();
      expect(controller.isActive, isFalse);
      expect(controller.depth, 0);
    });

    testWidgets('O-05 suspende el chrome inline de inserción', (tester) async {
      useViewport(tester, width: 390);
      final contextualOperations = WebsiteEditorContextualOperationController();
      addTearDown(contextualOperations.dispose);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-products');
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          contextualOperations: contextualOperations,
          onAddBlock: (type, {atIndex}) {},
        ),
      );

      expect(affordances(), findsNWidgets(2));
      final canvasContext = tester.element(find.byType(PageComposition));
      showWebsiteContextualSheet<void>(
        context: canvasContext,
        builder: (_) => const SizedBox(height: 300),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        affordances(),
        findsNothing,
        reason: 'el root Overlay no puede pintar marcadores sobre una hoja',
      );
      expect(contextualOperations.isActive, isTrue);

      Navigator.of(canvasContext).pop();
      await settle(tester);
      expect(affordances(), findsNWidgets(2));
      expect(contextualOperations.isActive, isFalse);
    });

    testWidgets('la geometría del lienzo no cambia por existir marcadores',
        (tester) async {
      // El aislamiento que pide el gate: MISMO renderer de Edit, mismos
      // bloques, con y sin `onAddBlock`. Lo único que difiere es que existan
      // afordancias, así que cualquier diferencia de rects es culpa de ellas.
      useViewport(tester, width: 390);
      Future<List<Rect>> rectsWith({required bool withAffordances}) async {
        final provider = WebsiteEditModeProvider()
          ..enterEditMode(pageBlocks, const <String, dynamic>{})
          ..selectBlock('b-products');
        await pumpHost(
          tester,
          host(
            composition: compositionOf(pageBlocks),
            editorWidth: 390,
            provider: provider,
            onAddBlock: withAffordances ? (type, {atIndex}) {} : null,
          ),
        );
        return [
          for (final block in pageBlocks)
            tester.getRect(
              find.byKey(
                ValueKey<String>('page-composition-block-${block['id']}'),
              ),
            ),
        ];
      }

      final without = await rectsWith(withAffordances: false);
      final with_ = await rectsWith(withAffordances: true);
      expect(with_, without,
          reason: 'los marcadores no pueden mover un solo pixel del documento');
    });

    testWidgets('doble toque abre UNA sola hoja', (tester) async {
      useViewport(tester, width: 390);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-hero');
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          onAddBlock: (type, {atIndex}) {},
        ),
      );

      final target = affordances().first;
      await tester.pump();
      await tester.tap(target, warnIfMissed: false);
      await tester.tap(target, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(WebsiteBlockCatalogSheet.sheetKey), findsOneWidget);
    });

    testWidgets('si el documento cambia mientras la hoja está abierta, aborta',
        (tester) async {
      useViewport(tester, width: 390);
      final calls = <(String, int?)>[];
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{}, pageId: 'page-a')
        ..selectBlock('b-hero');
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          onAddBlock: (type, {atIndex}) => calls.add((type, atIndex)),
        ),
      );

      await openSheet(tester, 0);
      // Otra página bajo la hoja abierta: el índice que nació con el marcador
      // ya no significa nada, y un append «a donde sea» sería una escritura
      // fail-open en una costura que el operador nunca señaló.
      provider.openEditorDocument(
        const <Map<String, dynamic>>[
          {'id': 'otro', 'block_type': 'text', 'block_data': {}},
        ],
        const <String, dynamic>{},
        mode: WebsiteEditorMode.edit,
        pageId: 'page-b',
      );
      await tester.pump();
      await chooseBlock(tester, WebsiteBlockType.text, 'text');

      expect(calls, isEmpty);
    });

    testWidgets(
        'el overlay sólo pinta y recibe taps entre topbar y dock medidos',
        (tester) async {
      useViewport(tester, width: 390);
      final topBand = WebsiteEditorChromeGeometry.topBandHeightFor(
        WebsiteEditorChromeGeometry.publishedPhoneSafeAreaTop,
      );
      // This is a measured input supplied by the shell, not a visual value
      // chosen by the insertion host. Reusing the published bar height keeps
      // the assertion readable while proving the cap responds to its owner.
      const dockBand = WebsiteEditorChromeGeometry.topBarHeight;
      const workspaceBand = WorkspaceShellScope.workspaceBarHeight;
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-hero');
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          canvasTopInset: topBand,
          contextualDockHeight: dockBand,
          nestedNavigatorTopInset: workspaceBand,
          onAddBlock: (type, {atIndex}) {},
        ),
      );

      final hostState = tester.state<WebsiteInsertionHostState>(
        find.byType(WebsiteInsertionHost),
      );
      expect(
        hostState.interactiveViewportRect,
        Rect.fromLTRB(0, workspaceBand + topBand, 390, 844 - dockBand),
      );

      // The first marker straddles the first block's leading seam. Its upper
      // half exists geometrically behind the editor bar, but the viewport clip
      // must remove it from both paint and hit testing.
      await tester.tapAt(Offset(195, workspaceBand + topBand - 12));
      await tester.pump();
      expect(find.byKey(WebsiteBlockCatalogSheet.sheetKey), findsNothing);
      expect(hostState.isResolving, isFalse);

      // The same marker remains interactive on the canvas side of the seam.
      await tester.tapAt(Offset(195, workspaceBand + topBand + 12));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(WebsiteBlockCatalogSheet.sheetKey), findsOneWidget);
    });

    testWidgets('intersecta viewports anidados y sigue el scroll exterior',
        (tester) async {
      useViewport(tester, width: 390);
      final outer = ScrollController();
      addTearDown(outer.dispose);
      final topBand = WebsiteEditorChromeGeometry.topBandHeightFor(
        WebsiteEditorChromeGeometry.publishedPhoneSafeAreaTop,
      );
      const dockBand = WebsiteEditorChromeGeometry.topBarHeight;
      const editorTop = 120.0;
      const editorHeight = 700.0;
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{})
        ..selectBlock('b-hero');
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 390,
          provider: provider,
          canvasTopInset: topBand,
          contextualDockHeight: dockBand,
          outerScrollController: outer,
          outerEditorTop: editorTop,
          outerEditorHeight: editorHeight,
          onAddBlock: (type, {atIndex}) {},
        ),
      );

      final state = tester.state<WebsiteInsertionHostState>(
        find.byType(WebsiteInsertionHost),
      );
      // Inner canvas: 120 + 92 .. 120 + 700. The measured dock caps its
      // bottom at 844 - 48.
      expect(
        state.interactiveViewportRect,
        Rect.fromLTRB(0, editorTop + topBand, 390, 844 - dockBand),
      );

      // Moving the INNER viewport with an OUTER ScrollPosition must refresh
      // the clip even though WebsiteInsertionHost itself did not rebuild.
      outer.jumpTo(180);
      await tester.pump();
      await tester.pump();

      expect(
        state.interactiveViewportRect,
        Rect.fromLTRB(
          0,
          editorTop - 180 + topBand,
          390,
          editorTop - 180 + editorHeight,
        ),
      );
    });
  });
}
