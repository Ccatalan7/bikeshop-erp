import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/supplier.dart' as shared_supplier;
import '../../../shared/services/inventory_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../models/purchase_invoice.dart';
import '../services/purchase_service.dart';

class PurchaseInvoiceFormPage extends StatefulWidget {
  final String? invoiceId;
  final bool isPrepayment;

  const PurchaseInvoiceFormPage({
    super.key,
    this.invoiceId,
    this.isPrepayment = false,
  });

  @override
  State<PurchaseInvoiceFormPage> createState() => _PurchaseInvoiceFormPageState();
}

class _PurchaseInvoiceFormPageState extends State<PurchaseInvoiceFormPage> {
  static const double _ivaRate = 0.19;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _invoiceNumberController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final List<_PurchaseLineEntry> _lineEntries = [];

  late PurchaseService _purchaseService;
  late InventoryService _inventoryService;

  shared_supplier.Supplier? _selectedSupplier;
  PurchaseInvoice? _loadedInvoice;
  DateTime _issueDate = DateTime.now();
  DateTime? _dueDate;
  PurchaseInvoiceStatus _status = PurchaseInvoiceStatus.draft;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUpdatingStatus = false;

  List<shared_supplier.Supplier> _supplierCache = const [];
  List<Product> _productCache = const [];

  @override
  void initState() {
    super.initState();
    _dueDate = _issueDate.add(const Duration(days: 30));
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    for (final entry in _lineEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    _purchaseService = context.read<PurchaseService>();
    _inventoryService = context.read<InventoryService>();

    try {
      final results = await Future.wait([
        _purchaseService.getSuppliers(forceRefresh: true),
        _inventoryService.getProducts(forceRefresh: true),
      ]);

      _supplierCache = results[0] as List<shared_supplier.Supplier>;
      _productCache = results[1] as List<Product>;

      if (widget.invoiceId != null) {
        final invoice = await _purchaseService.getPurchaseInvoice(widget.invoiceId!);
        if (invoice != null) {
          _loadedInvoice = invoice;
          _applyInvoice(invoice);
        }
      } else {
        _invoiceNumberController.text = _buildSuggestedNumber();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error preparando el formulario: $e'),
          backgroundColor: Colors.red,
        ),
      );
      _invoiceNumberController.text = _buildSuggestedNumber();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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

    _selectedSupplier = _supplierCache.firstWhere(
      (supplier) => supplier.id == invoice.supplierId,
      orElse: () => shared_supplier.Supplier(
        id: invoice.supplierId ?? '',
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
          trackStock: true,
          isActive: true,
          createdAt: item.createdAt,
          updatedAt: item.createdAt,
        ),
      );

      final entry = _PurchaseLineEntry(
        line: PurchaseInvoiceItem(
          productId: item.productId,
          productName: product.name,
          productSku: product.sku,
          quantity: item.quantity,
          unitCost: item.unitCost,
          discount: item.discount,
          ivaRate: item.ivaRate,
        ),
      );
      entry.attachListeners(_recalculateTotals);
      _lineEntries.add(entry);
    }
  }

  String _buildSuggestedNumber() {
    final now = DateTime.now();
    final datePortion = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timePortion = now.millisecondsSinceEpoch.toString().substring(7);
    return 'FC-$datePortion-$timePortion';
  }

  double get _subtotal => _lineEntries.fold<double>(0, (sum, entry) => sum + entry.line.netAmountClamped);

  double get _iva => _subtotal * _ivaRate;

  double get _total => _subtotal + _iva;

  void _recalculateTotals() {
    if (mounted) setState(() {});
  }

