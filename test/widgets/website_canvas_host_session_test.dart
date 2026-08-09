import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_canvas_manipulation.dart';
import 'package:vinabike_erp/modules/website/models/website_canvas_responsive_document.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/canvas_block.dart';
import 'package:vinabike_erp/modules/website/widgets/editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_canvas_editor_binding.dart';
import 'package:vinabike_erp/modules/website/widgets/website_canvas_layer_actions.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_block_sheet.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_contextual_dock.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

const _blockId = 'canvas-a';
const _carouselBlockId = 'carousel-a';
const _layerId = 'layer-a';

bool _startSelected(
  WebsiteEditModeProvider provider,
  WebsiteCanvasManipulationMode mode,
) {
  final target = provider.selectedCanvasLayerTarget!;
  if (provider.renderedCanvasViewport(target.document) == null) {
    provider.reportRenderedCanvasSize(
      target.document,
      const Size(390, 520),
      expectedMeasurementGeneration:
          provider.renderedCanvasMeasurementGeneration,
    );
  }
  return provider.startCanvasManipulation(
    mode,
    target: target,
    viewport: provider.renderedCanvasViewport(target.document)!,
  );
}

Map<String, dynamic> _block({bool includeSecondLayer = false}) =>
    <String, dynamic>{
      'id': _blockId,
      'block_type': 'canvas',
      'block_data': <String, dynamic>{
        'canvasResponsiveVersion': 2,
        'blockHeight': 520.0,
        'designWidth': 1200.0,
        'showGrid': false,
        'snap': false,
        'elements': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': _layerId,
            'type': 'text',
            'x': 80.0,
            'y': 80.0,
            'w': 600.0,
            'h': 240.0,
            'text': 'Capa táctil',
          },
          if (includeSecondLayer)
            <String, dynamic>{
              'id': 'layer-b',
              'type': 'text',
              'x': 320.0,
              'y': 240.0,
              'w': 400.0,
              'h': 160.0,
              'text': 'Segunda capa',
            },
        ],
      },
      'is_visible': true,
      'sort_order': 0,
    };

Map<String, dynamic> _carouselBlock() => <String, dynamic>{
      'id': _carouselBlockId,
      'block_type': 'carousel',
      'block_data': <String, dynamic>{
        'id': _carouselBlockId,
        'autoPlay': false,
        'showIndicators': false,
        'showArrows': false,
        'slides': <Map<String, dynamic>>[
          <String, dynamic>{
            'title': 'Campaña táctil',
            'useComposition': true,
            'canvasResponsiveVersion': 2,
            'designWidth': 1200.0,
            'mobileDesignWidth': 390.0,
            'designHeight': 520.0,
            'elements': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': _layerId,
                'type': 'text',
                'x': 80.0,
                'y': 80.0,
                'w': 600.0,
                'h': 240.0,
                'text': 'Capa de carrusel',
              },
            ],
          },
        ],
      },
      'is_visible': true,
      'sort_order': 0,
    };

Map<String, dynamic> _liveLayer(
  WebsiteEditModeProvider provider,
  String layerId,
) {
  final elements = provider.canvasDocument(_blockId)!['elements']! as List;
  return Map<String, dynamic>.from(
    elements.firstWhere(
      (element) => (element as Map)['id']?.toString() == layerId,
    ) as Map,
  );
}

