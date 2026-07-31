import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_services_block_content.dart';

const _services = <Map<String, dynamic>>[
  {
    'icon': 'build',
    'title': 'Mantención',
    'description': 'Servicio técnico programado.',
  },
  {
    'icon': 'support_agent',
    'title': 'Diagnóstico',
    'description': 'Orientación antes de reparar.',
  },
  {
    'icon': 'shopping_bag',
    'title': 'Repuestos',
    'description': 'Alternativas para cada bicicleta.',
  },
  {
    'icon': 'local_shipping',
    'title': 'Entrega',
    'description': 'Coordinación al terminar el trabajo.',
  },
];

Future<void> _pumpServices(
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
          child: WebsiteServicesBlockContent(
            data: data ??
                const <String, dynamic>{
                  'title': 'Nuestros Servicios',
                  'services': _services,
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
  group('WebsiteServicesBlockContent geometry', () {
    testWidgets('1440 renders every item in rows of at most three',
        (tester) async {
      await _pumpServices(tester, width: 1440);

      expect(find.byKey(WebsiteServicesBlockContent.rowKey(0)), findsOneWidget);
      expect(find.byKey(WebsiteServicesBlockContent.rowKey(1)), findsOneWidget);
      for (var index = 0; index < _services.length; index++) {
        expect(
          find.byKey(WebsiteServicesBlockContent.itemKey(index)),
          findsOneWidget,
        );
      }

      final first = find.byKey(WebsiteServicesBlockContent.itemKey(0));
      final second = find.byKey(WebsiteServicesBlockContent.itemKey(1));
      final third = find.byKey(WebsiteServicesBlockContent.itemKey(2));
      final fourth = find.byKey(WebsiteServicesBlockContent.itemKey(3));
      expect(tester.getSize(first).width, closeTo(1000 / 3, 0.01));
      expect(tester.getSize(second).width, closeTo(1000 / 3, 0.01));
      expect(tester.getSize(third).width, closeTo(1000 / 3, 0.01));
      expect(tester.getSize(fourth).width, closeTo(1000 / 3, 0.01));
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
      expect(tester.getTopLeft(second).dy, tester.getTopLeft(third).dy);
      expect(
        tester.getTopLeft(fourth).dy,
        greaterThan(tester.getTopLeft(first).dy),
      );
      expect(find.text('Entrega'), findsOneWidget);
      expect(find.byIcon(Icons.local_shipping), findsOneWidget);
    });

    testWidgets('834 keeps three flex items on the first row', (tester) async {
      await _pumpServices(tester, width: 834);

      for (var index = 0; index < 3; index++) {
        expect(
          tester
              .getSize(
                find.byKey(WebsiteServicesBlockContent.itemKey(index)),
              )
              .width,
          closeTo(786 / 3, 0.01),
        );
      }
      expect(
        find.byKey(WebsiteServicesBlockContent.desktopKey),
        findsOneWidget,
      );
    });

    testWidgets('390 gives every service the full useful width',
        (tester) async {
      await _pumpServices(tester, width: 390);

      expect(
        find.byKey(WebsiteServicesBlockContent.mobileKey),
        findsOneWidget,
      );
      for (var index = 0; index < _services.length; index++) {
        expect(
          tester
              .getSize(
                find.byKey(WebsiteServicesBlockContent.itemKey(index)),
              )
              .width,
          342,
        );
      }
      expect(
        tester
            .getTopLeft(find.byKey(WebsiteServicesBlockContent.itemKey(0)))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(WebsiteServicesBlockContent.itemKey(1)))
              .dy,
        ),
      );
    });

    testWidgets('620 applies the breakpoint to width after horizontal padding',
        (tester) async {
      await _pumpServices(tester, width: 620);

      expect(
        find.byKey(WebsiteServicesBlockContent.mobileKey),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(WebsiteServicesBlockContent.itemKey(0)))
            .width,
        572,
      );
    });
  });

  group('WebsiteServicesBlockContent data contract', () {
    testWidgets('empty canonical services win over a stale items alias',
        (tester) async {
      await _pumpServices(
        tester,
        width: 834,
        data: const <String, dynamic>{
          'title': 'Servicios',
          'services': <Map<String, dynamic>>[],
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
        find.byKey(WebsiteServicesBlockContent.collectionKey),
        findsNothing,
      );
      expect(find.text('Servicio Técnico'), findsNothing);
    });

    testWidgets('legacy items render only without the canonical key',
        (tester) async {
      await _pumpServices(
        tester,
        width: 834,
        data: const <String, dynamic>{
          'title': 'Servicios legacy',
          'items': [
            {
              'icon': 'tune',
              'title': 'Ajuste legacy',
              'description': 'Se conserva durante la migración.',
            },
          ],
        },
      );

      expect(find.text('Ajuste legacy'), findsOneWidget);
      expect(find.byIcon(Icons.tune), findsOneWidget);
    });

    testWidgets('presenter slots carry aliases and nested formatting targets',
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
      await _pumpServices(
        tester,
        width: 834,
        presenters: presenters,
        data: const <String, dynamic>{
          'title': 'Servicios',
          'services': [
            {
              'icon': 'build',
              'title': 'Mantención',
              'titleFormatting': {'bold': true},
              'description': 'Programada',
              'descriptionFormatting': {'italic': true},
            },
          ],
        },
      );

      expect(
        slots.map((slot) => slot.id),
        containsAllInOrder([
          'services.title',
          'services.item.0.title',
          'services.item.0.description',
        ]),
      );
      final title =
          slots.firstWhere((slot) => slot.id == 'services.item.0.title');
      expect(title.repeaterTarget?.collectionKeys, ['services', 'items']);
      expect(title.repeaterTarget?.itemIndex, 0);
      expect(title.valueKeys, ['title']);
      expect(title.formattingKeys, ['titleFormatting']);
      expect(title.formatting.isBold, isTrue);
      final description =
          slots.firstWhere((slot) => slot.id == 'services.item.0.description');
      expect(description.formattingKeys, ['descriptionFormatting']);
      expect(description.formatting.isItalic, isTrue);
    });
  });
}
