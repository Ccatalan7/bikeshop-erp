import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
// import '../theme/public_store_theme.dart'; // Unused
import '../services/catalog_page_prefetch_cache.dart';
import '../services/public_inventory_service.dart';
import '../services/public_store_scroll_state.dart';
import '../../shared/models/product.dart';
import '../../shared/models/public_product_visibility_policy.dart';
import '../../shared/utils/chilean_utils.dart';
import '../../shared/utils/seo_helper.dart';
// import '../providers/cart_provider.dart'; // Unused
import '../widgets/full_page_loading.dart';
import '../widgets/catalog_collection_presentation.dart';
import '../utils/product_url.dart';
import '../utils/public_store_tenant_resolver.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../modules/website/models/website_catalog_presentation.dart';
import '../../modules/website/models/website_catalog_query.dart';
import '../../modules/website/services/website_service.dart';
import '../../shared/widgets/safe_layout_builder.dart';
import '../widgets/public_store_layout.dart';

void _catalogDebugLog(String message) {
  if (kDebugMode || const bool.fromEnvironment('STORE_PERF_LOGS')) {
    debugPrint(message);
  }
}

class ProductCatalogPage extends StatefulWidget {
  const ProductCatalogPage({super.key});

  @override
  State<ProductCatalogPage> createState() => _ProductCatalogPageState();
}

@visibleForTesting
Set<String> resolveCatalogCategoryIdsForScope({
  required String selectedCategoryId,
  required WebsiteCatalogCategoryScope scope,
  required Iterable<String> subtreeCategoryIds,
}) {
  if (scope == WebsiteCatalogCategoryScope.direct) {
    return Set<String>.unmodifiable({selectedCategoryId});
  }

  return Set<String>.unmodifiable({
    selectedCategoryId,
    ...subtreeCategoryIds,
  });
}

@visibleForTesting
int resolveCatalogPageFromTotalCount({
  required int requestedPage,
  required int pageSize,
  required int totalCount,
}) {
  assert(pageSize > 0);
  final totalPages = totalCount <= 0 ? 1 : ((totalCount - 1) ~/ pageSize) + 1;
  return requestedPage.clamp(1, totalPages).toInt();
}

/// Represents a category node in the hierarchical tree
class _CategoryNode {
  final String id;
  final String name;
  final String fullPath;
  final String? parentId;
  final String description;
  final String imageUrl;
  final int sortOrder;
  final bool showOnWebsite;
  final List<_CategoryNode> children;

  _CategoryNode({
    required this.id,
    required this.name,
    required this.fullPath,
    this.parentId,
    this.description = '',
    this.imageUrl = '',
    this.sortOrder = 0,
    this.showOnWebsite = false,
    List<_CategoryNode>? children,
  }) : children = children ?? [];

  /// Get all descendant IDs (children, grandchildren, etc.)
  Set<String> getAllDescendantIds() {
    final result = <String>{id};
    for (final child in children) {
      result.addAll(child.getAllDescendantIds());
    }
    return result;
  }
}

