import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_about_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';

const _probeTitleKey = ValueKey<String>('about-probe-title');
const _probeContentKey = ValueKey<String>('about-probe-content');
const _probeMediaKey = ValueKey<String>('about-probe-media');

class _AboutPresenterProbe {
  final List<WebsiteInlineTextSlot> textSlots = <WebsiteInlineTextSlot>[];
  final List<WebsiteInlineMediaSlot> mediaSlots = <WebsiteInlineMediaSlot>[];

  WebsiteBlockContentPresenters get presenters => WebsiteBlockContentPresenters(
        text: (context, slot) {
          textSlots.add(slot);
          final isTitle = slot.valueKeys.contains('title');
          return Text(
            slot.displayTransform?.call(slot.value) ?? slot.value,
            key: isTitle ? _probeTitleKey : _probeContentKey,
            style: slot.formatting.applyTo(slot.baseStyle),
            textAlign: slot.textAlign,
            maxLines: slot.maxLines,
            overflow: TextOverflow.visible,
          );
        },
        media: (context, slot) {
          mediaSlots.add(slot);
          return const SizedBox.expand(
            key: _probeMediaKey,
            child: ColoredBox(color: Color(0xFFCCDDEE)),
          );
        },
      );

  WebsiteInlineTextSlot get titleSlot =>
      textSlots.lastWhere((slot) => slot.valueKeys.contains('title'));

  WebsiteInlineTextSlot get contentSlot =>
      textSlots.lastWhere((slot) => slot.valueKeys.contains('content'));

  WebsiteInlineMediaSlot get mediaSlot => mediaSlots.last;
}

