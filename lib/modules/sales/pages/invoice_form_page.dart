import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/product.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';

class InvoiceFormPage extends StatefulWidget {
  final String? invoiceId;

  const InvoiceFormPage({super.key, this.invoiceId});

  @override
  State<InvoiceFormPage> createState() => _InvoiceFormPageState();
}

class _InvoiceFormPageState extends State<InvoiceFormPage> {
  static const double _ivaRate = 0.19;

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

  Customer? _selectedCustomer;
  Invoice? _loadedInvoice;
  DateTime _issueDate = DateTime.now();
  DateTime? _dueDate;
  InvoiceStatus _status = InvoiceStatus.draft;

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
      _status == InvoiceStatus.sent &&
      _outstandingAmount > 0.01;
  bool get _shouldShowReadOnlyNotice =>
      !_canEditFields && _status == InvoiceStatus.draft;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.invoiceId == null;
    _dueDate = _issueDate.add(const Duration(days: 30));
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _referenceController.dispose();
    for (final entry in _lineEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    _salesService = context.read<SalesService>();
    _customerService = context.read<CustomerService>();
    _inventoryService = context.read<shared_inventory.InventoryService>();

    try {
      final customersFuture = _customerService.getCustomers();
      final productsFuture = _inventoryService.getProducts(forceRefresh: true);
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
        _invoiceNumberController.text = _buildSuggestedNumber();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error preparando el formulario: $e'),
            backgroundColor: Colors.red,
          ),
        );
        _invoiceNumberController.text = _buildSuggestedNumber();
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
        : _buildSuggestedNumber();
    _referenceController.text = invoice.reference ?? '';

    Customer? resolvedCustomer;
    if (invoice.customerId != null) {
      resolvedCustomer = _cachedCustomers.firstWhere(
        (customer) => customer.id == invoice.customerId,
        orElse: () => Customer(
          id: invoice.customerId,
          name: invoice.customerName ?? 'Cliente',
          rut: invoice.customerRut ?? '',
          email: null,
        ),
      );
    }

