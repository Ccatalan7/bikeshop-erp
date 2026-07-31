import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_stats_block_content.dart';

Widget _host({
  required Map<String, dynamic> data,
  WebsiteBlockContentPresenters? presenters,
  EdgeInsetsGeometry padding =
      const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: WebsiteStatsBlockContent(
        data: data,
        primaryColor: const Color(0xFF143D59),
        accentColor: const Color(0xFFF4B41A),
        headingFont: 'Inter',
        bodyFont: 'Inter',
        presenters: presenters,
        padding: padding,
      ),
    ),
  );
}

Future<void> _setViewport(WidgetTester tester, double width) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, 1200);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebsiteStatsBlockContent', () {
    testWidgets('uses real width at 1440, 834 and full-width below 600',
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
          expectedCardWidth: 220,
        ),
        (
          width: 834,
          padding: const EdgeInsets.symmetric(
            vertical: 64,
            horizontal: 24,
          ),
          expectedCardWidth: 220,
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
              'title': 'Resultados',
              'metrics': <Map<String, dynamic>>[
                <String, dynamic>{'value': '1200', 'label': 'Bicis'},
                <String, dynamic>{'value': '980', 'label': 'Clientes'},
              ],
            },
          ),
        );

        expect(
          tester.getSize(WebsiteStatsBlockContent.metricKey(0).finder).width,
          closeTo(testCase.expectedCardWidth, 0.01),
        );
        final frame = tester.widget<ConstrainedBox>(
          find.byKey(WebsiteStatsBlockContent.frameKey),
        );
        expect(frame.constraints.maxWidth, 1000);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('an explicit empty canonical collection never revives samples',
        (tester) async {
      await tester.pumpWidget(
        _host(
          data: const <String, dynamic>{
            'metrics': <Map<String, dynamic>>[],
            'stats': <Map<String, dynamic>>[
              <String, dynamic>{
                'value': 'STALE',
                'label': 'No publicar',
              },
            ],
          },
        ),
      );

      expect(find.byKey(WebsiteStatsBlockContent.rootKey), findsOneWidget);
      expect(
        tester.getSize(find.byKey(WebsiteStatsBlockContent.rootKey)),
        Size.zero,
      );
      expect(find.text('STALE'), findsNothing);
      expect(find.text('1200+'), findsNothing);
    });

    testWidgets(
      'legacy collection exposes atomic nested value, suffix and label slots',
      (tester) async {
        final slots = <String, WebsiteInlineTextSlot>{};
        final presenters = WebsiteBlockContentPresenters(
          text: (context, slot) {
            slots[slot.id] = slot;
            return Text(
              slot.displayTransform?.call(slot.value) ?? slot.value,
              style: slot.formatting.applyTo(slot.baseStyle),
              textAlign: slot.textAlign,
            );
          },
        );

        await tester.pumpWidget(
          _host(
            presenters: presenters,
            data: const <String, dynamic>{
              'title': 'Nuestros números',
              'stats': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'metric-a',
                  'value': '1200',
                  'suffix': '+',
                  'label': 'Bicis reparadas',
                  'icon': 'emoji_events',
                  'valueFormatting': <String, dynamic>{'bold': true},
                },
                <String, dynamic>{
                  'id': '',
                  'value': '980',
                  'label': 'Clientes',
                },
              ],
            },
          ),
        );

        expect(find.text('1200'), findsOneWidget);
        expect(find.text('+'), findsOneWidget);
        expect(find.text('Bicis reparadas'), findsOneWidget);
        expect(find.bySemanticsLabel('Trofeo'), findsOneWidget);

        final value = slots['stats.metric.0.value']!;
        final suffix = slots['stats.metric.0.suffix']!;
        final label = slots['stats.metric.0.label']!;
        expect(
          value.repeaterTarget?.collectionKeys,
          <String>['metrics', 'stats', 'items'],
        );
        expect(value.repeaterTarget?.itemIndex, 0);
        expect(value.repeaterTarget?.identityKey, 'id');
        expect(value.repeaterTarget?.identityValue, 'metric-a');
        expect(value.valueKeys, <String>['value']);
        expect(value.formattingKeys, <String>['valueFormatting']);
        expect(suffix.valueKeys, <String>['suffix']);
        expect(suffix.formattingKeys, <String>['suffixFormatting']);
        expect(label.valueKeys, <String>['label']);
        expect(label.formattingKeys, <String>['labelFormatting']);
        expect(
          slots['stats.metric.1.value']?.repeaterTarget?.identityKey,
          isNull,
        );
        expect(slots['stats.metric.1.suffix'], isNull);
      },
    );
  });
}

extension on Key {
  Finder get finder => find.byKey(this);
}
