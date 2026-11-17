import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_page_image_field.dart';

Widget _host(WebsitePageImageField field) => MaterialApp(
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: field),
      ),
    );

void main() {
  testWidgets('a page without a photo offers to choose one, nothing to remove',
      (tester) async {
    var picks = 0;
    await tester.pumpWidget(
      _host(
        WebsitePageImageField(
          url: '',
          isGuide: true,
          enabled: true,
          onPick: () => picks++,
          onClear: () => fail('nothing to remove'),
        ),
      ),
    );

    expect(find.text('Foto de la página'), findsOneWidget);
    expect(find.text('Quitar'), findsNothing);
    // A guide says where its photo shows: its rows in /guias.
    expect(find.textContaining('/guias'), findsOneWidget);
    await tester.tap(find.text('Elegir foto'));
    expect(picks, 1);
  });

  testWidgets('a page with a photo can change it or remove it', (tester) async {
    var picks = 0;
    var clears = 0;
    await tester.pumpWidget(
      _host(
        WebsitePageImageField(
          url: 'https://cdn.example/caliper.png',
          isGuide: false,
          enabled: true,
          onPick: () => picks++,
          onClear: () => clears++,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Se ve al compartir el enlace de la página.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cambiar foto'));
    await tester.tap(find.text('Quitar'));
    expect((picks, clears), (1, 1));
  });

  testWidgets('while the page saves, its photo does not change',
      (tester) async {
    await tester.pumpWidget(
      _host(
        WebsitePageImageField(
          url: 'https://cdn.example/caliper.png',
          isGuide: true,
          enabled: false,
          onPick: () => fail('saving'),
          onClear: () => fail('saving'),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Cambiar foto'), warnIfMissed: false);
    await tester.tap(find.text('Quitar'), warnIfMissed: false);
  });
}
