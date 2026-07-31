import '../../shared/models/product.dart';
import '../../shared/utils/gtin_utils.dart';
import 'public_product_seo_copy.dart';

enum PublicCommerceAvailability {
  inStock,
  outOfStock;

  String get merchantValue =>
      this == PublicCommerceAvailability.inStock ? 'in_stock' : 'out_of_stock';

  String get schemaValue => this == PublicCommerceAvailability.inStock
      ? 'https://schema.org/InStock'
      : 'https://schema.org/OutOfStock';
}

enum PublicCommerceEligibilityIssue {
  missingIdentity('missing_identity'),
  missingTitle('missing_title'),
  missingDescription('missing_description'),
  invalidPrice('invalid_price'),
  missingImage('missing_image'),
  missingBrand('missing_brand'),
  missingProductIdentifiers('missing_product_identifiers');

  const PublicCommerceEligibilityIssue(this.code);

  final String code;
}

/// One factual projection for every public commerce consumer.
///
/// The precedence is intentionally shared by the visible product page,
/// Product JSON-LD, static SEO snapshots, checkout mirrors, and Merchant:
///
/// * commerce override (`website_merchant_*`) when staff explicitly saved it;
/// * website override (`website_*`);
/// * canonical catalog value.
///
/// This projection never derives a GTIN, MPN, brand, or category from a title,
/// SKU, retailer name, or other heuristic. Category paths and linked brand
/// names must be supplied by their canonical catalog owners.
class PublicCommerceProductProjection {
  const PublicCommerceProductProjection({
    required this.id,
    required this.sku,
    required this.title,
    required this.description,
    required this.price,
    required this.currency,
    required this.availability,
    required this.imageUrls,
    required this.brand,
    required this.gtin,
    required this.mpn,
    required this.categoryId,
    required this.categoryPath,
    required this.googleProductCategory,
    required this.merchantIssues,
  });

  factory PublicCommerceProductProjection.fromProduct(
    Product product, {
    String? resolvedBrand,
    String? categoryPath,
  }) {
    final effectiveCategoryPath = product.categoryId?.trim().isNotEmpty == true
        ? _firstNonEmpty(categoryPath, product.categoryName)
        : '';
    return _build(
      id: product.id,
      sku: product.sku,
      title: _firstNonEmpty(
        product.websiteMerchantTitle,
        product.websiteName,
        product.name,
      ),
      description: _firstNonEmpty(
        product.websiteMerchantDescription,
        product.websiteDescription,
        product.description,
      ),
      price: product.websitePrice ?? product.price,
      currency: product.priceCurrency,
      available: !product.tracksInventory || product.availableStockQuantity > 0,
      imageUrls: _productImageUrls(product),
      brand: _firstNonEmpty(
        product.websiteMerchantBrand,
        resolvedBrand,
        product.brand,
      ),
      gtin: firstValidGtin([
        product.websiteMerchantGtin,
        product.gtin,
        product.barcode,
      ]),
      mpn: _firstNonEmpty(product.websiteMerchantMpn),
      categoryId: product.categoryId,
      categoryPath: effectiveCategoryPath,
      googleProductCategory:
          _firstNonEmpty(product.websiteGoogleProductCategory),
    );
  }

  factory PublicCommerceProductProjection.fromJson(
    Map<String, dynamic> product, {
    String? resolvedBrand,
    String? categoryPath,
  }) {
    final categoryId = _firstNonEmpty(product['category_id']);
    final effectiveCategoryPath =
        categoryId.isEmpty ? '' : _firstNonEmpty(categoryPath);
    final price =
        _toDouble(product['website_price']) ?? _toDouble(product['price']) ?? 0;
    final isService = product['product_type'] == 'service';
    final tracksInventory = !isService && product['track_stock'] != false;
    final availableQuantity = product['is_set'] == true
        ? _toInt(product['full_sets_available']) ??
            _toInt(product['stock_quantity']) ??
            _toInt(product['inventory_qty']) ??
            0
        : _toInt(product['stock_quantity']) ??
            _toInt(product['inventory_qty']) ??
            0;

    return _build(
      id: _firstNonEmpty(product['id']),
      sku: _firstNonEmpty(product['sku']),
      title: _firstNonEmpty(
        product['website_merchant_title'],
        product['website_name'],
        product['name'],
      ),
      description: _firstNonEmpty(
        product['website_merchant_description'],
        product['website_description'],
        product['description'],
      ),
      price: price,
      currency: _firstNonEmpty(product['price_currency'], 'CLP').toUpperCase(),
      available: !tracksInventory || availableQuantity > 0,
      imageUrls: _jsonImageUrls(product),
      brand: _firstNonEmpty(
        product['website_merchant_brand'],
        resolvedBrand,
        product['brand'],
      ),
      gtin: firstValidGtin([
        product['website_merchant_gtin'],
        product['gtin'],
        product['barcode'],
      ]),
      mpn: _firstNonEmpty(product['website_merchant_mpn']),
      categoryId: categoryId,
      categoryPath: effectiveCategoryPath,
      googleProductCategory:
          _firstNonEmpty(product['website_google_product_category']),
    );
  }

