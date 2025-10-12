import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/stock_movement.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../../../shared/themes/app_theme.dart';
import '../services/stock_movement_service.dart';

class StockMovementListPage extends StatefulWidget {
  const StockMovementListPage({super.key});

  @override
  State<StockMovementListPage> createState() => _StockMovementListPageState();
}

class _StockMovementListPageState extends State<StockMovementListPage> {
  final TextEditingController _searchController = TextEditingController();
  late StockMovementService _service;
  
  String? _selectedType;
  DateTime? _startDate;
  DateTime? _endDate;
  Map<String, dynamic>? _statistics;

  @override
  void initState() {
    super.initState();
    _service = StockMovementService();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _service.loadMovements(),
      _loadStatistics(),
    ]);
  }

  Future<void> _loadStatistics() async {
    final stats = await _service.getStatistics(
      startDate: _startDate,
      endDate: _endDate,
    );
    setState(() => _statistics = stats);
  }

  Future<void> _applyFilters() async {
    await _service.loadMovements(
      movementType: _selectedType,
      startDate: _startDate,
      endDate: _endDate,
      searchQuery: _searchController.text,
      forceRefresh: true,
    );
    await _loadStatistics();
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      locale: const Locale('es', 'CL'),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      await _applyFilters();
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedType = null;
      _startDate = null;
      _endDate = null;
      _searchController.clear();
    });
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _service,
      child: MainLayout(
        child: Column(
          children: [
            _buildHeader(),
            _buildStatisticsCards(),
            _buildFilters(),
            _buildSearchBar(),
            const SizedBox(height: 16),
            Expanded(child: _buildMovementsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isMobile = AppTheme.isMobile(context);
    
    return Padding(
      padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          const Expanded(
            child: Text(
              'Movimientos de Stock',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
          if (!isMobile)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              onPressed: _clearFilters,
              tooltip: 'Limpiar filtros',
            ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCards() {
    if (_statistics == null) {
      return const SizedBox.shrink();
    }

    final isMobile = AppTheme.isMobile(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12.0 : 16.0),
      child: isMobile
          ? Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Total',
                        _statistics!['total_movements'].toString(),
                        Icons.swap_horiz,
                        Colors.blue,
                        isMobile,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Entradas',
                        _statistics!['total_in'].toString(),
                        Icons.arrow_downward,
                        Colors.green,
                        isMobile,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Salidas',
                        _statistics!['total_out'].toString(),
                        Icons.arrow_upward,
                        Colors.red,
                        isMobile,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard(
                        'Ajustes',
                        _statistics!['total_adjustments'].toString(),
                        Icons.tune,
                        Colors.orange,
                        isMobile,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total',
                    _statistics!['total_movements'].toString(),
                    Icons.swap_horiz,
                    Colors.blue,
                    isMobile,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Entradas',
                    _statistics!['total_in'].toString(),
                    Icons.arrow_downward,
                    Colors.green,
                    isMobile,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Salidas',
                    _statistics!['total_out'].toString(),
                    Icons.arrow_upward,
                    Colors.red,
                    isMobile,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Ajustes',
                    _statistics!['total_adjustments'].toString(),
                    Icons.tune,
                    Colors.orange,
                    isMobile,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isMobile) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 8.0 : 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: isMobile ? 18 : 20, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isMobile ? 11 : 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            SizedBox(height: isMobile ? 2 : 4),
            Text(
              value,
              style: TextStyle(
                fontSize: isMobile ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // Date range filter
          OutlinedButton.icon(
            onPressed: _selectDateRange,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(
              _startDate != null && _endDate != null
                  ? '${DateFormat('dd/MM/yy').format(_startDate!)} - ${DateFormat('dd/MM/yy').format(_endDate!)}'
                  : 'Rango de fechas',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          // Movement type filter
          DropdownButton<String>(
            value: _selectedType,
            hint: const Text('Tipo de movimiento', style: TextStyle(fontSize: 13)),
            underline: const SizedBox(),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos')),
              const DropdownMenuItem(value: 'sales_invoice', child: Text('Venta')),
              const DropdownMenuItem(value: 'purchase_invoice', child: Text('Compra')),
              const DropdownMenuItem(value: 'adjustment', child: Text('Ajuste')),
              const DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
            ],
            onChanged: (value) {
              setState(() => _selectedType = value);
              _applyFilters();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SearchBarWidget(
        controller: _searchController,
        hintText: 'Buscar por producto, SKU, referencia...',
        onChanged: (value) {
          _applyFilters();
        },
      ),
    );
  }

  Widget _buildMovementsList() {
    return Consumer<StockMovementService>(
      builder: (context, service, child) {
        if (service.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (service.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  service.error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadData,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          );
        }

        if (service.movements.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.swap_horiz, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No hay movimientos',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _searchController.text.isNotEmpty || _selectedType != null
                      ? 'Intenta cambiar los filtros'
                      : 'Los movimientos aparecerán aquí',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          itemCount: service.movements.length,
          itemBuilder: (context, index) {
            final movement = service.movements[index];
            return _buildMovementCard(movement);
          },
        );
      },
    );
  }

  Widget _buildMovementCard(StockMovement movement) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final isInbound = movement.isInbound;
    final color = isInbound ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(
            isInbound ? Icons.arrow_downward : Icons.arrow_upward,
            color: color,
          ),
        ),
        title: Text(
          movement.productName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SKU: ${movement.productSku}'),
            if (movement.movementType != null)
              Text(
                movement.movementTypeDisplay,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            if (movement.reference != null)
              Text(
                movement.reference!,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[600],
                ),
              ),
            Text(
              dateFormat.format(movement.date),
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              movement.formattedQuantity,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              movement.type,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        onTap: () => _showMovementDetails(movement),
      ),
    );
  }

  void _showMovementDetails(StockMovement movement) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalle de Movimiento'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Producto', movement.productName),
              _buildDetailRow('SKU', movement.productSku),
              _buildDetailRow('Tipo', movement.movementTypeDisplay),
              _buildDetailRow('Cantidad', movement.formattedQuantity),
              _buildDetailRow('Dirección', movement.type),
              if (movement.reference != null)
                _buildDetailRow('Referencia', movement.reference!),
              if (movement.notes != null)
                _buildDetailRow('Notas', movement.notes!),
              _buildDetailRow('Fecha', dateFormat.format(movement.date)),
              _buildDetailRow('Creado', dateFormat.format(movement.createdAt)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
