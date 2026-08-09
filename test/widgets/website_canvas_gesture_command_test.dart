import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_canvas_manipulation.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/widgets/canvas_block.dart';
import 'package:vinabike_erp/modules/website/widgets/website_canvas_editor_binding.dart';

/// 7B-2B1 — the Canvas persists a property through the atomic command, never
/// by replacing the layer list.
///
/// Deliberately minimal: it drives the real `CanvasBlock` with a spy binding
/// instead of inflating a viewport or rebuilding the renderer.

class _Spy {
  final List<
      ({
        String layerId,
        Map<String, Object?> values,
        WebsiteWriteScope scope,
        WebsiteViewport viewport,
      })> layerWrites = [];
  final List<({String layerId, int targetIndex, WebsiteViewport viewport})>
      reorders = [];
  int wholeListWrites = 0;
  WebsiteWriteScope scope = WebsiteWriteScope.shared;

  final List<Map<String, dynamic>> inserted = [];
  final List<String> removed = [];
  final List<({String layerId, String newLayerId})> duplicated = [];
  final List<String?> selections = [];
  bool lifecycleSucceeds = true;
  bool layerWriteSucceeds = true;
  bool manipulationAvailable = true;
  int layerWriteAttempts = 0;

  WebsiteCanvasEditorBinding binding({
    String? activeElementId,
    WebsiteCanvasDocumentTarget documentTarget =
        const WebsiteCanvasDocumentTarget(blockId: 'canvas-block'),
    WebsiteCanvasManipulationSession? manipulationSession,
    Map<String, dynamic>? document,
    WebsiteCanvasDocumentReader? documentReader,
  }) {
    return WebsiteCanvasEditorBinding(
      documentTarget: documentTarget,
      activeElementId: activeElementId,
      manipulationSession: manipulationSession,
      manipulationAvailability: (
        layerId,
        mode, {
        required viewport,
      }) =>
          manipulationAvailable
              ? const WebsiteCanvasManipulationAvailability.available()
              : const WebsiteCanvasManipulationAvailability.blocked(
                  WebsiteCanvasManipulationBlockReason.layerLocked,
                ),
      commitManipulation: (
        expected,
        expectedDocument,
        expectedDocumentEpoch,
        values, {
        required scope,
      }) {
        layerWriteAttempts++;
        if (!layerWriteSucceeds ||
            !manipulationAvailable ||
            manipulationSession != expected) {
          return false;
        }
        layerWrites.add((
          layerId: expected.target.layerId,
          values: values,
          scope: scope,
          viewport: expected.viewport,
        ));
        return true;
      },
      writeScope: () => scope,
      onActiveElementChanged: selections.add,
      readDocument: documentReader ?? () => document ?? _document(),
      documentEpoch: () => 0,
      insertLayer: (layer, {required index}) {
        if (!lifecycleSucceeds) return false;
        inserted.add(layer);
        return true;
      },
      removeLayer: (layerId) {
        if (!lifecycleSucceeds) return false;
        removed.add(layerId);
        return true;
      },
      duplicateLayer: (layerId, newLayerId) {
        if (!lifecycleSucceeds) return false;
        duplicated.add((layerId: layerId, newLayerId: newLayerId));
        return true;
      },
      setLayerProperties: (layerId, values,
          {required scope, required viewport}) {
        layerWriteAttempts++;
        if (!layerWriteSucceeds) return false;
        layerWrites.add((
          layerId: layerId,
          values: values,
          scope: scope,
          viewport: viewport,
        ));
        return true;
      },
      reorderLayer: (layerId, targetIndex,
          {required scope, required viewport}) {
        reorders.add((
          layerId: layerId,
          targetIndex: targetIndex,
          viewport: viewport,
        ));
        return true;
      },
    );
  }
}

Map<String, dynamic> _document() => <String, dynamic>{
      'canvasResponsiveVersion': 2,
      'blockHeight': 480.0,
      'designWidth': 1200.0,
      'mobileDesignWidth': 1200.0,
      'showGrid': false,
      'snap': false,
      'elements': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'layer-a',
          'type': 'text',
          'x': 200.0,
          'y': 100.0,
          'w': 240.0,
          'h': 72.0,
          'text': 'Arrástrame',
          'responsive': <String, dynamic>{
            'version': 2,
            'mobile': <String, dynamic>{'x': 40.0},
          },
        },
      ],
    };

