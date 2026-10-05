import 'dart:convert';

// The core runs on the plain Dart VM: `dart test` here has no Flutter SDK, so
// this file fails to compile the day a core file imports Flutter. The rules
// themselves are covered by the ERP's unit tests (test/unit/public_*).
import 'package:test/test.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_base_definitions.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_google_reviews.dart';
import 'package:vinabike_public_core/modules/website/models/website_hero_content.dart';
import 'package:vinabike_public_core/modules/website/models/website_page_composition.dart';
import 'package:vinabike_public_core/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_public_core/modules/website/models/website_responsive_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';
import 'package:vinabike_public_core/public_store/seo/public_page_structured_data.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_product_brand_names.dart';
import 'package:vinabike_public_core/public_store/models/public_product_spec_sheet.dart';
import 'package:vinabike_public_core/public_store/seo/public_product_structured_data.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';

void main() {
  test(
    'a public product row becomes a page: projection, sheet, path, JSON-LD',
    () {
      final commerce = PublicCommerceProductProjection.fromJson(
        {
          'id': '6f1d2a3e-0000-4000-8000-000000000911',
          'name': 'Horquilla Suntour 29 Auron 35',
          'sku': 'H911',
          'price': 550000,
          'stock_quantity': 2,
          'track_stock': true,
          'image_urls': ['https://example.invalid/h911.jpg'],
          'category_id': 'c0000000-0000-4000-8000-000000000001',
        },
        resolvedBrand: 'Suntour',
        categoryPath: 'Componentes > Horquillas',
      );
      final sheet = PublicProductSpecSheet.build(
        rows: [
          PublicProductSpecRow.fromJson({
            'section_key': 'medidas',
            'section_sort_order': 1,
            'field_sort_order': 1,
            'spec_key': 'travel_mm',
            'spec_label': 'Recorrido',
            'display_value': '160',
            'unit': 'mm',
            'data_type': 'number',
          }),
        ],
        identity: const PublicSpecIdentity(brand: 'Suntour'),
      );
      final path = buildPublicProductPath(
        name: commerce.title,
        sku: commerce.sku,
      );
      final jsonLd = buildPublicProductStructuredData(
        commerce: commerce,
        productUrl: 'https://vinabike.cl$path',
        storeUrl: 'https://vinabike.cl',
        storeName: 'Viñabike',
        specSheet: sheet,
      );

      expect(commerce.sku, 'H911');
      expect(path, endsWith('/H911'));
      expect(sheet.hasTechnicalData, isTrue);
      expect(
        encodeStructuredDataForHtml(jsonLd!),
        contains('"@type":"Product"'),
      );
    },
  );

  test('a brand from another tenant never names a public product', () {
    final names = canonicalPublicProductBrandNames(
      rows: [
        {'id': 'b1', 'name': 'Suntour', 'tenant_id': null, 'is_active': true},
        {'id': 'b2', 'name': 'Ajena', 'tenant_id': 'otro', 'is_active': true},
      ],
      tenantId: 'mio',
      requestedBrandIds: ['b1', 'b2'],
    );
    expect(names, {'b1': 'Suntour'});
  });

  test('an editor page becomes blocks, sections and its schema.org node', () {
    final blocks = [
      {
        'id': 'faq',
        'block_type': 'faq',
        'order_index': 2,
        'block_data': {
          'title': 'Preguntas',
          'items': [
            {'question': '¿Cuánto demora?', 'answer': 'De 3 a 12 días.'},
          ],
        },
      },
      {
        'id': 'hero',
        'block_type': 'hero',
        'order_index': 0,
        'block_data': {'title': 'Envíos', 'blockHeight': 280},
      },
      {
        'id': 'oculto',
        'block_type': 'about',
        'order_index': 1,
        'is_visible': false,
        'block_data': {'title': 'Borrador', 'content': 'No se publica.'},
      },
    ];
    final composition = WebsitePageComposition.project(
      blocks: blocks,
      mode: WebsitePageCompositionMode.public,
      breakpoint: 'desktop',
    );
    final hero = WebsiteResponsiveBlockProjection.project(
      type: WebsiteBlockType.hero,
      data: {
        'title': 'Envíos',
        'blockHeight': 280,
        'responsive': {
          // Copy stays the same on every screen unless whitelisted; a
          // measurement may change.
          'mobile': {'title': 'Envíos a Chile', 'blockHeight': 200},
        },
      },
      viewport: WebsiteViewport.mobile,
    );

    expect(composition.blocks.map((block) => block.id), ['hero', 'faq']);
    expect(composition.blocks.first.geometry.fullBleed, isTrue);
    expect(composition.blocks.first.geometry.exactHeight, 280);
    expect(websiteBlockFieldsFor(WebsiteBlockType.hero), isNotEmpty);
    expect(hero['title'], 'Envíos');
    expect(hero['blockHeight'], 200);
    expect(hasMeaningfulPublicPolicyContent(blocks), isTrue);
    expect(
      extractPublicPolicySections(blocks).map((section) => section.title),
      ['Preguntas', 'Borrador'],
    );
    expect(
      buildPublicPageStructuredData(
        slug: 'envios',
        title: 'Envíos',
        description: 'Despachos a Chile continental.',
        pageUrl: 'https://vinabike.cl/envios',
        storeUrl: 'https://vinabike.cl',
        storeName: 'Viñabike',
      )['@type'],
      'WebPage',
    );
  });

  test('the home blocks read their content the same in Flutter and HTML', () {
    // A slide's button: its own fields, outlined unless it says otherwise.
    final action = resolveWebsiteCarouselSlideAction({
      'ctaText': 'Ver cámaras',
      'ctaLink': '/productos',
      'actionVariant': 'filled',
      'label': 'ignorado',
    });
    expect(action?.label, 'Ver cámaras');
    expect(action?.variant.storageValue, 'filled');
    expect(resolveWebsiteCarouselSlideAction({'ctaText': ' '}), isNull);

    expect(
      websiteYouTubeVideoId('https://youtu.be/BnJCsaH5Ybs?si=x'),
      'BnJCsaH5Ybs',
    );
    expect(websiteYouTubeVideoId('https://www.youtube.com/watch?v=abc'), 'abc');
    expect(websiteYouTubeVideoId('https://www.youtube.com/embed/xyz'), 'xyz');
    expect(websiteYouTubeVideoId('https://vimeo.com/1'), isNull);

    // Reviews: the store's synced ones when the block has none, filtered by
    // the block, and the aggregate over the whole list.
    final settings = {
      'google_reviews_data': jsonEncode([
        {'author_name': 'Mia', 'rating': 5},
        {
          'reviewer': {'displayName': 'Ana'},
          'starRating': 'FOUR',
        },
        {'author_name': 'Juan', 'rating': 2},
        {'author_name': 'Sin nota'},
      ]),
      'google_reviews_total': '36',
    };
    final data = WebsiteGoogleReviewsContent.withSyncedReviews({
      'minRating': 4,
    }, (key) => settings[key] ?? '');
    final content = WebsiteGoogleReviewsContent.fromData(data);
    expect(
      [
        for (final review in content.reviews)
          WebsiteGoogleReviewsContent.authorName(review.data),
      ],
      ['Mia', 'Ana'],
    );
    expect(content.rating, closeTo(11 / 3, 1e-9));
    expect(content.totalReviews, 36);
    expect(
      WebsiteGoogleReviewsContent.text(content.reviews.first.data),
      'Calificación publicada en Google.',
    );
    expect(
      WebsiteGoogleReviewsContent.fromData(const {}).rating,
      isNull,
      reason: 'without reviews there is no score to show',
    );
  });
}
