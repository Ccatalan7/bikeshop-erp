import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
// import 'package:flutter/foundation.dart' show kIsWeb; // Unused
// Conditional import for web-only features
// import 'dart:html' as html; // Removed - causes issues on native platforms
import 'package:file_picker/file_picker.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/document_accounting_preview.dart';
import '../../../shared/services/document_accounting_context_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/invoice_pdf_generator.dart';
import '../../settings/services/appearance_service.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';
import '../widgets/payment_form.dart' show PaymentForm;
import '../widgets/sales_corrections_menu.dart';

class InvoiceListPage extends StatefulWidget {
  const InvoiceListPage({
    super.key,
    this.initialInvoiceId,
    this.initialInvoiceNumber,
    this.forceSplitView = false,
  });

  final String? initialInvoiceId;
  final String? initialInvoiceNumber;
  final bool forceSplitView;

  @override
  State<InvoiceListPage> createState() => _InvoiceListPageState();
}

class _InvoiceListPageState extends State<InvoiceListPage> {
  String _searchTerm = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();

  Invoice? _selectedInvoice;
  bool _isHydratingSelectedInvoice = false;
  bool _showPaymentTerminal = false;
  final DocumentAccountingContextService _documentAccountingContextService =
      DocumentAccountingContextService();
  Future<DocumentAccountingContext>? _accountingContextFuture;
  String? _accountingContextInvoiceId;
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
  String? _lastAppliedInitialInvoiceLookupKey;

