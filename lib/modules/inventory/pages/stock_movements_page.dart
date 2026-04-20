import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/product.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../../purchases/models/purchase_invoice.dart';
import '../../purchases/services/purchase_service.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';
import '../../../shared/models/tax_treatment.dart';

import '../models/stock_movement.dart';
import '../models/stock_adjustment.dart';
import '../services/inventory_service.dart' as module_inventory;
import '../services/stock_movements_service.dart';

class StockMovementsPage extends StatefulWidget {
  const StockMovementsPage({super.key});

  @override
  State<StockMovementsPage> createState() => _StockMovementsPageState();
}

class _StockMovementsPageState extends State<StockMovementsPage> {
  String _searchQuery = '';
  String _movementTypeFilter = 'all';
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _searchController = TextEditingController();
  StockMovementsViewMode _viewMode = StockMovementsViewMode.recent;

  // Panel resizing
  static const double _minPanelWidth = 300.0;
  static const double _maxPanelWidth = 600.0;
  static const double _defaultPanelWidth = 400.0;
  double _productListWidth = _defaultPanelWidth;

  // Column widths (resizable)
  double _colProductWidth = 250.0;
  double _colDateWidth = 130.0;
  double _colTypeWidth = 80.0;
  double _colSourceWidth = 120.0;
  double _colRefWidth = 140.0;
  double _colIniWidth = 50.0;
  double _colMovWidth = 50.0;
  final double _colFinWidth = 50.0;

  static const double _minColWidth = 40.0;

  StockMovement? _selectedLinkedMovement;
  Invoice? _selectedSalesInvoice;
  PurchaseInvoice? _selectedPurchaseInvoice;
  StockAdjustmentDetail? _selectedStockAdjustment;
  bool _isLoadingLinkedDocument = false;
  String? _linkedDocumentError;

