import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../modules/sales/models/sales_models.dart';
import '../../modules/sales/services/sales_service.dart';

class QuoteReviewPanel extends StatefulWidget {
  final String invoiceId;
  final String? messageId; // To update the chat message status
  final VoidCallback onClose;
  final Function(String message)? onRequestChanges;
  final VoidCallback? onApprove;

  const QuoteReviewPanel({
    super.key,
    required this.invoiceId,
    this.messageId,
    required this.onClose,
    this.onRequestChanges,
    this.onApprove,
  });

  @override
  State<QuoteReviewPanel> createState() => _QuoteReviewPanelState();
}

class _QuoteReviewPanelState extends State<QuoteReviewPanel> {
  bool _isLoading = true;
  Invoice? _invoice;
  String? _error;
  final bool _isProcessingAction = false;

  @override
  void initState() {
    super.initState();
    _loadInvoice();
  }

  Future<void> _loadInvoice() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final salesService = context.read<SalesService>();
      final invoice = await salesService.fetchInvoice(widget.invoiceId);
      if (mounted) {
        setState(() {
          _invoice = invoice;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo cargar el presupuesto.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null || _invoice == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text(_error ?? 'Presupuesto no encontrado',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(
              onPressed: widget.onClose,
              child: const Text('Volver'),
            ),
          ],
        ),
      );
    }

    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
                tooltip: 'Cerrar',
              ),
              const Expanded(
                child: Text(
                  'Revisión de Presupuesto',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 48), // Balance for close button
            ],
          ),
        ),

        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      _buildInfoRow('Presupuesto #', _invoice!.invoiceNumber),
                      const SizedBox(height: 8),
                      _buildInfoRow('Fecha',
                          DateFormat('dd/MM/yyyy').format(_invoice!.date)),
                      const SizedBox(height: 8),
                      _buildInfoRow('Estado', _getStatusLabel(_invoice!.status),
                          isStatus: true),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                const Text('Detalle de Costos',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                // Items
                ..._invoice!.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.shopping_bag_outlined,
                                size: 16, color: Colors.blue),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    item.productName ??
                                        item.description ??
                                        'Item',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500)),
                                Text(
                                  '${item.quantity} x ${currencyFormat.format(item.unitPrice)}',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            currencyFormat.format(item.lineTotal),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )),

                const Divider(height: 32),

                // Totals
                _buildTotalRow('Subtotal', _invoice!.subtotal, currencyFormat),
                const SizedBox(height: 8),
                // Invoice doesn't have global discount field, removing it for now or calculate from items?
                // _buildTotalRow('Descuento', -_invoice!.discount, currencyFormat, isDiscount: true),
                _buildTotalRow(
                    'Impuestos', _invoice!.ivaAmount, currencyFormat),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      currencyFormat.format(_invoice!.total),
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Action Buttons
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              if (_isProcessingAction)
                const CircularProgressIndicator()
              else if (_invoice!.status == InvoiceStatus.sent) ...[
                // Only show actions if Sent (Pending)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.onApprove,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Aprobar Presupuesto'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showRequestChangesDialog(context),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Solicitar Cambios'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade800,
                      side: BorderSide(color: Colors.orange.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _invoice!.status == InvoiceStatus.confirmed
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _invoice!.status == InvoiceStatus.confirmed
                        ? '✅ Presupuesto Aprobado'
                        : 'Estado: ${_getStatusLabel(_invoice!.status)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _invoice!.status == InvoiceStatus.confirmed
                          ? Colors.green
                          : Colors.black54,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isStatus = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600])),
        isStatus
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                        fontSize: 12)),
              )
            : Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildTotalRow(String label, double value, NumberFormat format,
      {bool isDiscount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600])),
        Text(
          format.format(value),
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isDiscount ? Colors.green : Colors.black87,
          ),
        ),
      ],
    );
  }

  String _getStatusLabel(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return 'Borrador';
      case InvoiceStatus.sent:
        return 'Pendiente'; // 'Enviado' implies pending approval here
      case InvoiceStatus.confirmed:
        return 'Aprobado';
      case InvoiceStatus.paid:
        return 'Pagado';
      case InvoiceStatus.cancelled:
        return 'Cancelado';
      default:
        return status.name;
    }
  }

  void _showRequestChangesDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Solicitar Cambios'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Describe los cambios que necesitas en el presupuesto:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Ej: Preferiría usar repuestos alternativos...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty &&
                  widget.onRequestChanges != null) {
                widget.onRequestChanges!(controller.text);
              }
              Navigator.pop(context);
            },
            child: const Text('Enviar Solicitud'),
          ),
        ],
      ),
    );
  }
}
