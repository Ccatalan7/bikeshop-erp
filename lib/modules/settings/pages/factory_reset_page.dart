import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _performReset() async {
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
      await _resetService.performFactoryReset();
      
      if (!mounted) return;
      
      // Show success and navigate to login
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Sistema reiniciado exitosamente'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Navigate to login after delay
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      _showError('Error al reiniciar el sistema: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _showFinalConfirmation() async {
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
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esta acción es IRREVERSIBLE.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 16),
            Text('Se eliminarán TODOS los datos:'),
            SizedBox(height: 8),
            Text('• Todas las facturas de venta y compra'),
            Text('• Todo el inventario de productos'),
            Text('• Todos los clientes y proveedores'),
            Text('• Todos los asientos contables'),
            Text('• Todos los empleados y contratos'),
            Text('• Todos los pagos y cobros'),
            Text('• TODO el historial del sistema'),
            SizedBox(height: 16),
            Text(
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
            child: const Text('Sí, eliminar todo'),
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
      body: _isLoading
          ? _buildLoadingView()
          : _buildResetForm(),
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
                      Icon(Icons.delete_forever, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      const Text(
                        'Se eliminarán estos datos:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDataItem(Icons.receipt_long, 'Facturas de venta y compra'),
                  _buildDataItem(Icons.inventory, 'Productos e inventario'),
                  _buildDataItem(Icons.people, 'Clientes y proveedores'),
                  _buildDataItem(Icons.account_balance, 'Asientos contables'),
                  _buildDataItem(Icons.payments, 'Pagos y cobros'),
                  _buildDataItem(Icons.badge, 'Empleados y contratos'),
                  _buildDataItem(Icons.build, 'Órdenes de mantención'),
                  _buildDataItem(Icons.point_of_sale, 'Historial de POS'),
                  _buildDataItem(Icons.analytics, 'Reportes y estadísticas'),
                  const SizedBox(height: 16),
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
                            'La estructura de la base de datos se mantendrá, solo se eliminan los datos',
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
                      suffixIcon: _confirmController.text.trim().toUpperCase() == 'ELIMINAR'
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
            onPressed: _confirmationChecked && 
                     _confirmController.text.trim().toUpperCase() == 'ELIMINAR'
                ? _performReset
                : null,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Eliminar todos los datos'),
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

  Widget _buildDataItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(text),
        ],
      ),
    );
  }
}
