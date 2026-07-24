/// Product type applied to a public catalog destination.
enum WebsiteCatalogProductTypeFilter { product, service }

extension WebsiteCatalogProductTypeFilterX on WebsiteCatalogProductTypeFilter {
  String get storageValue => name;

  static WebsiteCatalogProductTypeFilter? tryParse(Object? raw) {
    return switch (raw?.toString().trim().toLowerCase()) {
      'product' ||
      'producto' ||
      'productos' =>
        WebsiteCatalogProductTypeFilter.product,
      'service' ||
      'servicio' ||
      'servicios' =>
        WebsiteCatalogProductTypeFilter.service,
      _ => null,
    };
  }
}

/// Defines whether a category destination includes its descendants.
///
/// [subtree] is the public collection represented by the clean category route:
/// products assigned to the category itself and to any descendant category.
/// [direct] is an explicit visitor refinement that includes only products
/// assigned directly to the selected category.
enum WebsiteCatalogCategoryScope { subtree, direct }

extension WebsiteCatalogCategoryScopeX on WebsiteCatalogCategoryScope {
  String get storageValue => name;

  static WebsiteCatalogCategoryScope? tryParse(Object? raw) {
    return switch (raw?.toString().trim().toLowerCase()) {
      'subtree' => WebsiteCatalogCategoryScope.subtree,
      'direct' => WebsiteCatalogCategoryScope.direct,
      _ => null,
    };
  }
}

/// Additional availability filter selected by a visitor.
///
/// A null value means that the website's canonical publication/stock policy is
/// authoritative. These values may narrow that result, but must never broaden
/// the catalog beyond the public policy.
enum WebsiteCatalogStockFilter { available, unavailable, all }

extension WebsiteCatalogStockFilterX on WebsiteCatalogStockFilter {
  String get storageValue => name;

  static WebsiteCatalogStockFilter? tryParse(Object? raw) {
    return switch (raw?.toString().trim().toLowerCase()) {
      'available' ||
      'available_only' ||
      'in_stock' ||
      'with_stock' ||
      'con_stock' ||
      'true' ||
      '1' =>
        WebsiteCatalogStockFilter.available,
      'unavailable' ||
      'out_of_stock' ||
      'out_of_stock_only' ||
      'sin_stock' =>
        WebsiteCatalogStockFilter.unavailable,
      'all' ||
      'both' ||
      'todos' ||
      'false' ||
      '0' =>
        WebsiteCatalogStockFilter.all,
      _ => null,
    };
  }
}

enum WebsiteCatalogSort { name, priceAsc, priceDesc, newest }

extension WebsiteCatalogSortX on WebsiteCatalogSort {
  String get storageValue => switch (this) {
        WebsiteCatalogSort.name => 'name',
        WebsiteCatalogSort.priceAsc => 'price_asc',
        WebsiteCatalogSort.priceDesc => 'price_desc',
        WebsiteCatalogSort.newest => 'newest',
      };

  static WebsiteCatalogSort? tryParse(Object? raw) {
    return switch (raw?.toString().trim().toLowerCase()) {
      'name' || 'nombre' => WebsiteCatalogSort.name,
      'price_asc' || 'price-asc' || 'precio_asc' => WebsiteCatalogSort.priceAsc,
      'price_desc' ||
      'price-desc' ||
      'precio_desc' =>
        WebsiteCatalogSort.priceDesc,
      'newest' ||
      'recent' ||
      'recientes' ||
      'nuevos' =>
        WebsiteCatalogSort.newest,
      _ => null,
    };
  }
}

