import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/app_button.dart';
import '../models/purchase_invoice.dart';
import '../services/purchase_service.dart';
import 'purchase_payment_form_page.dart';

/// Purchase Invoice Detail Page with 5-status workflow
/// Handles both Standard and Prepayment models with conditional buttons
class PurchaseInvoiceDetailPage extends StatefulWidget {
  final String invoiceId;

  const PurchaseInvoiceDetailPage({
    super.key,
    required this.invoiceId,
  });

  @override
  State<PurchaseInvoiceDetailPage> createState() =>
      _PurchaseInvoiceDetailPageState();
}

class _PurchaseInvoiceDetailPageState extends State<PurchaseInvoiceDetailPage> {
  late PurchaseService _purchaseService;
  PurchaseInvoice? _invoice;
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _hasChanges = false; // Track if any changes were made

  @override
  void initState() {
    super.initState();
    _purchaseService = context.read<PurchaseService>();
    _loadInvoice();
  }

  Future<void> _loadInvoice() async {
    setState(() => _isLoading = true);
    try {
      final invoice =
          await _purchaseService.getPurchaseInvoice(widget.invoiceId);
      if (mounted) {
        setState(() {
          _invoice = invoice;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Column(
        children: [
          // Header with title and back button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(_hasChanges),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    _invoice != null
                        ? 'Factura ${_invoice!.invoiceNumber}'
                        : 'Factura de Compra',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!_isLoading)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadInvoice,
                    tooltip: 'Actualizar',
                  ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _invoice == null
                    ? const Center(child: Text('Factura no encontrada'))
                    : _isProcessing
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeader(),
                                const SizedBox(height: 24),
                                _buildTimeline(),
                                const SizedBox(height: 24),
                                _buildDetails(),
                                const SizedBox(height: 24),
                                _buildItems(),
                                const SizedBox(height: 24),
                                _buildActionButtons(),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStatusBadge(_invoice!.status),
                const SizedBox(width: 8),
                _buildModelBadge(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _invoice!.invoiceNumber,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            if (_invoice!.supplierName != null) ...[
              const SizedBox(height: 8),
              Text(
                _invoice!.supplierName!,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              ChileanUtils.formatCurrency(_invoice!.total),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            if (_invoice!.paidAmount > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Pagado: ${ChileanUtils.formatCurrency(_invoice!.paidAmount)}',
                style: const TextStyle(fontSize: 14, color: Colors.green),
              ),
              Text(
                'Saldo: ${ChileanUtils.formatCurrency(_invoice!.balance)}',
                style: TextStyle(
                  fontSize: 14,
                  color: _invoice!.balance > 0 ? Colors.orange : Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(PurchaseInvoiceStatus status) {
    Color color;
    switch (status) {
      case PurchaseInvoiceStatus.draft:
        color = Colors.grey;
        break;
      case PurchaseInvoiceStatus.sent:
        color = Colors.blue;
        break;
      case PurchaseInvoiceStatus.confirmed:
        color = Colors.purple;
        break;
      case PurchaseInvoiceStatus.received:
        color = Colors.green;
        break;
      case PurchaseInvoiceStatus.paid:
        color = Colors.blue;
        break;
      case PurchaseInvoiceStatus.cancelled:
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildModelBadge() {
    final isPrepayment = _invoice!.prepaymentModel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isPrepayment ? Colors.orange[50] : Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPrepayment ? Colors.orange[300]! : Colors.blue[300]!,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPrepayment ? Icons.payment : Icons.local_shipping,
            size: 14,
            color: isPrepayment ? Colors.orange[700] : Colors.blue[700],
          ),
          const SizedBox(width: 4),
          Text(
            isPrepayment ? 'Prepago' : 'Estándar',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isPrepayment ? Colors.orange[700] : Colors.blue[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final isPrepayment = _invoice!.prepaymentModel;
    final status = _invoice!.status;

    // Different order for prepayment vs standard
    final steps = isPrepayment
        ? [
            _TimelineStep(
                'Borrador', _invoice!.createdAt, PurchaseInvoiceStatus.draft),
            _TimelineStep(
                'Enviada', _invoice!.sentDate, PurchaseInvoiceStatus.sent),
            _TimelineStep('Confirmada', _invoice!.confirmedDate,
                PurchaseInvoiceStatus.confirmed),
            _TimelineStep(
                'Pagada', _invoice!.paidDate, PurchaseInvoiceStatus.paid,
                highlighted: true),
            _TimelineStep('Recibida', _invoice!.receivedDate,
                PurchaseInvoiceStatus.received),
          ]
        : [
            _TimelineStep(
                'Borrador', _invoice!.createdAt, PurchaseInvoiceStatus.draft),
            _TimelineStep(
                'Enviada', _invoice!.sentDate, PurchaseInvoiceStatus.sent),
            _TimelineStep('Confirmada', _invoice!.confirmedDate,
                PurchaseInvoiceStatus.confirmed),
            _TimelineStep('Recibida', _invoice!.receivedDate,
                PurchaseInvoiceStatus.received,
                highlighted: true),
            _TimelineStep(
                'Pagada', _invoice!.paidDate, PurchaseInvoiceStatus.paid),
          ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Flujo de Estados',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...steps.asMap().entries.map((entry) {
              final index = entry.key;
              final step = entry.value;
              final isLast = index == steps.length - 1;
              final isActive = _isStatusReached(step.requiredStatus);

              return _buildTimelineItem(step, isActive, !isLast);
            }),
          ],
        ),
      ),
    );
  }

  bool _isStatusReached(PurchaseInvoiceStatus targetStatus) {
    final statusOrder = [
      PurchaseInvoiceStatus.draft,
      PurchaseInvoiceStatus.sent,
      PurchaseInvoiceStatus.confirmed,
      _invoice!.prepaymentModel
          ? PurchaseInvoiceStatus.paid
          : PurchaseInvoiceStatus.received,
      _invoice!.prepaymentModel
          ? PurchaseInvoiceStatus.received
          : PurchaseInvoiceStatus.paid,
    ];

    final currentIndex = statusOrder.indexOf(_invoice!.status);
    final targetIndex = statusOrder.indexOf(targetStatus);
    return currentIndex >= targetIndex;
  }

  Widget _buildTimelineItem(
      _TimelineStep step, bool isActive, bool showConnector) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isActive ? Colors.green : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Icon(
                isActive ? Icons.check : Icons.circle,
                size: 14,
                color: Colors.white,
              ),
            ),
            if (showConnector)
              Container(
                width: 2,
                height: 40,
                color: Colors.grey[300],
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.label,
                style: TextStyle(
                  fontWeight:
                      step.highlighted ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? Colors.black : Colors.grey,
                ),
              ),
              if (step.date != null)
                Text(
                  ChileanUtils.formatDateTime(step.date!),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              if (showConnector) const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detalles',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Fecha', ChileanUtils.formatDate(_invoice!.date)),
            if (_invoice!.dueDate != null)
              _buildDetailRow(
                  'Vencimiento', ChileanUtils.formatDate(_invoice!.dueDate!)),
            if (_invoice!.supplierInvoiceNumber != null)
              _buildDetailRow(
                  'Nº Factura Proveedor', _invoice!.supplierInvoiceNumber!),
            if (_invoice!.reference != null)
              _buildDetailRow('Referencia', _invoice!.reference!),
            if (_invoice!.notes != null && _invoice!.notes!.isNotEmpty)
              _buildDetailRow('Notas', _invoice!.notes!),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItems() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Items',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._invoice!.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.productName ?? item.productId),
                            if (item.productSku != null)
                              Text(
                                'SKU: ${item.productSku}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${item.quantity.toStringAsFixed(0)} un',
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          ChileanUtils.formatCurrency(item.netAmount),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                )),
            const Divider(),
            _buildTotalRow('Subtotal', _invoice!.subtotal),
            _buildTotalRow('IVA (19%)', _invoice!.ivaAmount),
            _buildTotalRow('Total', _invoice!.total, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            ChileanUtils.formatCurrency(amount),
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final status = _invoice!.status;
    final isPrepayment = _invoice!.prepaymentModel;

    List<Widget> buttons = [];

    // Conditional buttons based on status and model
    switch (status) {
      case PurchaseInvoiceStatus.draft:
        buttons = [
          FilledButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Enviar a Proveedor'),
            onPressed: _markAsSent,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit),
            label: const Text('Editar'),
            onPressed: () async {
              final edited =
                  await context.push<bool>('/purchases/${_invoice!.id}/edit');
              if (edited == true) {
                setState(() => _hasChanges = true);
                await _loadInvoice();
              }
            },
          ),
        ];
        break;

      case PurchaseInvoiceStatus.sent:
        buttons = [
          FilledButton.icon(
            icon: const Icon(Icons.check_circle),
            label: const Text('Confirmar Factura'),
            onPressed: _confirmInvoice,
            style: FilledButton.styleFrom(backgroundColor: Colors.purple),
          ),
          OutlinedButton(
            onPressed: _revertToDraft,
            child: const Text('Volver a Borrador'),
          ),
        ];
        break;

      case PurchaseInvoiceStatus.confirmed:
        if (isPrepayment) {
          // Prepayment: can pay before receiving
          buttons = [
            FilledButton.icon(
              icon: const Icon(Icons.payment),
              label: const Text('Registrar Pago'),
              onPressed: _navigateToPayment,
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            ),
            OutlinedButton(
              onPressed: _revertToSent,
              child: const Text('Volver a Enviada'),
            ),
          ];
        } else {
          // Standard: must receive before paying
          buttons = [
            FilledButton.icon(
              icon: const Icon(Icons.check_box),
              label: const Text('Marcar como Recibida'),
              onPressed: _markAsReceived,
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
            ),
            OutlinedButton(
              onPressed: _revertToSent,
              child: const Text('Volver a Enviada'),
            ),
          ];
        }
        break;

      case PurchaseInvoiceStatus.received:
        if (isPrepayment) {
          // Prepayment: already paid, can only revert
          buttons = [
            OutlinedButton(
              onPressed: _revertToPaid,
              child: const Text('Volver a Pagada'),
            ),
          ];
        } else {
          // Standard: can pay now
          buttons = [
            FilledButton.icon(
              icon: const Icon(Icons.payment),
              label: const Text('Registrar Pago'),
              onPressed: _navigateToPayment,
            ),
            OutlinedButton(
              onPressed: _revertToConfirmed,
              child: const Text('Volver a Confirmada'),
            ),
          ];
        }
        break;

      case PurchaseInvoiceStatus.paid:
        if (isPrepayment) {
          // Prepayment: can receive goods now
          buttons = [
            FilledButton.icon(
              icon: const Icon(Icons.inventory),
              label: const Text('Marcar como Recibida'),
              onPressed: _markAsReceived,
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
            ),
            OutlinedButton(
              onPressed: _undoPayment,
              child: const Text('Deshacer Pago'),
            ),
          ];
        } else {
          // Standard: process complete, can only undo payment
          buttons = [
            OutlinedButton(
              onPressed: _undoPayment,
              child: const Text('Deshacer Pago'),
            ),
          ];
        }
        break;

      case PurchaseInvoiceStatus.cancelled:
        buttons = [];
        break;
    }

    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: buttons
              .map((btn) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: btn,
                  ))
              .toList(),
        ),
      ),
    );
  }

  // =====================================================
  // Action Methods
  // =====================================================

  Future<void> _markAsSent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar a Proveedor'),
        content: const Text('¿Marcar esta orden como enviada al proveedor?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _executeAction(() async {
        await _purchaseService.markInvoiceAsSent(_invoice!.id!);
      });
    }
  }

  Future<void> _confirmInvoice() async {
    final TextEditingController supplierNumberController =
        TextEditingController();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Confirmar Factura del Proveedor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: supplierNumberController,
                decoration: InputDecoration(
                  labelText: 'Nº Factura Proveedor',
                  hintText: 'Ej: FC-12345',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.auto_awesome),
                    tooltip: 'Auto-generar',
                    onPressed: () {
                      // Generate supplier invoice number
                      final now = DateTime.now();
                      final autoNumber =
                          'FC-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
                      setState(() {
                        supplierNumberController.text = autoNumber;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ingrese el número de factura del proveedor o genere uno automáticamente',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (supplierNumberController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Por favor ingrese o genere un número de factura'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'number': supplierNumberController.text,
                  'date': DateTime.now(),
                });
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _executeAction(() async {
        await _purchaseService.confirmInvoice(
          invoiceId: _invoice!.id!,
          supplierInvoiceNumber: result['number'],
          supplierInvoiceDate: result['date'] as DateTime,
        );
      });
    }
  }

  Future<void> _markAsReceived() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar como Recibida'),
        content: const Text(
          'Los productos serán agregados al inventario.\n\n¿Confirmar recepción?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Confirmar Recepción'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _executeAction(() async {
        await _purchaseService.markInvoiceAsReceived(_invoice!.id!);
      });
    }
  }

  Future<void> _navigateToPayment() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PurchasePaymentFormPage(
          invoiceId: _invoice!.id!,
          invoice: _invoice!,
        ),
      ),
    );

    if (result == true) {
      setState(() => _hasChanges = true); // Mark that changes were made
      await _loadInvoice(); // Refresh invoice data
    }
  }

  Future<void> _revertToDraft() async {
    await _revertStatus(
        () => _purchaseService.revertInvoiceToDraft(_invoice!.id!),
        'Volver a Borrador');
  }

  Future<void> _revertToSent() async {
    await _revertStatus(
        () => _purchaseService.revertInvoiceToSent(_invoice!.id!),
        'Volver a Enviada');
  }

  Future<void> _revertToConfirmed() async {
    await _revertStatus(
        () => _purchaseService.revertInvoiceToConfirmed(_invoice!.id!),
        'Volver a Confirmada');
  }

  Future<void> _revertToPaid() async {
    await _revertStatus(
        () => _purchaseService.revertInvoiceToPaid(_invoice!.id!),
        'Volver a Pagada');
  }

  Future<void> _undoPayment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deshacer Pago'),
        content: const Text(
          'Se eliminará el pago y el asiento contable.\n\n¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar Pago'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _executeAction(() async {
        await _purchaseService.undoLastPayment(_invoice!.id!);
      });
    }
  }

  Future<void> _revertStatus(
      Future<void> Function() action, String actionName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(actionName),
        content: const Text('¿Revertir el estado de esta factura?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revertir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _executeAction(action);
    }
  }

  Future<void> _executeAction(Future<void> Function() action) async {
    setState(() => _isProcessing = true);
    try {
      await action();
      await _loadInvoice();
      setState(() => _hasChanges = true); // Mark that changes were made
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acción completada'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}

class _TimelineStep {
  final String label;
  final DateTime? date;
  final PurchaseInvoiceStatus requiredStatus;
  final bool highlighted;

  _TimelineStep(this.label, this.date, this.requiredStatus,
      {this.highlighted = false});
}