Widget _host(WebsiteEditModeProvider provider) {
  return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Scaffold(
        body: WebsiteEditorChromeScope(
          editorWidth: 390,
          canvasWidth: 390,
          child: Consumer<WebsiteEditModeProvider>(
            builder: (context, live, _) {
              final block = live.getBlock(_blockId)!;
              final data = Map<String, dynamic>.from(
                block['block_data'] as Map,
              );
              const document = WebsiteCanvasDocumentTarget(blockId: _blockId);
              final measurementGeneration =
                  live.renderedCanvasMeasurementGeneration;
              final binding = WebsiteCanvasEditorBinding(
                documentTarget: document,
                canvasMeasurementGeneration: measurementGeneration,
                onCanvasSizeChanged: (size) => live.reportRenderedCanvasSize(
                  document,
                  size,
                  expectedMeasurementGeneration: measurementGeneration,
                ),
                activeElementId: live.canvasElementSelection(_blockId),
                manipulationSession: live.canvasManipulationSession,
                manipulationAvailability: (
                  layerId,
                  mode, {
                  required viewport,
                }) =>
                    live.canvasManipulationAvailability(
                  mode,
                  target: WebsiteCanvasLayerTarget(
                    document: document,
                    layerId: layerId,
                  ),
                  viewport: viewport,
                ),
                requestManipulation: (
                  layerId,
                  mode, {
                  required viewport,
                }) =>
                    live.startCanvasManipulation(
                  mode,
                  target: WebsiteCanvasLayerTarget(
                    document: document,
                    layerId: layerId,
                  ),
                  viewport: viewport,
                ),
                commitManipulation: (
                  expected,
                  expectedDocument,
                  expectedDocumentEpoch,
                  values, {
                  required scope,
                }) =>
                    expected.target.document == document &&
                    live.commitCanvasManipulation(
                      expected,
                      expectedDocument,
                      expectedDocumentEpoch,
                      values,
                      scope: scope,
                    ),
                stopManipulation: (expected) =>
                    expected.target.document == document &&
                    live.stopCanvasManipulation(
                      expectedSession: expected,
                    ),
                captureAsyncIntent: (
                  layerId, {
                  required scope,
                  required viewport,
                }) {
                  final target = WebsiteCanvasLayerTarget(
                    document: document,
                    layerId: layerId,
                  );
                  if (live.selectedCanvasLayerTarget != target ||
                      live.renderedCanvasViewport(document) != viewport ||
                      live.writeScope != scope) {
                    return null;
                  }
                  return live.captureAsyncIntent(blockId: _blockId);
                },
                commitAsyncLayerProperties: (
                  expectedIntent,
                  layerId,
                  values, {
                  required scope,
                  required viewport,
                }) =>
                    live.commitAsyncIntent(expectedIntent, () {
                  final target = WebsiteCanvasLayerTarget(
                    document: document,
                    layerId: layerId,
                  );
                  if (live.selectedCanvasLayerTarget != target ||
                      live.renderedCanvasViewport(document) != viewport ||
                      live.writeScope != scope) {
                    return WebsiteInlineMutationResult.rejected;
                  }
                  final changed = live.setCanvasLayerProperties(
                    _blockId,
                    layerId,
                    values,
                    scope: scope,
                    viewport: viewport,
                  );
                  return changed
                      ? WebsiteInlineMutationResult.committed
                      : WebsiteInlineMutationResult.unchanged;
                }),
                writeScope: () => live.writeScope,
                readDocument: () => live.canvasDocument(_blockId),
                documentEpoch: () => live.pageDocumentEpoch,
                setLayerProperties: (
                  layerId,
                  values, {
                  required WebsiteWriteScope scope,
                  required WebsiteViewport viewport,
                }) =>
                    live.setCanvasLayerProperties(
                  _blockId,
                  layerId,
                  values,
                  scope: scope,
                  viewport: viewport,
                ),
                onActiveElementChanged: (layerId) =>
                    live.selectCanvasElement(_blockId, layerId),
                onBackgroundTap: () => live.selectBlock(_blockId),
              );
              return EditableBlockRenderer.build(
                context: context,
                blockId: _blockId,
                blockType: 'canvas',
                data: data,
                effectiveViewport: WebsiteViewport.mobile,
                contentOverride: CanvasBlock(
                  data: data,
                  editable: true,
                  accentColor: Colors.teal,
                  editorBinding: binding,
                  onCanvasSizeChanged: binding.onCanvasSizeChanged,
                  activeElementId: binding.activeElementId,
                  onActiveElementChanged: binding.onActiveElementChanged,
                ),
                primaryColor: Colors.blue,
                accentColor: Colors.teal,
              );
            },
          ),
        ),
      ),
    ),
  );
}

