import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/supplier.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/services/barcode_scanner_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';

import '../../purchases/services/purchase_service.dart';
import '../models/category_models.dart';
import '../models/inventory_models.dart';
import '../services/category_service.dart';
import '../services/inventory_service.dart' as inventory_services;
import '../widgets/product_movements_tab.dart';

enum ProductViewMode { table, cards }

enum StockFilter { all, inStock, lowStock, outOfStock }

class ProductListPage extends StatefulWidget {
  final String? initialCategoryId;
  final String? initialSupplierId;
  final String? refreshToken; // Add refresh parameter

  const ProductListPage({
    super.key,
    this.initialCategoryId,
    this.initialSupplierId,
    this.refreshToken,
  });

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _tableScrollController = ScrollController();

  late inventory_services.InventoryService _inventoryService;
  late CategoryService _categoryService;
  late PurchaseService _purchaseService;

  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  List<Category> _categories = [];
  List<Supplier> _suppliers = [];

  // Detail pane resize
  double _detailPaneWidth = 520.0;

  bool _isLoading = true;
  String _searchTerm = '';

  // 🔍 Smart Filters State
  String? _selectedCategoryId;
  String? _selectedSupplierId;
  ProductType? _selectedProductType;
  StockFilter _stockFilter = StockFilter.all;
  bool _filterWebPublished = false; // is_published = true
  bool _filterGoogleMerchant = false; // is_google_merchant = true
  bool _showInactive = false;

  // 🔽 Sorting State
  ProductSortOption _sortOption = ProductSortOption.nameAsc;

  // 📷 Scanner State
  bool _isScannerEnabled = true;

  ProductViewMode _viewMode = ProductViewMode.table;
  Product? _selectedProduct; // For split-pane detail view
  final Set<String> _expandedSets = {}; // Track which sets are expanded

  // Pagination
  int _currentPage = 1;
  int _itemsPerPage = 100; // Reduced for better performance
  int get _totalPages => (_filteredProducts.length / _itemsPerPage).ceil();
  List<Product> get _paginatedProducts {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex =
        (startIndex + _itemsPerPage).clamp(0, _filteredProducts.length);
    return _filteredProducts.sublist(startIndex, endIndex);
  }

  bool get _hasActiveFilters =>
      _selectedCategoryId != null ||
      _selectedSupplierId != null ||
      _selectedProductType != null ||
      _stockFilter != StockFilter.all ||
      _filterWebPublished ||
      _filterGoogleMerchant ||
      _showInactive ||
      _searchTerm.isNotEmpty;

  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _inventoryService = Provider.of<inventory_services.InventoryService>(
        context,
        listen: false);
    _categoryService = Provider.of<CategoryService>(context, listen: false);
    _purchaseService = Provider.of<PurchaseService>(context, listen: false);

    // Initial load sequence
    _loadData();

    // Listen for unified barcode scans (Physical + Mobile via Bridge)
    _scanSubscription =
        context.read<BarcodeScannerService>().barcodeStream.listen((barcode) {
      if (mounted && _isScannerEnabled) {
        _handleBarcodeScan(barcode);
      }
    });

