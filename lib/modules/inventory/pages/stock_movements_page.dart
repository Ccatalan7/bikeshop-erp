import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/models/product.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../../purchases/models/purchase_invoice.dart';
import '../../purchases/services/purchase_service.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';

import '../models/stock_movement.dart';
import '../models/stock_adjustment.dart';
import '../services/inventory_service.dart' as module_inventory;
import '../widgets/movement_inspector.dart';
import '../widgets/stock_ledger.dart';
import '../services/stock_movements_service.dart';
import '../widgets/stock_movements_responsive_frame.dart';

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
  static const int _productPreviewPageSize = 80;
  Timer? _productSearchDebounce;
  List<Product>? _productSearchResults;
  String _activeProductSearchQuery = '';
  bool _isProductSearchLoading = false;
  bool _isLoadingProductPreview = false;
  bool _hasRequestedInitialProductPreview = false;
  int _nextProductPreviewPage = 0;

  // Panel resizing
  static const double _minPanelWidth = 300.0;
  static const double _maxPanelWidth = 600.0;
  static const double _defaultPanelWidth = 400.0;
  double _productListWidth = _defaultPanelWidth;

  StockMovement? _selectedLinkedMovement;
  Invoice? _selectedSalesInvoice;
  PurchaseInvoice? _selectedPurchaseInvoice;
  StockAdjustmentDetail? _selectedStockAdjustment;
  bool _isLoadingLinkedDocument = false;
  String? _linkedDocumentError;
  Map<String, dynamic>? _selectedOperationTrace;
  bool _isLoadingOperationTrace = false;
  String? _operationTraceError;
  int _linkedDocumentRequestGeneration = 0;
  int _operationTraceRequestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadPanelWidth();
    _productListScrollController.addListener(_handleProductListScroll);
    // Load recent movements by default. Products are loaded lazily when the
    // user opens "Por Producto" so this module does not preload inventory.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StockMovementsService>().loadRecentMovements();
    });
  }

  void _handleProductListScroll() {
    if (_viewMode != StockMovementsViewMode.byProduct ||
        _searchQuery.trim().isNotEmpty ||
        !_productListScrollController.hasClients) {
      return;
    }

    final position = _productListScrollController.position;
    if (position.extentAfter < 480) {
      _loadNextProductPreviewPage();
    }
  }

  Future<void> _ensureInitialProductPreview() async {
    if (_hasRequestedInitialProductPreview) return;
    _hasRequestedInitialProductPreview = true;
    await _loadNextProductPreviewPage();
  }

  Future<void> _loadNextProductPreviewPage({bool reset = false}) async {
    if (!mounted || _isLoadingProductPreview) return;

    final inventoryService = context.read<InventoryService>();
    if (!reset && !inventoryService.hasMorePreviewPages) return;

    setState(() => _isLoadingProductPreview = true);
    try {
      final page = reset ? 0 : _nextProductPreviewPage;
      await inventoryService.loadProductPreviewPage(
        page: page,
        pageSize: _productPreviewPageSize,
        reset: reset,
      );
      if (!mounted) return;
      setState(() {
        _nextProductPreviewPage = page + 1;
      });
    } catch (e) {
      debugPrint('Error loading stock movement product preview: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingProductPreview = false);
      }
    }
  }

  void _onProductSearchChanged(String value) {
    setState(() => _searchQuery = value);

    _productSearchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _activeProductSearchQuery = '';
        _productSearchResults = null;
        _isProductSearchLoading = false;
      });
      _ensureInitialProductPreview();
      return;
    }

    _productSearchDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _runProductSearch(query),
    );
  }

  Future<void> _runProductSearch(String query) async {
    if (!mounted) return;

    setState(() {
      _activeProductSearchQuery = query;
      _isProductSearchLoading = true;
    });

    try {
      final products =
          await context.read<InventoryService>().searchProducts(query);
      if (!mounted || _searchQuery.trim() != query) return;
      setState(() {
        _productSearchResults = products;
        _isProductSearchLoading = false;
      });
    } catch (e) {
      debugPrint('Error searching stock movement products: $e');
      if (!mounted || _searchQuery.trim() != query) return;
      setState(() {
        _productSearchResults = const [];
        _isProductSearchLoading = false;
      });
    }
  }

  Future<void> _loadPanelWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedWidth = prefs.getDouble('stock_movements_panel_width');
      if (savedWidth != null && mounted) {
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
    final service = context.read<StockMovementsService>();
    final storeNow = stockMovementStoreTime(
      DateTime.now().toUtc(),
      storeTimezone: service.storeTimezone,
    );
    final firstDate = DateTime(2020);
    final lastDate = DateTime(storeNow.year, storeNow.month, storeNow.day);
    final selectedRange = _startDate != null && _endDate != null
        ? DateTimeRange(start: _startDate!, end: _endDate!)
        : null;
    final initialRange = selectedRange != null &&
            !selectedRange.start.isBefore(firstDate) &&
            !selectedRange.end.isAfter(lastDate)
        ? selectedRange
        : null;
    final result = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialRange,
    );

    if (!mounted) return;
    if (result != null) {
      setState(() {
        _startDate = result.start;
        _endDate = result.end;
      });
      await _pushFilters();
    }
  }

  void _clearDateRange() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    unawaited(_pushFilters(explicitAllPeriod: true));
  }

  void _clearAllMovementFilters() {
    setState(() {
      _movementTypeFilter = 'all';
      _startDate = null;
      _endDate = null;
    });
    unawaited(_pushFilters(explicitAllPeriod: true));
  }

  /// Hands the current filters to the service, which refetches when the date
  /// range changed. The range must reach the query: applying it to the newest
  /// rows already in memory answers a different question than the one asked.
  Future<void> _pushFilters({bool explicitAllPeriod = false}) async {
    final service = context.read<StockMovementsService>();
    if (explicitAllPeriod && _startDate == null && _endDate == null) {
      // `clearPeriod` owns the durable "Todo el período" intent. Merely pushing
      // two null dates makes the next Realtime refresh look like an initial
      // load, which reinstates the default 30-day period.
      await service.applyFilters(
        type: _movementTypeFilter,
        refetch: false,
      );
      await service.clearPeriod();
      return;
    }
    await service.applyFilters(
      type: _movementTypeFilter,
      startDate: _startDate,
      endDate: _endDate,
    );
  }

  void _closeInspector() {
    _linkedDocumentRequestGeneration++;
    _operationTraceRequestGeneration++;
    setState(() {
      _selectedLinkedMovement = null;
      _selectedSalesInvoice = null;
      _selectedPurchaseInvoice = null;
      _selectedStockAdjustment = null;
      _linkedDocumentError = null;
      _isLoadingLinkedDocument = false;
      _selectedOperationTrace = null;
      _isLoadingOperationTrace = false;
      _operationTraceError = null;
    });
  }

  /// Routes to the module that owns the loaded document. `push`, so the
  /// ledger, its filters and its scroll are all still here on return.
  void _openLinkedDocumentRoute() {
    final movement = _selectedLinkedMovement;
    final referenceId = movement?.navigableReferenceId;
    if (movement != null && referenceId != null) {
      if (movement.isPurchaseReceiptMovement) {
        unawaited(
          context.push(
            '/purchases/receipts/${Uri.encodeComponent(referenceId)}',
          ),
        );
        return;
      }
      if (movement.isMechanicJobSourceDocument) {
        unawaited(
          context.push('/taller/pegas/${Uri.encodeComponent(referenceId)}'),
        );
        return;
      }
      if (movement.isOnlineOrderSourceDocument) {
        unawaited(
          context.push(
            '/website/orders?order=${Uri.encodeQueryComponent(referenceId)}',
          ),
        );
        return;
      }
    }

    final sales = _selectedSalesInvoice;
    if (sales?.id != null) {
      unawaited(context.push('/sales/invoices/${sales!.id}'));
      return;
    }
    final purchase = _selectedPurchaseInvoice;
    if (purchase?.id != null) {
      unawaited(context.push('/purchases/${purchase!.id}/detail'));
    }
  }

  Future<void> _navigateToReference(StockMovement movement) async {
    final documentGeneration = ++_linkedDocumentRequestGeneration;
    final referenceId = movement.navigableReferenceId;

    // Every row can be inspected — the movement and its evidence exist even
    // when no document backs them. The old behaviour returned early here, so
    // exactly the rows most worth questioning could not be opened at all.
    if (!movement.hasNavigableReference ||
        referenceId == null ||
        !_loadsInlineDocument(movement)) {
      setState(() {
        _selectedLinkedMovement = movement;
        _selectedSalesInvoice = null;
        _selectedPurchaseInvoice = null;
        _selectedStockAdjustment = null;
        _linkedDocumentError = null;
        _isLoadingLinkedDocument = false;
        _selectedOperationTrace = null;
        _isLoadingOperationTrace = movement.operationId != null;
        _operationTraceError = null;
      });
      unawaited(_loadOperationTrace(movement));
      return;
    }

    setState(() {
      _selectedLinkedMovement = movement;
      _selectedSalesInvoice = null;
      _selectedPurchaseInvoice = null;
      _selectedStockAdjustment = null;
      _linkedDocumentError = null;
      _isLoadingLinkedDocument = true;
      _selectedOperationTrace = null;
      _isLoadingOperationTrace = movement.operationId != null;
      _operationTraceError = null;
    });
    unawaited(_loadOperationTrace(movement));

    try {
      if (movement.isStockAdjustmentSourceDocument ||
          (!movement.hasTypedSourceDocument &&
              movement.category == StockMovementCategory.adjustment)) {
        final adjustment = await context
            .read<module_inventory.InventoryService>()
            .getStockAdjustmentDetails(referenceId);
        if (!_isCurrentDocumentRequest(movement, documentGeneration)) return;

        setState(() {
          _selectedStockAdjustment = adjustment;
          _isLoadingLinkedDocument = false;
        });
        return;
      }

      if (movement.isPurchaseInvoiceSourceDocument ||
          (!movement.hasTypedSourceDocument &&
              movement.category == StockMovementCategory.purchase)) {
        final invoice = await context
            .read<PurchaseService>()
            .getPurchaseInvoice(referenceId, refresh: true);
        if (!_isCurrentDocumentRequest(movement, documentGeneration)) return;

        if (invoice == null) {
          throw Exception('No se pudo cargar la factura de compra.');
        }

        setState(() {
          _selectedPurchaseInvoice = invoice;
          _isLoadingLinkedDocument = false;
        });
        return;
      }

      if (movement.hasTypedSourceDocument &&
          !movement.isSalesInvoiceSourceDocument) {
        throw StateError(
          'El tipo de documento fuente no tiene un cargador de detalle.',
        );
      }

      final salesService = context.read<SalesService>();
      final invoice = await salesService.fetchInvoice(
        referenceId,
        refresh: true,
      );
      await salesService.loadPayments(forceRefresh: false);
      if (!_isCurrentDocumentRequest(movement, documentGeneration)) return;

      if (invoice == null) {
        throw Exception('No se pudo cargar la factura de venta.');
      }

      setState(() {
        _selectedSalesInvoice = invoice;
        _isLoadingLinkedDocument = false;
      });
    } catch (e) {
      if (!_isCurrentDocumentRequest(movement, documentGeneration)) return;
      setState(() {
        _linkedDocumentError = e.toString();
        _isLoadingLinkedDocument = false;
      });
    }
  }

  bool _loadsInlineDocument(StockMovement movement) {
    if (movement.hasTypedSourceDocument) {
      return movement.isSalesInvoiceSourceDocument ||
          movement.isPurchaseInvoiceSourceDocument ||
          movement.isStockAdjustmentSourceDocument;
    }
    return movement.category == StockMovementCategory.sale ||
        movement.category == StockMovementCategory.purchase ||
        movement.category == StockMovementCategory.adjustment;
  }

  bool _canOpenSelectedDocument(StockMovement movement) {
    if (movement.navigableReferenceId == null) return false;
    return movement.isPurchaseReceiptMovement ||
        movement.isMechanicJobSourceDocument ||
        movement.isOnlineOrderSourceDocument ||
        _selectedSalesInvoice != null ||
        _selectedPurchaseInvoice != null;
  }

  bool _isCurrentDocumentRequest(StockMovement movement, int generation) {
    return mounted &&
        generation == _linkedDocumentRequestGeneration &&
        _selectedLinkedMovement?.id == movement.id;
  }

  Future<void> _loadOperationTrace(StockMovement movement) async {
    final operationId = movement.operationId;
    if (operationId == null) return;
    final traceGeneration = ++_operationTraceRequestGeneration;
    try {
      final trace = await context
          .read<StockMovementsService>()
          .getOperationTrace(operationId);
      if (!_isCurrentTraceRequest(movement, traceGeneration)) return;
      setState(() {
        _selectedOperationTrace = trace;
        _isLoadingOperationTrace = false;
        _operationTraceError = trace == null
            ? 'La operación registrada no está disponible para esta empresa.'
            : null;
      });
    } catch (_) {
      if (!_isCurrentTraceRequest(movement, traceGeneration)) return;
      setState(() {
        _isLoadingOperationTrace = false;
        _operationTraceError = 'No se pudo cargar la traza de la operación.';
      });
    }
  }

  bool _isCurrentTraceRequest(StockMovement movement, int generation) {
    return mounted &&
        generation == _operationTraceRequestGeneration &&
        _selectedLinkedMovement?.id == movement.id;
  }

  void _closeLinkedDocument() {
    _linkedDocumentRequestGeneration++;
    _operationTraceRequestGeneration++;
    setState(() {
      _selectedLinkedMovement = null;
      _selectedSalesInvoice = null;
      _selectedPurchaseInvoice = null;
      _selectedStockAdjustment = null;
      _linkedDocumentError = null;
      _isLoadingLinkedDocument = false;
      _selectedOperationTrace = null;
      _isLoadingOperationTrace = false;
      _operationTraceError = null;
    });
  }

  void _selectRecentMode() {
    _closeLinkedDocument();
    setState(() => _viewMode = StockMovementsViewMode.recent);
    context.read<StockMovementsService>().setViewMode('recent');
  }

  void _selectProductMode() {
    _closeLinkedDocument();
    setState(() => _viewMode = StockMovementsViewMode.byProduct);
    context.read<StockMovementsService>().setViewMode('by_product');
    _ensureInitialProductPreview();
  }

  void _backToProductList() {
    _closeLinkedDocument();
    context.read<StockMovementsService>().clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final movementsService = context.watch<StockMovementsService>();
    final isRecentMode = _viewMode == StockMovementsViewMode.recent;
    final isCompact = ResponsiveViewport.usesCompactShell(context);
    final hasCompactWorkspace = isCompact &&
        (_selectedLinkedMovement != null ||
            (!isRecentMode && movementsService.selectedProductId != null));

    return MainLayout(
      child: PopScope(
        canPop: !hasCompactWorkspace,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || !hasCompactWorkspace) return;
          if (_selectedLinkedMovement != null) {
            _closeLinkedDocument();
          } else {
            _backToProductList();
          }
        },
        child: StockMovementsResponsiveFrame(
          isRecentMode: isRecentMode,
          hasSelectedProduct: movementsService.selectedProductId != null,
          recentScopeLabel: _compactRecentScopeLabel(movementsService),
          desktopHeader: _buildHeader(),
          recentBody: _buildMovementDetails(),
          productList: _buildProductList(),
          productDetail: _buildMovementDetails(),
          onSelectRecentMode: _selectRecentMode,
          onSelectProductMode: _selectProductMode,
          onBackToProducts: _backToProductList,
          desktopProductListWidth: _productListWidth,
          onDesktopPanelResize: _updatePanelWidth,
        ),
      ),
    );
  }

  String _compactRecentScopeLabel(StockMovementsService service) {
    final start = service.startDate;
    final end = service.endDate;
    if (start != null && end != null) {
      return '${DateFormat('dd/MM/yy').format(start)} – '
          '${DateFormat('dd/MM/yy').format(end)}';
    }
    if (service.isAllPeriodScope) {
      return service.isWindowTruncated
          ? 'Ventana de ${StockMovementsService.recentWindow} registros'
          : 'Todo el período';
    }
    return service.isLoading ? 'Cargando período reciente' : 'Período reciente';
  }

  /// The module's own title band.
  ///
  /// It carries one thing the workspace tab does not: which of the two
  /// readings is active. It deliberately no longer states the scope — the
  /// scope bar directly below owns that, and a second copy here is how the
  /// header came to announce "los últimos 100 movimientos" over a ledger that
  /// had been showing the last 30 days for some time.
  Widget _buildHeader() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isRecentMode = _viewMode == StockMovementsViewMode.recent;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Text(
            'Movimientos de stock',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 20),
          // Two readings of the same ledger, not two destinations: a segmented
          // control states both alternatives and the current one at zero click
          // cost, which a pair of filled buttons never did.
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildViewModeButton(
                  icon: Icons.receipt_long_outlined,
                  label: 'Todo el movimiento',
                  isSelected: isRecentMode,
                  onTap: _selectRecentMode,
                ),
                _buildViewModeButton(
                  icon: Icons.inventory_2_outlined,
                  label: 'Por producto',
                  isSelected: !isRecentMode,
                  onTap: _selectProductMode,
                ),
              ],
            ),
          ),
          const Spacer(),
          if (!isRecentMode && !_hasSelectedProduct)
            Text(
              'Elige un producto para ver su historial',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  bool get _hasSelectedProduct =>
      context.read<StockMovementsService>().selectedProductId != null;

  Widget _buildViewModeButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Vista $label',
      onTap: onTap,
      excludeSemantics: true,
      // A segment, not a button. The selected one is a raised surface inside
      // the track; the other is plain text on it. A saturated blue fill made a
      // reading mode look like the screen's primary action, which it is not.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.surface
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(context)
                        .colorScheme
                        .shadow
                        .withValues(alpha: 0.06),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 34),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isSelected
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductList() {
    return Consumer<InventoryService>(
      builder: (context, inventoryService, _) {
        final isSearching = _searchQuery.trim().isNotEmpty;
        final products = isSearching
            ? (_productSearchResults ?? const <Product>[])
            : inventoryService.products;
        final showInitialLoading = products.isEmpty &&
            ((isSearching && _isProductSearchLoading) ||
                (!isSearching &&
                    (inventoryService.isLoading || _isLoadingProductPreview)));
        final canLoadMoreProducts = !isSearching &&
            !inventoryService.hasLoaded &&
            inventoryService.hasMorePreviewPages;
        final showLoadingFooter = !isSearching &&
            products.isNotEmpty &&
            (_isLoadingProductPreview || canLoadMoreProducts);

        final countText = isSearching
            ? (_isProductSearchLoading &&
                    _activeProductSearchQuery == _searchQuery.trim()
                ? 'Buscando...'
                : '${products.length} resultados')
            : inventoryService.hasLoaded
                ? '${products.length} productos'
                : '${products.length} productos cargados';

        return Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: SearchBarWidget(
                controller: _searchController,
                hintText: 'Buscar producto por nombre o SKU...',
                onChanged: _onProductSearchChanged,
              ),
            ),
            // Product count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    countText,
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
              child: showInitialLoading
                  ? const Center(child: BrandedLoading())
                  : products.isEmpty
                      ? Center(
                          child: Text(
                            isSearching
                                ? 'Sin resultados'
                                : 'No hay productos cargados',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          controller: _productListScrollController,
                          itemCount:
                              products.length + (showLoadingFooter ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= products.length) {
                              if (_isLoadingProductPreview) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(child: BrandedLoading()),
                                );
                              }
                              return TextButton.icon(
                                onPressed: _loadNextProductPreviewPage,
                                icon: const Icon(Icons.expand_more),
                                label: const Text('Cargar más productos'),
                              );
                            }

                            final product = products[index];
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
    void selectProduct() {
      _closeLinkedDocument();
      context.read<StockMovementsService>().loadMovementsForProduct(product.id);
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          'Ver movimientos de ${product.name}, stock ${product.stockQuantity}',
      onTap: selectProduct,
      excludeSemantics: true,
      child: Material(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        child: InkWell(
          onTap: selectProduct,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 3,
                ),
                bottom: BorderSide(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.18),
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
                    size: 80, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 16),
                Text(
                  'Selecciona un producto',
                  style: TextStyle(
                      fontSize: 18, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(
                  'para ver su historial de movimientos',
                  style: TextStyle(
                      fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
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

        if (movementsService.error != null &&
            movementsService.movements.isEmpty) {
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
                        style: TextStyle(
                            fontSize: 18, color: theme.colorScheme.onSurface),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No se pudo obtener el libro de stock.',
                        style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => _retryMovementLoad(movementsService),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        // Filters compose inside the service and the date range is applied by
        // the query, so this list is the real answer to what was asked.
        final movements = movementsService.visibleMovements;

        return Column(
          children: [
            if (selectedProduct != null)
              _buildSelectedProductHeader(
                theme,
                selectedProduct,
                movementCount: movements.length,
              ),
            if (movementsService.error != null)
              _buildMovementRefreshWarning(movementsService),
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

  Widget _buildMovementRefreshWarning(StockMovementsService service) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: colors.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: colors.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No se pudo actualizar. Se conserva el último libro cargado.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _retryMovementLoad(service),
            style: TextButton.styleFrom(
              foregroundColor: colors.onErrorContainer,
              minimumSize: const Size(48, 40),
            ),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  void _retryMovementLoad(StockMovementsService service) {
    if (service.isRecentMode) {
      unawaited(service.loadRecentMovements());
      return;
    }
    final productId = service.selectedProductId;
    if (productId != null) {
      unawaited(service.loadMovementsForProduct(productId));
    }
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
    final isCompact = ResponsiveViewport.usesCompactShell(context);

    if (isCompact) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                    ? ImageService.buildProductImage(
                        imageUrl: thumbnailUrl,
                        size: 48,
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
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
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
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${product.stockQuantity} stock',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$movementCount mov.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

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
    if (movements.isEmpty && _selectedLinkedMovement == null) {
      final isRecentMode = context.read<StockMovementsService>().isRecentMode;
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
                    : isRecentMode
                        ? 'No hay movimientos en este período'
                        : 'No hay movimientos para este producto',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _hasActiveMovementFilters
                    ? 'Prueba quitando el tipo o el rango de fechas para ver más resultados.'
                    : isRecentMode
                        ? 'No se registraron cambios de stock dentro del período cargado.'
                        : 'Este producto todavía no registra cambios de stock.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
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

    // One ledger for every width. The old split rendered a horizontally
    // panning table on desktop and a wall of cards on compact — two different
    // readings of the same statement, and neither let a column be scanned
    // vertically, which is the only reason to put figures in a column.
    final service = context.read<StockMovementsService>();
    final ledger = StockLedger(
      movements: movements,
      chronological: service.isChronological,
      sortKey: service.sortKey,
      ascending: service.ascending,
      storeTimezone: service.storeTimezone,
      showProduct: service.isRecentMode,
      selectedId: _selectedLinkedMovement?.id,
      scrollController: _ledgerScrollController,
      onSort: (key) {
        final ascending = service.sortKey == key ? !service.ascending : false;
        unawaited(service.applySort(key, ascending: ascending));
      },
      onOpen: _navigateToReference,
    );

    final selected = _selectedLinkedMovement;
    if (selected == null) return ledger;

    final inspector = MovementInspector(
      key: ValueKey('movement-inspector-${selected.id}'),
      movement: selected,
      storeTimezone: service.storeTimezone,
      salesInvoice: _selectedSalesInvoice,
      purchaseInvoice: _selectedPurchaseInvoice,
      adjustment: _selectedStockAdjustment,
      loadingDocument: _isLoadingLinkedDocument,
      documentError: _linkedDocumentError,
      onRetryDocument: _loadsInlineDocument(selected)
          ? () => _navigateToReference(selected)
          : null,
      operationTrace: _selectedOperationTrace,
      loadingOperationTrace: _isLoadingOperationTrace,
      operationTraceError: _operationTraceError,
      onRetryOperationTrace: () {
        setState(() {
          _selectedOperationTrace = null;
          _operationTraceError = null;
          _isLoadingOperationTrace = selected.operationId != null;
        });
        unawaited(_loadOperationTrace(selected));
      },
      onOpenDocument:
          _canOpenSelectedDocument(selected) ? _openLinkedDocumentRoute : null,
      onClose: _closeInspector,
    );

    // With room, the inspector participates in layout beside the ledger:
    // rows stay clickable and inspecting a run of them costs one click each.
    // Without room it takes the pane, and closing restores the exact ledger
    // because the ledger never unmounted its state.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1080) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: ledger),
              Container(
                width: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              SizedBox(width: 380, child: inspector),
            ],
          );
        }
        return inspector;
      },
    );
  }

  /// Mirrors the service's scope into the page's controls.
  ///
  /// The service is the single owner: it is what the query uses, so it is what
  /// the bar must display. Keeping a second copy here is how the bar came to
  /// claim a period the query was not using.
  void _syncScopeFromService(StockMovementsService service) {
    _movementTypeFilter = service.typeFilter ?? 'all';
    _startDate = service.startDate;
    _endDate = service.endDate;
  }

  Widget _buildMovementFilters(StockMovementsService service) {
    _syncScopeFromService(service);
    if (ResponsiveViewport.usesCompactShell(context)) {
      final hasDateRange = _startDate != null && _endDate != null;
      final compactDateLabel = hasDateRange
          ? '${DateFormat('dd/MM').format(_startDate!)}–'
              '${DateFormat('dd/MM').format(_endDate!)}'
          : 'Fechas';

      return Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border(
              bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: SizedBox(
                height: 48,
                child: DropdownButtonFormField<String>(
                  initialValue: _movementTypeFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Todos')),
                    DropdownMenuItem(value: 'purchase', child: Text('Compras')),
                    DropdownMenuItem(value: 'sale', child: Text('Ventas')),
                    DropdownMenuItem(
                        value: 'adjustment', child: Text('Ajustes')),
                    DropdownMenuItem(
                      value: 'transfer',
                      child: Text('Transferencias'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _movementTypeFilter = value ?? 'all');
                    unawaited(_pushFilters());
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: Semantics(
                button: true,
                label: hasDateRange
                    ? 'Cambiar rango de fechas, $compactDateLabel'
                    : 'Elegir rango de fechas',
                child: OutlinedButton(
                  onPressed: _selectDateRange,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: hasDateRange
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    backgroundColor: hasDateRange
                        ? Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withValues(alpha: 0.55)
                        : null,
                  ),
                  child: Text(
                    compactDateLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            if (_hasActiveMovementFilters) ...[
              const SizedBox(width: 4),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  onPressed: _clearAllMovementFilters,
                  icon: const Icon(Icons.filter_alt_off, size: 20),
                  tooltip: 'Quitar todos los filtros',
                ),
              ),
            ],
          ],
        ),
      );
    }

    // A scope bar, not a form. The type selector used to be a full-width
    // outlined field with a floating label, so a one-word value claimed most of
    // the row while the date range — the filter that actually changes the
    // answer — was pushed to the edge. Both are now compact peers sized to
    // their content.
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasRange = _startDate != null && _endDate != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          _MovementScopeControl(
            icon: Icons.filter_list,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _movementTypeFilter,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'all', child: Text('Todo movimiento')),
                  DropdownMenuItem(value: 'purchase', child: Text('Compras')),
                  DropdownMenuItem(value: 'sale', child: Text('Ventas')),
                  DropdownMenuItem(value: 'adjustment', child: Text('Ajustes')),
                  DropdownMenuItem(
                      value: 'transfer', child: Text('Transferencias')),
                ],
                onChanged: (value) {
                  setState(() => _movementTypeFilter = value ?? 'all');
                  unawaited(_pushFilters());
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          _MovementScopeControl(
            icon: Icons.event_outlined,
            selected: hasRange,
            onTap: _selectDateRange,
            onClear: hasRange ? _clearDateRange : null,
            child: Text(
              hasRange
                  ? '${DateFormat('dd/MM/yy').format(_startDate!)} – '
                      '${DateFormat('dd/MM/yy').format(_endDate!)}'
                  : 'Todo el período',
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    hasRange ? colors.onSecondaryContainer : colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          if (_hasActiveMovementFilters)
            TextButton(
              onPressed: _clearAllMovementFilters,
              style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
              child: const Text('Quitar filtros'),
            ),
        ],
      ),
    );
  }

  Widget _buildMovementSummary(List<StockMovement> movements) {
    final summary = _buildFilteredSummary(movements);
    final truncated = context.read<StockMovementsService>().isWindowTruncated;

    // A total computed over the newest rows describes the window, not the
    // business. Say so rather than presenting it as the period's figure.
    if (truncated) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTruncatedSummaryNotice(),
          _buildMovementSummaryMetrics(summary),
        ],
      );
    }

    return _buildMovementSummaryMetrics(summary);
  }

  Widget _buildTruncatedSummaryNotice() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      color: theme.colorScheme.tertiaryContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 17,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Totales sobre una ventana de '
              '${StockMovementsService.recentWindow} registros según el orden '
              'actual, no sobre todo el período. Elige un rango de fechas para '
              'un total exacto.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementSummaryMetrics(Map<String, int> summary) {
    if (ResponsiveViewport.usesCompactShell(context)) {
      final netChange = summary['net_change'] ?? 0;
      final metrics = <({String label, String value, Color color})>[
        (
          label: _hasActiveMovementFilters ? 'Resultados' : 'Movimientos',
          value: summary['transaction_count'].toString(),
          color: Theme.of(context).colorScheme.primary,
        ),
        (
          label: 'Entradas',
          value: '+${summary['total_increase']}',
          color: Theme.of(context).colorScheme.primary,
        ),
        (
          label: 'Salidas',
          value: '-${summary['total_decrease']}',
          color: Theme.of(context).colorScheme.error,
        ),
        (
          label: 'Neto',
          value: netChange >= 0 ? '+$netChange' : '$netChange',
          color: netChange >= 0
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
        if ((summary['warning_count'] ?? 0) > 0)
          (
            label: 'A revisar',
            value: summary['warning_count'].toString(),
            color: Theme.of(context).colorScheme.tertiary,
          ),
      ];

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 7,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: itemWidth,
                    child: Semantics(
                      label: '${metric.label}: ${metric.value}',
                      excludeSemantics: true,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              metric.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            metric.value,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                              color: metric.color,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    // Comparable figures share one aligned row separated by hairlines. The
    // previous strip gave each metric its own coloured icon disc over a tinted
    // blue band, which is decoration competing with four numbers that are only
    // useful when read against each other.
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final net = summary['net_change'] ?? 0;
    final warnings = summary['warning_count'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _MovementFigure(
            label: _hasActiveMovementFilters ? 'Resultados' : 'Transacciones',
            value: summary['transaction_count'].toString(),
          ),
          _MovementFigure(
            label: 'Entradas',
            value: '+${summary['total_increase']}',
            divided: true,
          ),
          _MovementFigure(
            label: 'Salidas',
            value: '−${summary['total_decrease']}',
            divided: true,
          ),
          _MovementFigure(
            label: 'Cambio neto',
            value: net >= 0 ? '+$net' : '$net',
            tone: net >= 0 ? colors.primary : colors.error,
            emphasized: true,
            divided: true,
          ),
          const Spacer(),
          if (warnings > 0)
            Tooltip(
              message: 'Movimientos cuya evidencia de origen está incompleta. '
                  'Casi siempre son anteriores al registro de trazabilidad.',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '$warnings ${warnings == 1 ? 'fila' : 'filas'} con '
                    'evidencia parcial',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
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
    var warningCount = 0;

    for (final movement in movements) {
      final quantity = movement.summaryQuantity;
      netChange += quantity;
      if (quantity >= 0) {
        totalIncrease += quantity;
      } else {
        totalDecrease += quantity.abs();
      }
      if (movement.hasIntegrityWarning) {
        warningCount++;
      }
    }

    return {
      'transaction_count': movements.length,
      'total_increase': totalIncrease,
      'total_decrease': totalDecrease,
      'net_change': netChange,
      'warning_count': warningCount,
    };
  }

  final ScrollController _ledgerScrollController = ScrollController();
  final ScrollController _productListScrollController = ScrollController();

  @override
  void dispose() {
    _productSearchDebounce?.cancel();
    _ledgerScrollController.dispose();
    _productListScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Mobile card layout for smaller screens
}

/// One compact scope control in the movements filter bar.
///
/// Both filters are peers sized to their content: a scope bar states what you
/// are looking at, it is not a form to fill in.
class _MovementScopeControl extends StatelessWidget {
  const _MovementScopeControl({
    required this.icon,
    required this.child,
    this.selected = false,
    this.onTap,
    this.onClear,
  });

  final IconData icon;
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.secondaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: EdgeInsets.fromLTRB(11, 0, onClear == null ? 11 : 4, 0),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? Colors.transparent : colors.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? colors.onSecondaryContainer
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              child,
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 15),
                  tooltip: 'Quitar el rango',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                  color: colors.onSecondaryContainer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One figure in the movements summary row.
///
/// The hairline on the left is what groups these numbers as comparable. It
/// replaces a coloured icon disc per metric, which drew the eye to the
/// decoration rather than to the values being compared.
class _MovementFigure extends StatelessWidget {
  const _MovementFigure({
    required this.label,
    required this.value,
    this.tone,
    this.emphasized = false,
    this.divided = false,
  });

  final String label;
  final String value;
  final Color? tone;
  final bool emphasized;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: EdgeInsets.only(left: divided ? 20 : 0),
      padding: EdgeInsets.only(left: divided ? 20 : 0),
      decoration: divided
          ? BoxDecoration(
              border: Border(left: BorderSide(color: colors.outlineVariant)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: (emphasized
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.titleSmall)
                ?.copyWith(
              color: tone ?? colors.onSurface,
              fontWeight: FontWeight.w700,
              height: 1.05,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
