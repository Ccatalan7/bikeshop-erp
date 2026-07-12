import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/purchase_invoice.dart';
import '../models/purchase_receipt.dart';
import '../services/purchase_receiving_service.dart';

class PurchaseReceivingPage extends StatefulWidget {
  const PurchaseReceivingPage({
    super.key,
    required this.invoice,
    this.service,
  });

  final PurchaseInvoice invoice;
  final PurchaseReceivingService? service;

  @override
  State<PurchaseReceivingPage> createState() => _PurchaseReceivingPageState();
}

class _PurchaseReceivingPageState extends State<PurchaseReceivingPage> {
  final _formKey = GlobalKey<FormState>();
  final _deliveryReference = TextEditingController();
  final _location = TextEditingController(text: 'Bodega principal');
  final _notes = TextEditingController();
  late final PurchaseReceivingService _service;
  late final String _idempotencyKey;
  List<PurchaseReceiptLineDraft> _lines = const [];
  DateTime _receivedAt = DateTime.now();
  String? _loadError;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PurchaseReceivingService();
    _idempotencyKey = const Uuid().v4();
    _load();
  }

  @override
  void dispose() {
    _deliveryReference.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final invoiceId = widget.invoice.id;
      if (invoiceId == null) {
        throw StateError('La factura aún no está guardada.');
      }
      final previous = await _service.getPreviouslyReceivedByLine(invoiceId);
      final lines = <PurchaseReceiptLineDraft>[];
      for (var index = 0; index < widget.invoice.items.length; index++) {
        final item = widget.invoice.items[index];
        if (item.quantity != item.quantity.roundToDouble()) {
          throw StateError(
            '${item.productName ?? 'Producto'} usa una cantidad fraccionaria. '
            'Esta recepción exige unidades enteras.',
          );
        }
        final expected = item.quantity.toInt();
        final received = previous[index] ?? 0;
        if (received > expected) {
          throw StateError(
            '${item.productName ?? 'Producto'} registra $received unidades recibidas '
            'sobre $expected esperadas. Revisa la trazabilidad antes de continuar.',
          );
        }
        lines.add(PurchaseReceiptLineDraft(
          lineIndex: index,
          productName: item.productName ?? item.description ?? 'Producto',
          productSku: item.productSku,
          expectedQuantity: expected,
          previouslyReceivedQuantity: received,
          acceptedQuantity: expected - received,
        ));
      }
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  void _replaceLine(int position, PurchaseReceiptLineDraft line) {
    setState(() {
      final updated = List<PurchaseReceiptLineDraft>.from(_lines);
      updated[position] = line;
      _lines = updated;
    });
  }

  int get _acceptedTotal =>
      _lines.fold(0, (sum, line) => sum + line.acceptedQuantity);
  int get _discrepancyTotal => _lines.fold(
        0,
        (sum, line) =>
            sum +
            line.damagedQuantity +
            line.rejectedQuantity +
            line.shortageQuantity,
      );
  int get _remainingTotal =>
      _lines.fold(0, (sum, line) => sum + line.remainingAfter);

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _receivedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _receivedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _receivedAt.hour,
        _receivedAt.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final selected = _lines.where((line) => line.hasEffect).toList();
    if (selected.isEmpty) {
      _showError('Selecciona al menos una cantidad para recibir o reportar.');
      return;
    }
    for (final line in selected) {
      final error = line.validate();
      if (error != null) {
        _showError(error);
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar recepción física'),
        content: Text(
          'Entrarán $_acceptedTotal unidades al inventario. '
          'Se registrarán $_discrepancyTotal unidades con diferencia y '
          'quedarán $_remainingTotal pendientes.\n\n'
          'Esta acción no registra ni modifica pagos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Revisar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar recepción'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final result = await _service.createReceipt(
        invoiceId: widget.invoice.id!,
        lines: selected,
        receivedAt: _receivedAt,
        idempotencyKey: _idempotencyKey,
        deliveryReference: _deliveryReference.text,
        locationLabel: _location.text,
        notes: _notes.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 44),
          title: Text('Recepción ${result.receiptNumber} registrada'),
          content: Text(
            result.replayed
                ? 'La solicitud ya había sido procesada. No se duplicó inventario.'
                : 'El inventario aceptado y la trazabilidad quedaron registrados. '
                    'Los pagos y la cuenta por pagar no cambiaron.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Listo'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recibir productos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _ErrorState(message: _loadError!, onRetry: _load)
              : Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1100),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildHeader(context),
                                    const SizedBox(height: 16),
                                    _buildReceiptFields(),
                                    const SizedBox(height: 20),
                                    Text('Revisión por producto',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(height: 8),
                                    ..._lines.asMap().entries.map(
                                          (entry) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 12),
                                            child: _ReceiptLineCard(
                                              line: entry.value,
                                              onChanged: (line) =>
                                                  _replaceLine(entry.key, line),
                                            ),
                                          ),
                                        ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildFooter(context),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 32,
          runSpacing: 12,
          children: [
            _HeaderValue(label: 'Factura', value: widget.invoice.invoiceNumber),
            _HeaderValue(
              label: 'Proveedor',
              value: widget.invoice.supplierName ?? 'Sin proveedor',
            ),
            _HeaderValue(
              label: 'Estado contable',
              value: widget.invoice.status.displayName,
            ),
            const _HeaderValue(
              label: 'Efecto del pago',
              value: 'Sin cambios',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptFields() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 230,
              child: TextFormField(
                controller: _location,
                decoration: const InputDecoration(
                  labelText: 'Ubicación de recepción',
                  prefixIcon: Icon(Icons.warehouse_outlined),
                ),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Indica dónde quedó el stock.'
                    : null,
              ),
            ),
            SizedBox(
              width: 230,
              child: TextFormField(
                controller: _deliveryReference,
                decoration: const InputDecoration(
                  labelText: 'Guía / referencia (opcional)',
                  prefixIcon: Icon(Icons.local_shipping_outlined),
                ),
              ),
            ),
            SizedBox(
              width: 190,
              child: OutlinedButton.icon(
                onPressed: _selectDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  '${_receivedAt.day.toString().padLeft(2, '0')}/'
                  '${_receivedAt.month.toString().padLeft(2, '0')}/'
                  '${_receivedAt.year}',
                ),
              ),
            ),
            SizedBox(
              width: 300,
              child: TextFormField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notas de recepción (opcional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Inventario +$_acceptedTotal  •  Diferencias $_discrepancyTotal  •  Pendiente $_remainingTotal',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: _submitting ? null : () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.inventory_2_outlined),
                label: const Text('Revisar y registrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptLineCard extends StatelessWidget {
  const _ReceiptLineCard({required this.line, required this.onChanged});

  final PurchaseReceiptLineDraft line;
  final ValueChanged<PurchaseReceiptLineDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final completed = line.remainingBefore == 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.productName,
                          style: Theme.of(context).textTheme.titleMedium),
                      if (line.productSku?.isNotEmpty ?? false)
                        Text(line.productSku!,
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(
                  'Esperado ${line.expectedQuantity}  •  Anterior ${line.previouslyReceivedQuantity}  •  Pendiente ${line.remainingBefore}',
                ),
              ],
            ),
            if (completed)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Línea completamente recibida.'),
              )
            else ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _QuantityField(
                    label: 'Aceptadas',
                    value: line.acceptedQuantity,
                    onChanged: (value) =>
                        onChanged(line.copyWith(acceptedQuantity: value)),
                  ),
                  _QuantityField(
                    label: 'Dañadas',
                    value: line.damagedQuantity,
                    onChanged: (value) =>
                        onChanged(line.copyWith(damagedQuantity: value)),
                  ),
                  _QuantityField(
                    label: 'Rechazadas',
                    value: line.rejectedQuantity,
                    onChanged: (value) =>
                        onChanged(line.copyWith(rejectedQuantity: value)),
                  ),
                  _QuantityField(
                    label: 'Faltantes',
                    value: line.shortageQuantity,
                    onChanged: (value) =>
                        onChanged(line.copyWith(shortageQuantity: value)),
                  ),
                  SizedBox(
                    width: 330,
                    child: TextFormField(
                      initialValue: line.discrepancyReason,
                      decoration: InputDecoration(
                        labelText: line.hasDiscrepancy
                            ? 'Motivo de la diferencia'
                            : 'Motivo (si hay diferencia)',
                      ),
                      onChanged: (value) =>
                          onChanged(line.copyWith(discrepancyReason: value)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Después de esta recepción quedarán ${line.remainingAfter} unidades pendientes.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuantityField extends StatelessWidget {
  const _QuantityField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 125,
      child: TextFormField(
        key: ValueKey('$label-$value'),
        initialValue: value.toString(),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: (raw) => onChanged(int.tryParse(raw) ?? 0),
      ),
    );
  }
}

class _HeaderValue extends StatelessWidget {
  const _HeaderValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 3),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              const Text('No se puede preparar la recepción'),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
