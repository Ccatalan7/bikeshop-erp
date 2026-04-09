import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/supplier.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/barcode_scanner_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';

import '../../purchases/services/purchase_service.dart';
import '../models/brand_models.dart';
import '../models/bulk_product_edit_models.dart';
import '../models/category_models.dart';
import '../models/inventory_models.dart';
import '../services/brand_service.dart';
import '../services/category_service.dart';
import '../services/inventory_service.dart' as inventory_services;
import '../widgets/bulk_product_edit_dialog.dart';
import '../widgets/product_movements_tab.dart';

enum ProductViewMode { table, cards }

enum StockFilter { all, inStock, lowStock, outOfStock }

extension StockFilterX on StockFilter {
  String get label {
    switch (this) {
      case StockFilter.all:
        return 'Todos';
      case StockFilter.inStock:
        return 'En stock';
      case StockFilter.lowStock:
        return 'Stock bajo';
      case StockFilter.outOfStock:
        return 'Sin stock';
    }
  }
}

enum ProductTableColumn {
  product,
  sku,
  category,
  stock,
  price,
  cost,
  margin,
}

extension ProductTableColumnX on ProductTableColumn {
  String get label {
    switch (this) {
      case ProductTableColumn.product:
        return 'Producto';
      case ProductTableColumn.sku:
        return 'SKU';
      case ProductTableColumn.category:
        return 'Categoría';
      case ProductTableColumn.stock:
        return 'Stock';
      case ProductTableColumn.price:
        return 'Precio';
      case ProductTableColumn.cost:
        return 'Costo';
      case ProductTableColumn.margin:
        return 'Margen';
    }
  }
}

class ProductListPage extends StatefulWidget {
  final String? initialCategoryId;
  final String? initialSupplierId;
  final String? refreshToken; // Add refresh parameter

  final bool embedded;

  const ProductListPage({
    super.key,
    this.initialCategoryId,
    this.initialSupplierId,
    this.refreshToken,
    this.embedded = false,
  });

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _tableScrollController = ScrollController();

  late inventory_services.InventoryService _inventoryService;
  late CategoryService _categoryService;
  late BrandService _brandService;
  late PurchaseService _purchaseService;

  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  List<Category> _categories = [];
  List<Supplier> _suppliers = [];
  List<ProductBrand> _brands = [];

  // Detail pane resize
  double _detailPaneWidth = 520.0;

  bool _isLoading = true;
  String _searchTerm = '';

  // 🔍 Smart Filters State
  String? _selectedCategoryId;
  String? _selectedSupplierId;
  String? _selectedBrandId;
  ProductType? _selectedProductType;
  StockFilter _stockFilter = StockFilter.all;
  bool _filterWebPublished = false; // is_published = true
  bool _filterGoogleMerchant = false; // is_google_merchant = true
  bool _showInactive =
      false; // when true, show ALL products (including inactive)

  // 🔽 Sorting State
  ProductSortOption _sortOption = ProductSortOption.nameAsc;

  // 📷 Scanner State
  bool _isScannerEnabled = true;

  ProductViewMode _viewMode = ProductViewMode.table;
  Product? _selectedProduct; // For split-pane detail view
  final Set<String> _expandedSets = {}; // Track which sets are expanded

  // Column visibility (table view)
  static const String _columnsPrefsKey = 'products_table_columns_v1';
  Set<ProductTableColumn> _visibleColumns = {
    ProductTableColumn.product,
    ProductTableColumn.sku,
    ProductTableColumn.category,
    ProductTableColumn.stock,
    ProductTableColumn.price,
    ProductTableColumn.cost,
  };
  final List<ProductTableColumn> _columnOrder = const [
    ProductTableColumn.product,
    ProductTableColumn.sku,
    ProductTableColumn.category,
    ProductTableColumn.stock,
    ProductTableColumn.price,
    ProductTableColumn.cost,
    ProductTableColumn.margin,
  ];

  // Pagination
  int _currentPage = 1;
  final int _itemsPerPage = 100; // Reduced for better performance
  double? _savedScrollOffset; // Preserve scroll position when navigating
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
      _selectedBrandId != null ||
      _selectedProductType != null ||
      _stockFilter != StockFilter.all ||
      _filterWebPublished ||
      _filterGoogleMerchant ||
      _showInactive ||
      _searchTerm.isNotEmpty;

  StreamSubscription? _scanSubscription;
  StreamSubscription<String>? _externalSearchSub;
  List<String>?
      _aiMatchedSkus; // SKUs from AI search, used instead of keyword search
  bool _shouldRestoreState = false; // Local flag for this page instance

  // Hardware keyboard scanner state (USB/Bluetooth barcode scanners)
  final StringBuffer _scanBuffer = StringBuffer();
  Timer? _hwScanTimer;
  DateTime? _lastScanKeyTime;
  static const Duration _scanKeyTimeout = Duration(milliseconds: 100);
  static const int _minBarcodeLen = 3;
  DateTime?
      _lastVisibleTime; // Track when page was last visible for state timeout

