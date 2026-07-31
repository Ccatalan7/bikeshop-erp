import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_gallery_block_content.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

Future<void> _pumpGallery(
  WidgetTester tester, {
  required double width,
  required Map<String, dynamic> data,
  WebsiteBlockContentPresenters? presenters,
  WebsiteGalleryImageProviderBuilder? imageProviderBuilder,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 3600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _host(
      WebsiteGalleryBlockContent(
        data: data,
        presenters: presenters,
        imageProviderBuilder: imageProviderBuilder,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'uses approved 3/2/1 columns and full useful width below 600',
    (tester) async {
      const images = <Map<String, dynamic>>[
        <String, dynamic>{'imageUrl': ''},
        <String, dynamic>{'imageUrl': ''},
        <String, dynamic>{'imageUrl': ''},
        <String, dynamic>{'imageUrl': ''},
      ];

      for (final testCase in <({double width, double tileWidth})>[
        (width: 1440, tileWidth: 356),
        (width: 834, tileWidth: 385),
        (width: 390, tileWidth: 342),
      ]) {
        await _pumpGallery(
          tester,
          width: testCase.width,
          data: const <String, dynamic>{
            'title': 'Galería',
            'layout': 'grid',
            'images': images,
          },
        );

        expect(
          tester
              .getSize(
                find.byKey(WebsiteGalleryBlockContent.tileKey(0)),
              )
              .width,
          closeTo(testCase.tileWidth, 0.01),
          reason: 'width ${testCase.width}',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('empty collection renders no fake photos or public editor tip',
      (tester) async {
    await _pumpGallery(
      tester,
      width: 834,
      data: const <String, dynamic>{
        'title': 'Fotos reales',
        'images': <Map<String, dynamic>>[],
      },
    );

    expect(find.text('Fotos reales'), findsOneWidget);
    expect(find.byKey(WebsiteGalleryBlockContent.imagesKey), findsNothing);
    expect(find.textContaining('Agrega fotos reales'), findsNothing);
    expect(find.textContaining('imagen de ejemplo'), findsNothing);
    expect(find.textContaining('Optimiza tus imágenes'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('masonry and grid preserve the canonical aspect-ratio sequence',
      (tester) async {
    const images = <Map<String, dynamic>>[
      <String, dynamic>{'imageUrl': ''},
      <String, dynamic>{'imageUrl': ''},
      <String, dynamic>{'imageUrl': ''},
    ];

    await _pumpGallery(
      tester,
      width: 834,
      data: const <String, dynamic>{
        'layout': 'masonry',
        'images': images,
      },
    );
    expect(
      List<double>.generate(
        3,
        (index) => tester
            .widget<AspectRatio>(
              find.byKey(WebsiteGalleryBlockContent.mediaFrameKey(index)),
            )
            .aspectRatio,
      ),
      <double>[1.2, 0.8, 1.0],
    );

    await _pumpGallery(
      tester,
      width: 834,
      data: const <String, dynamic>{
        'layout': 'grid',
        'images': images,
      },
    );
    expect(
      List<double>.generate(
        3,
        (index) => tester
            .widget<AspectRatio>(
              find.byKey(WebsiteGalleryBlockContent.mediaFrameKey(index)),
            )
            .aspectRatio,
      ),
      <double>[1.0, 1.0, 1.0],
    );
  });

  testWidgets(
    'media and caption presenters receive the exact nested target and focal data',
    (tester) async {
      final textSlots = <String, WebsiteInlineTextSlot>{};
      final mediaSlots = <String, WebsiteInlineMediaSlot>{};
      final presenters = WebsiteBlockContentPresenters(
        text: (context, slot) {
          textSlots[slot.id] = slot;
          return Text(slot.value);
        },
        media: (context, slot) {
          mediaSlots[slot.id] = slot;
          return slot.fallback;
        },
      );

      await _pumpGallery(
        tester,
        width: 834,
        presenters: presenters,
        data: const <String, dynamic>{
          'title': 'Taller',
          'images': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'gallery-1',
              'imageUrl': 'https://invalid.local/gallery.jpg',
              'caption': 'Área de suspensiones',
              'altText': 'Banco de trabajo de suspensiones',
              'focalPointX': 0.75,
              'focalPointY': 0.25,
            },
          ],
        },
      );

      final media = mediaSlots['gallery.image.0.media']!;
      expect(media.url, 'https://invalid.local/gallery.jpg');
      expect(media.valueKeys, <String>['imageUrl']);
      expect(media.alignment, const Alignment(0.5, -0.5));
      expect(media.semanticLabel, 'Banco de trabajo de suspensiones');
      expect(media.repeaterTarget!.collectionKeys, <String>['images']);
      expect(media.repeaterTarget!.itemIndex, 0);
      expect(media.repeaterTarget!.identityKey, 'id');
      expect(media.repeaterTarget!.identityValue, 'gallery-1');

      final caption = textSlots['gallery.image.0.caption']!;
      expect(caption.valueKeys, <String>['caption']);
      expect(caption.repeaterTarget, same(media.repeaterTarget));
      expect(find.text('Área de suspensiones'), findsOneWidget);
    },
  );

  testWidgets('focal values clamp and invalid values fall back to center',
      (tester) async {
    final slots = <WebsiteInlineMediaSlot>[];
    final presenters = WebsiteBlockContentPresenters(
      media: (context, slot) {
        slots.add(slot);
        return slot.fallback;
      },
    );

    await _pumpGallery(
      tester,
      width: 834,
      presenters: presenters,
      data: const <String, dynamic>{
        'images': <Map<String, dynamic>>[
          <String, dynamic>{
            'imageUrl': '',
            'focalPointX': 4,
            'focalPointY': -2,
          },
          <String, dynamic>{
            'imageUrl': '',
            'focalPointX': 'not-a-number',
            'focalPointY': double.nan,
          },
        ],
      },
    );

    expect(slots[0].alignment, const Alignment(1, -1));
    expect(slots[1].alignment, Alignment.center);
  });

  testWidgets('missing and decode-failed media keep alt semantics and fallback',
      (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final invalidBytes = Uint8List.fromList(<int>[9, 8, 7, 6]);

    await _pumpGallery(
      tester,
      width: 834,
      imageProviderBuilder: (_) => MemoryImage(invalidBytes),
      data: const <String, dynamic>{
        'images': <Map<String, dynamic>>[
          <String, dynamic>{
            'imageUrl': '',
            'altText': 'Espacio de atención',
          },
          <String, dynamic>{
            'imageUrl': 'memory://invalid',
            'altText': 'Taller principal',
          },
        ],
      },
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(WebsiteGalleryBlockContent.imageFallbackKey(0)),
      findsOneWidget,
    );
    expect(
      find.byKey(WebsiteGalleryBlockContent.imageFallbackKey(1)),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Espacio de atención'), findsOneWidget);
    expect(find.bySemanticsLabel('Taller principal'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semanticsHandle.dispose();
  });
}
