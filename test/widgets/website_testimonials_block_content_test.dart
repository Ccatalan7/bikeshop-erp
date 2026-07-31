import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_testimonials_block_content.dart';

Widget _host({
  required Map<String, dynamic> data,
  WebsiteBlockContentPresenters? presenters,
  EdgeInsetsGeometry padding =
      const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: WebsiteTestimonialsBlockContent(
        data: data,
        primaryColor: const Color(0xFF143D59),
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
    ..physicalSize = Size(width, 1400);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebsiteTestimonialsBlockContent', () {
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
              'title': 'Testimonios',
              'testimonials': <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': 'Carolina',
                  'role': 'Ciclista',
                  'comment': 'Excelente servicio.',
                  'rating': 5,
                },
                <String, dynamic>{
                  'name': 'Luis',
                  'comment': 'Volveré.',
                  'rating': 4,
                },
              ],
            },
          ),
        );

        expect(
          tester
              .getSize(
                find.byKey(
                  WebsiteTestimonialsBlockContent.testimonialKey(0),
                ),
              )
              .width,
          closeTo(testCase.expectedCardWidth, 0.01),
        );
        final frame = tester.widget<ConstrainedBox>(
          find.byKey(WebsiteTestimonialsBlockContent.frameKey),
        );
        expect(frame.constraints.maxWidth, 1100);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('empty canonical testimonials never revive legacy or samples',
        (tester) async {
      await tester.pumpWidget(
        _host(
          data: const <String, dynamic>{
            'testimonials': <Map<String, dynamic>>[],
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'Stale',
                'quote': 'No publicar',
              },
            ],
          },
        ),
      );

      expect(
        tester.getSize(
          find.byKey(WebsiteTestimonialsBlockContent.rootKey),
        ),
        Size.zero,
      );
      expect(find.text('No publicar'), findsNothing);
      expect(find.text('Carolina M.'), findsNothing);
    });

    testWidgets('an empty persisted item adds no public identity or rating',
        (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          data: const <String, dynamic>{
            'title': 'Historias',
            'testimonials': <Map<String, dynamic>>[
              <String, dynamic>{},
            ],
          },
        ),
      );

      expect(find.text('Cliente'), findsNothing);
      expect(
        find.text('Agrega testimonios reales desde el editor.'),
        findsNothing,
      );
      expect(find.bySemanticsLabel(RegExp('Valoración:')), findsNothing);
      semanticsHandle.dispose();
    });

    testWidgets(
      'comment, quote and text aliases share one nested slot and rating clamps',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        final slots = <String, WebsiteInlineTextSlot>{};
        final presenters = WebsiteBlockContentPresenters(
          text: (context, slot) {
            slots[slot.id] = slot;
            return Text(
              slot.displayTransform?.call(slot.value) ?? slot.value,
              style: slot.formatting.applyTo(slot.baseStyle),
            );
          },
        );

        await tester.pumpWidget(
          _host(
            presenters: presenters,
            data: const <String, dynamic>{
              'title': 'Historias',
              'items': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'testimonial-a',
                  'name': 'Paula',
                  'role': 'Cicloturista',
                  'quote': 'Muy buena atención.',
                  'quoteFormatting': <String, dynamic>{'italic': true},
                  'rating': '8',
                },
                <String, dynamic>{
                  'id': '',
                  'name': 'Andrés',
                  'comment': '',
                  'quote': 'Este alias está obsoleto',
                  'rating': 0,
                },
              ],
            },
          ),
        );

        expect(find.text('Muy buena atención.'), findsOneWidget);
        expect(find.text('Este alias está obsoleto'), findsNothing);
        expect(
          find.text('Agrega testimonios reales desde el editor.'),
          findsNothing,
        );
        expect(find.bySemanticsLabel('Valoración: 5 de 5'), findsOneWidget);
        expect(find.bySemanticsLabel('Valoración: 1 de 5'), findsOneWidget);

        final comment = slots['testimonials.item.0.comment']!;
        expect(
          comment.valueKeys,
          <String>['comment', 'quote', 'text'],
        );
        expect(
          comment.formattingKeys,
          <String>[
            'commentFormatting',
            'quoteFormatting',
            'textFormatting',
          ],
        );
        expect(
          comment.repeaterTarget?.collectionKeys,
          <String>['testimonials', 'items'],
        );
        expect(comment.repeaterTarget?.identityKey, 'id');
        expect(comment.repeaterTarget?.identityValue, 'testimonial-a');
        expect(
          slots['testimonials.item.0.name']?.formattingKeys,
          <String>['nameFormatting'],
        );
        expect(
          slots['testimonials.item.0.role']?.formattingKeys,
          <String>['roleFormatting'],
        );
        expect(
          slots['testimonials.item.1.comment']?.repeaterTarget?.identityKey,
          isNull,
        );
        expect(slots['testimonials.item.1.role'], isNull);
        semanticsHandle.dispose();
      },
    );
  });
}
