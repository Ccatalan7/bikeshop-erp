import 'dart:convert';

import 'package:test/test.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_capabilities.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_section_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_section_palette.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

void main() {
  group('section tones', () {
    final primary = WebsiteRgba.fromArgb(0xFF123F68);
    final accent = WebsiteRgba.fromArgb(0xFFFF6F00);
    final white = WebsiteRgba.fromArgb(0xFFFFFFFF);
    final ink = WebsiteRgba.fromArgb(0xDD000000);

    test('the dark band is the primary toward black, its text white and '
        'its eyebrow the accent lightened', () {
      final dark = WebsiteSectionPalette.resolve(
        tone: WebsiteSectionTone.dark,
        primary: primary,
        accent: accent,
        background: white,
        onSurface: ink,
      );
      expect(dark.surface.css, 'rgb(11.88 41.58 68.64)');
      expect(dark.ink.css, 'rgb(255 255 255)');
      expect(dark.eyebrow.css, 'rgb(255 154.2 76.5)');
      expect(
        WebsiteRgba.contrast(dark.muted.withAlpha(1), dark.surface),
        greaterThan(4.5),
      );
    });

    test('a light band keeps the brand for its eyebrow when it reads, the '
        'dark tone otherwise', () {
      final band = WebsiteSectionPalette.resolve(
        tone: WebsiteSectionTone.band,
        primary: primary,
        accent: accent,
        background: white,
        onSurface: ink,
      );
      expect(band.eyebrow.css, primary.css);
      final pale = WebsiteSectionPalette.resolve(
        tone: WebsiteSectionTone.light,
        primary: WebsiteRgba.fromArgb(0xFFFFD54F),
        accent: accent,
        background: white,
        onSurface: ink,
      );
      expect(
        WebsiteRgba.contrast(pale.eyebrow, white),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('a primary so light that white does not read on its dark tone gets '
        'the dark ink', () {
      final dark = WebsiteSectionPalette.resolve(
        tone: WebsiteSectionTone.dark,
        primary: WebsiteRgba.fromArgb(0xFFFFFFFF),
        accent: accent,
        background: white,
        onSurface: ink,
      );
      expect(dark.ink.css, isNot('rgb(255 255 255)'));
    });

    test('each section type has its background, stored or by default', () {
      expect(
        WebsiteSectionTone.of(WebsiteBlockType.stats, const {}),
        WebsiteSectionTone.dark,
      );
      expect(
        WebsiteSectionTone.of(WebsiteBlockType.faq, const {}),
        WebsiteSectionTone.band,
      );
      expect(
        WebsiteSectionTone.of(WebsiteBlockType.team, const {'tone': 'dark'}),
        WebsiteSectionTone.dark,
      );
      expect(
        WebsiteSectionTone.of(WebsiteBlockType.team, const {'tone': 'neón'}),
        WebsiteSectionTone.light,
      );
    });

    test('the section blocks run to the edges unless they say otherwise', () {
      for (final type in const [
        WebsiteBlockType.stats,
        WebsiteBlockType.services,
        WebsiteBlockType.pricing,
        WebsiteBlockType.testimonials,
        WebsiteBlockType.gallery,
        WebsiteBlockType.team,
        WebsiteBlockType.faq,
        WebsiteBlockType.cta,
        WebsiteBlockType.partnersBanner,
      ]) {
        expect(websiteBlockDefaultFullBleed(type), isTrue, reason: '$type');
      }
      expect(websiteBlockDefaultFullBleed(WebsiteBlockType.text), isFalse);
    });

    test('the widths a section is laid out by', () {
      expect(WebsiteSectionWidth.of(390), WebsiteSectionWidth.phone);
      expect(WebsiteSectionWidth.of(600), WebsiteSectionWidth.tablet);
      expect(WebsiteSectionWidth.of(1023.9), WebsiteSectionWidth.tablet);
      expect(WebsiteSectionWidth.of(1024), WebsiteSectionWidth.desktop);
    });
  });

  group('gallery mosaic', () {
    int area(List<WebsiteMosaicSpan> spans) =>
        spans.fold(0, (sum, span) => sum + span.columns * span.rows);

    test('fills whole rows for any number of cells, never a hole', () {
      for (var count = 1; count <= 23; count++) {
        expect(
          area(websiteMosaicSpans(count, phone: false)) % 4,
          0,
          reason: 'desktop $count',
        );
        expect(
          area(websiteMosaicSpans(count, phone: true)) % 2,
          0,
          reason: 'phone $count',
        );
        expect(websiteMosaicSpans(count, phone: false), hasLength(count));
      }
    });

    test('a group of five is the big, the tall, two small and the wide', () {
      expect(websiteMosaicSpans(5, phone: false), [
        (columns: 2, rows: 2),
        (columns: 1, rows: 2),
        (columns: 1, rows: 1),
        (columns: 1, rows: 1),
        (columns: 4, rows: 1),
      ]);
      expect(websiteGalleryAddressSlot(4), 3);
      expect(websiteGalleryAddressSlot(2), 2);
    });

    test('an address is a street and a city, the country left out', () {
      expect(websiteAddressLines('Alvarez 32, Local 17, Viña del Mar, Chile'), (
        street: 'Alvarez 32, Local 17',
        city: 'Viña del Mar',
      ));
      expect(websiteAddressLines('Av. Libertad 100, Viña del Mar'), (
        street: 'Av. Libertad 100',
        city: 'Viña del Mar',
      ));
      expect(websiteAddressLines('Taller'), (street: 'Taller', city: ''));
      expect(websiteAddressLines('  '), (street: '', city: ''));
    });
  });

  group('testimonials', () {
    String Function(String) settings(Map<String, String> values) =>
        (key) => values[key] ?? '';
    final synced = settings({
      'google_reviews_rating': '4.4',
      'google_reviews_total': '36',
      'google_reviews_data': jsonEncode([
        {
          'author_name': 'Ana',
          'rating': 5,
          'relative_time': 'hace 1 mes',
          'text': 'Excelente',
        },
        {'author_name': 'Sin palabras', 'rating': 5, 'text': ''},
        {'author_name': 'Bajo', 'rating': 2, 'text': 'Malo'},
        {'author_name': 'Beto', 'rating': 4, 'text': 'Bien'},
      ]),
    });

    test("without quotes of its own it shows the synced reviews with words, "
        'only good ones, and the score', () {
      final content = WebsiteTestimonialsContent.resolve(
        const {'testimonials': <Object?>[]},
        setting: synced,
        mapsUrl: 'https://maps.google.com/?cid=1',
      );
      expect(content.quotes.map((quote) => quote.name), ['Ana', 'Beto']);
      expect(content.quotes.first.meta, 'Hace 1 mes · 5 estrellas');
      expect(content.quotes.first.isOwn, isFalse);
      expect(websiteRatingLabel(content.rating!), '4,4');
      expect(content.note(''), '36 reseñas en Google.');
      expect(
        content.note('Del taller y la tienda.'),
        'Del taller y la tienda.',
      );
      expect(content.mapsUrl, 'https://maps.google.com/?cid=1');
    });

    test('its own quotes win, addressed by where they are stored', () {
      final content = WebsiteTestimonialsContent.resolve(
        const {
          'testimonials': [
            'no es un testimonio',
            {
              'name': 'Carla',
              'role': 'Cliente del taller',
              'comment': 'Bueno',
              'rating': 5,
            },
          ],
        },
        setting: synced,
        mapsUrl: '',
      );
      expect(content.quotes.single.index, 1);
      expect(content.quotes.single.initial, 'C');
      expect(content.quotes.single.meta, 'Cliente del taller · 5 estrellas');
    });

    test('with the score turned off nothing comes from Google', () {
      final content = WebsiteTestimonialsContent.resolve(
        const {'showGoogleRating': false},
        setting: synced,
        mapsUrl: 'https://maps.google.com/?cid=1',
      );
      expect(content.quotes, isEmpty);
      expect(content.rating, isNull);
      expect(content.mapsUrl, isEmpty);
    });
  });

  group('call to action', () {
    test('an empty main button opens WhatsApp, or the contact page', () {
      final actions = websiteCtaActions(
        const {
          'buttonText': 'Escribir',
          'buttonLink': '',
          'secondaryText': 'Cómo llegar',
        },
        whatsappHref: 'https://wa.me/56998357797',
        mapsUrl: 'https://maps.google.com/?cid=1',
      );
      expect(actions.primary, (
        label: 'Escribir',
        href: 'https://wa.me/56998357797',
        whatsapp: true,
      ));
      expect(actions.secondary?.href, 'https://maps.google.com/?cid=1');
      final none = websiteCtaActions(
        const {'buttonText': 'Agendar', 'secondaryText': 'Cómo llegar'},
        whatsappHref: '',
        mapsUrl: '',
      );
      expect(none.primary?.href, '/contacto');
      expect(none.secondary, isNull);
    });

    test('a button without a label is not drawn', () {
      final actions = websiteCtaActions(
        const {'buttonText': ' ', 'buttonLink': '/x'},
        whatsappHref: '',
        mapsUrl: 'https://maps.google.com/?cid=1',
      );
      expect(actions.primary, isNull);
      expect(actions.secondary, isNull);
    });
  });

  test('plans go side by side while each has 260', () {
    expect(websitePlansSideBySide(3, 1136), isTrue);
    expect(websitePlansSideBySide(3, 770), isFalse);
    expect(websitePlansSideBySide(2, 560), isTrue);
    expect(websitePlansSideBySide(0, 1136), isFalse);
    expect(websiteStatsColumns(4, desktop: true), 4);
    expect(websiteStatsColumns(6, desktop: true), 4);
    expect(websiteStatsColumns(3, desktop: false), 2);
    expect(websiteStatsColumns(1, desktop: false), 1);
  });

  test('a Google figure reads the sync; until then, what is written', () {
    String synced(String key) => switch (key) {
      'google_reviews_rating' => '4.42',
      'google_reviews_total' => '1236',
      _ => '',
    };
    const rating = {'source': 'google_rating', 'value': '4,5', 'suffix': '★'};
    const reviews = {'source': 'google_reviews', 'value': ''};
    expect(websiteStatsFigure(rating, setting: synced), (
      value: '4,4',
      suffix: '★',
      live: true,
    ));
    expect(websiteStatsFigure(reviews, setting: synced), (
      value: '1.236',
      suffix: '',
      live: true,
    ));
    expect(websiteStatsFigure(rating, setting: (_) => ''), (
      value: '4,5',
      suffix: '★',
      live: false,
    ));
    expect(
      websiteStatsFigure(const {'value': '543'}, setting: synced).live,
      isFalse,
    );
    expect(websiteCountLabel(36), '36');
    expect(websiteCountLabel(1000), '1.000');
    expect(websiteCountLabel(1234567), '1.234.567');
  });
}
