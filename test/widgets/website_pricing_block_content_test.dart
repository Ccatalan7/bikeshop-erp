import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/widgets/website_action_button.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_pricing_block_content.dart';

Widget _host({
  required Map<String, dynamic> data,
  bool previewMode = false,
  void Function(String route)? onNavigate,
  bool Function(String href)? isNavigationEligible,
  WebsiteBlockContentPresenters? presenters,
  EdgeInsetsGeometry padding =
      const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: WebsitePricingBlockContent(
        data: data,
        primaryColor: const Color(0xFF143D59),
        accentColor: const Color(0xFFF4B41A),
        headingFont: 'Inter',
        bodyFont: 'Inter',
        previewMode: previewMode,
        onNavigate: onNavigate,
        isNavigationEligible: isNavigationEligible,
        presenters: presenters,
        padding: padding,
      ),
    ),
  );
}

Future<void> _setViewport(WidgetTester tester, double width) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, 1800);
  await tester.pump();
}

const _plan = <String, dynamic>{
  'name': 'Mantención',
  'price': '29.990',
  'features': <String>['Frenos', 'Cambios'],
  'ctaText': 'Reservar',
  'ctaLink': '/reservar',
  'actionVariant': 'outline',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebsitePricingBlockContent', () {
    testWidgets('uses 320 cards and full useful width below 600',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final testCase in <({
        double width,
        EdgeInsets padding,
        double expectedCardWidth,
      })>[
        (
          width: 1440,
          padding: const EdgeInsets.symmetric(
            vertical: 64,
            horizontal: 24,
          ),
          expectedCardWidth: 320,
        ),
        (
          width: 834,
          padding: const EdgeInsets.symmetric(
            vertical: 64,
            horizontal: 24,
          ),
          expectedCardWidth: 320,
        ),
        (
          width: 390,
          padding: const EdgeInsets.symmetric(
            vertical: 64,
            horizontal: 16,
          ),
          expectedCardWidth: 358,
        ),
      ]) {
        await _setViewport(tester, testCase.width);
        await tester.pumpWidget(
          _host(
            padding: testCase.padding,
            data: const <String, dynamic>{
              'title': 'Planes',
              'subtitle': 'Elige una alternativa',
              'plans': <Map<String, dynamic>>[
                _plan,
                <String, dynamic>{
                  'name': 'Full Service',
                  'price': '59.990',
                  'features': <String>['Servicio completo'],
                  'ctaText': 'Reservar',
                  'ctaLink': '/reservar',
                  'highlighted': true,
                },
              ],
            },
          ),
        );

        expect(
          tester
              .getSize(
                find.byKey(WebsitePricingBlockContent.planKey(0)),
              )
              .width,
          closeTo(testCase.expectedCardWidth, 0.01),
        );
        final frame = tester.widget<ConstrainedBox>(
          find.byKey(WebsitePricingBlockContent.frameKey),
        );
        expect(frame.constraints.maxWidth, 1100);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('canonical empty plans never revive items or preview samples',
        (tester) async {
      await tester.pumpWidget(
        _host(
          previewMode: true,
          data: const <String, dynamic>{
            'plans': <Map<String, dynamic>>[],
            'items': <Map<String, dynamic>>[
              <String, dynamic>{'name': 'Stale'},
            ],
          },
        ),
      );

      expect(
        tester.getSize(find.byKey(WebsitePricingBlockContent.rootKey)),
        Size.zero,
      );
      expect(find.text('Stale'), findsNothing);
      expect(find.text('Mantención Básica'), findsNothing);
    });

    testWidgets('a persisted empty plan adds no public editor guidance',
        (tester) async {
      await tester.pumpWidget(
        _host(
          data: const <String, dynamic>{
            'title': 'Planes',
            'plans': <Map<String, dynamic>>[
              <String, dynamic>{},
            ],
          },
        ),
      );

      expect(find.text('Plan'), findsNothing);
      expect(find.text('CLP 0'), findsNothing);
      expect(find.text('Agrega beneficios desde el editor.'), findsNothing);
      expect(find.text('Seleccionar'), findsNothing);
      expect(
        find.byKey(WebsitePricingBlockContent.actionKey(0)),
        findsNothing,
      );
    });

    testWidgets('legacy items, aliases and highlighted state remain visible',
        (tester) async {
      await tester.pumpWidget(
        _host(
          data: const <String, dynamic>{
            'title': 'Planes',
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'Legacy',
                'price': '19.990',
                'features': <String>['Ajuste'],
                'buttonText': 'Abrir',
                'buttonLink': '/legacy',
                'actionVariant': 'text',
                'isFeatured': true,
              },
            ],
          },
          onNavigate: (_) {},
        ),
      );

      expect(find.text('Legacy'), findsOneWidget);
      expect(find.text('CLP 19.990'), findsOneWidget);
      expect(find.text('Ajuste'), findsOneWidget);
      expect(find.text('Más popular'), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
      final action = tester.widget<WebsiteActionButton>(
        find.byType(WebsiteActionButton),
      );
      expect(action.action.label, 'Abrir');
      expect(action.action.href, '/legacy');
      expect(action.action.variant, WebsiteActionVariant.text);
    });

    testWidgets('Public navigates once while Preview and ineligible do not',
        (tester) async {
      final routes = <String>[];
      const data = <String, dynamic>{
        'plans': <Map<String, dynamic>>[_plan],
      };

      await tester.pumpWidget(
        _host(
          data: data,
          onNavigate: routes.add,
          isNavigationEligible: (_) => true,
        ),
      );
      await tester.tap(
        find.byKey(WebsitePricingBlockContent.actionKey(0)),
      );
      expect(routes, <String>['/reservar']);

      await tester.pumpWidget(
        _host(
          data: data,
          previewMode: true,
          onNavigate: routes.add,
          isNavigationEligible: (_) => true,
        ),
      );
      final previewButton = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(previewButton.onPressed, isNull);
      await tester.tap(
        find.byKey(WebsitePricingBlockContent.actionKey(0)),
      );
      expect(routes, <String>['/reservar']);

      await tester.pumpWidget(
        _host(
          data: data,
          onNavigate: routes.add,
          isNavigationEligible: (_) => false,
        ),
      );
      expect(
        find.byKey(WebsitePricingBlockContent.actionKey(0)),
        findsNothing,
      );
    });

    testWidgets('empty href stays absent from shared Public and Edit geometry',
        (tester) async {
      const data = <String, dynamic>{
        'plans': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Consulta',
            'price': '0',
            'ctaText': 'Hablar',
            'ctaLink': '',
          },
        ],
      };
      await tester.pumpWidget(
        _host(
          data: data,
          onNavigate: (_) => fail('An empty pricing action cannot navigate.'),
        ),
      );

      expect(
        find.byKey(WebsitePricingBlockContent.actionKey(0)),
        findsNothing,
      );

      await tester.pumpWidget(
        _host(
          data: data,
          onNavigate: (_) => fail('An empty pricing action cannot navigate.'),
          presenters: WebsiteBlockContentPresenters(
            action: (context, slot) => slot.child,
          ),
        ),
      );

      expect(
        find.byKey(WebsitePricingBlockContent.actionKey(0)),
        findsNothing,
      );
    });

    testWidgets('nested text/action slots carry aliases and formatting keys',
        (tester) async {
      final textSlots = <String, WebsiteInlineTextSlot>{};
      final actionSlots = <String, WebsiteInlineActionSlot>{};
      var navigations = 0;
      final presenters = WebsiteBlockContentPresenters(
        text: (context, slot) {
          textSlots[slot.id] = slot;
          return Text(
            slot.displayTransform?.call(slot.value) ?? slot.value,
            style: slot.formatting.applyTo(slot.baseStyle),
          );
        },
        action: (context, slot) {
          actionSlots[slot.id] = slot;
          return slot.child;
        },
      );

      await tester.pumpWidget(
        _host(
          presenters: presenters,
          onNavigate: (_) => navigations += 1,
          data: const <String, dynamic>{
            'title': 'Planes',
            'plans': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'plan-a',
                ..._plan,
                'nameFormatting': <String, dynamic>{'bold': true},
              },
              <String, dynamic>{
                'id': '',
                ..._plan,
              },
            ],
          },
        ),
      );

      final name = textSlots['pricing.plan.0.name']!;
      final price = textSlots['pricing.plan.0.price']!;
      expect(name.valueKeys, <String>['name']);
      expect(name.formattingKeys, <String>['nameFormatting']);
      expect(price.valueKeys, <String>['price']);
      expect(price.formattingKeys, <String>['priceFormatting']);
      expect(
        name.repeaterTarget?.collectionKeys,
        <String>['plans', 'items'],
      );
      expect(name.repeaterTarget?.identityKey, 'id');
      expect(name.repeaterTarget?.identityValue, 'plan-a');

      final actionSlot = actionSlots['pricing.plan.0.action'];
      expect(actionSlot?.id, 'pricing.plan.0.action');
      expect(
        actionSlot?.labelKeys,
        <String>['ctaText', 'buttonText'],
      );
      expect(
        actionSlot?.hrefKeys,
        <String>['ctaLink', 'buttonLink'],
      );
      expect(actionSlot?.variantKeys, <String>['actionVariant']);
      expect(actionSlot?.actionsKey, 'actions');
      expect(
        actionSlot?.repeaterTarget?.collectionKeys,
        <String>['plans', 'items'],
      );
      expect(
        textSlots['pricing.plan.1.name']?.repeaterTarget?.identityKey,
        isNull,
      );

      await tester.tap(
        find.byKey(WebsitePricingBlockContent.actionKey(0)),
      );
      expect(navigations, 0);
    });
  });
}
