import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/services/database_service.dart';
import '../../../shared/services/number_generation_service.dart';
import '../../../shared/services/remote_scanner_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/smart_product_field.dart';
import '../../../shared/widgets/line_row_wrapper.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../../inventory/pages/product_form_page.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';

class InvoiceFormPage extends StatefulWidget {
  final String? invoiceId;
  final String? preselectedJobId;
  final String? preselectedCustomerId;

  const InvoiceFormPage({
    super.key,
    this.invoiceId,
    this.preselectedJobId,
    this.preselectedCustomerId,
  });

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

  final List<Customer> _cachedCustomers = [];
  final List<Product> _cachedProducts = [];
  final List<_InvoiceLineEntry> _lineEntries = [];

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
  TaxTreatment _taxTreatment = TaxTreatment.noTax; // Default: no tax (cash/transfer common)
  String? _paymentMethodHint; // 'card' or 'other' - for smart tax validation

  String? get _currentInvoiceId => _loadedInvoice?.id ?? widget.invoiceId;
  bool get _canEditFields => _status == InvoiceStatus.draft && _isEditing;
  bool get _canMarkAsSent =>
      _currentInvoiceId != null &&
      _status == InvoiceStatus.draft &&
      !_isEditing;
  double get _outstandingAmount {
    final balance = _loadedInvoice?.balance;
    if (balance != null && balance > 0) {
      return balance;
    }
    final paid = _loadedInvoice?.paidAmount ?? 0;
    final total = _loadedInvoice?.total ?? _total;
    return (total - paid).clamp(0, double.infinity);
  }

  bool get _canRegisterPayment =>
      _currentInvoiceId != null &&
      (_status == InvoiceStatus.sent || _status == InvoiceStatus.confirmed) &&
      _outstandingAmount > 0.01;
  bool get _shouldShowReadOnlyNotice =>
      !_canEditFields && _status == InvoiceStatus.draft;
  
  StreamSubscription? _scanSubscription;
  final _remoteScannerService = RemoteScannerService();
  bool _scannerEnabled = false;

