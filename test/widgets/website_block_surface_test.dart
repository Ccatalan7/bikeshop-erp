import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_block_surface_style.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_surface.dart';

void main() {
  testWidgets('surface consumes the viewport resolved by page composition',
      (tester) async {
    final seen = <double, WebsiteBlockSurfaceStyle>{};
    final data = <String, dynamic>{
      'style': <String, dynamic>{'paddingTop': 40},
      'responsive': <String, dynamic>{
        'version': 2,
        'mobile': <String, dynamic>{'surfacePaddingTop': 8},
        'tablet': <String, dynamic>{'surfacePaddingTop': 20},
      },
    };

    Future<void> mount(double width) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 600);
      await tester.pumpWidget(
        MaterialApp(
          home: WebsiteBlockSurface(
            data: data,
            viewport: WebsiteResponsiveDataCodec.viewportForDocumentWidth(
              data,
              width,
            ),
            builder: (context, style) {
              seen[width] = style;
              return const SizedBox(height: 40);
            },
          ),
        ),
      );
    }

    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await mount(390);
    await mount(834);
    await mount(1440);

    expect(seen[390]!.viewport, WebsiteViewport.mobile);
    expect(seen[390]!.paddingTop.value, 8);
    expect(seen[834]!.viewport, WebsiteViewport.tablet);
    expect(seen[834]!.paddingTop.value, 20);
    expect(seen[1440]!.viewport, WebsiteViewport.desktop);
    expect(seen[1440]!.paddingTop.value, 40);
  });

  testWidgets('surface paints frame once and passes its same projection down',
      (tester) async {
    WebsiteBlockSurfaceStyle? received;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 390,
          child: WebsiteBlockSurface(
            data: const <String, dynamic>{
              'style': <String, dynamic>{
                'backgroundColor': '#112233',
                'borderWidth': 2,
                'borderColor': '#445566',
                'borderRadius': 12,
                'shadowEnabled': true,
              },
            },
            viewport: WebsiteViewport.mobile,
            builder: (context, style) {
              received = style;
              return const ColoredBox(
                color: Colors.transparent,
                child: SizedBox(height: 40),
              );
            },
          ),
        ),
      ),
    );

    final surface = tester.widget<Container>(
      find.byKey(WebsiteBlockSurface.fallbackKey),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(received, isNotNull);
    expect(decoration.color, const Color(0xFF112233));
    expect(decoration.border!.top.width, 2);
    expect(decoration.border!.top.style, BorderStyle.solid);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect(decoration.boxShadow, hasLength(1));
    expect(
      find.descendant(
        of: find.byKey(WebsiteBlockSurface.fallbackKey),
        matching: find.byType(WebsiteBlockSurface),
      ),
      findsNothing,
      reason: 'one surface must not wrap another surface',
    );
  });

  testWidgets('Canvas-style opt-out keeps projection but paints no decoration',
      (tester) async {
    WebsiteBlockSurfaceStyle? received;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 390,
          child: WebsiteBlockSurface(
            data: const <String, dynamic>{
              'style': <String, dynamic>{'backgroundColor': '#112233'},
            },
            viewport: WebsiteViewport.mobile,
            paintDecoration: false,
            builder: (context, style) {
              received = style;
              return const SizedBox(height: 40);
            },
          ),
        ),
      ),
    );

    expect(received!.backgroundColor, const Color(0xFF112233));
    expect(find.byType(Container), findsNothing);
    expect(find.byKey(WebsiteBlockSurface.fallbackKey), findsOneWidget);
  });
}
