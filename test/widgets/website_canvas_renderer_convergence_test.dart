import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/website/models/canvas_element_factory.dart';
import 'package:vinabike_erp/modules/website/models/website_canvas_manipulation.dart';
import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_canvas_block.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_canvas_editor_binding.dart';
import 'package:vinabike_erp/public_store/widgets/page_composition.dart';

Map<String, dynamic> _canvasBlock({
  required Map<String, dynamic> data,
}) {
  return <String, dynamic>{
    'id': 'canvas-block',
    'block_type': 'canvas',
    'order_index': 0,
    'is_visible': true,
    'block_data': data,
  };
}

String _breakpoint(double width) {
  return WebsiteViewport.fromLogicalWidth(width).wireName;
}

bool _containsActiveElementId(Object? value) {
  if (value is Map) {
    if (value.containsKey('activeElementId')) return true;
    return value.values.any(_containsActiveElementId);
  }
  if (value is Iterable) {
    return value.any(_containsActiveElementId);
  }
  return false;
}

Future<void> _preloadCanvasRenderers(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future.wait<void>(<Future<void>>[
      DeferredEditableBlockRenderer.preload(),
      preloadDeferredCanvasLibrary(),
    ]);
  });
}

Widget _pageHost({
  required WebsitePageComposition composition,
  WebsiteEditModeProvider? provider,
}) {
  final app = MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PageComposition(
          composition: composition,
          primaryColor: const Color(0xFF143D59),
          accentColor: const Color(0xFF00A09D),
          textColor: Colors.black,
          containerPadding: 24,
          onNavigate: (_) {},
          isNavigationEligible: (_) => true,
        ),
      ),
    ),
  );
  if (provider == null) return app;
  return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
    value: provider,
    child: app,
  );
}

Future<void> _pumpPageMode(
  WidgetTester tester, {
  required List<Map<String, dynamic>> blocks,
  required WebsitePageCompositionMode mode,
  WebsiteEditModeProvider? provider,
}) async {
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  await tester.pumpWidget(
    _pageHost(
      composition: WebsitePageComposition.project(
        blocks: blocks,
        mode: mode,
        breakpoint: _breakpoint(width),
        logicalWidth: width,
      ),
      provider: provider,
    ),
  );
  for (var attempt = 0; attempt < 12; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find
            .byKey(const ValueKey<String>('canvas_el_parity-layer'))
            .evaluate()
            .isNotEmpty) {
      break;
    }
  }
}

class _CanvasGeometry {
  const _CanvasGeometry({
    required this.blockSize,
    required this.elementOffset,
    required this.elementSize,
  });

  final Size blockSize;
  final Offset elementOffset;
  final Size elementSize;
}

_CanvasGeometry _captureGeometry(WidgetTester tester) {
  final block = find.byKey(
    const ValueKey<String>('page-composition-block-canvas-block'),
  );
  final element = find.byKey(
    const ValueKey<String>('canvas_el_parity-layer'),
  );
  expect(block, findsOneWidget);
  expect(element, findsOneWidget);

  final blockRect = tester.getRect(block);
  final elementRect = tester.getRect(element);
  return _CanvasGeometry(
    blockSize: blockRect.size,
    elementOffset: elementRect.topLeft - blockRect.topLeft,
    elementSize: elementRect.size,
  );
}

void _expectSameGeometry(
  _CanvasGeometry actual,
  _CanvasGeometry expected, {
  required String reason,
}) {
  expect(actual.blockSize.width, closeTo(expected.blockSize.width, 0.01),
      reason: '$reason block width');
  expect(actual.blockSize.height, closeTo(expected.blockSize.height, 0.01),
      reason: '$reason block height');
  expect(actual.elementOffset.dx, closeTo(expected.elementOffset.dx, 0.01),
      reason: '$reason element x');
  expect(actual.elementOffset.dy, closeTo(expected.elementOffset.dy, 0.01),
      reason: '$reason element y');
  expect(actual.elementSize.width, closeTo(expected.elementSize.width, 0.01),
      reason: '$reason element width');
  expect(actual.elementSize.height, closeTo(expected.elementSize.height, 0.01),
      reason: '$reason element height');
}

