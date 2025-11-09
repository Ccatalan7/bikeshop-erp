import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/purchase_invoice.dart';
import '../services/purchase_service.dart';
import '../widgets/purchase_model_selection_dialog.dart';

// Purchase Invoice List Page with Split-Pane View

class PurchaseInvoiceListPage extends StatefulWidget {
  const PurchaseInvoiceListPage({super.key});

  @override
  State<PurchaseInvoiceListPage> createState() => _PurchaseInvoiceListPageState();
}

class _PurchaseInvoiceListPageState extends State<PurchaseInvoiceListPage> {
  String _searchTerm = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();
  
  PurchaseInvoice? _selectedInvoice;
  double _listPaneWidth = 600.0;
  static const double _minListPaneWidth = 400.0;
  static const double _maxListPaneWidth = 900.0;
  static const double _minColumnWidth = 80.0;
  static const double _maxColumnWidth = 400.0;
  
  final Map<String, double> _columnWidths = {
    'date': 110.0,
    'invoice_number': 130.0,
    'supplier': 180.0,
    'status': 120.0,
    'total': 120.0,
    'balance': 120.0,
  };
  
  final Map<String, bool> _visibleColumns = {
    'date': true,
    'invoice_number': true,
    'supplier': true,
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
    
    // Sync scroll positions
    _headerScrollController.addListener(() {
      if (_bodyScrollController.offset != _headerScrollController.offset) {
        _bodyScrollController.jumpTo(_headerScrollController.offset);
      }
    });
    
    _bodyScrollController.addListener(() {
      if (_headerScrollController.offset != _bodyScrollController.offset) {
        _headerScrollController.jumpTo(_bodyScrollController.offset);
      }
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PurchaseService>().getPurchaseInvoices(forceRefresh: true);
    });
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _headerScrollController.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }
  
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _listPaneWidth = prefs.getDouble('purchase_invoice_list_pane_width') ?? 600.0;
      
      for (var key in _columnWidths.keys.toList()) {
        _columnWidths[key] = prefs.getDouble('purchase_invoice_col_$key') ?? _columnWidths[key]!;
      }
      