  /// Projects unsaved editor values with the exact public precedence and text
  /// normalization used by [fromProduct] and [fromJson].
  ///
  /// The editor cannot build a complete persisted [Product] while a form is
  /// being edited. This seam prevents its SEO preview from reimplementing the
  /// Merchant → website → catalog precedence independently.
  factory PublicCommerceProductProjection.fromDraft({
    String id = '',
    String sku = '',
    required String catalogTitle,
    String websiteTitle = '',
    String merchantTitle = '',
    required String catalogDescription,
    String websiteDescription = '',
    String merchantDescription = '',
    required double price,
    String currency = 'CLP',
    bool available = true,
    String brand = '',
    String categoryId = '',
    String categoryPath = '',
  }) {
    return _build(
      id: id,
      sku: sku,
      title: _firstNonEmpty(
        merchantTitle,
        websiteTitle,
        catalogTitle,
      ),
      description: _firstNonEmpty(
        merchantDescription,
        websiteDescription,
        catalogDescription,
      ),
      price: price,
      currency: currency,
      available: available,
      imageUrls: const [],
      brand: brand,
      gtin: '',
      mpn: '',
      categoryId: categoryId,
      categoryPath: categoryId.trim().isEmpty ? '' : categoryPath,
      googleProductCategory: '',
    );
  }

  final String id;
  final String sku;
  final String title;
  final String description;
  final double price;
  final String currency;
  final PublicCommerceAvailability availability;
  final List<String> imageUrls;
  final String brand;
  final String gtin;
  final String mpn;
  final String categoryId;
  final String categoryPath;
  final String googleProductCategory;
  final List<PublicCommerceEligibilityIssue> merchantIssues;

  bool get merchantEligible => merchantIssues.isEmpty;

  String get formattedPrice =>
      price % 1 == 0 ? price.toStringAsFixed(0) : price.toStringAsFixed(2);

  Map<String, dynamic> toContractJson() => {
        'id': id,
        'sku': sku,
        'title': title,
        'description': description,
        'price': price,
        'currency': currency,
        'availability': availability.merchantValue,
        'image_urls': imageUrls,
        'brand': brand,
        'gtin': gtin,
        'mpn': mpn,
        'category_id': categoryId,
        'category_path': categoryPath,
        'google_product_category': googleProductCategory,
        'merchant_eligible': merchantEligible,
        'merchant_issues':
            merchantIssues.map((issue) => issue.code).toList(growable: false),
      };

  static PublicCommerceProductProjection _build({
    required String id,
    required String sku,
    required String title,
    required String description,
    required double price,
    required String currency,
    required bool available,
    required List<String> imageUrls,
    required String brand,
    required String gtin,
    required String mpn,
    required String? categoryId,
    required String categoryPath,
    required String googleProductCategory,
  }) {
    final availability = available
        ? PublicCommerceAvailability.inStock
        : PublicCommerceAvailability.outOfStock;
    final hasVerifiableBrand = _isVerifiableBrand(brand);
    final issues = <PublicCommerceEligibilityIssue>[
      if (id.trim().isEmpty) PublicCommerceEligibilityIssue.missingIdentity,
      if (title.trim().isEmpty) PublicCommerceEligibilityIssue.missingTitle,
      if (description.trim().isEmpty)
        PublicCommerceEligibilityIssue.missingDescription,
      if (!price.isFinite || price <= 0)
        PublicCommerceEligibilityIssue.invalidPrice,
      if (imageUrls.isEmpty) PublicCommerceEligibilityIssue.missingImage,
      if (!hasVerifiableBrand) PublicCommerceEligibilityIssue.missingBrand,
      if (gtin.isEmpty && (!hasVerifiableBrand || mpn.trim().isEmpty))
        PublicCommerceEligibilityIssue.missingProductIdentifiers,
    ];

    return PublicCommerceProductProjection(
      id: id.trim(),
      sku: sku.trim(),
      title: storefrontDisplayTitle(title),
      description: storefrontDisplayText(description),
      price: price,
      currency: currency.trim().toUpperCase(),
      availability: availability,
      imageUrls: List.unmodifiable(imageUrls),
      brand: brand.trim(),
      gtin: gtin,
      mpn: mpn.trim(),
      categoryId: categoryId?.trim() ?? '',
      categoryPath: categoryPath.trim(),
      googleProductCategory: googleProductCategory.trim(),
      merchantIssues: List.unmodifiable(issues),
    );
  }
}

/// Builds a truthful, useful meta-description when the catalog owner has not
/// supplied product copy yet.
///
/// This is deliberately separate from [description]: it must not make a
/// product Merchant-eligible or pretend that generic SEO copy is authoritative
/// catalog content. Runtime and static snapshots share it only as a final
/// metadata fallback.
String buildPublicProductSeoDescription({
  required PublicCommerceProductProjection product,
  required String storeName,
}) {
  return buildPublicProductSeoFallbackDescription(
    product: PublicProductSeoProductInput(
      name: product.title,
      sku: product.sku,
      price: product.price,
      brand: product.brand,
      description: product.description,
      categoryPath: product.categoryPath,
    ),
    storeName: storeName,
  );
}