  Future<void> _openSupplierSelector() async {
    if (_supplierCache.isEmpty) {
      try {
        _supplierCache = await _purchaseService.getSuppliers(forceRefresh: true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar proveedores: $e'), backgroundColor: Colors.red),
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

    if (selected != null && mounted) {
      setState(() => _selectedSupplier = selected);
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
        SnackBar(content: Text('Error al crear proveedor: $e'), backgroundColor: Colors.red),
      );
      return null;
    }
  }

  Future<void> _openProductSelector() async {
    if (_productCache.isEmpty) {
      try {
        _productCache = await _inventoryService.getProducts(forceRefresh: true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar productos: $e'), backgroundColor: Colors.red),
        );
        return;
      }
    }

    if (!mounted) return;

    // Filter only products (not services) for purchase invoices
    final purchasableProducts = _productCache
        .where((p) => p.productType == ProductType.product)
        .toList();

    final selected = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProductSelector(products: purchasableProducts),
    );

    if (selected != null) {
      _addProductLine(selected);
    }
  }

  void _addProductLine(Product product) {
    for (final entry in _lineEntries) {
      if (entry.line.productId == product.id) {
        entry.line = entry.line.copyWith(quantity: entry.line.quantity + 1);
        entry.quantityController.text = entry.line.quantity.toStringAsFixed(0);
        _recalculateTotals();
        return;
      }
    }

    final entry = _PurchaseLineEntry(
      line: PurchaseInvoiceItem(
        productId: product.id,
        productName: product.name,
        productSku: product.sku,
        quantity: 1,
        unitCost: product.cost > 0 ? product.cost : product.price,
        discount: 0,
        ivaRate: _ivaRate,
      ),
    );
    entry.attachListeners(_recalculateTotals);

    setState(() {
      _lineEntries.add(entry);
    });
  }

  Future<void> _pickDate({required bool isIssueDate}) async {
    final initial = isIssueDate ? _issueDate : (_dueDate ?? _issueDate.add(const Duration(days: 30)));

    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: isIssueDate ? 'Fecha de emisión' : 'Fecha de vencimiento',
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
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona o crea un proveedor antes de guardar.'),
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

    final items = _lineEntries
        .where((entry) => entry.line.quantity > 0)
        .map((entry) => entry.line)
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

    final invoice = PurchaseInvoice(
      id: _loadedInvoice?.id,
      invoiceNumber: _invoiceNumberController.text.trim().isEmpty
          ? _buildSuggestedNumber()
          : _invoiceNumberController.text.trim(),
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
      items: items,
      // Set prepayment model when creating new invoice
      prepaymentModel: _loadedInvoice != null 
          ? _loadedInvoice!.prepaymentModel 
          : widget.isPrepayment,
    );

    setState(() => _isSaving = true);

    try {
      await _purchaseService.savePurchaseInvoice(invoice);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Factura de compra guardada correctamente'),
          backgroundColor: Colors.green,
        ),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la factura: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _markAsReceived() async {
    if (widget.invoiceId == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar recepción'),
        content: const Text(
          '¿Marcar esta factura como recibida?\n\n'
          'Esto aumentará el inventario de todos los productos '
          'y creará los asientos contables correspondientes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    setState(() => _isUpdatingStatus = true);
    
    try {
      final updated = await _purchaseService.markAsReceived(widget.invoiceId!);
      if (!mounted) return;
      
      if (updated != null) {
        setState(() {
          _status = updated.status;
          _loadedInvoice = updated;
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Factura marcada como recibida. Inventario actualizado.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar estado: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  Future<void> _markAsPaid() async {
    if (widget.invoiceId == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar pago'),
        content: const Text(
          '¿Marcar esta factura como pagada?\n\n'
          'Esto registrará el pago de la factura en el sistema contable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    setState(() => _isUpdatingStatus = true);
    
    try {
      final updated = await _purchaseService.markAsPaid(widget.invoiceId!);
      if (!mounted) return;
      
      if (updated != null) {
        setState(() {
          _status = updated.status;
          _loadedInvoice = updated;
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Factura marcada como pagada'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar estado: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  Future<void> _revertToDraft() async {
    if (widget.invoiceId == null) return;
    
    final statusName = _status == PurchaseInvoiceStatus.received 
        ? 'recibida' 
        : 'pagada';
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Confirmar reversión'),
        content: Text(
          '¿Volver esta factura $statusName a BORRADOR?\n\n'
          '⚠️ ADVERTENCIA: Esto reversará:\n'
          '• Los movimientos de inventario (reducirá el stock)\n'
          '• Los asientos contables (creará asientos de reverso)\n\n'
          'Solo usa esta opción si cometiste un error.\n\n'
          '¿Estás seguro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sí, revertir'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    setState(() => _isUpdatingStatus = true);
    
    try {
      final updated = await _purchaseService.revertToDraft(widget.invoiceId!);
      if (!mounted) return;
      
      if (updated != null) {
        setState(() {
          _status = updated.status;
          _loadedInvoice = updated;
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Factura revertida a borrador. Inventario y contabilidad actualizados.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al revertir: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  Future<void> _revertToReceived() async {
    if (widget.invoiceId == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar reversión'),
        content: const Text(
          '¿Volver esta factura pagada a RECIBIDA?\n\n'
          'Esto solo cambiará el estado. El inventario y '
          'la contabilidad se mantendrán intactos.\n\n'
          '¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Sí, revertir'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    setState(() => _isUpdatingStatus = true);
    
    try {
      final updated = await _purchaseService.revertToReceived(widget.invoiceId!);
      if (!mounted) return;
      
      if (updated != null) {
        setState(() {
          _status = updated.status;
          _loadedInvoice = updated;
        });
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Factura revertida a recibida'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al revertir: $e'),
          backgroundColor: Colors.red,
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
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('Eliminar factura'),
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
          backgroundColor: Colors.green,
        ),
      );
      
      // Return to list page
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  void _removeLine(_PurchaseLineEntry entry) {
    setState(() {
      _lineEntries.remove(entry);
      entry.dispose();
    });
    _recalculateTotals();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildForm(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final canMarkAsReceived = widget.invoiceId != null && 
        _status == PurchaseInvoiceStatus.draft;
    final canMarkAsPaid = widget.invoiceId != null && 
        _status == PurchaseInvoiceStatus.received;
    final canRevertToDraft = widget.invoiceId != null && 
        (_status == PurchaseInvoiceStatus.received || _status == PurchaseInvoiceStatus.paid);
    final canRevertToReceived = widget.invoiceId != null && 
        _status == PurchaseInvoiceStatus.paid;
    final canDelete = widget.invoiceId != null && 
        _status == PurchaseInvoiceStatus.draft;
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.invoiceId != null ? 'Editar factura de compra' : 'Nueva factura de compra',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                if (widget.invoiceId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: _buildStatusChip(_status),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Delete button (only for draft invoices)
          if (canDelete) ...[
            IconButton(
              onPressed: _isUpdatingStatus ? null : _deleteInvoice,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Eliminar factura',
              style: IconButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.1),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Reversal buttons (backward flow)
          if (canRevertToReceived) ...[
            ElevatedButton.icon(
              onPressed: _isUpdatingStatus ? null : _revertToReceived,
              icon: _isUpdatingStatus
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.undo),
              label: const Text('Volver a Recibida'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (canRevertToDraft) ...[
            ElevatedButton.icon(
              onPressed: _isUpdatingStatus ? null : _revertToDraft,
              icon: _isUpdatingStatus
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.undo),
              label: const Text('Volver a Borrador'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[700],
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Forward flow buttons
          if (canMarkAsReceived) ...[
            ElevatedButton.icon(
              onPressed: _isUpdatingStatus ? null : _markAsReceived,
              icon: _isUpdatingStatus 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.inventory_2),
              label: const Text('Marcar como Recibida'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (canMarkAsPaid) ...[
            ElevatedButton.icon(
              onPressed: _isUpdatingStatus ? null : _markAsPaid,
              icon: _isUpdatingStatus
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.payment),
              label: const Text('Marcar como Pagada'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          AppButton(
            text: 'Guardar',
            icon: Icons.save,
            onPressed: _isSaving ? null : _saveInvoice,
            isLoading: _isSaving,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(PurchaseInvoiceStatus status) {
    Color color;
    IconData icon;
    
    switch (status) {
      case PurchaseInvoiceStatus.draft:
        color = Colors.grey;
        icon = Icons.edit;
        break;
      case PurchaseInvoiceStatus.sent:
        color = Colors.orange;
        icon = Icons.send;
        break;
      case PurchaseInvoiceStatus.confirmed:
        color = Colors.purple;
        icon = Icons.verified;
        break;
      case PurchaseInvoiceStatus.received:
        color = Colors.green;
        icon = Icons.inventory_2;
        break;
      case PurchaseInvoiceStatus.paid:
        color = Colors.blue;
        icon = Icons.check_circle;
        break;
      case PurchaseInvoiceStatus.cancelled:
        color = Colors.red;
        icon = Icons.cancel;
        break;
    }
    
    return Chip(
      avatar: Icon(icon, size: 16, color: Colors.white),
      label: Text(
        status.displayName,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ListView(
        children: [
          _buildSupplierCard(),
          const SizedBox(height: 16),
          _buildInvoiceMetaCard(),
          const SizedBox(height: 16),
          _buildLinesCard(),
          const SizedBox(height: 16),
          _buildSummaryCard(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSupplierCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[300]!)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.store_outlined),
                const SizedBox(width: 8),
                const Text('Proveedor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openSupplierSelector,
                  icon: const Icon(Icons.search),
                  label: Text(_selectedSupplier == null ? 'Seleccionar' : 'Cambiar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_selectedSupplier == null)
              const Text(
                'No hay proveedor seleccionado. Toca "Seleccionar" para elegir uno o crear uno nuevo.',
                style: TextStyle(color: Colors.grey),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedSupplier!.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (_selectedSupplier!.rut != null && _selectedSupplier!.rut!.isNotEmpty)
                    Text('RUT: ${ChileanUtils.formatRut(_selectedSupplier!.rut!)}'),
                  if (_selectedSupplier!.email != null && _selectedSupplier!.email!.isNotEmpty)
                    Text('Email: ${_selectedSupplier!.email}'),
                  if (_selectedSupplier!.phone != null && _selectedSupplier!.phone!.isNotEmpty)
                    Text('Teléfono: ${_selectedSupplier!.phone}'),
                  if (_selectedSupplier!.address != null && _selectedSupplier!.address!.isNotEmpty)
                    Text('Dirección: ${_selectedSupplier!.address}'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceMetaCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[300]!)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Detalles de la factura', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _invoiceNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Número de factura',
                      hintText: 'Ej: FC-0001',
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Ingresa el número de factura'
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<PurchaseInvoiceStatus>(
                    value: _status,
                    decoration: const InputDecoration(labelText: 'Estado'),
                    items: PurchaseInvoiceStatus.values
                        .map((status) => DropdownMenuItem(
                              value: status,
                              child: Text(status.displayName),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _status = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(isIssueDate: true),
                    child: IgnorePointer(
                      child: TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de emisión',
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        controller: TextEditingController(
                          text: ChileanUtils.formatDate(_issueDate),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(isIssueDate: false),
                    child: IgnorePointer(
                      child: TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de vencimiento',
                          suffixIcon: Icon(Icons.event),
                        ),
                        controller: TextEditingController(
                          text: ChileanUtils.formatDate(_dueDate ?? _issueDate.add(const Duration(days: 30))),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Referencia (opcional)',
                hintText: 'Orden de compra, guía de despacho, etc.',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notas internas (opcional)',
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinesCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[300]!)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.list_alt_outlined),
                const SizedBox(width: 8),
                const Text('Productos y servicios', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openProductSelector,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar producto'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_lineEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Center(
                  child: Text(
                    'Agrega productos o servicios para registrar el costo de la compra.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Column(
                children: [
                  _buildLinesTableHeader(),
                  const Divider(),
                  ..._lineEntries.map((entry) => _PurchaseLineRow(
                        entry: entry,
                        onRemove: () => _removeLine(entry),
                      )),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinesTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: const [
          Expanded(flex: 4, child: Text('Producto', style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('Cantidad', style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('Costo unitario', style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('Descuento', style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('Subtotal', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.end)),
          SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[300]!)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Resumen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _buildSummaryRow('Subtotal', ChileanUtils.formatCurrency(_subtotal)),
            _buildSummaryRow('IVA (19%)', ChileanUtils.formatCurrency(_iva)),
            const Divider(),
            _buildSummaryRow('Total a pagar', ChileanUtils.formatCurrency(_total), isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: isTotal ? FontWeight.bold : FontWeight.normal))),
          Text(
            value,
            style: TextStyle(fontSize: isTotal ? 18 : 16, fontWeight: isTotal ? FontWeight.bold : FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _PurchaseLineEntry {
  _PurchaseLineEntry({required PurchaseInvoiceItem line})
      : line = line,
        quantityController = TextEditingController(text: line.quantity.toStringAsFixed(0)),
        unitCostController = TextEditingController(text: line.unitCost.toStringAsFixed(0)),
        discountController = TextEditingController(text: line.discount.toStringAsFixed(0));

  PurchaseInvoiceItem line;
  final TextEditingController quantityController;
  final TextEditingController unitCostController;
  final TextEditingController discountController;

  void attachListeners(VoidCallback onChanged) {
    quantityController.addListener(() {
      final value = double.tryParse(quantityController.text.replaceAll(',', '.'));
      if (value != null && value >= 0) {
        line = line.copyWith(quantity: value);
        onChanged();
      }
    });
    unitCostController.addListener(() {
      final value = double.tryParse(unitCostController.text.replaceAll(',', '.'));
      if (value != null && value >= 0) {
        line = line.copyWith(unitCost: value);
        onChanged();
      }
    });
    discountController.addListener(() {
      final value = double.tryParse(discountController.text.replaceAll(',', '.'));
      if (value != null && value >= 0) {
        line = line.copyWith(discount: value);
        onChanged();
      }
    });
  }

  void dispose() {
    quantityController.dispose();
    unitCostController.dispose();
    discountController.dispose();
  }
}

class _PurchaseLineRow extends StatelessWidget {
  final _PurchaseLineEntry entry;
  final VoidCallback onRemove;

  const _PurchaseLineRow({required this.entry, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.line.productName ?? 'Producto', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (entry.line.productSku != null && entry.line.productSku!.isNotEmpty)
                  Text('SKU: ${entry.line.productSku}', style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: TextField(
              controller: entry.quantityController,
              decoration: const InputDecoration(labelText: 'Cantidad'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: entry.unitCostController,
              decoration: const InputDecoration(labelText: 'Costo'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: entry.discountController,
              decoration: const InputDecoration(labelText: 'Descuento'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                ChileanUtils.formatCurrency(entry.line.netAmountClamped),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: Colors.red,
            onPressed: onRemove,
            tooltip: 'Eliminar línea',
          ),
        ],
      ),
    );
  }
}

class _SupplierSelector extends StatefulWidget {
  final List<shared_supplier.Supplier> suppliers;
  final Future<shared_supplier.Supplier?> Function(String name) onCreateSupplier;

  const _SupplierSelector({required this.suppliers, required this.onCreateSupplier});

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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
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
                                    if (supplier.rut != null && supplier.rut!.isNotEmpty)
                                      Text(
                                        'RUT: ${ChileanUtils.formatRut(supplier.rut!)}',
                                        style: TextStyle(
                                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        ),
                                      ),
                                    if (supplier.email != null && supplier.email!.isNotEmpty)
                                      Text(
                                        supplier.email!,
                                        style: TextStyle(
                                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                                onTap: () => Navigator.of(context).pop(supplier),
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
        return candidates.any((value) =>
            value != null && value.toLowerCase().contains(query));
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
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
                                    product.name.isNotEmpty ? product.name[0].toUpperCase() : '?',
                                    style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
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
                                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          'Costo: ${ChileanUtils.formatCurrency(product.cost)}',
                                          style: TextStyle(
                                            color: isDark ? Colors.grey[400] : Colors.grey[600],
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
                                            color: product.stockQuantity > 0
                                                ? (isDark ? Colors.green[900] : Colors.green[100])
                                                : (isDark ? Colors.red[900] : Colors.red[100]),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Stock: ${product.stockQuantity}',
                                            style: TextStyle(
                                              color: product.stockQuantity > 0
                                                  ? (isDark ? Colors.green[300] : Colors.green[800])
                                                  : (isDark ? Colors.red[300] : Colors.red[800]),
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
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
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
