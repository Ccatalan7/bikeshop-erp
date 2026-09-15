import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/document_accounting_preview.dart';
import '../../../shared/services/document_accounting_context_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/purchase_document_pdf_generator.dart';
import '../../../shared/models/payment_method.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_payment.dart';
import '../models/purchase_receipt.dart';
import '../models/purchase_receipt_resolution.dart';
import '../services/purchase_credit_note_service.dart';
import '../services/purchase_receipt_resolution_service.dart';
import '../services/purchase_receiving_service.dart';
import '../services/purchase_supplier_return_service.dart';
import '../services/purchase_service.dart';
import '../widgets/purchase_invoice_evidence_dropdown.dart';
import '../widgets/purchase_receipt_resolution_register.dart';
import 'purchase_credit_note_page.dart';
import 'purchase_receiving_page.dart';
import 'purchase_supplier_return_page.dart';
import '../../../shared/models/tax_treatment.dart';
import 'package:printing/printing.dart';
import '../../settings/services/appearance_service.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/widgets/branded_loading.dart';
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
  PurchaseInvoice? _receiptWorkspaceInvoice;
  Map<String, PurchaseReceiptFulfillment> _receiptFulfillments = const {};
  bool _isHydratingSelectedInvoice = false;
  final DocumentAccountingContextService _documentAccountingContextService =
      DocumentAccountingContextService();
  Future<DocumentAccountingContext>? _accountingContextFuture;
  String? _accountingContextInvoiceId;
  Future<List<PurchaseReceiptRecord>>? _receiptHistoryFuture;
  String? _receiptHistoryInvoiceId;
  Future<List<PurchaseReceiptResolutionCase>>? _receiptResolutionFuture;
  String? _receiptResolutionInvoiceId;
  String? _focusedPurchaseCreditNoteId;
  String? _focusedPurchaseRefundId;
  String? _focusedSupplierReturnId;
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
  bool _isOpeningReceipt = false;
  String _inlinePaymentIdempotencyKey = const Uuid().v4();
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

  String _documentKindLabel(PurchaseInvoice invoice) {
    final serverLabel = invoice.sourceDocumentKindLabel?.trim();
    if (serverLabel != null && serverLabel.isNotEmpty) return serverLabel;
    return invoice.sourceDocumentKind == PurchaseSourceDocumentKind.defaultCode
        ? 'Factura'
        : 'Documento de compra';
  }

  PurchaseReceiptFulfillment _fulfillmentFor(PurchaseInvoice invoice) {
    final invoiceId = invoice.id;
    if (invoiceId != null) {
      final fulfillment = _receiptFulfillments[invoiceId];
      if (fulfillment != null) return fulfillment;
    }
    final readModelFulfillment = invoice.receiptFulfillment;
    if (readModelFulfillment != null) return readModelFulfillment;
    return PurchaseReceiptFulfillment.derive(
      expectedQuantities: invoice.items
          .map((item) => item.quantity.round())
          .toList(growable: false),
      acceptedByLine: const {},
      legacyReceived: invoice.status == PurchaseInvoiceStatus.received ||
          invoice.receivedDate != null,
    );
  }

  Future<void> _loadReceiptFulfillments(
    Iterable<PurchaseInvoice> invoices,
  ) async {
    final byId = <String, PurchaseInvoice>{};
    for (final invoice in invoices) {
      final invoiceId = invoice.id;
      if (invoiceId != null && invoiceId.isNotEmpty) {
        byId[invoiceId] = invoice;
      }
    }
    final targets = byId.values.toList(growable: false);
    if (targets.isEmpty || !mounted) return;

    try {
      final fulfillments =
          await PurchaseReceivingService().getFulfillments(targets);
      if (!mounted) return;
      setState(() {
        _receiptFulfillments = {
          ..._receiptFulfillments,
          ...fulfillments,
        };
      });
    } catch (error) {
      debugPrint(
        'No se pudo cargar el estado físico de documentos de compra: $error',
      );
    }
  }

  Future<void> _refreshInvoiceList() async {
    await context
        .read<PurchaseService>()
        .getPurchaseInvoicesForList(forceRefresh: true);
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
      title: 'Documentos de compra',
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
                  'Documentos de compra',
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
            onRefresh: _refreshInvoiceList,
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
        _receiptWorkspaceInvoice = null;
        _showingPaymentForm = false;
        _isHydratingSelectedInvoice = false;
        _accountingContextInvoiceId = null;
        _accountingContextFuture = null;
        _receiptHistoryInvoiceId = null;
        _receiptHistoryFuture = null;
        _receiptResolutionInvoiceId = null;
        _receiptResolutionFuture = null;
        _focusedPurchaseCreditNoteId = null;
        _focusedPurchaseRefundId = null;
        _focusedSupplierReturnId = null;
      });
      return;
    }

    setState(() {
      _selectedInvoice = invoice;
      _receiptWorkspaceInvoice = null;
      _showingPaymentForm = false;
      _isHydratingSelectedInvoice = true;
      _accountingContextInvoiceId = null;
      _accountingContextFuture = null;
      _receiptHistoryInvoiceId = null;
      _receiptHistoryFuture = null;
      _receiptResolutionInvoiceId = null;
      _receiptResolutionFuture = null;
      _focusedPurchaseCreditNoteId = null;
      _focusedPurchaseRefundId = null;
      _focusedSupplierReturnId = null;
    });

    final fullInvoice =
        await context.read<PurchaseService>().fetchPurchaseInvoice(
              invoice.id!,
            );

    if (!mounted || _selectedInvoice?.id != invoice.id) {
      return;
    }

    final hydratedInvoice = (fullInvoice ?? invoice).copyWith(
      receiptFulfillment: invoice.receiptFulfillment,
    );
    if (hydratedInvoice.receiptFulfillment == null) {
      await _loadReceiptFulfillments([hydratedInvoice]);
      if (!mounted || _selectedInvoice?.id != invoice.id) {
        return;
      }
    }

    setState(() {
      _selectedInvoice = hydratedInvoice;
      _isHydratingSelectedInvoice = false;
      _primeAccountingContext(hydratedInvoice);
    });
  }

  void _primeAccountingContext(PurchaseInvoice invoice) {
    final invoiceId = invoice.id;
    if (invoiceId == null || invoiceId.isEmpty) {
      _accountingContextInvoiceId = null;
      _accountingContextFuture = null;
      _receiptHistoryInvoiceId = null;
      _receiptHistoryFuture = null;
      _receiptResolutionInvoiceId = null;
      _receiptResolutionFuture = null;
      return;
    }

    _accountingContextInvoiceId = invoiceId;
    _accountingContextFuture =
        _documentAccountingContextService.loadPurchaseInvoice(
      invoiceId: invoiceId,
      invoiceNumber: invoice.invoiceNumber,
    );
    _receiptHistoryInvoiceId = invoiceId;
    _receiptHistoryFuture = PurchaseReceivingService().getHistory(invoiceId);
    _receiptResolutionInvoiceId = invoiceId;
    _receiptResolutionFuture =
        PurchaseReceiptResolutionService().getCasesForInvoice(invoiceId);
  }

  void _openLinkedPayment(DocumentPaymentRecord payment) {
    if (payment.id.isEmpty) return;

    switch (payment.sourceType) {
      case DocumentPaymentSourceType.purchasePayment:
        context.push(
          '/purchases/payments?paymentId=${Uri.encodeComponent(payment.id)}',
        );
        break;
      case DocumentPaymentSourceType.expense:
        context.push('/accounting/expenses/${Uri.encodeComponent(payment.id)}');
        break;
      case DocumentPaymentSourceType.salesPayment:
      case DocumentPaymentSourceType.unknown:
        break;
    }
  }

  Future<void> _openLinkedReceipt(PurchaseReceiptRecord receipt) async {
    await _openReceiptById(receipt.id);
  }

  Future<void> _openReceiptById(String receiptId) async {
    if (receiptId.isEmpty) return;
    await context.push(
      '/purchases/receipts/${Uri.encodeComponent(receiptId)}',
    );
    if (!mounted || _selectedInvoice?.id == null) return;
    final current = _selectedInvoice!;
    setState(() => _primeAccountingContext(current));
    await _loadReceiptFulfillments([current]);
  }

  Future<void> _refreshSelectedInvoiceResolutionContext() async {
    final selected = _selectedInvoice;
    final invoiceId = selected?.id;
    if (selected == null || invoiceId == null || invoiceId.isEmpty) return;
    setState(() {
      _focusedPurchaseCreditNoteId = null;
      _focusedPurchaseRefundId = null;
      _focusedSupplierReturnId = null;
    });
    try {
      final refreshed = await context
          .read<PurchaseService>()
          .getPurchaseInvoice(invoiceId, refresh: true);
      final current = refreshed ?? selected;
      final fulfillment =
          await PurchaseReceivingService().getFulfillment(current);
      if (!mounted || _selectedInvoice?.id != invoiceId) return;
      setState(() {
        _selectedInvoice = current;
        _receiptFulfillments = {
          ..._receiptFulfillments,
          invoiceId: fulfillment,
        };
        _primeAccountingContext(current);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'El documento se cerró, pero no se pudo actualizar la compra: '
            '$error',
          ),
        ),
      );
    }
  }

  Future<void> _openResolutionCase(
    PurchaseReceiptResolutionCase resolutionCase,
  ) =>
      _openReceiptById(resolutionCase.purchaseReceiptId);

  Future<void> _openResolutionDocument(
    PurchaseReceiptResolutionCase resolutionCase,
    PurchaseReceiptResolutionAllocation allocation,
    PurchaseReceiptResolutionDocumentReference document,
  ) async {
    switch (document.kind) {
      case PurchaseReceiptResolutionDocumentKind.creditNote:
      case PurchaseReceiptResolutionDocumentKind.supplierRefund:
        final creditNoteId = allocation.purchaseCreditNoteId;
        if (creditNoteId != null && creditNoteId.isNotEmpty) {
          setState(() {
            _focusedPurchaseCreditNoteId = creditNoteId;
            _focusedPurchaseRefundId = document.kind ==
                    PurchaseReceiptResolutionDocumentKind.supplierRefund
                ? document.id
                : null;
            _focusedSupplierReturnId = null;
            _receiptWorkspaceInvoice = null;
            _showingPaymentForm = false;
          });
          return;
        }
        break;
      case PurchaseReceiptResolutionDocumentKind.laterReceipt:
        if (document.id.isNotEmpty) {
          await _openReceiptById(document.id);
          return;
        }
        break;
      case PurchaseReceiptResolutionDocumentKind.supplierReturn:
        if (document.id.isNotEmpty) {
          setState(() {
            _focusedSupplierReturnId = document.id;
            _focusedPurchaseCreditNoteId = null;
            _focusedPurchaseRefundId = null;
            _receiptWorkspaceInvoice = null;
            _showingPaymentForm = false;
          });
          return;
        }
        break;
      case PurchaseReceiptResolutionDocumentKind.documentedLoss:
      case PurchaseReceiptResolutionDocumentKind.documentedLossReversal:
        break;
    }

    await _openReceiptById(resolutionCase.purchaseReceiptId);
  }

  Future<void> _openFirstPendingResolution(PurchaseInvoice invoice) async {
    final invoiceId = invoice.id;
    if (invoiceId == null || invoiceId.isEmpty) return;
    try {
      final cases = await PurchaseReceiptResolutionService()
          .getCasesForInvoice(invoiceId);
      PurchaseReceiptResolutionCase? pending;
      for (final resolutionCase in cases) {
        if (resolutionCase.isOpen) {
          pending = resolutionCase;
          break;
        }
      }
      if (pending != null) {
        await _openResolutionCase(pending);
        return;
      }
      if (mounted) await _receiveProducts(invoice);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudieron abrir las diferencias: $error'),
        ),
      );
    }
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
                  hintText: 'Buscar documento, proveedor...',
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
            tooltip: 'Nuevo documento de compra',
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
              : _focusedSupplierReturnId != null && _selectedInvoice != null
                  ? PurchaseSupplierReturnPage(
                      invoice: _selectedInvoice!,
                      service: PurchaseSupplierReturnService(),
                      focusReturnId: _focusedSupplierReturnId,
                      embedded: true,
                      onClose: _refreshSelectedInvoiceResolutionContext,
                    )
                  : _focusedPurchaseCreditNoteId != null &&
                          _selectedInvoice != null
                      ? PurchaseCreditNotePage(
                          invoice: _selectedInvoice!,
                          service: PurchaseCreditNoteService(),
                          focusCreditNoteId: _focusedPurchaseCreditNoteId,
                          focusRefundId: _focusedPurchaseRefundId,
                          embedded: true,
                          onClose: _refreshSelectedInvoiceResolutionContext,
                        )
                      : _receiptWorkspaceInvoice != null
                          ? PurchaseReceivingWorkspace(
                              key: ValueKey(
                                'receipt-${_receiptWorkspaceInvoice!.id}',
                              ),
                              invoice: _receiptWorkspaceInvoice!,
                              onCancel: () => setState(
                                () => _receiptWorkspaceInvoice = null,
                              ),
                              onCompleted: _handleReceiptCompleted,
                            )
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
        'Documentos contabilizados',
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
              'No se encontraron documentos de compra',
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
                _openDocumentPage(invoice);
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
                      Expanded(
                        child: Text(
                          '${_documentKindLabel(invoice)} · ${invoice.invoiceNumber}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusChip(invoice),
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
                            ? 'N° interno'
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
            onPressed: _refreshInvoiceList,
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
                  ? 'No hay documentos de compra'
                  : 'No se encontraron documentos',
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
      'invoice_number': 'N° interno',
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
                            size: 18,
                            color: invoice.status == PurchaseInvoiceStatus.draft
                                ? Colors.red[700]
                                : Colors.grey[700]),
                        const SizedBox(width: 12),
                        Text(
                          invoice.status == PurchaseInvoiceStatus.draft
                              ? 'Eliminar borrador'
                              : 'Revisar reversión',
                          style: TextStyle(
                            color: invoice.status == PurchaseInvoiceStatus.draft
                                ? Colors.red[700]
                                : Colors.grey[800],
                          ),
                        ),
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
        await _openDocumentPage(invoice);
        break;
      case 'edit':
        await _openDocumentPage(invoice, edit: true);
        break;
      case 'delete':
        await _confirmDeleteInvoice(invoice);
        break;
    }
  }

  /// Opens the document page and, on return, re-reads what the operator may
  /// have changed there. The service refreshes the list rows itself; the
  /// selected invoice is page state and kept showing the pre-edit document
  /// until a manual reload.
  Future<void> _openDocumentPage(
    PurchaseInvoice invoice, {
    bool edit = false,
  }) async {
    final id = invoice.id;
    if (id == null || id.isEmpty) return;
    await context.push('/purchases/$id${edit ? '?edit=true' : ''}');
    if (!mounted || _selectedInvoice?.id != id) return;
    await _refreshSelectedInvoiceResolutionContext();
  }

  Future<void> _confirmDeleteInvoice(PurchaseInvoice invoice) async {
    if (invoice.status != PurchaseInvoiceStatus.draft) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.account_tree_outlined),
          title: const Text('Este documento conserva evidencia contable'),
          content: const SizedBox(
            width: 560,
            child: Text(
              'Un documento confirmado, pagado o recibido no se elimina. '
              'Primero deben anularse, mediante sus propias reversas, los '
              'documentos dependientes en este orden: reembolsos, notas de '
              'crédito, pérdidas documentadas o entregas posteriores, '
              'recepciones de stock y pagos. Cuando el documento vuelva a '
              'Borrador podrá eliminarse sin borrar evidencia histórica.',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.red, size: 48),
        title: const Text('Eliminar documento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '¿Estás seguro de eliminar el documento "${invoice.invoiceNumber}"?'),
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
          setState(() {
            _selectedInvoice = null;
            _accountingContextInvoiceId = null;
            _accountingContextFuture = null;
            _receiptHistoryInvoiceId = null;
            _receiptHistoryFuture = null;
            _receiptResolutionInvoiceId = null;
            _receiptResolutionFuture = null;
            _focusedPurchaseCreditNoteId = null;
            _focusedPurchaseRefundId = null;
            _focusedSupplierReturnId = null;
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Documento "${invoice.invoiceNumber}" eliminado'),
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
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              invoice.invoiceNumber,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              _documentKindLabel(invoice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
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
        content = _buildStatusChip(invoice);
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

  ({
    String label,
    Color foreground,
    Color background,
  }) _statusPresentationFor(PurchaseInvoice invoice) {
    final status = invoice.status;
    final fulfillment = _fulfillmentFor(invoice);
    final labels = {
      PurchaseInvoiceStatus.draft: 'BORRADOR',
      PurchaseInvoiceStatus.sent: 'ENVIADA',
      PurchaseInvoiceStatus.confirmed: 'CONFIRMADA',
      PurchaseInvoiceStatus.received: 'RECIBIDA',
      PurchaseInvoiceStatus.paid: 'PAGADA',
      PurchaseInvoiceStatus.cancelled: 'ANULADA',
    };

    final isPaid = status == PurchaseInvoiceStatus.paid ||
        (invoice.paidAmount > 0 && _effectiveBalance(invoice) <= 1);
    if (fulfillment.isClosedWithDifference) {
      return (
        label: isPaid ? 'PAGADA · CERRADA CON DIF.' : 'CERRADA CON DIF.',
        foreground: const Color(0xFF6F480B),
        background: const Color(0xFFF0D9A7),
      );
    }
    if (fulfillment.isComplete) {
      return (
        label: isPaid ? 'PAGADA · RECIBIDA' : 'RECIBIDA',
        foreground: const Color(0xFF165F52),
        background: const Color(0xFFCFE8DF),
      );
    }
    if (fulfillment.isOpen) {
      return (
        label: isPaid ? 'PAGADA · PARCIAL' : 'RECEP. PARCIAL',
        foreground: const Color(0xFF6F480B),
        background: const Color(0xFFF0D9A7),
      );
    }

    final colors = {
      PurchaseInvoiceStatus.draft: Colors.grey,
      PurchaseInvoiceStatus.sent: Colors.blue,
      PurchaseInvoiceStatus.confirmed: Colors.purple,
      PurchaseInvoiceStatus.received: Colors.green,
      PurchaseInvoiceStatus.paid: Colors.blue,
      PurchaseInvoiceStatus.cancelled: Colors.red,
    };
    final color = colors[status] ?? Colors.grey;
    return (
      label: labels[status] ?? status.name.toUpperCase(),
      foreground: color,
      background: color.withValues(alpha: 0.12),
    );
  }

  Widget _buildStatusChip(PurchaseInvoice invoice) {
    final presentation = _statusPresentationFor(invoice);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: presentation.background,
        border: Border.all(
          color: presentation.foreground.withValues(alpha: 0.32),
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        presentation.label,
        style: TextStyle(
          color: presentation.foreground,
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
        setState(() {
          _selectedInvoice = updated;
          _primeAccountingContext(updated);
        });
      }

      String message;
      switch (newStatus) {
        case PurchaseInvoiceStatus.sent:
          message = 'Documento enviado al proveedor';
          break;
        case PurchaseInvoiceStatus.confirmed:
          message = invoice.sourceDocumentWorkflowKind == 'direct_purchase'
              ? 'Compra confirmada'
              : 'Documento confirmado';
          break;
        case PurchaseInvoiceStatus.received:
          message = 'Recepción registrada. Inventario actualizado.';
          break;
        case PurchaseInvoiceStatus.draft:
          message = 'Documento revertido a borrador';
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

  Future<void> _receiveProducts(PurchaseInvoice invoice) async {
    final invoiceId = invoice.id;
    if (invoiceId == null || _isOpeningReceipt) return;
    final purchaseService = context.read<PurchaseService>();
    setState(() => _isOpeningReceipt = true);
    try {
      final receivingService = PurchaseReceivingService();
      final mode = await receivingService.getControlMode();
      if (!mode.acceptsCommands) {
        if (mounted) setState(() => _isOpeningReceipt = false);
        await _updateStatus(invoice, PurchaseInvoiceStatus.received);
        return;
      }

      final fullInvoice =
          await purchaseService.getPurchaseInvoice(invoiceId, refresh: true);
      if (fullInvoice == null) {
        throw StateError('No se pudo cargar el documento completo.');
      }
      if (!mounted) return;
      final fulfillment = await receivingService.getFulfillment(fullInvoice);
      if (!mounted) return;
      setState(() {
        _receiptFulfillments = {
          ..._receiptFulfillments,
          invoiceId: fulfillment,
        };
      });
      if (fulfillment.isClosed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fulfillment.isClosedWithDifference
                  ? 'La recepción ya está cerrada mediante una resolución de '
                      'diferencia. No se registró nada.'
                  : 'La recepción física ya está completa. '
                      'No se registró nada.',
            ),
          ),
        );
        return;
      }
      setState(() {
        _receiptWorkspaceInvoice = fullInvoice;
        _showingPaymentForm = false;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir la recepción: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningReceipt = false);
    }
  }

  Future<void> _handleReceiptCompleted(PurchaseReceiptResult result) async {
    final invoice = _receiptWorkspaceInvoice;
    final invoiceId = invoice?.id;
    if (invoice == null || invoiceId == null) return;

    try {
      final purchaseService = context.read<PurchaseService>();
      final refreshed =
          await purchaseService.getPurchaseInvoice(invoiceId, refresh: true);
      final current = refreshed ?? invoice;
      final fulfillment =
          await PurchaseReceivingService().getFulfillment(current);
      if (!mounted) return;
      setState(() {
        _selectedInvoice = current;
        _receiptFulfillments = {
          ..._receiptFulfillments,
          invoiceId: fulfillment,
        };
        _receiptWorkspaceInvoice = null;
        _primeAccountingContext(current);
      });

      final openDifferenceQuantity = fulfillment.unresolvedDifferenceQuantity;
      if (openDifferenceQuantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recepción ${result.receiptNumber} registrada'),
          ),
        );
        return;
      }

      final resolveNow = await _showReceiptRegisteredDecision(
        result: result,
        openDifferenceQuantity: openDifferenceQuantity,
      );
      if (!mounted) return;
      if (resolveNow) {
        await _openFirstPendingResolution(current);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.receiptNumber} quedó con '
            '$openDifferenceQuantity '
            '${openDifferenceQuantity == 1 ? 'unidad pendiente' : 'unidades pendientes'}. '
            'Quedó disponible en Diferencias y resoluciones dentro de la '
            'documento para cuando tengas respuesta del proveedor.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _receiptWorkspaceInvoice = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'La recepción ${result.receiptNumber} quedó registrada, pero no '
            'se pudo actualizar la vista. Usa Actualizar. Detalle: $error',
          ),
        ),
      );
    }
  }

  Future<bool> _showReceiptRegisteredDecision({
    required PurchaseReceiptResult result,
    required int openDifferenceQuantity,
  }) async {
    final resolveNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.fact_check_outlined),
          title: const Text('Recepción registrada'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${result.receiptNumber} quedó registrada y '
                  '$openDifferenceQuantity '
                  '${openDifferenceQuantity == 1 ? 'unidad quedó con diferencia' : 'unidades quedaron con diferencia'}.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Las diferencias quedaron abiertas. Registrar la recepción '
                  'no genera automáticamente una nota de crédito, una entrega '
                  'posterior ni una pérdida contable.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Puedes abrir ahora el caso pendiente y su recepción de '
                  'origen, o dejarlo en Diferencias y resoluciones hasta '
                  'tener una respuesta del proveedor.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Resolver después'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Resolver ahora'),
            ),
          ],
        ),
      ),
    );
    return resolveNow ?? false;
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
      _inlinePaymentIdempotencyKey = const Uuid().v4();
    });
    final paymentMethodService = context.read<PaymentMethodService>();
    await paymentMethodService.loadPaymentMethods();
    if (mounted) {
      setState(() {
        _isLoadingPaymentMethods = false;
        _paymentMethods = paymentMethodService.outgoingPaymentMethods;
        if (_paymentMethods.isNotEmpty) {
          _selectedPaymentMethod = _paymentMethods.first;
        }
        // Pre-fill the balance
        final balance = _effectiveBalance(invoice);
        _paymentAmountController.text =
            balance > 0 ? balance.toStringAsFixed(0) : '';
      });
    }
  }

  double _effectiveBalance(PurchaseInvoice invoice) {
    final b = invoice.balance;
    if (b.abs() < 1) return 0;
    if (b > 0) return b;
    final calculated = invoice.total - invoice.paidAmount;
    if (calculated.abs() < 1) return 0;
    return calculated < 0 ? 0 : calculated;
  }

  Future<void> _submitInlinePayment(PurchaseInvoice invoice) async {
    if (_isSavingPayment) {
      return;
    }

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
    final amountCents = (amount * 100).round();
    final balanceCents = (balance * 100).round();
    if (amountCents > balanceCents) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'El pago no puede exceder el saldo (${ChileanUtils.formatCurrency(balance)})')),
      );
      return;
    }
    final purchaseService = context.read<PurchaseService>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isSavingPayment = true);
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) return;

      final payment = PurchasePayment(
        tenantId: tenantId,
        invoiceId: invoice.id!,
        paymentMethodId: _selectedPaymentMethod!.id,
        idempotencyKey: _inlinePaymentIdempotencyKey,
        amount: amountCents / 100,
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
          backgroundColor: Colors.green,
        ),
      );

      final updated = await purchaseService.getPurchaseInvoice(invoice.id!);

      if (!mounted) return;

      setState(() {
        final refreshedInvoice = updated ?? invoice;
        _selectedInvoice = refreshedInvoice;
        _showingPaymentForm = false;
        _inlinePaymentIdempotencyKey = const Uuid().v4();
        _primeAccountingContext(refreshedInvoice);
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

      setState(() {
        final refreshedInvoice = updated ?? invoice;
        _selectedInvoice = refreshedInvoice;
        _primeAccountingContext(refreshedInvoice);
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Pago eliminado correctamente'),
          backgroundColor: Colors.green,
        ),
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

    final effectiveBalance = _effectiveBalance(invoice);
    final fulfillment = _fulfillmentFor(invoice);
    final isDirectPurchase =
        invoice.sourceDocumentWorkflowKind == 'direct_purchase';

    switch (invoice.status) {
      case PurchaseInvoiceStatus.draft:
        nextActionLabel = isDirectPurchase ? 'Confirmar compra' : 'Enviar';
        subLabel = isDirectPurchase
            ? 'Confirma que esta compra directa ocurrió; recepción y pago se registran por separado.'
            : 'Envía la orden al proveedor.';
        onActionPressed = () => _updateStatus(
              invoice,
              isDirectPurchase
                  ? PurchaseInvoiceStatus.confirmed
                  : PurchaseInvoiceStatus.sent,
            );
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
            onPressed: () => _updateStatus(
              invoice,
              isDirectPurchase
                  ? PurchaseInvoiceStatus.draft
                  : PurchaseInvoiceStatus.sent,
            ),
            icon: const Icon(Icons.undo, size: 16),
            label: Text(
              isDirectPurchase ? 'Volver a borrador' : 'Volver a enviado',
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        );

        if (invoice.prepaymentModel) {
          if (effectiveBalance <= 0) {
            nextActionLabel = 'Registrar recepción';
            subLabel =
                'Compra prepagada en su totalidad. Registra la recepción física para ingresar al inventario.';
            onActionPressed = () => _receiveProducts(invoice);
          } else {
            nextActionLabel = 'Registrar pago';
            subLabel =
                'Saldo pendiente: ${ChileanUtils.formatCurrency(effectiveBalance)}. Debes pagar antes de recibir los productos.';
            onActionPressed = () => _openPaymentForm(invoice);
          }
        } else {
          nextActionLabel = 'Registrar recepción';
          subLabel =
              'Confirma la recepción física para ingresar al inventario antes del pago.';
          onActionPressed = () => _receiveProducts(invoice);
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
        subLabel = 'Este documento ha sido pagado en su totalidad.';
        if (invoice.prepaymentModel) {
          nextActionLabel = 'Registrar recepción';
          subLabel =
              'Compra prepagada. Registra la recepción física para ingresar al inventario.';
          onActionPressed = () => _receiveProducts(invoice);
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

    final hasPhysicalWorkflow =
        invoice.status == PurchaseInvoiceStatus.confirmed ||
            invoice.status == PurchaseInvoiceStatus.received ||
            invoice.status == PurchaseInvoiceStatus.paid;
    if (hasPhysicalWorkflow && fulfillment.isClosedWithDifference) {
      subLabel = 'Cerrada con diferencia: ${fulfillment.acceptedQuantity} de '
          '${fulfillment.expectedQuantity} unidades ingresaron físicamente; '
          '${fulfillment.resolvedDifferenceQuantity} se cerraron mediante '
          'resolución vinculada.';
      if (effectiveBalance > 0) {
        nextActionLabel = 'Registrar pago';
        onActionPressed = () => _openPaymentForm(invoice);
      } else {
        nextActionLabel = null;
        onActionPressed = null;
      }
    } else if (hasPhysicalWorkflow && fulfillment.isComplete) {
      subLabel = fulfillment.hasReportedDifferences
          ? 'Recepción física completa con diferencias informadas. '
              'Inventario y resolución comercial se controlan por separado.'
          : 'Recepción física completa. El inventario ya fue actualizado.';
      if (effectiveBalance > 0) {
        nextActionLabel = 'Registrar pago';
        onActionPressed = () => _openPaymentForm(invoice);
      } else {
        nextActionLabel = null;
        onActionPressed = null;
      }
    } else if (hasPhysicalWorkflow && fulfillment.isOpen) {
      final openDifferences = fulfillment.unresolvedDifferenceQuantity;
      if (openDifferences > 0) {
        nextActionLabel = 'Resolver diferencias';
        subLabel = '$openDifferences '
            '${openDifferences == 1 ? 'unidad quedó pendiente' : 'unidades quedaron pendientes'} '
            'de resolución. No se aplicará ninguna consecuencia contable o '
            'logística hasta que elijas una resolución.';
        onActionPressed = () => _openFirstPendingResolution(invoice);
      } else {
        nextActionLabel = 'Registrar recepción';
        subLabel =
            'Recepción parcial: ${fulfillment.remainingQuantity} unidades '
            'siguen pendientes de recepción física.';
        onActionPressed = () => _receiveProducts(invoice);
      }
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
    final accountingFuture = _accountingContextInvoiceId == invoice.id
        ? _accountingContextFuture
        : null;
    final receiptHistoryFuture =
        _receiptHistoryInvoiceId == invoice.id ? _receiptHistoryFuture : null;
    final receiptResolutionFuture = _receiptResolutionInvoiceId == invoice.id
        ? _receiptResolutionFuture
        : null;

    return Container(
      color: const Color(0xFFF4F6FA),
      child: Column(
        children: [
          _buildActionBar(invoice),
          if (!_showingPaymentForm) _buildWorkflowBanner(invoice),
          Expanded(
            child: _showingPaymentForm
                ? _buildInlinePaymentForm(invoice)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final double paperWidth = (constraints.maxWidth - 48)
                          .clamp(360.0, 920.0)
                          .toDouble();

                      return FutureBuilder<DocumentAccountingContext>(
                        future: accountingFuture,
                        builder: (context, snapshot) {
                          final accounting =
                              snapshot.data ?? DocumentAccountingContext.empty;
                          final isLoadingAccounting =
                              accountingFuture != null &&
                                  snapshot.connectionState ==
                                      ConnectionState.waiting;

                          return FutureBuilder<List<PurchaseReceiptRecord>>(
                            future: receiptHistoryFuture,
                            builder: (context, receiptSnapshot) {
                              final receipts = receiptSnapshot.data ?? const [];
                              final isLoadingReceipts =
                                  receiptHistoryFuture != null &&
                                      receiptSnapshot.connectionState ==
                                          ConnectionState.waiting;

                              return FutureBuilder<
                                  List<PurchaseReceiptResolutionCase>>(
                                future: receiptResolutionFuture,
                                builder: (context, resolutionSnapshot) {
                                  final resolutionCases =
                                      resolutionSnapshot.data ?? const [];
                                  final isLoadingResolutions =
                                      receiptResolutionFuture != null &&
                                          resolutionSnapshot.connectionState ==
                                              ConnectionState.waiting;

                                  return SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      18,
                                      24,
                                      34,
                                    ),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 1240,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            if (isLoadingAccounting ||
                                                isLoadingReceipts ||
                                                isLoadingResolutions)
                                              const DocumentAccountingLoadingStrip()
                                            else ...[
                                              PurchaseInvoiceEvidenceDropdown(
                                                key: ValueKey(
                                                  'purchase-invoice-evidence-${invoice.id}',
                                                ),
                                                payments: accounting.payments,
                                                receipts: receipts,
                                                resolutionCases:
                                                    resolutionCases,
                                                onPaymentTap:
                                                    _openLinkedPayment,
                                                onReceiptTap:
                                                    _openLinkedReceipt,
                                                onResolutionCaseTap:
                                                    _openResolutionCase,
                                                onResolutionDocumentTap:
                                                    _openResolutionDocument,
                                              ),
                                              if (snapshot.hasError ||
                                                  receiptSnapshot.hasError ||
                                                  resolutionSnapshot.hasError)
                                                Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 14,
                                                    vertical: 10,
                                                  ),
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: Color(0xFFF8F3F3),
                                                    border:
                                                        Border.fromBorderSide(
                                                      BorderSide(
                                                        color:
                                                            Color(0xFFE2C9CA),
                                                      ),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                        Icons
                                                            .warning_amber_rounded,
                                                        size: 18,
                                                        color:
                                                            Color(0xFF874B4E),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      const Expanded(
                                                        child: Text(
                                                          'No se pudo cargar el '
                                                          'registro completo de '
                                                          'pagos, recepciones y '
                                                          'resoluciones.',
                                                          style: TextStyle(
                                                            fontSize: 12.5,
                                                            color: Color(
                                                                0xFF713F42),
                                                          ),
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed: invoice.id ==
                                                                null
                                                            ? null
                                                            : () => setState(
                                                                  () =>
                                                                      _primeAccountingContext(
                                                                    invoice,
                                                                  ),
                                                                ),
                                                        child: const Text(
                                                            'Reintentar'),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                            const SizedBox(height: 24),
                                            DocumentPaperShell(
                                              width: paperWidth,
                                              status: _documentPreviewStatus(
                                                  invoice),
                                              child: _buildInvoiceDocument(
                                                invoice,
                                                paperWidth,
                                              ),
                                            ),
                                            if (!isLoadingAccounting)
                                              DocumentJournalEntriesSection(
                                                entries:
                                                    accounting.journalEntries,
                                                documentLabel:
                                                    _documentKindLabel(invoice),
                                                emptyReference:
                                                    invoice.invoiceNumber,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
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

  DocumentPaperStatus _documentPreviewStatus(PurchaseInvoice invoice) {
    final effectiveBalance = _effectiveBalance(invoice);
    final fulfillment = _fulfillmentFor(invoice);
    final now = DateTime.now();
    final isPaid = invoice.status == PurchaseInvoiceStatus.paid ||
        (invoice.paidAmount > 0 && effectiveBalance <= 1);
    final isOverdue = !isPaid &&
        effectiveBalance > 1 &&
        invoice.dueDate != null &&
        invoice.dueDate!.isBefore(now);

    if (invoice.status == PurchaseInvoiceStatus.cancelled) {
      return const DocumentPaperStatus(
        label: 'ANULADA',
        foreground: Color(0xFF991B1B),
        background: Color(0xFFFFF1F2),
        border: Color(0xFFFECACA),
      );
    }

    if (fulfillment.isClosedWithDifference) {
      return DocumentPaperStatus(
        label: isPaid ? 'PAGADA · CERRADA CON DIF.' : 'CERRADA CON DIF.',
        foreground: const Color(0xFF6B4C12),
        background: const Color(0xFFFFFBEB),
        border: const Color(0xFFE5C574),
      );
    }

    if (fulfillment.isComplete) {
      return DocumentPaperStatus(
        label: isPaid ? 'PAGADA · RECIBIDA' : 'RECIBIDA',
        foreground: isPaid ? const Color(0xFF047857) : const Color(0xFF0F766E),
        background: isPaid ? const Color(0xFFECFDF5) : const Color(0xFFF0FDFA),
        border: isPaid ? const Color(0xFFA7F3D0) : const Color(0xFF99F6E4),
      );
    }

    if (fulfillment.isOpen) {
      return DocumentPaperStatus(
        label: isPaid ? 'PAGADA · RECEPCIÓN PARCIAL' : 'RECEPCIÓN PARCIAL',
        foreground: const Color(0xFF92400E),
        background: const Color(0xFFFFFBEB),
        border: const Color(0xFFFDE68A),
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
      case PurchaseInvoiceStatus.sent:
        return const DocumentPaperStatus(
          label: 'ENVIADA',
          foreground: Color(0xFF1D4ED8),
          background: Color(0xFFEFF6FF),
          border: Color(0xFFBFDBFE),
        );
      case PurchaseInvoiceStatus.confirmed:
        return const DocumentPaperStatus(
          label: 'CONFIRMADA',
          foreground: Color(0xFF6D28D9),
          background: Color(0xFFF5F3FF),
          border: Color(0xFFDDD6FE),
        );
      case PurchaseInvoiceStatus.received:
        return const DocumentPaperStatus(
          label: 'RECIBIDA',
          foreground: Color(0xFF0F766E),
          background: Color(0xFFF0FDFA),
          border: Color(0xFF99F6E4),
        );
      case PurchaseInvoiceStatus.draft:
      case PurchaseInvoiceStatus.paid:
      case PurchaseInvoiceStatus.cancelled:
        return const DocumentPaperStatus(
          label: 'BORRADOR',
          foreground: Color(0xFF475569),
          background: Color(0xFFF8FAFC),
          border: Color(0xFFE2E8F0),
        );
    }
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
                      tooltip: 'Volver al documento',
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
                        _buildPaymentRow('Total documento:',
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
                    final parsedCents = (parsed * 100).round();
                    final balanceCents = (balance * 100).round();
                    if (parsedCents > balanceCents) {
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
                '${_documentKindLabel(invoice)} · ${invoice.invoiceNumber}',
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
                  _showingPaymentForm = false;
                  _accountingContextInvoiceId = null;
                  _accountingContextFuture = null;
                  _receiptHistoryInvoiceId = null;
                  _receiptHistoryFuture = null;
                  _receiptResolutionInvoiceId = null;
                  _receiptResolutionFuture = null;
                  _focusedPurchaseCreditNoteId = null;
                  _focusedPurchaseRefundId = null;
                  _focusedSupplierReturnId = null;
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
                  key: const Key('purchase-preview-edit'),
                  onPressed: () => _openDocumentPage(invoice, edit: true),
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
              _buildPreviewBrand(companyNameSize, scale),
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
                      'Proveedor',
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
                    'Fecha del documento:',
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

  /// The preview mirrors the PDF: the company logo the generator prints, at
  /// the generator's 120×40 box, and the same text fallback when the tenant
  /// has no logo. The preview used to print the fallback unconditionally, so
  /// what the operator saw and what the supplier received disagreed.
  Widget _buildPreviewBrand(double companyNameSize, double scale) {
    final fallback = Text(
      'VIÑABIKE',
      style: TextStyle(
        fontSize: companyNameSize,
        fontWeight: FontWeight.bold,
        color: Colors.blue[800],
      ),
    );
    final logoUrl = context.read<AppearanceService>().companyLogoUrl;
    if (logoUrl == null || logoUrl.isEmpty) return fallback;
    return Image.network(
      logoUrl,
      key: const Key('purchase-preview-logo'),
      width: 120 * scale,
      height: 40 * scale,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      errorBuilder: (context, error, stackTrace) => fallback,
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

  bool _isGeneratingPdf = false;

  Future<void> _downloadInvoicePDF(PurchaseInvoice invoice) async {
    if (_isGeneratingPdf) return;

    setState(() => _isGeneratingPdf = true);

    final appearanceService = context.read<AppearanceService>();
    final inventoryService = context.read<InventoryService>();

    try {
      final bytes = await PurchaseDocumentPdfGenerator.generateBytes(
        invoice,
        appearanceService: appearanceService,
        inventoryService: inventoryService,
      );

      // Platform-specific download
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        // Desktop: Use Save As dialog
        final String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar documento de compra PDF',
          fileName:
              PurchaseDocumentPdfGenerator.fileNameFor(invoice.invoiceNumber),
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
          filename:
              PurchaseDocumentPdfGenerator.fileNameFor(invoice.invoiceNumber),
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

  String _cleanPdfText(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(RegExp(r'[^\x20-\x7E\xA0-\xFF\r\n\t]'), ' ');
  }
}
