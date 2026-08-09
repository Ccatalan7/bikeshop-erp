import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';

/// El último lote de familias normales: Planes y Precios, Contacto y Footer.
///
/// Las tres cierran compartidas, y eso es el resultado del lote, no una tarea
/// pendiente: dos ya componen por ancho y la tercera ni siquiera dibuja sus
/// campos, porque el pie real de la tienda es chrome del sitio. Esta ronda no
/// introduce ningún valor visual ni control nuevo.
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
    WebsiteBlockType.pricing,
    WebsiteBlockType.contact,
    WebsiteBlockType.footer,
  ];

  String sourceOf(String path) => File(path).readAsStringSync();

  final pricingSource = sourceOf(
    'lib/modules/website/widgets/website_pricing_block_content.dart',
  );
  final contactSource = sourceOf(
    'lib/modules/website/widgets/website_contact_block_content.dart',
  );
  final rendererSource =
      sourceOf('lib/modules/website/widgets/website_block_renderer.dart');
  final storefrontSource =
      sourceOf('lib/public_store/widgets/public_store_layout.dart');

  group('A · matriz exacta de las tres familias', () {
    test('Pricing: negocio y auto-layout, sin una sola capacidad', () {
      final fields = flatFieldsOf(WebsiteBlockType.pricing);
      expect(
        fields.keys.toSet(),
        <String>{
          'title',
          'subtitle',
          'plans',
          'plans.name',
          'plans.price',
          'plans.ctaText',
          'plans.ctaLink',
          'plans.features',
          'plans.highlighted',
        },
      );
      for (final entry in fields.entries) {
        expect(
          entry.value.allowsViewportOverride,
          isFalse,
          reason: '${entry.key}: precio, beneficio, copy y destino son negocio',
        );
      }

      // La composición sale del ancho disponible, no de un dato guardado.
      expect(pricingSource, contains('final compact = availableWidth < 600'));
      expect(pricingSource, contains('final cardWidth ='));
      expect(
        pricingSource,
        isNot(contains("data['layout']")),
        reason: 'si algún día lee un layout, toca migrarlo en su ronda',
      );
      expect(fields.containsKey('layout'), isFalse);
      expect(fields.containsKey('columns'), isFalse);
    });

    test('Pricing: `highlighted` se evaluó y se quedó compartida', () {
      // El candidato: es presentación y el renderer lo lee. Pero lo lee IGUAL
      // en los tres anchos, así que un override no cambiaría la composición:
      // cambiaría qué plan recomienda la tienda según el dispositivo.
      final highlighted =
          fieldOf(WebsiteBlockType.pricing, 'plans.highlighted');
      expect(
        highlighted.responsivePolicy,
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );
      expect(highlighted.canResetResponsiveOverride, isFalse);
      expect(highlighted.migrationAliases, contains('isFeatured'));
      // Su consumer, para que este veredicto se pueda reevaluar con evidencia.
      expect(pricingSource,
          contains("const <String>['highlighted', 'isFeatured']"));
      expect(pricingSource, contains('elevation: highlighted ? 4 : 1'));
      expect(
        pricingSource,
        isNot(contains('compact ? highlighted')),
        reason: 'no hay ninguna rama por ancho que lo lea distinto',
      );
    });

    test('Contact: dos interruptores de disponibilidad, no de composición', () {
      final fields = flatFieldsOf(WebsiteBlockType.contact);
      expect(
        fields.keys.toSet(),
        <String>{'title', 'subtitle', 'showForm', 'showMap'},
      );
      for (final entry in fields.entries) {
        expect(entry.value.allowsViewportOverride, isFalse, reason: entry.key);
      }

      // El renderer ya resuelve tres composiciones por ancho…
      expect(contactSource, contains('_ContactLayout.resolve('));
      expect(contactSource, contains('availableWidth >= 1088'));
      expect(contactSource, contains('availableWidth >= 552'));
      // …y lee los interruptores una sola vez, sin mirar el ancho.
      expect(contactSource, contains("data['showForm'] != false"));
      expect(contactSource, contains("data['showMap'] == true"));
      expect(
        contactSource,
        isNot(contains('compact && showMap')),
        reason: 'ninguna rama por ancho los reinterpreta',
      );
    });

    test('Footer: el bloque de página no dibuja el pie', () {
      final fields = flatFieldsOf(WebsiteBlockType.footer);
      expect(
        fields.keys.toSet(),
        <String>{
          'companyName',
          'copyright',
          'columns',
          'columns.title',
          'columns.items',
          'columns.items.label',
          'columns.items.link',
        },
      );
      for (final entry in fields.entries) {
        expect(
          entry.value.allowsViewportOverride,
          isFalse,
          reason: '${entry.key}: no tiene consumer que pudiera honrarlo',
        );
      }

      // El renderer del bloque sólo reserva alto: ni marca, ni columnas, ni
      // enlaces salen de `block_data`.
      expect(
        rendererSource,
        matches(
          RegExp(
            r'case WebsiteBlockType\.footer:\s*'
            r'return const SizedBox\(height: 64\);',
          ),
        ),
      );
    });

    test('ninguna colección del lote se volvió responsive entera', () {
      for (final (type, key) in const <(WebsiteBlockType, String)>[
        (WebsiteBlockType.pricing, 'plans'),
        (WebsiteBlockType.footer, 'columns'),
        (WebsiteBlockType.footer, 'columns.items'),
      ]) {
        final field = fieldOf(type, key);
        expect(field.type, WebsiteBlockFieldType.repeater);
        expect(field.allowsViewportOverride, isFalse, reason: '$type.$key');
      }
    });

    test('el lote no habilitó display copy ni claves ocultas', () {
      for (final type in batch) {
        for (final entry in flatFieldsOf(type).entries) {
          expect(
            entry.value.responsivePolicy,
            isNot(WebsiteResponsivePropertyPolicy.responsiveDisplayCopy),
            reason: '$type.${entry.key}',
          );
        }
        // La matriz derivada no inventa propiedades: sólo las declaradas más
        // las sintéticas de un media field, que estas familias no tienen.
        final matrix = WebsiteBlockRegistry.responsivePolicyMatrix()[type]!;
        expect(
          matrix.keys.toSet(),
          flatFieldsOf(type).keys.toSet(),
          reason: '$type',
        );
      }
    });

    test('los aliases legacy del lote siguen declarados', () {
      expect(
        fieldOf(WebsiteBlockType.pricing, 'plans').migrationAliases,
        contains('items'),
      );
      expect(
        fieldOf(WebsiteBlockType.pricing, 'plans.ctaText').migrationAliases,
        contains('buttonText'),
      );
      expect(
        fieldOf(WebsiteBlockType.pricing, 'plans.ctaLink').migrationAliases,
        contains('buttonLink'),
      );
    });
  });

  group('B · la frontera del footer sitewide', () {
    test('el pie real lo compone el layout público desde los settings', () {
      // Un solo dueño: settings efectivos (pending→saved) y navegación, no
      // `block_data`.
      expect(storefrontSource, contains('getEffectiveFooterSetting('));
      expect(storefrontSource, contains('_buildMobileFooter('));
      // Y elige composición sólo por ancho.
      expect(storefrontSource, contains('final isMobile = screenWidth < 800'));
      expect(storefrontSource, contains('if (isMobile) {'));
    });

    test('el pie sitewide no lee el bloque de página', () {
      // Si algún día lo leyera habría dos dueños del mismo pie, que es
      // exactamente lo que este contrato impide.
      for (final blockKey in const <String>[
        "['companyName']",
        "['copyright']",
        "data['columns']",
      ]) {
        expect(
          storefrontSource,
          isNot(contains(blockKey)),
          reason:
              '$blockKey pertenece al bloque de página, no al pie del sitio',
        );
      }
    });

    test('la navegación del pie sigue siendo su propio owner editable', () {
      // El pie se edita por su ruta de siempre —selección y destino de cada
      // ítem de navegación—, no por el schema del bloque.
      expect(storefrontSource, contains('getEffectiveFooterNavItem('));
      expect(storefrontSource, contains('updateFooterNavDestination('));
      expect(storefrontSource, contains("editProvider.selectBlock('footer')"));
    });
  });

  group('C · projection: compartido en los tres viewports', () {
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

    test('un override plantado no cambia precio, beneficio ni destino', () {
      final document = <String, dynamic>{
        'title': 'Planes de Servicio',
        'subtitle': 'Elige tu plan',
        'plans': <Map<String, dynamic>>[
          {
            'name': 'Full Service',
            'price': '59.990',
            'features': <String>['Ajuste integral'],
            'ctaText': 'Reservar',
            'ctaLink': '/contacto',
            'highlighted': true,
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{
                'price': '9.990',
                'highlighted': false,
                'ctaLink': '/otro',
              },
            },
          },
          {
            'name': 'Básico',
            'price': '29.990',
            'features': <String>['Revisión de frenos'],
          },
        ],
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{'title': 'Planes móvil'},
        },
      };

      for (final viewport in WebsiteViewport.values) {
        final result = projected(WebsiteBlockType.pricing, document, viewport);
        expect(result['title'], 'Planes de Servicio', reason: '$viewport');
        final plans = (result['plans'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        expect(plans[0]['price'], '59.990', reason: '$viewport');
        expect(plans[0]['highlighted'], isTrue, reason: '$viewport');
        expect(plans[0]['ctaLink'], '/contacto', reason: '$viewport');
        expect(plans[0]['features'], <String>['Ajuste integral']);
        // El hermano nunca se contamina.
        expect(plans[1]['price'], '29.990');
        expect(plans[1].containsKey('responsive'), isFalse);
      }
    });

    test('Contacto y Footer proyectan lo mismo en los tres viewports', () {
      final contact = <String, dynamic>{
        'title': 'Contáctanos',
        'subtitle': 'Respondemos en 24h',
        'showForm': true,
        'showMap': false,
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{'showForm': false, 'showMap': true},
          'tablet': <String, dynamic>{'title': 'Escríbenos'},
        },
      };
      final footer = <String, dynamic>{
        'companyName': 'Vinabike',
        'copyright': '© 2026 Vinabike',
        'columns': <Map<String, dynamic>>[
          {
            'title': 'Contacto',
            'items': <Map<String, dynamic>>[
              {'label': '+56 9 1234 5678', 'link': 'tel:+56912345678'},
            ],
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{'title': 'Otra columna'},
            },
          },
        ],
      };

      for (final viewport in WebsiteViewport.values) {
        final result = projected(WebsiteBlockType.contact, contact, viewport);
        expect(result['showForm'], isTrue, reason: '$viewport');
        expect(result['showMap'], isFalse, reason: '$viewport');
        expect(result['title'], 'Contáctanos', reason: '$viewport');

        final columns =
            (projected(WebsiteBlockType.footer, footer, viewport)['columns']
                    as List)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList(growable: false);
        expect(columns.single['title'], 'Contacto', reason: '$viewport');
        final links = (columns.single['items'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        expect(links.single['link'], 'tel:+56912345678');
      }
    });

    test('listas vacías y alias de colección sobreviven la proyección', () {
      final legacyPricing = <String, dynamic>{
        'items': <Map<String, dynamic>>[
          {'name': 'Plan heredado', 'price': '10.000'},
        ],
      };
      final emptyFooter = <String, dynamic>{
        'companyName': 'Vinabike',
        'columns': <Map<String, dynamic>>[],
      };
      for (final viewport in WebsiteViewport.values) {
        final plans = (projected(
                    WebsiteBlockType.pricing, legacyPricing, viewport)['plans']
                as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
        expect(plans.single['name'], 'Plan heredado', reason: '$viewport');
        expect(
          projected(WebsiteBlockType.footer, emptyFooter, viewport)['columns'],
          isEmpty,
        );
      }
    });
  });
}
