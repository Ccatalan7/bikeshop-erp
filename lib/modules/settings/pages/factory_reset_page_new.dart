import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../accounting/services/accounting_service.dart';
import '../../sales/services/sales_service.dart';
import '../../inventory/services/inventory_service.dart';
import '../services/factory_reset_service.dart';
import '../models/reset_configuration.dart';
import '../../../shared/widgets/branded_loading.dart';

class FactoryResetPageNew extends StatefulWidget {
  const FactoryResetPageNew({super.key});

  @override
  State<FactoryResetPageNew> createState() => _FactoryResetPageNewState();
}

class _FactoryResetPageNewState extends State<FactoryResetPageNew> {
  final FactoryResetService _resetService = FactoryResetService();
  bool _isLoading = false;
  bool _confirmationChecked = false;
  final TextEditingController _confirmController = TextEditingController();
  
  // Saved configurations
  List<ResetConfiguration> _savedConfigs = [];
  ResetConfiguration? _selectedConfig;
  bool _isLoadingConfigs = true;
  
  // Current selection (either from saved config or manual)
  bool _deleteSales = false;
  bool _deletePurchases = false;
  bool _deleteInventory = false;
  bool _deleteStockMovements = false;
  bool _deleteCustomers = false;
  bool _deleteSuppliers = false;
  bool _deleteAccounting = false;
  bool _deleteEmployees = false;
  bool _deleteMechanic = false;
  bool _deleteEcommerce = false;

  @override
  void initState() {
    super.initState();
    _loadConfigurations();
  }

  Future<void> _loadConfigurations() async {
    setState(() => _isLoadingConfigs = true);
    try {
      final configs = await _resetService.getConfigurations();
      setState(() {
        _savedConfigs = configs;
        _isLoadingConfigs = false;
      });
    } catch (e) {
      setState(() => _isLoadingConfigs = false);
      if (mounted) {
        _showError('Error al cargar configuraciones: $e');
      }
    }
  }

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

  void _applyConfiguration(ResetConfiguration config) {
    setState(() {
      _selectedConfig = config;
      _deleteSales = config.deleteSales;
      _deletePurchases = config.deletePurchases;
      _deleteInventory = config.deleteInventory;
      _deleteStockMovements = config.deleteStockMovements;
      _deleteCustomers = config.deleteCustomers;
      _deleteSuppliers = config.deleteSuppliers;
      _deleteAccounting = config.deleteAccounting;
      _deleteEmployees = config.deleteEmployees;
      _deleteMechanic = config.deleteMechanic;
      _deleteEcommerce = config.deleteEcommerce;
    });
  }

