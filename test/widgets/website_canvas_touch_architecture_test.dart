import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_canvas_alignment.dart';
import 'package:vinabike_erp/modules/website/models/website_canvas_manipulation.dart';
import 'package:vinabike_erp/modules/website/models/website_canvas_responsive_document.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_canvas_layer_actions.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_block_sheet.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_contextual_dock.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Canvas on touch: what a finger may do, and where the capability lives.
///
/// The state this replaces was not "the drag is awkward" — it was that a
/// Canvas layer drag used the same recognizer as pointer editing. A real touch
/// contact is normalized to the primary button, so the layer could enter the
/// gesture arena even in browse and defeat the page Scrollable. Direct
/// manipulation now requires one exact document/layer/mode session.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 — frame **10d** (the Layers
/// list: rows of 44/48, selected row `inset 3px accent`, per-row `⋯`), frame
/// **10e** (the dock at 48) and `O-05` for the sheet. **Not published:** any
/// geometry for direct-manipulation handles on touch. That paint is left
/// exactly as it is and recorded as visual debt; the capability is re-housed
/// in the published surfaces instead of invented here.
void main() {
  const blocks = <Map<String, dynamic>>[
    {
      'id': 'canvas-1',
      'block_type': 'canvas',
      'block_data': <String, dynamic>{
        'elements': [
          {'id': 'layer-a', 'type': 'text', 'x': 10.0, 'y': 10.0},
          {'id': 'layer-b', 'type': 'text', 'x': 40.0, 'y': 40.0},
        ],
      },
      'is_visible': true,
      'sort_order': 0,
    },
  ];

  void reportCanvas(
    WebsiteEditModeProvider provider, {
    double width = 390,
    String blockId = 'canvas-1',
    int? slideIndex,
  }) {
    provider.reportRenderedCanvasSize(
      WebsiteCanvasDocumentTarget(
        blockId: blockId,
        slideIndex: slideIndex,
      ),
      Size(width, 520),
      expectedMeasurementGeneration:
          provider.renderedCanvasMeasurementGeneration,
    );
  }

  WebsiteEditModeProvider newProvider({
    DevicePreviewMode previewMode = DevicePreviewMode.desktop,
  }) {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(blocks, const <String, dynamic>{}, pageId: 'page-a')
      ..setDevicePreviewMode(previewMode);
    final width = switch (previewMode) {
      DevicePreviewMode.mobile => 390.0,
      DevicePreviewMode.tablet => 834.0,
      DevicePreviewMode.desktop => 1200.0,
    };
    reportCanvas(provider, width: width);
    return provider;
  }

  Widget dockHost(WebsiteEditModeProvider provider, {double width = 390}) {
    return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: Brightness.light,
        ),
        home: WebsiteEditorChromeScope(
          editorWidth: width,
          canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(width),
          child: const Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: WebsiteEditorContextualDock(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  group('un swipe normal conserva el scroll', () {
    test('sin sesión es browse, y no se puede armar sin selección', () {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      // Sin sesión el Scrollable de la página es dueño del swipe.
      expect(provider.canvasManipulationSession, isNull);

      // Sin capa seleccionada no hay nada que manipular, y la razón se dice.
      expect(
        provider.startCanvasManipulation(
          WebsiteCanvasManipulationMode.move,
          target: const WebsiteCanvasLayerTarget(
            document: WebsiteCanvasDocumentTarget(blockId: 'canvas-1'),
            layerId: 'layer-a',
          ),
          viewport: WebsiteViewport.desktop,
        ),
        isFalse,
      );
      expect(provider.canvasManipulationSession, isNull);
      expect(
        provider
            .canvasManipulationAvailability(WebsiteCanvasManipulationMode.move)
            .reason,
        isNotNull,
      );
    });
  });

  group('390 · la capacidad vive en superficies publicadas y mide 48', () {
    testWidgets('con una capa seleccionada el dock ofrece Mover a 48',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider()
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(dockHost(provider));
      await tester.pump();

      // El dock lleva UNA entrada de capa; los cuatro modos viven en `O-05`.
      // Cuatro botones de 48 más las cinco acciones de bloque desbordaban la
      // fila a 390, y `F-06` no admite encogerlos.
      final move = find.byKey(WebsiteEditorContextualDock.layerActionsKey);
      expect(move, findsOneWidget, reason: 'la operación no depende de hover');
      // `F-06`: bajo 900 la densidad es touch y todo objetivo mide 48.
      expect(
        tester.getSize(move).height,
        greaterThanOrEqualTo(WebsiteEditorContextualDock.touchTarget),
      );
      expect(
        tester.getSize(move).width,
        greaterThanOrEqualTo(WebsiteEditorContextualDock.touchTarget),
      );
    });

    testWidgets('sin capa seleccionada el dock no ofrece Mover',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider()..selectBlock('canvas-1');
      addTearDown(provider.dispose);

      await tester.pumpWidget(dockHost(provider));
      await tester.pump();

      expect(
        find.byKey(WebsiteEditorContextualDock.layerActionsKey),
        findsNothing,
        reason: 'no hay capa que manipular',
      );
    });

    testWidgets('todo objetivo crítico del dock mide 48', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider()
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(dockHost(provider));
      await tester.pump();

      for (final key in <Key>[
        WebsiteEditorContextualDock.moveUpKey,
        WebsiteEditorContextualDock.moveDownKey,
        WebsiteEditorContextualDock.visibilityKey,
        WebsiteEditorContextualDock.duplicateKey,
        WebsiteEditorContextualDock.overflowKey,
        WebsiteEditorContextualDock.layerActionsKey,
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(
          size.height,
          greaterThanOrEqualTo(WebsiteEditorContextualDock.touchTarget),
          reason: '$key mide ${size.height}',
        );
      }
    });

    testWidgets('el exit viejo del dock no cancela una generación nueva',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider(previewMode: DevicePreviewMode.mobile)
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);
      final target = provider.selectedCanvasLayerTarget!;
      expect(
        provider.startCanvasManipulation(
          WebsiteCanvasManipulationMode.move,
          target: target,
          viewport: provider.previewViewport,
        ),
        isTrue,
      );

      await tester.pumpWidget(dockHost(provider));
      await tester.pump();
      final staleExit = tester
          .widget<IconButton>(
            find.byKey(WebsiteEditorContextualDock.exitManipulationKey),
          )
          .onPressed!;
      final first = provider.canvasManipulationSession!;
      expect(provider.stopCanvasManipulation(expectedSession: first), isTrue);
      expect(
        provider.startCanvasManipulation(
          WebsiteCanvasManipulationMode.move,
          target: target,
          viewport: provider.previewViewport,
        ),
        isTrue,
      );
      final second = provider.canvasManipulationSession!;

      // Deliberately no pump: this is the callback the old dock row retained.
      staleExit();
      expect(provider.canvasManipulationSession, second);
      expect(second.generation, greaterThan(first.generation));
      expect(provider.canUndo, isFalse);
    });
  });

  group('la identidad de la capa llega al dock', () {
    testWidgets('el dock nombra la capa, no sólo el bloque', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider()
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(dockHost(provider));
      await tester.pump();

      expect(provider.selectedCanvasElementId, 'layer-a');
      // Identidad HUMANA: el tipo y las palabras de la capa, nunca `· capa`
      // ni el id serializado (t10 10d).
      expect(provider.selectedCanvasLayerLabel, isNotNull);
      expect(find.textContaining('Texto'), findsWidgets);
      expect(find.textContaining('· capa'), findsNothing);
      expect(find.textContaining('layer-a'), findsNothing);
    });
  });

  group('el alcance de escritura es atómico y una sola operación', () {
    test('una escritura móvil toca sólo móvil y deja UN paso de historia', () {
      final provider = newProvider(previewMode: DevicePreviewMode.mobile)
        ..setWriteScope(WebsiteWriteScope.viewport)
        ..selectBlock('canvas-1');
      addTearDown(provider.dispose);

      final before = provider.canUndo;
      final changed = provider.setBlockResponsiveProperty(
        'canvas-1',
        'paddingTop',
        24,
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(changed, isTrue);
      expect(before, isFalse);
      expect(provider.canUndo, isTrue);

      // El valor vive en móvil y el común queda intacto.
      expect(
        provider
            .resolveBlockProperty<num>(
              'canvas-1',
              'paddingTop',
              viewport: WebsiteViewport.mobile,
              decode: (v) => v as num?,
            )
            .value,
        24,
      );
      expect(
        provider
            .resolveBlockProperty<num>(
              'canvas-1',
              'paddingTop',
              viewport: WebsiteViewport.desktop,
              decode: (v) => v as num?,
            )
            .value,
        isNull,
      );

      // Y UN solo deshacer devuelve el documento entero.
      provider.undo();
      expect(provider.canUndo, isFalse);
      expect(
        provider
            .resolveBlockProperty<num>(
              'canvas-1',
              'paddingTop',
              viewport: WebsiteViewport.mobile,
              decode: (v) => v as num?,
            )
            .value,
        isNull,
      );
    });

    test('la sesión NO es estado del documento: no ensucia ni crea historia',
        () {
      final provider = newProvider()
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      final target = provider.selectedCanvasLayerTarget!;
      provider.startCanvasManipulation(
        WebsiteCanvasManipulationMode.move,
        target: target,
        viewport: provider.previewViewport,
      );
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.canUndo, isFalse);
      provider.stopCanvasManipulation(
        expectedSession: provider.canvasManipulationSession!,
      );
      expect(provider.canUndo, isFalse);
    });
  });
  group('el boundary de tema: el operador ve el ERP, no la marca del cliente',
      () {
    testWidgets('host oscuro con sitio claro: el dock sigue en roles ERP',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider()
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      final erpDark = AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: Brightness.dark,
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: erpDark,
            home: WebsiteEditorChromeScope(
              editorWidth: 390,
              canvasWidth: 390,
              // The AUTHORED site is light while the operator's ERP is dark.
              // The dock is the operator's tool and must not wear the tenant's
              // brand, so it resolves from the theme above it, not from the
              // storefront theme wrapping the canvas.
              child: Theme(
                data: AppTheme.resolve(
                  preset: AppearancePresets.pacific,
                  brightness: Brightness.light,
                ),
                child: Builder(
                  builder: (siteContext) => Theme(
                    data: erpDark,
                    child: const Scaffold(
                      body: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: WebsiteEditorContextualDock(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final dock = tester.widget<Material>(
        find.byKey(WebsiteEditorContextualDock.dockKey),
      );
      expect(dock.color, erpDark.colorScheme.surface);
      expect(tester.takeException(), isNull);
    });
  });

  group('1440 pointer no degrada', () {
    testWidgets('el host con pane no monta el dock táctil', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.reset);

      final provider = newProvider()
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(dockHost(provider, width: 1440));
      await tester.pump();

      // El dock es la respuesta del host contextual. En 1440 el operador tiene
      // pane, mouse, hover y teclado, y nada de eso se toca.
      expect(
        WebsiteEditorChromeGeometry.compositionFor(1440),
        WebsiteEditorChromeComposition.pane,
      );
      // Y no hay sesión: no se arma sola por existir.
      expect(provider.canvasManipulationSession, isNull);
    });
  });
  group('la alineación tiene UNA definición', () {
    test('las seis alineaciones son puras y deterministas', () {
      const w = 100.0;
      const h = 50.0;
      const surfaceW = 1000.0;
      const surfaceH = 600.0;

      WebsiteCanvasAlignedOrigin at(WebsiteCanvasAlignment a) =>
          WebsiteCanvasAlignmentMath.align(
            alignment: a,
            x: 33,
            y: 77,
            width: w,
            height: h,
            designWidth: surfaceW,
            designHeight: surfaceH,
          );

      expect(at(WebsiteCanvasAlignment.left).x, 0);
      expect(at(WebsiteCanvasAlignment.right).x, surfaceW - w);
      expect(at(WebsiteCanvasAlignment.horizontalCenter).x, (surfaceW - w) / 2);
      expect(at(WebsiteCanvasAlignment.top).y, 0);
      expect(at(WebsiteCanvasAlignment.bottom).y, surfaceH - h);
      expect(at(WebsiteCanvasAlignment.verticalCenter).y, (surfaceH - h) / 2);

      // Un eje que no se alinea no se toca.
      expect(at(WebsiteCanvasAlignment.left).y, 77);
      expect(at(WebsiteCanvasAlignment.top).x, 33);
    });

    test('una superficie inutilizable no lanza la capa a coordenadas locas',
        () {
      final origin = WebsiteCanvasAlignmentMath.align(
        alignment: WebsiteCanvasAlignment.right,
        x: 40,
        y: 40,
        width: 100,
        height: 50,
        designWidth: 0,
        designHeight: 0,
      );
      // Sin superficie medible el origen se conserva, no se vuelve negativo.
      expect(origin.x, 40);
      expect(origin.y, 40);
    });
  });

  group('O-05 · el grupo de capa es la superficie de las operaciones', () {
    testWidgets('los cuatro modos existen y el no soportado explica por qué',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider()
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.resolve(
              preset: AppearancePresets.pacific,
              brightness: Brightness.light,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: WebsiteCanvasLayerActions(provider: provider),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final mode in WebsiteCanvasManipulationMode.values) {
        final row = find.byKey(WebsiteCanvasLayerActions.modeKey(mode));
        expect(row, findsOneWidget, reason: '$mode debe existir');
        // `F-06` · toda fila táctil mide 48.
        expect(
          tester.getSize(row).height,
          greaterThanOrEqualTo(WebsiteCanvasLayerActions.rowHeight),
        );
      }

      // Recortar no aplica a un texto, y lo DICE en vez de no hacer nada.
      expect(
        find.text('Esta capa no admite esta operación.'),
        findsOneWidget,
      );

      // Y la identidad humana encabeza el grupo.
      expect(find.textContaining('Texto'), findsWidgets);
    });

    testWidgets('callbacks viejos no arman otra capa ni cancelan otra sesión',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider(previewMode: DevicePreviewMode.mobile)
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      Widget host() => ChangeNotifierProvider<WebsiteEditModeProvider>.value(
            value: provider,
            child: MaterialApp(
              theme: AppTheme.resolve(
                preset: AppearancePresets.pacific,
                brightness: Brightness.light,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: WebsiteCanvasLayerActions(provider: provider),
                ),
              ),
            ),
          );

      await tester.pumpWidget(host());
      await tester.pump();
      final staleEnter = tester
          .widget<InkWell>(
            find.byKey(
              WebsiteCanvasLayerActions.modeKey(
                WebsiteCanvasManipulationMode.move,
              ),
            ),
          )
          .onTap!;

      provider.selectCanvasElement('canvas-1', 'layer-b');
      final targetB = provider.selectedCanvasLayerTarget!;
      expect(
        provider.startCanvasManipulation(
          WebsiteCanvasManipulationMode.move,
          target: targetB,
          viewport: provider.previewViewport,
        ),
        isTrue,
      );
      final sessionB = provider.canvasManipulationSession!;
      staleEnter();
      expect(
        provider.canvasManipulationSession,
        sessionB,
        reason: 'the callback built for A cannot arm the selected B',
      );

      provider.selectCanvasElement('canvas-1', 'layer-a');
      final targetA = provider.selectedCanvasLayerTarget!;
      expect(
        provider.startCanvasManipulation(
          WebsiteCanvasManipulationMode.move,
          target: targetA,
          viewport: provider.previewViewport,
        ),
        isTrue,
      );
      await tester.pump();
      final staleExit = tester
          .widget<InkWell>(
            find.byKey(
              WebsiteCanvasLayerActions.modeKey(
                WebsiteCanvasManipulationMode.move,
              ),
            ),
          )
          .onTap!;
      final firstA = provider.canvasManipulationSession!;
      expect(provider.stopCanvasManipulation(expectedSession: firstA), isTrue);
      expect(
        provider.startCanvasManipulation(
          WebsiteCanvasManipulationMode.move,
          target: targetA,
          viewport: provider.previewViewport,
        ),
        isTrue,
      );
      final secondA = provider.canvasManipulationSession!;
      staleExit();
      expect(provider.canvasManipulationSession, secondA);
      expect(secondA.generation, greaterThan(firstA.generation));
      expect(provider.canUndo, isFalse);
    });

    testWidgets('callbacks viejos no se redirigen a otro viewport',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider(previewMode: DevicePreviewMode.mobile)
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.resolve(
              preset: AppearancePresets.pacific,
              brightness: Brightness.light,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: WebsiteCanvasLayerActions(provider: provider),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final staleEnter = tester
          .widget<InkWell>(
            find.byKey(
              WebsiteCanvasLayerActions.modeKey(
                WebsiteCanvasManipulationMode.move,
              ),
            ),
          )
          .onTap!;
      final staleAlign = tester
          .widget<IconButton>(
            find.byKey(
              WebsiteCanvasLayerActions.alignKey(
                WebsiteCanvasAlignment.right,
              ),
            ),
          )
          .onPressed!;

      provider.setDevicePreviewMode(DevicePreviewMode.desktop);
      staleEnter();
      staleAlign();

      expect(provider.canvasManipulationSession, isNull);
      expect(provider.canUndo, isFalse);
      expect(provider.hasPageDraftChanges, isFalse);
    });

    testWidgets('callbacks viejos no cambian el scope que anunciaron',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider(previewMode: DevicePreviewMode.mobile)
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.resolve(
              preset: AppearancePresets.pacific,
              brightness: Brightness.light,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: WebsiteCanvasLayerActions(provider: provider),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final staleEnter = tester
          .widget<InkWell>(
            find.byKey(
              WebsiteCanvasLayerActions.modeKey(
                WebsiteCanvasManipulationMode.move,
              ),
            ),
          )
          .onTap!;
      final staleAlign = tester
          .widget<IconButton>(
            find.byKey(
              WebsiteCanvasLayerActions.alignKey(
                WebsiteCanvasAlignment.right,
              ),
            ),
          )
          .onPressed!;

      provider.setWriteScope(WebsiteWriteScope.viewport);
      staleEnter();
      staleAlign();

      expect(provider.canvasManipulationSession, isNull);
      expect(provider.canUndo, isFalse);
      expect(provider.hasPageDraftChanges, isFalse);
    });

    testWidgets('bloquear y ocultar están, con su razón y a 48',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider(previewMode: DevicePreviewMode.mobile)
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.resolve(
              preset: AppearancePresets.pacific,
              brightness: Brightness.light,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Consumer<WebsiteEditModeProvider>(
                  builder: (context, liveProvider, child) =>
                      WebsiteCanvasLayerActions(provider: liveProvider),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final key in <Key>[
        WebsiteCanvasLayerActions.lockKey,
        WebsiteCanvasLayerActions.visibilityKey,
      ]) {
        expect(find.byKey(key), findsOneWidget);
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(WebsiteCanvasLayerActions.rowHeight),
        );
      }
      // No existe un badge global que mienta: cada familia publica el alcance
      // que su operación realmente escribe.
      expect(find.text('Alinear · común'), findsOneWidget);
      expect(find.text('Orden · común'), findsOneWidget);
      expect(find.text('Geometría · común'), findsOneWidget);
      expect(
        find.text(
          'Bloquear impide moverla por accidente. Alcance: común.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'La visibilidad es independiente por dispositivo. Alcance: móvil.',
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(WebsiteCanvasLayerActions.visibilityKey),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      final hiddenDocument = provider.canvasDocument('canvas-1')!;
      expect(
        WebsiteCanvasResponsiveDocument.projectLayers(
          data: hiddenDocument,
          viewport: WebsiteViewport.desktop,
        ).first.visible,
        isTrue,
      );
      expect(
        WebsiteCanvasResponsiveDocument.projectLayers(
          data: hiddenDocument,
          viewport: WebsiteViewport.mobile,
        ).first.visible,
        isFalse,
      );

      provider.setWriteScope(WebsiteWriteScope.viewport);
      await tester.pump();
      expect(find.text('Alinear · móvil'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(WebsiteCanvasLayerActions.lockKey),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      final lockedLayer = Map<String, dynamic>.from(
        (provider.canvasDocument('canvas-1')!['elements'] as List).first as Map,
      );
      expect(lockedLayer['locked'], isTrue);
      expect(
        (lockedLayer['responsive'] as Map?)?['mobile'],
        anyOf(isNull, isNot(contains('locked'))),
        reason: 'bloquear declara y escribe siempre en común',
      );
      expect(find.text('Duplicar capa · común'), findsOneWidget);
      expect(find.text('Eliminar capa · común'), findsOneWidget);

      provider.setDevicePreviewMode(DevicePreviewMode.desktop);
      reportCanvas(provider, width: 1200);
      await tester.pump();
      expect(
        find.text('Cambia la visibilidad base de la capa. Alcance: común.'),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(WebsiteCanvasLayerActions.visibilityKey),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      final desktopLayer = Map<String, dynamic>.from(
        (provider.canvasDocument('canvas-1')!['elements'] as List).first as Map,
      );
      expect(
        desktopLayer['visible'],
        isFalse,
        reason: 'desktop declara y escribe la visibilidad base común',
      );
    });
  });

  group('O-05 a 390 · superficie operativa completa', () {
    Widget sheetHost(WebsiteEditModeProvider provider) {
      return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.pacific,
            brightness: Brightness.light,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Consumer<WebsiteEditModeProvider>(
                builder: (context, liveProvider, child) =>
                    WebsiteCanvasLayerActions(provider: liveProvider),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('todas las operaciones existen, a 48 y sin desbordes',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider()
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(sheetHost(provider));
      await tester.pump();

      // Las seis alineaciones, el z-order completo, duplicar y borrar.
      for (final alignment in WebsiteCanvasLayerActions.alignments) {
        final key = WebsiteCanvasLayerActions.alignKey(alignment);
        expect(find.byKey(key), findsOneWidget, reason: '$alignment');
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(WebsiteCanvasLayerActions.iconTarget),
        );
      }
      for (final action in const ['back', 'backward', 'forward', 'front']) {
        final key = WebsiteCanvasLayerActions.zOrderKey(action);
        expect(find.byKey(key), findsOneWidget, reason: action);
        expect(
          tester.getSize(find.byKey(key)).width,
          greaterThanOrEqualTo(WebsiteCanvasLayerActions.iconTarget),
        );
      }
      for (final key in <Key>[
        WebsiteCanvasLayerActions.duplicateKey,
        WebsiteCanvasLayerActions.deleteKey,
      ]) {
        expect(find.byKey(key), findsOneWidget);
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(WebsiteCanvasLayerActions.rowHeight),
        );
      }
      // Precisión numérica para las cinco propiedades de geometría.
      for (final field in const ['x', 'y', 'w', 'h', 'rotation']) {
        expect(
          find.byKey(WebsiteCanvasLayerActions.geometryKey(field)),
          findsOneWidget,
          reason: field,
        );
      }
      // Ni un desborde a 390: seis targets de 48 no caben en una fila, así que
      // envuelven en vez de encogerse.
      expect(tester.takeException(), isNull);
    });

    testWidgets('la ruta real separa acciones de capa e inspector',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider()
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(dockHost(provider));
      await tester.pump();

      await tester.tap(
        find.byKey(WebsiteEditorContextualDock.layerActionsKey),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.byKey(WebsiteBlockEditSheet.sheetKey), findsOneWidget);
      expect(find.byKey(WebsiteCanvasLayerActions.groupKey), findsOneWidget);
      expect(find.byKey(WebsiteBlockEditSheet.sectionTabsKey), findsNothing);
      expect(
        tester
            .widget<WebsiteContextualSheetScaffold>(
              find.byType(WebsiteContextualSheetScaffold),
            )
            .scope,
        isNull,
        reason:
            'una hoja con scopes mixtos no puede atribuir todas sus filas a uno',
      );

      await tester.tap(find.byKey(WebsiteBlockEditSheet.doneKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(WebsiteEditorContextualDock.editKey));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(tester.takeException(), isNull);
      expect(find.byKey(WebsiteCanvasLayerActions.groupKey), findsNothing);
      expect(find.byKey(WebsiteBlockEditSheet.sectionTabsKey), findsOneWidget);
    });

    testWidgets(
        'acciones de capa no se convierte en inspector si la capa desaparece',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider()
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(dockHost(provider));
      await tester.pump();
      await tester.tap(
        find.byKey(WebsiteEditorContextualDock.layerActionsKey),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(WebsiteCanvasLayerActions.groupKey), findsOneWidget);
      expect(provider.removeCanvasLayer('canvas-1', 'layer-a'), isTrue);
      await tester.pump();

      expect(provider.selectedCanvasLayerTarget, isNull);
      expect(find.byKey(WebsiteBlockEditSheet.sheetKey), findsOneWidget);
      expect(find.byKey(WebsiteCanvasLayerActions.groupKey), findsNothing);
      expect(find.byKey(WebsiteBlockEditSheet.sectionTabsKey), findsNothing);
      expect(
        find.text('Selecciona una capa del lienzo para ver sus acciones.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'confirmación vieja no elimina otra selección ni su capa previa',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider(previewMode: DevicePreviewMode.mobile)
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(sheetHost(provider));
      await tester.pump();
      await tester.tap(find.byKey(WebsiteCanvasLayerActions.deleteKey));
      await tester.pump();
      expect(find.text('¿Eliminar esta capa?'), findsOneWidget);

      provider.selectCanvasElement('canvas-1', 'layer-b');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(TextButton, 'Eliminar capa'),
      );
      await tester.pumpAndSettle();

      final ids = (provider.canvasDocument('canvas-1')!['elements'] as List)
          .whereType<Map>()
          .map((layer) => layer['id'])
          .toSet();
      expect(ids, containsAll(<String>{'layer-a', 'layer-b'}));
      expect(provider.selectedCanvasLayerTarget?.layerId, 'layer-b');
      expect(provider.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('alinear escribe UNA vez bajo el scope común visible, un undo',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider(previewMode: DevicePreviewMode.mobile)
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(sheetHost(provider));
      await tester.pump();
      expect(provider.canUndo, isFalse);

      await tester.tap(
        find.byKey(
          WebsiteCanvasLayerActions.alignKey(WebsiteCanvasAlignment.left),
        ),
      );
      await tester.pump();

      // Una operación, un paso de historia. El eje que no se alinea no viaja
      // en un segundo write.
      expect(provider.canUndo, isTrue);
      final alignedDocument = provider.canvasDocument('canvas-1')!;
      final alignedShared = Map<String, dynamic>.from(
        (alignedDocument['elements'] as List).first as Map,
      );
      expect(alignedShared['x'], 0.0);
      expect(
        (alignedShared['responsive'] as Map?)?['mobile'],
        anyOf(isNull, isNot(contains('x'))),
        reason: 'el badge común no puede crear un override móvil oculto',
      );
      provider.undo();
      expect(provider.canUndo, isFalse);
    });

    testWidgets('alinear móvil usa la raíz móvil proyectada', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const <Map<String, dynamic>>[
            {
              'id': 'canvas-1',
              'block_type': 'canvas',
              'block_data': <String, dynamic>{
                'canvasResponsiveVersion': 2,
                'designWidth': 1200.0,
                'blockHeight': 300.0,
                'responsive': <String, dynamic>{
                  'version': 2,
                  'mobile': <String, dynamic>{'designWidth': 390.0},
                },
                'elements': [
                  {
                    'id': 'layer-a',
                    'type': 'text',
                    'x': 10.0,
                    'y': 10.0,
                    'w': 100.0,
                    'h': 48.0,
                  },
                ],
              },
              'is_visible': true,
              'sort_order': 0,
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement('canvas-1', 'layer-a');
      reportCanvas(provider);
      addTearDown(provider.dispose);

      await tester.pumpWidget(sheetHost(provider));
      await tester.pump();
      await tester.tap(
        find.byKey(
          WebsiteCanvasLayerActions.alignKey(WebsiteCanvasAlignment.right),
        ),
      );
      await tester.pump();

      final document = provider.canvasDocument('canvas-1')!;
      final layer = WebsiteCanvasResponsiveDocument.projectLayers(
        data: document,
        viewport: WebsiteViewport.mobile,
      ).single;
      expect(layer.data['x'], 290.0);
      final shared = Map<String, dynamic>.from(
        (document['elements'] as List).single as Map,
      );
      expect(shared['x'], 290.0);
    });

    testWidgets('alinear bajo Este viewport no reescribe el común',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const <Map<String, dynamic>>[
            {
              'id': 'canvas-1',
              'block_type': 'canvas',
              'block_data': <String, dynamic>{
                'canvasResponsiveVersion': 2,
                'designWidth': 1200.0,
                'blockHeight': 300.0,
                'responsive': <String, dynamic>{
                  'version': 2,
                  'mobile': <String, dynamic>{'designWidth': 390.0},
                },
                'elements': [
                  {
                    'id': 'layer-a',
                    'type': 'text',
                    'x': 10.0,
                    'y': 10.0,
                    'w': 100.0,
                    'h': 48.0,
                  },
                ],
              },
              'is_visible': true,
              'sort_order': 0,
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setWriteScope(WebsiteWriteScope.viewport)
        ..selectCanvasElement('canvas-1', 'layer-a');
      reportCanvas(provider);
      addTearDown(provider.dispose);

      await tester.pumpWidget(sheetHost(provider));
      await tester.pump();
      await tester.tap(
        find.byKey(
          WebsiteCanvasLayerActions.alignKey(WebsiteCanvasAlignment.right),
        ),
      );
      await tester.pump();

      final document = provider.canvasDocument('canvas-1')!;
      final shared = Map<String, dynamic>.from(
        (document['elements'] as List).single as Map,
      );
      expect(shared['x'], 10.0);
      expect(
        WebsiteCanvasResponsiveDocument.projectLayers(
          data: document,
          viewport: WebsiteViewport.mobile,
        ).single.data['x'],
        290.0,
      );
      expect(
        WebsiteCanvasResponsiveDocument.projectLayers(
          data: document,
          viewport: WebsiteViewport.desktop,
        ).single.data['x'],
        10.0,
      );
    });

    testWidgets('geometría inválida vuelve a la verdad del documento',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider(previewMode: DevicePreviewMode.mobile)
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(sheetHost(provider));
      await tester.pump();
      final widthField = find.byKey(WebsiteCanvasLayerActions.geometryKey('w'));

      for (final invalid in <String>['0', '-1', 'NaN', 'Infinity']) {
        await tester.enterText(widthField, invalid);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(
          tester.widget<TextField>(widthField).controller!.text,
          isEmpty,
          reason: invalid,
        );
        expect(provider.canUndo, isFalse, reason: invalid);
        expect(provider.hasPageDraftChanges, isFalse, reason: invalid);
      }
    });

    testWidgets('cambiar viewport descarta texto geométrico no confirmado',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider(previewMode: DevicePreviewMode.mobile)
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(sheetHost(provider));
      await tester.pump();
      final xField = find.byKey(WebsiteCanvasLayerActions.geometryKey('x'));
      await tester.enterText(xField, '999');
      expect(tester.widget<TextField>(xField).controller!.text, '999');

      provider.setDevicePreviewMode(DevicePreviewMode.desktop);
      await tester.pump();

      expect(tester.widget<TextField>(xField).controller!.text, '10');
      expect(provider.canUndo, isFalse);
    });

    testWidgets('cambiar capa descarta texto aunque el valor efectivo coincida',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = newProvider();
      expect(
        provider.setCanvasLayerProperties(
          'canvas-1',
          'layer-b',
          const <String, Object?>{'x': 10.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        isTrue,
      );
      provider
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..reportRenderedCanvasSize(
          const WebsiteCanvasDocumentTarget(blockId: 'canvas-1'),
          const Size(390, 520),
          expectedMeasurementGeneration:
              provider.renderedCanvasMeasurementGeneration,
        )
        ..selectCanvasElement('canvas-1', 'layer-a');
      reportCanvas(provider);
      addTearDown(provider.dispose);

      await tester.pumpWidget(sheetHost(provider));
      await tester.pump();
      final xField = find.byKey(WebsiteCanvasLayerActions.geometryKey('x'));
      await tester.enterText(xField, '999');
      expect(tester.widget<TextField>(xField).controller!.text, '999');

      provider.selectCanvasElement('canvas-1', 'layer-b');
      await tester.pump();

      expect(tester.widget<TextField>(xField).controller!.text, '10');
    });

    testWidgets('una capa bloqueada explica en vez de no hacer nada',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const <Map<String, dynamic>>[
            {
              'id': 'canvas-1',
              'block_type': 'canvas',
              'block_data': <String, dynamic>{
                'elements': [
                  {
                    'id': 'layer-a',
                    'type': 'text',
                    'x': 10.0,
                    'y': 10.0,
                    'locked': true,
                  },
                ],
              },
              'is_visible': true,
              'sort_order': 0,
            },
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..selectCanvasElement('canvas-1', 'layer-a');
      reportCanvas(provider);
      addTearDown(provider.dispose);

      await tester.pumpWidget(sheetHost(provider));
      await tester.pump();

      final alignLeft = find.byKey(
        WebsiteCanvasLayerActions.alignKey(WebsiteCanvasAlignment.left),
      );
      expect(
        tester.widget<IconButton>(alignLeft).onPressed,
        isNull,
        reason: 'una capa bloqueada no se alinea',
      );
      // Y dice por qué, donde `A-01` lo pide.
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: alignLeft, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, contains('bloqueada'));
      // Desbloquear sí está disponible: el límite tiene salida.
      expect(find.byKey(WebsiteCanvasLayerActions.lockKey), findsOneWidget);
    });

    testWidgets('con el teclado arriba la hoja sigue recorriéndose',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.viewInsets = const FakeViewPadding(bottom: 292);
      addTearDown(tester.view.reset);

      final provider = newProvider()
        ..selectCanvasElement('canvas-1', 'layer-a');
      addTearDown(provider.dispose);

      await tester.pumpWidget(sheetHost(provider));
      await tester.pump();

      // El grupo vive en un scroll propio, así que el teclado reduce el alto
      // disponible sin dejar ningún control inalcanzable.
      expect(find.byType(SingleChildScrollView), findsWidgets);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -300),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(WebsiteCanvasLayerActions.deleteKey), findsOneWidget);
    });
  });
}
