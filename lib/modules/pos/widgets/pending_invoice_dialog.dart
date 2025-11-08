import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../sales/models/sales_models.dart';

/// Dialog to show and select pending invoices for a customer
/// Used in POS to load invoice for payment
class PendingInvoiceDialog extends StatelessWidget {
  final List<Invoice> invoices;
  final String customerName;

  const PendingInvoiceDialog({
    super.key,
    required this.invoices,
    required this.customerName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final dateFormat = DateFormat('dd/MM/yyyy');

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Facturas Pendientes'),
          const SizedBox(height: 4),
          Text(
            customerName,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Este cliente tiene ${invoices.length} ${invoices.length == 1 ? 'factura pendiente' : 'facturas pendientes'}. Selecciona una para procesar el pago.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: invoices.length,
                itemBuilder: (context, index) {
                  final invoice = invoices[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(invoice),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Invoice icon
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.receipt_long,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Invoice details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    invoice.invoiceNumber,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Fecha: ${dateFormat.format(invoice.date)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  if (invoice.reference != null && invoice.reference!.isNotEmpty)
                                    Text(
                                      'Ref: ${invoice.reference}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Financial details
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Total',
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  currencyFormat.format(invoice.total),
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.red.shade200),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Saldo',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.red.shade900,
                                        ),
                                      ),
                                      Text(
                                        currencyFormat.format(invoice.balance),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

/// Show pending invoice dialog and return selected invoice
Future<Invoice?> showPendingInvoiceDialog({
  required BuildContext context,
  required List<Invoice> invoices,
  required String customerName,
}) {
  return showDialog<Invoice>(
    context: context,
    builder: (context) => PendingInvoiceDialog(
      invoices: invoices,
      customerName: customerName,
    ),
  );
}
