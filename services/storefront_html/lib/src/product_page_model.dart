import 'dart:convert';

import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_destination.dart';
import 'package:vinabike_public_core/modules/website/models/website_page_models.dart';
import 'package:vinabike_public_core/modules/website/models/website_seo_settings_aliases.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_product_brand_names.dart';
import 'package:vinabike_public_core/public_store/models/public_product_seo_copy.dart';
import 'package:vinabike_public_core/public_store/models/public_product_spec_sheet.dart';
import 'package:vinabike_public_core/public_store/seo/public_product_structured_data.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/shared/models/product.dart';

import 'storefront_config.dart';

/// What every page shares, read by `get_public_storefront_shell_v1`.
class StorefrontShell {
  StorefrontShell._({
    required this.settings,
    required this.navigation,
    required this.pagesById,
    required this.categories,
    required this.shippingTiers,
  });

  factory StorefrontShell.fromJson(Map<String, dynamic> json) {
    final rawSettings = json['settings'];
    return StorefrontShell._(
      settings: {
        if (rawSettings is Map)
          for (final entry in rawSettings.entries)
            entry.key.toString(): switch (entry.value) {
              null => '',
              final String text => text,
              final other => jsonEncode(other),
            },
      },
      navigation: [
        for (final row in _rows(json['navigation']))
          WebsiteNavigation.fromJson(row),
      ]..sort((a, b) => a.orderIndex.compareTo(b.orderIndex)),
      pagesById: {
        for (final row in _rows(json['pages']))
          row['id'].toString(): WebsitePage.fromJson(row),
      },
      categories: {
        for (final row in _rows(json['categories'])) row['id'].toString(): row,
      },
      shippingTiers: _rows(json['shipping_tiers']),
    );
  }

  final Map<String, String> settings;
  final List<WebsiteNavigation> navigation;
  final Map<String, WebsitePage> pagesById;
  final Map<String, Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> shippingTiers;

  late final WebsiteCatalogPresentationRegistry _presentations =
      WebsiteCatalogPresentationRegistry.decode(
        settings[websiteCatalogPresentationsSettingKey],
      );

  String setting(String key, [String fallback = '']) {
    final value = settings[key]?.trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  /// The public path of a category, as the editor's «Catálogo web» presents
  /// it, or the slug of its name when it has no presentation.
  String categoryPath(String id, {bool services = false}) {
    final name = (categories[id]?['name'] ?? '').toString();
    return publicCategoryPath(
      presentation:
          _presentations.forCategory(id) ??
          WebsiteCatalogPresentation.fallback(
            categoryId: id,
            categoryName: name,
          ),
      services: services,
    );
  }

  /// Menu items as the Flutter store draws them: a phone shows only
  /// `show_on_mobile`, a desktop only `show_on_desktop`, so an item hidden on
  /// both is never drawn. The view turns the rest into responsive classes.
  List<WebsiteNavigation> topLevel(MenuLocation location) => [
    for (final item in navigation)
      if (item.menuLocation == location &&
          item.parentId == null &&
          _shownSomewhere(item))
        item,
  ];

  List<WebsiteNavigation> childrenOf(WebsiteNavigation parent) => [
    for (final item in navigation)
      if (item.parentId == parent.id && _shownSomewhere(item)) item,
  ];

  static bool _shownSomewhere(WebsiteNavigation item) =>
      item.isVisible && (item.showOnDesktop || item.showOnMobile);

  /// The store's own origin for canonical URLs and structured data: the
  /// editor's `store_url`, normalized like the Flutter page and the snapshot
  /// generator do, or the service's configured origin when it is not set.
  String storeOrigin(String fallback) {
    final configured = WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
      settings['store_url'] ?? '',
    );
    return (configured.isNotEmpty ? configured : fallback).replaceAll(
      RegExp(r'/+$'),
      '',
    );
  }

