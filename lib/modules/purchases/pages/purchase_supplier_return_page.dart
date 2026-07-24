import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/purchase_invoice.dart';
import '../models/purchase_supplier_return.dart';
import '../services/purchase_supplier_return_service.dart';

class PurchaseSupplierReturnPage extends StatefulWidget {
  const PurchaseSupplierReturnPage({
    super.key,
    required this.invoice,
    this.service,
    this.focusReturnId,
    this.embedded = false,
    this.onClose,
  });

  final PurchaseInvoice invoice;
  final PurchaseSupplierReturnService? service;
  final String? focusReturnId;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  State<PurchaseSupplierReturnPage> createState() =>
      _PurchaseSupplierReturnPageState();
}

class _PurchaseSupplierReturnPageState
    extends State<PurchaseSupplierReturnPage> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _shipmentReference = TextEditingController();
  final _notes = TextEditingController();
  late final PurchaseSupplierReturnService _service;
  late final String _idempotencyKey;
  List<PurchaseReturnableReceipt> _receipts = const [];
  List<PurchaseSupplierReturnRecord> _history = const [];
  List<PurchaseSupplierReturnLineDraft> _lines = const [];
  String? _selectedReceiptId;
  DateTime _returnedAt = DateTime.now();
  String? _loadError;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PurchaseSupplierReturnService();
    _idempotencyKey = const Uuid().v4();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _shipmentReference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final invoiceId = widget.invoice.id;
      if (invoiceId == null) {
        throw StateError('La factura aún no está guardada.');
      }
      final results = await Future.wait([
        _service.getReturnableReceipts(invoiceId),
        _service.getSupplierReturns(invoiceId),
      ]);
      final receipts = results[0] as List<PurchaseReturnableReceipt>;
      final history = results[1] as List<PurchaseSupplierReturnRecord>;
      final focusedId = widget.focusReturnId;
      if (focusedId != null) {
        history.sort((a, b) {
          if (a.id == focusedId) return -1;
          if (b.id == focusedId) return 1;
          return b.returnedAt.compareTo(a.returnedAt);
        });
      }
      if (!mounted) return;
      setState(() {
        _receipts = receipts;
        _history = history;
        _selectedReceiptId = receipts.firstOrNull?.id;
        _lines = List.of(receipts.firstOrNull?.lines ?? const []);
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

  void _selectReceipt(String? receiptId) {
    final receipt = _receipts.where((item) => item.id == receiptId).firstOrNull;
    setState(() {
      _selectedReceiptId = receipt?.id;
      _lines = List.of(receipt?.lines ?? const []);
    });
  }

  void _replaceLine(int index, PurchaseSupplierReturnLineDraft line) {
    setState(() {
      final updated = List<PurchaseSupplierReturnLineDraft>.from(_lines);
      updated[index] = line;
      _lines = updated;
    });
  }

  int get _returnTotal =>
      _lines.fold(0, (sum, line) => sum + line.returnedQuantity);

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _returnedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _returnedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _returnedAt.hour,
        _returnedAt.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final receiptId = _selectedReceiptId;
    if (receiptId == null) {
      _showError('No existe una recepción con cantidades devolvibles.');
      return;
    }
    final selected = _lines.where((line) => line.isSelected).toList();
    if (selected.isEmpty) {
      _showError('Indica cuántas unidades se enviarán al proveedor.');
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
        title: const Text('Confirmar devolución física'),
        content: Text(
          'Saldrán $_returnTotal unidades del inventario y quedarán vinculadas '
          'a su recepción original.\n\nEsta acción no reduce la cuenta por pagar, '
          'no deshace pagos y no crea una nota de crédito.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Revisar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Registrar devolución'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final result = await _service.createSupplierReturn(
        receiptId: receiptId,
        lines: selected,
        returnedAt: _returnedAt,
        reason: _reason.text,
        idempotencyKey: _idempotencyKey,
        shipmentReference: _shipmentReference.text,
        notes: _notes.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 44),
          title: Text('Devolución ${result.returnNumber} registrada'),
          content: Text(
            result.replayed
                ? 'La solicitud ya estaba procesada. No se descontó inventario dos veces.'
                : 'La salida física y su trazabilidad quedaron registradas. '
                    'La corrección financiera sigue pendiente de una nota de crédito.',
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

  Future<void> _voidReturn(PurchaseSupplierReturnRecord record) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text('Anular ${record.returnNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'El stock se restaurará mediante movimientos enlazados. '
              'También se revertirá la reclasificación contable entre '
              'Inventarios y Reclamos a Proveedores. El documento original '
              'permanecerá visible como anulado.',
            ),
            const SizedBox(height: 10),
            const Text(
              'Si existe una nota de crédito vinculada, debes anular primero '
              'sus reembolsos y luego la nota.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration:
                  const InputDecoration(labelText: 'Motivo de anulación'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Anular y restaurar stock'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;

    setState(() => _submitting = true);
    try {
      await _service.voidSupplierReturn(
        supplierReturnId: record.id,
        reason: reason,
        idempotencyKey: const Uuid().v4(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${record.returnNumber} anulada; stock restaurado'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _loading = true;
        _loadError = null;
      });
      await _load();
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
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _loadError != null
            ? _ReturnErrorState(message: _loadError!, onRetry: _load)
            : widget.focusReturnId != null
                ? _buildFocusedReturn()
                : _receipts.isEmpty && _history.isEmpty
                    ? const _EmptyReturnState()
                    : _receipts.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(24),
                            children: [_buildHistory()],
                          )
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
                                          constraints: const BoxConstraints(
                                              maxWidth: 1000),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              _buildHeader(),
                                              const SizedBox(height: 16),
                                              _buildReturnFields(),
                                              const SizedBox(height: 20),
                                              Text(
                                                'Productos a devolver',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge,
                                              ),
                                              const SizedBox(height: 8),
                                              ..._lines.asMap().entries.map(
                                                    (entry) => Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              bottom: 12),
                                                      child: _ReturnLineCard(
                                                        line: entry.value,
                                                        onChanged: (line) =>
                                                            _replaceLine(
                                                                entry.key,
                                                                line),
                                                      ),
                                                    ),
                                                  ),
                                              if (_history.isNotEmpty) ...[
                                                const SizedBox(height: 20),
                                                _buildHistory(),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildFooter(),
                              ],
                            ),
                          );
    if (!widget.embedded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Devolver al proveedor')),
        body: body,
      );
    }
    return Column(
      children: [
        Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFD8DEE3)),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Volver a la factura',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.focusReturnId == null
                      ? 'Devolver al proveedor'
                      : 'Documento de devolución',
                  style: const TextStyle(
                    color: Color(0xFF26323A),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildFocusedReturn() {
    final record =
        _history.where((item) => item.id == widget.focusReturnId).firstOrNull;
    if (record == null) {
      return const Center(
        child: Text('No se encontró la devolución vinculada.'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0xFFD8DEE3)),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            record.returnNumber,
                            style: const TextStyle(
                              color: Color(0xFF26323A),
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          record.canVoid ? 'VIGENTE' : 'ANULADA',
                          style: TextStyle(
                            color: record.canVoid
                                ? const Color(0xFF2F6F62)
                                : const Color(0xFF874B4E),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Factura ${widget.invoice.invoiceNumber} · '
                      '${widget.invoice.supplierName ?? 'Sin proveedor'}',
                      style: const TextStyle(color: Color(0xFF68747D)),
                    ),
                    const Divider(height: 28),
                    _FocusedReturnField(
                      label: 'Fecha',
                      value:
                          '${record.returnedAt.day.toString().padLeft(2, '0')}/'
                          '${record.returnedAt.month.toString().padLeft(2, '0')}/'
                          '${record.returnedAt.year}',
                    ),
                    _FocusedReturnField(
                      label: 'Cantidad',
                      value: '${record.quantity} unidades',
                    ),
                    _FocusedReturnField(
                      label: 'Motivo',
                      value: record.reason,
                    ),
                    if ((record.shipmentReference ?? '').isNotEmpty)
                      _FocusedReturnField(
                        label: 'Guía / envío',
                        value: record.shipmentReference!,
                      ),
                    if ((record.voidReason ?? '').isNotEmpty)
                      _FocusedReturnField(
                        label: 'Motivo de anulación',
                        value: record.voidReason!,
                      ),
                    if (record.canVoid) ...[
                      const Divider(height: 28),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed:
                              _submitting ? null : () => _voidReturn(record),
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Anular devolución'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Factura',
                      style: Theme.of(context).textTheme.labelMedium),
                  Text(widget.invoice.invoiceNumber,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(widget.invoice.supplierName ?? 'Sin proveedor'),
                ],
              ),
            ),
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedReceiptId,
                decoration: const InputDecoration(
                  labelText: 'Recepción de origen',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                items: _receipts
                    .map(
                      (receipt) => DropdownMenuItem(
                        value: receipt.id,
                        child: Text(
                          '${receipt.receiptNumber} · ${receipt.returnableQuantity} disponibles',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _selectReceipt,
              ),
            ),
            const Chip(
              avatar: Icon(Icons.account_balance_outlined, size: 18),
              label: Text('Sin efecto financiero'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReturnFields() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 300,
              child: TextFormField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Motivo de la devolución',
                  prefixIcon: Icon(Icons.assignment_outlined),
                ),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'El motivo es obligatorio.'
                    : null,
              ),
            ),
            SizedBox(
              width: 240,
              child: TextFormField(
                controller: _shipmentReference,
                decoration: const InputDecoration(
                  labelText: 'Guía / envío (opcional)',
                  prefixIcon: Icon(Icons.local_shipping_outlined),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _selectDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                '${_returnedAt.day.toString().padLeft(2, '0')}/'
                '${_returnedAt.month.toString().padLeft(2, '0')}/'
                '${_returnedAt.year}',
              ),
            ),
            SizedBox(
              width: 300,
              child: TextFormField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notas / evidencia (opcional)',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Salida de inventario: $_returnTotal unidades · Efecto financiero: ninguno',
                  style: Theme.of(context).textTheme.titleMedium,
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
                    : const Icon(Icons.local_shipping_outlined),
                label: const Text('Revisar y registrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistory() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Historial de devoluciones',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ..._history.map(
              (record) => Card(
                child: ListTile(
                  leading: Icon(
                    record.canVoid ? Icons.local_shipping_outlined : Icons.undo,
                  ),
                  title: Text(
                    '${record.returnNumber} · ${record.quantity} unidades',
                  ),
                  subtitle: Text(
                    '${record.returnedAt.day.toString().padLeft(2, '0')}/'
                    '${record.returnedAt.month.toString().padLeft(2, '0')}/'
                    '${record.returnedAt.year} · ${record.reason}'
                    '${record.voidReason == null ? '' : ' · Anulada: ${record.voidReason}'}',
                  ),
                  trailing: record.canVoid
                      ? OutlinedButton.icon(
                          onPressed:
                              _submitting ? null : () => _voidReturn(record),
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Anular'),
                        )
                      : const Chip(label: Text('Anulada')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusedReturnField extends StatelessWidget {
  const _FocusedReturnField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF68747D),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF26323A),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReturnLineCard extends StatelessWidget {
  const _ReturnLineCard({required this.line, required this.onChanged});

  final PurchaseSupplierReturnLineDraft line;
  final ValueChanged<PurchaseSupplierReturnLineDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.inventory_2_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.productName,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    '${line.productSku ?? 'Sin SKU'} · Recibidas ${line.acceptedQuantity} · '
                    'Devueltas ${line.previouslyReturnedQuantity} · '
                    'Disponibles ${line.returnableQuantity}',
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 150,
              child: TextFormField(
                key: ValueKey('${line.receiptLineId}-${line.returnedQuantity}'),
                initialValue: line.returnedQuantity.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Devolver ahora'),
                onChanged: (value) => onChanged(
                  line.copyWith(returnedQuantity: int.tryParse(value) ?? 0),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 260,
              child: TextFormField(
                initialValue: line.reason,
                decoration:
                    const InputDecoration(labelText: 'Detalle (opcional)'),
                onChanged: (value) => onChanged(line.copyWith(reason: value)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyReturnState extends StatelessWidget {
  const _EmptyReturnState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Esta factura no tiene recepciones publicadas con cantidades pendientes de devolución.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ReturnErrorState extends StatelessWidget {
  const _ReturnErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
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
    );
  }
}
