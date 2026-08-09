import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';

void main() {
  group('WebsiteResponsiveBlockProjection', () {
    test('tablet and mobile inherit directly from shared', () {
      final source = <String, dynamic>{
        'alignment': 'left',
        'title': 'Texto común',
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{
            'alignment': 'right',
            // Title is shared-only and must never become display-copy just
            // because malformed persisted data contains an override.
            'title': 'Texto móvil no autorizado',
          },
        },
      };

      final tablet = WebsiteResponsiveBlockProjection.project(
        type: WebsiteBlockType.hero,
        data: source,
        viewport: WebsiteViewport.tablet,
      );
      final mobile = WebsiteResponsiveBlockProjection.project(
        type: WebsiteBlockType.hero,
        data: source,
        viewport: WebsiteViewport.mobile,
      );

      expect(tablet['alignment'], 'left');
      expect(mobile['alignment'], 'right');
      expect(tablet['title'], 'Texto común');
      expect(mobile['title'], 'Texto común');
      expect(source['alignment'], 'left', reason: 'projection is immutable');
    });

    test('legacy mobile cover aliases and focal point remain readable', () {
      final source = <String, dynamic>{
        'backgroundImage': 'https://cdn.test/shared.webp',
        'mobileImageUrl': 'https://cdn.test/mobile.webp',
        'focalPointX': 0.5,
        'focalPointY': 0.4,
        'mobileFocalPointX': 0.2,
        'mobileFocalPointY': 0.8,
      };

      final mobile = WebsiteResponsiveBlockProjection.project(
        type: WebsiteBlockType.hero,
        data: source,
        viewport: WebsiteViewport.mobile,
      );
      final tablet = WebsiteResponsiveBlockProjection.project(
        type: WebsiteBlockType.hero,
        data: source,
        viewport: WebsiteViewport.tablet,
      );

      expect(mobile['imageUrl'], 'https://cdn.test/mobile.webp');
      expect(mobile['backgroundImage'], 'https://cdn.test/mobile.webp');
      expect(mobile['focalPointX'], 0.2);
      expect(mobile['focalPointY'], 0.8);
      expect(tablet['imageUrl'], 'https://cdn.test/shared.webp');
      expect(tablet['focalPointX'], 0.5);
      expect(tablet['focalPointY'], 0.4);
    });

    test('canonical focal override wins without deleting legacy aliases', () {
      final source = <String, dynamic>{
        'backgroundImage': 'https://cdn.test/shared.webp',
        'focalPointX': 0.5,
        'focalPointY': 0.4,
        'mobileFocalPointX': 0.1,
        'mobileFocalPointY': 0.9,
        'mobileBgAlignment': 'right',
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{
            'focalPointX': 0.25,
            'focalPointY': 0.75,
          },
        },
      };

      final mobile = WebsiteResponsiveBlockProjection.project(
        type: WebsiteBlockType.hero,
        data: source,
        viewport: WebsiteViewport.mobile,
      );

      expect(mobile['focalPointX'], 0.25);
      expect(mobile['focalPointY'], 0.75);
      expect(mobile['mobileFocalPointX'], 0.1);
      expect(mobile['mobileFocalPointY'], 0.9);
      expect(mobile['mobileBgAlignment'], 'right');
      expect(source['focalPointX'], 0.5, reason: 'projection is immutable');
      expect(
        (source['responsive'] as Map)['mobile'],
        <String, dynamic>{'focalPointX': 0.25, 'focalPointY': 0.75},
      );
    });

    test('legacy mobile alignment preset is adapted by the projection owner',
        () {
      final source = <String, dynamic>{
        'backgroundImage': 'https://cdn.test/shared.webp',
        'focalPointX': 0.2,
        'focalPointY': 0.8,
        'mobileBgAlignment': 'topCenter',
      };

      final mobile = WebsiteResponsiveBlockProjection.project(
        type: WebsiteBlockType.hero,
        data: source,
        viewport: WebsiteViewport.mobile,
      );
      final desktop = WebsiteResponsiveBlockProjection.project(
        type: WebsiteBlockType.hero,
        data: source,
        viewport: WebsiteViewport.desktop,
      );

      expect(mobile['focalPointX'], 0.5);
      expect(mobile['focalPointY'], 0.0);
      expect(desktop['focalPointX'], 0.2);
      expect(desktop['focalPointY'], 0.8);
      expect(source['mobileBgAlignment'], 'topCenter');
    });

    test('nested carousel overrides remain isolated per slide', () {
      final source = <String, dynamic>{
        'slides': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'slide-a',
            'imageUrl': 'https://cdn.test/a-shared.webp',
            'focalPointX': 0.5,
            'altText': 'Alt común A',
            'responsive': <String, dynamic>{
              'version': 2,
              'mobile': <String, dynamic>{
                'imageUrl': 'https://cdn.test/a-mobile.webp',
                'focalPointX': 0.25,
                'altText': 'Alt móvil no autorizado',
              },
            },
          },
          <String, dynamic>{
            'id': 'slide-b',
            'imageUrl': 'https://cdn.test/b-shared.webp',
            'focalPointX': 0.75,
            'altText': 'Alt común B',
          },
        ],
      };

      final projected = WebsiteResponsiveBlockProjection.project(
        type: WebsiteBlockType.carousel,
        data: source,
        viewport: WebsiteViewport.mobile,
      );
      final slides = (projected['slides'] as List).cast<Map>();

      expect(slides[0]['imageUrl'], 'https://cdn.test/a-mobile.webp');
      expect(slides[0]['focalPointX'], 0.25);
      expect(slides[0]['altText'], 'Alt común A');
      expect(slides[1]['imageUrl'], 'https://cdn.test/b-shared.webp');
      expect(slides[1]['focalPointX'], 0.75);
      expect(slides[1]['altText'], 'Alt común B');
    });

    test('cross-family height and spacing use the same projection owner', () {
      final source = <String, dynamic>{
        'blockHeight': 640,
        'spacingAfter': 72,
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{
            'blockHeight': 360,
            'spacingAfter': 24,
          },
        },
      };

      final mobile = WebsiteResponsiveBlockProjection.project(
        type: WebsiteBlockType.hero,
        data: source,
        viewport: WebsiteViewport.mobile,
      );
      final desktop = WebsiteResponsiveBlockProjection.project(
        type: WebsiteBlockType.hero,
        data: source,
        viewport: WebsiteViewport.desktop,
      );

      expect(mobile['blockHeight'], 360);
      expect(mobile['spacingAfter'], 24);
      expect(desktop['blockHeight'], 640);
      expect(desktop['spacingAfter'], 72);
    });

    test('a nested v2 item opts the document into canonical 600/900 bands', () {
      final data = <String, dynamic>{
        'slides': <Map<String, dynamic>>[
          <String, dynamic>{
            'imageUrl': 'shared.webp',
            'responsive': <String, dynamic>{
              'version': 2,
              'mobile': <String, dynamic>{'imageUrl': 'mobile.webp'},
            },
          },
        ],
      };

      expect(WebsiteResponsiveDataCodec.usesCanonicalSchema(data), isTrue);
      expect(
        WebsiteResponsiveDataCodec.viewportForDocumentWidth(data, 620),
        WebsiteViewport.tablet,
      );
    });
  });
}