  @override
  void initState() {
    super.initState();
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
    _invoiceNumberController.dispose();
    _referenceController.dispose();
    for (final entry in _lineEntries) {
      entry.dispose();
    }
    _scanSubscription?.cancel();
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
    
    try {
      if (_scannerEnabled) {
        await _remoteScannerService.stopListening();
        setState(() => _scannerEnabled = false);
      } else {
        await _remoteScannerService.startListening();
        setState(() => _scannerEnabled = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📱 Escáner remoto activado'),
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
  
  Future<void> _handleBarcodeScan(String barcode) async {
    // Search for product by SKU
    final product = _cachedProducts.cast<Product?>().firstWhere(
      (p) => p!.sku.toLowerCase() == barcode.toLowerCase(),
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
    _customerService = context.read<CustomerService>();
    _inventoryService = context.read<shared_inventory.InventoryService>();

    try {
      // Don't force refresh - use cached data if available for faster loading
      final customersFuture = _customerService.getCustomers();
      final productsFuture = _inventoryService.getProducts(forceRefresh: false);
      final results = await Future.wait([customersFuture, productsFuture]);

      _cachedCustomers
        ..clear()
        ..addAll(results[0] as List<Customer>);
      _cachedProducts
        ..clear()
        ..addAll(results[1] as List<Product>);

      if (widget.invoiceId != null) {
        final invoice =
            await _salesService.fetchInvoice(widget.invoiceId!, refresh: true);
        if (invoice != null) {
          _loadedInvoice = invoice;
          _applyInvoice(invoice);
        }
      } else {
        _invoiceNumberController.text = await _generateInvoiceNumber();

        // Preselect customer if coming from a job
        if (widget.preselectedJobId != null) {
          await _loadJobAndPreselectCustomer(widget.preselectedJobId!);
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
        _invoiceNumberController.text = await _generateInvoiceNumber();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyInvoice(Invoice invoice) {
    if (!mounted) return;

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
    // Deprecated: Use NumberGenerationService.nextSalesInvoiceNumber() instead
    // This fallback should rarely be used
    final now = DateTime.now();
    final datePortion =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timePortion = now.millisecondsSinceEpoch.toString().substring(7);
    return 'FV-$datePortion-$timePortion';
  }

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
      setState(() {});
    }
  }

  void _startEditing() {
    if (_status != InvoiceStatus.draft) return;
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
    final refreshed =
        await _salesService.fetchInvoice(invoiceId, refresh: true);
    if (refreshed != null && mounted) {
      _applyInvoice(refreshed);
    }
  }

  Future<void> _updateStatus(InvoiceStatus newStatus) async {
    final invoiceId = _currentInvoiceId;
    if (invoiceId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Guarda la factura como borrador antes de cambiar el estado.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // ⚠️ Smart validation: If paying with card but no tax → auto-fix
    if (newStatus == InvoiceStatus.confirmed && 
        _paymentMethodHint == 'card' && 
        _taxTreatment == TaxTreatment.noTax) {
      // Auto-add tax for card payments
      setState(() => _taxTreatment = TaxTreatment.taxIncluded);
      await _saveInvoice();
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    setState(() => _isUpdatingStatus = true);
    try {
      final updated = await _salesService.updateInvoiceStatus(
          invoiceId, newStatus);
      if (updated != null && mounted) {
        _applyInvoice(updated);
        await _refreshInvoiceById(invoiceId);
      } else if (mounted) {
        await _refreshInvoiceById(invoiceId);
      }
      if (mounted) {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar el estado: $e'),
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
    if (lastEntry.product != null || lastEntry.productNameController.text.isNotEmpty) {
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
        .where((entry) => entry.line.quantity > 0)
        .map((entry) => entry.toInvoiceItem())
        .toList();

    if (items.isEmpty) {
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
      throw Exception('User does not have a tenant_id. Cannot proceed.');
    }

    final invoice = Invoice(
      id: _loadedInvoice?.id,
      tenantId: tenantId,
      invoiceNumber: _invoiceNumberController.text.trim(),
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

    setState(() => _isSaving = true);

    try {
      final saved = await _salesService.saveInvoice(invoice);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Borrador guardado correctamente'),
          backgroundColor: Colors.green,
        ),
      );

      if (widget.invoiceId == null && saved.id != null) {
        // Navigate to the saved invoice detail page
        context.go('/sales/invoices/${saved.id}');
        return;
      }

      _applyInvoice(saved);
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
                  ? const Center(child: CircularProgressIndicator())
                  : _buildForm(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
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
            _scannerEnabled ? Icons.qr_code_scanner : Icons.qr_code_scanner_outlined,
            color: _scannerEnabled ? Colors.green : null,
          ),
          tooltip: _scannerEnabled ? 'Desactivar Escáner' : 'Activar Escáner',
          style: IconButton.styleFrom(
            backgroundColor: _scannerEnabled 
                ? Colors.green.withOpacity(0.1) 
                : null,
          ),
        ),
      );
      actionButtons.add(const SizedBox(width: 8));
      
      if (_loadedInvoice != null) {
        actionButtons.add(
          OutlinedButton.icon(
            onPressed: _isSaving ? null : _cancelEditing,
            icon: const Icon(Icons.close),
            label: const Text('Cancelar'),
          ),
        );
      }
      actionButtons.add(
        AppButton(
          text: 'Guardar borrador',
          icon: Icons.save_outlined,
          onPressed: _isSaving ? null : _saveInvoice,
          isLoading: _isSaving,
        ),
      );
    } else {
      // Not editing - show workflow buttons based on status
      if (_status == InvoiceStatus.draft) {
        actionButtons.add(
          OutlinedButton.icon(
            onPressed: _isUpdatingStatus ? null : _startEditing,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar'),
          ),
        );
        actionButtons.add(const SizedBox(width: 8));
        if (_canMarkAsSent) {
          actionButtons.add(
            FilledButton.icon(
              onPressed: _isUpdatingStatus ? null : () => _updateStatus(InvoiceStatus.sent),
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
        }
      } else if (_status == InvoiceStatus.sent) {
        actionButtons.add(
          OutlinedButton.icon(
            onPressed: _isUpdatingStatus ? null : () => _updateStatus(InvoiceStatus.draft),
            icon: const Icon(Icons.undo_outlined),
            label: const Text('Volver a borrador'),
          ),
        );
        actionButtons.add(const SizedBox(width: 8));
        actionButtons.add(
          FilledButton.icon(
            onPressed: _isUpdatingStatus ? null : () => _updateStatus(InvoiceStatus.confirmed),
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
      } else if (_status == InvoiceStatus.confirmed) {
        actionButtons.add(
          OutlinedButton.icon(
            onPressed: _isUpdatingStatus ? null : () => _updateStatus(InvoiceStatus.sent),
            icon: const Icon(Icons.undo_outlined),
            label: const Text('Volver a enviado'),
          ),
        );
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
      } else if (_status == InvoiceStatus.paid) {
        // Paid status: Can only undo payment (which deletes payment record)
        // Status will auto-revert to 'confirmed' via database trigger
        actionButtons.add(
          OutlinedButton.icon(
            onPressed: _undoLastPayment,
            icon: const Icon(Icons.undo_outlined, color: Colors.red),
            label: const Text('Deshacer pago', style: TextStyle(color: Colors.red)),
          ),
        );
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
      _buildStatusChip(theme),
      ...actionButtons,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              // Check if we should return to a specific page (e.g., from pegas table)
              final returnTo = GoRouterState.of(context).uri.queryParameters['returnTo'];
              if (returnTo != null && returnTo.isNotEmpty) {
                context.go(returnTo);
              } else {
                // Default: Navigate back to invoice list
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

  Widget _buildForm(ThemeData theme) {
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
                        if (_shouldShowReadOnlyNotice)
                          _buildReadOnlyNotice(theme),
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

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_shouldShowReadOnlyNotice)
                  _buildReadOnlyNotice(theme),
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
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
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
                border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Table header
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Row(
                  children: [
                    // # column
                    Container(
                      width: _colIndexWidth,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                      right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                    ),
                  ),
                  child: Center(
                    child: Text('#', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ),
                
                // Artículo column (flex to fill remaining space)
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 250), // Reduced from 300 for better shrinking
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                      ),
                    ),
                    child: Text(
                      'DETALLES DEL ARTÍCULO',
                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
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
                      right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                    ),
                  ),
                  child: Center(
                    child: Text('CANTIDAD', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ),
                
                // Tarifa column
                Container(
                  width: _colPriceWidth,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                    ),
                  ),
                  child: Center(
                    child: Text('TARIFA', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ),
                
                // Descuento column
                Container(
                  width: _colDiscountWidth,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                    ),
                  ),
                  child: Center(
                    child: Text('DESCUENTO', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ),
                
                // Importe column
                Container(
                  width: _colTotalWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text('IMPORTE', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.right),
                ),
                
                // Actions column
                SizedBox(width: _colActionsWidth),
              ],
            ),
          ),
          
          // Header/Content divider
          Divider(height: 1, thickness: 1, color: theme.colorScheme.outline.withOpacity(0.2)),
        
          // Line items
          Column(
            children: [
            // Line items (all states)
            if (_lineEntries.isNotEmpty)
              ..._lineEntries.asMap().entries.map((entry) => 
                _buildCompactLineRow(theme, entry.key + 1, entry.value)
              ),
              
              // Add new line button (only when editing)
              if (_canEditFields)
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
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
                              right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                            ),
                          ),
                        ),
                        
                        // Search field spanning the product details column
                        Expanded(
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 250), // Match header column
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                              ),
                            ),
                            child: SmartProductField(
                              key: ValueKey(_autocompleteKey), // Reset field when key changes
                              onProductChanged: (selection) {
                                if (selection == null) return;
                                if (selection.isCatalogProduct && selection.product != null) {
                                  _addProductLine(selection.product!);
                                } else if (!selection.isCatalogProduct && selection.productName != null) {
                                  _addCustomItemLine(selection.productName!);
                                }
                              },
                              allowCustomItems: true,
                              showCost: false,
                              hintText: 'Buscar por nombre o SKU, o escribir artículo personalizado...',
                            ),
                          ),
                        ),
                        
                        // Empty spaces for other columns to maintain alignment
                        Container(
                          width: _colQuantityWidth,
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                            ),
                          ),
                        ),
                        Container(
                          width: _colPriceWidth,
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
                            ),
                          ),
                        ),
                        Container(
                          width: _colDiscountWidth,
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
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

  /// Builds a single line row using the universal LineRowWrapper.
  /// Hover state is managed locally inside the wrapper, preventing SmartProductField rebuilds.
  Widget _buildCompactLineRow(ThemeData theme, int index, _InvoiceLineEntry entry) {
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
        // Product details column - uses CACHED widget from entry
        LineColumn(
          expanded: true,
          minWidth: 250,
          padding: const EdgeInsets.all(12),
          child: entry.buildSmartProductField(
            context,
            theme,
            _canEditFields,
            () {}, // No setState needed - hover is local to wrapper
            () => _autoAddEmptyLineIfNeeded(),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: _canEditFields ? const OutlineInputBorder() : InputBorder.none,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                ],
              ),
              
              // Stock warning (hide for services)
              if (line.product != null && !line.product!.isService && line.product!.stockQuantity < line.quantity)
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: _canEditFields ? const OutlineInputBorder() : InputBorder.none,
                prefixText: '\$ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: _canEditFields ? const OutlineInputBorder() : InputBorder.none,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                // Dropdown for % or fixed amount (placeholder)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3)),
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
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Tratamiento de IVA'),
          subtitle: DropdownButtonFormField<TaxTreatment>(
            value: _taxTreatment,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            items: const [
              DropdownMenuItem(
                value: TaxTreatment.noTax,
                child: Text('Sin IVA'),
              ),
              DropdownMenuItem(
                value: TaxTreatment.taxIncluded,
                child: Text('IVA Incluido (19%)'),
              ),
            ],
            onChanged: _canEditFields
                ? (value) {
                    if (value != null) {
                      setState(() => _taxTreatment = value);
                    }
                  }
                : null,
          ),
        ),
        // 💳 Payment method hint (only show when ready to confirm)
        if (_status == InvoiceStatus.sent)
          ListTile(
            leading: const Icon(Icons.payment),
            title: const Text('Método de pago esperado'),
            subtitle: DropdownButtonFormField<String>(
              value: _paymentMethodHint,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Selecciona para validación automática',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'card',
                  child: Text('💳 Tarjeta (se agregará IVA si falta)'),
                ),
                DropdownMenuItem(
                  value: 'other',
                  child: Text('💵 Efectivo/Transferencia'),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _paymentMethodHint = value;
                  // Auto-add tax if selecting card
                  if (value == 'card' && _taxTreatment == TaxTreatment.noTax) {
                    _taxTreatment = TaxTreatment.taxIncluded;
                  }
                });
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSummary(ThemeData theme) {
    final textStyle =
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    return Column(
      children: [
        _buildSummaryRow('Subtotal', ChileanUtils.formatCurrency(_subtotal),
            textStyle, theme),
        if (_taxTreatment == TaxTreatment.taxIncluded) ...[
          const SizedBox(height: 8),
          _buildSummaryRow(
              'Neto', ChileanUtils.formatCurrency(_netAmount), textStyle, theme),
          const SizedBox(height: 8),
          _buildSummaryRow(
              'IVA (19%)', ChileanUtils.formatCurrency(_iva), textStyle, theme),
        ],
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
  });

  final String? productId; // Nullable for ad-hoc items
  final Product? product;
  final double cost;
  final String? description; // Custom notes for line item
  final bool isCatalogProduct; // Track if catalog vs ad-hoc
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
        descriptionController = TextEditingController(text: line.description ?? ''),
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
    // Don't listen to productNameController - only update on selection
  }

  InvoiceItem toInvoiceItem() {
    return InvoiceItem(
      productId: line.productId, // Nullable - null for ad-hoc items
      productName: line.name,
      productSku: line.sku,
      description: descriptionController.text.trim().isEmpty 
          ? null 
          : descriptionController.text.trim(),
      isCatalogProduct: line.isCatalogProduct,
      quantity: line.quantity,
      unitPrice: line.unitPrice,
      discount: line.discount,
      lineTotal: line.netAmount,
      cost: line.cost,
    );
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
  
  Widget buildSmartProductField(BuildContext context, ThemeData theme, bool canEdit, VoidCallback onUpdate, VoidCallback onAutoAdd) {
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
  
  void _showProductDetailsPane(BuildContext context, Product product, ThemeData theme) {
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
                      border: Border(bottom: BorderSide(color: theme.dividerColor)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Detalles del artículo', style: theme.textTheme.titleLarge),
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.imageUrl != null && product.imageUrl!.isNotEmpty)
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
                                  child: Image.network(product.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2_outlined, size: 80)),
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),
                          Text(product.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          _detailRow('SKU', product.sku),
                          if (product.description != null && product.description!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text('Descripción', style: theme.textTheme.labelLarge),
                            const SizedBox(height: 4),
                            Text(product.description!),
                          ],
                          const SizedBox(height: 16),
                          _detailRow('Precio', '\$${product.price.toStringAsFixed(0)}'),
                          _detailRow('Costo', '\$${product.cost.toStringAsFixed(0)}'),
                          _detailRow('Stock', '${product.stockQuantity}'),
                          if (product.brand != null && product.brand!.isNotEmpty)
                            _detailRow('Marca', product.brand!),
                          if (product.model != null && product.model!.isNotEmpty)
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
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOut)),
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
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
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

