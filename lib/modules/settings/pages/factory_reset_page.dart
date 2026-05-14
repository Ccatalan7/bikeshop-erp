import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../accounting/services/accounting_service.dart';
import '../../sales/services/sales_service.dart';
import '../../inventory/services/inventory_service.dart';
import '../services/factory_reset_service.dart';

class FactoryResetPage extends StatefulWidget {
  const FactoryResetPage({super.key});

  @override
  State<FactoryResetPage> createState() => _FactoryResetPageState();
}

class _FactoryResetPageState extends State<FactoryResetPage> {
  final FactoryResetService _resetService = FactoryResetService();
  bool _isLoading = false;
  bool _confirmationChecked = false;
  final TextEditingController _confirmController = TextEditingController();

  // Checkboxes for what to delete
  bool _deleteSales = true;
  bool _deletePurchases = true;
  bool _deleteInventory = true;
  bool _deleteStockMovements = true;
  bool _deleteCustomers = true;
  bool _deleteSuppliers = true;
  bool _deleteAccounting = true;
  bool _deleteEmployees = true;
  bool _deleteMechanic = true;
  bool _deleteEcommerce = true;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  bool get _hasSelections =>
      _deleteSales ||
      _deletePurchases ||
      _deleteInventory ||
      _deleteStockMovements ||
      _deleteCustomers ||
      _deleteSuppliers ||
      _deleteAccounting ||
      _deleteEmployees ||
      _deleteMechanic ||
      _deleteEcommerce;

