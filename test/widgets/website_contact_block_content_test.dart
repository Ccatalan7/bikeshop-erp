import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_contact_block_content.dart';

const _completeContact = <String, dynamic>{
  'title': 'Conversemos',
  'subtitle': 'Te ayudamos a preparar tu próxima salida.',
  'phone': '+56 9 1234 5678',
  'email': 'hola@vinabike.cl',
  'address': 'Curicó, Chile',
  'showForm': true,
  'showMap': true,
  'mapUrl': '/mapa',
};

Future<void> _pumpContact(
  WidgetTester tester, {
  required double width,
  Map<String, dynamic> data = _completeContact,
  bool previewMode = false,
  void Function(String route)? onNavigate,
  bool Function(String href)? isNavigationEligible,
  WebsiteBlockContentPresenters? presenters,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteContactBlockContent(
            data: data,
            primaryColor: Colors.indigo,
            accentColor: Colors.orange,
            previewMode: previewMode,
            onNavigate: onNavigate,
            isNavigationEligible: isNavigationEligible,
            presenters: presenters,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Size _sizeOf(WidgetTester tester, Key key) {
  return tester.getSize(find.byKey(key));
}

Offset _topLeftOf(WidgetTester tester, Key key) {
  return tester.getTopLeft(find.byKey(key));
}

void main() {
  group('WebsiteContactBlockContent responsive geometry', () {
    testWidgets('1440 frame uses canonical 320/360/360 desktop columns',
        (tester) async {
      await _pumpContact(tester, width: 1440);

      expect(
        _sizeOf(tester, WebsiteContactBlockContent.infoCardKey).width,
        320,
      );
      expect(
        _sizeOf(tester, WebsiteContactBlockContent.formCardKey).width,
        360,
      );
      expect(
        _sizeOf(tester, WebsiteContactBlockContent.mapCardKey).width,
        360,
      );

      final info = _topLeftOf(
        tester,
        WebsiteContactBlockContent.infoCardKey,
      );
      final form = _topLeftOf(
        tester,
        WebsiteContactBlockContent.formCardKey,
      );
      final map = _topLeftOf(
        tester,
        WebsiteContactBlockContent.mapCardKey,
      );
      expect(form.dx - (info.dx + 320), 24);
      expect(map.dx - (form.dx + 360), 24);
      expect(form.dy, info.dy);
      expect(map.dy, info.dy);

      final heading = tester.widget<Text>(find.text('Conversemos'));
      expect(heading.style?.fontSize, 40);
      final subtitle = tester.widget<Text>(
        find.text('Te ayudamos a preparar tu próxima salida.'),
      );
      expect(subtitle.style?.fontSize, 17);
    });

    testWidgets('834 frame uses two columns then a full-width last row',
        (tester) async {
      await _pumpContact(tester, width: 834);

      final infoSize = _sizeOf(tester, WebsiteContactBlockContent.infoCardKey);
      final formSize = _sizeOf(tester, WebsiteContactBlockContent.formCardKey);
      final mapSize = _sizeOf(tester, WebsiteContactBlockContent.mapCardKey);
      expect(infoSize.width, 381);
      expect(formSize.width, 381);
      expect(mapSize.width, 786);

      final info = _topLeftOf(
        tester,
        WebsiteContactBlockContent.infoCardKey,
      );
      final form = _topLeftOf(
        tester,
        WebsiteContactBlockContent.formCardKey,
      );
      final map = _topLeftOf(
        tester,
        WebsiteContactBlockContent.mapCardKey,
      );
      expect(info.dy, form.dy);
      expect(form.dx - (info.dx + infoSize.width), 24);
      expect(map.dy, greaterThan(info.dy + infoSize.height));

      final heading = tester.widget<Text>(find.text('Conversemos'));
      expect(heading.style?.fontSize, 34);
    });

    testWidgets('390 frame stacks full-width cards in stable semantic order',
        (tester) async {
      await _pumpContact(tester, width: 390);

      for (final key in [
        WebsiteContactBlockContent.infoCardKey,
        WebsiteContactBlockContent.formCardKey,
        WebsiteContactBlockContent.mapCardKey,
      ]) {
        expect(
          _sizeOf(tester, key).width,
          342,
          reason: 'Expected $key to fill the compact content width.',
        );
      }

      final infoY = _topLeftOf(
        tester,
        WebsiteContactBlockContent.infoCardKey,
      ).dy;
      final formY = _topLeftOf(
        tester,
        WebsiteContactBlockContent.formCardKey,
      ).dy;
      final mapY = _topLeftOf(
        tester,
        WebsiteContactBlockContent.mapCardKey,
      ).dy;
      expect(infoY, lessThan(formY));
      expect(formY, lessThan(mapY));

      final heading = tester.widget<Text>(find.text('Conversemos'));
      expect(heading.style?.fontSize, 26);
    });

    testWidgets('info-only mode is centered and capped at 520', (tester) async {
      await _pumpContact(
        tester,
        width: 1440,
        data: const <String, dynamic>{
          'title': 'Información',
          'phone': '+56 9 1234 5678',
          'showForm': false,
          'showMap': false,
        },
      );

      final infoFinder = find.byKey(WebsiteContactBlockContent.infoCardKey);
      expect(tester.getSize(infoFinder).width, 520);
      expect(tester.getCenter(infoFinder).dx, 720);
      expect(
        find.byKey(WebsiteContactBlockContent.formCardKey),
        findsNothing,
      );
      expect(
        find.byKey(WebsiteContactBlockContent.mapCardKey),
        findsNothing,
      );
    });
  });

  group('WebsiteContactBlockContent behavior', () {
    testWidgets('showForm and showMap remove their nodes without reordering',
        (tester) async {
      await _pumpContact(
        tester,
        width: 1440,
        data: <String, dynamic>{
          ..._completeContact,
          'showForm': false,
        },
      );

      expect(
        find.byKey(WebsiteContactBlockContent.formCardKey),
        findsNothing,
      );
      expect(
        find.byKey(WebsiteContactBlockContent.infoCardKey),
        findsOneWidget,
      );
      expect(
        find.byKey(WebsiteContactBlockContent.mapCardKey),
        findsOneWidget,
      );
      expect(
        _topLeftOf(tester, WebsiteContactBlockContent.infoCardKey).dx,
        lessThan(
          _topLeftOf(tester, WebsiteContactBlockContent.mapCardKey).dx,
        ),
      );

      await _pumpContact(
        tester,
        width: 1440,
        data: <String, dynamic>{
          ..._completeContact,
          'showMap': false,
        },
      );
      expect(
        find.byKey(WebsiteContactBlockContent.mapCardKey),
        findsNothing,
      );
      expect(
        find.byKey(WebsiteContactBlockContent.mapActionKey),
        findsNothing,
      );
    });

    testWidgets('map action exists only for an eligible non-empty map URL',
        (tester) async {
      await _pumpContact(
        tester,
        width: 1440,
        isNavigationEligible: (_) => false,
      );
      expect(
        find.byKey(WebsiteContactBlockContent.mapActionKey),
        findsNothing,
      );

      await _pumpContact(
        tester,
        width: 1440,
        data: <String, dynamic>{
          ..._completeContact,
          'mapUrl': '',
        },
        isNavigationEligible: (_) => true,
      );
      expect(
        find.byKey(WebsiteContactBlockContent.mapActionKey),
        findsNothing,
      );
    });

    testWidgets('public map action delegates to the injected navigator',
        (tester) async {
      final navigations = <String>[];
      await _pumpContact(
        tester,
        width: 1440,
        isNavigationEligible: (_) => true,
        onNavigate: navigations.add,
      );

      await tester.tap(
        find.byKey(WebsiteContactBlockContent.mapActionKey),
      );
      await tester.pump();
      expect(navigations, ['/mapa']);
    });

    testWidgets('preview and Edit presenters keep the map action inert',
        (tester) async {
      final previewNavigations = <String>[];
      await _pumpContact(
        tester,
        width: 1440,
        previewMode: true,
        isNavigationEligible: (_) => true,
        onNavigate: previewNavigations.add,
      );
      await tester.tap(
        find.byKey(WebsiteContactBlockContent.mapActionKey),
      );
      expect(previewNavigations, isEmpty);

      final slots = <WebsiteInlineTextSlot>[];
      final editNavigations = <String>[];
      final presenters = WebsiteBlockContentPresenters(
        text: (context, slot) {
          slots.add(slot);
          final displayValue =
              slot.displayTransform?.call(slot.value) ?? slot.value;
          return Text(
            displayValue,
            style: slot.baseStyle,
            textAlign: slot.textAlign,
          );
        },
      );
      await _pumpContact(
        tester,
        width: 1440,
        presenters: presenters,
        isNavigationEligible: (_) => true,
        onNavigate: editNavigations.add,
      );
      await tester.tap(
        find.byKey(WebsiteContactBlockContent.mapActionKey),
      );

      expect(editNavigations, isEmpty);
      expect(
        slots.map((slot) => slot.id).toSet(),
        {'contact-title', 'contact-subtitle'},
      );
      expect(slots.first.valueKeys, ['title']);
      expect(slots.last.valueKeys, ['subtitle']);
      expect(
        _sizeOf(tester, WebsiteContactBlockContent.infoCardKey).width,
        320,
      );
      expect(
        _sizeOf(tester, WebsiteContactBlockContent.formCardKey).width,
        360,
      );
      expect(
        _sizeOf(tester, WebsiteContactBlockContent.mapCardKey).width,
        360,
      );
    });

    testWidgets('public contact form remains visibly disabled', (tester) async {
      await _pumpContact(tester, width: 390);

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields, hasLength(3));
      expect(fields.every((field) => field.enabled == false), isTrue);

      final sendButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Enviar consulta'),
      );
      expect(sendButton.onPressed, isNull);
    });
  });
}