class _ProductCatalogPageState extends State<ProductCatalogPage>
    with AutomaticKeepAliveClientMixin {
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _hasLoadedInitialProducts = false;
  int _totalProductCount = 0;
  int _categoryTotalCount = 0;
  int _loadToken = 0;
  int? _facetCategoryCountsLoadToken;
  String _lastCategoryCountsSignature = '';
  String? _activeCatalogPageSignature;
  String? _lastLoggedModeKey;
  String? _lastDependencyModeKey;
  String? _lastSeoSignature;
  Timer? _searchDebounce;
  PublicInventoryService? _observedInventoryService;
  String? _loadedCategoriesTenantId;
  bool _inventoryInvalidationScheduled = false;
  WebsiteCatalogPresentationRegistry _presentationRegistry =
      const WebsiteCatalogPresentationRegistry({});
  final CatalogPagePrefetchCache<PublicProductPage> _catalogPageCache =
      CatalogPagePrefetchCache<PublicProductPage>(
    maxAge: const Duration(seconds: 30),
    maxEntries: 6,
  );
  final CatalogPagePrefetchCache<PublicCatalogFacetSnapshot>
      _catalogFacetCache = CatalogPagePrefetchCache<PublicCatalogFacetSnapshot>(
    maxAge: const Duration(seconds: 30),
    maxEntries: 1,
    shouldCache: (snapshot) => snapshot.isAvailable,
  );

  // Hierarchical category tree (only root-level visible categories)
  List<_CategoryNode> _categoryTree = [];

  // All categories indexed by ID for quick lookup
  Map<String, _CategoryNode> _allCategoriesById = {};
  Map<String, int> _directCategoryProductCounts = {};

  // Track which parent categories are expanded in the UI
  final Set<String> _expandedCategories = {};

  final TextEditingController _filtersSearchController =
      TextEditingController();
  final FocusNode _filtersSearchFocusNode = FocusNode();
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 20; // Default: 20 items per page
  static const List<int> _itemsPerPageOptions = [20, 50, 100];

  String _searchQuery = '';
  String _lastRouteFiltersSignature = '';
  final Set<String> _selectedBrandIds = <String>{};
  double? _minPrice;
  double? _maxPrice;
  String? _priceFilterError;
  String? _catalogQueryError;
  String? _catalogLoadError;
  PublicCatalogFacetSnapshot _catalogFacets =
      const PublicCatalogFacetSnapshot.unavailable();
  bool _showAllBrands = false;
  String? _selectedCategoryId;
  ProductType? _selectedProductType = ProductType.product;
  String? _pendingRouteCategoryValue;
  String? _categoryRouteError;
  String _sortBy = 'name'; // name, price_asc, price_desc, newest
  WebsiteCatalogStockFilter? _stockFilter;
  WebsiteCatalogCategoryScope _categoryScope =
      WebsiteCatalogCategoryScope.subtree;

  bool get _onlyInStock => _stockFilter == WebsiteCatalogStockFilter.available;
  bool get _isDirectCategoryScope =>
      _selectedCategoryId != null &&
      _categoryScope == WebsiteCatalogCategoryScope.direct;

  // DISABLED: AutomaticKeepAliveClientMixin causes element activation conflicts
  // during edit/preview mode switches. The performance cost of reloading is acceptable.
  @override
  bool get wantKeepAlive => false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inventoryService = context.read<PublicInventoryService>();
    if (!identical(_observedInventoryService, inventoryService)) {
      _observedInventoryService
          ?.removeListener(_handlePublicInventoryInvalidated);
      _observedInventoryService = inventoryService
        ..addListener(_handlePublicInventoryInvalidated);
    }
    final editProvider = context.read<WebsiteEditModeProvider>();
    final modeKey = editProvider.isEditMode
        ? 'edit'
        : (editProvider.isPreviewMode ? 'preview' : 'normal');
    final shouldReloadForMode =
        _lastDependencyModeKey != null && _lastDependencyModeKey != modeKey;
    _lastDependencyModeKey = modeKey;
    _syncFiltersFromRoute(reloadForModeChange: shouldReloadForMode);
  }

  void _handlePublicInventoryInvalidated() {
    _loadToken++;
    _activeCatalogPageSignature = null;
    _catalogPageCache.clear();
    _catalogFacetCache.clear();
    if (!mounted || _inventoryInvalidationScheduled) return;
    _inventoryInvalidationScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inventoryInvalidationScheduled = false;
      if (!mounted) return;
      setState(() {
        _loadedCategoriesTenantId = null;
        _catalogFacets = const PublicCatalogFacetSnapshot.unavailable();
        _directCategoryProductCounts = const {};
        _categoryTotalCount = 0;
      });
      unawaited(
        _loadProducts(
          resetPage: false,
          forceCategoryRefresh: true,
        ),
      );
    });
  }

  void _syncFiltersFromRoute({bool reloadForModeChange = false}) {
    final uri = GoRouterState.of(context).uri;
    final qp = uri.queryParameters;
    final routePath = uri.path.trim().toLowerCase();
    final legacyCategoria = (qp['categoria'] ?? '').trim();
    final catalogQuery = WebsiteCatalogQuery.tryParse(uri);
    var routeQuery = catalogQuery?.searchQuery ?? '';
    final routeCategoryFromPath = _categoryValueFromPath(uri.path);
    final routeCategory = (routeCategoryFromPath ??
            qp['category'] ??
            qp['category_id'] ??
            qp['cat'] ??
            '')
        .trim();
    final routeType = catalogQuery?.productType?.storageValue ?? '';

    // Backward-compat: historically, some website links used `?categoria=mtb`
    // as a collection-style filter. We now treat that value as a free-text
    // search term (so it never “forces” the catalog into a wrong category).
    if (routeQuery.isEmpty && legacyCategoria.isNotEmpty) {
      routeQuery = legacyCategoria;
    }

    final signature = uri.toString();
    if (signature == _lastRouteFiltersSignature && !reloadForModeChange) {
      return;
    }
    _lastRouteFiltersSignature = signature;

    final parsedType = _parseProductType(routeType);
    final routeDefaultType = _defaultProductTypeForRoute(routePath);
    final routeCategoryScope =
        catalogQuery?.categoryScope ?? WebsiteCatalogCategoryScope.subtree;
    final hasInvalidDirectScope = routeCategory.isEmpty &&
        routeCategoryScope == WebsiteCatalogCategoryScope.direct;

    // Avoid calling setState during build (this page can be kept-alive/offstage).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      String? resolvedAliasCategoryId;

      setState(() {
        _catalogQueryError = catalogQuery == null
            ? 'La URL contiene filtros de catálogo inválidos.'
            : hasInvalidDirectScope
                ? 'El alcance directo necesita una categoría válida.'
                : catalogQuery.stock == WebsiteCatalogStockFilter.unavailable
                    ? 'El filtro exclusivo de productos agotados todavía no está disponible.'
                    : null;
        _searchQuery = routeQuery;
        _selectedProductType = parsedType ?? routeDefaultType;
        _selectedBrandIds
          ..clear()
          ..addAll(catalogQuery?.brandIds ?? const <String>[]);
        _minPrice = catalogQuery?.minPrice;
        _maxPrice = catalogQuery?.maxPrice;
        _stockFilter =
            catalogQuery?.stock == WebsiteCatalogStockFilter.available
                ? WebsiteCatalogStockFilter.available
                : null;
        _categoryScope = routeCategory.isEmpty
            ? WebsiteCatalogCategoryScope.subtree
            : routeCategoryScope;
        _sortBy = catalogQuery?.sort.storageValue ?? 'name';
        _currentPage = catalogQuery?.page ?? 1;
        _itemsPerPage = catalogQuery?.pageSize ?? 20;
        _syncPriceControllers();

        // Keep the visible search field in sync so users can see
        // what term is currently filtering the catalog.
        if (_filtersSearchController.text != routeQuery) {
          _filtersSearchController.value =
              _filtersSearchController.value.copyWith(
            text: routeQuery,
            selection: TextSelection.collapsed(offset: routeQuery.length),
            composing: TextRange.empty,
          );
        }

        if (routeCategory.isEmpty) {
          _selectedCategoryId = null;
          _pendingRouteCategoryValue = null;
          _categoryRouteError = null;
        } else {
          final resolved = _resolveCategoryIdFromValue(routeCategory);
          if (resolved == null && routeCategoryFromPath != null) {
            // A clean collection path is authoritative route context. Keep it
            // pending until the real category registry is loaded; never turn
            // an unknown collection slug into an unrelated search result.
            _selectedCategoryId = null;
            _pendingRouteCategoryValue = routeCategory;
            _categoryRouteError = null;
          } else if (resolved == null && !_looksLikeUuid(routeCategory)) {
            // If `category` is a non-UUID string we can't resolve, treat it as
            // a search token instead of defaulting to an arbitrary category.
            if (_searchQuery.isEmpty) {
              _searchQuery = routeCategory;
              if (_filtersSearchController.text != routeCategory) {
                _filtersSearchController.value =
                    _filtersSearchController.value.copyWith(
                  text: routeCategory,
                  selection:
                      TextSelection.collapsed(offset: routeCategory.length),
                  composing: TextRange.empty,
                );
              }
            }
            _selectedCategoryId = null;
            _pendingRouteCategoryValue = null;
          } else {
            _selectedCategoryId = resolved;
            _pendingRouteCategoryValue =
                resolved == null ? routeCategory : null;
            _categoryRouteError = null;
            if (resolved != null &&
                routeCategoryFromPath != null &&
                _isAliasForCategory(routeCategory, resolved)) {
              resolvedAliasCategoryId = resolved;
            }
          }
        }
      });

      if (resolvedAliasCategoryId != null &&
          _replaceResolvedCategoryAlias(
            rawSlug: routeCategory,
            categoryId: resolvedAliasCategoryId!,
          )) {
        return;
      }
      if (reloadForModeChange) {
        _lastCategoryCountsSignature = '';
        _activeCatalogPageSignature = null;
        _catalogPageCache.clear();
        _catalogFacetCache.clear();
        if (kDebugMode) {
          debugPrint(
            '🧭 [StoreModeTrace][Catalog] RELOAD_FOR_MODE '
            'mode=$_lastDependencyModeKey uri=${GoRouterState.of(context).uri}',
          );
        }
        // The URL is authoritative during a mode transition. In particular,
        // keep a direct/back-forward `?page=N` request on that page instead of
        // silently loading page 1 under a page-N URL.
        unawaited(
          _loadProducts(
            resetPage: false,
            forceCategoryRefresh: true,
          ),
        );
      } else {
        _handleFiltersChanged(resetPage: false);
      }
    });
  }

  void _syncPriceControllers() {
    final minText = _formatPriceInput(_minPrice);
    final maxText = _formatPriceInput(_maxPrice);
    if (_minPriceController.text != minText) {
      _minPriceController.text = minText;
    }
    if (_maxPriceController.text != maxText) {
      _maxPriceController.text = maxText;
    }
  }

  String _formatPriceInput(double? value) {
    if (value == null) return '';
    return value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  ProductType? _parseProductType(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    if (v == 'service' || v == 'servicio' || v == 'servicios') {
      return ProductType.service;
    }
    if (v == 'product' || v == 'producto' || v == 'productos') {
      return ProductType.product;
    }
    return null;
  }

  ProductType _defaultProductTypeForRoute(String path) {
    final normalized =
        path.startsWith('/tienda/') ? path.substring('/tienda'.length) : path;
    if (normalized == '/servicios' ||
        normalized == '/servicios/' ||
        normalized.startsWith('/servicios/')) {
      return ProductType.service;
    }
    return ProductType.product;
  }

  String? _categoryValueFromPath(String path) {
    final normalizedPath =
        path.startsWith('/tienda/') ? path.substring('/tienda'.length) : path;
    final match =
        RegExp(r'^/(?:productos|servicios)/categoria/([^/?#]+)').firstMatch(
      normalizedPath.trim(),
    );
    final raw = match?.group(1);
    if (raw == null || raw.isEmpty) return null;
    return Uri.decodeComponent(raw);
  }

  bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  String? _resolveCategoryIdFromValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // Route identity never overrides category publication. Before categories
    // load this returns null so the value remains pending; afterwards only a
    // category published by the canonical owner can become route context.
    if (_looksLikeUuid(trimmed)) {
      return _allCategoriesById[trimmed]?.showOnWebsite == true
          ? trimmed
          : null;
    }

    final registryClaimCount =
        _presentationRegistry.categorySlugClaimCount(trimmed);
    if (registryClaimCount > 0) {
      final presentation = _presentationRegistry.forSlug(trimmed);
      if (presentation != null &&
          _allCategoriesById[presentation.categoryId]?.showOnWebsite == true) {
        return presentation.categoryId;
      }
      // A stored but ambiguous/unpublished route must not fall through to a
      // similarly named category and silently select a different owner.
      return null;
    }

    final wanted = _normalizeForSearch(trimmed);
    if (wanted.isEmpty) return null;

    final matches = <String>{};
    for (final entry in _allCategoriesById.entries) {
      if (!entry.value.showOnWebsite) continue;
      final normalizedName = _normalizeForSearch(entry.value.name);
      final normalizedPath = _normalizeForSearch(entry.value.fullPath);
      if (normalizedName == wanted ||
          normalizedPath == wanted ||
          websiteCategorySlug(entry.value.name) ==
              websiteCategorySlug(trimmed) ||
          websiteCategorySlug(entry.value.fullPath) ==
              websiteCategorySlug(trimmed)) {
        matches.add(entry.key);
      }
    }

    // Legacy categories without a saved presentation may still resolve by
    // name/full path, but duplicate leaf slugs fail closed.
    return matches.length == 1 ? matches.single : null;
  }

  bool _isAliasForCategory(String rawSlug, String categoryId) {
    final resolution = _presentationRegistry.resolveSlug(rawSlug);
    return resolution?.matchedAlias == true &&
        resolution?.presentation.categoryId == categoryId;
  }

  bool _replaceResolvedCategoryAlias({
    required String rawSlug,
    required String categoryId,
  }) {
    final currentRouteSlug =
        _categoryValueFromPath(GoRouterState.of(context).uri.path);
    if (currentRouteSlug == null ||
        websiteCategorySlug(currentRouteSlug) != websiteCategorySlug(rawSlug) ||
        !_isAliasForCategory(rawSlug, categoryId)) {
      return false;
    }
    return _replaceCategoryRoute(
      categoryId,
      preserveCategoryScope: true,
    );
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty && _filtersSearchController.text.isEmpty) return;
    setState(() {
      _searchQuery = '';
      _filtersSearchController.clear();
    });
    _syncCatalogQueryToRoute(resetPage: true);
    _handleFiltersChanged();
  }

  void _syncCatalogQueryToRoute({bool resetPage = false}) {
    try {
      if (resetPage) _currentPage = 1;
      final current = GoRouterState.of(context).uri;
      final routeIsServices = current.path == '/servicios' ||
          current.path.startsWith('/servicios/') ||
          current.path == '/tienda/servicios' ||
          current.path.startsWith('/tienda/servicios/');
      final routeType = routeIsServices
          ? WebsiteCatalogProductTypeFilter.service
          : WebsiteCatalogProductTypeFilter.product;
      final selectedType = switch (_selectedProductType) {
        ProductType.product => WebsiteCatalogProductTypeFilter.product,
        ProductType.service => WebsiteCatalogProductTypeFilter.service,
        _ => null,
      };
      final query = WebsiteCatalogQuery(
        searchQuery: _searchQuery,
        productType: selectedType == routeType ? null : selectedType,
        brandIds: _selectedBrandIds,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        stock: _stockFilter,
        categoryScope: _categoryScope,
        sort: WebsiteCatalogSortX.tryParse(_sortBy) ?? WebsiteCatalogSort.name,
        page: _currentPage,
        pageSize: _itemsPerPage,
      );

      final nextParameters = Map<String, String>.from(current.queryParameters);
      for (final key in const {
        'q',
        'search',
        'type',
        'product_type',
        'tipo',
        'brand',
        'brands',
        'brand_id',
        'brand_ids',
        'marca',
        'marcas',
        'min_price',
        'price_min',
        'precio_min',
        'max_price',
        'price_max',
        'precio_max',
        'stock',
        'availability',
        'disponibilidad',
        'only_in_stock',
        'sort',
        'sort_by',
        'orden',
        'page',
        'pagina',
        'page_size',
        'per_page',
        'limit',
        'category_scope',
      }) {
        nextParameters.remove(key);
      }
      nextParameters.addAll(query.toQueryParameters());
      final destination = Uri(
        path: current.path,
        queryParameters: nextParameters.isEmpty ? null : nextParameters,
      ).toString();
      if (destination == current.toString()) return;
      _lastRouteFiltersSignature = destination;
      GoRouter.of(context).replace(destination);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[ProductCatalogPage] Could not sync catalog URL: $error');
      }
    }
  }

  String _catalogPageSignature({
    required String tenantId,
    required List<String>? categoryIds,
    required String searchQuery,
    required ProductType? productType,
    required PublicProductVisibilityPolicy? policy,
    required bool onlyInStock,
    required bool applyAvailabilityFacet,
    required List<String> brandIds,
    required double? minPrice,
    required double? maxPrice,
    required String sortBy,
    required int pageSize,
  }) {
    final categories = [...?categoryIds]..sort();
    final brands = [...brandIds]..sort();
    final policySettings = policy?.toSettings().entries.toList() ?? [];
    policySettings.sort((a, b) => a.key.compareTo(b.key));

    return <String>[
      'catalog-page-v1',
      tenantId,
      categories.join(','),
      searchQuery.trim().toLowerCase(),
      productType?.name ?? '',
      policySettings.map((entry) => '${entry.key}=${entry.value}').join(','),
      onlyInStock.toString(),
      applyAvailabilityFacet.toString(),
      brands.join(','),
      minPrice?.toString() ?? '',
      maxPrice?.toString() ?? '',
      sortBy,
      pageSize.toString(),
    ].map(Uri.encodeComponent).join('|');
  }

  String _catalogFacetSignature({
    required String tenantId,
    required List<String>? categoryIds,
    required String searchQuery,
    required ProductType? productType,
    required PublicProductVisibilityPolicy? policy,
    required bool onlyInStock,
    required bool applyAvailabilityFacet,
    required List<String> brandIds,
    required double? minPrice,
    required double? maxPrice,
  }) {
    final categories = [...?categoryIds]..sort();
    final brands = [...brandIds]..sort();
    final policySettings = policy?.toSettings().entries.toList() ?? [];
    policySettings.sort((a, b) => a.key.compareTo(b.key));
    return <String>[
      'catalog-facets-v1',
      tenantId,
      categories.join(','),
      searchQuery.trim().toLowerCase(),
      productType?.name ?? '',
      policySettings.map((entry) => '${entry.key}=${entry.value}').join(','),
      onlyInStock.toString(),
      applyAvailabilityFacet.toString(),
      brands.join(','),
      minPrice?.toString() ?? '',
      maxPrice?.toString() ?? '',
    ].map(Uri.encodeComponent).join('|');
  }

  Future<void> _loadProducts({
    bool resetPage = false,
    bool forceCategoryRefresh = false,
  }) async {
    final token = ++_loadToken;
    if (resetPage) _currentPage = 1;

    final requestSearch = _searchQuery.trim();
    final requestProductType = _selectedProductType;
    final requestApplyAvailabilityFacet = _onlyInStock;
    // The canonical query's own default/site rule remains authoritative. The
    // visitor flag below is an additional narrowing only when explicitly on.
    const requestCanonicalStockPolicy = true;
    final requestBrandIds = _selectedBrandIds.toList(growable: false)..sort();
    final requestMinPrice = _minPrice;
    final requestMaxPrice = _maxPrice;
    final requestCategoryScope = _categoryScope;
    final requestSort = _sortBy;
    final requestPage = _currentPage;
    final requestPageSize = _itemsPerPage;

    // Check if we're in edit mode (admin editing website)
    final editProvider = context.read<WebsiteEditModeProvider>();
    if (kDebugMode) {
      debugPrint(
        '🧭 [StoreCatalogTrace] LOAD_START token=$token '
        'mode=${editProvider.isEditMode ? 'edit' : (editProvider.isPreviewMode ? 'preview' : 'public')} '
        'uri=${GoRouterState.of(context).uri} '
        'category=$_selectedCategoryId pending=$_pendingRouteCategoryValue '
        'type=${_selectedProductType?.name} stock=${_stockFilter?.storageValue ?? 'policy'}',
      );
    }

    final tenantId = await resolvePublicStoreTenantId(context);
    if (!mounted || token != _loadToken) return;

    if (tenantId == null) {
      debugPrint('[ProductCatalogPage] No tenant ID available');
      setState(() {
        _catalogLoadError =
            'No pudimos identificar la tienda para cargar este catálogo.';
        _allProducts = const [];
        _filteredProducts = const [];
        _totalProductCount = 0;
        _isLoading = false;
        _isRefreshing = false;
        _hasLoadedInitialProducts = true;
      });
      return;
    }

    if (_loadedCategoriesTenantId != null &&
        _loadedCategoriesTenantId != tenantId) {
      setState(() {
        _loadedCategoriesTenantId = null;
        _categoryTree = const [];
        _allCategoriesById = const {};
      });
    }

    // Use public inventory service (works for anonymous users)
    final publicInventoryService = context.read<PublicInventoryService>();
    try {
      final websiteService = context.read<WebsiteService>();
      _presentationRegistry = WebsiteCatalogPresentationRegistry.decode(
        websiteService.getSetting(websiteCatalogPresentationsSettingKey),
      );
    } catch (_) {
      _presentationRegistry = const WebsiteCatalogPresentationRegistry({});
    }
    final visibilityPolicy = _readVisibilityPolicy();

    setState(() {
      _catalogLoadError = null;
      if (!_hasLoadedInitialProducts) {
        _isLoading = true;
      }
    });

    if (_catalogQueryError != null) {
      if (mounted && token == _loadToken) {
        setState(() {
          _allProducts = const [];
          _filteredProducts = const [];
          _catalogFacets = const PublicCatalogFacetSnapshot.unavailable();
          _totalProductCount = 0;
          _isLoading = false;
          _isRefreshing = false;
          _hasLoadedInitialProducts = true;
        });
      }
      return;
    }

    try {
      // Load visible categories (show_on_website = true). Start it early so
      // the first product/service page can overlap with filter metadata work.
      final categoriesFuture = _allCategoriesById.isEmpty ||
              _loadedCategoriesTenantId != tenantId ||
              forceCategoryRefresh
          ? _loadVisibleCategories(
              tenantId,
              publicInventoryService,
              token: token,
              forceRefresh: forceCategoryRefresh,
            )
          : Future<void>.value();

      Future<PublicProductPage>? productPageFuture;
      Future<PublicCatalogFacetSnapshot>? facetSnapshotFuture;
      String? productPageSignature;

      Future<PublicProductPage> fetchPageForCategoryIds({
        required List<String>? categoryIds,
        required int pageNumber,
        int? pageLimit,
      }) {
        final effectiveLimit = pageLimit ?? requestPageSize;
        Future<PublicProductPage> loader() {
          return publicInventoryService.getProductPageForTenant(
            tenantId: tenantId,
            categoryIds: categoryIds,
            searchQuery: requestSearch.isEmpty ? null : requestSearch,
            productType: requestProductType,
            policy: visibilityPolicy,
            onlyInStock: requestCanonicalStockPolicy,
            applyAvailabilityFacet: requestApplyAvailabilityFacet,
            brandIds: requestBrandIds,
            minPrice: requestMinPrice,
            maxPrice: requestMaxPrice,
            sortBy: requestSort,
            limit: effectiveLimit,
            offset: (pageNumber - 1) * effectiveLimit,
          );
        }

        if (effectiveLimit != requestPageSize) return loader();
        final signature = _catalogPageSignature(
          tenantId: tenantId,
          categoryIds: categoryIds,
          searchQuery: requestSearch,
          productType: requestProductType,
          policy: visibilityPolicy,
          onlyInStock: requestCanonicalStockPolicy,
          applyAvailabilityFacet: requestApplyAvailabilityFacet,
          brandIds: requestBrandIds,
          minPrice: requestMinPrice,
          maxPrice: requestMaxPrice,
          sortBy: requestSort,
          pageSize: requestPageSize,
        );
        return _catalogPageCache.load(
          signature: signature,
          pageNumber: pageNumber,
          loader: loader,
        );
      }

      Future<PublicCatalogFacetSnapshot> fetchFacetsForCategoryIds(
        List<String>? categoryIds,
      ) {
        final signature = _catalogFacetSignature(
          tenantId: tenantId,
          categoryIds: categoryIds,
          searchQuery: requestSearch,
          productType: requestProductType,
          policy: visibilityPolicy,
          onlyInStock: requestCanonicalStockPolicy,
          applyAvailabilityFacet: requestApplyAvailabilityFacet,
          brandIds: requestBrandIds,
          minPrice: requestMinPrice,
          maxPrice: requestMaxPrice,
        );
        return _catalogFacetCache.load(
          signature: signature,
          pageNumber: 1,
          loader: () => publicInventoryService.getCatalogFacetsForTenant(
            tenantId: tenantId,
            categoryIds: categoryIds,
            searchQuery: requestSearch.isEmpty ? null : requestSearch,
            productType: requestProductType,
            onlyInStock: requestCanonicalStockPolicy,
            applyAvailabilityFacet: requestApplyAvailabilityFacet,
            brandIds: requestBrandIds,
            minPrice: requestMinPrice,
            maxPrice: requestMaxPrice,
          ),
        );
      }

      final canStartPageBeforeCategories = !editProvider.isEditMode &&
          _pendingRouteCategoryValue == null &&
          _selectedCategoryId == null;
      if (canStartPageBeforeCategories) {
        productPageSignature = _catalogPageSignature(
          tenantId: tenantId,
          categoryIds: null,
          searchQuery: requestSearch,
          productType: requestProductType,
          policy: visibilityPolicy,
          onlyInStock: requestCanonicalStockPolicy,
          applyAvailabilityFacet: requestApplyAvailabilityFacet,
          brandIds: requestBrandIds,
          minPrice: requestMinPrice,
          maxPrice: requestMaxPrice,
          sortBy: requestSort,
          pageSize: requestPageSize,
        );
        productPageFuture = fetchPageForCategoryIds(
          categoryIds: null,
          pageNumber: requestPage,
        );
        facetSnapshotFuture = fetchFacetsForCategoryIds(null);
      }

      await categoriesFuture;
      if (!mounted || token != _loadToken) return;

      // If the URL carried a category filter we couldn't resolve earlier (e.g.
      // because categories weren't loaded yet), resolve it now.
      if (_pendingRouteCategoryValue != null) {
        final pendingRouteCategoryValue = _pendingRouteCategoryValue!;
        final resolved = _resolveCategoryIdFromValue(pendingRouteCategoryValue);
        if (resolved != null && mounted) {
          setState(() {
            _selectedCategoryId = resolved;
            _pendingRouteCategoryValue = null;
          });
          if (_replaceResolvedCategoryAlias(
            rawSlug: pendingRouteCategoryValue,
            categoryId: resolved,
          )) {
            return;
          }
        } else if (resolved == null && mounted) {
          final unresolved = _pendingRouteCategoryValue!.trim();
          setState(() {
            _pendingRouteCategoryValue = null;
            _selectedCategoryId = null;
            _categoryRouteError = unresolved;
            _allProducts = const [];
            _filteredProducts = const [];
            _totalProductCount = 0;
            _hasLoadedInitialProducts = true;
          });
          return;
        }
      }

      if (kDebugMode) {
        debugPrint(
          '🧭 [StoreCatalogTrace] CATEGORY_RESOLVED token=$token '
          'category=$_selectedCategoryId '
          'name=${_allCategoriesById[_selectedCategoryId]?.name ?? '-'} '
          'pending=$_pendingRouteCategoryValue error=$_categoryRouteError',
        );
      }

      if (editProvider.isEditMode) {
        // Active editing can inspect the complete editable product set. Plain
        // preview deliberately stays on the public, server-paged path so the
        // editor shows exactly what a customer can browse.
        final products = await publicInventoryService.getProductsForTenant(
          tenantId: tenantId,
          onlyInStock: false,
          includeUnpublished: true,
        );
        if (!mounted || token != _loadToken) return;

        _allProducts = products;
        _totalProductCount = products.length;
        _catalogDebugLog(
            '[ProductCatalogPage] Loaded ${products.length} products');
        // `_loadProducts` already applied the requested reset at entry. Keep
        // the route-restored page when this load came from direct navigation.
        _applyLocalFilters(resetPage: false);
        return;
      }

      final selectedCategoryIds = _selectedCategoryId == null
          ? null
          : resolveCatalogCategoryIdsForScope(
              selectedCategoryId: _selectedCategoryId!,
              scope: requestCategoryScope,
              subtreeCategoryIds:
                  _getCategoryAndDescendantIds(_selectedCategoryId!),
            ).toList(growable: false);

      Future<PublicProductPage> fetchPublicPage({
        required int pageNumber,
        int? pageLimit,
      }) {
        return fetchPageForCategoryIds(
          categoryIds: selectedCategoryIds,
          pageNumber: pageNumber,
          pageLimit: pageLimit,
        );
      }

      if (productPageFuture == null) {
        if (kDebugMode) {
          debugPrint(
            '🧭 [StoreCatalogTrace] PUBLIC_REQUEST token=$token '
            'source=get_public_products category=$_selectedCategoryId '
            'scope=${requestCategoryScope.storageValue} '
            'categoryIds=${selectedCategoryIds ?? const <String>[]} '
            'query=$requestSearch type=${requestProductType?.name} '
            'policy=${visibilityPolicy?.toSettings() ?? const <String, String>{}} '
            'stock=${requestApplyAvailabilityFacet ? 'available' : 'policy'} brands=$requestBrandIds '
            'price=$requestMinPrice..$requestMaxPrice '
            'page=$requestPage limit=$requestPageSize',
          );
        }
        productPageSignature = _catalogPageSignature(
          tenantId: tenantId,
          categoryIds: selectedCategoryIds,
          searchQuery: requestSearch,
          productType: requestProductType,
          policy: visibilityPolicy,
          onlyInStock: requestCanonicalStockPolicy,
          applyAvailabilityFacet: requestApplyAvailabilityFacet,
          brandIds: requestBrandIds,
          minPrice: requestMinPrice,
          maxPrice: requestMaxPrice,
          sortBy: requestSort,
          pageSize: requestPageSize,
        );
        productPageFuture = fetchPublicPage(pageNumber: requestPage);
        facetSnapshotFuture = fetchFacetsForCategoryIds(selectedCategoryIds);
      }

      _activeCatalogPageSignature = productPageSignature;
      final cachedPage = _catalogPageCache.peek(
        signature: productPageSignature!,
        pageNumber: requestPage,
      );
      if (_hasLoadedInitialProducts) {
        setState(() {
          if (cachedPage != null) {
            _allProducts = cachedPage.products;
            _filteredProducts = cachedPage.products;
            _totalProductCount = cachedPage.totalCount;
            _isRefreshing = false;
          } else {
            _isRefreshing = true;
            _filteredProducts = const [];
            _totalProductCount = 0;
          }
        });
      }

      var page = await productPageFuture;
      if (page.products.isEmpty && requestPage > 1) {
        // A paged SQL row carries `total_count`; an offset past the end has no
        // row from which to read it. Probe the first eligible row, clamp to the
        // real last page, and fetch that page so a stale deep link never turns
        // the whole catalog into a false zero-result state.
        final countProbe = await fetchPublicPage(pageNumber: 1, pageLimit: 1);
        if (!mounted || token != _loadToken) return;
        final resolvedPage = resolveCatalogPageFromTotalCount(
          requestedPage: requestPage,
          pageSize: requestPageSize,
          totalCount: countProbe.totalCount,
        );
        if (_currentPage != resolvedPage) {
          setState(() => _currentPage = resolvedPage);
          _syncCatalogQueryToRoute();
        }
        page = countProbe.totalCount == 0
            ? countProbe
            : await fetchPublicPage(pageNumber: resolvedPage);
      }
      if (!mounted || token != _loadToken) return;

      if (page.products.isNotEmpty && requestPage > 1) {
        final resolvedPage = resolveCatalogPageFromTotalCount(
          requestedPage: requestPage,
          pageSize: requestPageSize,
          totalCount: page.totalCount,
        );
        if (requestPage > resolvedPage && _currentPage != resolvedPage) {
          // The faceted RPC clamps an excessive offset internally. Keep the
          // visible page and URL aligned with the rows it actually returned.
          setState(() => _currentPage = resolvedPage);
          _syncCatalogQueryToRoute();
        }
      }

      setState(() {
        _allProducts = page.products;
        _filteredProducts = page.products;
        _totalProductCount = page.totalCount;
        _hasLoadedInitialProducts = true;
        _isLoading = false;
        _isRefreshing = false;
      });

      _catalogDebugLog(
        '🧭 [StoreCatalogTrace] PUBLIC_RESPONSE token=$token '
        'category=$_selectedCategoryId '
        'products=${page.products.length} total=${page.totalCount}',
      );

      final totalPages = page.totalCount == 0
          ? 1
          : ((page.totalCount - 1) ~/ requestPageSize) + 1;
      final effectivePage = _currentPage.clamp(1, totalPages).toInt();
      if (effectivePage < totalPages) {
        unawaited(
          _warmAdjacentCatalogPage(
            signature: productPageSignature,
            pageNumber: effectivePage + 1,
            loader: () => fetchPublicPage(pageNumber: effectivePage + 1),
          ),
        );
      }

      // Facets describe the result set, not an individual page. A page turn
      // reuses the prior snapshot, and a genuinely new snapshot updates in the
      // background without holding the product grid behind it.
      final facetSnapshot = await facetSnapshotFuture!;
      if (!mounted || token != _loadToken) return;
      setState(() {
        _catalogFacets = facetSnapshot;
        if (facetSnapshot.isAvailable &&
            facetSnapshot.filteredTotalCount != null) {
          _directCategoryProductCounts = facetSnapshot.directCategoryCounts;
          _categoryTotalCount = facetSnapshot.filteredTotalCount!;
          _facetCategoryCountsLoadToken = token;
        }
      });

      if (!facetSnapshot.isAvailable) {
        // The legacy counts RPC is a fallback only. Running it beside a healthy
        // facets query repeats the expensive availability scan.
        unawaited(
          _loadCategoryCounts(
            tenantId: tenantId,
            service: publicInventoryService,
            policy: visibilityPolicy,
            token: token,
          ),
        );
      }
    } catch (e) {
      debugPrint('[ProductCatalogPage] Error loading products: $e');
      if (mounted && token == _loadToken) {
        setState(() {
          _catalogLoadError = _hasActiveProfessionalFilters
              ? 'No pudimos aplicar estos filtros en este momento.'
              : 'No pudimos cargar el catálogo en este momento.';
          _allProducts = const [];
          _filteredProducts = const [];
          _totalProductCount = 0;
        });
      }
    } finally {
      if (mounted && token == _loadToken) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          _hasLoadedInitialProducts = true;
        });
      }
    }
  }

  Future<void> _warmAdjacentCatalogPage({
    required String? signature,
    required int pageNumber,
    required Future<PublicProductPage> Function() loader,
  }) async {
    if (signature == null || pageNumber < 1) return;
    try {
      // Let the current page claim bandwidth and decode time first. Warming
      // only the next page's first visible row keeps the transition snappy
      // without downloading every below-the-fold image in advance.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_catalogPageCache.isActive(signature)) return;

      final page = await loader();
      if (!mounted || !_catalogPageCache.isActive(signature)) return;

      final width = MediaQuery.sizeOf(context).width;
      final firstRowCount = width >= 900
          ? 4
          : width >= 600
              ? 3
              : 2;
      final urls = page.products
          .take(firstRowCount)
          .map((product) => product.imageUrlOptimized ?? product.imageUrl)
          .whereType<String>()
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toSet();

      await Future.wait<void>(
        urls.map(
          (url) => precacheImage(NetworkImage(url), context).catchError((_) {}),
        ),
      );
    } catch (_) {
      // Prefetch is opportunistic. The foreground load remains authoritative.
    }
  }

  Future<void> _loadCategoryCounts({
    required String tenantId,
    required PublicInventoryService service,
    required PublicProductVisibilityPolicy? policy,
    required int token,
  }) async {
    final signature = [
      tenantId,
      _selectedProductType?.name ?? 'all',
      policy?.stockPolicy.storageValue ?? 'server',
      policy?.requireImage ?? 'server',
      policy?.requireVisibleCategory ?? 'server',
      policy?.includeUncategorized ?? 'server',
    ].join('|');
    if (signature == _lastCategoryCountsSignature) return;

    final snapshot = await service.getCategoryCountsForTenant(
      tenantId: tenantId,
      productType: _selectedProductType,
      policy: policy,
      onlyInStock: true,
    );

    if (!mounted || token != _loadToken) return;
    if (_facetCategoryCountsLoadToken == token) return;
    setState(() {
      _directCategoryProductCounts = snapshot.directCountsByCategoryId;
      _categoryTotalCount = snapshot.totalCount;
      _lastCategoryCountsSignature = signature;
    });
    if (kDebugMode) {
      debugPrint(
        '🧭 [StoreCatalogTrace] PUBLIC_COUNTS token=$token '
        'total=${snapshot.totalCount} '
        'selected=$_selectedCategoryId '
        'selectedDirect=${snapshot.directCountsByCategoryId[_selectedCategoryId] ?? 0}',
      );
    }
  }

  PublicProductVisibilityPolicy? _readVisibilityPolicy() {
    try {
      final service = context.read<WebsiteService>();
      if (!PublicProductVisibilityPolicy.hasAnySetting(service.settings)) {
        return null;
      }
      return PublicProductVisibilityPolicy.fromSettings(service.settings);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadVisibleCategories(
    String tenantId,
    PublicInventoryService publicInventoryService, {
    required int token,
    bool forceRefresh = false,
  }) async {
    try {
      // Load every active category to build membership through the complete
      // hierarchy. `show_on_website` owns navigation/filter eligibility; it
      // restricts product eligibility only when the separate public rule says
      // so. Hidden descendants therefore remain part of a published parent's
      // result without becoming public navigation options themselves.
      final categories = forceRefresh
          ? await publicInventoryService.refreshCategoriesForTenant(
              tenantId: tenantId,
            )
          : await publicInventoryService.getCategoriesForTenant(
              tenantId: tenantId,
            );
      if (!mounted || token != _loadToken) return;
      final visibleCategoryIds = <String>{};

      // Build nodes for all categories while separately tracking which ones
      // the Website Builder publishes as public navigation/filter choices.
      final nodesById = <String, _CategoryNode>{};
      for (final category in categories) {
        final id = category.id;
        if (id == null) continue;
        nodesById[id] = _CategoryNode(
          id: id,
          name: category.name,
          fullPath: category.fullPath,
          parentId: category.parentId,
          description: category.description ?? '',
          imageUrl: category.imageUrl ?? '',
          sortOrder: category.sortOrder,
          showOnWebsite: category.showOnWebsite,
        );
        if (category.showOnWebsite) {
          visibleCategoryIds.add(id);
        }
      }

      // Build parent-child relationships
      for (final node in nodesById.values) {
        if (node.parentId != null && nodesById.containsKey(node.parentId)) {
          nodesById[node.parentId]!.children.add(node);
        }
      }

      // Sort children alphabetically
      for (final node in nodesById.values) {
        node.children.sort((a, b) {
          final byOrder = a.sortOrder.compareTo(b.sortOrder);
          return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
        });
      }

      // Build root-level tree: only categories with show_on_website = true
      // that are either root OR whose parent is not visible
      final rootCategories = <_CategoryNode>[];
      for (final id in visibleCategoryIds) {
        final node = nodesById[id]!;
        // A visible category is a "root" in our display if:
        // - It has no parent, OR
        // - Its parent is not in the visible set
        if (node.parentId == null ||
            !visibleCategoryIds.contains(node.parentId)) {
          rootCategories.add(node);
        }
      }
      rootCategories.sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
      });

      if (mounted) {
        setState(() {
          _categoryTree = rootCategories;
          _allCategoriesById = nodesById;
          _loadedCategoriesTenantId = tenantId;
        });
      }
      _catalogDebugLog(
          '[ProductCatalogPage] Loaded ${visibleCategoryIds.length} visible categories, ${rootCategories.length} root nodes');
    } catch (e) {
      debugPrint('[ProductCatalogPage] Error loading visible categories: $e');
    }
  }

  /// Get all category IDs that should be included when filtering by the given category
  /// This includes the category itself and all its descendants
  Set<String> _getCategoryAndDescendantIds(String categoryId) {
    final node = _allCategoriesById[categoryId];
    if (node == null) return {categoryId};
    return node.getAllDescendantIds();
  }

  WebsiteCatalogPresentation? _presentationForCategory(String? categoryId) {
    if (categoryId == null) {
      final root = _selectedProductType == ProductType.service
          ? WebsiteCatalogRoot.services
          : WebsiteCatalogRoot.products;
      return _presentationRegistry.forCatalogRoot(root) ??
          WebsiteCatalogPresentation.catalogRoot(root);
    }
    final node = _allCategoriesById[categoryId];
    if (node == null) return null;
    return _presentationRegistry.forCategory(categoryId) ??
        WebsiteCatalogPresentation.fallback(
          categoryId: categoryId,
          categoryName: node.name,
        );
  }

  void _scheduleCatalogSeo(WebsiteEditModeProvider editProvider) {
    if (!kIsWeb) return;

    final currentUri = GoRouterState.of(context).uri;
    final selectedId = _selectedCategoryId;
    final category = selectedId == null ? null : _allCategoriesById[selectedId];
    final presentation = _presentationForCategory(selectedId);
    final websiteService = context.read<WebsiteService>();
    final savedStoreName =
        websiteService.getSetting('store_name', 'VINABIKE').trim();
    final storeName = savedStoreName.isEmpty ? 'VINABIKE' : savedStoreName;
    final savedStoreDescription = websiteService
        .getSetting(
          'store_description',
          'Todo lo que necesitas para tu bicicleta en Viña del Mar',
        )
        .trim();
    final storeDescription = savedStoreDescription.isEmpty
        ? 'Todo lo que necesitas para tu bicicleta en Viña del Mar'
        : savedStoreDescription;
    final logoUrl = websiteService.getSetting('logo_url', '');
    final rootLabel =
        _selectedProductType == ProductType.service ? 'Servicios' : 'Productos';
    final collectionLabel = category?.name ?? rootLabel;
    final effectiveTitle = presentation?.seoTitle.trim().isNotEmpty == true
        ? presentation!.seoTitle.trim()
        : '${presentation?.heroTitle.trim().isNotEmpty == true ? presentation!.heroTitle.trim() : collectionLabel} | $storeName';
    final effectiveDescription =
        presentation?.seoDescription.trim().isNotEmpty == true
            ? presentation!.seoDescription.trim()
            : presentation?.heroDescription.trim().isNotEmpty == true
                ? presentation!.heroDescription.trim()
                : category?.description.trim().isNotEmpty == true
                    ? category!.description.trim()
                    : storeDescription;
    final effectiveImage =
        presentation?.socialImageUrl.trim().isNotEmpty == true
            ? presentation!.socialImageUrl.trim()
            : presentation?.heroImageUrl.trim().isNotEmpty == true
                ? presentation!.heroImageUrl.trim()
                : category?.imageUrl.trim().isNotEmpty == true
                    ? category!.imageUrl.trim()
                    : logoUrl;
    final isErpMounted =
        currentUri.path == '/tienda' || currentUri.path.startsWith('/tienda/');
    final ownerIsPublished =
        selectedId == null || category?.showOnWebsite == true;
    final hasEligibleContent = _categoryRouteError == null &&
        _catalogLoadError == null &&
        _hasLoadedInitialProducts &&
        _totalProductCount > 0;
    final routeProjection = projectStorefrontSeoRoute(
      currentUri,
      isErpMounted:
          isErpMounted || editProvider.isEditMode || editProvider.isPreviewMode,
      ownerAllowsIndexing: presentation?.allowIndexing ?? false,
      ownerIsPublished: ownerIsPublished,
      hasEligibleContent: hasEligibleContent,
    );
    final canonicalUrl = _catalogCanonicalUrl(
      websiteService,
      routeProjection.canonicalPath,
    );
    final signature = [
      effectiveTitle,
      effectiveDescription,
      effectiveImage,
      canonicalUrl ?? '',
      routeProjection.robots,
    ].join('\u0000');
    if (_lastSeoSignature == signature) return;
    _lastSeoSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastSeoSignature != signature) return;
      SeoHelper.updateSeo(
        title: effectiveTitle,
        description: effectiveDescription,
        imageUrl: effectiveImage.isEmpty ? null : effectiveImage,
        canonicalUrl: canonicalUrl,
        robots: routeProjection.robots,
      );
    });
  }

  String? _catalogCanonicalUrl(
    WebsiteService websiteService,
    String canonicalPath,
  ) {
    final explicit = websiteService.getSetting('store_url', '').trim();
    final base = explicit.isNotEmpty
        ? Uri.tryParse(explicit)
        : Uri.base.host.isEmpty
            ? null
            : Uri(
                scheme: Uri.base.scheme,
                host: Uri.base.host,
                port: Uri.base.hasPort ? Uri.base.port : null,
              );
    return base
        ?.resolve(canonicalPath)
        .replace(query: null, fragment: null)
        .toString();
  }

  void _selectCategory(String? categoryId) {
    // Clean collection URLs mount a new routed surface. Let that surface own
    // its state instead of dirtying the current TextField/LayoutBuilder tree
    // immediately before GoRouter replaces it (which can violate Flutter's
    // relayout boundary invariants in the desktop editor shell).
    if (_replaceCategoryRoute(categoryId)) return;

    setState(() {
      _selectedCategoryId = categoryId;
      _pendingRouteCategoryValue = null;
      _categoryScope = WebsiteCatalogCategoryScope.subtree;
      _currentPage = 1;
      if (_hasLoadedInitialProducts) {
        _isRefreshing = true;
        _filteredProducts = const [];
        _totalProductCount = 0;
      }
    });
    _handleFiltersChanged();
  }

  bool _replaceCategoryRoute(
    String? categoryId, {
    bool preserveCategoryScope = false,
  }) {
    try {
      final current = GoRouterState.of(context).uri;
      final isMounted =
          current.path == '/tienda' || current.path.startsWith('/tienda/');
      final services = _selectedProductType == ProductType.service;
      final presentation = _presentationForCategory(categoryId);
      final canonicalPath = presentation == null
          ? (services ? '/servicios' : '/productos')
          : publicCategoryPath(
              presentation: presentation,
              services: services,
            );
      final path = normalizePublicCatalogRouteForRuntime(
        canonicalPath,
        isErpMounted: isMounted,
      );
      final query = Map<String, String>.from(current.queryParameters)
        ..remove('category')
        ..remove('category_id')
        ..remove('cat')
        ..remove('categoria');
      if (!preserveCategoryScope) {
        query.remove('category_scope');
      }
      final destination = Uri(
        path: path,
        queryParameters: query.isEmpty ? null : query,
      ).toString();
      if (destination == current.toString()) return false;

      final router = GoRouter.of(context);
      final isCatalogRoot = current.path == '/productos' ||
          current.path == '/servicios' ||
          current.path == '/tienda/productos' ||
          current.path == '/tienda/servicios';

      // Entering a nested collection from the catalog root must be a push.
      // Replacing the root match forces go_router to reactivate the catalog
      // page while its editor LayoutBuilder is laying out, which trips
      // Flutter's relayout-boundary assertion on desktop. Once inside a
      // collection, replacements remain appropriate for switching collection
      // or clearing it without growing the navigation stack indefinitely.
      if (categoryId != null && isCatalogRoot) {
        router.push(destination);
      } else {
        router.replace(destination);
      }
      return true;
    } catch (_) {
      // The selected state still works if a host does not expose GoRouter.
      return false;
    }
  }

  void _setOnlyInStock(bool value) {
    if (_onlyInStock == value) return;
    setState(() {
      _stockFilter = value ? WebsiteCatalogStockFilter.available : null;
    });
    _syncCatalogQueryToRoute(resetPage: true);
    _handleFiltersChanged();
  }

  void _includeCategoryDescendants() {
    if (!_isDirectCategoryScope) return;
    setState(() {
      _categoryScope = WebsiteCatalogCategoryScope.subtree;
      _currentPage = 1;
    });
    _syncCatalogQueryToRoute(resetPage: true);
    _handleFiltersChanged();
  }

  void _toggleBrand(String brandId) {
    setState(() {
      if (!_selectedBrandIds.add(brandId)) {
        _selectedBrandIds.remove(brandId);
      }
    });
    _syncCatalogQueryToRoute(resetPage: true);
    _handleFiltersChanged();
  }

  double? _parsePriceInput(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    return double.tryParse(
      value.replaceAll(RegExp(r'[.\s]'), '').replaceAll(',', '.'),
    );
  }

  void _applyPriceRange() {
    final minPrice = _parsePriceInput(_minPriceController.text);
    final maxPrice = _parsePriceInput(_maxPriceController.text);
    final hasInvalidMin = _minPriceController.text.trim().isNotEmpty &&
        (minPrice == null || minPrice < 0);
    final hasInvalidMax = _maxPriceController.text.trim().isNotEmpty &&
        (maxPrice == null || maxPrice < 0);
    if (hasInvalidMin ||
        hasInvalidMax ||
        (minPrice != null && maxPrice != null && minPrice > maxPrice)) {
      setState(() {
        _priceFilterError = hasInvalidMin || hasInvalidMax
            ? 'Ingresa montos válidos.'
            : 'El mínimo no puede superar el máximo.';
      });
      return;
    }
    setState(() {
      _minPrice = minPrice;
      _maxPrice = maxPrice;
      _priceFilterError = null;
      _syncPriceControllers();
    });
    _syncCatalogQueryToRoute(resetPage: true);
    _handleFiltersChanged();
  }

  void _clearPriceRange() {
    if (_minPrice == null && _maxPrice == null) return;
    setState(() {
      _minPrice = null;
      _maxPrice = null;
      _priceFilterError = null;
      _syncPriceControllers();
    });
    _syncCatalogQueryToRoute(resetPage: true);
    _handleFiltersChanged();
  }

  void _clearAllSecondaryFilters() {
    setState(() {
      _searchQuery = '';
      _filtersSearchController.clear();
      _selectedBrandIds.clear();
      _minPrice = null;
      _maxPrice = null;
      _stockFilter = null;
      _priceFilterError = null;
      _syncPriceControllers();
    });
    _syncCatalogQueryToRoute(resetPage: true);
    _handleFiltersChanged();
  }

  void _handleFiltersChanged({
    bool debounce = false,
    bool resetPage = true,
  }) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    if (editProvider.isEditMode) {
      // The editor uses the complete product set and filters it locally, but
      // there is nothing to filter on the first visit until that set has been
      // fetched. Previously this branch returned immediately and left
      // `_isLoading` true forever when the page selector opened /productos.
      if (!_hasLoadedInitialProducts) {
        // The initial Edit request loads one complete editable source set.
        // Route/filter changes can safely reuse it and will be applied after
        // arrival. Do not invalidate that request without a replacement or
        // the editor can remain stuck in its loading state forever.
        if (_loadToken == 0 || !_isLoading) {
          unawaited(_loadProducts(resetPage: resetPage));
        }
        return;
      }

      // The source set is already local, so no server request can repaint an
      // obsolete result.
      _applyLocalFilters(resetPage: resetPage);
      return;
    }

    // Invalidate an in-flight public request at the moment the visitor changes
    // a control. Waiting until a debounced replacement starts would allow the
    // previous response to repaint stale rows under the new selection.
    if (_loadToken > 0) _loadToken++;

    if (_hasLoadedInitialProducts && mounted) {
      setState(() {
        _isRefreshing = true;
        _filteredProducts = const [];
        _totalProductCount = 0;
        _catalogFacets = const PublicCatalogFacetSnapshot.unavailable();
        _directCategoryProductCounts = const {};
        _categoryTotalCount = 0;
      });
    }

    _searchDebounce?.cancel();
    _activeCatalogPageSignature = null;
    if (debounce) {
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _loadProducts(resetPage: resetPage);
        }
      });
      return;
    }

    _loadProducts(resetPage: resetPage);
  }

  void _applyLocalFilters({bool resetPage = true}) {
    var routePageWasClamped = false;
    setState(() {
      if (resetPage) {
        // User-authored filter changes start a new result set. Route-authored
        // changes restore the page encoded in the URL instead.
        _currentPage = 1;
      }

      final tokens = _tokenizeSearchQuery(_searchQuery);
      bool matchesBaseFilters(
        Product product, {
        required bool includeCategoryContext,
      }) {
        // Type filter
        if (_selectedProductType != null &&
            product.productType != _selectedProductType) {
          return false;
        }

        // Search filter
        if (tokens.isNotEmpty) {
          final textHaystack = _buildNormalizedProductSearchText(product);
          final idHaystack = _buildNormalizedProductIdSearchText(product);

          // AND semantics: every token must match somewhere.
          for (final token in tokens) {
            final isNumericToken = RegExp(r'^\d+$').hasMatch(token);

            // Heuristic: numeric-only tokens (like "26") often represent sizes.
            // They should match human text (name/description), and may match
            // identifiers only when not embedded inside a larger number.
            if (isNumericToken) {
              final boundaryRe = RegExp(
                '(^|[^0-9])${RegExp.escape(token)}([^0-9]|\$)',
              );

              if (!textHaystack.contains(token) &&
                  !boundaryRe.hasMatch(idHaystack)) {
                return false;
              }
            } else {
              if (!textHaystack.contains(token) &&
                  !idHaystack.contains(token)) {
                return false;
              }
            }
          }
        }

        // The clean collection route includes descendants. A typed direct
        // scope intentionally narrows the same category owner to products
        // assigned to that category itself.
        if (includeCategoryContext && _selectedCategoryId != null) {
          final validCategoryIds = resolveCatalogCategoryIdsForScope(
            selectedCategoryId: _selectedCategoryId!,
            scope: _categoryScope,
            subtreeCategoryIds:
                _getCategoryAndDescendantIds(_selectedCategoryId!),
          );
          if (product.categoryId == null ||
              !validCategoryIds.contains(product.categoryId)) {
            return false;
          }
        }

        if (_onlyInStock &&
            product.tracksInventory &&
            product.availableStockQuantity <= 0) {
          return false;
        }

        return true;
      }

      final baseProducts = _allProducts
          .where(
            (product) => matchesBaseFilters(
              product,
              includeCategoryContext: true,
            ),
          )
          .toList(growable: false);
      final categoryFacetProducts = _allProducts
          .where(
        (product) => matchesBaseFilters(
          product,
          includeCategoryContext: false,
        ),
      )
          .where((product) {
        if (_selectedBrandIds.isNotEmpty &&
            (product.brandId == null ||
                !_selectedBrandIds.contains(product.brandId))) {
          return false;
        }
        if (_minPrice != null && product.price < _minPrice!) return false;
        if (_maxPrice != null && product.price > _maxPrice!) return false;
        return true;
      }).toList(growable: false);
      final directCategoryCounts = <String, int>{};
      for (final product in categoryFacetProducts) {
        final categoryId = product.categoryId?.trim() ?? '';
        if (categoryId.isEmpty) continue;
        directCategoryCounts[categoryId] =
            (directCategoryCounts[categoryId] ?? 0) + 1;
      }
      final brandCounts = <String, int>{};
      final brandLabels = <String, String>{};
      for (final product in baseProducts) {
        if ((_minPrice != null && product.price < _minPrice!) ||
            (_maxPrice != null && product.price > _maxPrice!)) {
          continue;
        }
        final brandId = product.brandId?.trim() ?? '';
        final label = product.brand?.trim() ?? '';
        if (brandId.isEmpty || label.isEmpty) continue;
        brandCounts[brandId] = (brandCounts[brandId] ?? 0) + 1;
        brandLabels.putIfAbsent(brandId, () => label);
      }
      final priceCandidates = baseProducts.where((product) {
        return _selectedBrandIds.isEmpty ||
            (product.brandId != null &&
                _selectedBrandIds.contains(product.brandId));
      }).toList(growable: false);
      final prices = priceCandidates.map((product) => product.price).toList();
      _catalogFacets = PublicCatalogFacetSnapshot(
        brands: brandCounts.entries
            .map(
              (entry) => PublicCatalogBrandFacet(
                id: entry.key,
                label: brandLabels[entry.key]!,
                itemCount: entry.value,
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.label.compareTo(b.label)),
        directCategoryCounts: Map.unmodifiable(directCategoryCounts),
        filteredTotalCount: categoryFacetProducts.length,
        minPrice:
            prices.isEmpty ? null : prices.reduce((a, b) => a < b ? a : b),
        maxPrice:
            prices.isEmpty ? null : prices.reduce((a, b) => a > b ? a : b),
      );

      _filteredProducts = baseProducts.where((product) {
        if (_selectedBrandIds.isNotEmpty &&
            (product.brandId == null ||
                !_selectedBrandIds.contains(product.brandId))) {
          return false;
        }
        if (_minPrice != null && product.price < _minPrice!) return false;
        if (_maxPrice != null && product.price > _maxPrice!) return false;
        return true;
      }).toList();

      // Apply sorting
      switch (_sortBy) {
        case 'name':
          _filteredProducts.sort((a, b) => a.name.compareTo(b.name));
          break;
        case 'price_asc':
          _filteredProducts.sort((a, b) => a.price.compareTo(b.price));
          break;
        case 'price_desc':
          _filteredProducts.sort((a, b) => b.price.compareTo(a.price));
          break;
        case 'newest':
          _filteredProducts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          break;
      }
      _totalProductCount = _filteredProducts.length;
      _directCategoryProductCounts = Map.unmodifiable(directCategoryCounts);
      _categoryTotalCount = categoryFacetProducts.length;
      final totalPages = math.max(
        1,
        (_totalProductCount / _itemsPerPage).ceil(),
      );
      if (_currentPage > totalPages) {
        _currentPage = totalPages;
        routePageWasClamped = true;
      }
    });
    if (routePageWasClamped) {
      _syncCatalogQueryToRoute();
    }
  }

  String _normalizeForSearch(String input) {
    var s = input.toLowerCase();

    // Fast accent/diacritic normalization for Spanish.
    s = s
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');

    // Normalize punctuation to spaces (keeps token boundaries consistent).
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    return s.trim();
  }

  List<String> _tokenizeSearchQuery(String query) {
    final normalized = _normalizeForSearch(query);
    if (normalized.isEmpty) return const [];
    return normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  }

  String _buildNormalizedProductSearchText(Product product) {
    final raw = <String?>[
      product.name,
      product.description,
      product.brand,
      product.model,
      product.manufacturer,
      product.manufacturerSku,
      product.categoryName,
    ].whereType<String>().join(' ');

    return _normalizeForSearch(raw);
  }

  String _buildNormalizedProductIdSearchText(Product product) {
    final raw = <String?>[
      product.sku,
      product.barcode,
      product.gtin,
    ].whereType<String>().join(' ');

    return _normalizeForSearch(raw);
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Filtros',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Filter content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: _buildFilters(
                    refreshPanel: () => setSheetState(() {}),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Ordenar por',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Sort options
            _buildSortOption(context, 'name', 'Nombre'),
            _buildSortOption(context, 'price_asc', 'Precio, menor a mayor'),
            _buildSortOption(context, 'price_desc', 'Precio, mayor a menor'),
            _buildSortOption(context, 'newest', 'Más recientes'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(BuildContext context, String value, String label) {
    final isSelected = _sortBy == value;
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing:
          isSelected ? const Icon(Icons.check, color: Colors.black) : null,
      onTap: () {
        if (!isSelected) {
          setState(() => _sortBy = value);
          _syncCatalogQueryToRoute(resetPage: true);
          _handleFiltersChanged();
        }
        Navigator.pop(context);
      },
    );
  }

  @override
  void dispose() {
    // Debug: dispose
    _searchDebounce?.cancel();
    _observedInventoryService
        ?.removeListener(_handlePublicInventoryInvalidated);
    _catalogPageCache.clear();
    _catalogFacetCache.clear();
    _filtersSearchController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _filtersSearchFocusNode.dispose();
    super.dispose();
  }

  bool get _hasActiveSecondaryFilters =>
      _searchQuery.trim().isNotEmpty ||
      _selectedBrandIds.isNotEmpty ||
      _minPrice != null ||
      _maxPrice != null ||
      _onlyInStock;

  bool get _hasActiveProfessionalFilters =>
      _selectedBrandIds.isNotEmpty ||
      _minPrice != null ||
      _maxPrice != null ||
      _onlyInStock;

  String _brandLabel(String brandId) {
    for (final facet in _catalogFacets.brands) {
      if (facet.id == brandId && facet.label.trim().isNotEmpty) {
        return facet.label.trim();
      }
    }
    for (final product in _allProducts) {
      if (product.brandId == brandId &&
          product.brand?.trim().isNotEmpty == true) {
        return product.brand!.trim();
      }
    }
    return 'Marca seleccionada';
  }

  String _activePriceLabel() {
    if (_minPrice != null && _maxPrice != null) {
      return 'Precio: ${ChileanUtils.formatCurrency(_minPrice!)} – '
          '${ChileanUtils.formatCurrency(_maxPrice!)}';
    }
    if (_minPrice != null) {
      return 'Desde ${ChileanUtils.formatCurrency(_minPrice!)}';
    }
    return 'Hasta ${ChileanUtils.formatCurrency(_maxPrice!)}';
  }

  Widget _buildActiveFilterSummary() {
    if (!_hasActiveSecondaryFilters) return const SizedBox.shrink();

    final chips = <Widget>[];
    final search = _searchQuery.trim();
    if (search.isNotEmpty) {
      chips.add(
        _buildActiveFilterChip(
          label: 'Búsqueda: $search',
          tooltip: 'Quitar búsqueda',
          onDeleted: _clearSearch,
        ),
      );
    }

    final brandIds = _selectedBrandIds.toList(growable: false)
      ..sort((a, b) => _brandLabel(a).compareTo(_brandLabel(b)));
    for (final brandId in brandIds) {
      chips.add(
        _buildActiveFilterChip(
          label: 'Marca: ${_brandLabel(brandId)}',
          tooltip: 'Quitar marca',
          onDeleted: () => _toggleBrand(brandId),
        ),
      );
    }

    if (_minPrice != null || _maxPrice != null) {
      chips.add(
        _buildActiveFilterChip(
          label: _activePriceLabel(),
          tooltip: 'Quitar rango de precio',
          onDeleted: _clearPriceRange,
        ),
      );
    }

    if (_onlyInStock) {
      chips.add(
        _buildActiveFilterChip(
          label: 'Sólo disponibles',
          tooltip: 'Usar la política pública de stock',
          onDeleted: () => _setOnlyInStock(false),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Filtros activos',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          ...chips,
          TextButton(
            onPressed: _clearAllSecondaryFilters,
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Limpiar todo',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterChip({
    required String label,
    required String tooltip,
    required VoidCallback onDeleted,
  }) {
    return InputChip(
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      tooltip: tooltip,
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close, size: 15),
      deleteIconColor: Colors.grey.shade700,
      backgroundColor: Colors.grey.shade50,
      side: BorderSide(color: Colors.grey.shade300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.only(left: 4),
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Colors.black87,
      ),
    );
  }

  List<_CategoryNode> _selectedCategoryPath() {
    final selectedId = _selectedCategoryId;
    if (selectedId == null) return const [];
    final path = <_CategoryNode>[];
    var current = _allCategoriesById[selectedId];
    final visited = <String>{};
    while (current != null && visited.add(current.id)) {
      path.insert(0, current);
      current = current.parentId == null
          ? null
          : _allCategoriesById[current.parentId!];
    }
    return path.where((node) => node.showOnWebsite).toList(growable: false);
  }

  Widget _buildCollectionIntroduction({required bool compact}) {
    final selectedId = _selectedCategoryId;
    final category = selectedId == null ? null : _allCategoriesById[selectedId];
    final presentation = _presentationForCategory(selectedId);
    if (category == null || presentation == null) {
      return const SizedBox.shrink();
    }

    final title = presentation.heroTitle.isNotEmpty
        ? presentation.heroTitle
        : category.name;
    final description = presentation.heroDescription.isNotEmpty
        ? presentation.heroDescription
        : category.description;
    final imageUrl = presentation.heroImageUrl.isNotEmpty
        ? presentation.heroImageUrl
        : category.imageUrl;
    final visibleChildren = category.children
        .where(
          (child) =>
              child.showOnWebsite &&
              _countProductsInCategoryTree(child, null) > 0,
        )
        .toList(growable: false);
    return CatalogCollectionPresentationHeader(
      presentation: presentation,
      title: title,
      description: description,
      imageUrl: imageUrl,
      compact: compact,
      // The hierarchy is rendered in the catalog heading below the hero so it
      // replaces the generic title instead of creating a separate white row.
      breadcrumbs: const [],
      subcategories: visibleChildren
          .map(
            (child) => CatalogCollectionNavigationItem(
              id: child.id,
              label: child.name,
              onTap: () => _selectCategory(child.id),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final modeKey = editProvider.isEditMode
        ? 'edit'
        : (editProvider.isPreviewMode ? 'preview' : 'normal');
    _scheduleCatalogSeo(editProvider);

    if (kDebugMode && _lastLoggedModeKey != modeKey) {
      final previousMode = _lastLoggedModeKey ?? 'unmounted';
      _lastLoggedModeKey = modeKey;
      final uri = GoRouterState.of(context).uri;
      debugPrint(
        '🧭 [StoreModeTrace][Catalog] TREE $previousMode→$modeKey '
        'uri=$uri category=$_selectedCategoryId '
        'loading=$_isLoading refreshing=$_isRefreshing '
        'loaded=$_hasLoadedInitialProducts products=${_filteredProducts.length}/$_totalProductCount',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        debugPrint(
          '🧭 [StoreModeTrace][Catalog] FRAME mode=$modeKey '
          'uri=${GoRouterState.of(context).uri} '
          'category=$_selectedCategoryId loading=$_isLoading '
          'products=${_filteredProducts.length}/$_totalProductCount',
        );
      });
    }

    // Debug: build
    if (_isLoading) {
      return const FullPageLoading();
    }
    if (_categoryRouteError != null) {
      return _buildUnavailableCategoryState();
    }
    if (_catalogLoadError != null) {
      return _buildCatalogLoadErrorState();
    }

    return Container(
      color: Colors.white,
      child: MediaQueryLayoutBuilder(
        key: ValueKey('catalog_layout_$modeKey'),
        builder: (context, constraints) {
          // Mobile: stacked layout, hide sidebar
          final isMobile = constraints.maxWidth < 700;

          if (isMobile) {
            // IMPORTANT: Do not create a nested scroll view here.
            // The public store layout already provides a single scroll
            // controller (sticky header scaffold). Keeping one scroll
            // controller allows restoring scroll position when navigating
            // to product detail and back.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedCategoryId != null)
                  _buildCollectionIntroduction(compact: true),
                // Header section - clean white
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCatalogHeading(compact: true),
                      const SizedBox(height: 6),
                      Text(
                        '$_totalProductCount ${_catalogNounPlural()}',
                        style: TextStyle(
                          fontFamily: null,
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (_isDirectCategoryScope) ...[
                        const SizedBox(height: 5),
                        _buildCategoryScopeIndicator(compact: true),
                      ],
                    ],
                  ),
                ),
                // Controls bar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Filter button
                      InkWell(
                        onTap: () => _showFilterSheet(context),
                        child: Row(
                          children: [
                            Icon(Icons.tune,
                                size: 20, color: Colors.grey.shade700),
                            const SizedBox(width: 6),
                            Text(
                              'Filtro',
                              style: TextStyle(
                                fontFamily: null,
                                fontSize: 14,
                                color: Colors.grey.shade700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Sort button
                      InkWell(
                        onTap: () => _showSortSheet(context),
                        child: Row(
                          children: [
                            Text(
                              'Ordenar por',
                              style: TextStyle(
                                fontFamily: null,
                                fontSize: 14,
                                color: Colors.grey.shade700,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_down,
                                size: 20, color: Colors.grey.shade700),
                          ],
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                // Product grid
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_hasActiveSecondaryFilters)
                        _buildActiveFilterSummary(),
                      const SizedBox(height: 12),
                      _buildProductGrid(modeKey),
                    ],
                  ),
                ),
              ],
            );
          }

          // Desktop: sidebar layout
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_selectedCategoryId != null)
                _buildCollectionIntroduction(compact: false),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1560),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 30,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 236,
                          child: _buildFilters(),
                        ),
                        const SizedBox(width: 40),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(),
                              if (_hasActiveSecondaryFilters)
                                _buildActiveFilterSummary(),
                              const SizedBox(height: 28),
                              _buildProductGrid(modeKey),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUnavailableCategoryState() {
    return Container(
      color: Colors.white,
      constraints: const BoxConstraints(minHeight: 520),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.category_outlined,
                size: 44, color: Colors.black45),
            const SizedBox(height: 18),
            const Text(
              'Esta colección no está disponible',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'La categoría puede haber cambiado de ruta, estar fuera de la navegación pública o ya no existir.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () {
                _selectCategory(null);
              },
              child: const Text('Ver todos los productos'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogLoadErrorState() {
    final hasProfessionalFilters = _hasActiveProfessionalFilters;
    return Container(
      color: Colors.white,
      constraints: const BoxConstraints(minHeight: 520),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6F8),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.cloud_off_outlined,
                size: 28,
                color: Color(0xFF34495E),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasProfessionalFilters
                  ? 'No pudimos aplicar los filtros'
                  : 'No pudimos cargar el catálogo',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _catalogLoadError!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => _loadProducts(resetPage: false),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reintentar'),
                ),
                if (hasProfessionalFilters)
                  OutlinedButton(
                    onPressed: _clearAllSecondaryFilters,
                    child: const Text('Quitar filtros'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters({VoidCallback? refreshPanel}) {
    final presentation = _presentationForCategory(_selectedCategoryId);
    final facets =
        presentation?.facets ?? WebsiteCatalogPresentation.defaultFacets;
    final sections = <Widget>[];
    for (final facet in facets) {
      final content = switch (facet) {
        WebsiteCatalogFacet.categories => _buildCategoryFacet(),
        WebsiteCatalogFacet.availability =>
          _buildAvailabilityFacet(refreshPanel),
        WebsiteCatalogFacet.brand => _buildBrandFacet(refreshPanel),
        WebsiteCatalogFacet.price => _buildPriceFacet(refreshPanel),
      };
      if (content is SizedBox && content.width == 0 && content.height == 0) {
        continue;
      }
      if (sections.isNotEmpty) {
        sections.addAll([
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 18),
        ]);
      }
      sections.add(content);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Filtros',
          style: TextStyle(
            fontFamily: null,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 20),

        // Search
        TextField(
          controller: _filtersSearchController,
          focusNode: _filtersSearchFocusNode,
          decoration: InputDecoration(
            hintText: 'Buscar ${_catalogNounPlural()}',
            hintStyle: TextStyle(
              fontFamily: null,
              color: Colors.grey.shade500,
              fontSize: 14,
            ),
            prefixIcon:
                Icon(Icons.search, color: Colors.grey.shade400, size: 20),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(0),
              borderSide: BorderSide.none,
            ),
            suffixIcon: _searchQuery.trim().isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: () {
                      _clearSearch();
                      refreshPanel?.call();
                    },
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                  ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          style: const TextStyle(
            fontFamily: null,
            fontSize: 14,
          ),
          onChanged: (value) {
            setState(() => _searchQuery = value);
            _syncCatalogQueryToRoute(resetPage: true);
            _handleFiltersChanged(debounce: true);
            refreshPanel?.call();
          },
        ),
        if (sections.isNotEmpty) const SizedBox(height: 22),
        ...sections,
      ],
    );
  }

  Widget _buildCategoryFacet() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFacetHeading('Categorías'),
        const SizedBox(height: 12),
        _buildCategoryFilters(),
      ],
    );
  }

  Widget _buildAvailabilityFacet(VoidCallback? refreshPanel) {
    final canApplyVisitorFilter =
        context.read<WebsiteEditModeProvider>().isEditMode ||
            _catalogFacets.isAvailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildFacetHeading('Disponibilidad'),
            const SizedBox(width: 6),
            const Tooltip(
              message:
                  'Filtra adicionalmente el catálogo público. Nunca puede mostrar productos que las reglas del sitio ya ocultan.',
              child: Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: Colors.black45,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        MergeSemantics(
          child: MouseRegion(
            cursor: canApplyVisitorFilter
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canApplyVisitorFilter
                  ? () {
                      _setOnlyInStock(!_onlyInStock);
                      refreshPanel?.call();
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Checkbox(
                      value: _onlyInStock,
                      onChanged: canApplyVisitorFilter
                          ? (value) {
                              _setOnlyInStock(value != false);
                              refreshPanel?.call();
                            }
                          : null,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Sólo productos disponibles',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (!canApplyVisitorFilter)
          const Padding(
            padding: EdgeInsets.only(left: 4, top: 5),
            child: Text(
              'Se está usando la regla pública de stock configurada para el sitio.',
              style: TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
          ),
      ],
    );
  }

  Widget _buildBrandFacet(VoidCallback? refreshPanel) {
    if (!_catalogFacets.isAvailable) return const SizedBox.shrink();
    final brands = List<PublicCatalogBrandFacet>.from(_catalogFacets.brands)
      ..sort((a, b) {
        final aSelected = _selectedBrandIds.contains(a.id);
        final bSelected = _selectedBrandIds.contains(b.id);
        if (aSelected != bSelected) return aSelected ? -1 : 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    if (brands.isEmpty) return const SizedBox.shrink();
    final visible = _showAllBrands ? brands : brands.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFacetHeading('Marca'),
        const SizedBox(height: 8),
        ...visible.map(
          (brand) => _buildFacetCheckbox(
            checked: _selectedBrandIds.contains(brand.id),
            label: brand.label,
            count: brand.itemCount,
            onChanged: () {
              _toggleBrand(brand.id);
              refreshPanel?.call();
            },
          ),
        ),
        if (brands.length > 8)
          TextButton(
            onPressed: () {
              setState(() => _showAllBrands = !_showAllBrands);
              refreshPanel?.call();
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
            child: Text(
              _showAllBrands
                  ? 'Mostrar menos'
                  : 'Ver ${brands.length - visible.length} marcas más',
            ),
          ),
      ],
    );
  }

  Widget _buildPriceFacet(VoidCallback? refreshPanel) {
    if (!_catalogFacets.isAvailable) return const SizedBox.shrink();
    final hasBounds =
        _catalogFacets.minPrice != null && _catalogFacets.maxPrice != null;
    if (!hasBounds && _minPrice == null && _maxPrice == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFacetHeading('Precio'),
        if (hasBounds) ...[
          const SizedBox(height: 4),
          Text(
            '${ChileanUtils.formatCurrency(_catalogFacets.minPrice!)} – '
            '${ChileanUtils.formatCurrency(_catalogFacets.maxPrice!)}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _minPriceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Mínimo',
                  prefixText: r'$ ',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  _applyPriceRange();
                  refreshPanel?.call();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _maxPriceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Máximo',
                  prefixText: r'$ ',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  _applyPriceRange();
                  refreshPanel?.call();
                },
              ),
            ),
          ],
        ),
        if (_priceFilterError != null) ...[
          const SizedBox(height: 6),
          Text(
            _priceFilterError!,
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _applyPriceRange();
                  refreshPanel?.call();
                },
                child: const Text('Aplicar'),
              ),
            ),
            if (_minPrice != null || _maxPrice != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Quitar rango de precio',
                onPressed: () {
                  _clearPriceRange();
                  refreshPanel?.call();
                },
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildFacetHeading(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Colors.black87,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildFacetCheckbox({
    required bool checked,
    required String label,
    required int count,
    required VoidCallback onChanged,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Checkbox(
                value: checked,
                onChanged: (_) => onChanged(),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final sourceProducts = editProvider.isEditMode
        ? (_selectedProductType == null
            ? _allProducts
            : _allProducts
                .where((p) => p.productType == _selectedProductType)
                .toList())
        : null;
    final allCount = sourceProducts?.length ?? _categoryTotalCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Todas" option
        _buildCategoryOption(null, 'Todas', allCount, isRoot: true),
        const SizedBox(height: 4),
        // Hierarchical category tree
        ..._categoryTree.map((node) => _buildCategoryTreeNode(
              node,
              sourceProducts,
              depth: 0,
            )),
      ],
    );
  }

  /// Count products in a category and all its descendants
  int _countProductsInCategoryTree(
    _CategoryNode node,
    Iterable<Product>? products,
  ) {
    final validIds = node.getAllDescendantIds();
    if (products == null) {
      return validIds.fold<int>(
        0,
        (sum, categoryId) =>
            sum + (_directCategoryProductCounts[categoryId] ?? 0),
      );
    }

    return products
        .where((p) => p.categoryId != null && validIds.contains(p.categoryId))
        .length;
  }

  Widget _buildCategoryTreeNode(
    _CategoryNode node,
    List<Product>? sourceProducts, {
    required int depth,
  }) {
    final productCount = _countProductsInCategoryTree(node, sourceProducts);

    // Don't show categories with no products in their tree
    if (productCount == 0) return const SizedBox.shrink();

    final hasChildren = node.children.isNotEmpty;
    final isExpanded = _expandedCategories.contains(node.id);
    final isSelected = _selectedCategoryId == node.id;

    // Check if any child has products
    final childrenWithProducts = hasChildren
        ? node.children
            .where((child) =>
                child.showOnWebsite &&
                _countProductsInCategoryTree(child, sourceProducts) > 0)
            .toList()
        : <_CategoryNode>[];
    final hasVisibleChildren = childrenWithProducts.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category row with optional expand arrow
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                // Auto-expand when selecting a parent category
                if (hasVisibleChildren && !isExpanded) {
                  _expandedCategories.add(node.id);
                }
              });
              _selectCategory(node.id);
            },
            child: Padding(
              padding: EdgeInsets.only(
                left: depth * 16.0,
                top: 8,
                bottom: 8,
              ),
              child: Row(
                children: [
                  // Expand/collapse arrow for categories with children
                  if (hasVisibleChildren)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedCategories.remove(node.id);
                          } else {
                            _expandedCategories.add(node.id);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    )
                  else
                    const SizedBox(
                        width: 22), // Align with items that have arrows
                  // Selection indicator
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? Colors.black : Colors.transparent,
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.grey.shade400,
                        width: 1.5,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  // Category name and count
                  Expanded(
                    child: Text(
                      '${node.name} ($productCount)',
                      style: TextStyle(
                        fontFamily: null,
                        fontSize: 13,
                        color: isSelected ? Colors.black : Colors.grey.shade700,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Children (if expanded)
        if (isExpanded && hasVisibleChildren)
          ...childrenWithProducts.map((child) => _buildCategoryTreeNode(
                child,
                sourceProducts,
                depth: depth + 1,
              )),
      ],
    );
  }

  Widget _buildCategoryOption(String? id, String name, int count,
      {bool isRoot = false}) {
    final isSelected = _selectedCategoryId == id;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _selectCategory(id);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 22), // Align with tree items
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? Colors.black : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? Colors.black : Colors.grey.shade400,
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$name ($count)',
                  style: TextStyle(
                    fontFamily: null,
                    fontSize: 13,
                    color: isSelected ? Colors.black : Colors.grey.shade700,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final totalProducts = _totalProductCount;
    final startIndex = ((_currentPage - 1) * _itemsPerPage) + 1;
    final endIndex = (_currentPage * _itemsPerPage).clamp(0, totalProducts);
    final noun = _catalogNounPlural();
    final pageSizeOptions = {..._itemsPerPageOptions, _itemsPerPage}.toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final controls = _buildCatalogOrderControls(pageSizeOptions);
            if (constraints.maxWidth < 820) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCatalogHeading(compact: false),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: controls),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: _buildCatalogHeading(compact: false)),
                const SizedBox(width: 24),
                controls,
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          totalProducts > 0
              ? 'Mostrando $startIndex - $endIndex de $totalProducts $noun'
              : '0 $noun encontrados',
          style: TextStyle(
            fontFamily: null,
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        if (_isDirectCategoryScope) ...[
          const SizedBox(height: 5),
          _buildCategoryScopeIndicator(compact: false),
        ],
      ],
    );
  }

  Widget _buildCatalogOrderControls(List<int> pageSizeOptions) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mostrar:',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _itemsPerPage,
                  isDense: true,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                  items: pageSizeOptions
                      .map(
                        (count) => DropdownMenuItem(
                          value: count,
                          child: Text('$count por página'),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _itemsPerPage = value;
                      _currentPage = 1;
                    });
                    _syncCatalogQueryToRoute(resetPage: true);
                    _handleFiltersChanged();
                  },
                ),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ordenar por:',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _sortBy,
                  isDense: true,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'name', child: Text('Nombre')),
                    DropdownMenuItem(
                      value: 'price_asc',
                      child: Text('Precio ↑'),
                    ),
                    DropdownMenuItem(
                      value: 'price_desc',
                      child: Text('Precio ↓'),
                    ),
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text('Recientes'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _sortBy = value);
                    _syncCatalogQueryToRoute(resetPage: true);
                    _handleFiltersChanged();
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryScopeIndicator({required bool compact}) {
    final categoryName =
        _allCategoriesById[_selectedCategoryId]?.name.trim() ?? '';
    final qualifier =
        categoryName.isEmpty ? 'Solo esta categoría' : 'Solo $categoryName';

    return Wrap(
      key: const ValueKey<String>('catalog-category-scope-direct'),
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          label: categoryName.isEmpty
              ? 'Mostrando solo productos de esta categoría'
              : 'Mostrando solo productos asignados directamente a $categoryName',
          child: Text(
            qualifier,
            style: TextStyle(
              fontFamily: null,
              fontSize: compact ? 11 : 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          key: const ValueKey<String>(
            'catalog-category-scope-include-descendants',
          ),
          onPressed: _includeCategoryDescendants,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.primary,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: TextStyle(
              fontFamily: null,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Text('Incluir subcategorías'),
        ),
      ],
    );
  }

  String _catalogTitle() {
    return _selectedProductType == ProductType.service
        ? 'SERVICIOS'
        : 'PRODUCTOS';
  }

  Widget _buildCatalogHeading({required bool compact}) {
    final selectedId = _selectedCategoryId;
    final presentation = _presentationForCategory(selectedId);
    final showHierarchy =
        selectedId != null && presentation?.showBreadcrumbs == true;
    final path =
        showHierarchy ? _selectedCategoryPath() : const <_CategoryNode>[];
    final baseLabel =
        _selectedProductType == ProductType.service ? 'Servicios' : 'Productos';
    final textStyle = TextStyle(
      fontFamily: null,
      fontSize: compact ? 18 : 20,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: Colors.black,
    );

    Widget segment({
      required String label,
      required VoidCallback? onTap,
      required bool current,
    }) {
      return InkWell(
        onTap: current ? null : onTap,
        borderRadius: BorderRadius.circular(2),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            label,
            style: textStyle.copyWith(
              color: current ? Colors.black : Colors.grey.shade700,
              fontWeight: current ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 24,
          color: Colors.black,
          margin: const EdgeInsets.only(right: 12),
        ),
        Expanded(
          child: showHierarchy
              ? Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    segment(
                      label: baseLabel,
                      onTap: () => _selectCategory(null),
                      current: false,
                    ),
                    for (final item in path) ...[
                      Text(
                        '/',
                        style: textStyle.copyWith(
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      segment(
                        label: item.name,
                        onTap: () => _selectCategory(item.id),
                        current: item.id == selectedId,
                      ),
                    ],
                  ],
                )
              : Text(_catalogTitle(), style: textStyle),
        ),
      ],
    );
  }

  String _catalogNounPlural() {
    return _selectedProductType == ProductType.service
        ? 'servicios'
        : 'productos';
  }

  Widget _buildProductGrid(String modeKey) {
    if (_isRefreshing) {
      return const SizedBox(
        height: 320,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (_filteredProducts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(64),
          child: Column(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'No se encontraron ${_catalogNounPlural()}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Intenta ajustar los filtros de búsqueda',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Public and preview modes are already paged by the database; active edit
    // mode uses local pagination over the complete editable set.
    final isServerPaged = !context.read<WebsiteEditModeProvider>().isEditMode;
    final totalProducts =
        isServerPaged ? _totalProductCount : _filteredProducts.length;
    final totalPages = (totalProducts / _itemsPerPage).ceil();
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, totalProducts);
    final paginatedProducts = isServerPaged
        ? _filteredProducts
        : _filteredProducts.sublist(startIndex, endIndex);
    final gridDensity =
        _presentationForCategory(_selectedCategoryId)?.gridDensity ??
            WebsiteCatalogGridDensity.balanced;

    return MediaQueryLayoutBuilder(
      key: ValueKey('product_grid_layout_$modeKey'),
      builder: (context, constraints) {
        final metrics = websiteCatalogGridMetrics(
          width: constraints.maxWidth,
          density: gridDensity,
        );

        return Column(
          children: [
            // Product Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: metrics.crossAxisCount,
                childAspectRatio: metrics.childAspectRatio,
                crossAxisSpacing: metrics.crossAxisSpacing,
                mainAxisSpacing: metrics.mainAxisSpacing,
              ),
              itemCount: paginatedProducts.length,
              itemBuilder: (context, index) {
                return _CatalogProductCard(product: paginatedProducts[index]);
              },
            ),

            // Pagination Controls
            if (totalPages > 1) ...[
              const SizedBox(height: 32),
              _buildPaginationControls(totalPages),
            ],
          ],
        );
      },
    );
  }

  void _goToPage(int page) {
    final nextPage = page < 1 ? 1 : page;
    if (nextPage == _currentPage) return;
    final editProvider = context.read<WebsiteEditModeProvider>();
    final signature = _activeCatalogPageSignature;
    final cachedPage = signature == null
        ? null
        : _catalogPageCache.peek(
            signature: signature,
            pageNumber: nextPage,
          );
    setState(() {
      _currentPage = nextPage;
      if (!editProvider.isEditMode) {
        if (cachedPage != null) {
          _allProducts = cachedPage.products;
          _filteredProducts = cachedPage.products;
          _totalProductCount = cachedPage.totalCount;
          _isRefreshing = false;
        } else {
          _allProducts = const [];
          _filteredProducts = const [];
          _totalProductCount = 0;
          _isRefreshing = true;
        }
      }
    });

    final currentUri = GoRouterState.of(context).uri;
    final scrollState = context.read<PublicStoreScrollState>();
    scrollState.requestScrollToTop(currentUri.toString());
    scrollState.requestScrollToTopForPath(currentUri.path);
    _syncCatalogQueryToRoute();

    if (!editProvider.isEditMode) {
      unawaited(_loadProducts(resetPage: false));
    }
  }

  Widget _buildPaginationControls(int totalPages) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous button
        if (_currentPage > 1)
          TextButton(
            onPressed: () => _goToPage(_currentPage - 1),
            child: Row(
              children: [
                Icon(Icons.chevron_left, size: 20, color: Colors.grey.shade700),
                Text('Anterior', style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          )
        else
          const SizedBox(width: 100),

        const SizedBox(width: 16),

        // Page numbers
        ..._buildPageNumbers(totalPages),

        const SizedBox(width: 16),

        // Next button
        if (_currentPage < totalPages)
          TextButton(
            onPressed: () => _goToPage(_currentPage + 1),
            child: Row(
              children: [
                Text('Siguiente',
                    style: TextStyle(color: Colors.grey.shade700)),
                Icon(Icons.chevron_right,
                    size: 20, color: Colors.grey.shade700),
              ],
            ),
          )
        else
          const SizedBox(width: 100),
      ],
    );
  }

  List<Widget> _buildPageNumbers(int totalPages) {
    final List<Widget> pages = [];

    // Show first page, last page, current page, and neighbors
    // Pattern: 1 2 3 ... 28 29 30 (when on page 1-3)
    // Pattern: 1 ... 5 6 7 ... 30 (when on page 6)
    // Pattern: 1 ... 28 29 30 (when on page 28-30)

    final Set<int> pagesToShow = {};

    // Always show first and last page
    pagesToShow.add(1);
    pagesToShow.add(totalPages);

    // Show current page and neighbors
    for (int i = _currentPage - 1; i <= _currentPage + 1; i++) {
      if (i >= 1 && i <= totalPages) {
        pagesToShow.add(i);
      }
    }

    // Show pages 2, 3 if we're near the start
    if (_currentPage <= 3) {
      pagesToShow.addAll([2, 3].where((p) => p <= totalPages));
    }

    // Show last few pages if we're near the end
    if (_currentPage >= totalPages - 2) {
      pagesToShow.addAll([totalPages - 2, totalPages - 1].where((p) => p >= 1));
    }

    final sortedPages = pagesToShow.toList()..sort();

    for (int i = 0; i < sortedPages.length; i++) {
      final page = sortedPages[i];

      // Add ellipsis if there's a gap
      if (i > 0 && page - sortedPages[i - 1] > 1) {
        pages.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('...', style: TextStyle(color: Colors.grey.shade600)),
          ),
        );
      }

      pages.add(_buildPageButton(page));
    }

    return pages;
  }

  Widget _buildPageButton(int page) {
    final isSelected = page == _currentPage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => _goToPage(page),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFB71C1C) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            '$page',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}

// Premium product card for catalog page
class _CatalogProductCard extends StatefulWidget {
  final Product product;

  const _CatalogProductCard({required this.product});

  @override
  State<_CatalogProductCard> createState() => _CatalogProductCardState();
}

class _CatalogProductCardState extends State<_CatalogProductCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final brand = product.brand?.trim();
    final hasBrand = brand != null && brand.isNotEmpty;
    // Prefer optimized image for faster loading, fallback to original
    final displayImageUrl = product.imageUrlOptimized ?? product.imageUrl;
    final hasImage = displayImageUrl != null && displayImageUrl.isNotEmpty;
    final isInStock =
        product.tracksInventory ? product.availableStockQuantity > 0 : true;
    final stockLabel = isInStock ? 'EN STOCK' : 'AGOTADO';
    const hoverDuration = Duration(milliseconds: 220);
    const logoBlue = Color(0xFF0B3A5F);

    final mediaQuery = MediaQuery.maybeOf(context);
    final reduceMotion = (mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false);

    final hoverActive = _isHovered && !reduceMotion;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => PublicStoreLayout.navigateToHref(
            context, publicProductPath(product)),
        child: AnimatedContainer(
          duration: hoverDuration,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: hoverActive ? Colors.white : Colors.transparent,
            boxShadow: hoverActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 34,
                      spreadRadius: 2,
                      offset: const Offset(0, 18),
                    ),
                  ]
                : const [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Product Image Area
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: Colors.white,
                      padding: EdgeInsets.fromLTRB(
                        12,
                        10,
                        12,
                        hasBrand ? 28 : 10,
                      ),
                      child: hasImage
                          ? Image.network(
                              displayImageUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Icon(
                                    Icons.pedal_bike_outlined,
                                    size: 48,
                                    color: Colors.grey.shade300,
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Icon(
                                Icons.pedal_bike_outlined,
                                size: 48,
                                color: Colors.grey.shade300,
                              ),
                            ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: hoverDuration,
                          curve: Curves.easeOutCubic,
                          height: hoverActive ? 42 : 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          color: logoBlue.withValues(alpha: 0.78),
                          child: AnimatedOpacity(
                            duration: hoverDuration,
                            curve: Curves.easeOutCubic,
                            opacity: hoverActive ? 1 : 0,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    hasBrand ? brand.toUpperCase() : '',
                                    style: const TextStyle(
                                      fontFamily: null,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: 0.65,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  stockLabel,
                                  style: const TextStyle(
                                    fontFamily: null,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.75,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (hasBrand && !hoverActive)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 6,
                        child: Text(
                          brand.toUpperCase(),
                          style: TextStyle(
                            fontFamily: null,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.45,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              // Product Info Area — fixed height keeps separators aligned; content stays top-stacked.
              SizedBox(
                height: 90,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: hoverActive
                            ? Colors.transparent
                            : const Color(0xFFE8E2D8),
                        width: 1,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: null,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                          height: 1.3,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ChileanUtils.formatCurrency(product.price),
                        style: const TextStyle(
                          fontFamily: null,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
