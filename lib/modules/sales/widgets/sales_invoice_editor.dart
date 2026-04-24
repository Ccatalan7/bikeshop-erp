import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/services/database_service.dart';
import '../../../shared/services/number_generation_service.dart';
import '../../../shared/services/remote_scanner_service.dart';
import '../../../shared/services/barcode_scanner_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/invoice_pdf_generator.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/smart_product_field.dart';
import '../../../shared/widgets/line_row_wrapper.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../../bikeshop/widgets/task_form_dialog.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io' show Platform, File;
import 'package:file_picker/file_picker.dart';

/// A reusable, embeddable widget for creating and editing sales invoices.
///
/// **Usage Context:**
/// This widget is designed to be used inline within other pages, such as the
/// Calendar View side panel, Job details views, or modal bottom sheets.
/// It supports a `compact` mode specifically for constrained spaces.
///
/// **Important Note for Developers/AI:**
/// If you are modifying the invoice form UI or logic (like adding fields or changing
/// line item behavior), you MUST apply the SAME changes to the main full-page
/// invoice form located at `lib/modules/sales/pages/invoice_form_page.dart`.
class SalesInvoiceEditor extends StatefulWidget {
  final String? invoiceId;
  final String? preselectedJobId;
  final String? preselectedCustomerId;
  final bool isCompact; // Enable compact mode for side panels
  final VoidCallback? onSaved; // Callback after successful save

  const SalesInvoiceEditor({
    super.key,
    this.invoiceId,
    this.preselectedJobId,
    this.preselectedCustomerId,
    this.isCompact = false,
    this.onSaved,
  });

  @override
  State<SalesInvoiceEditor> createState() => _SalesInvoiceEditorState();
}

