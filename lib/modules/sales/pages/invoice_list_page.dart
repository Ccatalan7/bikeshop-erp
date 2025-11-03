import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';

class InvoiceListPage extends StatefulWidget {
  const InvoiceListPage({super.key});

  @override
  State<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends State<InvoiceListPage> {
  String _searchTerm = '';
  final TextEditingController _searchController = TextEditingController();
  
  Invoice? _selectedInvoice;
  double _listPaneWidth = 600.0;
  static const double _minListPaneWidth = 400.0;
  static const double _maxListPaneWidth = 900.0;
  static const double _minColumnWidth = 80.0;
  static const double _maxColumnWidth = 400.0;
  
  final Map<String, double> _columnWidths = {
    'date': 110.0,
    'invoice_number': 130.0,
    'customer': 180.0,
    'status': 120.0,
    'total': 120.0,
    'balance': 120.0,
  };
  
  final Map<String, bool> _visibleColumns = {
    'date': true,
    'invoice_number': true,
    'customer': true,
    'status': true,
    'total': true,
    'balance': true,
  };
  
  String _sortColumn = 'date';
  bool _sortAscending = false;
  
  @override
  void initState() {
    super.initState();
    _loadPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesService>().loadInvoices();
    });
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _listPaneWidth = prefs.getDouble('invoice_list_pane_width') ?? 600.0;
      
      for (var key in _columnWidths.keys.toList()) {
        _columnWidths[key] = prefs.getDouble('invoice_col_$key') ?? _columnWidths[key]!;
      }
      