  Future<void> _performReset() async {
    if (!_hasSelections) {
      _showError('Debes seleccionar al menos una categoría para eliminar');
      return;
    }

    if (!_confirmationChecked) {
      _showError('Debes marcar la casilla de confirmación');
      return;
    }

    if (_confirmController.text.trim().toUpperCase() != 'ELIMINAR') {
      _showError('Debes escribir "ELIMINAR" para confirmar');
      return;
    }

    final confirmed = await _showFinalConfirmation();
    if (!confirmed) return;

    setState(() => _isLoading = true);

    try {
      await _resetService.performSelectiveReset(
        deleteSales: _deleteSales,
        deletePurchases: _deletePurchases,
        deleteInventory: _deleteInventory,
        deleteStockMovements: _deleteStockMovements,
        deleteCustomers: _deleteCustomers,
        deleteSuppliers: _deleteSuppliers,
        deleteAccounting: _deleteAccounting,
        deleteEmployees: _deleteEmployees,
        deleteMechanic: _deleteMechanic,
        deleteEcommerce: _deleteEcommerce,
      );

      if (!mounted) return;

      // Clear all service caches to force reload
      try {
        final accountingService = context.read<AccountingService>();
        await accountingService.reloadJournalEntries();
      } catch (e) {
        debugPrint('Could not reload accounting service: $e');
      }

      try {
        context.read<SalesService>();
        // Sales service will reload on next access
      } catch (e) {
        debugPrint('Could not access sales service: $e');
      }

      try {
        context.read<InventoryService>();
        // Inventory service will reload on next access
      } catch (e) {
        debugPrint('Could not access inventory service: $e');
      }

      // Show success and navigate back
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Datos eliminados exitosamente'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Navigate back after delay
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      _showError('Error al eliminar datos: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _showFinalConfirmation() async {
    final selectedItems = <String>[];
    if (_deleteSales) selectedItems.add('Facturas de venta y pagos');
    if (_deletePurchases) selectedItems.add('Facturas de compra y pagos');
    if (_deleteInventory) selectedItems.add('Productos e inventario');
    if (_deleteStockMovements)
      selectedItems.add('Movimientos de stock (ajustes y registros)');
    if (_deleteCustomers) selectedItems.add('Clientes');
    if (_deleteSuppliers) selectedItems.add('Proveedores');
    if (_deleteAccounting) selectedItems.add('Asientos contables');
    if (_deleteEmployees) selectedItems.add('Trabajadores y contratos');
    if (_deleteMechanic) selectedItems.add('Órdenes de mantención');
    if (_deleteEcommerce) selectedItems.add('Tienda online');

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[700], size: 32),
            const SizedBox(width: 12),
            const Text('¿Estás completamente seguro?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta acción es IRREVERSIBLE.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Se eliminarán los siguientes datos:'),
            const SizedBox(height: 8),
            ...selectedItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $item'),
                )),
            const SizedBox(height: 16),
            const Text(
              'No hay forma de recuperar estos datos.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
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
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Sí, eliminar'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reiniciar Sistema'),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
      ),
      body: _isLoading ? _buildLoadingView() : _buildResetForm(),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Eliminando todos los datos...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Esto puede tardar unos momentos',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildResetForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Warning Card
          Card(
            color: Colors.red[50],
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.red[200]!),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 64,
                    color: Colors.red[700],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '⚠️ ADVERTENCIA',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[900],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Esta acción eliminará TODOS los datos del sistema de forma PERMANENTE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.red[900],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // What will be deleted
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.checklist, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      const Text(
                        'Selecciona qué datos eliminar:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _deleteSales = true;
                            _deletePurchases = true;
                            _deleteInventory = true;
                            _deleteStockMovements = true;
                            _deleteCustomers = true;
                            _deleteSuppliers = true;
                            _deleteAccounting = true;
                            _deleteEmployees = true;
                            _deleteMechanic = true;
                            _deleteEcommerce = true;
                          });
                        },
                        icon: const Icon(Icons.select_all, size: 18),
                        label: const Text('Seleccionar todo'),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _deleteSales = false;
                            _deletePurchases = false;
                            _deleteInventory = false;
                            _deleteStockMovements = false;
                            _deleteCustomers = false;
                            _deleteSuppliers = false;
                            _deleteAccounting = false;
                            _deleteEmployees = false;
                            _deleteMechanic = false;
                            _deleteEcommerce = false;
                          });
                        },
                        icon: const Icon(Icons.deselect, size: 18),
                        label: const Text('Deseleccionar todo'),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      ),
                    ],
                  ),
                  const Divider(),
                  _buildCheckboxItem(
                    Icons.point_of_sale,
                    'Facturas de venta y pagos',
                    _deleteSales,
                    (value) => setState(() => _deleteSales = value ?? false),
                  ),
                  _buildCheckboxItem(
                    Icons.shopping_cart,
                    'Facturas de compra y pagos',
                    _deletePurchases,
                    (value) =>
                        setState(() => _deletePurchases = value ?? false),
                  ),
                  _buildCheckboxItem(
                    Icons.inventory,
                    'Productos e inventario',
                    _deleteInventory,
                    (value) =>
                        setState(() => _deleteInventory = value ?? false),
                  ),
                  _buildCheckboxItem(
                    Icons.swap_horiz,
                    'Movimientos de stock (ajustes y registros)',
                    _deleteStockMovements,
                    (value) =>
                        setState(() => _deleteStockMovements = value ?? false),
                  ),
                  _buildCheckboxItem(
                    Icons.people,
                    'Clientes',
                    _deleteCustomers,
                    (value) =>
                        setState(() => _deleteCustomers = value ?? false),
                  ),
                  _buildCheckboxItem(
                    Icons.business,
                    'Proveedores',
                    _deleteSuppliers,
                    (value) =>
                        setState(() => _deleteSuppliers = value ?? false),
                  ),
                  _buildCheckboxItem(
                    Icons.account_balance,
                    'Asientos contables',
                    _deleteAccounting,
                    (value) =>
                        setState(() => _deleteAccounting = value ?? false),
                  ),
                  _buildCheckboxItem(
                    Icons.badge,
                    'Trabajadores y contratos',
                    _deleteEmployees,
                    (value) =>
                        setState(() => _deleteEmployees = value ?? false),
                  ),
                  _buildCheckboxItem(
                    Icons.build,
                    'Órdenes de mantención (Trabajos)',
                    _deleteMechanic,
                    (value) => setState(() => _deleteMechanic = value ?? false),
                  ),
                  _buildCheckboxItem(
                    Icons.storefront,
                    'Tienda online y pedidos web',
                    _deleteEcommerce,
                    (value) =>
                        setState(() => _deleteEcommerce = value ?? false),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Solo se eliminan los datos seleccionados. La estructura de la base de datos se mantiene.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Confirmation checkbox
          Card(
            child: CheckboxListTile(
              value: _confirmationChecked,
              onChanged: (value) {
                setState(() => _confirmationChecked = value ?? false);
              },
              title: const Text(
                'Entiendo que esta acción es irreversible',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'No podré recuperar los datos eliminados',
                style: TextStyle(fontSize: 12),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
          const SizedBox(height: 16),

          // Confirmation text field
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Para confirmar, escribe "ELIMINAR" en mayúsculas:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmController,
                    decoration: InputDecoration(
                      hintText: 'ELIMINAR',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.keyboard),
                      suffixIcon: _confirmController.text
                                  .trim()
                                  .toUpperCase() ==
                              'ELIMINAR'
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (value) => setState(() {}),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Reset button
          FilledButton.icon(
            onPressed: _hasSelections &&
                    _confirmationChecked &&
                    _confirmController.text.trim().toUpperCase() == 'ELIMINAR'
                ? _performReset
                : null,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Eliminar datos seleccionados'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Cancelar y volver'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildCheckboxItem(
    IconData icon,
    String text,
    bool value,
    Function(bool?) onChanged,
  ) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }
}
