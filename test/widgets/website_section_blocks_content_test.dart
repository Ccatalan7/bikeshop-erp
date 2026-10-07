import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_base_definitions.dart';
import 'package:vinabike_erp/modules/website/models/website_block_surface_style.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_cta_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_faq_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_gallery_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_partners_strip_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_pricing_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_section_frame.dart';
import 'package:vinabike_erp/modules/website/widgets/website_services_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_stats_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_team_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_testimonials_block_content.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';

/// The section blocks of the sections design (2026-10-07), which the HTML
/// storefront draws the same (`website_section_blocks_view.dart`): their
/// layout at a desktop, a tablet and a phone width, their tones, and the
/// contracts they keep with the editor (inline slots, collection aliases,
/// no samples, inert in Edit).

const _primary = Color(0xFF123F68);
const _accent = Color(0xFFFF6F00);
const _deep = Color.from(alpha: 1, red: 0.0466, green: 0.1631, blue: 0.2692);

const _contact = PublicWebsiteContactFacts(
  phone: '+56 9 9835 7797',
  email: 'contacto@vinabike.cl',
  address: 'Alvarez 32, Local 17, Viña del Mar, Chile',
  whatsapp: '+56 9 9835 7797',
  mapsUrl: 'https://maps.google.com/?cid=1',
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 1440,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, 4000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: _primary,
          secondary: _accent,
          surface: Colors.white,
          onSurface: Color(0xDD000000),
        ),
      ),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
}

/// Records every inline slot the content offers, drawing it as text.
class _Recorder {
  final text = <String, WebsiteInlineTextSlot>{};
  final actions = <String, WebsiteInlineActionSlot>{};
  final media = <String, WebsiteInlineMediaSlot>{};

  WebsiteBlockContentPresenters get presenters => WebsiteBlockContentPresenters(
        text: (context, slot) {
          text[slot.id] = slot;
          return Text(slot.displayTransform?.call(slot.value) ?? slot.value);
        },
        action: (context, slot) {
          actions[slot.id] = slot;
          return slot.child;
        },
        media: (context, slot) {
          media[slot.id] = slot;
          return slot.fallback;
        },
      );
}

