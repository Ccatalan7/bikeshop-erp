import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';

/// The campaign/cover batch: Hero, Carousel, CTA, Video Banner, Partners.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` `handoff-t10/spec.json`
/// `property_policy_matrix` — `media.assetUrl`/`media.focalPoint`/`fit` and
/// `cta.presentation` are `responsiveOptional`; `media.altText`,
/// `cta.label`, `cta.destination` and `text.value` are `sharedOnly`.
void main() {
  const batch = <WebsiteBlockType>[
    WebsiteBlockType.hero,
    WebsiteBlockType.carousel,
    WebsiteBlockType.cta,
    WebsiteBlockType.videoBanner,
    WebsiteBlockType.partnersBanner,
  ];

  Map<String, WebsiteBlockFieldSchema> flatFieldsOf(WebsiteBlockType type) {
    final result = <String, WebsiteBlockFieldSchema>{};
    void walk(Iterable<WebsiteBlockFieldSchema> fields, String prefix) {
      for (final field in fields) {
        result['$prefix${field.key}'] = field;
        walk(field.itemFields, '$prefix${field.key}.');
      }
    }

    walk(WebsiteBlockRegistry.definitionFor(type).fields, '');
    return result;
  }

  WebsiteBlockFieldSchema fieldOf(WebsiteBlockType type, String path) {
    final field = flatFieldsOf(type)[path];
    expect(field, isNotNull, reason: '$type no declara $path');
    return field!;
  }

  group('1 · matriz exacta de políticas del lote', () {
    const responsive = <(WebsiteBlockType, String)>[
      // Hero — línea base ya migrada; se afirma para que no retroceda.
      (WebsiteBlockType.hero, 'imageUrl'),
      (WebsiteBlockType.hero, 'isFullScreen'),
      (WebsiteBlockType.hero, 'alignment'),
      (WebsiteBlockType.hero, 'showOverlay'),
      (WebsiteBlockType.hero, 'overlayOpacity'),
      // Carousel — por slide.
      (WebsiteBlockType.carousel, 'slides.imageUrl'),
      (WebsiteBlockType.carousel, 'slides.showOverlay'),
      (WebsiteBlockType.carousel, 'slides.overlayOpacity'),
      // CTA.
      (WebsiteBlockType.cta, 'backgroundImage'),
      (WebsiteBlockType.cta, 'overlayColor'),
      (WebsiteBlockType.cta, 'overlayOpacity'),
      // Video Banner — presentación, nunca las fuentes de video.
      (WebsiteBlockType.videoBanner, 'imageUrl'),
      (WebsiteBlockType.videoBanner, 'overlayOpacity'),
      (WebsiteBlockType.videoBanner, 'showCta'),
      // Partners.
      (WebsiteBlockType.partnersBanner, 'imageUrl'),
    ];

    test('cada propiedad de presentación admite override de viewport', () {
      for (final (type, path) in responsive) {
        final field = fieldOf(type, path);
        expect(
          field.responsivePolicy,
          WebsiteResponsivePropertyPolicy.responsiveOptional,
          reason: '$type.$path',
        );
        expect(field.allowsViewportOverride, isTrue, reason: '$type.$path');
        expect(
          field.canResetResponsiveOverride,
          isTrue,
          reason: '$type.$path debe poder volver al común',
        );
      }
    });

    const sharedOnly = <(WebsiteBlockType, String)>[
      // Copy, títulos y subtítulos.
      (WebsiteBlockType.hero, 'title'),
      (WebsiteBlockType.hero, 'subtitle'),
      (WebsiteBlockType.carousel, 'slides.title'),
      (WebsiteBlockType.carousel, 'slides.subtitle'),
      (WebsiteBlockType.cta, 'title'),
      (WebsiteBlockType.cta, 'subtitle'),
      (WebsiteBlockType.videoBanner, 'title'),
      (WebsiteBlockType.videoBanner, 'subtitle'),
      (WebsiteBlockType.partnersBanner, 'title'),
      // Etiquetas y destinos de acción.
      (WebsiteBlockType.hero, 'ctaText'),
      (WebsiteBlockType.hero, 'ctaLink'),
      (WebsiteBlockType.carousel, 'slides.ctaText'),
      (WebsiteBlockType.carousel, 'slides.ctaLink'),
      (WebsiteBlockType.cta, 'buttonText'),
      (WebsiteBlockType.cta, 'buttonLink'),
      (WebsiteBlockType.videoBanner, 'ctaText'),
      (WebsiteBlockType.videoBanner, 'ctaLink'),
      // Las DOS fuentes de video.
      (WebsiteBlockType.videoBanner, 'videoUrl'),
      (WebsiteBlockType.videoBanner, 'videoFileUrl'),
      // Colecciones.
      (WebsiteBlockType.carousel, 'slides'),
      (WebsiteBlockType.partnersBanner, 'items'),
      (WebsiteBlockType.partnersBanner, 'items.label'),
    ];

    test(
        'ningún copy, destino, colección ni fuente de video se volvió '
        'responsive', () {
      for (final (type, path) in sharedOnly) {
        final field = fieldOf(type, path);
        expect(
          field.responsivePolicy,
          WebsiteResponsivePropertyPolicy.sharedOnly,
          reason: '$type.$path se volvió responsive y no debía',
        );
        expect(field.allowsViewportOverride, isFalse, reason: '$type.$path');
      }
    });

    test('el alt text de cada imagen del lote sigue compartido', () {
      const mediaFields = <(WebsiteBlockType, String)>[
        (WebsiteBlockType.hero, 'imageUrl'),
        (WebsiteBlockType.carousel, 'slides.imageUrl'),
        (WebsiteBlockType.cta, 'backgroundImage'),
        (WebsiteBlockType.videoBanner, 'imageUrl'),
        (WebsiteBlockType.partnersBanner, 'imageUrl'),
      ];
      for (final (type, path) in mediaFields) {
        final field = fieldOf(type, path);
        expect(field.hasAltTextControl, isTrue, reason: '$type.$path');
        final altKey = field.altTextKey;
        final alt = flatFieldsOf(type)[
            path.contains('.') ? '${path.split('.').first}.$altKey' : altKey];
        // El alt puede no ser un campo del schema (se edita junto a la media),
        // pero si lo es NUNCA puede ser responsive.
        if (alt != null) {
          expect(
            alt.responsivePolicy,
            WebsiteResponsivePropertyPolicy.sharedOnly,
            reason: '$type.$altKey',
          );
        }
      }
    });

    test('toda media responsive del lote declara familia y superficies', () {
      const mediaFields = <(WebsiteBlockType, String)>[
        (WebsiteBlockType.hero, 'imageUrl'),
        (WebsiteBlockType.carousel, 'slides.imageUrl'),
        (WebsiteBlockType.cta, 'backgroundImage'),
        (WebsiteBlockType.videoBanner, 'imageUrl'),
        (WebsiteBlockType.partnersBanner, 'imageUrl'),
      ];
      for (final (type, path) in mediaFields) {
        final field = fieldOf(type, path);
        expect(
          field.resolvedPropertyFamily,
          WebsiteResponsivePropertyFamily.media,
          reason: '$type.$path',
        );
        expect(field.hasFocalPointControl, isTrue, reason: '$type.$path');
        expect(
          field.authoringSurfaces,
          contains(WebsiteAuthoringSurface.contextSheet),
          reason: '$type.$path debe existir también en el host compacto',
        );
      }
    });

    test('el lote no habilitó display copy: la whitelist sigue vacía', () {
      for (final type in batch) {
        for (final entry in flatFieldsOf(type).entries) {
          expect(
            entry.value.responsivePolicy,
            isNot(WebsiteResponsivePropertyPolicy.responsiveDisplayCopy),
            reason: '$type.${entry.key}',
          );
        }
      }
    });

    test('el inventario responsive del producto está cerrado', () {
      // Este guard nació como «ninguna familia fuera de los lotes migrados
      // cambió». Con las 24 familias normales ya migradas, esa lista quedó
      // vacía y su trabajo es otro: congelar QUÉ familias pueden declarar un
      // override y cuáles cierran compartidas, para que nadie mueva una de
      // lado sin actualizar su matriz. Cada lote conserva la suya:
      // `website_simple_responsive_policies_test.dart` (text, button,
      // divider), `website_catalog_responsive_policies_test.dart` (products,
      // categoryGrid, brandLogos),
      // `website_collections_responsive_policies_test.dart` (gallery,
      // testimonials, googleReviews, team, faq),
      // `website_content_responsive_policies_test.dart` (services, about,
      // features, stats) y
      // `website_conversion_responsive_policies_test.dart` (pricing, contact,
      // footer). Canvas queda para su fase estructural.
      const withCapability = <WebsiteBlockType>{
        WebsiteBlockType.hero,
        WebsiteBlockType.carousel,
        WebsiteBlockType.text,
        WebsiteBlockType.button,
        WebsiteBlockType.divider,
        WebsiteBlockType.products,
        WebsiteBlockType.about,
        WebsiteBlockType.features,
        WebsiteBlockType.cta,
        WebsiteBlockType.gallery,
        WebsiteBlockType.categoryGrid,
        WebsiteBlockType.videoBanner,
        WebsiteBlockType.partnersBanner,
        WebsiteBlockType.brandLogos,
      };
      const sharedOrAutoLayout = <WebsiteBlockType>{
        WebsiteBlockType.canvas,
        WebsiteBlockType.services,
        WebsiteBlockType.testimonials,
        WebsiteBlockType.contact,
        WebsiteBlockType.faq,
        WebsiteBlockType.pricing,
        WebsiteBlockType.team,
        WebsiteBlockType.stats,
        WebsiteBlockType.footer,
        WebsiteBlockType.googleReviews,
      };

      expect(
        withCapability.union(sharedOrAutoLayout),
        WebsiteBlockType.values.toSet(),
        reason: 'una familia nueva entra al inventario con su matriz',
      );
      expect(withCapability.intersection(sharedOrAutoLayout), isEmpty);

      for (final type in sharedOrAutoLayout) {
        for (final entry in flatFieldsOf(type).entries) {
          expect(
            entry.value.allowsViewportOverride,
            isFalse,
            reason: '$type.${entry.key} ganó una capacidad sin su matriz',
          );
        }
      }
      for (final type in withCapability) {
        expect(
          flatFieldsOf(type)
              .values
              .any((field) => field.allowsViewportOverride),
          isTrue,
          reason: '$type perdió su capacidad responsive',
        );
      }
    });
  });

  group('7 · guards estáticos del lote', () {
    final carouselSource = File(
      'lib/modules/website/widgets/editor_panel/carousel_controls.dart',
    ).readAsStringSync();

    test('el overlay del slide ya no escribe por la ruta compartida', () {
      expect(carouselSource, contains('_slideScalarBinding<bool>('));
      expect(carouselSource, contains('_slideScalarBinding<num>('));
      expect(
        carouselSource,
        contains('WebsiteResponsiveScalarBinding<T>.forField('),
      );
      expect(carouselSource, contains('ResponsiveFieldShell<T>('));
      for (final legacyWrite in const [
        "_updateSlide(_selectedSlideIndex, 'showOverlay'",
        "_updateSlide(_selectedSlideIndex, 'overlayOpacity'",
      ]) {
        expect(
          carouselSource,
          isNot(contains(legacyWrite)),
          reason: '$legacyWrite volvería a escribir el valor compartido',
        );
      }
    });

    test('el slide usa la factory de repeater, nunca la de raíz', () {
      expect(
        carouselSource,
        contains('WebsiteResponsiveMediaBinding.repeaterItem('),
      );
      expect(
        carouselSource,
        isNot(contains('WebsiteResponsiveMediaBinding.root(')),
      );
      expect(
          carouselSource, contains('WebsiteResponsiveRepeaterField.forItem('));
    });

    test('ningún control del lote revive las claves móviles como autoridad',
        () {
      for (final path in const [
        'lib/modules/website/widgets/editor_panel/carousel_controls.dart',
        'lib/modules/website/widgets/editor_panel/schema_controls.dart',
      ]) {
        final source = File(path).readAsStringSync();
        for (final legacyKey in const [
          "'mobileImageUrl'",
          "'mobileFocalPointX'",
          "'mobileFocalPointY'",
        ]) {
          expect(
            source,
            isNot(contains(legacyKey)),
            reason: '$path nombra $legacyKey; la autoridad es el schema',
          );
        }
      }
    });

    test('la media legacy sigue siendo sólo lectura declarada en el schema',
        () {
      // El alias móvil vive en el registro como `legacyResponsiveAliases` —
      // lectura y reset — y en ningún control.
      final hero = fieldOf(WebsiteBlockType.hero, 'imageUrl');
      final slide = fieldOf(WebsiteBlockType.carousel, 'slides.imageUrl');
      expect(hero.legacyResponsiveAliases, contains('mobileImageUrl'));
      expect(slide.legacyResponsiveAliases, contains('mobileImageUrl'));
      // Y las familias nuevas del lote no inventan aliases que nadie escribe.
      for (final (type, path) in const <(WebsiteBlockType, String)>[
        (WebsiteBlockType.cta, 'backgroundImage'),
        (WebsiteBlockType.videoBanner, 'imageUrl'),
        (WebsiteBlockType.partnersBanner, 'imageUrl'),
      ]) {
        expect(
          fieldOf(type, path).legacyResponsiveAliases,
          isEmpty,
          reason: '$type.$path no tiene dato legacy que leer',
        );
      }
    });
  });
}
