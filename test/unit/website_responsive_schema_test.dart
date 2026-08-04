import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';

void main() {
  group('Website responsive field schema', () {
    test('every declared field has an explicit safe authoring contract', () {
      for (final type in WebsiteBlockType.values) {
        final fields = _flatten(
          WebsiteBlockRegistry.definitionFor(type).fields,
        );
        for (final field in fields) {
          expect(field.authoringSurfaces, isNotEmpty,
              reason: '$type.${field.key}');
          if (field.responsivePolicy ==
              WebsiteResponsivePropertyPolicy.sharedOnly) {
            expect(
              field.canResetResponsiveOverride,
              isFalse,
              reason: '$type.${field.key}',
            );
          }
        }
      }
    });

    test('first vertical slice exposes reusable responsive capabilities', () {
      final hero = WebsiteBlockRegistry.definitionFor(WebsiteBlockType.hero);
      final text = WebsiteBlockRegistry.definitionFor(WebsiteBlockType.text);
      final button =
          WebsiteBlockRegistry.definitionFor(WebsiteBlockType.button);

      final image = _field(hero, 'imageUrl');
      expect(
        image.responsivePolicy,
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
          image.resolvedPropertyFamily, WebsiteResponsivePropertyFamily.media);
      expect(
        image.authoringSurfaces,
        containsAll(const {
          WebsiteAuthoringSurface.inline,
          WebsiteAuthoringSurface.contextSheet,
          WebsiteAuthoringSurface.inspector,
        }),
      );
      expect(image.legacyResponsiveAliases, contains('mobileImageUrl'));

      expect(
        _field(hero, 'alignment').resolvedPropertyFamily,
        WebsiteResponsivePropertyFamily.geometry,
      );
      expect(
        _field(text, 'maxWidth').responsivePolicy,
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        _field(button, 'style').resolvedPropertyFamily,
        WebsiteResponsivePropertyFamily.action,
      );
    });

    test('semantic content and destinations remain shared by default', () {
      final hero = WebsiteBlockRegistry.definitionFor(WebsiteBlockType.hero);
      for (final key in const ['title', 'subtitle', 'ctaText', 'ctaLink']) {
        expect(
          _field(hero, key).responsivePolicy,
          WebsiteResponsivePropertyPolicy.sharedOnly,
          reason: key,
        );
      }

      final displayCopyFields = WebsiteBlockType.values
          .expand(
            (type) => _flatten(
              WebsiteBlockRegistry.definitionFor(type).fields,
            ),
          )
          .where(
            (field) =>
                field.responsivePolicy ==
                WebsiteResponsivePropertyPolicy.responsiveDisplayCopy,
          );
      expect(
        displayCopyFields,
        isEmpty,
        reason: 'The display-copy whitelist starts empty.',
      );
    });

    test('capability matrix is registry-derived and total for every block', () {
      final matrix = WebsiteBlockRegistry.responsivePolicyMatrix();

      expect(matrix.keys.toSet(), WebsiteBlockType.values.toSet());
      expect(
        matrix[WebsiteBlockType.hero]?['imageUrl'],
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        matrix[WebsiteBlockType.hero]?['ctaLink'],
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );
      expect(
        matrix[WebsiteBlockType.hero]?['focalPointX'],
        WebsiteResponsivePropertyPolicy.perViewportGeometry,
      );
      expect(
        matrix[WebsiteBlockType.hero]?['imageAltText'],
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );
      expect(
        matrix[WebsiteBlockType.carousel]?['slides.imageUrl'],
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        matrix[WebsiteBlockType.carousel]?['slides.focalPointX'],
        WebsiteResponsivePropertyPolicy.perViewportGeometry,
      );
      expect(
        matrix[WebsiteBlockType.carousel]?['slides.altText'],
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );
    });

    test('carousel exposes one reusable media contract per slide', () {
      final carousel =
          WebsiteBlockRegistry.definitionFor(WebsiteBlockType.carousel);
      final slides = _field(carousel, 'slides');
      final image = slides.itemFields.singleWhere(
        (field) => field.key == 'imageUrl',
      );

      expect(image.resolvedMediaRole, WebsiteMediaRole.cover);
      expect(image.supportsFocalPoint, isTrue);
      expect(image.altTextKey, 'altText');
      expect(image.legacyResponsiveAliases, contains('mobileImageUrl'));
      expect(image.mobileFocalPointXKey, 'mobileFocalPointX');
      expect(image.mobileFocalPointYKey, 'mobileFocalPointY');
      expect(
        image.authoringSurfaces,
        containsAll(const {
          WebsiteAuthoringSurface.inline,
          WebsiteAuthoringSurface.contextSheet,
          WebsiteAuthoringSurface.inspector,
        }),
      );
      expect(
        slides.itemFields.where((field) => field.key == image.altTextKey),
        isEmpty,
        reason: 'Alt text is owned by the media field, not a duplicate input.',
      );
    });

    test('custom editors resolve the same nested schema by owner path', () {
      expect(
        WebsiteBlockRegistry.fieldForPath(
          WebsiteBlockType.hero,
          'imageUrl',
        )?.label,
        'Imagen de fondo',
      );
      expect(
        WebsiteBlockRegistry.fieldForPath(
          WebsiteBlockType.carousel,
          'slides.imageUrl',
        )?.supportsFocalPoint,
        isTrue,
      );
      expect(
        WebsiteBlockRegistry.fieldForPath(
          WebsiteBlockType.carousel,
          'slides.0.imageUrl',
        ),
        isNull,
        reason: 'Runtime indexes are not schema owners.',
      );
    });
  });
}

Iterable<WebsiteBlockFieldSchema> _flatten(
  Iterable<WebsiteBlockFieldSchema> fields,
) sync* {
  for (final field in fields) {
    yield field;
    yield* _flatten(field.itemFields);
  }
}

WebsiteBlockFieldSchema _field(
  WebsiteBlockDefinition definition,
  String key,
) =>
    definition.fields.singleWhere((field) => field.key == key);