      for (var key in _visibleColumns.keys.toList()) {
        _visibleColumns[key] = prefs.getBool('purchase_invoice_visible_$key') ?? _visibleColumns[key]!;
      }
    });
  }
  
  Future<void> _saveListPaneWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('purchase_invoice_list_pane_width', width);
  }
  
  Future<void> _saveColumnWidth(String column, double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('purchase_invoice_col_$column', width);
  }
  
  List<PurchaseInvoice> _getFilteredAndSortedInvoices(List<PurchaseInvoice> invoices) {
    List<PurchaseInvoice> filtered = List.from(invoices);
    
    if (_searchTerm.isNotEmpty) {
      final term = _searchTerm.toLowerCase();
      filtered = filtered.where((invoice) {
        return invoice.invoiceNumber.toLowerCase().contains(term) ||
            (invoice.supplierName?.toLowerCase().contains(term) ?? false) ||
            (invoice.supplierRut?.toLowerCase().contains(term) ?? false);
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
        case 'supplier':
          comparison = (a.supplierName ?? '').compareTo(b.supplierName ?? '');
          break;
        case 'status':
          comparison = a.status.name.compareTo(b.status.name);
          break;
        case 'total':
          comparison = a.total.compareTo(b.total);
          break;
        case 'balance':
          final aBalance = a.total - a.paidAmount;
          final bBalance = b.total - b.paidAmount;
          comparison = aBalance.compareTo(bBalance);
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
    final purchaseService = context.watch<PurchaseService>();
    final invoices = _getFilteredAndSortedInvoices(purchaseService.purchaseInvoices);
    
    return MainLayout(
      title: 'Facturas de Compra',
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
                  'Facturas de Compra',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _createNewInvoice,
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
                ? _buildFullListView(invoices, purchaseService)
                : _buildSplitView(invoices, purchaseService),
          ),
        ],
      ),
    );
  }
  
  Future<void> _createNewInvoice() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const PurchaseModelSelectionDialog(),
    );

    if (result == null || !mounted) return;

    final isPrepayment = result; // result is already a boolean
    context.push('/purchases/new?prepayment=$isPrepayment');
  }
  
  Widget _buildFullListView(List<PurchaseInvoice> invoices, PurchaseService purchaseService) {
    return Column(
      children: [
        _buildSummaryCards(invoices),
        const SizedBox(height: 16),
        _buildSearchBar(),
        const SizedBox(height: 8),
        Expanded(
          child: _buildInvoiceTable(invoices, purchaseService, isFullWidth: true),
        ),
      ],
    );
  }
  
  Widget _buildSplitView(List<PurchaseInvoice> invoices, PurchaseService purchaseService) {
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
  
  Widget _buildSummaryCards(List<PurchaseInvoice> invoices) {
    final totalPayable = invoices
        .where((inv) => inv.status != PurchaseInvoiceStatus.draft && inv.paidAmount < inv.total)
        .fold(0.0, (sum, inv) => sum + (inv.total - inv.paidAmount));
    
    final overdue = invoices.where((inv) {
      if (inv.dueDate == null || inv.paidAmount >= inv.total) return false;
      return inv.dueDate!.isBefore(DateTime.now());
    }).fold(0.0, (sum, inv) => sum + (inv.total - inv.paidAmount));
    
    final dueIn30Days = invoices.where((inv) {
      if (inv.dueDate == null || inv.paidAmount >= inv.total) return false;
      final now = DateTime.now();
      return inv.dueDate!.isAfter(now) && 
             inv.dueDate!.isBefore(now.add(const Duration(days: 30)));
    }).fold(0.0, (sum, inv) => sum + (inv.total - inv.paidAmount));
    
    final overdueCount = invoices.where((inv) {
      if (inv.dueDate == null || inv.paidAmount >= inv.total) return false;
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
            'Total de cuentas pendientes de pago',
            ChileanUtils.formatCurrency(totalPayable),
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
  
  Widget _buildInvoiceCardsList(List<PurchaseInvoice> invoices) {
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
        final balance = invoice.total - invoice.paidAmount;
        
        return Container(
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[50] : Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey[200]!),
              left: BorderSide(
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedInvoice = invoice;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        invoice.invoiceNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      _buildStatusChip(invoice.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    invoice.supplierName ?? 'Sin proveedor',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 13, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        ChileanUtils.formatDate(invoice.date),
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        ChileanUtils.formatCurrency(invoice.total),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  if (balance > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Saldo: ${ChileanUtils.formatCurrency(balance)}',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchTerm = value),
      decoration: InputDecoration(
        hintText: 'Buscar por número, proveedor o RUT...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _searchTerm.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchTerm = '');
                },
              )
            : null,
        isDense: true,
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
  
  Widget _buildInvoiceTable(List<PurchaseInvoice> invoices, PurchaseService purchaseService, {required bool isFullWidth}) {
    if (invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty ? 'No hay facturas de compra' : 'No se encontraron facturas',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    final tableWidth = MediaQuery.of(context).size.width - (isFullWidth ? 0 : 400);
    
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
          SingleChildScrollView(
            controller: _headerScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: _buildTableHeader(isFullWidth),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _bodyScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: ListView.builder(
                  itemCount: invoices.length,
                  itemBuilder: (context, index) {
                    final invoice = invoices[index];
                    final isSelected = _selectedInvoice?.id == invoice.id;
                    return _buildInvoiceRow(invoice, isSelected, isFullWidth);
                  },
                ),
              ),
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
            height: 38,
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
    final labels = {
      'date': 'Fecha',
      'invoice_number': 'N° Factura',
      'supplier': 'Proveedor',
      'status': 'Estado',
      'total': 'Total',
      'balance': 'Saldo',
    };
    
    final isSorted = _sortColumn == columnName;
    
    return SizedBox(
      width: width,
      height: 38,
      child: Stack(
        children: [
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
                          (labels[columnName] ?? columnName).toUpperCase(),
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
                      _columnWidths[columnName] = (_columnWidths[columnName]! + details.delta.dx)
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
  
  Widget _buildInvoiceRow(PurchaseInvoice invoice, bool isSelected, bool isFullWidth) {
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
  
  List<Widget> _buildRowCells(PurchaseInvoice invoice, bool isFullWidth) {
    final cells = <Widget>[];
    
    for (var entry in _visibleColumns.entries) {
      if (!entry.value) continue;
      
      final width = isFullWidth ? _columnWidths[entry.key]! * 1.5 : _columnWidths[entry.key]!;
      cells.add(_buildCell(entry.key, invoice, width));
    }
    
    return cells;
  }
  
  Widget _buildCell(String column, PurchaseInvoice invoice, double width) {
    final balance = invoice.total - invoice.paidAmount;
    
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
      case 'supplier':
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              invoice.supplierName ?? 'Sin proveedor',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (invoice.supplierRut != null)
              Text(
                invoice.supplierRut!,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
          ],
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
          ChileanUtils.formatCurrency(balance),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: balance > 0 ? Colors.orange[700] : Colors.green[700],
          ),
        );
        break;
      default:
        content = const Text('');
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
  
  Widget _buildStatusChip(PurchaseInvoiceStatus status) {
    final labels = {
      PurchaseInvoiceStatus.draft: 'Borrador',
      PurchaseInvoiceStatus.sent: 'Enviada',
      PurchaseInvoiceStatus.confirmed: 'Confirmada',
      PurchaseInvoiceStatus.received: 'Recibida',
      PurchaseInvoiceStatus.paid: 'Pagada',
      PurchaseInvoiceStatus.cancelled: 'Anulada',
    };
    
    final colors = {
      PurchaseInvoiceStatus.draft: Colors.grey,
      PurchaseInvoiceStatus.sent: Colors.blue,
      PurchaseInvoiceStatus.confirmed: Colors.purple,
      PurchaseInvoiceStatus.received: Colors.green,
      PurchaseInvoiceStatus.paid: Colors.blue,
      PurchaseInvoiceStatus.cancelled: Colors.red,
    };
    
    final color = colors[status] ?? Colors.grey;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        labels[status] ?? status.name,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
  
  Widget _buildInvoicePreview(PurchaseInvoice invoice) {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          _buildActionBar(invoice),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double availableWidth = constraints.maxWidth - 40;
                
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    width: availableWidth,
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
                    child: _buildInvoiceDocument(invoice, availableWidth),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionBar(PurchaseInvoice invoice) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // TOP ROW: Invoice number + utility icons
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          color: Colors.white,
          child: Row(
            children: [
              // Invoice number on the left
              Text(
                invoice.invoiceNumber,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              
              // Attachment icon
              IconButton(
                icon: const Icon(Icons.attach_file, size: 20),
                onPressed: () => debugPrint('TODO: Attach file'),
                tooltip: 'Adjuntar archivo',
                color: Colors.grey[600],
                padding: const EdgeInsets.all(8),
              ),
              const SizedBox(width: 4),
              
              // Comment icon
              IconButton(
                icon: const Icon(Icons.comment_outlined, size: 20),
                onPressed: () => debugPrint('TODO: Add comment'),
                tooltip: 'Comentarios',
                color: Colors.grey[600],
                padding: const EdgeInsets.all(8),
              ),
              const SizedBox(width: 4),
              
              // Close button
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => _selectedInvoice = null),
                tooltip: 'Cerrar',
                color: Colors.grey[600],
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        ),
        
        // BOTTOM ROW: Action buttons bar (light gray background)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEEEEEE),
            border: Border(
              top: BorderSide(color: Colors.grey[200]!),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Editar button
                TextButton.icon(
                  onPressed: () => context.push('/purchases/${invoice.id}'),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF666666),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
                  ),
                ),
                
                // Enviar correo button
                TextButton.icon(
                  onPressed: () => debugPrint('TODO: Send email'),
                  icon: const Icon(Icons.email_outlined, size: 16),
                  label: const Text('Enviar correo electrónico'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF666666),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
                  ),
                ),
                
                // Compartir button
                TextButton.icon(
                  onPressed: () => debugPrint('TODO: Share'),
                  icon: const Icon(Icons.share_outlined, size: 16),
                  label: const Text('Compartir'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF666666),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
                  ),
                ),
                
                // PDF/Imprimir dropdown
                PopupMenuButton<String>(
                  offset: const Offset(0, 40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.picture_as_pdf_outlined, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Text(
                          'PDF/Imprimir',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w400),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[600]),
                      ],
                    ),
                  ),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.download_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Descargar PDF', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'print',
                      child: Row(
                        children: [
                          Icon(Icons.print_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Imprimir', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'download') {
                      debugPrint('TODO: Download PDF');
                    } else if (value == 'print') {
                      debugPrint('TODO: Print');
                    }
                  },
                ),
                const SizedBox(width: 8),
                
                // Three dots menu
                PopupMenuButton<String>(
                  offset: const Offset(0, 40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.more_horiz, size: 18, color: Colors.grey[600]),
                  ),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'duplicate',
                      child: Row(
                        children: [
                          Icon(Icons.content_copy_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Duplicar', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Eliminar', style: TextStyle(color: Colors.red, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'duplicate') {
                      debugPrint('TODO: Duplicate invoice');
                    } else if (value == 'delete') {
                      debugPrint('TODO: Delete invoice');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildInvoiceDocument(PurchaseInvoice invoice, double containerWidth) {
    final balance = invoice.total - invoice.paidAmount;
    
    // Calculate responsive sizes based on width
    final double scale = (containerWidth / 800.0).clamp(0.6, 1.0);
    final double padding = 40 * scale;
    final double companyNameSize = 22 * scale;
    final double invoiceNumberSize = 15 * scale;
    final double labelSize = 12 * scale;
    final double dataSize = 13 * scale;
    final double spacing = 24 * scale;
    
    return Padding(
      padding: EdgeInsets.all(padding),
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
                  fontSize: companyNameSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
              // Invoice number and balance in top right
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '# ${invoice.invoiceNumber}',
                    style: TextStyle(
                      fontSize: invoiceNumberSize,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 12 * scale),
                  Text(
                    'Saldo adeudado',
                    style: TextStyle(
                      fontSize: labelSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  SizedBox(height: 2 * scale),
                  Text(
                    ChileanUtils.formatCurrency(balance),
                    style: TextStyle(
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: spacing),
          Text('Viñabike', style: TextStyle(fontSize: dataSize)),
          Text('Valparaíso', style: TextStyle(fontSize: dataSize)),
          Text('Chile', style: TextStyle(fontSize: dataSize)),
          SizedBox(height: spacing),
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
                        fontSize: labelSize,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    SizedBox(height: 6 * scale),
                    Text(
                      invoice.supplierName ?? 'Sin registro',
                      style: TextStyle(
                        fontSize: 14 * scale,
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
                      fontSize: labelSize,
                      color: Colors.grey[700],
                    ),
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    ChileanUtils.formatDate(invoice.date),
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: dataSize,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: spacing),
          SizedBox(height: spacing),
          Table(
            border: TableBorder.all(color: Colors.grey[300]!),
            columnWidths: {
              0: FixedColumnWidth(50 * scale),
              1: FlexColumnWidth(3),
              2: FixedColumnWidth(80 * scale),
              3: FixedColumnWidth(90 * scale),
              4: FixedColumnWidth(100 * scale),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey[800]),
                children: [
                  _buildTableCell('#', isHeader: true, scale: scale),
                  _buildTableCell('Artículo & Descripción', isHeader: true, scale: scale),
                  _buildTableCell('Cant.', isHeader: true, scale: scale),
                  _buildTableCell('Tarifa', isHeader: true, scale: scale),
                  _buildTableCell('Cantidad', isHeader: true, scale: scale),
                ],
              ),
              ...invoice.items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final itemTotal = item.quantity * item.unitCost * (1 - item.discount) * (1 + item.ivaRate);
                
                return TableRow(
                  children: [
                    _buildTableCell('${index + 1}', scale: scale),
                    _buildTableCell(
                      item.productName ?? 'Sin nombre',
                      subtitle: item.productSku != null ? 'SKU: ${item.productSku}' : null,
                      scale: scale,
                    ),
                    _buildTableCell('${item.quantity.toStringAsFixed(2)}', scale: scale),
                    _buildTableCell(ChileanUtils.formatCurrency(item.unitCost), scale: scale),
                    _buildTableCell(ChileanUtils.formatCurrency(itemTotal), scale: scale),
                  ],
                );
              }),
            ],
          ),
          SizedBox(height: spacing),
          Row(
            children: [
              const Spacer(),
              SizedBox(
                width: 300 * scale,
                child: Column(
                  children: [
                    _buildTotalRow('Subtotal', invoice.subtotal, scale: scale),
                    const Divider(),
                    _buildTotalRow('Total', invoice.total, isTotal: true, scale: scale),
                    if (invoice.paidAmount > 0) ...[
                      const Divider(),
                      _buildTotalRow('Pago realizado', -invoice.paidAmount, isNegative: true, scale: scale),
                    ],
                    const Divider(thickness: 2),
                    _buildTotalRow('Saldo adeudado', balance, isTotal: true, scale: scale),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildTableCell(String text, {bool isHeader = false, String? subtitle, double scale = 1.0}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: isHeader ? Colors.white : Colors.black87,
              fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
              fontSize: (isHeader ? 12 : 13) * scale,
            ),
          ),
          if (subtitle != null) ...[
            SizedBox(height: 3 * scale),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey[600], 
                fontSize: 11 * scale,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildTotalRow(String label, double amount, {bool isTotal = false, bool isNegative = false, double scale = 1.0}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8 * scale),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: (isTotal ? 16 : 14) * scale,
            ),
          ),
          Text(
            (isNegative && amount > 0 ? '(-) ' : '') + ChileanUtils.formatCurrency(amount.abs()),
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              fontSize: (isTotal ? 16 : 14) * scale,
              color: isNegative ? Colors.red : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
