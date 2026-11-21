import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_product_page_template.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_on_order_lead.dart';
import 'package:vinabike_public_core/public_store/models/public_product_brand_names.dart';
import 'package:vinabike_public_core/public_store/models/public_product_model.dart';
import 'package:vinabike_public_core/public_store/models/public_product_seo_copy.dart';
import 'package:vinabike_public_core/public_store/models/public_product_spec_sheet.dart';
import 'package:vinabike_public_core/public_store/models/public_shipping_promise.dart';
import 'package:vinabike_public_core/public_store/seo/public_product_structured_data.dart';
import 'package:vinabike_public_core/public_store/seo/storefront_seo_route.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/shared/models/product.dart';

import 'product_images.dart';
import 'product_question_view.dart' show productQuestionCss;
import 'site_layout.dart';
import 'storefront_shell.dart';

typedef TrailCrumb = ({String name, String? path});
typedef RelatedProduct = ({
  PublicCommerceProductProjection commerce,
  String path,

  /// Its model, when it is one of several sizes or colors (20261120230000):
  /// the card says «2 colores · 3 tallas».
  PublicProductModelSummary? model,
});

/// One value of a model's axis in the page's selector (20261120230000):
/// the variant it leads to ([path], null when that combination does not
/// exist), whether it is the page's own, and whether it can be bought now.
typedef VariantChoice = ({
  String label,
  String? path,
  bool current,
  bool soldOut,
  String? image,
});

/// One axis of the selector: «Color: Blanco/Negro» with photo tiles, «Talla:
/// S/M» with buttons.
typedef VariantAxis = ({
  String name,
  String current,
  bool swatches,
  List<VariantChoice> choices,
});

