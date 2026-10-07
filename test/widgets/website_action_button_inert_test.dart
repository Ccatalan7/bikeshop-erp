import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/widgets/website_action_button.dart';

/// The editor's inert copy of a site button (no `onPressed`) wears the colors
/// its block gives it, as the visitor's does: Material's grey disabled look
/// had drawn the video banner's white outline button dark on dark.
void main() {
  for (final variant in WebsiteActionVariant.values) {
    testWidgets('an inert $variant button keeps its block\'s colors',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: WebsiteActionButton(
                action: WebsiteActionValue(
                  label: 'Descubrir más',
                  href: '/productos',
                  variant: variant,
                ),
                onPressed: null,
                backgroundColor: const Color(0xFF0B6E4F),
                foregroundColor: Colors.white,
                outlineColor: Colors.white,
              ),
            ),
          ),
        ),
      );

      final label = find.text('Descubrir más');
      final ink = DefaultTextStyle.of(tester.element(label)).style.color;
      expect(ink, Colors.white);
      if (variant == WebsiteActionVariant.filled) {
        final material = tester.widget<Material>(
          find.descendant(
            of: find.byType(ElevatedButton),
            matching: find.byType(Material),
          ),
        );
        expect(material.color, const Color(0xFF0B6E4F));
      }
    });
  }
}
