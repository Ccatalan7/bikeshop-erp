import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/pos_transaction.dart';
import '../widgets/receipt_preview.dart';

class POSReceiptPage extends StatefulWidget {
  final POSTransaction transaction;

  const POSReceiptPage({
    super.key,
    required this.transaction,
  });

  @override
  State<POSReceiptPage> createState() => _POSReceiptPageState();
}

class _POSReceiptPageState extends State<POSReceiptPage> {
  void _newSale() {
    // Go back to main POS dashboard
    context.go('/pos');
  }

  void _printReceipt() {
    // TODO: Implement print functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Funcionalidad de impresión no implementada'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Header with title and actions
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Comprobante de Venta',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: _printReceipt,
                icon: const Icon(Icons.print),
              ),
              IconButton(
                onPressed: _newSale,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),

        // Content area
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Success message
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '¡Venta Exitosa!',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Transacción completada correctamente',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),

                // Receipt preview
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: ReceiptPreview(transaction: widget.transaction),
                ),

                const SizedBox(height: 24),

                // Action buttons
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Print button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _printReceipt,
                          icon: const Icon(Icons.print),
                          label: const Text('Imprimir Comprobante'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // New sale button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _newSale,
                          icon: const Icon(Icons.add_shopping_cart),
                          label: const Text('Nueva Venta'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