void main() {
  testWidgets(
    'Deferred Canvas binding keeps repeated and background selection transient',
    (tester) async {
      await _preloadCanvasRenderers(tester);
      await tester.binding.setSurfaceSize(const Size(800, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final element = createCanvasElement(
        id: 'selection-layer',
        type: 'text',
      )..addAll(<String, dynamic>{
          'x': 80.0,
          'y': 64.0,
          'w': 240.0,
          'h': 72.0,
          'text': 'Seleccionable',
        });
      final initialData = <String, dynamic>{
        'blockHeight': 420.0,
        'designWidth': 800.0,
        'showGrid': false,
        'elements': <Map<String, dynamic>>[element],
      };
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[_canvasBlock(data: initialData)],
          const <String, dynamic>{},
          pageId: 'canvas-page',
          pageSlug: 'canvas-page',
        );
      addTearDown(provider.dispose);

      final baseline = jsonEncode(provider.blocks);
      final selectionEvents = <String?>[];
      var backgroundTaps = 0;
      var elementWrites = 0;

      await tester.pumpWidget(
        ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer<WebsiteEditModeProvider>(
                builder: (context, currentProvider, child) {
                  final blockData = Map<String, dynamic>.from(
                    currentProvider.blocks.single['block_data'] as Map,
                  );
                  return Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 800,
                      child: DeferredCanvasBlock(
                        data: blockData,
                        accentColor: const Color(0xFF00A09D),
                        editorBinding: WebsiteCanvasEditorBinding(
                          documentTarget: const WebsiteCanvasDocumentTarget(
                            blockId: 'canvas-block',
                          ),
                          activeElementId: currentProvider
                              .canvasElementSelection('canvas-block'),
                          // 7B-2B2: the whole-list write is gone from the
                          // production binding. Selection must still trigger
                          // no document command at all.
                          setLayerProperties: (
                            layerId,
                            values, {
                            required scope,
                            required viewport,
                          }) {
                            elementWrites++;
                            return currentProvider.setCanvasLayerProperties(
                              'canvas-block',
                              layerId,
                              values,
                              scope: scope,
                              viewport: viewport,
                            );
                          },
                          removeLayer: (layerId) {
                            elementWrites++;
                            return currentProvider.removeCanvasLayer(
                              'canvas-block',
                              layerId,
                            );
                          },
                          onActiveElementChanged: (elementId) {
                            selectionEvents.add(elementId);
                            currentProvider.selectCanvasElement(
                              'canvas-block',
                              elementId,
                            );
                          },
                          onBackgroundTap: () {
                            backgroundTaps++;
                            currentProvider.selectBlock('canvas-block');
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      final elementFinder = find.byKey(
        const ValueKey<String>('canvas_el_selection-layer'),
      );
      for (var attempt = 0; attempt < 12; attempt++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (elementFinder.evaluate().isNotEmpty) break;
      }
      expect(elementFinder, findsOneWidget);

      GestureDetector elementTapTarget() {
        return tester
            .widgetList<GestureDetector>(
              find.descendant(
                of: elementFinder,
                matching: find.byType(GestureDetector),
              ),
            )
            .firstWhere(
              (gesture) => gesture.onTap != null && gesture.onDoubleTap != null,
            );
      }

      elementTapTarget().onTap!.call();
      await tester.pump();
      elementTapTarget().onTap!.call();
      await tester.pump();

      expect(
        selectionEvents,
        <String?>['selection-layer', 'selection-layer'],
      );
      expect(provider.selectedBlockId, 'canvas-block');
      expect(
        provider.canvasElementSelection('canvas-block'),
        'selection-layer',
      );
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(provider.canRedo, isFalse);
      expect(elementWrites, 0);
      expect(jsonEncode(provider.blocks), baseline);
      expect(_containsActiveElementId(provider.blocks), isFalse);

      final backgroundTapTarget = tester
          .widgetList<GestureDetector>(
            find.descendant(
              of: find.byType(DeferredCanvasBlock),
              matching: find.byType(GestureDetector),
            ),
          )
          .firstWhere(
            (gesture) => gesture.child == null && gesture.onTap != null,
          );
      backgroundTapTarget.onTap!.call();
      await tester.pump();

      expect(selectionEvents.last, isNull);
      expect(backgroundTaps, 1);
      expect(provider.canvasElementSelection('canvas-block'), isNull);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(provider.canRedo, isFalse);
      expect(elementWrites, 0);
      expect(jsonEncode(provider.blocks), baseline);
      expect(_containsActiveElementId(provider.blocks), isFalse);
    },
  );

  testWidgets(
    'PageComposition keeps Canvas geometry equal in Edit Preview and Public',
    (tester) async {
      await _preloadCanvasRenderers(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final element = createCanvasElement(
        id: 'parity-layer',
        type: 'text',
      )..addAll(<String, dynamic>{
          'x': 180.0,
          'y': 96.0,
          'w': 360.0,
          'h': 84.0,
          'rotation': 12.0,
          'text': 'Geometría canónica',
        });
      final initialBlocks = <Map<String, dynamic>>[
        _canvasBlock(
          data: <String, dynamic>{
            'blockHeight': 480.0,
            'designWidth': 1200.0,
            'mobileDesignWidth': 1200.0,
            'fullBleed': true,
            'showGrid': false,
            'elements': <Map<String, dynamic>>[element],
          },
        ),
      ];

      for (final width in <double>[1440, 834, 390]) {
        await tester.binding.setSurfaceSize(Size(width, 900));

        final editProvider = WebsiteEditModeProvider()
          ..enterEditMode(
            initialBlocks,
            const <String, dynamic>{},
            pageId: 'canvas-page',
            pageSlug: 'canvas-page',
          );
        await _pumpPageMode(
          tester,
          blocks: editProvider.blocks,
          mode: WebsitePageCompositionMode.edit,
          provider: editProvider,
        );
        final edit = _captureGeometry(tester);

        await _pumpPageMode(
          tester,
          blocks: initialBlocks,
          mode: WebsitePageCompositionMode.preview,
        );
        final preview = _captureGeometry(tester);

        await _pumpPageMode(
          tester,
          blocks: initialBlocks,
          mode: WebsitePageCompositionMode.public,
        );
        final public = _captureGeometry(tester);

        _expectSameGeometry(
          edit,
          preview,
          reason: 'Edit/Preview at ${width.toInt()}',
        );
        _expectSameGeometry(
          preview,
          public,
          reason: 'Preview/Public at ${width.toInt()}',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        editProvider.dispose();
      }
    },
  );

  testWidgets(
    'PageComposition uses one Deferred Canvas content owner in every mode',
    (tester) async {
      await _preloadCanvasRenderers(tester);
      await tester.binding.setSurfaceSize(const Size(834, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final element = createCanvasElement(
        id: 'parity-layer',
        type: 'text',
      );
      final blocks = <Map<String, dynamic>>[
        _canvasBlock(
          data: <String, dynamic>{
            'blockHeight': 420.0,
            'designWidth': 1200.0,
            'fullBleed': true,
            'showGrid': false,
            'elements': <Map<String, dynamic>>[element],
          },
        ),
      ];
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          blocks,
          const <String, dynamic>{},
          pageId: 'canvas-page',
          pageSlug: 'canvas-page',
        );
      addTearDown(provider.dispose);

      await _pumpPageMode(
        tester,
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.edit,
        provider: provider,
      );
      expect(
        find.byType(DeferredCanvasBlock),
        findsOneWidget,
        reason: 'Edit must inject editorBinding into the same deferred Canvas '
            'content owner used by Preview/Public',
      );
      final editCanvas = tester.widget<DeferredCanvasBlock>(
        find.byType(DeferredCanvasBlock),
      );
      expect(editCanvas.editorBinding, isNotNull);

      for (final mode in <WebsitePageCompositionMode>[
        WebsitePageCompositionMode.preview,
        WebsitePageCompositionMode.public,
      ]) {
        await _pumpPageMode(
          tester,
          blocks: blocks,
          mode: mode,
        );
        final canvas = tester.widget<DeferredCanvasBlock>(
          find.byType(DeferredCanvasBlock),
        );
        expect(canvas.editorBinding, isNull, reason: mode.name);
      }
    },
  );
}
