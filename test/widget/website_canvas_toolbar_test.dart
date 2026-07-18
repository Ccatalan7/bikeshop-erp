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

  testWidgets('image toolbar keeps crop and transform actions together',
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
    expect(find.byKey(const ValueKey('toolbar_rotate_90')), findsOneWidget);
  });
}