  /// Where a menu item leads, through the same models the Flutter store uses
  /// (`WebsiteNavigation.href`, `WebsitePage.fullPath`,
  /// `WebsiteDestination.parse`). A category link becomes its clean public
  /// path; any other filter in the link is kept. `null` hides the item: an
  /// action, or a page that is not published.
  String? hrefFor(WebsiteNavigation item) {
    var resolved = item;
    if (item.linkType == NavLinkType.page) {
      final value = item.linkValue?.trim() ?? '';
      final page = pagesById[value];
      if (page != null) {
        resolved = item.copyWith(linkedPage: page);
      } else if (_uuid.hasMatch(value)) {
        return null;
      }
    }
    final raw = resolved.href;
    if (raw == null) return null;
    final destination = WebsiteDestination.parse(raw);
    switch (destination.kind) {
      case WebsiteDestinationKind.none:
        return null;
      case WebsiteDestinationKind.category:
        final id = destination.reference ?? '';
        if (!categories.containsKey(id)) return destination.href;
        final uri = Uri.parse(destination.href);
        final rest = Map<String, String>.of(uri.queryParameters)
          ..remove('category');
        final path = categoryPath(
          id,
          services: uri.path.startsWith('/servicios'),
        );
        return rest.isEmpty
            ? path
            : Uri(path: path, queryParameters: rest).toString();
      default:
        return destination.href;
    }
  }

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
}

typedef TrailCrumb = ({String name, String? path});
typedef RelatedProduct = ({
  PublicCommerceProductProjection commerce,
  String path,
});

/// A product page, built only from the two public reads and the shared core.
class ProductPageModel {
  ProductPageModel._({
    required this.shell,
    required this.row,
    required this.commerce,
    required this.sheet,
    required this.trail,
    required this.related,
    required this.seo,
    required this.productUrl,
    required this.storeUrl,
    required this.storeName,
    required this.tenantId,
    required this.structuredData,
  });

  factory ProductPageModel.build({
    required StorefrontConfig config,
    required StorefrontShell shell,
    required Map<String, dynamic> page,
  }) {
    final row = Map<String, dynamic>.from(page['product'] as Map);
    final id = row['id'].toString();
    final categoryId = (row['category_id'] ?? '').toString();
    final brandId = (row['brand_id'] ?? '').toString();

    // The rows cover the product and its related products, as Flutter's
    // `_attachCanonicalBrandNames` resolves every row it shows.
    final brandNames = canonicalPublicProductBrandNames(
      rows: _rows(page['brand_rows']),
      tenantId: config.tenantId,
      requestedBrandIds: [
        if (brandId.isNotEmpty) brandId,
        for (final other in _rows(page['related']))
          if ((other['brand_id'] ?? '').toString().isNotEmpty)
            other['brand_id'].toString(),
      ],
    );
    final commerce = PublicCommerceProductProjection.fromJson(
      row,
      resolvedBrand: brandNames[brandId],
      categoryPath: (shell.categories[categoryId]?['full_path'] ?? '')
          .toString(),
    );
    final sheet = PublicProductSpecSheet.build(
      rows: [
        for (final spec in _rows(page['specs']))
          PublicProductSpecRow.fromJson(spec),
      ].where((spec) => spec.value.isNotEmpty).toList(),
      identity: PublicSpecIdentity(
        brand: commerce.brand.isEmpty ? null : commerce.brand,
        model: _text(row['model']),
        manufacturerSku: _text(row['manufacturer_sku']),
        gtin: commerce.gtin.isEmpty ? null : commerce.gtin,
      ),
    );
    final seo = resolvePublicProductSeoCopyFromInput(
      PublicProductSeoCopyInput.fromSettings(
        settings: shell.settings,
        seoTitleOverride: _text(row['website_seo_title']) ?? '',
        seoDescriptionOverride: _text(row['website_seo_description']) ?? '',
        searchTerms: [
          for (final term in (row['website_search_terms'] as List?) ?? const [])
            term.toString(),
        ],
        product: PublicProductSeoProductInput(
          name: commerce.title,
          sku: commerce.sku,
          price: commerce.price,
          brand: commerce.brand,
          description: commerce.description,
          categoryPath: commerce.categoryPath,
        ),
      ),
    );

    final storeUrl = shell.storeOrigin(config.storeOrigin);
    final productUrl = '$storeUrl${publicProductPath(Product.fromJson(row))}';
    final trail = _trail(categoryId, shell);
    final storeName = shell.setting('store_name', 'Viñabike');
    final structuredData = buildPublicProductStructuredData(
      commerce: commerce,
      productUrl: productUrl,
      storeUrl: storeUrl,
      storeName: storeName,
      categoryTrail: [
        for (final crumb in trail)
          if (crumb.path != null)
            PublicStructuredDataCrumb(crumb.name, '$storeUrl${crumb.path}'),
      ],
      specSheet: sheet,
      model: _text(row['model']) ?? '',
    );

    return ProductPageModel._(
      shell: shell,
      row: row,
      commerce: commerce,
      sheet: sheet,
      trail: trail,
      related: [
        for (final other in _rows(page['related']))
          if (other['id'].toString() != id)
            (
              commerce: PublicCommerceProductProjection.fromJson(
                other,
                resolvedBrand: brandNames[(other['brand_id'] ?? '').toString()],
              ),
              path: publicProductPath(Product.fromJson(other)),
            ),
      ].where((item) => item.commerce.imageUrls.isNotEmpty).take(8).toList(),
      seo: seo,
      productUrl: productUrl,
      storeUrl: storeUrl,
      storeName: storeName,
      tenantId: config.tenantId,
      structuredData: structuredData,
    );
  }

