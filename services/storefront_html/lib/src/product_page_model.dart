import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_product_page_template.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_product_brand_names.dart';
import 'package:vinabike_public_core/public_store/models/public_product_seo_copy.dart';
import 'package:vinabike_public_core/public_store/models/public_product_spec_sheet.dart';
import 'package:vinabike_public_core/public_store/seo/public_product_structured_data.dart';
import 'package:vinabike_public_core/public_store/seo/storefront_seo_route.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/shared/models/product.dart';

import 'product_images.dart';
import 'site_layout.dart';
import 'storefront_shell.dart';

typedef TrailCrumb = ({String name, String? path});
typedef RelatedProduct = ({
  PublicCommerceProductProjection commerce,
  String path,
});

/// A product page, built only from the public reads and the shared core.
class ProductPageModel {
  ProductPageModel._({
    required this.page,
    required this.row,
    required this.commerce,
    required this.sheet,
    required this.trail,
    required this.related,
    required this.seo,
    required this.path,
    required this.productUrl,
    required this.structuredData,
    required this.photos,
    required this.isService,
  });

  factory ProductPageModel.build({
    required PageContext page,
    required Map<String, dynamic> read,
  }) {
    final shell = page.shell;
    final row = Map<String, dynamic>.from(read['product'] as Map);
    final id = row['id'].toString();
    final categoryId = (row['category_id'] ?? '').toString();
    final brandId = (row['brand_id'] ?? '').toString();
    final isService = (row['product_type'] ?? '').toString() == 'service';

    // The rows cover the product and its related products, as Flutter's
    // `_attachCanonicalBrandNames` resolves every row it shows.
    final brandNames = canonicalPublicProductBrandNames(
      rows: rowsOf(read['brand_rows']),
      tenantId: page.tenantId,
      requestedBrandIds: [
        if (brandId.isNotEmpty) brandId,
        for (final other in rowsOf(read['related']))
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
        for (final spec in rowsOf(read['specs']))
          PublicProductSpecRow.fromJson(spec),
      ].where((spec) => spec.value.isNotEmpty).toList(),
      identity: PublicSpecIdentity(
        brand: commerce.brand.isEmpty ? null : commerce.brand,
        model: textOf(row['model']),
        manufacturerSku: textOf(row['manufacturer_sku']),
        gtin: commerce.gtin.isEmpty ? null : commerce.gtin,
      ),
    );
    final seo = resolvePublicProductSeoCopyFromInput(
      PublicProductSeoCopyInput.fromSettings(
        settings: shell.settings,
        seoTitleOverride: textOf(row['website_seo_title']) ?? '',
        seoDescriptionOverride: textOf(row['website_seo_description']) ?? '',
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

    final storeUrl = page.storeUrl;
    final path = publicProductPath(Product.fromJson(row));
    final productUrl = '$storeUrl$path';
    final categoryTrail = _trail(categoryId, shell);
    // A service hangs from `/servicios`, where it is listed; of its
    // categories («Servicio / Mantenciones», not public pages) the trail
    // keeps the group the price list shows it under.
    final trail = isService
        ? <TrailCrumb>[
            if (categoryTrail.isNotEmpty)
              (name: categoryTrail.last.name, path: null),
          ]
        : categoryTrail;
    final structuredData = isService
        ? buildPublicServiceStructuredData(
            commerce: commerce,
            serviceUrl: productUrl,
            storeUrl: storeUrl,
            serviceType: trail.isEmpty ? '' : trail.last.name,
          )
        : buildPublicProductStructuredData(
            commerce: commerce,
            productUrl: productUrl,
            storeUrl: storeUrl,
            storeName: shell.storeName,
            categoryTrail: [
              for (final crumb in trail)
                if (crumb.path != null)
                  PublicStructuredDataCrumb(
                    crumb.name,
                    '$storeUrl${crumb.path}',
                  ),
            ],
            specSheet: sheet,
            model: textOf(row['model']) ?? '',
          );

    return ProductPageModel._(
      page: page,
      row: row,
      commerce: commerce,
      sheet: sheet,
      trail: trail,
      related: [
        for (final other in rowsOf(read['related']))
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
      path: path,
      productUrl: productUrl,
      structuredData: structuredData,
      photos: productPhotos(row, commerce.imageUrls),
      isService: isService,
    );
  }

  final PageContext page;
  final Map<String, dynamic> row;
  final PublicCommerceProductProjection commerce;
  final PublicProductSpecSheet sheet;
  final List<TrailCrumb> trail;
  final List<RelatedProduct> related;
  final PublicProductSeoCopy seo;

  /// The canonical public path, `/productos/<slug>/<sku>`.
  final String path;
  final String productUrl;
  final Map<String, dynamic>? structuredData;

  /// The gallery: the main photo at the size it is shown, then the rest.
  final List<ProductImage> photos;

  /// A workshop service (`product_type = 'service'`): done in the workshop
  /// and booked, not put in a cart and shipped. Until 2026-10-08 its page
  /// said «En stock», «Agregar al carrito» and «Despacho a domicilio».
  final bool isService;

  /// The button that books a service: the services page's own (its hero
  /// action, edited on `/servicios`), so both say and go to the same place.
  WebsiteActionValue? get serviceAction => shell.presentations
      .forCatalogRoot(WebsiteCatalogRoot.services)
      ?.heroAction;

  StorefrontShell get shell => page.shell;

  /// The product page template the editor saved: what the page shows around
  /// the product and in what words (as Flutter's product page draws it).
  WebsiteProductPageTemplate get template => WebsiteProductPageTemplate.decode(
    shell.setting(websiteProductPageTemplateSettingKey),
  );

  String? get model => textOf(row['model']);

  bool get inStock =>
      commerce.availability == PublicCommerceAvailability.inStock;

  /// The most a cart line may hold: the published stock of a tracked
  /// product, as Flutter bounds a line; 0 when stock is not tracked.
  int get cartLimit {
    if (row['track_stock'] == false) return 0;
    final stock = row['stock_quantity'] ?? row['inventory_qty'];
    return stock is num && stock > 0 ? stock.toInt() : 0;
  }

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

  PageMeta get meta => PageMeta(
    title: seo.title.isNotEmpty ? seo.title : commerce.title,
    description: seo.description,
    canonicalUrl: productUrl,
    // A tracking or filter parameter makes the copy noindex, as Flutter's
    // `_productSeoRouteProjection` decides it.
    indexable: projectStorefrontSeoRoute(
      page.uri,
      isErpMounted: false,
      ownerAllowsIndexing: true,
      ownerIsPublished: true,
      hasEligibleContent: true,
    ).isIndexable,
    ogType: isService ? 'website' : 'product',
    preloadHeadingFont: true,
    imageUrl: commerce.imageUrls.isEmpty ? '' : commerce.imageUrls.first,
    preloadImage: photos.isEmpty
        ? null
        : (
            src: photos.first.src,
            srcset: photos.first.srcset,
            sizes: photos.first.sizes,
          ),
    structuredData: [?structuredData],
  );
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
      path: shell.isPublishedCategory(current)
          ? shell.categoryPath(current)
          : null,
    ));
    current = (category['parent_id'] ?? '').toString();
  }
  return trail;
}
