import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/purchase_invoice.dart';
import '../services/purchase_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../shared/models/tax_treatment.dart';
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import '../../settings/services/appearance_service.dart';
import '../../../shared/services/inventory_service.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

// Purchase Invoice List Page with Split-Pane View

class PurchaseInvoiceListPage extends StatefulWidget {
  const PurchaseInvoiceListPage({super.key});

  @override
  State<PurchaseInvoiceListPage> createState() =>
      _PurchaseInvoiceListPageState();
}

class _PurchaseInvoiceListPageState extends State<PurchaseInvoiceListPage> {
  String _searchTerm = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();

  // Mobile UI state
  bool _isSearchExpanded = false;
  String _selectedStatus = 'all'; // all, draft, pending, paid, overdue

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
      context
          .read<PurchaseService>()
          .getPurchaseInvoices(); // Uses cache if valid
      context.read<InventoryService>().getProducts(); // Ensure cache is loaded
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
      _listPaneWidth =
          prefs.getDouble('purchase_invoice_list_pane_width') ?? 600.0;

      for (var key in _columnWidths.keys.toList()) {
        _columnWidths[key] =
            prefs.getDouble('purchase_invoice_col_$key') ?? _columnWidths[key]!;
      }

      for (var key in _visibleColumns.keys.toList()) {
        _visibleColumns[key] = prefs.getBool('purchase_invoice_visible_$key') ??
            _visibleColumns[key]!;
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

  List<PurchaseInvoice> _getFilteredAndSortedInvoices(
      List<PurchaseInvoice> invoices) {
    List<PurchaseInvoice> filtered = List.from(invoices);

    // Status filter
    if (_selectedStatus != 'all') {
      filtered = filtered.where((invoice) {
        final now = DateTime.now();
        switch (_selectedStatus) {
          case 'draft':
            return invoice.status == PurchaseInvoiceStatus.draft;
          case 'pending':
            return invoice.paidAmount < invoice.total &&
                invoice.status != PurchaseInvoiceStatus.draft;
          case 'paid':
            return invoice.paidAmount >= invoice.total;
          case 'overdue':
            return invoice.dueDate != null &&
                invoice.dueDate!.isBefore(now) &&
                invoice.paidAmount < invoice.total;
          default:
            return true;
        }
      }).toList();
    }

    // Search filter
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
    final invoices =
        _getFilteredAndSortedInvoices(purchaseService.purchaseInvoices);

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
    // Navigate directly to form - payment model is now selected inside the form
    // Default is prepayment (true), but user can change it in the form
    context.push('/purchases/new?prepayment=true');
  }

  // ============ MOBILE LAYOUT METHODS ============

  Widget _buildMobileLayout(List<PurchaseInvoice> invoices) {
    return Column(
      children: [
        _buildMobileHeader(invoices),
        _buildMobileFilterTabs(invoices),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => context
                .read<PurchaseService>()
                .getPurchaseInvoices(forceRefresh: true),
            child: _buildInvoiceCardsList(invoices),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileHeader(List<PurchaseInvoice> invoices) {
    final theme = Theme.of(context);

    if (_isSearchExpanded) {
      // Expanded search mode
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (v) => setState(() => _searchTerm = v),
                decoration: InputDecoration(
                  hintText: 'Buscar factura, proveedor...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchTerm = '';
                        _isSearchExpanded = false;
                      });
                    },
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Collapsed header
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Text(
            'Compras',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${invoices.length}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _isSearchExpanded = true),
            tooltip: 'Buscar',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createNewInvoice,
            tooltip: 'Nueva factura',
          ),
        ],
      ),
    );
  }

  Widget _buildMobileFilterTabs(List<PurchaseInvoice> allInvoices) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    // Calculate counts for each status
    final draftCount = allInvoices
        .where((i) => i.status == PurchaseInvoiceStatus.draft)
        .length;
    final pendingCount = allInvoices
        .where((i) =>
            i.paidAmount < i.total && i.status != PurchaseInvoiceStatus.draft)
        .length;
    final paidCount = allInvoices.where((i) => i.paidAmount >= i.total).length;
    final overdueCount = allInvoices
        .where((i) =>
            i.dueDate != null &&
            i.dueDate!.isBefore(now) &&
            i.paidAmount < i.total)
        .length;

    final filters = [
      ('all', 'Todas', allInvoices.length, null),
      ('draft', 'Borrador', draftCount, Colors.grey),
      ('pending', 'Pendiente', pendingCount, Colors.orange),
      ('paid', 'Pagadas', paidCount, Colors.green),
      ('overdue', 'Vencidas', overdueCount, Colors.red),
    ];

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final (key, label, count, color) = filters[index];
          final isSelected = _selectedStatus == key;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : color ?? theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedStatus = key),
              selectedColor: color ?? theme.colorScheme.primary,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : null,
                fontWeight: isSelected ? FontWeight.w600 : null,
              ),
              side: BorderSide(
                color: isSelected
                    ? (color ?? theme.colorScheme.primary)
                    : theme.dividerColor,
              ),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          );
        },
      ),
    );
  }

  // ============ DESKTOP LAYOUT METHODS ============

  Widget _buildFullListView(
      List<PurchaseInvoice> invoices, PurchaseService purchaseService) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        if (isMobile) {
          return _buildMobileLayout(invoices);
        }

        return Column(
          children: [
            _buildSummaryCards(invoices),
            const SizedBox(height: 16),
            _buildSearchBar(false),
            const SizedBox(height: 8),
            Expanded(
              child: _buildInvoiceTable(invoices, purchaseService,
                  isFullWidth: true),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSplitView(
      List<PurchaseInvoice> invoices, PurchaseService purchaseService) {
    final theme = Theme.of(context);
    return Row(
      children: [
        // Left pane - Invoice list
        Container(
          width: _listPaneWidth,
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(
              right: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          child: Column(
            children: [
              // Search bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor),
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
              color: theme.dividerColor,
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
        .where((inv) =>
            inv.status != PurchaseInvoiceStatus.draft &&
            inv.paidAmount < inv.total)
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

    final cards = [
      _buildSummaryCard(
        'Por pagar',
        ChileanUtils.formatCurrency(totalPayable),
        Icons.account_balance_wallet_outlined,
        Colors.orange,
      ),
      _buildSummaryCard(
        'Vencidos hoy',
        ChileanUtils.formatCurrency(overdue),
        Icons.warning_amber_outlined,
        Colors.red,
      ),
      _buildSummaryCard(
        'Próximos 30 días',
        ChileanUtils.formatCurrency(dueIn30Days),
        Icons.schedule_outlined,
        Colors.blue,
      ),
      _buildSummaryCard(
        'Vencidas (Qt)',
        '$overdueCount',
        Icons.receipt_long_outlined,
        overdueCount > 0 ? Colors.red : Colors.green,
      ),
    ];

    // Responsive layout
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          // Mobile/Tablet: 2x2 Grid or vertical stack
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[1]),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: cards[2]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[3]),
                  ],
                ),
              ],
            ),
          );
        } else {
          // Desktop: Single Row
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
                cards[0],
                const SizedBox(width: 24),
                cards[1],
                const SizedBox(width: 24),
                cards[2],
                const SizedBox(width: 24),
                cards[3],
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildSummaryCard(
      String label, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
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
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
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
                    color: theme.textTheme.bodyLarge?.color,
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
    final theme = Theme.of(context);
    if (invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(
              'No se encontraron facturas',
              style: TextStyle(color: theme.hintColor, fontSize: 14),
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
        final rawBalance = invoice.total - invoice.paidAmount;
        final balance = rawBalance.abs() < 0.01 ? 0.0 : rawBalance;
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? theme.colorScheme.primary.withOpacity(0.15)
                    : Colors.blue[50])
                : theme.cardColor,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
              left: BorderSide(
                color:
                    isSelected ? theme.colorScheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: InkWell(
            onTap: () {
              if (MediaQuery.of(context).size.width < 800) {
                // Mobile: Navigate to details (using same route as edit/view)
                context.push('/purchases/${invoice.id}');
              } else {
                // Desktop: Select
                setState(() {
                  _selectedInvoice = invoice;
                });
              }
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
                      color:
                          theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 13, color: theme.hintColor),
                      const SizedBox(width: 4),
                      Text(
                        ChileanUtils.formatDate(invoice.date),
                        style: TextStyle(color: theme.hintColor, fontSize: 12),
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

  Widget _buildSearchBar([bool isMobile = false]) {
    return Row(
      children: [
        Expanded(
          child: TextField(
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
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.primary),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ),
        if (!isMobile) ...[
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.view_column_outlined),
            tooltip: 'Columnas',
            itemBuilder: (context) {
              return _visibleColumns.keys.map((column) {
                return CheckedPopupMenuItem<String>(
                  value: column,
                  checked: _visibleColumns[column] ?? false,
                  child: Text(column == 'date'
                      ? 'Fecha'
                      : column == 'invoice_number'
                          ? 'N° Factura'
                          : column == 'supplier'
                              ? 'Proveedor'
                              : column == 'status'
                                  ? 'Estado'
                                  : column == 'total'
                                      ? 'Total'
                                      : column == 'balance'
                                          ? 'Saldo'
                                          : column),
                );
              }).toList();
            },
            onSelected: (column) {
              setState(() {
                _visibleColumns[column] = !(_visibleColumns[column] ?? false);
              });
              SharedPreferences.getInstance().then((prefs) {
                prefs.setBool('purchase_invoice_visible_$column',
                    _visibleColumns[column] ?? false);
              });
            },
          ),
        ],
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Actualizar',
          onPressed: () => context
              .read<PurchaseService>()
              .getPurchaseInvoices(forceRefresh: true),
        ),
      ],
    );
  }

  Widget _buildInvoiceTable(
      List<PurchaseInvoice> invoices, PurchaseService purchaseService,
      {required bool isFullWidth}) {
    final theme = Theme.of(context);
    if (invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: theme.hintColor),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty
                  ? 'No hay facturas de compra'
                  : 'No se encontraron facturas',
              style:
                  theme.textTheme.titleMedium?.copyWith(color: theme.hintColor),
            ),
          ],
        ),
      );
    }

    final tableWidth =
        MediaQuery.of(context).size.width - (isFullWidth ? 0 : 400);

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(color: theme.dividerColor),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
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
                          _sortAscending
                              ? Icons.arrow_drop_up
                              : Icons.arrow_drop_down,
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
                      _columnWidths[columnName] =
                          (_columnWidths[columnName]! + details.delta.dx)
                              .clamp(_minColumnWidth, _maxColumnWidth);
                    });
                  },
                  onHorizontalDragEnd: (_) =>
                      _saveColumnWidth(columnName, _columnWidths[columnName]!),
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

  Widget _buildInvoiceRow(
      PurchaseInvoice invoice, bool isSelected, bool isFullWidth) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedInvoice = isSelected ? null : invoice;
        });
      },
      hoverColor: isDark ? Colors.grey[800] : Colors.grey[50],
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? theme.colorScheme.primary.withOpacity(0.15)
                  : Colors.blue[50])
              : null,
          border: Border(
            bottom: BorderSide(color: theme.dividerColor, width: 1),
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
            // 3-dot menu for actions
            SizedBox(
              width: 48,
              height: 38,
              child: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 18, color: Colors.grey[600]),
                padding: EdgeInsets.zero,
                tooltip: 'Acciones',
                offset: const Offset(0, 38),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(Icons.visibility_outlined, size: 18),
                        SizedBox(width: 12),
                        Text('Ver detalle'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 12),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 18, color: Colors.red[700]),
                        const SizedBox(width: 12),
                        Text('Eliminar',
                            style: TextStyle(color: Colors.red[700])),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) => _handleRowAction(value, invoice),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleRowAction(String action, PurchaseInvoice invoice) async {
    switch (action) {
      case 'view':
        context.push('/purchases/${invoice.id}');
        break;
      case 'edit':
        context.push('/purchases/${invoice.id}');
        break;
      case 'delete':
        await _confirmDeleteInvoice(invoice);
        break;
    }
  }

  Future<void> _confirmDeleteInvoice(PurchaseInvoice invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.red, size: 48),
        title: const Text('Eliminar factura'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '¿Estás seguro de eliminar la factura "${invoice.invoiceNumber}"?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Proveedor: ${invoice.supplierName ?? "Sin proveedor"}'),
                  Text('Total: ${ChileanUtils.formatCurrency(invoice.total)}'),
                  Text('Estado: ${invoice.status.name}'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Esta acción no se puede deshacer.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final purchaseService = context.read<PurchaseService>();
        await purchaseService.deletePurchaseInvoice(invoice.id!);

        // Clear selection if this invoice was selected
        if (_selectedInvoice?.id == invoice.id) {
          setState(() => _selectedInvoice = null);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Factura "${invoice.invoiceNumber}" eliminada'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  List<Widget> _buildRowCells(PurchaseInvoice invoice, bool isFullWidth) {
    final cells = <Widget>[];

    for (var entry in _visibleColumns.entries) {
      if (!entry.value) continue;

      final width = isFullWidth
          ? _columnWidths[entry.key]! * 1.5
          : _columnWidths[entry.key]!;
      cells.add(_buildCell(entry.key, invoice, width));
    }

    return cells;
  }

  Widget _buildCell(String column, PurchaseInvoice invoice, double width) {
    final rawBalance = invoice.total - invoice.paidAmount;
    // Tolerance of $1 for rounding differences (e.g. payment of 61612 on total of 61612.25)
    final balance = rawBalance.abs() < 1.0 ? 0.0 : rawBalance;

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w400),
                  ),
                ),

                // Enviar correo button
                TextButton.icon(
                  onPressed: () => debugPrint('TODO: Send email'),
                  icon: const Icon(Icons.email_outlined, size: 16),
                  label: const Text('Enviar correo electrónico'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF666666),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w400),
                  ),
                ),

                // Compartir button
                TextButton.icon(
                  onPressed: () => debugPrint('TODO: Share'),
                  icon: const Icon(Icons.share_outlined, size: 16),
                  label: const Text('Compartir'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF666666),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w400),
                  ),
                ),

                // PDF/Imprimir dropdown
                PopupMenuButton<String>(
                  offset: const Offset(0, 40),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.picture_as_pdf_outlined,
                            size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Text(
                          'PDF/Imprimir',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w400),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.arrow_drop_down,
                            size: 18, color: Colors.grey[600]),
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
                    if (value == 'download' || value == 'print') {
                      _downloadInvoicePDF(invoice);
                    }
                  },
                ),
                const SizedBox(width: 8),

                // Three dots menu
                PopupMenuButton<String>(
                  offset: const Offset(0, 40),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.more_horiz,
                        size: 18, color: Colors.grey[600]),
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
                          Icon(Icons.delete_outline,
                              size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Eliminar',
                              style:
                                  TextStyle(color: Colors.red, fontSize: 13)),
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
    final rawBalance = invoice.total - invoice.paidAmount;
    final balance = rawBalance.abs() < 0.01 ? 0.0 : rawBalance;

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
                  _buildTableCell('Artículo & Descripción',
                      isHeader: true, scale: scale),
                  _buildTableCell('Cant.', isHeader: true, scale: scale),
                  _buildTableCell('Tarifa', isHeader: true, scale: scale),
                  _buildTableCell('Importe', isHeader: true, scale: scale),
                ],
              ),
              ...invoice.items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;

                // Lookup clean product name from cache if available (mirrors form view logic)
                final products = context.read<InventoryService>().products;
                final product = products.cast<dynamic>().firstWhere(
                      (p) => p.id == item.productId,
                      orElse: () => null,
                    );
                final displayName =
                    product?.name ?? item.productName ?? 'Sin nombre';
                final displaySku = product?.sku ?? item.productSku;

                return TableRow(
                  children: [
                    _buildTableCell('${index + 1}', scale: scale),
                    _buildTableCell(
                      displayName,
                      subtitle: item.description != null &&
                              item.description!.isNotEmpty
                          ? item.description
                          : (displaySku != null ? 'SKU: $displaySku' : null),
                      scale: scale,
                    ),
                    _buildTableCell('${item.quantity.toStringAsFixed(2)}',
                        scale: scale),
                    _buildTableCell(ChileanUtils.formatCurrency(item.unitCost),
                        scale: scale),
                    _buildTableCell(
                        ChileanUtils.formatCurrency(item.netAmountClamped),
                        scale: scale),
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
                    // Subtotal (the actual stored subtotal is always the net amount for purchases)
                    _buildTotalRow(
                        invoice.taxTreatment == TaxTreatment.taxIncluded
                            ? 'Subtotal (Neto)'
                            : 'Subtotal',
                        invoice.subtotal,
                        scale: scale),
                    if (invoice.discountAmount > 0)
                      _buildTotalRow(
                          'Descuento',
                          invoice
                              .discountAmount, // Fix UI bug by not negatively reversing it
                          isNegative: true,
                          scale: scale),
                    if (invoice.ivaAmount > 0)
                      _buildTotalRow('IVA (19%)', invoice.ivaAmount,
                          scale: scale),
                    const Divider(),
                    _buildTotalRow('Total', invoice.total,
                        isTotal: true, scale: scale),
                    if (invoice.paidAmount > 0) ...[
                      const Divider(),
                      _buildTotalRow('Pago realizado', invoice.paidAmount,
                          isNegative: true, scale: scale),
                    ],
                    const Divider(thickness: 2),
                    _buildTotalRow('Saldo adeudado', balance,
                        isTotal: true, scale: scale),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableCell(String text,
      {bool isHeader = false, String? subtitle, double scale = 1.0}) {
    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
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

  Widget _buildTotalRow(String label, double amount,
      {bool isTotal = false, bool isNegative = false, double scale = 1.0}) {
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
            (isNegative && amount > 0 ? '(-) ' : '') +
                ChileanUtils.formatCurrency(amount.abs()),
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

  // Cached logo bytes for PDF generation
  Uint8List? _cachedLogoBytes;
  String? _cachedLogoUrl;
  bool _isGeneratingPdf = false;

  Future<void> _downloadInvoicePDF(PurchaseInvoice invoice) async {
    if (_isGeneratingPdf) return;

    setState(() => _isGeneratingPdf = true);

    try {
      final pdf = await _generatePurchaseInvoicePDF(invoice);
      final bytes = await pdf.save();

      // Platform-specific download
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        // Desktop: Use Save As dialog
        final String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Factura PDF',
          fileName: 'factura_compra_${invoice.invoiceNumber}.pdf',
          allowedExtensions: ['pdf'],
          type: FileType.custom,
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsBytes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('PDF guardado en: $outputFile'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        // Use printing package for mobile/share
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'factura_compra_${invoice.invoiceNumber}.pdf',
        );
      }
    } catch (e) {
      debugPrint('Error generating PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al generar PDF: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<pw.Document> _generatePurchaseInvoicePDF(
      PurchaseInvoice invoice) async {
    final pdf = pw.Document();

    // Try to load company logo (use cache if available)
    pw.ImageProvider? logoImage;
    try {
      final appearanceService = context.read<AppearanceService>();
      final logoUrl = appearanceService.companyLogoUrl;
      if (logoUrl != null && logoUrl.isNotEmpty) {
        // Check if we already have cached bytes for this URL
        if (_cachedLogoBytes != null && _cachedLogoUrl == logoUrl) {
          logoImage = pw.MemoryImage(_cachedLogoBytes!);
        } else {
          // Fetch and cache
          final response = await http.get(Uri.parse(logoUrl));
          if (response.statusCode == 200) {
            _cachedLogoBytes = response.bodyBytes;
            _cachedLogoUrl = logoUrl;
            logoImage = pw.MemoryImage(_cachedLogoBytes!);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading logo for PDF: $e');
    }

    // Load products to use clean names
    final products = await context.read<InventoryService>().getProducts();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header - much more compact
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Company logo or text fallback
                if (logoImage != null)
                  pw.Image(logoImage,
                      width: 120, height: 40, fit: pw.BoxFit.contain)
                else
                  pw.Text(
                    'VIÑABIKE',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    ),
                  ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      '# ${invoice.invoiceNumber}',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Saldo adeudado',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      ChileanUtils.formatCurrency(
                          invoice.total - invoice.paidAmount),
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 16),

            // Company info - smaller
            pw.Text('Viñabike',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.black)),
            pw.Text('Valparaíso',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.black)),
            pw.Text('Chile',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.black)),

            pw.SizedBox(height: 16),

            // Supplier and date info - more compact
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Proveedor',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      invoice.supplierName ?? 'Sin registro',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue700,
                      ),
                    ),
                    if (invoice.supplierRut != null)
                      pw.Text(
                        invoice.supplierRut!,
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Fecha de la factura :',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      ChileanUtils.formatDate(invoice.date),
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 16),

            // Items table - much tighter
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColors.grey300,
                width: 0.3, // Ultra thin borders
              ),
              columnWidths: {
                0: const pw.FixedColumnWidth(35),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FixedColumnWidth(60),
                3: const pw.FixedColumnWidth(70),
                4: const pw.FixedColumnWidth(70),
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey800),
                  children: [
                    _buildPdfTableCell('#', isHeader: true),
                    _buildPdfTableCell('Artículo & Descripción',
                        isHeader: true),
                    _buildPdfTableCell('Cant.', isHeader: true),
                    _buildPdfTableCell('Tarifa', isHeader: true),
                    _buildPdfTableCell('Importe', isHeader: true),
                  ],
                ),
                // Data rows
                ...invoice.items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;

                  // Lookup clean product name from cache if available (mirrors form view logic)
                  final product = products.cast<dynamic>().firstWhere(
                        (p) => p.id == item.productId,
                        orElse: () => null,
                      );
                  final displayName =
                      product?.name ?? item.productName ?? 'Sin nombre';
                  final displaySku = product?.sku ?? item.productSku;

                  final hasDescription =
                      item.description != null && item.description!.isNotEmpty;
                  final hasSku = displaySku != null && displaySku.isNotEmpty;

                  return pw.TableRow(
                    children: [
                      _buildPdfTableCell('${index + 1}'),
                      // Product name + description (Zoho style)
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 5),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              displayName,
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                            if (hasDescription) ...[
                              pw.SizedBox(height: 3),
                              pw.Text(
                                item.description!,
                                style: const pw.TextStyle(
                                  fontSize: 9,
                                  color: PdfColors.grey700,
                                ),
                              ),
                            ] else if (hasSku) ...[
                              pw.SizedBox(height: 3),
                              pw.Text(
                                'SKU: $displaySku',
                                style: const pw.TextStyle(
                                  fontSize: 9,
                                  color: PdfColors.grey700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      _buildPdfTableCell('${item.quantity.toStringAsFixed(2)}'),
                      _buildPdfTableCell(
                          ChileanUtils.formatCurrency(item.unitCost)),
                      _buildPdfTableCell(
                          ChileanUtils.formatCurrency(item.netAmountClamped)),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 16),

            // Totals - tighter
            pw.Row(
              children: [
                pw.Spacer(),
                pw.SizedBox(
                  width: 250,
                  child: pw.Column(
                    children: [
                      // Subtotal (the actual stored subtotal is always the net amount for purchases)
                      _buildPdfTotalRow(
                          invoice.taxTreatment == TaxTreatment.taxIncluded
                              ? 'Subtotal (Neto)'
                              : 'Subtotal',
                          invoice.subtotal),
                      if (invoice.discountAmount > 0)
                        _buildPdfTotalRow('Descuento', -invoice.discountAmount),
                      if (invoice.ivaAmount > 0)
                        _buildPdfTotalRow('IVA (19%)', invoice.ivaAmount),
                      pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                      _buildPdfTotalRow('Total', invoice.total, isTotal: true),
                      if (invoice.paidAmount > 0) ...[
                        pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                        _buildPdfTotalRow(
                            'Pago realizado', -invoice.paidAmount),
                      ],
                      pw.Divider(thickness: 1, color: PdfColors.grey800),
                      _buildPdfTotalRow(
                          'Saldo adeudado', invoice.total - invoice.paidAmount,
                          isTotal: true),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return pdf;
  }

  pw.Widget _buildPdfTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: isHeader ? PdfColors.white : PdfColors.black,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: isHeader ? 9 : 10,
        ),
      ),
    );
  }

  pw.Widget _buildPdfTotalRow(String label, double amount,
      {bool isTotal = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: isTotal ? 12 : 11,
              color: PdfColors.black,
            ),
          ),
          pw.Text(
            ChileanUtils.formatCurrency(amount.abs()),
            style: pw.TextStyle(
              fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: isTotal ? 12 : 11,
              color: PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }
}
