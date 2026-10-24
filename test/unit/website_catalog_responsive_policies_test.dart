import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';

/// The catalogue batch: Products, Category Grid and Brand Logos.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` `handoff-t10/spec.json`
/// `property_policy_matrix` — `collection.columns` and `cta.presentation` are
/// `responsiveOptional`; `media.productBinding`, `cta.destination`,
/// `media.altText` and `text.value` are `sharedOnly`. No visual value is
/// introduced by this round.
void main() {
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

  group('A · matriz exacta de las tres familias', () {
    test('Products migra sólo presentación con consumer real', () {
      final fields = flatFieldsOf(WebsiteBlockType.products);
      expect(
        fields.keys.toSet(),
        <String>{
          'layout',
          'itemsPerRow',
          'showPrice',
          'showSku',
          'showBrand',
          'showViewAll',
        },
        reason: 'el schema de Products declara sólo lo que se expone',
      );

      // Cada propiedad responsive declarada tiene consumer en el renderer.
      final showViewAll = fieldOf(WebsiteBlockType.products, 'showViewAll');
      expect(
        showViewAll.responsivePolicy,
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        showViewAll.resolvedPropertyFamily,
        WebsiteResponsivePropertyFamily.action,
      );
      expect(showViewAll.canResetResponsiveOverride, isTrue);

      final layout = fieldOf(WebsiteBlockType.products, 'layout');
      expect(
        layout.responsivePolicy,
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        layout.resolvedPropertyFamily,
        WebsiteResponsivePropertyFamily.geometry,
      );

      for (final key in const <String>[
        'showPrice',
        'showSku',
        'showBrand',
      ]) {
        final field = fieldOf(WebsiteBlockType.products, key);
        expect(
          field.responsivePolicy,
          WebsiteResponsivePropertyPolicy.responsiveOptional,
          reason: key,
        );
        expect(
          field.resolvedPropertyFamily,
          WebsiteResponsivePropertyFamily.visibility,
          reason: key,
        );
        expect(field.canResetResponsiveOverride, isTrue, reason: key);
      }

      // `itemsPerRow` se expone como base compartida, no como capacidad: la
      // tienda calcula las columnas por su cuenta. El contrato completo vive
      // en `website_products_items_per_row_contract_test.dart`.
      final itemsPerRow = fieldOf(WebsiteBlockType.products, 'itemsPerRow');
      expect(
        itemsPerRow.responsivePolicy,
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );
      expect(itemsPerRow.allowsViewportOverride, isFalse);
    });

    test('la identidad de catálogo de Products NO entró al schema', () {
      // Fuente, categoría, selección, tope y copy/destino del "ver todos" son
      // datos de negocio: siguen siendo compartidos y los editan los pickers
      // existentes, no el protocolo responsive.
      final fields = flatFieldsOf(WebsiteBlockType.products);
      for (final businessKey in const <String>[
        'title',
        'subtitle',
        'productSource',
        'categoryId',
        'selectedProducts',
        'productIds',
        'maxProducts',
        'viewAllText',
        'viewAllLink',
      ]) {
        expect(
          fields.containsKey(businessKey),
          isFalse,
          reason: '$businessKey no puede volverse responsive',
        );
      }
    });

    test('Category Grid: imagen por item responsive, todo lo demás compartido',
        () {
      final image =
          fieldOf(WebsiteBlockType.categoryGrid, 'categories.imageUrl');
      expect(
        image.responsivePolicy,
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        image.resolvedPropertyFamily,
        WebsiteResponsivePropertyFamily.media,
      );
      expect(image.hasFocalPointControl, isTrue);
      expect(
        image.authoringSurfaces,
        contains(WebsiteAuthoringSurface.contextSheet),
      );

      for (final path in const <String>[
        'title',
        'subtitle',
        'categories',
        'categories.title',
        'categories.subtitle',
        'categories.link',
      ]) {
        expect(
          fieldOf(WebsiteBlockType.categoryGrid, path).responsivePolicy,
          WebsiteResponsivePropertyPolicy.sharedOnly,
          reason: path,
        );
      }
    });

    test(
        'el subtítulo de Category Grid vuelve al schema como contrato ya '
        'existente', () {
      final subtitle = fieldOf(WebsiteBlockType.categoryGrid, 'subtitle');
      expect(subtitle.type, WebsiteBlockFieldType.textarea);
      expect(subtitle.textRole, WebsiteTextRole.paragraph);
      // Y la sección de contenido lo expone, para que el editor pueda llegar.
      final section = WebsiteBlockRegistry.definitionFor(
        WebsiteBlockType.categoryGrid,
      ).controlSections.single;
      expect(section.fieldKeys, contains('subtitle'));
      // El renderer ya lo leía: este test falla si alguien lo quita de ahí.
      final rendererSource =
          File('lib/modules/website/widgets/website_block_renderer.dart')
              .readAsStringSync();
      expect(rendererSource, contains("widget.data['subtitle']"));
    });

    test('Brand Logos: sólo logoSize; la marca entera es compartida', () {
      final logoSize = fieldOf(WebsiteBlockType.brandLogos, 'logoSize');
      expect(
        logoSize.responsivePolicy,
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        logoSize.resolvedPropertyFamily,
        WebsiteResponsivePropertyFamily.geometry,
      );

      for (final path in const <String>[
        'title',
        'brands',
        'brands.name',
        'brands.imageUrl',
        'brands.link',
      ]) {
        expect(
          fieldOf(WebsiteBlockType.brandLogos, path).responsivePolicy,
          WebsiteResponsivePropertyPolicy.sharedOnly,
          reason: '$path: un logo identifica la marca, no es art direction',
        );
      }
    });

    test('ninguna colección del lote se volvió responsive entera', () {
      for (final (type, key) in const <(WebsiteBlockType, String)>[
        (WebsiteBlockType.categoryGrid, 'categories'),
        (WebsiteBlockType.brandLogos, 'brands'),
      ]) {
        final field = fieldOf(type, key);
        expect(field.type, WebsiteBlockFieldType.repeater);
        expect(field.allowsViewportOverride, isFalse, reason: '$type.$key');
      }
    });

    test('el lote no habilitó display copy', () {
      for (final type in const [
        WebsiteBlockType.products,
        WebsiteBlockType.categoryGrid,
        WebsiteBlockType.brandLogos,
      ]) {
        for (final entry in flatFieldsOf(type).entries) {
          expect(
            entry.value.responsivePolicy,
            isNot(WebsiteResponsivePropertyPolicy.responsiveDisplayCopy),
            reason: '$type.${entry.key}',
          );
        }
      }
    });
  });

  group('deuda declarada, no capacidad fingida', () {
    test('los toggles visibles de Products llegan hasta la tarjeta', () {
      final rendererSource =
          File('lib/modules/website/widgets/website_block_renderer.dart')
              .readAsStringSync();
      final cardSource =
          File('lib/modules/website/widgets/premium_product_card.dart')
              .readAsStringSync();
      final fields = flatFieldsOf(WebsiteBlockType.products);

      for (final key in const <String>['showPrice', 'showSku', 'showBrand']) {
        expect(
          fields.containsKey(key),
          isTrue,
          reason: '$key debe tener owner responsive',
        );
        expect(
          rendererSource.contains('$key: contract.$key'),
          isTrue,
          reason: '$key debe viajar al consumer de la tarjeta',
        );
        expect(cardSource, contains('widget.$key'));
      }

      expect(fields.containsKey('showStock'), isFalse);
      expect(
        WebsiteBlockRegistry.definitionFor(WebsiteBlockType.products)
            .defaultData
            .containsKey('showStock'),
        isFalse,
        reason: 'el control fantasma sin UI ni consumer no se persiste',
      );
      expect(rendererSource, contains('final subtitle = contract.subtitle'));
    });

    test('layout de Products tiene consumer real también en móvil', () {
      final fields = flatFieldsOf(WebsiteBlockType.products);
      expect(fields.containsKey('layout'), isTrue);
      expect(
        fieldOf(WebsiteBlockType.products, 'layout').responsivePolicy,
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      final rendererSource =
          File('lib/modules/website/widgets/website_block_renderer.dart')
              .readAsStringSync();
      expect(rendererSource, contains("layout == 'carousel'"));
      expect(rendererSource, contains('screenWidth < 600'));
      expect(rendererSource, isNot(contains('screenWidth < 700')));
    });

    test('accentColor de Brand Logos no existe como capacidad', () {
      final fields = flatFieldsOf(WebsiteBlockType.brandLogos);
      expect(
        fields.containsKey('accentColor'),
        isFalse,
        reason: 'no tiene consumer en el renderer; no se inventa',
      );
    });
  });

  group('C · projection por viewport, sin cascada', () {
    test('Products proyecta layout/visibilidad; itemsPerRow no', () {
      final document = <String, dynamic>{
        'layout': 'grid',
        'itemsPerRow': 4,
        'showPrice': true,
        'showSku': false,
        'showBrand': false,
        'showViewAll': true,
        'maxProducts': 8,
        'viewAllLink': '/productos',
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{
            'layout': 'carousel',
            'itemsPerRow': 1,
            'showPrice': false,
            'showSku': true,
            'showBrand': true,
            'showViewAll': false,
          },
          'tablet': <String, dynamic>{'itemsPerRow': 2, 'showBrand': true},
        },
      };

      Map<String, dynamic> projected(WebsiteViewport viewport) =>
          WebsiteResponsiveBlockProjection.project(
            type: WebsiteBlockType.products,
            data: document,
            viewport: viewport,
          );

      expect(projected(WebsiteViewport.desktop)['showViewAll'], isTrue);
      expect(projected(WebsiteViewport.desktop)['layout'], 'grid');
      expect(projected(WebsiteViewport.desktop)['showPrice'], isTrue);
      expect(projected(WebsiteViewport.desktop)['showSku'], isFalse);
      expect(projected(WebsiteViewport.desktop)['showBrand'], isFalse);
      expect(
        projected(WebsiteViewport.tablet)['showViewAll'],
        isTrue,
        reason: 'tablet no hereda de móvil',
      );
      expect(projected(WebsiteViewport.tablet)['layout'], 'grid');
      expect(projected(WebsiteViewport.tablet)['showPrice'], isTrue);
      expect(projected(WebsiteViewport.tablet)['showSku'], isFalse);
      expect(projected(WebsiteViewport.tablet)['showBrand'], isTrue);
      expect(projected(WebsiteViewport.mobile)['showViewAll'], isFalse);
      expect(projected(WebsiteViewport.mobile)['layout'], 'carousel');
      expect(projected(WebsiteViewport.mobile)['showPrice'], isFalse);
      expect(projected(WebsiteViewport.mobile)['showSku'], isTrue);
      expect(projected(WebsiteViewport.mobile)['showBrand'], isTrue);

      // `itemsPerRow` es compartido: ni un override guardado por error puede
      // cambiar lo que la tienda muestra.
      for (final viewport in WebsiteViewport.values) {
        expect(projected(viewport)['itemsPerRow'], 4, reason: '$viewport');
        expect(projected(viewport)['maxProducts'], 8);
        expect(projected(viewport)['viewAllLink'], '/productos');
      }
    });

    test('la imagen de una categoría proyecta su propio override por item', () {
      final document = <String, dynamic>{
        'title': 'Explora',
        'categories': <Map<String, dynamic>>[
          {
            'title': 'MTB',
            'link': '/productos',
            'altText': 'Bicicletas de montaña',
            'imageUrl': 'https://cdn/mtb.webp',
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{
                'imageUrl': 'https://cdn/mtb-mobile.webp',
              },
            },
          },
          {
            'title': 'Ruta',
            'link': '/productos',
            'imageUrl': 'https://cdn/ruta.webp',
          },
        ],
      };

      List<Map<String, dynamic>> categories(WebsiteViewport viewport) {
        final projected = WebsiteResponsiveBlockProjection.project(
          type: WebsiteBlockType.categoryGrid,
          data: document,
          viewport: viewport,
        );
        return (projected['categories'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
      }

      expect(
        categories(WebsiteViewport.mobile)[0]['imageUrl'],
        'https://cdn/mtb-mobile.webp',
      );
      expect(
        categories(WebsiteViewport.tablet)[0]['imageUrl'],
        'https://cdn/mtb.webp',
        reason: 'tablet hereda de la base, no de móvil',
      );
      expect(
        categories(WebsiteViewport.mobile)[1]['imageUrl'],
        'https://cdn/ruta.webp',
        reason: 'el hermano no se contamina',
      );
      // El alt y el destino son los mismos en los tres.
      for (final viewport in WebsiteViewport.values) {
        expect(
          categories(viewport)[0]['altText'],
          'Bicicletas de montaña',
        );
        expect(categories(viewport)[0]['link'], '/productos');
      }
    });

    test('logoSize resuelve por viewport y las marcas no cambian', () {
      final document = <String, dynamic>{
        'logoSize': 'large',
        'brands': <Map<String, dynamic>>[
          {'name': 'Shimano', 'imageUrl': 'https://cdn/shimano.svg'},
        ],
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{'logoSize': 'small'},
        },
      };

      Map<String, dynamic> projected(WebsiteViewport viewport) =>
          WebsiteResponsiveBlockProjection.project(
            type: WebsiteBlockType.brandLogos,
            data: document,
            viewport: viewport,
          );

      expect(projected(WebsiteViewport.desktop)['logoSize'], 'large');
      expect(projected(WebsiteViewport.tablet)['logoSize'], 'large');
      expect(projected(WebsiteViewport.mobile)['logoSize'], 'small');
      for (final viewport in WebsiteViewport.values) {
        final brands = (projected(viewport)['brands'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        expect(brands.single['name'], 'Shimano');
        expect(brands.single['imageUrl'], 'https://cdn/shimano.svg');
      }
    });
  });

  group('H · las clases bespoke muertas no vuelven', () {
    test('el archivo entero y su part directive desaparecieron', () {
      expect(
        File(
          'lib/modules/website/widgets/editor_panel/collection_block_controls.dart',
        ).existsSync(),
        isFalse,
      );
      final panelSource =
          File('lib/modules/website/widgets/website_editor_panel.dart')
              .readAsStringSync();
      expect(
        panelSource,
        isNot(contains('collection_block_controls.dart')),
        reason: 'la part directive tiene que irse con el archivo',
      );
    });

    test('ninguna de las cuatro clases existe en lib/', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final dead in const <String>[
          '_CategoryGridBlockControls',
          '_VideoBannerBlockControls',
          '_PartnersBannerBlockControls',
          '_BrandLogosBlockControls',
        ]) {
          if (source.contains(dead)) offenders.add('${entity.path}: $dead');
        }
      }
      expect(offenders, isEmpty);
    });

    test('el editor genérico sigue atendiendo a esas familias', () {
      // Se borró código muerto, no capacidad: las cuatro familias entran por
      // `_GenericBlockControls`, que es donde ya estaban siendo atendidas.
      final tabSource = File(
        'lib/modules/website/widgets/editor_panel/edit_block_tab.dart',
      ).readAsStringSync();
      for (final family in const <String>[
        'categoryGrid',
        'partnersBanner',
        'brandLogos',
        'videoBanner',
      ]) {
        expect(tabSource, contains("case '$family':"), reason: family);
      }
      expect(tabSource, contains('_GenericBlockControls('));
    });
  });
}
