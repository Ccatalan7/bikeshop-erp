import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/sales_models.dart';
import '../models/sales_return.dart';
import '../services/sales_return_service.dart';

class SalesReturnPage extends StatefulWidget {
  const SalesReturnPage({
    super.key,
    required this.invoice,
    this.service,
  });
  final Invoice invoice;
  final SalesReturnService? service;

  @override
  State<SalesReturnPage> createState() => _SalesReturnPageState();
}

class _SalesReturnPageState extends State<SalesReturnPage> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  late final SalesReturnService _service;
  late String _idempotencyKey;
  List<SalesReturnLineDraft> _lines = const [];
  List<SalesReturnRecord> _history = const [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SalesReturnService();
    _idempotencyKey = const Uuid().v4();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final id = widget.invoice.id;
      if (id == null) throw StateError('La factura aún no está guardada.');
      final results = await Future.wait([
        _service.getReturnableLines(widget.invoice),
        _service.getHistory(id),
      ]);
      if (!mounted) return;
      setState(() {
        _lines = (results[0] as List<SalesReturnableLine>)
            .map((line) => SalesReturnLineDraft(line: line))
            .toList(growable: false);
        _history = results[1] as List<SalesReturnRecord>;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await _load();
  }

  void _replace(int index, SalesReturnLineDraft line) {
    setState(() {
      final updated = List<SalesReturnLineDraft>.from(_lines);
      updated[index] = line;
      _lines = updated;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final selected = _lines.where((line) => line.isSelected).toList();
    if (selected.isEmpty) {
      return _showError('Indica al menos una cantidad devuelta.');
    }
    for (final line in selected) {
      final error = line.validate();
      if (error != null) return _showError(error);
    }
    final restock = selected
        .where((line) => line.disposition == SalesReturnDisposition.restock)
        .fold<int>(0, (sum, line) => sum + line.quantity);
    final quarantine = selected
        .where((line) => line.disposition == SalesReturnDisposition.quarantine)
        .fold<int>(0, (sum, line) => sum + line.quantity);
    final scrap = selected
        .where((line) => line.disposition == SalesReturnDisposition.scrap)
        .fold<int>(0, (sum, line) => sum + line.quantity);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar devolución física'),
        content: Text(
          'Stock disponible: +$restock\nA inspección: $quarantine\nBaja: $scrap\n\n'
          'Cada unidad quedará vinculada a la salida original. Esta acción '
          'registra custodia y valor de inventario, pero no reduce el saldo '
          'del cliente: la corrección financiera se hace con nota de crédito.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Revisar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Registrar devolución')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      final result = await _service.create(
        invoiceId: widget.invoice.id!,
        lines: selected,
        returnedAt: DateTime.now(),
        reason: _reason.text,
        notes: _notes.text,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      _showSuccess(result.replayed
          ? 'La solicitud ya existía; no se duplicó el movimiento.'
          : '${result.number} registrada con trazabilidad completa.');
      _reason.clear();
      _notes.clear();
      _idempotencyKey = const Uuid().v4();
      await _reload();
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String?> _askReason(String title, String action) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Motivo obligatorio'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(action)),
        ],
      ),
    );
    controller.dispose();
    return result == null || result.isEmpty ? null : result;
  }

  Future<void> _resolve(SalesReturnHistoryLine line, String disposition) async {
    final reason = await _askReason(
        disposition == 'release' ? 'Liberar a stock' : 'Dar de baja',
        disposition == 'release' ? 'Liberar' : 'Registrar baja');
    if (reason == null || line.quarantineId == null) return;
    await _runAction(() => _service.resolveQuarantine(
          quarantineId: line.quarantineId!,
          disposition: disposition,
          reason: reason,
          idempotencyKey: const Uuid().v4(),
        ));
  }

  Future<void> _voidResolution(SalesReturnHistoryLine line) async {
    final reason = await _askReason('Reabrir inspección', 'Reabrir');
    if (reason == null || line.resolutionId == null) return;
    await _runAction(() =>
        _service.voidResolution(line.resolutionId!, reason, const Uuid().v4()));
  }

  Future<void> _voidReturn(SalesReturnRecord record) async {
    final reason =
        await _askReason('Anular ${record.number}', 'Anular con reversión');
    if (reason == null) return;
    await _runAction(
        () => _service.voidReturn(record.id, reason, const Uuid().v4()));
  }

  Future<void> _runAction(Future<dynamic> Function() action) async {
    setState(() => _submitting = true);
    try {
      await action();
      if (!mounted) return;
      _showSuccess('Acción registrada y trazada.');
      await _reload();
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String text) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.red.shade700));
  void _showSuccess(String text) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.green.shade700));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devoluciones de cliente')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1050),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _header(),
                              const SizedBox(height: 16),
                              _fields(),
                              const SizedBox(height: 20),
                              Text('Productos devolvibles',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 8),
                              if (_lines.isEmpty)
                                const Card(
                                    child: Padding(
                                        padding: EdgeInsets.all(20),
                                        child: Text(
                                            'No quedan productos devolvibles.'))),
                              ..._lines.asMap().entries.map(
                                  (entry) => _lineCard(entry.key, entry.value)),
                              const SizedBox(height: 20),
                              if (_history.isNotEmpty) ...[
                                Text('Historial e inspecciones',
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 8),
                                ..._history.map(_historyCard),
                              ],
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: _submitting || _lines.isEmpty
                                    ? null
                                    : _submit,
                                icon: _submitting
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(
                                        Icons.assignment_return_outlined),
                                label:
                                    const Text('Registrar devolución física'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _header() => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(spacing: 24, runSpacing: 8, children: [
            Text('Factura ${widget.invoice.invoiceNumber}',
                style: Theme.of(context).textTheme.titleMedium),
            Text(widget.invoice.customerName ?? 'Sin cliente'),
            const Chip(
                avatar: Icon(Icons.link, size: 18),
                label: Text('Vinculada a salida original')),
          ]),
        ),
      );

  Widget _fields() => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(spacing: 16, runSpacing: 12, children: [
            SizedBox(
              width: 360,
              child: TextFormField(
                controller: _reason,
                decoration:
                    const InputDecoration(labelText: 'Motivo de la devolución'),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Explica por qué vuelve la mercadería.'
                    : null,
              ),
            ),
            SizedBox(
                width: 360,
                child: TextFormField(
                    controller: _notes,
                    decoration: const InputDecoration(
                        labelText: 'Notas de recepción (opcional)'))),
          ]),
        ),
      );

  Widget _lineCard(int index, SalesReturnLineDraft draft) => Card(
        key: ValueKey('return-${draft.line.lineIndex}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 18,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 340,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(draft.line.productName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                          '${draft.line.productSku ?? 'Sin SKU'} · Vendidas ${draft.line.soldQuantity} · Ya devueltas ${draft.line.returnedQuantity} · Disponibles ${draft.line.remainingQuantity}'),
                    ]),
              ),
              SizedBox(
                width: 130,
                child: TextFormField(
                  initialValue: draft.quantity.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                  onChanged: (value) => _replace(index,
                      draft.copyWith(quantity: int.tryParse(value) ?? 0)),
                ),
              ),
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<SalesReturnDisposition>(
                  initialValue: draft.disposition,
                  decoration:
                      const InputDecoration(labelText: 'Destino físico'),
                  items: SalesReturnDisposition.values
                      .map((value) => DropdownMenuItem(
                          value: value, child: Text(value.label)))
                      .toList(),
                  onChanged: (value) =>
                      _replace(index, draft.copyWith(disposition: value)),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _historyCard(SalesReturnRecord record) {
    final hasResolution = record.lines.any((line) => line.hasActiveResolution);
    return Card(
      child: ExpansionTile(
        title: Text(
            '${record.number} · ${record.status == 'posted' ? 'Registrada' : 'Anulada'}'),
        subtitle: Text(record.reason),
        trailing: record.canVoid && !hasResolution
            ? OutlinedButton.icon(
                onPressed: _submitting ? null : () => _voidReturn(record),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Anular'))
            : null,
        children: record.lines
            .map((line) => ListTile(
                  title: Text('${line.productName} · ${line.quantity} u.'),
                  subtitle: Text(line.disposition == 'quarantine'
                      ? 'Inspección: ${line.quarantineStatus ?? 'sin estado'}'
                      : line.disposition == 'restock'
                          ? 'Repuesta al stock'
                          : 'Baja directa'),
                  trailing: line.isHeld
                      ? Wrap(spacing: 8, children: [
                          TextButton(
                              onPressed: _submitting
                                  ? null
                                  : () => _resolve(line, 'scrap'),
                              child: const Text('Dar de baja')),
                          FilledButton(
                              onPressed: _submitting
                                  ? null
                                  : () => _resolve(line, 'release'),
                              child: const Text('Liberar a stock')),
                        ])
                      : line.hasActiveResolution
                          ? OutlinedButton(
                              onPressed: _submitting
                                  ? null
                                  : () => _voidResolution(line),
                              child: const Text('Reabrir inspección'))
                          : null,
                ))
            .toList(),
      ),
    );
  }
}