Future<void> _pump(
  WidgetTester tester, {
  required _Spy spy,
  required double width,
  String? activeElementId,
  WebsiteCanvasManipulationSession? manipulationSession,
}) async {
  final document = _document();
  await tester.binding.setSurfaceSize(Size(width, 900));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: CanvasBlock(
            data: document,
            editable: true,
            accentColor: const Color(0xFF00A09D),
            editorBinding: spy.binding(
              activeElementId: activeElementId,
              manipulationSession: manipulationSession,
              document: document,
            ),
            activeElementId: activeElementId,
            onElementsChanged: (elements) => spy.wholeListWrites++,
            // CanvasBlock reports selection through its own callback, so the
            // spy has to listen where production listens.
            onActiveElementChanged: spy.selections.add,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _layer(String id) =>
    find.byKey(ValueKey<String>('canvas_el_$id'), skipOffstage: false);

/// The selection toolbar floats over the canvas and can sit outside its box,
/// so it is found off-stage and tapped without the miss warning.
Future<void> _tapToolbar(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey<String>(key), skipOffstage: false);
  expect(button, findsOneWidget, reason: 'the toolbar must expose $key');
  await tester.tap(button, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Map<String, dynamic> _touchDocument() => <String, dynamic>{
      'canvasResponsiveVersion': 2,
      'blockHeight': 520.0,
      'designWidth': 1200.0,
      'showGrid': false,
      'snap': false,
      'elements': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'layer-a',
          'type': 'text',
          'x': 80.0,
          'y': 80.0,
          'w': 600.0,
          'h': 240.0,
          'text': 'Capa táctil',
        },
      ],
    };

Map<String, dynamic> _touchImageDocument() => <String, dynamic>{
      ..._touchDocument(),
      'elements': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'layer-a',
          'type': 'image',
          'x': 80.0,
          'y': 80.0,
          'w': 600.0,
          'h': 240.0,
          'imageUrl': '',
          'fit': 'contain',
          'focalPointX': 0.5,
          'focalPointY': 0.5,
        },
      ],
    };

Map<String, dynamic> _shortResizeDocument({
  double x = 80,
  double y = 80,
  double width = 120,
  double height = 56,
  double rotation = 0,
  bool constrainElementsToSafeArea = true,
}) =>
    <String, dynamic>{
      'canvasResponsiveVersion': 2,
      'blockHeight': 300.0,
      'designWidth': 390.0,
      'showGrid': false,
      'snap': false,
      'constrainElementsToSafeArea': constrainElementsToSafeArea,
      'elements': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'layer-a',
          'type': 'text',
          'x': x,
          'y': y,
          'w': width,
          'h': height,
          'rotation': rotation,
          'text': 'Capa baja',
        },
      ],
    };

Future<ScrollController> _pumpScrollableCanvas(
  WidgetTester tester, {
  required _Spy spy,
  required WebsiteCanvasDocumentTarget documentTarget,
  WebsiteCanvasManipulationSession? manipulationSession,
  Map<String, dynamic>? document,
  WebsiteCanvasDocumentReader? documentReader,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 600));
  final controller = ScrollController();
  final sourceDocument = document ?? _touchDocument();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: controller,
          physics: const ClampingScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 120),
              SizedBox(
                width: 390,
                child: CanvasBlock(
                  data: sourceDocument,
                  editable: true,
                  accentColor: const Color(0xFF00A09D),
                  editorBinding: spy.binding(
                    activeElementId: 'layer-a',
                    documentTarget: documentTarget,
                    manipulationSession: manipulationSession,
                    document: sourceDocument,
                    documentReader: documentReader,
                  ),
                  activeElementId: 'layer-a',
                  onElementsChanged: (_) => spy.wholeListWrites++,
                  onActiveElementChanged: spy.selections.add,
                ),
              ),
              const SizedBox(height: 900),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