  // Mobile state
  bool _isSearchExpanded = false;
  InvoiceStatus? _filterStatus;

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final salesService = context.read<SalesService>();
      await salesService.loadInvoices();
      if (!mounted) return;
      await _selectInitialInvoiceIfNeeded(salesService);
    });
  }

  @override
  void didUpdateWidget(covariant InvoiceListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialInvoiceId == widget.initialInvoiceId &&
        oldWidget.initialInvoiceNumber == widget.initialInvoiceNumber) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _selectInitialInvoiceIfNeeded(
        context.read<SalesService>(),
        force: true,
      );
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
      _listPaneWidth = prefs.getDouble('invoice_list_pane_width') ?? 600.0;

      for (var key in _columnWidths.keys.toList()) {
        _columnWidths[key] =
            prefs.getDouble('invoice_col_$key') ?? _columnWidths[key]!;
      }

      for (var key in _visibleColumns.keys.toList()) {
        _visibleColumns[key] =
            prefs.getBool('invoice_visible_$key') ?? _visibleColumns[key]!;
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

    if (_filterStatus != null) {
      filtered =
          filtered.where((invoice) => invoice.status == _filterStatus).toList();
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

  Future<void> _selectInitialInvoiceIfNeeded(
    SalesService salesService, {
    bool force = false,
  }) async {
    final invoiceId = widget.initialInvoiceId?.trim();
    final invoiceNumber = widget.initialInvoiceNumber?.trim();
    if ((invoiceId == null || invoiceId.isEmpty) &&
        (invoiceNumber == null || invoiceNumber.isEmpty)) {
      return;
    }

    final lookupKey = [
      if (invoiceId != null && invoiceId.isNotEmpty) 'id:$invoiceId',
      if (invoiceNumber != null && invoiceNumber.isNotEmpty)
        'number:$invoiceNumber',
    ].join('|');
    if (!force && _lastAppliedInitialInvoiceLookupKey == lookupKey) return;

    _lastAppliedInitialInvoiceLookupKey = lookupKey;

    Invoice? cachedInvoice;
    for (final invoice in salesService.invoices) {
      if ((invoiceId != null &&
              invoiceId.isNotEmpty &&
              invoice.id == invoiceId) ||
          (invoiceNumber != null &&
              invoiceNumber.isNotEmpty &&
              invoice.invoiceNumber == invoiceNumber)) {
        cachedInvoice = invoice;
        break;
      }
    }

    if (mounted && cachedInvoice != null) {
      setState(() {
        _selectedInvoice = cachedInvoice;
        _showPaymentTerminal = false;
        _isHydratingSelectedInvoice = true;
        _accountingContextInvoiceId = null;
        _accountingContextFuture = null;
      });
    }

    final fullInvoice = invoiceId == null || invoiceId.isEmpty
        ? null
        : await salesService.fetchInvoice(invoiceId);
    if (!mounted) return;
    if (widget.initialInvoiceId?.trim() != invoiceId ||
        widget.initialInvoiceNumber?.trim() != invoiceNumber) {
      return;
    }

    final selectedInvoice = fullInvoice ?? cachedInvoice;
    if (selectedInvoice == null) {
      setState(() => _isHydratingSelectedInvoice = false);
      return;
    }

    setState(() {
      _selectedInvoice = selectedInvoice;
      _showPaymentTerminal = false;
      _isHydratingSelectedInvoice = false;
      _primeAccountingContext(selectedInvoice);
    });
  }

  @override
  Widget build(BuildContext context) {
    final salesService = context.watch<SalesService>();
    final invoices = _getFilteredAndSortedInvoices(salesService.invoices);

    // Use MediaQuery for robust detection, ignoring parent constraints issues
    // FORCE mobile on Android/iOS app to avoid desktop layout on high-res phones/tablets
    final screenWidth = MediaQuery.of(context).size.width;
    final forceSplitPreview = widget.forceSplitView && _selectedInvoice != null;
    final isMobile = !forceSplitPreview &&
        (screenWidth < 1100 ||
            (!kIsWeb && (Platform.isAndroid || Platform.isIOS)));

    return MainLayout(
      title: isMobile ? 'Ventas' : 'Facturas',
      child: isMobile
          ? _buildMobileLayout(invoices)
          : _buildDesktopLayout(invoices, salesService),
    );
  }

  // ============================================================
  // MOBILE LAYOUT
  // ============================================================
  Widget _buildMobileLayout(List<Invoice> invoices) {
    final theme = Theme.of(context);

    // If viewing details, show detail view (simulated for now by context.go, but for split pane logic...)
    // Note: Invoice list currently uses context.push for mobile details, so we just show list here.

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // Compact Header
          _buildMobileHeader(theme, invoices.length),

          // Filter Tabs
          _buildMobileFilterTabs(theme),

          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await context.read<SalesService>().loadInvoices(
                      forceRefresh: true,
                    );
              },
              child: _buildInvoiceCardsList(invoices),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/sales/invoices/new'),
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildMobileHeader(ThemeData theme, int count) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          // Title with count badge
          Expanded(
            child: Row(
              children: [
                Text(
                  'Ventas',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search button
          IconButton(
            icon: Icon(_isSearchExpanded ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearchExpanded = !_isSearchExpanded;
                if (!_isSearchExpanded) {
                  _searchTerm = '';
                  _searchController.clear();
                }
              });
            },
          ),

          // More options
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'refresh') {
                context.read<SalesService>().loadInvoices(
                      forceRefresh: true,
                    );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 20),
                    SizedBox(width: 12),
                    Text('Actualizar'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileFilterTabs(ThemeData theme) {
    return Column(
      children: [
        if (_isSearchExpanded)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: theme.cardColor,
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar factura, cliente...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchTerm.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchTerm = '';
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.brightness == Brightness.dark
                    ? Colors.grey[800]
                    : Colors.grey[100],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
              ),
              onChanged: (value) {
                setState(() {
                  _searchTerm = value;
                });
              },
            ),
          ),

        // Filter tabs
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _buildMobileStatusChip('Todas', null),
                _buildMobileStatusChip('Borrador', InvoiceStatus.draft),
                _buildMobileStatusChip('Enviada', InvoiceStatus.sent),
                _buildMobileStatusChip('Confirmada', InvoiceStatus.confirmed),
                _buildMobileStatusChip('Pagada', InvoiceStatus.paid),
                _buildMobileStatusChip('Anulada', InvoiceStatus.cancelled),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileStatusChip(String label, InvoiceStatus? status) {
    final isSelected = _filterStatus == status;
    final theme = Theme.of(context);

    // Status colors
    Color color = theme.colorScheme.primary;
    if (status != null) {
      // Simple mapping for chip color
      switch (status) {
        case InvoiceStatus.draft:
          color = Colors.grey;
          break;
        case InvoiceStatus.sent:
          color = Colors.blue;
          break;
        case InvoiceStatus.confirmed:
          color = Colors.orange;
          break;
        case InvoiceStatus.paid:
          color = Colors.green;
          break;
        case InvoiceStatus.cancelled:
          color = Colors.red;
          break;
        case InvoiceStatus.overdue:
          color = Colors.redAccent;
          break;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _filterStatus = status;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : theme.dividerColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color:
                  isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DESKTOP LAYOUT
  // ============================================================
  Widget _buildDesktopLayout(
      List<Invoice> invoices, SalesService salesService) {
    return Column(
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
                onPressed: () {
                  context.go('/sales/invoices/new');
                },
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
              ? _buildDesktopFullList(invoices, salesService)
              : _buildSplitView(invoices, salesService),
        ),
      ],
    );
  }

  Widget _buildDesktopFullList(
      List<Invoice> invoices, SalesService salesService) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            _buildSummaryCards(invoices),
            const SizedBox(height: 16),
            _buildSearchBar(false),
            const SizedBox(height: 8),
            Expanded(
              child:
                  _buildInvoiceTable(invoices, salesService, isFullWidth: true),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleInvoiceSelection(
    Invoice invoice, {
    required bool isSelected,
  }) async {
    if (isSelected) {
      if (!mounted) return;
      setState(() {
        _selectedInvoice = null;
        _isHydratingSelectedInvoice = false;
        _accountingContextInvoiceId = null;
        _accountingContextFuture = null;
      });
      return;
    }

    setState(() {
      _selectedInvoice = invoice;
      _isHydratingSelectedInvoice = true;
      _accountingContextInvoiceId = null;
      _accountingContextFuture = null;
    });

    final fullInvoice = await context.read<SalesService>().fetchInvoice(
          invoice.id!,
        );

    if (!mounted || _selectedInvoice?.id != invoice.id) {
      return;
    }

    setState(() {
      final hydratedInvoice = fullInvoice ?? invoice;
      _selectedInvoice = hydratedInvoice;
      _isHydratingSelectedInvoice = false;
      _primeAccountingContext(hydratedInvoice);
    });
  }

  void _primeAccountingContext(Invoice invoice) {
    final invoiceId = invoice.id;
    if (invoiceId == null || invoiceId.isEmpty) {
      _accountingContextInvoiceId = null;
      _accountingContextFuture = null;
      return;
    }

    _accountingContextInvoiceId = invoiceId;
    _accountingContextFuture =
        _documentAccountingContextService.loadSalesInvoice(
      invoiceId: invoiceId,
      invoiceNumber: invoice.invoiceNumber,
    );
  }

  Future<void> _refreshSelectedInvoiceAfterCorrection(Invoice invoice) async {
    final invoiceId = invoice.id;
    if (invoiceId == null) return;

    final refreshed = await context.read<SalesService>().fetchInvoice(
          invoiceId,
          refresh: true,
        );
    if (!mounted || _selectedInvoice?.id != invoiceId) return;

    setState(() {
      final current = refreshed ?? invoice;
      _selectedInvoice = current;
      _primeAccountingContext(current);
    });
  }

  void _openLinkedPayment(DocumentPaymentRecord payment) {
    if (payment.id.isEmpty ||
        payment.sourceType != DocumentPaymentSourceType.salesPayment) {
      return;
    }

    context.push(
      '/sales/payments?paymentId=${Uri.encodeComponent(payment.id)}',
    );
  }

  Widget _buildSplitView(List<Invoice> invoices, SalesService salesService) {
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

  Widget _buildSummaryCards(List<Invoice> invoices) {
    if (invoices.isEmpty) return const SizedBox.shrink();

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

    final cards = [
      _buildSummaryCard(
        'Por cobrar',
        ChileanUtils.formatCurrency(totalReceivable),
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

  Widget _buildInvoiceCardsList(List<Invoice> invoices) {
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
      padding: const EdgeInsets.only(bottom: 80), // Add padding for FAB
      itemCount: invoices.length,
      itemBuilder: (context, index) {
        final invoice = invoices[index];
        final isSelected = _selectedInvoice?.id == invoice.id;
        final isDark = theme.brightness == Brightness.dark;

        return InkWell(
          onTap: () {
            if (MediaQuery.of(context).size.width < 800) {
              // Mobile: Navigate to details
              context.push('/sales/invoices/${invoice.id}');
            } else {
              // Desktop/Tablet: Select for split view
              _handleInvoiceSelection(invoice, isSelected: isSelected);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : Colors.blue[50])
                  : theme.cardColor,
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
                left: isSelected
                    ? BorderSide(color: theme.colorScheme.primary, width: 3)
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
                        color: theme.hintColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•',
                      style: TextStyle(
                          color: theme.hintColor.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ChileanUtils.formatDate(invoice.date),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.hintColor,
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

  Widget _buildSearchBar([bool isMobile = false]) {
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchTerm = value),
            ),
          ),
          const SizedBox(width: 12),
          if (!isMobile) ...[
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
                  prefs.setBool('invoice_visible_$column',
                      _visibleColumns[column] ?? false);
                });
              },
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () => context.read<SalesService>().loadInvoices(
                  forceRefresh: true,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceTable(List<Invoice> invoices, SalesService salesService,
      {required bool isFullWidth}) {
    if (salesService.isLoadingInvoices) {
      return const Center(child: BrandedLoading());
    }

    if (invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty
                  ? 'No hay facturas'
                  : 'No se encontraron facturas',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final tableWidth =
        MediaQuery.of(context).size.width - (isFullWidth ? 0 : 400);

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

  Widget _buildInvoiceRow(Invoice invoice, bool isSelected, bool isFullWidth) {
    return InkWell(
      onTap: () {
        _handleInvoiceSelection(invoice, isSelected: isSelected);
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
                  _handleInvoiceSelection(
                    invoice,
                    isSelected: value != true,
                  );
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            ..._buildRowCells(invoice, isFullWidth),
            // Actions menu
            SizedBox(
              width: 48,
              height: 38,
              child: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 18, color: Colors.grey[600]),
                tooltip: '',
                padding: EdgeInsets.zero,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 16),
                        SizedBox(width: 8),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Eliminar', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'edit') {
                    context.go('/sales/invoices/${invoice.id}');
                  } else if (value == 'delete') {
                    _confirmDeleteInvoice(invoice);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRowCells(Invoice invoice, bool isFullWidth) {
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
    if (_showPaymentTerminal) {
      return _buildPaymentTerminal(invoice);
    }

    final accountingFuture = _accountingContextInvoiceId == invoice.id
        ? _accountingContextFuture
        : null;

    return Container(
      color: const Color(0xFFF4F6FA),
      child: Column(
        children: [
          _buildActionBar(invoice),
          _buildStatusActionBanner(invoice),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double paperWidth =
                    (constraints.maxWidth - 48).clamp(360.0, 920.0).toDouble();

                return FutureBuilder<DocumentAccountingContext>(
                  future: accountingFuture,
                  builder: (context, snapshot) {
                    final accounting =
                        snapshot.data ?? DocumentAccountingContext.empty;
                    final isLoadingAccounting = accountingFuture != null &&
                        snapshot.connectionState == ConnectionState.waiting;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 34),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1240),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (isLoadingAccounting)
                                const DocumentAccountingLoadingStrip()
                              else
                                DocumentPaymentsDropdown(
                                  title: 'Pagos recibidos',
                                  payments: accounting.payments,
                                  onPaymentTap: _openLinkedPayment,
                                ),
                              const SizedBox(height: 24),
                              DocumentPaperShell(
                                width: paperWidth,
                                status: _documentPreviewStatus(invoice),
                                child:
                                    _buildInvoiceDocument(invoice, paperWidth),
                              ),
                              if (!isLoadingAccounting)
                                DocumentJournalEntriesSection(
                                  entries: accounting.journalEntries,
                                  documentLabel: 'Factura',
                                  emptyReference: invoice.invoiceNumber,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  DocumentPaperStatus _documentPreviewStatus(Invoice invoice) {
    final calculatedBalance = invoice.total - invoice.paidAmount;
    final effectiveBalance = invoice.balance > 0
        ? invoice.balance
        : calculatedBalance.clamp(0.0, invoice.total).toDouble();
    final now = DateTime.now();
    final isPaid = invoice.status == InvoiceStatus.paid ||
        (invoice.paidAmount > 0 && effectiveBalance <= 1);
    final isOverdue = !isPaid &&
        effectiveBalance > 1 &&
        (invoice.status == InvoiceStatus.overdue ||
            (invoice.dueDate != null && invoice.dueDate!.isBefore(now)));

    if (invoice.status == InvoiceStatus.cancelled) {
      return const DocumentPaperStatus(
        label: 'ANULADA',
        foreground: Color(0xFF991B1B),
        background: Color(0xFFFFF1F2),
        border: Color(0xFFFECACA),
      );
    }

    if (isPaid) {
      return const DocumentPaperStatus(
        label: 'PAGADA',
        foreground: Color(0xFF047857),
        background: Color(0xFFECFDF5),
        border: Color(0xFFA7F3D0),
      );
    }

    if (isOverdue) {
      return const DocumentPaperStatus(
        label: 'VENCIDA',
        foreground: Color(0xFFB91C1C),
        background: Color(0xFFFEF2F2),
        border: Color(0xFFFECACA),
      );
    }

    if (invoice.paidAmount > 0 && effectiveBalance > 1) {
      return const DocumentPaperStatus(
        label: 'PAGO PARCIAL',
        foreground: Color(0xFFB45309),
        background: Color(0xFFFFFBEB),
        border: Color(0xFFFDE68A),
      );
    }

    switch (invoice.status) {
      case InvoiceStatus.sent:
        return const DocumentPaperStatus(
          label: 'ENVIADA',
          foreground: Color(0xFF1D4ED8),
          background: Color(0xFFEFF6FF),
          border: Color(0xFFBFDBFE),
        );
      case InvoiceStatus.confirmed:
        return const DocumentPaperStatus(
          label: 'CONFIRMADA',
          foreground: Color(0xFF6D28D9),
          background: Color(0xFFF5F3FF),
          border: Color(0xFFDDD6FE),
        );
      case InvoiceStatus.draft:
      case InvoiceStatus.paid:
      case InvoiceStatus.overdue:
      case InvoiceStatus.cancelled:
        return const DocumentPaperStatus(
          label: 'BORRADOR',
          foreground: Color(0xFF475569),
          background: Color(0xFFF8FAFC),
          border: Color(0xFFE2E8F0),
        );
    }
  }

  Widget _buildPaymentTerminal(Invoice invoice) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => setState(() => _showPaymentTerminal = false),
          tooltip: 'Cancelar y volver al documento',
        ),
        title: Text(
          'TERMINAL DE PAGO',
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey[200]),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: PaymentForm(
              invoice: invoice,
              dismissOnSubmit: false,
              onCompleted: () async {
                final salesService = context.read<SalesService>();
                final updated =
                    await salesService.fetchInvoice(invoice.id!, refresh: true);
                if (mounted) {
                  setState(() {
                    final refreshedInvoice = updated ?? invoice;
                    _selectedInvoice = refreshedInvoice;
                    _showPaymentTerminal = false;
                    _primeAccountingContext(refreshedInvoice);
                  });
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar(Invoice invoice) {
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
                onPressed: () => setState(() {
                  _selectedInvoice = null;
                  _showPaymentTerminal = false;
                  _accountingContextInvoiceId = null;
                  _accountingContextFuture = null;
                }),
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
                  onPressed: () {
                    context.go('/sales/invoices/${invoice.id}');
                  },
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
                  onPressed: () => _sendEmailInvoice(invoice),
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
                  onPressed: () => _shareInvoice(invoice),
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
                    const PopupMenuItem<String>(
                      enabled: false,
                      height: 32,
                      child: Text(
                        'Descargar PDF',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'download_invoice',
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Factura', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'download_invoice_diagnosis',
                      child: Row(
                        children: [
                          Icon(Icons.download_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Factura + Diagnóstico',
                              style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      enabled: false,
                      height: 32,
                      child: Text(
                        'Imprimir',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'print_invoice',
                      child: Row(
                        children: [
                          Icon(Icons.print_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Factura', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'print_invoice_diagnosis',
                      child: Row(
                        children: [
                          Icon(Icons.print_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Factura + Diagnóstico',
                              style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'download_invoice') {
                      _downloadInvoicePDF(
                        invoice,
                        mode: InvoicePdfExportMode.invoiceOnly,
                      );
                    } else if (value == 'download_invoice_diagnosis') {
                      _downloadInvoicePDF(
                        invoice,
                        mode: InvoicePdfExportMode.invoiceWithDiagnosis,
                      );
                    } else if (value == 'print_invoice') {
                      _printInvoice(
                        invoice,
                        mode: InvoicePdfExportMode.invoiceOnly,
                      );
                    } else if (value == 'print_invoice_diagnosis') {
                      _printInvoice(
                        invoice,
                        mode: InvoicePdfExportMode.invoiceWithDiagnosis,
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),

                SalesCorrectionsMenu(
                  invoice: invoice,
                  dense: true,
                  onChanged: () =>
                      _refreshSelectedInvoiceAfterCorrection(invoice),
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
                      _confirmDeleteInvoice(invoice);
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

  bool _isGeneratingPdf = false;

  Future<void> _downloadInvoicePDF(
    Invoice invoice, {
    InvoicePdfExportMode mode = InvoicePdfExportMode.invoiceOnly,
  }) async {
    if (_isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final salesService = context.read<SalesService>();
      await salesService.fetchInvoice(invoice.id!, refresh: true);
      final freshInvoice = salesService.invoices
          .firstWhere((i) => i.id == invoice.id, orElse: () => invoice);
      if (!mounted) return;
      final resolvedBikeNames = await _resolveBikeNames(freshInvoice);
      if (!mounted) return;
      final diagnosisNarratives =
          mode == InvoicePdfExportMode.invoiceWithDiagnosis
              ? await InvoicePdfGenerator.resolveDiagnosisNarratives(
                  context,
                  freshInvoice,
                  resolvedBikeNames,
                )
              : const <InvoiceDiagnosisNarrative>[];

      if (mode == InvoicePdfExportMode.invoiceWithDiagnosis &&
          diagnosisNarratives.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Esta factura no tiene ficha narrativa disponible para exportar.',
              ),
            ),
          );
        }
        return;
      }

      final pdf = await _generateInvoicePDF(
        freshInvoice,
        resolvedBikeNames,
        diagnosisNarratives: diagnosisNarratives,
      );
      final bytes = await pdf.save();
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final initialDirectory =
            await InvoicePdfGenerator.resolveDefaultSaveDirectory();
        final String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Factura PDF',
          fileName: mode.fileNameFor(freshInvoice.invoiceNumber),
          initialDirectory: initialDirectory,
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
                  backgroundColor: Colors.green),
            );
          }
        }
      } else {
        await Printing.sharePdf(
            bytes: bytes,
            filename: 'factura_${freshInvoice.invoiceNumber}.pdf');
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

  Future<void> _printInvoice(
    Invoice invoice, {
    InvoicePdfExportMode mode = InvoicePdfExportMode.invoiceOnly,
  }) async {
    if (_isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final salesService = context.read<SalesService>();
      await salesService.fetchInvoice(invoice.id!, refresh: true);
      final freshInvoice = salesService.invoices
          .firstWhere((i) => i.id == invoice.id, orElse: () => invoice);
      if (!mounted) return;
      final resolvedBikeNames = await _resolveBikeNames(freshInvoice);
      if (!mounted) return;
      final diagnosisNarratives =
          mode == InvoicePdfExportMode.invoiceWithDiagnosis
              ? await InvoicePdfGenerator.resolveDiagnosisNarratives(
                  context,
                  freshInvoice,
                  resolvedBikeNames,
                )
              : const <InvoiceDiagnosisNarrative>[];

      if (mode == InvoicePdfExportMode.invoiceWithDiagnosis &&
          diagnosisNarratives.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Esta factura no tiene ficha narrativa disponible para imprimir.',
              ),
            ),
          );
        }
        return;
      }

      final pdf = await _generateInvoicePDF(
        freshInvoice,
        resolvedBikeNames,
        diagnosisNarratives: diagnosisNarratives,
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: mode.documentNameFor(freshInvoice.invoiceNumber),
      );
    } catch (e) {
      debugPrint('Error printing PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al imprimir: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  /// Resolves bike display names from the database for PDF generation.
  Future<Map<String, String>> _resolveBikeNames(Invoice invoice) async {
    return InvoicePdfGenerator.resolveBikeNames(context, invoice);
  }

  Future<pw.Document> _generateInvoicePDF(
    Invoice invoice,
    Map<String, String> resolvedBikeNames, {
    List<InvoiceDiagnosisNarrative> diagnosisNarratives =
        const <InvoiceDiagnosisNarrative>[],
  }) {
    return InvoicePdfGenerator.generateInvoicePDF(
      context,
      invoice,
      resolvedBikeNames,
      diagnosisNarratives: diagnosisNarratives,
    );
  }

  void _sendEmailInvoice(Invoice invoice) {
    // TODO: Implement email sending
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Función de envío de correo próximamente')),
    );
  }

  void _shareInvoice(Invoice invoice) {
    // TODO: Implement sharing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Función de compartir próximamente')),
    );
  }

  void _confirmDeleteInvoice(Invoice invoice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar factura'),
        content: Text(
            '¿Está seguro que desea eliminar la factura ${invoice.invoiceNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Delete invoice via service
              final messenger = ScaffoldMessenger.of(context);
              try {
                final salesService = context.read<SalesService>();

                await salesService.deleteInvoice(invoice.id!);
                setState(() {
                  _selectedInvoice = null;
                  _isHydratingSelectedInvoice = false;
                  _accountingContextInvoiceId = null;
                  _accountingContextFuture = null;
                });
                await salesService.loadInvoices(
                  forceRefresh: true,
                );

                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Factura eliminada correctamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Error al eliminar factura: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceDocument(Invoice invoice, double containerWidth) {
    // Calculate responsive sizes based on width
    final double scale = (containerWidth / 800.0).clamp(0.6, 1.0);
    final double padding = 40 * scale;
    final double companyNameSize = 22 * scale;
    final double invoiceNumberSize = 15 * scale;
    final double labelSize = 12 * scale;
    final double dataSize = 13 * scale;
    final double spacing = 24 * scale;

    // Get company logo URL
    final appearanceService = context.read<AppearanceService>();
    final logoUrl = appearanceService.companyLogoUrl;
    final hasLogo = logoUrl != null && logoUrl.isNotEmpty;

    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Company logo or text fallback
              if (hasLogo)
                Image.network(
                  logoUrl,
                  width: 120 * scale,
                  height: 40 * scale,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Text(
                    'VIÑABIKE',
                    style: TextStyle(
                      fontSize: companyNameSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                )
              else
                Text(
                  'VIÑABIKE',
                  style: TextStyle(
                    fontSize: companyNameSize,
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
                    ChileanUtils.formatCurrency(invoice.balance),
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
                      invoice.customerName ?? 'Sin registro',
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
                  _buildTableCell('Cantidad', isHeader: true, scale: scale),
                ],
              ),
              ...invoice.items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;

                return TableRow(
                  children: [
                    _buildTableCell('${index + 1}', scale: scale),
                    _buildTableCell(
                      item.productName ?? 'Sin nombre',
                      subtitle: item.description,
                      scale: scale,
                    ),
                    _buildTableCell(item.quantity.toStringAsFixed(2),
                        scale: scale),
                    _buildTableCell(ChileanUtils.formatCurrency(item.unitPrice),
                        scale: scale),
                    _buildTableCell(ChileanUtils.formatCurrency(item.lineTotal),
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
                    _buildTotalRow('Subtotal', invoice.subtotal, scale: scale),
                    const Divider(),
                    _buildTotalRow('Total', invoice.total,
                        isTotal: true, scale: scale),
                    if (invoice.paidAmount > 0) ...[
                      const Divider(),
                      _buildTotalRow('Pago realizado', -invoice.paidAmount,
                          isNegative: true, scale: scale),
                    ],
                    const Divider(thickness: 2),
                    _buildTotalRow(
                        'Saldo adeudado',
                        (invoice.total - invoice.paidAmount)
                            .clamp(0.0, invoice.total),
                        isTotal: true,
                        scale: scale),
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

  // ============================================================
  // STATUS ACTION BANNER (Zoho-like)
  // ============================================================
  Widget _buildStatusActionBanner(Invoice invoice) {
    String? nextActionLabel;
    String? subLabel;
    VoidCallback? onActionPressed;
    List<Widget> secondaryActions = [];

    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final effectiveBalance =
        (invoice.total - invoice.paidAmount).clamp(0.0, invoice.total);

    switch (invoice.status) {
      case InvoiceStatus.draft:
        nextActionLabel = 'Marcar como enviada';
        subLabel =
            'Mueva la factura al estado "Enviada" para indicar que fue entregada al cliente.';
        onActionPressed = () => _markAsSent(invoice);
        break;

      case InvoiceStatus.sent:
        nextActionLabel = 'Confirmar';
        subLabel =
            'Confirme la factura para contabilizarla y deducir el stock del inventario.';
        onActionPressed = () => _markAsConfirmed(invoice);
        secondaryActions = [
          OutlinedButton.icon(
            onPressed: () => _revertToDraft(invoice),
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Volver a borrador'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ];
        break;

      case InvoiceStatus.confirmed:
        if (effectiveBalance > 0) {
          nextActionLabel = 'Registrar pago';
          subLabel =
              'Factura pendiente de pago. Saldo: ${ChileanUtils.formatCurrency(effectiveBalance)}.';
          onActionPressed = () => _openPaymentForm(invoice);
        } else {
          subLabel = 'Factura confirmada y contabilizada.';
        }

        if (invoice.paidAmount == 0) {
          secondaryActions.add(
            OutlinedButton.icon(
              onPressed: () => _revertToSent(invoice),
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Volver a enviada'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          );
        } else {
          secondaryActions.add(
            OutlinedButton.icon(
              onPressed: () => _undoLastPayment(invoice),
              icon: const Icon(Icons.history, size: 16),
              label: const Text('Deshacer último pago'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red[700],
                side: BorderSide(color: Colors.red[100]!),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          );
        }
        break;

      case InvoiceStatus.paid:
        subLabel = 'Esta factura ha sido pagada en su totalidad.';
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

      case InvoiceStatus.overdue:
        nextActionLabel = 'Registrar pago';
        subLabel =
            'Factura VENCIDA. Saldo: ${ChileanUtils.formatCurrency(effectiveBalance)}.';
        onActionPressed = () => _openPaymentForm(invoice);
        break;

      case InvoiceStatus.cancelled:
        subLabel = 'Esta factura ha sido ANULADA.';
        break;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child:
                      Icon(Icons.info_outline, color: primaryColor, size: 20),
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
                      const SizedBox(height: 2),
                      Text(
                        subLabel,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87),
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
                        backgroundColor: invoice.status == InvoiceStatus.sent
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
        ],
      ),
    );
  }

  // ============================================================
  // STATUS TRANSITION LOGIC
  // ============================================================

  Future<void> _markAsSent(Invoice invoice) async {
    if (invoice.id == null) return;
    final salesService = context.read<SalesService>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final updated = await salesService.updateInvoiceStatus(
          invoice.id!, InvoiceStatus.sent);
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _selectedInvoice = updated;
          _primeAccountingContext(updated);
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Factura marcada como enviada')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text('No se pudo actualizar el estado: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _markAsConfirmed(Invoice invoice) async {
    if (invoice.id == null) return;

    final salesService = context.read<SalesService>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final updated = await salesService.updateInvoiceStatus(
          invoice.id!, InvoiceStatus.confirmed);
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _selectedInvoice = updated;
          _primeAccountingContext(updated);
        });
        messenger.showSnackBar(
          const SnackBar(
              content: Text(
                  'Factura confirmada - contabilizada y stock actualizado')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text('No se pudo confirmar la factura: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _revertToDraft(Invoice invoice) async {
    if (invoice.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revertir a borrador'),
        content: const Text(
          'Esto eliminará el asiento contable y restaurará el inventario. '
          '¿Está seguro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revertir'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final salesService = context.read<SalesService>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final updated = await salesService.updateInvoiceStatus(
          invoice.id!, InvoiceStatus.draft);
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _selectedInvoice = updated;
          _primeAccountingContext(updated);
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Factura revertida a borrador')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text('No se pudo revertir: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _revertToSent(Invoice invoice) async {
    if (invoice.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revertir a enviada'),
        content: const Text(
          'Esto eliminará el asiento contable y restaurará el inventario. '
          '¿Está seguro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revertir'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final salesService = context.read<SalesService>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final updated = await salesService.updateInvoiceStatus(
          invoice.id!, InvoiceStatus.sent);
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _selectedInvoice = updated;
          _primeAccountingContext(updated);
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Factura revertida a enviada')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text('No se pudo revertir: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _undoLastPayment(Invoice invoice) async {
    if (invoice.id == null) return;
    final salesService = context.read<SalesService>();
    final messenger = ScaffoldMessenger.of(context);
    await salesService.loadPayments(forceRefresh: true);
    final payments = salesService.getPaymentsForInvoice(invoice.id!);

    if (payments.isEmpty) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('No hay pagos para deshacer')),
      );
      return;
    }

    final lastPayment = payments.first;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deshacer pago'),
        content: Text(
          'Se eliminará el pago de ${ChileanUtils.formatCurrency(lastPayment.amount)} '
          'y su asiento contable asociado. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar pago'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await salesService.deletePayment(lastPayment.id!);
      // Refresh to get updated balance/status
      final updated =
          await salesService.fetchInvoice(invoice.id!, refresh: true);
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _selectedInvoice = updated;
          _primeAccountingContext(updated);
        });
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Pago eliminado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo eliminar el pago: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openPaymentForm(Invoice invoice) async {
    final effectiveBalance =
        (invoice.total - invoice.paidAmount).clamp(0.0, invoice.total);
    if (invoice.id == null || effectiveBalance <= 0) return;
    setState(() => _showPaymentTerminal = true);
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