  @override
  void initState() {
    super.initState();
    _loadPanelWidth();
    // Load recent movements by default, and preload products for switching
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StockMovementsService>().loadRecentMovements();
      context.read<InventoryService>().getProducts();
    });
  }

  Future<void> _loadPanelWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedWidth = prefs.getDouble('stock_movements_panel_width');
      if (savedWidth != null) {
        setState(() {
          _productListWidth = savedWidth;
        });
      }
    } catch (e) {
      debugPrint('Error loading panel width: $e');
    }
  }

  Future<void> _savePanelWidth(double width) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('stock_movements_panel_width', width);
    } catch (e) {
      debugPrint('Error saving panel width: $e');
    }
  }

  void _updatePanelWidth(double delta) {
    setState(() {
      _productListWidth =
          (_productListWidth + delta).clamp(_minPanelWidth, _maxPanelWidth);
    });
    _savePanelWidth(_productListWidth);
  }

  Future<void> _selectDateRange() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (result != null) {
      setState(() {
        _startDate = result.start;
        _endDate = result.end;
      });
    }
  }

  void _clearDateRange() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
  }

  void _clearAllMovementFilters() {
    setState(() {
      _movementTypeFilter = 'all';
      _startDate = null;
      _endDate = null;
    });
  }

  Future<void> _navigateToReference(StockMovement movement) async {
    if (!movement.hasNavigableReference || movement.referenceId == null) {
      return;
    }

    setState(() {
      _selectedLinkedMovement = movement;
      _selectedSalesInvoice = null;
      _selectedPurchaseInvoice = null;
      _selectedStockAdjustment = null;
      _linkedDocumentError = null;
      _isLoadingLinkedDocument = true;
    });

    try {
      if (movement.category == StockMovementCategory.adjustment) {
        final adjustment = await context
            .read<module_inventory.InventoryService>()
            .getStockAdjustmentDetails(movement.referenceId!);
        if (!mounted) return;

        setState(() {
          _selectedStockAdjustment = adjustment;
          _isLoadingLinkedDocument = false;
        });
        return;
      }

      if (movement.category == StockMovementCategory.purchase) {
        final invoice = await context
            .read<PurchaseService>()
            .getPurchaseInvoice(movement.referenceId!);
        if (!mounted) return;

        if (invoice == null) {
          throw Exception('No se pudo cargar la factura de compra.');
        }

        setState(() {
          _selectedPurchaseInvoice = invoice;
          _isLoadingLinkedDocument = false;
        });
        return;
      }

      final invoice = await context
          .read<SalesService>()
          .fetchInvoice(movement.referenceId!, refresh: true);
      await context.read<SalesService>().loadPayments(forceRefresh: false);
      if (!mounted) return;

      if (invoice == null) {
        throw Exception('No se pudo cargar la factura de venta.');
      }

      setState(() {
        _selectedSalesInvoice = invoice;
        _isLoadingLinkedDocument = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _linkedDocumentError = e.toString();
        _isLoadingLinkedDocument = false;
      });
    }
  }

  void _closeLinkedDocument() {
    setState(() {
      _selectedLinkedMovement = null;
      _selectedSalesInvoice = null;
      _selectedPurchaseInvoice = null;
      _selectedStockAdjustment = null;
      _linkedDocumentError = null;
      _isLoadingLinkedDocument = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<StockMovementsService>();
    final isRecentMode = _viewMode == StockMovementsViewMode.recent;

    return MainLayout(
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: isRecentMode
                // Recent mode: full-width movements table
                ? _buildMovementDetails()
                // By product mode: split panel layout
                : Row(
                    children: [
                      // Left panel: Product list (resizable)
                      SizedBox(
                        width: _productListWidth,
                        child: _buildProductList(),
                      ),
                      // Resizable divider
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (details) {
                            _updatePanelWidth(details.delta.dx);
                          },
                          child: Container(
                            width: 8,
                            color: Colors.transparent,
                            child: Center(
                              child: Container(
                                width: 1,
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Right panel: Movement details
                      Expanded(
                        child: _buildMovementDetails(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final movementsService = context.watch<StockMovementsService>();
    final isRecentMode = _viewMode == StockMovementsViewMode.recent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.timeline, size: 28),
          const SizedBox(width: 12),
          const Text(
            'Movimientos de Stock',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 32),
          // View mode toggle
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildViewModeButton(
                  icon: Icons.history,
                  label: 'Últimos',
                  isSelected: isRecentMode,
                  onTap: () {
                    _closeLinkedDocument();
                    setState(() => _viewMode = StockMovementsViewMode.recent);
                    movementsService.setViewMode('recent');
                  },
                ),
                _buildViewModeButton(
                  icon: Icons.inventory_2,
                  label: 'Por Producto',
                  isSelected: !isRecentMode,
                  onTap: () {
                    _closeLinkedDocument();
                    setState(
                        () => _viewMode = StockMovementsViewMode.byProduct);
                    movementsService.setViewMode('by_product');
                  },
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            isRecentMode
                ? 'Mostrando los últimos 100 movimientos'
                : 'Selecciona un producto para ver su historial',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductList() {
    return Consumer<InventoryService>(
      builder: (context, inventoryService, _) {
        if (inventoryService.isLoading) {
          return const Center(child: BrandedLoading());
        }

        // Filter products by search query
        final filteredProducts = inventoryService.products.where((p) {
          return _matchesTokenSearch(_searchQuery, p);
        }).toList();

        return Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: SearchBarWidget(
                controller: _searchController,
                hintText: 'Buscar producto por nombre o SKU...',
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
              ),
            ),
            // Product count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '${filteredProducts.length} productos',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Product list
            Expanded(
              child: ListView.builder(
                itemCount: filteredProducts.length,
                itemBuilder: (context, index) {
                  final product = filteredProducts[index];
                  return _buildProductTile(product);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProductTile(Product product) {
    final movementsService = context.watch<StockMovementsService>();
    final isSelected = movementsService.selectedProductId == product.id;
    final theme = Theme.of(context);
    final thumbnailUrl = product.imageUrlOptimized ?? product.imageUrl;

    return Material(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.06)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          _closeLinkedDocument();
          context
              .read<StockMovementsService>()
              .loadMovementsForProduct(product.id);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color:
                    isSelected ? theme.colorScheme.primary : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.18),
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                      ? ImageService.buildProductImage(
                          imageUrl: thumbnailUrl,
                          size: 52,
                          isListThumbnail: true,
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.inventory_2_outlined,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      product.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.sku,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Stock',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.stockQuantity.toString(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMovementDetails() {
    return Consumer<StockMovementsService>(
      builder: (context, movementsService, _) {
        final inventoryService = context.watch<InventoryService>();
        final theme = Theme.of(context);
        final isRecentMode = _viewMode == StockMovementsViewMode.recent;
        final selectedProduct = !isRecentMode
            ? _findSelectedMovementProduct(inventoryService, movementsService)
            : null;

        // Only show "select a product" message in by_product mode with no selection
        if (!isRecentMode && movementsService.selectedProductId == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'Selecciona un producto',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'para ver su historial de movimientos',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        if (movementsService.isLoading) {
          return Column(
            children: [
              if (selectedProduct != null)
                _buildSelectedProductHeader(
                  theme,
                  selectedProduct,
                  movementCount: movementsService.movements.length,
                ),
              const Expanded(child: Center(child: BrandedLoading())),
            ],
          );
        }

        if (movementsService.error != null) {
          return Column(
            children: [
              if (selectedProduct != null)
                _buildSelectedProductHeader(
                  theme,
                  selectedProduct,
                  movementCount: movementsService.movements.length,
                ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'Error al cargar movimientos',
                        style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        movementsService.error!,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        // Apply filters
        var movements = movementsService.movements;
        movements = movementsService.filterByType(_movementTypeFilter);
        movements = movementsService.filterByDateRange(_startDate, _endDate);

        return Column(
          children: [
            if (selectedProduct != null)
              _buildSelectedProductHeader(
                theme,
                selectedProduct,
                movementCount: movements.length,
              ),
            _buildMovementFilters(movementsService),
            _buildMovementSummary(movements),
            const Divider(height: 1),
            Expanded(
              child: _buildMovementContent(movements),
            ),
          ],
        );
      },
    );
  }

  Product? _findSelectedMovementProduct(
    InventoryService inventoryService,
    StockMovementsService movementsService,
  ) {
    final selectedId = movementsService.selectedProductId;
    if (selectedId == null) return null;

    for (final product in inventoryService.products) {
      if (product.id == selectedId) {
        return product;
      }
    }

    return null;
  }

  Widget _buildSelectedProductHeader(
    ThemeData theme,
    Product product, {
    required int movementCount,
  }) {
    final thumbnailUrl = product.imageUrlOptimized ?? product.imageUrl;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 56,
              child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                  ? ImageService.buildProductImage(
                      imageUrl: thumbnailUrl,
                      size: 56,
                      isListThumbnail: true,
                    )
                  : Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.inventory_2_outlined,
                        size: 22,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Producto seleccionado',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.sku,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          _buildSelectedProductMetric(
            theme,
            label: 'Stock actual',
            value: product.stockQuantity.toString(),
          ),
          const SizedBox(width: 20),
          _buildSelectedProductMetric(
            theme,
            label: 'Movimientos',
            value: movementCount.toString(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedProductMetric(
    ThemeData theme, {
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildMovementContent(List<StockMovement> movements) {
    if (_isLoadingLinkedDocument) {
      return const Center(child: BrandedLoading());
    }

    if (_linkedDocumentError != null) {
      return _buildInlineDocumentScaffold(
        title: 'No se pudo cargar el documento',
        subtitle: _selectedLinkedMovement?.referenceDisplay,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 12),
                Text(
                  _linkedDocumentError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_selectedSalesInvoice != null) {
      return _buildInlineDocumentScaffold(
        title: null,
        subtitle: null,
        child: _buildSalesInvoiceInlineView(_selectedSalesInvoice!),
      );
    }

    if (_selectedStockAdjustment != null) {
      return _buildInlineDocumentScaffold(
        title: 'Detalle de ajuste',
        subtitle: _selectedStockAdjustment!.referenceDisplay,
        child: _buildStockAdjustmentInlineView(_selectedStockAdjustment!),
      );
    }

    if (_selectedPurchaseInvoice != null) {
      return _buildInlineDocumentScaffold(
        title: 'Detalle de compra',
        subtitle: _selectedLinkedMovement?.productName,
        child: _buildPurchaseInvoiceInlineView(_selectedPurchaseInvoice!),
      );
    }

    if (movements.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.filter_alt_off, size: 52, color: Colors.grey[350]),
              const SizedBox(height: 16),
              Text(
                _hasActiveMovementFilters
                    ? 'No hay movimientos con los filtros actuales'
                    : 'No hay movimientos para este producto',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _hasActiveMovementFilters
                    ? 'Prueba quitando el tipo o el rango de fechas para ver más resultados.'
                    : 'Este producto todavía no registra cambios de stock.',
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              if (_hasActiveMovementFilters) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _clearAllMovementFilters,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Limpiar filtros'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        if (isWide) {
          final tableWidth = _totalTableWidth > constraints.maxWidth
              ? _totalTableWidth
              : constraints.maxWidth;

          return Scrollbar(
            controller: _horizontalScrollController,
            trackVisibility: true,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  children: [
                    _buildMovementTableHeader(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: movements.length,
                        itemBuilder: (context, index) {
                          return _buildMovementRow(movements[index]);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: movements.length,
          itemBuilder: (context, index) {
            return _buildMovementCard(movements[index]);
          },
        );
      },
    );
  }

  Widget _buildInlineDocumentScaffold({
    String? title,
    String? subtitle,
    required Widget child,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _closeLinkedDocument,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Volver a movimientos'),
              ),
              if ((title != null && title.isNotEmpty) ||
                  (subtitle != null && subtitle.isNotEmpty)) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null && title.isNotEmpty)
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildStockAdjustmentInlineView(StockAdjustmentDetail detail) {
    final theme = Theme.of(context);
    final metrics = <Widget>[
      _buildAdjustmentMetricCard(
        'Cantidad',
        detail.quantity > 0 ? '+${detail.quantity}' : '${detail.quantity}',
        valueColor: detail.isIncrease ? Colors.green[700] : Colors.red[700],
      ),
      _buildAdjustmentMetricCard(
        'Stock antes',
        '${detail.stockBefore}',
      ),
      _buildAdjustmentMetricCard(
        'Stock despues',
        '${detail.stockAfter}',
      ),
      _buildAdjustmentMetricCard(
        'Valor inventario',
        ChileanUtils.formatCurrency(detail.inventoryValue),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detail.productName,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ((detail.productSku ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail.productSku!,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: detail.isIncrease
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  detail.adjustmentTypeLabel,
                  style: TextStyle(
                    color:
                        detail.isIncrease ? Colors.green[700] : Colors.red[700],
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildAdjustmentMetaItem('Referencia', detail.referenceDisplay),
                _buildAdjustmentMetaItem(
                  'Fecha efectiva',
                  DateFormat('dd/MM/yyyy HH:mm').format(detail.adjustmentDate),
                ),
                _buildAdjustmentMetaItem(
                    'Registrado por', detail.createdByDisplay),
                if (detail.hasAdjustmentOrigin)
                  _buildAdjustmentMetaItem(
                    'Origen',
                    detail.adjustmentOriginDisplay!,
                  ),
                if ((detail.journalEntryNumber ?? '').isNotEmpty)
                  _buildAdjustmentMetaItem(
                    'Asiento',
                    detail.journalEntryNumber!,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: metrics,
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Motivo registrado',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(detail.reasonDisplay),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Impacto contable',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if ((detail.journalEntryNumber ?? '').isEmpty)
                  Text(detail.accountingImpactMessage)
                else ...[
                  _buildAdjustmentMetaItem(
                    'Descripción',
                    detail.journalEntryDescription ?? '-',
                  ),
                  const SizedBox(height: 10),
                  _buildAdjustmentMetaItem(
                    'Cuenta contraparte',
                    [
                      if ((detail.counterpartAccountCode ?? '').isNotEmpty)
                        detail.counterpartAccountCode,
                      if ((detail.counterpartAccountName ?? '').isNotEmpty)
                        detail.counterpartAccountName,
                    ].whereType<String>().join(' - '),
                  ),
                  const SizedBox(height: 10),
                  _buildAdjustmentMetaItem(
                    detail.isIncrease
                        ? 'Crédito contraparte'
                        : 'Débito contraparte',
                    ChileanUtils.formatCurrency(detail.counterpartAmount),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustmentMetricCard(
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustmentMetaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSalesInvoiceInlineView(Invoice invoice) {
    final payments =
        context.read<SalesService>().getPaymentsForInvoice(invoice.id ?? '');
    final inventoryService = context.watch<InventoryService>();

    final statusColor = _salesStatusColor(invoice.status);
    final statusText = _salesStatusLabel(invoice.status);

    // Group Items by Bike
    final Map<String, List<InvoiceItem>> groupedItems = {};
    for (final item in invoice.items) {
      final key =
          item.bikeName?.isNotEmpty == true ? item.bikeName! : 'General';
      groupedItems.putIfAbsent(key, () => []).add(item);
    }
    final sortedKeys = groupedItems.keys.toList()
      ..sort((a, b) {
        if (a == 'General' && b != 'General') return -1;
        if (b == 'General' && a != 'General') return 1;
        return a.compareTo(b);
      });

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER ROW
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.invoiceNumber.isNotEmpty
                          ? 'Factura ${invoice.invoiceNumber}'
                          : 'Factura',
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      invoice.customerName ?? 'Cliente Asociado',
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        invoice.status == InvoiceStatus.paid
                            ? Icons.check_circle
                            : Icons.info_outline,
                        size: 16,
                        color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      statusText.toUpperCase(),
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // DATES AND SOURCE
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                _buildInfoColumn(
                    'Fecha de emisión',
                    ChileanUtils.formatDate(invoice.date),
                    Icons.calendar_today),
                const SizedBox(width: 32),
                if (invoice.dueDate != null) ...[
                  _buildInfoColumn(
                      'Vencimiento',
                      ChileanUtils.formatDate(invoice.dueDate!),
                      Icons.schedule),
                  const SizedBox(width: 32),
                ],
                _buildInfoColumn(
                    'Origen', invoice.source ?? 'sale', Icons.storefront),
                if (invoice.reference != null &&
                    invoice.reference!.isNotEmpty) ...[
                  const SizedBox(width: 32),
                  _buildInfoColumn(
                      'Referencia', invoice.reference!, Icons.link),
                ],
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Text('Bicicletas y Productos',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          // ITEMS GROUPED BY BIKE
          if (invoice.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text('Esta factura no tiene ítems asociados.',
                      style: TextStyle(fontStyle: FontStyle.italic))),
            )
          else
            ...sortedKeys.map((sectionKey) {
              final items = groupedItems[sectionKey]!;
              final subtotal =
                  items.fold<double>(0, (sum, i) => sum + i.lineTotal);
              final isGeneral = sectionKey == 'General';

              return Container(
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Section Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                        border: Border(
                            bottom: BorderSide(color: Colors.grey[200]!)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                              isGeneral
                                  ? Icons.inventory_2_outlined
                                  : Icons.pedal_bike,
                              size: 20,
                              color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Text(
                            isGeneral ? 'Artículos Generales' : sectionKey,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[800]),
                          ),
                          const Spacer(),
                          Text(
                            ChileanUtils.formatCurrency(subtotal),
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[800]),
                          ),
                        ],
                      ),
                    ),
                    // Items List
                    ...items.map((item) {
                      final product = item.productId != null
                          ? inventoryService.products
                              .cast<Product?>()
                              .firstWhere((p) => p?.id == item.productId,
                                  orElse: () => null)
                          : null;
                      final imageUrl = product?.imageUrls.isNotEmpty == true
                          ? product!.imageUrls.first
                          : (product?.imageUrl);
                      final isLast = items.last == item;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          border: isLast
                              ? null
                              : Border(
                                  bottom: BorderSide(color: Colors.grey[100]!)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Thumbnail
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[200]!),
                                image: imageUrl != null && imageUrl.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(imageUrl),
                                        fit: BoxFit.cover)
                                    : null,
                              ),
                              child: imageUrl == null || imageUrl.isEmpty
                                  ? Icon(
                                      item.isService
                                          ? Icons.build_outlined
                                          : Icons.inventory_2_outlined,
                                      color: Colors.grey[400])
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            // Item info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName ??
                                        item.productSku ??
                                        'Ítem sin nombre',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15),
                                  ),
                                  if (item.productSku != null &&
                                      item.productSku!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text('SKU: ${item.productSku}',
                                        style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 12)),
                                  ],
                                  if (item.description != null &&
                                      item.description!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(item.description!,
                                        style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic)),
                                  ],
                                ],
                              ),
                            ),
                            // Price
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  ChileanUtils.formatCurrency(item.lineTotal),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_formatQuantity(item.quantity)} x ${ChileanUtils.formatCurrency(item.unitPrice)}',
                                  style: TextStyle(
                                      color: Colors.grey[600], fontSize: 13),
                                ),
                                if (item.discount > 0) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '-${ChileanUtils.formatCurrency(item.discount)}',
                                    style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),

          // TOTALS
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Payments (Left side)
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Restumen de Pagos',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 16),
                      if (payments.isEmpty)
                        Text('No se han registrado pagos.',
                            style: TextStyle(
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic))
                      else
                        ...payments.map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.payments_outlined,
                                      size: 16, color: Colors.green[600]),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(
                                          ChileanUtils.formatDate(p.date),
                                          style: TextStyle(
                                              color: Colors.grey[700]))),
                                  Text(ChileanUtils.formatCurrency(p.amount),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            )),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Summary Calculation (Right side)
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Subtotal',
                              style: TextStyle(color: Colors.grey[600])),
                          Text(ChileanUtils.formatCurrency(invoice.subtotal),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('IVA (19%)',
                              style: TextStyle(color: Colors.grey[600])),
                          Text(ChileanUtils.formatCurrency(invoice.ivaAmount),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 18)),
                          Text(ChileanUtils.formatCurrency(invoice.total),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: Colors.blue)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Pagado',
                              style: TextStyle(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w600)),
                          Text(ChileanUtils.formatCurrency(invoice.paidAmount),
                              style: TextStyle(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Saldo Pendiente',
                              style: TextStyle(
                                  color: invoice.balance > 0
                                      ? Colors.orange[800]
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.w600)),
                          Text(ChileanUtils.formatCurrency(invoice.balance),
                              style: TextStyle(
                                  color: invoice.balance > 0
                                      ? Colors.orange[800]
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.05),
              shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: Colors.blue[700]),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2)),
            const SizedBox(height: 2),
            Text(value,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCol(String label, String value,
      [Color? valueColor,
      double fontSize = 16,
      FontWeight fontWeight = FontWeight.bold]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey[500],
              letterSpacing: 1),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: valueColor ?? Colors.black87),
        ),
      ],
    );
  }

  Widget _buildPurchaseInvoiceInlineView(PurchaseInvoice invoice) {
    final inventoryService = context.watch<InventoryService>();
    final totalUnits = invoice.items.fold<double>(
      0,
      (sum, item) => sum + item.quantity,
    );

    final statusColor = _purchaseStatusColor(invoice.status);
    final statusText = invoice.status.displayName;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER ROW
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.invoiceNumber.isNotEmpty
                          ? 'Factura de Compra ${invoice.invoiceNumber}'
                          : 'Factura de Compra',
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      invoice.supplierName ?? 'Proveedor Asociado',
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        invoice.status == PurchaseInvoiceStatus.paid
                            ? Icons.check_circle
                            : Icons.info_outline,
                        size: 16,
                        color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      statusText.toUpperCase(),
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // SUMMARY METRICS ROW
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricCol(
                      'FECHA', DateFormat('dd/MM/yyyy').format(invoice.date)),
                ),
                Expanded(
                  child: _buildMetricCol(
                    'ÍTEMS',
                    '${invoice.items.length} prod. / ${_formatQuantity(totalUnits)} uds.',
                  ),
                ),
                Expanded(
                  child: _buildMetricCol(
                      'IMPUESTO',
                      invoice.taxTreatment == TaxTreatment.taxIncluded
                          ? 'IVA Incluido'
                          : 'Sin IVA'),
                ),
                Expanded(
                  child: _buildMetricCol(
                    'TOTAL',
                    ChileanUtils.formatCurrency(invoice.total),
                    Colors.black87,
                    20,
                    FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // ITEMS LIST
          Text(
            'Productos ingresados',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
                letterSpacing: -0.5),
          ),
          const SizedBox(height: 16),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                // Table Header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(11)),
                    border:
                        Border(bottom: BorderSide(color: Colors.grey[300]!)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 48 + 16), // space for image
                      Expanded(
                        flex: 3,
                        child: Text('PRODUCTO',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                                letterSpacing: 0.5)),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text('CANT.',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                                letterSpacing: 0.5)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('COSTO U.',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                                letterSpacing: 0.5)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('TOTAL',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                ),

                // Items List
                ...invoice.items.map((item) {
                  final productList = inventoryService.products
                      .where((p) => p.id == item.productId)
                      .toList();
                  final product =
                      productList.isNotEmpty ? productList.first : null;

                  final imageUrl = product?.imageUrls.isNotEmpty == true
                      ? product!.imageUrls.first
                      : (product?.imageUrl);
                  final isLast = invoice.items.last == item;

                  final subtotal = item.quantity * item.unitCost;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      border: !isLast
                          ? Border(bottom: BorderSide(color: Colors.grey[200]!))
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Image Thumbnail
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[200]!),
                            image: imageUrl != null && imageUrl.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(imageUrl),
                                    fit: BoxFit.cover)
                                : null,
                          ),
                          child: imageUrl == null || imageUrl.isEmpty
                              ? Icon(
                                  Icons.inventory_2_outlined,
                                  color: Colors.grey[400],
                                  size: 20,
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName ?? 'Producto sin nombre',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              if (item.productSku != null &&
                                  item.productSku!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    item.productSku!,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                        fontFamily: 'monospace'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            item.quantity.toStringAsFixed(0),
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            ChileanUtils.formatCurrency(item.unitCost),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                color: Colors.grey[700], fontSize: 13),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            ChileanUtils.formatCurrency(subtotal),
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ), // Ensure child Column is closed here
    ); // Ensure SingleChildScrollView is closed here
  }

  String _formatQuantity(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.0001) {
      return rounded.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  String _salesStatusLabel(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return 'Borrador';
      case InvoiceStatus.sent:
        return 'Enviada';
      case InvoiceStatus.confirmed:
        return 'Confirmada';
      case InvoiceStatus.paid:
        return 'Pagada';
      case InvoiceStatus.overdue:
        return 'Vencida';
      case InvoiceStatus.cancelled:
        return 'Anulada';
    }
  }

  Color _salesStatusColor(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return Colors.grey;
      case InvoiceStatus.sent:
        return Colors.blue;
      case InvoiceStatus.confirmed:
        return Colors.purple;
      case InvoiceStatus.paid:
        return Colors.green;
      case InvoiceStatus.overdue:
        return Colors.orange;
      case InvoiceStatus.cancelled:
        return Colors.red;
    }
  }

  Color _purchaseStatusColor(PurchaseInvoiceStatus status) {
    switch (status) {
      case PurchaseInvoiceStatus.draft:
        return Colors.grey;
      case PurchaseInvoiceStatus.sent:
        return Colors.blue;
      case PurchaseInvoiceStatus.confirmed:
        return Colors.purple;
      case PurchaseInvoiceStatus.received:
        return Colors.teal;
      case PurchaseInvoiceStatus.paid:
        return Colors.green;
      case PurchaseInvoiceStatus.cancelled:
        return Colors.red;
    }
  }

  Widget _buildMovementFilters(StockMovementsService service) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          // Type filter
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _movementTypeFilter,
              decoration: const InputDecoration(
                labelText: 'Tipo de movimiento',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todos')),
                DropdownMenuItem(value: 'purchase', child: Text('Compras')),
                DropdownMenuItem(value: 'sale', child: Text('Ventas')),
                DropdownMenuItem(value: 'adjustment', child: Text('Ajustes')),
                DropdownMenuItem(
                    value: 'transfer', child: Text('Transferencias')),
              ],
              onChanged: (value) {
                setState(() => _movementTypeFilter = value ?? 'all');
              },
            ),
          ),
          const SizedBox(width: 16),
          // Date range picker
          ElevatedButton.icon(
            onPressed: _selectDateRange,
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(
              _startDate != null && _endDate != null
                  ? '${DateFormat('dd/MM/yy').format(_startDate!)} - ${DateFormat('dd/MM/yy').format(_endDate!)}'
                  : 'Rango de fechas',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _startDate != null && _endDate != null
                  ? Colors.blue.withValues(alpha: 0.1)
                  : Colors.white,
              foregroundColor: _startDate != null && _endDate != null
                  ? Colors.blue
                  : Colors.black87,
            ),
          ),
          if (_startDate != null || _endDate != null)
            IconButton(
              onPressed: _clearDateRange,
              icon: const Icon(Icons.clear, size: 18),
              tooltip: 'Limpiar filtro de fecha',
            ),
          if (_hasActiveMovementFilters) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _clearAllMovementFilters,
              icon: const Icon(Icons.filter_alt_off, size: 18),
              label: const Text('Quitar filtros'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMovementSummary(List<StockMovement> movements) {
    final summary = _buildFilteredSummary(movements);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          _buildSummaryItem(
            _hasActiveMovementFilters ? 'Resultados' : 'Transacciones',
            summary['transaction_count'].toString(),
            Icons.receipt_long,
            Colors.blue,
          ),
          const SizedBox(width: 24),
          _buildSummaryItem(
            'Entradas',
            '+${summary['total_increase']}',
            Icons.add_circle_outline,
            Colors.green,
          ),
          const SizedBox(width: 24),
          _buildSummaryItem(
            'Salidas',
            '${summary['total_decrease']}',
            Icons.remove_circle_outline,
            Colors.red,
          ),
          const SizedBox(width: 24),
          _buildSummaryItem(
            'Balance',
            (summary['net_change'] ?? 0) >= 0
                ? '+${summary['net_change']}'
                : summary['net_change'].toString(),
            Icons.bar_chart,
            (summary['net_change'] ?? 0) >= 0 ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }

  bool get _hasActiveMovementFilters {
    return _movementTypeFilter != 'all' ||
        _startDate != null ||
        _endDate != null;
  }

  Map<String, int> _buildFilteredSummary(List<StockMovement> movements) {
    var totalIncrease = 0;
    var totalDecrease = 0;
    var netChange = 0;

    for (final movement in movements) {
      final quantity = movement.quantity;
      netChange += quantity;
      if (quantity >= 0) {
        totalIncrease += quantity;
      } else {
        totalDecrease += quantity.abs();
      }
    }

    return {
      'transaction_count': movements.length,
      'total_increase': totalIncrease,
      'total_decrease': totalDecrease,
      'net_change': netChange,
    };
  }

  Widget _buildSummaryItem(
      String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
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
      product.categoryName?.toLowerCase() ?? '',
    ].join(' ');
    // ALL tokens must be found in searchable text
    return tokens.every((token) => searchableText.contains(token));
  }

  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  double get _totalTableWidth {
    final movementsService = context.read<StockMovementsService>();
    final showProductColumn = movementsService.isRecentMode;
    // Sum of all visible columns + resize handles (8px each)
    double width = 0;
    if (showProductColumn) width += _colProductWidth + 8;
    width += _colDateWidth + 8;
    width += _colTypeWidth + 8;
    width += _colSourceWidth + 8;
    width += _colRefWidth + 8;
    width += _colIniWidth + 8;
    width += _colMovWidth + 8;
    width += _colFinWidth; // Last one has no handle
    return width;
  }

  Widget _buildMovementTableHeader() {
    final showProductColumn = _viewMode == StockMovementsViewMode.recent;
    final theme = Theme.of(context);

    TextStyle headerStyle = theme.textTheme.labelSmall!.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
      letterSpacing: 0.3,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        children: [
          // Product column (only in recent mode)
          if (showProductColumn) ...[
            SizedBox(
              width: _colProductWidth,
              child: Text('Producto', style: headerStyle),
            ),
            _buildResizeHandle((delta) => setState(() => _colProductWidth =
                (_colProductWidth + delta).clamp(_minColWidth, 400))),
          ],
          SizedBox(
            width: _colDateWidth,
            child: Text('Fecha', style: headerStyle),
          ),
          _buildResizeHandle((delta) => setState(() => _colDateWidth =
              (_colDateWidth + delta).clamp(_minColWidth, 200))),
          SizedBox(
            width: _colTypeWidth,
            child: Text('Movimiento', style: headerStyle),
          ),
          _buildResizeHandle((delta) => setState(() => _colTypeWidth =
              (_colTypeWidth + delta).clamp(_minColWidth, 150))),
          SizedBox(
            width: _colSourceWidth,
            child: Text('Origen', style: headerStyle),
          ),
          _buildResizeHandle((delta) => setState(() => _colSourceWidth =
              (_colSourceWidth + delta).clamp(_minColWidth, 200))),
          SizedBox(
            width: _colRefWidth,
            child: Text('Referencia', style: headerStyle),
          ),
          _buildResizeHandle((delta) => setState(() =>
              _colRefWidth = (_colRefWidth + delta).clamp(_minColWidth, 200))),
          SizedBox(
            width: _colIniWidth,
            child: Text(
              'Inicial',
              style: headerStyle,
              textAlign: TextAlign.right,
            ),
          ),
          _buildResizeHandle((delta) => setState(
              () => _colIniWidth = (_colIniWidth + delta).clamp(35, 80))),
          SizedBox(
            width: _colMovWidth,
            child: Text(
              'Cambio',
              style: headerStyle,
              textAlign: TextAlign.right,
            ),
          ),
          _buildResizeHandle((delta) => setState(
              () => _colMovWidth = (_colMovWidth + delta).clamp(35, 80))),
          SizedBox(
            width: _colFinWidth,
            child: Text(
              'Final',
              style: headerStyle,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResizeHandle(Function(double) onDrag) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Container(
          width: 8,
          height: 20,
          color: Colors.transparent, // Transparent hit target
          // Removed visible line to reduce noise
        ),
      ),
    );
  }

  Widget _buildMovementRow(StockMovement movement) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final showProductColumn = _viewMode == StockMovementsViewMode.recent;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Product column (only in recent mode)
          if (showProductColumn) ...[
            SizedBox(
              width: _colProductWidth,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                      image: movement.productImageUrl != null &&
                              movement.productImageUrl!.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(movement.productImageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: movement.productImageUrl == null ||
                            movement.productImageUrl!.isEmpty
                        ? Icon(Icons.inventory_2_outlined,
                            size: 20, color: Colors.grey[400])
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          movement.productName,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (movement.productSku != null)
                          Text(
                            movement.productSku!,
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[600]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8), // Matches resize handle
          ],
          // Date
          SizedBox(
            width: _colDateWidth,
            child: Text(
              dateFormat.format(movement.transactionDate),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Type
          SizedBox(
            width: _colTypeWidth,
            child: _buildMovementTypeCell(movement),
          ),
          const SizedBox(width: 8),
          // Source
          SizedBox(
            width: _colSourceWidth,
            child: _buildSourceCell(movement),
          ),
          const SizedBox(width: 8),
          // Reference
          SizedBox(
            width: _colRefWidth,
            child: _buildReferenceCell(movement),
          ),
          const SizedBox(width: 8),
          // Stock Before
          SizedBox(
            width: _colIniWidth,
            child: Text(
              movement.stockBefore.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          // Quantity
          SizedBox(
            width: _colMovWidth,
            child: Text(
              movement.quantity >= 0
                  ? '+${movement.quantity}'
                  : movement.quantity.toString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color:
                    movement.isIncrease ? Colors.green[700] : Colors.red[700],
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          // Stock After
          SizedBox(
            width: _colFinWidth,
            child: Text(
              movement.stockAfter.toString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementTypeCell(StockMovement movement) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          movement.movementTypeDisplay,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
            height: 1.15,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          movement.category.displayName,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildSourceCell(StockMovement movement) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          movement.sourceDisplay,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (movement.hasAdjustmentOrigin) ...[
          const SizedBox(height: 2),
          Text(
            movement.adjustmentOriginDisplay!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildCompactSourceInfo(StockMovement movement) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          movement.sourceDisplay,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (movement.hasAdjustmentOrigin)
          Text(
            movement.adjustmentOriginDisplay!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  Widget _buildReferenceCell(StockMovement movement) {
    final theme = Theme.of(context);
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: movement.hasNavigableReference
              ? theme.colorScheme.primary.withValues(alpha: 0.22)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Text(
              movement.referenceDisplay,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: movement.hasNavigableReference
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (movement.hasNavigableReference) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.open_in_new,
              size: 14,
              color: theme.colorScheme.primary,
            ),
          ],
        ],
      ),
    );

    if (!movement.hasNavigableReference) {
      return child;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _navigateToReference(movement),
      child: child,
    );
  }

  // Mobile card layout for smaller screens
  Widget _buildMovementCard(StockMovement movement) {
    final dateFormat = DateFormat('dd/MM/yy HH:mm');
    final showProductHeader = _viewMode == StockMovementsViewMode.recent;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product name + type chip
            if (showProductHeader)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      movement.productName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildTypeChip(movement),
                ],
              )
            else
              _buildTypeChip(movement),
            const SizedBox(height: 8),
            // Date + Source
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  dateFormat.format(movement.transactionDate),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildCompactSourceInfo(movement),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Stock changes
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Reference
                if (movement.referenceNumber != null)
                  InkWell(
                    onTap: movement.hasNavigableReference
                        ? () => _navigateToReference(movement)
                        : null,
                    child: Text(
                      movement.referenceDisplay,
                      style: TextStyle(
                        fontSize: 12,
                        color: movement.hasNavigableReference
                            ? Colors.blue
                            : Colors.grey[700],
                        decoration: movement.hasNavigableReference
                            ? TextDecoration.underline
                            : TextDecoration.none,
                      ),
                    ),
                  )
                else
                  const SizedBox(),
                // Stock: before -> change -> after
                Row(
                  children: [
                    Text(
                      '${movement.stockBefore}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      movement.quantity >= 0
                          ? '+${movement.quantity}'
                          : '${movement.quantity}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: movement.isIncrease ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward,
                        size: 12, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      '${movement.stockAfter}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(StockMovement movement) {
    Color color;
    switch (movement.category) {
      case StockMovementCategory.purchase:
        color = Colors.green;
        break;
      case StockMovementCategory.sale:
        color = Colors.blue;
        break;
      case StockMovementCategory.adjustment:
        color = Colors.orange;
        break;
      case StockMovementCategory.transfer:
        color = Colors.purple;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        movement.movementTypeDisplay,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}