    // Check for initial filters from widget arguments
    if (widget.initialCategoryId != null) {
      _selectedCategoryId = widget.initialCategoryId;
    }
    if (widget.initialSupplierId != null) {
      _selectedSupplierId = widget.initialSupplierId;
    }
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadCategories(),
      _loadSuppliers(),
      _loadProducts(),
    ]);
  }

  // 🔽 Selection State
  final Set<String> _selectedProductIds = {};
  bool get _isMultiSelectMode => _selectedProductIds.isNotEmpty;

  @override
  void didUpdateWidget(ProductListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload products when refresh token changes (from import page)
    if (widget.refreshToken != null &&
        widget.refreshToken != oldWidget.refreshToken) {
      _loadProducts();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableScrollController.dispose();
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    // Only handle scans if scanner is enabled and page is visible
    if (!_isScannerEnabled || !mounted || !ModalRoute.of(context)!.isCurrent)
      return;

    // Search for product by SKU
    final product = _products.cast<Product?>().firstWhere(
          (p) => p!.sku.toLowerCase() == barcode.toLowerCase(),
          orElse: () => null,
        );

    if (product != null) {
      // Navigate to product edit page
      if (mounted) {
        final result =
            await context.push('/inventory/products/${product.id}/edit');
        if (result == true) {
          _loadProducts(forceRefresh: true);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Producto encontrado: ${product.name}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Producto no encontrado: $barcode'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _categoryService.getCategories(activeOnly: true);
      if (mounted) {
        setState(() {
          _categories = categories;
        });
      }
    } catch (_) {
      // Ignored: categories are optional for listing products.
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await _purchaseService.getSuppliers(activeOnly: true);
      if (mounted) {
        setState(() {
          _suppliers = suppliers;
        });
      }
    } catch (_) {
      // Ignored: suppliers are optional for listing products.
    }
  }

  Future<void> _loadProducts({bool forceRefresh = false}) async {
    if (!mounted) return;

    // 🚀 INSTANT RENDER: Show cached data immediately if available
    if (_inventoryService.hasProductsCache &&
        _products.isEmpty &&
        !forceRefresh) {
      setState(() {
        _products = _inventoryService.cachedProducts;
        _applyFilters();
        _isLoading = false;
      });
    } else if (_products.isEmpty) {
      // Only show loading spinner if we have no products
      setState(() => _isLoading = true);
    }

    try {
      final products = await _inventoryService.getProducts(
        categoryId: _selectedCategoryId,
        // We now filter low stock client-side to allow complex combinations
        // lowStockOnly: _filterLowStock,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;

      // Update data
      setState(() {
        _products = products;
        _applyFilters();
        _isLoading = false;
      });

      _syncSharedInventorySilently();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando productos: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _syncSharedInventorySilently() {
    if (!mounted) return;
    try {
      final sharedInventory = context.read<shared_inventory.InventoryService>();
      unawaited(sharedInventory.getProducts(forceRefresh: true));
    } catch (_) {
      // Shared inventory may not be available in some test contexts.
    }
  }

  /// Token-based search: splits query into words and matches if ALL tokens found
  bool _matchesTokenSearch(String query, Product product) {
    if (query.isEmpty) return true;
    final tokens = query.toLowerCase().split(RegExp(r'\s+'));
    final searchableText = [
      product.name.toLowerCase(),
      product.sku.toLowerCase(),
      product.supplierCode?.toLowerCase() ?? '',
      product.brand?.toLowerCase() ?? '',
      product.model?.toLowerCase() ?? '',
      _resolveCategoryName(product)?.toLowerCase() ?? '',
    ].join(' ');
    // ALL tokens must be found in searchable text
    return tokens.every((token) => searchableText.contains(token));
  }

  void _applyFilters() {
    List<Product> filtered = List<Product>.from(_products);

    // 1. Hide set components from main list
    filtered = filtered.where((product) => !product.isSetComponent).toList();

    // 2. Category Filter
    if (_selectedCategoryId != null && _selectedCategoryId!.isNotEmpty) {
      filtered = filtered
          .where((product) => product.categoryId == _selectedCategoryId)
          .toList();
    }

    // 3. Supplier Filter
    if (_selectedSupplierId != null && _selectedSupplierId!.isNotEmpty) {
      filtered = filtered
          .where((product) => product.supplierId == _selectedSupplierId)
          .toList();
    }

    // 3.5 Product Type Filter
    if (_selectedProductType != null) {
      filtered = filtered
          .where((product) => product.productType == _selectedProductType)
          .toList();
    }

    // 4. Stock Filters
    switch (_stockFilter) {
      case StockFilter.all:
        // No filtration
        break;
      case StockFilter.inStock:
        // Show only products with positive stock
        filtered = filtered
            .where((product) => !product.isService && product.inventoryQty > 0)
            .toList();
        break;
      case StockFilter.lowStock:
        // Show low stock (includes out of stock usually, or strictly low?)
        // User said "Bajo stock", "Sin stock", "Con stock".
        // Low stock usually implies it needs attention.
        filtered = filtered
            .where((product) => !product.isService && product.isLowStock)
            .toList();
        break;
      case StockFilter.outOfStock:
        filtered = filtered
            .where((product) => !product.isService && product.isOutOfStock)
            .toList();
        break;
    }

    if (_filterWebPublished) {
      filtered = filtered.where((product) => product.isPublished).toList();
    }

    if (_filterGoogleMerchant) {
      filtered = filtered.where((product) => product.isGoogleMerchant).toList();
    }

    if (!_showInactive) {
      filtered = filtered.where((product) => product.isActive).toList();
    }

    // 5. Search
    if (_searchTerm.isNotEmpty) {
      filtered = filtered.where((product) {
        return _matchesTokenSearch(_searchTerm, product);
      }).toList();
    }

    // 6. Sorting
    switch (_sortOption) {
      case ProductSortOption.createdAtDesc:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case ProductSortOption.createdAtAsc:
        filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case ProductSortOption.nameAsc:
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case ProductSortOption.nameDesc:
        filtered.sort((a, b) => b.name.compareTo(a.name));
        break;
      case ProductSortOption.skuAsc:
        filtered.sort((a, b) => a.sku.compareTo(b.sku));
        break;
      case ProductSortOption.skuDesc:
        filtered.sort((a, b) => b.sku.compareTo(a.sku));
        break;
      case ProductSortOption.priceDesc:
        filtered.sort((a, b) => b.price.compareTo(a.price));
        break;
      case ProductSortOption.priceAsc:
        filtered.sort((a, b) => a.price.compareTo(b.price));
        break;
      case ProductSortOption.stockDesc:
        filtered.sort((a, b) => b.inventoryQty.compareTo(a.inventoryQty));
        break;
      case ProductSortOption.stockAsc:
        filtered.sort((a, b) => a.inventoryQty.compareTo(b.inventoryQty));
        break;
    }

    _filteredProducts = filtered;
    _currentPage = 1;
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchTerm = value.trim();
      _applyFilters();
    });
  }

  // ---------------------------------------------------------------------------
  // UI BUILDERS (Minimalistic Redesign)
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MainLayout(
      child: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: BrandedLoading());
    }

    return Column(
      children: [
        // 1. Sleek Header Area (Title + Primary Actions)
        _buildHeaderArea(theme),

        // 1.5 Bulk Actions Bar (Overlays standard header/filters when active)
        if (_isMultiSelectMode) _buildBulkActionsBar(theme),

        // 2. Smart Filter Bar (Separated, minimal)
        if (!_isMultiSelectMode) _buildSmartFilterBar(theme),

        // 3. Main Content
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobileWidth = constraints.maxWidth < 800;
              if (_filteredProducts.isEmpty) {
                return _buildEmptyState(theme);
              }
              // Mobile: support cards and list view, Desktop: support cards and table
              if (isMobileWidth) {
                return _viewMode == ProductViewMode.cards
                    ? _buildCardGridView(theme)
                    : _buildMobileListView(theme);
              }
              return _viewMode == ProductViewMode.cards
                  ? _buildCardGridView(theme)
                  : _buildTableViewWithScrollableHeader(theme);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderArea(ThemeData theme) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    if (isMobile) {
      return _buildMobileHeader(theme);
    }

    return _buildDesktopHeader(theme);
  }

  Widget _buildMobileHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          // Title
          Text(
            'Productos',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          // Count Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_filteredProducts.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const Spacer(),

          // Scanner Toggle Icon
          IconButton(
            icon: Icon(
              _isScannerEnabled
                  ? Icons.qr_code_scanner
                  : Icons.qr_code_2_outlined,
              color: _isScannerEnabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: _isScannerEnabled ? 'Escáner activo' : 'Escáner inactivo',
            onPressed: () {
              setState(() => _isScannerEnabled = !_isScannerEnabled);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isScannerEnabled
                      ? 'Escáner habilitado'
                      : 'Escáner deshabilitado'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),

          // View Toggle (Cards/List)
          IconButton(
            icon: Icon(
              _viewMode == ProductViewMode.cards
                  ? Icons.grid_view_rounded
                  : Icons.view_list_rounded,
            ),
            tooltip: _viewMode == ProductViewMode.cards
                ? 'Vista lista'
                : 'Vista tarjetas',
            onPressed: () {
              setState(() {
                _viewMode = _viewMode == ProductViewMode.cards
                    ? ProductViewMode.table // table mode = list view on mobile
                    : ProductViewMode.cards;
              });
            },
          ),

          // Sort & More Options Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Más opciones',
            onSelected: (value) async {
              if (value == 'import') {
                final result = await context.push('/inventory/products/import');
                if (result == true) _loadProducts(forceRefresh: true);
              } else if (value == 'new') {
                final result = await context.push('/inventory/products/new');
                if (result == true) _loadProducts(forceRefresh: true);
              } else if (value.startsWith('sort_')) {
                final sortKey = value.replaceFirst('sort_', '');
                setState(() {
                  _sortOption = ProductSortOption.values.firstWhere(
                    (e) => e.name == sortKey,
                    orElse: () => ProductSortOption.nameAsc,
                  );
                  _applyFilters();
                });
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new',
                child: Row(
                  children: [
                    Icon(Icons.add),
                    SizedBox(width: 12),
                    Text('Nuevo Producto'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.upload_file_outlined),
                    SizedBox(width: 12),
                    Text('Importar'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              // Sort Options
              PopupMenuItem(
                enabled: false,
                child: Text('Ordenar por',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary)),
              ),
              PopupMenuItem(
                value: 'sort_nameAsc',
                child: Row(
                  children: [
                    Icon(
                        _sortOption == ProductSortOption.nameAsc
                            ? Icons.check
                            : Icons.sort_by_alpha,
                        size: 18,
                        color: _sortOption == ProductSortOption.nameAsc
                            ? theme.colorScheme.primary
                            : null),
                    const SizedBox(width: 12),
                    const Text('Nombre A-Z'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sort_nameDesc',
                child: Row(
                  children: [
                    Icon(
                        _sortOption == ProductSortOption.nameDesc
                            ? Icons.check
                            : Icons.sort_by_alpha,
                        size: 18,
                        color: _sortOption == ProductSortOption.nameDesc
                            ? theme.colorScheme.primary
                            : null),
                    const SizedBox(width: 12),
                    const Text('Nombre Z-A'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sort_priceDesc',
                child: Row(
                  children: [
                    Icon(
                        _sortOption == ProductSortOption.priceDesc
                            ? Icons.check
                            : Icons.attach_money,
                        size: 18,
                        color: _sortOption == ProductSortOption.priceDesc
                            ? theme.colorScheme.primary
                            : null),
                    const SizedBox(width: 12),
                    const Text('Precio Mayor'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sort_priceAsc',
                child: Row(
                  children: [
                    Icon(
                        _sortOption == ProductSortOption.priceAsc
                            ? Icons.check
                            : Icons.attach_money,
                        size: 18,
                        color: _sortOption == ProductSortOption.priceAsc
                            ? theme.colorScheme.primary
                            : null),
                    const SizedBox(width: 12),
                    const Text('Precio Menor'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sort_stockDesc',
                child: Row(
                  children: [
                    Icon(
                        _sortOption == ProductSortOption.stockDesc
                            ? Icons.check
                            : Icons.inventory_2,
                        size: 18,
                        color: _sortOption == ProductSortOption.stockDesc
                            ? theme.colorScheme.primary
                            : null),
                    const SizedBox(width: 12),
                    const Text('Stock Mayor'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sort_createdAtDesc',
                child: Row(
                  children: [
                    Icon(
                        _sortOption == ProductSortOption.createdAtDesc
                            ? Icons.check
                            : Icons.schedule,
                        size: 18,
                        color: _sortOption == ProductSortOption.createdAtDesc
                            ? theme.colorScheme.primary
                            : null),
                    const SizedBox(width: 12),
                    const Text('Más Recientes'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          // Title
          Text(
            'Productos',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: 12),
          // Product Count Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_filteredProducts.length}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const Spacer(),

          // Scanner Toggle (Minimal Switch)
          Row(
            children: [
              Icon(
                _isScannerEnabled
                    ? Icons.qr_code_scanner
                    : Icons.qr_code_2_outlined,
                size: 18,
                color: _isScannerEnabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Switch(
                value: _isScannerEnabled,
                onChanged: (val) {
                  setState(() => _isScannerEnabled = val);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          val ? 'Escáner habilitado' : 'Escáner deshabilitado'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      width: 200,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(width: 16),

          // Vertical Divider
          Container(
            height: 24,
            width: 1,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(width: 16),

          // Import Button
          AppButton(
            text: 'Importar',
            icon: Icons.upload_file_outlined,
            type: ButtonType.outline,
            onPressed: () async {
              final result = await context.push('/inventory/products/import');
              if (result == true) _loadProducts(forceRefresh: true);
            },
          ),
          const SizedBox(width: 8),

          // New Product Button
          AppButton(
            text: 'Nuevo',
            icon: Icons.add,
            onPressed: () async {
              final result = await context.push('/inventory/products/new');
              if (result == true) _loadProducts(forceRefresh: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSmartFilterBar(ThemeData theme) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Buscar productos...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _hasActiveFilters
                        ? IconButton(
                            icon: Icon(Icons.filter_list_off,
                                color: theme.colorScheme.error),
                            onPressed: _resetFilters,
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    filled: true,
                    fillColor:
                        theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _showMobileFilters(theme),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _hasActiveFilters
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _hasActiveFilters
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Icon(Icons.tune,
                    size: 20,
                    color: _hasActiveFilters
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Search Input (Expanded)
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre, SKU...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: theme.colorScheme.outlineVariant),
                      ),
                      filled: true,
                      fillColor:
                          theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Sort Dropdown (Compact) - Kept for Date sorting
              _buildCompactSortDropdown(theme),
              const SizedBox(width: 8),

              // View Toggle
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ToggleButtons(
                  isSelected: [
                    _viewMode == ProductViewMode.table,
                    _viewMode == ProductViewMode.cards
                  ],
                  onPressed: (index) {
                    setState(() => _viewMode = index == 0
                        ? ProductViewMode.table
                        : ProductViewMode.cards);
                  },
                  borderRadius: BorderRadius.circular(8),
                  constraints:
                      const BoxConstraints(minHeight: 38, minWidth: 38),
                  color: theme.colorScheme.onSurfaceVariant,
                  selectedColor: theme.colorScheme.primary,
                  fillColor:
                      theme.colorScheme.primaryContainer.withOpacity(0.2),
                  children: const [
                    Icon(Icons.table_rows_outlined, size: 18),
                    Icon(Icons.grid_view_outlined, size: 18),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Secondary Filter Row (Dropdowns)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Category Filter
                _buildSearchableMenu<Category>(
                  theme: theme,
                  hint: 'Categoría',
                  value: _categories.cast<Category?>().firstWhere(
                        (c) => c!.id == _selectedCategoryId,
                        orElse: () => null,
                      ),
                  items: _categories,
                  labelBuilder: (c) => c.name,
                  onChanged: (val) {
                    setState(() {
                      _selectedCategoryId = val?.id;
                      _applyFilters();
                    });
                  },
                ),
                const SizedBox(width: 8),

                // Supplier Filter
                _buildSearchableMenu<Supplier>(
                  theme: theme,
                  hint: 'Proveedor',
                  value: _suppliers.cast<Supplier?>().firstWhere(
                        (s) => s!.id == _selectedSupplierId,
                        orElse: () => null,
                      ),
                  items: _suppliers,
                  labelBuilder: (s) => s.name,
                  onChanged: (val) {
                    setState(() {
                      _selectedSupplierId = val?.id;
                      _applyFilters();
                    });
                  },
                ),

                const SizedBox(width: 8),

                // Product Type Filter
                _buildProductTypeFilterDropdown(theme),

                const SizedBox(width: 8),

                // Stock Filter Dropdown
                _buildStockFilterDropdown(theme),

                const SizedBox(width: 8),

                // Channels (Internet) Dropdown
                _buildChannelsFilterDropdown(theme),

                const SizedBox(width: 8),

                // Status Filter Dropdown
                _buildStatusFilterDropdown(theme),

                if (_hasActiveFilters) ...[
                  const VerticalDivider(width: 24),
                  _clearFilters(theme),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSortDropdown(ThemeData theme) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ProductSortOption>(
          value: _sortOption,
          isDense: true,
          icon: const Icon(Icons.sort, size: 18),
          selectedItemBuilder: (context) {
            return ProductSortOption.values.map((e) {
              return Center(
                  child: Text(e.label, style: theme.textTheme.bodySmall));
            }).toList();
          },
          items: ProductSortOption.values
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e.label, style: theme.textTheme.bodyMedium),
                  ))
              .toList(),
          onChanged: (val) {
            if (val != null)
              setState(() {
                _sortOption = val;
                _applyFilters();
              });
          },
        ),
      ),
    );
  }

  Widget _buildStockFilterDropdown(ThemeData theme) {
    String label = 'Inventario';
    IconData icon = Icons.inventory_2_outlined;
    Color? color;

    switch (_stockFilter) {
      case StockFilter.all:
        label = 'Inventario';
        break;
      case StockFilter.inStock:
        label = 'Con Stock';
        icon = Icons.check_circle_outline;
        color = Colors.green;
        break;
      case StockFilter.lowStock:
        label = 'Bajo Stock';
        icon = Icons.warning_amber_rounded;
        color = Colors.orange;
        break;
      case StockFilter.outOfStock:
        label = 'Sin Stock';
        icon = Icons.cancel_outlined;
        color = Colors.red;
        break;
    }

    final isSelected = _stockFilter != StockFilter.all;

    return PopupMenuButton<StockFilter>(
      tooltip: 'Filtrar por inventario',
      initialValue: _stockFilter,
      onSelected: (StockFilter item) {
        setState(() {
          _stockFilter = item;
          _applyFilters();
        });
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<StockFilter>>[
        const PopupMenuItem<StockFilter>(
          value: StockFilter.all,
          child: Text('Todos'),
        ),
        const PopupMenuItem<StockFilter>(
          value: StockFilter.inStock,
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
              SizedBox(width: 8),
              Text('Con Stock (>0)'),
            ],
          ),
        ),
        const PopupMenuItem<StockFilter>(
          value: StockFilter.lowStock,
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Text('Bajo Stock'),
            ],
          ),
        ),
        const PopupMenuItem<StockFilter>(
          value: StockFilter.outOfStock,
          child: Row(
            children: [
              Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
              SizedBox(width: 8),
              Text('Sin Stock (0)'),
            ],
          ),
        ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (color ?? theme.colorScheme.primary).withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? (color ?? theme.colorScheme.primary)
                : theme.colorScheme.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: isSelected
                    ? (color ?? theme.colorScheme.primary)
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isSelected
                    ? (color ?? theme.colorScheme.primary)
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelsFilterDropdown(ThemeData theme) {
    final isSelected = _filterWebPublished || _filterGoogleMerchant;

    return PopupMenuButton<String>(
      tooltip: 'Canales de venta',
      onSelected: (String value) {
        setState(() {
          if (value == 'web') _filterWebPublished = !_filterWebPublished;
          if (value == 'google') _filterGoogleMerchant = !_filterGoogleMerchant;
          _applyFilters();
        });
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        CheckedPopupMenuItem<String>(
          value: 'web',
          checked: _filterWebPublished,
          child: const Text('Publicado en Web'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'google',
          checked: _filterGoogleMerchant,
          child: const Text('Google Merchant'),
        ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public,
                size: 16,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              'Canales',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusFilterDropdown(ThemeData theme) {
    final isInactiveSelected = _showInactive;

    return PopupMenuButton<bool>(
      tooltip: 'Estado del producto',
      initialValue: _showInactive,
      onSelected: (bool value) {
        setState(() {
          _showInactive = value;
          _applyFilters();
        });
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<bool>>[
        const PopupMenuItem<bool>(
          value: false,
          child: Text('Solo Activos'),
        ),
        const PopupMenuItem<bool>(
          value: true,
          child: Text('Mostrar Inactivos'),
        ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isInactiveSelected
              ? theme.colorScheme.error.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isInactiveSelected
                ? theme.colorScheme.error
                : theme.colorScheme.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                isInactiveSelected
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 16,
                color: isInactiveSelected
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              isInactiveSelected ? 'Inactivos' : 'Activos',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isInactiveSelected
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactDropdown<T>({
    required ThemeData theme,
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: theme.textTheme.bodySmall),
          icon: Icon(Icons.arrow_drop_down,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          style: theme.textTheme.bodySmall,
          selectedItemBuilder: (context) {
            return [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(hint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              ...items.map((item) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(labelBuilder(item),
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  )),
            ];
          },
          items: [
            DropdownMenuItem<T>(
              value: null,
              child: Text('Todos',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary)),
            ),
            ...items.map((item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(labelBuilder(item),
                      style: theme.textTheme.bodySmall),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildProductTypeFilterDropdown(ThemeData theme) {
    return _buildCompactDropdown<ProductType>(
      theme: theme,
      hint: 'Tipo',
      value: _selectedProductType,
      items: ProductType.values,
      labelBuilder: (type) => type.displayName,
      onChanged: (val) {
        setState(() {
          _selectedProductType = val;
          _applyFilters();
        });
      },
    );
  }

  Widget _buildSearchableMenu<T>({
    required ThemeData theme,
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: DropdownMenu<T?>(
        width: 200,
        initialSelection: value,
        hintText: hint,
        textStyle: theme.textTheme.bodySmall,
        menuHeight: 300,
        enableFilter: true,
        requestFocusOnTap: true,
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: InputBorder.none,
          constraints: const BoxConstraints(maxHeight: 36),
          hintStyle: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        trailingIcon: Icon(Icons.arrow_drop_down,
            size: 18, color: theme.colorScheme.onSurfaceVariant),
        selectedTrailingIcon: Icon(Icons.arrow_drop_up,
            size: 18, color: theme.colorScheme.onSurfaceVariant),
        dropdownMenuEntries: [
          DropdownMenuEntry<T?>(
            value: null,
            label: 'Todos',
            style: ButtonStyle(
              textStyle: MaterialStateProperty.all(theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary)),
            ),
          ),
          ...items.map((item) => DropdownMenuEntry<T?>(
                value: item,
                label: labelBuilder(item),
                style: ButtonStyle(
                  textStyle:
                      MaterialStateProperty.all(theme.textTheme.bodySmall),
                ),
              )),
        ],
        onSelected: onChanged,
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      _selectedCategoryId = null;
      _selectedSupplierId = null;
      _selectedProductType = null;
      _stockFilter = StockFilter.all;
      _filterWebPublished = false;
      _filterGoogleMerchant = false;
      _showInactive = false;
      _searchTerm = '';
      _searchController.clear();
      _applyFilters();
    });
  }

  Widget _clearFilters(ThemeData theme) {
    return TextButton.icon(
      onPressed: _resetFilters,
      icon: const Icon(Icons.close, size: 14),
      label: const Text('Limpiar'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
        foregroundColor: theme.colorScheme.error,
        textStyle: theme.textTheme.labelSmall,
      ),
    );
  }

  Widget _buildTableViewWithScrollableHeader(ThemeData theme) {
    return LayoutBuilder(builder: (context, constraints) {
      // Default to 400 or 1/3 if width not set yet
      // This ensures we always have a valid width
      if (_detailPaneWidth == 400 && constraints.maxWidth > 1200) {
        // _detailPaneWidth = constraints.maxWidth * 0.3;
      }

      return Row(
        children: [
          // Main area with fixed header and table header
          Expanded(
            child: Column(
              children: [
                // Fixed table header
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: theme.colorScheme.outlineVariant)),
                    color: theme.colorScheme.surface,
                  ),
                  child: _buildTableHeader(theme),
                ),

                // Scrollable table rows
                Expanded(
                  child: ListView.builder(
                    controller: _tableScrollController,
                    itemCount: _paginatedProducts.length,
                    itemBuilder: (context, index) {
                      final product = _paginatedProducts[index];
                      return _buildZohoTableRow(product, theme);
                    },
                  ),
                ),
                // Pagination controls
                _buildPaginationControls(theme),
              ],
            ),
          ),
          // Split-pane detail view
          if (_selectedProduct != null)
            SizedBox(
              width: _detailPaneWidth,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildDetailPane(theme),
                  // Resize Handle Overlay
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 10,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            _detailPaneWidth -= details.delta.dx;
                            // Clamp width between reasonable limits
                            if (_detailPaneWidth < 300) _detailPaneWidth = 300;
                            if (_detailPaneWidth > constraints.maxWidth * 0.6)
                              _detailPaneWidth = constraints.maxWidth * 0.6;
                          });
                        },
                        child: Container(
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  /// Mobile-optimized compact list view with proper rows
  Widget _buildMobileListView(ThemeData theme) {
    return ListView.builder(
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        return _buildMobileProductRow(product, theme);
      },
    );
  }

  Widget _buildMobileProductRow(Product product, ThemeData theme) {
    final stockQty = product.inventoryQty;
    final isLowStock = stockQty > 0 && stockQty <= product.minStockLevel;
    final isOutOfStock = stockQty <= 0;

    return InkWell(
      onTap: () => _handleProductAction('edit', product),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
          ),
        ),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(6),
              ),
              clipBehavior: Clip.antiAlias,
              child: product.imageUrl != null
                  ? Image.network(
                      product.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.image_not_supported,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Icon(
                      Icons.inventory_2_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            ),
            const SizedBox(width: 12),

            // Name & SKU
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.sku.isNotEmpty)
                    Text(
                      product.sku,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                    ),
                ],
              ),
            ),

            // Stock indicator
            Container(
              width: 32,
              alignment: Alignment.center,
              child: Text(
                '$stockQty',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isOutOfStock
                      ? theme.colorScheme.error
                      : isLowStock
                          ? Colors.orange
                          : theme.colorScheme.primary,
                ),
              ),
            ),

            // Price
            SizedBox(
              width: 70,
              child: Text(
                ChileanUtils.formatCurrency(product.price),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.right,
              ),
            ),

            // More actions
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              padding: EdgeInsets.zero,
              onSelected: (action) => _handleProductAction(action, product),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                const PopupMenuItem(
                    value: 'duplicate', child: Text('Duplicar')),
                const PopupMenuItem(
                    value: 'adjust_stock', child: Text('Ajustar Stock')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardGridView(ThemeData theme) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        return _buildProductCard(_filteredProducts[index], theme);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TABLE ROW & HEADER (Keep existing logic, updated style)
  // ---------------------------------------------------------------------------

  Widget _buildTableHeader(ThemeData theme) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Select All Checkbox
          SizedBox(
            width: 40,
            child: Checkbox(
              value: _filteredProducts.isNotEmpty &&
                  _selectedProductIds.length == _filteredProducts.length,
              tristate: true,
              onChanged: (bool? value) {
                setState(() {
                  if (value == true) {
                    _selectedProductIds.addAll(_filteredProducts
                        .where((p) => p.id != null)
                        .map((p) => p.id!));
                  } else {
                    _selectedProductIds.clear();
                  }
                });
              },
            ),
          ),
          _buildHeaderCell(
            theme,
            'Producto',
            flex: 4,
            sortOptionAsc: ProductSortOption.nameAsc,
            sortOptionDesc: ProductSortOption.nameDesc,
          ),
          _buildHeaderCell(
            theme,
            'SKU',
            flex: 2,
            sortOptionAsc: ProductSortOption.skuAsc,
            sortOptionDesc: ProductSortOption.skuDesc,
          ),
          _buildHeaderCell(theme, 'Categoría',
              flex: 2), // Category sort not yet explicitly defined in Enum
          _buildHeaderCell(
            theme,
            'Stock',
            flex: 1,
            align: TextAlign.center,
            sortOptionAsc: ProductSortOption.stockAsc,
            sortOptionDesc: ProductSortOption.stockDesc,
          ),
          _buildHeaderCell(
            theme,
            'Precio',
            flex: 1,
            align: TextAlign.right,
            sortOptionAsc: ProductSortOption.priceAsc,
            sortOptionDesc: ProductSortOption.priceDesc,
          ),
          const SizedBox(width: 48), // Actions column space
        ],
      ),
    );
  }

  Widget _buildHeaderCell(ThemeData theme, String text,
      {int flex = 1,
      TextAlign align = TextAlign.left,
      ProductSortOption? sortOptionAsc,
      ProductSortOption? sortOptionDesc}) {
    final isSorted = (sortOptionAsc != null && _sortOption == sortOptionAsc) ||
        (sortOptionDesc != null && _sortOption == sortOptionDesc);
    final isAsc = sortOptionAsc != null && _sortOption == sortOptionAsc;

    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: (sortOptionAsc == null || sortOptionDesc == null)
            ? null
            : () {
                setState(() {
                  if (_sortOption == sortOptionAsc) {
                    _sortOption = sortOptionDesc;
                  } else {
                    _sortOption = sortOptionAsc;
                  }
                  _applyFilters();
                });
              },
        child: Container(
          alignment: align == TextAlign.right
              ? Alignment.centerRight
              : align == TextAlign.center
                  ? Alignment.center
                  : Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: align,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isSorted
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isSorted) ...[
                const SizedBox(width: 4),
                Icon(
                  isAsc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Re-implementing _buildZohoTableRow as it was likely cut off or needed updates
  Widget _buildZohoTableRow(Product product, ThemeData theme) {
    final isSelected = _selectedProduct?.id == product.id;
    final rowColor =
        isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.1) : null;

    final isProductSet = product.isSet; // Using direct property
    final isExpanded =
        product.id != null && _expandedSets.contains(product.id!);

    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _selectedProduct = isSelected ? null : product;
              if (isProductSet && product.id != null) {
                if (_expandedSets.contains(product.id!)) {
                  _expandedSets.remove(product.id!);
                } else {
                  _expandedSets.add(product.id!);
                }
              }
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: rowColor,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.2),
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Selection Checkbox
                SizedBox(
                  width: 40,
                  child: Checkbox(
                    value: product.id != null &&
                        _selectedProductIds.contains(product.id!),
                    onChanged: (bool? value) {
                      if (product.id == null) return;
                      setState(() {
                        if (value == true) {
                          _selectedProductIds.add(product.id!);
                        } else {
                          _selectedProductIds.remove(product.id!);
                        }
                      });
                    },
                  ),
                ),
                // Product Name & Image
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      if (isProductSet)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_down
                                  : Icons.keyboard_arrow_right,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(4),
                          image: product.imageUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(product.imageUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: product.imageUrl == null
                            ? Icon(Icons.image_not_supported_outlined,
                                size: 20,
                                color: theme.colorScheme.onSurfaceVariant)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (isProductSet)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color:
                                          theme.colorScheme.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text('SET',
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                Expanded(
                                  child: Text(
                                    product.name,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if (product.brand != null)
                              Text(
                                product.brand!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // SKU
                Expanded(
                  flex: 2,
                  child: SelectableText(
                    // Make SKU copyable
                    product.sku,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                // Category
                Expanded(
                  flex: 2,
                  child: Text(
                    _resolveCategoryName(product) ?? '-',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Stock
                Expanded(
                  flex: 1,
                  child: _buildStockBadge(theme, product),
                ),
                // Price
                Expanded(
                  flex: 1,
                  child: Text(
                    ChileanUtils.formatCurrency(product.price),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Actions
                SizedBox(
                  width: 48,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    padding: EdgeInsets.zero,
                    onSelected: (value) => _handleProductAction(value, product),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Editar'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline,
                                size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Eliminar',
                                style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Expanded component rows for sets
        if (isProductSet && isExpanded)
          _buildSetComponentsPanel(product, theme),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // BULK ACTIONS BAR
  // ---------------------------------------------------------------------------

  Widget _buildBulkActionsBar(ThemeData theme) {
    return Container(
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 12),
          Text(
            '${_selectedProductIds.length} seleccionados',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              // Placeholder for bulk update
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Edición masiva: Próximamente')),
              );
            },
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('Editar'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () {
              // Placeholder for bulk delete
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Eliminación masiva: Próximamente')),
              );
            },
            icon: const Icon(Icons.delete, size: 18),
            label: const Text('Eliminar'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
          ),
          const VerticalDivider(indent: 12, endIndent: 12),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancelar selección',
            onPressed: () => setState(() => _selectedProductIds.clear()),
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS & COMPONENTS
  // ---------------------------------------------------------------------------

  /// Build the expandable panel showing set components
  Widget _buildSetComponentsPanel(Product product, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(108, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Componentes del Set',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            _buildComponentsList(product, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildComponentsList(Product product, ThemeData theme) {
    final components = _products
        .where((p) => p.parentSetId == product.id)
        .toList()
      ..sort((a, b) =>
          (a.componentPosition ?? 0).compareTo(b.componentPosition ?? 0));

    if (components.isEmpty) {
      return Text(
        '💡 No hay componentes creados aún. Guarda el set para crearlos.',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      children: components.map((comp) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildComponentRow(comp, theme),
        );
      }).toList(),
    );
  }

  Widget _buildComponentRow(Product component, ThemeData theme) {
    final hasStock = component.inventoryQty > 0;

    return InkWell(
      onTap: () => _openEditor(component),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ImageService.buildProductImage(
                imageUrl: component.imageUrl,
                size: 36,
                isListThumbnail: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    component.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    component.sku,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: hasStock
                    ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                    : theme.colorScheme.errorContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Stock: ${component.inventoryQty}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: hasStock
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _resolveCategoryName(Product product) {
    if (product.categoryName != null && product.categoryName!.isNotEmpty) {
      return product.categoryName;
    }
    if (product.categoryId != null) {
      final cat = _categories
          .cast<Category?>()
          .firstWhere((c) => c!.id == product.categoryId, orElse: () => null);
      if (cat != null) return cat.name;
    }
    return null;
  }

  Widget _buildStockBadge(ThemeData theme, Product product) {
    if (product.isService) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withOpacity(0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'SERV',
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
          ),
        ),
      );
    }

    // NEW: Partial Set Indicator (Set = 0 but has components)
    // We calculate isPartial locally since DB column might be missing
    final bool isPartialSet = product.isSet &&
        product.inventoryQty == 0 &&
        _products.any((p) =>
            p.parentSetId == product.id &&
            p.inventoryQty > 0); // Check if ANY component has stock

    if (isPartialSet) {
      return Center(
        child: Tooltip(
          message: 'Set incompleto: faltan componentes',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 14, color: Colors.deepOrange),
                const SizedBox(width: 4),
                Text(
                  '0', // Still 0 stock
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.deepOrange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Color color = theme.colorScheme.primary;
    if (product.isOutOfStock)
      color = theme.colorScheme.error;
    else if (product.isLowStock) color = Colors.orange;

    return Center(
      child: Text(
        '${product.inventoryQty}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _handleProductAction(String action, Product product) async {
    if (action == 'edit') {
      _openEditor(product);
    } else if (action == 'delete') {
      _confirmDelete(product);
    }
  }

  Future<void> _openEditor(Product product) async {
    final result = await context.push('/inventory/products/${product.id}/edit');
    if (result == true) _loadProducts(forceRefresh: true);
  }

  Future<void> _confirmDelete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Estás seguro de eliminar "${product.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isLoading = true);
      try {
        await _inventoryService.deleteProduct(product.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Producto eliminado')),
          );
          _loadProducts(forceRefresh: true);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            _searchTerm.isNotEmpty || _hasActiveFilters
                ? 'No se encontraron productos'
                : 'No hay productos registrados',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_searchTerm.isNotEmpty || _hasActiveFilters)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.clear_all),
                label: const Text('Limpiar filtros'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPaginationControls(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_paginatedProducts.length} de ${_filteredProducts.length} resultados',
            style: theme.textTheme.bodySmall,
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1
                    ? () => setState(() => _currentPage--)
                    : null,
              ),
              Text(
                '$_currentPage / ${_totalPages == 0 ? 1 : _totalPages}',
                style: theme.textTheme.bodyMedium,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < _totalPages
                    ? () => setState(() => _currentPage++)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product, ThemeData theme) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _handleProductAction('edit', product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                color: theme.colorScheme.surfaceVariant,
                width: double.infinity,
                child: product.imageUrl != null
                    ? Image.network(product.imageUrl!, fit: BoxFit.cover)
                    : Icon(Icons.image_not_supported,
                        size: 48, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(ChileanUtils.formatCurrency(product.price),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      _buildStockBadge(theme, product),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPane(ThemeData theme) {
    if (_selectedProduct == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        border:
            Border(left: BorderSide(color: theme.colorScheme.outlineVariant)),
        color: theme.colorScheme.surface,
      ),
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Tabs and Close Button
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      labelColor: theme.colorScheme.primary,
                      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                      indicatorColor: theme.colorScheme.primary,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelStyle: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      tabs: const [
                        Tab(text: 'Detalles'),
                        Tab(text: 'Movimientos'),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cerrar panel',
                    onPressed: () => setState(() => _selectedProduct = null),
                  ),
                ],
              ),
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                children: [
                  // Tab 1: Details (Existing Content)
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selectedProduct!.imageUrl != null)
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                color: Colors.white,
                                child: Image.network(
                                    _selectedProduct!.imageUrl!,
                                    fit: BoxFit.contain),
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),

                        // Header Info
                        Text(_selectedProduct!.name,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: _selectedProduct!.sku));
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('SKU copiado')));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'SKU: ${_selectedProduct!.sku}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        _buildDetailSection(theme, title: 'Precios', children: [
                          _buildDetailRow(
                              theme,
                              'Precio Venta',
                              ChileanUtils.formatCurrency(
                                  _selectedProduct!.price),
                              isHighlight: true),
                          _buildDetailRow(
                              theme,
                              'Costo',
                              ChileanUtils.formatCurrency(
                                  _selectedProduct!.cost)),
                        ]),

                        const SizedBox(height: 24),

                        if (!_selectedProduct!.isService)
                          _buildDetailSection(theme,
                              title: 'Inventario',
                              children: [
                                _buildDetailRow(theme, 'Stock Actual',
                                    '${_selectedProduct!.inventoryQty}',
                                    isHighlight: true),
                                if (_selectedProduct!.warehouseLocation != null)
                                  _buildDetailRow(theme, 'Ubicación',
                                      _selectedProduct!.warehouseLocation!),
                              ]),

                        const SizedBox(height: 32),

                        SizedBox(
                          width: double.infinity,
                          child: AppButton(
                            text: 'Editar Producto',
                            icon: Icons.edit_outlined,
                            onPressed: () => _openEditor(_selectedProduct!),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tab 2: Stock Movements
                  _selectedProduct!.id != null
                      ? ProductMovementsTab(productId: _selectedProduct!.id!)
                      : const Center(child: Text('Guarde el producto primero')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(ThemeData theme, String label, String value,
      {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(value,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
                  color: isHighlight
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface)),
        ],
      ),
    );
  }

  Widget _buildDetailSection(ThemeData theme,
      {required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  void _showMobileFilters(ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color: theme.colorScheme.outlineVariant),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.tune),
                          const SizedBox(width: 12),
                          Text(
                            'Filtros',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                _resetFilters();
                              });
                              // Also update main state
                              setState(() {});
                            },
                            child: const Text('Limpiar'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    // Content
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Categoría',
                                style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            _buildSearchableMenu<Category>(
                              theme: theme,
                              hint: 'Seleccionar categoría...',
                              value: _categories.cast<Category?>().firstWhere(
                                    (c) => c!.id == _selectedCategoryId,
                                    orElse: () => null,
                                  ),
                              items: _categories,
                              labelBuilder: (c) => c.name,
                              onChanged: (val) {
                                setModalState(
                                    () => _selectedCategoryId = val?.id);
                                setState(() {
                                  _selectedCategoryId = val?.id;
                                  _applyFilters();
                                });
                              },
                            ),
                            const SizedBox(height: 24),

                            Text('Proveedor',
                                style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            _buildSearchableMenu<Supplier>(
                              theme: theme,
                              hint: 'Seleccionar proveedor...',
                              value: _suppliers.cast<Supplier?>().firstWhere(
                                    (s) => s!.id == _selectedSupplierId,
                                    orElse: () => null,
                                  ),
                              items: _suppliers,
                              labelBuilder: (s) => s.name,
                              onChanged: (val) {
                                setModalState(
                                    () => _selectedSupplierId = val?.id);
                                setState(() {
                                  _selectedSupplierId = val?.id;
                                  _applyFilters();
                                });
                              },
                            ),
                            const SizedBox(height: 24),

                            Text('Tipo de Producto',
                                style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            _buildProductTypeFilterDropdown(theme),

                            const SizedBox(height: 24),

                            Text('Inventario',
                                style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            // Custom segment control for stock
                            LayoutBuilder(builder: (context, constraints) {
                              return ToggleButtons(
                                isSelected: [
                                  _stockFilter == StockFilter.all,
                                  _stockFilter == StockFilter.inStock,
                                  _stockFilter == StockFilter.lowStock,
                                  _stockFilter == StockFilter.outOfStock,
                                ],
                                onPressed: (index) {
                                  final newFilter = StockFilter.values[index];
                                  setModalState(() => _stockFilter = newFilter);
                                  setState(() {
                                    _stockFilter = newFilter;
                                    _applyFilters();
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                constraints: BoxConstraints(
                                  minWidth: (constraints.maxWidth - 6) / 4,
                                  minHeight: 40,
                                ),
                                children: const [
                                  Text('Todos', style: TextStyle(fontSize: 12)),
                                  Text('Con Stock',
                                      style: TextStyle(fontSize: 12)),
                                  Text('Bajo', style: TextStyle(fontSize: 12)),
                                  Text('Sin Stock',
                                      style: TextStyle(fontSize: 12)),
                                ],
                              );
                            }),

                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),

                            SwitchListTile(
                              title: const Text('Publicado en Web'),
                              value: _filterWebPublished,
                              onChanged: (val) {
                                setModalState(() => _filterWebPublished = val);
                                setState(() {
                                  _filterWebPublished = val;
                                  _applyFilters();
                                });
                              },
                            ),
                            SwitchListTile(
                              title: const Text('Google Merchant'),
                              value: _filterGoogleMerchant,
                              onChanged: (val) {
                                setModalState(
                                    () => _filterGoogleMerchant = val);
                                setState(() {
                                  _filterGoogleMerchant = val;
                                  _applyFilters();
                                });
                              },
                            ),
                            SwitchListTile(
                              title: const Text('Mostrar Inactivos'),
                              value: _showInactive,
                              onChanged: (val) {
                                setModalState(() => _showInactive = val);
                                setState(() {
                                  _showInactive = val;
                                  _applyFilters();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Footer
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child:
                              Text('Ver ${_filteredProducts.length} productos'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
