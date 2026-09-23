import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

/// `/servicios` es el catálogo de servicios del taller: el snapshot que lee
/// Google lleva cada servicio con su precio, no una página «no disponible».
void main() {
  Map<String, dynamic> service(
    String id,
    String name,
    num price, {
    String? categoryId,
  }) =>
      {
        'id': id,
        'name': name,
        'sku': id,
        'price': price,
        'product_type': 'service',
        'category_id': categoryId,
        'is_active': true,
        'is_published': true,
        'show_on_website': true,
      };

  test('los servicios se listan con precio, agrupados y ordenados', () {
    final entries = snapshots.buildSeoServiceCatalogEntries(
      services: [
        service('M2', 'Mantención Semi', 40000, categoryId: 'mant'),
        service('M1', 'Ajuste de frenos', 3000),
        service('M3', 'Centrado de rueda', 10000, categoryId: 'generica'),
        service('M4', 'Diagnóstico sin precio', 0),
      ],
      activeCategoryPathsById: {
        'mant': 'Taller > Mantenciones',
        'generica': 'Servicio',
      },
    );

    expect(
      entries.map((entry) => (entry.group, entry.name, entry.price)),
      [
        ('Mantenciones', 'Mantención Semi', 40000),
        ('Servicios', 'Ajuste de frenos', 3000),
        ('Servicios', 'Centrado de rueda', 10000),
      ],
      reason: 'sin precio no se promete; «Servicio» se une a «Servicios»',
    );
  });

  test('el HTML inicial muestra cada precio y no enlaza fichas sin snapshot',
      () {
    final html = snapshots.buildSeoServicesCatalogFallbackHtml(
      entries: const [
        snapshots.SeoServiceCatalogEntry(
          name: 'Mantención Full',
          price: 70000,
          group: 'Servicios',
        ),
      ],
      title: 'Servicios del taller',
      description: 'Precios en CLP.',
    );

    expect(html, contains('Mantención Full: \$70.000'));
    expect(RegExp('<h1').allMatches(html), hasLength(1));
    expect(RegExp('<main').allMatches(html), hasLength(1));
    expect(html, isNot(contains('/productos/')));
    expect(html, contains('href="/contacto"'));
  });

  test('los datos estructurados declaran servicios, no productos ni locales',
      () {
    final jsonLd = jsonDecode(
      snapshots.buildSeoServicesCatalogJsonLd(
        entries: const [
          snapshots.SeoServiceCatalogEntry(
            name: 'Tubeless',
            price: 25000,
            group: 'Servicios',
          ),
        ],
        servicesUrl: 'https://vinabike.cl/servicios',
        title: 'Servicios',
      ),
    ) as Map<String, dynamic>;

    expect(jsonLd['@type'], 'ItemList');
    final item = (jsonLd['itemListElement'] as List).single['item'] as Map;
    expect(item['@type'], 'Service');
    expect(item['offers'], {
      '@type': 'Offer',
      'price': '25000',
      'priceCurrency': 'CLP',
    });
    expect(jsonEncode(jsonLd), isNot(contains('LocalBusiness')),
        reason: 'la página ya declara un único LocalBusiness');
    expect(jsonEncode(jsonLd), isNot(contains('"Product"')),
        reason: 'un servicio no es un producto de Merchant');
  });

  test('el precio se escribe como en Chile', () {
    expect(snapshots.formatSeoClpAmount(3000), '\$3.000');
    expect(snapshots.formatSeoClpAmount(125990), '\$125.990');
    expect(snapshots.formatSeoClpAmount(900), '\$900');
    expect(snapshots.formatSeoClpAmount(1250000), '\$1.250.000');
  });

  test('la lectura de servicios pide product_type=service', () {
    final uri = snapshots.buildSeoSnapshotProductPageUri(
      supabaseUrl: 'https://example.supabase.co',
      tenantId: 'tenant',
      onlyMerchant: false,
      pageSize: 1000,
      productType: 'service',
    );
    expect(uri.queryParameters['product_type'], 'eq.service');
    expect(
      snapshots
          .buildSeoSnapshotProductPageUri(
            supabaseUrl: 'https://example.supabase.co',
            tenantId: 'tenant',
            onlyMerchant: false,
            pageSize: 1000,
          )
          .queryParameters['product_type'],
      'eq.product',
      reason: 'las fichas de producto no cambian',
    );
  });
}
