import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/supplier.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/services/remote_scanner_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../../purchases/services/purchase_service.dart';
import '../models/category_models.dart';
import '../models/inventory_models.dart';
import '../services/category_service.dart';
import '../services/inventory_service.dart' as inventory_services;

enum ProductViewMode { table, cards }

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
  static const double _minDetailPaneWidth = 300.0;
  static const double _maxDetailPaneWidth = 600.0;

  bool _isLoading = true;
  String _searchTerm = '';
  String? _selectedCategoryId;
  String? _selectedSupplierId;
  bool _showLowStockOnly = false;
  bool _showInactive = false;
  ProductViewMode _viewMode = ProductViewMode.table;
  Product? _selectedProduct; // For split-pane detail view
  
  // Pagination
  int _currentPage = 1;
  int _itemsPerPage = 200;
  int get _totalPages => (_filteredProducts.length / _itemsPerPage).ceil();
  List<Product> get _paginatedProducts {
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, _filteredProducts.length);
    return _filteredProducts.sublist(startIndex, endIndex);
  }
  
  StreamSubscription? _scanSubscription;
  final _remoteScannerService = RemoteScannerService();
  bool _scannerEnabled = false;

  @override
  void initState() {
    super.initState();
    _inventoryService = Provider.of<inventory_services.InventoryService>(context, listen: false);
    _categoryService = Provider.of<CategoryService>(context, listen: false);
    _purchaseService = Provider.of<PurchaseService>(context, listen: false);

    // Don't set initial category/supplier until categories are loaded
    _loadCategories().then((_) {
      // After categories load, validate and set the initial category filter
      if (widget.initialCategoryId != null && mounted) {
        final categoryExists =
            _categories.any((c) => c.id == widget.initialCategoryId);
        if (categoryExists) {
          setState(() {
            _selectedCategoryId = widget.initialCategoryId;
          });
          _applyFilters();
        }
      }

      // Set initial supplier filter if provided
      if (widget.initialSupplierId != null && mounted) {
        setState(() {
          _selectedSupplierId = widget.initialSupplierId;
        });
        _applyFilters();
      }
    });

    _loadSuppliers();
    _loadProducts();
    
    // Listen for barcode scans
    _scanSubscription = _remoteScannerService.scanStream.listen((scan) {
      if (mounted) {
        _handleBarcodeScan(scan.barcode);
      }
    });
  }

  @override
  void didUpdateWidget(ProductListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload products when refresh token changes (from import page)
    if (widget.refreshToken != null && widget.refreshToken != oldWidget.refreshToken) {
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
  
  Future<void> _toggleScanner() async {
    try {
      if (_scannerEnabled) {
        await _remoteScannerService.stopListening();
        setState(() => _scannerEnabled = false);
      } else {
        await _remoteScannerService.startListening();
        setState(() => _scannerEnabled = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📱 Escáner remoto activado'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error con escáner: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _handleBarcodeScan(String barcode) async {
    // Search for product by SKU
    final product = _products.cast<Product?>().firstWhere(
      (p) => p!.sku.toLowerCase() == barcode.toLowerCase(),
      orElse: () => null,
    );
    
    if (product != null) {
      // Navigate to product edit page
      if (mounted) {
        context.push('/inventory/products/${product.id}/edit');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Producto encontrado: ${product.name}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
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

  Future<void> _loadProducts() async {
    if (!mounted) return;
    
    // 🚀 INSTANT RENDER: Show cached data immediately if available
    if (_inventoryService.hasProductsCache && _products.isEmpty) {
      setState(() {
        _products = _inventoryService.cachedProducts;
        _applyFilters();
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = true);
    }
    
    try {
      final products = await _inventoryService.getProducts(
        categoryId: _selectedCategoryId,
        lowStockOnly: _showLowStockOnly,
      );

      if (!mounted) return;
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

  void _applyFilters() {
    List<Product> filtered = List<Product>.from(_products);

    if (_selectedCategoryId != null && _selectedCategoryId!.isNotEmpty) {
      filtered = filtered
          .where((product) => product.categoryId == _selectedCategoryId)
          .toList();
    }

    if (_selectedSupplierId != null && _selectedSupplierId!.isNotEmpty) {
      filtered = filtered
          .where((product) => product.supplierId == _selectedSupplierId)
          .toList();
    }

    if (_showLowStockOnly) {
      filtered = filtered
          .where((product) => !product.isService && (product.isLowStock || product.isOutOfStock))
          .toList();
    }

    if (!_showInactive) {
      filtered = filtered.where((product) => product.isActive).toList();
    }

    if (_searchTerm.isNotEmpty) {
      final query = _searchTerm.toLowerCase();
      filtered = filtered.where((product) {
        final matchesName = product.name.toLowerCase().contains(query);
        final matchesSku = product.sku.toLowerCase().contains(query);
        final matchesBrand =
            product.brand?.toLowerCase().contains(query) ?? false;
        final matchesModel =
            product.model?.toLowerCase().contains(query) ?? false;
        final matchesCategory =
            _resolveCategoryName(product)?.toLowerCase().contains(query) ??
                false;
        return matchesName ||
            matchesSku ||
            matchesBrand ||
            matchesModel ||
            matchesCategory;
      }).toList();
    }

    _filteredProducts = filtered;
    
    // Reset to page 1 when filters change
    _currentPage = 1;
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchTerm = value.trim();
      _applyFilters();
    });
  }

  void _onCategoryChanged(String? categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
      _applyFilters();
    });
  }

  void _onSupplierChanged(String? supplierId) {
    setState(() {
      _selectedSupplierId = supplierId;
      _applyFilters();
    });
  }

  void _onLowStockToggle(bool value) {
    setState(() {
      _showLowStockOnly = value;
      _applyFilters();
    });
  }

  void _onInactiveToggle(bool value) {
    setState(() {
      _showInactive = value;
      _applyFilters();
    });
  }

  void _onViewModeChanged(ProductViewMode mode) {
    if (_viewMode == mode) return;
    setState(() => _viewMode = mode);
  }

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

    if (_filteredProducts.isEmpty) {
      // Maintain same layout structure as non-empty view
      if (_viewMode == ProductViewMode.table) {
        return Column(
          children: [
            _buildCleanHeader(theme),
            Expanded(
              child: _buildEmptyState(theme),
            ),
          ],
        );
      } else {
        // Card view with scrollable layout
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildCleanHeader(theme),
              _buildEmptyState(theme),
            ],
          ),
        );
      }
    }

    // For table view, use custom scrolling structure
    if (_viewMode == ProductViewMode.table) {
      return _buildTableViewWithScrollableHeader(theme);
    }

    // For card view, wrap header + content in scrollable
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildCleanHeader(theme),
          SizedBox(
            height: MediaQuery.of(context).size.height - 300,
            child: _buildCardGridScrollable(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildTableViewWithScrollableHeader(ThemeData theme) {
    return Row(
      children: [
        // Main area with fixed header and table header
        Expanded(
          child: Column(
            children: [
              // Fixed top bar
              _buildCleanHeader(theme),
              // Fixed table header
              _buildTableHeader(theme),
              // Scrollable table rows only
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                  ),
                  child: ListView.builder(
                    controller: _tableScrollController,
                    itemCount: _paginatedProducts.length,
                    itemBuilder: (context, index) {
                      final product = _paginatedProducts[index];
                      final isSelected = _selectedProduct?.id == product.id;
                      return _buildZohoTableRow(product, theme, isSelected);
                    },
                  ),
                ),
              ),
              // Pagination controls
              _buildPaginationControls(theme),
            ],
          ),
        ),
        // Split-pane detail view
        if (_selectedProduct != null)
          _buildDetailPane(theme),
      ],
    );
  }

  Widget _buildCleanHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title and primary actions
          Row(
            children: [
              Expanded(
                child: Text(
                  'Productos',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // View mode toggle
              SegmentedButton<ProductViewMode>(
                segments: const [
                  ButtonSegment<ProductViewMode>(
                    value: ProductViewMode.table,
                    icon: Icon(Icons.table_rows_outlined, size: 16),
                  ),
                  ButtonSegment<ProductViewMode>(
                    value: ProductViewMode.cards,
                    icon: Icon(Icons.dashboard_outlined, size: 16),
                  ),
                ],
                selected: <ProductViewMode>{_viewMode},
                onSelectionChanged: (selection) =>
                    _onViewModeChanged(selection.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: MaterialStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Scanner button
              IconButton(
                onPressed: _toggleScanner,
                icon: Icon(
                  _scannerEnabled ? Icons.qr_code_scanner : Icons.qr_code_scanner_outlined,
                  size: 18,
                ),
                tooltip: _scannerEnabled ? 'Desactivar Escáner' : 'Activar Escáner',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  backgroundColor: _scannerEnabled 
                      ? Colors.green.withOpacity(0.1) 
                      : null,
                  foregroundColor: _scannerEnabled ? Colors.green : null,
                ),
              ),
              const SizedBox(width: 8),
              // Import button
              AppButton(
                text: 'Importar',
                icon: Icons.file_upload_outlined,
                type: ButtonType.outline,
                onPressed: () {
                  context.push('/inventory/products/import').then((_) {
                    _loadProducts();
                  });
                },
              ),
              const SizedBox(width: 8),
              // New product button
              AppButton(
                text: 'Nuevo producto',
                icon: Icons.add,
                onPressed: () {
                  context.push('/inventory/products/new').then((_) {
                    _loadProducts();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Search and filters row
          Row(
            children: [
              // Search bar
              Expanded(
                flex: 2,
                child: SearchBarWidget(
                  controller: _searchController,
                  hintText: 'Buscar por nombre, SKU, marca o categoría…',
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: 8),
              // Category filter
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _selectedCategoryId,
                  decoration: InputDecoration(
                    labelText: 'Categoría',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    isDense: true,
                  ),
                  style: theme.textTheme.bodySmall,
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Todas'),
                    ),
                    ..._categories.map((category) {
                      return DropdownMenuItem<String>(
                        value: category.id,
                        child: Text(category.name),
                      );
                    }),
                  ],
                  onChanged: _onCategoryChanged,
                ),
              ),
              const SizedBox(width: 8),
              // Supplier filter
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _selectedSupplierId,
                  decoration: InputDecoration(
                    labelText: 'Proveedor',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    isDense: true,
                  ),
                  style: theme.textTheme.bodySmall,
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    ..._suppliers.map((supplier) {
                      return DropdownMenuItem<String>(
                        value: supplier.id,
                        child: Text(supplier.name),
                      );
                    }),
                  ],
                  onChanged: _onSupplierChanged,
                ),
              ),
              const SizedBox(width: 8),
              // Filter chips
              FilterChip(
                avatar: Icon(
                  Icons.warning_amber_outlined,
                  size: 16,
                  color: _showLowStockOnly
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
                label: const Text('Stock crítico'),
                labelStyle: theme.textTheme.labelSmall,
                selected: _showLowStockOnly,
                onSelected: _onLowStockToggle,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              ),
              const SizedBox(width: 6),
              FilterChip(
                avatar: Icon(
                  Icons.visibility_off_outlined,
                  size: 16,
                  color: _showInactive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                label: const Text('Inactivos'),
                labelStyle: theme.textTheme.labelSmall,
                selected: _showInactive,
                onSelected: _onInactiveToggle,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              ),
              const SizedBox(width: 6),
              // Refresh button
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh_outlined, size: 18),
                onPressed: _loadProducts,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          // Summary stats (compact)
          if (!_isLoading && _products.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildCompactSummary(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactSummary(ThemeData theme) {
    // Exclude services from stock counts
    final productsOnly = _products.where((p) => !p.isService);
    final lowStock = productsOnly.where((p) => p.isLowStock).length;
    final outOfStock = productsOnly.where((p) => p.isOutOfStock).length;
    final inventoryValue = productsOnly.fold<double>(
      0.0,
      (total, product) => total + product.inventoryValue,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          _buildCompactStat(
            theme,
            icon: Icons.inventory_2_outlined,
            label: 'Total',
            value: _products.length.toString(),
          ),
          const SizedBox(width: 20),
          _buildCompactStat(
            theme,
            icon: Icons.warning_amber_outlined,
            label: 'Crítico',
            value: lowStock.toString(),
            color: lowStock > 0 ? theme.colorScheme.error : null,
          ),
          const SizedBox(width: 20),
          _buildCompactStat(
            theme,
            icon: Icons.block_outlined,
            label: 'Sin stock',
            value: outOfStock.toString(),
            color: outOfStock > 0 ? theme.colorScheme.error : null,
          ),
          const Spacer(),
          _buildCompactStat(
            theme,
            icon: Icons.attach_money,
            label: 'Valor',
            value: ChileanUtils.formatCurrency(inventoryValue),
            color: theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStat(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContentArea(ThemeData theme) {
    return _viewMode == ProductViewMode.table
        ? _buildZohoTableView(theme)
        : _buildCardGridScrollable(theme);
  }

  Widget _buildZohoTableView(ThemeData theme) {
    return Row(
      children: [
        // Main table view
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
            ),
            child: Column(
              children: [
                _buildTableHeader(theme),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadProducts,
                    child: ListView.builder(
                      controller: _tableScrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        final isSelected = _selectedProduct?.id == product.id;
                        return _buildZohoTableRow(product, theme, isSelected);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Split-pane detail view
        if (_selectedProduct != null)
          _buildDetailPane(theme),
      ],
    );
  }

  Widget _buildCardGridScrollable(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: _buildCardGrid(theme),
    );
  }

  Widget _buildTableHeader(ThemeData theme) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.8),
          ),
        ),
      ),
      child: Row(
        children: [
          // Checkbox column
          SizedBox(
            width: 48,
            child: Checkbox(
              value: false,
              onChanged: (value) {
                // TODO: Select all
              },
              visualDensity: VisualDensity.compact,
            ),
          ),
          // Thumbnail column
          const SizedBox(width: 60),
          // Name column
          Expanded(
            flex: 3,
            child: Text(
              'Nombre',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          // SKU column
          SizedBox(
            width: 140,
            child: Text(
              'SKU',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          // Price column
          SizedBox(
            width: 140,
            child: Text(
              'Precio',
              textAlign: TextAlign.right,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          // Stock column
          SizedBox(
            width: 120,
            child: Text(
              'Stock',
              textAlign: TextAlign.right,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildZohoTableRow(Product product, ThemeData theme, bool isSelected) {
    final priceText = ChileanUtils.formatCurrency(product.price);
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedProduct = isSelected ? null : product;
        });
      },
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected 
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : null,
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            // Checkbox
            SizedBox(
              width: 48,
              child: Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    _selectedProduct = value! ? product : null;
                  });
                },
                visualDensity: VisualDensity.compact,
              ),
            ),
            // Thumbnail
            SizedBox(
              width: 60,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: ImageService.buildProductImage(
                    imageUrl: product.imageUrl,
                    size: 36,
                    isListThumbnail: true,
                  ),
                ),
              ),
            ),
            // Name
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      product.name,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (product.categoryName != null && product.categoryName!.isNotEmpty)
                      Text(
                        product.categoryName!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
            // SKU
            SizedBox(
              width: 140,
              child: Text(
                product.sku,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Price
            SizedBox(
              width: 140,
              child: Text(
                priceText,
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            // Stock (show dash for services)
            SizedBox(
              width: 120,
              child: product.isService
                  ? Text(
                      '-',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${product.inventoryQty}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (product.isLowStock)
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: theme.colorScheme.error,
                    )
                  else if (product.isOutOfStock)
                    Icon(
                      Icons.block,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPane(ThemeData theme) {
    final product = _selectedProduct!;
    // Format prices with $ at the beginning
    final priceText = '\$ ${ChileanUtils.formatCurrency(product.price).replaceAll('\$', '').trim()}';
    final costText = '\$ ${ChileanUtils.formatCurrency(product.cost).replaceAll('\$', '').trim()}';
    final marginPercent = product.cost > 0
        ? ((product.price - product.cost) / product.cost) * 100
        : 0;
    
    return Container(
      width: _detailPaneWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Main content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with close button
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                  child: Text(
                    'Detalles del Producto',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _selectedProduct = null;
                    });
                  },
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product image
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ImageService.buildProductImage(
                        imageUrl: product.imageUrl,
                        size: 200,
                        isListThumbnail: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Product name
                  Text(
                    product.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'SKU: ${product.sku}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: product.sku));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('SKU copiado'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.copy,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!product.isActive) ...[
                    const SizedBox(height: 8),
                    Chip(
                      label: const Text('Inactivo'),
                      backgroundColor: theme.colorScheme.errorContainer,
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  // Sections layout - two columns when wide enough
                  if (_detailPaneWidth > 400)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left column: Pricing
                        Expanded(
                          child: _buildDetailSection(
                            theme,
                            title: 'Precios',
                            children: [
                              _buildDetailRow(theme, 'Precio de Venta', priceText),
                              _buildDetailRow(theme, 'Costo', costText),
                              _buildDetailRow(
                                theme,
                                'Margen',
                                '${marginPercent.toStringAsFixed(1)}%',
                                valueColor: marginPercent < 0
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.tertiary,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),
                        // Right column: Inventory (hide for services)
                        if (!product.isService)
                          Expanded(
                            child: _buildDetailSection(
                              theme,
                              title: 'Inventario',
                              children: [
                                _buildDetailRowNumeric(theme, 'Stock Actual', product.inventoryQty),
                                _buildDetailRowNumeric(theme, 'Stock Mínimo', product.minStockLevel),
                                _buildDetailRowNumeric(theme, 'Stock Máximo', product.maxStockLevel ?? 0),
                                if (product.warehouseLocation != null)
                                  _buildDetailRow(theme, 'Ubicación', product.warehouseLocation!),
                              ],
                            ),
                          )
                        else
                          const Expanded(child: SizedBox()), // Empty space for services
                      ],
                    )
                  else ...[
                    // Single column layout for narrow panes
                    _buildDetailSection(
                      theme,
                      title: 'Precios',
                      children: [
                        _buildDetailRow(theme, 'Precio de Venta', priceText),
                        _buildDetailRow(theme, 'Costo', costText),
                        _buildDetailRow(
                          theme,
                          'Margen',
                          '${marginPercent.toStringAsFixed(1)}%',
                          valueColor: marginPercent < 0
                              ? theme.colorScheme.error
                              : theme.colorScheme.tertiary,
                        ),
                      ],
                    ),
                    // Only show inventory section for products, not services
                    if (!product.isService) ...[
                      const SizedBox(height: 24),
                      _buildDetailSection(
                        theme,
                        title: 'Inventario',
                        children: [
                          _buildDetailRowNumeric(theme, 'Stock Actual', product.inventoryQty),
                          _buildDetailRowNumeric(theme, 'Stock Mínimo', product.minStockLevel),
                          _buildDetailRowNumeric(theme, 'Stock Máximo', product.maxStockLevel ?? 0),
                          if (product.warehouseLocation != null)
                            _buildDetailRow(theme, 'Ubicación', product.warehouseLocation!),
                        ],
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  // Product info section
                  _buildDetailSection(
                    theme,
                    title: 'Información',
                    children: [
                      if (product.categoryName != null)
                        _buildDetailRow(theme, 'Categoría', product.categoryName!),
                      if (product.brand != null && product.brand!.isNotEmpty)
                        _buildDetailRow(theme, 'Marca', product.brand!),
                      if (product.model != null && product.model!.isNotEmpty)
                        _buildDetailRow(theme, 'Modelo', product.model!),
                      if (product.gtin != null && product.gtin!.isNotEmpty)
                        _buildDetailRow(theme, 'GTIN', product.gtin!),
                    ],
                  ),
                  if (product.description != null && product.description!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildDetailSection(
                      theme,
                      title: 'Descripción',
                      children: [
                        Text(
                          product.description!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Action buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'Editar',
                    icon: Icons.edit_outlined,
                    type: ButtonType.outline,
                    onPressed: () => _openEditor(product),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    text: 'Ajustar Stock',
                    icon: Icons.inventory_outlined,
                    onPressed: () => _openStockAdjustment(product),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
          // Resize handle on the left edge
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _detailPaneWidth = (_detailPaneWidth - details.delta.dx).clamp(
                      _minDetailPaneWidth,
                      _maxDetailPaneWidth,
                    );
                  });
                },
                child: Container(
                  width: 8,
                  color: Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailSection(
    ThemeData theme, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildDetailRow(
    ThemeData theme,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRowNumeric(
    ThemeData theme,
    String label,
    int value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              value.toString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: valueColor,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  void _openStockAdjustment(Product product) {
    // Navigate to stock adjustment page (you can implement a dedicated page)
    // For now, just open the editor
    _openEditor(product);
  }

  Widget _buildCardGrid(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount = 2;
        if (width < 640) {
          crossAxisCount = 1;
        } else if (width < 1024) {
          crossAxisCount = 2;
        } else if (width < 1400) {
          crossAxisCount = 3;
        } else {
          crossAxisCount = 4;
        }

        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 18,
            mainAxisSpacing: 18,
            childAspectRatio: 0.86,
          ),
          itemCount: _filteredProducts.length,
          itemBuilder: (context, index) {
            final product = _filteredProducts[index];
            return _buildProductCard(product, theme);
          },
        );
      },
    );
  }

  Widget _buildProductCard(Product product, ThemeData theme) {
    final categoryName = _resolveCategoryName(product);
    final priceText = ChileanUtils.formatCurrency(product.price);
    final marginPercent = product.cost > 0
        ? ((product.price - product.cost) / product.cost) * 100
        : 0;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _openEditor(product),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: ImageService.buildProductImage(
                        imageUrl: product.imageUrl,
                        size: double.infinity,
                        isListThumbnail: false,
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _buildStockChip(product, theme),
                    ),
                    if (!product.isActive)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Chip(
                          label: const Text('Inactivo'),
                          backgroundColor:
                              theme.colorScheme.surfaceVariant.withOpacity(0.9),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'SKU ${product.sku}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (categoryName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      categoryName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (product.supplierName != null &&
                      product.supplierName!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.business_outlined,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            product.supplierName!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            priceText,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Margen ${marginPercent.toStringAsFixed(1)}%',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: marginPercent < 0
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.tertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Hide stock for services
                          if (!product.isService) ...[
                            Text(
                              'Stock ${product.inventoryQty}',
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              _stockStatusLabel(product),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ] else
                            Text(
                              'Servicio',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _openEditor(product),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final hasFilters = _searchTerm.isNotEmpty ||
        _showLowStockOnly ||
        _selectedCategoryId != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilters
                  ? Icons.search_off_outlined
                  : Icons.inventory_2_outlined,
              size: 92,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.25),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilters
                  ? 'No encontramos productos con esos filtros'
                  : 'Aún no tienes productos registrados',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters
                  ? 'Prueba ajustar la búsqueda o restablecer los filtros.'
                  : 'Crea tu primer producto para comenzar a gestionar el inventario.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            AppButton(
              text: 'Nuevo producto',
              icon: Icons.add,
              onPressed: () {
                context.push('/inventory/products/new').then((_) {
                  _loadProducts();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStockChip(Product product, ThemeData theme) {
    final color = _stockStatusColor(product, theme);
    final icon = _stockStatusIcon(product);
    final label = _stockStatusLabel(product);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPill(ThemeData theme,
      {required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _openEditor(Product product) {
    final productId = product.id;
    if (productId == null) return;
    context.push('/inventory/products/$productId/edit').then((_) {
      _loadProducts();
    });
  }

  String? _resolveCategoryName(Product product) {
    if (product.categoryName != null && product.categoryName!.isNotEmpty) {
      return product.categoryName;
    }
    if (product.categoryId == null) return null;
    final category = _categories.firstWhere(
      (c) => c.id == product.categoryId,
      orElse: () => Category(
        id: product.categoryId!,
        tenantId: '', // Display-only fallback
        name: 'Categoría sin nombre',
        fullPath: 'Categoría sin nombre',
      ),
    );
    return category.name;
  }

  String _stockStatusLabel(Product product) {
    if (product.isOutOfStock) return 'Sin stock';
    if (product.isLowStock) return 'Stock crítico';
    return 'Stock saludable';
  }

  Color _stockStatusColor(Product product, ThemeData theme) {
    if (product.isOutOfStock) return theme.colorScheme.error;
    if (product.isLowStock) return theme.colorScheme.tertiary;
    return theme.colorScheme.primary;
  }

  IconData _stockStatusIcon(Product product) {
    if (product.isOutOfStock) return Icons.block;
    if (product.isLowStock) return Icons.warning_amber_outlined;
    return Icons.check_circle_outline;
  }

  // Pagination controls
  Widget _buildPaginationControls(ThemeData theme) {
    if (_totalPages <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Page info
          Text(
            'Página $_currentPage de $_totalPages (${_filteredProducts.length} productos)',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // Navigation controls
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _currentPage > 1 ? _goToFirstPage : null,
                tooltip: 'Primera página',
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 1 ? _previousPage : null,
                tooltip: 'Página anterior',
              ),
              // Page selector dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _currentPage,
                    items: List.generate(_totalPages, (index) {
                      final pageNum = index + 1;
                      return DropdownMenuItem(
                        value: pageNum,
                        child: Text('$pageNum'),
                      );
                    }),
                    onChanged: (page) {
                      if (page != null) _goToPage(page);
                    },
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < _totalPages ? _nextPage : null,
                tooltip: 'Página siguiente',
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _currentPage < _totalPages ? _goToLastPage : null,
                tooltip: 'Última página',
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _goToFirstPage() {
    setState(() => _currentPage = 1);
  }

  void _previousPage() {
    if (_currentPage > 1) {
      setState(() => _currentPage--);
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages) {
      setState(() => _currentPage++);
    }
  }

  void _goToLastPage() {
    setState(() => _currentPage = _totalPages);
  }

  void _goToPage(int page) {
    if (page >= 1 && page <= _totalPages) {
      setState(() => _currentPage = page);
    }
  }
}