Color? _bandColor(WidgetTester tester, Finder root) {
  final band = tester.widget<ColoredBox>(
    find.descendant(of: root, matching: find.byType(ColoredBox)).first,
  );
  return band.color;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stats', () {
    const metrics = <Map<String, dynamic>>[
      {'value': '543', 'label': 'trabajos'},
      {'value': '4,4', 'suffix': '★', 'label': 'en Google'},
      {'value': '1.575', 'label': 'productos'},
      {'value': '2015', 'label': 'abrimos'},
    ];

    testWidgets(
        'four figures in a row on a desktop, two on a phone, on the '
        'dark band', (tester) async {
      await _pump(
        tester,
        const WebsiteStatsBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {'title': 'El taller en números', 'metrics': metrics},
        ),
      );
      // (1136 - 3 × 28) / 4 = 263, the column after the first one starts
      // 28 after the line.
      expect(
        tester.getTopLeft(find.byKey(WebsiteStatsBlockContent.metricKey(0))).dx,
        152,
      );
      expect(
        tester.getSize(find.byKey(WebsiteStatsBlockContent.metricKey(0))).width,
        263,
      );
      expect(
        tester.getTopLeft(find.byKey(WebsiteStatsBlockContent.metricKey(1))).dx,
        415,
      );
      expect(
        tester.getTopLeft(find.byKey(WebsiteStatsBlockContent.metricKey(3))).dy,
        tester.getTopLeft(find.byKey(WebsiteStatsBlockContent.metricKey(0))).dy,
      );
      final band = _bandColor(
        tester,
        find.byKey(WebsiteStatsBlockContent.rootKey),
      )!;
      expect(band.r, closeTo(_deep.r, 0.002));
      expect(band.b, closeTo(_deep.b, 0.002));

      await _pump(
        tester,
        const WebsiteStatsBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {'metrics': metrics},
        ),
        width: 390,
      );
      expect(
        tester.getSize(find.byKey(WebsiteStatsBlockContent.metricKey(0))).width,
        175,
      );
      expect(
        tester.getTopLeft(find.byKey(WebsiteStatsBlockContent.metricKey(2))).dy,
        greaterThan(
          tester
              .getTopLeft(find.byKey(WebsiteStatsBlockContent.metricKey(1)))
              .dy,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a Google figure reads the sync and is not written in place; a new '
        'block invents no number', (tester) async {
      final recorder = _Recorder();
      String settings(String key) => switch (key) {
            'google_reviews_rating' => '4.4',
            'google_reviews_total' => '1236',
            _ => '',
          };
      await _pump(
        tester,
        WebsiteStatsBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          presenters: recorder.presenters,
          setting: settings,
          data: Map<String, dynamic>.from(
            websiteBaseBlockDefinitions[WebsiteBlockType.stats]!.defaultData,
          ),
        ),
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(WebsiteStatsBlockContent.liveValueKey(0)),
            )
            .data,
        '4,4',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(WebsiteStatsBlockContent.liveValueKey(1)),
            )
            .data,
        '1.236',
      );
      expect(recorder.text['stats.metric.0.value'], isNull);
      expect(recorder.text['stats.metric.1.value'], isNull);
      expect(recorder.text['stats.metric.0.suffix']?.value, '★');

      // Before the first sync the written value stands, editable in place.
      await _pump(
        tester,
        WebsiteStatsBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          presenters: recorder.presenters,
          setting: (_) => '',
          data: const {
            'metrics': [
              {'source': 'google_rating', 'value': '4,5', 'label': 'nota'},
            ],
          },
        ),
      );
      expect(
        find.byKey(WebsiteStatsBlockContent.liveValueKey(0)),
        findsNothing,
      );
      expect(recorder.text['stats.metric.0.value']?.value, '4,5');
    });

    testWidgets('the light tone and an authored background paint otherwise',
        (tester) async {
      await _pump(
        tester,
        const WebsiteStatsBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {'tone': 'light', 'metrics': metrics},
        ),
      );
      expect(
        _bandColor(tester, find.byKey(WebsiteStatsBlockContent.rootKey)),
        Colors.white,
      );
      await _pump(
        tester,
        const WebsiteStatsBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          paintSurface: false,
          data: {'metrics': metrics},
        ),
      );
      expect(
        _bandColor(tester, find.byKey(WebsiteStatsBlockContent.rootKey)),
        Colors.transparent,
      );
    });

    testWidgets('an explicit empty collection never revives samples',
        (tester) async {
      await _pump(
        tester,
        const WebsiteStatsBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {
            'metrics': <Object?>[],
            'stats': [
              {'value': 'STALE', 'label': 'No publicar'},
            ],
          },
        ),
      );
      expect(
        tester.getSize(find.byKey(WebsiteStatsBlockContent.rootKey)),
        Size.zero,
      );
      expect(find.text('STALE'), findsNothing);
    });

    testWidgets('a legacy collection exposes each figure and the header',
        (tester) async {
      final recorder = _Recorder();
      await _pump(
        tester,
        WebsiteStatsBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          presenters: recorder.presenters,
          data: const {
            'eyebrow': 'Cifras',
            'title': 'Resultados',
            'subtitle': 'Viña del Mar',
            'stats': [
              {
                'id': 'm1',
                'value': '10',
                'suffix': '+',
                'label': 'años',
                'valueFormatting': {'bold': true},
              },
            ],
          },
        ),
      );
      expect(
        recorder.text.keys,
        containsAll([
          'stats.eyebrow',
          'stats.title',
          'stats.subtitle',
          'stats.metric.0.value',
          'stats.metric.0.suffix',
          'stats.metric.0.label',
        ]),
      );
      final value = recorder.text['stats.metric.0.value']!;
      expect(
          value.repeaterTarget?.collectionKeys, ['metrics', 'stats', 'items']);
      expect(value.repeaterTarget?.identityValue, 'm1');
      expect(value.formatting.isBold, isTrue);
      expect(recorder.text['stats.title']!.displayTransform!('Resultados'),
          'RESULTADOS');
    });
  });

  group('services', () {
    const services = <Map<String, dynamic>>[
      {'title': 'Regulación de frenos', 'price': r'$4.000'},
      {
        'title': 'Centrado de rueda',
        'description': 'Por rueda.',
        'price': r'$10.000',
      },
    ];

    testWidgets(
        'numbered rows beside the photo on a desktop; no number nor '
        'photo on a phone', (tester) async {
      await _pump(
        tester,
        WebsiteServicesBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          imageProviderBuilder: (_) => MemoryImage(base64Decode(_pixel)),
          data: const {
            'title': 'Carta del taller',
            'imageUrl': 'https://example.invalid/taller.webp',
            'services': services,
          },
        ),
      );
      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(WebsiteServicesBlockContent.figureKey)).width,
        420,
      );
      expect(
        tester
            .getTopRight(
              find.byKey(WebsiteServicesBlockContent.itemPriceKey(0)),
            )
            .dx,
        lessThan(
          tester
              .getTopLeft(find.byKey(WebsiteServicesBlockContent.figureKey))
              .dx,
        ),
      );

      await _pump(
        tester,
        const WebsiteServicesBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {
            'imageUrl': 'https://example.invalid/taller.webp',
            'services': services,
          },
        ),
        width: 390,
      );
      expect(find.text('01'), findsNothing);
      expect(find.byKey(WebsiteServicesBlockContent.figureKey), findsNothing);
      expect(
        tester
            .getTopRight(
              find.byKey(WebsiteServicesBlockContent.itemPriceKey(1)),
            )
            .dx,
        370,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty canonical services win over a stale items alias',
        (tester) async {
      await _pump(
        tester,
        const WebsiteServicesBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {
            'services': <Object?>[],
            'items': [
              {'title': 'Viejo'},
            ],
          },
        ),
      );
      expect(find.text('Viejo'), findsNothing);
      expect(find.byKey(WebsiteServicesBlockContent.rowKey(0)), findsNothing);
    });

    testWidgets('slots carry the alias, the formatting and the price',
        (tester) async {
      final recorder = _Recorder();
      await _pump(
        tester,
        WebsiteServicesBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          presenters: recorder.presenters,
          data: const {
            'title': 'Servicios',
            'items': [
              {
                'title': 'Mantención',
                'titleFormatting': {'bold': true},
                'description': 'Programada',
                'price': r'$8.000',
              },
            ],
          },
        ),
      );
      final title = recorder.text['services.item.0.title']!;
      expect(title.repeaterTarget?.collectionKeys, ['services', 'items']);
      expect(title.formattingKeys, ['titleFormatting']);
      expect(title.formatting.isBold, isTrue);
      expect(recorder.text['services.item.0.price']!.valueKeys, ['price']);
      expect(recorder.text, contains('services.title'));
      // Without a photo Edit adds no place for one: one geometry.
      expect(recorder.media, isNot(contains('services.image')));
    });
  });

  group('pricing', () {
    const plans = <Map<String, dynamic>>[
      {
        'id': 'basic',
        'name': 'Básica',
        'tag': 'Nivel 1',
        'price': r'$24.990',
        'features': ['Frenos'],
        'ctaText': 'Agendar',
        'ctaLink': '/contacto',
      },
      {
        'name': 'Semi',
        'price': r'$40.000',
        'ctaText': 'Agendar',
        'ctaLink': '/contacto',
      },
      {
        'name': 'Full',
        'badge': 'Desarme completo',
        'price': r'$70.000',
        'ctaText': 'Agendar la Full',
        'ctaLink': '/contacto',
        'highlighted': true,
      },
    ];

    testWidgets(
        'side by side in one card on a desktop, stacked on a phone '
        'with only the highlighted button', (tester) async {
      await _pump(
        tester,
        const WebsitePricingBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {'plans': plans},
        ),
      );
      final first = tester.getRect(
        find.byKey(WebsitePricingBlockContent.planKey(0)),
      );
      final third = tester.getRect(
        find.byKey(WebsitePricingBlockContent.planKey(2)),
      );
      expect(first.top, third.top);
      expect(first.width, closeTo(378, 1));
      expect(find.byKey(WebsitePricingBlockContent.actionKey(0)), findsOne);
      expect(find.text('DESARME COMPLETO'), findsOneWidget);

      await _pump(
        tester,
        const WebsitePricingBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {'plans': plans},
        ),
        width: 390,
      );
      expect(
        tester.getTopLeft(find.byKey(WebsitePricingBlockContent.planKey(1))).dy,
        greaterThan(
          tester
              .getBottomLeft(find.byKey(WebsitePricingBlockContent.planKey(0)))
              .dy,
        ),
      );
      expect(find.byKey(WebsitePricingBlockContent.actionKey(0)), findsNothing);
      expect(find.byKey(WebsitePricingBlockContent.actionKey(2)), findsOne);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty destination has no button, in Public and in Edit',
        (tester) async {
      const data = {
        'plans': [
          {'name': 'Consulta', 'ctaText': 'Hablar', 'ctaLink': ''},
        ],
      };
      await _pump(
        tester,
        WebsitePricingBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          onNavigate: (_) => fail('An empty action cannot navigate.'),
          data: data,
        ),
      );
      expect(find.byKey(WebsitePricingBlockContent.actionKey(0)), findsNothing);
      await _pump(
        tester,
        WebsitePricingBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          presenters: _Recorder().presenters,
          data: data,
        ),
      );
      expect(find.byKey(WebsitePricingBlockContent.actionKey(0)), findsNothing);
    });

    testWidgets(
        'slots and the action carry their keys; Edit does not '
        'navigate, Preview does', (tester) async {
      final recorder = _Recorder();
      final routes = <String>[];
      await _pump(
        tester,
        WebsitePricingBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          presenters: recorder.presenters,
          onNavigate: routes.add,
          data: const {'plans': plans},
        ),
      );
      final name = recorder.text['pricing.plan.0.name']!;
      expect(name.repeaterTarget?.collectionKeys, ['plans', 'items']);
      expect(name.repeaterTarget?.identityValue, 'basic');
      expect(recorder.text['pricing.plan.0.price']!.formattingKeys, [
        'priceFormatting',
      ]);
      final action = recorder.actions['pricing.plan.0.action']!;
      expect(action.labelKeys, ['ctaText', 'buttonText']);
      expect(action.hrefKeys, ['ctaLink', 'buttonLink']);
      await tester.tap(find.byKey(WebsitePricingBlockContent.actionKey(0)));
      expect(routes, isEmpty);

      await _pump(
        tester,
        WebsitePricingBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          onNavigate: routes.add,
          data: const {'plans': plans},
        ),
      );
      await tester.tap(find.byKey(WebsitePricingBlockContent.actionKey(2)));
      expect(routes, ['/contacto']);
    });
  });

  group('testimonials', () {
    String settings(String key) => switch (key) {
          'google_reviews_rating' => '4.4',
          'google_reviews_total' => '36',
          'google_reviews_data' => jsonEncode([
              {
                'author_name': 'Ana',
                'rating': 5,
                'relative_time': 'hace 1 mes',
                'text': 'Excelente',
              },
              {'author_name': 'Sin palabras', 'rating': 5, 'text': ''},
            ]),
          _ => '',
        };

    testWidgets(
        "the store's score and synced reviews when it has no quotes "
        'of its own; the map link navigates', (tester) async {
      final routes = <String>[];
      await _pump(
        tester,
        WebsiteTestimonialsBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          setting: settings,
          mapsUrl: 'https://maps.google.com/?cid=1',
          onNavigate: routes.add,
          data: const {'eyebrow': 'Reseñas en Google'},
        ),
      );
      expect(find.text('4,4'), findsOneWidget);
      expect(find.text('36 reseñas en Google.'), findsOneWidget);
      expect(find.text('“Excelente”'), findsOneWidget);
      expect(find.text('Hace 1 mes · 5 estrellas'), findsOneWidget);
      expect(find.text('Sin palabras'), findsNothing);
      expect(find.bySemanticsLabel('4,4 de 5 estrellas'), findsOneWidget);
      await tester.tap(find.text('VER EN GOOGLE MAPS'));
      expect(routes, ['https://maps.google.com/?cid=1']);
      // The score beside the quotes on a desktop.
      expect(
        tester
            .getTopLeft(
                find.byKey(WebsiteTestimonialsBlockContent.collectionKey))
            .dx,
        152 + 340 + 72,
      );

      await _pump(
        tester,
        WebsiteTestimonialsBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          setting: settings,
          mapsUrl: 'https://maps.google.com/?cid=1',
          data: const {},
        ),
        width: 390,
      );
      expect(find.text('VER EN GOOGLE MAPS'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('its own quotes win and are edited where they are',
        (tester) async {
      final recorder = _Recorder();
      await _pump(
        tester,
        WebsiteTestimonialsBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          setting: settings,
          presenters: recorder.presenters,
          data: const {
            'items': [
              {'name': 'Carla', 'role': 'Cliente', 'comment': 'Bueno'},
            ],
          },
        ),
      );
      final comment = recorder.text['testimonials.item.0.comment']!;
      expect(comment.repeaterTarget?.collectionKeys, ['testimonials', 'items']);
      expect(comment.displayTransform!('Bueno'), '“Bueno”');
      expect(find.text('“Excelente”'), findsNothing);
    });

    testWidgets('without the score nothing comes from Google', (tester) async {
      await _pump(
        tester,
        WebsiteTestimonialsBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          setting: settings,
          data: const {'showGoogleRating': false, 'title': 'Clientes'},
        ),
      );
      expect(find.text('4,4'), findsNothing);
      expect(find.text('“Excelente”'), findsNothing);
      expect(find.text('CLIENTES'), findsOneWidget);
    });
  });

  group('gallery', () {
    final images = [
      for (final caption in ['Taller', 'Ruedas', 'Ruta', 'Sendero'])
        {
          'imageUrl': 'https://example.invalid/$caption.webp',
          'caption': caption
        },
    ];
    ImageProvider pixel(String _) => MemoryImage(base64Decode(_pixel));

    testWidgets(
        'the mosaic with the address fourth on a desktop; on a phone '
        'neither the address nor captions', (tester) async {
      await _pump(
        tester,
        WebsiteGalleryBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          address: _contact.address,
          imageProviderBuilder: pixel,
          data: {'images': images},
        ),
      );
      // Four columns of (1136 - 36) / 4 = 275: the first photo is two
      // columns and two rows of 230.
      expect(
        tester.getSize(find.byKey(WebsiteGalleryBlockContent.tileKey(0))),
        const Size(562, 472),
      );
      expect(
        tester.getSize(find.byKey(WebsiteGalleryBlockContent.addressKey)),
        const Size(275, 230),
      );
      expect(find.text('ALVAREZ 32, LOCAL 17'), findsOneWidget);
      expect(find.text('Viña del Mar'), findsOneWidget);
      // The fourth photo runs the whole width under them.
      expect(
        tester.getSize(find.byKey(WebsiteGalleryBlockContent.tileKey(3))),
        const Size(1136, 230),
      );

      await _pump(
        tester,
        WebsiteGalleryBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          address: _contact.address,
          imageProviderBuilder: pixel,
          data: {'images': images},
        ),
        width: 390,
      );
      expect(find.byKey(WebsiteGalleryBlockContent.addressKey), findsNothing);
      expect(find.text('TALLER'), findsNothing);
      expect(
        tester.getSize(find.byKey(WebsiteGalleryBlockContent.tileKey(0))),
        const Size(350, 308),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'no photos are fabricated: an item without one is a place '
        'for it, where Edit puts the photo', (tester) async {
      final recorder = _Recorder();
      await _pump(
        tester,
        WebsiteGalleryBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          presenters: recorder.presenters,
          data: const {
            'images': [
              {'caption': 'Sin foto', 'focalPointX': 2, 'focalPointY': 0},
            ],
          },
        ),
      );
      expect(
        find.byKey(WebsiteGalleryBlockContent.imageFallbackKey(0)),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
      final media = recorder.media['gallery.image.0.media']!;
      expect(media.url, isNull);
      expect(media.valueKeys, ['imageUrl']);
      expect(media.alignment, const Alignment(1, -1));
      expect(media.repeaterTarget?.collectionKeys, ['images']);
    });

    testWidgets(
        'without photos the address alone fills the row, as the HTML '
        'draws it; a new gallery brings four places for photos',
        (tester) async {
      await _pump(
        tester,
        WebsiteGalleryBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          address: _contact.address,
          data: const {'images': <Map<String, dynamic>>[]},
        ),
      );
      expect(
        tester.getSize(find.byKey(WebsiteGalleryBlockContent.addressKey)),
        const Size(1136, 230),
      );

      final fresh = Map<String, dynamic>.from(
        websiteBaseBlockDefinitions[WebsiteBlockType.gallery]!.defaultData,
      );
      await _pump(
        tester,
        WebsiteGalleryBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          address: _contact.address,
          data: fresh,
        ),
      );
      for (var index = 0; index < 4; index++) {
        expect(
          find.byKey(WebsiteGalleryBlockContent.imageFallbackKey(index)),
          findsOneWidget,
        );
      }
      // One whole group: two photos, the address fourth, a wide photo.
      expect(
        tester.getSize(find.byKey(WebsiteGalleryBlockContent.tileKey(3))),
        const Size(1136, 230),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the even grid has three columns and no address',
        (tester) async {
      await _pump(
        tester,
        WebsiteGalleryBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          address: _contact.address,
          imageProviderBuilder: pixel,
          data: {'layout': 'grid', 'images': images},
        ),
      );
      expect(find.byKey(WebsiteGalleryBlockContent.addressKey), findsNothing);
      expect(
        tester.getSize(find.byKey(WebsiteGalleryBlockContent.tileKey(0))).width,
        closeTo((1136 - 24) / 3, 0.01),
      );
    });
  });

  group('team', () {
    const members = <Map<String, dynamic>>[
      {'name': 'Claudio', 'role': 'Jefe de taller', 'bio': 'Suspensiones.'},
      {
        'name': 'Pablo',
        'role': 'Mecánico',
        'bio': 'Ruedas.',
        'instagram': 'https://instagram.com/vinabike',
      },
    ];

    testWidgets(
        'members in columns on a desktop, a list on a phone; the '
        'person mark without a portrait', (tester) async {
      final routes = <String>[];
      await _pump(
        tester,
        WebsiteTeamBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          onNavigate: routes.add,
          data: const {'title': 'Equipo', 'members': members},
        ),
      );
      expect(
        tester
            .getTopLeft(find.byKey(WebsiteTeamBlockContent.memberCardKey(1)))
            .dy,
        tester
            .getTopLeft(find.byKey(WebsiteTeamBlockContent.memberCardKey(0)))
            .dy,
      );
      expect(
        tester.getSize(find.byKey(WebsiteTeamBlockContent.memberAvatarKey(0))),
        const Size(88, 88),
      );
      expect(find.byIcon(Icons.person_outline), findsNWidgets(2));
      await tester.tap(find.text('INSTAGRAM'));
      expect(routes, ['https://instagram.com/vinabike']);

      await _pump(
        tester,
        const WebsiteTeamBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {'members': members},
        ),
        width: 390,
      );
      expect(
        tester.getSize(find.byKey(WebsiteTeamBlockContent.memberAvatarKey(0))),
        const Size(64, 64),
      );
      expect(
        tester
            .getTopLeft(find.byKey(WebsiteTeamBlockContent.memberCardKey(1)))
            .dy,
        greaterThan(
          tester
                  .getBottomLeft(
                      find.byKey(WebsiteTeamBlockContent.memberCardKey(0)))
                  .dy -
              1,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no members are fabricated; slots keep the aliases',
        (tester) async {
      await _pump(
        tester,
        const WebsiteTeamBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {'members': <Object?>[]},
        ),
      );
      expect(find.byKey(WebsiteTeamBlockContent.membersKey), findsNothing);
      final recorder = _Recorder();
      await _pump(
        tester,
        WebsiteTeamBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          presenters: recorder.presenters,
          onNavigate: (_) => fail('Edit is inert.'),
          data: const {'team': members},
        ),
      );
      final name = recorder.text['team.member.0.name']!;
      expect(name.repeaterTarget?.collectionKeys, ['members', 'team', 'items']);
      expect(recorder.media['team.member.0.avatar']!.valueKeys, [
        'avatarUrl',
        'image',
      ]);
      await tester.tap(find.text('INSTAGRAM'));
    });
  });

  group('faq', () {
    const items = <Map<String, dynamic>>[
      {'question': '¿Cuánto demora?', 'answer': 'Entre 3 y 12 días.'},
      {'question': '¿Retiro?', 'answer': 'Sí, sin costo.'},
    ];

    testWidgets(
        'the first question opens; the side beside the list on a '
        'desktop, above it on a phone', (tester) async {
      await _pump(
        tester,
        const WebsiteFaqBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          siteContact: _contact,
          data: {'title': 'Envíos', 'items': items},
        ),
      );
      expect(find.text('Entre 3 y 12 días.'), findsOneWidget);
      expect(find.text('Sí, sin costo.'), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(WebsiteFaqBlockContent.collectionKey)).dx,
        152 + 360 + 72,
      );
      await tester.tap(find.text('¿Retiro?'));
      await tester.pumpAndSettle();
      expect(find.text('Sí, sin costo.'), findsOneWidget);

      await _pump(
        tester,
        const WebsiteFaqBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          siteContact: _contact,
          data: {'title': 'Envíos', 'items': items},
        ),
        width: 390,
      );
      expect(
        tester.getTopLeft(find.byKey(WebsiteFaqBlockContent.collectionKey)).dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(WebsiteFaqBlockContent.sideKey)).dy,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        "the invitation to write with the store's WhatsApp and mail; "
        'off when the block says so', (tester) async {
      final routes = <String>[];
      await _pump(
        tester,
        WebsiteFaqBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          siteContact: _contact,
          onNavigate: routes.add,
          data: const {'items': items},
        ),
      );
      final line = tester.widget<Text>(
        find.descendant(
          of: find.byKey(WebsiteFaqBlockContent.contactKey),
          matching: find.byType(Text),
        ),
      );
      expect(
        line.textSpan!.toPlainText(),
        '¿Otra duda? Escríbenos al +56 9 9835 7797 o a contacto@vinabike.cl.',
      );
      await _pump(
        tester,
        const WebsiteFaqBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          siteContact: _contact,
          data: {'showContact': false, 'items': items},
        ),
      );
      expect(find.byKey(WebsiteFaqBlockContent.contactKey), findsNothing);
    });

    testWidgets('an explicit empty list shows no question; slots are nested',
        (tester) async {
      await _pump(
        tester,
        const WebsiteFaqBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {'items': <Object?>[], 'title': 'Preguntas'},
        ),
      );
      expect(find.byKey(WebsiteFaqBlockContent.collectionKey), findsNothing);
      final recorder = _Recorder();
      await _pump(
        tester,
        WebsiteFaqBlockContent(
          primaryColor: _primary,
          accentColor: _accent,
          presenters: recorder.presenters,
          data: const {
            'items': [
              {
                'question': '¿Casco?',
                'answer': 'Sí',
                'answerFormatting': {'italic': true},
              },
            ],
          },
        ),
      );
      final answer = recorder.text['faq.item.0.answer']!;
      expect(answer.repeaterTarget?.collectionKeys, ['items']);
      expect(answer.formattingKeys, ['answerFormatting']);
      expect(answer.formatting.isItalic, isTrue);
    });
  });

  group('call to action', () {
    WebsiteBlockSurfaceStyle surface([Map<String, dynamic> data = const {}]) =>
        WebsiteBlockSurfaceStyle.resolve(
          data: data,
          viewport: WebsiteViewport.desktop,
        );

    testWidgets(
        "empty buttons open the store's WhatsApp and its map; the "
        'contacts beside on a desktop', (tester) async {
      final routes = <String>[];
      await _pump(
        tester,
        WebsiteCtaBlockContent(
          surfaceStyle: surface(),
          primaryColor: _primary,
          accentColor: _accent,
          siteContact: _contact,
          onNavigate: routes.add,
          data: const {
            'title': 'Agenda tu mantención',
            'buttonText': 'Escribir por WhatsApp',
            'buttonLink': '',
            'secondaryText': 'Cómo llegar',
          },
        ),
      );
      expect(find.text('AGENDA TU MANTENCIÓN'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
      await tester.tap(find.byKey(WebsiteCtaBlockContent.actionKey));
      await tester.tap(find.byKey(WebsiteCtaBlockContent.secondaryActionKey));
      expect(routes, [
        'https://wa.me/56998357797',
        'https://maps.google.com/?cid=1',
      ]);
      expect(find.text('WHATSAPP'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(WebsiteCtaBlockContent.contactsKey)).width,
        340,
      );

      await _pump(
        tester,
        WebsiteCtaBlockContent(
          surfaceStyle: surface(),
          primaryColor: _primary,
          accentColor: _accent,
          siteContact: _contact,
          data: const {'buttonText': 'Agendar', 'showContact': false},
        ),
        width: 390,
      );
      expect(find.byKey(WebsiteCtaBlockContent.contactsKey), findsNothing);
      expect(
        tester.getSize(find.byKey(WebsiteCtaBlockContent.actionKey)).width,
        350,
      );
      expect(find.text('¿NECESITAS AYUDA?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Edit gets the stored destinations: an empty one stays empty and '
        'says where it leads; the second button mirrors nothing',
        (tester) async {
      final recorder = _Recorder();
      await _pump(
        tester,
        WebsiteCtaBlockContent(
          surfaceStyle: surface(),
          primaryColor: _primary,
          accentColor: _accent,
          siteContact: _contact,
          presenters: recorder.presenters,
          data: const {
            'buttonText': 'Escribir por WhatsApp',
            'buttonLink': '',
            'secondaryText': 'Cómo llegar',
            'secondaryLink': '',
          },
        ),
      );
      final primary = recorder.actions['cta.action']!;
      expect(primary.action.href, '');
      expect(primary.actionsKey, 'actions');
      expect(primary.destinationHelp, 'Vacío, abre el WhatsApp de la tienda.');
      final secondary = recorder.actions['cta.secondary']!;
      expect(secondary.action.href, '');
      expect(secondary.actionsKey, isNull);
      expect(secondary.destinationHelp, 'Vacío, abre el mapa del negocio.');
      // The visitor's buttons still lead to the WhatsApp and the map.
      expect(
        tester
            .widget<WebsiteSectionButton>(
              find.descendant(
                of: find.byKey(WebsiteCtaBlockContent.actionKey),
                matching: find.byType(WebsiteSectionButton),
              ),
            )
            .href,
        'https://wa.me/56998357797',
      );
    });

    testWidgets(
        "the veil is the brand's deepest tone unless the block chose "
        'a color; a height is kept', (tester) async {
      await _pump(
        tester,
        WebsiteCtaBlockContent(
          surfaceStyle: surface(),
          primaryColor: _primary,
          accentColor: _accent,
          imageProviderBuilder: (_) => MemoryImage(base64Decode(_pixel)),
          data: const {
            'title': 'Ven',
            'backgroundImage': 'https://example.invalid/ruta.webp',
            'blockHeight': 360,
          },
        ),
      );
      final veil = tester.widget<ColoredBox>(
        find.byKey(WebsiteCtaBlockContent.overlayKey),
      );
      expect(veil.color.a, closeTo(0.8, 0.001));
      expect(veil.color.r, closeTo(0.0353, 0.002));
      expect(tester.getSize(find.byKey(WebsiteCtaBlockContent.rootKey)).height,
          360);

      await _pump(
        tester,
        WebsiteCtaBlockContent(
          surfaceStyle: surface(),
          primaryColor: _primary,
          accentColor: _accent,
          imageProviderBuilder: (_) => MemoryImage(base64Decode(_pixel)),
          data: const {
            'backgroundImage': 'https://example.invalid/ruta.webp',
            'overlayColor': '#000000',
            'overlayOpacity': 0.4,
          },
        ),
      );
      expect(
        tester
            .widget<ColoredBox>(find.byKey(WebsiteCtaBlockContent.overlayKey))
            .color,
        Colors.black.withValues(alpha: 0.4),
      );
    });

    testWidgets(
        'Edit offers the texts and both buttons where they are, '
        'and never navigates', (tester) async {
      final recorder = _Recorder();
      await _pump(
        tester,
        WebsiteCtaBlockContent(
          surfaceStyle: surface(),
          primaryColor: _primary,
          accentColor: _accent,
          siteContact: _contact,
          presenters: recorder.presenters,
          onNavigate: (_) => fail('Edit is inert.'),
          data: const {
            'title': 'Agenda',
            'subtitle': 'Texto',
            'buttonText': 'Escribir',
            'secondaryText': 'Cómo llegar',
          },
        ),
      );
      expect(recorder.text, contains('cta.title'));
      expect(recorder.text['cta.subtitle']!.valueKeys, [
        'subtitle',
        'description',
      ]);
      expect(
          recorder.actions['cta.action']!.hrefKeys, ['buttonLink', 'ctaLink']);
      expect(recorder.actions['cta.secondary']!.labelKeys, ['secondaryText']);
      await tester.tap(find.byKey(WebsiteCtaBlockContent.actionKey));
    });
  });

  group('brands strip', () {
    testWidgets('the label and the names in a row, never samples',
        (tester) async {
      await _pump(
        tester,
        const WebsitePartnersStripContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {
            'title': 'Marcas que trabajamos',
            'items': [
              {'label': 'Shimano'},
              {'label': 'Maxxis'},
            ],
          },
        ),
      );
      expect(find.text('MARCAS QUE TRABAJAMOS'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('MAXXIS')).dy,
        closeTo(tester.getTopLeft(find.text('SHIMANO')).dy, 0.5),
      );
      await _pump(
        tester,
        const WebsitePartnersStripContent(
          primaryColor: _primary,
          accentColor: _accent,
          data: {'items': <Object?>[]},
        ),
      );
      expect(find.text('SANTIAGO, CHILE'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  test('the section colors come from the site theme', () {
    expect(websiteSectionColor(websiteSectionRgba(_primary)), _primary);
  });
}

/// A 1×1 PNG.
const _pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
