import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/supplier.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
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

  const ProductListPage({
    super.key,
    this.initialCategoryId,
    this.initialSupplierId,
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

  bool _isLoading = true;
  String _searchTerm = '';
  String? _selectedCategoryId;
  String? _selectedSupplierId;
  bool _showLowStockOnly = false;
  bool _showInactive = false;
  ProductViewMode _viewMode = ProductViewMode.table;

  @override
  void initState() {
    super.initState();
    final database = Provider.of<DatabaseService>(context, listen: false);
    _inventoryService = inventory_services.InventoryService(database);
    _categoryService = CategoryService(database);
    _purchaseService = PurchaseService(database);

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
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableScrollController.dispose();
    super.dispose();
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
    setState(() => _isLoading = true);
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
          .where((product) => product.isLowStock || product.isOutOfStock)
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
      child: Column(
        children: [
          _buildHeader(theme),
          const SizedBox(height: 8),
          _buildFilters(theme),
          if (!_isLoading && _products.isNotEmpty) _buildSummary(theme),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Productos',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Administra tu catálogo, stock y márgenes',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const Spacer(),
          SegmentedButton<ProductViewMode>(
            segments: const [
              ButtonSegment<ProductViewMode>(
                value: ProductViewMode.table,
                label: Text('Tabla'),
                icon: Icon(Icons.table_rows_outlined),
              ),
              ButtonSegment<ProductViewMode>(
                value: ProductViewMode.cards,
                label: Text('Tarjetas'),
                icon: Icon(Icons.dashboard_outlined),
              ),
            ],
            selected: <ProductViewMode>{_viewMode},
            onSelectionChanged: (selection) =>
                _onViewModeChanged(selection.first),
          ),
          const SizedBox(width: 16),
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
          const SizedBox(width: 12),
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
    );
  }

  Widget _buildFilters(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          SearchBarWidget(
            controller: _searchController,
            hintText: 'Buscar por nombre, SKU, marca o categoría…',
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  value: _selectedCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Todas las categorías'),
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
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  value: _selectedSupplierId,
                  decoration: const InputDecoration(
                    labelText: 'Proveedor',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Todos los proveedores'),
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
              FilterChip(
                avatar: Icon(
                  Icons.warning_amber_outlined,
                  color: _showLowStockOnly
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
                selectedColor:
                    theme.colorScheme.errorContainer.withOpacity(0.3),
                label: const Text('Solo stock crítico'),
                selected: _showLowStockOnly,
                onSelected: _onLowStockToggle,
              ),
              FilterChip(
                avatar: Icon(
                  Icons.visibility_off_outlined,
                  color: _showInactive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                label: const Text('Mostrar inactivos'),
                selected: _showInactive,
                onSelected: _onInactiveToggle,
              ),
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh_outlined),
                onPressed: _loadProducts,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(ThemeData theme) {
    final lowStock = _products.where((p) => p.isLowStock).length;
    final outOfStock = _products.where((p) => p.isOutOfStock).length;
    final inactive = _products.where((p) => !p.isActive).length;
    final inventoryValue = _products.fold<double>(
      0.0,
      (total, product) => total + product.inventoryValue,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Wrap(
            spacing: 24,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildStatTile(
                theme,
                icon: Icons.inventory_2_outlined,
                color: theme.colorScheme.primary,
                label: 'Productos totales',
                value: _products.length.toString(),
              ),
              _buildStatTile(
                theme,
                icon: Icons.warning_amber_outlined,
                color: theme.colorScheme.error,
                label: 'Stock crítico',
                value: lowStock.toString(),
              ),
              _buildStatTile(
                theme,
                icon: Icons.block_outlined,
                color: theme.colorScheme.error,
                label: 'Sin stock',
                value: outOfStock.toString(),
              ),
              _buildStatTile(
                theme,
                icon: Icons.visibility_off_outlined,
                color: theme.colorScheme.onSurfaceVariant,
                label: 'Inactivos',
                value: inactive.toString(),
              ),
              _buildStatTile(
                theme,
                icon: Icons.attach_money,
                color: theme.colorScheme.tertiary,
                label: 'Valor inventario',
                value: ChileanUtils.formatCurrency(inventoryValue),
              ),
              _buildStatTile(
                theme,
                icon: Icons.filter_alt_outlined,
                color: theme.colorScheme.primary,
                label: 'Mostrando',
                value: _filteredProducts.length.toString(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredProducts.isEmpty) {
      return _buildEmptyState(theme);
    }

    final scrollable = _viewMode == ProductViewMode.table
        ? _buildTableView(theme)
        : _buildCardGrid(theme);

    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: scrollable,
    );
  }

  Widget _buildTableView(ThemeData theme) {
    return ListView.separated(
      controller: _tableScrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: _filteredProducts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        return _buildTableRow(product, theme);
      },
    );
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

  Widget _buildTableRow(Product product, ThemeData theme) {
    final categoryName = _resolveCategoryName(product);
    final priceText = ChileanUtils.formatCurrency(product.price);
    final costText = ChileanUtils.formatCurrency(product.cost);
    final marginPercent = product.cost > 0
        ? ((product.price - product.cost) / product.cost) * 100
        : 0;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openEditor(product),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          color: theme.colorScheme.surface,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 88,
                height: 88,
                child: ImageService.buildProductImage(
                  imageUrl: product.imageUrl,
                  size: 88,
                  isListThumbnail: true,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!product.isActive)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Chip(
                            label: const Text('Inactivo'),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: theme.colorScheme.surfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildInfoPill(
                        theme,
                        icon: Icons.confirmation_number_outlined,
                        label: 'SKU ${product.sku}',
                      ),
                      if (categoryName != null)
                        _buildInfoPill(
                          theme,
                          icon: Icons.category_outlined,
                          label: categoryName,
                        ),
                      if (product.supplierName != null &&
                          product.supplierName!.isNotEmpty)
                        _buildInfoPill(
                          theme,
                          icon: Icons.business_outlined,
                          label: product.supplierName!,
                        ),
                      if (product.brand?.isNotEmpty ?? false)
                        _buildInfoPill(
                          theme,
                          icon: Icons.directions_bike_outlined,
                          label: product.brand!,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    priceText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Costo $costText',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
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
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildStockChip(product, theme),
                const SizedBox(height: 8),
                Text(
                  'Stock: ${product.inventoryQty}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Editar producto',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _openEditor(product),
            ),
          ],
        ),
      ),
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
}
