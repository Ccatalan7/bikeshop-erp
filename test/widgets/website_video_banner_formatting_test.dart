import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_renderer.dart';

/// The video banner's title and subtitle wear what the inspector's «Formato»
/// saves for them, over the banner's own white, centered type. Until
/// 2026-10-07 the control saved `titleFormatting` and `subtitleFormatting`
/// and neither the canvas nor the public page drew them.
void main() {
  testWidgets('the banner draws its title and subtitle formatting',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => WebsiteBlockRenderer.build(
              context: context,
              blockType: 'videoBanner',
              data: const <String, dynamic>{
                'title': 'Vive la Aventura',
                'subtitle': 'Rodar sin límites',
                'showCta': false,
                'titleFormatting': {'fontSize': 52, 'textColor': 0xFFAB1234},
                'subtitleFormatting': {'bold': true, 'textAlign': 'end'},
              },
              effectiveViewport: WebsiteViewport.desktop,
              primaryColor: Colors.blue,
              accentColor: Colors.green,
              onNavigate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final title = tester.widget<Text>(find.text('Vive la Aventura'));
    expect(title.style?.fontSize, 52);
    expect(title.style?.color, const Color(0xFFAB1234));
    expect(title.textAlign, TextAlign.center);
    final subtitle = tester.widget<Text>(find.text('Rodar sin límites'));
    expect(subtitle.style?.fontWeight, FontWeight.bold);
    expect(subtitle.style?.fontStyle, FontStyle.italic);
    expect(subtitle.textAlign, TextAlign.end);
  });
}