Future<void> _pointerDrag(
  WidgetTester tester,
  Finder target,
  List<Offset> deltas, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
  int buttons = kPrimaryButton,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: kind,
    buttons: buttons,
  );
  for (final delta in deltas) {
    await gesture.moveBy(delta);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('a drag is one atomic command and zero whole-list writes',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final spy = _Spy();
    await _pump(tester, spy: spy, width: 1440, activeElementId: 'layer-a');

    await tester.drag(
      _layer('layer-a'),
      const Offset(60, 40),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(spy.layerWrites.length, 1, reason: 'exactly one atomic write');
    expect(
      spy.layerWrites.single.values.keys.toSet(),
      <String>{'x', 'y'},
      reason: 'a move is x and y together',
    );
    expect(spy.layerWrites.single.layerId, 'layer-a');
    expect(spy.wholeListWrites, 0, reason: 'no property may replace the list');
  });

  testWidgets('the write viewport comes from the canvas width', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final previousFatalSetting = WidgetController.hitTestWarningShouldBeFatal;
    addTearDown(
      () => WidgetController.hitTestWarningShouldBeFatal = previousFatalSetting,
    );
    // A drag that lands on selection chrome instead of the layer would still
    // produce "a write"; make that mistake fail loudly rather than pass.
    WidgetController.hitTestWarningShouldBeFatal = true;

    for (final entry in <double, WebsiteViewport>{
      390: WebsiteViewport.mobile,
      834: WebsiteViewport.tablet,
      1440: WebsiteViewport.desktop,
    }.entries) {
      final spy = _Spy();
      // Unselected: no handles can intercept, so the gesture is deterministic
      // at every width.
      await _pump(tester, spy: spy, width: entry.key);
      await tester.drag(
        _layer('layer-a'),
        const Offset(30, 20),
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(
        spy.layerWrites.map((w) => w.values.keys.toSet()).toList(),
        <Set<String>>[
          <String>{'x', 'y'}
        ],
        reason: 'a move must write x and y, not rotation, at ${entry.key}',
      );
      expect(
        spy.layerWrites.single.viewport,
        entry.value,
        reason: 'the canvas width, not the ERP window, picks the viewport '
            'at ${entry.key}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('a phone drag starts from the EFFECTIVE x, not the base',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final spy = _Spy()..scope = WebsiteWriteScope.viewport;
    // Unselected on purpose: at 390 px the layer renders small enough that the
    // selection chrome's rotation handle would take the drag instead.
    await _pump(tester, spy: spy, width: 390);

    // The mobile override puts the layer at x = 40 while the base says 200.
    await tester.drag(
      _layer('layer-a'),
      const Offset(30, 0),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(
      spy.layerWrites.map((w) => w.values.keys.toList()).toList(),
      <List<String>>[
        <String>['x', 'y']
      ],
      reason: 'one drag on the phone is one x+y write',
    );
    // The exact distance depends on the touch slop the recognizer eats, so the
    // discriminating fact is the ANCHOR: continuing from the override (40)
    // lands far below the base (200), which a base-anchored drag never could.
    final written = (spy.layerWrites.single.values['x'] as num).toDouble();
    expect(
      written,
      greaterThan(40.0),
      reason: 'the drag moved the layer to the right',
    );
    expect(
      written,
      lessThan(180.0),
      reason: 'the drag must continue from the mobile override (40), not jump '
          'to the base (200) and drag from there',
    );
    expect(spy.layerWrites.single.scope, WebsiteWriteScope.viewport);
    expect(spy.wholeListWrites, 0);
  });

  testWidgets('browse touch yields the drag to the page scroll owner',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final spy = _Spy();
    final controller = await _pumpScrollableCanvas(
      tester,
      spy: spy,
      documentTarget: const WebsiteCanvasDocumentTarget(blockId: 'canvas-a'),
    );
    addTearDown(controller.dispose);

    await _pointerDrag(
      tester,
      _layer('layer-a'),
      const <Offset>[Offset(0, -40), Offset(0, -80)],
    );

    expect(controller.offset, greaterThan(0));
    expect(spy.layerWrites, isEmpty);
    expect(spy.wholeListWrites, 0);
  });

  testWidgets('armed touch moves only its exact document layer once',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const document = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const target = WebsiteCanvasLayerTarget(
      document: document,
      layerId: 'layer-a',
    );
    const session = WebsiteCanvasManipulationSession(
      target: target,
      mode: WebsiteCanvasManipulationMode.move,
      viewport: WebsiteViewport.mobile,
      generation: 1,
    );
    final spy = _Spy();
    final controller = await _pumpScrollableCanvas(
      tester,
      spy: spy,
      documentTarget: document,
      manipulationSession: session,
    );
    addTearDown(controller.dispose);

    await _pointerDrag(
      tester,
      _layer('layer-a'),
      const <Offset>[Offset(40, 0), Offset(0, -50)],
      buttons: 0,
    );

    expect(controller.offset, 0);
    expect(spy.layerWrites, hasLength(1));
    expect(spy.layerWrites.single.layerId, 'layer-a');
    expect(spy.layerWrites.single.values.keys.toSet(), <String>{'x', 'y'});
    expect(spy.layerWrites.single.viewport, WebsiteViewport.mobile);
    expect(spy.wholeListWrites, 0);
  });

  testWidgets('a session for Canvas A cannot arm retained selection in B',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const documentA = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const documentB = WebsiteCanvasDocumentTarget(blockId: 'canvas-b');
    const sessionA = WebsiteCanvasManipulationSession(
      target: WebsiteCanvasLayerTarget(
        document: documentA,
        layerId: 'layer-a',
      ),
      mode: WebsiteCanvasManipulationMode.move,
      viewport: WebsiteViewport.mobile,
      generation: 1,
    );
    final spyB = _Spy();
    final controller = await _pumpScrollableCanvas(
      tester,
      spy: spyB,
      documentTarget: documentB,
      manipulationSession: sessionA,
    );
    addTearDown(controller.dispose);

    await _pointerDrag(
      tester,
      _layer('layer-a'),
      const <Offset>[Offset(0, -40), Offset(0, -80)],
    );

    expect(controller.offset, greaterThan(0));
    expect(spyB.layerWrites, isEmpty);
    expect(spyB.wholeListWrites, 0);
  });

  testWidgets('selected resize and rotation handles also yield in browse',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final handleKey in const <String>[
      'resize_bottomRight_layer-a',
      'rotation_handle_layer-a',
    ]) {
      final spy = _Spy();
      final controller = await _pumpScrollableCanvas(
        tester,
        spy: spy,
        documentTarget: const WebsiteCanvasDocumentTarget(blockId: 'canvas-a'),
      );
      final handle = find.byKey(ValueKey<String>(handleKey));
      expect(handle, findsOneWidget);

      await _pointerDrag(
        tester,
        handle,
        const <Offset>[Offset(0, -40), Offset(0, -80)],
      );

      expect(
        controller.offset,
        greaterThan(0),
        reason: '$handleKey must not win a browse swipe',
      );
      expect(spy.layerWrites, isEmpty);
      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('exact resize and rotate sessions each commit once',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const document = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const target = WebsiteCanvasLayerTarget(
      document: document,
      layerId: 'layer-a',
    );

    for (final entry in const <({
      WebsiteCanvasManipulationMode mode,
      String handleKey,
      Set<String> keys,
      List<Offset> deltas,
    })>[
      (
        mode: WebsiteCanvasManipulationMode.resize,
        handleKey: 'resize_bottomRight_layer-a',
        keys: <String>{'x', 'y', 'w', 'h'},
        deltas: <Offset>[Offset(30, 20), Offset(20, 10)],
      ),
      (
        mode: WebsiteCanvasManipulationMode.rotate,
        handleKey: 'rotation_handle_layer-a',
        keys: <String>{'rotation'},
        deltas: <Offset>[Offset(50, 0), Offset(0, 60)],
      ),
    ]) {
      final spy = _Spy();
      final controller = await _pumpScrollableCanvas(
        tester,
        spy: spy,
        documentTarget: document,
        manipulationSession: WebsiteCanvasManipulationSession(
          target: target,
          mode: entry.mode,
          viewport: WebsiteViewport.mobile,
          generation: 1,
        ),
      );
      final handle = find.byKey(ValueKey<String>(entry.handleKey));
      expect(handle, findsOneWidget);

      await _pointerDrag(
        tester,
        handle,
        entry.deltas,
        buttons: 0,
      );

      expect(controller.offset, 0);
      expect(
        spy.layerWrites,
        hasLength(1),
        reason: '${entry.handleKey} must commit one command',
      );
      expect(spy.layerWrites.single.values.keys.toSet(), entry.keys);
      expect(spy.layerWrites.single.viewport, WebsiteViewport.mobile);
      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('compact resize has one owner and resolves all eight intentions',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final previousFatalSetting = WidgetController.hitTestWarningShouldBeFatal;
    addTearDown(
      () => WidgetController.hitTestWarningShouldBeFatal = previousFatalSetting,
    );
    WidgetController.hitTestWarningShouldBeFatal = true;
    const documentTarget = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const target = WebsiteCanvasLayerTarget(
      document: documentTarget,
      layerId: 'layer-a',
    );
    const cases = <({Alignment alignment, Offset delta})>[
      (alignment: Alignment.topLeft, delta: Offset(-16, -16)),
      (alignment: Alignment.topCenter, delta: Offset(0, -16)),
      (alignment: Alignment.topRight, delta: Offset(16, -16)),
      (alignment: Alignment.centerRight, delta: Offset(16, 0)),
      (alignment: Alignment.bottomRight, delta: Offset(16, 16)),
      (alignment: Alignment.bottomCenter, delta: Offset(0, 16)),
      (alignment: Alignment.bottomLeft, delta: Offset(-16, 16)),
      (alignment: Alignment.centerLeft, delta: Offset(-16, 0)),
    ];

    for (final originalHeight in const <double>[56, 72]) {
      for (final testCase in cases) {
        final spy = _Spy();
        final controller = await _pumpScrollableCanvas(
          tester,
          spy: spy,
          documentTarget: documentTarget,
          manipulationSession: const WebsiteCanvasManipulationSession(
            target: target,
            mode: WebsiteCanvasManipulationMode.resize,
            viewport: WebsiteViewport.mobile,
            generation: 1,
          ),
          document: _shortResizeDocument(height: originalHeight),
        );
        final surface = find.byKey(const ValueKey('resize_surface_layer-a'));
        expect(surface, findsOneWidget);
        final rect = tester.getRect(surface);
        final point = Offset(
          switch (testCase.alignment.x) {
            -1 => rect.left + 2,
            0 => rect.center.dx,
            _ => rect.right - 2,
          },
          switch (testCase.alignment.y) {
            -1 => rect.top + 2,
            0 => rect.center.dy,
            _ => rect.bottom - 2,
          },
        );
        final gesture = await tester.startGesture(
          point,
          kind: PointerDeviceKind.touch,
          buttons: 0,
        );
        await gesture.moveBy(testCase.delta);
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(spy.layerWrites, hasLength(1));
        final values = spy.layerWrites.single.values;
        final x = (values['x']! as num).toDouble();
        final y = (values['y']! as num).toDouble();
        final w = (values['w']! as num).toDouble();
        final h = (values['h']! as num).toDouble();
        if (testCase.alignment.x < 0) {
          expect(x, lessThan(80.0));
          expect(w, greaterThan(120.0));
        } else if (testCase.alignment.x > 0) {
          expect(x, 80.0);
          expect(w, greaterThan(120.0));
        } else {
          expect(x, 80.0);
          expect(w, 120.0);
        }
        if (testCase.alignment.y < 0) {
          expect(y, lessThan(80.0));
          expect(h, greaterThan(originalHeight));
        } else if (testCase.alignment.y > 0) {
          expect(y, 80.0);
          expect(h, greaterThan(originalHeight));
        } else {
          expect(y, 80.0);
          expect(h, originalHeight);
        }
        expect(spy.wholeListWrites, 0);

        controller.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('compact resize leases the handle at pointer-down',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const documentTarget = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const target = WebsiteCanvasLayerTarget(
      document: documentTarget,
      layerId: 'layer-a',
    );
    final spy = _Spy();
    final controller = await _pumpScrollableCanvas(
      tester,
      spy: spy,
      documentTarget: documentTarget,
      manipulationSession: const WebsiteCanvasManipulationSession(
        target: target,
        mode: WebsiteCanvasManipulationMode.resize,
        viewport: WebsiteViewport.mobile,
        generation: 1,
      ),
      document: _shortResizeDocument(),
    );
    addTearDown(controller.dispose);

    final surface = find.byKey(const ValueKey('resize_surface_layer-a'));
    final rect = tester.getRect(surface);
    final gesture = await tester.startGesture(
      rect.bottomRight - const Offset(2, 2),
      kind: PointerDeviceKind.touch,
      buttons: 0,
    );
    // The first move crosses the layer centre. Intent remains bottom-right;
    // it is not recomputed from the post-slop pointer location.
    await gesture.moveBy(const Offset(-80, -80));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(-8, -8));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(spy.layerWrites, hasLength(1));
    final values = spy.layerWrites.single.values;
    expect(values['x'], 80.0);
    expect(values['y'], 80.0);
    expect((values['w']! as num).toDouble(), lessThan(120.0));
    expect((values['h']! as num).toDouble(), lessThan(56.0));
    expect(spy.wholeListWrites, 0);
  });

  testWidgets('24px corner layers keep the compact hit owner inside Canvas',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final previousFatalSetting = WidgetController.hitTestWarningShouldBeFatal;
    addTearDown(
      () => WidgetController.hitTestWarningShouldBeFatal = previousFatalSetting,
    );
    WidgetController.hitTestWarningShouldBeFatal = true;
    const documentTarget = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const target = WebsiteCanvasLayerTarget(
      document: documentTarget,
      layerId: 'layer-a',
    );
    const cases = <({double x, double y, Alignment handle, Offset delta})>[
      (x: 0, y: 0, handle: Alignment.bottomRight, delta: Offset(40, 40)),
      (x: 366, y: 0, handle: Alignment.bottomLeft, delta: Offset(-40, 40)),
      (x: 366, y: 276, handle: Alignment.topLeft, delta: Offset(-40, -40)),
      (x: 0, y: 276, handle: Alignment.topRight, delta: Offset(40, -40)),
    ];

    for (final testCase in cases) {
      final spy = _Spy();
      final controller = await _pumpScrollableCanvas(
        tester,
        spy: spy,
        documentTarget: documentTarget,
        manipulationSession: const WebsiteCanvasManipulationSession(
          target: target,
          mode: WebsiteCanvasManipulationMode.resize,
          viewport: WebsiteViewport.mobile,
          generation: 1,
        ),
        document: _shortResizeDocument(
          x: testCase.x,
          y: testCase.y,
          width: 24,
          height: 24,
        ),
      );
      final surface = find.byKey(const ValueKey('resize_surface_layer-a'));
      final canvasRect = tester.getRect(find.byType(CanvasBlock));
      final surfaceRect = tester.getRect(surface);
      expect(surfaceRect.left, greaterThanOrEqualTo(canvasRect.left));
      expect(surfaceRect.top, greaterThanOrEqualTo(canvasRect.top));
      expect(surfaceRect.right, lessThanOrEqualTo(canvasRect.right));
      expect(surfaceRect.bottom, lessThanOrEqualTo(canvasRect.bottom));

      final layerRect = tester.getRect(_layer('layer-a'));
      final point = Offset(
        switch (testCase.handle.x) {
          -1 => layerRect.left + 2,
          0 => layerRect.center.dx,
          _ => layerRect.right - 2,
        },
        switch (testCase.handle.y) {
          -1 => layerRect.top + 2,
          0 => layerRect.center.dy,
          _ => layerRect.bottom - 2,
        },
      );
      final gesture = await tester.startGesture(
        point,
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await gesture.moveBy(testCase.delta);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spy.layerWrites, hasLength(1), reason: '${testCase.handle}');
      expect(
        spy.layerWrites.single.values.keys.toSet(),
        <String>{'x', 'y', 'w', 'h'},
      );
      expect(spy.wholeListWrites, 0);
      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('rotated compact resize keeps its owner and visual centre',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final previousFatalSetting = WidgetController.hitTestWarningShouldBeFatal;
    addTearDown(
      () => WidgetController.hitTestWarningShouldBeFatal = previousFatalSetting,
    );
    WidgetController.hitTestWarningShouldBeFatal = true;
    const documentTarget = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const target = WebsiteCanvasLayerTarget(
      document: documentTarget,
      layerId: 'layer-a',
    );
    const corners = <({double x, double y})>[
      (x: 0, y: 0),
      (x: 366, y: 0),
      (x: 366, y: 276),
      (x: 0, y: 276),
    ];

    for (final corner in corners) {
      final spy = _Spy();
      final controller = await _pumpScrollableCanvas(
        tester,
        spy: spy,
        documentTarget: documentTarget,
        manipulationSession: const WebsiteCanvasManipulationSession(
          target: target,
          mode: WebsiteCanvasManipulationMode.resize,
          viewport: WebsiteViewport.mobile,
          generation: 1,
        ),
        document: _shortResizeDocument(
          x: corner.x,
          y: corner.y,
          width: 24,
          height: 24,
          rotation: 45,
          constrainElementsToSafeArea: false,
        ),
      );
      final surface = find.byKey(const ValueKey('resize_surface_layer-a'));
      final canvasRect = tester.getRect(find.byType(CanvasBlock));
      final surfaceRect = tester.getRect(surface);
      expect(surfaceRect.width, 48.0);
      expect(surfaceRect.height, 48.0);
      expect(surfaceRect.left, greaterThanOrEqualTo(canvasRect.left));
      expect(surfaceRect.top, greaterThanOrEqualTo(canvasRect.top));
      expect(surfaceRect.right, lessThanOrEqualTo(canvasRect.right));
      expect(surfaceRect.bottom, lessThanOrEqualTo(canvasRect.bottom));

      final usesBottomRight = corner.y == 0;
      final layerCenter =
          canvasRect.topLeft + Offset(corner.x + 12, corner.y + 12);
      final startPoint = layerCenter +
          Offset(0, usesBottomRight ? 16.9705627485 : -16.9705627485);
      expect(surfaceRect.contains(startPoint), isTrue, reason: '$corner');
      final gesture = await tester.startGesture(
        startPoint,
        kind: PointerDeviceKind.touch,
        buttons: 0,
      );
      await gesture.moveBy(Offset(0, usesBottomRight ? 40 : -40));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(
        Offset(0, usesBottomRight ? 16.5685424949 : -16.5685424949),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(spy.layerWrites, hasLength(1), reason: '$corner');
      final values = spy.layerWrites.single.values;
      expect(values.keys.toSet(), <String>{'x', 'y', 'w', 'h'});
      expect((values['w']! as num).toDouble(), closeTo(64, 0.01));
      expect((values['h']! as num).toDouble(), closeTo(64, 0.01));
      expect(
        (values['x']! as num).toDouble(),
        closeTo(corner.x - 20, 0.01),
      );
      expect(
        (values['y']! as num).toDouble(),
        closeTo(
          corner.y + (usesBottomRight ? 8.2842712475 : -48.2842712475),
          0.01,
        ),
      );
      expect(spy.wholeListWrites, 0);
      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('rotated normal layer keeps every visible resize corner hittable',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final previousFatalSetting = WidgetController.hitTestWarningShouldBeFatal;
    addTearDown(
      () => WidgetController.hitTestWarningShouldBeFatal = previousFatalSetting,
    );
    WidgetController.hitTestWarningShouldBeFatal = true;
    const documentTarget = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const target = WebsiteCanvasLayerTarget(
      document: documentTarget,
      layerId: 'layer-a',
    );
    final spy = _Spy();
    final controller = await _pumpScrollableCanvas(
      tester,
      spy: spy,
      documentTarget: documentTarget,
      manipulationSession: const WebsiteCanvasManipulationSession(
        target: target,
        mode: WebsiteCanvasManipulationMode.resize,
        viewport: WebsiteViewport.mobile,
        generation: 1,
      ),
      document: _shortResizeDocument(
        x: 100,
        y: 80,
        width: 120,
        height: 56,
        rotation: 45,
        constrainElementsToSafeArea: false,
      ),
    );
    addTearDown(controller.dispose);

    final canvasRect = tester.getRect(find.byType(CanvasBlock));
    final surfaceRect = tester.getRect(
      find.byKey(const ValueKey('resize_surface_layer-a')),
    );
    final paintedBottomRight = canvasRect.topLeft +
        const Offset(160, 108) +
        const Offset(32 / math.sqrt2, 88 / math.sqrt2);
    final rotatedBottomRight = paintedBottomRight - const Offset(0, 2);
    expect(
      surfaceRect.contains(rotatedBottomRight),
      isTrue,
      reason: 'the owner must cover the painted 45-degree corner, not only '
          'the unrotated 120x56 frame',
    );

    final gesture = await tester.startGesture(
      rotatedBottomRight,
      kind: PointerDeviceKind.touch,
      buttons: 0,
    );
    await gesture.moveBy(const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(24, 24));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(spy.layerWrites, hasLength(1));
    expect(
      spy.layerWrites.single.values.keys.toSet(),
      <String>{'x', 'y', 'w', 'h'},
    );
    expect(
      (spy.layerWrites.single.values['w']! as num).toDouble(),
      greaterThan(120),
    );
    expect(spy.wholeListWrites, 0);
  });

  testWidgets('corner layers keep the compact rotate owner actionable',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final previousFatalSetting = WidgetController.hitTestWarningShouldBeFatal;
    addTearDown(
      () => WidgetController.hitTestWarningShouldBeFatal = previousFatalSetting,
    );
    WidgetController.hitTestWarningShouldBeFatal = true;
    const documentTarget = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const target = WebsiteCanvasLayerTarget(
      document: documentTarget,
      layerId: 'layer-a',
    );
    const sizes = <({double width, double height})>[
      (width: 24, height: 24),
      (width: 48, height: 48),
      (width: 72, height: 48),
    ];

    for (final size in sizes) {
      final corners = <({double x, double y})>[
        (x: 0, y: 0),
        (x: 390 - size.width, y: 0),
        (x: 390 - size.width, y: 300 - size.height),
        (x: 0, y: 300 - size.height),
      ];
      for (final corner in corners) {
        final spy = _Spy();
        final controller = await _pumpScrollableCanvas(
          tester,
          spy: spy,
          documentTarget: documentTarget,
          manipulationSession: const WebsiteCanvasManipulationSession(
            target: target,
            mode: WebsiteCanvasManipulationMode.rotate,
            viewport: WebsiteViewport.mobile,
            generation: 1,
          ),
          document: _shortResizeDocument(
            x: corner.x,
            y: corner.y,
            width: size.width,
            height: size.height,
          ),
        );
        final surface = find.byKey(const ValueKey('rotation_handle_layer-a'));
        final canvasRect = tester.getRect(find.byType(CanvasBlock));
        final surfaceRect = tester.getRect(surface);
        expect(surfaceRect.width, 48.0);
        expect(surfaceRect.height, 48.0);
        expect(surfaceRect.left, greaterThanOrEqualTo(canvasRect.left));
        expect(surfaceRect.top, greaterThanOrEqualTo(canvasRect.top));
        expect(surfaceRect.right, lessThanOrEqualTo(canvasRect.right));
        expect(surfaceRect.bottom, lessThanOrEqualTo(canvasRect.bottom));

        final layerCenter = tester.getRect(_layer('layer-a')).center;
        final radial = surfaceRect.center - layerCenter;
        final perpendicular = Offset(-radial.dy, radial.dx) *
            (48 / math.max(1.0, radial.distance));
        final gesture = await tester.startGesture(
          surfaceRect.center,
          kind: PointerDeviceKind.touch,
          buttons: 0,
        );
        await gesture.moveBy(perpendicular);
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(spy.layerWrites, hasLength(1));
        expect(
          spy.layerWrites.single.values.keys.toSet(),
          <String>{'rotation'},
        );
        expect(
          (spy.layerWrites.single.values['rotation']! as num).isFinite,
          isTrue,
        );
        expect(spy.wholeListWrites, 0);
        controller.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('an exact crop session owns the image gesture and commits once',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const document = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const session = WebsiteCanvasManipulationSession(
      target: WebsiteCanvasLayerTarget(
        document: document,
        layerId: 'layer-a',
      ),
      mode: WebsiteCanvasManipulationMode.crop,
      viewport: WebsiteViewport.mobile,
      generation: 1,
    );
    final spy = _Spy();
    final controller = await _pumpScrollableCanvas(
      tester,
      spy: spy,
      documentTarget: document,
      manipulationSession: session,
      document: _touchImageDocument(),
    );
    addTearDown(controller.dispose);

    await _pointerDrag(
      tester,
      _layer('layer-a'),
      const <Offset>[Offset(32, 0), Offset(0, 24)],
      buttons: 0,
    );

    expect(controller.offset, 0);
    expect(spy.layerWrites, hasLength(1));
    expect(
      spy.layerWrites.single.values.keys.toSet(),
      <String>{'fit', 'focalPointX', 'focalPointY'},
    );
    expect(spy.layerWrites.single.values['fit'], 'cover');
    expect(spy.wholeListWrites, 0);
  });

  testWidgets('revoking availability mid-gesture discards the draft',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const document = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const session = WebsiteCanvasManipulationSession(
      target: WebsiteCanvasLayerTarget(
        document: document,
        layerId: 'layer-a',
      ),
      mode: WebsiteCanvasManipulationMode.move,
      viewport: WebsiteViewport.mobile,
      generation: 1,
    );
    final spy = _Spy();
    final controller = await _pumpScrollableCanvas(
      tester,
      spy: spy,
      documentTarget: document,
      manipulationSession: session,
    );
    addTearDown(controller.dispose);

    final gesture = await tester.startGesture(
      tester.getCenter(_layer('layer-a')),
      kind: PointerDeviceKind.touch,
      buttons: 0,
    );
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    spy.manipulationAvailable = false;
    await gesture.up();
    await tester.pumpAndSettle();

    expect(spy.layerWriteAttempts, 0);
    expect(spy.layerWrites, isEmpty);
    expect(spy.wholeListWrites, 0);
  });

  testWidgets('a rejected atomic write never falls back to the whole list',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final spy = _Spy()..layerWriteSucceeds = false;
    await _pump(tester, spy: spy, width: 1440);

    await tester.drag(
      _layer('layer-a'),
      const Offset(60, 40),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(spy.layerWriteAttempts, 1);
    expect(spy.layerWrites, isEmpty);
    expect(spy.wholeListWrites, 0);
  });

  testWidgets('a missing owner document resyncs to empty without a ghost',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const document = WebsiteCanvasDocumentTarget(blockId: 'canvas-a');
    const session = WebsiteCanvasManipulationSession(
      target: WebsiteCanvasLayerTarget(
        document: document,
        layerId: 'layer-a',
      ),
      mode: WebsiteCanvasManipulationMode.move,
      viewport: WebsiteViewport.mobile,
      generation: 1,
    );
    final spy = _Spy()..layerWriteSucceeds = false;
    Map<String, dynamic>? ownerDocument = _touchDocument();
    final controller = await _pumpScrollableCanvas(
      tester,
      spy: spy,
      documentTarget: document,
      manipulationSession: session,
      document: ownerDocument,
      documentReader: () => ownerDocument,
    );
    addTearDown(controller.dispose);

    final gesture = await tester.startGesture(
      tester.getCenter(_layer('layer-a')),
      kind: PointerDeviceKind.touch,
      buttons: 0,
    );
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    ownerDocument = null;
    await gesture.moveBy(const Offset(16, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(spy.layerWriteAttempts, 1);
    expect(spy.layerWrites, isEmpty);
    expect(spy.wholeListWrites, 0);
    expect(
      _layer('layer-a'),
      findsNothing,
      reason: 'readDocument null means the addressed document disappeared',
    );
  });

  testWidgets('the toolbar duplicates and deletes through the commands',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final spy = _Spy();
    await _pump(tester, spy: spy, width: 1440, activeElementId: 'layer-a');

    await _tapToolbar(tester, 'toolbar_duplicate');

    expect(spy.duplicated.length, 1, reason: 'duplicate is a command');
    expect(spy.duplicated.single.layerId, 'layer-a');
    expect(
      spy.selections.last,
      spy.duplicated.single.newLayerId,
      reason: 'only the new identity becomes selected',
    );
    expect(spy.wholeListWrites, 0);

    // The spy does not mutate the document, so the freshly selected copy has
    // no layer and the toolbar rightly hides. Re-mount on a real selection to
    // exercise delete.
    spy.selections.clear();
    await _pump(tester, spy: spy, width: 1440, activeElementId: 'layer-a');
    await _tapToolbar(tester, 'toolbar_delete');

    expect(spy.removed, <String>['layer-a'], reason: 'delete is a command');
    expect(
      spy.selections.last,
      isNull,
      reason: 'deleting the selected layer clears the selection',
    );
    expect(spy.wholeListWrites, 0);
  });

  testWidgets('a refused lifecycle command leaves the selection alone',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final spy = _Spy()..lifecycleSucceeds = false;
    await _pump(tester, spy: spy, width: 1440, activeElementId: 'layer-a');
    spy.selections.clear();

    await _tapToolbar(tester, 'toolbar_duplicate');
    await _tapToolbar(tester, 'toolbar_delete');

    expect(spy.duplicated, isEmpty);
    expect(spy.removed, isEmpty);
    expect(
      spy.selections,
      isEmpty,
      reason: 'selection follows only a command that landed',
    );
    expect(
      spy.wholeListWrites,
      0,
      reason: 'a refusal must not fall back to the whole-list write',
    );
  });

  testWidgets('a cancelled pan writes nothing', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final spy = _Spy();
    await _pump(tester, spy: spy, width: 1440, activeElementId: 'layer-a');

    final gesture = await tester.startGesture(
      tester.getCenter(_layer('layer-a')),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.moveBy(const Offset(50, 50));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(spy.layerWrites, isEmpty, reason: 'cancel must not persist');
    expect(spy.wholeListWrites, 0);
  });
}
