import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_surface.dart';
import 'package:vinabike_erp/modules/website/widgets/website_cta_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_pricing_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_testimonials_block_content.dart';
import 'package:vinabike_erp/public_store/widgets/page_composition.dart';

enum _RenderMode { edit, preview, public }

void main() {
  const data = <String, dynamic>{
    'title': 'Una superficie',
    'subtitle': 'El contenido es idéntico en los tres consumidores.',
    'style': <String, dynamic>{
      'backgroundColor': '#FF112233',
      'paddingTop': 40,
      'paddingRight': 30,
      'paddingBottom': 20,
      'paddingLeft': 10,
      'borderWidth': 2,
      'borderColor': '#FF445566',
      'borderStyle': 'solid',
      'borderRadius': 12,
      'shadowEnabled': true,
      'shadowOffsetY': 4,
      'shadowBlur': 12,
    },
    'responsive': <String, dynamic>{
      'version': 2,
      'mobile': <String, dynamic>{
        'surfacePaddingTop': 8,
        'surfacePaddingLeft': 6,
      },
      'tablet': <String, dynamic>{
        'surfacePaddingRight': 18,
      },
    },
  };

  Widget host({
    required double width,
    required _RenderMode mode,
    String blockType = 'cta',
    Map<String, dynamic> blockData = data,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Builder(
              builder: (context) => WebsiteBlockRenderer.build(
                context: context,
                blockType: blockType,
                data: blockData,
                effectiveViewport:
                    WebsiteResponsiveDataCodec.viewportForDocumentWidth(
                  blockData,
                  width,
                ),
                primaryColor: const Color(0xFF143D59),
                accentColor: const Color(0xFFF4B41A),
                previewMode: mode != _RenderMode.public,
                contentPresenters: mode == _RenderMode.edit
                    ? const WebsiteBlockContentPresenters()
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Edit Preview Public share one surface at 390 834 and 1440',
      (tester) async {
    for (final width in <double>[390, 834, 1440]) {
      ({
        Color? color,
        double border,
        BorderRadiusGeometry? radius,
        int shadows,
        EdgeInsets padding,
        Size size,
      })? baseline;

      for (final mode in _RenderMode.values) {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = Size(width, 1000);
        await tester.pumpWidget(host(width: width, mode: mode));
        await tester.pump();

        expect(find.byType(WebsiteBlockSurface), findsOneWidget);
        expect(find.byKey(WebsiteBlockSurface.fallbackKey), findsOneWidget);
        final surface = tester.widget<Container>(
          find.byKey(WebsiteBlockSurface.fallbackKey),
        );
        final decoration = surface.decoration! as BoxDecoration;
        final contentPadding = tester.widget<Padding>(
          find.byKey(WebsiteCtaBlockContent.paddingKey),
        );
        final signature = (
          color: decoration.color,
          border: decoration.border!.top.width,
          radius: decoration.borderRadius,
          shadows: decoration.boxShadow!.length,
          padding: contentPadding.padding as EdgeInsets,
          size: tester.getSize(find.byKey(WebsiteBlockSurface.fallbackKey)),
        );

        baseline ??= signature;
        expect(signature, baseline, reason: '$width $mode');
        expect(
          find.descendant(
            of: find.byKey(WebsiteBlockSurface.fallbackKey),
            matching: find.byType(WebsiteBlockSurface),
          ),
          findsNothing,
          reason: '$width $mode never nests or double-paints the surface',
        );
        expect(tester.takeException(), isNull);
      }

      expect(
        baseline!.padding,
        switch (width) {
          390 => const EdgeInsets.fromLTRB(6, 8, 30, 20),
          834 => const EdgeInsets.fromLTRB(10, 40, 18, 20),
          _ => const EdgeInsets.fromLTRB(10, 40, 30, 20),
        },
      );
    }
    addTearDown(tester.view.reset);
  });

  testWidgets(
      'PageComposition keeps the canvas viewport after block edge padding',
      (tester) async {
    final composition = WebsitePageComposition.project(
      blocks: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'surface-owner',
          'block_type': 'cta',
          'order_index': 0,
          'is_visible': true,
          'block_data': <String, dynamic>{
            'title': 'Viewport owner',
            'style': <String, dynamic>{
              'paddingLeft': 31,
              'paddingTop': 0,
              'paddingRight': 0,
              'paddingBottom': 0,
            },
            'responsive': <String, dynamic>{
              'version': 2,
              'mobile': <String, dynamic>{'surfacePaddingLeft': 7},
              'tablet': <String, dynamic>{'surfacePaddingLeft': 19},
            },
          },
        },
      ],
      mode: WebsitePageCompositionMode.public,
      breakpoint: 'desktop',
    );

    Future<EdgeInsets> paddingAt(double width) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = Size(width, 600);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageComposition(
              composition: composition,
              primaryColor: Colors.blue,
              accentColor: Colors.orange,
              textColor: Colors.black,
              containerPadding: 24,
            ),
          ),
        ),
      );
      await tester.pump();
      return tester
          .widget<Padding>(find.byKey(WebsiteCtaBlockContent.paddingKey))
          .padding as EdgeInsets;
    }

    expect(
      (await paddingAt(620)).left,
      19,
      reason: '620 is Tablet even though the padded content is only 572 px',
    );
    expect(
      (await paddingAt(920)).left,
      31,
      reason: '920 is Desktop even though the padded content is only 872 px',
    );
    expect(tester.takeException(), isNull);
    addTearDown(tester.view.reset);
  });

  testWidgets('legacy page Footer opts out and remains an exact 64 spacer',
      (tester) async {
    const footerData = <String, dynamic>{
      'companyName': 'Must not render',
      'style': <String, dynamic>{
        'backgroundColor': '#FFFF0000',
        'paddingTop': 180,
        'paddingBottom': 180,
        'borderWidth': 12,
      },
    };
    await tester.pumpWidget(
      host(
        width: 390,
        mode: _RenderMode.public,
        blockType: 'footer',
        blockData: footerData,
      ),
    );
    await tester.pump();

    expect(find.byType(WebsiteBlockSurface), findsOneWidget);
    expect(
      tester.getSize(find.byKey(WebsiteBlockSurface.fallbackKey)).height,
      64,
    );
    expect(find.text('Must not render'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color ==
                const Color(0xFFFF0000),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Testimonials and Pricing expose authored background to the one surface '
      'and retain their fallback', (tester) async {
    final families = <({
      String type,
      Map<String, dynamic> data,
      Key rootKey,
    })>[
      (
        type: 'testimonials',
        data: <String, dynamic>{
          'title': 'Testimonios',
          'testimonials': <Map<String, dynamic>>[
            <String, dynamic>{'name': 'Ana', 'comment': 'Excelente'},
          ],
        },
        rootKey: WebsiteTestimonialsBlockContent.rootKey,
      ),
      (
        type: 'pricing',
        data: <String, dynamic>{
          'title': 'Planes',
          'plans': <Map<String, dynamic>>[
            <String, dynamic>{'name': 'Base', 'price': '10'},
          ],
        },
        rootKey: WebsitePricingBlockContent.rootKey,
      ),
    ];

    for (final family in families) {
      for (final mode in _RenderMode.values) {
        final authored = <String, dynamic>{
          ...family.data,
          'style': <String, dynamic>{'backgroundColor': '#FF112233'},
        };
        await tester.pumpWidget(
          host(
            width: 834,
            mode: mode,
            blockType: family.type,
            blockData: authored,
          ),
        );
        await tester.pump();

        final surface = tester.widget<Container>(
          find.byKey(WebsiteBlockSurface.fallbackKey),
        );
        expect((surface.decoration! as BoxDecoration).color,
            const Color(0xFF112233));
        final contentBackground = tester.widget<ColoredBox>(
          find
              .ancestor(
                of: find.byKey(family.rootKey),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        expect(contentBackground.color, Colors.transparent,
            reason: '${family.type} $mode must not cover the surface owner');
      }

      await tester.pumpWidget(
        host(
          width: 834,
          mode: _RenderMode.public,
          blockType: family.type,
          blockData: family.data,
        ),
      );
      await tester.pump();
      final fallbackBackground = tester.widget<ColoredBox>(
        find
            .ancestor(
              of: find.byKey(family.rootKey),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(fallbackBackground.color, isNot(Colors.transparent),
          reason: '${family.type} keeps its established unstyled fallback');
      expect(tester.takeException(), isNull);
    }
  });
}
