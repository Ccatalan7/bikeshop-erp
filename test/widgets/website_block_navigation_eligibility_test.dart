import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_renderer.dart';

Widget _rendererHost({
  required String blockType,
  required Map<String, dynamic> data,
  required bool Function(String href) isNavigationEligible,
  void Function(String route)? onNavigate,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => WebsiteBlockRenderer.build(
          context: context,
          blockType: blockType,
          data: data,
          primaryColor: Colors.blue,
          accentColor: Colors.green,
          onNavigate: onNavigate ?? (_) {},
          isNavigationEligible: isNavigationEligible,
        ),
      ),
    ),
  );
}

void main() {
  group('WebsiteBlockRenderer navigation eligibility', () {
    test('shared action filter preserves eligible and empty destinations', () {
      const eligible = WebsiteActionValue(
        label: 'Comprar',
        href: '/productos',
      );
      const empty = WebsiteActionValue(
        label: 'Configurar',
        href: '',
      );

      expect(
        WebsiteBlockRenderer.visibleNavigationAction(
          eligible,
          isNavigationEligible: (_) => true,
        ),
        same(eligible),
      );
      expect(
        WebsiteBlockRenderer.visibleNavigationAction(
          eligible,
          isNavigationEligible: (_) => false,
        ),
        isNull,
      );
      expect(
        WebsiteBlockRenderer.visibleNavigationAction(
          empty,
          isNavigationEligible: (_) => false,
        ),
        same(empty),
      );
      expect(
        WebsiteBlockRenderer.visibleNavigationAction(
          eligible,
          isNavigationEligible: null,
        ),
        same(eligible),
      );
    });

    testWidgets('public render removes ineligible CTA affordances',
        (tester) async {
      const hiddenLabel = 'CTA OCULTA';
      final cases = <({String type, Map<String, dynamic> data})>[
        (
          type: 'button',
          data: const <String, dynamic>{
            'label': hiddenLabel,
            'link': '/productos/categoria/pinones',
          },
        ),
        (
          type: 'hero',
          data: const <String, dynamic>{
            'title': 'Hero visible',
            'ctaText': hiddenLabel,
            'ctaLink': '/productos/categoria/pinones',
          },
        ),
        (
          type: 'cta',
          data: const <String, dynamic>{
            'title': 'Campaña visible',
            'buttonText': hiddenLabel,
            'buttonLink': '/productos/categoria/pinones',
          },
        ),
        (
          type: 'carousel',
          data: const <String, dynamic>{
            'autoPlay': false,
            'slides': [
              {
                'title': 'Slide visible',
                'ctaText': hiddenLabel,
                'ctaLink': '/productos/categoria/pinones',
              },
            ],
          },
        ),
        (
          type: 'pricing',
          data: const <String, dynamic>{
            'title': 'Planes visibles',
            'plans': [
              {
                'name': 'Plan visible',
                'price': '10.000',
                'ctaText': hiddenLabel,
                'ctaLink': '/productos/categoria/pinones',
              },
            ],
          },
        ),
        (
          type: 'videoBanner',
          data: const <String, dynamic>{
            'title': 'Video visible',
            'showCta': true,
            'ctaText': hiddenLabel,
            'ctaLink': '/productos/categoria/pinones',
          },
        ),
      ];

      for (final testCase in cases) {
        await tester.pumpWidget(
          _rendererHost(
            blockType: testCase.type,
            data: testCase.data,
            isNavigationEligible: (_) => false,
          ),
        );
        await tester.pump();

        expect(
          find.text(hiddenLabel),
          findsNothing,
          reason: '${testCase.type} exposed an ineligible CTA.',
        );
      }
    });

    testWidgets('Canvas buttons use the same public eligibility boundary',
        (tester) async {
      const hiddenLabel = 'CANVAS OCULTO';
      const canvasData = <String, dynamic>{
        'blockHeight': 240.0,
        'designWidth': 800.0,
        'elements': [
          {
            'id': 'button-1',
            'type': 'button',
            'label': hiddenLabel,
            'link': '/productos/categoria/pinones',
            'x': 20.0,
            'y': 20.0,
            'w': 220.0,
            'h': 56.0,
          },
        ],
      };

      await tester.pumpWidget(
        _rendererHost(
          blockType: 'canvas',
          data: canvasData,
          isNavigationEligible: (_) => false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(hiddenLabel), findsNothing);

      await tester.pumpWidget(
        _rendererHost(
          blockType: 'canvas',
          data: canvasData,
          isNavigationEligible: (_) => true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(hiddenLabel), findsOneWidget);
    });

    testWidgets('composed carousel Canvas cannot restore a hidden CTA',
        (tester) async {
      await tester.pumpWidget(
        _rendererHost(
          blockType: 'carousel',
          data: const <String, dynamic>{
            'autoPlay': false,
            'slides': [
              {
                'title': 'Slide compuesto',
                'useComposition': true,
                'elements': [
                  {
                    'id': 'button-1',
                    'type': 'button',
                    'label': 'CTA COMPUESTO OCULTO',
                    'link': '/productos/categoria/pinones',
                    'x': 20.0,
                    'y': 20.0,
                    'w': 260.0,
                    'h': 56.0,
                  },
                ],
              },
            ],
          },
          isNavigationEligible: (_) => false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CTA COMPUESTO OCULTO'), findsNothing);
    });

    testWidgets('brand artwork stays visible without a dead category link',
        (tester) async {
      var navigations = 0;
      const brandData = <String, dynamic>{
        'title': 'Marcas',
        'brands': [
          {
            'name': 'Marca enlazada',
            'imageUrl': '',
            'link': '/productos/categoria/pinones',
          },
        ],
      };

      await tester.pumpWidget(
        _rendererHost(
          blockType: 'brandLogos',
          data: brandData,
          isNavigationEligible: (_) => false,
          onNavigate: (_) => navigations += 1,
        ),
      );
      await tester.pump();
      expect(find.text('Marca enlazada'), findsOneWidget);
      await tester.tap(find.text('Marca enlazada'));
      expect(navigations, 0);

      await tester.pumpWidget(
        _rendererHost(
          blockType: 'brandLogos',
          data: brandData,
          isNavigationEligible: (_) => true,
          onNavigate: (_) => navigations += 1,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Marca enlazada'));
      expect(navigations, 1);
    });

    testWidgets('contact and team omit ineligible secondary links',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _rendererHost(
          blockType: 'contact',
          data: const <String, dynamic>{
            'showMap': true,
            'mapUrl': '/productos/categoria/pinones',
          },
          isNavigationEligible: (_) => false,
        ),
      );
      await tester.pump();
      expect(find.text('Abrir mapa'), findsNothing);

      await tester.pumpWidget(
        _rendererHost(
          blockType: 'team',
          data: const <String, dynamic>{
            'members': [
              {
                'name': 'Persona',
                'instagram': '/productos/categoria/pinones',
                'linkedin': '/productos/categoria/pinones',
              },
            ],
          },
          isNavigationEligible: (_) => false,
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Instagram'), findsNothing);
      expect(find.byTooltip('LinkedIn'), findsNothing);
    });
  });
}