  @override
  void initState() {
    super.initState();
    _inventoryService = Provider.of<inventory_services.InventoryService>(
        context,
        listen: false);
    _categoryService = Provider.of<CategoryService>(context, listen: false);
    _brandService = Provider.of<BrandService>(context, listen: false);
    _purchaseService = Provider.of<PurchaseService>(context, listen: false);

    // Restore if there's any saved state (pending flag OR grace window).
    // NEVER clear saved state in initState - the page can be rebuilt multiple
    // times by the router during navigation transitions, and clearing here
    // would lose the user's scroll/filter state on the second rebuild.
    _shouldRestoreState = _inventoryService.shouldRestoreState ||
        _inventoryService.hasRecentSavedState;
    if (_shouldRestoreState) {
      _restoreSavedState();
    }
    // Note: Don't clear state here - it's cleared when user navigates away from inventory

    // Listen to external search commands (e.g., from the AI Assistant panel)
    _externalSearchSub = _inventoryService.externalSearchStream.listen((term) {
      if (mounted) {
        setState(() {
          _searchTerm = term;
          _searchController.text = term;
          _aiMatchedSkus = _inventoryService.aiMatchedSkus;
          if (_inventoryService.aiStockFilterIndex != null) {
            _stockFilter = StockFilter.values[_inventoryService
                .aiStockFilterIndex!
                .clamp(0, StockFilter.values.length - 1)];
          }
        });
        _applyFilters(resetPagination: true);
      }
    });

    // Initial load sequence - SMART: skip full reload if we have cached data
    if (_shouldRestoreState && _inventoryService.hasProductsCache) {
      // Use cached data directly - no network fetch needed!
      debugPrint(
          '⚡ [ProductListPage] Using cached products for restore (skip reload)');
      _products = _inventoryService.cachedProducts;
      _loadCategories(); // Still need filter options
      _loadSuppliers();
      _loadBrands();
      _applyFilters(resetPagination: false);
      _isLoading = false;
      // Schedule scroll restore after the frame renders
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scheduleScrollRestore();
          // Mark state as restored so next navigation to another module starts fresh
          _inventoryService.markStateRestored();
        }
      });
    } else {
      // Fresh load - no state to restore or cache is empty
      _loadData();
    }

    _loadColumnPreferences();

    // Listen for barcode scans from remote/phone scanner
    _scanSubscription =
        context.read<BarcodeScannerService>().barcodeStream.listen((barcode) {
      if (mounted && _isScannerEnabled) {
        _handleBarcodeScan(barcode);
      }
    });

    // Register hardware handler for USB/Bluetooth keyboard-emulating scanners.
    // HardwareKeyboard bypasses the focus system so it works even when
    // the search bar is focused.
    HardwareKeyboard.instance.addHandler(_hardwareKeyHandler);

    // Check for initial filters from widget arguments (override saved state)
    if (widget.initialCategoryId != null) {
      _selectedCategoryId = widget.initialCategoryId;
    }
    if (widget.initialSupplierId != null) {
      _selectedSupplierId = widget.initialSupplierId;
    }

    // Track initial visibility
    _lastVisibleTime = DateTime.now();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if we're becoming visible again after being away from inventory
    _checkVisibilityAndResetIfNeeded();
  }

  /// Check if we've been away from this page for more than the grace window.
  /// If so, reset all filters and reload fresh data.
  void _checkVisibilityAndResetIfNeeded() {
    if (_lastVisibleTime == null) return;

    final now = DateTime.now();
    final timeSinceLastVisible = now.difference(_lastVisibleTime!);

    // If we've been away for more than 30 seconds, reset to fresh state
    if (timeSinceLastVisible.inSeconds > 30) {
      debugPrint(
          '🔄 [ProductListPage] Away for ${timeSinceLastVisible.inSeconds}s - resetting to fresh state');
      // Reset all filters to defaults
      _searchTerm = '';
      _searchController.clear();
      _searchTerm = '';
      _searchController.clear();
      _selectedCategoryId = null;
      _selectedSupplierId = null;
      _selectedBrandId = null;
      _selectedProductType = null;
      _stockFilter = StockFilter.all;
      _filterWebPublished = false;
      _filterGoogleMerchant = false;
      _showInactive = false;
      _currentPage = 1;
      _sortOption = ProductSortOption.nameAsc;
      // Clear saved state in service too
      _inventoryService.clearListState();
      // Reload fresh data
      _loadData();
    }

    // Update last visible time
    _lastVisibleTime = now;
  }

  Future<void> _loadColumnPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_columnsPrefsKey);
    if (saved == null || saved.isEmpty) return;

    final parsed = saved
        .map((name) => ProductTableColumn.values.firstWhere(
            (c) => c.name == name,
            orElse: () => ProductTableColumn.product))
        .toSet();

    if (!mounted) return;
    setState(() {
      _visibleColumns = parsed..add(ProductTableColumn.product);
    });
  }

  Future<void> _saveColumnPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _columnsPrefsKey,
      _visibleColumns.map((c) => c.name).toList(),
    );
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadCategories(),
      _loadSuppliers(),
      _loadBrands(),
      _loadProducts(preserveState: _shouldRestoreState),
    ]);
  }

  // ============================================================
  // STATE PRESERVATION - Only when returning from product edit
  // ============================================================
  void _restoreSavedState() {
    // Restore state from service
    _searchTerm = _inventoryService.savedSearchTerm ?? '';
    _searchController.text = _searchTerm;
    _aiMatchedSkus = _inventoryService.aiMatchedSkus;
    _currentPage = _inventoryService.savedCurrentPage;
    _savedScrollOffset = _inventoryService.savedScrollOffset > 0
        ? _inventoryService.savedScrollOffset
        : null;
    _selectedCategoryId = _inventoryService.savedCategoryId;
    _selectedSupplierId = _inventoryService.savedSupplierId;

    // Restore ProductType enum
    if (_inventoryService.savedProductTypeIndex != null) {
      _selectedProductType =
          ProductType.values[_inventoryService.savedProductTypeIndex!];
    }

    // Restore StockFilter enum
    _stockFilter = StockFilter.values[_inventoryService.savedStockFilterIndex];

    _filterWebPublished = _inventoryService.savedFilterWebPublished;
    _filterGoogleMerchant = _inventoryService.savedFilterGoogleMerchant;
    _showInactive = _inventoryService.savedShowInactive;

    // Restore sort option
    _sortOption =
        ProductSortOption.values[_inventoryService.savedSortOptionIndex];
  }

  /// Schedules a scroll position restoration after the current frame.
  /// Uses a double-delayed approach to handle rapid rebuilds.
  void _scheduleScrollRestore() {
    final scrollOffset = _savedScrollOffset ??
        (_inventoryService.savedScrollOffset > 0
            ? _inventoryService.savedScrollOffset
            : null);
    if (scrollOffset == null || scrollOffset <= 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Double-schedule to handle rapid rebuilds and ensure layout is complete
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_tableScrollController.hasClients && mounted) {
          final maxScroll = _tableScrollController.position.maxScrollExtent;
          final targetOffset = scrollOffset.clamp(0.0, maxScroll);
          _tableScrollController.jumpTo(targetOffset);
          // Only clear after successful jump
          _savedScrollOffset = null;
        }
      });
    });
  }

  void _saveCurrentState() {
    _inventoryService.saveListState(
      searchTerm: _searchTerm,
      currentPage: _currentPage,
      scrollOffset:
          _tableScrollController.hasClients ? _tableScrollController.offset : 0,
      categoryId: _selectedCategoryId,
      supplierId: _selectedSupplierId,
      productTypeIndex: _selectedProductType?.index,
      stockFilterIndex: _stockFilter.index,
      filterWebPublished: _filterWebPublished,
      filterGoogleMerchant: _filterGoogleMerchant,
      showInactive: _showInactive,
      sortOptionIndex: _sortOption.index,
    );
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
    _externalSearchSub?.cancel();
    HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
    _hwScanTimer?.cancel();
    super.dispose();
  }

  /// Hardware keyboard handler for USB/Bluetooth barcode scanners.
  /// Returns false so key events still reach focused widgets (e.g. search bar).
  bool _hardwareKeyHandler(KeyEvent event) {
    if (!_isScannerEnabled || !mounted) return false;
    if (!ModalRoute.of(context)!.isCurrent) return false;
    if (event is! KeyDownEvent) return false;

    if (_isTextInputFocused) {
      _scanBuffer.clear();
      _hwScanTimer?.cancel();
      return false;
    }

    final now = DateTime.now();
    if (_lastScanKeyTime != null &&
        now.difference(_lastScanKeyTime!) > _scanKeyTimeout) {
      _scanBuffer.clear();
    }
    _lastScanKeyTime = now;
    _hwScanTimer?.cancel();

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final barcode = _scanBuffer.toString().trim();
      _scanBuffer.clear();
      if (barcode.length >= _minBarcodeLen) {
        _handleBarcodeScan(barcode);
      }
      return false;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty) {
      _scanBuffer.write(char);
      _hwScanTimer = Timer(_scanKeyTimeout, () {
        if (_isTextInputFocused) {
          _scanBuffer.clear();
          return;
        }
        final barcode = _scanBuffer.toString().trim();
        _scanBuffer.clear();
        if (barcode.length >= _minBarcodeLen && mounted) {
          _handleBarcodeScan(barcode);
        }
      });
    }

    return false; // Never consume — let events reach text fields normally
  }

  bool get _isTextInputFocused {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;

    return focusedContext.widget is EditableText;
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    // Only handle scans if scanner is enabled and page is visible
    if (!_isScannerEnabled || !mounted || !ModalRoute.of(context)!.isCurrent) {
      return;
    }

    // Search for product by SKU or barcode field
    final product = _products.cast<Product?>().firstWhere(
          (p) =>
              p!.sku.toLowerCase() == barcode.toLowerCase() ||
              (p.barcode?.toLowerCase() == barcode.toLowerCase()),
          orElse: () => null,
        );

    if (product != null) {
      // Navigate to product edit page
      if (mounted) {
        // Save current state to service before navigating
        _saveCurrentState();

        final result =
            await context.push('/inventory/products/${product.id}/edit');
        if (!mounted) return;

        // Always restore state when coming back (even without saving)
        _shouldRestoreState = true;
        _restoreSavedState();

        // Reload products; force refresh only if a save occurred
        _loadProducts(
          forceRefresh: result == true,
          preserveState: true,
        );

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

  Future<void> _openBulkEditWorkspace({bool useSelection = false}) async {
    final hasSelection = _selectedProductIds.isNotEmpty;
    final initialSource = useSelection && hasSelection
        ? BulkProductScopeSource.selected
        : (hasSelection
            ? BulkProductScopeSource.selected
            : BulkProductScopeSource.filtered);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BulkProductEditDialog(
        allProducts: _products,
        filteredProducts: _filteredProducts,
        selectedProductIds: _selectedProductIds,
        categories: _categories,
        brands: _brands,
        suppliers: _suppliers,
        initialSource: initialSource,
        lockSource: useSelection && hasSelection,
      ),
    );

    if (result == true && mounted) {
      setState(() => _selectedProductIds.clear());
      await _loadProducts(forceRefresh: true, preserveState: true);
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

  Future<void> _loadBrands() async {
    try {
      final brands = await _brandService.getBrands();
      if (mounted) {
        setState(() {
          _brands = brands.where((b) => b.isActive).toList();
        });
      }
    } catch (_) {
      // Ignored: brands are optional for listing products.
    }
  }

  Future<void> _loadProducts(
      {bool forceRefresh = false, bool preserveState = false}) async {
    if (!mounted) return;

    // 🚀 INSTANT RENDER: Show cached data immediately if available
    if (_inventoryService.hasProductsCache &&
        _products.isEmpty &&
        !forceRefresh) {
      setState(() {
        _products = _inventoryService.cachedProducts;
        _applyFilters(resetPagination: !preserveState);
        _isLoading = false;
      });

      // Also restore scroll position on instant render
      if (preserveState) {
        _scheduleScrollRestore();
      }
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
        _applyFilters(resetPagination: !preserveState);
        _isLoading = false;
      });

      // Restore scroll position after data loads
      if (preserveState) {
        _scheduleScrollRestore();
        // Note: We intentionally do NOT clear the pending restore flag here.
        // The router can rebuild the page multiple times during navigation.
      }

      // OPTIMIZATION: Disabled redundant sync - shared inventory has its own cache
      // and is preloaded on app start. Syncing on every list load caused double fetches.
      // _syncSharedInventorySilently();
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

  /// Normalizes text by removing diacritics and converting to lowercase
  String _normalizeText(String text) {
    if (text.isEmpty) return text;
    String normalized = text.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r'[áàäâ]'), 'a');
    normalized = normalized.replaceAll(RegExp(r'[éèëê]'), 'e');
    normalized = normalized.replaceAll(RegExp(r'[íìïî]'), 'i');
    normalized = normalized.replaceAll(RegExp(r'[óòöô]'), 'o');
    normalized = normalized.replaceAll(RegExp(r'[úùüû]'), 'u');
    normalized = normalized.replaceAll(RegExp(r'[ñ]'), 'n');
    normalized = normalized.replaceAll(RegExp(r'[ç]'), 'c');
    return normalized;
  }

  /// Naive Spanish stemming for search queries
  String _stemSearchTerm(String term) {
    if (term.length <= 3) return term;
    if (term.endsWith('es')) {
      if (term == 'mes' || term == 'tres') return term;
      final beforeEs = term.substring(0, term.length - 2);
      if (beforeEs.isNotEmpty) {
        final lastChar = beforeEs[beforeEs.length - 1];
        if ('ldrn'.contains(lastChar)) return beforeEs;
      }
    }
    if (term.endsWith('s')) {
      if (term == 'cas' ||
          term == 'dos' ||
          term == 'mas' ||
          term == 'las' ||
          term == 'los' ||
          term == 'sus') {
        return term;
      }
      return term.substring(0, term.length - 1);
    }
    return term;
  }

  /// Token-based search: splits query into words and matches if ALL tokens found
  bool _matchesTokenSearch(String query, Product product) {
    if (query.isEmpty) return true;
    final rawTokens = query.toLowerCase().split(RegExp(r'\s+'));
    final tokens =
        rawTokens.map((t) => _stemSearchTerm(_normalizeText(t))).toList();

    final searchableText = [
      _normalizeText(product.name),
      _normalizeText(product.sku),
      _normalizeText(product.supplierCode ?? ''),
      _normalizeText(product.brand ?? ''),
      _normalizeText(product.model ?? ''),
      _normalizeText(_resolveCategoryName(product) ?? ''),
    ].join(' ');

    // ALL tokens must be found in searchable text.
    // Numeric tokens use word-boundary matching to avoid "29" matching "295".
    return tokens.every((token) {
      if (RegExp(r'^\d+$').hasMatch(token)) {
        return RegExp('(?:^|\\s|[^0-9])$token(?:\$|\\s|[^0-9])')
            .hasMatch(searchableText);
      }
      return searchableText.contains(token);
    });
  }

  void _applyFilters({bool resetPagination = true}) {
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
            .where((product) =>
                product.tracksInventory && product.inventoryQty > 0)
            .toList();
        break;
      case StockFilter.lowStock:
        // Show low stock (includes out of stock usually, or strictly low?)
        // User said "Bajo stock", "Sin stock", "Con stock".
        // Low stock usually implies it needs attention.
        filtered = filtered
            .where((product) => product.tracksInventory && product.isLowStock)
            .toList();
        break;
      case StockFilter.outOfStock:
        filtered = filtered
            .where((product) => product.tracksInventory && product.isOutOfStock)
            .toList();
        break;
    }

    if (_filterWebPublished) {
      filtered = filtered.where((product) => product.isPublished).toList();
    }

    if (_filterGoogleMerchant) {
      filtered = filtered.where((product) => product.isGoogleMerchant).toList();
    }

    if (_selectedBrandId != null) {
      final brand = _brands.firstWhere(
        (b) => b.id == _selectedBrandId,
        orElse: () => _brands.first,
      );
      final brandNameLower = brand.name.toLowerCase();
      filtered = filtered
          .where((product) =>
              (product.brand ?? '').toLowerCase() == brandNameLower ||
              product.brandId == _selectedBrandId)
          .toList();
    }

    if (!_showInactive) {
      filtered = filtered.where((product) => product.isActive).toList();
    }

    // 5. Search — use AI-matched SKUs if available, otherwise keyword search
    if (_aiMatchedSkus != null && _aiMatchedSkus!.isNotEmpty) {
      final skuSet = _aiMatchedSkus!.toSet();
      filtered =
          filtered.where((product) => skuSet.contains(product.sku)).toList();
    } else if (_searchTerm.isNotEmpty) {
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

    // Only reset pagination when filters/search change, not on reload
    if (resetPagination) {
      _currentPage = 1;
    } else {
      // Ensure current page is still valid after filtering
      if (_currentPage > _totalPages && _totalPages > 0) {
        _currentPage = _totalPages;
      }
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchTerm = value.trim();
      _aiMatchedSkus = null; // Clear AI results when user types manually
      _applyFilters();
    });
  }

  // ---------------------------------------------------------------------------
  // UI BUILDERS (Minimalistic Redesign)
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final body = _buildBody(theme);
    if (widget.embedded) return body;

    return MainLayout(child: body);
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: BrandedLoading());
    }

    return Column(
      children: [
        // 1. Unified Master Header (Title + Search + Actions)
        _buildUnifiedHeader(theme),

        // 2. Control Toolbar (Filters Left | View Options Right)
        _buildControlToolbar(theme),

        // 3. Slim Stats Bar
        if (!_isMultiSelectMode) _buildSlimStatsBar(theme),

        // 4. Bulk Actions (if active)
        if (_isMultiSelectMode) _buildBulkActionsBar(theme),

        // 5. Main Content
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobileWidth = constraints.maxWidth < 800;
              if (_filteredProducts.isEmpty) {
                return _buildEmptyState(theme);
              }
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

  // Combines Title, Search, and Actions into one cohesive bar
  Widget _buildUnifiedHeader(ThemeData theme) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    if (isMobile) return _buildMobileHeader(theme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Title Section with accent
          Container(
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                    width: 1),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.primary.withOpacity(0.5)
                          ],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Text(
                      'Productos',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                if (_filteredProducts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Text(
                      '${_filteredProducts.length} productos',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Search Bar - Left-aligned right after title
          Container(
            width: 320,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textAlignVertical: TextAlignVertical.center,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, SKU, marca...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: Icon(Icons.search_rounded,
                      size: 20, color: theme.colorScheme.onSurfaceVariant),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
                suffixIcon: _searchTerm.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: InputBorder.none,
              ),
            ),
          ),

          const Spacer(),

          // Actions with modern styling
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Scanner Toggle
              _buildScannerToggle(theme),
              const SizedBox(width: 10),

              // Import Button
              _buildSecondaryActionButton(
                theme: theme,
                icon: Icons.file_upload_outlined,
                label: 'Importar',
                onPressed: () async {
                  final result =
                      await context.push('/inventory/products/import');
                  if (result == true) _loadProducts(forceRefresh: true);
                },
              ),
              const SizedBox(width: 10),

              _buildSecondaryActionButton(
                theme: theme,
                icon: Icons.rule_folder_outlined,
                label: 'Edición masiva',
                onPressed: _openBulkEditWorkspace,
              ),
              const SizedBox(width: 10),

              // Primary CTA - New Product
              _buildPrimaryCTA(
                theme: theme,
                icon: Icons.add_rounded,
                label: 'Nuevo Producto',
                onPressed: () async {
                  final result = await context.push('/inventory/products/new');
                  if (result == true) _loadProducts(forceRefresh: true);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryActionButton({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryCTA({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withBlue(
                    (theme.colorScheme.primary.blue + 20).clamp(0, 255)),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.onPrimary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Productos',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text('${_filteredProducts.length} items',
                      style: theme.textTheme.bodySmall),
                ],
              ),
              Row(
                children: [
                  // Scanner Toggle (Mobile Compact)
                  IconButton.filledTonal(
                    icon: const Icon(Icons.rule_folder_outlined, size: 20),
                    onPressed: _openBulkEditWorkspace,
                    tooltip: 'Edición masiva',
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    icon: Icon(
                      _isScannerEnabled
                          ? Icons.qr_code_scanner
                          : Icons.qr_code_2_outlined,
                      size: 20,
                      color: _isScannerEnabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () {
                      setState(() => _isScannerEnabled = !_isScannerEnabled);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(_isScannerEnabled
                                ? 'Escáner activado'
                                : 'Escáner desactivado')),
                      );
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: _isScannerEnabled
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () async {
                      final result =
                          await context.push('/inventory/products/new');
                      if (result == true) _loadProducts(forceRefresh: true);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 12),
          // Search Field
          SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Buscar...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchTerm.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerToggle(ThemeData theme) {
    return Tooltip(
      message: _isScannerEnabled
          ? 'Escáner activo - Click para desactivar'
          : 'Click para activar escáner',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _isScannerEnabled = !_isScannerEnabled),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              gradient: _isScannerEnabled
                  ? LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primary.withOpacity(0.85),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: _isScannerEnabled
                  ? null
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              boxShadow: _isScannerEnabled
                  ? [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 18,
                  color: _isScannerEnabled
                      ? Colors.white
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _isScannerEnabled
                        ? Colors.white
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  child: const Text('ON'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Row with Filters on the Left and View Options on the Right
  Widget _buildControlToolbar(ThemeData theme) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    if (isMobile) return _buildSmartFilterBar(theme); // Fallback for mobile

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
        ),
      ),
      child: Row(
        children: [
          // Left: Filter Cluster
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ModernFilterChip(
                    theme: theme,
                    label: _selectedCategoryId != null
                        ? (_categories
                                .where((c) => c.id == _selectedCategoryId)
                                .firstOrNull
                                ?.name ??
                            'Categoría')
                        : 'Categoría',
                    isActive: _selectedCategoryId != null,
                    onTap: (chipCtx, link) {
                      _showFilterMenu<Category>(
                        buttonContext: chipCtx,
                        layerLink: link,
                        theme: theme,
                        title: 'Categoría',
                        items: _categories,
                        labelBuilder: (c) => c.name,
                        selectedId: _selectedCategoryId,
                        idExtractor: (c) => c.id,
                        onSelected: (id) {
                          setState(() {
                            _selectedCategoryId = id;
                            _applyFilters();
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _ModernFilterChip(
                    theme: theme,
                    label: _selectedSupplierId != null
                        ? (_suppliers
                                .where((s) => s.id == _selectedSupplierId)
                                .firstOrNull
                                ?.name ??
                            'Proveedor')
                        : 'Proveedor',
                    isActive: _selectedSupplierId != null,
                    onTap: (chipCtx, link) {
                      _showFilterMenu<Supplier>(
                        buttonContext: chipCtx,
                        layerLink: link,
                        theme: theme,
                        title: 'Proveedor',
                        items: _suppliers,
                        labelBuilder: (s) => s.name,
                        selectedId: _selectedSupplierId,
                        idExtractor: (s) => s.id,
                        onSelected: (id) {
                          setState(() {
                            _selectedSupplierId = id;
                            _applyFilters();
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _ModernFilterChip(
                    theme: theme,
                    label: _selectedProductType?.displayName ?? 'Tipo',
                    isActive: _selectedProductType != null,
                    onTap: (chipCtx, link) =>
                        _showProductTypeMenu(chipCtx, link, theme),
                  ),
                  const SizedBox(width: 8),
                  _ModernFilterChip(
                    theme: theme,
                    label: _stockFilter != StockFilter.all
                        ? _stockFilter.label
                        : 'Inventario',
                    isActive: _stockFilter != StockFilter.all,
                    onTap: (chipCtx, link) =>
                        _showStockFilterMenu(chipCtx, link, theme),
                  ),
                  const SizedBox(width: 8),
                  _ModernFilterChip(
                    theme: theme,
                    label: 'Canales',
                    isActive: _filterWebPublished || _filterGoogleMerchant,
                    onTap: (chipCtx, link) =>
                        _showChannelsMenu(chipCtx, link, theme),
                  ),
                  const SizedBox(width: 8),
                  _ModernFilterChip(
                    theme: theme,
                    label: _selectedBrandId != null
                        ? (_brands
                                .where((b) => b.id == _selectedBrandId)
                                .firstOrNull
                                ?.name ??
                            'Marca')
                        : 'Marca',
                    isActive: _selectedBrandId != null,
                    onTap: (chipCtx, link) {
                      _showFilterMenu<ProductBrand>(
                        buttonContext: chipCtx,
                        layerLink: link,
                        theme: theme,
                        title: 'Marca',
                        items: _brands,
                        labelBuilder: (b) => b.name,
                        selectedId: _selectedBrandId,
                        idExtractor: (b) => b.id,
                        onSelected: (id) {
                          setState(() {
                            _selectedBrandId = id;
                            _applyFilters();
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _ModernFilterChip(
                    theme: theme,
                    label: _showInactive ? 'Incl. inactivos' : 'Estado',
                    isActive: _showInactive,
                    onTap: (chipCtx, link) =>
                        _showActivosMenu(chipCtx, link, theme),
                  ),
                  if (_hasActiveFilters) ...[
                    const SizedBox(width: 16),
                    _buildClearFiltersButton(theme),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Right: View Controls
          _buildModernSortButton(theme),
          const SizedBox(width: 10),

          if (_viewMode == ProductViewMode.table) ...[
            _buildModernIconButton(
              theme: theme,
              icon: Icons.view_column_outlined,
              label: 'Columnas',
              onPressed: _showColumnCustomizer,
            ),
            const SizedBox(width: 10),
          ],

          // Grid/List Toggle
          _buildViewModeToggle(theme),
        ],
      ),
    );
  }

  Widget _buildClearFiltersButton(ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _resetFilters,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_alt_off_rounded,
                  size: 16, color: theme.colorScheme.error),
              const SizedBox(width: 6),
              Text(
                'Limpiar',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernSortButton(ThemeData theme) {
    return PopupMenuButton<String>(
      tooltip: 'Ordenar',
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sort_rounded,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              _sortOption.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
      itemBuilder: (context) => ProductSortOption.values.map((option) {
        final isSelected = _sortOption == option;
        return PopupMenuItem<String>(
          value: option.name,
          child: Row(
            children: [
              if (isSelected)
                Icon(Icons.check_rounded,
                    size: 18, color: theme.colorScheme.primary)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              Text(
                option.label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? theme.colorScheme.primary : null,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onSelected: (value) {
        setState(() {
          _sortOption =
              ProductSortOption.values.firstWhere((e) => e.name == value);
          _applyFilters();
        });
      },
    );
  }

  Widget _buildModernIconButton({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewModeToggle(ThemeData theme) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleOption(
            theme: theme,
            icon: Icons.table_rows_rounded,
            isSelected: _viewMode == ProductViewMode.table,
            onTap: () => setState(() => _viewMode = ProductViewMode.table),
            isFirst: true,
          ),
          Container(
              width: 1,
              height: 20,
              color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
          _buildToggleOption(
            theme: theme,
            icon: Icons.grid_view_rounded,
            isSelected: _viewMode == ProductViewMode.cards,
            onTap: () => setState(() => _viewMode = ProductViewMode.cards),
            isFirst: false,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required ThemeData theme,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isFirst,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.horizontal(
          left: isFirst ? const Radius.circular(9) : Radius.zero,
          right: !isFirst ? const Radius.circular(9) : Radius.zero,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: isFirst ? const Radius.circular(9) : Radius.zero,
              right: !isFirst ? const Radius.circular(9) : Radius.zero,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // Helper methods for filter menus
  void _showFilterMenu<T>({
    required BuildContext buttonContext,
    required LayerLink layerLink,
    required ThemeData theme,
    required String title,
    required List<T> items,
    required String Function(T) labelBuilder,
    required String? selectedId,
    required String? Function(T) idExtractor,
    required ValueChanged<String?> onSelected,
  }) {
    final isDesktop = MediaQuery.of(buttonContext).size.width >= 800;

    if (isDesktop) {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: Colors.transparent,
        pageBuilder: (context, anim1, anim2) {
          return Stack(
            children: [
              CompositedTransformFollower(
                link: layerLink,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 4),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 300,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 400),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _DesktopSearchableFilterList<T>(
                          items: items,
                          labelBuilder: labelBuilder,
                          selectedId: selectedId,
                          idExtractor: idExtractor,
                          onSelected: (val) {
                            onSelected(val);
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => Container(
            padding: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Expanded(
                  child: _DesktopSearchableFilterList<T>(
                    items: items,
                    labelBuilder: labelBuilder,
                    selectedId: selectedId,
                    idExtractor: idExtractor,
                    onSelected: (val) {
                      onSelected(val);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _showProductTypeMenu(
      BuildContext context, LayerLink link, ThemeData theme) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    Widget buildMenuContent(BuildContext ctx) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tipo de Producto',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Todos'),
                leading: Radio<ProductType?>(
                    value: null,
                    groupValue: _selectedProductType,
                    onChanged: (_) {
                      setState(() {
                        _selectedProductType = null;
                        _applyFilters();
                      });
                      Navigator.pop(ctx);
                    }),
                onTap: () {
                  setState(() {
                    _selectedProductType = null;
                    _applyFilters();
                  });
                  Navigator.pop(ctx);
                },
              ),
              ...ProductType.values.map((type) => ListTile(
                    title: Text(type.displayName),
                    leading: Radio<ProductType?>(
                        value: type,
                        groupValue: _selectedProductType,
                        onChanged: (_) {
                          setState(() {
                            _selectedProductType = type;
                            _applyFilters();
                          });
                          Navigator.pop(ctx);
                        }),
                    onTap: () {
                      setState(() {
                        _selectedProductType = type;
                        _applyFilters();
                      });
                      Navigator.pop(ctx);
                    },
                  )),
            ],
          ),
        );

    if (isDesktop) {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: Colors.transparent,
        pageBuilder: (context, anim1, anim2) {
          return Stack(
            children: [
              CompositedTransformFollower(
                link: link,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 4),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 300,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: buildMenuContent(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: buildMenuContent,
      );
    }
  }

  void _showStockFilterMenu(
      BuildContext context, LayerLink link, ThemeData theme) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    Widget buildMenuContent(BuildContext ctx) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Inventario',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...StockFilter.values.map((filter) => ListTile(
                    title: Text(filter.label),
                    leading: Radio<StockFilter>(
                        value: filter,
                        groupValue: _stockFilter,
                        onChanged: (_) {
                          setState(() {
                            _stockFilter = filter;
                            _applyFilters();
                          });
                          Navigator.pop(ctx);
                        }),
                    onTap: () {
                      setState(() {
                        _stockFilter = filter;
                        _applyFilters();
                      });
                      Navigator.pop(ctx);
                    },
                  )),
            ],
          ),
        );

    if (isDesktop) {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: Colors.transparent,
        pageBuilder: (context, anim1, anim2) {
          return Stack(
            children: [
              CompositedTransformFollower(
                link: link,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 4),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 300,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: buildMenuContent(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: buildMenuContent,
      );
    }
  }

  void _showChannelsMenu(
      BuildContext context, LayerLink link, ThemeData theme) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    Widget buildMenuContent(BuildContext ctx, StateSetter setModalState) =>
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Canales de Venta',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Publicado en Web'),
                value: _filterWebPublished,
                onChanged: (val) {
                  setModalState(() => _filterWebPublished = val ?? false);
                  setState(() => _applyFilters());
                },
              ),
              CheckboxListTile(
                title: const Text('Google Merchant'),
                value: _filterGoogleMerchant,
                onChanged: (val) {
                  setModalState(() => _filterGoogleMerchant = val ?? false);
                  setState(() => _applyFilters());
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Aplicar'),
                ),
              ),
            ],
          ),
        );

    if (isDesktop) {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: Colors.transparent,
        pageBuilder: (context, anim1, anim2) {
          return Stack(
            children: [
              CompositedTransformFollower(
                link: link,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 4),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 300,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: StatefulBuilder(
                            builder: (context, setModalState) =>
                                buildMenuContent(context, setModalState)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) =>
              buildMenuContent(ctx, setModalState),
        ),
      );
    }
  }

  void _showActivosMenu(BuildContext context, LayerLink link, ThemeData theme) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    Widget buildMenuContent(BuildContext ctx) => Container(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Solo activos'),
                leading: Radio<bool>(
                  value: false,
                  groupValue: _showInactive,
                  onChanged: (_) {
                    setState(() {
                      _showInactive = false;
                      _applyFilters();
                    });
                    Navigator.pop(ctx);
                  },
                ),
                onTap: () {
                  setState(() {
                    _showInactive = false;
                    _applyFilters();
                  });
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                title: const Text('Incluir inactivos'),
                leading: Radio<bool>(
                  value: true,
                  groupValue: _showInactive,
                  onChanged: (_) {
                    setState(() {
                      _showInactive = true;
                      _applyFilters();
                    });
                    Navigator.pop(ctx);
                  },
                ),
                onTap: () {
                  setState(() {
                    _showInactive = true;
                    _applyFilters();
                  });
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );

    if (isDesktop) {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: Colors.transparent,
        pageBuilder: (context, anim1, anim2) {
          return Stack(
            children: [
              CompositedTransformFollower(
                link: link,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 4),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 240,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(8),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: buildMenuContent(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: buildMenuContent,
      );
    }
  }

  // Compact inline stats - minimal height
  Widget _buildSlimStatsBar(ThemeData theme) {
    if (_filteredProducts.isEmpty) return const SizedBox.shrink();

    final stockProducts =
        _filteredProducts.where((p) => p.tracksInventory).toList();
    final lowStock =
        stockProducts.where((p) => p.inventoryQty > 0 && p.isLowStock).length;
    final outOfStock = stockProducts.where((p) => p.inventoryQty <= 0).length;
    final stockValue = stockProducts.fold<double>(
      0,
      (sum, p) => sum + (p.cost > 0 ? p.cost * p.inventoryQty : 0),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          _buildCompactStat(
              theme,
              Icons.inventory_2_outlined,
              'Costo inventario:',
              ChileanUtils.formatCurrency(stockValue),
              theme.colorScheme.primary),
          const SizedBox(width: 24),
          _buildCompactStat(theme, Icons.warning_amber_rounded, 'Bajo stock:',
              '$lowStock', const Color(0xFFE67E22)),
          const SizedBox(width: 24),
          _buildCompactStat(theme, Icons.remove_shopping_cart_outlined,
              'Sin stock:', '$outOfStock', const Color(0xFFE74C3C)),
        ],
      ),
    );
  }

  Widget _buildCompactStat(
      ThemeData theme, IconData icon, String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
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
                        theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
                      : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
                          theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
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

              const SizedBox(width: 8),

              // Column Customizer (Table View)
              if (_viewMode == ProductViewMode.table)
                OutlinedButton.icon(
                  onPressed: _showColumnCustomizer,
                  icon: const Icon(Icons.view_column_outlined, size: 18),
                  label: const Text('Columnas'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  allLabel: 'Categoría: Todas',
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
                  allLabel: 'Proveedor: Todos',
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
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
            if (val != null) {
              setState(() {
                _sortOption = val;
                _applyFilters();
              });
            }
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
    final hasValue = value != null;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: hasValue
            ? theme.colorScheme.primaryContainer.withOpacity(0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              hasValue ? Colors.transparent : theme.colorScheme.outlineVariant,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500)),
          icon: Icon(Icons.arrow_drop_down,
              size: 18,
              color: hasValue
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant),
          style: theme.textTheme.bodySmall?.copyWith(
            color: hasValue
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
            fontWeight: hasValue ? FontWeight.bold : FontWeight.normal,
          ),
          selectedItemBuilder: (context) {
            return [
              // Logic to show null item? No, value is T?.
              // We just map items.
              // If value is null, hint is shown.
              // If value matches, selectedItemBuilder index is used.
              // Wait, SelectedItemBuilder requires mapping ALL items including null if items has it?
              // The original impl had custom selectedItemBuilder.

              // Simplification: Standard builder.
              ...[null, ...items].map((item) {
                if (item == null) {
                  return Text(hint,
                      style:
                          TextStyle(color: theme.colorScheme.onSurfaceVariant));
                }
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(labelBuilder(item as T),
                      overflow: TextOverflow.ellipsis),
                );
              }),
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
    String allLabel = 'Todos',
    required T? value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    final hasValue = value != null;
    final previewItems = items.take(4).map(labelBuilder).toList();
    final previewText = previewItems.isEmpty
        ? 'Sin opciones disponibles'
        : '${items.length} opciones • ${previewItems.join(', ')}';

    return Container(
      height: 32, // Sleek height
      decoration: BoxDecoration(
        color: hasValue
            ? theme.colorScheme.primaryContainer.withOpacity(0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              hasValue ? Colors.transparent : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Tooltip(
        message: previewText,
        waitDuration: const Duration(milliseconds: 400),
        child: DropdownMenu<T?>(
          width: 200,
          initialSelection: value,
          hintText: hint,
          textStyle: theme.textTheme.bodySmall?.copyWith(
            color: hasValue
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
            fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
          ),
          menuHeight: 300,
          enableFilter: true,
          requestFocusOnTap: true,
          inputDecorationTheme: InputDecorationTheme(
            isDense: true,
            contentPadding: const EdgeInsets.only(left: 12, right: 8),
            border: InputBorder.none,
            constraints: const BoxConstraints(maxHeight: 32),
            hintStyle: theme.textTheme.bodySmall?.copyWith(
              color: hasValue
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailingIcon: Icon(Icons.arrow_drop_down,
              size: 18,
              color: hasValue
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant),
          selectedTrailingIcon: Icon(Icons.arrow_drop_up,
              size: 18,
              color: hasValue
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant),
          dropdownMenuEntries: [
            DropdownMenuEntry<T?>(
              value: null,
              label: allLabel,
              style: ButtonStyle(
                textStyle: WidgetStateProperty.all(theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary)),
              ),
            ),
            ...items.map((item) => DropdownMenuEntry<T?>(
                  value: item,
                  label: labelBuilder(item),
                  style: ButtonStyle(
                    textStyle:
                        WidgetStateProperty.all(theme.textTheme.bodySmall),
                  ),
                )),
          ],
          onSelected: onChanged,
        ),
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      _selectedCategoryId = null;
      _selectedSupplierId = null;
      _selectedBrandId = null;
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

  bool _isColumnVisible(ProductTableColumn column) {
    return _visibleColumns.contains(column);
  }

  Future<void> _toggleColumn(ProductTableColumn column, bool isVisible) async {
    setState(() {
      if (isVisible) {
        _visibleColumns.add(column);
      } else {
        _visibleColumns.remove(column);
      }
      _visibleColumns.add(ProductTableColumn.product);
    });
    await _saveColumnPreferences();
  }

  Future<void> _resetColumnPreferences() async {
    setState(() {
      _visibleColumns = {
        ProductTableColumn.product,
        ProductTableColumn.sku,
        ProductTableColumn.category,
        ProductTableColumn.stock,
        ProductTableColumn.price,
        ProductTableColumn.cost,
      };
    });
    await _saveColumnPreferences();
  }

  void _showColumnCustomizer() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Columnas visibles'),
              content: SizedBox(
                width: 340,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _columnOrder.map((column) {
                      final isLocked = column == ProductTableColumn.product;
                      final isChecked = _isColumnVisible(column);
                      return CheckboxListTile(
                        value: isChecked,
                        onChanged: isLocked
                            ? null
                            : (value) async {
                                if (value == null) return;
                                await _toggleColumn(column, value);
                                setModalState(() {});
                              },
                        title: Text(column.label),
                        subtitle:
                            isLocked ? const Text('Siempre visible') : null,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await _resetColumnPreferences();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Restablecer'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
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
                            if (_detailPaneWidth > constraints.maxWidth * 0.6) {
                              _detailPaneWidth = constraints.maxWidth * 0.6;
                            }
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
    final isLowStock = product.tracksInventory &&
        stockQty > 0 &&
        stockQty <= product.minStockLevel;
    final isOutOfStock = product.tracksInventory && stockQty <= 0;

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
            // Thumbnail - hover for 2 seconds to show larger image
            Tooltip(
              waitDuration: const Duration(seconds: 2),
              preferBelow: false,
              verticalOffset: 60,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              richMessage: product.imageUrl != null
                  ? WidgetSpan(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          product.imageUrl!,
                          width: 250,
                          height: 250,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            width: 250,
                            height: 250,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image, size: 48),
                          ),
                        ),
                      ),
                    )
                  : const TextSpan(text: 'Sin imagen'),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
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
            SizedBox(
              width: 92,
              child: Align(
                alignment: Alignment.centerRight,
                child: product.tracksInventory
                    ? Text(
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
                      )
                    : _buildStockBadge(theme, product),
              ),
            ),

            // Price
            SizedBox(
              width: _isColumnVisible(ProductTableColumn.cost) ? 100 : 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ChileanUtils.formatCurrency(product.price),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  if (_isColumnVisible(ProductTableColumn.cost))
                    Text(
                      ChileanUtils.formatCurrency(product.cost),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        childAspectRatio: 0.72,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
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
          if (_isColumnVisible(ProductTableColumn.sku))
            _buildHeaderCell(
              theme,
              'SKU',
              flex: 2,
              sortOptionAsc: ProductSortOption.skuAsc,
              sortOptionDesc: ProductSortOption.skuDesc,
            ),
          if (_isColumnVisible(ProductTableColumn.category))
            _buildHeaderCell(theme, 'Categoría',
                flex: 2), // Category sort not yet explicitly defined in Enum
          if (_isColumnVisible(ProductTableColumn.stock))
            _buildHeaderCell(
              theme,
              'Stock',
              flex: 1,
              align: TextAlign.center,
              sortOptionAsc: ProductSortOption.stockAsc,
              sortOptionDesc: ProductSortOption.stockDesc,
            ),
          if (_isColumnVisible(ProductTableColumn.price))
            _buildHeaderCell(
              theme,
              'Precio',
              flex: 1,
              align: TextAlign.right,
              sortOptionAsc: ProductSortOption.priceAsc,
              sortOptionDesc: ProductSortOption.priceDesc,
            ),
          if (_isColumnVisible(ProductTableColumn.cost))
            _buildHeaderCell(
              theme,
              'Costo',
              flex: 1,
              align: TextAlign.right,
            ),
          if (_isColumnVisible(ProductTableColumn.margin))
            _buildHeaderCell(
              theme,
              'Margen',
              flex: 1,
              align: TextAlign.right,
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
                      // Thumbnail - hover for 2 seconds to show larger image
                      Tooltip(
                        waitDuration: const Duration(seconds: 2),
                        preferBelow: false,
                        verticalOffset: 50,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        richMessage: product.imageUrl != null
                            ? WidgetSpan(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    product.imageUrl!,
                                    width: 250,
                                    height: 250,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 250,
                                      height: 250,
                                      color: theme.colorScheme.surfaceContainerHighest,
                                      child: const Icon(Icons.broken_image,
                                          size: 48),
                                    ),
                                  ),
                                ),
                              )
                            : const TextSpan(text: 'Sin imagen'),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
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
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  product.brand!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // SKU
                if (_isColumnVisible(ProductTableColumn.sku))
                  Expanded(
                    flex: 2,
                    child: SelectableText(
                      // Make SKU copyable
                      product.sku,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                // Category
                if (_isColumnVisible(ProductTableColumn.category))
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
                if (_isColumnVisible(ProductTableColumn.stock))
                  Expanded(
                    flex: 1,
                    child: _buildStockBadge(theme, product),
                  ),
                // Price
                if (_isColumnVisible(ProductTableColumn.price))
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
                // Cost
                if (_isColumnVisible(ProductTableColumn.cost))
                  Expanded(
                    flex: 1,
                    child: Text(
                      ChileanUtils.formatCurrency(product.cost),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                // Margin
                if (_isColumnVisible(ProductTableColumn.margin))
                  Expanded(
                    flex: 1,
                    child: _buildMarginCell(theme, product),
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
            onPressed: () => _openBulkEditWorkspace(useSelection: true),
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('Editar lote'),
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

  Widget _buildStockBadge(ThemeData theme, Product product,
      {bool isGrid = false}) {
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

    if (!product.tracksInventory) {
      return Center(
        child: Tooltip(
          message: 'Consumible de taller: no maneja inventario',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'N/A',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                fontSize: 10,
              ),
            ),
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

    Color textColor;

    if (product.isOutOfStock) {
      textColor = theme.colorScheme.error;
    } else if (product.isLowStock) {
      textColor = Colors.deepOrange;
    } else {
      textColor = theme.colorScheme.primary;
    }

    if (isGrid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'STOCK',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 10,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
          ),
          Text(
            '${product.inventoryQty}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
            maxLines: 1,
          ),
        ],
      );
    }

    // Traditional table layout
    return Center(
      child: Text(
        '${product.inventoryQty}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMarginCell(ThemeData theme, Product product) {
    // Calculamos el margen con IVA incluido. El neto se divide por 1.19.
    final netPrice = product.price / 1.19;
    final margin = netPrice - product.cost;
    final marginPct = product.cost > 0 ? margin / product.cost : null;
    final isNegative = margin < 0;

    return Tooltip(
      message: marginPct == null
          ? 'Sin margen'
          : 'Margen ${(marginPct * 100).toStringAsFixed(1)}%',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ChileanUtils.formatCurrency(margin),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: isNegative
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface,
            ),
          ),
          if (marginPct != null)
            Text(
              '${(marginPct * 100).toStringAsFixed(1)}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
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
    // Save current state to service before navigating
    _saveCurrentState();

    final result = await context.push('/inventory/products/${product.id}/edit');
    if (!mounted) return;

    // Always restore state when coming back (even without saving)
    _shouldRestoreState = true;
    _restoreSavedState();

    // Reload products; force refresh only if a save occurred
    _loadProducts(
      forceRefresh: result == true,
      preserveState: true,
    );
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
          // Preserve pagination after delete
          _loadProducts(forceRefresh: true, preserveState: true);
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
    final hasNoImage = product.imageUrl == null || product.imageUrl!.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _handleProductAction('edit', product),
          hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
          highlightColor: theme.colorScheme.onSurface.withValues(alpha: 0.02),
          splashColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Superior Image Section (Landscape)
              AspectRatio(
                aspectRatio: 1.33,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        border: Border(
                          bottom: BorderSide(
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: hasNoImage
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inventory_2_outlined,
                                    size: 40,
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.4)),
                              ],
                            )
                          : Image.network(
                              product.imageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                  Icons.broken_image,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.4)),
                            ),
                    ),
                    if (!product.isActive)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: theme.colorScheme.error
                                    .withValues(alpha: 0.2)),
                          ),
                          child: Text('Inactivo',
                              style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    if (product.isSet)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('SET',
                              style: TextStyle(
                                  color: theme.colorScheme.onPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand and Category
                      Text(
                        [
                          product.brand ?? 'Genérico',
                          product.categoryName ?? 'Sin categoría'
                        ].where((e) => e.isNotEmpty).join(' • ').toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),

                      // Name
                      Expanded(
                        child: Tooltip(
                          message: product.name,
                          child: Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),

                      if (product.sku.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'SKU: ${product.sku}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                      // Price & Stock
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  ChileanUtils.formatCurrency(product.price),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_isColumnVisible(ProductTableColumn.cost))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      'Costo: ${ChileanUtils.formatCurrency(product.cost)}',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.error,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStockBadge(theme, product, isGrid: true),
                        ],
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
                              color: theme.colorScheme.surfaceContainerHighest,
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
                              allLabel: 'Todas',
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
                              allLabel: 'Todos',
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

class _ModernFilterChip extends StatefulWidget {
  final ThemeData theme;
  final String label;
  final bool isActive;
  final void Function(BuildContext context, LayerLink link) onTap;

  const _ModernFilterChip({
    required this.theme,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_ModernFilterChip> createState() => _ModernFilterChipState();
}

class _ModernFilterChipState extends State<_ModernFilterChip> {
  final LayerLink _layerLink = LayerLink();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onTap(context, _layerLink),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: widget.isActive
                  ? LinearGradient(
                      colors: [
                        widget.theme.colorScheme.primary.withOpacity(0.15),
                        widget.theme.colorScheme.primary.withOpacity(0.08),
                      ],
                    )
                  : null,
              color: widget.isActive
                  ? null
                  : widget.theme.colorScheme.surfaceContainerHighest
                      .withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.isActive
                    ? widget.theme.colorScheme.primary.withOpacity(0.4)
                    : widget.theme.colorScheme.outlineVariant.withOpacity(0.6),
                width: widget.isActive ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: widget.theme.textTheme.labelMedium?.copyWith(
                    color: widget.isActive
                        ? widget.theme.colorScheme.primary
                        : widget.theme.colorScheme.onSurfaceVariant,
                    fontWeight:
                        widget.isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: widget.isActive
                      ? widget.theme.colorScheme.primary
                      : widget.theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopSearchableFilterList<T> extends StatefulWidget {
  final List<T> items;
  final String Function(T) labelBuilder;
  final String? selectedId;
  final String? Function(T) idExtractor;
  final ValueChanged<String?> onSelected;

  const _DesktopSearchableFilterList({
    required this.items,
    required this.labelBuilder,
    required this.selectedId,
    required this.idExtractor,
    required this.onSelected,
  });

  @override
  State<_DesktopSearchableFilterList<T>> createState() =>
      _DesktopSearchableFilterListState<T>();
}

class _DesktopSearchableFilterListState<T>
    extends State<_DesktopSearchableFilterList<T>> {
  late TextEditingController _searchCtrl;
  late List<T> _filtered;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _filtered = widget.items;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _normalizeText(String text) {
    if (text.isEmpty) return text;
    String normalized = text.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r'[áàäâ]'), 'a');
    normalized = normalized.replaceAll(RegExp(r'[éèëê]'), 'e');
    normalized = normalized.replaceAll(RegExp(r'[íìïî]'), 'i');
    normalized = normalized.replaceAll(RegExp(r'[óòöô]'), 'o');
    normalized = normalized.replaceAll(RegExp(r'[úùüû]'), 'u');
    normalized = normalized.replaceAll(RegExp(r'[ñ]'), 'n');
    normalized = normalized.replaceAll(RegExp(r'[ç]'), 'c');
    return normalized;
  }

  void _filter(String query) {
    final normalizedQuery = _normalizeText(query);
    setState(() {
      _filtered = widget.items.where((e) {
        final normalizedLabel = _normalizeText(widget.labelBuilder(e));
        return normalizedLabel.contains(normalizedQuery);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _filter,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Buscar...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                title: const Text('Todos', style: TextStyle(fontSize: 14)),
                dense: true,
                onTap: () => widget.onSelected(null),
                selected: widget.selectedId == null,
              ),
              ..._filtered.map((item) {
                final id = widget.idExtractor(item);
                return ListTile(
                  title: Text(widget.labelBuilder(item),
                      style: const TextStyle(fontSize: 14)),
                  dense: true,
                  onTap: () => widget.onSelected(id),
                  selected: widget.selectedId == id,
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}
