import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/canvas_block_toolbar.dart';

void main() {
  testWidgets('image toolbar exposes the canonical replace action',
      (tester) async {
    var replacements = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: CanvasElementToolbar(
              type: 'image',
              properties: const {
                'fit': 'contain',
                'rotation': 0.0,
              },
              maxWidth: 640,
              onReplaceImage: () => replacements++,
              onDelete: () {},
              onDuplicate: () {},
              onBringToFront: () {},
              onSendToBack: () {},
              onMoveForward: () {},
              onMoveBackward: () {},
              onRotateQuarterTurn: () {},
              onAlign: (_) {},
              onUpdate: (_, __) {},
            ),
          ),
        ),
      ),
    );

    final replace = find.byKey(const ValueKey('toolbar_replace_image'));
    expect(replace, findsOneWidget);
    await tester.tap(replace);
    expect(replacements, 1);
  });

  testWidgets(
      'image toolbar keeps crop direct and precise transforms one level away',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasElementToolbar(
            type: 'image',
            properties: const {'fit': 'cover'},
            maxWidth: 720,
            onDelete: () {},
            onDuplicate: () {},
            onBringToFront: () {},
            onSendToBack: () {},
            onMoveForward: () {},
            onMoveBackward: () {},
            onRotateQuarterTurn: () {},
            onAlign: (_) {},
            onToggleCrop: () {},
            onUpdate: (_, __) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('toolbar_crop')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toolbar_more')));
    await tester.pump();
    expect(find.byKey(const ValueKey('toolbar_rotate_90')), findsOneWidget);
  });

  testWidgets('relative layer order is always directly available',
      (tester) async {
    var backward = 0;
    var forward = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasElementToolbar(
            type: 'shape',
            properties: const {'shape': 'rectangle'},
            maxWidth: 720,
            onDelete: () {},
            onDuplicate: () {},
            onBringToFront: () {},
            onSendToBack: () {},
            onMoveForward: () => forward++,
            onMoveBackward: () => backward++,
            onRotateQuarterTurn: () {},
            onAlign: (_) {},
            onUpdate: (_, __) {},
          ),
        ),
      ),
    );

    final moveBackward = find.byKey(const ValueKey('toolbar_move_backward'));
    final moveForward = find.byKey(const ValueKey('toolbar_move_forward'));
    expect(moveBackward, findsOneWidget);
    expect(moveForward, findsOneWidget);
    await tester.tap(moveBackward);
    await tester.tap(moveForward);
    expect(backward, 1);
    expect(forward, 1);
  });

  testWidgets(
      'arrange palette exposes extremes and canvas alignment in one step',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasElementToolbar(
            type: 'button',
            properties: const {'style': 'filled'},
            maxWidth: 720,
            onDelete: () {},
            onDuplicate: () {},
            onBringToFront: () {},
            onSendToBack: () {},
            onMoveForward: () {},
            onMoveBackward: () {},
            onRotateQuarterTurn: () {},
            onAlign: (_) {},
            onUpdate: (_, __) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('toolbar_arrange')));
    await tester.pump();

    expect(find.byKey(const ValueKey('toolbar_send_to_back')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('toolbar_bring_to_front')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('toolbar_align_left')), findsOneWidget);
    expect(find.byKey(const ValueKey('toolbar_align_bottom')), findsOneWidget);
  });

  testWidgets('text alignment uses a visible palette instead of an icon cycle',
      (tester) async {
    String? updatedAlignment;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasElementToolbar(
            type: 'text',
            properties: const {'align': 'left', 'fontSize': 24.0},
            maxWidth: 720,
            onDelete: () {},
            onDuplicate: () {},
            onBringToFront: () {},
            onSendToBack: () {},
            onMoveForward: () {},
            onMoveBackward: () {},
            onRotateQuarterTurn: () {},
            onAlign: (_) {},
            onUpdate: (key, value) {
              if (key == 'align') updatedAlignment = value as String;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('toolbar_text_align')));
    await tester.pump();
    final center = find.byKey(const ValueKey('toolbar_text_align_center'));
    expect(center, findsOneWidget);
    await tester.tap(center);
    await tester.pump();
    expect(updatedAlignment, 'center');
    expect(find.byKey(const ValueKey('toolbar_move_forward')), findsOneWidget);
  });
}
