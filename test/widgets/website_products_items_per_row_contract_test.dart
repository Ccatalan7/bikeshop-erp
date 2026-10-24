import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';

/// `Productos por fila` is a SHARED base value, and this file says why.
///
/// The property was briefly declared responsive. It was a false capability:
/// a phone grid forces one safe column and tablet grids force two; carousel
/// cards size themselves independently. An override would have been a control
/// the page cannot honour, and the inspector would have shown a number the
/// renderer ignores. Layout itself is separate and is honoured at every width.
///
/// The correction: the renderer keeps its auto-layout untouched, the registry
/// declares the property shared, and the inspector states the reason per
/// viewport instead of offering the change. What follows pins that decision so
/// the false capability cannot come back.
void main() {
  final rendererSource =
      File('lib/modules/website/widgets/website_block_renderer.dart')
          .readAsStringSync();

  group('el registro declara el valor como base compartida', () {
    test('itemsPerRow no admite override de viewport', () {
      final field = WebsiteBlockRegistry.fieldForPath(
        WebsiteBlockType.products,
        'itemsPerRow',
      );
      expect(field, isNotNull);
      expect(
        field!.responsivePolicy,
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );
      expect(field.allowsViewportOverride, isFalse);
      expect(field.canResetResponsiveOverride, isFalse);
    });

    test('showViewAll SÍ conserva su capacidad responsive', () {
      final field = WebsiteBlockRegistry.fieldForPath(
        WebsiteBlockType.products,
        'showViewAll',
      );
      expect(field, isNotNull);
      expect(
        field!.responsivePolicy,
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(field.allowsViewportOverride, isTrue);
      expect(field.canResetResponsiveOverride, isTrue);
    });
  });

  group('el renderer conserva densidad automática, sin rama de override', () {
    test('la lectura del override desapareció del consumer', () {
      expect(
        rendererSource,
        isNot(contains('hasExplicitItemsPerRow')),
        reason: 'el renderer no puede fingir que consume un override',
      );
      expect(
        rendererSource,
        isNot(contains("WebsiteResponsiveDataCodec.hasOverride(")),
      );
    });

    test('la densidad automática sigue textualmente en su sitio', () {
      expect(rendererSource, contains('WebsiteViewport.mobile => 1'));
      expect(rendererSource, contains('WebsiteViewport.tablet => 2'));
      expect(rendererSource, contains('itemsPerRow.clamp(2, 4)'));
      expect(rendererSource, isNot(contains('screenWidth < 450')));
      expect(rendererSource, isNot(contains('screenWidth < 700')));
      expect(rendererSource, contains("layout == 'carousel'"));
      // El carrusel adapta su implementación, no el valor guardado de layout.
      expect(
        rendererSource,
        contains('viewport == WebsiteViewport.mobile'),
      );
      expect(rendererSource, contains('_MobileProductAutoCarousel'));
    });

    test('el carrusel móvil no recibe ni lee itemsPerRow', () {
      final carouselStart =
          rendererSource.indexOf('class _MobileProductAutoCarousel');
      expect(carouselStart, greaterThan(-1));
      final carouselSource = rendererSource.substring(
        carouselStart,
        carouselStart + 4000 > rendererSource.length
            ? rendererSource.length
            : carouselStart + 4000,
      );
      expect(
        carouselSource.contains('itemsPerRow'),
        isFalse,
        reason: 'si algún día lo consume, la propiedad puede volver a migrarse',
      );
    });
  });

  group('la projection ya no puede producir un valor por viewport', () {
    test('un override guardado en un documento antiguo NO se resuelve', () {
      // Un documento que alcanzó a guardar el override durante la ronda
      // anterior no debe cambiar lo que la tienda muestra: el campo es
      // compartido, así que la projection devuelve la base en los tres.
      final document = <String, dynamic>{
        'itemsPerRow': 4,
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{'itemsPerRow': 2},
          'tablet': <String, dynamic>{'itemsPerRow': 3},
        },
      };

      for (final viewport in WebsiteViewport.values) {
        final projected = WebsiteResponsiveBlockProjection.project(
          type: WebsiteBlockType.products,
          data: document,
          viewport: viewport,
        );
        expect(
          projected['itemsPerRow'],
          4,
          reason: '$viewport debe ver la base',
        );
      }
    });

    test('showViewAll sí resuelve por viewport, sin cascada', () {
      final document = <String, dynamic>{
        'showViewAll': true,
        'viewAllLink': '/productos',
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{'showViewAll': false},
        },
      };

      Map<String, dynamic> projected(WebsiteViewport viewport) =>
          WebsiteResponsiveBlockProjection.project(
            type: WebsiteBlockType.products,
            data: document,
            viewport: viewport,
          );

      expect(projected(WebsiteViewport.desktop)['showViewAll'], isTrue);
      expect(
        projected(WebsiteViewport.tablet)['showViewAll'],
        isTrue,
        reason: 'tablet no hereda de móvil',
      );
      expect(projected(WebsiteViewport.mobile)['showViewAll'], isFalse);
      // Y el destino compartido no se mueve.
      for (final viewport in WebsiteViewport.values) {
        expect(projected(viewport)['viewAllLink'], '/productos');
      }
    });
  });
}
