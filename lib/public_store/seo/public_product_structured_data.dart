import 'dart:convert';

import '../models/public_commerce_product_projection.dart';
import '../models/public_product_spec_sheet.dart';

/// One step of the trail a product page shows above its title.
class PublicStructuredDataCrumb {
  const PublicStructuredDataCrumb(this.name, this.url);

  final String name;

  /// Absolute URL on the store's own origin.
  final String url;
}

/// The Product structured data of a public product page.
///
/// One builder for the two places that declare it: the deploy-time snapshot
/// (`scripts/generate_product_seo_snapshots.dart`) and the page itself once
/// Flutter runs, which replaces the snapshot's script by its id. Until
/// 2026-10-04 each kept its own map: the page dropped the snapshot's
/// breadcrumbs when it took over, and neither declared the technical sheet
/// the customer reads next to the price.
///
/// Everything comes from [commerce] (the shared public projection) and from
/// the published sheet; nothing is derived from a title or a SKU. Returns
/// null without an image, as Google requires one for a product result.
Map<String, dynamic>? buildPublicProductStructuredData({
  required PublicCommerceProductProjection commerce,
  required String productUrl,
  required String storeUrl,
  required String storeName,
  List<PublicStructuredDataCrumb> categoryTrail = const [],
  PublicProductSpecSheet? specSheet,
  String model = '',
}) {
  if (commerce.imageUrls.isEmpty) return null;

  final title = _clean(commerce.title);
  final description = _clean(commerce.description);
  final cleanModel = _clean(model);
  final properties = <Map<String, dynamic>>[
    for (final group in specSheet?.groups ?? const <PublicSpecGroup>[])
      if (group.title != PublicProductSpecSheet.identityTitle)
        for (final item in group.items)
          if (_clean(item.label).isNotEmpty && _clean(item.value).isNotEmpty)
            {
              '@type': 'PropertyValue',
              'name': _clean(item.label),
              'value': _clean(item.value),
            },
  ];

  final product = <String, dynamic>{
    '@type': 'Product',
    'name': title,
    if (description.isNotEmpty) 'description': description,
    'url': productUrl,
    'image': commerce.imageUrls,
    if (commerce.sku.isNotEmpty) 'sku': commerce.sku,
    if (commerce.gtin.isNotEmpty) 'gtin': commerce.gtin,
    if (commerce.mpn.isNotEmpty) 'mpn': commerce.mpn,
    if (cleanModel.isNotEmpty) 'model': cleanModel,
    if (commerce.brand.isNotEmpty)
      'brand': {'@type': 'Brand', 'name': commerce.brand},
    if (commerce.categoryPath.isNotEmpty) 'category': commerce.categoryPath,
    if (properties.isNotEmpty) 'additionalProperty': properties,
    'offers': {
      '@type': 'Offer',
      'url': productUrl,
      'priceCurrency': commerce.currency,
      if (commerce.price > 0) 'price': commerce.formattedPrice,
      'availability': commerce.availability.schemaValue,
      'itemCondition': 'https://schema.org/NewCondition',
      'seller': {'@type': 'Organization', 'name': storeName},
    },
  };

  final crumbs = <PublicStructuredDataCrumb>[
    PublicStructuredDataCrumb('Inicio', storeUrl),
    PublicStructuredDataCrumb('Productos', '$storeUrl/productos'),
    ...categoryTrail.where((crumb) => _clean(crumb.name).isNotEmpty),
    PublicStructuredDataCrumb(title, productUrl),
  ];

  return {
    '@context': 'https://schema.org',
    '@graph': [
      product,
      {
        '@type': 'BreadcrumbList',
        'itemListElement': [
          for (var i = 0; i < crumbs.length; i++)
            {
              '@type': 'ListItem',
              'position': i + 1,
              'name': _clean(crumbs[i].name),
              'item': crumbs[i].url,
            },
        ],
      },
    ],
  };
}

/// JSON for an inline `<script type="application/ld+json">`: a value that
/// carries `</script>` or `<!--` cannot close the element early.
String encodeStructuredDataForHtml(Object data) => jsonEncode(data)
    .replaceAll('<', r'\u003c')
    .replaceAll('>', r'\u003e')
    .replaceAll('&', r'\u0026');

String _clean(String text) => text
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
