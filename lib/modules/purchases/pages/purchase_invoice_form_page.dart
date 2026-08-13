import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/barcode_scanner_service.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/supplier.dart' as shared_supplier;
import '../../../shared/models/supplier_variant_resolution.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/number_generation_service.dart';
import '../../../shared/services/return_navigation.dart';
import '../../../shared/services/remote_scanner_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/workspace_manager.dart';
import '../../../shared/services/invoice_parser_service.dart';
import '../../../shared/services/ocr_file_handoff_service.dart';
import '../../../shared/services/supplier_variant_resolution_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/smart_product_field.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../../../shared/widgets/line_row_wrapper.dart';
import '../../../shared/widgets/ocr_upload_widget.dart';
import '../../inventory/pages/product_form_page.dart';
import '../../bikeshop/widgets/task_form_dialog.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_credit_note.dart';
import '../models/purchase_receipt.dart';
import '../models/purchase_receipt_resolution.dart';
import '../models/purchase_supplier_return.dart';
import '../services/purchase_receiving_service.dart';
import '../services/purchase_credit_note_service.dart';
import '../services/purchase_receipt_resolution_service.dart';
import '../services/purchase_supplier_return_service.dart';
import '../services/purchase_service.dart';
import '../widgets/purchase_receipt_history_panel.dart';
import '../widgets/purchase_receipt_resolution_register.dart';
import 'purchase_receiving_page.dart';
import 'purchase_credit_note_page.dart';
import 'purchase_supplier_return_page.dart';
import '../services/purchase_invoice_ocr_application_policy.dart';

class _OcrPurchaseLineResolution {
  const _OcrPurchaseLineResolution({
    required this.lineNumber,
    required this.item,
    this.product,
    this.supplierPlan,
    this.preparedSupplierSource,
    this.failureReason,
  });

  final int lineNumber;
  final ParsedLineItem item;
  final Product? product;
  final _OcrSupplierSourcePlan? supplierPlan;
  final SupplierInvoiceSourceResolution? preparedSupplierSource;
  final String? failureReason;

  bool get canPrepareOrApply =>
      failureReason == null && (product != null || supplierPlan != null);

  bool get isResolved =>
      failureReason == null &&
      (product != null || preparedSupplierSource != null);

  _OcrPurchaseLineResolution withPreparedSupplierSource(
    SupplierInvoiceSourceResolution prepared,
  ) {
    return _OcrPurchaseLineResolution(
      lineNumber: lineNumber,
      item: item,
      product: product,
      supplierPlan: supplierPlan,
      preparedSupplierSource: prepared,
      failureReason: failureReason,
    );
  }
}

class _OcrSupplierSourcePlan {
  const _OcrSupplierSourcePlan({
    required this.resolution,
    required this.optionEvidence,
    required this.sourceLineKey,
    required this.sourceDocumentDate,
    required this.sourcePurchaseQuantity,
    required this.sourceLineTotalMinor,
    required this.currencyCode,
    required this.productsById,
  });

  final SupplierVariantResolution resolution;
  final SupplierOptionEvidence optionEvidence;
  final String sourceLineKey;
  final DateTime sourceDocumentDate;
  final double sourcePurchaseQuantity;
  final int sourceLineTotalMinor;
  final String currencyCode;
  final Map<String, Product> productsById;
}

@visibleForTesting
bool isPurchaseSupplierResolutionLineLocked(PurchaseInvoiceItem line) =>
    line.hasSupplierResolutionProvenance;

@visibleForTesting
bool purchaseSupplierResolutionLinesShareGroup(
  PurchaseInvoiceItem left,
  PurchaseInvoiceItem right,
) {
  final applicationId = left.resolutionApplicationId;
  if (applicationId != null && applicationId.isNotEmpty) {
    return right.resolutionApplicationId == applicationId;
  }
  final sourceLineKey = left.sourceLineKey;
  return sourceLineKey != null &&
      sourceLineKey.isNotEmpty &&
      right.sourceLineKey == sourceLineKey;
}

@visibleForTesting
bool hasPurchaseSupplierResolutionLines(
  Iterable<PurchaseInvoiceItem> lines,
) =>
    lines.any(isPurchaseSupplierResolutionLineLocked);

@visibleForTesting
bool isPurchaseDraftEmptyForSupplierResolution(
  Iterable<PurchaseInvoiceItem> lines,
) {
  final current = lines.toList(growable: false);
  if (current.isEmpty) return true;
  if (current.length != 1) return false;
  final placeholder = current.single;
  return placeholder.productId.trim().isEmpty &&
      (placeholder.productName?.trim().isEmpty ?? true) &&
      (placeholder.productSku?.trim().isEmpty ?? true) &&
      (placeholder.description?.trim().isEmpty ?? true) &&
      placeholder.unitCost == 0 &&
      placeholder.discount == 0 &&
      !placeholder.hasSupplierResolutionProvenance;
}

@visibleForTesting
String? purchaseSupplierResolutionApplyBlockReason({
  required bool hasAuthoritativeGraph,
  required Iterable<PurchaseInvoiceItem> existingLines,
  required String globalDiscountText,
  required TaxTreatment currentTaxTreatment,
  required TaxTreatment targetTaxTreatment,
}) {
  if (!hasAuthoritativeGraph) return null;
  if (!isPurchaseDraftEmptyForSupplierResolution(existingLines)) {
    return 'La resolución del proveedor sólo puede aplicarse a un borrador '
        'vacío.';
  }
  final normalizedDiscount = globalDiscountText.trim().replaceAll(',', '.');
  final discount =
      normalizedDiscount.isEmpty ? 0.0 : double.tryParse(normalizedDiscount);
  if (discount == null || !discount.isFinite || discount != 0) {
    return 'La resolución del proveedor requiere descuento global en cero.';
  }
  if (currentTaxTreatment != TaxTreatment.noTax ||
      targetTaxTreatment != TaxTreatment.noTax) {
    return 'La resolución del proveedor sólo puede aplicarse sin IVA.';
  }
  return null;
}

