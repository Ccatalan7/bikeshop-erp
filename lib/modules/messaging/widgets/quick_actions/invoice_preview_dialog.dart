import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../sales/models/sales_models.dart';
import '../../../sales/services/sales_service.dart';

class InvoicePreviewDialog extends StatelessWidget {
  final String invoiceNumber;

  const InvoicePreviewDialog({super.key, required this.invoiceNumber});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Invoice>>(
      future: _fetchInvoice(context),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AlertDialog(content: LinearProgressIndicator());
        }

        final invoice = snapshot.data?.firstOrNull;

        if (invoice == null) {
          return AlertDialog(
            title: const Text('Comprobante no encontrado'),
            content: Text('No se encontró el comprobante #$invoiceNumber'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          );
        }

        return AlertDialog(
          title: Text('Comprobante #${invoice.invoiceNumber}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRow('Cliente:', invoice.customerName ?? 'Desconocido'),
              _buildRow('Status:', invoice.status.name.toUpperCase()),
              _buildRow('Total:', '\$${invoice.total.toStringAsFixed(0)}'),
              if (invoice.status == InvoiceStatus.overdue)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('⚠️ Vencida',
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                // TODO: Navigate to invoice detail
              },
              child: const Text('Ver Detalles'),
            ),
          ],
        );
      },
    );
  }

  Future<List<Invoice>> _fetchInvoice(BuildContext context) async {
    final service = context.read<SalesService>();
    // Ensure we have data
    if (service.invoices.isEmpty) {
      await service.loadInvoices();
    }
    return service.searchInvoices(invoiceNumber);
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
