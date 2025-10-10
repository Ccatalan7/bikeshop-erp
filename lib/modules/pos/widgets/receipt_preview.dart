import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/pos_transaction.dart';

class ReceiptPreview extends StatelessWidget {
  final POSTransaction transaction;
  final VoidCallback? onPrint;
  final VoidCallback? onShare;
  final bool showActions;

  const ReceiptPreview({
    super.key,
    required this.transaction,
    this.onPrint,
    this.onShare,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Text(
              'VINABIKE',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            
            Text(
              'Venta de Bicicletas y Accesorios',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            
            const Divider(height: 24),
            
            // Receipt info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recibo:', style: theme.textTheme.bodyMedium),
                Text(
                  transaction.receiptNumber ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Fecha:', style: theme.textTheme.bodyMedium),
                Text(
                  dateFormat.format(transaction.completedAt ?? transaction.createdAt),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            
            if (transaction.customer != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cliente:', style: theme.textTheme.bodyMedium),
                  Expanded(
                    child: Text(
                      transaction.customer!.displayName,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            
            const Divider(height: 24),
            
            // Items
            ...transaction.items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.product.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '\$${item.total.toStringAsFixed(0)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '  ${item.quantity} x \$${item.unitPrice.toStringAsFixed(0)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (item.discount > 0)
                        Text(
                          'Desc. ${item.discount.toStringAsFixed(0)}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            )),
            
            const Divider(height: 24),
            
            // Totals
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Subtotal:', style: theme.textTheme.bodyMedium),
                Text(
                  '\$${transaction.subtotal.toStringAsFixed(0)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            
            if (transaction.discountAmount > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Descuento:', style: theme.textTheme.bodyMedium),
                  Text(
                    '-\$${transaction.discountAmount.toStringAsFixed(0)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('IVA (19%):', style: theme.textTheme.bodyMedium),
                Text(
                  '\$${transaction.taxAmount.toStringAsFixed(0)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            
            const Divider(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TOTAL:',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '\$${transaction.total.toStringAsFixed(0)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            
            // Payment methods
            const Divider(height: 24),
            
            ...transaction.payments.map((payment) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  payment.method.name,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  '\$${payment.amount.toStringAsFixed(0)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            )),
            
            if (transaction.changeAmount > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Vuelto:',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '\$${transaction.changeAmount.toStringAsFixed(0)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
            
            const Divider(height: 24),
            
            // Footer
            Text(
              '¡Gracias por su compra!',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 8),
            
            Text(
              'Garantía 30 días',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            
            // Actions
            if (showActions) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  if (onPrint != null)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onPrint,
                        icon: const Icon(Icons.print),
                        label: const Text('Imprimir'),
                      ),
                    ),
                  
                  if (onPrint != null && onShare != null)
                    const SizedBox(width: 8),
                  
                  if (onShare != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onShare,
                        icon: const Icon(Icons.share),
                        label: const Text('Compartir'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}