/// Canonical, shareable query state for a public product collection.
///
/// The category itself remains route context (`/productos/categoria/:slug`).
/// This value owns only secondary filters, sorting and pagination. It is not
/// persisted inside `WebsiteCatalogPresentation`.
class WebsiteCatalogQuery {
  WebsiteCatalogQuery({
    String searchQuery = '',
    this.productType,
    this.categoryScope = WebsiteCatalogCategoryScope.subtree,
    Iterable<String> brandIds = const <String>[],
    this.minPrice,
    this.maxPrice,
    this.stock,
    this.sort = WebsiteCatalogSort.name,
    this.page = defaultPage,
    this.pageSize = defaultPageSize,
  })  : searchQuery = _normalizeSearch(searchQuery),
        brandIds = List<String>.unmodifiable(_normalizeBrandIds(brandIds)) {
    _validatePrice(minPrice, 'minPrice');
    _validatePrice(maxPrice, 'maxPrice');
    if (minPrice != null && maxPrice != null && minPrice! > maxPrice!) {
      throw ArgumentError.value(
        '$minPrice..$maxPrice',
        'priceRange',
        'El precio mínimo no puede superar el máximo.',
      );
    }
    if (page < 1) {
      throw ArgumentError.value(page, 'page', 'Debe ser mayor o igual a 1.');
    }
    if (pageSize < 1 || pageSize > maxPageSize) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'Debe estar entre 1 y $maxPageSize.',
      );
    }
  }

  static const int defaultPage = 1;
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  final String searchQuery;
  final WebsiteCatalogProductTypeFilter? productType;
  final WebsiteCatalogCategoryScope categoryScope;
  final List<String> brandIds;
  final double? minPrice;
  final double? maxPrice;
  final WebsiteCatalogStockFilter? stock;
  final WebsiteCatalogSort sort;
  final int page;
  final int pageSize;

  /// Decodes canonical query parameters and supported compatibility aliases.
  ///
  /// Invalid filters return null instead of being silently discarded. This is
  /// especially important for prices: dropping an invalid bound would broaden
  /// the destination beyond what its author selected.
  static WebsiteCatalogQuery? tryParse(Uri uri) {
    final parameters = uri.queryParameters;

    final rawType = _firstNonEmpty(parameters, const [
      'type',
      'product_type',
      'tipo',
    ]);
    final productType = WebsiteCatalogProductTypeFilterX.tryParse(rawType);
    if (rawType != null && productType == null) return null;

    final rawCategoryScope = _firstPresent(parameters, const [
      'category_scope',
    ]);
    final categoryScope = rawCategoryScope == null
        ? WebsiteCatalogCategoryScope.subtree
        : WebsiteCatalogCategoryScopeX.tryParse(rawCategoryScope);
    if (categoryScope == null) return null;

    final rawMinPrice = _firstPresent(parameters, const [
      'min_price',
      'price_min',
      'precio_min',
    ]);
    final rawMaxPrice = _firstPresent(parameters, const [
      'max_price',
      'price_max',
      'precio_max',
    ]);
    final minPrice = _parsePrice(rawMinPrice);
    final maxPrice = _parsePrice(rawMaxPrice);
    if ((rawMinPrice != null && minPrice == null) ||
        (rawMaxPrice != null && maxPrice == null) ||
        (minPrice != null && maxPrice != null && minPrice > maxPrice)) {
      return null;
    }

    final rawStock = _firstNonEmpty(parameters, const [
      'stock',
      'availability',
      'disponibilidad',
      'only_in_stock',
    ]);
    final stock = WebsiteCatalogStockFilterX.tryParse(rawStock);
    if (rawStock != null && stock == null) return null;

    final rawSort = _firstNonEmpty(parameters, const [
      'sort',
      'sort_by',
      'orden',
    ]);
    final sort = rawSort == null
        ? WebsiteCatalogSort.name
        : WebsiteCatalogSortX.tryParse(rawSort);
    if (sort == null) return null;

    final rawPage = _firstNonEmpty(parameters, const ['page', 'pagina']);
    final rawPageSize = _firstNonEmpty(parameters, const [
      'page_size',
      'per_page',
      'limit',
    ]);
    final page = rawPage == null ? defaultPage : int.tryParse(rawPage);
    final pageSize =
        rawPageSize == null ? defaultPageSize : int.tryParse(rawPageSize);
    if (page == null ||
        page < 1 ||
        pageSize == null ||
        pageSize < 1 ||
        pageSize > maxPageSize) {
      return null;
    }

    final rawBrands = _firstNonEmpty(parameters, const [
      'brand',
      'brands',
      'brand_id',
      'brand_ids',
      'marca',
      'marcas',
    ]);

    try {
      return WebsiteCatalogQuery(
        searchQuery: _firstNonEmpty(parameters, const ['q', 'search']) ?? '',
        productType: productType,
        categoryScope: categoryScope,
        brandIds: rawBrands?.split(',') ?? const <String>[],
        minPrice: minPrice,
        maxPrice: maxPrice,
        stock: stock,
        sort: sort,
        page: page,
        pageSize: pageSize,
      );
    } on ArgumentError {
      return null;
    }
  }

  factory WebsiteCatalogQuery.fromUri(Uri uri) {
    final query = tryParse(uri);
    if (query == null) {
      throw const FormatException('Filtros de catálogo inválidos.');
    }
    return query;
  }

  /// Canonical order is intentional and stable for destinations, comparisons
  /// and audit output. Defaults are omitted so equivalent URLs stay identical.
  Map<String, String> toQueryParameters() {
    final result = <String, String>{};
    if (searchQuery.isNotEmpty) result['q'] = searchQuery;
    if (productType != null) result['type'] = productType!.storageValue;
    if (categoryScope == WebsiteCatalogCategoryScope.direct) {
      result['category_scope'] = categoryScope.storageValue;
    }
    if (brandIds.isNotEmpty) result['brand'] = brandIds.join(',');
    if (minPrice != null) result['min_price'] = _formatPrice(minPrice!);
    if (maxPrice != null) result['max_price'] = _formatPrice(maxPrice!);
    if (stock != null) result['stock'] = stock!.storageValue;
    if (sort != WebsiteCatalogSort.name) result['sort'] = sort.storageValue;
    if (page != defaultPage) result['page'] = '$page';
    if (pageSize != defaultPageSize) result['page_size'] = '$pageSize';
    return result;
  }

  static String _normalizeSearch(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static List<String> _normalizeBrandIds(Iterable<String> raw) {
    final values = raw
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map((value) {
          if (!_uuidPattern.hasMatch(value)) {
            throw ArgumentError.value(
              value,
              'brandIds',
              'Cada marca debe usar su identificador UUID canónico.',
            );
          }
          return value.toLowerCase();
        })
        .toSet()
        .toList(growable: false)
      ..sort();
    return values;
  }

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String? _firstNonEmpty(
    Map<String, String> parameters,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = parameters[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String? _firstPresent(
    Map<String, String> parameters,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (parameters.containsKey(key)) return parameters[key]?.trim() ?? '';
    }
    return null;
  }

  static double? _parsePrice(String? raw) {
    if (raw == null) return null;
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite || value < 0) return null;
    return value;
  }

  static void _validatePrice(double? value, String name) {
    if (value != null && (!value.isFinite || value < 0)) {
      throw ArgumentError.value(value, name, 'Debe ser un número no negativo.');
    }
  }

  static String _formatPrice(double value) {
    if (value == value.truncateToDouble()) return value.toInt().toString();
    return value.toString();
  }
}
