import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_features_block_content.dart';

const _features = <Map<String, dynamic>>[
  {
    'icon': 'verified',
    'title': 'Diagnóstico',
    'description': 'Revisión antes de intervenir.',
  },
  {
    'icon': 'pedal_bike',
    'title': 'Experiencia',
    'description': 'Trabajo especializado en bicicletas.',
  },
  {
    'icon': 'support_agent',
    'title': 'Acompañamiento',
    'description': 'Orientación durante el proceso.',
  },
  {
    'icon': 'build',
    'title': 'Taller',
    'description': 'Herramientas para cada servicio.',
  },
];

Future<void> _pumpFeatures(
  WidgetTester tester, {
  required double width,
  Map<String, dynamic>? data,
  WebsiteBlockContentPresenters? presenters,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteFeaturesBlockContent(
            data: data ??
                const <String, dynamic>{
                  'title': 'Por qué elegirnos',
                  'layout': 'grid',
                  'features': _features,
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
  group('WebsiteFeaturesBlockContent geometry', () {
    testWidgets('1440 uses 320px cards with at most three per row',
        (tester) async {
      await _pumpFeatures(tester, width: 1440);

      for (var index = 0; index < _features.length; index++) {
        expect(
          tester
              .getSize(
                find.byKey(WebsiteFeaturesBlockContent.itemKey(index)),
              )
              .width,
          320,
        );
      }
      final first = tester.getTopLeft(
        find.byKey(WebsiteFeaturesBlockContent.itemKey(0)),
      );
      final second = tester.getTopLeft(
        find.byKey(WebsiteFeaturesBlockContent.itemKey(1)),
      );
      final third = tester.getTopLeft(
        find.byKey(WebsiteFeaturesBlockContent.itemKey(2)),
      );
      final fourth = tester.getTopLeft(
        find.byKey(WebsiteFeaturesBlockContent.itemKey(3)),
      );
      expect(first.dy, second.dy);
      expect(second.dy, third.dy);
      expect(second.dx - (first.dx + 320), 24);
      expect(third.dx - (second.dx + 320), 24);
      expect(fourth.dy, greaterThan(first.dy));
    });

    testWidgets('834 wraps nominal cards without changing their width',
        (tester) async {
      await _pumpFeatures(tester, width: 834);

      final first = find.byKey(WebsiteFeaturesBlockContent.itemKey(0));
      final second = find.byKey(WebsiteFeaturesBlockContent.itemKey(1));
      final third = find.byKey(WebsiteFeaturesBlockContent.itemKey(2));
      expect(tester.getSize(first).width, 320);
      expect(tester.getSize(second).width, 320);
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
      expect(
        tester.getTopLeft(third).dy,
        greaterThan(tester.getTopLeft(first).dy),
      );
    });

    testWidgets('390 makes every card fill the useful width', (tester) async {
      await _pumpFeatures(tester, width: 390);

      for (var index = 0; index < _features.length; index++) {
        expect(
          tester
              .getSize(
                find.byKey(WebsiteFeaturesBlockContent.itemKey(index)),
              )
              .width,
          342,
        );
      }
      expect(
        tester
            .getTopLeft(find.byKey(WebsiteFeaturesBlockContent.itemKey(0)))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(WebsiteFeaturesBlockContent.itemKey(1)))
              .dy,
        ),
      );
    });

    testWidgets('620 applies the breakpoint to width after horizontal padding',
        (tester) async {
      await _pumpFeatures(tester, width: 620);

      expect(
        tester
            .getSize(find.byKey(WebsiteFeaturesBlockContent.itemKey(0)))
            .width,
        572,
      );
    });

    testWidgets('list mode retains the persisted order', (tester) async {
      await _pumpFeatures(
        tester,
        width: 834,
        data: const <String, dynamic>{
          'title': 'Lista',
          'layout': 'list',
          'features': _features,
        },
      );

      expect(find.byKey(WebsiteFeaturesBlockContent.listKey), findsOneWidget);
      expect(find.byKey(WebsiteFeaturesBlockContent.gridKey), findsNothing);
      final ys = [
        for (var index = 0; index < _features.length; index++)
          tester
              .getTopLeft(
                find.byKey(WebsiteFeaturesBlockContent.itemKey(index)),
              )
              .dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
    });
  });

  group('WebsiteFeaturesBlockContent data contract', () {
    testWidgets('empty canonical collection wins over a stale items alias',
        (tester) async {
      await _pumpFeatures(
        tester,
        width: 834,
        data: const <String, dynamic>{
          'title': 'Sin ventajas',
          'features': <Map<String, dynamic>>[],
          'items': [
            {
              'title': 'No debe aparecer',
              'description': 'Alias obsoleto',
            },
          ],
        },
      );

      expect(find.text('No debe aparecer'), findsNothing);
      expect(
        find.byKey(WebsiteFeaturesBlockContent.collectionKey),
        findsNothing,
      );
      expect(find.text('Servicio certificado'), findsNothing);
    });

    testWidgets('legacy items render only when the canonical key is absent',
        (tester) async {
      await _pumpFeatures(
        tester,
        width: 834,
        data: const <String, dynamic>{
          'title': 'Ventajas legacy',
          'items': [
            {
              'icon': 'check_circle',
              'title': 'Dato legacy',
              'description': 'Se conserva durante la migración.',
            },
          ],
        },
      );

      expect(find.text('Dato legacy'), findsOneWidget);
      expect(
        find.byKey(WebsiteFeaturesBlockContent.itemKey(0)),
        findsOneWidget,
      );
    });

    testWidgets('presenter slots carry atomic collection aliases and formats',
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
      await _pumpFeatures(
        tester,
        width: 834,
        presenters: presenters,
        data: const <String, dynamic>{
          'title': 'Ventajas',
          'titleFormatting': {'bold': true},
          'features': [
            {
              'icon': 'verified',
              'title': 'Diagnóstico',
              'titleFormatting': {'italic': true},
              'description': 'Revisión',
              'descriptionFormatting': {'underline': true},
            },
          ],
        },
      );

      expect(
        slots.map((slot) => slot.id),
        containsAllInOrder([
          'features.title',
          'features.item.0.title',
          'features.item.0.description',
        ]),
      );
      final itemTitle =
          slots.firstWhere((slot) => slot.id == 'features.item.0.title');
      expect(itemTitle.valueKeys, ['title']);
      expect(itemTitle.formattingKeys, ['titleFormatting']);
      expect(itemTitle.formatting.isItalic, isTrue);
      expect(itemTitle.repeaterTarget?.collectionKeys, ['features', 'items']);
      expect(itemTitle.repeaterTarget?.itemIndex, 0);
      final itemDescription =
          slots.firstWhere((slot) => slot.id == 'features.item.0.description');
      expect(
        itemDescription.formattingKeys,
        ['descriptionFormatting'],
      );
      expect(itemDescription.formatting.isUnderline, isTrue);
    });
  });
}
