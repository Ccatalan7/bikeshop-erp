import 'product.dart';

enum PublicCatalogStockPolicy {
  availableOnly,
  outOfStockOnly,
  all,
}

extension PublicCatalogStockPolicyLabel on PublicCatalogStockPolicy {
  String get label {
    switch (this) {
      case PublicCatalogStockPolicy.availableOnly:
        return 'Con stock';
      case PublicCatalogStockPolicy.outOfStockOnly:
        return 'Sin stock';
      case PublicCatalogStockPolicy.all:
        return 'Ambos';
    }
  }

  String get storageValue {
    switch (this) {
      case PublicCatalogStockPolicy.availableOnly:
        return 'available_only';
      case PublicCatalogStockPolicy.outOfStockOnly:
        return 'out_of_stock_only';
      case PublicCatalogStockPolicy.all:
        return 'all';
    }
  }

  static PublicCatalogStockPolicy fromStorageValue(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'out_of_stock_only':
      case 'out-of-stock-only':
      case 'out_of_stock':
      case 'sin_stock':
        return PublicCatalogStockPolicy.outOfStockOnly;
      case 'all':
      case 'both':
      case 'ambos':
        return PublicCatalogStockPolicy.all;
      case 'available_only':
      case 'in_stock_only':
      case 'with_stock':
      case 'con_stock':
      default:
        return PublicCatalogStockPolicy.availableOnly;
    }
  }
}

class PublicProductVisibilityPolicy {
  const PublicProductVisibilityPolicy({
    this.stockPolicy = PublicCatalogStockPolicy.availableOnly,
    this.requireImage = false,
    this.requireVisibleCategory = false,
    this.includeUncategorized = true,
  });

  static const stockPolicyKey = 'product_visibility_stock_policy';
  static const requireImageKey = 'product_visibility_require_image';
  static const requireVisibleCategoryKey =
      'product_visibility_require_visible_category';
  static const includeUncategorizedKey =
      'product_visibility_include_uncategorized';
  static const settingKeys = <String>[
    stockPolicyKey,
    requireImageKey,
    requireVisibleCategoryKey,
    includeUncategorizedKey,
  ];

  /// Whether a search lets the visitor include what is out of stock
  /// («Incluir agotados», 2026-10-24): `offer` (the default without a row)
  /// or `hide`, edited in the ERP's «Reglas de la tienda». The database
  /// decides it (`get_public_products`, 20261024050000); a page reads it to
  /// offer the option.
  static const searchOutOfStockKey = 'product_visibility_search_out_of_stock';

  /// A search can widen to what is out of stock: the store keeps it out of
  /// its listings (with «aparecen en los listados» a search shows it already)
  /// and offers it.
  static bool offersOutOfStockSearch(Map<String, String> settings) =>
      PublicCatalogStockPolicyLabel.fromStorageValue(
            settings[stockPolicyKey],
          ) ==
          PublicCatalogStockPolicy.availableOnly &&
      (settings[searchOutOfStockKey] ?? '').trim().toLowerCase() != 'hide';

  static bool hasAnySetting(Map<String, String> settings) {
    return settingKeys.any(settings.containsKey);
  }

  final PublicCatalogStockPolicy stockPolicy;
  final bool requireImage;
  final bool requireVisibleCategory;
  final bool includeUncategorized;

  factory PublicProductVisibilityPolicy.fromSettings(
    Map<String, String> settings,
  ) {
    return PublicProductVisibilityPolicy(
      stockPolicy: PublicCatalogStockPolicyLabel.fromStorageValue(
        settings[stockPolicyKey],
      ),
      requireImage: _settingBool(settings[requireImageKey], false),
      requireVisibleCategory: _settingBool(
        settings[requireVisibleCategoryKey],
        false,
      ),
      includeUncategorized: _settingBool(
        settings[includeUncategorizedKey],
        true,
      ),
    );
  }

  Map<String, String> toSettings() {
    return {
      stockPolicyKey: stockPolicy.storageValue,
      requireImageKey: requireImage.toString(),
      requireVisibleCategoryKey: requireVisibleCategory.toString(),
      includeUncategorizedKey: includeUncategorized.toString(),
    };
  }

  PublicProductVisibilityPolicy copyWith({
    PublicCatalogStockPolicy? stockPolicy,
    bool? requireImage,
    bool? requireVisibleCategory,
    bool? includeUncategorized,
  }) {
    return PublicProductVisibilityPolicy(
      stockPolicy: stockPolicy ?? this.stockPolicy,
      requireImage: requireImage ?? this.requireImage,
      requireVisibleCategory:
          requireVisibleCategory ?? this.requireVisibleCategory,
      includeUncategorized: includeUncategorized ?? this.includeUncategorized,
    );
  }

  bool allowsProduct(
    Product product, {
    Set<String>? visibleCategoryIds,
  }) {
    if (!product.isActive || !product.isPublished) return false;

    if (!_allowsStock(product)) return false;
    if (requireImage && !_hasPublicImage(product)) return false;
    if (requireVisibleCategory) {
      final categoryId = product.categoryId?.trim();
      if (categoryId == null || categoryId.isEmpty) {
        if (!includeUncategorized) return false;
      } else if (visibleCategoryIds != null &&
          !visibleCategoryIds.contains(categoryId)) {
        return false;
      }
    }

    return true;
  }

  bool _allowsStock(Product product) {
    if (product.productType == ProductType.service) return true;
    final tracksStock = product.trackStock;
    final hasStock = product.stockQuantity > 0;

    switch (stockPolicy) {
      case PublicCatalogStockPolicy.availableOnly:
        return !tracksStock || hasStock;
      case PublicCatalogStockPolicy.outOfStockOnly:
        return tracksStock && !hasStock;
      case PublicCatalogStockPolicy.all:
        return true;
    }
  }

  static bool _hasPublicImage(Product product) {
    return _notBlank(product.websiteImageUrl) ||
        _notBlank(product.websiteImageUrlOptimized) ||
        product.websiteImageUrls.any(_notBlank) ||
        _notBlank(product.imageUrl) ||
        _notBlank(product.imageUrlOptimized) ||
        product.imageUrls.any(_notBlank);
  }

  static bool _settingBool(String? raw, bool fallback) {
    if (raw == null) return fallback;
    switch (raw.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'si':
      case 'sí':
        return true;
      case 'false':
      case '0':
      case 'no':
        return false;
      default:
        return fallback;
    }
  }

  static bool _notBlank(String? value) => value?.trim().isNotEmpty == true;
}
