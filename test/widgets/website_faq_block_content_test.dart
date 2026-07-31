import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_faq_block_content.dart';

const _faqItems = <Map<String, dynamic>>[
  {
    'question': '¿Cuánto demora una mantención?',
    'answer': 'El plazo se confirma después del diagnóstico.',
  },
  {
    'question': '¿Trabajan con bicicletas eléctricas?',
    'answer': 'La compatibilidad se revisa antes de recibir el trabajo.',
  },
];

Future<void> _pumpFaq(
  WidgetTester tester, {
  required double width,
  Map<String, dynamic>? data,
  WebsiteBlockContentPresenters? presenters,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteFaqBlockContent(
            data: data ??
                const <String, dynamic>{
                  'title': 'Preguntas frecuentes',
                  'subtitle': 'Información antes de agendar.',
                  'items': _faqItems,
                },
            primaryColor: Colors.teal,
            presenters: presenters,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('WebsiteFaqBlockContent geometry', () {
    testWidgets('1440 caps the FAQ content at 900', (tester) async {
      await _pumpFaq(tester, width: 1440);

      expect(
        tester.getSize(find.byKey(WebsiteFaqBlockContent.collectionKey)).width,
        900,
      );
      expect(
        tester.getSize(find.byKey(WebsiteFaqBlockContent.itemKey(0))).width,
        900,
      );
      final title = tester.widget<Text>(find.text('Preguntas frecuentes'));
      expect(title.style?.fontSize, 40);
    });

    testWidgets('834 uses the full 786px useful width', (tester) async {
      await _pumpFaq(tester, width: 834);

      expect(
        tester.getSize(find.byKey(WebsiteFaqBlockContent.collectionKey)).width,
        786,
      );
      expect(
        tester.getSize(find.byKey(WebsiteFaqBlockContent.itemKey(0))).width,
        786,
      );
      final title = tester.widget<Text>(find.text('Preguntas frecuentes'));
      expect(title.style?.fontSize, 34);
    });

    testWidgets('390 keeps every FAQ item at the full useful width',
        (tester) async {
      await _pumpFaq(tester, width: 390);

      expect(
        tester.getSize(find.byKey(WebsiteFaqBlockContent.collectionKey)).width,
        342,
      );
      for (var index = 0; index < _faqItems.length; index++) {
        expect(
          tester
              .getSize(find.byKey(WebsiteFaqBlockContent.itemKey(index)))
              .width,
          342,
        );
      }
      final title = tester.widget<Text>(find.text('Preguntas frecuentes'));
      expect(title.style?.fontSize, 26);
    });

    testWidgets('620 applies the breakpoint to width after horizontal padding',
        (tester) async {
      await _pumpFaq(tester, width: 620);

      expect(
        tester.getSize(find.byKey(WebsiteFaqBlockContent.collectionKey)).width,
        572,
      );
      final title = tester.widget<Text>(find.text('Preguntas frecuentes'));
      expect(title.style?.fontSize, 26);
    });
  });

  group('WebsiteFaqBlockContent behavior and data', () {
    testWidgets(
        'the same ExpansionTile starts collapsed and reveals its answer',
        (tester) async {
      await _pumpFaq(tester, width: 834);

      expect(find.byType(ExpansionTile), findsNWidgets(2));
      expect(
        find.text('El plazo se confirma después del diagnóstico.'),
        findsNothing,
      );

      await tester.tap(find.text('¿Cuánto demora una mantención?'));
      await tester.pumpAndSettle();
      expect(
        find.text('El plazo se confirma después del diagnóstico.'),
        findsOneWidget,
      );
    });

    testWidgets('an explicit empty collection renders no fabricated FAQ',
        (tester) async {
      await _pumpFaq(
        tester,
        width: 834,
        data: const <String, dynamic>{
          'title': 'Preguntas',
          'items': <Map<String, dynamic>>[],
        },
      );

      expect(
        find.byKey(WebsiteFaqBlockContent.collectionKey),
        findsNothing,
      );
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.text('¿Cómo agendo una mantención?'), findsNothing);
      expect(find.text('¿Pregunta de ejemplo?'), findsNothing);
    });

    testWidgets('only the canonical items collection is consumed',
        (tester) async {
      await _pumpFaq(
        tester,
        width: 834,
        data: const <String, dynamic>{
          'title': 'Preguntas',
          'questions': [
            {
              'question': 'No debe aparecer',
              'answer': 'Alias no registrado',
            },
          ],
        },
      );

      expect(find.text('No debe aparecer'), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
    });

    testWidgets('presenter slots describe canonical nested formatting writes',
        (tester) async {
      final slots = <WebsiteInlineTextSlot>[];
      final presenters = WebsiteBlockContentPresenters(
        text: (context, slot) {
          slots.add(slot);
          return Text(
            slot.displayTransform?.call(slot.value) ?? slot.value,
            style: slot.formatting.applyTo(slot.baseStyle),
            textAlign: slot.textAlign,
          );
        },
      );
      await _pumpFaq(
        tester,
        width: 834,
        presenters: presenters,
        data: const <String, dynamic>{
          'title': 'Preguntas',
          'titleFormatting': {'bold': true},
          'subtitle': 'Respuestas',
          'subtitleFormatting': {'italic': true},
          'items': [
            {
              'question': '¿Pregunta?',
              'questionFormatting': {'underline': true},
              'answer': 'Respuesta.',
              'answerFormatting': {'italic': true},
            },
          ],
        },
      );

      expect(
        slots.map((slot) => slot.id),
        containsAllInOrder([
          'faq.title',
          'faq.subtitle',
          'faq.item.0.question',
          'faq.item.0.answer',
        ]),
      );
      final question =
          slots.firstWhere((slot) => slot.id == 'faq.item.0.question');
      expect(question.repeaterTarget?.collectionKeys, ['items']);
      expect(question.repeaterTarget?.itemIndex, 0);
      expect(question.valueKeys, ['question']);
      expect(question.formattingKeys, ['questionFormatting']);
      expect(question.formatting.isUnderline, isTrue);
      final answer = slots.firstWhere((slot) => slot.id == 'faq.item.0.answer');
      expect(answer.valueKeys, ['answer']);
      expect(answer.formattingKeys, ['answerFormatting']);
      expect(answer.formatting.isItalic, isTrue);
    });
  });
}