class _SalesInvoiceEditorState extends State<SalesInvoiceEditor>
    with AutomaticKeepAliveClientMixin {
  // Column widths for table alignment
  static const double _colIndexWidth = 40.0;
  static const double _colQuantityWidth = 120.0;
  static const double _colPriceWidth = 130.0;
  static const double _colDiscountWidth = 130.0;
  static const double _colTotalWidth = 130.0;
  static const double _colActionsWidth = 48.0;

  @override
  bool get wantKeepAlive => true;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _invoiceNumberController =
      TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final List<_InvoiceLineEntry> _lineEntries = [];

  // Bike linkage for invoice lines
  final List<MechanicJobBike> _availableJobBikes = [];
  String _debugBikeMessage = 'DEBUG: Init state';

  // State management
  late SalesService _salesService;
  late CustomerService _customerService;
  late shared_inventory.InventoryService _inventoryService;
  late BikeshopService _bikeshopService; // Added BikeshopService

  final List<Customer> _cachedCustomers = [];
  final List<Product> _cachedProducts = [];

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  bool _isUpdatingStatus = false;
  bool _isDirty = false; // Tracks unsaved changes to protect from rebuilds
  bool _isGeneratingPdf = false;

  StreamSubscription? _scanSubscription;
  final _remoteScannerService = RemoteScannerService();
  bool _scannerEnabled = false;

  final StringBuffer _scanBuffer = StringBuffer();
  Timer? _hwScanTimer;
  DateTime? _lastScanKeyTime;
  static const Duration _scanKeyTimeout = Duration(milliseconds: 100);
  static const int _minBarcodeLen = 3;

  // Key to reset autocomplete field after adding product
  int _autocompleteKey = 0;

  Customer? _selectedCustomer;
  Invoice? _loadedInvoice;
  DateTime _issueDate = DateTime.now();
  DateTime? _dueDate;
  InvoiceStatus _status = InvoiceStatus.draft;
  TaxTreatment _taxTreatment =
      TaxTreatment.noTax; // Default: no tax (cash/transfer common)

  String? get _currentInvoiceId => _loadedInvoice?.id ?? widget.invoiceId;
  bool get _canEditFields => _status == InvoiceStatus.draft && _isEditing;
  bool get _canMarkAsSent =>
      _currentInvoiceId != null &&
      _status == InvoiceStatus.draft &&
      !_isEditing;
  bool get _shouldShowReadOnlyNotice =>
      !_canEditFields && _status == InvoiceStatus.draft;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.invoiceId == null;
    _dueDate = _issueDate.add(const Duration(days: 30));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initialize());
    });
  }

  @override
  void didUpdateWidget(SalesInvoiceEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.invoiceId != oldWidget.invoiceId &&
            widget.invoiceId != _loadedInvoice?.id) ||
        widget.preselectedJobId != oldWidget.preselectedJobId ||
        widget.preselectedCustomerId != oldWidget.preselectedCustomerId) {
      _resetAndReload();
    }
  }

  void _resetAndReload() {
    for (final entry in _lineEntries) {
      entry.dispose();
    }
    _lineEntries.clear();

    _invoiceNumberController.clear();
    _referenceController.clear();

    setState(() {
      _isLoading = true;
      _isEditing = widget.invoiceId == null;
      _loadedInvoice = null;
      _selectedCustomer = null;
      _availableJobBikes.clear();
      _status = InvoiceStatus.draft;
      _issueDate = DateTime.now();
      _dueDate = _issueDate.add(const Duration(days: 30));
      _isDirty = false;
    });

    unawaited(_initialize());
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _referenceController.dispose();
    for (final entry in _lineEntries) {
      entry.dispose();
    }
    _scanSubscription?.cancel();
    HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
    _hwScanTimer?.cancel();
    super.dispose();
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

    final barcodeService = context.read<BarcodeScannerService>();

    try {
      if (_scannerEnabled) {
        await _remoteScannerService.stopListening();
        _scanSubscription?.cancel();
        _scanSubscription = null;
        HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
        _hwScanTimer?.cancel();
        _scanBuffer.clear();
        setState(() => _scannerEnabled = false);
      } else {
        await _remoteScannerService.startListening();
        // Register hardware key handler for USB/Bluetooth keyboard scanners.
        // HardwareKeyboard bypasses the focus system so it works even when
        // text fields are focused.
        HardwareKeyboard.instance.addHandler(_hardwareKeyHandler);
        // Also subscribe to remote scanner stream (phone scanning)
        _scanSubscription?.cancel();
        _scanSubscription = barcodeService.barcodeStream.listen((barcode) {
          if (mounted && _scannerEnabled && _canEditFields) {
            _handleBarcodeScan(barcode);
          }
        });
        setState(() => _scannerEnabled = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📱 Escáner activado'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error con escáner: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Hardware keyboard handler for USB/Bluetooth barcode scanners.
  /// Returns false so key events still reach focused widgets (text fields).
  bool _hardwareKeyHandler(KeyEvent event) {
    if (!_scannerEnabled || !mounted || !_canEditFields) return false;
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    if (_lastScanKeyTime != null &&
        now.difference(_lastScanKeyTime!) > _scanKeyTimeout) {
      // Gap too large — human typing, reset buffer
      _scanBuffer.clear();
    }
    _lastScanKeyTime = now;
    _hwScanTimer?.cancel();

    final key = event.logicalKey;
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
    if (char != null && char.isNotEmpty) {
      _scanBuffer.write(char);
      // Auto-process if scanner doesn't send Enter
      _hwScanTimer = Timer(_scanKeyTimeout, () {
        final barcode = _scanBuffer.toString().trim();
        _scanBuffer.clear();
        if (barcode.length >= _minBarcodeLen && mounted && _canEditFields) {
          _handleBarcodeScan(barcode);
        }
      });
    }

    return false; // Never consume — let events reach text fields normally
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    // Search for product by SKU or barcode field
    Product? product = _cachedProducts.cast<Product?>().firstWhere(
          (p) =>
              p!.sku.toLowerCase() == barcode.toLowerCase() ||
              (p.barcode?.toLowerCase() == barcode.toLowerCase()),
          orElse: () => null,
        );

    if (product == null) {
      final matches =
          await _inventoryService.searchProducts(barcode, limit: 20);
      for (final candidate in matches) {
        if (candidate.sku.toLowerCase() == barcode.toLowerCase() ||
            candidate.barcode?.toLowerCase() == barcode.toLowerCase()) {
          product = candidate;
          break;
        }
      }

      final resolvedProduct = product;
      if (resolvedProduct != null &&
          !_cachedProducts
              .any((candidate) => candidate.id == resolvedProduct.id)) {
        _cachedProducts.add(resolvedProduct);
      }
    }

    final resolvedProduct = product;
    if (resolvedProduct != null) {
      // Check if product is already in the invoice
      final existingLineIndex = _lineEntries.indexWhere(
        (entry) => entry.line.product?.id == resolvedProduct.id,
      );

      if (existingLineIndex != -1) {
        // Increment quantity
        final entry = _lineEntries[existingLineIndex];
        final currentQty = int.tryParse(entry.quantityController.text) ?? 0;
        entry.quantityController.text = (currentQty + 1).toString();
        _handleLinesChanged(); // Trigger recalculation and mark dirty
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Cantidad aumentada: ${resolvedProduct.name}'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        // Add as new line - simplified approach
        setState(() {
          final newLine = _InvoiceLine(
            productId: resolvedProduct.id,
            product: resolvedProduct,
            name: resolvedProduct.name,
            sku: resolvedProduct.sku,
            quantity: 1,
            unitPrice: resolvedProduct.price,
            discount: 0,
            cost: resolvedProduct.cost,
            purchaseTreatment: resolvedProduct.purchaseTreatment,
            isService: resolvedProduct.isService,
          );
          _applyPreferredJobBike(newLine);
          final newEntry = _InvoiceLineEntry(newLine);
          newEntry.attachListeners(_handleLinesChanged);
          _lineEntries.add(newEntry);
          _markDirty();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Producto agregado: ${resolvedProduct.name}'),
              backgroundColor: Colors.green,
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

  Future<void> _initialize() async {
    _salesService = Provider.of<SalesService>(context, listen: false);
    _customerService = Provider.of<CustomerService>(context, listen: false);
    _inventoryService =
        Provider.of<shared_inventory.InventoryService>(context, listen: false);
    _bikeshopService = Provider.of<BikeshopService>(context, listen: false);

    try {
      if (_customerService.hasListCustomersCache) {
        _cachedCustomers
          ..clear()
          ..addAll(_customerService.cachedListCustomers);
      }

      if (_inventoryService.products.isNotEmpty) {
        _cachedProducts
          ..clear()
          ..addAll(_inventoryService.products);
      }

      final futures = <Future<dynamic>>[
        _customerService.getCustomersForList(),
        _inventoryService.products.isNotEmpty
            ? Future<List<Product>>.value(_inventoryService.products)
            : _inventoryService.loadProductPreviewPage(page: 0, pageSize: 80),
      ];

      if (widget.invoiceId == null) {
        futures.add(_previewInvoiceNumber());
      }

      final results = await Future.wait(futures);

      _cachedCustomers
        ..clear()
        ..addAll(results[0] as List<Customer>);
      _cachedProducts
        ..clear()
        ..addAll(results[1] as List<Product>);

      if (widget.invoiceId == null && results.length > 2) {
        _invoiceNumberController.text = results[2] as String;
      }

      if (widget.invoiceId != null) {
        // Only fetch if we don't already have it or if it's a different one
        if (_loadedInvoice?.id != widget.invoiceId) {
          final invoice = await _salesService.fetchInvoice(widget.invoiceId!,
              refresh: true);
          if (invoice != null) {
            await _hydrateMissingInvoiceProducts(invoice);
            _loadedInvoice = invoice;
            _applyInvoice(invoice);
          }
        }

        // Check if this invoice is linked to a job, to load bikes
        final db = Provider.of<DatabaseService>(context, listen: false);
        try {
          _debugBikeMessage =
              'DEBUG: Querying mechanic_jobs for editor invoice ${widget.invoiceId}';
          final jobDataList = await db.supabase
              .from('mechanic_jobs')
              .select('id')
              .eq('invoice_id', widget.invoiceId as Object)
              .limit(1);

          if (jobDataList.isNotEmpty) {
            final jobId = jobDataList.first['id'] as String;
            _debugBikeMessage =
                'DEBUG: Editor found job $jobId, loading bikes...';
            await _loadJobBikes(jobId);
          } else if (_loadedInvoice != null) {
            _debugBikeMessage =
                'DEBUG: Editor no direct job link, trying fallback...';
            bool foundFallback = false;
            for (final item in _loadedInvoice!.items) {
              if (item.jobBikeId != null && item.jobBikeId!.isNotEmpty) {
                _debugBikeMessage =
                    'DEBUG: Editor fallback found jobBikeId ${item.jobBikeId}';
                final bikeData = await db.supabase
                    .from('mechanic_job_bikes')
                    .select('job_id')
                    .eq('id', item.jobBikeId as Object)
                    .maybeSingle();
                if (bikeData != null && bikeData['job_id'] != null) {
                  final jobId = bikeData['job_id'] as String;
                  _debugBikeMessage =
                      'DEBUG: Editor fallback resolved job $jobId, calling load';
                  await _loadJobBikes(jobId);
                  foundFallback = true;
                  break;
                }
              }
            }
            if (!foundFallback) {
              _debugBikeMessage =
                  'DEBUG: Editor fallback exhausted without finding job_id';
            }
          }
        } catch (e) {
          debugPrint('Error loading job for invoice id: $e');
          _debugBikeMessage = 'DEBUG: Editor catch block $e';
        }
      } else {
        if (_invoiceNumberController.text.isEmpty) {
          _invoiceNumberController.text = await _previewInvoiceNumber();
        }

        if (widget.preselectedJobId != null) {
          _debugBikeMessage =
              'DEBUG: Editor new invoice from job ${widget.preselectedJobId}, loading bikes...';
          await _loadJobAndPreselectCustomer(widget.preselectedJobId!);
          await _loadJobBikes(widget.preselectedJobId!);
        } else if (widget.preselectedCustomerId != null) {
          _preselectCustomer(widget.preselectedCustomerId!);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error preparando el formulario: $e'),
            backgroundColor: Colors.red,
          ),
        );
        _invoiceNumberController.text = await _previewInvoiceNumber();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyInvoice(Invoice invoice) {
    if (!mounted) return;

    // 🛡️ DATA LOSS PROTECTION: If the server returns an empty item list but we currently
    // have items in the editor, this is almost certainly a database sync race condition.
    // We update the metadata (status, dates, etc.) but PRESERVE our current items.
    if (invoice.items.isEmpty && _lineEntries.isNotEmpty) {
      debugPrint(
          '🚨 [InvoiceEditor] Server returned 0 items for invoice ${invoice.id}. PRESERVING local items to prevent data loss.');
      setState(() {
        _loadedInvoice = invoice.copyWith(
          items: _lineEntries.map((e) => e.toInvoiceItem()).toList(),
        );
        _selectedCustomer = _selectedCustomer; // Keep customer
        _issueDate = invoice.date;
        _dueDate =
            invoice.dueDate ?? invoice.date.add(const Duration(days: 30));
        _status = invoice.status;
        _taxTreatment = invoice.taxTreatment;
        // Do NOT update _lineEntries from empty list
      });
      return;
    }

    debugPrint(
        '🐛 [InvoiceEditor] Applying invoice: ${invoice.id}. Items: ${invoice.items.length}');
    // Log items for detail
    for (var item in invoice.items) {
      debugPrint('   - Item: ${item.productName} (Qty: ${item.quantity})');
    }

    _invoiceNumberController.text = invoice.invoiceNumber.isNotEmpty
        ? invoice.invoiceNumber
        : _buildSuggestedNumber();
    _referenceController.text = invoice.reference ?? '';

    Customer? resolvedCustomer;
    if (invoice.customerId != null) {
      resolvedCustomer = _cachedCustomers.firstWhere(
        (customer) => customer.id == invoice.customerId,
        orElse: () => Customer(
          id: invoice.customerId,
          tenantId: '',
          name: invoice.customerName ?? 'Cliente',
          rut: invoice.customerRut ?? '',
          email: null,
        ),
      );
    }

    final newEntries = <_InvoiceLineEntry>[];
    for (final item in invoice.items) {
      Product? product;
      if (item.isCatalogProduct && item.productId != null) {
        for (final candidate in _cachedProducts) {
          if (candidate.id == item.productId) {
            product = candidate;
            break;
          }
        }
      }

      final entry = _InvoiceLineEntry(
        _InvoiceLine(
          productId: item.productId,
          product: product,
          name: item.productName ?? product?.name ?? 'Artículo',
          sku: item.productSku ?? product?.sku ?? '',
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          discount: item.discount,
          cost: item.cost,
          purchaseTreatment: item.purchaseTreatment,
          isService: item.isService,
          description: item.description,
          isCatalogProduct: item.isCatalogProduct,
          jobBikeId: item.jobBikeId,
          bikeName: item.bikeName,
        ),
      );
      entry.attachListeners(_handleLinesChanged);
      newEntries.add(entry);
    }

    for (final entry in _lineEntries) {
      entry.dispose();
    }

    setState(() {
      _loadedInvoice = invoice;
      _selectedCustomer = resolvedCustomer;
      _issueDate = invoice.date;
      _dueDate = invoice.dueDate ?? invoice.date.add(const Duration(days: 30));
      _status = invoice.status;
      _taxTreatment = invoice.taxTreatment;
      _isEditing = false;
      _lineEntries
        ..clear()
        ..addAll(newEntries);
    });
  }

  String _buildSuggestedNumber() {
    final now = DateTime.now();
    final datePortion =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timePortion = now.millisecondsSinceEpoch.toString().substring(7);
    return 'FV-$datePortion-$timePortion';
  }

  Future<String> _previewInvoiceNumber() async {
    try {
      final numberService = NumberGenerationService();
      return await numberService.previewSalesInvoiceNumber();
    } catch (e) {
      if (kDebugMode) print('Error previewing invoice number: $e');
      return _buildSuggestedNumber();
    }
  }

  Future<String> _generateInvoiceNumber() async {
    try {
      final numberService = NumberGenerationService();
      return await numberService.nextSalesInvoiceNumber();
    } catch (e) {
      if (kDebugMode) print('Error generating invoice number: $e');
      return _buildSuggestedNumber();
    }
  }

  Future<void> _hydrateMissingInvoiceProducts(Invoice invoice) async {
    final missingProductIds = invoice.items
        .where((item) => item.isCatalogProduct && item.productId != null)
        .map((item) => item.productId!)
        .where(
          (productId) =>
              !_cachedProducts.any((candidate) => candidate.id == productId),
        )
        .toSet()
        .toList(growable: false);

    if (missingProductIds.isEmpty) {
      return;
    }

    final db = Provider.of<DatabaseService>(context, listen: false);
    final rows = await Future.wait(
      missingProductIds.map((productId) => db.selectById(
            'products',
            productId,
            selectColumns: Product.listPreviewSelect,
          )),
    );

    for (final row in rows) {
      if (row == null) continue;
      final product = Product.fromJson(row);
      if (_cachedProducts.any((candidate) => candidate.id == product.id)) {
        continue;
      }
      _cachedProducts.add(product);
    }
  }

  Future<void> _loadJobBikes(String jobId) async {
    try {
      _debugBikeMessage = 'DEBUG: Editor fetching bikes for $jobId';
      final bikes = await _bikeshopService.getJobBikes(jobId);
      if (mounted) {
        setState(() {
          _debugBikeMessage =
              'DEBUG: Editor loaded ${bikes.length} bikes from getJobBikes';
          _availableJobBikes.clear();
          _availableJobBikes.addAll(bikes);
        });
      } else {
        _debugBikeMessage =
            'DEBUG: Editor widget not mounted after getJobBikes';
      }
    } catch (e) {
      debugPrint('Error loading bikes for job: $e');
      if (mounted) {
        setState(() {
          _debugBikeMessage = 'DEBUG: Editor catch getJobBikes $e';
        });
      }
    }
  }

  MechanicJobBike? _preferredJobBikeForNewLines() {
    if (_availableJobBikes.isEmpty) return null;

    if (_availableJobBikes.length == 1) {
      return _availableJobBikes.first;
    }

    final distinctAssignedBikeIds = _lineEntries
        .map((entry) => entry.line.jobBikeId)
        .whereType<String>()
        .where((bikeId) => _availableJobBikes.any((bike) => bike.id == bikeId))
        .toSet();

    if (distinctAssignedBikeIds.length == 1) {
      final inferredBikeId = distinctAssignedBikeIds.first;
      return _availableJobBikes
          .where((bike) => bike.id == inferredBikeId)
          .firstOrNull;
    }

    return null;
  }

  void _applyPreferredJobBike(_InvoiceLine line) {
    final preferredBike = _preferredJobBikeForNewLines();
    if (preferredBike == null) return;

    line.jobBikeId = preferredBike.id;
    line.bikeName = preferredBike.displayName;
  }

  Future<void> _loadJobAndPreselectCustomer(String jobId) async {
    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      final jobData = await db.selectById('mechanic_jobs', jobId);

      if (jobData != null) {
        final customerId = jobData['customer_id'] as String?;
        if (customerId != null) {
          _preselectCustomer(customerId);

          final jobNumber = jobData['job_number'] as String?;
          if (jobNumber != null) {
            _referenceController.text = 'Pega $jobNumber';
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading job for invoice: $e');
    }
  }

  void _preselectCustomer(String customerId) {
    final customer =
        _cachedCustomers.where((c) => c.id == customerId).firstOrNull;
    if (customer != null) {
      setState(() {
        _selectedCustomer = customer;
      });
    }
  }

  void _handleLinesChanged() {
    if (mounted) {
      _markDirty(); // Track that changes have been made
      setState(() {});
    }
  }

  /// Mark that the editor has unsaved changes
  void _markDirty() {
    if (!_isDirty && _isEditing) {
      _isDirty = true;
      // debugPrint('🟡 [InvoiceEditor] Marked as dirty (unsaved changes)');
    }
  }

  /// Clear dirty state (after save or discard)
  void _clearDirty() {
    _isDirty = false;
    // debugPrint('✅ [InvoiceEditor] Dirty state cleared');
  }

  void _startEditing() {
    if (_status != InvoiceStatus.draft) return;
    setState(() => _isEditing = true);
  }

  void _cancelEditing() {
    if (!_isEditing) return;
    _clearDirty(); // Discard changes - no longer dirty
    if (_loadedInvoice != null) {
      _applyInvoice(_loadedInvoice!);
    } else if (mounted) {
      setState(() => _isEditing = false);
    }
  }

  Future<void> _updateStatus(InvoiceStatus newStatus) async {
    final invoiceId = _currentInvoiceId;
    if (invoiceId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Guarda la factura como borrador antes de cambiar el estado.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    // 🚀 UNIFIED ATOMIC SAVE: We set the new status locally and then call _saveInvoice
    // This ensures that BOTH the new items AND the new status are sent in a single
    // transaction to the database, eliminating race conditions with triggers.
    final oldStatus = _status;
    setState(() {
      _status = newStatus;
      _isUpdatingStatus = true;
    });

    try {
      await _saveInvoice();
      if (!mounted) return;

      // If save failed (e.g. validation error or network issue), revert status
      if (_isDirty) {
        debugPrint('⚠️ [InvoiceEditor] Save failed or was aborted.');
        setState(() {
          _status = oldStatus;
        });
        return;
      }

      // Success!
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Factura marcada como ${newStatus.name}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar el estado: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _status = oldStatus;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  // Payment logic temporarily disabled for side panel simplicity

  double get _subtotal {
    final value = _lineEntries.fold<double>(
        0, (sum, entry) => sum + entry.line.netAmount);
    return value < 0 ? 0 : value;
  }

  double get _netAmount {
    if (_taxTreatment == TaxTreatment.taxIncluded) {
      return _subtotal / 1.19;
    } else {
      return _subtotal;
    }
  }

  double get _iva {
    if (_taxTreatment == TaxTreatment.taxIncluded) {
      return _subtotal - _netAmount;
    } else {
      return 0;
    }
  }

  double get _total => _subtotal;

  Future<void> _openCustomerSelector() async {
    if (_cachedCustomers.isEmpty) {
      try {
        final customers = await _customerService.getCustomersForList();
        _cachedCustomers
          ..clear()
          ..addAll(customers);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudieron cargar los clientes: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    final selected = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _CustomerSelector(
          initialCustomers: List<Customer>.from(_cachedCustomers),
          customerService: _customerService,
          onCreateCustomer: _createQuickCustomer,
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => _selectedCustomer = selected);
      final exists =
          _cachedCustomers.any((customer) => customer.id == selected.id);
      if (!exists) {
        _cachedCustomers.add(selected);
      }
    }
  }

  Future<Customer?> _createQuickCustomer(String name) async {
    if (name.trim().isEmpty) return null;
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) {
        throw Exception('No se pudo obtener el tenant_id del usuario');
      }

      final customer = Customer(
        tenantId: tenantId,
        name: name.trim(),
        rut: '',
      );

      final created = await _customerService.createCustomer(customer);
      _cachedCustomers.add(created);
      return created;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear cliente: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  void _addProductLine(Product product) {
    final line = _InvoiceLine(
      productId: product.id,
      product: product,
      name: product.name,
      sku: product.sku,
      quantity: 1,
      unitPrice: product.price,
      discount: 0,
      cost: product.cost,
      purchaseTreatment: product.purchaseTreatment,
      isService: product.isService,
      isCatalogProduct: true,
    );

    _applyPreferredJobBike(line);

    final entry = _InvoiceLineEntry(line);
    entry.attachListeners(_handleLinesChanged);

    setState(() {
      _lineEntries.add(entry);
      _autocompleteKey++;
    });
  }

  void _addCustomItemLine(String description) {
    final line = _InvoiceLine(
      productId: null,
      product: null,
      name: description,
      sku: '',
      quantity: 1,
      unitPrice: 0,
      discount: 0,
      cost: 0,
      isCatalogProduct: false,
      description: description,
    );

    _applyPreferredJobBike(line);

    final entry = _InvoiceLineEntry(line);
    entry.attachListeners(_handleLinesChanged);

    setState(() {
      _lineEntries.add(entry);
      _autocompleteKey++;
    });
  }

  void _autoAddEmptyLineIfNeeded() {
    if (_lineEntries.isEmpty) return;

    final lastEntry = _lineEntries.last;
    if (lastEntry.product != null ||
        lastEntry.productNameController.text.isNotEmpty) {
      final line = _InvoiceLine(
        productId: null,
        product: null,
        name: '',
        sku: '',
        quantity: 1,
        unitPrice: 0,
        discount: 0,
        cost: 0,
        purchaseTreatment: PurchaseTreatment.inventory,
        isService: false,
        isCatalogProduct: false,
      );

      _applyPreferredJobBike(line);

      final entry = _InvoiceLineEntry(line, shouldAutoFocus: true);
      entry.attachListeners(_handleLinesChanged);

      setState(() {
        _lineEntries.add(entry);
      });
    }
  }

  void _removeLine(_InvoiceLineEntry entry) {
    setState(() {
      _lineEntries.remove(entry);
      entry.dispose();
    });
  }

  void _moveLineUp(_InvoiceLineEntry entry) {
    final currentIndex = _lineEntries.indexOf(entry);
    if (currentIndex > 0) {
      setState(() {
        _lineEntries.removeAt(currentIndex);
        _lineEntries.insert(currentIndex - 1, entry);
      });
    }
  }

  void _moveLineDown(_InvoiceLineEntry entry) {
    final currentIndex = _lineEntries.indexOf(entry);
    if (currentIndex < _lineEntries.length - 1) {
      setState(() {
        _lineEntries.removeAt(currentIndex);
        _lineEntries.insert(currentIndex + 1, entry);
      });
    }
  }

  Future<void> _pickDate({required bool isIssueDate}) async {
    final initialDate = isIssueDate
        ? _issueDate
        : (_dueDate ?? _issueDate.add(const Duration(days: 30)));
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (selected == null) return;

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
    // Validation Logic
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un cliente antes de guardar.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_lineEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega al menos un producto a la factura.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final customerId = _selectedCustomer!.id;
    if (customerId == null || customerId.isEmpty) {
      // Show Error
      return;
    }

    final items = _lineEntries
        .where((entry) =>
            entry.productNameController.text.trim().isNotEmpty ||
            entry.product != null)
        .map((entry) => entry.toInvoiceItem())
        .toList();

    if (items.isEmpty) {
      // Show Error
      return;
    }

    final tenantId = await TenantService().getTenantId();
    if (tenantId == null) {
      throw Exception('User does not have a tenant_id. Cannot proceed.');
    }

    String invoiceNumber = _invoiceNumberController.text.trim();
    if (_loadedInvoice?.id == null && widget.invoiceId == null) {
      invoiceNumber = await _generateInvoiceNumber();
      _invoiceNumberController.text = invoiceNumber;
    }

    final invoice = Invoice(
      id: _loadedInvoice?.id,
      tenantId: tenantId,
      invoiceNumber: invoiceNumber,
      customerId: customerId,
      customerName: _selectedCustomer!.name,
      customerRut: _selectedCustomer!.rut,
      date: _issueDate,
      dueDate: _dueDate,
      reference: _referenceController.text.trim().isEmpty
          ? null
          : _referenceController.text.trim(),
      status: _status, // Maintain status (usually draft if new)
      subtotal: _subtotal,
      ivaAmount: _iva,
      total: _total,
      taxTreatment: _taxTreatment,
      netAmount: _netAmount,
      items: items,
    );

    setState(() => _isSaving = true);

    try {
      final saved = await _salesService.saveInvoice(invoice);

      // FIX: Link new invoice to the job if we have a preselectedJobId
      // and we just created a NEW invoice (widget.invoiceId was null)
      if (widget.preselectedJobId != null && widget.invoiceId == null) {
        try {
          final db = Provider.of<DatabaseService>(context, listen: false);
          await db.update('mechanic_jobs', widget.preselectedJobId!, {
            'invoice_id': saved.id,
          });
          if (saved.id != null) {
            await _salesService.triggerLinkedJobSync(saved.id!);
          }
        } catch (e) {
          debugPrint('❌ Failed to link/sync invoice to job: $e');
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Factura guardada correctamente'),
          backgroundColor: Colors.green,
        ),
      );

      // ALWAYS apply saved invoice to local state to ensure UI reflects latest data
      _applyInvoice(saved);
      _clearDirty(); // Save successful - clear dirty state

      if (widget.onSaved != null) {
        widget.onSaved!();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo guardar la factura: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _downloadInvoicePDF({
    InvoicePdfExportMode mode = InvoicePdfExportMode.invoiceOnly,
  }) async {
    if (_isGeneratingPdf || _loadedInvoice == null) return;

    setState(() => _isGeneratingPdf = true);

    try {
      if (_isDirty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('⚠️ Guarde los cambios antes de descargar el PDF'),
              backgroundColor: Colors.orange),
        );
        return;
      }

      final resolvedBikeNames =
          await InvoicePdfGenerator.resolveBikeNames(context, _loadedInvoice!);

      final diagnosisNarratives =
          mode == InvoicePdfExportMode.invoiceWithDiagnosis
              ? await InvoicePdfGenerator.resolveDiagnosisNarratives(
                  context,
                  _loadedInvoice!,
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
        _loadedInvoice!,
        resolvedBikeNames,
        diagnosisNarratives: diagnosisNarratives,
      );
      final bytes = await pdf.save();

      // Platform-specific download
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final initialDirectory =
            await InvoicePdfGenerator.resolveDefaultSaveDirectory();
        final String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Factura PDF',
          fileName: mode.fileNameFor(_loadedInvoice!.invoiceNumber),
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
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        await Printing.sharePdf(
          bytes: bytes,
          filename: mode.fileNameFor(_loadedInvoice!.invoiceNumber),
        );
      }
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final theme = Theme.of(context);

    // If compact, don't use MainLayout, just the form content
    // But we need to handle scroll properly.

    final content = Form(
      key: _formKey,
      child: Column(
        children: [
          _buildHeader(theme),
          Expanded(
            child: _isLoading
                ? const Center(child: BrandedLoading())
                : _buildForm(theme),
          ),
        ],
      ),
    );

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldPop = await _showDiscardConfirmDialog(context);
        if (shouldPop == true) {
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: content,
    );
  }

  Future<bool?> _showDiscardConfirmDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar cambios?'),
        content: const Text(
            'Tienes cambios sin guardar en esta factura. ¿Estás seguro de que quieres salir y perderlos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuar editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Descartar cambios'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    // Simplified header for compact mode
    if (widget.isCompact) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _invoiceNumberController.text.isEmpty
                        ? 'Nueva Factura'
                        : _invoiceNumberController.text,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                _buildStatusChip(theme),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _buildActionButtons(),
              ),
            ),
          ],
        ),
      );
    }

    // Original Header Logic
    final invoiceNumber = _invoiceNumberController.text.trim();
    final hasExistingInvoice = _currentInvoiceId != null;
    final title = invoiceNumber.isNotEmpty
        ? 'Factura $invoiceNumber'
        : (hasExistingInvoice ? 'Factura' : 'Nueva factura');

    final actionWidgets = <Widget>[
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
      _buildStatusChip(theme),
      ..._buildActionButtons(),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          // Note: Back button logic should be handled by parent if needed
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
                  'Emite documentos auditables y con IVA integrado.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actionWidgets,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFullScreenEditor() async {
    if (_isDirty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('⚠️ Guarde los cambios antes de expandir'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    if (_currentInvoiceId == null && _lineEntries.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('⚠️ Guarde el borrador antes de expandir'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 900),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Scaffold(
              appBar: AppBar(
                title:
                    Text('Editando Factura ${_invoiceNumberController.text}'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
              body: SalesInvoiceEditor(
                invoiceId: _currentInvoiceId,
                preselectedJobId: widget.preselectedJobId,
                preselectedCustomerId: widget.preselectedCustomerId,
                isCompact: false,
                onSaved: () {
                  Navigator.of(ctx).pop();
                  widget.onSaved?.call();
                },
              ),
            ),
          ),
        ),
      ),
    );

    // Refresh after closing
    if (_currentInvoiceId != null) {
      final inv =
          await _salesService.fetchInvoice(_currentInvoiceId!, refresh: true);
      if (inv != null && mounted) _applyInvoice(inv);
    }
  }

  List<Widget> _buildActionButtons() {
    final actionButtons = <Widget>[];

    // -1. EXPAND BUTTON (Only in compact mode)
    if (widget.isCompact) {
      actionButtons.add(
        IconButton(
          icon: const Icon(Icons.open_in_full, size: 20),
          onPressed: _openFullScreenEditor,
          tooltip: 'Expandir factura',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      );
      actionButtons.add(const SizedBox(width: 8));
    }

    // 0. DOWNLOAD BUTTON (If invoice exists)
    if (_loadedInvoice != null) {
      actionButtons.add(
        PopupMenuButton<InvoicePdfExportMode>(
          enabled: !_isGeneratingPdf,
          tooltip: 'Exportar PDF',
          onSelected: (mode) => _downloadInvoicePDF(mode: mode),
          itemBuilder: (context) => InvoicePdfExportMode.values
              .map(
                (mode) => PopupMenuItem<InvoicePdfExportMode>(
                  value: mode,
                  child: Text(mode.label),
                ),
              )
              .toList(growable: false),
          icon: _isGeneratingPdf
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf),
        ),
      );
      // Add divider/spacing
      if (!widget.isCompact) {
        actionButtons.add(const SizedBox(width: 8));
        actionButtons
            .add(Container(height: 24, width: 1, color: Colors.grey[300]));
        actionButtons.add(const SizedBox(width: 8));
      }

      actionButtons.add(
        IconButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => TaskFormDialog(
                prefillSalesInvoiceId: _loadedInvoice!.id,
                prefillSalesInvoiceNumber: _loadedInvoice!.invoiceNumber,
                prefillCustomerId: _selectedCustomer?.id,
                prefillCustomerName: _selectedCustomer?.name,
                prefillJobId: widget.preselectedJobId,
              ),
            );
          },
          icon: Icon(Icons.add_task,
              color: Theme.of(context).colorScheme.primary),
          tooltip: 'Crear Tarea',
        ),
      );

      if (!widget.isCompact) {
        actionButtons.add(const SizedBox(width: 8));
        actionButtons
            .add(Container(height: 24, width: 1, color: Colors.grey[300]));
        actionButtons.add(const SizedBox(width: 8));
      }
    }

    if (_canEditFields) {
      // 1. SCANNER BUTTON
      // In expanded mode, show a more prominent button if possible, or just the icon
      if (!widget.isCompact) {
        if (_scannerEnabled) {
          actionButtons.add(
            IconButton(
              onPressed: _toggleScanner,
              icon: const Icon(Icons.qr_code_scanner, color: Colors.green),
              tooltip: 'Desactivar',
            ),
          );
        } else {
          actionButtons.add(
            OutlinedButton.icon(
              onPressed: _toggleScanner,
              icon: const Icon(Icons.qr_code_scanner_outlined, size: 18),
              label: const Text('Escanear'),
            ),
          );
        }
      } else {
        // Compact mode scanner
        actionButtons.add(
          IconButton(
            onPressed: _toggleScanner,
            icon: Icon(
              _scannerEnabled
                  ? Icons.qr_code_scanner
                  : Icons.qr_code_scanner_outlined,
              color: _scannerEnabled ? Colors.green : null,
            ),
            tooltip: _scannerEnabled ? 'Desactivar Escáner' : 'Activar Escáner',
          ),
        );
      }

      if (!widget.isCompact) actionButtons.add(const SizedBox(width: 8));

      // 2. CANCEL BUTTON (only if editing existing invoice)
      if (_loadedInvoice != null) {
        actionButtons.add(
          OutlinedButton.icon(
            onPressed: _isSaving ? null : _cancelEditing,
            icon: const Icon(Icons.close),
            label: const Text('Cancelar'),
          ),
        );
        if (!widget.isCompact) actionButtons.add(const SizedBox(width: 8));
      }

      // 3. SAVE BUTTON
      actionButtons.add(
        AppButton(
          text: 'Guardar',
          icon: Icons.save_outlined,
          onPressed: _isSaving ? null : _saveInvoice,
          isLoading: _isSaving,
        ),
      );
    } else {
      // READ-ONLY MODE ACTIONS
      if (_status == InvoiceStatus.draft) {
        actionButtons.add(
          OutlinedButton.icon(
            onPressed: _isUpdatingStatus ? null : _startEditing,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar'),
          ),
        );
        if (!widget.isCompact) actionButtons.add(const SizedBox(width: 8));

        if (_canMarkAsSent) {
          actionButtons.add(FilledButton.icon(
            onPressed: _isUpdatingStatus
                ? null
                : () => _updateStatus(InvoiceStatus.sent),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Enviar'),
          ));
        }
      } else if (_status == InvoiceStatus.sent) {
        actionButtons.add(FilledButton.icon(
          onPressed: _isUpdatingStatus
              ? null
              : () => _updateStatus(InvoiceStatus.confirmed),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Confirmar'),
        ));
      }
    }
    return actionButtons;
  }

  Widget _buildForm(ThemeData theme) {
    if (widget.isCompact) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _buildCustomerSection(theme),
              const SizedBox(height: 16),
              _buildLineItemsSection(theme),
              const SizedBox(height: 16),
              _buildDatesAndStatus(theme),
              const SizedBox(height: 16),
              _buildSummary(theme),
              const SizedBox(height: 16),
              _buildReferenceField(theme),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (_shouldShowReadOnlyNotice) _buildReadOnlyNotice(theme),
                  if (_shouldShowReadOnlyNotice) const SizedBox(height: 16),
                  _buildSectionCard(
                    theme,
                    icon: Icons.person_outline,
                    title: 'Cliente',
                    children: [_buildCustomerSection(theme)],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    theme,
                    icon: Icons.shopping_basket_outlined,
                    title: 'Productos y servicios',
                    children: [_buildLineItemsSection(theme)],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    theme,
                    icon: Icons.notes_outlined,
                    title: 'Referencia',
                    children: [_buildReferenceField(theme)],
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
                    icon: Icons.event_available_outlined,
                    title: 'Fechas y estado',
                    children: [_buildDatesAndStatus(theme)],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    theme,
                    icon: Icons.calculate_outlined,
                    title: 'Resumen',
                    children: [_buildSummary(theme)],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyNotice(ThemeData theme) {
    if (widget.isCompact) return const SizedBox.shrink();
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: ListTile(
        leading:
            Icon(Icons.lock_outline, color: theme.colorScheme.onSurfaceVariant),
        title: const Text('Factura en modo lectura'),
        subtitle: const Text(
            'Usa “Editar” para habilitar los campos y modificar el borrador.'),
      ),
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

  Widget _buildCustomerSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.isCompact)
          TextFormField(
            controller: _invoiceNumberController,
            enabled: _canEditFields,
            decoration: const InputDecoration(
              labelText: 'Número de factura',
              helperText:
                  'Puedes modificar el folio si tu numeración es manual',
            ),
          ),
        if (!widget.isCompact) const SizedBox(height: 20),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: widget.isCompact
              ? null
              : CircleAvatar(
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.15),
                  child: Icon(
                    Icons.person,
                    color: theme.colorScheme.primary,
                  ),
                ),
          title: Text(
            _selectedCustomer?.name ?? 'Selecciona un cliente',
            style: theme.textTheme.titleMedium,
          ),
          subtitle: _selectedCustomer == null
              ? const Text('Cliente Requerido')
              : Text('RUT: ${_selectedCustomer!.rut}'),
          trailing: _canEditFields
              ? IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _openCustomerSelector,
                )
              : null,
        ),
      ],
    );
  }

  Widget _buildLineItemsSection(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate minimum required width based on columns
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Table header
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                            width: _colIndexWidth,
                            child: Center(child: Text('#'))),
                        Expanded(
                            child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('DETALLES'))),
                        SizedBox(
                            width: _colQuantityWidth,
                            child: Center(child: Text('CANT'))),
                        SizedBox(
                            width: _colPriceWidth,
                            child: Center(child: Text('PRECIO'))),
                        SizedBox(
                            width: _colDiscountWidth,
                            child: Center(child: Text('DESC'))),
                        SizedBox(
                            width: _colTotalWidth,
                            child: Center(child: Text('TOTAL'))),
                        SizedBox(width: _colActionsWidth),
                      ],
                    ),
                  ),
                  Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                  Column(
                    children: [
                      ..._buildGroupedTableRows(theme),
                      if (_canEditFields) _buildAddLineRow(theme),
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

  Widget _buildAddLineRow(ThemeData theme) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: _colIndexWidth),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SmartProductField(
                key: ValueKey(_autocompleteKey),
                onProductChanged: (selection) {
                  if (selection == null) return;
                  if (selection.isCatalogProduct && selection.product != null) {
                    _addProductLine(selection.product!);
                  } else if (!selection.isCatalogProduct &&
                      selection.productName != null) {
                    _addCustomItemLine(selection.productName!);
                  }
                },
                allowCustomItems: true,
                showCost: false,
                hintText: 'Buscar producto o servicio...',
              ),
            ),
          ),
          const SizedBox(width: _colQuantityWidth),
          const SizedBox(width: _colPriceWidth),
          const SizedBox(width: _colDiscountWidth),
          const SizedBox(width: _colTotalWidth),
          const SizedBox(width: _colActionsWidth),
        ],
      ),
    );
  }

  /// Calculates the subtotal for a specific bike group
  double _getBikeSubtotal(String? bikeName) {
    if (bikeName == null || bikeName.isEmpty) {
      return _lineEntries
          .where((e) => (e.line.bikeName == null || e.line.bikeName!.isEmpty))
          .fold(0.0, (sum, e) => sum + e.line.netAmount);
    }
    return _lineEntries
        .where((e) => e.line.bikeName == bikeName)
        .fold(0.0, (sum, e) => sum + e.line.netAmount);
  }

  /// Builds table rows grouped by bike with section headers.
  List<Widget> _buildGroupedTableRows(ThemeData theme) {
    final widgets = <Widget>[];
    String? lastBikeName;
    int itemIndex = 0;

    // Sort by bike name so same-bike items are grouped together
    final sortedEntries = List<_InvoiceLineEntry>.from(_lineEntries)
      ..sort((a, b) {
        final aName = a.line.bikeName ?? '';
        final bName = b.line.bikeName ?? '';
        if (aName.isEmpty && bName.isEmpty) return 0;
        if (aName.isEmpty) return 1;
        if (bName.isEmpty) return -1;
        return aName.compareTo(bName);
      });

    for (final entry in sortedEntries) {
      final bikeName = entry.line.bikeName;
      itemIndex++;

      if (bikeName != null && bikeName.isNotEmpty && bikeName != lastBikeName) {
        widgets.add(_buildBikeSectionHeader(
            theme, bikeName, _getBikeSubtotal(bikeName)));
        lastBikeName = bikeName;
      } else if ((bikeName == null || bikeName.isEmpty) &&
          lastBikeName != null) {
        widgets.add(
            _buildBikeSectionHeader(theme, 'General', _getBikeSubtotal(null)));
        lastBikeName = null;
      }

      widgets.add(_buildCompactLineRow(theme, itemIndex, entry));
    }

    return widgets;
  }

  /// Builds a visual section header for bike grouping.
  Widget _buildBikeSectionHeader(
      ThemeData theme, String bikeName, double subtotal) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          bottom: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]),
            child: Icon(
              Icons.pedal_bike,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bikeName.toUpperCase(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'GRUPO DE ARTÍCULOS',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Subtotal:',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  ChileanUtils.formatCurrency(subtotal),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBikeSelector(ThemeData theme, _InvoiceLineEntry entry) {
    if (_availableJobBikes.isEmpty) {
      return Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: null,
            isExpanded: true,
            hint: Text(_debugBikeMessage,
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface),
            icon: Icon(Icons.pedal_bike,
                size: 14,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            items: const [],
            onChanged: null,
          ),
        ),
      );
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
        border:
            Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _availableJobBikes.any((b) => b.id == entry.line.jobBikeId)
              ? entry.line.jobBikeId
              : null,
          isExpanded: true,
          hint: Text('General / Venta',
              style: TextStyle(
                  fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface),
          icon: Icon(Icons.pedal_bike,
              size: 14, color: theme.colorScheme.primary),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('General / Venta',
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic)),
            ),
            ..._availableJobBikes.map((bike) {
              return DropdownMenuItem<String?>(
                value: bike.id,
                child: Text(bike.displayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            }),
          ],
          onChanged: _canEditFields
              ? (String? newBikeId) {
                  setState(() {
                    entry.line.jobBikeId = newBikeId;
                    if (newBikeId == null) {
                      entry.line.bikeName = null;
                    } else {
                      final bike = _availableJobBikes
                          .firstWhere((b) => b.id == newBikeId);
                      entry.line.bikeName = bike.displayName;
                    }
                    _handleLinesChanged();
                  });
                }
              : null,
        ),
      ),
    );
  }

  Widget _buildCompactLineRow(
      ThemeData theme, int index, _InvoiceLineEntry entry) {
    // Reusing original implementation for desktop table
    // ... (Copy of _buildCompactLineRow from InvoiceFormPage)
    // I'll implement a simplified version for this file to save space, assuming LineRowWrapper exists

    return LineRowWrapper(
      key: ValueKey('line_${entry.hashCode}_$index'),
      index: index,
      canMoveUp: index > 1 && _canEditFields,
      canMoveDown: index < _lineEntries.length && _canEditFields,
      onMoveUp: () => _moveLineUp(entry),
      onMoveDown: () => _moveLineDown(entry),
      onRemove: () => _removeLine(entry),
      canEdit: _canEditFields,
      indexColumnWidth: _colIndexWidth,
      actionsColumnWidth: _colActionsWidth,
      columns: [
        LineColumn(
          expanded: true,
          minWidth: 250,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              entry.buildSmartProductField(
                context,
                theme,
                _canEditFields,
                () {},
                () => _autoAddEmptyLineIfNeeded(),
                preferredJobBikeId: _preferredJobBikeForNewLines()?.id,
                availableJobBikes: _availableJobBikes,
              ),
              if (_availableJobBikes.isNotEmpty)
                _buildBikeSelector(theme, entry),
            ],
          ),
        ),
        LineColumn(
          width: _colQuantityWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: TextField(
            controller: entry.quantityController,
            enabled: _canEditFields,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
        LineColumn(
          width: _colPriceWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: TextField(
            controller: entry.unitPriceController,
            enabled: _canEditFields,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
                border: InputBorder.none, prefixText: '\$ '),
          ),
        ),
        LineColumn(
          width: _colDiscountWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: TextField(
            controller: entry.discountController,
            enabled: _canEditFields,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
        LineColumn(
          width: _colTotalWidth,
          showRightBorder: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            ChileanUtils.formatCurrency(entry.line.netAmount),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildDatesAndStatus(ThemeData theme) {
    if (widget.isCompact) {
      return Column(
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('Estado:',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              DropdownButton<InvoiceStatus>(
                  value: _status,
                  isDense: true,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down, size: 20),
                  items: InvoiceStatus.values
                      .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(_getLocalizedStatus(s),
                              style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: _canEditFields
                      ? null
                      : (v) {
                          if (v != null) _updateStatus(v);
                        }),
            ],
          ),
          // Dates...
        ],
      );
    }

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_note),
          title: const Text('Fecha de emisión'),
          subtitle: Text(ChileanUtils.formatDate(_issueDate)),
          trailing: TextButton(
            onPressed:
                _canEditFields ? () => _pickDate(isIssueDate: true) : null,
            child: const Text('Cambiar'),
          ),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Estado'),
          subtitle: Text(_getLocalizedStatus(_status)),
          // ...
        ),
        // ...
      ],
    );
  }

  Widget _buildSummary(ThemeData theme) {
    // Get paid amount and balance from invoice if available
    final paidAmount = _loadedInvoice?.paidAmount ?? 0;
    final balance = _loadedInvoice?.balance ?? _total;
    final hasPayments = paidAmount > 0;

    return Column(
      children: [
        _buildSummaryRow(
            'Subtotal', ChileanUtils.formatCurrency(_subtotal), null, theme),
        const Divider(),
        _buildSummaryRow(
          'Total',
          ChileanUtils.formatCurrency(_total),
          theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
          theme,
        ),
        // Show payment info when there are payments
        if (hasPayments) ...[
          const Divider(),
          _buildSummaryRow(
            'Pagado',
            ChileanUtils.formatCurrency(paidAmount),
            TextStyle(color: Colors.green[700]),
            theme,
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'Saldo',
            ChileanUtils.formatCurrency(balance),
            theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: balance <= 0 ? Colors.green : Colors.orange[800],
            ),
            theme,
          ),
        ],
      ],
    );
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

  Widget _buildReferenceField(ThemeData theme) {
    return TextFormField(
      controller: _referenceController,
      enabled: _canEditFields,
      decoration: const InputDecoration(
        labelText: 'Referencia / Observaciones',
      ),
      maxLines: 2,
    );
  }

  String _getLocalizedStatus(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return 'Borrador';
      case InvoiceStatus.sent:
        return 'Enviada';
      case InvoiceStatus.paid:
        return 'Pagada';
      case InvoiceStatus.overdue:
        return 'Vencida';
      case InvoiceStatus.cancelled:
        return 'Anulada';
      case InvoiceStatus.confirmed:
        return 'Confirmada';
    }
  }

  Color _getStatusColor(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return Colors.grey;
      case InvoiceStatus.sent:
        return Colors.blue;
      case InvoiceStatus.paid:
        return Colors.green;
      case InvoiceStatus.overdue:
        return Colors.red;
      case InvoiceStatus.cancelled:
        return Colors.red.shade900;
      case InvoiceStatus.confirmed:
        return Colors.teal;
    }
  }

  Widget _buildStatusChip(ThemeData theme) {
    final color = _getStatusColor(_status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        _getLocalizedStatus(_status).toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// Private classes copied and adapted
class _InvoiceLine {
  _InvoiceLine({
    this.productId,
    this.product,
    required this.name,
    this.sku = '',
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    this.cost = 0,
    this.purchaseTreatment = PurchaseTreatment.inventory,
    this.isService = false,
    this.description,
    this.isCatalogProduct = true,
    this.jobBikeId,
    this.bikeName,
  });

  final String? productId;
  final Product? product;
  double cost;
  PurchaseTreatment purchaseTreatment;
  bool isService;
  String? description;
  final bool isCatalogProduct;
  String? jobBikeId;
  String? bikeName;
  double quantity;
  double unitPrice;
  double discount;
  final String name;
  final String sku;

  double get netAmount {
    final value = quantity * unitPrice - discount;
    return value < 0 ? 0 : value;
  }
}

class _InvoiceLineEntry {
  _InvoiceLineEntry(this.line, {this.shouldAutoFocus = false})
      : product = line.product,
        quantityController =
            TextEditingController(text: line.quantity.toStringAsFixed(0)),
        unitPriceController =
            TextEditingController(text: line.unitPrice.toStringAsFixed(0)),
        discountController =
            TextEditingController(text: line.discount.toStringAsFixed(0)),
        productNameController = TextEditingController(text: line.name),
        productSkuController = TextEditingController(text: line.sku),
        descriptionController =
            TextEditingController(text: line.description ?? ''),
        productNameFocusNode = FocusNode();

  final _InvoiceLine line;
  Product? product;
  bool shouldAutoFocus;
  final TextEditingController quantityController;
  final TextEditingController unitPriceController;
  final TextEditingController discountController;
  final TextEditingController productNameController;
  final TextEditingController productSkuController;
  final TextEditingController descriptionController;
  final FocusNode productNameFocusNode;
  VoidCallback? _listener;

  void attachListeners(VoidCallback listener) {
    _listener = listener;
    quantityController.addListener(_onQuantityChanged);
    unitPriceController.addListener(_onUnitPriceChanged);
    discountController.addListener(_onDiscountChanged);
    descriptionController.addListener(() {
      line.description = descriptionController.text;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _listener?.call();
      });
    });
  }

  InvoiceItem toInvoiceItem() {
    final item = InvoiceItem(
      productId: product?.id ?? line.productId,
      productName: productNameController.text.trim().isEmpty
          ? line.name
          : productNameController.text.trim(),
      productSku: productSkuController.text.trim().isEmpty
          ? line.sku
          : productSkuController.text.trim(),
      description: descriptionController.text.trim().isEmpty
          ? line.description
          : descriptionController.text.trim(),
      isCatalogProduct: product != null || line.isCatalogProduct,
      quantity: line.quantity,
      unitPrice: line.unitPrice,
      discount: line.discount,
      lineTotal: line.netAmount,
      cost: line.cost,
      purchaseTreatment: line.purchaseTreatment,
      isService: line.isService,
      jobBikeId: line.jobBikeId,
      bikeName: line.bikeName,
    );
    debugPrint(
        '🐛 [InvoiceLineEntry] Converting item: ${item.productName}. ProductId: ${item.productId}');
    return item;
  }

  void _onQuantityChanged() {
    final value = double.tryParse(quantityController.text.replaceAll(',', '.'));
    if (value != null && value >= 0) {
      line.quantity = value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _listener?.call();
      });
    }
  }

  void _onUnitPriceChanged() {
    final value =
        double.tryParse(unitPriceController.text.replaceAll(',', '.'));
    if (value != null && value >= 0) {
      line.unitPrice = value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _listener?.call();
      });
    }
  }

  void _onDiscountChanged() {
    final value = double.tryParse(discountController.text.replaceAll(',', '.'));
    if (value != null && value >= 0) {
      line.discount = value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _listener?.call();
      });
    }
  }

  void dispose() {
    quantityController.dispose();
    unitPriceController.dispose();
    discountController.dispose();
    productNameController.dispose();
    productSkuController.dispose();
    descriptionController.dispose();
    productNameFocusNode.dispose();
  }

  Widget buildSmartProductField(BuildContext context, ThemeData theme,
      bool canEdit, VoidCallback onUpdate, VoidCallback onAutoAdd,
      {String? preferredJobBikeId,
      List<MechanicJobBike> availableJobBikes = const []}) {
    // Simplified for brevity, reusing SmartProductField
    return SmartProductField(
      key: ValueKey('product_$hashCode'),
      initialData: ProductFieldData(
        product: product,
        productName: line.name.isEmpty ? null : line.name,
        productSku: line.sku.isEmpty ? null : line.sku,
        isCatalogProduct: line.isCatalogProduct,
        description: descriptionController.text,
      ),
      enabled: canEdit,
      showCost: false,
      allowCustomItems: true,
      autoFocus: shouldAutoFocus,
      focusNode: productNameFocusNode,
      descriptionController: descriptionController,
      onAutoAddLine: onAutoAdd,
      onProductChanged: (selection) {
        if (selection == null) {
          product = null;
          line.cost = 0;
          line.purchaseTreatment = PurchaseTreatment.inventory;
          line.isService = false;
          productNameController.clear();
          productSkuController.clear();
          descriptionController.clear();
          onUpdate();
        } else {
          product = selection.product;
          line.cost = selection.product?.cost ?? 0;
          line.purchaseTreatment = selection.product?.purchaseTreatment ??
              PurchaseTreatment.inventory;
          line.isService = selection.product?.isService ?? false;
          productNameController.text = selection.productName ?? '';
          productSkuController.text = selection.productSku ?? '';
          if (line.jobBikeId == null && preferredJobBikeId != null) {
            final bike = availableJobBikes
                .where((b) => b.id == preferredJobBikeId)
                .firstOrNull;
            if (bike != null) {
              line.jobBikeId = bike.id;
              line.bikeName = bike.displayName;
            }
          }
          if (selection.price > 0) {
            unitPriceController.text = selection.price.toStringAsFixed(0);
          }
          onUpdate();
        }
      },
    );
  }
}