  Future<void> _saveCurrentAsConfiguration() async {
    if (!_hasSelections) {
      _showError('Selecciona al menos una categoría antes de guardar');
      return;
    }

    final nameController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guardar Configuración'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                hintText: 'Ej: Reset Mensual, Limpiar Transacciones',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                hintText: 'Ej: Elimina facturas y asientos contables',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    final name = nameController.text.trim();
    if (name.isEmpty) {
      _showError('El nombre es obligatorio');
      return;
    }

    try {
      final config = ResetConfiguration(
        name: name,
        description: descController.text.trim().isEmpty 
            ? null 
            : descController.text.trim(),
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

      await _resetService.saveConfiguration(config);
      await _loadConfigurations();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Configuración guardada'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Error al guardar configuración: $e');
      }
    }
  }

  Future<void> _deleteConfiguration(ResetConfiguration config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Configuración'),
        content: Text('¿Eliminar la configuración "${config.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _resetService.deleteConfiguration(config.id!);
      await _loadConfigurations();
      
      if (_selectedConfig?.id == config.id) {
        setState(() => _selectedConfig = null);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Configuración eliminada'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Error al eliminar configuración: $e');
      }
    }
  }

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
      } catch (e) {
        debugPrint('Could not access sales service: $e');
      }

      try {
        context.read<InventoryService>();
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
    if (_deleteStockMovements) selectedItems.add('Movimientos de stock (ajustes y registros)');
    if (_deleteCustomers) selectedItems.add('Clientes');
    if (_deleteSuppliers) selectedItems.add('Proveedores');
    if (_deleteAccounting) selectedItems.add('Asientos contables');
    if (_deleteEmployees) selectedItems.add('Empleados y contratos');
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
          const BrandedLoading(),
          const SizedBox(height: 24),
          Text(
            'Eliminando datos...',
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
                    'Esta acción eliminará datos del sistema de forma PERMANENTE',
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

          // Saved Configurations Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bookmark, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      const Text(
                        'Configuraciones Guardadas',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loadConfigurations,
                        tooltip: 'Recargar',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isLoadingConfigs)
                    const Center(child: BrandedLoading())
                  else if (_savedConfigs.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.grey),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No hay configuraciones guardadas. Selecciona las opciones y guarda una configuración personalizada.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._savedConfigs.map((config) => Card(
                      elevation: 0,
                      color: _selectedConfig?.id == config.id 
                          ? Colors.blue[50] 
                          : Colors.grey[50],
                      child: ListTile(
                        leading: Icon(
                          Icons.bookmark,
                          color: _selectedConfig?.id == config.id 
                              ? Colors.blue 
                              : Colors.grey,
                        ),
                        title: Text(
                          config.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (config.description != null) ...[
                              const SizedBox(height: 4),
                              Text(config.description!),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              '${config.getSelectedCategories().length} categorías',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _deleteConfiguration(config),
                              tooltip: 'Eliminar configuración',
                            ),
                          ],
                        ),
                        onTap: () => _applyConfiguration(config),
                      ),
                    )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // What to delete section
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
                            _selectedConfig = null;
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
                            _selectedConfig = null;
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
                    (value) {
                      setState(() {
                        _selectedConfig = null;
                        _deleteSales = value ?? false;
                      });
                    },
                  ),
                  _buildCheckboxItem(
                    Icons.shopping_cart,
                    'Facturas de compra y pagos',
                    _deletePurchases,
                    (value) {
                      setState(() {
                        _selectedConfig = null;
                        _deletePurchases = value ?? false;
                      });
                    },
                  ),
                  _buildCheckboxItem(
                    Icons.inventory,
                    'Productos e inventario',
                    _deleteInventory,
                    (value) {
                      setState(() {
                        _selectedConfig = null;
                        _deleteInventory = value ?? false;
                      });
                    },
                  ),
                  _buildCheckboxItem(
                    Icons.swap_horiz,
                    'Movimientos de stock (ajustes y registros)',
                    _deleteStockMovements,
                    (value) {
                      setState(() {
                        _selectedConfig = null;
                        _deleteStockMovements = value ?? false;
                      });
                    },
                  ),
                  _buildCheckboxItem(
                    Icons.people,
                    'Clientes',
                    _deleteCustomers,
                    (value) {
                      setState(() {
                        _selectedConfig = null;
                        _deleteCustomers = value ?? false;
                      });
                    },
                  ),
                  _buildCheckboxItem(
                    Icons.business,
                    'Proveedores',
                    _deleteSuppliers,
                    (value) {
                      setState(() {
                        _selectedConfig = null;
                        _deleteSuppliers = value ?? false;
                      });
                    },
                  ),
                  _buildCheckboxItem(
                    Icons.account_balance,
                    'Asientos contables',
                    _deleteAccounting,
                    (value) {
                      setState(() {
                        _selectedConfig = null;
                        _deleteAccounting = value ?? false;
                      });
                    },
                  ),
                  _buildCheckboxItem(
                    Icons.badge,
                    'Empleados y contratos',
                    _deleteEmployees,
                    (value) {
                      setState(() {
                        _selectedConfig = null;
                        _deleteEmployees = value ?? false;
                      });
                    },
                  ),
                  _buildCheckboxItem(
                    Icons.build,
                    'Órdenes de mantención (Pegas)',
                    _deleteMechanic,
                    (value) {
                      setState(() {
                        _selectedConfig = null;
                        _deleteMechanic = value ?? false;
                      });
                    },
                  ),
                  _buildCheckboxItem(
                    Icons.storefront,
                    'Tienda online y pedidos web',
                    _deleteEcommerce,
                    (value) {
                      setState(() {
                        _selectedConfig = null;
                        _deleteEcommerce = value ?? false;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // Save configuration button
                  OutlinedButton.icon(
                    onPressed: _hasSelections ? _saveCurrentAsConfiguration : null,
                    icon: const Icon(Icons.bookmark_add, size: 20),
                    label: const Text('Guardar esta configuración'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
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
