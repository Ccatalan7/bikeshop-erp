import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/services/database_service.dart';
import '../../../shared/services/number_generation_service.dart';
import '../../../shared/services/remote_scanner_service.dart';
import '../../../shared/services/barcode_scanner_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/smart_product_field.dart';
import '../../../shared/widgets/line_row_wrapper.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../inventory/pages/product_form_page.dart';
import '../../messaging/widgets/entity_chat_sidebar.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data' show Uint8List;
import 'package:file_picker/file_picker.dart';
import 'dart:io' show Platform, File;

import '../../settings/services/appearance_service.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';
import '../../../shared/services/whatsapp_service.dart';

/// The main, full-screen page for creating and editing sales invoices.
///
/// **Usage Context:**
/// This page is used for the dedicated `/sales/invoices/new` and `/sales/invoices/:id`
/// routes. It provides the complete, expansive UI for managing an invoice.
///
/// **Important Note for Developers/AI:**
/// If you are modifying the invoice form UI or core logic, you MUST apply the
/// SAME changes to the embeddable version of this form located at
/// `lib/modules/sales/widgets/sales_invoice_editor.dart`, which is used
/// in side-panels and quick-edit views like the Calendar.
class InvoiceFormPage extends StatefulWidget {
  final String? invoiceId;
  final String? preselectedJobId;
  final String? preselectedCustomerId;

  const InvoiceFormPage({
    super.key,
    this.invoiceId,
    this.preselectedJobId,
    this.preselectedCustomerId,
    this.referrer,
    this.referrerJobId,
  });

  final String? referrer;
  final String? referrerJobId;

  @override
  State<InvoiceFormPage> createState() => _InvoiceFormPageState();
}

class _InvoiceFormPageState extends State<InvoiceFormPage> {
  // Column widths for table alignment
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

  late SalesService _salesService;
  late CustomerService _customerService;
  late shared_inventory.InventoryService _inventoryService;
  bool _salesServiceListenerAttached = false;

  final List<Customer> _cachedCustomers = [];
  final List<Product> _cachedProducts = [];
  final List<_InvoiceLineEntry> _lineEntries = [];
  final List<MechanicJobBike> _availableJobBikes = [];
  String? _defaultJobBikeId; // Global default bike for new line items
  String _debugBikeMessage = 'DEBUG: Init state';
  String? _linkedJobId;
  String? _linkedJobNumber;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  bool _isUpdatingStatus = false;

  // Key to reset autocomplete field after adding product
  int _autocompleteKey = 0;

  Customer? _selectedCustomer;
  Invoice? _loadedInvoice;
  DateTime _issueDate = DateTime.now();
  DateTime? _dueDate;
  InvoiceStatus _status = InvoiceStatus.draft;
  TaxTreatment _taxTreatment =
      TaxTreatment.noTax; // Default: no tax (cash/transfer common)
  String? _paymentMethodHint; // 'card' or 'other' - for smart tax validation

  String? get _currentInvoiceId => _loadedInvoice?.id ?? widget.invoiceId;
  bool get _canEditFields => _status != InvoiceStatus.paid && _isEditing;
  bool get _canMarkAsSent =>
      _currentInvoiceId != null &&
      _status == InvoiceStatus.draft &&
      !_isEditing;
  double get _outstandingAmount {
    final paid = _loadedInvoice?.paidAmount ?? 0;
    final total = _loadedInvoice?.total ?? _total;
    return (total - paid).clamp(0, double.infinity);
  }

  bool get _canRegisterPayment =>
      _currentInvoiceId != null &&
      (_status == InvoiceStatus.sent || _status == InvoiceStatus.confirmed) &&
      _outstandingAmount > 0.01;
  bool get _shouldShowReadOnlyNotice =>
      !_canEditFields && _status != InvoiceStatus.paid;
  String get _invoiceChatTitle {
    final invoiceNumber = _loadedInvoice?.invoiceNumber;
    if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
      return 'Factura #$invoiceNumber';
    }

    final invoiceId = _currentInvoiceId;
    if (invoiceId != null && invoiceId.length >= 6) {
      return 'Factura #${invoiceId.substring(0, 6)}';
    }