/// What goes with the product (`fits` of the page read): a card with what
/// the cart needs to add it from the page.
typedef FitProduct = ({
  PublicCommerceProductProjection commerce,
  String path,
  int max,
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
    required this.fitsKind,
    required this.fits,
    required this.seo,
    required this.path,
    required this.productUrl,
    required this.structuredData,
    required this.photos,
    required this.isService,
    required this.group,
    required this.variantAxes,
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
        for (final other in [
          ...rowsOf(read['related']),
          ...rowsOf(_fitsOf(read)['items']),
        ])
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
            priceMode: (row['website_price_mode'] ?? 'exact').toString(),
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
    // The model as Google reads it: one ProductGroup with every variant.
    final groupRead = PublicProductModel.fromJson(read['model']);
    final groupedData = isService || groupRead == null
        ? structuredData
        : withPublicProductGroup(
            structuredData,
            groupId: groupRead.id,
            groupName: groupRead.name,
            axes: [for (final axis in groupRead.choosableAxes) axis.name],
            variants: [
              for (final variant in groupRead.variants)
                (
                  commerce: PublicCommerceProductProjection.fromJson(
                    variant,
                    resolvedBrand: brandNames[brandId],
                  ),
                  url:
                      '$storeUrl${publicProductPath(Product.fromJson(variant))}',
                  options: PublicProductModel.optionsOf(variant),
                ),
            ],
            currentUrl: productUrl,
            storeName: shell.storeName,
          );

    // The model this product is a size or color of (20261120230000): its
    // variants are judged by the same projection as the page (stock, lead
    // time, price), and each one keeps its own page.
    final group = PublicProductModel.fromJson(read['model']);
    final variants = [
      for (final variant in group?.variants ?? const <Map<String, dynamic>>[])
        (
          row: variant,
          commerce: PublicCommerceProductProjection.fromJson(
            variant,
            resolvedBrand: brandNames[brandId],
          ),
          path: publicProductPath(Product.fromJson(variant)),
          options: PublicProductModel.optionsOf(variant),
        ),
    ];
    final variantAxes = group == null
        ? const <VariantAxis>[]
        : _variantAxes(
            group,
            // The page's own row carries no options: they live on the
            // model's variants (get_public_product_model_v1).
            current: PublicProductModel.optionsOf(group.variantById(id) ?? row),
            id: id,
            variants: variants,
          );

    return ProductPageModel._(
      group: variantAxes.isEmpty ? null : group,
      variantAxes: variantAxes,
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
              model: PublicProductModelSummary.fromRow(other),
            ),
      ].where((item) => item.commerce.imageUrls.isNotEmpty).take(8).toList(),
      fitsKind: (_fitsOf(read)['kind'] ?? '').toString(),
      fits: [
        for (final other in rowsOf(_fitsOf(read)['items']))
          if (other['id'].toString() != id)
            (
              commerce: PublicCommerceProductProjection.fromJson(
                other,
                resolvedBrand: brandNames[(other['brand_id'] ?? '').toString()],
              ),
              path: publicProductPath(Product.fromJson(other)),
              max: other['track_stock'] == false
                  ? 0
                  : switch (other['stock_quantity'] ?? other['inventory_qty']) {
                      final num stock when stock > 0 => stock.toInt(),
                      _ => 0,
                    },
            ),
      ].where((item) => item.commerce.price > 0).take(6).toList(),
      seo: seo,
      path: path,
      productUrl: productUrl,
      structuredData: groupedData,
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

  /// `tubes` (a tyre's page) or `tyres` (a tube's page), with [fits].
  final String fitsKind;
  final List<FitProduct> fits;
  final PublicProductSeoCopy seo;

  /// The canonical public path, `/productos/<slug>/<sku>`.
  final String path;
  final String productUrl;
  final Map<String, dynamic>? structuredData;

  /// The gallery: the main photo at the size it is shown, then the rest.
  final List<ProductImage> photos;

  /// The model this product is a size or color of, when the store shows
  /// more than one of them (20261120230000); null otherwise.
  final PublicProductModel? group;

  /// The page's selector: one row per axis that varies.
  final List<VariantAxis> variantAxes;

  /// The brand above the title, as international brands' pages name it
  /// (2026-11-20): «LEATT», then «Rodillera 3DF 5.0».
  String get brandEyebrow => commerce.brand.trim();

  /// The title under the brand: the model's name when the product is one of
  /// several sizes or colors (the selector says which), without the brand
  /// the line above already names.
  String get displayTitle {
    final base = (group?.name.trim().isNotEmpty ?? false)
        ? group!.name.trim()
        : commerce.title;
    return withoutBrand(base, brandEyebrow);
  }

  /// One sentence that sells it, under the title: the description's first
  /// sentence when it is short enough to read at a glance.
  String? get lede {
    final paragraphs = descriptionParagraphs;
    if (paragraphs.isEmpty) return null;
    final first = paragraphs.first.split('\n').first.trim();
    final match = RegExp(r'^.{20,170}?[.!?](\s|$)').firstMatch(first);
    final sentence = match?.group(0)?.trim();
    if (sentence == null) return first.length <= 170 ? first : null;
    return sentence;
  }

  /// «¿Dudas con la talla? Escríbenos» when there are sizes to choose.
  bool get hasSizes => variantAxes.any(
    (axis) => !axis.swatches && axis.name.toLowerCase() == 'talla',
  );

  /// What this variant's photos show: its color (every axis named like
  /// one), empty when the model has none; null without a selector. The page
  /// script keeps the photos in sight when another size has the same one
  /// (2026-11-21): each size keeps the same picture under its own file, and
  /// loading it again was half of the «refresh medio raro» the owner saw.
  String? get variantLook {
    final model = group;
    if (model == null) return null;
    final options = PublicProductModel.optionsOf(
      model.variantById(commerce.id) ?? row,
    );
    return [
      for (final entry in options.entries)
        if (entry.key.toLowerCase().contains('color')) entry.value,
    ].join('|');
  }

  /// The sticky bar opens a layer to choose the options before adding
  /// (owner, 2026-11-21): a product with sizes or colors whose page shows
  /// that bar.
  bool get choosesOptions =>
      variantAxes.isNotEmpty && !isService && template.showStickyBuyBar;

  /// That layer's title, with the selector's axes: «Elige color y talla».
  String get optionsTitle {
    final names = [for (final axis in variantAxes) axis.name.toLowerCase()];
    if (names.isEmpty) return 'Elige tus opciones';
    if (names.length == 1) return 'Elige ${names.single}';
    return 'Elige ${names.sublist(0, names.length - 1).join(', ')} '
        'y ${names.last}';
  }

  /// A workshop service (`product_type = 'service'`): done in the workshop
  /// and booked, not put in a cart and shipped. Until 2026-10-08 its page
  /// said «En stock», «Agregar al carrito» and «Despacho a domicilio».
  final bool isService;

  /// How the price reads (`website_price_mode`): «Desde $X», «A cotizar».
  String get priceMode => (row['website_price_mode'] ?? 'exact').toString();

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

  /// «Pregunta por este producto»: a product's page (a service books in
  /// its own button), when the box or the help card shows.
  bool get asksQuestions =>
      !isService && (template.showAsk || template.showHelp);

  bool get inStock =>
      commerce.availability == PublicCommerceAvailability.inStock;

  /// Sold out but bought with the cart all the same: the supplier brings it
  /// in this dispatch time (20261120210000). Null in stock or when it cannot
  /// be bought this way now.
  PublicOnOrderLead? get onOrder =>
      !inStock && commerce.purchasable ? commerce.onOrder : null;

  /// Bought with the cart: in stock or with a dispatch time.
  bool get purchasable => commerce.purchasable;

  /// Sold out, and the shop quotes it (20261103070000): «Se cotiza» on its
  /// form, a brand it quotes without stock, or sold with a lead time the
  /// supplier cannot meet now. Otherwise the page says «Agotado» and only
  /// takes a question.
  bool get quotable => commerce.soldOutQuotable;

  /// «En stock», «Despacho en 3 a 5 días hábiles» or «Agotado», wherever
  /// the page names it: never «a pedido» (owner, 2026-11-20).
  String get stockWord =>
      inStock ? 'En stock' : onOrder?.dispatchLabel ?? 'Agotado';

  /// The most a cart line may hold: the published stock of a tracked
  /// product, as Flutter bounds a line, or what one purchase may take with a
  /// dispatch time; 0 when stock is not tracked.
  int get cartLimit {
    if (row['track_stock'] == false) return 0;
    if (onOrder case final lead?) return lead.maxQuantity ?? 0;
    final stock = row['stock_quantity'] ?? row['inventory_qty'];
    return stock is num && stock > 0 ? stock.toInt() : 0;
  }

  /// What the buy box promises about home delivery, from the store's zones.
  PublicShippingPromise? get shippingPromise =>
      PublicShippingPromise.fromTiers(shell.shippingTiers);

  /// A bicycle ships in its own box, priced per unit by zone
  /// (20261121120000): its category, or one above it, is marked in
  /// Sitio Web › Envíos.
  bool get shipsAsBike =>
      shippingPromise?.shipsAsBike(row['category_id']?.toString()) ?? false;

  /// Description paragraphs as plain text: the HTML is the customer's words,
  /// never markup copied from the ERP. A blank line starts a paragraph and a
  /// single line break stays inside it (the page shows it as a new line), so
  /// «Peso: 570 g» written on its own line is never glued to the sentence
  /// before it.
  List<String> get descriptionParagraphs {
    final source = commerce.descriptionText.isNotEmpty
        ? commerce.descriptionText
        : commerce.description;
    return source
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .split(RegExp(r'\n\s*\n|\\n\\n'))
        .map(
          (p) => p
              .split('\n')
              .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
              .where((line) => line.isNotEmpty)
              .join('\n'),
        )
        .where((p) => p.isNotEmpty)
        .toList();
  }

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
    styles: asksQuestions ? productQuestionCss : '',
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

Map<String, dynamic> _fitsOf(Map<String, dynamic> read) => read['fits'] is Map
    ? Map<String, dynamic>.from(read['fits'] as Map)
    : const {};

/// [title] without the brand the line above names («Rodillera Leatt 3DF
/// 5.0» under «Leatt» reads «Rodillera 3DF 5.0»); unchanged when the brand
/// is not a word of it or would leave too little.
String withoutBrand(String title, String brand) {
  final trimmed = brand.trim();
  if (trimmed.isEmpty) return title;
  final pattern = RegExp(
    '(^|\\s)${RegExp.escape(trimmed)}(?=\\s|\$)',
    caseSensitive: false,
  );
  final match = pattern.firstMatch(title);
  if (match == null) return title;
  final rest = title
      .replaceRange(match.start, match.end, match.group(1) ?? '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return rest.length < 3 ? title : rest;
}

/// The selector of a model's page: for each axis that varies, its values in
/// order, each one a link to the variant that is exactly this one with that
/// value. The first axis (the color, with its photo) always leads somewhere:
/// to the variant of that color that keeps most of this one's choices. A
/// later axis (the size) shows crossed out the values this color does not
/// come in, and the sizes it comes in that cannot be bought now.
List<VariantAxis> _variantAxes(
  PublicProductModel group, {
  required Map<String, String> current,
  required String id,
  required List<
    ({
      Map<String, dynamic> row,
      PublicCommerceProductProjection commerce,
      String path,
      Map<String, String> options,
    })
  >
  variants,
}) {
  final axes = group.choosableAxes;
  if (axes.isEmpty) return const [];
  ({
    Map<String, dynamic> row,
    PublicCommerceProductProjection commerce,
    String path,
    Map<String, String> options,
  })?
  find(Map<String, dynamic>? row) {
    if (row == null) return null;
    for (final variant in variants) {
      if (variant.row['id']?.toString() == row['id']?.toString()) {
        return variant;
      }
    }
    return null;
  }

  final result = <VariantAxis>[];
  for (var index = 0; index < axes.length; index++) {
    final axis = axes[index];
    final swatches = index == 0 && axis.name.toLowerCase().contains('color');
    final choices = <VariantChoice>[];
    for (final value in axis.values) {
      final exact = find(group.exactVariant(current, axis.name, value));
      final target =
          exact ??
          (index == 0
              ? find(
                  group.variantFor(
                    current,
                    axis.name,
                    value,
                    available: (row) =>
                        find(row)?.commerce.purchasable ?? false,
                  ),
                )
              : null);
      if (target == null &&
          !variants.any((v) => v.options[axis.name] == value)) {
        continue;
      }
      final isCurrent = target != null && target.row['id']?.toString() == id;
      choices.add((
        label: value,
        path: isCurrent ? null : target?.path,
        current: isCurrent,
        soldOut: target == null || !target.commerce.purchasable,
        image: target != null && target.commerce.imageUrls.isNotEmpty
            ? target.commerce.imageUrls.first
            : null,
      ));
    }
    if (choices.length < 2) continue;
    result.add((
      name: axis.name,
      current: current[axis.name] ?? '',
      swatches: swatches && choices.every((choice) => choice.image != null),
      choices: choices,
    ));
  }
  return result;
}
