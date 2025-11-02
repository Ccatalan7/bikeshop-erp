import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/product.dart';
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

  @override
  void initState() {
    super.initState();
    _loadPanelWidth();
    // Load products on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
      _productListWidth = (_productListWidth + delta).clamp(_minPanelWidth, _maxPanelWidth);
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

    if (movement.movementType == 'purchase') {
      context.push(
        '/purchases/invoice/${movement.referenceId}',
        extra: {'readOnly': true},
      );
    } else if (movement.movementType == 'sale') {
      context.push(
        '/sales/invoice/${movement.referenceId}',
        extra: {'readOnly': true},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Row(
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
          const Spacer(),
          const Text(
            'Selecciona un producto para ver su historial',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList() {
    return Consumer<InventoryService>(
      builder: (context, inventoryService, _) {
        if (inventoryService.isLoading) {
          return const Center(child: CircularProgressIndicator());
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
          context.read<StockMovementsService>().loadMovementsForProduct(product.id);
        },
      ),
    );
  }

  Widget _buildMovementDetails() {
    return Consumer<StockMovementsService>(
      builder: (context, movementsService, _) {
        if (movementsService.selectedProductId == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[300]),
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
          return const Center(child: CircularProgressIndicator());
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
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: 900, // Minimum width for all columns
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
                DropdownMenuItem(value: 'transfer', child: Text('Transferencias')),
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

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
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

  Widget _buildMovementTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 120,
            child: Text('Fecha', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 16),
          SizedBox(
            width: 130,
            child: Text('Tipo', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 16),
          SizedBox(
            width: 150,
            child: Text('Origen', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 16),
          SizedBox(
            width: 130,
            child: Text('Referencia', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: Text('Stock Inicial', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
          ),
          SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: Text('Movimiento', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
          ),
          SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: Text('Stock Final', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementRow(StockMovement movement) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          // Date
          SizedBox(
            width: 120,
            child: Text(
              dateFormat.format(movement.transactionDate),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 16),
          // Type
          SizedBox(
            width: 130,
            child: _buildTypeChip(movement),
          ),
          const SizedBox(width: 16),
          // Source
          SizedBox(
            width: 150,
            child: Text(
              movement.sourceDisplay,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 16),
          // Reference
          SizedBox(
            width: 130,
            child: movement.referenceNumber != null
                ? InkWell(
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
                : const Text(
                    '-',
                    style: TextStyle(fontSize: 12),
                  ),
          ),
          const SizedBox(width: 16),
          // Stock Before
          SizedBox(
            width: 80,
            child: Text(
              movement.stockBefore.toString(),
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 16),
          // Quantity
          SizedBox(
            width: 80,
            child: Text(
              movement.quantity >= 0 ? '+${movement.quantity}' : movement.quantity.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: movement.isIncrease ? Colors.green : Colors.red,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 16),
          // Stock After
          SizedBox(
            width: 80,
            child: Text(
              movement.stockAfter.toString(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
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