    return 'Factura';
  }

  StreamSubscription? _scanSubscription;
  final _remoteScannerService = RemoteScannerService();
  bool _scannerEnabled = false;

  // Hardware keyboard scanner state (for USB/Bluetooth barcode scanners)
  final StringBuffer _scanBuffer = StringBuffer();
  Timer? _hwScanTimer;
  DateTime? _lastScanKeyTime;
  static const Duration _scanKeyTimeout = Duration(milliseconds: 100);
  static const int _minBarcodeLen = 3;

  @override
  void initState() {
    super.initState();
    debugPrint(
        '🔍 InvoiceFormPage initState - referrer: ${widget.referrer}, jobId: ${widget.referrerJobId}');
    _isEditing = widget.invoiceId == null;
    _dueDate = _issueDate.add(const Duration(days: 30));
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());

    // Listen for barcode scans
    _scanSubscription = _remoteScannerService.scanStream.listen((scan) {
      if (mounted && _canEditFields) {
        _handleBarcodeScan(scan.barcode);
      }
    });
  }

  @override
  void dispose() {
    if (_salesServiceListenerAttached) {
      _salesService.removeListener(_handleSalesServiceChanged);
    }
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
          if (mounted && _canEditFields) _handleBarcodeScan(barcode);
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
    final product = _cachedProducts.cast<Product?>().firstWhere(
          (p) =>
              p!.sku.toLowerCase() == barcode.toLowerCase() ||
              (p.barcode?.toLowerCase() == barcode.toLowerCase()),
          orElse: () => null,
        );

    if (product != null) {
      // Check if product is already in the invoice
      final existingLineIndex = _lineEntries.indexWhere(
        (entry) => entry.line.product?.id == product.id,
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
              content: Text('✅ Cantidad aumentada: ${product.name}'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        // Add as new line - simplified approach
        setState(() {
          final newLine = _InvoiceLine(
            productId: product.id,
            product: product,
            name: product.name,
            sku: product.sku,
            quantity: 1,
            unitPrice: product.price,
            discount: 0,
            cost: product.cost,
          );
          final newEntry = _InvoiceLineEntry(newLine);
          newEntry.attachListeners(() {
            setState(() {});
          });
          _lineEntries.add(newEntry);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Producto agregado: ${product.name}'),
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
    _salesService = context.read<SalesService>();
    if (!_salesServiceListenerAttached) {
      _salesService.addListener(_handleSalesServiceChanged);
      _salesServiceListenerAttached = true;
    }
    _customerService = context.read<CustomerService>();
    _inventoryService = context.read<shared_inventory.InventoryService>();

    try {
      // Don't force refresh - use cached data if available for faster loading
      // Don't force refresh - use cached data if available for faster loading
      final futures = <Future<dynamic>>[
        _customerService.getCustomers(),
        _inventoryService.getProducts(forceRefresh: false),
      ];

      // Also fetch preview number in parallel if this is a new invoice
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

      // Handle preview number if loaded
      if (widget.invoiceId == null && results.length > 2) {
        _invoiceNumberController.text = results[2] as String;
      }

      if (widget.invoiceId != null) {
        debugPrint(
          '🔄 [InvoiceFormPage] _initialize fetching existing invoice | invoiceId=${widget.invoiceId}',
        );
        final invoice =
            await _salesService.fetchInvoice(widget.invoiceId!, refresh: true);
        if (invoice != null) {
          debugPrint(
            '✅ [InvoiceFormPage] _initialize fetched invoice | id=${invoice.id} | itemCount=${invoice.items.length} | subtotal=${invoice.subtotal} | total=${invoice.total}',
          );
          _loadedInvoice = invoice;
          _applyInvoice(invoice);
        } else {
          debugPrint(
            '⚠️ [InvoiceFormPage] _initialize fetch returned null | invoiceId=${widget.invoiceId}',
          );
        }
      } else {
        if (_invoiceNumberController.text.isEmpty) {
          _invoiceNumberController.text = await _previewInvoiceNumber();
        }

        // Preselect customer if coming from a job
        if (widget.preselectedJobId != null) {
          await _loadJobAndPreselectCustomer(widget.preselectedJobId!);
        } else if (widget.preselectedCustomerId != null) {
          _preselectCustomer(widget.preselectedCustomerId!);
        }
      }

      // Check if this invoice is linked to a job, to load bikes
      // This MUST run outside the above blocks to catch existing invoices too!
      final db = Provider.of<DatabaseService>(context, listen: false);
      try {
        if (widget.invoiceId != null) {
          _debugBikeMessage =
              'DEBUG: Querying mechanic_jobs for existing invoice ${widget.invoiceId}';
          final jobDataList = await db.supabase
              .from('mechanic_jobs')
              .select('id, job_number')
              .eq('invoice_id', widget.invoiceId!)
              .limit(1);

          if (jobDataList.isNotEmpty) {
            final jobId = jobDataList.first['id'] as String;
            _linkedJobId = jobId;
            _linkedJobNumber = jobDataList.first['job_number']?.toString();
            _debugBikeMessage =
                'DEBUG: Found job $jobId for existing invoice, loading bikes...';
            await _loadJobBikes(jobId);
          } else if (_loadedInvoice != null) {
            _debugBikeMessage =
                'DEBUG: No direct job link for existing invoice, trying fallback...';
            bool foundFallback = false;
            for (final item in _loadedInvoice!.items) {
              if (item.jobBikeId != null && item.jobBikeId!.isNotEmpty) {
                _debugBikeMessage =
                    'DEBUG: Fallback found jobBikeId ${item.jobBikeId}';
                final bikeData = await db.supabase
                    .from('mechanic_job_bikes')
                    .select('job_id')
                    .eq('id', item.jobBikeId!)
                    .maybeSingle();
                if (bikeData != null && bikeData['job_id'] != null) {
                  final jobId = bikeData['job_id'] as String;
                  _linkedJobId = jobId;
                  try {
                    final linkedJobData =
                        await db.selectById('mechanic_jobs', jobId);
                    _linkedJobNumber = linkedJobData?['job_number']?.toString();
                  } catch (_) {}
                  _debugBikeMessage =
                      'DEBUG: Fallback resolved job $jobId, calling load';
                  await _loadJobBikes(jobId);
                  foundFallback = true;
                  break;
                }
              }
            }
            if (!foundFallback) {
              _debugBikeMessage =
                  'DEBUG: Existing invoice fallback exhausted without finding job_id';
            }
          }
        } else if (widget.preselectedJobId != null) {
          _linkedJobId = widget.preselectedJobId;
          try {
            final linkedJob = await context
                .read<BikeshopService>()
                .getJobById(widget.preselectedJobId!);
            _linkedJobNumber = linkedJob?.jobNumber;
          } catch (_) {}
          _debugBikeMessage =
              'DEBUG: New invoice from job ${widget.preselectedJobId}, loading bikes...';
          await _loadJobBikes(widget.preselectedJobId!);
        }
      } catch (e) {
        debugPrint('Error loading job for invoice id: $e');
        _debugBikeMessage = 'DEBUG: Catch block $e';
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

    debugPrint(
      '🧩 [InvoiceFormPage] _applyInvoice | id=${invoice.id ?? 'null'} | itemCount=${invoice.items.length} | subtotal=${invoice.subtotal} | total=${invoice.total} | customerId=${invoice.customerId ?? 'null'}',
    );
    for (var i = 0; i < invoice.items.length; i++) {
      final item = invoice.items[i];
      debugPrint(
        '   ↳ applyItem[$i] productId=${item.productId ?? 'null'} | name="${item.productName}" | qty=${item.quantity} | unit=${item.unitPrice} | total=${item.lineTotal} | jobBikeId=${item.jobBikeId ?? 'null'}',
      );
    }

    _invoiceNumberController.text = invoice.invoiceNumber.isNotEmpty
        ? invoice.invoiceNumber
        : _buildSuggestedNumber(); // Keep old fallback for existing invoices
    _referenceController.text = invoice.reference ?? '';

    Customer? resolvedCustomer;
    if (invoice.customerId != null) {
      resolvedCustomer = _cachedCustomers.firstWhere(
        (customer) => customer.id == invoice.customerId,
        orElse: () => Customer(
          id: invoice.customerId,
          tenantId: '', // Display-only fallback
          name: invoice.customerName ?? 'Cliente',
          rut: invoice.customerRut ?? '',
          email: null,
        ),
      );
    }

    final newEntries = <_InvoiceLineEntry>[];
    for (final item in invoice.items) {
      Product? product;
      // Only look for product if it's a catalog item
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
          productId: item.productId, // Nullable - null for ad-hoc items
          product: product,
          name: item.productName ?? product?.name ?? 'Artículo',
          sku: item.productSku ?? product?.sku ?? '',
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          discount: item.discount,
          cost: item.cost,
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

  void _handleSalesServiceChanged() {
    if (!mounted || _isEditing || _isSaving || _isUpdatingStatus) {
      return;
    }

    final invoiceId = _currentInvoiceId;
    if (invoiceId == null || invoiceId.isEmpty) {
      return;
    }

    Invoice? serviceInvoice;
    for (final candidate in _salesService.invoices) {
      if (candidate.id == invoiceId) {
        serviceInvoice = candidate;
        break;
      }
    }

    if (serviceInvoice == null) {
      return;
    }

    final currentInvoice = _loadedInvoice;
    final hasChanged = currentInvoice == null ||
        serviceInvoice.updatedAt.isAfter(currentInvoice.updatedAt) ||
        serviceInvoice.status != currentInvoice.status ||
        serviceInvoice.paidAmount != currentInvoice.paidAmount ||
        serviceInvoice.balance != currentInvoice.balance ||
        serviceInvoice.total != currentInvoice.total;

    if (!hasChanged) {
      return;
    }

    debugPrint(
      '🔄 [InvoiceFormPage] SalesService pushed invoice update | id=$invoiceId | '
      'status=${serviceInvoice.status.name} | paid=${serviceInvoice.paidAmount} | '
      'balance=${serviceInvoice.balance}',
    );
    _applyInvoice(serviceInvoice);
  }

  String _buildSuggestedNumber() {
    // Deprecated: Use NumberGenerationService instead
    // This fallback should rarely be used
    final now = DateTime.now();
    final datePortion =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timePortion = now.millisecondsSinceEpoch.toString().substring(7);
    return 'FV-$datePortion-$timePortion';
  }

  /// Preview what the next invoice number will be (doesn't increment counter)
  /// Used when entering form - actual number assigned only on save
  Future<String> _previewInvoiceNumber() async {
    try {
      final numberService = NumberGenerationService();
      return await numberService.previewSalesInvoiceNumber();
    } catch (e) {
      if (kDebugMode) print('Error previewing invoice number: $e');
      return _buildSuggestedNumber(); // Fallback to old method
    }
  }

  /// Generate the actual invoice number (increments counter)
  /// Used only when actually SAVING a new invoice
  Future<String> _generateInvoiceNumber() async {
    try {
      final numberService = NumberGenerationService();
      return await numberService.nextSalesInvoiceNumber();
    } catch (e) {
      if (kDebugMode) print('Error generating invoice number: $e');
      return _buildSuggestedNumber(); // Fallback to old method
    }
  }

  Future<void> _loadJobAndPreselectCustomer(String jobId) async {
    try {
      // Get database service from context
      final db = Provider.of<DatabaseService>(context, listen: false);
      final jobData = await db.selectById('mechanic_jobs', jobId);

      if (jobData != null) {
        final customerId = jobData['customer_id'] as String?;
        if (customerId != null) {
          _preselectCustomer(customerId);

          // Set reference to job number
          final jobNumber = jobData['job_number'] as String?;
          if (jobNumber != null) {
            _referenceController.text = 'Pega $jobNumber';
          }
          await _loadJobBikes(jobId);
        }
      }
    } catch (e) {
      debugPrint('Error loading job for invoice: $e');
    }
  }

  Future<void> _loadJobBikes(String jobId) async {
    try {
      final bikeshopService = context.read<BikeshopService>();
      _debugBikeMessage = 'DEBUG: Fetching bikes for $jobId';
      final bikes = await bikeshopService.getJobBikes(jobId);
      if (mounted) {
        setState(() {
          _debugBikeMessage =
              'DEBUG: Loaded ${bikes.length} bikes from getJobBikes';
          _availableJobBikes.clear();
          _availableJobBikes.addAll(bikes);
        });
      } else {
        _debugBikeMessage = 'DEBUG: Widget not mounted after getJobBikes';
      }
    } catch (e) {
      debugPrint('Error loading bikes for job: $e');
      if (mounted) {
        setState(() {
          _debugBikeMessage = 'DEBUG: Catch getJobBikes $e';
        });
      }
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
      setState(() {});
    }
  }

  void _startEditing() {
    if (_status == InvoiceStatus.paid) return;
    setState(() => _isEditing = true);
  }

  void _cancelEditing() {
    if (!_isEditing) return;
    if (_loadedInvoice != null) {
      _applyInvoice(_loadedInvoice!);
    } else if (mounted) {
      setState(() => _isEditing = false);
    }
  }

  Future<void> _refreshInvoiceById(String invoiceId) async {
    debugPrint(
        '🔁 [InvoiceFormPage] _refreshInvoiceById start | invoiceId=$invoiceId');
    final refreshed =
        await _salesService.fetchInvoice(invoiceId, refresh: true);
    if (refreshed != null && mounted) {
      debugPrint(
        '✅ [InvoiceFormPage] _refreshInvoiceById fetched | id=${refreshed.id} | itemCount=${refreshed.items.length} | subtotal=${refreshed.subtotal} | total=${refreshed.total}',
      );
      _applyInvoice(refreshed);
    } else {
      debugPrint(
        '⚠️ [InvoiceFormPage] _refreshInvoiceById got null or widget unmounted | invoiceId=$invoiceId',
      );
    }
  }

  Future<void> _updateStatus(InvoiceStatus newStatus) async {
    await _updateStatusInternal(newStatus, showFeedback: true);
  }

  Future<bool> _updateStatusInternal(
    InvoiceStatus newStatus, {
    required bool showFeedback,
  }) async {
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
      return false;
    }

    // ⚠️ Smart validation: If paying with card but no tax → auto-fix
    if (newStatus == InvoiceStatus.confirmed &&
        _paymentMethodHint == 'card' &&
        _taxTreatment == TaxTreatment.noTax) {
      // Auto-add tax for card payments
      setState(() => _taxTreatment = TaxTreatment.taxIncluded);
      await _saveInvoice();
      if (!mounted) return false;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    setState(() => _isUpdatingStatus = true);
    try {
      final updated =
          await _salesService.updateInvoiceStatus(invoiceId, newStatus);
      if (updated != null && mounted) {
        _applyInvoice(updated);
        await _refreshInvoiceById(invoiceId);
      } else if (mounted) {
        await _refreshInvoiceById(invoiceId);
      }

      // Safety net: ensure invoice JE exists after confirming.
      // Idempotent — no-op if trigger already created it.
      // Needed because deployed trigger didn't handle draft→confirmed.
      if (newStatus == InvoiceStatus.confirmed ||
          newStatus == InvoiceStatus.paid) {
        try {
          await Supabase.instance.client.rpc(
            'ensure_sales_invoice_journal_entry',
            params: {'p_invoice_id': invoiceId},
          );
        } catch (_) {}
      }
      if (mounted && showFeedback) {
        String message = 'Estado actualizado';
        switch (newStatus) {
          case InvoiceStatus.draft:
            message = 'Factura devuelta a borrador';
            break;
          case InvoiceStatus.sent:
            message = 'Factura marcada como enviada';
            break;
          case InvoiceStatus.confirmed:
            message = 'Factura confirmada - Stock deducido';
            break;
          case InvoiceStatus.paid:
            message = 'Factura marcada como pagada';
            break;
          case InvoiceStatus.cancelled:
            message = 'Factura cancelada';
            break;
          case InvoiceStatus.overdue:
            message = 'Factura marcada como vencida';
            break;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar el estado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  Future<void> _sendInvoiceToCustomer() async {
    final invoice = _loadedInvoice;
    if (invoice == null || invoice.id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Guarda la factura antes de enviarla al cliente.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final customer = _selectedCustomer;
    final customerPhone = customer?.phone?.trim();
    if (customer == null || customerPhone == null || customerPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'El cliente debe tener un teléfono para enviar la factura.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isUpdatingStatus = true);
    try {
      final whatsappService = WhatsAppService();
      final success = await whatsappService.sendInvoice(
        context: context,
        customerPhone: customerPhone,
        customerName: customer.name,
        invoice: invoice,
      );

      if (!success || !mounted) {
        return;
      }

      final shouldMarkAsSent = _status == InvoiceStatus.draft;
      final markedAsSent = !shouldMarkAsSent ||
          await _updateStatusInternal(
            InvoiceStatus.sent,
            showFeedback: false,
          );

      if (!mounted) {
        return;
      }

      final message = switch (whatsappService.lastDeliveryMethod) {
        WhatsAppDeliveryMethod.cloudApi => markedAsSent
            ? 'Factura enviada por WhatsApp Cloud API y marcada como enviada'
            : 'Factura enviada por WhatsApp Cloud API',
        WhatsAppDeliveryMethod.manualFallback => markedAsSent
            ? 'WhatsApp abierto con la factura lista para enviar y marcada como enviada'
            : 'WhatsApp abierto con la factura lista para enviar',
        WhatsAppDeliveryMethod.failed => 'No se pudo enviar la factura',
      };

      final backgroundColor =
          whatsappService.lastDeliveryMethod == WhatsAppDeliveryMethod.failed
              ? Colors.red
              : Colors.green;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo enviar la factura: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  Future<void> _openPaymentForm() async {
    final invoiceId = _currentInvoiceId;
    if (invoiceId == null) {
      return;
    }

    final didRegisterPayment = await context.push<bool>(
          '/sales/invoices/$invoiceId/payment',
        ) ??
        false;

    if (didRegisterPayment && mounted) {
      await _refreshInvoiceById(invoiceId);
    }
  }

  Future<void> _undoLastPayment() async {
    final invoiceId = _currentInvoiceId;
    if (invoiceId == null) {
      return;
    }

    // Ensure payments are loaded before checking
    await _salesService.loadPayments(invoiceId: invoiceId, forceRefresh: true);

    // Get all payments for this invoice
    final payments = _salesService.getPaymentsForInvoice(invoiceId);
    if (payments.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay pagos para deshacer'),
            backgroundColor: Colors.orange,
          ),
        );
      }
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
          'y su asiento contable asociado. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
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
      await _salesService.deletePayment(lastPayment.id!);
      if (mounted) {
        await _refreshInvoiceById(invoiceId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago eliminado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar el pago: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  double get _subtotal {
    final value = _lineEntries.fold<double>(
        0, (sum, entry) => sum + entry.line.netAmount);
    return value < 0 ? 0 : value;
  }

  // Calculate net, IVA, and total based on tax treatment
  double get _netAmount {
    if (_taxTreatment == TaxTreatment.taxIncluded) {
      // Tax included: net = subtotal ÷ 1.19
      return _subtotal / 1.19;
    } else {
      // No tax: net = full subtotal
      return _subtotal;
    }
  }

  double get _iva {
    if (_taxTreatment == TaxTreatment.taxIncluded) {
      // Tax included: IVA = subtotal - net
      return _subtotal - _netAmount;
    } else {
      // No tax: IVA = 0
      return 0;
    }
  }

  double get _total => _subtotal;

  Future<void> _openCustomerSelector() async {
    if (_cachedCustomers.isEmpty) {
      try {
        final customers = await _customerService.getCustomers();
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
    // Always add as new line (allow duplicates on different lines)
    final line = _InvoiceLine(
      productId: product.id,
      product: product,
      name: product.name,
      sku: product.sku,
      quantity: 1,
      unitPrice: product.price,
      discount: 0,
      cost: product.cost,
      isCatalogProduct: true,
    );

    if (_defaultJobBikeId != null) {
      final bike = _availableJobBikes
          .where((b) => b.id == _defaultJobBikeId)
          .firstOrNull;
      if (bike != null) {
        line.jobBikeId = bike.id;
        line.bikeName = bike.displayName;
      }
    }

    final entry = _InvoiceLineEntry(line);
    entry.attachListeners(_handleLinesChanged);

    setState(() {
      _lineEntries.add(entry);
      _autocompleteKey++; // Reset autocomplete field
    });
  }

  void _addCustomItemLine(String description) {
    final line = _InvoiceLine(
      productId: null, // Ad-hoc items have no product ID
      product: null,
      name: description,
      sku: '',
      quantity: 1,
      unitPrice: 0, // User must enter price manually
      discount: 0,
      cost: 0,
      isCatalogProduct: false,
      description: description,
    );

    if (_defaultJobBikeId != null) {
      final bike = _availableJobBikes
          .where((b) => b.id == _defaultJobBikeId)
          .firstOrNull;
      if (bike != null) {
        line.jobBikeId = bike.id;
        line.bikeName = bike.displayName;
      }
    }

    final entry = _InvoiceLineEntry(line);
    entry.attachListeners(_handleLinesChanged);

    setState(() {
      _lineEntries.add(entry);
      _autocompleteKey++; // Reset autocomplete field
    });
  }

  void _autoAddEmptyLineIfNeeded() {
    // Check if the last line has a product selected
    if (_lineEntries.isEmpty) return;

    final lastEntry = _lineEntries.last;
    if (lastEntry.product != null ||
        lastEntry.productNameController.text.isNotEmpty) {
      // Last line is filled, add a new empty line
      final line = _InvoiceLine(
        productId: null,
        product: null,
        name: '',
        sku: '',
        quantity: 1,
        unitPrice: 0,
        discount: 0,
        cost: 0,
        isCatalogProduct: false,
      );

      // Pre-assign the global default bike if one is selected
      if (_defaultJobBikeId != null) {
        final bike = _availableJobBikes
            .where((b) => b.id == _defaultJobBikeId)
            .firstOrNull;
        if (bike != null) {
          line.jobBikeId = bike.id;
          line.bikeName = bike.displayName;
        }
      }

      // Create entry with shouldAutoFocus=true so the product field auto-focuses and shows overlay
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
    debugPrint(
      '💾 [InvoiceFormPage] Save tapped | invoiceId=${widget.invoiceId ?? _loadedInvoice?.id ?? 'NEW'} | lineEntries=${_lineEntries.length} | selectedCustomer=${_selectedCustomer?.id ?? 'null'}',
    );

    if (_selectedCustomer == null) {
      debugPrint('❌ [InvoiceFormPage] Save aborted: no selected customer');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un cliente antes de guardar.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_lineEntries.isEmpty) {
      debugPrint('❌ [InvoiceFormPage] Save aborted: _lineEntries is empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega al menos un producto a la factura.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      debugPrint('❌ [InvoiceFormPage] Save aborted: form validation failed');
      return;
    }

    final customerId = _selectedCustomer!.id;
    if (customerId == null || customerId.isEmpty) {
      debugPrint(
          '❌ [InvoiceFormPage] Save aborted: selected customer id is null/empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('El cliente seleccionado no tiene un identificador válido.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final items = _lineEntries
        .where((entry) => entry.line.quantity > 0 && entry.hasValidProduct)
        .map((entry) => entry.toInvoiceItem())
        .toList();

    debugPrint(
      '🧾 [InvoiceFormPage] Built items from form | originalEntries=${_lineEntries.length} | validItems=${items.length}',
    );
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      debugPrint(
        '   ↳ item[$i] productId=${item.productId ?? 'null'} | name="${item.productName}" | qty=${item.quantity} | unit=${item.unitPrice} | total=${item.lineTotal} | jobBikeId=${item.jobBikeId ?? 'null'}',
      );
    }

    if (items.isEmpty) {
      debugPrint(
          '❌ [InvoiceFormPage] Save aborted: items list is empty after filtering');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay líneas válidas para guardar.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final tenantId = await TenantService().getTenantId();
    if (tenantId == null) {
      debugPrint('❌ [InvoiceFormPage] Save aborted: tenantId is null');
      throw Exception('User does not have a tenant_id. Cannot proceed.');
    }

    debugPrint(
      '🏢 [InvoiceFormPage] Tenant resolved | tenantId=$tenantId | customerId=$customerId | preselectedJobId=${widget.preselectedJobId ?? 'null'} | loadedInvoiceId=${_loadedInvoice?.id ?? 'null'}',
    );

    // For NEW invoices (no ID yet), generate the ACTUAL number now
    // This is when the counter actually increments
    String invoiceNumber = _invoiceNumberController.text.trim();
    if (_loadedInvoice?.id == null && widget.invoiceId == null) {
      invoiceNumber = await _generateInvoiceNumber();
      _invoiceNumberController.text = invoiceNumber;
      debugPrint(
          '🧮 [InvoiceFormPage] Generated new invoice number: $invoiceNumber');
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
      status: InvoiceStatus.draft,
      subtotal: _subtotal,
      ivaAmount: _iva,
      total: _total,
      taxTreatment: _taxTreatment,
      netAmount: _netAmount,
      items: items,
    );

    debugPrint(
      '📦 [InvoiceFormPage] Saving invoice payload | id=${invoice.id ?? 'NEW'} | number=${invoice.invoiceNumber} | subtotal=${invoice.subtotal} | iva=${invoice.ivaAmount} | total=${invoice.total} | itemCount=${invoice.items.length} | status=${invoice.status.name}',
    );

    setState(() => _isSaving = true);

    try {
      debugPrint('🚀 [InvoiceFormPage] Calling SalesService.saveInvoice()');
      final saved = await _salesService.saveInvoice(invoice);
      debugPrint(
        '✅ [InvoiceFormPage] Save completed | savedId=${saved.id ?? 'null'} | number=${saved.invoiceNumber} | itemCount=${saved.items.length} | subtotal=${saved.subtotal} | iva=${saved.ivaAmount} | total=${saved.total}',
      );
      for (var i = 0; i < saved.items.length; i++) {
        final item = saved.items[i];
        debugPrint(
          '   ↳ savedItem[$i] productId=${item.productId ?? 'null'} | name="${item.productName}" | qty=${item.quantity} | unit=${item.unitPrice} | total=${item.lineTotal} | jobBikeId=${item.jobBikeId ?? 'null'}',
        );
      }

      if (!mounted) return;

      // If this invoice was created from a mechanic job, write the link back
      if (_linkedJobId != null &&
          saved.id != null &&
          widget.invoiceId == null) {
        try {
          final db = Provider.of<DatabaseService>(context, listen: false);
          await db.supabase
              .from('mechanic_jobs')
              .update({'invoice_id': saved.id}).eq('id', _linkedJobId!);
          debugPrint(
              '🔗 [InvoiceFormPage] Linked invoice ${saved.id} to job $_linkedJobId');
        } catch (e) {
          debugPrint('⚠️ [InvoiceFormPage] Could not link invoice to job: $e');
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Borrador guardado correctamente'),
          backgroundColor: Colors.green,
        ),
      );

      if (widget.invoiceId == null && saved.id != null) {
        debugPrint(
            '🧭 [InvoiceFormPage] New invoice saved, navigating to /sales/invoices/${saved.id}');
        // Navigate to the saved invoice detail page
        context.go('/sales/invoices/${saved.id}');
        return;
      }

      debugPrint(
          '📝 [InvoiceFormPage] Applying saved invoice back into form state');
      _applyInvoice(saved);
    } catch (e) {
      debugPrint('❌ [InvoiceFormPage] Save failed: $e');
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
        debugPrint(
            '🏁 [InvoiceFormPage] Save flow finished, clearing _isSaving');
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Check if we should return to a specific page (e.g., from pegas table)
    final returnTo = GoRouterState.of(context).uri.queryParameters['returnTo'];

    return MainLayout(
      onBackPressed: returnTo != null && returnTo.isNotEmpty
          ? () => context.go(returnTo)
          : null, // null = use default back button behavior
      child: Form(
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
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        final invoiceNumber = _invoiceNumberController.text.trim();
        final hasExistingInvoice = _currentInvoiceId != null;
        final title = invoiceNumber.isNotEmpty
            ? 'Factura $invoiceNumber'
            : (hasExistingInvoice ? 'Factura' : 'Nueva factura');

        final actionButtons = <Widget>[];

        if (_canEditFields) {
          // Scanner button (only when editing)
          actionButtons.add(
            IconButton(
              onPressed: _toggleScanner,
              icon: Icon(
                _scannerEnabled
                    ? Icons.qr_code_scanner
                    : Icons.qr_code_scanner_outlined,
                color: _scannerEnabled ? Colors.green : null,
              ),
              tooltip:
                  _scannerEnabled ? 'Desactivar Escáner' : 'Activar Escáner',
              style: IconButton.styleFrom(
                backgroundColor:
                    _scannerEnabled ? Colors.green.withOpacity(0.1) : null,
              ),
            ),
          );
          if (!isMobile) actionButtons.add(const SizedBox(width: 8));

          if (_loadedInvoice != null) {
            if (isMobile) {
              actionButtons.add(IconButton(
                onPressed: _isSaving ? null : _cancelEditing,
                icon: const Icon(Icons.close),
                tooltip: 'Cancelar',
              ));
            } else {
              actionButtons.add(
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _cancelEditing,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancelar'),
                ),
              );
            }
          }
          if (isMobile) {
            actionButtons.add(
              IconButton.filled(
                onPressed: _isSaving ? null : _saveInvoice,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save),
                tooltip: 'Guardar borrador',
              ),
            );
          } else {
            actionButtons.add(
              AppButton(
                text: 'Guardar borrador',
                icon: Icons.save_outlined,
                onPressed: _isSaving ? null : _saveInvoice,
                isLoading: _isSaving,
              ),
            );
          }
        } else {
          // Not editing - show workflow buttons based on status

          // PDF Download Button (Always available in view mode if invoice exists)
          if (_loadedInvoice != null) {
            actionButtons.add(
              IconButton(
                onPressed: () => _downloadInvoicePDF(_loadedInvoice!),
                icon: _isGeneratingPdf
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf),
                tooltip: 'Descargar PDF',
              ),
            );
            if (!isMobile) actionButtons.add(const SizedBox(width: 8));
          }

          if (_status == InvoiceStatus.draft) {
            if (isMobile) {
              // Combine into simplified actions or menu?
              // For now, just icons
              actionButtons.add(IconButton.outlined(
                onPressed: _isUpdatingStatus ? null : _startEditing,
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Editar',
              ));
            } else {
              actionButtons.add(
                OutlinedButton.icon(
                  onPressed: _isUpdatingStatus ? null : _startEditing,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
              );
            }

            if (!isMobile) actionButtons.add(const SizedBox(width: 8));

            if (_canMarkAsSent) {
              if (isMobile) {
                actionButtons.add(IconButton.filled(
                  onPressed: _isUpdatingStatus ? null : _sendInvoiceToCustomer,
                  icon: _isUpdatingStatus
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_outlined),
                  tooltip: 'Enviar al cliente',
                ));
              } else {
                actionButtons.add(
                  FilledButton.icon(
                    onPressed:
                        _isUpdatingStatus ? null : _sendInvoiceToCustomer,
                    icon: _isUpdatingStatus
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: const Text('Enviar al cliente'),
                  ),
                );
              }
            }
          } else if (_status == InvoiceStatus.sent) {
            // Mobile handling for SENT status
            // ... Similar pattern ...
            if (isMobile) {
              actionButtons.add(PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (val) {
                  if (val == 'undo') _updateStatus(InvoiceStatus.draft);
                  if (val == 'confirm') _updateStatus(InvoiceStatus.confirmed);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: 'undo', child: Text('Volver a borrador')),
                  const PopupMenuItem(
                      value: 'confirm', child: Text('Confirmar')),
                ],
              ));
            } else {
              actionButtons.add(
                OutlinedButton.icon(
                  onPressed: _isUpdatingStatus
                      ? null
                      : () => _updateStatus(InvoiceStatus.draft),
                  icon: const Icon(Icons.undo_outlined),
                  label: const Text('Volver a borrador'),
                ),
              );
              actionButtons.add(const SizedBox(width: 8));
              actionButtons.add(
                FilledButton.icon(
                  onPressed: _isUpdatingStatus
                      ? null
                      : () => _updateStatus(InvoiceStatus.confirmed),
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
            }
          } else if (_status == InvoiceStatus.confirmed) {
            final hasPartialPayments = (_loadedInvoice?.paidAmount ?? 0) > 0;
            // Mobile handling for CONFIRMED status
            if (isMobile) {
              // Show "Deshacer pago" if there are partial payments
              if (hasPartialPayments) {
                actionButtons.add(IconButton.outlined(
                  onPressed: _undoLastPayment,
                  icon: const Icon(Icons.undo_outlined, color: Colors.red),
                  tooltip: 'Deshacer pago',
                ));
              } else {
                // Only show "Volver a enviado" if NO payments have been made
                actionButtons.add(PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (val) {
                    if (val == 'undo') _updateStatus(InvoiceStatus.sent);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: 'undo', child: Text('Volver a enviado')),
                  ],
                ));
              }
              if (_canRegisterPayment) {
                actionButtons.add(IconButton.filled(
                  onPressed: _openPaymentForm,
                  icon: const Icon(Icons.payments_outlined),
                  tooltip: 'Registrar pago',
                ));
              }
            } else {
              // Desktop: Show "Deshacer pago" if partial payments, else "Volver a enviado"
              if (hasPartialPayments) {
                actionButtons.add(
                  OutlinedButton.icon(
                    onPressed: _undoLastPayment,
                    icon: const Icon(Icons.undo_outlined, color: Colors.red),
                    label: const Text('Deshacer pago',
                        style: TextStyle(color: Colors.red)),
                  ),
                );
              } else {
                actionButtons.add(
                  OutlinedButton.icon(
                    onPressed: _isUpdatingStatus
                        ? null
                        : () => _updateStatus(InvoiceStatus.sent),
                    icon: const Icon(Icons.undo_outlined),
                    label: const Text('Volver a enviado'),
                  ),
                );
              }
              actionButtons.add(const SizedBox(width: 8));
              if (_canRegisterPayment) {
                actionButtons.add(
                  FilledButton.icon(
                    onPressed: _openPaymentForm,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Registrar pago'),
                  ),
                );
              }
            }
          } else if (_status == InvoiceStatus.paid) {
            if (isMobile) {
              actionButtons.add(IconButton.outlined(
                onPressed: _undoLastPayment,
                icon: const Icon(Icons.undo_outlined, color: Colors.red),
                tooltip: 'Deshacer pago',
              ));
            } else {
              actionButtons.add(
                OutlinedButton.icon(
                  onPressed: _undoLastPayment,
                  icon: const Icon(Icons.undo_outlined, color: Colors.red),
                  label: const Text('Deshacer pago',
                      style: TextStyle(color: Colors.red)),
                ),
              );
            }
          }
        }

        final actionWidgets = <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
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
          if (!isMobile) _buildStatusChip(theme),
          ...actionButtons,
        ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      debugPrint(
                          '🔙 Back button pressed - referrer: ${widget.referrer}, jobId: ${widget.referrerJobId}');
                      final returnTo = GoRouterState.of(context)
                          .uri
                          .queryParameters['returnTo'];
                      if (widget.referrer == 'job' &&
                          widget.referrerJobId != null) {
                        debugPrint(
                            '🔙 Navigating back to job: ${widget.referrerJobId}');
                        context.go('/taller/pegas/${widget.referrerJobId}');
                      } else if (widget.referrer == 'movements') {
                        debugPrint('🔙 Navigating back to movements');
                        context.go('/inventory/movements');
                      } else if (returnTo != null && returnTo.isNotEmpty) {
                        debugPrint('🔙 Navigating to returnTo: $returnTo');
                        context.go(returnTo);
                      } else {
                        debugPrint('🔙 Navigating to default: /sales/invoices');
                        context.go('/sales/invoices');
                      }
                    },
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
                          style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: isMobile ? 20 : null),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!isMobile)
                          Text(
                            'Emite documentos auditables y con IVA integrado.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isMobile) ...[
                    const SizedBox(width: 16),
                    Flexible(
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: actionWidgets,
                      ),
                    ),
                  ]
                ],
              ),
              if (isMobile) ...[
                const SizedBox(height: 12),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatusChip(theme),
                      Flexible(
                          child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children:
                            actionButtons, // Reuse logic but maybe needs filtering if we used widgets
                      ))
                    ])
              ]
            ],
          ),
        );
      },
    );
  }

  Widget _buildForm(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1180;
        final showChatSidebar = isWide && _currentInvoiceId != null;
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
                        if (_shouldShowReadOnlyNotice)
                          _buildReadOnlyNotice(theme),
                        if (_shouldShowReadOnlyNotice)
                          const SizedBox(height: 16),
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
                          trailing: _buildDefaultBikeDropdown(theme),
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
                        if (_linkedJobId != null) ...[
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            theme,
                            icon: Icons.build_circle_outlined,
                            title: 'Trabajo Vinculado',
                            children: [_buildLinkedJobCard(theme)],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (showChatSidebar) ...[
                  const SizedBox(width: 8),
                  EntityChatSidebar(
                    entityType: 'invoice',
                    entityId: _currentInvoiceId!,
                    entityTitle: _invoiceChatTitle,
                  ),
                ],
              ],
            ),
          );
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                  trailing: _buildDefaultBikeDropdown(theme),
                  children: [_buildLineItemsSection(theme)],
                ),
                const SizedBox(height: 16),
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
                if (_linkedJobId != null) ...[
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    theme,
                    icon: Icons.build_circle_outlined,
                    title: 'Trabajo Vinculado',
                    children: [_buildLinkedJobCard(theme)],
                  ),
                ],
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
        );
      },
    );
  }

  Widget _buildReadOnlyNotice(ThemeData theme) {
    return Card(
      color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
      child: ListTile(
        leading:
            Icon(Icons.lock_outline, color: theme.colorScheme.onSurfaceVariant),
        title: const Text('Factura en modo lectura'),
        subtitle: Text(_status != InvoiceStatus.paid
            ? 'Usa "Editar" para habilitar los campos y modificar la factura.'
            : 'Esta factura está pagada y no se puede modificar.'),
        trailing: _status != InvoiceStatus.paid
            ? OutlinedButton.icon(
                onPressed: _isUpdatingStatus ? null : _startEditing,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar'),
              )
            : null,
      ),
    );
  }

  Widget _buildSectionCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required List<Widget> children,
    Widget? trailing,
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
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                  child: Icon(icon, color: theme.colorScheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing,
                ],
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildLinkedJobCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border.all(color: Colors.blue[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.build_circle, color: Colors.blue[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Trabajo: ${_linkedJobNumber ?? "Cargando número..."}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue[900],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Acceso rápido a la pega relacionada con esta factura.',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _linkedJobId == null
                ? null
                : () => context.push('/taller/pegas/${_linkedJobId!}'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Ver Trabajo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerSection(ThemeData theme) {
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
            backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
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
              ? const Text('Necesario para facturación electrónica y reportes')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    if (_selectedCustomer!.rut.isNotEmpty)
                      Text('RUT: ${_selectedCustomer!.rut}'),
                    if ((_selectedCustomer!.email ?? '').isNotEmpty)
                      Text('Email: ${_selectedCustomer!.email}'),
                    if ((_selectedCustomer!.phone ?? '').isNotEmpty)
                      Text('Teléfono: ${_selectedCustomer!.phone}'),
                  ],
                ),
          trailing: FilledButton.icon(
            onPressed: _canEditFields ? _openCustomerSelector : null,
            icon: const Icon(Icons.search),
            label:
                Text(_selectedCustomer == null ? 'Buscar cliente' : 'Cambiar'),
          ),
        ),
      ],
    );
  }

  Widget _buildLineItemsSection(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 800) {
          return _buildMobileLineItemsList(theme);
        }

        // Calculate minimum required width based on columns
        const minTableWidth = 800.0; // Reduced from 900
        // Use available width if larger, otherwise use minimum (enables scroll)
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
                    color: theme.colorScheme.outline.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Table header
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                    child: Row(
                      children: [
                        // # column
                        Container(
                          width: _colIndexWidth,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withOpacity(0.2)),
                            ),
                          ),
                          child: Center(
                            child: Text('#',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                        ),

                        // Artículo column (flex to fill remaining space)
                        Expanded(
                          child: Container(
                            constraints: const BoxConstraints(
                                minWidth:
                                    250), // Reduced from 300 for better shrinking
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withOpacity(0.2)),
                              ),
                            ),
                            child: Text(
                              'DETALLES DEL ARTÍCULO',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.visible,
                            ),
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
                                      .withOpacity(0.2)),
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
                                      .withOpacity(0.2)),
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
                                      .withOpacity(0.2)),
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
                        SizedBox(width: _colActionsWidth),
                      ],
                    ),
                  ),

                  // Header/Content divider
                  Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.outline.withOpacity(0.2)),

                  // Line items
                  Column(
                    children: [
                      // Line items (all states)
                      if (_lineEntries.isNotEmpty)
                        ..._buildGroupedLineItems(theme, isCompact: true),

                      // Add new line button (only when editing)
                      if (_canEditFields)
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                  color: theme.colorScheme.outline
                                      .withOpacity(0.2)),
                            ),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Empty space for # column
                                Container(
                                  width: _colIndexWidth,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withOpacity(0.2)),
                                    ),
                                  ),
                                ),

                                // Search field spanning the product details column
                                Expanded(
                                  child: Container(
                                    constraints: const BoxConstraints(
                                        minWidth: 250), // Match header column
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(
                                            color: theme.colorScheme.outline
                                                .withOpacity(0.2)),
                                      ),
                                    ),
                                    child: SmartProductField(
                                      key: ValueKey(
                                          _autocompleteKey), // Reset field when key changes
                                      onProductChanged: (selection) {
                                        if (selection == null) return;
                                        if (selection.isCatalogProduct &&
                                            selection.product != null) {
                                          _addProductLine(selection.product!);
                                        } else if (!selection
                                                .isCatalogProduct &&
                                            selection.productName != null) {
                                          _addCustomItemLine(
                                              selection.productName!);
                                        }
                                      },
                                      allowCustomItems: true,
                                      showCost: false,
                                      hintText:
                                          'Buscar por nombre o SKU, o escribir artículo personalizado...',
                                    ),
                                  ),
                                ),

                                // Empty spaces for other columns to maintain alignment
                                Container(
                                  width: _colQuantityWidth,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withOpacity(0.2)),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: _colPriceWidth,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withOpacity(0.2)),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: _colDiscountWidth,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      right: BorderSide(
                                          color: theme.colorScheme.outline
                                              .withOpacity(0.2)),
                                    ),
                                  ),
                                ),
                                SizedBox(width: _colTotalWidth),
                                SizedBox(width: _colActionsWidth),
                              ],
                            ),
                          ),
                        ),

                      // Empty state
                      if (_lineEntries.isEmpty && !_canEditFields)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No hay artículos en esta factura',
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

  Widget _buildMobileLineItemsList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_lineEntries.isEmpty && !_canEditFields)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'No hay artículos en esta factura',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ..._buildGroupedLineItems(theme, isCompact: false),
        if (_canEditFields)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ElevatedButton.icon(
              onPressed: _showMobileAddLineSheet,
              icon: const Icon(Icons.add),
              label: const Text('Agregar Artículo'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
      ],
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

  /// Builds line items grouped by bike with section headers.
  /// Items are sorted by bike so all items for one bike appear under a single header.
  List<Widget> _buildGroupedLineItems(ThemeData theme,
      {required bool isCompact}) {
    final widgets = <Widget>[];
    String? lastBikeName;
    int itemIndex = 0;

    // Sort entries by bike name so same-bike items are grouped together
    // Items without a bike come last
    final sortedEntries = List<_InvoiceLineEntry>.from(_lineEntries)
      ..sort((a, b) {
        final aName = a.line.bikeName ?? '';
        final bName = b.line.bikeName ?? '';
        if (aName.isEmpty && bName.isEmpty) return 0;
        if (aName.isEmpty) return 1; // no-bike items go last
        if (bName.isEmpty) return -1;
        return aName.compareTo(bName);
      });

    for (final entry in sortedEntries) {
      final bikeName = entry.line.bikeName;
      itemIndex++;

      // Insert bike section header when bike changes
      if (bikeName != null && bikeName.isNotEmpty && bikeName != lastBikeName) {
        widgets.add(_buildBikeSectionHeader(
            theme, bikeName, _getBikeSubtotal(bikeName)));
        lastBikeName = bikeName;
      } else if ((bikeName == null || bikeName.isEmpty) &&
          lastBikeName != null) {
        // Items without a bike after bike-grouped items
        widgets.add(
            _buildBikeSectionHeader(theme, 'General', _getBikeSubtotal(null)));
        lastBikeName = null;
      }

      if (isCompact) {
        widgets.add(_buildCompactLineRow(theme, itemIndex, entry));
      } else {
        widgets.add(_buildMobileLineItemCard(theme, itemIndex, entry));
      }
    }

    return widgets;
  }

  /// Builds a visual section header for bike grouping in invoices.
  Widget _buildBikeSectionHeader(
      ThemeData theme, String bikeName, double subtotal) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
          bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.1)),
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
                    color: theme.colorScheme.outline.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
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
              border:
                  Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
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

  Widget _buildMobileLineItemCard(
      ThemeData theme, int index, _InvoiceLineEntry entry) {
    final line = entry.line;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (line.sku.isNotEmpty)
                        Text(
                          line.sku,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      if (_availableJobBikes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _buildBikeSelector(theme, entry),
                        ),
                    ],
                  ),
                ),
                if (_canEditFields)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (value) {
                      if (value == 'edit') {
                        // Implement edit dialog
                      } else if (value == 'delete') {
                        _removeLine(entry);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Eliminar',
                                style: TextStyle(color: Colors.red))
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Qty & Price
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${line.quantity} x ${ChileanUtils.formatCurrency(line.unitPrice)}'),
                    if (line.discount > 0)
                      Text('Desc: ${line.discount}%',
                          style: const TextStyle(
                              color: Colors.green, fontSize: 12)),
                  ],
                ),
                // Total
                Text(
                  ChileanUtils.formatCurrency(line.netAmount),
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: theme.primaryColor),
                ),
              ],
            ),
            if (_canEditFields) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: entry.quantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cant.',
                        isDense: true,
                        contentPadding: EdgeInsets.all(8),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _handleLinesChanged(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: entry
                          .unitPriceController, // Assuming this exists or using helper
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Precio',
                        isDense: true,
                        contentPadding: EdgeInsets.all(8),
                        border: OutlineInputBorder(),
                        prefixText: '\$ ',
                      ),
                      onChanged: (_) => _handleLinesChanged(),
                    ),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }

  void _showMobileAddLineSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Agregar Artículo',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SmartProductField(
                onProductChanged: (selection) {
                  if (selection == null) return;
                  Navigator.pop(context);
                  if (selection.isCatalogProduct && selection.product != null) {
                    _addProductLine(selection.product!);
                  } else if (!selection.isCatalogProduct &&
                      selection.productName != null) {
                    _addCustomItemLine(selection.productName!);
                  }
                },
                allowCustomItems: true,
                showCost: false,
                hintText: 'Buscar por nombre o SKU...',
                autoFocus: true,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Global default bike dropdown shown in the "Productos y servicios" header.
  /// When a bike is selected here, all newly added line items are pre-assigned to it.
  Widget _buildDefaultBikeDropdown(ThemeData theme) {
    if (_availableJobBikes.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _defaultJobBikeId != null
            ? theme.colorScheme.primaryContainer.withOpacity(0.6)
            : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _defaultJobBikeId != null
              ? theme.colorScheme.primary.withOpacity(0.4)
              : theme.colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _availableJobBikes.any((b) => b.id == _defaultJobBikeId)
              ? _defaultJobBikeId
              : null,
          hint: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pedal_bike,
                  size: 13, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('Agregar a...',
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
          icon: Icon(Icons.expand_more_rounded,
              size: 14,
              color: _defaultJobBikeId != null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant),
          isDense: true,
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('General / Venta',
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic)),
            ),
            ..._availableJobBikes.map((bike) => DropdownMenuItem<String?>(
                  value: bike.id,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pedal_bike,
                          size: 13, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(bike.displayName,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                )),
          ],
          onChanged: _canEditFields
              ? (String? newId) {
                  setState(() => _defaultJobBikeId = newId);
                }
              : null,
        ),
      ),
    );
  }

  Widget _buildBikeSelector(ThemeData theme, _InvoiceLineEntry entry) {
    if (_availableJobBikes.isEmpty) {
      // For debugging/UX: if it's empty but we expect it, show a disabled selector
      return Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3)),
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
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5)),
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
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3)),
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

  /// Builds a single line row using the universal LineRowWrapper.
  /// Hover state is managed locally inside the wrapper, preventing SmartProductField rebuilds.
  Widget _buildCompactLineRow(
      ThemeData theme, int index, _InvoiceLineEntry entry) {
    final line = entry.line;

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
                () {}, // No setState needed - hover is local to wrapper
                () => _autoAddEmptyLineIfNeeded(),
                defaultJobBikeId: _defaultJobBikeId,
                availableJobBikes: _availableJobBikes,
              ),
              _buildBikeSelector(theme, entry),
            ],
          ),
        ),

        // Cantidad column with stock warning
        LineColumn(
          width: _colQuantityWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: entry.quantityController,
                enabled: _canEditFields,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: _canEditFields
                      ? const OutlineInputBorder()
                      : InputBorder.none,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                ],
              ),

              // Stock warning (hide for services)
              if (line.product != null &&
                  !line.product!.isService &&
                  line.product!.stockQuantity < line.quantity)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber, size: 12, color: Colors.red),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Stock bajo: ${line.product!.stockQuantity.toInt()} disponibles',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.red,
                            fontSize: 10,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Tarifa/Price column
        LineColumn(
          width: _colPriceWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Center(
            child: TextField(
              controller: entry.unitPriceController,
              enabled: _canEditFields,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: _canEditFields
                    ? const OutlineInputBorder()
                    : InputBorder.none,
                prefixText: '\$ ',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
            ),
          ),
        ),

        // Descuento column with % symbol
        LineColumn(
          width: _colDiscountWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Center(
            child: Row(
              children: [
                const SizedBox(width: 4),
                const Text('\$ ', style: TextStyle(fontSize: 14)),
                Expanded(
                  child: TextField(
                    controller: entry.discountController,
                    enabled: _canEditFields,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      border: _canEditFields
                          ? const OutlineInputBorder()
                          : InputBorder.none,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                // Dropdown for % or fixed amount (placeholder)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('%', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ),

        // Importe/Total column (no right border - last content column)
        LineColumn(
          width: _colTotalWidth,
          showRightBorder: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Center(
            child: Text(
              ChileanUtils.formatCurrency(line.netAmount),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatesAndStatus(ThemeData theme) {
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
          trailing: _status == InvoiceStatus.draft
              ? Text(
                  _canEditFields ? 'Editando' : 'Solo lectura',
                  style: theme.textTheme.labelMedium,
                )
              : null,
        ),
      ],
    );
  }

  Widget _buildSummary(ThemeData theme) {
    final textStyle =
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);

    // Compute balance from paid_amount to stay consistent with payment terminal
    // Do NOT use raw DB `balance` field — it can be stale/inconsistent if total changed
    final paidAmount = _loadedInvoice?.paidAmount ?? 0;
    final balance = (_loadedInvoice?.total ?? _total) - paidAmount;
    final hasPayments = paidAmount > 0;

    return Column(
      children: [
        _buildSummaryRow('Subtotal', ChileanUtils.formatCurrency(_subtotal),
            textStyle, theme),
        const Divider(height: 24),
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
          const Divider(height: 24),
          _buildSummaryRow(
            'Pagado',
            ChileanUtils.formatCurrency(paidAmount),
            TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600),
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
        hintText: 'Ej: Pedido web, orden de compra, notas internas...',
        alignLabelWithHint: true,
      ),
      maxLines: 4,
    );
  }

  String _statusDisplayName(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return 'Borrador';
      case InvoiceStatus.sent:
        return 'Enviada';
      case InvoiceStatus.confirmed:
        return 'Confirmada';
      case InvoiceStatus.paid:
        return 'Pagada';
      case InvoiceStatus.overdue:
        return 'Vencida';
      case InvoiceStatus.cancelled:
        return 'Cancelada';
    }
  }

  Color _statusColor(ThemeData theme) {
    switch (_status) {
      case InvoiceStatus.draft:
        return theme.colorScheme.outline;
      case InvoiceStatus.sent:
        return theme.colorScheme.primary;
      case InvoiceStatus.confirmed:
        return Colors.purple;
      case InvoiceStatus.paid:
        return Colors.green;
      case InvoiceStatus.overdue:
        return Colors.orange;
      case InvoiceStatus.cancelled:
        return theme.colorScheme.error;
    }
  }

  Widget _buildStatusChip(ThemeData theme) {
    final color = _statusColor(theme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusDisplayName(_status),
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Cached logo bytes for PDF generation
  Uint8List? _cachedLogoBytes;
  String? _cachedLogoUrl;
  bool _isGeneratingPdf = false;

  /// Build a fresh Invoice object from current form values
  /// This ensures PDF always has the latest data
  Invoice _buildCurrentInvoice() {
    // Build items from current line entries (excluding empty ones)
    final items = _lineEntries
        .where((entry) => entry.line.quantity > 0 && entry.hasValidProduct)
        .map((entry) => entry.toInvoiceItem())
        .toList();

    // Use paidAmount from DB; compute balance consistently as total - paidAmount
    final paidAmount = _loadedInvoice?.paidAmount ?? 0;
    final balance = _total - paidAmount;

    return Invoice(
      id: _loadedInvoice?.id,
      tenantId: _loadedInvoice?.tenantId ?? '',
      invoiceNumber: _invoiceNumberController.text.trim(),
      customerId: _selectedCustomer?.id,
      customerName: _selectedCustomer?.name,
      customerRut: _selectedCustomer?.rut,
      date: _issueDate,
      dueDate: _dueDate,
      reference: _referenceController.text.trim().isEmpty
          ? null
          : _referenceController.text.trim(),
      status: _loadedInvoice?.status ?? InvoiceStatus.draft,
      subtotal: _subtotal,
      ivaAmount: _iva,
      total: _total,
      paidAmount: paidAmount,
      balance: balance,
      taxTreatment: _taxTreatment,
      netAmount: _netAmount,
      items: items,
      createdAt: _loadedInvoice?.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _downloadInvoicePDF(Invoice _) async {
    if (_isGeneratingPdf) return;

    setState(() => _isGeneratingPdf = true);

    try {
      final currentInvoice = _buildCurrentInvoice();

      // ── Resolve bike names from the database ──────────────────────────────
      final Map<String, String> resolvedBikeNames = {};
      try {
        if (!mounted) return;
        final db = context.read<DatabaseService>();

        // 1. Single-bike invoice: fetch via invoice.bikeId (from loaded invoice)
        final bikeId = _loadedInvoice?.bikeId;
        if (bikeId != null && bikeId.isNotEmpty) {
          final bikeData = await db.supabase
              .from('bikes')
              .select('brand, model, year')
              .eq('id', bikeId as Object)
              .maybeSingle();
          if (bikeData != null) {
            final parts = <String>[
              if ((bikeData['brand'] as String?)?.isNotEmpty == true)
                bikeData['brand'] as String,
              if ((bikeData['model'] as String?)?.isNotEmpty == true)
                bikeData['model'] as String,
              if (bikeData['year'] != null) bikeData['year'].toString(),
            ];
            if (parts.isNotEmpty) resolvedBikeNames['single'] = parts.join(' ');
          }
        }

        // 2. Multi-bike items via jobBikeId
        final jobBikeIds = currentInvoice.items
            .where((i) => i.jobBikeId != null && i.jobBikeId!.isNotEmpty)
            .map((i) => i.jobBikeId!)
            .toSet();

        for (final jobBikeId in jobBikeIds) {
          final existingName = currentInvoice.items
              .firstWhere((i) => i.jobBikeId == jobBikeId)
              .bikeName;
          if (existingName != null && existingName.isNotEmpty) {
            resolvedBikeNames[jobBikeId] = existingName;
            continue;
          }
          final jobBikeData = await db.supabase
              .from('mechanic_job_bikes')
              .select('bikes(brand, model, year)')
              .eq('id', jobBikeId as Object)
              .maybeSingle();
          if (jobBikeData != null) {
            final bikeMap = jobBikeData['bikes'] as Map<String, dynamic>?;
            if (bikeMap != null) {
              final parts = <String>[
                if ((bikeMap['brand'] as String?)?.isNotEmpty == true)
                  bikeMap['brand'] as String,
                if ((bikeMap['model'] as String?)?.isNotEmpty == true)
                  bikeMap['model'] as String,
                if (bikeMap['year'] != null) bikeMap['year'].toString(),
              ];
              if (parts.isNotEmpty)
                resolvedBikeNames[jobBikeId] = parts.join(' ');
            }
          }
        }
      } catch (e) {
        debugPrint('Could not resolve bike names for PDF: $e');
      }

      final pdf = await _generateInvoicePDF(currentInvoice, resolvedBikeNames);
      final bytes = await pdf.save();

      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar Factura PDF',
          fileName: 'factura_${currentInvoice.invoiceNumber}.pdf',
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
          filename: 'factura_${currentInvoice.invoiceNumber}.pdf',
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

  Future<pw.Document> _generateInvoicePDF(
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) async {
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
                      color: PdfColors.grey800,
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
                      ChileanUtils.formatCurrency(invoice.balance),
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

            // Customer and date info - more compact
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Facturar a',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      invoice.customerName ?? 'Sin registro',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue700,
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

            // ── Bicycle info banner ──────────────────────────────────
            ..._buildFormPdfBikeBanner(invoice, resolvedBikeNames),

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
                    _buildPdfTableCell('Cantidad', isHeader: true),
                  ],
                ),
                // Data rows grouped by bike
                ..._buildFormPdfItemRows(invoice, resolvedBikeNames),
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
                      _buildPdfTotalRow('Subtotal', invoice.subtotal),
                      pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                      _buildPdfTotalRow('Total', invoice.total, isTotal: true),
                      if (invoice.paidAmount > 0) ...[
                        pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                        _buildPdfTotalRow(
                            'Pago realizado', -invoice.paidAmount),
                      ],
                      pw.Divider(thickness: 1, color: PdfColors.grey800),
                      _buildPdfTotalRow('Saldo adeudado', invoice.balance,
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

  /// Bike banner for the form page PDF (Table layout).
  List<pw.Widget> _buildFormPdfBikeBanner(
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) {
    final multiBikeNames = <String>[];
    for (final item in invoice.items) {
      final jbId = item.jobBikeId;
      if (jbId != null && jbId.isNotEmpty) {
        final name = resolvedBikeNames[jbId] ?? item.bikeName ?? '';
        if (name.isNotEmpty && !multiBikeNames.contains(name))
          multiBikeNames.add(name);
      }
    }
    final singleBikeName = resolvedBikeNames['single'];
    final List<String> bikeNames;
    if (multiBikeNames.isNotEmpty) {
      bikeNames = multiBikeNames;
    } else if (singleBikeName != null && singleBikeName.isNotEmpty) {
      bikeNames = [singleBikeName];
    } else {
      return [];
    }
    final isMultiBike = bikeNames.length > 1;
    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.only(top: 8, bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              isMultiBike ? 'Bicicletas en servicio' : 'Bicicleta en servicio',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
            pw.SizedBox(height: 4),
            if (!isMultiBike)
              pw.Text(
                bikeNames.first,
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.black,
                ),
              )
            else
              ...bikeNames.map(
                (name) => pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2, left: 4),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        width: 3,
                        height: 3,
                        margin: const pw.EdgeInsets.only(right: 6),
                        decoration: const pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.Text(
                        name,
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      pw.SizedBox(height: 12),
    ];
  }

  /// Item table rows, with bike sub-headers for multi-bike jobs.
  List<pw.TableRow> _buildFormPdfItemRows(
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) {
    final rows = <pw.TableRow>[];
    String? lastBikeName;
    int itemIndex = 0;

    final bikeNamesForItems = <String>{};
    for (final item in invoice.items) {
      final jbId = item.jobBikeId;
      if (jbId != null && jbId.isNotEmpty) {
        final name = resolvedBikeNames[jbId] ?? item.bikeName ?? '';
        if (name.isNotEmpty) bikeNamesForItems.add(name);
      }
    }
    final hasMultiBike = bikeNamesForItems.length > 1;

    for (final item in invoice.items) {
      if (hasMultiBike) {
        final jbId = item.jobBikeId ?? '';
        final bikeName = jbId.isNotEmpty
            ? (resolvedBikeNames[jbId] ?? item.bikeName ?? '')
            : (item.bikeName ?? '');
        if (bikeName.isNotEmpty && bikeName != lastBikeName) {
          lastBikeName = bikeName;
          rows.add(pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
            children: [
              pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: pw.SizedBox()),
              pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: pw.Text(bikeName,
                    style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800)),
              ),
              pw.SizedBox(),
              pw.SizedBox(),
              pw.SizedBox(),
            ],
          ));
        }
      }
      itemIndex++;
      final hasDescription =
          item.description != null && item.description!.isNotEmpty;
      rows.add(pw.TableRow(
        children: [
          _buildPdfTableCell('$itemIndex'),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_cleanPdfText(item.productName ?? 'Sin nombre'),
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 10)),
                if (hasDescription) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(_cleanPdfText(item.description!),
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey700)),
                ],
              ],
            ),
          ),
          _buildPdfTableCell(item.quantity.toStringAsFixed(2)),
          _buildPdfTableCell(ChileanUtils.formatCurrency(item.unitPrice)),
          _buildPdfTableCell(ChileanUtils.formatCurrency(item.lineTotal)),
        ],
      ));
    }
    return rows;
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