@visibleForTesting
String purchaseLineDecimalText(double value) {
  if (!value.isFinite) return '';
  return value == value.truncateToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

/// Expands one database-prepared supplier source without reinterpreting its
/// package or allocation evidence in the UI.
@visibleForTesting
List<PurchaseInvoiceItem> buildPreparedSupplierPurchaseLines({
  required SupplierInvoiceSourceResolution prepared,
  required Map<String, Product> productsById,
  double ivaRate = 0.19,
}) {
  return prepared.components.map((component) {
    final product = productsById[component.productId];
    if (product == null || !product.isActive || product.isService) {
      throw StateError(
        'La resolución del proveedor apunta a un producto no utilizable.',
      );
    }
    if (component.resolvedQuantity <= 0) {
      throw StateError(
        'La resolución del proveedor produjo una cantidad inválida.',
      );
    }

    return PurchaseInvoiceItem(
      productId: product.id,
      productName: product.name,
      productSku: product.sku,
      description: product.description,
      purchaseTreatment: product.purchaseTreatment,
      quantity: component.resolvedQuantity,
      unitCost: component.allocatedLineTotalMinor / component.resolvedQuantity,
      discount: 0,
      ivaRate: ivaRate,
      resolutionApplicationId: prepared.id,
      resolutionRevisionId: prepared.resolutionRevisionId,
      sourceLineKey: prepared.sourceLineKey,
      componentPosition: component.position,
      componentRole: component.componentRole,
      sourcePurchaseQuantity: prepared.sourcePurchaseQuantity,
      catalogUnitsPerPurchase: component.catalogUnitsPerPurchase,
      sourceLineTotalMinor: prepared.sourceLineTotalMinor,
      allocatedLineTotalMinor: component.allocatedLineTotalMinor,
      allocationRatio: component.allocationRatio,
      sourceRowIndex: prepared.sourceRowIndex,
      sourceOrderNumbers: prepared.sourceOrderNumbers,
      supplierListingId: prepared.supplierListingId,
      supplierVariantKey: prepared.supplierVariantKey.value,
      optionEvidenceHash: prepared.optionEvidenceHash,
      sourceTitle: prepared.sourceTitle,
      selectedOption: prepared.selectedOption,
      rawPackCount: prepared.rawPackCount,
      rawUnitToken: prepared.rawUnitToken,
      rawPackEvidenceConflict: prepared.packEvidenceConflict,
      sourceEvidenceSnapshot: prepared.sourceSnapshot,
    );
  }).toList(growable: false);
}

/// Route-level authority used by [GoRoute.onExit] while a purchase operation
/// is between its remote commit and local invoice reconciliation.
///
/// The key is scoped to one router and one route page, so an operation in one
/// workspace cannot block navigation in another workspace or overwrite a
/// stacked invoice page's handler.
class PurchaseInvoiceExitGuard {
  const PurchaseInvoiceExitGuard._();

  static final Map<Object, _PurchaseInvoiceExitRegistration> _handlers =
      <Object, _PurchaseInvoiceExitRegistration>{};

  static void register(
    Object scope,
    Object owner,
    Future<bool> Function() handler,
  ) {
    _handlers[scope] = _PurchaseInvoiceExitRegistration(
      owner: owner,
      handler: handler,
    );
  }

  static void unregister(Object scope, Object owner) {
    final registration = _handlers[scope];
    if (registration == null || !identical(registration.owner, owner)) return;
    _handlers.remove(scope);
  }

  static Future<bool> canExit(Object scope) async {
    final handler = _handlers[scope]?.handler;
    if (handler == null) return true;
    try {
      return await handler();
    } catch (error, stackTrace) {
      debugPrint('Purchase invoice exit guard failed closed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }
}

class _PurchaseInvoiceExitRegistration {
  const _PurchaseInvoiceExitRegistration({
    required this.owner,
    required this.handler,
  });

  final Object owner;
  final Future<bool> Function() handler;
}

class PurchaseInvoiceFormPage extends StatefulWidget {
  final String? invoiceId;
  final bool isPrepayment;
  final String? initialSupplierId;
  final List<Map<String, dynamic>>? initialLineItems;
  final bool readOnly; // View-only mode (no editing, no status changes)

  const PurchaseInvoiceFormPage({
    super.key,
    this.invoiceId,
    this.isPrepayment = false,
    this.initialSupplierId,
    this.initialLineItems,
    this.readOnly = false,
    this.referrer,
    this.exitGuardScope,
  });

  final String? referrer;
  final Object? exitGuardScope;

  @override
  State<PurchaseInvoiceFormPage> createState() =>
      _PurchaseInvoiceFormPageState();
}

class _PurchaseInvoiceFormPageState extends State<PurchaseInvoiceFormPage> {
  static const double _ivaRate = 0.19;
  static const int _productPreviewPageSize = 80;

  // Table column widths (match sales invoice)
  static const double _colIndexWidth = 40.0;
  static const double _colQuantityWidth = 120.0;
  static const double _colPriceWidth = 130.0;
  static const double _colDiscountWidth = 130.0;
  static const double _colTotalWidth = 130.0;
  static const double _colActionsWidth = 48.0;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _invoiceNumberController =
      TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final List<_PurchaseLineEntry> _lineEntries = [];
  final Map<String, String> _supplierSourceOperationIds = <String, String>{};

  bool get _hasSupplierResolutionLines => hasPurchaseSupplierResolutionLines(
        _lineEntries.map((entry) => entry.line),
      );

  late PurchaseService _purchaseService;
  late InventoryService _inventoryService;

  shared_supplier.Supplier? _selectedSupplier;
  PurchaseInvoice? _loadedInvoice;
  DateTime _issueDate = DateTime.now();
  DateTime? _dueDate;
  PurchaseInvoiceStatus _status = PurchaseInvoiceStatus.draft;
  TaxTreatment _taxTreatment = TaxTreatment.noTax;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUpdatingStatus = false;
  bool _isEditing = false; // Edit mode toggle (like sales invoice)
  bool _professionalReceivingEnabled = false;
  bool _showingReceiptWorkspace = false;
  bool _showingOcrWorkspace = false;
  bool _isApplyingOcrResult = false;
  final GlobalKey<OCRUploadWidgetState> _ocrWorkspaceKey =
      GlobalKey<OCRUploadWidgetState>();
  final Object _workspaceCloseGuardOwner = Object();
  WorkspaceManager? _workspaceManager;
  String? _workspaceId;
  FocusNode? _focusBeforeOcr;
  OcrFileHandoffPayload? _ocrInitialFile;
  PurchaseReceiptFulfillment _receiptFulfillment =
      PurchaseReceiptFulfillment.none;
  bool _purchaseCreditNotesEnabled = false;
  int _receiptHistoryRevision = 0;

  /// Payment model: true = Prepayment (pay before receive), false = Standard (receive before pay)
  /// Defaults to true (prepayment) for new invoices
  late bool _isPrepaymentModel;

  List<shared_supplier.Supplier> _supplierCache = const [];
  List<Product> _productCache = const [];

  StreamSubscription? _scanSubscription;
  RemoteScannerService? _remoteScannerService; // Lazy init to avoid blocking
  bool _scannerEnabled = false;

  // Hardware keyboard scanner state (for USB/Bluetooth barcode scanners)
  final StringBuffer _scanBuffer = StringBuffer();
  Timer? _hwScanTimer;
  DateTime? _lastScanKeyTime;
  static const Duration _scanKeyTimeout = Duration(milliseconds: 100);
  static const int _minBarcodeLen = 3;

  // Global invoice-level discount
  String _discountType = 'percentage'; // 'percentage' or 'amount'
  bool _isDiscountBeforeTax = true;
  final TextEditingController _discountValueController =
      TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    final exitGuardScope = widget.exitGuardScope;
    if (exitGuardScope != null) {
      PurchaseInvoiceExitGuard.register(
        exitGuardScope,
        this,
        _confirmCanLeave,
      );
    }
    _dueDate = _issueDate.add(const Duration(days: 30));

    // Initialize payment model:
    // - New invoice: default to prepayment (true) unless widget says otherwise
    // - Existing invoice: will be loaded from database in _initialize()
    _isPrepaymentModel = widget.isPrepayment ||
        widget.invoiceId == null; // Default to prepayment for new

    // Set initial editing state:
    // - New invoice (invoiceId == null) → editing mode
    // - Existing draft → view mode (user clicks "Editar" to edit)
    // - Other statuses → always view mode
    _isEditing = widget.invoiceId == null;

    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());

    // DON'T subscribe to barcode scanner here - causes freeze!
    // Will be set up after initialization completes
  }

  @override
  void didUpdateWidget(covariant PurchaseInvoiceFormPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exitGuardScope == widget.exitGuardScope) return;
    final oldScope = oldWidget.exitGuardScope;
    if (oldScope != null) {
      PurchaseInvoiceExitGuard.unregister(oldScope, this);
    }
    final newScope = widget.exitGuardScope;
    if (newScope != null) {
      PurchaseInvoiceExitGuard.register(newScope, this, _confirmCanLeave);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindWorkspaceCloseGuard();
  }

  void _bindWorkspaceCloseGuard() {
    WorkspaceManager? manager;
    Workspace? workspace;
    try {
      manager = context.read<WorkspaceManager>();
      workspace = context.read<Workspace>();
    } on ProviderNotFoundException {
      _unbindWorkspaceCloseGuard();
      return;
    }
    if (identical(_workspaceManager, manager) && _workspaceId == workspace.id) {
      return;
    }
    _unbindWorkspaceCloseGuard();
    if (manager.registerWorkspaceCloseGuard(
      workspaceId: workspace.id,
      owner: _workspaceCloseGuardOwner,
      guard: _confirmCanLeave,
    )) {
      _workspaceManager = manager;
      _workspaceId = workspace.id;
    }
  }

  void _unbindWorkspaceCloseGuard() {
    final manager = _workspaceManager;
    final workspaceId = _workspaceId;
    _workspaceManager = null;
    _workspaceId = null;
    if (manager == null || workspaceId == null) return;
    manager.unregisterWorkspaceCloseGuard(
      workspaceId: workspaceId,
      owner: _workspaceCloseGuardOwner,
    );
  }

  Future<bool> _confirmCanLeave() async {
    final childBlocksExit =
        _ocrWorkspaceKey.currentState?.blocksOwnerExit ?? false;
    if (!_isApplyingOcrResult && !childBlocksExit) return true;
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Espera a que termine la creación y se vinculen los productos a la factura.',
          ),
        ),
      );
    }
    return false;
  }

  @override
  void dispose() {
    final exitGuardScope = widget.exitGuardScope;
    if (exitGuardScope != null) {
      PurchaseInvoiceExitGuard.unregister(exitGuardScope, this);
    }
    _unbindWorkspaceCloseGuard();
    _invoiceNumberController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    _discountValueController.dispose();
    for (final entry in _lineEntries) {
      entry.dispose();
    }
    _scanSubscription?.cancel();
    HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
    _hwScanTimer?.cancel();
    super.dispose();
  }

  // Can edit fields only when status is draft AND in editing mode
  bool get _canEditFields =>
      _status == PurchaseInvoiceStatus.draft && _isEditing;

  double get _effectiveInvoiceBalance {
    final loadedInvoice = _loadedInvoice;
    if (loadedInvoice != null) {
      final storedBalance = loadedInvoice.balance;
      if (storedBalance.abs() <= 0.01) {
        return 0;
      }
      return math.max(storedBalance, 0);
    }

    if (_total <= 0.01) {
      return 0;
    }

    return _total;
  }

  bool get _hasReusableProductCache =>
      _inventoryService.products.isNotEmpty &&
      (_inventoryService.hasLoaded ||
          _inventoryService.loadedPreviewPageCount > 0);

  Future<void> _receiveProducts() async {
    final invoice = _loadedInvoice;
    final invoiceId = invoice?.id;
    if (invoice == null || invoiceId == null || _isUpdatingStatus) return;

    setState(() => _isUpdatingStatus = true);
    try {
      final receivingService = PurchaseReceivingService();
      final mode = await receivingService.getControlMode();
      if (!mode.acceptsCommands) {
        if (mounted) setState(() => _isUpdatingStatus = false);
        await _updateStatus(PurchaseInvoiceStatus.received);
        return;
      }

      if (!mounted) return;
      final fulfillment = await receivingService.getFulfillment(invoice);
      if (!mounted) return;
      setState(() => _receiptFulfillment = fulfillment);
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
      setState(() => _showingReceiptWorkspace = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir la recepción: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  Future<void> _handleReceiptCompleted(PurchaseReceiptResult result) async {
    final invoiceId = _loadedInvoice?.id;
    if (invoiceId == null) return;

    try {
      final refreshed = await _purchaseService.getPurchaseInvoice(
        invoiceId,
        refresh: true,
      );
      final current = refreshed ?? _loadedInvoice!;
      final fulfillment =
          await PurchaseReceivingService().getFulfillment(current);
      if (!mounted) return;
      setState(() {
        _loadedInvoice = current;
        _status = current.status;
        _receiptFulfillment = fulfillment;
        _showingReceiptWorkspace = false;
        _receiptHistoryRevision++;
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
        await _openFirstPendingResolution();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.receiptNumber} quedó con '
            '$openDifferenceQuantity '
            '${openDifferenceQuantity == 1 ? 'unidad pendiente' : 'unidades pendientes'}. '
            'Quedó disponible en Diferencias y resoluciones dentro de la '
            'factura para cuando tengas respuesta del proveedor.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _showingReceiptWorkspace = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'La recepción ${result.receiptNumber} quedó registrada, pero no '
            'se pudo actualizar la vista. Vuelve a abrir la factura. '
            'Detalle: $error',
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

  Future<void> _refreshAfterReceiptChange() async {
    final invoiceId = _loadedInvoice?.id;
    if (invoiceId == null) return;
    final refreshed = await _purchaseService.getPurchaseInvoice(
      invoiceId,
      refresh: true,
    );
    final current = refreshed ?? _loadedInvoice;
    final fulfillment = current == null
        ? PurchaseReceiptFulfillment.none
        : await PurchaseReceivingService().getFulfillment(current);
    if (!mounted) return;
    setState(() {
      if (refreshed != null) {
        _loadedInvoice = refreshed;
        _status = refreshed.status;
      }
      _receiptFulfillment = fulfillment;
      _receiptHistoryRevision++;
    });
  }

  Future<void> _openReceiptDetail(PurchaseReceiptRecord receipt) async {
    await _openReceiptById(receipt.id);
  }

  Future<void> _openReceiptById(String receiptId) async {
    if (receiptId.isEmpty) return;
    await context.push(
      '/purchases/receipts/${Uri.encodeComponent(receiptId)}',
    );
    if (!mounted) return;
    await _refreshAfterReceiptChange();
  }

  Future<void> _openFirstPendingResolution() async {
    final invoiceId = _loadedInvoice?.id;
    if (invoiceId == null || invoiceId.isEmpty || _isUpdatingStatus) return;

    setState(() => _isUpdatingStatus = true);
    try {
      final cases = await PurchaseReceiptResolutionService()
          .getCasesForInvoice(invoiceId);
      for (final resolutionCase in cases) {
        if (!resolutionCase.isOpen) continue;
        await _openReceiptById(resolutionCase.purchaseReceiptId);
        return;
      }

      await _refreshAfterReceiptChange();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No quedan diferencias pendientes. La factura fue actualizada.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudieron abrir las diferencias: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
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
    final invoice = _loadedInvoice;
    if (invoice == null) return;
    switch (document.kind) {
      case PurchaseReceiptResolutionDocumentKind.creditNote:
      case PurchaseReceiptResolutionDocumentKind.supplierRefund:
        final creditNoteId = allocation.purchaseCreditNoteId;
        if (creditNoteId != null && creditNoteId.isNotEmpty) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => PurchaseCreditNotePage(
                invoice: invoice,
                service: PurchaseCreditNoteService(),
                focusCreditNoteId: creditNoteId,
                focusRefundId: document.kind ==
                        PurchaseReceiptResolutionDocumentKind.supplierRefund
                    ? document.id
                    : null,
              ),
            ),
          );
          if (mounted) await _refreshAfterReceiptChange();
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
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => PurchaseSupplierReturnPage(
                invoice: invoice,
                service: PurchaseSupplierReturnService(),
                focusReturnId: document.id,
              ),
            ),
          );
          if (mounted) await _refreshAfterReceiptChange();
          return;
        }
        break;
      case PurchaseReceiptResolutionDocumentKind.documentedLoss:
      case PurchaseReceiptResolutionDocumentKind.documentedLossReversal:
        break;
    }
    await _openReceiptById(resolutionCase.purchaseReceiptId);
  }

  Future<void> _openSupplierReturn() async {
    final invoice = _loadedInvoice;
    if (invoice?.id == null || !_professionalReceivingEnabled) return;
    try {
      final result =
          await Navigator.of(context).push<PurchaseSupplierReturnResult>(
        MaterialPageRoute(
          builder: (_) => PurchaseSupplierReturnPage(
            invoice: invoice!,
            service: PurchaseSupplierReturnService(),
          ),
        ),
      );
      if (!mounted) return;
      await _refreshAfterReceiptChange();
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Devolución ${result.returnNumber} registrada'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir la devolución: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _openPurchaseCreditNote() async {
    final invoice = _loadedInvoice;
    final invoiceId = invoice?.id;
    if (invoice == null || invoiceId == null || !_purchaseCreditNotesEnabled) {
      return;
    }
    try {
      final result = await Navigator.of(context).push<PurchaseCreditNoteResult>(
        MaterialPageRoute(
          builder: (_) => PurchaseCreditNotePage(
            invoice: invoice,
            service: PurchaseCreditNoteService(),
          ),
        ),
      );
      if (!mounted) return;
      await _refreshAfterReceiptChange();
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.number} registrada'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir la nota de crédito: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _replaceProductCache(Iterable<Product> products) {
    final filteredProducts = products
        .where((product) => product.parentSetId == null)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _productCache = filteredProducts;
  }

  void _upsertProductCache(Product product) {
    if (product.parentSetId != null) return;

    final updatedProducts = List<Product>.from(_productCache);
    final existingIndex =
        updatedProducts.indexWhere((candidate) => candidate.id == product.id);

    if (existingIndex == -1) {
      updatedProducts.add(product);
    } else {
      updatedProducts[existingIndex] = product;
    }

    updatedProducts
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _productCache = updatedProducts;
  }

  Future<void> _hydrateProductsByIds(Iterable<String> productIds) async {
    final missingIds = productIds
        .map((productId) => productId.trim())
        .where(
          (productId) =>
              productId.isNotEmpty &&
              !_productCache.any((candidate) => candidate.id == productId),
        )
        .toSet()
        .toList(growable: false);

    if (missingIds.isEmpty) {
      return;
    }

    final products = await _inventoryService.getProductsByIds(missingIds);
    for (final product in products) {
      _upsertProductCache(product);
    }
  }

  Product? _findCachedProductByCode(
    String code, {
    String? supplierId,
  }) {
    final normalizedCode = code.trim().toLowerCase();
    if (normalizedCode.isEmpty) {
      return null;
    }

    return _productCache.cast<Product?>().firstWhere(
          (product) =>
              product != null &&
              (product.sku.toLowerCase() == normalizedCode ||
                  product.barcode?.toLowerCase() == normalizedCode ||
                  (supplierId != null &&
                      supplierId.isNotEmpty &&
                      product.supplierCode?.trim().toLowerCase() ==
                          normalizedCode &&
                      product.supplierId == supplierId)),
          orElse: () => null,
        );
  }

  Future<Product?> _findProductByExactCode(
    String code, {
    String? supplierId,
  }) async {
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty) {
      return null;
    }

    final cachedProduct = _findCachedProductByCode(
      normalizedCode,
      supplierId: supplierId,
    );
    if (cachedProduct != null) {
      return cachedProduct;
    }

    Product? product = await _inventoryService.getProductBySku(normalizedCode);
    product ??= await _inventoryService.getProductByBarcode(normalizedCode);
    if (product == null && supplierId != null && supplierId.isNotEmpty) {
      product = await _inventoryService.getProductBySupplierCodeForSupplier(
        supplierId: supplierId,
        supplierCode: normalizedCode,
      );
    }

    if (product != null) {
      _upsertProductCache(product);
    }

    return product;
  }

  Future<void> _toggleScanner() async {
    if (!_canEditFields) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No se puede escanear en facturas enviadas'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final barcodeService = context.read<BarcodeScannerService>();

      // Lazy init scanner service
      _remoteScannerService ??= RemoteScannerService();

      if (_scannerEnabled) {
        await _remoteScannerService!.stopListening();
        _scanSubscription?.cancel();
        _scanSubscription = null;
        HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
        _hwScanTimer?.cancel();
        _scanBuffer.clear();
        setState(() => _scannerEnabled = false);
      } else {
        await _remoteScannerService!.startListening();
        HardwareKeyboard.instance.addHandler(_hardwareKeyHandler);
        _scanSubscription?.cancel();
        _scanSubscription = barcodeService.barcodeStream.listen((barcode) {
          if (mounted &&
              _scannerEnabled &&
              _canEditFields &&
              !_showingOcrWorkspace) {
            _handleBarcodeScan(barcode);
          }
        });
        setState(() => _scannerEnabled = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Escáner activado'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error con escáner: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Hardware keyboard handler for USB/Bluetooth barcode scanners.
  /// Returns false so key events still reach focused widgets (text fields).
  bool _hardwareKeyHandler(KeyEvent event) {
    if (!_scannerEnabled ||
        !mounted ||
        !_canEditFields ||
        _showingOcrWorkspace) {
      return false;
    }
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    if (_lastScanKeyTime != null &&
        now.difference(_lastScanKeyTime!) > _scanKeyTimeout) {
      _scanBuffer.clear();
    }
    _lastScanKeyTime = now;
    _hwScanTimer?.cancel();

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _scanBuffer.clear();
      return false;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final barcode = _scanBuffer.toString().trim();
      _scanBuffer.clear();
      if (barcode.length >= _minBarcodeLen) {
        _handleBarcodeScan(barcode);
      }
      return false;
    }

    final char = event.character;
    if (char != null && char.trim().isNotEmpty) {
      _scanBuffer.write(char);
      _hwScanTimer = Timer(_scanKeyTimeout, () {
        final barcode = _scanBuffer.toString().trim();
        _scanBuffer.clear();
        if (barcode.length >= _minBarcodeLen &&
            mounted &&
            _canEditFields &&
            !_showingOcrWorkspace) {
          _handleBarcodeScan(barcode);
        }
      });
    }

    return false;
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    if (!_scannerEnabled ||
        !mounted ||
        !_canEditFields ||
        _showingOcrWorkspace) {
      return;
    }

    final product = await _findProductByExactCode(barcode);
    if (!mounted || _showingOcrWorkspace) return;

    if (product != null) {
      // Check if product is already in the invoice
      final existingLineIndex = _lineEntries.indexWhere(
        (entry) =>
            entry.line.productId == product.id &&
            !entry.isSupplierResolutionLocked,
      );

      if (existingLineIndex != -1) {
        // Increment quantity
        final entry = _lineEntries[existingLineIndex];
        final currentQty = int.tryParse(entry.quantityController.text) ?? 0;
        entry.quantityController.text = (currentQty + 1).toString();
        setState(() {}); // Trigger recalculation
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cantidad aumentada: ${product.name}'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        // Add as new line
        setState(() {
          final newLine = PurchaseInvoiceItem(
            productId: product.id,
            productName: product.name,
            productSku: product.sku,
            purchaseTreatment: product.purchaseTreatment,
            quantity: 1,
            unitCost: product.cost,
            discount: 0,
            description:
                product.description, // Initialize with product description
          );
          final newEntry = _PurchaseLineEntry(line: newLine, product: product);
          newEntry.attachListeners(() {
            setState(() {});
          });
          _lineEntries.add(newEntry);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Producto agregado: ${product.name}'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Producto no encontrado: $barcode'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Open OCR scanner to extract invoice data from image
  Future<void> _openOCRScanner({
    OcrFileHandoffPayload? initialFile,
  }) async {
    if (!_canEditFields) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No se puede escanear en facturas enviadas'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _focusBeforeOcr = FocusManager.instance.primaryFocus;
    _focusBeforeOcr?.unfocus();
    setState(() {
      _ocrInitialFile = initialFile;
      _showingReceiptWorkspace = false;
      _showingOcrWorkspace = true;
    });
  }

  void _closeOcrWorkspace() {
    if (!mounted) return;
    final focusToRestore = _focusBeforeOcr;
    setState(() {
      _showingOcrWorkspace = false;
      _ocrInitialFile = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _showingOcrWorkspace) return;
      if (focusToRestore?.context != null && focusToRestore!.canRequestFocus) {
        focusToRestore.requestFocus();
      }
      if (identical(_focusBeforeOcr, focusToRestore)) {
        _focusBeforeOcr = null;
      }
    });
  }

  void _handleOcrWorkspaceBack() {
    if (_isApplyingOcrResult) return;
    final consumed = _ocrWorkspaceKey.currentState?.handleBack() ?? false;
    if (!consumed) _closeOcrWorkspace();
  }

  Widget _buildOcrWorkspace() {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleOcrWorkspaceBack();
      },
      child: Material(
        color: theme.colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: theme.colorScheme.surface,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: kMinInteractiveDimension,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('purchase-ocr-workspace-back'),
                        onPressed: _isApplyingOcrResult
                            ? null
                            : _handleOcrWorkspaceBack,
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Volver a la factura',
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OCR de factura de compra',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Lee el documento, resuelve sus productos y vuelve al borrador.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            Expanded(
              child: OCRUploadWidget(
                key: _ocrWorkspaceKey,
                documentType: OCRDocumentType.invoice,
                showPreview: true,
                initialFile: _ocrInitialFile,
                supplierId: _selectedSupplier?.id,
                supplierName: _selectedSupplier?.name,
                onComplete: (parsedInvoice) async {
                  if (_isApplyingOcrResult) return;
                  setState(() => _isApplyingOcrResult = true);
                  try {
                    await _loadProducts();
                    final applied = await _applyOCRData(parsedInvoice);
                    if (applied && mounted && _showingOcrWorkspace) {
                      _closeOcrWorkspace();
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _isApplyingOcrResult = false);
                    }
                  }
                },
                onError: (error) {
                  debugPrint('OCR Error: $error');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  shared_supplier.Supplier? _matchOcrSupplier(ParsedInvoice parsedInvoice) {
    if (parsedInvoice.rut == null && parsedInvoice.supplierName == null) {
      return _selectedSupplier;
    }
    final rut = parsedInvoice.rut?.replaceAll(RegExp(r'[.\-]'), '');
    final name = parsedInvoice.supplierName?.trim().toLowerCase();
    return _supplierCache.cast<shared_supplier.Supplier?>().firstWhere(
      (supplier) {
        if (supplier == null) return false;
        if (rut != null && supplier.rut != null) {
          final supplierRut = supplier.rut!.replaceAll(RegExp(r'[.\-]'), '');
          if (supplierRut == rut) return true;
        }
        if (name != null && name.isNotEmpty) {
          final supplierName = supplier.name.trim().toLowerCase();
          return supplierName.contains(name) || name.contains(supplierName);
        }
        return false;
      },
      orElse: () => null,
    );
  }

  Future<List<_OcrPurchaseLineResolution>> _resolveOcrPurchaseLines(
    ParsedInvoice parsedInvoice, {
    String? supplierId,
  }) async {
    await _hydrateProductsByIds(
      parsedInvoice.lineItems
          .where(
            (item) =>
                item.existsInDatabase == true &&
                item.matchedProductId != null &&
                item.matchedProductId!.isNotEmpty,
          )
          .map((item) => item.matchedProductId!),
    );

    final graphProductIds = parsedInvoice.lineItems
        .expand(
          (item) =>
              item.supplierResolution?.edges ??
              const <SupplierVariantResolutionEdge>[],
        )
        .map((edge) => edge.productId)
        .toSet();
    final graphProductsById = <String, Product>{};
    await Future.wait(
      graphProductIds.map((productId) async {
        // Supplier graph edges may legitimately point to a set component.
        // The ordinary picker cache hides those rows, so this authoritative
        // path must read every edge by ID and keep it outside that cache.
        final product = await _inventoryService.getProductById(
          productId,
          forceRefresh: true,
        );
        if (product != null) graphProductsById[productId] = product;
      }),
    );

    final isAliExpress =
        PurchaseInvoiceOcrApplicationPolicy.isAliExpress(parsedInvoice);
    final resolutions = <_OcrPurchaseLineResolution>[];
    for (var index = 0; index < parsedInvoice.lineItems.length; index++) {
      final item = parsedInvoice.lineItems[index];
      final supplierResolution = item.supplierResolution;
      if (supplierResolution?.isResolved == true) {
        final plan = _buildOcrSupplierSourcePlan(
          parsedInvoice: parsedInvoice,
          item: item,
          sourceRowIndex: index,
          supplierId: supplierId,
          resolution: supplierResolution!,
          graphProductsById: graphProductsById,
        );
        resolutions.add(
          _OcrPurchaseLineResolution(
            lineNumber: index + 1,
            item: item,
            supplierPlan: plan,
          ),
        );
        continue;
      }

      if (isAliExpress &&
          SupplierOptionEvidence.requiresExplicitCompositionFor(
            packCount: item.rawPackCount,
            rawUnitToken: item.rawUnitToken,
            packEvidenceConflict: item.rawPackEvidenceConflict,
          )) {
        resolutions.add(
          _OcrPurchaseLineResolution(
            lineNumber: index + 1,
            item: item,
            failureReason: item.rawPackEvidenceConflict
                ? 'la evidencia del paquete es contradictoria'
                : 'el paquete de ${item.rawPackCount} unidades no tiene una '
                    'resolución autorizada',
          ),
        );
        continue;
      }

      Product? matchedProduct;

      if (item.existsInDatabase == true &&
          item.matchedProductId != null &&
          item.matchedProductId!.isNotEmpty) {
        matchedProduct = _productCache.cast<Product?>().firstWhere(
              (product) => product?.id == item.matchedProductId,
              orElse: () => null,
            );
      }

      final sku = item.sku?.trim();
      if (matchedProduct == null && sku != null && sku.isNotEmpty) {
        matchedProduct = await _findProductByExactCode(
          sku,
          supplierId: supplierId,
        );
      }

      resolutions.add(
        _OcrPurchaseLineResolution(
          lineNumber: index + 1,
          item: item,
          product: matchedProduct,
        ),
      );
    }

    // Do not stage only part of a document that is already known to be
    // inapplicable. The form stays unchanged and no prepared graph is consumed.
    if (resolutions.any((resolution) => !resolution.canPrepareOrApply)) {
      return resolutions;
    }

    if (!mounted) {
      throw StateError('El formulario se cerró antes de preparar el OCR.');
    }
    final supplierResolutionService = SupplierVariantResolutionService(
      database: context.read<DatabaseService>(),
    );
    final prepared = <_OcrPurchaseLineResolution>[];
    for (final resolution in resolutions) {
      final plan = resolution.supplierPlan;
      if (plan == null) {
        prepared.add(resolution);
        continue;
      }
      final operationId = _supplierSourceOperationIds.putIfAbsent(
        plan.sourceLineKey,
        () => const Uuid().v4(),
      );
      final source = await supplierResolutionService.prepareInvoiceSource(
        operationId: operationId,
        resolution: plan.resolution,
        sourceLineKey: plan.sourceLineKey,
        sourceRowIndex: resolution.lineNumber - 1,
        sourceDocumentDate: plan.sourceDocumentDate,
        sourcePurchaseQuantity: plan.sourcePurchaseQuantity,
        sourceLineTotalMinor: plan.sourceLineTotalMinor,
        currencyCode: plan.currencyCode,
        sourceOrderNumbers: resolution.item.sourceOrderNumbers,
        sourceTitle: _ocrSupplierSourceTitle(resolution.item),
        selectedOption: resolution.item.variantLabel,
        optionEvidence: plan.optionEvidence,
        sourceSnapshot: <String, dynamic>{
          if (resolution.item.sourcePurchaseUnitPrice != null)
            'source_purchase_unit_price':
                resolution.item.sourcePurchaseUnitPrice,
        },
      );
      prepared.add(resolution.withPreparedSupplierSource(source));
    }
    return prepared;
  }

  _OcrSupplierSourcePlan _buildOcrSupplierSourcePlan({
    required ParsedInvoice parsedInvoice,
    required ParsedLineItem item,
    required int sourceRowIndex,
    required String? supplierId,
    required SupplierVariantResolution resolution,
    required Map<String, Product> graphProductsById,
  }) {
    final normalizedSupplierId = supplierId?.trim() ?? '';
    if (normalizedSupplierId.isEmpty ||
        resolution.supplierId?.toLowerCase() !=
            normalizedSupplierId.toLowerCase()) {
      throw StateError(
        'La resolución del proveedor no pertenece al proveedor de la factura.',
      );
    }
    final sourceDate = parsedInvoice.date;
    final currencyCode = parsedInvoice.currencyCode?.trim().toUpperCase();
    if (sourceDate == null || currencyCode != 'CLP') {
      throw StateError(
        'La resolución requiere fecha y moneda CLP estructuradas en el OCR.',
      );
    }
    final sourceQuantity = item.sourcePurchaseQuantity ?? item.quantity;
    final sourceTotal = _ocrSourceLineTotal(item);
    if (sourceQuantity == null ||
        !sourceQuantity.isFinite ||
        sourceQuantity <= 0 ||
        sourceTotal == null ||
        item.sourceOrderNumbers.isEmpty) {
      throw StateError(
        'La línea resuelta no conserva cantidad, total u órdenes de origen.',
      );
    }

    final rawVariantKey = item.variantKey?.trim();
    if (rawVariantKey == null || rawVariantKey.isEmpty) {
      throw StateError(
        'La línea resuelta no conserva una variante inmutable del proveedor.',
      );
    }
    late final SupplierOptionEvidence optionEvidence;
    try {
      optionEvidence = SupplierOptionEvidence(
        variantKey: rawVariantKey,
        packCount: item.rawPackCount,
        rawUnitToken: item.rawPackCount == null ? null : item.rawUnitToken,
        packEvidenceConflict: item.rawPackEvidenceConflict,
      );
    } on ArgumentError catch (error) {
      throw StateError('La evidencia del paquete es contradictoria: $error');
    } on FormatException catch (error) {
      throw StateError('La variante del proveedor no es inmutable: $error');
    }

    final productsById = <String, Product>{};
    for (final edge in resolution.edges) {
      final product = graphProductsById[edge.productId];
      if (product == null || !product.isActive || product.isService) {
        throw StateError(
          'La línea ${sourceRowIndex + 1} apunta a un producto faltante, '
          'inactivo o de servicio (${edge.productId}).',
        );
      }
      productsById[edge.productId] = product;
    }

    final listingId = resolution.listingId;
    if (listingId == null || listingId.isEmpty) {
      throw StateError('La resolución no conserva el listing del proveedor.');
    }
    final sourceLineKey = SupplierVariantResolutionService.buildSourceLineKey(
      supplierId: normalizedSupplierId,
      sourceDate: sourceDate,
      sourceOrderNumbers: item.sourceOrderNumbers,
      listingId: listingId,
      variantKey: optionEvidence.variantKey,
      // This matches the key used when the OCR review learned the graph. Two
      // commercial rows of one immutable variant must never collapse merely
      // because their display names are equal.
      commercialSplitKey: item.sourcePurchaseUnitPrice == null
          ? null
          : 'source-price:${item.sourcePurchaseUnitPrice}',
    );
    return _OcrSupplierSourcePlan(
      resolution: resolution,
      optionEvidence: optionEvidence,
      sourceLineKey: sourceLineKey,
      sourceDocumentDate: sourceDate,
      sourcePurchaseQuantity: sourceQuantity,
      sourceLineTotalMinor: sourceTotal.round(),
      currencyCode: 'CLP',
      productsById: productsById,
    );
  }

  double? _ocrSourceLineTotal(ParsedLineItem item) {
    final explicit = item.total;
    if (explicit != null && explicit.isFinite && explicit >= 0) {
      return explicit;
    }
    final sourceQuantity = item.sourcePurchaseQuantity ?? item.quantity;
    final unitCost = item.unitPrice;
    if (sourceQuantity == null ||
        !sourceQuantity.isFinite ||
        sourceQuantity <= 0 ||
        unitCost == null ||
        !unitCost.isFinite ||
        unitCost < 0) {
      return null;
    }
    final gross = sourceQuantity * unitCost;
    final discount = item.discount != null && item.discount! > 0
        ? item.discount!
        : item.discountRate != null && item.discountRate! > 0
            ? gross * item.discountRate! / 100
            : 0.0;
    final total = math.max(0.0, gross - discount).toDouble();
    return total.isFinite ? total : null;
  }

  String _ocrSupplierSourceTitle(ParsedLineItem item) {
    final title = item.lineTitle?.trim();
    return title == null || title.isEmpty ? item.description.trim() : title;
  }

  List<_PurchaseLineEntry> _buildOcrPurchaseLineEntries(
    _OcrPurchaseLineResolution resolution,
  ) {
    final preparedSupplierSource = resolution.preparedSupplierSource;
    final supplierPlan = resolution.supplierPlan;
    if (preparedSupplierSource != null && supplierPlan != null) {
      final lines = buildPreparedSupplierPurchaseLines(
        prepared: preparedSupplierSource,
        productsById: supplierPlan.productsById,
        ivaRate: _ivaRate,
      );
      return lines.map((line) {
        final entry = _PurchaseLineEntry(
          line: line,
          product: supplierPlan.productsById[line.productId],
        );
        entry.attachListeners(_recalculateTotals);
        return entry;
      }).toList(growable: false);
    }

    final item = resolution.item;
    final matchedProduct = resolution.product!;
    final finalQty =
        PurchaseInvoiceOcrApplicationPolicy.normalizedQuantity(item.quantity);
    final finalUnitCost = item.unitPrice ?? matchedProduct.cost;

    var finalDiscount = 0.0;
    var finalDiscountType = DiscountType.amount;
    if (item.discount != null && item.discount! > 0) {
      finalDiscount = item.discount!;
    } else if (item.discountRate != null && item.discountRate! > 0) {
      finalDiscountType = DiscountType.percentage;
      finalDiscount = item.discountRate!;
    }

    final entry = _PurchaseLineEntry(
      line: PurchaseInvoiceItem(
        productId: matchedProduct.id,
        productName: matchedProduct.name,
        productSku: matchedProduct.sku,
        purchaseTreatment: matchedProduct.purchaseTreatment,
        quantity: finalQty,
        unitCost: finalUnitCost,
        discount: 0,
        description: matchedProduct.description,
      ),
      product: matchedProduct,
    );

    entry.productNameController.text = matchedProduct.name;
    entry.productSkuController.text = matchedProduct.sku;
    entry.descriptionController.text = matchedProduct.description ?? '';
    if (entry.line.unitCost > 0) {
      entry.unitCostController.text = purchaseLineDecimalText(
        entry.line.unitCost,
      );
    }
    if (finalDiscount > 0) {
      entry.discountType = finalDiscountType;
      entry.discountController.text = finalDiscount.toStringAsFixed(0);
      entry.recalculateDiscount();
    }
    entry.attachListeners(_recalculateTotals);
    return <_PurchaseLineEntry>[entry];
  }

  Future<void> _showOcrApplicationBlocked({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.error_outline,
            color: Theme.of(context).colorScheme.error),
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(child: SelectableText(message)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<bool> _applyOCRData(ParsedInvoice parsedInvoice) async {
    final matchedOcrSupplier = _matchOcrSupplier(parsedInvoice);
    final targetTaxTreatment =
        PurchaseInvoiceOcrApplicationPolicy.taxTreatmentFor(
      invoice: parsedInvoice,
      current: _taxTreatment,
    );
    final graphPreflightFailure = purchaseSupplierResolutionApplyBlockReason(
      hasAuthoritativeGraph: parsedInvoice.lineItems.any(
        (item) => item.supplierResolution?.isResolved == true,
      ),
      existingLines: _lineEntries.map((entry) => entry.line),
      globalDiscountText: _discountValueController.text,
      currentTaxTreatment: _taxTreatment,
      targetTaxTreatment: targetTaxTreatment,
    );
    if (graphPreflightFailure != null) {
      await _showOcrApplicationBlocked(
        title: 'El borrador no admite esta resolución',
        message: '$graphPreflightFailure No se preparó ni aplicó ningún dato. '
            'Usa un borrador nuevo, sin descuento global y sin IVA para que '
            'cada total de origen se contabilice una sola vez.',
      );
      return false;
    }

    late final List<_OcrPurchaseLineResolution> resolutions;
    try {
      resolutions = await _resolveOcrPurchaseLines(
        parsedInvoice,
        supplierId: matchedOcrSupplier?.id,
      );
    } catch (error, stackTrace) {
      debugPrint('OCR product resolution failed: $error\n$stackTrace');
      await _showOcrApplicationBlocked(
        title: 'No se pudo validar el OCR',
        message: 'No se aplicó ningún dato porque no fue posible verificar '
            'los productos en inventario. Reintenta cuando haya conexión.\n\n'
            'Detalle: $error',
      );
      return false;
    }

    if (!mounted) return false;

    final unresolved = resolutions
        .where((resolution) => !resolution.isResolved)
        .toList(growable: false);
    final resolvedLineCount = resolutions.length - unresolved.length;
    if (!PurchaseInvoiceOcrApplicationPolicy.allParsedLinesResolved(
      parsedLineCount: parsedInvoice.lineItems.length,
      resolvedLineCount: resolvedLineCount,
    )) {
      final details = unresolved.map((resolution) {
        final sku = resolution.item.sku?.trim();
        final identifier = sku == null || sku.isEmpty ? 'sin SKU' : 'SKU $sku';
        return '• Línea ${resolution.lineNumber} ($identifier): '
            '${resolution.item.description.trim()}'
            '${resolution.failureReason == null ? '' : ' — ${resolution.failureReason}'}';
      }).join('\n');
      await _showOcrApplicationBlocked(
        title: 'Faltan productos por vincular',
        message: 'No se aplicó ningún dato. ${unresolved.length} de '
            '${parsedInvoice.lineItems.length} líneas no tienen un producto '
            'resuelto:\n\n$details\n\nVuelve al OCR y usa Encontrar parecidos '
            'o crea el producto antes de continuar. El borrador se mantuvo sin '
            'cambios.',
      );
      return false;
    }

    final isAliExpress =
        PurchaseInvoiceOcrApplicationPolicy.isAliExpress(parsedInvoice);
    if (isAliExpress && parsedInvoice.total != null && resolutions.isNotEmpty) {
      final reconciliation = PurchaseInvoiceOcrApplicationPolicy.reconcile(
        invoiceTotal: parsedInvoice.total!,
        appliedLineTotals: resolutions.map(
          (resolution) => resolution.preparedSupplierSource != null
              ? resolution.preparedSupplierSource!.sourceLineTotalMinor
                  .toDouble()
              : PurchaseInvoiceOcrApplicationPolicy.appliedLineTotal(
                  resolution.item,
                  fallbackUnitCost: resolution.product!.cost,
                ),
        ),
      );

      if (!reconciliation.isWithinTolerance) {
        await _showOcrApplicationBlocked(
          title: 'El total de AliExpress no cuadra',
          message: 'No se aplicó ningún dato porque los costos aterrizados '
              'no coinciden con el total OCR.\n\n'
              'Total OCR: '
              '${ChileanUtils.formatCurrency(reconciliation.invoiceTotal)}\n'
              'Suma de ${resolutions.length} líneas aplicables: '
              '${ChileanUtils.formatCurrency(reconciliation.appliedLineTotal)}\n'
              'Diferencia: '
              '${ChileanUtils.formatCurrency(reconciliation.difference)}\n'
              'Tolerancia: '
              '${ChileanUtils.formatCurrency(reconciliation.toleranceClp)} '
              '(máximo 1 CLP por línea por redondeo).\n\n'
              'Revisa cantidades y costos en el OCR antes de continuar. El '
              'borrador se mantuvo sin cambios.',
        );
        return false;
      }
    }

    final newEntries = resolutions
        .expand(_buildOcrPurchaseLineEntries)
        .toList(growable: false);
    final appliedLineCount = newEntries.length;
    setState(() {
      if (parsedInvoice.invoiceNumber?.isNotEmpty == true) {
        _invoiceNumberController.text = parsedInvoice.invoiceNumber!;
      }

      if (parsedInvoice.date != null) {
        _issueDate = parsedInvoice.date!;
        _dueDate = _issueDate.add(const Duration(days: 30));
      }

      if (matchedOcrSupplier != null) {
        _selectedSupplier = matchedOcrSupplier;
      }

      if (parsedInvoice.total != null && parsedInvoice.lineItems.isEmpty) {
        final totalStr = ChileanUtils.formatCurrency(parsedInvoice.total!);
        _notesController.text =
            'Total detectado: $totalStr\n${_notesController.text}';
      }

      if (newEntries.isNotEmpty) {
        if (_lineEntries.length == 1) {
          final firstEntry = _lineEntries.first;
          final firstLine = firstEntry.line;
          if (firstLine.productId.isEmpty &&
              (firstLine.productName == null ||
                  firstLine.productName!.isEmpty)) {
            _lineEntries.clear();
            firstEntry.dispose();
          }
        }
        _lineEntries.addAll(newEntries);
      }

      // AliExpress line costs already contain distributed tax, shipping and
      // discounts. `noTax` prevents the purchase form from adding another 19%.
      _taxTreatment = targetTaxTreatment;
    });

    if (!mounted) return false;
    final extractedFields = <String>[];
    if (parsedInvoice.invoiceNumber != null) extractedFields.add('N° Factura');
    if (parsedInvoice.supplierName != null) extractedFields.add('Proveedor');
    if (parsedInvoice.date != null) extractedFields.add('Fecha');
    if (parsedInvoice.total != null) extractedFields.add('Total');
    if (parsedInvoice.lineItems.isNotEmpty) {
      extractedFields.add('$appliedLineCount productos aplicados');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Datos extraídos: ${extractedFields.join(', ')}'),
        duration: const Duration(seconds: 3),
      ),
    );
    return true;
  }

  Future<void> _initialize() async {
    debugPrint('🔍 PurchaseForm._initialize() START');

    try {
      debugPrint('🔍 Getting PurchaseService from context...');
      _purchaseService = context.read<PurchaseService>();
      debugPrint('✅ Got PurchaseService');

      debugPrint('🔍 Getting InventoryService from context...');
      _inventoryService = context.read<InventoryService>();
      debugPrint('✅ Got InventoryService');
    } catch (e) {
      debugPrint('❌ Error getting services: $e');
      rethrow;
    }

    if (!mounted) {
      debugPrint('⚠️ Widget not mounted after getting services');
      return;
    }

    try {
      // Load suppliers and products in parallel
      debugPrint('🔍 Loading data in parallel (suppliers + products)...');

      if (_hasReusableProductCache) {
        _replaceProductCache(_inventoryService.products);
      }

      final futures = <Future<dynamic>>[
        _purchaseService.getSuppliers(forceRefresh: false),
        _hasReusableProductCache
            ? Future<List<Product>>.value(_inventoryService.products)
            : _inventoryService.loadProductPreviewPage(
                page: 0,
                pageSize: _productPreviewPageSize,
              ),
      ];

      // Also fetch preview number in parallel if this is a new invoice
      if (widget.invoiceId == null) {
        futures.add(_previewPurchaseInvoiceNumber());
      }

      final results = await Future.wait(futures);

      _supplierCache = results[0] as List<shared_supplier.Supplier>;
      debugPrint('✅ Loaded ${_supplierCache.length} suppliers');

      // Helper to process loaded products
      void processProducts(List<Product> products) {
        // Filter out child products (components) as they should not be purchased directly.
        _replaceProductCache(products);
        debugPrint(
            '✅ Loaded ${_productCache.length} products (filtered from ${products.length})');
      }

      processProducts(results[1] as List<Product>);

      if (!mounted) {
        debugPrint('⚠️ Widget not mounted after loading data');
        return;
      }

      // Handle preview number if loaded
      if (widget.invoiceId == null && results.length > 2) {
        _invoiceNumberController.text = results[2] as String;
      }

      if (widget.invoiceId != null) {
        final invoice =
            await _purchaseService.getPurchaseInvoice(widget.invoiceId!);
        if (invoice != null) {
          await _hydrateProductsByIds(
            invoice.items.map((item) => item.productId),
          );
          _loadedInvoice = invoice;
          _applyInvoice(invoice);
          final receivingMode =
              await PurchaseReceivingService().getControlMode();
          _professionalReceivingEnabled = receivingMode.acceptsCommands;
          _receiptFulfillment =
              await PurchaseReceivingService().getFulfillment(invoice);
          _purchaseCreditNotesEnabled =
              await PurchaseCreditNoteService().isEnabled();
        }
      } else {
        // If preview number failed or wasn't loaded in parallel (shouldn't happen with above logic), fallback
        if (_invoiceNumberController.text.isEmpty) {
          _invoiceNumberController.text = await _previewPurchaseInvoiceNumber();
        }

        // Check for pending data from smart purchase list (via service)

        // Check for pending data from smart purchase list (via service)
        final pendingData = _purchaseService.consumePendingSmartPurchaseData();

        // Pre-fill from constructor params OR pending data from service
        final supplierId =
            widget.initialSupplierId ?? pendingData?['supplierId'] as String?;
        final lineItems = widget.initialLineItems ??
            pendingData?['lineItems'] as List<Map<String, dynamic>>?;

        await _hydrateProductsByIds(
          lineItems
                  ?.map((item) => item['product_id']?.toString() ?? '')
                  .toList(growable: false) ??
              const <String>[],
        );

        if (supplierId != null && _supplierCache.isNotEmpty) {
          try {
            _selectedSupplier = _supplierCache.firstWhere(
              (s) => s.id == supplierId,
            );
          } catch (e) {
            // Supplier not found, leave null
          }
        }

        if (lineItems != null && lineItems.isNotEmpty) {
          for (final item in lineItems) {
            final productId = item['product_id'] as String?;
            final productName = item['product_name'] as String?;
            final productSku = item['product_sku'] as String?;
            final suggestedQty = (item['suggested_quantity'] as int?) ?? 1;

            if (productId != null &&
                productId.isNotEmpty &&
                _productCache.isNotEmpty) {
              try {
                final product = _productCache.firstWhere(
                  (p) => p.id == productId,
                );

                // Add line with suggested quantity from database product
                final entry = _PurchaseLineEntry(
                  line: PurchaseInvoiceItem(
                    productId: product.id,
                    productName: product.name,
                    productSku: product.sku,
                    purchaseTreatment: product.purchaseTreatment,
                    quantity: suggestedQty.toDouble(),
                    unitCost: product.cost > 0 ? product.cost : product.price,
                    discount: 0,
                    ivaRate: _ivaRate,
                    description: product
                        .description, // Initialize with product description
                  ),
                  product: product, // Pass full product for image access
                );
                entry.attachListeners(_recalculateTotals);
                _lineEntries.add(entry);
              } catch (e) {
                debugPrint('⚠️ Product $productId not found: $e');
                // Product not found in cache, add as ad-hoc item
                if (productName != null && productName.isNotEmpty) {
                  final entry = _PurchaseLineEntry(
                    line: PurchaseInvoiceItem(
                      productId: '', // Ad-hoc item (empty string)
                      productName: productName,
                      productSku: productSku,
                      purchaseTreatment: parsePurchaseTreatment(
                        item['purchase_treatment'],
                      ),
                      quantity: suggestedQty.toDouble(),
                      unitCost: 0, // User will fill this
                      discount: 0,
                      ivaRate: _ivaRate,
                      description:
                          item['notes'] as String?, // Map notes to description
                    ),
                  );
                  entry.attachListeners(_recalculateTotals);
                  _lineEntries.add(entry);
                }
              }
            } else if (productName != null && productName.isNotEmpty) {
              // No productId or empty, add as ad-hoc item
              final entry = _PurchaseLineEntry(
                line: PurchaseInvoiceItem(
                  productId: '', // Ad-hoc item (empty string)
                  productName: productName,
                  productSku: productSku,
                  purchaseTreatment: parsePurchaseTreatment(
                    item['purchase_treatment'],
                  ),
                  quantity: suggestedQty.toDouble(),
                  unitCost: 0, // User will fill this
                  discount: 0,
                  ivaRate: _ivaRate,
                  description:
                      item['notes'] as String?, // Map notes to description
                ),
              );
              entry.attachListeners(_recalculateTotals);
              _lineEntries.add(entry);
            }
          }

          // Recalculate totals after adding all lines
          if (_lineEntries.isNotEmpty) {
            _recalculateTotals();
          } else {
            // If no lines, add one empty line to start
            _addEmptyLine();
          }
        } else {
          // New invoice - start with one empty line
          _addEmptyLine();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error preparando el formulario: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      _invoiceNumberController.text = await _previewPurchaseInvoiceNumber();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_consumePendingPurchaseInvoiceOcrFile());
          }
        });
      }
    }
  }

  Future<void> _consumePendingPurchaseInvoiceOcrFile() async {
    if (!mounted || widget.invoiceId != null || _isLoading || !_canEditFields) {
      return;
    }

    final handoffService = context.read<OcrFileHandoffService>();
    final payload = handoffService.take(OcrFileHandoffTarget.purchaseInvoice);
    if (payload == null || !mounted) return;

    await _openOCRScanner(initialFile: payload);
  }

  void _applyInvoice(PurchaseInvoice invoice) {
    _invoiceNumberController.text = invoice.invoiceNumber.isNotEmpty
        ? invoice.invoiceNumber
        : _buildSuggestedNumber();
    _referenceController.text = invoice.reference ?? '';
    _notesController.text = invoice.notes ?? '';
    _issueDate = invoice.date;
    _dueDate = invoice.dueDate ?? invoice.date.add(const Duration(days: 30));
    _status = invoice.status;
    _taxTreatment = invoice.taxTreatment;
    _isPrepaymentModel =
        invoice.prepaymentModel; // Load payment model from invoice

    // Load discount
    _discountType = invoice.discountType;
    _isDiscountBeforeTax = invoice.isDiscountBeforeTax;
    _discountValueController.text = invoice.discountValue > 0
        ? invoice.discountValue.toStringAsFixed(0)
        : '0';

    _selectedSupplier = _supplierCache.firstWhere(
      (supplier) => supplier.id == invoice.supplierId,
      orElse: () => shared_supplier.Supplier(
        id: invoice.supplierId ?? '',
        tenantId: invoice.tenantId, // Use invoice's tenant_id
        name: invoice.supplierName ?? 'Proveedor',
        createdAt: invoice.createdAt,
        updatedAt: invoice.updatedAt,
      ),
    );

    for (final item in invoice.items) {
      final product = _productCache.firstWhere(
        (candidate) => candidate.id == item.productId,
        orElse: () => Product(
          id: item.productId,
          name: item.productName ?? 'Producto',
          sku: item.productSku ?? '',
          price: item.unitCost,
          cost: item.unitCost,
          stockQuantity: 0,
          minStockLevel: 0,
          maxStockLevel: 0,
          description: null,
          imageUrl: null,
          imageUrls: const [],
          category: ProductCategory.other,
          specifications: const {},
          tags: const [],
          unit: ProductUnit.unit,
          weight: 0,
          trackStock: item.purchaseTreatment == PurchaseTreatment.inventory,
          isActive: true,
          purchaseTreatment: item.purchaseTreatment,
          createdAt: item.createdAt,
          updatedAt: item.createdAt,
        ),
      );

      final entry = _PurchaseLineEntry(
        // Keep the complete staged supplier provenance when reopening a
        // draft. Reconstructing the line from visible fields silently erased
        // the database receipt that makes a composite expansion auditable.
        line: item.copyWith(
          productName: product.name,
          productSku: product.sku,
        ),
        product: product, // Pass full product for image access
      );
      entry.attachListeners(_recalculateTotals);
      _lineEntries.add(entry);
    }
  }

  Future<void> _loadProducts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      debugPrint('🔄 Refreshing purchase product preview cache...');
      final products = _inventoryService.hasLoaded
          ? _inventoryService.products
          : await _inventoryService.loadProductPreviewPage(
              page: 0,
              pageSize: _productPreviewPageSize,
              reset: true,
            );
      _replaceProductCache(products);
      debugPrint('✅ Ready with ${_productCache.length} products');
    } catch (e) {
      debugPrint('❌ Error reloading products: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _buildSuggestedNumber() {
    // Deprecated: Use NumberGenerationService instead
    // This fallback should rarely be used
    final now = DateTime.now();
    final datePortion =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timePortion = now.millisecondsSinceEpoch.toString().substring(7);
    return 'FC-$datePortion-$timePortion';
  }

  /// Preview what the next invoice number will be (doesn't increment counter)
  /// Used when entering form - actual number assigned only on save
  Future<String> _previewPurchaseInvoiceNumber() async {
    try {
      final numberService = NumberGenerationService();
      return await numberService.previewPurchaseInvoiceNumber();
    } catch (e) {
      debugPrint('Error previewing purchase invoice number: $e');
      return _buildSuggestedNumber(); // Fallback to old method
    }
  }

  /// Generate the actual invoice number (increments counter)
  /// Used only when actually SAVING a new invoice
  Future<String> _generatePurchaseInvoiceNumber() async {
    try {
      final numberService = NumberGenerationService();
      return await numberService.nextPurchaseInvoiceNumber();
    } catch (e) {
      debugPrint('Error generating purchase invoice number: $e');
      return _buildSuggestedNumber(); // Fallback to old method
    }
  }

  double get _subtotalBeforeDiscount => _lineEntries.fold<double>(
      0, (sum, entry) => sum + entry.line.netAmountClamped);

  double get _discountAmount {
    final rawValue =
        double.tryParse(_discountValueController.text.replaceAll(',', '.')) ??
            0;
    if (rawValue <= 0) return 0;

    // Base amount for percentage calculation
    double baseAmount = _subtotalBeforeDiscount;
    // If calculating AFTER tax (and tax is included), base should be Total-ish
    // But strictly speaking, if we just want "10% off the final bill", we apply it to the total.
    // If tax is included (19%), the Net is Subtotal. The Gross is Subtotal * 1.19.
    if (!_isDiscountBeforeTax && _taxTreatment == TaxTreatment.taxIncluded) {
      baseAmount = _subtotalBeforeDiscount * 1.19;
    }

    double calculatedAmount;
    if (_discountType == 'percentage') {
      calculatedAmount = baseAmount * rawValue / 100;
    } else {
      calculatedAmount = rawValue;
    }

    // Clamp to ensure we don't discount more than the available amount
    return calculatedAmount.clamp(0, baseAmount);
  }

  double get _subtotal {
    final value = _isDiscountBeforeTax
        ? _subtotalBeforeDiscount - _discountAmount
        : _subtotalBeforeDiscount;

    if (value <= 0) return 0;
    return value.roundToDouble();
  }

  // Tax calculations for PURCHASES (tax is ADDED, not included)
  // Opposite to sales where tax is included in price
  double get _netAmount {
    return _subtotal; // Net is always the subtotal for purchases
  }

  double get _iva {
    if (_taxTreatment == TaxTreatment.taxIncluded) {
      return (_subtotal * 0.19)
          .roundToDouble(); // Add 19% tax on (possibly discounted) subtotal
    } else {
      return 0; // No tax
    }
  }

  double get _total {
    double t;
    if (_taxTreatment == TaxTreatment.taxIncluded) {
      t = _subtotal + _iva;
    } else {
      t = _subtotal;
    }

    // If discount is AFTER tax, subtract it from the total here
    // Note: If discount is BEFORE tax, it's already handled in _subtotal getter
    if (!_isDiscountBeforeTax) {
      t -= _discountAmount;
    }
    return t.roundToDouble();
  }

  void _recalculateTotals() {
    if (mounted) setState(() {});
  }

  Future<void> _openSupplierSelector() async {
    if (_hasSupplierResolutionLines) return;
    if (_supplierCache.isEmpty) {
      try {
        _supplierCache =
            await _purchaseService.getSuppliers(forceRefresh: true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al cargar proveedores: $e'),
              backgroundColor: Colors.red),
        );
        return;
      }
    }

    if (!mounted) return;

    final selected = await showModalBottomSheet<shared_supplier.Supplier>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _SupplierSelector(
          suppliers: _supplierCache,
          onCreateSupplier: _createQuickSupplier,
        );
      },
    );

    if (selected != null && mounted && !_hasSupplierResolutionLines) {
      setState(() {
        _selectedSupplier = selected;

        // 💡 Smart default: Auto-update tax treatment based on supplier
        // Only update if still in initial state (noTax), don't override user's manual selection
        if (_taxTreatment == TaxTreatment.noTax && _lineEntries.isEmpty) {
          _taxTreatment = selected.defaultTaxTreatment;

          // Show hint to user
          final taxLabel = _taxTreatment == TaxTreatment.taxIncluded
              ? 'IVA Incluido (19%)'
              : 'Sin IVA';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('💡 Tratamiento tributario sugerido: $taxLabel'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    }
  }

  Future<shared_supplier.Supplier?> _createQuickSupplier(String name) async {
    if (name.trim().isEmpty) return null;
    try {
      final supplier = await _purchaseService.createSupplier(name.trim());
      _supplierCache = [..._supplierCache, supplier];
      return supplier;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error al crear proveedor: $e'),
            backgroundColor: Colors.red),
      );
      return null;
    }
  }

  Future<void> _pickDate({required bool isIssueDate}) async {
    if (isIssueDate && _hasSupplierResolutionLines) return;
    final initial = isIssueDate
        ? _issueDate
        : (_dueDate ?? _issueDate.add(const Duration(days: 30)));

    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: isIssueDate ? 'Fecha de emisión' : 'Fecha de vencimiento',
    );
    if (selected == null || (isIssueDate && _hasSupplierResolutionLines)) {
      return;
    }

    setState(() {
      if (isIssueDate) {
        _issueDate = selected;
        if (_dueDate != null && _dueDate!.isBefore(_issueDate)) {
          _dueDate = _issueDate.add(const Duration(days: 30));
        }
      } else {
        _dueDate = selected.isBefore(_issueDate)
            ? _issueDate.add(const Duration(days: 30))
            : selected;
      }
    });
  }

  Future<void> _saveInvoice() async {
    setState(() => _isSaving = true);

    try {
      final saved = await _persistInvoiceChanges();
      if (saved == null || !mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Factura de compra guardada correctamente'),
        ),
      );
      // Navigate back - check if we can pop, otherwise go to list
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/purchases');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<PurchaseInvoice?> _persistInvoiceChanges({
    bool showSuccessFeedback = false,
  }) async {
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('Selecciona o crea un proveedor antes de guardar.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    if (_lineEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Agrega al menos un producto a la factura.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    if (!_formKey.currentState!.validate()) {
      return null;
    }

    final items = _lineEntries
        .where((entry) => entry.line.quantity > 0)
        .map((entry) => entry.line)
        .toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No hay líneas válidas para guardar.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }

    final tenantService = context.read<TenantService>();
    final tenantId = await tenantService.getTenantId();

    if (tenantId == null) {
      throw Exception('No tenant found. Please log in again.');
    }

    // For NEW invoices (no ID yet), only generate a number if the field is empty
    // This preserves OCR-detected or manually-entered invoice numbers
    String invoiceNumber = _invoiceNumberController.text.trim();
    if (_loadedInvoice?.id == null &&
        widget.invoiceId == null &&
        invoiceNumber.isEmpty) {
      invoiceNumber = await _generatePurchaseInvoiceNumber();
      _invoiceNumberController.text = invoiceNumber;
    }

    // Check for duplicate invoice number
    final existingInvoice = await _purchaseService.checkInvoiceNumberExists(
      invoiceNumber,
      excludeId: _loadedInvoice?.id ?? widget.invoiceId,
    );

    if (existingInvoice != null && mounted) {
      // Show warning dialog
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(Icons.warning_amber_rounded,
              color: VinabikeThemeRoles.of(context).warning.accent, size: 48),
          title: const Text('Número de factura duplicado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ya existe una factura con el número "$invoiceNumber".',
                style: const TextStyle(fontSize: 15),
              ),
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
                    Text(
                      'Factura existente:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                        'Proveedor: ${existingInvoice.supplierName ?? "Sin proveedor"}'),
                    Text(
                        'Fecha: ${existingInvoice.date.day}/${existingInvoice.date.month}/${existingInvoice.date.year}'),
                    Text(
                        'Total: \$${existingInvoice.total.toStringAsFixed(0)}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '¿Deseas continuar de todos modos?',
                style: TextStyle(fontWeight: FontWeight.w500),
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
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Guardar de todos modos'),
            ),
          ],
        ),
      );

      if (shouldContinue != true) {
        return null; // User cancelled, don't save
      }
    }

    final invoice = PurchaseInvoice(
      id: _loadedInvoice?.id,
      tenantId: tenantId,
      invoiceNumber: invoiceNumber,
      supplierId: _selectedSupplier!.id,
      supplierName: _selectedSupplier!.name,
      supplierRut: _selectedSupplier!.rut,
      date: _issueDate,
      dueDate: _dueDate,
      reference: _referenceController.text.trim().isEmpty
          ? null
          : _referenceController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      status: _status,
      subtotal: _subtotal,
      ivaAmount: _iva,
      total: _total,
      taxTreatment: _taxTreatment,
      netAmount: _netAmount,
      discountType: _discountType,
      discountValue:
          double.tryParse(_discountValueController.text.replaceAll(',', '.')) ??
              0,
      discountAmount: _discountAmount,
      isDiscountBeforeTax: _isDiscountBeforeTax,
      items: items,
      // Use the form's payment model state
      prepaymentModel: _isPrepaymentModel,
    );

    debugPrint('🔍 Save: prepaymentModel = ${invoice.prepaymentModel}');

    try {
      final saved = await _purchaseService.savePurchaseInvoice(invoice);

      if (!mounted) return saved;

      setState(() {
        _loadedInvoice = saved;
        _status = saved.status;
      });

      if (showSuccessFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Factura de compra guardada correctamente'),
          ),
        );
      }

      return saved;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la factura: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return null;
    }
  }

  Future<bool> _persistDraftChangesBeforeStatusTransition() async {
    // Persist pending edits in draft mode so date/line changes are not lost
    // when the user goes directly from editing to a workflow action.
    final saved = await _persistInvoiceChanges(showSuccessFeedback: false);
    return saved != null;
  }

  Future<void> _updateStatus(PurchaseInvoiceStatus newStatus) async {
    if (widget.invoiceId == null) return;

    setState(() => _isUpdatingStatus = true);

    try {
      if (_status == PurchaseInvoiceStatus.draft && _isEditing) {
        final didPersist = await _persistDraftChangesBeforeStatusTransition();
        if (!didPersist || !mounted) {
          return;
        }
      }

      // Update status via service
      final updated = await _purchaseService.updateInvoiceStatus(
        widget.invoiceId!,
        newStatus,
      );

      if (!mounted) return;

      if (updated != null) {
        setState(() {
          _status = updated.status;
          _loadedInvoice = updated;
        });
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar estado: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  Future<void> _deleteInvoice() async {
    if (widget.invoiceId == null) return;

    if (_status != PurchaseInvoiceStatus.draft) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.account_tree_outlined),
          title: const Text('La factura no se puede eliminar'),
          content: const SizedBox(
            width: 560,
            child: Text(
              'Los documentos contabilizados no se borran. Anula primero '
              'reembolsos, notas de crédito, pérdidas documentadas o entregas '
              'posteriores, recepciones y pagos. Cada acción publicará su '
              'reversa y avisará sus consecuencias. Solo el borrador final, '
              'sin documentos dependientes, puede eliminarse.',
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

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete_forever,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            const Text('Eliminar factura'),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar la factura '
          '${_invoiceNumberController.text}?\n\n'
          'Esta acción no se puede deshacer.\n\n'
          'Nota: Solo se pueden eliminar facturas en estado Borrador.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sí, eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isUpdatingStatus = true);

    try {
      await _purchaseService.deletePurchaseInvoice(widget.invoiceId!);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Factura eliminada correctamente'),
        ),
      );

      // Return to list page
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  /// Navigate to payment form (similar to sales invoice)
  Future<void> _openPaymentForm() async {
    final invoiceId = widget.invoiceId;
    if (invoiceId == null) {
      return;
    }

    final didRegisterPayment = await context.push<bool>(
          '/purchases/invoices/$invoiceId/payment',
        ) ??
        false;

    if (didRegisterPayment && mounted) {
      await _refreshInvoiceById(invoiceId);
    }
  }

  /// Undo last payment (similar to sales invoice)
  Future<void> _undoLastPayment() async {
    final invoiceId = widget.invoiceId;
    if (invoiceId == null) {
      return;
    }

    // Get all payments for this invoice
    final payments = await _purchaseService.getPaymentsForInvoice(invoiceId);
    if (!mounted) {
      return;
    }
    if (payments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay pagos para deshacer'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Get the last payment (most recent)
    payments.sort((a, b) => b.date.compareTo(a.date));
    final lastPayment = payments.first;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deshacer pago'),
        content: Text(
          'Se eliminará el pago de ${ChileanUtils.formatCurrency(lastPayment.amount)} '
          'y su asiento contable asociado.\n\n'
          'El estado de la factura se revertirá automáticamente. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Eliminar pago'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _purchaseService.deletePayment(lastPayment.id!);
      if (!mounted) return;
      await _refreshInvoiceById(invoiceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pago eliminado correctamente'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar el pago: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Refresh invoice after payment changes
  Future<void> _refreshInvoiceById(String invoiceId) async {
    try {
      final invoices =
          await _purchaseService.getPurchaseInvoices(forceRefresh: true);
      final updated = invoices.firstWhere((inv) => inv.id == invoiceId);

      if (mounted) {
        setState(() {
          _status = updated.status;
          _loadedInvoice = updated;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing invoice: $e');
    }
  }

  Future<bool> _requestManualSupplierResolutionEdit(
    _PurchaseLineEntry selectedEntry,
  ) async {
    if (!selectedEntry.isSupplierResolutionLocked) return true;
    if (!_canEditFields) return false;

    final groupEntries = _lineEntries
        .where(
          (entry) => purchaseSupplierResolutionLinesShareGroup(
            selectedEntry.line,
            entry.line,
          ),
        )
        .toList(growable: false);
    if (groupEntries.isEmpty) return false;

    final isComposite = groupEntries.length > 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isComposite
              ? 'Editar esta descomposición'
              : 'Editar esta conversión de unidades',
        ),
        content: Text(
          isComposite
              ? 'Estas ${groupEntries.length} líneas provienen de una sola '
                  'línea del proveedor y ahora se validan juntas. Para cambiar '
                  'producto, cantidad, tarifa o descuento se convertirán '
                  'juntas en líneas manuales. Se conservarán los valores '
                  'actuales, pero dejarán de estar protegidas por la '
                  'descomposición confirmada.'
              : 'Esta línea convierte automáticamente la unidad comprada en '
                  'unidades de inventario. Para cambiar producto, cantidad, '
                  'tarifa o descuento se convertirá en una línea manual. Se '
                  'conservarán los valores actuales, pero dejará de estar '
                  'protegida por la conversión confirmada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Mantener protegida'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Editar manualmente'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    setState(() {
      for (final entry in groupEntries) {
        entry.line = entry.line.withoutSupplierResolutionProvenance();
        entry.invalidateSmartProductFieldCache();
      }
    });
    _recalculateTotals();
    return true;
  }

  void _removeLine(_PurchaseLineEntry entry) {
    if (entry.isSupplierResolutionLocked) return;
    setState(() {
      _lineEntries.remove(entry);
      entry.dispose();

      // Prevent empty state: If list becomes empty, auto-add a new line
      if (_lineEntries.isEmpty) {
        _addEmptyLine(shouldAutoFocus: true);
      }
    });
    _recalculateTotals();
  }

  void _moveLineUp(_PurchaseLineEntry entry) {
    final index = _lineEntries.indexOf(entry);
    if (index <= 0 ||
        entry.isSupplierResolutionLocked ||
        _lineEntries[index - 1].isSupplierResolutionLocked) {
      return;
    }
    setState(() {
      _lineEntries.removeAt(index);
      _lineEntries.insert(index - 1, entry);
    });
  }

  void _moveLineDown(_PurchaseLineEntry entry) {
    final index = _lineEntries.indexOf(entry);
    if (index < 0 ||
        index >= _lineEntries.length - 1 ||
        entry.isSupplierResolutionLocked ||
        _lineEntries[index + 1].isSupplierResolutionLocked) {
      return;
    }
    setState(() {
      _lineEntries.removeAt(index);
      _lineEntries.insert(index + 1, entry);
    });
  }

  void _addEmptyLine({bool shouldAutoFocus = false}) {
    if (!_canEditFields) return;

    final entry = _PurchaseLineEntry(
      line: PurchaseInvoiceItem(
        productId: '',
        productName: '',
        productSku: null,
        quantity: 1,
        unitCost: 0,
        discount: 0,
        ivaRate: _ivaRate,
      ),
      shouldAutoFocus: shouldAutoFocus,
    );
    entry.attachListeners(_recalculateTotals);

    setState(() {
      _lineEntries.add(entry);
    });
  }

  void _autoAddEmptyLineIfNeeded() {
    // Check if the last line has a product selected
    if (_lineEntries.isEmpty) return;

    final lastEntry = _lineEntries.last;
    if (lastEntry.line.productName?.isNotEmpty ?? false) {
      // Last line is filled, add a new empty line with auto-focus
      _addEmptyLine(shouldAutoFocus: true);
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    debugPrint(
        '🎨 PurchaseInvoiceFormPage.build() called, _isLoading = $_isLoading');
    final invoiceForm = Form(
      key: _formKey,
      child: Column(
        children: [
          _buildHeader(Theme.of(context)),
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : _buildForm(),
          ),
        ],
      ),
    );
    return MainLayout(
      child: _showingReceiptWorkspace && _loadedInvoice != null
          ? PurchaseReceivingWorkspace(
              key: ValueKey('receipt-${_loadedInvoice!.id}'),
              invoice: _loadedInvoice!,
              onCancel: () => setState(
                () => _showingReceiptWorkspace = false,
              ),
              onCompleted: _handleReceiptCompleted,
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Offstage(
                  offstage: _showingOcrWorkspace,
                  child: TickerMode(
                    enabled: !_showingOcrWorkspace,
                    child: invoiceForm,
                  ),
                ),
                if (_showingOcrWorkspace)
                  Positioned.fill(child: _buildOcrWorkspace()),
              ],
            ),
    );
  }

  /// Closes the form and returns to whatever opened it.
  ///
  /// The live history entry restores the host with its filters, selection and
  /// scroll intact. The referrer hint only reconstructs a route, so it serves
  /// deep links that have no history to return to.
  void _returnToOrigin() {
    if (ReturnNavigation.canReturn(context)) {
      ReturnNavigation.close(context, fallbackRoute: '/purchases');
      return;
    }
    if (widget.referrer == 'movements') {
      context.go('/inventory/movements');
      return;
    }
    context.go('/purchases');
  }

  Widget _buildHeader(ThemeData theme) {
    final title = widget.invoiceId == null
        ? 'Nueva factura de compra'
        : 'Factura ${_invoiceNumberController.text}';

    // Helper to build the action buttons (Scanner, OCR, Save)
    List<Widget> buildEditActions() {
      if (widget.readOnly || !_canEditFields) return [];
      return [
        // OCR Scanner Button
        IconButton(
          key: const Key('purchase-invoice-open-ocr'),
          onPressed: _openOCRScanner,
          icon: const Icon(Icons.document_scanner_outlined),
          tooltip: 'Escanear Factura (OCR)',
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(width: 8),
        // Barcode Scanner Button
        IconButton(
          onPressed: _toggleScanner,
          icon: Icon(
            _scannerEnabled
                ? Icons.qr_code_scanner
                : Icons.qr_code_scanner_outlined,
            color: _scannerEnabled ? theme.colorScheme.primary : null,
          ),
          tooltip: _scannerEnabled ? 'Desactivar Escáner' : 'Activar Escáner',
          style: IconButton.styleFrom(
            backgroundColor: _scannerEnabled
                ? theme.colorScheme.primary.withValues(alpha: 0.1)
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 0, // Don't force expand in Row, but allow in Column if needed
          child: AppButton(
            text: 'Guardar',
            icon: Icons.save,
            onPressed: _isSaving ? null : _saveInvoice,
            isLoading: _isSaving,
          ),
        ),
      ];
    }

    // Helper to build status/workflow actions
    List<Widget> buildWorkflowActions() {
      final actionButtons = <Widget>[];

      if (!widget.readOnly && widget.invoiceId != null) {
        // Use form's payment model state
        final isPrepayment = _isPrepaymentModel;
        final physicalComplete = _receiptFulfillment.isClosed;
        final hasUnresolvedDifferences =
            _receiptFulfillment.unresolvedDifferenceQuantity > 0;

        void addReceiptAction() {
          actionButtons.add(
            FilledButton.icon(
              onPressed: _isUpdatingStatus
                  ? null
                  : hasUnresolvedDifferences
                      ? _openFirstPendingResolution
                      : _receiveProducts,
              icon: _isUpdatingStatus
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      hasUnresolvedDifferences
                          ? Icons.rule_folder_outlined
                          : Icons.inventory_2_outlined,
                    ),
              label: Text(
                hasUnresolvedDifferences
                    ? 'Resolver diferencias'
                    : 'Registrar recepción',
              ),
            ),
          );
        }

        actionButtons.add(
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => TaskFormDialog(
                  prefillPurchaseInvoiceId: _loadedInvoice!.id,
                  prefillPurchaseInvoiceNumber: _loadedInvoice!.invoiceNumber,
                  prefillSupplierId: _selectedSupplier?.id,
                  prefillSupplierName: _selectedSupplier?.name,
                ),
              );
            },
            icon: Icon(Icons.add_task,
                color: Theme.of(context).colorScheme.primary),
            tooltip: 'Crear Tarea',
          ),
        );
        actionButtons.add(const SizedBox(width: 8));
        actionButtons
            .add(Container(height: 24, width: 1, color: Colors.grey[300]));
        actionButtons.add(const SizedBox(width: 8));

        if (_professionalReceivingEnabled &&
            _status != PurchaseInvoiceStatus.draft &&
            _status != PurchaseInvoiceStatus.sent &&
            _status != PurchaseInvoiceStatus.cancelled) {
          actionButtons.add(
            OutlinedButton.icon(
              onPressed: _openSupplierReturn,
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Devolver al proveedor'),
            ),
          );
          actionButtons.add(const SizedBox(width: 8));
        }

        if (_purchaseCreditNotesEnabled &&
            _status != PurchaseInvoiceStatus.draft &&
            _status != PurchaseInvoiceStatus.sent &&
            _status != PurchaseInvoiceStatus.cancelled) {
          actionButtons.add(
            OutlinedButton.icon(
              onPressed: _openPurchaseCreditNote,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Nota de crédito'),
            ),
          );
          actionButtons.add(const SizedBox(width: 8));
        }

        if (_status == PurchaseInvoiceStatus.draft) {
          // Draft: Can edit (if not editing), send to supplier, or delete

          // Show "Editar" button when viewing draft (not editing)
          if (!_isEditing) {
            actionButtons.add(
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _isEditing = true;
                  });
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar'),
              ),
            );
            actionButtons.add(const SizedBox(width: 8));
          }

          actionButtons.add(
            OutlinedButton.icon(
              onPressed: _deleteInvoice,
              icon: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              label: Text('Eliminar',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          );
          actionButtons.add(const SizedBox(width: 8));
          actionButtons.add(
            FilledButton.icon(
              onPressed: _isUpdatingStatus
                  ? null
                  : () => _updateStatus(PurchaseInvoiceStatus.sent),
              icon: _isUpdatingStatus
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text('Enviar'),
            ),
          );
        } else if (_status == PurchaseInvoiceStatus.sent) {
          // Sent: Can revert to draft or confirm
          actionButtons.add(
            OutlinedButton.icon(
              onPressed: _isUpdatingStatus
                  ? null
                  : () => _updateStatus(PurchaseInvoiceStatus.draft),
              icon: const Icon(Icons.undo_outlined),
              label: const Text('Volver a borrador'),
            ),
          );
          actionButtons.add(const SizedBox(width: 8));
          actionButtons.add(
            FilledButton.icon(
              onPressed: _isUpdatingStatus
                  ? null
                  : () => _updateStatus(PurchaseInvoiceStatus.confirmed),
              icon: _isUpdatingStatus
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Confirmar'),
            ),
          );
        } else if (_status == PurchaseInvoiceStatus.confirmed) {
          // Confirmed: Next step depends on prepayment model
          actionButtons.add(
            OutlinedButton.icon(
              onPressed: _isUpdatingStatus
                  ? null
                  : () => _updateStatus(PurchaseInvoiceStatus.sent),
              icon: const Icon(Icons.undo_outlined),
              label: const Text('Volver a enviado'),
            ),
          );
          actionButtons.add(const SizedBox(width: 8));

          if (hasUnresolvedDifferences) {
            addReceiptAction();
          } else if (physicalComplete) {
            if (_effectiveInvoiceBalance > 0) {
              actionButtons.add(
                FilledButton.icon(
                  onPressed: _openPaymentForm,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Registrar pago'),
                ),
              );
            }
          } else if (isPrepayment && _effectiveInvoiceBalance > 0) {
            // Prepayment: Pay first, then receive
            actionButtons.add(
              FilledButton.icon(
                onPressed: _openPaymentForm,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Registrar pago'),
              ),
            );
          } else {
            addReceiptAction();
          }
        } else if (_status == PurchaseInvoiceStatus.received) {
          // Received workflow
          final effectiveBalance = _effectiveInvoiceBalance;
          final isPrepayment = _isPrepaymentModel;

          if (isPrepayment && effectiveBalance <= 0) {
            actionButtons.add(
              OutlinedButton.icon(
                onPressed: _isUpdatingStatus
                    ? null
                    : () => _updateStatus(PurchaseInvoiceStatus.paid),
                icon: const Icon(Icons.undo_outlined),
                label: const Text('Volver a pagada'),
              ),
            );
          } else {
            actionButtons.add(
              OutlinedButton.icon(
                onPressed: _isUpdatingStatus
                    ? null
                    : () => _updateStatus(PurchaseInvoiceStatus.confirmed),
                icon: const Icon(Icons.undo_outlined),
                label: const Text('Volver a confirmada'),
              ),
            );
            if (effectiveBalance > 0) {
              actionButtons.add(const SizedBox(width: 8));
              actionButtons.add(
                FilledButton.icon(
                  onPressed: _openPaymentForm,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Registrar pago'),
                ),
              );
            }
          }
          if (hasUnresolvedDifferences) {
            actionButtons.add(const SizedBox(width: 8));
            addReceiptAction();
          }
        } else if (_status == PurchaseInvoiceStatus.paid) {
          // Paid: Can undo payment or mark as received (prepayment only)
          final isPrepayment = _isPrepaymentModel;

          actionButtons.add(
            OutlinedButton.icon(
              onPressed: _undoLastPayment,
              icon: Icon(Icons.undo_outlined,
                  color: Theme.of(context).colorScheme.error),
              label: Text('Deshacer pago',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          );

          if (hasUnresolvedDifferences) {
            actionButtons.add(const SizedBox(width: 8));
            addReceiptAction();
          } else if (isPrepayment && !physicalComplete) {
            actionButtons.add(const SizedBox(width: 8));
            addReceiptAction();
          }
        }
      }

      // Add status chip and total badge if not new
      final widgets = <Widget>[];
      if (widget.invoiceId != null) {
        widgets.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.payments_outlined,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  ChileanUtils.formatCurrency(_total),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
        widgets.add(_buildStatusChip(theme));
      }
      widgets.addAll(actionButtons);
      return widgets;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        if (isMobile) {
          // Mobile Layout: Stacked
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _returnToOrigin,
                      icon: const Icon(Icons.arrow_back),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 20, // Slightly smaller on mobile
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 36), // Align with title
                  child: Text(
                    _isPrepaymentModel
                        ? 'Prepago: pagar antes de recibir'
                        : 'Estándar: recibir antes de pagar',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Actions in a horizontal scroll if needed, or wrapped
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...buildEditActions(),
                      if (buildEditActions().isNotEmpty &&
                          buildWorkflowActions().isNotEmpty)
                        const SizedBox(width: 12),
                      ...buildWorkflowActions().map((w) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: w,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          // Desktop/Tablet Layout: Row
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: _returnToOrigin,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Volver',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isPrepaymentModel
                            ? 'Prepago: pagar antes de recibir mercancía'
                            : 'Flujo estándar: recibir y luego pagar',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ...buildEditActions(),
                const SizedBox(width: 16),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: buildWorkflowActions(),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    final isCancelled = _status == PurchaseInvoiceStatus.cancelled;
    final background = isCancelled
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = isCancelled
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;
    final label = _receiptFulfillment.isClosedWithDifference
        ? _status == PurchaseInvoiceStatus.paid
            ? 'PAGADA · CERRADA CON DIFERENCIA'
            : 'CERRADA CON DIFERENCIA'
        : _receiptFulfillment.isComplete
            ? _status == PurchaseInvoiceStatus.paid
                ? 'PAGADA · RECIBIDA'
                : 'RECIBIDA'
            : _receiptFulfillment.isOpen
                ? _status == PurchaseInvoiceStatus.paid
                    ? 'PAGADA · RECEPCIÓN PARCIAL'
                    : 'RECEPCIÓN PARCIAL'
                : _status.displayName.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Build payment model toggle (Prepayment vs Standard)
  Widget _buildPaymentModelToggle(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Modelo de pago',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Prepago'),
                icon: Icon(Icons.payment),
              ),
              ButtonSegment(
                value: false,
                label: Text('Estándar'),
                icon: Icon(Icons.local_shipping),
              ),
            ],
            selected: {_isPrepaymentModel},
            onSelectionChanged: (selection) {
              setState(() {
                _isPrepaymentModel = selection.first;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            _isPrepaymentModel
                ? 'Pagar primero, recibir después (importaciones, transferencias)'
                : 'Recibir primero, pagar después (proveedores locales)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1180;
        if (isWide) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Payment model toggle (only for new invoices or draft)
                        if (_canEditFields) _buildPaymentModelToggle(theme),
                        if (_canEditFields) const SizedBox(height: 16),
                        _buildSectionCard(
                          theme,
                          icon: Icons.store_outlined,
                          title: 'Proveedor',
                          children: [_buildSupplierSection(theme)],
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          theme,
                          icon: Icons.shopping_basket_outlined,
                          title: 'Productos y servicios',
                          children: [_buildLineItemsSection(theme)],
                        ),
                        if (_professionalReceivingEnabled &&
                            widget.invoiceId != null) ...[
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            theme,
                            icon: Icons.inventory_2_outlined,
                            title: 'Recepciones y diferencias',
                            children: [
                              PurchaseReceiptHistoryPanel(
                                key: ValueKey(_receiptHistoryRevision),
                                invoiceId: widget.invoiceId!,
                                onChanged: _refreshAfterReceiptChange,
                                onReceiptTap: _openReceiptDetail,
                                onResolutionCaseTap: _openResolutionCase,
                                onResolutionDocumentTap:
                                    _openResolutionDocument,
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          theme,
                          icon: Icons.notes_outlined,
                          title: 'Referencia',
                          children: [_buildReferenceSection(theme)],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildSectionCard(
                          theme,
                          icon: Icons.calendar_today_outlined,
                          title: 'Fechas y estado',
                          children: [_buildInvoiceMetaSection(theme)],
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryCard(theme),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          // Narrow layout: stack vertically
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Payment model toggle (only for new invoices or draft)
                if (_canEditFields) _buildPaymentModelToggle(theme),
                if (_canEditFields) const SizedBox(height: 16),
                _buildSectionCard(
                  theme,
                  icon: Icons.store_outlined,
                  title: 'Proveedor',
                  children: [_buildSupplierSection(theme)],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  theme,
                  icon: Icons.calendar_today_outlined,
                  title: 'Fechas y estado',
                  children: [_buildInvoiceMetaSection(theme)],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  theme,
                  icon: Icons.shopping_basket_outlined,
                  title: 'Productos y servicios',
                  children: [_buildLineItemsSection(theme)],
                ),
                if (_professionalReceivingEnabled &&
                    widget.invoiceId != null) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    theme,
                    icon: Icons.inventory_2_outlined,
                    title: 'Recepciones y diferencias',
                    children: [
                      PurchaseReceiptHistoryPanel(
                        key: ValueKey(_receiptHistoryRevision),
                        invoiceId: widget.invoiceId!,
                        onChanged: _refreshAfterReceiptChange,
                        onReceiptTap: _openReceiptDetail,
                        onResolutionCaseTap: _openResolutionCase,
                        onResolutionDocumentTap: _openResolutionDocument,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                _buildSectionCard(
                  theme,
                  icon: Icons.notes_outlined,
                  title: 'Referencia',
                  children: [_buildReferenceSection(theme)],
                ),
                const SizedBox(height: 16),
                _buildSummaryCard(theme),
                const SizedBox(height: 32),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildSectionCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(icon, color: theme.colorScheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierSection(ThemeData theme) {
    final canEditSupplier = _canEditFields && !_hasSupplierResolutionLines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _invoiceNumberController,
          enabled: _canEditFields,
          decoration: const InputDecoration(
            labelText: 'Número de factura',
            helperText: 'Puedes modificar el folio si tu numeración es manual',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Ingresa un número de factura';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: _selectedSupplier == null
                ? theme.colorScheme.surfaceContainerHighest
                : theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Icon(
              Icons.store,
              color: _selectedSupplier == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
          ),
          title: Text(_selectedSupplier?.name ?? 'Selecciona un proveedor'),
          subtitle: _selectedSupplier != null && _selectedSupplier!.rut != null
              ? Text('RUT: ${ChileanUtils.formatRut(_selectedSupplier!.rut!)}')
              : const Text('Necesario para facturación y reportes'),
          trailing: FilledButton.tonalIcon(
            onPressed: canEditSupplier ? _openSupplierSelector : null,
            icon: Icon(_selectedSupplier == null ? Icons.search : Icons.edit,
                size: 18),
            label: Text(
                _selectedSupplier == null ? 'Buscar proveedor' : 'Cambiar'),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceMetaSection(ThemeData theme) {
    final canEditFinancialInterpretation =
        _canEditFields && !_hasSupplierResolutionLines;
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_note),
          title: const Text('Fecha de emisión'),
          subtitle: Text(ChileanUtils.formatDate(_issueDate)),
          trailing: TextButton(
            onPressed: canEditFinancialInterpretation
                ? () => _pickDate(isIssueDate: true)
                : null,
            child: const Text('Cambiar'),
          ),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('Fecha de vencimiento'),
          subtitle: Text(ChileanUtils.formatDate(
              _dueDate ?? _issueDate.add(const Duration(days: 30)))),
          trailing: TextButton(
            onPressed:
                _canEditFields ? () => _pickDate(isIssueDate: false) : null,
            child: const Text('Cambiar'),
          ),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Estado de la factura'),
          subtitle: Text(_statusDisplayName(_status)),
          trailing: _status == PurchaseInvoiceStatus.draft
              ? Text(
                  _canEditFields ? 'Editando' : 'Solo lectura',
                  style: theme.textTheme.labelMedium,
                )
              : null,
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.receipt_long_outlined,
            color: _taxTreatment == TaxTreatment.taxIncluded
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: const Text('Tratamiento de IVA'),
          subtitle: DropdownButtonFormField<TaxTreatment>(
            isExpanded: true,
            initialValue: _taxTreatment,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: canEditFinancialInterpretation
                  ? null
                  : theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
            ),
            items: const [
              DropdownMenuItem(
                value: TaxTreatment.noTax,
                child: Text('Sin IVA (exento o no afecto)'),
              ),
              DropdownMenuItem(
                value: TaxTreatment.taxIncluded,
                child: Text('IVA Incluido en precio (19%)'),
              ),
            ],
            onChanged: canEditFinancialInterpretation
                ? (value) {
                    if (value != null && !_hasSupplierResolutionLines) {
                      setState(() => _taxTreatment = value);
                    }
                  }
                : null,
          ),
        ),
      ],
    );
  }

  String _statusDisplayName(PurchaseInvoiceStatus status) {
    switch (status) {
      case PurchaseInvoiceStatus.draft:
        return 'Borrador';
      case PurchaseInvoiceStatus.sent:
        return 'Enviada';
      case PurchaseInvoiceStatus.confirmed:
        return 'Confirmada';
      case PurchaseInvoiceStatus.received:
        return 'Recibida';
      case PurchaseInvoiceStatus.paid:
        return 'Pagada';
      case PurchaseInvoiceStatus.cancelled:
        return 'Cancelada';
    }
  }

  String _purchaseTreatmentLabel(PurchaseTreatment treatment) {
    switch (treatment) {
      case PurchaseTreatment.inventory:
        return 'Inventario';
      case PurchaseTreatment.workshopConsumable:
        return 'Consumible taller';
    }
  }

  IconData _purchaseTreatmentIcon(PurchaseTreatment treatment) {
    switch (treatment) {
      case PurchaseTreatment.inventory:
        return Icons.inventory_2_outlined;
      case PurchaseTreatment.workshopConsumable:
        return Icons.build_outlined;
    }
  }

  Color _purchaseTreatmentColor(
    ThemeData theme,
    PurchaseTreatment treatment,
  ) {
    switch (treatment) {
      case PurchaseTreatment.inventory:
        return theme.colorScheme.primary;
      case PurchaseTreatment.workshopConsumable:
        return Colors.orange.shade700;
    }
  }

  Widget _buildPurchaseTreatmentControl(
    ThemeData theme,
    _PurchaseLineEntry entry,
  ) {
    final treatment = entry.line.purchaseTreatment;
    final accentColor = _purchaseTreatmentColor(theme, treatment);
    final canEditLine = _canEditFields && !entry.isSupplierResolutionLocked;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_purchaseTreatmentIcon(treatment), size: 14, color: accentColor),
          const SizedBox(width: 6),
          Text(
            _purchaseTreatmentLabel(treatment),
            style: theme.textTheme.labelSmall?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (canEditLine) ...[
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: accentColor),
          ],
        ],
      ),
    );

    if (!canEditLine) {
      return chip;
    }

    return PopupMenuButton<PurchaseTreatment>(
      tooltip: 'Tratamiento de compra',
      initialValue: treatment,
      onSelected: (value) {
        if (entry.isSupplierResolutionLocked) return;
        setState(() {
          entry.line = entry.line.copyWith(purchaseTreatment: value);
        });
      },
      itemBuilder: (context) => PurchaseTreatment.values
          .map(
            (value) => PopupMenuItem<PurchaseTreatment>(
              value: value,
              child: Row(
                children: [
                  Icon(
                    _purchaseTreatmentIcon(value),
                    size: 18,
                    color: _purchaseTreatmentColor(theme, value),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_purchaseTreatmentLabel(value))),
                ],
              ),
            ),
          )
          .toList(),
      child: chip,
    );
  }

  Widget _buildLineItemsSection(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Mobile Breakpoint for Form Items
        if (constraints.maxWidth < 700) {
          return Column(
            children: [
              if (_lineEntries.isNotEmpty)
                ..._lineEntries.asMap().entries.map((entry) =>
                    _buildMobileItemCard(theme, entry.key + 1, entry.value)),
              if (_canEditFields) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => _addEmptyLine(shouldAutoFocus: true),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline,
                            size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Agregar producto',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_lineEntries.isEmpty && !_canEditFields)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.remove_shopping_cart_outlined,
                            size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(
                          'No hay artículos',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }

        // Desktop Table View (Existing Logic)
        const minTableWidth = 800.0;
        final tableWidth = constraints.maxWidth > minTableWidth
            ? constraints.maxWidth
            : minTableWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  // Table header
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(7),
                        topRight: Radius.circular(7),
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // # column
                          Container(
                            width: _colIndexWidth,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.2)),
                              ),
                            ),
                            child: Center(
                              child: Text('#',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ),

                          // Product details column (expandable)
                          Expanded(
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 250),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.2)),
                                ),
                              ),
                              child: Text('DETALLES DEL ARTÍCULO',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ),

                          // Cantidad column
                          Container(
                            width: _colQuantityWidth,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.2)),
                              ),
                            ),
                            child: Center(
                              child: Text('CANTIDAD',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ),

                          // Tarifa column
                          Container(
                            width: _colPriceWidth,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.2)),
                              ),
                            ),
                            child: Center(
                              child: Text('TARIFA',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ),

                          // Descuento column
                          Container(
                            width: _colDiscountWidth,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.2)),
                              ),
                            ),
                            child: Center(
                              child: Text('DESCUENTO',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ),

                          // Importe column
                          Container(
                            width: _colTotalWidth,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Text('IMPORTE',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                textAlign: TextAlign.right),
                          ),

                          // Actions column
                          const SizedBox(width: _colActionsWidth),
                        ],
                      ),
                    ),
                  ),

                  // Header/Content divider
                  Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.outline.withValues(alpha: 0.2)),

                  // Line items
                  Column(
                    children: [
                      // Existing line items - using same pattern as sales invoice
                      if (_lineEntries.isNotEmpty)
                        ..._lineEntries.asMap().entries.map((entry) =>
                            _buildCompactLineRow(
                                theme, entry.key + 1, entry.value)),

                      // Manual Add Line Button
                      if (_canEditFields)
                        InkWell(
                          onTap: () => _addEmptyLine(shouldAutoFocus: true),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme
                                  .surface, // Background for contrast
                              border: Border(
                                top: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.2)),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_circle_outline,
                                    size: 18, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'Agregar línea',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Empty state
                      if (_lineEntries.isEmpty && !_canEditFields)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No hay artículos en esta factura de compra',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileItemCard(
      ThemeData theme, int index, _PurchaseLineEntry entry) {
    final isResolutionLocked = entry.isSupplierResolutionLocked;
    final canEditStructure = _canEditFields && !isResolutionLocked;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header with Product Name and Delete Action
          Container(
            padding: const EdgeInsets.all(12),
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      entry.buildSmartProductField(
                        context,
                        theme,
                        _canEditFields,
                        canEditStructure,
                        () {},
                        () => _autoAddEmptyLineIfNeeded(),
                      ),
                      const SizedBox(height: 8),
                      _buildPurchaseTreatmentControl(theme, entry),
                    ],
                  ),
                ),
                if (canEditStructure)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: theme.colorScheme.error,
                    onPressed: () => _removeLine(entry),
                  ),
              ],
            ),
          ),

          // Details Grid (Qty, Price, Discount, Total)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    // Quantity
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cantidad', style: theme.textTheme.labelSmall),
                          const SizedBox(height: 4),
                          _canEditFields
                              ? SizedBox(
                                  height: 40,
                                  child: TextField(
                                    controller: entry.quantityController,
                                    readOnly: isResolutionLocked,
                                    onTap: isResolutionLocked
                                        ? () => unawaited(
                                              _requestManualSupplierResolutionEdit(
                                                entry,
                                              ),
                                            )
                                        : null,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      contentPadding:
                                          EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : Text(entry.quantityController.text,
                                  style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Price
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Costo Unit.',
                              style: theme.textTheme.labelSmall),
                          const SizedBox(height: 4),
                          _canEditFields
                              ? SizedBox(
                                  height: 40,
                                  child: TextField(
                                    controller: entry.unitCostController,
                                    readOnly: isResolutionLocked,
                                    onTap: isResolutionLocked
                                        ? () => unawaited(
                                              _requestManualSupplierResolutionEdit(
                                                entry,
                                              ),
                                            )
                                        : null,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      prefixText: '\$',
                                      contentPadding:
                                          EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textAlign: TextAlign.right,
                                  ),
                                )
                              : Text(
                                  ChileanUtils.formatCurrency(
                                      entry.line.unitCost),
                                  style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Discount
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Descuento', style: theme.textTheme.labelSmall),
                          const SizedBox(height: 4),
                          _canEditFields
                              ? SizedBox(
                                  height: 40,
                                  child: TextField(
                                    controller: entry.discountController,
                                    readOnly: isResolutionLocked,
                                    onTap: isResolutionLocked
                                        ? () => unawaited(
                                              _requestManualSupplierResolutionEdit(
                                                entry,
                                              ),
                                            )
                                        : null,
                                    decoration: InputDecoration(
                                      border: const OutlineInputBorder(),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8),
                                      suffixIcon: InkWell(
                                        onTap: () {
                                          if (isResolutionLocked) {
                                            unawaited(
                                              _requestManualSupplierResolutionEdit(
                                                entry,
                                              ),
                                            );
                                            return;
                                          }
                                          setState(() {
                                            entry.toggleDiscountType();
                                            _recalculateTotals();
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Text(
                                            entry.discountType ==
                                                    DiscountType.amount
                                                ? '\$'
                                                : '%',
                                            style: TextStyle(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : Text(
                                  '${entry.discountController.text} ${entry.discountType == DiscountType.amount ? '\$' : '%'}',
                                  style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Total
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Total Línea',
                              style: theme.textTheme.labelSmall),
                          const SizedBox(height: 4),
                          Container(
                            alignment: Alignment.centerRight,
                            height: 40, // Height matching input fields
                            child: Text(
                              ChileanUtils.formatCurrency(
                                  entry.line.netAmountClamped),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a single line row using the universal LineRowWrapper.
  /// Hover state is managed locally inside the wrapper, preventing SmartProductField rebuilds.
  Widget _buildCompactLineRow(
      ThemeData theme, int index, _PurchaseLineEntry entry) {
    final line = entry.line;
    final isResolutionLocked = entry.isSupplierResolutionLocked;
    final canEditStructure = _canEditFields && !isResolutionLocked;

    return LineRowWrapper(
      key: ValueKey('line_${entry.hashCode}_$index'),
      index: index,
      canMoveUp: canEditStructure &&
          index > 1 &&
          !_lineEntries[index - 2].isSupplierResolutionLocked,
      canMoveDown: canEditStructure &&
          index < _lineEntries.length &&
          !_lineEntries[index].isSupplierResolutionLocked,
      onMoveUp: () => _moveLineUp(entry),
      onMoveDown: () => _moveLineDown(entry),
      onRemove: () => _removeLine(entry),
      canEdit: canEditStructure,
      indexColumnWidth: _colIndexWidth,
      actionsColumnWidth: _colActionsWidth,
      columns: [
        // Product details column - uses CACHED widget from entry
        LineColumn(
          expanded: true,
          minWidth: 250,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              entry.buildSmartProductField(
                context,
                theme,
                _canEditFields,
                canEditStructure,
                () {},
                () => _autoAddEmptyLineIfNeeded(),
              ),
              const SizedBox(height: 8),
              _buildPurchaseTreatmentControl(theme, entry),
            ],
          ),
        ),

        // Cantidad column
        LineColumn(
          width: _colQuantityWidth,
          alignment: Alignment.center,
          child: _canEditFields
              ? TextField(
                  controller: entry.quantityController,
                  readOnly: isResolutionLocked,
                  onTap: isResolutionLocked
                      ? () => unawaited(
                            _requestManualSupplierResolutionEdit(entry),
                          )
                      : null,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    isDense: true,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                )
              : Center(
                  child: Text(
                    entry.quantityController.text,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
        ),

        // Precio column
        LineColumn(
          width: _colPriceWidth,
          alignment: Alignment.center,
          child: _canEditFields
              ? TextField(
                  controller: entry.unitCostController,
                  readOnly: isResolutionLocked,
                  onTap: isResolutionLocked
                      ? () => unawaited(
                            _requestManualSupplierResolutionEdit(entry),
                          )
                      : null,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    isDense: true,
                    prefixText: '\$',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium,
                )
              : Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    ChileanUtils.formatCurrency(line.unitCost),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
        ),

        // Descuento column
        LineColumn(
          width: _colDiscountWidth,
          alignment: Alignment.center,
          child: _canEditFields
              ? TextField(
                  controller: entry.discountController,
                  readOnly: isResolutionLocked,
                  onTap: isResolutionLocked
                      ? () => unawaited(
                            _requestManualSupplierResolutionEdit(entry),
                          )
                      : null,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    isDense: true,
                    suffixIcon: InkWell(
                      onTap: () {
                        if (isResolutionLocked) {
                          unawaited(
                            _requestManualSupplierResolutionEdit(entry),
                          );
                          return;
                        }
                        setState(() {
                          entry.toggleDiscountType();
                          // Trigger recalculation in UI
                          _recalculateTotals();
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Text(
                          entry.discountType == DiscountType.amount
                              ? '\$'
                              : '%',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                )
              : Center(
                  child: Text(
                    entry.discountController.text,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
        ),

        // Importe/Total column (no right border - last content column)
        LineColumn(
          width: _colTotalWidth,
          showRightBorder: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              ChileanUtils.formatCurrency(line.netAmountClamped),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReferenceSection(ThemeData theme) {
    return Column(
      children: [
        TextFormField(
          controller: _referenceController,
          enabled: _canEditFields,
          decoration: const InputDecoration(
            labelText: 'Referencia (opcional)',
            hintText: 'Ej: Orden de compra, guía de despacho...',
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notesController,
          enabled: _canEditFields,
          decoration: const InputDecoration(
            labelText: 'Notas internas (opcional)',
            hintText: 'Observaciones adicionales...',
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildSummaryCard(ThemeData theme) {
    return _buildSectionCard(
      theme,
      icon: Icons.calculate_outlined,
      title: 'Resumen',
      children: [_buildSummary(theme)],
    );
  }

  Widget _buildSummary(ThemeData theme) {
    final textStyle =
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    final discountAmt = _discountAmount;
    // ignore: unused_local_variable
    final hasDiscount = discountAmt > 0;

    // Build rows dynamically based on timing
    final List<Widget> rows = [];

    // 1. Base Subtotal
    rows.add(_buildSummaryRow(
        // If discount is Pre-Tax, this is Bruto (before discount).
        // If discount is Post-Tax, this is *already* Net (because discount applies later).
        (_isDiscountBeforeTax && discountAmt > 0)
            ? 'Subtotal (Bruto)'
            : (_taxTreatment == TaxTreatment.taxIncluded
                ? 'Subtotal (Neto)'
                : 'Subtotal'),
        ChileanUtils.formatCurrency(_subtotalBeforeDiscount),
        textStyle,
        theme));

    // 2. Pre-Tax Discount Section
    if (_isDiscountBeforeTax) {
      if (discountAmt > 0) {
        // Show discount input
        rows.add(const SizedBox(height: 12));
        rows.add(
            _buildDiscountRow(theme, textStyle, discountAmt, discountAmt > 0));

        // Show Net after discount
        rows.add(const SizedBox(height: 8));
        rows.add(_buildSummaryRow(
            'Neto con Descuento',
            ChileanUtils.formatCurrency(_subtotal),
            textStyle?.copyWith(fontWeight: FontWeight.w700),
            theme));
      } else {
        // Even if 0, show input here for "Pre-Tax" mode
        rows.add(const SizedBox(height: 12));
        rows.add(
            _buildDiscountRow(theme, textStyle, discountAmt, discountAmt > 0));
      }
    }

    // 3. IVA Section
    if (_taxTreatment == TaxTreatment.taxIncluded) {
      rows.add(const SizedBox(height: 8));
      rows.add(_buildSummaryRow(
          'IVA (19%)',
          ChileanUtils.formatCurrency(_iva),
          textStyle?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          theme));
    }

    // 4. Post-Tax Discount Section
    if (!_isDiscountBeforeTax) {
      // Create a visual break before Total
      rows.add(const SizedBox(height: 8));

      // Calculate "Total Pre-Discount" if needed for clarity
      if (discountAmt > 0 && _taxTreatment == TaxTreatment.taxIncluded) {
        rows.add(_buildSummaryRow(
            'Total Pre-Descuento',
            ChileanUtils.formatCurrency(_subtotalBeforeDiscount + _iva),
            textStyle?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
            theme));
      }

      rows.add(const SizedBox(height: 8));
      rows.add(
          _buildDiscountRow(theme, textStyle, discountAmt, discountAmt > 0));
    }

    // 5. Final Total
    rows.add(const Divider(height: 24));
    rows.add(_buildSummaryRow(
      'Total',
      ChileanUtils.formatCurrency(_total),
      theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: theme.colorScheme.primary,
      ),
      theme,
    ));

    return Column(children: rows);
  }

  Widget _buildSummaryRow(
      String label, String value, TextStyle? style, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        Text(value, style: style),
      ],
    );
  }

  Widget _buildDiscountRow(ThemeData theme, TextStyle? textStyle,
      double discountAmt, bool hasDiscount) {
    final isPercent = _discountType == 'percentage';
    final canEditFinancialInterpretation =
        _canEditFields && !_hasSupplierResolutionLines;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Descuento',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: hasDiscount
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              // Timing Toggle
              _buildDiscountTimingToggle(theme),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Custom condensed input container
              Container(
                width: 90,
                height: 30,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _discountValueController,
                        enabled: canEditFinancialInterpretation,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.0,
                        ),
                        cursorHeight: 16,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.only(left: 4, bottom: 8),
                        ),
                        onChanged: (_) {
                          if (!_hasSupplierResolutionLines) {
                            _recalculateTotals();
                          }
                        },
                      ),
                    ),
                    // Toggle Unit
                    GestureDetector(
                      onTap: canEditFinancialInterpretation
                          ? () => setState(() {
                                if (_hasSupplierResolutionLines) return;
                                _discountType =
                                    isPercent ? 'amount' : 'percentage';
                              })
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        margin: const EdgeInsets.all(2),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isPercent ? '%' : '\u0024',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Computed discount display
              SizedBox(
                width: 80, // Fixed width for alignment
                child: Text(
                  hasDiscount
                      ? '-${ChileanUtils.formatCurrency(discountAmt)}'
                      : ChileanUtils.formatCurrency(0),
                  textAlign: TextAlign.right,
                  style: textStyle?.copyWith(
                    color: hasDiscount
                        ? Colors.red.shade700
                        : theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountTimingToggle(ThemeData theme) {
    final canEditFinancialInterpretation =
        _canEditFields && !_hasSupplierResolutionLines;
    return PopupMenuButton<bool>(
      enabled: canEditFinancialInterpretation,
      tooltip: 'Momento del descuento',
      initialValue: _isDiscountBeforeTax,
      onSelected: (bool isBefore) {
        if (canEditFinancialInterpretation && !_hasSupplierResolutionLines) {
          setState(() => _isDiscountBeforeTax = isBefore);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<bool>>[
        const PopupMenuItem<bool>(
          value: true,
          child: Text('Antes de IVA (Reduce base imponible)'),
        ),
        const PopupMenuItem<bool>(
          value: false,
          child: Text('Después de IVA (Descuento al total)'),
        ),
      ],
      offset: const Offset(0, 30),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          _isDiscountBeforeTax ? Icons.call_received : Icons.call_made,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

enum DiscountType { amount, percentage }

class _PurchaseLineEntry {
  _PurchaseLineEntry(
      {required this.line, this.product, this.shouldAutoFocus = false})
      : quantityController =
            TextEditingController(text: purchaseLineDecimalText(line.quantity)),
        unitCostController =
            TextEditingController(text: purchaseLineDecimalText(line.unitCost)),
        discountController =
            TextEditingController(text: purchaseLineDecimalText(line.discount)),
        productNameController =
            TextEditingController(text: line.productName ?? ''),
        productSkuController =
            TextEditingController(text: line.productSku ?? ''),
        descriptionController = TextEditingController(
            text: line.description ?? ''), // Initialize with description
        productNameFocusNode = FocusNode();

  PurchaseInvoiceItem line;
  Product? product; // Store full product for image access
  /// Whether this line's product field should auto-focus (for newly added lines)
  bool shouldAutoFocus;
  DiscountType discountType = DiscountType.amount; // Default to amount

  final TextEditingController quantityController;
  final TextEditingController unitCostController;
  final TextEditingController discountController;
  final TextEditingController productNameController;
  final TextEditingController productSkuController;
  final TextEditingController descriptionController;
  final FocusNode productNameFocusNode;

  bool get isSupplierResolutionLocked =>
      isPurchaseSupplierResolutionLineLocked(line);

  void toggleDiscountType() {
    if (isSupplierResolutionLocked) return;
    discountType = discountType == DiscountType.amount
        ? DiscountType.percentage
        : DiscountType.amount;

    // Recalculate discount based on new type and current input
    recalculateDiscount();
  }

  void recalculateDiscount() {
    if (isSupplierResolutionLocked) return;
    final inputValue =
        double.tryParse(discountController.text.replaceAll(',', '.')) ?? 0;

    if (inputValue < 0) return;

    double calculatedDiscount = 0;
    if (discountType == DiscountType.amount) {
      calculatedDiscount = inputValue;
    } else {
      // Percentage: (qty * unitCost) * (percentage / 100)
      final totalAmount = line.quantity * line.unitCost;
      calculatedDiscount = totalAmount * (inputValue / 100);
    }

    line = line.copyWith(discount: calculatedDiscount);
  }

  void attachListeners(VoidCallback onChanged) {
    quantityController.addListener(() {
      if (isSupplierResolutionLocked) return;
      final value =
          double.tryParse(quantityController.text.replaceAll(',', '.'));
      if (value != null && value >= 0) {
        line = line.copyWith(quantity: value);
        // Recalculate discount if it's percentage based (depends on total)
        if (discountType == DiscountType.percentage) {
          recalculateDiscount();
        }
        onChanged();
      }
    });
    unitCostController.addListener(() {
      if (isSupplierResolutionLocked) return;
      final value =
          double.tryParse(unitCostController.text.replaceAll(',', '.'));
      if (value != null && value >= 0) {
        line = line.copyWith(unitCost: value);
        // Recalculate discount if it's percentage based (depends on total)
        if (discountType == DiscountType.percentage) {
          recalculateDiscount();
        }
        onChanged();
      }
    });
    discountController.addListener(() {
      if (isSupplierResolutionLocked) return;
      recalculateDiscount();
      onChanged();
    });
    // ❌ DON'T listen to productNameController - it causes auto-selection on every keystroke
    // Product name is updated ONLY when onProductSelected is called in ProductAutocompleteField
    productSkuController.addListener(() {
      if (isSupplierResolutionLocked) return;
      line = line.copyWith(productSku: productSkuController.text);
      onChanged();
    });
    // Add listener for description updates
    descriptionController.addListener(() {
      line = line.copyWith(description: descriptionController.text);
      onChanged();
    });
  }

  void dispose() {
    quantityController.dispose();
    unitCostController.dispose();
    discountController.dispose();
    productNameController.dispose();
    productSkuController.dispose();
    descriptionController.dispose();
    productNameFocusNode.dispose();
  }

  // CRITICAL: Cache the SmartProductField widget to prevent rebuilds on parent hover state changes
  // This is the fix for flickering and disappearing dropdown when mouse moves
  Widget? _cachedSmartProductField;
  bool? _cachedCanEdit;
  bool? _cachedCanChangeProduct;

  void invalidateSmartProductFieldCache() {
    _cachedSmartProductField = null;
    _cachedCanEdit = null;
    _cachedCanChangeProduct = null;
  }

  /// Build the SmartProductField for this line entry
  /// This method lives on the entry (not the row widget state) to prevent
  /// row hover state changes from rebuilding the field
  Widget buildSmartProductField(
    BuildContext context,
    ThemeData theme,
    bool canEdit,
    bool canChangeProduct,
    VoidCallback onUpdate,
    VoidCallback onAutoAdd,
  ) {
    // Return cached widget if nothing meaningful changed
    // Only rebuild if canEdit changes (not on hover which doesn't change canEdit)
    if (_cachedSmartProductField != null &&
        _cachedCanEdit == canEdit &&
        _cachedCanChangeProduct == canChangeProduct) {
      return _cachedSmartProductField!;
    }

    _cachedCanEdit = canEdit;
    _cachedCanChangeProduct = canChangeProduct;
    _cachedSmartProductField = SmartProductField(
      key: ValueKey('product_$hashCode'),
      initialData: ProductFieldData(
        product: product,
        productName:
            line.productName?.isEmpty ?? true ? null : line.productName,
        productSku: line.productSku?.isEmpty ?? true ? null : line.productSku,
        isCatalogProduct: line.productId.isNotEmpty,
        description: descriptionController.text,
      ),
      enabled: canEdit,
      canChangeProduct: canChangeProduct,
      showCost: true, // Purchases use cost, not price
      allowCustomItems: true,
      autoFocus: shouldAutoFocus,
      focusNode: productNameFocusNode,
      descriptionController: descriptionController,
      onAutoAddLine: onAutoAdd,
      onEditProduct: (p) => _showEditProductDialog(context, p),
      onShowProductDetails: (p) => _showProductDetailsPane(context, p, theme),
      onProductChanged: (selection) {
        if (isSupplierResolutionLocked) return;
        if (selection == null) {
          // Product cleared
          product = null;
          productNameController.clear();
          productSkuController.clear();
          descriptionController.clear();
          line = line.copyWith(
            productId: '',
            productName: '',
            productSku: '',
            purchaseTreatment: PurchaseTreatment.inventory,
          );
          onUpdate();
        } else {
          // Product selected or description changed
          product = selection.product;
          productNameController.text = selection.productName ?? '';
          productSkuController.text = selection.productSku ?? '';
          line = line.copyWith(
            productId: selection.product?.id ?? '',
            productName: selection.productName ?? '',
            productSku: selection.productSku,
            purchaseTreatment: selection.product?.purchaseTreatment ??
                PurchaseTreatment.inventory,
            unitCost: selection.price > 0 ? selection.price : line.unitCost,
          );
          if (selection.price > 0) {
            unitCostController.text = purchaseLineDecimalText(selection.price);
          }
          onUpdate();
        }
      },
    );

    return _cachedSmartProductField!;
  }

  void _showEditProductDialog(BuildContext context, Product product) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ProductFormPage(productId: product.id, showInDialog: true),
          ),
        ),
      ),
    );
  }

  void _showProductDetailsPane(
      BuildContext context, Product product, ThemeData theme) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Product Details',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            child: Container(
              width: 400,
              height: double.infinity,
              color: theme.scaffoldBackgroundColor,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Detalles del Producto',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.imageUrl != null)
                            Center(
                              child: Image.network(
                                product.imageUrl!,
                                height: 200,
                                fit: BoxFit.contain,
                              ),
                            ),
                          const SizedBox(height: 16),
                          Text(product.name, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text('SKU: ${product.sku}'),
                          Text('Costo: \$${product.cost.toStringAsFixed(0)}'),
                          Text('Precio: \$${product.price.toStringAsFixed(0)}'),
                          Text('Stock: ${product.availableStockQuantity}'),
                          if (product.description != null) ...[
                            const SizedBox(height: 16),
                            Text('Descripción:',
                                style: theme.textTheme.titleSmall),
                            Text(product.description!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SupplierSelector extends StatefulWidget {
  final List<shared_supplier.Supplier> suppliers;
  final Future<shared_supplier.Supplier?> Function(String name)
      onCreateSupplier;

  const _SupplierSelector(
      {required this.suppliers, required this.onCreateSupplier});

  @override
  State<_SupplierSelector> createState() => _SupplierSelectorState();
}

class _SupplierSelectorState extends State<_SupplierSelector> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _newSupplierController = TextEditingController();

  late List<shared_supplier.Supplier> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.suppliers;
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _newSupplierController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = widget.suppliers.where((supplier) {
        return supplier.name.toLowerCase().contains(query) ||
            (supplier.rut?.toLowerCase().contains(query) ?? false) ||
            (supplier.email?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  Future<void> _handleCreateSupplier() async {
    final name = _newSupplierController.text.trim();
    if (name.isEmpty) return;
    final supplier = await widget.onCreateSupplier(name);
    if (supplier != null && mounted) {
      Navigator.of(context).pop(supplier);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.95,
          initialChildSize: 0.8,
          builder: (context, controller) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Seleccionar proveedor',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SearchBarWidget(
                    controller: _searchController,
                    hintText: 'Buscar por nombre, RUT o email...',
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newSupplierController,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Crear proveedor rápido',
                      hintText: 'Nombre del proveedor',
                      labelStyle: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                      ),
                      hintStyle: TextStyle(
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          Icons.check,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        onPressed: _handleCreateSupplier,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: isDark ? Colors.grey[700]! : Colors.grey[400]!,
                        ),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _handleCreateSupplier(),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No se encontraron proveedores',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: controller,
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              final supplier = _filtered[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isDark
                                      ? Colors.grey[800]
                                      : Colors.grey[200],
                                  child: Icon(
                                    Icons.store_outlined,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                title: Text(
                                  supplier.name,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (supplier.rut != null &&
                                        supplier.rut!.isNotEmpty)
                                      Text(
                                        'RUT: ${ChileanUtils.formatRut(supplier.rut!)}',
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                        ),
                                      ),
                                    if (supplier.email != null &&
                                        supplier.email!.isNotEmpty)
                                      Text(
                                        supplier.email!,
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                                onTap: () =>
                                    Navigator.of(context).pop(supplier),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProductSelector extends StatefulWidget {
  final List<Product> products;

  const _ProductSelector({required this.products});

  @override
  State<_ProductSelector> createState() => _ProductSelectorState();
}

class _ProductSelectorState extends State<_ProductSelector> {
  final TextEditingController _searchController = TextEditingController();
  late List<Product> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.products;
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = widget.products.where((product) {
        final candidates = [
          product.name,
          product.sku,
          product.brand,
          product.model,
        ];
        return candidates.any(
            (value) => value != null && value.toLowerCase().contains(query));
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.95,
          initialChildSize: 0.85,
          builder: (context, controller) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Seleccionar producto',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  SearchBarWidget(
                    controller: _searchController,
                    hintText: 'Buscar por nombre, SKU, marca...',
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No se encontraron productos',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: controller,
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              final product = _filtered[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isDark
                                      ? Colors.grey[800]
                                      : Colors.grey[200],
                                  child: Text(
                                    product.name.isNotEmpty
                                        ? product.name[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color:
                                          isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  product.name,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SKU: ${product.sku}',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          'Costo: ${ChileanUtils.formatCurrency(product.cost)}',
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.grey[400]
                                                : Colors.grey[600],
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                product.availableStockQuantity >
                                                        0
                                                    ? (isDark
                                                        ? Colors.green[900]
                                                        : Colors.green[100])
                                                    : (isDark
                                                        ? Colors.red[900]
                                                        : Colors.red[100]),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Stock: ${product.availableStockQuantity}',
                                            style: TextStyle(
                                              color:
                                                  product.availableStockQuantity >
                                                          0
                                                      ? (isDark
                                                          ? Colors.green[300]
                                                          : Colors.green[800])
                                                      : (isDark
                                                          ? Colors.red[300]
                                                          : Colors.red[800]),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: Icon(
                                  Icons.chevron_right,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                                onTap: () => Navigator.of(context).pop(product),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
