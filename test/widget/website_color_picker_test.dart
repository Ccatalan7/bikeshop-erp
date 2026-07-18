import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_color_picker.dart';

void main() {
  test('parses and serializes the editor ARGB compatibility format', () {
    final color = parseWebsiteEditorColor('#8808100D');

    expect((websiteEditorColorOpacity(color) * 100).round(), 53);
    expect(serializeWebsiteEditorColor(color), '#8808100D');
    expect(serializeWebsiteEditorColor(color, includeAlpha: false), '#08100D');
  });

  testWidgets(
    'shows a visual color and explicit opacity before exposing the code',
    (tester) async {
      var value = '#8808100D';

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SizedBox(
                width: 320,
                child: WebsiteColorPickerField(
                  label: 'Color de relleno',
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Opacidad 53%'), findsOneWidget);
      expect(find.text('Código avanzado'), findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey('website_color_picker_Color de relleno'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PALETA DEL SITIO'), findsOneWidget);
      expect(find.text('Código avanzado'), findsOneWidget);
      expect(find.text('Aplicar'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('website_color_swatch_#F0642F')),
      );
      await tester.tap(
        find.byKey(const ValueKey('website_color_picker_apply')),
      );
      await tester.pumpAndSettle();

      expect(value, '#88F0642F');
      expect(find.text('Opacidad 53%'), findsOneWidget);
    },
  );
}
