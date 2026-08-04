import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  WebsiteCanvasEditorBinding binding({String? activeElementId}) {
    return WebsiteCanvasEditorBinding(
      activeElementId: activeElementId,
      writeScope: () => scope,
      onActiveElementChanged: selections.add,
      readDocument: () => <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'layer-a'},
        ],
      },
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
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: CanvasBlock(
            data: _document(),
            editable: true,
            accentColor: const Color(0xFF00A09D),
            editorBinding: spy.binding(activeElementId: activeElementId),
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

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('a drag is one atomic command and zero whole-list writes',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final spy = _Spy();
    await _pump(tester, spy: spy, width: 1440, activeElementId: 'layer-a');

    await tester.drag(_layer('layer-a'), const Offset(60, 40));
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
      await tester.drag(_layer('layer-a'), const Offset(30, 20));
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
    await tester.drag(_layer('layer-a'), const Offset(30, 0));
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
    );
    await gesture.moveBy(const Offset(50, 50));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(spy.layerWrites, isEmpty, reason: 'cancel must not persist');
    expect(spy.wholeListWrites, 0);
  });
}
