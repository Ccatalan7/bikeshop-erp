import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/models/payment_method.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_payment.dart';
import '../services/purchase_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../shared/models/tax_treatment.dart';
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import '../../settings/services/appearance_service.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/widgets/branded_loading.dart';
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
  bool _isHydratingSelectedInvoice = false;
  // When true, the right pane shows the inline payment form instead of the PDF
  bool _showingPaymentForm = false;
  // Payment form state
  final _paymentFormKey = GlobalKey<FormState>();
  final _paymentAmountController = TextEditingController();
  final _paymentReferenceController = TextEditingController();
  final _paymentNotesController = TextEditingController();
  PaymentMethod? _selectedPaymentMethod;
  DateTime _paymentDate = DateTime.now();
  bool _isSavingPayment = false;
  bool _isLoadingPaymentMethods = false;
  List<PaymentMethod> _paymentMethods = [];
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
      context.read<PurchaseService>().getPurchaseInvoicesForList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _headerScrollController.dispose();
    _bodyScrollController.dispose();
    _paymentAmountController.dispose();
    _paymentReferenceController.dispose();
    _paymentNotesController.dispose();
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

  bool _isCurrentMonth(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  bool _isAccountedInvoice(PurchaseInvoice invoice) {
    return invoice.status == PurchaseInvoiceStatus.received ||
        invoice.status == PurchaseInvoiceStatus.paid;
  }

  double _taxCreditBase(PurchaseInvoice invoice) {
    if (invoice.ivaAmount <= 0) return 0;
    if (invoice.netAmount > 0) return invoice.netAmount;
    return invoice.subtotal;
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
        _getFilteredAndSortedInvoices(purchaseService.listInvoices);

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
                .getPurchaseInvoicesForList(forceRefresh: true),
            child: _buildInvoiceCardsList(invoices),
          ),
        ),
      ],
    );
  }

  Future<void> _handleInvoiceSelection(
    PurchaseInvoice invoice, {
    required bool isSelected,
  }) async {
    if (isSelected) {
      if (!mounted) return;
      setState(() {
        _selectedInvoice = null;
        _showingPaymentForm = false;
        _isHydratingSelectedInvoice = false;
      });
      return;
    }

    setState(() {
      _selectedInvoice = invoice;
      _showingPaymentForm = false;
      _isHydratingSelectedInvoice = true;
    });

    final fullInvoice =
        await context.read<PurchaseService>().fetchPurchaseInvoice(
              invoice.id!,
            );

    if (!mounted || _selectedInvoice?.id != invoice.id) {
      return;
    }

    setState(() {
      _selectedInvoice = fullInvoice ?? invoice;
      _isHydratingSelectedInvoice = false;
    });
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
            _buildSummaryCards(purchaseService.listInvoices),
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
              _buildSearchBar(),
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
          child: _isHydratingSelectedInvoice
              ? const Center(child: BrandedLoading())
              : _buildInvoicePreview(_selectedInvoice!),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(List<PurchaseInvoice> invoices) {
    final currentMonthInvoices = invoices
        .where((inv) => _isAccountedInvoice(inv) && _isCurrentMonth(inv.date))
        .toList();

    final monthlyPurchases = currentMonthInvoices.fold<double>(
      0,
      (sum, inv) => sum + inv.total,
    );

    final monthlyTaxBase = currentMonthInvoices.fold<double>(
      0,
      (sum, inv) => sum + _taxCreditBase(inv),
    );

    final monthlyIvaCredit = currentMonthInvoices.fold<double>(
      0,
      (sum, inv) => sum + (inv.ivaAmount > 0 ? inv.ivaAmount : 0),
    );

    final monthlyCount = currentMonthInvoices.length;

    final cards = [
      _buildSummaryCard(
        'Compras del mes',
        ChileanUtils.formatCurrency(monthlyPurchases),
        Icons.shopping_bag_outlined,
        Colors.blue,
      ),
      _buildSummaryCard(
        'Base IVA crédito',
        ChileanUtils.formatCurrency(monthlyTaxBase),
        Icons.receipt_long_outlined,
        Colors.orange,
      ),
      _buildSummaryCard(
        'IVA crédito mes',
        ChileanUtils.formatCurrency(monthlyIvaCredit),
        Icons.account_balance_outlined,
        Colors.green,
      ),
      _buildSummaryCard(
        'Facturas contabilizadas',
        '$monthlyCount',
        Icons.fact_check_outlined,
        monthlyCount > 0 ? Colors.teal : Colors.grey,
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
              color: color.withValues(alpha: 0.12),
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
                    color: theme.textTheme.bodySmall?.color
                        ?.withValues(alpha: 0.7),
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
                    ? theme.colorScheme.primary.withValues(alpha: 0.15)
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
                _handleInvoiceSelection(invoice, isSelected: isSelected);
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
                      color: theme.textTheme.bodyMedium?.color
                          ?.withValues(alpha: 0.8),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por número, proveedor o RUT...',
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchTerm = value),
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
                .getPurchaseInvoicesForList(forceRefresh: true),
          ),
        ],
      ),
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
      onTap: () => _handleInvoiceSelection(invoice, isSelected: isSelected),
      hoverColor: isDark ? Colors.grey[800] : Colors.grey[50],
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : Colors.blue[50])
              : null,
          border: Border(
            bottom: BorderSide(
                color: isDark ? theme.dividerColor : Colors.grey[200]!,
                width: 1),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 38,
              child: Checkbox(
                value: isSelected,
                onChanged: (value) =>
                    _handleInvoiceSelection(invoice, isSelected: value != true),
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
      PurchaseInvoiceStatus.draft: 'BORRADOR',
      PurchaseInvoiceStatus.sent: 'ENVIADA',
      PurchaseInvoiceStatus.confirmed: 'CONFIRMADA',
      PurchaseInvoiceStatus.received: 'RECIBIDA',
      PurchaseInvoiceStatus.paid: 'PAGADA',
      PurchaseInvoiceStatus.cancelled: 'ANULADA',
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        labels[status] ?? status.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // ============================================================
  // STATUS TRANSITION LOGIC
  // ============================================================

  Future<void> _updateStatus(
      PurchaseInvoice invoice, PurchaseInvoiceStatus newStatus) async {
    if (invoice.id == null) return;

    final purchaseService = context.read<PurchaseService>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final updated = await purchaseService.updateInvoiceStatus(
        invoice.id!,
        newStatus,
      );

      if (!mounted) return;

      if (updated != null) {
        setState(() => _selectedInvoice = updated);
      }

      String message;
      switch (newStatus) {
        case PurchaseInvoiceStatus.sent:
          message = 'Factura enviada al proveedor';
          break;
        case PurchaseInvoiceStatus.confirmed:
          message = 'Factura confirmada';
          break;
        case PurchaseInvoiceStatus.received:
          message = 'Factura marcada como recibida. Inventario actualizado.';
          break;
        case PurchaseInvoiceStatus.draft:
          message = 'Factura revertida a borrador';
          break;
        default:
          message = 'Estado actualizado';
      }

      messenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text('Error al actualizar estado: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openPaymentForm(PurchaseInvoice invoice) async {
    if (invoice.id == null) return;
    // Load payment methods
    setState(() {
      _isLoadingPaymentMethods = true;
      _showingPaymentForm = true;
      _paymentDate = DateTime.now();
      _paymentAmountController.text = '';
      _paymentReferenceController.text = '';
      _paymentNotesController.text = '';
      _selectedPaymentMethod = null;
    });
    final paymentMethodService = context.read<PaymentMethodService>();
    await paymentMethodService.loadPaymentMethods();
    if (mounted) {
      setState(() {
        _isLoadingPaymentMethods = false;
        _paymentMethods = paymentMethodService.paymentMethods;
        if (_paymentMethods.isNotEmpty) {
          _selectedPaymentMethod = _paymentMethods.first;
        }
        // Pre-fill the balance
        final balance = invoice.total - invoice.paidAmount;
        _paymentAmountController.text =
            balance > 0 ? balance.toStringAsFixed(0) : '';
      });
    }
  }

  double _effectiveBalance(PurchaseInvoice invoice) {
    final b = invoice.balance;
    if (b > 0) return b;
    final calculated = invoice.total - invoice.paidAmount;
    return calculated < 0 ? 0 : calculated;
  }

  Future<void> _submitInlinePayment(PurchaseInvoice invoice) async {
    if (!(_paymentFormKey.currentState?.validate() ?? false)) return;
    if (_selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un método de pago.')),
      );
      return;
    }
    final rawAmount = _paymentAmountController.text
        .trim()
        .replaceAll('.', '')
        .replaceAll(',', '.');
    final amount = double.tryParse(rawAmount);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un monto válido.')),
      );
      return;
    }
    final balance = _effectiveBalance(invoice);
    if (amount.round() - balance.round() > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'El pago no puede exceder el saldo (${ChileanUtils.formatCurrency(balance)})')),
      );
      return;
    }
    final purchaseService = context.read<PurchaseService>();
    final messenger = ScaffoldMessenger.of(context);
    final tenantId = await TenantService().getTenantId();
    if (tenantId == null) return;

    setState(() => _isSavingPayment = true);
    try {
      final payment = PurchasePayment(
        tenantId: tenantId,
        invoiceId: invoice.id!,
        paymentMethodId: _selectedPaymentMethod!.id,
        amount: amount > balance ? balance : amount,
        date: _paymentDate,
        reference: _paymentReferenceController.text.trim().isEmpty
            ? null
            : _paymentReferenceController.text.trim(),
        notes: _paymentNotesController.text.trim().isEmpty
            ? null
            : _paymentNotesController.text.trim(),
      );
      await purchaseService.createPayment(payment);

      if (!mounted) return;

      messenger.showSnackBar(
        const SnackBar(
            content: Text('Pago registrado correctamente'),
            backgroundColor: Colors.green),
      );

      final updated = await purchaseService.getPurchaseInvoice(invoice.id!);

      if (!mounted) return;

      setState(() {
        _selectedInvoice = updated ?? invoice;
        _showingPaymentForm = false;
      });
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
              content: Text('No se pudo registrar el pago: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingPayment = false);
    }
  }

  Future<void> _undoLastPayment(PurchaseInvoice invoice) async {
    if (invoice.id == null) return;

    final purchaseService = context.read<PurchaseService>();
    final messenger = ScaffoldMessenger.of(context);

    // Get all payments for this invoice
    final payments = await purchaseService.getPaymentsForInvoice(invoice.id!);
    if (payments.isEmpty) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('No hay pagos para deshacer'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    // Get the last payment
    payments.sort((a, b) => b.date.compareTo(a.date));
    final lastPayment = payments.first;

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deshacer pago'),
        content: Text(
          'Se eliminará el pago de ${ChileanUtils.formatCurrency(lastPayment.amount)} '
          'y su asiento contable asociado.\n\n'
          'Este cambio se reflejará instantáneamente. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar pago'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await purchaseService.deletePayment(lastPayment.id!);
      if (!mounted) return;

      final updated = await purchaseService.getPurchaseInvoice(invoice.id!);

      if (!mounted) return;

      setState(() => _selectedInvoice = updated ?? invoice);
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Pago eliminado correctamente'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
              content: Text('Error al eliminar el pago: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ============================================================
  // WORKFLOW BANNER
  // ============================================================

  Widget _buildWorkflowBanner(PurchaseInvoice invoice) {
    if (invoice.id == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    String? nextActionLabel;
    String? subLabel;
    VoidCallback? onActionPressed;
    final List<Widget> secondaryActions = [];

    final effectiveBalance = invoice.total - invoice.paidAmount;

    switch (invoice.status) {
      case PurchaseInvoiceStatus.draft:
        nextActionLabel = 'Enviar';
        subLabel = 'Envía la orden al proveedor.';
        onActionPressed =
            () => _updateStatus(invoice, PurchaseInvoiceStatus.sent);
        break;

      case PurchaseInvoiceStatus.sent:
        nextActionLabel = 'Confirmar';
        subLabel = 'Confirma la recepción o aceptación por el proveedor.';
        onActionPressed =
            () => _updateStatus(invoice, PurchaseInvoiceStatus.confirmed);
        secondaryActions.add(
          OutlinedButton.icon(
            onPressed: () =>
                _updateStatus(invoice, PurchaseInvoiceStatus.draft),
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Volver a borrador'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        );
        break;

      case PurchaseInvoiceStatus.confirmed:
        secondaryActions.add(
          OutlinedButton.icon(
            onPressed: () => _updateStatus(invoice, PurchaseInvoiceStatus.sent),
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Volver a enviado'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        );

        if (invoice.prepaymentModel) {
          if (effectiveBalance <= 0) {
            nextActionLabel = 'Marcar como Recibida';
            subLabel =
                'Factura prepagada pagada en su totalidad. Registra la recepción física para ingresar al inventario.';
            onActionPressed =
                () => _updateStatus(invoice, PurchaseInvoiceStatus.received);
          } else {
            nextActionLabel = 'Registrar pago';
            subLabel =
                'Saldo pendiente: ${ChileanUtils.formatCurrency(effectiveBalance)}. Debes pagar antes de recibir los productos.';
            onActionPressed = () => _openPaymentForm(invoice);
          }
        } else {
          nextActionLabel = 'Marcar como Recibida';
          subLabel =
              'Confirma la recepción física para ingresar al inventario antes del pago.';
          onActionPressed =
              () => _updateStatus(invoice, PurchaseInvoiceStatus.received);
        }
        break;

      case PurchaseInvoiceStatus.received:
        if (invoice.prepaymentModel && effectiveBalance <= 0) {
          subLabel =
              'Productos recibidos e inventario actualizado tras el prepago.';
          secondaryActions.add(
            OutlinedButton.icon(
              onPressed: () =>
                  _updateStatus(invoice, PurchaseInvoiceStatus.paid),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Volver a pagada'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          );
        } else {
          if (effectiveBalance > 0) {
            nextActionLabel = 'Registrar pago';
            subLabel =
                'Productos recibidos. Saldo pendiente: ${ChileanUtils.formatCurrency(effectiveBalance)}.';
            onActionPressed = () => _openPaymentForm(invoice);
          } else {
            subLabel = 'Productos recibidos e inventario actualizado.';
          }
          secondaryActions.add(
            OutlinedButton.icon(
              onPressed: () =>
                  _updateStatus(invoice, PurchaseInvoiceStatus.confirmed),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Volver a confirmada'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          );
        }
        break;

      case PurchaseInvoiceStatus.paid:
        subLabel = 'Esta factura ha sido pagada en su totalidad.';
        if (invoice.prepaymentModel) {
          nextActionLabel = 'Marcar como Recibida';
          subLabel =
              'Factura prepagada pagada. Registra la recepción física para ingresar al inventario.';
          onActionPressed =
              () => _updateStatus(invoice, PurchaseInvoiceStatus.received);
        }

        secondaryActions.add(
          OutlinedButton.icon(
            onPressed: () => _undoLastPayment(invoice),
            icon: const Icon(Icons.history, size: 16),
            label: const Text('Deshacer pago'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red[700],
              side: BorderSide(color: Colors.red[100]!),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        );
        break;

      default:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.info_outline, color: primaryColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FLUJO DE TRABAJO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: primaryColor.withValues(alpha: 0.8),
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    subLabel,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ...secondaryActions.map((action) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: action,
                )),
            if (nextActionLabel != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilledButton(
                  onPressed: onActionPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        invoice.status == PurchaseInvoiceStatus.sent
                            ? Colors.green[600]
                            : primaryColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                  ),
                  child: Text(nextActionLabel,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
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
          if (!_showingPaymentForm) _buildWorkflowBanner(invoice),
          Expanded(
            child: _showingPaymentForm
                ? _buildInlinePaymentForm(invoice)
                : LayoutBuilder(
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
                                color: Colors.black.withValues(alpha: 0.08),
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

  Widget _buildInlinePaymentForm(PurchaseInvoice invoice) {
    final theme = Theme.of(context);
    final balance = _effectiveBalance(invoice);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _paymentFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Volver a la factura',
                      onPressed: () =>
                          setState(() => _showingPaymentForm = false),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Registrar pago',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Balance breakdown card
                Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildPaymentRow('Total factura:',
                            ChileanUtils.formatCurrency(invoice.total), theme),
                        const SizedBox(height: 4),
                        _buildPaymentRow(
                            'Pagado:',
                            ChileanUtils.formatCurrency(invoice.paidAmount),
                            theme),
                        const Divider(height: 16),
                        _buildPaymentRow(
                          'Saldo pendiente:',
                          ChileanUtils.formatCurrency(balance),
                          theme,
                          isBold: true,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Amount
                TextFormField(
                  controller: _paymentAmountController,
                  decoration: const InputDecoration(
                      labelText: 'Monto', prefixText: '\$ '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa el monto del pago';
                    }
                    final parsed = double.tryParse(
                        value.trim().replaceAll('.', '').replaceAll(',', '.'));
                    if (parsed == null || parsed <= 0) return 'Monto inválido';
                    if (parsed.round() - balance.round() > 1) {
                      return 'No puede superar el saldo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Payment method
                if (_isLoadingPaymentMethods)
                  const LinearProgressIndicator()
                else if (_paymentMethods.isEmpty)
                  const Text('No hay métodos de pago disponibles',
                      style: TextStyle(color: Colors.red))
                else
                  DropdownButtonFormField<PaymentMethod>(
                    initialValue: _selectedPaymentMethod,
                    decoration:
                        const InputDecoration(labelText: 'Medio de pago'),
                    items: _paymentMethods
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Row(
                                children: [
                                  Icon(_paymentMethodIcon(m.icon), size: 18),
                                  const SizedBox(width: 8),
                                  Text(m.name),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedPaymentMethod = v),
                    validator: (v) =>
                        v == null ? 'Selecciona un método de pago' : null,
                  ),
                const SizedBox(height: 12),

                // Date
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _paymentDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _paymentDate = picked);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Fecha de pago',
                        border: OutlineInputBorder()),
                    child: Row(
                      children: [
                        const Icon(Icons.event),
                        const SizedBox(width: 8),
                        Text(ChileanUtils.formatDate(_paymentDate)),
                        const Spacer(),
                        const Icon(Icons.keyboard_arrow_down),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Reference
                TextFormField(
                  controller: _paymentReferenceController,
                  decoration: InputDecoration(
                    labelText: _selectedPaymentMethod?.requiresReference == true
                        ? 'Referencia *'
                        : 'Referencia',
                    hintText: 'Número de transferencia, comprobante, etc.',
                  ),
                  validator: (value) {
                    if (_selectedPaymentMethod?.requiresReference == true &&
                        (value == null || value.trim().isEmpty)) {
                      return 'Este método de pago requiere una referencia';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Notes
                TextFormField(
                  controller: _paymentNotesController,
                  decoration:
                      const InputDecoration(labelText: 'Notas internas'),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => _showingPaymentForm = false),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isSavingPayment
                          ? null
                          : () => _submitInlinePayment(invoice),
                      icon: _isSavingPayment
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: const Text('Registrar pago'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentRow(String label, String value, ThemeData theme,
      {bool isBold = false, Color? color}) {
    final style = isBold
        ? theme.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold, color: color)
        : theme.textTheme.bodyLarge?.copyWith(color: color);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }

  IconData _paymentMethodIcon(String? iconName) {
    switch (iconName?.toLowerCase()) {
      case 'cash':
        return Icons.attach_money;
      case 'bank':
        return Icons.account_balance;
      case 'credit_card':
        return Icons.credit_card;
      case 'receipt':
        return Icons.receipt;
      default:
        return Icons.payment;
    }
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
              1: const FlexColumnWidth(3),
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
                final displayName = _cleanPdfText(
                    product?.name ?? item.productName ?? 'Sin nombre');
                final displaySku =
                    _cleanPdfText(product?.sku ?? item.productSku ?? '');

                return TableRow(
                  children: [
                    _buildTableCell('${index + 1}', scale: scale),
                    _buildTableCell(
                      displayName,
                      subtitle: item.description != null &&
                              item.description!.isNotEmpty
                          ? item.description
                          : ('SKU: $displaySku'),
                      scale: scale,
                    ),
                    _buildTableCell(item.quantity.toStringAsFixed(2),
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
    final appearanceService = context.read<AppearanceService>();
    final inventoryService = context.read<InventoryService>();

    // Try to load company logo (use cache if available)
    pw.ImageProvider? logoImage;
    try {
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
    final products = await inventoryService.getProducts();

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
                  final displayName = _cleanPdfText(
                      product?.name ?? item.productName ?? 'Sin nombre');
                  final displaySku =
                      _cleanPdfText(product?.sku ?? item.productSku ?? '');

                  final hasDescription =
                      item.description != null && item.description!.isNotEmpty;
                  final hasSku = displaySku.isNotEmpty;

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
                                _cleanPdfText(item.description!),
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
                      _buildPdfTableCell(item.quantity.toStringAsFixed(2)),
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

  String _cleanPdfText(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(RegExp(r'[^\x20-\x7E\xA0-\xFF\r\n\t]'), ' ');
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
