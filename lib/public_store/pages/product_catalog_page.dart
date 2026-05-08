import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// import '../theme/public_store_theme.dart'; // Unused
import '../services/public_inventory_service.dart';
import '../services/public_store_scroll_state.dart';
import '../providers/public_store_tenant_provider.dart';
import '../theme/public_store_theme.dart';
import '../../shared/models/product.dart';
import '../../shared/utils/chilean_utils.dart';
// import '../providers/cart_provider.dart'; // Unused
import '../widgets/full_page_loading.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../shared/services/tenant_service.dart';
import '../../shared/widgets/safe_layout_builder.dart';
import '../widgets/public_store_layout.dart';

class ProductCatalogPage extends StatefulWidget {
  const ProductCatalogPage({super.key});

  @override
  State<ProductCatalogPage> createState() => _ProductCatalogPageState();
}

/// Represents a category node in the hierarchical tree
class _CategoryNode {
  final String id;
  final String name;
  final String? parentId;
  final List<_CategoryNode> children;

  _CategoryNode({
    required this.id,
    required this.name,
    this.parentId,
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
  bool _hasLoadedInitialProducts = false;
  int _totalProductCount = 0;
  int _categoryTotalCount = 0;
  int _loadToken = 0;
  String _lastCategoryCountsSignature = '';
  Timer? _searchDebounce;

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

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 20; // Default: 20 items per page
  static const List<int> _itemsPerPageOptions = [20, 50, 100];

  String _searchQuery = '';
  String _lastRouteFiltersSignature = '';
  String? _selectedCategoryId;
  ProductType? _selectedProductType = ProductType.product;
  String? _pendingRouteCategoryValue;
  String _sortBy = 'name'; // name, price_asc, price_desc, newest
  bool _isGridView = true; // Grid view vs list view

  // DISABLED: AutomaticKeepAliveClientMixin causes element activation conflicts
  // during edit/preview mode switches. The performance cost of reloading is acceptable.
  @override
  bool get wantKeepAlive => false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFiltersFromRoute();
  }

  void _syncFiltersFromRoute() {
    final uri = GoRouterState.of(context).uri;
    final qp = uri.queryParameters;
    final routePath = uri.path.trim().toLowerCase();
    final legacyCategoria = (qp['categoria'] ?? '').trim();
    var routeQuery = (qp['q'] ?? qp['search'] ?? '').trim();
    final routeCategoryFromPath = _categoryValueFromPath(uri.path);
    final routeCategory = (routeCategoryFromPath ??
            qp['category'] ??
            qp['category_id'] ??
            qp['cat'] ??
            '')
        .trim();
    final routeType =
        (qp['type'] ?? qp['product_type'] ?? qp['tipo'] ?? '').trim();

    // Backward-compat: historically, some website links used `?categoria=mtb`
    // as a collection-style filter. We now treat that value as a free-text
    // search term (so it never “forces” the catalog into a wrong category).
    if (routeQuery.isEmpty && legacyCategoria.isNotEmpty) {
      routeQuery = legacyCategoria;
    }

    final signature =
        '$routePath|$routeQuery|$routeCategory|$routeType|$legacyCategoria';
    if (signature == _lastRouteFiltersSignature) return;
    _lastRouteFiltersSignature = signature;

    final parsedType = _parseProductType(routeType);
    final routeDefaultType = _defaultProductTypeForRoute(routePath);

    // Avoid calling setState during build (this page can be kept-alive/offstage).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        _searchQuery = routeQuery;
        _selectedProductType = parsedType ?? routeDefaultType;

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
        } else {
          final resolved = _resolveCategoryIdFromValue(routeCategory);
          if (resolved == null && !_looksLikeUuid(routeCategory)) {
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
          }
        }
      });

      _handleFiltersChanged();
    });
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
    final match =
        RegExp(r'^/(?:productos|servicios)/categoria/([^/?#]+)').firstMatch(
      path.trim(),
    );
    final raw = match?.group(1);
    if (raw == null || raw.isEmpty) return null;
    return Uri.decodeComponent(raw.replaceAll('-', ' '));
  }

  bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  String? _resolveCategoryIdFromValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // If it's already an ID, accept it.
    if (_looksLikeUuid(trimmed)) return trimmed;

    final wanted = _normalizeForSearch(trimmed);
    if (wanted.isEmpty) return null;

    for (final entry in _allCategoriesById.entries) {
      final normalizedName = _normalizeForSearch(entry.value.name);
      if (normalizedName == wanted || normalizedName.contains(wanted)) {
        return entry.key;
      }
    }

    return null;
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty && _filtersSearchController.text.isEmpty) return;
    setState(() {
      _searchQuery = '';
      _filtersSearchController.clear();
    });
    _handleFiltersChanged();

    // Best-effort: remove q/search from the URL so refresh/share is consistent.
    try {
      final router = GoRouter.of(context);
      final uri = GoRouterState.of(context).uri;
      final nextQp = Map<String, String>.from(uri.queryParameters)
        ..remove('q')
        ..remove('search');
      final destination = Uri(
        path: uri.path,
        queryParameters: nextQp.isEmpty ? null : nextQp,
      ).toString();
      router.replace(destination);
      _lastRouteFiltersSignature = '';
    } catch (_) {
      // Ignore (non-critical)
    }
  }

  Future<void> _loadProducts({bool resetPage = false}) async {
    final token = ++_loadToken;

    // Check if we're in edit mode (admin editing website)
    final editProvider = context.read<WebsiteEditModeProvider>();

    // Get tenant from provider (detected from subdomain)
    final tenantProvider = context.read<PublicStoreTenantProvider>();
    String? tenantId = tenantProvider.tenantId;

    // FALLBACK: In editor context, subdomain detection doesn't work.
    // Use the authenticated user's tenant instead.
    if (tenantId == null && editProvider.isInEditorContext) {
      final tenantService = context.read<TenantService>();
      tenantId = tenantService.currentTenantId;
      debugPrint('[ProductCatalogPage] Using authenticated tenant: $tenantId');
    }

    if (tenantId == null) {
      debugPrint('[ProductCatalogPage] No tenant ID available');
      setState(() => _isLoading = false);
      return;
    }

    // Use public inventory service (works for anonymous users)
    final publicInventoryService = context.read<PublicInventoryService>();

    if (resetPage) {
      _currentPage = 1;
    }

    if (!_hasLoadedInitialProducts) {
      setState(() => _isLoading = true);
    }

    try {
      // Load visible categories (show_on_website = true)
      await _loadVisibleCategories(tenantId);
      if (!mounted || token != _loadToken) return;

      // If the URL carried a category filter we couldn't resolve earlier (e.g.
      // because categories weren't loaded yet), resolve it now.
      if (_pendingRouteCategoryValue != null) {
        final resolved =
            _resolveCategoryIdFromValue(_pendingRouteCategoryValue!);
        if (resolved != null && mounted) {
          setState(() {
            _selectedCategoryId = resolved;
            _pendingRouteCategoryValue = null;
          });
        } else if (resolved == null && mounted) {
          // If we still can't resolve the legacy category token after products
          // load, fall back to using it as a search query.
          final token = _pendingRouteCategoryValue!.trim();
          if (token.isNotEmpty && _searchQuery.isEmpty) {
            setState(() {
              _searchQuery = token;
              _filtersSearchController.value =
                  _filtersSearchController.value.copyWith(
                text: token,
                selection: TextSelection.collapsed(offset: token.length),
                composing: TextRange.empty,
              );
              _pendingRouteCategoryValue = null;
              _selectedCategoryId = null;
            });
          } else {
            setState(() {
              _pendingRouteCategoryValue = null;
            });
          }
        }
      }

      if (editProvider.isInEditorContext) {
        // Editor/preview still needs the full editable product set.
        final products = await publicInventoryService.getProductsForTenant(
          tenantId: tenantId,
          onlyInStock: false,
          includeUnpublished: true,
        );
        if (!mounted || token != _loadToken) return;

        _allProducts = products;
        _totalProductCount = products.length;
        debugPrint('[ProductCatalogPage] Loaded ${products.length} products');
        _applyLocalFilters();
        return;
      }

      await _loadCategoryCounts(
        tenantId: tenantId,
        service: publicInventoryService,
      );
      if (!mounted || token != _loadToken) return;

      final selectedCategoryIds = _selectedCategoryId == null
          ? null
          : _getCategoryAndDescendantIds(_selectedCategoryId!).toList();
      final page = await publicInventoryService.getProductPageForTenant(
        tenantId: tenantId,
        categoryIds: selectedCategoryIds,
        searchQuery: _searchQuery.trim().isEmpty ? null : _searchQuery,
        productType: _selectedProductType,
        onlyInStock: true,
        sortBy: _sortBy,
        limit: _itemsPerPage,
        offset: (_currentPage - 1) * _itemsPerPage,
      );
      if (!mounted || token != _loadToken) return;

      setState(() {
        _allProducts = page.products;
        _filteredProducts = page.products;
        _totalProductCount = page.totalCount;
        _hasLoadedInitialProducts = true;
      });

      debugPrint(
          '[ProductCatalogPage] Loaded page ${page.products.length}/${page.totalCount} products');
    } catch (e) {
      debugPrint('[ProductCatalogPage] Error loading products: $e');
    } finally {
      if (mounted && token == _loadToken) {
        setState(() {
          _isLoading = false;
          _hasLoadedInitialProducts = true;
        });
      }
    }
  }

  Future<void> _loadCategoryCounts({
    required String tenantId,
    required PublicInventoryService service,
  }) async {
    final signature = '$tenantId|${_selectedProductType?.name ?? 'all'}';
    if (signature == _lastCategoryCountsSignature) return;

    final snapshot = await service.getCategoryCountsForTenant(
      tenantId: tenantId,
      productType: _selectedProductType,
      onlyInStock: true,
    );

    if (!mounted) return;
    setState(() {
      _directCategoryProductCounts = snapshot.directCountsByCategoryId;
      _categoryTotalCount = snapshot.totalCount;
      _lastCategoryCountsSignature = signature;
    });
  }

  Future<void> _loadVisibleCategories(String tenantId) async {
    try {
      // Load ALL categories to build the hierarchy
      // We need the full tree to show children of visible parents
      final response = await Supabase.instance.client
          .from('product_categories')
          .select('id, name, parent_id, show_on_website')
          .eq('tenant_id', tenantId)
          .eq('is_active', true)
          .eq('show_on_website', true)
          .order('name');

      final allCategories = <String, Map<String, dynamic>>{};
      final visibleCategoryIds = <String>{};

      // First pass: collect all categories and identify visible ones
      for (final row in response as List) {
        final id = row['id'] as String?;
        if (id == null) continue;
        allCategories[id] = row as Map<String, dynamic>;
        if (row['show_on_website'] == true) {
          visibleCategoryIds.add(id);
        }
      }

      // Build nodes for all categories
      final nodesById = <String, _CategoryNode>{};
      for (final entry in allCategories.entries) {
        final id = entry.key;
        final data = entry.value;
        nodesById[id] = _CategoryNode(
          id: id,
          name: data['name'] as String? ?? 'Sin nombre',
          parentId: data['parent_id'] as String?,
        );
      }

      // Build parent-child relationships
      for (final node in nodesById.values) {
        if (node.parentId != null && nodesById.containsKey(node.parentId)) {
          nodesById[node.parentId]!.children.add(node);
        }
      }

      // Sort children alphabetically
      for (final node in nodesById.values) {
        node.children.sort((a, b) => a.name.compareTo(b.name));
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
      rootCategories.sort((a, b) => a.name.compareTo(b.name));

      if (mounted) {
        setState(() {
          _categoryTree = rootCategories;
          _allCategoriesById = nodesById;
        });
      }
      debugPrint(
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

  void _handleFiltersChanged({bool debounce = false}) {
    final editProvider = context.read<WebsiteEditModeProvider>();
    if (editProvider.isInEditorContext) {
      _applyLocalFilters();
      return;
    }

    _searchDebounce?.cancel();
    if (debounce) {
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _loadProducts(resetPage: true);
        }
      });
      return;
    }

    _loadProducts(resetPage: true);
  }

  void _applyLocalFilters() {
    setState(() {
      // Reset to first page when filters change
      _currentPage = 1;

      final tokens = _tokenizeSearchQuery(_searchQuery);

      _filteredProducts = _allProducts.where((product) {
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

        // Category filter - includes selected category AND all descendants
        if (_selectedCategoryId != null) {
          final validCategoryIds =
              _getCategoryAndDescendantIds(_selectedCategoryId!);
          if (product.categoryId == null ||
              !validCategoryIds.contains(product.categoryId)) {
            return false;
          }
        }

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
    });
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
      builder: (context) => DraggableScrollableSheet(
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
                child: _buildFilters(),
              ),
            ),
          ],
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
        setState(() => _sortBy = value);
        _handleFiltersChanged();
        Navigator.pop(context);
      },
    );
  }

  @override
  void dispose() {
    // Debug: dispose
    _searchDebounce?.cancel();
    _filtersSearchController.dispose();
    _filtersSearchFocusNode.dispose();
    super.dispose();
  }

  Widget _buildActiveSearchIndicator() {
    final q = _searchQuery.trim();
    if (q.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha(18),
        border: Border.all(color: Colors.blue.withAlpha(40)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Filtrando por: "$q"',
              style: TextStyle(
                fontSize: 13,
                color: Colors.blue.shade900,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _clearSearch,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close, size: 16, color: Colors.blue.shade700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // Debug: build
    if (_isLoading) {
      return const FullPageLoading();
    }

    // Get edit mode to use as key suffix - prevents element reactivation conflicts
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final modeKey = editProvider.isEditMode
        ? 'edit'
        : (editProvider.isPreviewMode ? 'preview' : 'normal');

    return Container(
      color: Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1560),
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
                    // Header section - clean white
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 24,
                                color: Colors.black,
                                margin: const EdgeInsets.only(right: 12),
                              ),
                              Text(
                                _catalogTitle(),
                                style: const TextStyle(
                                  fontFamily:
                                      PublicStoreTheme.defaultHeadingFont,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$_totalProductCount ${_catalogNounPlural()}',
                            style: TextStyle(
                              fontFamily: PublicStoreTheme.defaultBodyFont,
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Controls bar
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
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
                                    fontFamily:
                                        PublicStoreTheme.defaultHeadingFont,
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
                                    fontFamily:
                                        PublicStoreTheme.defaultHeadingFont,
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
                          // View toggles
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.grid_view,
                                    size: 20,
                                    color: _isGridView
                                        ? Colors.black
                                        : Colors.grey.shade400),
                                onPressed: () =>
                                    setState(() => _isGridView = true),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                              ),
                              IconButton(
                                icon: Icon(Icons.view_list,
                                    size: 20,
                                    color: !_isGridView
                                        ? Colors.black
                                        : Colors.grey.shade400),
                                onPressed: () =>
                                    setState(() => _isGridView = false),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(8),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Product grid
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_searchQuery.trim().isNotEmpty)
                            _buildActiveSearchIndicator(),
                          const SizedBox(height: 12),
                          _buildProductGrid(modeKey),
                        ],
                      ),
                    ),
                  ],
                );
              }

              // Desktop: sidebar layout
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sidebar Filters
                    SizedBox(
                      width: 224,
                      child: _buildFilters(),
                    ),
                    const SizedBox(width: 32),
                    // Main Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          if (_searchQuery.trim().isNotEmpty)
                            _buildActiveSearchIndicator(),
                          const SizedBox(height: 24),
                          _buildProductGrid(modeKey),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Filtros',
          style: TextStyle(
            fontFamily: PublicStoreTheme.defaultHeadingFont,
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
              fontFamily: PublicStoreTheme.defaultBodyFont,
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
                    onPressed: _clearSearch,
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
            fontFamily: PublicStoreTheme.defaultBodyFont,
            fontSize: 14,
          ),
          onChanged: (value) {
            setState(() => _searchQuery = value);
            _handleFiltersChanged(debounce: true);
          },
        ),

        const SizedBox(height: 28),
        Container(height: 1, color: Colors.grey.shade200),
        const SizedBox(height: 20),

        // Categories
        const Text(
          'Categorías',
          style: TextStyle(
            fontFamily: PublicStoreTheme.defaultHeadingFont,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 16),
        _buildCategoryFilters(),
      ],
    );
  }

  Widget _buildCategoryFilters() {
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final sourceProducts = editProvider.isInEditorContext
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
                _countProductsInCategoryTree(child, sourceProducts) > 0)
            .toList()
        : <_CategoryNode>[];
    final hasVisibleChildren = childrenWithProducts.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category row with optional expand arrow
        InkWell(
          onTap: () {
            setState(() {
              _selectedCategoryId = node.id;
              // Auto-expand when selecting a parent category
              if (hasVisibleChildren && !isExpanded) {
                _expandedCategories.add(node.id);
              }
            });
            _handleFiltersChanged();
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
                      fontFamily: PublicStoreTheme.defaultBodyFont,
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
    return InkWell(
      onTap: () {
        setState(() => _selectedCategoryId = id);
        _handleFiltersChanged();
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
                  fontFamily: PublicStoreTheme.defaultBodyFont,
                  fontSize: 13,
                  color: isSelected ? Colors.black : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final totalProducts = _totalProductCount;
    final startIndex = ((_currentPage - 1) * _itemsPerPage) + 1;
    final endIndex = (_currentPage * _itemsPerPage).clamp(0, totalProducts);
    final titleText = _catalogTitle();
    final noun = _catalogNounPlural();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title section
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              color: Colors.black,
              margin: const EdgeInsets.only(right: 12),
            ),
            Text(
              titleText,
              style: const TextStyle(
                fontFamily: PublicStoreTheme.defaultHeadingFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          totalProducts > 0
              ? 'Mostrando $startIndex - $endIndex de $totalProducts $noun'
              : '0 $noun encontrados',
          style: TextStyle(
            fontFamily: PublicStoreTheme.defaultBodyFont,
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 16),
        // Controls - use Wrap to prevent overflow on mobile
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Items per page selector
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
                      style:
                          const TextStyle(fontSize: 13, color: Colors.black87),
                      items: _itemsPerPageOptions.map((count) {
                        return DropdownMenuItem(
                          value: count,
                          child: Text('$count por página'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _itemsPerPage = value;
                            _currentPage = 1;
                          });
                          _handleFiltersChanged();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            // Sort Dropdown
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
                      style:
                          const TextStyle(fontSize: 13, color: Colors.black87),
                      items: const [
                        DropdownMenuItem(value: 'name', child: Text('Nombre')),
                        DropdownMenuItem(
                            value: 'price_asc', child: Text('Precio ↑')),
                        DropdownMenuItem(
                            value: 'price_desc', child: Text('Precio ↓')),
                        DropdownMenuItem(
                            value: 'newest', child: Text('Recientes')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _sortBy = value);
                          _handleFiltersChanged();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  String _catalogTitle() {
    return _selectedProductType == ProductType.service
        ? 'SERVICIOS'
        : 'PRODUCTOS';
  }

  String _catalogNounPlural() {
    return _selectedProductType == ProductType.service
        ? 'servicios'
        : 'productos';
  }

  Widget _buildProductGrid(String modeKey) {
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

    // Calculate pagination. Public mode is already paged by the database;
    // editor mode still uses local pagination over the full editable set.
    final isServerPaged =
        !context.read<WebsiteEditModeProvider>().isInEditorContext;
    final totalProducts =
        isServerPaged ? _totalProductCount : _filteredProducts.length;
    final totalPages = (totalProducts / _itemsPerPage).ceil();
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, totalProducts);
    final paginatedProducts = isServerPaged
        ? _filteredProducts
        : _filteredProducts.sublist(startIndex, endIndex);

    return MediaQueryLayoutBuilder(
      key: ValueKey('product_grid_layout_$modeKey'),
      builder: (context, constraints) {
        // Responsive grid settings
        final width = constraints.maxWidth;
        int crossAxisCount;
        double childAspectRatio;
        double crossAxisSpacing;
        double mainAxisSpacing;

        if (width < 400) {
          crossAxisCount = 2;
          childAspectRatio = 0.58;
          crossAxisSpacing = 16;
          mainAxisSpacing = 22;
        } else if (width < 600) {
          crossAxisCount = 2;
          childAspectRatio = 0.63;
          crossAxisSpacing = 18;
          mainAxisSpacing = 24;
        } else if (width < 980) {
          crossAxisCount = 3;
          childAspectRatio = 0.69;
          crossAxisSpacing = 22;
          mainAxisSpacing = 30;
        } else if (width < 1320) {
          crossAxisCount = 4;
          childAspectRatio = 0.72;
          crossAxisSpacing = 24;
          mainAxisSpacing = 32;
        } else {
          crossAxisCount = 5;
          childAspectRatio = 0.75;
          crossAxisSpacing = 28;
          mainAxisSpacing = 36;
        }

        return Column(
          children: [
            // Product Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: crossAxisSpacing,
                mainAxisSpacing: mainAxisSpacing,
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
    setState(() => _currentPage = nextPage);

    final currentUri = GoRouterState.of(context).uri;
    final scrollState = context.read<PublicStoreScrollState>();
    scrollState.requestScrollToTop(currentUri.toString());
    scrollState.requestScrollToTopForPath(currentUri.path);

    final editProvider = context.read<WebsiteEditModeProvider>();
    if (!editProvider.isInEditorContext) {
      _loadProducts();
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
        product.tracksInventory ? product.stockQuantity > 0 : true;
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
            context, '/productos/${product.id}'),
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
                                      fontFamily:
                                          PublicStoreTheme.defaultBodyFont,
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
                                    fontFamily:
                                        PublicStoreTheme.defaultBodyFont,
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
                            fontFamily: PublicStoreTheme.defaultBodyFont,
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
                          fontFamily: PublicStoreTheme.defaultHeadingFont,
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
                          fontFamily: PublicStoreTheme.defaultBodyFont,
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
