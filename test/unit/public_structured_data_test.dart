import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/models/public_business_hours.dart';
import 'package:vinabike_erp/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_erp/public_store/models/public_product_spec_sheet.dart';
import 'package:vinabike_erp/public_store/seo/public_business_structured_data.dart';
import 'package:vinabike_erp/public_store/seo/public_product_structured_data.dart';

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

/// Lo que se le declara a Google del producto y del negocio (2026-10-04).
void main() {
  const storeUrl = 'https://vinabike.cl';

  PublicCommerceProductProjection commerce({
    String description = '',
    List<String> images = const ['https://cdn.test/a.jpg'],
  }) =>
      PublicCommerceProductProjection.fromJson({
        'id': 'p1',
        'sku': 'S56467',
        'name': 'Aceite mineral Shimano',
        'description': description,
        'price': 8990,
        'price_currency': 'CLP',
        'track_stock': true,
        'stock_quantity': 3,
        'website_image_urls': images,
        'brand': 'Shimano',
        'category_id': 'c1',
      }, categoryPath: 'Mantención / Lubricantes');

  Map<String, dynamic> productNode(Map<String, dynamic> data) =>
      (data['@graph'] as List).first as Map<String, dynamic>;

  group('ficha de producto', () {
    test('declara la ficha técnica publicada, no la identidad repetida', () {
      final sheet = PublicProductSpecSheet.build(
        rows: const [
          PublicProductSpecRow(
            sectionKey: 'primary',
            key: 'fluid_type',
            label: 'Tipo de líquido',
            value: 'Aceite mineral',
          ),
          PublicProductSpecRow(
            sectionKey: 'measurement',
            key: 'volume_ml',
            label: 'Volumen',
            value: '50',
            unit: 'ml',
            dataType: 'number',
          ),
        ],
        identity: const PublicSpecIdentity(
          brand: 'Shimano',
          model: 'SM-DB-OIL',
          manufacturerSku: 'Y83998020',
        ),
      );

      final data = buildPublicProductStructuredData(
        commerce: commerce(),
        productUrl: '$storeUrl/productos/aceite/S56467',
        storeUrl: storeUrl,
        storeName: 'Viñabike',
        specSheet: sheet,
        model: 'SM-DB-OIL',
      )!;
      final product = productNode(data);
      final properties = (product['additionalProperty'] as List)
          .map((property) => '${property['name']}=${property['value']}')
          .toList();

      expect(properties, contains('Tipo de líquido=Aceite mineral'));
      expect(properties.any((entry) => entry.startsWith('Volumen=50')), isTrue);
      expect(properties.any((entry) => entry.startsWith('Marca=')), isFalse,
          reason: 'la marca ya va en brand');
      expect(product['model'], 'SM-DB-OIL');
      expect(product['brand'], {'@type': 'Brand', 'name': 'Shimano'});
    });

    test('la descripción sólo se declara cuando el producto la tiene', () {
      final without = productNode(buildPublicProductStructuredData(
        commerce: commerce(),
        productUrl: '$storeUrl/productos/aceite/S56467',
        storeUrl: storeUrl,
        storeName: 'Viñabike',
      )!);
      final withText = productNode(buildPublicProductStructuredData(
        commerce: commerce(description: '<p>Para frenos   Shimano.</p>'),
        productUrl: '$storeUrl/productos/aceite/S56467',
        storeUrl: storeUrl,
        storeName: 'Viñabike',
      )!);

      expect(without.containsKey('description'), isFalse);
      expect(withText['description'], 'Para frenos Shimano.');
      expect(without.containsKey('additionalProperty'), isFalse);
    });

    test('las migas siguen el recorrido visible de la ficha', () {
      final data = buildPublicProductStructuredData(
        commerce: commerce(),
        productUrl: '$storeUrl/productos/aceite/S56467',
        storeUrl: storeUrl,
        storeName: 'Viñabike',
        categoryTrail: const [
          PublicStructuredDataCrumb(
              'Mantención', '$storeUrl/productos/categoria/mantencion'),
          PublicStructuredDataCrumb(
              'Lubricantes', '$storeUrl/productos/categoria/lubricantes'),
        ],
      )!;
      final crumbs = ((data['@graph'] as List)[1]['itemListElement'] as List)
          .map((item) => '${item['position']}:${item['name']}')
          .toList();

      expect(crumbs, [
        '1:Inicio',
        '2:Productos',
        '3:Mantención',
        '4:Lubricantes',
        '5:Aceite mineral Shimano',
      ]);
    });

    test('sin imagen no hay ficha que declarar', () {
      expect(
        buildPublicProductStructuredData(
          commerce: commerce(images: const []),
          productUrl: '$storeUrl/productos/aceite/S56467',
          storeUrl: storeUrl,
          storeName: 'Viñabike',
        ),
        isNull,
      );
    });

    test('un texto con </script> no cierra el elemento', () {
      final encoded = encodeStructuredDataForHtml({'name': 'a</script><b>'});
      expect(encoded, isNot(contains('</script>')));
      expect(jsonDecode(encoded), {'name': 'a</script><b>'});
    });
  });

  group('horario', () {
    test('lee el formato de Google Places y el de Google Business', () {
      final places = parsePublicBusinessHours(jsonEncode({
        'periods': [
          {
            'open': {'day': 1, 'time': '1030'},
            'close': {'day': 1, 'time': '1900'},
          },
          {
            'open': {'day': 0, 'time': '1000'},
            'close': {'day': 0, 'time': '1400'},
          },
        ],
      }));
      final business = parsePublicBusinessHours(jsonEncode({
        'opening_hours': {
          'periods': [
            {
              'openDay': 'SATURDAY',
              'openTime': {'hours': 10, 'minutes': 30},
              'closeTime': {'hours': 15, 'minutes': 30},
            },
          ],
        },
      }));

      expect(places.map((p) => '${p.day} ${p.opens}-${p.closes}'),
          ['MONDAY 10:30-19:00', 'SUNDAY 10:00-14:00']);
      expect(business.single.day, 'SATURDAY');
      expect(business.single.opens, '10:30');
      expect(parsePublicBusinessHours('no es json'), isEmpty);
    });

    test('los días con el mismo horario van juntos', () {
      final spec = openingHoursSpecificationFor([
        for (final day in ['MONDAY', 'TUESDAY', 'WEDNESDAY'])
          PublicBusinessHoursPeriod(day: day, opens: '10:30', closes: '19:00'),
        const PublicBusinessHoursPeriod(
            day: 'SATURDAY', opens: '10:30', closes: '15:30'),
      ]);

      expect(spec, hasLength(2));
      expect(spec.first['dayOfWeek'], [
        'https://schema.org/Monday',
        'https://schema.org/Tuesday',
        'https://schema.org/Wednesday',
      ]);
      expect(spec.last['closes'], '15:30');
    });
  });

  group('negocio', () {
    final tiers = [
      PublicShippingTier.fromRow({
        'country_code': 'CL',
        'min_order_gross': '0.00',
        'max_order_gross': '30000.00',
        'shipping_gross': '6990.00',
        'estimated_min_business_days': 3,
        'estimated_max_business_days': 12,
      }),
      PublicShippingTier.fromRow({
        'country_code': 'CL',
        'min_order_gross': '150000.00',
        'max_order_gross': null,
        'shipping_gross': '14990.00',
        'estimated_min_business_days': 3,
        'estimated_max_business_days': 12,
      }),
    ];

    test('el envío sale de los tramos que cobra el checkout', () {
      final node = completePublicBusinessStructuredData(
        {'@type': 'BikeStore', 'name': 'Viñabike'},
        logoUrl: '',
        imageUrl: '',
        mapUrl: '',
        hours: const [],
        shippingTiers: tiers,
        currency: 'CLP',
        pickupCountryCode: 'CL',
        returnPolicyUrl: '',
      );
      final services = node['hasShippingService'] as List;
      final delivery = services.first as Map;
      final conditions = delivery['shippingConditions'] as List;

      expect(conditions.first['orderValue'], {
        '@type': 'MonetaryAmount',
        'currency': 'CLP',
        'minValue': 0,
        'maxValue': 29999
      });
      expect(conditions.first['shippingRate']['value'], 6990);
      expect(conditions.last['orderValue'].containsKey('maxValue'), isFalse);
      expect(conditions.first['transitTime']['duration']['maxValue'], 12);
      expect(services.last['fulfillmentType'],
          'https://schema.org/FulfillmentTypeCollectionPoint');
      expect(
          services.last['shippingConditions'].single['shippingRate']['value'],
          0);
      expect(node.containsKey('hasMerchantReturnPolicy'), isFalse,
          reason: 'sin página publicada no hay política que enlazar');
    });

    test('la devolución enlaza la página publicada y nada más', () {
      final node = completePublicBusinessStructuredData(
        {'@type': 'BikeStore', 'name': 'Viñabike'},
        logoUrl: '$storeUrl/assets/logo.webp',
        imageUrl: '',
        mapUrl: 'https://maps.google.com/?cid=1',
        hours: const [],
        shippingTiers: const [],
        currency: 'CLP',
        pickupCountryCode: '',
        returnPolicyUrl: '$storeUrl/devoluciones',
      );

      expect(node['hasMerchantReturnPolicy'], {
        '@type': 'MerchantReturnPolicy',
        'merchantReturnLink': '$storeUrl/devoluciones',
      });
      expect(node['logo'], '$storeUrl/assets/logo.webp');
      expect(node['hasMap'], 'https://maps.google.com/?cid=1');
      expect(node.containsKey('hasShippingService'), isFalse);
    });

    test('el build completa el nodo del shell sin tocar su identidad', () {
      const shell = '<html><head>'
          '<script type="application/ld+json">'
          '{"@context":"https://schema.org","@type":"BikeStore",'
          '"name":"Viñabike","telephone":"+56 9 9835 7797"}'
          '</script></head><body></body></html>';

      final html = snapshots.completeSeoBusinessJsonLd(
        shell,
        settings: {
          'business_hours_json': jsonEncode({
            'periods': [
              {
                'open': {'day': 6, 'time': '1030'},
                'close': {'day': 6, 'time': '1530'},
              },
            ],
          }),
          'seo_og_image': '$storeUrl/portada.jpg',
        },
        storeUrl: storeUrl,
        tenantId: 'otro-tenant',
        tenantLogoUrl: null,
        shippingTiers: tiers,
        returnPolicyPublished: true,
      );
      final json = RegExp(r'<script[^>]*>(.*?)</script>', dotAll: true)
          .firstMatch(html)!
          .group(1)!;
      final node = jsonDecode(json) as Map<String, dynamic>;

      expect(node['telephone'], '+56 9 9835 7797');
      expect(node['image'], '$storeUrl/portada.jpg');
      expect(node.containsKey('logo'), isFalse,
          reason: 'otra tienda sin logo no hereda el de Viñabike');
      expect(node['openingHoursSpecification'].single['dayOfWeek'],
          ['https://schema.org/Saturday']);
      expect(node['hasMerchantReturnPolicy']['merchantReturnLink'],
          '$storeUrl/devoluciones');
      expect((node['hasShippingService'] as List), hasLength(2));
    });

    test('un shell sin negocio, o con dos, no se publica', () {
      expect(
        () => snapshots.completeSeoBusinessJsonLd(
          '<html><head></head></html>',
          settings: const {},
          storeUrl: storeUrl,
          tenantId: 't',
          tenantLogoUrl: null,
          shippingTiers: const [],
          returnPolicyPublished: false,
        ),
        throwsStateError,
      );
    });
  });

  group('validador', () {
    Future<void> validate(String businessJson,
        {Set<String> trustPaths = const {'/devoluciones'},
        String extraJsonLd = ''}) async {
      final buildDir =
          await Directory.systemTemp.createTemp('vinabike-seo-business-');
      final baseHtml = '<!DOCTYPE html>\n<html lang="es"><head>\n'
          '  <title>Viñabike</title>\n'
          '  <meta name="title" content="Viñabike">\n'
          '  <meta name="description" content="Tienda de bicicletas">\n'
          '  <meta name="robots" content="index,follow">\n'
          '  <link rel="canonical" href="$storeUrl">\n'
          '  <meta property="og:url" content="$storeUrl">\n'
          '  <meta property="og:title" content="Viñabike">\n'
          '  <meta property="og:description" content="Tienda de bicicletas">\n'
          '  <meta name="twitter:url" content="$storeUrl">\n'
          '  <meta name="twitter:title" content="Viñabike">\n'
          '  <meta name="twitter:description" content="Tienda de bicicletas">\n'
          '  <script type="application/ld+json">$businessJson</script>\n'
          '  $extraJsonLd\n'
          '</head><body>\n'
          '  <noscript id="storefront-nojs-fallback">\n'
          '    <main class="storefront-nojs-fallback"><h1>Viñabike</h1></main>\n'
          '  </noscript>\n'
          '</body></html>\n';
      try {
        await File('${buildDir.path}/index.html').writeAsString(baseHtml);
        for (final slug in const [
          'nosotros',
          'envios',
          'devoluciones',
          'terminos',
          'privacidad',
        ]) {
          final published = trustPaths.contains('/$slug');
          await File('${buildDir.path}/$slug').writeAsString(
            snapshots.buildStaticTrustPageSnapshotHtml(
              baseHtml: baseHtml,
              slug: slug,
              storeUrl: storeUrl,
              storeName: 'Viñabike',
              settings: const {},
              page: published
                  ? {
                      'id': slug,
                      'slug': slug,
                      'title': slug,
                      'is_published': true,
                    }
                  : null,
              blocks: published
                  ? [
                      {
                        'id': '$slug-block',
                        'block_type': 'text',
                        'block_data': {'content': 'Diez días para devolver.'},
                        'is_visible': true,
                      },
                    ]
                  : const [],
              publishedPaths: trustPaths,
              availablePublicPaths: trustPaths,
            ),
          );
        }
        await File('${buildDir.path}/sitemap.xml').writeAsString(
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
          '${trustPaths.map((path) => '<url><loc>$storeUrl$path</loc></url>').join()}'
          '</urlset>',
        );
        await snapshots.validateGeneratedSeoArtifacts(
          buildDir: buildDir,
          storeUrl: storeUrl,
          staticTrustPagePaths: trustPaths,
        );
      } finally {
        await buildDir.delete(recursive: true);
      }
    }

    final withPolicy = jsonEncode({
      '@context': 'https://schema.org',
      '@type': 'BikeStore',
      'name': 'Viñabike',
      'hasMerchantReturnPolicy': {
        '@type': 'MerchantReturnPolicy',
        'merchantReturnLink': '$storeUrl/devoluciones',
      },
    });

    test('acepta la tienda de bicicletas con su política publicada', () async {
      await validate(withPolicy);
    });

    test('rechaza la política si la página no está publicada', () async {
      await expectLater(
        validate(withPolicy, trustPaths: const {}),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('/devoluciones publicada'))),
      );
    });

    test('rechaza una política fuera del negocio', () async {
      await expectLater(
        validate(
          jsonEncode({'@type': 'BikeStore', 'name': 'Viñabike'}),
          extraJsonLd: '<script type="application/ld+json">'
              '{"@type":"Product","hasMerchantReturnPolicy":'
              '{"@type":"MerchantReturnPolicy"}}</script>',
        ),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('sólo cabe la del negocio'))),
      );
    });
  });

  test(
      'web/index.html es salida de sync_seo_index.sh: cada script vive en '
      'la plantilla', () {
    // 2026-10-04: el script que evita la doble navegación de un <a href> de
    // Flutter se agregó sólo a web/index.html; el deploy regenera ese archivo
    // desde la plantilla y producción nunca lo tuvo.
    final index = File('web/index.html').readAsStringSync();
    final template = File('scripts/sync_seo_index.sh').readAsStringSync();
    final scripts = RegExp(
      r'<script(?![^>]*ld\+json)[^>]*>(.*?)</script>',
      dotAll: true,
    ).allMatches(index);

    expect(scripts, isNotEmpty);
    for (final script in scripts) {
      final lines = script
          .group(1)!
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) continue;
      // The template substitutes a few values (ids, host, titles); every
      // other line is copied verbatim.
      final missing = lines.where((line) => !template.contains(line)).toList();
      expect(template, contains(lines.first),
          reason: 'script sin plantilla: ${lines.first}');
      expect(missing.length, lessThanOrEqualTo((lines.length * 0.15).ceil()),
          reason: 'líneas fuera de la plantilla: $missing');
    }
  });
}