      for (var key in _visibleColumns.keys.toList()) {
        _visibleColumns[key] = prefs.getBool('invoice_visible_$key') ?? _visibleColumns[key]!;
      }
    });
  }
  
  Future<void> _saveListPaneWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('invoice_list_pane_width', width);
  }
  
  Future<void> _saveColumnWidth(String column, double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('invoice_col_$column', width);
  }
  
  List<Invoice> _getFilteredAndSortedInvoices(List<Invoice> invoices) {
    List<Invoice> filtered = List.from(invoices);
    
    if (_searchTerm.isNotEmpty) {
      final term = _searchTerm.toLowerCase();
      filtered = filtered.where((invoice) {
        return invoice.invoiceNumber.toLowerCase().contains(term) ||
            (invoice.customerName?.toLowerCase().contains(term) ?? false) ||
            (invoice.customerRut?.toLowerCase().contains(term) ?? false);
      }).toList();
    }
    
    filtered.sort((a, b) {
      int comparison = 0;
      
      switch (_sortColumn) {
        case 'date':
          comparison = a.date.compareTo(b.date);
          break;
        case 'invoice_number':
          comparison = a.invoiceNumber.compareTo(b.invoiceNumber);
          break;
        case 'customer':
          comparison = (a.customerName ?? '').compareTo(b.customerName ?? '');
          break;
        case 'status':
          comparison = a.status.name.compareTo(b.status.name);
          break;
        case 'total':
          comparison = a.total.compareTo(b.total);
          break;
        case 'balance':
          comparison = a.balance.compareTo(b.balance);
          break;
      }
      
      return _sortAscending ? comparison : -comparison;
    });
    
    return filtered;
  }
  
  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final salesService = context.watch<SalesService>();
    final invoices = _getFilteredAndSortedInvoices(salesService.invoices);
    
    return MainLayout(
      title: 'Facturas',
      child: Column(
        children: [
          // Header with New button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Facturas de Venta',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => debugPrint('TODO: Create invoice'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nuevo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // Main content
          Expanded(
            child: _selectedInvoice == null
                ? _buildFullListView(invoices, salesService)
                : _buildSplitView(invoices, salesService),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFullListView(List<Invoice> invoices, SalesService salesService) {
    return Column(
      children: [
        _buildSummaryCards(invoices),
        const SizedBox(height: 16),
        _buildSearchBar(),
        const SizedBox(height: 8),
        Expanded(
          child: _buildInvoiceTable(invoices, salesService, isFullWidth: true),
        ),
      ],
    );
  }
  
  Widget _buildSplitView(List<Invoice> invoices, SalesService salesService) {
    return Row(
      children: [
        // Left pane - Invoice list
        Container(
          width: _listPaneWidth,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              right: BorderSide(color: Colors.grey[300]!, width: 1),
            ),
          ),
          child: Column(
            children: [
              // Search bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[200]!),
                  ),
                ),
                child: _buildSearchBar(),
              ),
              // Invoice cards list
              Expanded(
                child: _buildInvoiceCardsList(invoices),
              ),
            ],
          ),
        ),
        
        // Resize handle
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                _listPaneWidth = (_listPaneWidth + details.delta.dx)
                    .clamp(_minListPaneWidth, _maxListPaneWidth);
              });
            },
            onHorizontalDragEnd: (_) => _saveListPaneWidth(_listPaneWidth),
            child: Container(
              width: 1,
              color: Colors.grey[300],
            ),
          ),
        ),
        
        // Right pane - Invoice preview
        Expanded(
          child: _buildInvoicePreview(_selectedInvoice!),
        ),
      ],
    );
  }
  
  Widget _buildSummaryCards(List<Invoice> invoices) {
    final totalReceivable = invoices
        .where((inv) => inv.status != InvoiceStatus.draft && inv.balance > 0)
        .fold(0.0, (sum, inv) => sum + inv.balance);
    
    final overdue = invoices.where((inv) {
      if (inv.dueDate == null || inv.balance <= 0) return false;
      return inv.dueDate!.isBefore(DateTime.now());
    }).fold(0.0, (sum, inv) => sum + inv.balance);
    
    final dueIn30Days = invoices.where((inv) {
      if (inv.dueDate == null || inv.balance <= 0) return false;
      final now = DateTime.now();
      return inv.dueDate!.isAfter(now) && 
             inv.dueDate!.isBefore(now.add(const Duration(days: 30)));
    }).fold(0.0, (sum, inv) => sum + inv.balance);
    
    final overdueCount = invoices.where((inv) {
      if (inv.dueDate == null || inv.balance <= 0) return false;
      return inv.dueDate!.isBefore(DateTime.now());
    }).length;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          _buildSummaryCard(
            'Total de cuentas pendientes de cobro',
            ChileanUtils.formatCurrency(totalReceivable),
            Icons.account_balance_wallet_outlined,
            Colors.orange,
          ),
          const SizedBox(width: 24),
          _buildSummaryCard(
            'Vencidos hoy',
            ChileanUtils.formatCurrency(overdue),
            Icons.warning_amber_outlined,
            Colors.red,
          ),
          const SizedBox(width: 24),
          _buildSummaryCard(
            'Vence en los próximos 30 días',
            ChileanUtils.formatCurrency(dueIn30Days),
            Icons.schedule_outlined,
            Colors.blue,
          ),
          const SizedBox(width: 24),
          _buildSummaryCard(
            'Facturas vencidas',
            '$overdueCount',
            Icons.receipt_long_outlined,
            overdueCount > 0 ? Colors.red : Colors.green,
          ),
        ],
      ),
    );
  }
  
  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[900],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInvoiceCardsList(List<Invoice> invoices) {
    if (invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No se encontraron facturas',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: invoices.length,
      itemBuilder: (context, index) {
        final invoice = invoices[index];
        final isSelected = _selectedInvoice?.id == invoice.id;
        
        return InkWell(
          onTap: () {
            setState(() {
              _selectedInvoice = isSelected ? null : invoice;
            });
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue[50] : Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!),
                left: isSelected 
                    ? BorderSide(color: Colors.blue, width: 3)
                    : BorderSide.none,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        invoice.customerName ?? 'Sin registro',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      ChileanUtils.formatCurrency(invoice.total),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      invoice.invoiceNumber,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ChileanUtils.formatDate(invoice.date),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildStatusChip(invoice.status),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar en Facturas ( / )',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchTerm.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchTerm = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchTerm = value),
            ),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            icon: const Icon(Icons.view_column_outlined),
            tooltip: 'Columnas',
            itemBuilder: (context) {
              return _visibleColumns.keys.map((column) {
                return CheckedPopupMenuItem<String>(
                  value: column,
                  checked: _visibleColumns[column] ?? false,
                  child: Text(_getColumnLabel(column)),
                );
              }).toList();
            },
            onSelected: (column) {
              setState(() {
                _visibleColumns[column] = !(_visibleColumns[column] ?? false);
              });
              SharedPreferences.getInstance().then((prefs) {
                prefs.setBool('invoice_visible_$column', _visibleColumns[column] ?? false);
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () => context.read<SalesService>().loadInvoices(forceRefresh: true),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInvoiceTable(List<Invoice> invoices, SalesService salesService, {required bool isFullWidth}) {
    if (salesService.isLoadingInvoices) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty ? 'No hay facturas' : 'No se encontraron facturas',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Column(
        children: [
          _buildTableHeader(isFullWidth),
          Expanded(
            child: ListView.builder(
              itemCount: invoices.length,
              itemBuilder: (context, index) {
                final invoice = invoices[index];
                final isSelected = _selectedInvoice?.id == invoice.id;
                return _buildInvoiceRow(invoice, isSelected, isFullWidth);
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTableHeader(bool isFullWidth) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 38, // Match row height
            child: Checkbox(
              value: false, 
              onChanged: (val) {},
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          for (final entry in _columnWidths.entries.toList())
            if (_visibleColumns[entry.key] ?? true)
              _buildColumnHeaderCell(
                entry.key, 
                isFullWidth ? entry.value * 1.5 : entry.value,
              ),
        ],
      ),
    );
  }
  
  Widget _buildColumnHeaderCell(String columnName, double width) {
    final isSorted = _sortColumn == columnName;
    
    return SizedBox(
      width: width,
      height: 38, // Match row height
      child: Stack(
        children: [
          // Main content area (same as data cells)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _onSort(columnName),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _getColumnLabel(columnName).toUpperCase(),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                            letterSpacing: 0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSorted)
                        Icon(
                          _sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                          size: 18,
                          color: Colors.grey[700],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Resize handle (positioned at right edge, outside content flow)
          if (columnName != 'balance')
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _columnWidths[columnName] = 
                          (_columnWidths[columnName]! + details.delta.dx)
                              .clamp(_minColumnWidth, _maxColumnWidth);
                    });
                  },
                  onHorizontalDragEnd: (_) => _saveColumnWidth(columnName, _columnWidths[columnName]!),
                  child: Container(
                    width: 8,
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        width: 1,
                        height: 20,
                        color: Colors.grey[350],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  List<Widget> _buildColumnHeaders(bool isFullWidth) {
    final headers = <Widget>[];
    
    for (var entry in _visibleColumns.entries) {
      if (!entry.value) continue;
      
      final width = isFullWidth ? _columnWidths[entry.key]! * 1.5 : _columnWidths[entry.key]!;
      
      headers.add(
        _buildResizableHeader(
          column: entry.key,
          label: _getColumnLabel(entry.key),
          width: width,
        ),
      );
    }
    
    return headers;
  }
  
  Widget _buildResizableHeader({
    required String column,
    required String label,
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _onSort(column),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_sortColumn == column) ...[
                      const SizedBox(width: 4),
                      Icon(
                        _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _columnWidths[column] = (_columnWidths[column]! + details.delta.dx).clamp(80.0, 400.0);
                });
              },
              onHorizontalDragEnd: (_) => _saveColumnWidth(column, _columnWidths[column]!),
              child: Container(
                width: 8,
                height: 40,
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 1,
                    height: 20,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInvoiceRow(Invoice invoice, bool isSelected, bool isFullWidth) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedInvoice = isSelected ? null : invoice;
        });
      },
      hoverColor: Colors.grey[50],
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[50] : null,
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!, width: 1),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 38,
              child: Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    _selectedInvoice = value == true ? invoice : null;
                  });
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            ..._buildRowCells(invoice, isFullWidth),
          ],
        ),
      ),
    );
  }
  
  List<Widget> _buildRowCells(Invoice invoice, bool isFullWidth) {
    final cells = <Widget>[];
    
    for (var entry in _visibleColumns.entries) {
      if (!entry.value) continue;
      
      final width = isFullWidth ? _columnWidths[entry.key]! * 1.5 : _columnWidths[entry.key]!;
      cells.add(_buildCell(entry.key, invoice, width));
    }
    
    return cells;
  }
  
  Widget _buildCell(String column, Invoice invoice, double width) {
    Widget content;
    
    switch (column) {
      case 'date':
        content = Text(
          ChileanUtils.formatDate(invoice.date),
          style: const TextStyle(fontSize: 13, color: Colors.black87),
        );
        break;
        
      case 'invoice_number':
        content = Text(
          invoice.invoiceNumber,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.blue,
            fontWeight: FontWeight.w500,
          ),
        );
        break;
        
      case 'customer':
        content = Text(
          invoice.customerName ?? 'Sin registro',
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          overflow: TextOverflow.ellipsis,
        );
        break;
        
      case 'status':
        content = _buildStatusChip(invoice.status);
        break;
        
      case 'total':
        content = Text(
          ChileanUtils.formatCurrency(invoice.total),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        );
        break;
        
      case 'balance':
        content = Text(
          ChileanUtils.formatCurrency(invoice.balance),
          style: TextStyle(
            fontSize: 13,
            color: invoice.balance > 0 ? Colors.orange[700] : Colors.green[700],
            fontWeight: FontWeight.w500,
          ),
        );
        break;
        
      default:
        content = const Text('-');
    }
    
    return SizedBox(
      width: width,
      height: 38,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: content,
        ),
      ),
    );
  }
  
  Widget _buildStatusChip(InvoiceStatus status) {
    Color bgColor;
    Color textColor;
    String label;
    
    switch (status) {
      case InvoiceStatus.draft:
        bgColor = Colors.grey[200]!;
        textColor = Colors.grey[700]!;
        label = 'BORRADOR';
        break;
      case InvoiceStatus.sent:
        bgColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        label = 'ENVIADA';
        break;
      case InvoiceStatus.confirmed:
        bgColor = Colors.purple[100]!;
        textColor = Colors.purple[800]!;
        label = 'CONFIRMADA';
        break;
      case InvoiceStatus.paid:
        bgColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        label = 'PAGADO';
        break;
      case InvoiceStatus.overdue:
        bgColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        label = 'VENCIDA';
        break;
      case InvoiceStatus.cancelled:
        bgColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        label = 'ANULADA';
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
  
  Widget _buildInvoicePreview(Invoice invoice) {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          _buildActionBar(invoice),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Use full width minus padding
                final double contentWidth = constraints.maxWidth - 40;
                
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    width: contentWidth,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildInvoiceDocument(invoice),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionBar(Invoice invoice) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          Text(
            invoice.invoiceNumber,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => debugPrint('TODO: Edit invoice'),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Editar'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => debugPrint('TODO: Send email'),
            icon: const Icon(Icons.email_outlined, size: 16),
            label: const Text('Enviar correo'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => debugPrint('TODO: Share'),
            icon: const Icon(Icons.share_outlined, size: 16),
            label: const Text('Compartir'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _selectedInvoice = null),
            tooltip: 'Cerrar',
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
  
  Widget _buildInvoiceDocument(Invoice invoice) {
    return Padding(
      padding: const EdgeInsets.all(40), // Reduced from 48
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'VIÑABIKE',
                style: TextStyle(
                  fontSize: 22, // Reduced from headlineMedium
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
              // Invoice number and balance in top right (like Zoho)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '# ${invoice.invoiceNumber}',
                    style: const TextStyle(
                      fontSize: 15, // Reduced from 16
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12), // Reduced from 16
                  Text(
                    'Saldo adeudado',
                    style: TextStyle(
                      fontSize: 12, // Reduced from 13
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ChileanUtils.formatCurrency(invoice.balance),
                    style: const TextStyle(
                      fontSize: 16, // Reduced from 18
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24), // Reduced from 32
          Text('Viñabike', style: TextStyle(fontSize: 13)),
          Text('Valparaíso', style: TextStyle(fontSize: 13)),
          Text('Chile', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 24), // Reduced from 32
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Facturar a',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      invoice.customerName ?? 'Sin registro',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Fecha de la factura :',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ChileanUtils.formatDate(invoice.date),
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24), // Reduced from 32
          Table(
            border: TableBorder.all(color: Colors.grey[300]!),
            columnWidths: const {
              0: FixedColumnWidth(50), // Reduced from 60
              1: FlexColumnWidth(3),
              2: FixedColumnWidth(80), // Reduced from 100
              3: FixedColumnWidth(90), // Reduced from 100
              4: FixedColumnWidth(100), // Reduced from 120
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey[800]),
                children: [
                  _buildTableCell('#', isHeader: true),
                  _buildTableCell('Artículo & Descripción', isHeader: true),
                  _buildTableCell('Cant.', isHeader: true),
                  _buildTableCell('Tarifa', isHeader: true),
                  _buildTableCell('Cantidad', isHeader: true),
                ],
              ),
              ...invoice.items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                
                return TableRow(
                  children: [
                    _buildTableCell('${index + 1}'),
                    _buildTableCell(
                      item.productName ?? 'Sin nombre',
                      subtitle: item.description,
                    ),
                    _buildTableCell('${item.quantity.toStringAsFixed(2)}'),
                    _buildTableCell(ChileanUtils.formatCurrency(item.unitPrice)),
                    _buildTableCell(ChileanUtils.formatCurrency(item.lineTotal)),
                  ],
                );
              }),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Spacer(),
              SizedBox(
                width: 300,
                child: Column(
                  children: [
                    _buildTotalRow('Subtotal', invoice.subtotal),
                    const Divider(),
                    _buildTotalRow('Total', invoice.total, isTotal: true),
                    if (invoice.paidAmount > 0) ...[
                      const Divider(),
                      _buildTotalRow('Pago realizado', -invoice.paidAmount, isNegative: true),
                    ],
                    const Divider(thickness: 2),
                    _buildTotalRow('Saldo adeudado', invoice.balance, isTotal: true),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildTableCell(String text, {bool isHeader = false, String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), // More compact
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: isHeader ? Colors.white : Colors.black87,
              fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
              fontSize: isHeader ? 12 : 13, // Smaller fonts
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey[600], 
                fontSize: 11, // Smaller subtitle
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildTotalRow(String label, double amount, {bool isTotal = false, bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 16 : 14,
            ),
          ),
          Text(
            (isNegative && amount > 0 ? '(-) ' : '') + ChileanUtils.formatCurrency(amount.abs()),
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              fontSize: isTotal ? 16 : 14,
              color: isNegative ? Colors.red : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
  
  String _getColumnLabel(String column) {
    switch (column) {
      case 'date':
        return 'FECHA';
      case 'invoice_number':
        return 'N.º DE FACTURA';
      case 'customer':
        return 'NOMBRE DEL CLIENTE';
      case 'status':
        return 'ESTADO DE LA FACTURA';
      case 'total':
        return 'IMPORTE DE LA FACTURA';
      case 'balance':
        return 'SALDO';
      default:
        return column.toUpperCase();
    }
  }
}
