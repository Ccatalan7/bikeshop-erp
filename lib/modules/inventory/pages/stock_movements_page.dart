import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/product.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../models/stock_movement.dart';
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
  double _colFinWidth = 50.0;

  static const double _minColWidth = 40.0;

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
            colorScheme: ColorScheme.light(
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

  void _navigateToReference(StockMovement movement) {
    if (movement.referenceId == null) return;

    final type = movement.movementType.toLowerCase();

    if (type == 'purchase') {
      context.push(
        '/purchases/${movement.referenceId}?referrer=movements',
        extra: {'readOnly': true},
      );
    } else if (type == 'sale' || type == 'venta') {
      context.push(
        '/sales/invoices/${movement.referenceId}?referrer=movements',
        extra: {'readOnly': true},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final movementsService = context.watch<StockMovementsService>();
    final isRecentMode = movementsService.isRecentMode;

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
    final isRecentMode = movementsService.isRecentMode;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                  onTap: () => movementsService.setViewMode('recent'),
                ),
                _buildViewModeButton(
                  icon: Icons.inventory_2,
                  label: 'Por Producto',
                  isSelected: !isRecentMode,
                  onTap: () => movementsService.setViewMode('by_product'),
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
          final matchesSearch = _searchQuery.isEmpty ||
              p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              p.sku.toLowerCase().contains(_searchQuery.toLowerCase());
          return matchesSearch;
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

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue.withOpacity(0.1) : null,
        border: Border(
          left: BorderSide(
            color: isSelected ? Colors.blue : Colors.transparent,
            width: 4,
          ),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isSelected ? Colors.blue : Colors.grey[300],
          child: Text(
            product.stockQuantity.toString(),
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          product.name,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(product.sku),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: isSelected ? Colors.blue : Colors.grey,
        ),
        onTap: () {
          context
              .read<StockMovementsService>()
              .loadMovementsForProduct(product.id);
        },
      ),
    );
  }

  Widget _buildMovementDetails() {
    return Consumer<StockMovementsService>(
      builder: (context, movementsService, _) {
        final isRecentMode = movementsService.isRecentMode;

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
          return const Center(child: BrandedLoading());
        }

        if (movementsService.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
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
          );
        }

        // Apply filters
        var movements = movementsService.movements;
        movements = movementsService.filterByType(_movementTypeFilter);
        movements = movementsService.filterByDateRange(_startDate, _endDate);

        return Column(
          children: [
            _buildMovementFilters(movementsService),
            _buildMovementSummary(movementsService),
            const Divider(height: 1),
            Expanded(
              child: movements.isEmpty
                  ? Center(
                      child: Text(
                        'No hay movimientos para este producto',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 600;

                        if (isWide) {
                          // Desktop: Full-width table with horizontal scroll
                          // Ensure we use the full available width or the calculated total, whichever is larger
                          final tableWidth =
                              _totalTableWidth > constraints.maxWidth
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
                                          return _buildMovementRow(
                                              movements[index]);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        } else {
                          // Mobile: Card-based layout
                          return ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: movements.length,
                            itemBuilder: (context, index) {
                              return _buildMovementCard(movements[index]);
                            },
                          );
                        }
                      },
                    ),
            ),
          ],
        );
      },
    );
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
              value: _movementTypeFilter,
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
                  ? Colors.blue.withOpacity(0.1)
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
        ],
      ),
    );
  }

  Widget _buildMovementSummary(StockMovementsService service) {
    final summary = service.getSummary();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          _buildSummaryItem(
            'Transacciones',
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
    final movementsService = context.watch<StockMovementsService>();
    final showProductColumn = movementsService.isRecentMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          // Product column (only in recent mode)
          if (showProductColumn) ...[
            SizedBox(
              width: _colProductWidth,
              child: const Text('Producto',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            _buildResizeHandle((delta) => setState(() => _colProductWidth =
                (_colProductWidth + delta).clamp(_minColWidth, 400))),
          ],
          SizedBox(
            width: _colDateWidth,
            child: const Text('Fecha',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          _buildResizeHandle((delta) => setState(() => _colDateWidth =
              (_colDateWidth + delta).clamp(_minColWidth, 200))),
          SizedBox(
            width: _colTypeWidth,
            child: const Text('Tipo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          _buildResizeHandle((delta) => setState(() => _colTypeWidth =
              (_colTypeWidth + delta).clamp(_minColWidth, 150))),
          SizedBox(
            width: _colSourceWidth,
            child: const Text('Origen',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          _buildResizeHandle((delta) => setState(() => _colSourceWidth =
              (_colSourceWidth + delta).clamp(_minColWidth, 200))),
          SizedBox(
            width: _colRefWidth,
            child: const Text('Referencia',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          _buildResizeHandle((delta) => setState(() =>
              _colRefWidth = (_colRefWidth + delta).clamp(_minColWidth, 200))),
          SizedBox(
            width: _colIniWidth,
            child: const Text('Ini',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                textAlign: TextAlign.right),
          ),
          _buildResizeHandle((delta) => setState(
              () => _colIniWidth = (_colIniWidth + delta).clamp(35, 80))),
          SizedBox(
            width: _colMovWidth,
            child: const Text('Mov',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                textAlign: TextAlign.right),
          ),
          _buildResizeHandle((delta) => setState(
              () => _colMovWidth = (_colMovWidth + delta).clamp(35, 80))),
          SizedBox(
            width: _colFinWidth,
            child: const Text('Fin',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                textAlign: TextAlign.right),
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
    final movementsService = context.watch<StockMovementsService>();
    final showProductColumn = movementsService.isRecentMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
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
              style: const TextStyle(fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          // Type
          SizedBox(
            width: _colTypeWidth,
            child: _buildTypeChip(movement),
          ),
          const SizedBox(width: 8),
          // Source
          SizedBox(
            width: _colSourceWidth,
            child: Text(
              movement.sourceDisplay,
              style: const TextStyle(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Reference
          SizedBox(
            width: _colRefWidth,
            child: movement.referenceNumber != null
                ? InkWell(
                    onTap: () => _navigateToReference(movement),
                    child: Text(
                      movement.referenceNumber!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  )
                : const Text('-', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 8),
          // Stock Before
          SizedBox(
            width: _colIniWidth,
            child: Text(
              movement.stockBefore.toString(),
              style: const TextStyle(fontSize: 11),
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
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: movement.isIncrease ? Colors.green : Colors.red,
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
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // Mobile card layout for smaller screens
  Widget _buildMovementCard(StockMovement movement) {
    final dateFormat = DateFormat('dd/MM/yy HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product name + type chip
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
            ),
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
                Text(
                  movement.sourceDisplay,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                    onTap: () => _navigateToReference(movement),
                    child: Text(
                      movement.referenceNumber!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
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
    switch (movement.movementType) {
      case 'purchase':
        color = Colors.green;
        break;
      case 'sale':
        color = Colors.blue;
        break;
      case 'adjustment':
        color = Colors.orange;
        break;
      case 'transfer':
        color = Colors.purple;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
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
