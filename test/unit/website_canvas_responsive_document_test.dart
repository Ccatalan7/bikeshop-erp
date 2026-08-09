import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_document_sanitizer.dart';
import 'package:vinabike_erp/modules/website/models/website_canvas_responsive_document.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';

/// Fase 7A: el modelo de datos responsive de Canvas, puro.
///
/// Nada de esto toca widget, provider ni persistencia: son documentos que
/// entran y documentos nuevos que salen. El objetivo del corte es que ningún
/// gesto de Canvas pueda escribir algo inseguro cuando 7B lo conecte.
void main() {
  Map<String, dynamic> layer(
    String id, {
    String type = 'text',
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) =>
      <String, dynamic>{
        'id': id,
        'type': type,
        'x': 24.0,
        'y': 24.0,
        'w': 360.0,
        'h': 72.0,
        'rotation': 0.0,
        ...extra,
      };

  Map<String, dynamic> canonicalDocument() => <String, dynamic>{
        'designWidth': 1200.0,
        'blockHeight': 420.0,
        'backgroundColor': '#FFFFFF',
        'backgroundImageUrl': 'https://cdn/canvas.webp',
        'backgroundImageAltText': 'Taller de bicicletas',
        'focalPointX': 0.5,
        'focalPointY': 0.5,
        'constrainElementsToSafeArea': true,
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{
            'designWidth': 390.0,
            'backgroundImageUrl': 'https://cdn/canvas-vertical.webp',
            'focalPointX': 0.8,
            'blockHeight': 560.0,
          },
          'tablet': <String, dynamic>{'designWidth': 834.0},
        },
        'elements': <Map<String, dynamic>>[
          layer(
            'hero-title',
            extra: <String, dynamic>{
              'text': 'Somos Vinabike',
              'fontSize': 48.0,
              'color': '#111111',
              'visible': true,
              'responsive': <String, dynamic>{
                'version': 2,
                'mobile': <String, dynamic>{
                  'x': 12.0,
                  'w': 320.0,
                  'fontSize': 28.0,
                },
              },
            },
          ),
          layer(
            'hero-badge',
            type: 'shape',
            extra: <String, dynamic>{
              'shape': 'rectangle',
              'fillColor': '#1F2937',
              'visible': true,
              'responsive': <String, dynamic>{
                'version': 2,
                'mobile': <String, dynamic>{'visible': false},
              },
            },
          ),
        ],
      };

  /// Documento heredado con los gemelos generados que el editor antiguo creaba.
  Map<String, dynamic> legacyTwinsDocument() => <String, dynamic>{
        'designWidth': 1200.0,
        'mobileDesignWidth': 390.0,
        'focalPointX': 0.5,
        'mobileFocalPointX': 0.85,
        'elements': <Map<String, dynamic>>[
          layer(
            'hero-title_desktop',
            extra: <String, dynamic>{
              'text': 'Somos Vinabike',
              'fontSize': 48.0,
              'color': '#111111',
              'hideOnMobile': true,
            },
          ),
          layer(
            'hero-subtitle_desktop',
            extra: <String, dynamic>{
              'text': 'Diez años en el taller',
              'fontSize': 24.0,
              'hideOnMobile': true,
            },
          ),
          layer(
            'hero-cta_desktop',
            type: 'button',
            extra: <String, dynamic>{
              'label': 'Agendar',
              'link': '/contacto',
              'style': 'filled',
              'hideOnMobile': true,
            },
          ),
          layer(
            'logo',
            type: 'image',
            extra: <String, dynamic>{
              'imageUrl': 'https://cdn/logo.webp',
              'altText': 'Logo',
            },
          ),
          layer(
            'hero-title_mobile',
            extra: <String, dynamic>{
              'text': 'Somos Vinabike',
              'fontSize': 28.0,
              'color': '#111111',
              'x': 12.0,
              'w': 320.0,
              'showOnMobile': true,
            },
          ),
          layer(
            'hero-subtitle_mobile',
            extra: <String, dynamic>{
              'text': 'Diez años en el taller',
              'fontSize': 18.0,
              'x': 12.0,
              'showOnMobile': true,
            },
          ),
          layer(
            'hero-cta_mobile',
            type: 'button',
            extra: <String, dynamic>{
              'label': 'Agendar',
              'link': '/contacto',
              'style': 'filled',
              'x': 12.0,
              'w': 320.0,
              'showOnMobile': true,
            },
          ),
        ],
      };

  List<Map<String, dynamic>> elementsOf(Map<String, dynamic> document) =>
      (document['elements'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);

  group('A · proyección canónica por viewport', () {
    test('390, 834 y 1440 resuelven raíz y capas sin cascada', () {
      final document = canonicalDocument();

      for (final (width, viewport) in const <(double, WebsiteViewport)>[
        (390, WebsiteViewport.mobile),
        (834, WebsiteViewport.tablet),
        (1440, WebsiteViewport.desktop),
      ]) {
        expect(
          WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(
            document,
            width,
          ),
          viewport,
          reason: '$width',
        );
      }

      final desktop = WebsiteCanvasResponsiveDocument.project(
        data: document,
        viewport: WebsiteViewport.desktop,
      );
      final tablet = WebsiteCanvasResponsiveDocument.project(
        data: document,
        viewport: WebsiteViewport.tablet,
      );
      final mobile = WebsiteCanvasResponsiveDocument.project(
        data: document,
        viewport: WebsiteViewport.mobile,
      );

      expect(desktop['designWidth'], 1200.0);
      expect(tablet['designWidth'], 834.0);
      expect(mobile['designWidth'], 390.0);
      // Tablet hereda de la base, nunca de móvil.
      expect(tablet['blockHeight'], 420.0);
      expect(mobile['blockHeight'], 560.0);
      expect(tablet['focalPointX'], 0.5);
      expect(mobile['focalPointX'], 0.8);
      expect(
        tablet['backgroundImageUrl'],
        'https://cdn/canvas.webp',
        reason: 'el asset móvil no se filtra a tablet',
      );
      expect(
        mobile['backgroundImageUrl'],
        'https://cdn/canvas-vertical.webp',
      );
      // El alt y las reglas de autoría son las mismas en los tres.
      for (final projected in <Map<String, dynamic>>[desktop, tablet, mobile]) {
        expect(projected['backgroundImageAltText'], 'Taller de bicicletas');
        expect(projected['constrainElementsToSafeArea'], isTrue);
        expect(
          projected.containsKey('responsive'),
          isFalse,
          reason: 'la proyección entrega valores, no el contenedor',
        );
      }

      final mobileLayers = WebsiteCanvasResponsiveDocument.projectLayers(
        data: document,
        viewport: WebsiteViewport.mobile,
      );
      expect(mobileLayers.first.data['x'], 12.0);
      expect(mobileLayers.first.data['w'], 320.0);
      expect(mobileLayers.first.data['fontSize'], 28.0);
      expect(
        mobileLayers.first.data['text'],
        'Somos Vinabike',
        reason: 'el copy es compartido',
      );
      expect(mobileLayers.first.data['color'], '#111111');

      final tabletLayers = WebsiteCanvasResponsiveDocument.projectLayers(
        data: document,
        viewport: WebsiteViewport.tablet,
      );
      expect(tabletLayers.first.data['x'], 24.0);
      expect(tabletLayers.first.data['fontSize'], 48.0);
    });

    test('la visibilidad tipada gana y las capas ocultas siguen presentes', () {
      final document = canonicalDocument();
      final mobile = WebsiteCanvasResponsiveDocument.projectLayers(
        data: document,
        viewport: WebsiteViewport.mobile,
      );
      expect(mobile.length, 2, reason: 'Edit puede seleccionar lo oculto');
      expect(mobile.last.visible, isFalse);
      expect(
        WebsiteCanvasResponsiveDocument.visibleLayers(
          data: document,
          viewport: WebsiteViewport.mobile,
        ).map((item) => item.id),
        <String>['hero-title'],
      );
      expect(
        WebsiteCanvasResponsiveDocument.visibleLayers(
          data: document,
          viewport: WebsiteViewport.desktop,
        ).map((item) => item.id),
        <String>['hero-title', 'hero-badge'],
      );
    });

    test('el orden base es la posición en la lista; el override es excepción',
        () {
      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          layer('a'),
          layer(
            'b',
            extra: <String, dynamic>{
              'responsive': <String, dynamic>{
                'version': 2,
                'mobile': <String, dynamic>{'order': 0},
              },
            },
          ),
        ],
      };

      expect(
        WebsiteCanvasResponsiveDocument.projectLayers(
          data: document,
          viewport: WebsiteViewport.desktop,
        ).map((item) => item.order),
        <int>[0, 1],
      );
      expect(
        WebsiteCanvasResponsiveDocument.projectLayers(
          data: document,
          viewport: WebsiteViewport.mobile,
        ).map((item) => item.id),
        <String>['b', 'a'],
        reason: 'el override de orden manda sólo en su viewport',
      );
      // Y no existe un segundo dueño del orden base.
      for (final item in elementsOf(document)) {
        expect(item.containsKey('order'), isFalse);
      }
    });

    test('escribir y restablecer no deja rastro ni cascada', () {
      final original = canonicalDocument();
      final customized = WebsiteCanvasResponsiveDocument.setLayerProperty(
        data: original,
        layerId: 'hero-badge',
        key: 'fillColor',
        value: '#FF0000',
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.tablet,
      );
      final badge = elementsOf(customized)[1];
      expect(
        ((badge['responsive'] as Map)['tablet'] as Map)['fillColor'],
        '#FF0000',
      );
      expect(badge['fillColor'], '#1F2937');
      expect(
        ((badge['responsive'] as Map)['mobile'] as Map)['visible'],
        isFalse,
        reason: 'el override de móvil sigue siendo suyo',
      );

      final reset = WebsiteCanvasResponsiveDocument.clearLayerOverride(
        data: customized,
        layerId: 'hero-badge',
        key: 'fillColor',
        viewport: WebsiteViewport.tablet,
      );
      expect(reset, original, reason: 'igualdad profunda');
    });

    test('escritorio y sharedOnly siempre escriben la base', () {
      final document = canonicalDocument();
      final desktopWrite = WebsiteCanvasResponsiveDocument.setRootProperty(
        data: document,
        key: 'backgroundColor',
        value: '#000000',
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.desktop,
      );
      expect(desktopWrite['backgroundColor'], '#000000');
      expect(
        (desktopWrite['responsive'] as Map).containsKey('desktop'),
        isFalse,
      );

      final sharedWrite = WebsiteCanvasResponsiveDocument.setRootProperty(
        data: document,
        key: 'backgroundImageAltText',
        value: 'Otro alt',
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      );
      expect(sharedWrite['backgroundImageAltText'], 'Otro alt');
      expect(
        (sharedWrite['responsive'] as Map)['mobile'],
        isNot(contains('backgroundImageAltText')),
      );
    });

    test('una imagen ligada a producto no admite art direction', () {
      final bound = <String, dynamic>{
        'id': 'product-shot',
        'type': 'image',
        'productId': 'sku-1',
        'imageSource': 'product',
        'imageUrl': 'https://cdn/manual.webp',
      };
      final manual = <String, dynamic>{
        'id': 'free-shot',
        'type': 'image',
        'productId': '',
        'imageSource': 'manual',
        'imageUrl': 'https://cdn/manual.webp',
      };
      expect(
        WebsiteCanvasResponsivePolicy.isOverridableForLayer(bound, 'imageUrl'),
        isFalse,
      );
      expect(
        WebsiteCanvasResponsivePolicy.isOverridableForLayer(manual, 'imageUrl'),
        isTrue,
      );

      // Y la escritura obedece: en una capa ligada aterriza en la base.
      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[bound],
      };
      final written = WebsiteCanvasResponsiveDocument.setLayerProperty(
        data: document,
        layerId: 'product-shot',
        key: 'imageUrl',
        value: 'https://cdn/otro.webp',
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      );
      final layerData = elementsOf(written).single;
      expect(layerData['imageUrl'], 'https://cdn/otro.webp');
      expect(layerData.containsKey('responsive'), isFalse);
    });
  });

  group('B · lectura legacy sin migrar', () {
    test('la clasificación heredada usa las bandas 640/1024 en 620 y 1000', () {
      final legacy = legacyTwinsDocument();
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(legacy, 620),
        WebsiteViewport.mobile,
      );
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(legacy, 1000),
        WebsiteViewport.tablet,
      );
      // El documento canónico usa el owner 600/900 del producto.
      final canonical = canonicalDocument();
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(canonical, 620),
        WebsiteViewport.tablet,
      );
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(canonical, 1000),
        WebsiteViewport.desktop,
      );
    });

    test('renderer y comandos comparten el umbral de Canvas heredado', () {
      // El documento legacy conserva 640/1024 para lectura general, pero el
      // Canvas editable históricamente conmuta su única variante compacta a
      // 600. El renderer y el owner del gesto deben consumir esta misma API.
      expect(WebsiteCanvasResponsiveDocument.legacyCanvasCompactWidth, 600);
      final legacy = legacyTwinsDocument();
      for (final (width, expected) in <(double, WebsiteViewport)>[
        (599, WebsiteViewport.mobile),
        (600, WebsiteViewport.desktop),
        (620, WebsiteViewport.desktop),
      ]) {
        expect(
          WebsiteCanvasResponsiveDocument.viewportForRenderedCanvasWidth(
            legacy,
            width,
          ),
          expected,
          reason: 'Canvas legacy a $width',
        );
      }
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(legacy, 620),
        WebsiteViewport.mobile,
        reason: 'la banda heredada del documento dice móvil a 620',
      );
      final canonical = canonicalDocument();
      for (final (width, expected) in <(double, WebsiteViewport)>[
        (599, WebsiteViewport.mobile),
        (600, WebsiteViewport.tablet),
        (899, WebsiteViewport.tablet),
        (900, WebsiteViewport.desktop),
      ]) {
        expect(
          WebsiteCanvasResponsiveDocument.viewportForRenderedCanvasWidth(
            canonical,
            width,
          ),
          expected,
          reason: 'Canvas canónico a $width',
        );
      }
    });

    test('los alias de raíz y el par de visibilidad se leen sin migrar', () {
      final legacy = legacyTwinsDocument();
      final mobile = WebsiteCanvasResponsiveDocument.project(
        data: legacy,
        viewport: WebsiteViewport.mobile,
      );
      final desktop = WebsiteCanvasResponsiveDocument.project(
        data: legacy,
        viewport: WebsiteViewport.desktop,
      );
      expect(mobile['designWidth'], 390.0);
      expect(desktop['designWidth'], 1200.0);
      expect(mobile['focalPointX'], 0.85);
      expect(desktop['focalPointX'], 0.5);

      final visibleOnMobile = WebsiteCanvasResponsiveDocument.visibleLayers(
        data: legacy,
        viewport: WebsiteViewport.mobile,
      ).map((item) => item.id);
      expect(
        visibleOnMobile,
        <String>[
          'logo',
          'hero-title_mobile',
          'hero-subtitle_mobile',
          'hero-cta_mobile',
        ],
      );
      final visibleOnDesktop = WebsiteCanvasResponsiveDocument.visibleLayers(
        data: legacy,
        viewport: WebsiteViewport.desktop,
      ).map((item) => item.id);
      expect(
        visibleOnDesktop,
        <String>[
          'hero-title_desktop',
          'hero-subtitle_desktop',
          'hero-cta_desktop',
          'logo',
        ],
      );

      // Leer no migra: el documento original no cambió.
      expect(legacy['mobileDesignWidth'], 390.0);
      expect(legacy.containsKey('responsive'), isFalse);
      expect(elementsOf(legacy).length, 7);
    });

    test('analyze no cambia el documento', () {
      final legacy = legacyTwinsDocument();
      final before = Map<String, dynamic>.from(legacy);
      final result = WebsiteCanvasMigration.analyze(legacy);
      expect(result.document, before);
      expect(result.changed, isTrue, reason: 'sí habría trabajo que hacer');
      expect(result.mergedStems, <String>[
        'hero-cta',
        'hero-subtitle',
        'hero-title',
      ]);
      expect(legacy, before, reason: 'la entrada nunca se muta');
    });
  });

  group('C · migración segura, idempotente y reversible', () {
    test('un par que ya tenía overrides typed conserva lo que el teléfono ve',
        () {
      // Los dos gemelos llevan el MISMO contenedor typed, así que el par sigue
      // siendo seguro. Lo que el teléfono dibuja, sin embargo, no está en el
      // nivel superior del gemelo móvil sino dentro de su propio
      // `responsive.mobile`: si la fusión sólo mira el nivel superior, esos
      // valores desaparecen y la campaña cambia de tamaño en el teléfono.
      Map<String, dynamic> twin(String id, Map<String, dynamic> flags) => layer(
            id,
            extra: <String, dynamic>{
              ...flags,
              'text': 'Somos Vinabike',
              'fontSize': 48.0,
              'responsive': <String, dynamic>{
                'version': 2,
                'mobile': <String, dynamic>{
                  'fontSize': 22.0,
                  'x': 12.0,
                  'h': 120.0,
                },
              },
            },
          );

      final legacy = <String, dynamic>{
        'designWidth': 1200.0,
        'elements': <Map<String, dynamic>>[
          twin('hero-title_desktop', <String, dynamic>{'hideOnMobile': true}),
          twin('hero-title_mobile', <String, dynamic>{'showOnMobile': true}),
        ],
      };
      final before = <String, dynamic>{
        for (final viewport in WebsiteViewport.values)
          viewport.name: WebsiteCanvasResponsiveDocument.projectLayers(
            data: legacy,
            viewport: viewport,
          )
              .where((entry) => entry.visible)
              .map((entry) => <String, dynamic>{
                    'fontSize': entry.data['fontSize'],
                    'x': entry.data['x'],
                    'h': entry.data['h'],
                    'text': entry.data['text'],
                  })
              .toList(),
      };

      expect(
        WebsiteCanvasMigration.inspect(legacy).state,
        WebsiteCanvasMigrationState.safe,
        reason: 'contenedores idénticos: no hay nada que decidir',
      );

      final result = WebsiteCanvasMigration.migrate(legacy);
      expect(result.changed, isTrue);
      expect(result.mergedStems, <String>['hero-title']);

      final merged = Map<String, dynamic>.from(
        (result.document['elements'] as List).single as Map,
      );
      expect(merged['fontSize'], 48.0);
      expect(
        (merged['responsive'] as Map)['mobile'],
        <String, dynamic>{'fontSize': 22.0, 'x': 12.0, 'h': 120.0},
        reason: 'la rama móvil resultante es lo que el gemelo móvil dibujaba',
      );

      for (final viewport in WebsiteViewport.values) {
        final after = WebsiteCanvasResponsiveDocument.projectLayers(
          data: result.document,
          viewport: viewport,
        )
            .where((entry) => entry.visible)
            .map((entry) => <String, dynamic>{
                  'fontSize': entry.data['fontSize'],
                  'x': entry.data['x'],
                  'h': entry.data['h'],
                  'text': entry.data['text'],
                })
            .toList();
        expect(
          after,
          before[viewport.name],
          reason: 'geometría, estilo y visibilidad idénticos en '
              '${viewport.name}',
        );
      }

      expect(
        WebsiteCanvasMigration.expandToLegacy(result.document),
        legacy,
        reason: 'la vuelta devuelve el documento heredado exacto',
      );
    });

    test('los tres pares se fusionan conservando geometría, estilo y acción',
        () {
      final legacy = legacyTwinsDocument();
      final result = WebsiteCanvasMigration.migrate(legacy);
      expect(result.changed, isTrue);
      expect(result.issues, isEmpty);

      final elements = elementsOf(result.document);
      expect(
        elements.map((item) => item['id']),
        <String>['hero-title', 'hero-subtitle', 'hero-cta', 'logo'],
      );

      final title = elements.first;
      expect(title['text'], 'Somos Vinabike');
      expect(title['fontSize'], 48.0);
      expect(title['x'], 24.0);
      expect(title['visible'], isTrue);
      expect(title.containsKey('hideOnMobile'), isFalse);
      expect(title.containsKey('showOnMobile'), isFalse);
      final titleMobile = (title['responsive'] as Map)['mobile'] as Map;
      expect(titleMobile['x'], 12.0);
      expect(titleMobile['w'], 320.0);
      expect(titleMobile['fontSize'], 28.0);
      expect(
        titleMobile.containsKey('text'),
        isFalse,
        reason: 'el copy idéntico no se duplica',
      );

      final cta = elements[2];
      expect(cta['label'], 'Agendar');
      expect(cta['link'], '/contacto');
      expect(((cta['responsive'] as Map)['mobile'] as Map)['x'], 12.0);
      expect(
        ((cta['responsive'] as Map)['mobile'] as Map).containsKey('link'),
        isFalse,
        reason: 'el destino jamás entra al override',
      );

      // La paridad por viewport: cada composición conserva su z-order.
      expect(
        WebsiteCanvasResponsiveDocument.visibleLayers(
          data: result.document,
          viewport: WebsiteViewport.desktop,
        ).map((item) => item.id),
        <String>['hero-title', 'hero-subtitle', 'hero-cta', 'logo'],
      );
      expect(
        WebsiteCanvasResponsiveDocument.visibleLayers(
          data: result.document,
          viewport: WebsiteViewport.mobile,
        ).map((item) => item.id),
        <String>['logo', 'hero-title', 'hero-subtitle', 'hero-cta'],
        reason: 'en móvil el logo iba primero y así se conserva',
      );
    });

    test('la migración nunca escribe un orden base', () {
      final result = WebsiteCanvasMigration.migrate(legacyTwinsDocument());
      for (final item in elementsOf(result.document)) {
        expect(
          item.containsKey('order'),
          isFalse,
          reason: 'el orden base es la posición en la lista',
        );
      }
    });

    test('expandir devuelve exactamente el documento heredado', () {
      final legacy = legacyTwinsDocument();
      final migrated = WebsiteCanvasMigration.migrate(legacy).document;
      final expanded = WebsiteCanvasMigration.expandToLegacy(migrated);
      expect(expanded, legacy);
    });

    test('una segunda migración no cambia nada', () {
      final once = WebsiteCanvasMigration.migrate(legacyTwinsDocument());
      final twice = WebsiteCanvasMigration.migrate(once.document);
      expect(twice.changed, isFalse);
      expect(twice.document, once.document);
      expect(twice.issues, isEmpty);
    });

    test('un orden invertido entre dos pares se conserva, no se rechaza', () {
      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          layer('a_desktop', extra: <String, dynamic>{'hideOnMobile': true}),
          layer('b_desktop', extra: <String, dynamic>{'hideOnMobile': true}),
          layer('b_mobile', extra: <String, dynamic>{'showOnMobile': true}),
          layer('a_mobile', extra: <String, dynamic>{'showOnMobile': true}),
        ],
      };
      final result = WebsiteCanvasMigration.migrate(document);
      expect(result.issues, isEmpty);
      expect(result.mergedStems, <String>['a', 'b']);

      // Cada viewport conserva SU z-order.
      expect(
        WebsiteCanvasResponsiveDocument.visibleLayers(
          data: result.document,
          viewport: WebsiteViewport.desktop,
        ).map((item) => item.id),
        <String>['a', 'b'],
      );
      expect(
        WebsiteCanvasResponsiveDocument.visibleLayers(
          data: result.document,
          viewport: WebsiteViewport.mobile,
        ).map((item) => item.id),
        <String>['b', 'a'],
      );
      // Y el ida y vuelta sigue siendo exacto.
      expect(WebsiteCanvasMigration.expandToLegacy(result.document), document);
    });

    test('una presentación ausente en el gemelo móvil se marca sin fijar', () {
      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'hero_desktop',
            'type': 'text',
            'text': 'Somos Vinabike',
            'x': 24.0,
            'y': 24.0,
            'w': 360.0,
            'fontSize': 48.0,
            'hideOnMobile': true,
          },
          // El gemelo móvil no traía `fontSize` ni `w`: el renderer usaba su
          // propio default, no el valor de escritorio.
          <String, dynamic>{
            'id': 'hero_mobile',
            'type': 'text',
            'text': 'Somos Vinabike',
            'x': 12.0,
            'y': 24.0,
            'showOnMobile': true,
          },
        ],
      };

      final result = WebsiteCanvasMigration.migrate(document);
      expect(result.issues, isEmpty);
      final merged = elementsOf(result.document).single;
      final mobile = (merged['responsive'] as Map)['mobile'] as Map;
      expect(merged['fontSize'], 48.0);
      expect(merged['w'], 360.0);
      expect(mobile.containsKey('fontSize'), isTrue);
      expect(mobile['fontSize'], isNull, reason: 'sin fijar, no heredado');
      expect(mobile.containsKey('w'), isTrue);
      expect(mobile['w'], isNull);
      expect(mobile['x'], 12.0);

      // La proyección entrega ese "sin fijar" al consumidor…
      final mobileLayer = WebsiteCanvasResponsiveDocument.projectLayers(
        data: result.document,
        viewport: WebsiteViewport.mobile,
      ).single;
      expect(mobileLayer.data['fontSize'], isNull);
      expect(mobileLayer.data['w'], isNull);
      expect(mobileLayer.data['text'], 'Somos Vinabike');
      // …y escritorio conserva los suyos.
      final desktopLayer = WebsiteCanvasResponsiveDocument.projectLayers(
        data: result.document,
        viewport: WebsiteViewport.desktop,
      ).single;
      expect(desktopLayer.data['fontSize'], 48.0);
      expect(desktopLayer.data['w'], 360.0);

      // Y la vuelta restituye la AUSENCIA, no un null.
      final expanded = WebsiteCanvasMigration.expandToLegacy(result.document);
      expect(expanded, document);
      final expandedMobile = elementsOf(expanded)[1];
      expect(expandedMobile.containsKey('fontSize'), isFalse);
      expect(expandedMobile.containsKey('w'), isFalse);
    });

    test('los alias de raíz se absorben y vuelven exactos', () {
      final legacy = legacyTwinsDocument();
      final migrated = WebsiteCanvasMigration.migrate(legacy).document;

      expect(migrated.containsKey('mobileDesignWidth'), isFalse);
      expect(migrated.containsKey('mobileFocalPointX'), isFalse);
      final mobile = (migrated['responsive'] as Map)['mobile'] as Map;
      expect(mobile['designWidth'], 390.0);
      expect(mobile['focalPointX'], 0.85);
      expect(migrated['designWidth'], 1200.0);
      expect(migrated['focalPointX'], 0.5);

      // El renderer ya no necesita leer el alias: la proyección da lo mismo
      // antes y después de migrar.
      for (final viewport in WebsiteViewport.values) {
        expect(
          WebsiteCanvasResponsiveDocument.project(
            data: migrated,
            viewport: viewport,
          )['designWidth'],
          WebsiteCanvasResponsiveDocument.project(
            data: legacy,
            viewport: viewport,
          )['designWidth'],
          reason: '$viewport',
        );
      }

      expect(WebsiteCanvasMigration.expandToLegacy(migrated), legacy);
    });

    test('un alias de raíz ausente no se inventa, y uno explícito se conserva',
        () {
      final withoutAlias = <String, dynamic>{
        'designWidth': 1200.0,
        'elements': <Map<String, dynamic>>[
          layer('solo', extra: <String, dynamic>{'hideOnMobile': true}),
        ],
      };
      final migrated = WebsiteCanvasMigration.migrate(withoutAlias).document;
      expect(migrated.containsKey('mobileDesignWidth'), isFalse);
      expect(
        (migrated['responsive'] as Map?)?.containsKey('mobile'),
        isNot(isTrue),
        reason: 'sin alias no hay override de raíz que crear',
      );
      expect(WebsiteCanvasMigration.expandToLegacy(migrated), withoutAlias);

      // Un alias con valor explícito —incluido un cero— viaja tal cual.
      final explicitZero = <String, dynamic>{
        'focalPointX': 0.5,
        'mobileFocalPointX': 0.0,
        'elements': <Map<String, dynamic>>[layer('a')],
      };
      final zeroMigrated =
          WebsiteCanvasMigration.migrate(explicitZero).document;
      expect(
        ((zeroMigrated['responsive'] as Map)['mobile'] as Map)['focalPointX'],
        0.0,
      );
      expect(
        WebsiteCanvasResponsiveDocument.project(
          data: zeroMigrated,
          viewport: WebsiteViewport.mobile,
        )['focalPointX'],
        0.0,
      );
      expect(
        WebsiteCanvasMigration.expandToLegacy(zeroMigrated),
        explicitZero,
      );
    });

    test('una capa canónica nativa no recibe procedencia inventada', () {
      final document = canonicalDocument();
      final result = WebsiteCanvasMigration.migrate(document);
      expect(result.changed, isFalse);
      expect(result.document, document);
      expect(
        result.document.containsKey(WebsiteCanvasMigration.provenanceKey),
        isFalse,
      );
      // Y expandir un documento sin procedencia lo devuelve igual.
      expect(WebsiteCanvasMigration.expandToLegacy(document), document);
    });

    test('una capa canónica junto a un par migrado no se toca', () {
      // Regresión: convivir con una migración no puede darle a una capa ya
      // canónica ni `visible` inventado ni procedencia de gemelo.
      final native = layer(
        'nativa',
        extra: <String, dynamic>{
          'text': 'Ya canónica',
          'responsive': <String, dynamic>{
            'version': 2,
            'mobile': <String, dynamic>{'x': 8.0},
          },
        },
      );
      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          layer(
            'par_desktop',
            extra: <String, dynamic>{'text': 'Par', 'hideOnMobile': true},
          ),
          Map<String, dynamic>.from(native),
          layer(
            'par_mobile',
            extra: <String, dynamic>{
              'text': 'Par',
              'x': 12.0,
              'showOnMobile': true,
            },
          ),
        ],
      };

      final result = WebsiteCanvasMigration.migrate(document);
      expect(result.mergedStems, <String>['par']);
      final migratedNative = elementsOf(result.document)
          .firstWhere((item) => item['id'] == 'nativa');
      expect(migratedNative, native, reason: 'equivalente en valor');
      expect(migratedNative.containsKey('visible'), isFalse);

      final records = ((result.document[WebsiteCanvasMigration.provenanceKey]
              as Map)['layers'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      final nativeRecord =
          records.firstWhere((record) => record['id'] == 'nativa');
      expect(
        nativeRecord['kind'],
        'placement',
        reason: 'no es un gemelo legacy y no puede fingir serlo',
      );
      expect(nativeRecord.containsKey('flags'), isFalse);
      expect(WebsiteCanvasMigration.expandToLegacy(result.document), document);
    });

    test('una capa suelta conserva su visibilidad heredada como tipada', () {
      final legacy = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          layer('solo', extra: <String, dynamic>{'hideOnMobile': true}),
          layer('mobile-only', extra: <String, dynamic>{'showOnMobile': true}),
          layer(
            'contradictorio',
            extra: <String, dynamic>{
              'hideOnMobile': true,
              'showOnMobile': true,
            },
          ),
        ],
      };
      final migrated = WebsiteCanvasMigration.migrate(legacy).document;
      final elements = elementsOf(migrated);

      expect(elements[0]['visible'], isTrue);
      expect(
        ((elements[0]['responsive'] as Map)['mobile'] as Map)['visible'],
        isFalse,
      );
      expect(elements[1]['visible'], isFalse);
      expect(
        ((elements[1]['responsive'] as Map)['mobile'] as Map)['visible'],
        isTrue,
      );
      // El par contradictorio se resuelve como lo dibuja hoy la tienda:
      // invisible en ambos, sin contradicción persistida.
      expect(elements[2]['visible'], isFalse);
      expect(elements[2].containsKey('responsive'), isFalse);
      for (final item in elements) {
        expect(item.containsKey('hideOnMobile'), isFalse);
        expect(item.containsKey('showOnMobile'), isFalse);
      }
      expect(WebsiteCanvasMigration.expandToLegacy(migrated), legacy);
    });
  });

  group('D · lo ambiguo queda intacto y tipado', () {
    Map<String, dynamic> pairWith({
      required Map<String, dynamic> desktopExtra,
      required Map<String, dynamic> mobileExtra,
      String desktopId = 'hero_desktop',
      String mobileId = 'hero_mobile',
      String desktopType = 'text',
      String mobileType = 'text',
    }) =>
        <String, dynamic>{
          'elements': <Map<String, dynamic>>[
            layer(
              desktopId,
              type: desktopType,
              extra: <String, dynamic>{'hideOnMobile': true, ...desktopExtra},
            ),
            layer(
              mobileId,
              type: mobileType,
              extra: <String, dynamic>{'showOnMobile': true, ...mobileExtra},
            ),
          ],
        };

    void expectUnchanged(
      Map<String, dynamic> document,
      WebsiteCanvasMigrationIssueCode code,
    ) {
      final before = Map<String, dynamic>.from(document);
      final result = WebsiteCanvasMigration.migrate(document);
      expect(result.changed, isFalse, reason: code.name);
      expect(result.document, before, reason: 'byte-equivalente');
      expect(result.mergedStems, isEmpty);
      expect(result.issues.map((issue) => issue.code), contains(code));
    }

    test('copy distinto', () {
      expectUnchanged(
        pairWith(
          desktopExtra: <String, dynamic>{'text': 'Uno'},
          mobileExtra: <String, dynamic>{'text': 'Otro'},
        ),
        WebsiteCanvasMigrationIssueCode.differingSharedValue,
      );
    });

    test('destino distinto', () {
      final document = pairWith(
        desktopExtra: <String, dynamic>{'label': 'Ir', 'link': '/a'},
        mobileExtra: <String, dynamic>{'label': 'Ir', 'link': '/b'},
        desktopType: 'button',
        mobileType: 'button',
      );
      final result = WebsiteCanvasMigration.migrate(document);
      expect(result.changed, isFalse);
      final issue = result.issues.single;
      expect(
        issue.code,
        WebsiteCanvasMigrationIssueCode.differingSharedValue,
      );
      expect(issue.propertyKey, 'link');
      expect(issue.layerIds, <String>['hero_desktop', 'hero_mobile']);
    });

    test('stem duplicado: la identidad lo detiene antes', () {
      // Dos capas con el MISMO id exacto son el caso que antes llegaba como
      // `duplicateStem`. Con la identidad validada se detiene una etapa antes
      // y con una garantía más fuerte: no se migra ninguna capa, porque nada
      // podría revertirse exactamente.
      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          layer('hero_desktop', extra: <String, dynamic>{'hideOnMobile': true}),
          layer('hero_mobile', extra: <String, dynamic>{'showOnMobile': true}),
          layer(
            'hero_mobile',
            extra: <String, dynamic>{'showOnMobile': true, 'x': 40.0},
          ),
        ],
      };
      expectUnchanged(
        document,
        WebsiteCanvasMigrationIssueCode.conflictingIdentity,
      );
      final issue = WebsiteCanvasMigration.migrate(document).issues.single;
      expect(issue.propertyKey, 'id');
      expect(issue.stem, 'hero_mobile');
    });

    test('gemelo ausente', () {
      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          layer('hero_desktop', extra: <String, dynamic>{'hideOnMobile': true}),
        ],
      };
      final result = WebsiteCanvasMigration.migrate(document);
      expect(result.mergedStems, isEmpty);
      expect(
        result.issues.map((issue) => issue.code),
        contains(WebsiteCanvasMigrationIssueCode.missingPair),
      );
    });

    test('tipos incompatibles', () {
      expectUnchanged(
        pairWith(
          desktopExtra: const <String, dynamic>{},
          mobileExtra: const <String, dynamic>{},
          mobileType: 'button',
        ),
        WebsiteCanvasMigrationIssueCode.incompatibleType,
      );
    });

    test('visibilidad no complementaria', () {
      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          layer('hero_desktop'),
          layer('hero_mobile', extra: <String, dynamic>{'showOnMobile': true}),
        ],
      };
      expectUnchanged(
        document,
        WebsiteCanvasMigrationIssueCode.nonComplementaryVisibility,
      );
    });

    test('un orden base en conflicto sí es ambiguo', () {
      // Dos autoridades para el mismo z-order: la posición en la lista y una
      // clave `order` guardada. No se elige una en silencio.
      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          layer(
            'hero_desktop',
            extra: <String, dynamic>{'hideOnMobile': true, 'order': 5},
          ),
          layer('hero_mobile', extra: <String, dynamic>{'showOnMobile': true}),
        ],
      };
      final before = Map<String, dynamic>.from(document);
      final result = WebsiteCanvasMigration.migrate(document);
      expect(result.changed, isFalse);
      expect(result.document, before);
      final issue = result.issues.single;
      expect(issue.code, WebsiteCanvasMigrationIssueCode.uncertainOrder);
      expect(issue.propertyKey, 'order');
    });

    test('un par ambiguo no impide migrar a los demás', () {
      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          layer(
            'ok_desktop',
            extra: <String, dynamic>{'text': 'Igual', 'hideOnMobile': true},
          ),
          layer(
            'bad_desktop',
            extra: <String, dynamic>{'text': 'Uno', 'hideOnMobile': true},
          ),
          layer(
            'ok_mobile',
            extra: <String, dynamic>{
              'text': 'Igual',
              'x': 12.0,
              'showOnMobile': true,
            },
          ),
          layer(
            'bad_mobile',
            extra: <String, dynamic>{'text': 'Otro', 'showOnMobile': true},
          ),
        ],
      };
      final result = WebsiteCanvasMigration.migrate(document);
      expect(result.mergedStems, <String>['ok']);
      expect(
        result.issues.single.code,
        WebsiteCanvasMigrationIssueCode.differingSharedValue,
      );
      final ids = elementsOf(result.document).map((item) => item['id']);
      expect(ids, contains('ok'));
      expect(ids, containsAll(<String>['bad_desktop', 'bad_mobile']));
    });
  });

  group('F · marcador canónico, filtrado estricto e identidad', () {
    test('una pareja idéntica migrada usa 600/900 aunque no deje overrides',
        () {
      // Gemelos con TODO igual: la fusión no deja ningún override y la
      // normalización quita el contenedor vacío. Sin marcador propio, este
      // documento volvería a las bandas heredadas.
      final legacy = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          layer(
            'hero_desktop',
            extra: <String, dynamic>{'text': 'Igual', 'hideOnMobile': true},
          ),
          layer(
            'hero_mobile',
            extra: <String, dynamic>{'text': 'Igual', 'showOnMobile': true},
          ),
        ],
      };
      final migrated = WebsiteCanvasMigration.migrate(legacy).document;
      final merged = elementsOf(migrated).single;
      expect(merged.containsKey('responsive'), isFalse);
      expect(merged['visible'], isTrue);
      expect(
        migrated[WebsiteCanvasResponsiveDocument.schemaVersionKey],
        WebsiteCanvasResponsiveDocument.schemaVersion,
      );

      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(migrated, 620),
        WebsiteViewport.tablet,
      );
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(migrated, 1000),
        WebsiteViewport.desktop,
      );
      // El heredado original sigue en 640/1024.
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(legacy, 620),
        WebsiteViewport.mobile,
      );
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(legacy, 1000),
        WebsiteViewport.tablet,
      );

      // Y la vuelta lo deja exactamente como estaba, sin marcador.
      expect(WebsiteCanvasMigration.expandToLegacy(migrated), legacy);
    });

    test('un Canvas canónico nativo sin overrides se declara', () {
      final native = <String, dynamic>{
        'designWidth': 1200.0,
        'elements': <Map<String, dynamic>>[
          layer('a', extra: <String, dynamic>{'visible': true}),
        ],
      };
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(native, 620),
        WebsiteViewport.mobile,
        reason: 'sin marcador ni overrides, todavía es heredado',
      );

      final marked = WebsiteCanvasResponsiveDocument.markCanonical(native);
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(marked, 620),
        WebsiteViewport.tablet,
      );
      expect(
        WebsiteCanvasResponsiveDocument.viewportForCanvasWidth(marked, 1000),
        WebsiteViewport.desktop,
      );
      // La normalización conserva el marcador.
      expect(
        WebsiteCanvasResponsiveDocument.normalize(
          marked,
        )[WebsiteCanvasResponsiveDocument.schemaVersionKey],
        WebsiteCanvasResponsiveDocument.schemaVersion,
      );
      // Y no se fabrica un contenedor vacío para simularlo.
      expect(
        WebsiteCanvasResponsiveDocument.normalize(marked)
            .containsKey('responsive'),
        isFalse,
      );
    });

    test('un override desconocido no sobrevive, ni en raíz ni en capa', () {
      final data = <String, dynamic>{
        'designWidth': 1200.0,
        'futureUnknown': 'valor legítimo',
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{
            'designWidth': 390.0,
            'futureUnknown': 'no clasificado',
          },
        },
        'elements': <Map<String, dynamic>>[
          layer(
            'a',
            extra: <String, dynamic>{
              'text': 'Hola',
              'algoNuevo': 'valor de capa',
              'responsive': <String, dynamic>{
                'version': 2,
                'mobile': <String, dynamic>{
                  'fontSize': 20.0,
                  'algoNuevo': 'no clasificado',
                  'text': 'copy móvil',
                },
              },
            },
          ),
        ],
      };

      final normalized = WebsiteCanvasResponsiveDocument.normalize(data);
      final rootMobile = (normalized['responsive'] as Map)['mobile'] as Map;
      expect(rootMobile['designWidth'], 390.0);
      expect(rootMobile.containsKey('futureUnknown'), isFalse);
      expect(
        normalized['futureUnknown'],
        'valor legítimo',
        reason: 'su valor compartido es autoral y no se toca',
      );

      final layerData = elementsOf(normalized).single;
      final layerMobile = (layerData['responsive'] as Map)['mobile'] as Map;
      expect(layerMobile['fontSize'], 20.0);
      expect(layerMobile.containsKey('algoNuevo'), isFalse);
      expect(
        layerMobile.containsKey('text'),
        isFalse,
        reason: 'el copy es compartido por política',
      );
      expect(layerData['algoNuevo'], 'valor de capa');

      // Y la proyección tampoco resuelve lo desconocido por viewport.
      final mobile = WebsiteCanvasResponsiveDocument.project(
        data: data,
        viewport: WebsiteViewport.mobile,
      );
      expect(mobile['futureUnknown'], 'valor legítimo');
    });

    test('el orden base no se puede escribir como valor compartido', () {
      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[layer('a'), layer('b')],
      };

      for (final (scope, viewport)
          in const <(WebsiteWriteScope, WebsiteViewport)>[
        (WebsiteWriteScope.shared, WebsiteViewport.mobile),
        (WebsiteWriteScope.viewport, WebsiteViewport.desktop),
        (WebsiteWriteScope.shared, WebsiteViewport.desktop),
      ]) {
        expect(
          () => WebsiteCanvasResponsiveDocument.setLayerProperty(
            data: document,
            layerId: 'b',
            key: 'order',
            value: 0,
            scope: scope,
            viewport: viewport,
          ),
          throwsA(isA<StateError>()),
          reason: '$scope/$viewport',
        );
      }

      // El override por viewport sí es válido.
      final written = WebsiteCanvasResponsiveDocument.setLayerProperty(
        data: document,
        layerId: 'b',
        key: 'order',
        value: 0,
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      );
      final target = elementsOf(written)[1];
      expect(((target['responsive'] as Map)['mobile'] as Map)['order'], 0);
      expect(target.containsKey('order'), isFalse);
      expect(
        WebsiteCanvasResponsiveDocument.projectLayers(
          data: written,
          viewport: WebsiteViewport.mobile,
        ).map((item) => item.id),
        <String>['b', 'a'],
      );
    });

    test('la geometría inválida se rechaza antes de un patch parcial', () {
      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[layer('a')],
      };
      final baseline = <String, dynamic>{
        'elements': <Map<String, dynamic>>[layer('a')],
      };

      for (final values in <Map<String, Object?>>[
        <String, Object?>{'x': double.nan},
        <String, Object?>{'y': double.infinity},
        <String, Object?>{'rotation': double.negativeInfinity},
        <String, Object?>{'w': 0.0},
        <String, Object?>{'h': -1.0},
        <String, Object?>{'x': '10'},
        <String, Object?>{'x': 300.0, 'w': 0.0},
      ]) {
        expect(
          () => WebsiteCanvasResponsiveDocument.setLayerProperties(
            data: document,
            layerId: 'a',
            values: values,
            scope: WebsiteWriteScope.shared,
            viewport: WebsiteViewport.desktop,
          ),
          throwsA(isA<StateError>()),
          reason: '$values',
        );
        expect(document, baseline, reason: '$values must not mutate input');
      }

      final small = WebsiteCanvasResponsiveDocument.setLayerProperties(
        data: document,
        layerId: 'a',
        values: const <String, Object?>{'w': 24.0, 'h': 24.0},
        scope: WebsiteWriteScope.shared,
        viewport: WebsiteViewport.desktop,
      );
      expect(elementsOf(small).single['w'], 24.0);
      expect(elementsOf(small).single['h'], 24.0);
    });

    test('un marcador preexistente vuelve exactamente como estaba', () {
      // El documento ya se declaraba canónico Y traía un alias heredado: la
      // migración absorbe el alias, pero no puede quedarse con el marcador
      // ajeno ni borrarlo al revertir.
      final document = <String, dynamic>{
        WebsiteCanvasResponsiveDocument.schemaVersionKey: 2,
        'designWidth': 1200.0,
        'mobileDesignWidth': 390.0,
        'elements': <Map<String, dynamic>>[
          layer(
            'hero_desktop',
            extra: <String, dynamic>{'text': 'Igual', 'hideOnMobile': true},
          ),
          layer(
            'hero_mobile',
            extra: <String, dynamic>{
              'text': 'Igual',
              'x': 12.0,
              'showOnMobile': true,
            },
          ),
        ],
      };

      final result = WebsiteCanvasMigration.migrate(document);
      expect(result.changed, isTrue);
      expect(result.mergedStems, <String>['hero']);
      expect(
        result.document[WebsiteCanvasResponsiveDocument.schemaVersionKey],
        2,
      );
      final marker = (result.document[WebsiteCanvasMigration.provenanceKey]
          as Map)['marker'] as Map;
      expect(marker['present'], isTrue);
      expect(marker['created'], isFalse);
      expect(marker['value'], 2);

      expect(WebsiteCanvasMigration.expandToLegacy(result.document), document);

      // Y cuando la migración SÍ lo creó, la vuelta lo retira.
      final unmarked = Map<String, dynamic>.from(document)
        ..remove(WebsiteCanvasResponsiveDocument.schemaVersionKey);
      final created = WebsiteCanvasMigration.migrate(unmarked);
      expect(
        ((created.document[WebsiteCanvasMigration.provenanceKey]
            as Map)['marker'] as Map)['created'],
        isTrue,
      );
      expect(
        WebsiteCanvasMigration.expandToLegacy(created.document),
        unmarked,
      );
    });

    test('un marcador con valor futuro tampoco se pisa', () {
      final document = <String, dynamic>{
        WebsiteCanvasResponsiveDocument.schemaVersionKey: 7,
        'designWidth': 1200.0,
        'mobileFocalPointX': 0.9,
        'focalPointX': 0.5,
        'elements': <Map<String, dynamic>>[layer('a')],
      };
      final migrated = WebsiteCanvasMigration.migrate(document).document;
      expect(
        migrated[WebsiteCanvasResponsiveDocument.schemaVersionKey],
        7,
        reason: 'el marcador es dato del documento, no del migrador',
      );
      expect(WebsiteCanvasMigration.expandToLegacy(migrated), document);
    });

    test('escribir una capa inexistente o duplicada falla cerrado', () {
      final duplicated = <String, dynamic>{
        'elements': <Map<String, dynamic>>[layer('a'), layer('a')],
      };
      expect(
        () => WebsiteCanvasResponsiveDocument.setLayerProperty(
          data: duplicated,
          layerId: 'a',
          key: 'x',
          value: 1.0,
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        throwsA(isA<StateError>()),
      );

      final document = <String, dynamic>{
        'elements': <Map<String, dynamic>>[layer('a')],
      };
      expect(
        () => WebsiteCanvasResponsiveDocument.setLayerProperty(
          data: document,
          layerId: 'no-existe',
          key: 'x',
          value: 1.0,
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => WebsiteCanvasResponsiveDocument.clearLayerOverride(
          data: document,
          layerId: 'no-existe',
          key: 'x',
          viewport: WebsiteViewport.mobile,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('escribir sobre una identidad inválida falla cerrado', () {
      // El id existe y es único como cadena exacta, pero el documento no
      // cumple el contrato: el escritor no puede ser más permisivo que la
      // migración que lo respalda.
      final blank = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          layer(''),
          layer('b'),
        ],
      };
      final blankSnapshot = elementsOf(blank);
      expect(
        () => WebsiteCanvasResponsiveDocument.setLayerProperty(
          data: blank,
          layerId: '',
          key: 'x',
          value: 99.0,
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        throwsA(isA<StateError>()),
      );
      expect(elementsOf(blank), blankSnapshot, reason: 'nada se mutó');

      // `'a'` y `' a '` son la misma identidad canónica.
      final normalizedDuplicate = <String, dynamic>{
        'elements': <Map<String, dynamic>>[
          layer('a'),
          layer(' a '),
        ],
      };
      final duplicateSnapshot = elementsOf(normalizedDuplicate);
      expect(
        () => WebsiteCanvasResponsiveDocument.setLayerProperty(
          data: normalizedDuplicate,
          layerId: 'a',
          key: 'x',
          value: 99.0,
          scope: WebsiteWriteScope.shared,
          viewport: WebsiteViewport.desktop,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => WebsiteCanvasResponsiveDocument.clearLayerOverride(
          data: normalizedDuplicate,
          layerId: 'a',
          key: 'x',
          viewport: WebsiteViewport.mobile,
        ),
        throwsA(isA<StateError>()),
      );
      expect(elementsOf(normalizedDuplicate), duplicateSnapshot);

      // Y la migración usa la misma semántica: tampoco los fusiona.
      expect(
        WebsiteCanvasMigration.migrate(normalizedDuplicate)
            .issues
            .map((issue) => issue.code),
        contains(WebsiteCanvasMigrationIssueCode.conflictingIdentity),
      );
    });

    test('un id en blanco detiene la migración de capas', () {
      final document = <String, dynamic>{
        'mobileDesignWidth': 390.0,
        'designWidth': 1200.0,
        'elements': <Map<String, dynamic>>[
          layer('', extra: <String, dynamic>{'hideOnMobile': true}),
          layer('hero_desktop', extra: <String, dynamic>{'hideOnMobile': true}),
          layer('hero_mobile', extra: <String, dynamic>{'showOnMobile': true}),
        ],
      };
      final result = WebsiteCanvasMigration.migrate(document);

      expect(result.mergedStems, isEmpty);
      expect(
        result.issues.map((issue) => issue.code),
        contains(WebsiteCanvasMigrationIssueCode.conflictingIdentity),
      );
      // Las capas quedan intactas…
      expect(elementsOf(result.document), elementsOf(document));
      // …pero los alias de raíz sí se absorben: su reversibilidad no depende
      // de ninguna capa.
      expect(result.changed, isTrue);
      expect(result.document.containsKey('mobileDesignWidth'), isFalse);
      expect(
        ((result.document['responsive'] as Map)['mobile']
            as Map)['designWidth'],
        390.0,
      );
      expect(
        WebsiteCanvasMigration.expandToLegacy(result.document),
        document,
      );
    });
  });

  group('E · pureza, saneamiento e inventario', () {
    test('ni la proyección ni la migración mutan la entrada', () {
      final canonical = canonicalDocument();
      final snapshot = canonicalDocument();
      WebsiteCanvasResponsiveDocument.project(
        data: canonical,
        viewport: WebsiteViewport.mobile,
      );
      WebsiteCanvasResponsiveDocument.setLayerProperty(
        data: canonical,
        layerId: 'hero-title',
        key: 'x',
        value: 999.0,
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      );
      WebsiteCanvasMigration.migrate(canonical);
      expect(canonical, snapshot);

      // La proyección tampoco comparte referencias con la entrada.
      final projected = WebsiteCanvasResponsiveDocument.project(
        data: canonical,
        viewport: WebsiteViewport.mobile,
      );
      final projectedLayer =
          (projected['elements'] as List).first as Map<String, dynamic>;
      projectedLayer['x'] = -1.0;
      projectedLayer['text'] = 'mutado';
      expect(elementsOf(canonical).first['x'], 24.0);
      expect(elementsOf(canonical).first['text'], 'Somos Vinabike');
    });

    test('el saneador limpia el contenedor responsive de raíz y de capa', () {
      final data = <String, dynamic>{
        'activeElementId': 'sel-1',
        'designWidth': 1200.0,
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{
            'activeElementId': 'sel-2',
            'designWidth': 1200.0,
          },
          'tablet': <String, dynamic>{},
        },
        'elements': <Map<String, dynamic>>[
          layer(
            'hero-title',
            extra: <String, dynamic>{
              'activeElementId': 'element-owned-value',
              'text': 'Hola',
              'responsive': <String, dynamic>{
                'version': 2,
                'mobile': <String, dynamic>{
                  'activeElementId': 'sel-3',
                  'x': 24.0,
                  'text': 'Copy móvil',
                  'fontSize': 28.0,
                },
              },
            },
          ),
        ],
      };

      final sanitized = sanitizeWebsiteBlockDataForPersistence(
        blockType: 'canvas',
        data: data,
      );

      expect(sanitized.containsKey('activeElementId'), isFalse);
      expect(
        sanitized.containsKey('responsive'),
        isFalse,
        reason: 'sin selección ni override distinto, el contenedor entero se '
            'va: no quedan mapas vacíos',
      );
      final sanitizedLayer = elementsOf(sanitized).single;
      expect(
        sanitizedLayer['activeElementId'],
        'element-owned-value',
        reason: 'dentro de una capa es contenido autoral, no selección',
      );
      final override = (sanitizedLayer['responsive'] as Map)['mobile'] as Map;
      expect(override.containsKey('activeElementId'), isFalse);
      expect(
        override.containsKey('text'),
        isFalse,
        reason: 'el copy es compartido: no puede vivir en un override',
      );
      expect(override.containsKey('x'), isFalse, reason: 'igual a la base');
      expect(override['fontSize'], 28.0);
    });

    test('un slide de carrusel con Canvas usa el mismo owner', () {
      // El payload de un slide es un documento Canvas más sus propias claves:
      // la misma proyección lo resuelve sin conocer al carrusel.
      final slide = <String, dynamic>{
        'title': 'Slide con capas',
        'imageUrl': 'https://cdn/slide.webp',
        'designWidth': 1200.0,
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{'designWidth': 390.0},
        },
        'elements': <Map<String, dynamic>>[
          layer(
            'slide-title',
            extra: <String, dynamic>{
              'text': 'Servicio técnico',
              'fontSize': 44.0,
              'responsive': <String, dynamic>{
                'version': 2,
                'mobile': <String, dynamic>{'fontSize': 26.0, 'x': 12.0},
              },
            },
          ),
        ],
      };

      final mobile = WebsiteCanvasResponsiveDocument.project(
        data: slide,
        viewport: WebsiteViewport.mobile,
      );
      expect(mobile['designWidth'], 390.0);
      expect(
        mobile['title'],
        'Slide con capas',
        reason: 'las claves propias del slide viajan intactas',
      );
      expect(mobile['imageUrl'], 'https://cdn/slide.webp');
      final mobileLayer = elementsOf(mobile).single;
      expect(mobileLayer['fontSize'], 26.0);
      expect(mobileLayer['x'], 12.0);
      expect(mobileLayer['text'], 'Servicio técnico');

      final desktop = WebsiteCanvasResponsiveDocument.project(
        data: slide,
        viewport: WebsiteViewport.desktop,
      );
      expect(desktop['designWidth'], 1200.0);
      expect(elementsOf(desktop).single['fontSize'], 44.0);
    });

    test('el saneador alcanza las capas de un slide de carrusel', () {
      final sanitized = sanitizeWebsiteBlockDataForPersistence(
        blockType: 'carousel',
        data: <String, dynamic>{
          'slides': <Map<String, dynamic>>[
            <String, dynamic>{
              'activeElementId': 'sel-1',
              'title': 'Slide',
              'elements': <Map<String, dynamic>>[
                layer(
                  'slide-title',
                  extra: <String, dynamic>{
                    'text': 'Hola',
                    'responsive': <String, dynamic>{
                      'version': 2,
                      'mobile': <String, dynamic>{
                        'activeElementId': 'sel-2',
                        'text': 'Copy móvil',
                        'fontSize': 22.0,
                      },
                      'tablet': <String, dynamic>{},
                    },
                  },
                ),
              ],
            },
          ],
        },
      );

      final slide = Map<String, dynamic>.from(
        (sanitized['slides'] as List).single as Map,
      );
      expect(slide.containsKey('activeElementId'), isFalse);
      final override =
          ((slide['elements'] as List).single as Map)['responsive'] as Map;
      final mobile = override['mobile'] as Map;
      expect(override.containsKey('tablet'), isFalse);
      expect(mobile.containsKey('activeElementId'), isFalse);
      expect(mobile.containsKey('text'), isFalse);
      expect(mobile['fontSize'], 22.0);
    });

    test('la colección de capas nunca puede ser un override', () {
      expect(
        WebsiteCanvasResponsivePolicy.rootPolicyFor('elements'),
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );
      final attempted = WebsiteCanvasResponsiveDocument.setRootProperty(
        data: canonicalDocument(),
        key: 'elements',
        value: <Map<String, dynamic>>[layer('intruso')],
        scope: WebsiteWriteScope.viewport,
        viewport: WebsiteViewport.mobile,
      );
      expect(
        (attempted['responsive'] as Map)['mobile'],
        isNot(contains('elements')),
      );
      expect(elementsOf(attempted).single['id'], 'intruso',
          reason: 'se escribió como base, que es su única autoridad');
    });

    test('inventario de políticas por tipo de capa', () {
      const expected = <WebsiteCanvasLayerKind, (Set<String>, Set<String>)>{
        WebsiteCanvasLayerKind.text: (
          <String>{'text', 'fontRole'},
          <String>{
            'fontSize',
            'fontWeight',
            'color',
            'align',
            'letterSpacing',
            'lineHeight',
            'uppercase',
          },
        ),
        WebsiteCanvasLayerKind.button: (
          <String>{'label', 'link'},
          <String>{
            'style',
            'inheritTheme',
            'bgColor',
            'fgColor',
            'radius',
            'fontSize',
            'letterSpacing',
            'uppercase',
            'shadow',
          },
        ),
        WebsiteCanvasLayerKind.image: (
          <String>{'productId', 'imageSource', 'altText'},
          <String>{'imageUrl', 'fit', 'radius', 'focalPointX', 'focalPointY'},
        ),
        WebsiteCanvasLayerKind.shape: (
          <String>{'shape'},
          <String>{'fillColor', 'borderColor', 'borderWidth', 'radius'},
        ),
        WebsiteCanvasLayerKind.product: (
          <String>{'productId', 'showPrice'},
          <String>{},
        ),
        WebsiteCanvasLayerKind.productsGallery: (
          <String>{'mode', 'productIds', 'maxProducts', 'showPrice'},
          <String>{'layout', 'columns', 'cardWidth'},
        ),
      };

      for (final entry in expected.entries) {
        for (final key in entry.value.$1) {
          expect(
            WebsiteCanvasResponsivePolicy.layerPolicyFor(entry.key, key)
                .supportsViewportOverride,
            isFalse,
            reason: '${entry.key.name}.$key',
          );
        }
        for (final key in entry.value.$2) {
          expect(
            WebsiteCanvasResponsivePolicy.layerPolicyFor(entry.key, key)
                .supportsViewportOverride,
            isTrue,
            reason: '${entry.key.name}.$key',
          );
        }
        // Identidad y geometría comunes a todos los tipos.
        for (final key in const <String>['id', 'type', 'locked']) {
          expect(
            WebsiteCanvasResponsivePolicy.layerPolicyFor(entry.key, key),
            WebsiteResponsivePropertyPolicy.sharedOnly,
            reason: '${entry.key.name}.$key',
          );
        }
        for (final key in const <String>['x', 'y', 'w', 'h', 'rotation']) {
          expect(
            WebsiteCanvasResponsivePolicy.layerPolicyFor(entry.key, key),
            WebsiteResponsivePropertyPolicy.perViewportGeometry,
            reason: '${entry.key.name}.$key',
          );
        }
        expect(
          WebsiteCanvasResponsivePolicy.layerPolicyFor(entry.key, 'visible'),
          WebsiteResponsivePropertyPolicy.responsiveVisibility,
        );
        expect(
          WebsiteCanvasResponsivePolicy.layerPolicyFor(entry.key, 'anim'),
          WebsiteResponsivePropertyPolicy.responsiveOptional,
        );
        // Una clave desconocida jamás se vuelve responsive sola.
        expect(
          WebsiteCanvasResponsivePolicy.layerPolicyFor(
            entry.key,
            'algoNuevoDelFuturo',
          ),
          WebsiteResponsivePropertyPolicy.sharedOnly,
        );
      }
    });

    test('inventario de políticas de la raíz', () {
      const geometry = <String>[
        'designWidth',
        'blockHeight',
        'heightMode',
        'vhPct',
        'focalPointX',
        'focalPointY',
      ];
      const presentation = <String>[
        'backgroundColor',
        'backgroundImageUrl',
        'backgroundVideoUrl',
        'backgroundYoutubeId',
        'backgroundFit',
        'overlayEnabled',
        'overlayOpacity',
        'overlayColor',
        'fullBleed',
      ];
      const shared = <String>[
        'backgroundImageAltText',
        'showGrid',
        'gridSize',
        'snap',
        'snapDistance',
        'constrainElementsToSafeArea',
        'elements',
      ];

      for (final key in geometry) {
        expect(
          WebsiteCanvasResponsivePolicy.rootPolicyFor(key),
          WebsiteResponsivePropertyPolicy.perViewportGeometry,
          reason: key,
        );
      }
      for (final key in presentation) {
        expect(
          WebsiteCanvasResponsivePolicy.rootPolicyFor(key),
          WebsiteResponsivePropertyPolicy.responsiveOptional,
          reason: key,
        );
      }
      for (final key in shared) {
        expect(
          WebsiteCanvasResponsivePolicy.rootPolicyFor(key),
          WebsiteResponsivePropertyPolicy.sharedOnly,
          reason: key,
        );
      }
      expect(
        WebsiteCanvasResponsivePolicy.rootPolicyFor('otraClaveFutura'),
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );
    });
  });
}