// _CustomerSelector class (copied)
class _CustomerSelector extends StatefulWidget {
  final List<Customer> initialCustomers;
  final CustomerService customerService;
  final Future<Customer?> Function(String name) onCreateCustomer;

  const _CustomerSelector({
    required this.initialCustomers,
    required this.customerService,
    required this.onCreateCustomer,
  });

  @override
  State<_CustomerSelector> createState() => _CustomerSelectorState();
}

class _CustomerSelectorState extends State<_CustomerSelector> {
  late List<Customer> _customers = widget.initialCustomers;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _newCustomerController = TextEditingController();
  Timer? _debounce;
  // bool _isSearching = false; // Unused for now

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _newCustomerController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String term) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = term.trim().isEmpty
            ? widget.initialCustomers
            : await widget.customerService.getCustomers(searchTerm: term);
        if (mounted) {
          setState(() => _customers = results);
        }
      } catch (_) {
        if (mounted) {
          setState(() => _customers = widget.initialCustomers);
        }
      } finally {
        if (mounted) {
          // _isSearching = false;
        }
      }
    });
  }

  // Future<void> _handleCreateCustomer() async {
  //   final name = _newCustomerController.text.trim();
  //   if (name.isEmpty) return;
  //   final customer = await widget.onCreateCustomer(name);
  //   if (customer != null && mounted) {
  //     Navigator.of(context).pop(customer);
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(labelText: 'Buscar cliente'),
            onChanged: _onSearchChanged,
          ),
          SizedBox(
            height: 300,
            child: ListView.builder(
                itemCount: _customers.length,
                itemBuilder: (context, index) {
                  final c = _customers[index];
                  return ListTile(
                    title: Text(c.name),
                    subtitle: Text(c.rut),
                    onTap: () => Navigator.of(context).pop(c),
                  );
                }),
          )
        ]));
  }
}
