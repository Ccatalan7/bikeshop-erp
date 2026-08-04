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
import 'package:vinabike_erp/public_store/widgets/page_composition.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

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
    required void Function(String type, {int? atIndex}) onAddBlock,
    WebsiteEditModeProvider? provider,
    Brightness brightness = Brightness.light,
  }) {
    final content = MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: brightness,
      ),
      home: Scaffold(
        body: WebsiteEditorChromeScope(
          editorWidth: editorWidth,
          canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(editorWidth),
          child: SingleChildScrollView(
            child: PageComposition(
              composition: composition,
              primaryColor: Colors.blue,
              accentColor: Colors.green,
              textColor: Colors.black,
              containerPadding: 16,
              onAddBlock: onAddBlock,
            ),
          ),
        ),
      ),
    );
    if (provider == null) return content;
    return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
      value: provider,
      child: content,
    );
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
    // A tall page scrolls: an affordance below the fold has to be brought into
    // view before it can be tapped, exactly as the operator would.
    await tester.ensureVisible(target);
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
    testWidgets('390: una al inicio, una entre bloques y una al final',
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

      // 3 bloques ⇒ 4 huecos: inicio, dos intermedios y final.
      expect(affordances(), findsNWidgets(4));
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
        ..enterEditMode(pageBlocks, const <String, dynamic>{});
      await pumpHost(
        tester,
        host(
          composition: compositionOf(pageBlocks),
          editorWidth: 834,
          provider: provider,
          onAddBlock: (type, {atIndex}) {},
        ),
      );

      expect(affordances(), findsNWidgets(4));
      expect(
        tester.getSize(affordances().first).height,
        WebsiteInsertBlockAffordance.height,
      );
    });

    testWidgets('página vacía: exactamente UNA', (tester) async {
      useViewport(tester, width: 390);
      await pumpHost(
        tester,
        host(
          composition: compositionOf(const <Map<String, dynamic>>[]),
          editorWidth: 390,
          onAddBlock: (type, {atIndex}) {},
        ),
      );

      expect(affordances(), findsOneWidget);
    });

    testWidgets('1440 con pane: ninguna, el flujo de arrastre se conserva',
        (tester) async {
      useViewport(tester, width: 1440, height: 900);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(pageBlocks, const <String, dynamic>{});
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

      // Índice 1 = el hueco inmediatamente bajo el primer bloque.
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

      await openSheet(tester, 3);
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
        ..enterEditMode(pageBlocks, const <String, dynamic>{});
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
          ..enterEditMode(pageBlocks, const <String, dynamic>{});
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
        ..enterEditMode(pageBlocks, const <String, dynamic>{});
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
}