class _InvoiceLine {
  _InvoiceLine({
    this.productId, // NOW NULLABLE - null for ad-hoc items
    this.product,
    required this.name,
    this.sku = '',
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    this.cost = 0,
    this.description, // Custom description/notes
    this.isCatalogProduct = true, // true = catalog product, false = ad-hoc item
    this.jobBikeId, // Multi-bike sync: links item to specific bike
    this.bikeName, // Multi-bike sync: display name for section grouping
  });

  final String? productId; // Nullable for ad-hoc items
  final Product? product;
  final double cost;
  String?
      description; // Custom notes for line item (mutable so listener can update)
  final bool isCatalogProduct; // Track if catalog vs ad-hoc
  String? jobBikeId; // Multi-bike sync metadata
  String? bikeName; // Multi-bike sync metadata
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
  Product? product; // Store full product for image access
  /// Whether this line's product field should auto-focus (for newly added lines)
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
    // Listen to description changes so the line model stays in sync before save
    descriptionController.addListener(() {
      line.description = descriptionController.text;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _listener?.call();
      });
    });
    // Don't listen to productNameController - only update on selection
  }

  InvoiceItem toInvoiceItem() {
    // Use controller values (which are current) rather than line values (which may be stale)
    // The controllers are updated when product changes, but line object isn't
    final currentName = productNameController.text.trim();
    final currentSku = productSkuController.text.trim();
    final currentProductId =
        product?.id ?? line.productId; // Use current product if available

    return InvoiceItem(
      productId: currentProductId, // Nullable - null for ad-hoc items
      productName: currentName.isNotEmpty ? currentName : line.name,
      productSku: currentSku.isNotEmpty ? currentSku : line.sku,
      description: descriptionController.text.trim().isEmpty
          ? null
          : descriptionController.text.trim(),
      isCatalogProduct: product != null || line.isCatalogProduct,
      quantity: line.quantity,
      unitPrice: line.unitPrice,
      discount: line.discount,
      lineTotal: line.netAmount,
      cost: product?.cost ?? line.cost,
      jobBikeId: line.jobBikeId,
      bikeName: line.bikeName,
    );
  }

  /// Check if this line entry has valid product data
  bool get hasValidProduct {
    final name = productNameController.text.trim();
    return name.isNotEmpty && name != 'Producto' && name != 'producto';
  }

  void _onQuantityChanged() {
    final value = double.tryParse(quantityController.text.replaceAll(',', '.'));
    if (value != null && value >= 0) {
      line.quantity = value;
      // Defer callback to avoid setState during build
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
      // Defer callback to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _listener?.call();
      });
    }
  }

  void _onDiscountChanged() {
    final value = double.tryParse(discountController.text.replaceAll(',', '.'));
    if (value != null && value >= 0) {
      line.discount = value;
      // Defer callback to avoid setState during build
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

  // CRITICAL: Cache the SmartProductField widget to prevent rebuilds on parent hover state changes
  // This is the fix for flickering and disappearing dropdown when mouse moves
  Widget? _cachedSmartProductField;
  bool? _cachedCanEdit;

  Widget buildSmartProductField(BuildContext context, ThemeData theme,
      bool canEdit, VoidCallback onUpdate, VoidCallback onAutoAdd,
      {String? defaultJobBikeId,
      List<MechanicJobBike> availableJobBikes = const []}) {
    // Return cached widget if nothing meaningful changed
    // Only rebuild if canEdit changes (not on hover which doesn't change canEdit)
    if (_cachedSmartProductField != null && _cachedCanEdit == canEdit) {
      return _cachedSmartProductField!;
    }

    _cachedCanEdit = canEdit;
    _cachedSmartProductField = SmartProductField(
      key: ValueKey('product_${hashCode}'),
      initialData: ProductFieldData(
        product: product,
        productName: line.name.isEmpty ? null : line.name,
        productSku: line.sku.isEmpty ? null : line.sku,
        isCatalogProduct: line.isCatalogProduct,
        description: descriptionController.text,
      ),
      enabled: canEdit,
      showCost: false, // Sales uses price, not cost
      allowCustomItems: true,
      autoFocus: shouldAutoFocus, // Auto-focus newly added lines
      focusNode: productNameFocusNode,
      descriptionController: descriptionController,
      onAutoAddLine: onAutoAdd,
      onEditProduct: (p) => _showEditProductDialog(context, p),
      onShowProductDetails: (p) => _showProductDetailsPane(context, p, theme),
      onProductChanged: (selection) {
        if (selection == null) {
          // Product cleared
          product = null;
          productNameController.clear();
          productSkuController.clear();
          descriptionController.clear();
          onUpdate();
        } else {
          // Product selected or description changed
          product = selection.product;
          productNameController.text = selection.productName ?? '';
          productSkuController.text = selection.productSku ?? '';
          if (line.jobBikeId == null && defaultJobBikeId != null) {
            final bike = availableJobBikes
                .where((b) => b.id == defaultJobBikeId)
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
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            elevation: 8,
            child: Container(
              width: 400,
              height: MediaQuery.of(context).size.height,
              color: theme.scaffoldBackgroundColor,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: theme.dividerColor)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Detalles del artículo',
                              style: theme.textTheme.titleLarge),
                        ),
                        IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop()),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.imageUrl != null &&
                              product.imageUrl!.isNotEmpty)
                            Center(
                              child: Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: theme.dividerColor),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(product.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                          Icons.inventory_2_outlined,
                                          size: 80)),
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),
                          Text(product.name,
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          _detailRow('SKU', product.sku),
                          if (product.description != null &&
                              product.description!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text('Descripción',
                                style: theme.textTheme.labelLarge),
                            const SizedBox(height: 4),
                            Text(product.description!),
                          ],
                          const SizedBox(height: 16),
                          _detailRow('Precio',
                              '\$${product.price.toStringAsFixed(0)}'),
                          _detailRow(
                              'Costo', '\$${product.cost.toStringAsFixed(0)}'),
                          _detailRow('Stock', '${product.stockQuantity}'),
                          if (product.brand != null &&
                              product.brand!.isNotEmpty)
                            _detailRow('Marca', product.brand!),
                          if (product.model != null &&
                              product.model!.isNotEmpty)
                            _detailRow('Modelo', product.model!),
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
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim1, curve: Curves.easeOut)),
          child: child,
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 100,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

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
  bool _isSearching = false;

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
      setState(() => _isSearching = true);
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
          setState(() => _isSearching = false);
        }
      }
    });
  }

  Future<void> _handleCreateCustomer() async {
    final name = _newCustomerController.text.trim();
    if (name.isEmpty) return;
    final customer = await widget.onCreateCustomer(name);
    if (customer != null && mounted) {
      Navigator.of(context).pop(customer);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar cliente',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newCustomerController,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
              ),
              decoration: InputDecoration(
                labelText: 'Crear cliente rápido',
                hintText: 'Nombre del cliente',
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
                  onPressed: _handleCreateCustomer,
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[400]!,
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              onSubmitted: (_) => _handleCreateCustomer(),
            ),
            const SizedBox(height: 16),
            if (_isSearching) const LinearProgressIndicator(minHeight: 2),
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: _customers.isEmpty
                  ? const Center(child: Text('No se encontraron clientes'))
                  : ListView.separated(
                      itemCount: _customers.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final customer = _customers[index];
                        return ListTile(
                          title: Text(customer.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (customer.rut.isNotEmpty)
                                Text('RUT: ${customer.rut}'),
                              if ((customer.email ?? '').isNotEmpty)
                                Text(customer.email!),
                              if ((customer.phone ?? '').isNotEmpty)
                                Text(customer.phone!),
                            ],
                          ),
                          onTap: () => Navigator.of(context).pop(customer),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
