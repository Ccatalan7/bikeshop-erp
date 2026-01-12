import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
// import '../theme/public_store_theme.dart'; // Unused
import '../services/public_inventory_service.dart';
import '../providers/public_store_tenant_provider.dart';
import '../../shared/models/product.dart';
import '../../shared/utils/chilean_utils.dart';
// import '../providers/cart_provider.dart'; // Unused
import '../widgets/full_page_loading.dart';
import '../../modules/website/providers/website_edit_mode_provider.dart';
import '../../shared/services/tenant_service.dart';

class ProductCatalogPage extends StatefulWidget {
  const ProductCatalogPage({super.key});

  @override
  State<ProductCatalogPage> createState() => _ProductCatalogPageState();
}

class _ProductCatalogPageState extends State<ProductCatalogPage>
    with AutomaticKeepAliveClientMixin {
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;

  final TextEditingController _filtersSearchController =
      TextEditingController();

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 20; // Default: 20 items per page
  static const List<int> _itemsPerPageOptions = [20, 50, 100];

  String _searchQuery = '';
  String _lastRouteFiltersSignature = '';
  String? _selectedCategoryId;
  ProductType? _selectedProductType;
  String? _pendingRouteCategoryValue;
  String _sortBy = 'name'; // name, price_asc, price_desc, newest
  bool _isGridView = true; // Grid view vs list view

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Debug: initState
    _loadProducts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFiltersFromRoute();
  }

  void _syncFiltersFromRoute() {
    final qp = GoRouterState.of(context).uri.queryParameters;
    final legacyCategoria = (qp['categoria'] ?? '').trim();
    var routeQuery = (qp['q'] ?? qp['search'] ?? '').trim();
    final routeCategory = (qp['category'] ?? qp['category_id'] ?? qp['cat'] ?? '')
        .trim();
    final routeType = (qp['type'] ?? qp['product_type'] ?? qp['tipo'] ?? '').trim();

    // Backward-compat: historically, some website links used `?categoria=mtb`
    // as a collection-style filter. We now treat that value as a free-text
    // search term (so it never “forces” the catalog into a wrong category).
    if (routeQuery.isEmpty && legacyCategoria.isNotEmpty) {
      routeQuery = legacyCategoria;
    }

    final signature = '$routeQuery|$routeCategory|$routeType|$legacyCategoria';
    if (signature == _lastRouteFiltersSignature) return;
    _lastRouteFiltersSignature = signature;

    final parsedType = _parseProductType(routeType);

    // Avoid calling setState during build (this page can be kept-alive/offstage).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        _searchQuery = routeQuery;
        _selectedProductType = parsedType;

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
                  selection: TextSelection.collapsed(offset: routeCategory.length),
                  composing: TextRange.empty,
                );
              }
            }
            _selectedCategoryId = null;
            _pendingRouteCategoryValue = null;
          } else {
            _selectedCategoryId = resolved;
            _pendingRouteCategoryValue = resolved == null ? routeCategory : null;
          }
        }
      });

      _applyFilters();
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

    // Best-effort mapping by category name.
    if (_allProducts.isEmpty) return null;

    final wanted = _normalizeForSearch(trimmed);
    if (wanted.isEmpty) return null;

    // If a type filter is active, prefer matching within that subset.
    final sourceProducts = _selectedProductType == null
        ? _allProducts
        : _allProducts.where((p) => p.productType == _selectedProductType).toList();

    final categoriesMap = <String, String>{};
    for (final p in sourceProducts) {
      final id = p.categoryId;
      if (id == null) continue;
      categoriesMap[id] = p.categoryName ?? 'Sin categoría';
    }

    String? bestId;
    for (final entry in categoriesMap.entries) {
      final normalizedName = _normalizeForSearch(entry.value);
      if (normalizedName == wanted || normalizedName.contains(wanted)) {
        bestId = entry.key;
        break;
      }
    }
    return bestId;
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty && _filtersSearchController.text.isEmpty) return;
    setState(() {
      _searchQuery = '';
      _filtersSearchController.clear();
    });
    _applyFilters();

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

  Future<void> _loadProducts() async {
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

    setState(() => _isLoading = true);

    try {
      // Load ALL products at once (no pagination) so search works across entire catalog
      var products = await publicInventoryService.getProductsForTenant(
        tenantId: tenantId,
        onlyInStock: !editProvider
            .isInEditorContext, // Show all products in edit/preview mode
        // No limit - fetch all products
      );

      _allProducts = products;
      debugPrint('[ProductCatalogPage] Loaded ${products.length} products');

      // If the URL carried a category filter we couldn't resolve earlier (e.g.
      // because products weren't loaded yet), resolve it now.
      if (_pendingRouteCategoryValue != null) {
        final resolved = _resolveCategoryIdFromValue(_pendingRouteCategoryValue!);
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

      _applyFilters();
    } catch (e) {
      debugPrint('[ProductCatalogPage] Error loading products: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
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

        // Category filter
        if (_selectedCategoryId != null &&
            product.categoryId != _selectedCategoryId) {
          return false;
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
        _applyFilters();
        Navigator.pop(context);
      },
    );
  }

  @override
  void dispose() {
    // Debug: dispose
    _filtersSearchController.dispose();
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

    return Container(
      color: Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: LayoutBuilder(
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
                              const Text(
                                'PRODUCTOS',
                                style: TextStyle(
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
                            '${_filteredProducts.length} productos',
                            style: TextStyle(
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
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
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
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
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
                          _buildProductGrid(),
                        ],
                      ),
                    ),
                  ],
                );
              }

              // Desktop: sidebar layout
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sidebar Filters
                    SizedBox(
                      width: 260,
                      child: _buildFilters(),
                    ),
                    const SizedBox(width: 40),
                    // Main Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          if (_searchQuery.trim().isNotEmpty)
                            _buildActiveSearchIndicator(),
                          const SizedBox(height: 24),
                          _buildProductGrid(),
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
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 24),

        // Search
        TextField(
          controller: _filtersSearchController,
          decoration: InputDecoration(
            hintText: 'Buscar productos',
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
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
          style: const TextStyle(fontSize: 14),
          onChanged: (value) {
            _searchQuery = value;
            _applyFilters();
          },
        ),

        const SizedBox(height: 32),
        Container(height: 1, color: Colors.grey.shade200),
        const SizedBox(height: 24),

        // Categories
        const Text(
          'Categorías',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        _buildCategoryFilters(),
      ],
    );
  }

  Widget _buildCategoryFilters() {
    // Use a Map to properly deduplicate categories by ID
    final categoriesMap = <String, String>{};
    final sourceProducts = _selectedProductType == null
        ? _allProducts
        : _allProducts.where((p) => p.productType == _selectedProductType);
    for (final p in sourceProducts) {
      if (p.categoryId != null) {
        categoriesMap[p.categoryId!] = p.categoryName ?? 'Sin categoría';
      }
    }

    // Sort categories alphabetically by name
    final sortedCategories = categoriesMap.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final allCount = sourceProducts.length;

    return Column(
      children: [
        _buildCategoryOption(null, 'Todas', allCount),
        ...sortedCategories.map((entry) {
          final count = sourceProducts.where((p) => p.categoryId == entry.key).length;
          return _buildCategoryOption(entry.key, entry.value, count);
        }),
      ],
    );
  }

  Widget _buildCategoryOption(String? id, String name, int count) {
    final isSelected = _selectedCategoryId == id;
    return InkWell(
      onTap: () {
        setState(() => _selectedCategoryId = id);
        _applyFilters();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.black : Colors.grey.shade400,
                  width: isSelected ? 5 : 1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$name ($count)',
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? Colors.black : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final totalProducts = _filteredProducts.length;
    final startIndex = ((_currentPage - 1) * _itemsPerPage) + 1;
    final endIndex = (_currentPage * _itemsPerPage).clamp(0, totalProducts);
    final isServicesView = _selectedProductType == ProductType.service;
    final titleText = isServicesView ? 'SERVICIOS' : 'PRODUCTOS';
    final noun = isServicesView ? 'servicios' : 'productos';

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
              style: TextStyle(
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
                          _applyFilters();
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

  Widget _buildProductGrid() {
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
              const Text(
                'No se encontraron productos',
                style: TextStyle(
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

    // Calculate pagination
    final totalProducts = _filteredProducts.length;
    final totalPages = (totalProducts / _itemsPerPage).ceil();
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, totalProducts);
    final paginatedProducts = _filteredProducts.sublist(startIndex, endIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive grid settings
        final width = constraints.maxWidth;
        int crossAxisCount;
        double childAspectRatio;
        double spacing;

        if (width < 400) {
          // Mobile small: 2 columns, taller cards
          crossAxisCount = 2;
          childAspectRatio = 0.58;
          spacing = 12;
        } else if (width < 600) {
          // Mobile/tablet: 2 columns
          crossAxisCount = 2;
          childAspectRatio = 0.65;
          spacing = 16;
        } else if (width < 900) {
          // Tablet: 3 columns
          crossAxisCount = 3;
          childAspectRatio = 0.68;
          spacing = 20;
        } else {
          // Desktop: 3-4 columns
          crossAxisCount = 3;
          childAspectRatio = 0.72;
          spacing = 20;
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
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
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

  Widget _buildPaginationControls(int totalPages) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous button
        if (_currentPage > 1)
          TextButton(
            onPressed: () => setState(() => _currentPage--),
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
            onPressed: () => setState(() => _currentPage++),
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
        onTap: () => setState(() => _currentPage = page),
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
    // Prefer optimized image for faster loading, fallback to original
    final displayImageUrl = product.imageUrlOptimized ?? product.imageUrl;
    final hasImage = displayImageUrl != null && displayImageUrl.isNotEmpty;
    final inStock = product.stockQuantity > 0;

    final mediaQuery = MediaQuery.maybeOf(context);
    final reduceMotion = (mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false);

    final hoverActive = _isHovered && !reduceMotion;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.push('/productos/${product.id}'),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          scale: hoverActive ? 1.015 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: hoverActive
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : const [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Image
                Expanded(
                  flex: 4,
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        color: Colors.white,
                        padding: const EdgeInsets.all(16),
                        child: hasImage
                            ? Image.network(
                                displayImageUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Icon(
                                      Icons.pedal_bike_outlined,
                                      size: 48,
                                      color: Colors.grey.shade400,
                                    ),
                                  );
                                },
                              )
                            : Center(
                                child: Icon(
                                  Icons.pedal_bike_outlined,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                      ),
                      // Out of stock badge
                      if (!inStock)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            color: Colors.black87,
                            child: const Text(
                              'AGOTADO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      // Hover overlay
                      if (hoverActive)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              color: Colors.black,
                              child: const Text(
                                'VER PRODUCTO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Product Info
                Expanded(
                  flex: 4,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Brand
                        if (product.brand != null && product.brand!.isNotEmpty)
                          Text(
                            product.brand!.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        const SizedBox(height: 4),
                        // Product name
                        Expanded(
                          child: Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                              height: 1.3,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Price
                        Text(
                          ChileanUtils.formatCurrency(product.price),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        if (inStock)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Stock: ${product.stockQuantity}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