  final StorefrontShell shell;
  final Map<String, dynamic> row;
  final PublicCommerceProductProjection commerce;
  final PublicProductSpecSheet sheet;
  final List<TrailCrumb> trail;
  final List<RelatedProduct> related;
  final PublicProductSeoCopy seo;
  final String productUrl;
  final String storeUrl;
  final String storeName;
  final String tenantId;
  final Map<String, dynamic>? structuredData;

  String? get model => _text(row['model']);

  bool get inStock =>
      commerce.availability == PublicCommerceAvailability.inStock;

  /// The cheapest shipping tier and its delivery window, for the buy box.
  ({double price, String days})? get cheapestShipping {
    final tiers = shell.shippingTiers;
    if (tiers.isEmpty) return null;
    final cheapest = tiers.reduce(
      (a, b) =>
          (a['shipping_gross'] as num) <= (b['shipping_gross'] as num) ? a : b,
    );
    return (
      price: (cheapest['shipping_gross'] as num).toDouble(),
      days:
          '${cheapest['estimated_min_business_days']} a '
          '${cheapest['estimated_max_business_days']}',
    );
  }

  /// Description paragraphs as plain text: the HTML is the customer's words,
  /// never markup copied from the ERP.
  List<String> get descriptionParagraphs => commerce.description
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .split(RegExp(r'\n\s*\n|\\n\\n'))
      .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((p) => p.isNotEmpty)
      .toList();
}

/// Each category from the root to the product's, linked only when it is a
/// public destination.
List<TrailCrumb> _trail(String categoryId, StorefrontShell shell) {
  final trail = <TrailCrumb>[];
  final seen = <String>{};
  var current = categoryId;
  while (current.isNotEmpty && seen.add(current)) {
    final category = shell.categories[current];
    if (category == null) break;
    trail.insert(0, (
      name: category['name'].toString(),
      path: category['show_on_website'] == true
          ? shell.categoryPath(current)
          : null,
    ));
    current = (category['parent_id'] ?? '').toString();
  }
  return trail;
}

List<Map<String, dynamic>> _rows(Object? value) => [
  if (value is List)
    for (final row in value)
      if (row is Map) Map<String, dynamic>.from(row),
];

String? _text(Object? value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}