Future<void> _pumpAbout(
  WidgetTester tester, {
  required double width,
  required Map<String, dynamic> data,
  WebsiteBlockContentPresenters? presenters,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: WebsiteAboutBlockContent(
                data: data,
                headingFont: 'Heading Test',
                bodyFont: 'Body Test',
                presenters: presenters,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  Future<void> useWideTestSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets(
    'local 1440, 834 and 390 constraints select canonical typography and ratios',
    (tester) async {
      await useWideTestSurface(tester);

      final cases = <({
        double width,
        double titleSize,
        double bodySize,
        double imageRatio,
        bool desktop,
      })>[
        (
          width: 1440,
          titleSize: 40,
          bodySize: 17,
          imageRatio: 4 / 3,
          desktop: true,
        ),
        (
          width: 834,
          titleSize: 34,
          bodySize: 16.5,
          imageRatio: 16 / 9,
          desktop: false,
        ),
        (
          width: 390,
          titleSize: 26,
          bodySize: 16,
          imageRatio: 3 / 2,
          desktop: false,
        ),
      ];

      for (final testCase in cases) {
        final probe = _AboutPresenterProbe();
        await _pumpAbout(
          tester,
          width: testCase.width,
          data: const <String, dynamic>{
            'title': 'Nuestra historia',
            'content': 'Contenido editorial',
            'imageUrl': 'https://example.invalid/about.jpg',
            'imagePosition': 'right',
          },
          presenters: probe.presenters,
        );

        expect(probe.titleSlot.baseStyle.fontSize, testCase.titleSize);
        expect(probe.contentSlot.baseStyle.fontSize, testCase.bodySize);
        expect(probe.titleSlot.baseStyle.fontFamily, 'Heading Test');
        expect(probe.contentSlot.baseStyle.fontFamily, 'Body Test');

        expect(
          find.byKey(
            ValueKey<String>(
              testCase.desktop
                  ? 'website-about-desktop-layout'
                  : 'website-about-stacked-layout',
            ),
          ),
          findsOneWidget,
        );

        final mediaSize = tester.getSize(find.byKey(_probeMediaKey));
        expect(
          mediaSize.width / mediaSize.height,
          closeTo(testCase.imageRatio, 0.01),
          reason: 'ratio at ${testCase.width}px',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('desktop imagePosition controls left and right column order',
      (tester) async {
    await useWideTestSurface(tester);

    for (final position in const <String>['left', 'right']) {
      final probe = _AboutPresenterProbe();
      await _pumpAbout(
        tester,
        width: 1440,
        data: <String, dynamic>{
          'title': 'Nuestra historia',
          'content': 'Contenido editorial',
          'imageUrl': 'https://example.invalid/about.jpg',
          'imagePosition': position,
        },
        presenters: probe.presenters,
      );

      final mediaX = tester.getTopLeft(find.byKey(_probeMediaKey)).dx;
      final textX = tester.getTopLeft(find.byKey(_probeTitleKey)).dx;
      if (position == 'left') {
        expect(mediaX, lessThan(textX));
      } else {
        expect(mediaX, greaterThan(textX));
      }
    }
  });

  testWidgets('below 900 the image stacks first regardless of imagePosition',
      (tester) async {
    await useWideTestSurface(tester);

    for (final width in const <double>[834, 390]) {
      for (final position in const <String>['left', 'right']) {
        final probe = _AboutPresenterProbe();
        await _pumpAbout(
          tester,
          width: width,
          data: <String, dynamic>{
            'title': 'Nuestra historia',
            'content': 'Contenido editorial',
            'imageUrl': 'https://example.invalid/about.jpg',
            'imagePosition': position,
          },
          presenters: probe.presenters,
        );

        expect(
          tester.getBottomLeft(find.byKey(_probeMediaKey)).dy,
          lessThan(tester.getTopLeft(find.byKey(_probeTitleKey)).dy),
          reason: '$position at ${width}px must keep media first',
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
      'no-image content remains visible and long text is never truncated',
      (tester) async {
    await useWideTestSurface(tester);
    final longContent = List<String>.filled(
      28,
      'La historia completa del taller permanece visible sin recortes.',
    ).join(' ');

    for (final width in const <double>[1440, 834, 390]) {
      await _pumpAbout(
        tester,
        width: width,
        data: <String, dynamic>{
          'title': 'Historia sin fotografía',
          'content': longContent,
          'imageUrl': '',
        },
      );

      expect(find.text('Historia sin fotografía'), findsOneWidget);
      final content = tester.widget<Text>(find.text(longContent));
      expect(content.maxLines, isNull);
      expect(content.overflow, TextOverflow.visible);
      expect(
        find.byKey(
          const ValueKey<String>('website-about-no-media-frame'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('website-about-media-frame'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'presenter slots expose canonical aliases and reserve empty media geometry',
    (tester) async {
      await useWideTestSurface(tester);

      var probe = _AboutPresenterProbe();
      await _pumpAbout(
        tester,
        width: 1440,
        data: const <String, dynamic>{
          'title': 'Canonical',
          'content': 'Contenido canónico',
          'imageUrl': 'https://example.invalid/canonical.jpg',
          'imageAltText': 'Equipo del taller',
        },
        presenters: probe.presenters,
      );

      expect(find.byKey(_probeTitleKey), findsOneWidget);
      expect(find.byKey(_probeContentKey), findsOneWidget);
      expect(find.byKey(_probeMediaKey), findsOneWidget);
      expect(probe.titleSlot.valueKeys, const <String>['title']);
      expect(
        probe.contentSlot.valueKeys,
        const <String>['content', 'description'],
      );
      expect(
        probe.contentSlot.formattingKeys,
        const <String>[
          'contentFormatting',
          'descriptionFormatting',
        ],
      );
      expect(probe.contentSlot.value, 'Contenido canónico');
      expect(
        probe.mediaSlot.valueKeys,
        const <String>['imageUrl', 'image'],
      );
      expect(
        probe.mediaSlot.url,
        'https://example.invalid/canonical.jpg',
      );
      expect(probe.mediaSlot.semanticLabel, 'Equipo del taller');

      probe = _AboutPresenterProbe();
      await _pumpAbout(
        tester,
        width: 834,
        data: const <String, dynamic>{
          'title': 'Legacy',
          'description': 'Contenido heredado',
          'image': 'https://example.invalid/legacy.jpg',
        },
        presenters: probe.presenters,
      );
      expect(probe.contentSlot.value, 'Contenido heredado');
      expect(probe.mediaSlot.url, 'https://example.invalid/legacy.jpg');

      probe = _AboutPresenterProbe();
      await _pumpAbout(
        tester,
        width: 390,
        data: const <String, dynamic>{
          'title': 'Configurar imagen',
          'description': 'El texto sigue presente.',
        },
        presenters: probe.presenters,
      );
      expect(probe.mediaSlot.url, isNull);
      expect(find.byKey(_probeMediaKey), findsOneWidget);
      final emptyMediaSize = tester.getSize(find.byKey(_probeMediaKey));
      expect(
          emptyMediaSize.width / emptyMediaSize.height, closeTo(3 / 2, 0.01));
      expect(find.text('El texto sigue presente.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