Widget _carouselHost(WebsiteEditModeProvider provider) {
  return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Scaffold(
        body: WebsiteEditorChromeScope(
          editorWidth: 390,
          canvasWidth: 390,
          child: Consumer<WebsiteEditModeProvider>(
            builder: (context, live, _) {
              final block = live.getBlock(_carouselBlockId)!;
              final data = Map<String, dynamic>.from(
                block['block_data'] as Map,
              );
              return SizedBox(
                height: 520,
                child: EditableBlockRenderer.build(
                  context: context,
                  blockId: _carouselBlockId,
                  blockType: 'carousel',
                  data: data,
                  effectiveViewport: WebsiteViewport.mobile,
                  primaryColor: Colors.blue,
                  accentColor: Colors.teal,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// The compact production composition used by the 451 px regression.
///
/// Unlike [_host], this deliberately does not create an editor binding or call
/// either side of the manipulation contract from the harness. The real
/// [EditableBlockRenderer] owns its binding, the deferred Canvas reports its
/// laid-out size, O-05 starts the session, and the outer scrollable arbitrates
/// browse touch.
Widget _interactive451Host(
  WebsiteEditModeProvider provider,
  ScrollController scrollController,
) {
  return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: Brightness.light,
      ),
      home: WebsiteEditorChromeScope(
        editorWidth: 451,
        canvasWidth: 451,
        child: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  key: const ValueKey('canvas-451-page-scroll'),
                  controller: scrollController,
                  child: Consumer<WebsiteEditModeProvider>(
                    builder: (context, live, _) {
                      final block = live.getBlock(_blockId)!;
                      final data = Map<String, dynamic>.from(
                        block['block_data'] as Map,
                      );
                      return Column(
                        children: [
                          EditableBlockRenderer.build(
                            context: context,
                            blockId: _blockId,
                            blockType: 'canvas',
                            data: data,
                            effectiveViewport: WebsiteViewport.mobile,
                            primaryColor: Colors.blue,
                            accentColor: Colors.teal,
                          ),
                          const SizedBox(height: 900),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const Positioned(
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

Widget _unmeasured451DockHost(WebsiteEditModeProvider provider) {
  return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: Brightness.light,
      ),
      home: const WebsiteEditorChromeScope(
        editorWidth: 451,
        canvasWidth: 451,
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: WebsiteEditorContextualDock(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'async Canvas intent cannot cross an identical provider replacement',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      WebsiteEditModeProvider provider() => WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);

      final providerA = provider();
      final providerB = provider();
      addTearDown(providerA.dispose);
      addTearDown(providerB.dispose);

      await tester.pumpWidget(_host(providerA));
      await tester.pumpAndSettle();
      expect(providerA.selectedBlockId, _blockId);
      expect(
        providerA.selectedCanvasLayerTarget,
        const WebsiteCanvasLayerTarget(
          document: WebsiteCanvasDocumentTarget(blockId: _blockId),
          layerId: _layerId,
        ),
      );
      expect(
        providerA.renderedCanvasViewport(
          const WebsiteCanvasDocumentTarget(blockId: _blockId),
        ),
        WebsiteViewport.mobile,
      );
      expect(providerA.writeScope, WebsiteWriteScope.shared);
      final bindingA =
          tester.widget<CanvasBlock>(find.byType(CanvasBlock)).editorBinding!;
      final intent = bindingA.captureAsyncIntent!(
        _layerId,
        scope: WebsiteWriteScope.shared,
        viewport: WebsiteViewport.mobile,
      );
      expect(intent, isNotNull);

      await tester.pumpWidget(_host(providerB));
      await tester.pumpAndSettle();
      final bindingB =
          tester.widget<CanvasBlock>(find.byType(CanvasBlock)).editorBinding!;
      final result = bindingB.commitAsyncLayerProperties!(
        intent!,
        _layerId,
        <String, Object?>{'x': 999.0},
        scope: WebsiteWriteScope.shared,
        viewport: WebsiteViewport.mobile,
      );

      expect(result, WebsiteInlineMutationResult.rejected);
      expect(_liveLayer(providerA, _layerId)['x'], 80.0);
      expect(_liveLayer(providerB, _layerId)['x'], 80.0);
      expect(providerA.canUndo, isFalse);
      expect(providerB.canUndo, isFalse);
    },
  );

  testWidgets(
    'dock fails closed before the selected Canvas reports its real viewport',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(451, 896);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.desktop)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);

      await tester.pumpWidget(_unmeasured451DockHost(provider));
      await tester.pump();

      const document = WebsiteCanvasDocumentTarget(blockId: _blockId);
      expect(provider.renderedCanvasViewport(document), isNull);
      expect(find.textContaining('vista efectiva sin medir'), findsOneWidget);
      expect(find.text('Preparando el lienzo'), findsOneWidget);
      expect(find.textContaining('vista escritorio'), findsNothing);
      expect(find.text('Escribe en: común'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final requestedMode in const <DevicePreviewMode>[
    DevicePreviewMode.desktop,
    DevicePreviewMode.tablet,
  ]) {
    testWidgets(
      '451 ${requestedMode.name}: renderer measures Mobile, O-05 closes, '
      'touch writes once and browse scrolls',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(451, 896);
        addTearDown(tester.view.reset);

        final provider = WebsiteEditModeProvider()
          ..enterEditMode(
            <Map<String, dynamic>>[_block()],
            const <String, dynamic>{},
            pageId: 'page-a',
          )
          ..setDevicePreviewMode(requestedMode)
          ..selectCanvasElement(_blockId, _layerId);
        final requestedViewport = switch (requestedMode) {
          DevicePreviewMode.desktop => WebsiteViewport.desktop,
          DevicePreviewMode.tablet => WebsiteViewport.tablet,
          DevicePreviewMode.mobile => WebsiteViewport.mobile,
        };
        addTearDown(provider.dispose);
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        await tester.pumpWidget(
          _interactive451Host(provider, scrollController),
        );
        const document = WebsiteCanvasDocumentTarget(blockId: _blockId);
        for (var frame = 0;
            frame < 20 && provider.renderedCanvasViewport(document) == null;
            frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        // The size report is posted after layout; draw the consumer frame it
        // invalidated before reading the dock or opening O-05.
        await tester.pump();

        expect(provider.previewViewport, requestedViewport);
        expect(
          provider.renderedCanvasViewport(document),
          WebsiteViewport.mobile,
        );
        expect(find.textContaining('vista móvil'), findsOneWidget);

        await tester.tap(
          find.byKey(WebsiteEditorContextualDock.layerActionsKey),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(WebsiteBlockEditSheet.sheetKey), findsOneWidget);

        await tester.tap(
          find.byKey(
            WebsiteCanvasLayerActions.modeKey(
              WebsiteCanvasManipulationMode.move,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(WebsiteBlockEditSheet.sheetKey), findsNothing);
        expect(
          provider.canvasManipulationSession?.viewport,
          WebsiteViewport.mobile,
        );
        expect(
          provider.canvasManipulationSession?.mode,
          WebsiteCanvasManipulationMode.move,
        );

        final layer = find.byKey(
          const ValueKey<String>('canvas_el_$_layerId'),
          skipOffstage: false,
        );
        expect(layer, findsOneWidget);
        final gesture = await tester.startGesture(
          tester.getCenter(layer),
          kind: PointerDeviceKind.touch,
          buttons: 0,
        );
        await gesture.moveBy(const Offset(48, 24));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await tester.pumpAndSettle();

        final moved = _liveLayer(provider, _layerId);
        expect(
          <double>[
            (moved['x'] as num).toDouble(),
            (moved['y'] as num).toDouble(),
          ],
          isNot(<double>[80, 80]),
        );
        expect(provider.canUndo, isTrue);
        expect(scrollController.offset, 0);

        await tester.tap(
          find.byKey(WebsiteEditorContextualDock.exitManipulationKey),
        );
        await tester.pump();
        expect(provider.canvasManipulationSession, isNull);

        final xBeforeBrowse = (moved['x'] as num).toDouble();
        final yBeforeBrowse = (moved['y'] as num).toDouble();
        final browseGesture = await tester.startGesture(
          tester.getCenter(layer),
          kind: PointerDeviceKind.touch,
          buttons: kPrimaryButton,
        );
        await browseGesture.moveBy(const Offset(0, -64));
        await tester.pump(const Duration(milliseconds: 16));
        await browseGesture.moveBy(const Offset(0, -96));
        await tester.pump(const Duration(milliseconds: 16));
        await browseGesture.up();
        await tester.pumpAndSettle();

        final afterBrowse = _liveLayer(provider, _layerId);
        expect(scrollController.offset, greaterThan(0));
        expect((afterBrowse['x'] as num).toDouble(), xBeforeBrowse);
        expect((afterBrowse['y'] as num).toDouble(), yBeforeBrowse);
        expect(provider.canUndo, isTrue);

        provider.undo();
        await tester.pump();
        expect(provider.canUndo, isFalse, reason: 'one touch is one command');
        expect(_liveLayer(provider, _layerId)['x'], 80.0);
        expect(_liveLayer(provider, _layerId)['y'], 80.0);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets(
    'composed Carousel uses one authoring document for render read and commit',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_carouselBlock()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(
          _carouselBlockId,
          _layerId,
          slideIndex: 0,
          slideCount: 1,
        );
      addTearDown(provider.dispose);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_carouselHost(provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final layer = find.byKey(
        const ValueKey<String>('canvas_el_$_layerId'),
        skipOffstage: false,
      );
      expect(layer, findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(layer),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await gesture.moveBy(const Offset(48, 24));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      final document = provider.canvasDocument(
        _carouselBlockId,
        slideIndex: 0,
      )!;
      final moved = Map<String, dynamic>.from(
        (document['elements'] as List).single as Map,
      );
      expect(
        <double>[
          (moved['x'] as num).toDouble(),
          (moved['y'] as num).toDouble(),
        ],
        isNot(<double>[80.0, 80.0]),
        reason: 'the composed Canvas accepted and committed the touch',
      );
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(provider.canUndo, isFalse, reason: 'one gesture is one command');
      final restored = Map<String, dynamic>.from(
        (provider.canvasDocument(_carouselBlockId, slideIndex: 0)!['elements']
                as List)
            .single as Map,
      );
      expect(restored['x'], 80.0);
      expect(restored['y'], 80.0);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'edit preview edit snapshot transition invalidates an old pointer',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(
            const ValueKey<String>('canvas_el_$_layerId'),
            skipOffstage: false,
          ),
        ),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await gesture.moveBy(const Offset(48, 24));
      await tester.pump(const Duration(milliseconds: 16));

      provider.enterPreviewMode(
        <Map<String, dynamic>>[_block()],
        const <String, dynamic>{},
        pageId: 'page-a',
      );
      provider.enterEditMode(
        <Map<String, dynamic>>[_block()],
        const <String, dynamic>{},
        pageId: 'page-a',
      );
      expect(provider.canvasManipulationSession, isNull);
      // No frame: the pointer-up still reaches the render object admitted in
      // the earlier lifecycle, which must now fail closed.
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_liveLayer(provider, _layerId)['x'], 80.0);
      expect(_liveLayer(provider, _layerId)['y'], 80.0);
      expect(provider.canUndo, isFalse);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'production host pointer-down and repeated selection keep exact mode',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);

      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );
      final armed = provider.canvasManipulationSession;

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final layer = find.byKey(
        const ValueKey<String>('canvas_el_$_layerId'),
        skipOffstage: false,
      );
      expect(layer, findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(layer),
        kind: PointerDeviceKind.touch,
        buttons: kPrimaryButton,
      );
      await tester.pump();

      // This passes through EditableBlockRenderer's outer Listener before the
      // exact Canvas recognizer. Merely contacting the selected block is not an
      // exit from the mode the operator armed in O-05.
      expect(provider.canvasManipulationSession, armed);

      await gesture.cancel();
      await tester.pump();
      // Drain the tap/double-tap arbitration timer created by the same real
      // Canvas surface; the assertion below concerns provider state, not that
      // recognizer's 40ms bookkeeping.
      await tester.pump(const Duration(milliseconds: 50));

      provider.selectCanvasElement(_blockId, _layerId);
      await tester.pump();
      expect(provider.canvasManipulationSession, armed);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.canUndo, isFalse);

      final secondGesture = await tester.startGesture(
        tester.getCenter(layer),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await secondGesture.moveBy(const Offset(32, 16));
      final observed = provider.canvasManipulationSession!;
      expect(
        provider.stopCanvasManipulation(expectedSession: observed),
        isTrue,
      );
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.rotate),
        isTrue,
      );
      final third = provider.canvasManipulationSession!;
      expect(third.generation, greaterThan(observed.generation));
      await secondGesture.up();
      await tester.pumpAndSettle();

      final afterModeChange = provider.canvasDocument(_blockId)!;
      final afterElements = afterModeChange['elements']! as List;
      final afterLayer = Map<String, dynamic>.from(afterElements.single as Map);
      expect(afterLayer['x'], 80.0);
      expect(afterLayer['y'], 80.0);
      expect(provider.canvasManipulationSession, third);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'stale touch cannot commit after same-target stop and re-arm without pump',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      final layer = find.byKey(
        const ValueKey<String>('canvas_el_$_layerId'),
        skipOffstage: false,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(layer),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await gesture.moveBy(const Offset(48, 24));

      final first = provider.canvasManipulationSession!;
      expect(provider.stopCanvasManipulation(expectedSession: first), isTrue);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );
      final second = provider.canvasManipulationSession!;
      expect(second.generation, greaterThan(first.generation));

      // Deliberately no pump between re-arm and pointer-up: the mounted
      // binding still carries S1, while the provider already owns S2.
      await gesture.up();
      await tester.pumpAndSettle();

      final document = provider.canvasDocument(_blockId)!;
      final elements = document['elements']! as List;
      final layerData = Map<String, dynamic>.from(elements.single as Map);
      expect(layerData['x'], 80.0);
      expect(layerData['y'], 80.0);
      expect(provider.canvasManipulationSession, second);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'pointer-down lease cannot adopt a re-arm before touch slop',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      final layer = find.byKey(
        const ValueKey<String>('canvas_el_$_layerId'),
        skipOffstage: false,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(layer),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );

      final first = provider.canvasManipulationSession!;
      expect(provider.stopCanvasManipulation(expectedSession: first), isTrue);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );
      final second = provider.canvasManipulationSession!;
      await tester.pump();

      // The recognizer entered the arena under S1. Crossing slop after the
      // rebuild must not let that pointer capture S2 from the new binding.
      await gesture.moveBy(const Offset(48, 24));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_liveLayer(provider, _layerId)['x'], 80.0);
      expect(_liveLayer(provider, _layerId)['y'], 80.0);
      expect(provider.canvasManipulationSession, second);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'source change after pointer-down invalidates the lease before slop',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      final layer = find.byKey(
        const ValueKey<String>('canvas_el_$_layerId'),
        skipOffstage: false,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(layer),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );

      expect(
        provider.setCanvasLayerProperties(
          _blockId,
          _layerId,
          const <String, Object?>{'x': 999.0, 'y': 777.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.mobile,
        ),
        isTrue,
      );
      await tester.pump();

      await gesture.moveBy(const Offset(48, 24));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_liveLayer(provider, _layerId)['x'], 999.0);
      expect(_liveLayer(provider, _layerId)['y'], 777.0);
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(provider.canUndo, isFalse,
          reason: 'only the external write exists');
      expect(_liveLayer(provider, _layerId)['x'], 80.0);
      expect(_liveLayer(provider, _layerId)['y'], 80.0);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'external document write after slop wins even without a rebuild',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(
            const ValueKey<String>('canvas_el_$_layerId'),
            skipOffstage: false,
          ),
        ),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await gesture.moveBy(const Offset(48, 24));
      await tester.pump(const Duration(milliseconds: 16));

      expect(
        provider.setCanvasLayerProperties(
          _blockId,
          _layerId,
          const <String, Object?>{'x': 999.0, 'y': 777.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.mobile,
        ),
        isTrue,
      );
      // Deliberately no pump: the pointer-up reaches the old render object
      // before didUpdateWidget can advance its local source epoch.
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_liveLayer(provider, _layerId)['x'], 999.0);
      expect(_liveLayer(provider, _layerId)['y'], 777.0);
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(provider.canUndo, isFalse,
          reason: 'only the external write may enter history');
      expect(_liveLayer(provider, _layerId)['x'], 80.0);
      expect(_liveLayer(provider, _layerId)['y'], 80.0);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'undo after slop cannot be overwritten before the next frame',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);
      expect(
        provider.setCanvasLayerProperties(
          _blockId,
          _layerId,
          const <String, Object?>{'x': 999.0, 'y': 777.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.mobile,
        ),
        isTrue,
      );
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(
            const ValueKey<String>('canvas_el_$_layerId'),
            skipOffstage: false,
          ),
        ),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await gesture.moveBy(const Offset(48, 24));
      await tester.pump(const Duration(milliseconds: 16));

      provider.undo();
      // Deliberately no pump between owner replacement and pointer-up.
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_liveLayer(provider, _layerId)['x'], 80.0);
      expect(_liveLayer(provider, _layerId)['y'], 80.0);
      expect(provider.canUndo, isFalse);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'undo redo ABA after slop still invalidates the old pointer',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);
      expect(
        provider.setCanvasLayerProperties(
          _blockId,
          _layerId,
          const <String, Object?>{'x': 999.0, 'y': 777.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.mobile,
        ),
        isTrue,
      );
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(
            const ValueKey<String>('canvas_el_$_layerId'),
            skipOffstage: false,
          ),
        ),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await gesture.moveBy(const Offset(48, 24));
      await tester.pump(const Duration(milliseconds: 16));

      provider.undo();
      provider.redo();
      // The bytes are B again, but the owner epoch proves the source crossed A.
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_liveLayer(provider, _layerId)['x'], 999.0);
      expect(_liveLayer(provider, _layerId)['y'], 777.0);
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(provider.canUndo, isFalse,
          reason: 'the stale pointer did not append a second B-derived write');
      expect(_liveLayer(provider, _layerId)['x'], 80.0);
      expect(_liveLayer(provider, _layerId)['y'], 80.0);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'scope is leased at pointer-down and cannot change before pointer-up',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      Finder layer() => find.byKey(
            const ValueKey<String>('canvas_el_$_layerId'),
            skipOffstage: false,
          );
      final staleGesture = await tester.startGesture(
        tester.getCenter(layer()),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await staleGesture.moveBy(const Offset(48, 24));
      await tester.pump(const Duration(milliseconds: 16));

      provider.setWriteScope(WebsiteWriteScope.viewport);
      // Deliberately no pump: the old pointer must retain its common scope and
      // fail, never consult the newly selected viewport scope on release.
      await staleGesture.up();
      await tester.pumpAndSettle();
      expect(provider.canUndo, isFalse);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(_liveLayer(provider, _layerId)['x'], 80.0);

      final currentGesture = await tester.startGesture(
        tester.getCenter(layer()),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await currentGesture.moveBy(const Offset(48, 24));
      await tester.pump(const Duration(milliseconds: 16));
      await currentGesture.up();
      await tester.pumpAndSettle();

      final document = provider.canvasDocument(_blockId)!;
      final shared = Map<String, dynamic>.from(
        (document['elements'] as List).single as Map,
      );
      final mobile = WebsiteCanvasResponsiveDocument.projectLayers(
        data: document,
        viewport: WebsiteViewport.mobile,
      ).single.data;
      expect(shared['x'], 80.0, reason: 'the base remains common truth');
      expect((mobile['x'] as num).toDouble(), greaterThan(80.0));
      expect(provider.canUndo, isTrue);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'source write and selection change cancel an active draft immediately',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block(includeSecondLayer: true)],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      final layer = find.byKey(
        const ValueKey<String>('canvas_el_$_layerId'),
        skipOffstage: false,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(layer),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await gesture.moveBy(const Offset(48, 24));

      expect(
        provider.setCanvasLayerProperties(
          _blockId,
          _layerId,
          const <String, Object?>{'x': 999.0, 'y': 777.0},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.mobile,
        ),
        isTrue,
      );
      provider.selectCanvasElement(_blockId, 'layer-b');
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('canvas_chrome_layer-b')),
        findsOneWidget,
        reason: 'the published selection must follow B in the same rebuild',
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_liveLayer(provider, _layerId)['x'], 999.0);
      expect(_liveLayer(provider, _layerId)['y'], 777.0);
      expect(provider.selectedCanvasLayerTarget?.layerId, 'layer-b');
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(provider.canUndo, isFalse,
          reason: 'only the external write exists');
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'crossing a responsive band cancels the old viewport gesture',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      final layer = find.byKey(
        const ValueKey<String>('canvas_el_$_layerId'),
        skipOffstage: false,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(layer),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await gesture.moveBy(const Offset(48, 24));

      tester.view.physicalSize = const Size(834, 700);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_liveLayer(provider, _layerId)['x'], 80.0);
      expect(_liveLayer(provider, _layerId)['y'], 80.0);
      expect(provider.canUndo, isFalse);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'removing a layer mid-gesture cancels its draft and removes it immediately',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      final layer = find.byKey(
        const ValueKey<String>('canvas_el_$_layerId'),
        skipOffstage: false,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(layer),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await gesture.moveBy(const Offset(48, 24));

      expect(provider.removeCanvasLayer(_blockId, _layerId), isTrue);
      await tester.pump();
      expect(layer, findsNothing, reason: 'no stale local ghost may survive');
      expect(provider.canvasManipulationSession, isNull);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(provider.canvasDocument(_blockId)!['elements'], isEmpty);
      expect(provider.canUndo, isTrue);
      provider.undo();
      await tester.pump();
      expect(provider.canUndo, isFalse, reason: 'only remove created history');
      expect(layer, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'unmount stops only the session generation the Canvas actually observed',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);

      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );
      await tester.pumpWidget(_host(provider));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(provider.canvasManipulationSession, isNull);
      expect(tester.takeException(), isNull);

      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );
      await tester.pumpWidget(_host(provider));
      await tester.pump();
      final observed = provider.canvasManipulationSession!;
      expect(
        provider.stopCanvasManipulation(expectedSession: observed),
        isTrue,
      );
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );
      final newer = provider.canvasManipulationSession!;

      // No pump: the mounted Canvas still carries [observed]. Its dispose must
      // not clear [newer], despite every structural field except generation
      // being equal.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(provider.canvasManipulationSession, newer);
      expect(newer.generation, greaterThan(observed.generation));
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'deferred unmount stop is safe after an owned provider is disposed',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );
      final armed = provider.canvasManipulationSession!;

      await tester.pumpWidget(
        ChangeNotifierProvider<WebsiteEditModeProvider>(
          create: (_) => provider,
          child: _host(provider),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        provider.stopCanvasManipulation(
          expectedSession: armed,
        ),
        isFalse,
        reason: 'all manipulation APIs fail closed after provider disposal',
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'unmount during an active pointer stops its exact lease without a write',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);

      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectCanvasElement(_blockId, _layerId);
      addTearDown(provider.dispose);
      expect(
        _startSelected(provider, WebsiteCanvasManipulationMode.move),
        isTrue,
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(
            const ValueKey<String>('canvas_el_$_layerId'),
            skipOffstage: false,
          ),
        ),
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await gesture.moveBy(const Offset(48, 24));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await gesture.cancel();
      await tester.pump();

      expect(provider.canvasManipulationSession, isNull);
      expect(provider.canUndo, isFalse);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'inline Canvas text commits once through the exact layer intent',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectBlock(_blockId);
      addTearDown(provider.dispose);

      await tester.pumpWidget(_host(provider));
      await tester.pumpAndSettle();
      final layer = find.byKey(
        const ValueKey<String>('canvas_el_$_layerId'),
        skipOffstage: false,
      );
      final editTarget = tester
          .widgetList<GestureDetector>(
            find.descendant(of: layer, matching: find.byType(GestureDetector)),
          )
          .firstWhere(
            (gesture) => gesture.onTap != null && gesture.onDoubleTap != null,
          );
      editTarget.onDoubleTap!.call();
      await tester.pump();

      final editor = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == 'Capa táctil',
      );
      expect(editor, findsOneWidget);
      await tester.enterText(editor, 'Texto exacto');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(_liveLayer(provider, _layerId)['text'], 'Texto exacto');
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(_liveLayer(provider, _layerId)['text'], 'Capa táctil');
      expect(provider.canUndo, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'inline Canvas text rejects same-document ABA before blur',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      addTearDown(tester.view.reset);
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_block()],
          const <String, dynamic>{},
          pageId: 'page-a',
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..selectBlock(_blockId);
      addTearDown(provider.dispose);

      await tester.pumpWidget(_host(provider));
      await tester.pumpAndSettle();
      final layer = find.byKey(
        const ValueKey<String>('canvas_el_$_layerId'),
        skipOffstage: false,
      );
      final editTarget = tester
          .widgetList<GestureDetector>(
            find.descendant(of: layer, matching: find.byType(GestureDetector)),
          )
          .firstWhere(
            (gesture) => gesture.onTap != null && gesture.onDoubleTap != null,
          );
      editTarget.onDoubleTap!.call();
      await tester.pump();
      final editor = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == 'Capa táctil',
      );
      await tester.enterText(editor, 'Borrador A');

      expect(
        provider.setCanvasLayerProperties(
          _blockId,
          _layerId,
          const <String, Object?>{'text': 'Temporal'},
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.mobile,
        ),
        isTrue,
      );
      provider.undo();
      await tester.pumpAndSettle();

      expect(_liveLayer(provider, _layerId)['text'], 'Capa táctil');
      expect(provider.canUndo, isFalse);
      expect(find.text('Borrador A'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
