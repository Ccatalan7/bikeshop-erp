import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';

/// El lote de contenido: Servicios, Sobre Nosotros, Características e
/// Indicadores.
///
/// Matriz derivada del schema y del consumer real. Dos familias ganan una
/// capacidad —la imagen de About, con su encuadre, y el diseño de Features— y
/// dos cierran deliberadamente en auto-layout compartido. Esta ronda no
/// introduce ningún valor visual: reutiliza `ResponsiveFieldShell` y
/// `ResponsiveMediaField` tal como quedaron aprobados, y el único cambio de
/// renderer consume un valor ya proyectado (`focalPointX/Y`) en la alineación
/// que la imagen ya tenía.
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

  const batch = <WebsiteBlockType>[
    WebsiteBlockType.services,
    WebsiteBlockType.about,
    WebsiteBlockType.features,
    WebsiteBlockType.stats,
  ];

  String sourceOf(String path) => File(path).readAsStringSync();

  final aboutSource =
      sourceOf('lib/modules/website/widgets/website_about_block_content.dart');
  final featuresSource = sourceOf(
    'lib/modules/website/widgets/website_features_block_content.dart',
  );
  final servicesSource = sourceOf(
    'lib/modules/website/widgets/website_services_block_content.dart',
  );
  final statsSource =
      sourceOf('lib/modules/website/widgets/website_stats_block_content.dart');

  group('A · matriz exacta de las cuatro familias', () {
    test('About: la imagen y su encuadre; el resto compartido', () {
      final fields = flatFieldsOf(WebsiteBlockType.about);
      expect(
        fields.keys.toSet(),
        <String>{'title', 'content', 'imageUrl', 'imagePosition'},
      );

      final image = fieldOf(WebsiteBlockType.about, 'imageUrl');
      expect(
        image.responsivePolicy,
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        image.resolvedPropertyFamily,
        WebsiteResponsivePropertyFamily.media,
      );
      expect(
        image.supportsFocalPoint,
        isTrue,
        reason: 'el marco cambia de forma por viewport: hay que reencuadrar',
      );
      expect(image.hasFocalPointControl, isTrue);
      expect(image.altTextKey, 'imageAltText');
      expect(image.migrationAliases, contains('image'));
      expect(
        image.authoringSurfaces,
        containsAll(const <WebsiteAuthoringSurface>{
          WebsiteAuthoringSurface.inline,
          WebsiteAuthoringSurface.contextSheet,
          WebsiteAuthoringSurface.inspector,
        }),
      );

      // El marco que justifica la capacidad, leído del consumer real.
      expect(aboutSource, contains('final imageAspectRatio = isDesktop'));
      expect(aboutSource, contains('4 / 3'));
      expect(aboutSource, contains('16 / 9'));
      expect(aboutSource, contains('3 / 2'));
      // Y el consumer sí usa el foco proyectado: sin esto sería falso.
      expect(aboutSource, contains('_resolveFocalAlignment(data)'));
      expect(aboutSource, contains('alignment: alignment'));

      final matrix = WebsiteBlockRegistry.responsivePolicyMatrix()[
          WebsiteBlockType.about]!;
      expect(
        matrix['focalPointX'],
        WebsiteResponsivePropertyPolicy.perViewportGeometry,
      );
      expect(
        matrix['focalPointY'],
        WebsiteResponsivePropertyPolicy.perViewportGeometry,
      );
      expect(
        matrix['imageAltText'],
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );

      for (final path in const <String>['title', 'content', 'imagePosition']) {
        expect(
          fieldOf(WebsiteBlockType.about, path).responsivePolicy,
          WebsiteResponsivePropertyPolicy.sharedOnly,
          reason: path,
        );
      }
    });

    test('Features: sólo el diseño, y el renderer monta dos árboles', () {
      final fields = flatFieldsOf(WebsiteBlockType.features);
      expect(
        fields.keys.toSet(),
        <String>{
          'title',
          'layout',
          'features',
          'features.icon',
          'features.title',
          'features.description',
        },
      );

      final layout = fieldOf(WebsiteBlockType.features, 'layout');
      expect(
        layout.responsivePolicy,
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        layout.resolvedPropertyFamily,
        WebsiteResponsivePropertyFamily.geometry,
      );
      expect(layout.canResetResponsiveOverride, isTrue);
      // El consumer lo lee en los tres anchos y cambia de composición.
      expect(featuresSource, contains("data['layout']"));
      expect(featuresSource, contains("layout == 'list'"));
      expect(featuresSource, contains('_FeaturesList('));
      expect(featuresSource, contains('_FeaturesGrid('));

      for (final path in const <String>[
        'title',
        'features',
        'features.icon',
        'features.title',
        'features.description',
      ]) {
        expect(
          fieldOf(WebsiteBlockType.features, path).responsivePolicy,
          WebsiteResponsivePropertyPolicy.sharedOnly,
          reason: '$path: contenido e identidad de la característica',
        );
      }
    });

    test('Servicios: auto-layout compartido, y no se inventó una propiedad',
        () {
      final fields = flatFieldsOf(WebsiteBlockType.services);
      expect(
        fields.keys.toSet(),
        <String>{
          'title',
          'services',
          'services.icon',
          'services.title',
          'services.description',
        },
      );
      for (final entry in fields.entries) {
        expect(
          entry.value.allowsViewportOverride,
          isFalse,
          reason: entry.key,
        );
      }
      // La composición sale del ancho, no de un dato guardado.
      expect(servicesSource, contains('final isCompact = usefulWidth < 600'));
      expect(servicesSource, contains('_ServicesMobileList('));
      expect(servicesSource, contains('_ServicesDesktopRows('));
      expect(
        servicesSource,
        isNot(contains("data['layout']")),
        reason: 'si algún día lo lee, toca migrarlo en su ronda',
      );
      expect(fields.containsKey('layout'), isFalse);
    });

    test('Indicadores: auto-layout compartido y cifras compartidas', () {
      final fields = flatFieldsOf(WebsiteBlockType.stats);
      expect(
        fields.keys.toSet(),
        <String>{
          'title',
          'metrics',
          'metrics.label',
          'metrics.value',
          'metrics.suffix',
          'metrics.icon',
        },
      );
      for (final entry in fields.entries) {
        expect(
          entry.value.allowsViewportOverride,
          isFalse,
          reason: '${entry.key}: un logro no cambia según el dispositivo',
        );
      }
      expect(statsSource, contains('final compact = availableWidth < 600'));
      expect(statsSource, contains('final itemWidth ='));
      expect(
        statsSource,
        isNot(contains("data['layout']")),
      );
      expect(fields.containsKey('layout'), isFalse);
    });

    test('ninguna colección del lote se volvió responsive entera', () {
      for (final (type, key) in const <(WebsiteBlockType, String)>[
        (WebsiteBlockType.services, 'services'),
        (WebsiteBlockType.features, 'features'),
        (WebsiteBlockType.stats, 'metrics'),
      ]) {
        final field = fieldOf(type, key);
        expect(field.type, WebsiteBlockFieldType.repeater);
        expect(field.allowsViewportOverride, isFalse, reason: '$type.$key');
      }
    });

    test('el lote no habilitó display copy', () {
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

    test('los aliases legacy del lote siguen declarados', () {
      expect(
        fieldOf(WebsiteBlockType.services, 'services').migrationAliases,
        contains('items'),
      );
      expect(
        fieldOf(WebsiteBlockType.features, 'features').migrationAliases,
        contains('items'),
      );
      expect(
        fieldOf(WebsiteBlockType.stats, 'metrics').migrationAliases,
        containsAll(const <String>['stats', 'items']),
      );
      expect(
        fieldOf(WebsiteBlockType.about, 'imageUrl').migrationAliases,
        contains('image'),
      );
    });
  });

  group('B · lo que NO se ofrece, con su razón', () {
    test('imagePosition sólo lo honra la composición de escritorio', () {
      // Bajo 900 el bloque apila y la imagen va SIEMPRE primero, así que un
      // override de tablet o móvil no podría cambiar nada. Y sobre 900,
      // Escritorio ya es la base. Por eso queda compartida en vez de ofrecer
      // un control que no hace nada.
      final position = fieldOf(WebsiteBlockType.about, 'imagePosition');
      expect(
        position.responsivePolicy,
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );
      expect(position.allowsViewportOverride, isFalse);
      expect(position.canResetResponsiveOverride, isFalse);

      expect(aboutSource, contains("data['imagePosition']?.toString()"));
      expect(aboutSource, contains('final isDesktop = availableWidth >= 900'));
      // El apilado no consulta la posición: media primero, siempre.
      final stackedIndex = aboutSource.indexOf('website-about-stacked-layout');
      expect(stackedIndex, greaterThan(-1));
      expect(
        aboutSource.substring(stackedIndex),
        isNot(contains('imageOnLeft')),
        reason: 'bajo 900 la imagen va primero, sin consultar la posición',
      );
      expect(
        aboutSource.indexOf('imageOnLeft ? media'),
        greaterThan(aboutSource.indexOf('if (isDesktop) {')),
        reason: 'la posición sólo vive dentro de la composición de escritorio',
      );
    });

    test('las columnas y anchos automáticos no entraron al schema', () {
      // Cada familia calcula sus columnas/ancho de tarjeta desde el ancho
      // disponible. Declararlo sería un segundo owner del mismo cálculo.
      for (final (type, source) in <(WebsiteBlockType, String)>[
        (WebsiteBlockType.features, featuresSource),
        (WebsiteBlockType.services, servicesSource),
        (WebsiteBlockType.stats, statsSource),
      ]) {
        final fields = flatFieldsOf(type);
        for (final invented in const <String>[
          'columns',
          'itemsPerRow',
          'cardWidth',
        ]) {
          expect(fields.containsKey(invented), isFalse, reason: '$type');
        }
        expect(source, contains('LayoutBuilder'));
      }
    });
  });

  group('C · projection por viewport, sin cascada ni contaminación', () {
    Map<String, dynamic> projected(
      WebsiteBlockType type,
      Map<String, dynamic> document,
      WebsiteViewport viewport,
    ) =>
        WebsiteResponsiveBlockProjection.project(
          type: type,
          data: document,
          viewport: viewport,
        );

    test('About: asset y encuadre por viewport; alt, copy y posición no', () {
      final document = <String, dynamic>{
        'title': 'Somos Vinabike',
        'content': 'Diez años reparando bicicletas.',
        'imageUrl': 'https://cdn/taller.webp',
        'imageAltText': 'Nuestro taller en Viña',
        'imagePosition': 'left',
        'focalPointX': 0.5,
        'focalPointY': 0.5,
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{
            'imageUrl': 'https://cdn/taller-vertical.webp',
            'focalPointX': 0.8,
          },
          'tablet': <String, dynamic>{'focalPointY': 0.2},
        },
      };

      expect(
        projected(WebsiteBlockType.about, document, WebsiteViewport.desktop)[
            'imageUrl'],
        'https://cdn/taller.webp',
      );
      expect(
        projected(WebsiteBlockType.about, document, WebsiteViewport.tablet)[
            'imageUrl'],
        'https://cdn/taller.webp',
        reason: 'tablet hereda de la base, no de móvil',
      );
      expect(
        projected(WebsiteBlockType.about, document, WebsiteViewport.mobile)[
            'imageUrl'],
        'https://cdn/taller-vertical.webp',
      );

      // Cada eje del encuadre resuelve por separado y sin cascada.
      expect(
        projected(WebsiteBlockType.about, document, WebsiteViewport.mobile)[
            'focalPointX'],
        0.8,
      );
      expect(
        projected(WebsiteBlockType.about, document, WebsiteViewport.mobile)[
            'focalPointY'],
        0.5,
      );
      expect(
        projected(WebsiteBlockType.about, document, WebsiteViewport.tablet)[
            'focalPointY'],
        0.2,
      );
      expect(
        projected(WebsiteBlockType.about, document, WebsiteViewport.tablet)[
            'focalPointX'],
        0.5,
      );

      for (final viewport in WebsiteViewport.values) {
        final result = projected(WebsiteBlockType.about, document, viewport);
        expect(result['imageAltText'], 'Nuestro taller en Viña');
        expect(result['content'], 'Diez años reparando bicicletas.');
        expect(result['imagePosition'], 'left', reason: '$viewport');
      }
    });

    test('About: el foco móvil anterior sigue leyéndose sin migrar nada', () {
      final legacy = <String, dynamic>{
        'imageUrl': 'https://cdn/taller.webp',
        'focalPointX': 0.5,
        'focalPointY': 0.5,
        'mobileFocalPointX': 0.9,
        'mobileFocalPointY': 0.1,
      };
      final mobile =
          projected(WebsiteBlockType.about, legacy, WebsiteViewport.mobile);
      expect(mobile['focalPointX'], 0.9);
      expect(mobile['focalPointY'], 0.1);
      final desktop =
          projected(WebsiteBlockType.about, legacy, WebsiteViewport.desktop);
      expect(desktop['focalPointX'], 0.5);
      // Y leer no migra: el documento original no cambió.
      expect(legacy['mobileFocalPointX'], 0.9);
      expect(legacy.containsKey('responsive'), isFalse);
    });

    test('Features: el diseño resuelve por viewport y los items no', () {
      final document = <String, dynamic>{
        'title': 'Por qué elegirnos',
        'layout': 'grid',
        'features': <Map<String, dynamic>>[
          {
            'icon': 'verified',
            'title': 'Técnicos certificados',
            'description': 'Equipo con certificación oficial.',
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{'title': 'Otro título'},
            },
          },
        ],
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{'layout': 'list'},
        },
      };

      expect(
        projected(WebsiteBlockType.features, document, WebsiteViewport.desktop)[
            'layout'],
        'grid',
      );
      expect(
        projected(WebsiteBlockType.features, document, WebsiteViewport.tablet)[
            'layout'],
        'grid',
      );
      expect(
        projected(WebsiteBlockType.features, document, WebsiteViewport.mobile)[
            'layout'],
        'list',
      );

      for (final viewport in WebsiteViewport.values) {
        final items = (projected(
                    WebsiteBlockType.features, document, viewport)['features']
                as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        expect(
          items.single['title'],
          'Técnicos certificados',
          reason: '$viewport: un override plantado sobre copy se ignora',
        );
        expect(items.single['icon'], 'verified');
      }
    });

    test('Servicios e Indicadores ignoran cualquier override plantado', () {
      final services = <String, dynamic>{
        'title': 'Nuestros Servicios',
        'services': <Map<String, dynamic>>[
          {
            'icon': 'build',
            'title': 'Mantención completa',
            'description': 'Ajuste integral.',
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{'icon': 'favorite'},
            },
          },
        ],
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{'title': 'Servicios móvil'},
        },
      };
      final stats = <String, dynamic>{
        'title': 'Resultados',
        'metrics': <Map<String, dynamic>>[
          {
            'label': 'Bicis reparadas',
            'value': '1.200+',
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{'value': '9.999+'},
            },
          },
        ],
      };

      for (final viewport in WebsiteViewport.values) {
        final servicesResult =
            projected(WebsiteBlockType.services, services, viewport);
        expect(servicesResult['title'], 'Nuestros Servicios');
        final service = (servicesResult['services'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .single;
        expect(service['icon'], 'build', reason: '$viewport');

        final metric =
            (projected(WebsiteBlockType.stats, stats, viewport)['metrics']
                    as List)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .single;
        expect(
          metric['value'],
          '1.200+',
          reason: '$viewport: la cifra publicada es una sola',
        );
      }
    });

    test('las listas vacías y los alias de colección sobreviven', () {
      final legacyFeatures = <String, dynamic>{
        'items': <Map<String, dynamic>>[
          {'title': 'Garantía', 'description': 'Un año'},
        ],
      };
      final emptyServices = <String, dynamic>{
        'title': 'Servicios',
        'services': <Map<String, dynamic>>[],
      };
      for (final viewport in WebsiteViewport.values) {
        final features = (projected(WebsiteBlockType.features, legacyFeatures,
                viewport)['features'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        expect(features.single['title'], 'Garantía', reason: '$viewport');
        expect(
          projected(
              WebsiteBlockType.services, emptyServices, viewport)['services'],
          isEmpty,
        );
      }
    });
  });
}
