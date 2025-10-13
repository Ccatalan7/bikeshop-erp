import 'package:flutter/material.dart';

/// Dialog to select payment model when creating a new purchase invoice
/// Shows two options: Standard (pay after receipt) vs Prepayment (pay before receipt)
class PurchaseModelSelectionDialog extends StatefulWidget {
  const PurchaseModelSelectionDialog({super.key});

  @override
  State<PurchaseModelSelectionDialog> createState() => _PurchaseModelSelectionDialogState();
}

class _PurchaseModelSelectionDialogState extends State<PurchaseModelSelectionDialog> {
  String? _selectedModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: const Text('Seleccionar Modelo de Pago'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Cómo se va a gestionar el pago de esta factura de compra?',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Esto determina el flujo de estados y cuándo se registra el pago.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            
            // Standard Model Option
            _buildModelOption(
              value: 'standard',
              title: 'Pago Después de Recibir (Modelo Estándar)',
              flow: 'Flujo: Enviada → Confirmada → Recibida → Pagada',
              description: 'El pago se registra DESPUÉS de recibir los productos',
              idealFor: 'Ideal para: Proveedores locales, entregas contra pago',
              icon: Icons.local_shipping,
              color: Colors.blue,
            ),
            
            const SizedBox(height: 16),
            
            // Prepayment Model Option
            _buildModelOption(
              value: 'prepayment',
              title: 'Pago Anticipado (Prepago)',
              flow: 'Flujo: Enviada → Confirmada → Pagada → Recibida',
              description: 'El pago se registra ANTES de recibir los productos',
              idealFor: 'Ideal para: Importaciones, transferencias bancarias, pre-órdenes',
              icon: Icons.payment,
              color: Colors.orange,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _selectedModel == null 
            ? null 
            : () => Navigator.pop(context, _selectedModel == 'prepayment'),
          child: const Text('Continuar'),
        ),
      ],
    );
  }

  Widget _buildModelOption({
    required String value,
    required String title,
    required String flow,
    required String description,
    required String idealFor,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedModel == value;
    
    return InkWell(
      onTap: () => setState(() => _selectedModel = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? color.withOpacity(0.05) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Radio<String>(
              value: value,
              groupValue: _selectedModel,
              onChanged: (val) => setState(() => _selectedModel = val),
              activeColor: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    flow,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    idealFor,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Show the model selection dialog and return isPrepayment boolean
/// Returns null if user cancels
Future<bool?> showPurchaseModelSelectionDialog(BuildContext context) async {
  return await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const PurchaseModelSelectionDialog(),
  );
}
