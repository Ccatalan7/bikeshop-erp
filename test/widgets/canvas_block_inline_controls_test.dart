import 'package:vinabike_erp/modules/website/models/canvas_element_factory.dart';
import 'package:vinabike_erp/modules/website/widgets/canvas_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical Canvas factory gives every layer shared transform state', () {
    for (final type in const [
      'text',
      'image',
      'button',
      'shape',
      'product',
      'productsGallery',
    ]) {
      final element = createCanvasElement(id: 'layer-$type', type: type);
      expect(element['rotation'], 0.0, reason: type);
      expect(element['locked'], isFalse, reason: type);
    }

    final image = createCanvasElement(id: 'image', type: 'image');
    expect(image['fit'], 'cover');
    expect(image['focalPointX'], 0.5);
    expect(image['focalPointY'], 0.5);
  });

  testWidgets(
      'selected image exposes eight frame handles, rotation, and crop reframe',
      (tester) async {
    List<Map<String, dynamic>> latest = [];
    final image = createCanvasElement(id: 'image-1', type: 'image')
      ..addAll({
        'x': 140.0,
        'y': 100.0,
        'w': 320.0,
        'h': 200.0,
      });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 800,
              child: CanvasBlock(
                data: {
                  'blockHeight': 500.0,
                  'designWidth': 800.0,
                  'activeElementId': 'image-1',
                  'elements': [image],
                },
                editable: true,
                accentColor: const Color(0xFF00A09D),
                onElementsChanged: (elements) => latest = elements,
                clipContentToBounds: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final handle in const [
      'topLeft',
      'top',
      'topRight',
      'right',
      'bottomRight',
      'bottom',
      'bottomLeft',
      'left',
    ]) {
      expect(find.byKey(ValueKey('resize_${handle}_image-1')), findsOneWidget);
    }
    expect(
        find.byKey(const ValueKey('rotation_handle_image-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('toolbar_crop')), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
    expect(find.byType(PopupMenuButton), findsNothing);

    await tester.tap(find.byKey(const ValueKey('toolbar_crop')));
    await tester.pump();

    for (final handle in const [
      'topLeft',
      'top',
      'topRight',
      'right',
      'bottomRight',
      'bottom',
      'bottomLeft',
      'left',
    ]) {
      expect(find.byKey(ValueKey('crop_${handle}_image-1')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('rotation_handle_image-1')), findsNothing);
    expect(find.text('RECORTE · ARRASTRA LA IMAGEN'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('canvas_el_image-1')),
      const Offset(48, 0),
    );
    await tester.pump();
    expect(latest, isNotEmpty);
    expect((latest.single['focalPointX'] as num).toDouble(), lessThan(0.5));

    final widthBefore = (latest.single['w'] as num).toDouble();
    await tester.drag(
      find.byKey(const ValueKey('crop_right_image-1')),
      const Offset(40, 0),
    );
    await tester.pump();
    expect((latest.single['w'] as num).toDouble(), greaterThan(widthBefore));

    await tester.tap(find.byKey(const ValueKey('toolbar_crop')));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('rotation_handle_image-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toolbar_more')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar_rotate_90')));
    await tester.pump();
    expect((latest.single['rotation'] as num).toDouble(), 90);

    await tester.tap(find.byKey(const ValueKey('toolbar_back')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('toolbar_arrange')));
    await tester.pump();
    expect(find.byKey(const ValueKey('toolbar_align_left')), findsOneWidget);
    expect(find.byKey(const ValueKey('toolbar_send_to_back')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('toolbar_bring_to_front')), findsOneWidget);
    expect(find.byType(PopupMenuButton), findsNothing);

    await tester.tap(find.byKey(const ValueKey('toolbar_align_left')));
    await tester.pump();
    expect((latest.single['x'] as num).toDouble(), 0);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('rotation handle drag changes and persists the layer rotation',
      (tester) async {
    List<Map<String, dynamic>> latest = [];
    final image = createCanvasElement(id: 'rotating-image', type: 'image')
      ..addAll({
        'x': 180.0,
        'y': 120.0,
        'w': 320.0,
        'h': 220.0,
      });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: CanvasBlock(
                data: {
                  'blockHeight': 720.0,
                  'designWidth': 1200.0,
                  'activeElementId': 'rotating-image',
                  'elements': [image],
                },
                editable: true,
                accentColor: const Color(0xFF00A09D),
                onElementsChanged: (elements) => latest = elements,
                clipContentToBounds: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final handle = find.byKey(const ValueKey('rotation_handle_rotating-image'));
    expect(handle, findsOneWidget);

    // The handle begins above the element center. Moving it down and right
    // sweeps the pointer around that center and must produce a real rotation.
    await tester.drag(handle, const Offset(110, 110));
    await tester.pump();

    expect(latest, isNotEmpty);
    expect(
      ((latest.single['rotation'] as num?)?.toDouble() ?? 0).abs(),
      greaterThan(30),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact layers keep a working rotation target inside bounds',
      (tester) async {
    List<Map<String, dynamic>> latest = [];
    final button = createCanvasElement(id: 'compact-button', type: 'button')
      ..addAll({
        'x': 120.0,
        'y': 80.0,
        'w': 240.0,
        'h': 44.0,
      });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 700,
              child: CanvasBlock(
                data: {
                  'blockHeight': 360.0,
                  'designWidth': 700.0,
                  'activeElementId': 'compact-button',
                  'elements': [button],
                },
                editable: true,
                accentColor: const Color(0xFF00A09D),
                onElementsChanged: (elements) => latest = elements,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final handle = find.byKey(const ValueKey('rotation_handle_compact-button'));
    expect(handle, findsOneWidget);
    final buttonRect =
        tester.getRect(find.byKey(const ValueKey('canvas_el_compact-button')));
    final handleRect = tester.getRect(handle);
    expect(buttonRect.contains(handleRect.topLeft), isTrue);
    expect(buttonRect.contains(handleRect.bottomRight - const Offset(0.1, 0.1)),
        isTrue);

    await tester.drag(handle, const Offset(-70, 70));
    await tester.pump();
    expect(
      ((latest.single['rotation'] as num?)?.toDouble() ?? 0).abs(),
      greaterThan(30),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow Canvas uses overlay-free palettes without layout errors',
      (tester) async {
    List<Map<String, dynamic>> latest = [];
    final image = createCanvasElement(id: 'narrow-image', type: 'image')
      ..addAll({
        'x': 28.0,
        'y': 100.0,
        'w': 210.0,
        'h': 150.0,
      });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: CanvasBlock(
                data: {
                  'blockHeight': 420.0,
                  'designWidth': 280.0,
                  'activeElementId': 'narrow-image',
                  'elements': [image],
                },
                editable: true,
                accentColor: const Color(0xFF00A09D),
                onElementsChanged: (elements) => latest = elements,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final arrange = find.byKey(const ValueKey('toolbar_arrange'));
    await tester.ensureVisible(arrange);
    await tester.pump();
    await tester.tap(arrange);
    await tester.pump();
    final alignLeft = find.byKey(const ValueKey('toolbar_align_left'));
    expect(alignLeft, findsOneWidget);
    await tester.ensureVisible(alignLeft);
    await tester.pump();
    await tester.tap(alignLeft);
    await tester.pump();
    expect((latest.single['x'] as num).toDouble(), 0);
    expect(find.byType(PopupMenuButton), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
    expect(tester.takeException(), isNull);

    final back = find.byKey(const ValueKey('toolbar_back'));
    await tester.ensureVisible(back);
    await tester.pump();
    await tester.tap(back);
    await tester.pump();
    final delete = find.byKey(const ValueKey('toolbar_delete'));
    await tester.ensureVisible(delete);
    await tester.pump();
    await tester.tap(delete);
    await tester.pump();
    expect(latest, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