/// Collapses whitespace a catalog operator never meant to publish.
///
/// Product names are typed in the ERP, where a line break or a double space is
/// invisible. On the storefront they are not: an embedded newline splits an H1
/// across two lines mid-phrase, and a double space shows up in the middle of a
/// title. Measured on the live catalog: 25 names carry a line break or tab and
/// 18 carry a double space.
///
/// Presentation-layer only — the ERP row is untouched, and this also guards
/// every future entry rather than one round of data cleanup.
String storefrontDisplayText(String raw) {
  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// [storefrontDisplayText] plus the ERP's unit-of-measure marker.
///
/// `C/U` ("cada uno") is a stock-keeping unit of measure, not part of a product
/// name — "CADENA ... Z8.3 DISPLAY KMC C/U" should read "... KMC". Only this
/// marker is stripped: trailing words like `PAR` or `SET` are genuine product
/// information for bike parts sold in pairs or kits, so removing them would
/// destroy meaning rather than noise.
String storefrontDisplayTitle(String raw) {
  final normalized = storefrontDisplayText(raw);
  final withoutUnit = normalized.replaceFirst(
    RegExp(r'[\s,\-–—]*\bc\s*/\s*u\.?$', caseSensitive: false),
    '',
  );
  final trimmed = withoutUnit.trim();
  // Never let normalisation empty a title that had content.
  return trimmed.isEmpty ? normalized : trimmed;
}

String _firstNonEmpty(
  dynamic first, [
  dynamic second,
  dynamic third,
  dynamic fourth,
]) {
  for (final value in [first, second, third, fourth]) {
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString());
}

int? _toInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString());
}

List<String> _productImageUrls(Product product) {
  final websitePrimaryVariants = [
    product.websiteImageUrlOptimized,
    product.websiteImageUrl,
  ];
  final catalogPrimaryVariants = [
    product.imageUrlOptimized,
    product.imageUrl,
  ];
  final primaryVariants = _hasPublicImageUrl(websitePrimaryVariants)
      ? websitePrimaryVariants
      : catalogPrimaryVariants;
  final gallery = product.websiteImageUrls.isNotEmpty
      ? product.websiteImageUrls
      : product.imageUrls;

  return _collectPrimaryAndGalleryImageUrls(
    primaryVariants: primaryVariants,
    gallery: gallery,
  );
}

List<String> _jsonImageUrls(Map<String, dynamic> product) {
  final websiteGallery = product['website_image_urls'];
  final baseGallery = product['image_urls'];
  final gallery = websiteGallery is List && websiteGallery.isNotEmpty
      ? websiteGallery
      : baseGallery is List
          ? baseGallery
          : const [];
  final websitePrimaryVariants = [
    product['website_image_url_optimized'],
    product['website_image_url'],
  ];
  final catalogPrimaryVariants = [
    product['image_url_optimized'],
    product['image_url'],
  ];
  final primaryVariants = _hasPublicImageUrl(websitePrimaryVariants)
      ? websitePrimaryVariants
      : catalogPrimaryVariants;

  return _collectPrimaryAndGalleryImageUrls(
    primaryVariants: primaryVariants,
    gallery: gallery,
  );
}

List<String> _collectPrimaryAndGalleryImageUrls({
  required Iterable<dynamic> primaryVariants,
  required Iterable<dynamic> gallery,
}) {
  final normalizedPrimaryVariants =
      primaryVariants.map(_publicImageUrlOrNull).whereType<String>().toSet();
  final primary = normalizedPrimaryVariants.isEmpty
      ? null
      : normalizedPrimaryVariants.first;

  return _collectPublicImageUrls([
    primary,
    ...gallery.where((value) {
      final url = _publicImageUrlOrNull(value);
      return url == null || !normalizedPrimaryVariants.contains(url);
    }),
  ]);
}

bool _hasPublicImageUrl(Iterable<dynamic> values) {
  return values.any((value) => _publicImageUrlOrNull(value) != null);
}

String? _publicImageUrlOrNull(dynamic value) {
  final url = (value ?? '').toString().trim();
  if (!url.startsWith('https://') && !url.startsWith('http://')) {
    return null;
  }
  return url;
}

List<String> _collectPublicImageUrls(Iterable<dynamic> values) {
  final urls = <String>[];
  for (final value in values) {
    final url = _publicImageUrlOrNull(value);
    if (url == null || urls.contains(url)) {
      continue;
    }
    urls.add(url);
    if (urls.length == 10) break;
  }
  return urls;
}

bool _isVerifiableBrand(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[áàäâ]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöô]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u');
  if (normalized.isEmpty) return false;
  return !const {
    'generico',
    'generic',
    'china',
    'taiwan',
    'aliexpress',
  }.contains(normalized);
}