    final newEntries = <_InvoiceLineEntry>[];
    for (final item in invoice.items) {
      Product? product;
      for (final candidate in _cachedProducts) {
        if (candidate.id == item.productId) {
          product = candidate;
          break;
        }
      }

      final entry = _InvoiceLineEntry(
        _InvoiceLine(
          productId: item.productId,
          product: product,
          name: item.productName ?? product?.name ?? 'Producto',
          sku: item.productSku ?? product?.sku ?? '',
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          discount: item.discount,
          cost: item.cost,
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

  Future<void> _markAsSent() async {
    final invoiceId = _currentInvoiceId;
    if (invoiceId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Guarda la factura como borrador antes de enviarla.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isUpdatingStatus = true);
    try {
      final updated = await _salesService.updateInvoiceStatus(
          invoiceId, InvoiceStatus.sent);
      if (updated != null && mounted) {
        _applyInvoice(updated);
        await _refreshInvoiceById(invoiceId);
      } else if (mounted) {
        await _refreshInvoiceById(invoiceId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Factura marcada como enviada'),
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

  double get _subtotal {
    final value = _lineEntries.fold<double>(
        0, (sum, entry) => sum + entry.line.netAmount);
    return value < 0 ? 0 : value;
  }

  double get _iva => _subtotal * _ivaRate;

  double get _total => _subtotal + _iva;

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

  Future<void> _openProductSelector() async {
    if (_cachedProducts.isEmpty) {
      try {
        final products =
            await _inventoryService.getProducts(forceRefresh: true);
        _cachedProducts
          ..clear()
          ..addAll(products);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudieron cargar los productos: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    final selected = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _ProductSelector(
          inventoryService: _inventoryService,
          initialProducts: List<Product>.from(_cachedProducts),
        );
      },
    );

    if (selected != null && mounted) {
      _addProductLine(selected);
    }
  }

  void _addProductLine(Product product) {
    for (final entry in _lineEntries) {
      if (entry.line.productId == product.id) {
        entry.line.quantity += 1;
        entry.quantityController.text = entry.line.quantity.toStringAsFixed(0);
        _handleLinesChanged();
        return;
      }
    }

    final line = _InvoiceLine(
      productId: product.id,
      product: product,
      name: product.name,
      sku: product.sku,
      quantity: 1,
      unitPrice: product.price,
      discount: 0,
      cost: product.cost,
    );

    final entry = _InvoiceLineEntry(line);
    entry.attachListeners(_handleLinesChanged);

    setState(() {
      _lineEntries.add(entry);
    });
  }

  void _removeLine(_InvoiceLineEntry entry) {
    setState(() {
      _lineEntries.remove(entry);
      entry.dispose();
    });
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

    final invoice = Invoice(
      id: _loadedInvoice?.id,
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
        // Use pop and push instead of go to maintain navigation stack
        context.pop(); // Remove the form page from stack
        context.push('/sales/invoices/${saved.id}'); // Show the detail page
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
    return MainLayout(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(theme),
                Expanded(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: _buildForm(theme),
                  ),
                ),
              ],
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
      if (_status == InvoiceStatus.draft) {
        actionButtons.add(
          OutlinedButton.icon(
            onPressed: _isUpdatingStatus ? null : _startEditing,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar'),
          ),
        );
        if (_canMarkAsSent) {
          actionButtons.add(
            FilledButton.icon(
              onPressed: _isUpdatingStatus ? null : _markAsSent,
              icon: _isUpdatingStatus
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text('Marcar como enviado'),
            ),
          );
        }
      } else if (_canRegisterPayment) {
        actionButtons.add(
          FilledButton.icon(
            onPressed: _openPaymentForm,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Pagar factura'),
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
            onPressed: () => context.pop(),
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
    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 1180;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
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
                const SizedBox(width: 24),
                if (_shouldShowReadOnlyNotice)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildReadOnlyNotice(theme),
                  ),
                SizedBox(
                  width: 360,
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
              ],
            );
          }

          return Column(
            children: [
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
          );
        },
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add_shopping_cart_outlined),
            label: const Text('Agregar producto'),
            onPressed: _canEditFields ? _openProductSelector : null,
          ),
        ),
        const SizedBox(height: 12),
        if (_lineEntries.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.production_quantity_limits,
                    size: 48, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  'Aún no has agregado productos',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Usa el buscador para seleccionar artículos del inventario.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          Column(
            children: _lineEntries
                .map((entry) => _buildLineCard(theme, entry))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildLineCard(ThemeData theme, _InvoiceLineEntry entry) {
    final line = entry.line;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        line.sku.isEmpty ? 'SKU pendiente' : 'SKU: ${line.sku}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  onPressed: _canEditFields ? () => _removeLine(entry) : null,
                  icon: Icon(Icons.delete_outline,
                      color: theme.colorScheme.error),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: entry.quantityController,
                    enabled: _canEditFields,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: entry.unitPriceController,
                    enabled: _canEditFields,
                    decoration: const InputDecoration(
                      labelText: 'Precio unitario (sin IVA)',
                      prefixText: 'CLP ',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: entry.discountController,
                    enabled: _canEditFields,
                    decoration: const InputDecoration(
                      labelText: 'Descuento',
                      prefixText: 'CLP ',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Total línea: ${ChileanUtils.formatCurrency(line.netAmount)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (line.product != null && line.product!.trackStock)
                  Text(
                    'Stock disponible: ${line.product!.stockQuantity}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: line.product!.stockQuantity <=
                              line.product!.minStockLevel
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
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
    return Column(
      children: [
        _buildSummaryRow('Subtotal', ChileanUtils.formatCurrency(_subtotal),
            textStyle, theme),
        const SizedBox(height: 8),
        _buildSummaryRow(
            'IVA (19%)', ChileanUtils.formatCurrency(_iva), textStyle, theme),
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
    required this.productId,
    this.product,
    required this.name,
    required this.sku,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.cost,
  });

  final String productId;
  final Product? product;
  final double cost;
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
  _InvoiceLineEntry(this.line)
      : quantityController =
            TextEditingController(text: line.quantity.toStringAsFixed(0)),
        unitPriceController =
            TextEditingController(text: line.unitPrice.toStringAsFixed(0)),
        discountController =
            TextEditingController(text: line.discount.toStringAsFixed(0));

  final _InvoiceLine line;
  final TextEditingController quantityController;
  final TextEditingController unitPriceController;
  final TextEditingController discountController;
  VoidCallback? _listener;

  void attachListeners(VoidCallback listener) {
    _listener = listener;
    quantityController.addListener(_onQuantityChanged);
    unitPriceController.addListener(_onUnitPriceChanged);
    discountController.addListener(_onDiscountChanged);
  }

  InvoiceItem toInvoiceItem() {
    return InvoiceItem(
      productId: line.productId,
      productName: line.name,
      productSku: line.sku,
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
      _listener?.call();
    }
  }

  void _onUnitPriceChanged() {
    final value =
        double.tryParse(unitPriceController.text.replaceAll(',', '.'));
    if (value != null && value >= 0) {
      line.unitPrice = value;
      _listener?.call();
    }
  }

  void _onDiscountChanged() {
    final value = double.tryParse(discountController.text.replaceAll(',', '.'));
    if (value != null && value >= 0) {
      line.discount = value;
      _listener?.call();
    }
  }

  void dispose() {
    quantityController.dispose();
    unitPriceController.dispose();
    discountController.dispose();
  }
}

class _CustomerSelector extends StatefulWidget {
  final List<Customer> initialCustomers;
  final CustomerService customerService;

  const _CustomerSelector({
    required this.initialCustomers,
    required this.customerService,
  });

  @override
  State<_CustomerSelector> createState() => _CustomerSelectorState();
}

class _CustomerSelectorState extends State<_CustomerSelector> {
  late List<Customer> _customers = widget.initialCustomers;
  Timer? _debounce;
  bool _isSearching = false;

  @override
  void dispose() {
    _debounce?.cancel();
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
              decoration: const InputDecoration(
                labelText: 'Buscar cliente',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearchChanged,
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

class _ProductSelector extends StatefulWidget {
  final shared_inventory.InventoryService inventoryService;
  final List<Product> initialProducts;

  const _ProductSelector({
    required this.inventoryService,
    required this.initialProducts,
  });

  @override
  State<_ProductSelector> createState() => _ProductSelectorState();
}

class _ProductSelectorState extends State<_ProductSelector> {
  late List<Product> _products = widget.initialProducts;
  Timer? _debounce;
  bool _isSearching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String term) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() => _isSearching = true);
      try {
        final results = term.trim().isEmpty
            ? widget.initialProducts
            : await widget.inventoryService.searchProducts(term);
        if (mounted) {
          setState(() => _products = results);
        }
      } catch (_) {
        if (mounted) {
          setState(() => _products = widget.initialProducts);
        }
      } finally {
        if (mounted) {
          setState(() => _isSearching = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
              decoration: const InputDecoration(
                labelText: 'Buscar producto por nombre, SKU o marca',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 16),
            if (_isSearching) const LinearProgressIndicator(minHeight: 2),
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: _products.isEmpty
                  ? const Center(child: Text('No se encontraron productos'))
                  : ListView.separated(
                      itemCount: _products.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final product = _products[index];
                        return ListTile(
                          title: Text(product.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('SKU: ${product.sku}'),
                              if (product.brand != null &&
                                  product.brand!.isNotEmpty)
                                Text('Marca: ${product.brand}'),
                              Text('Stock: ${product.stockQuantity}'),
                            ],
                          ),
                          trailing: Text(
                            ChileanUtils.formatCurrency(product.price),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () => Navigator.of(context).pop(product),
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
