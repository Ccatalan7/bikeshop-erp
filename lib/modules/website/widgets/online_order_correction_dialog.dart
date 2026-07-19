import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../models/online_order_correction.dart';
import '../models/website_models.dart';
import '../services/website_service.dart';

Future<bool?> showOnlineOrderCorrectionDialog({
  required BuildContext context,
  required OnlineOrder order,
  required WebsiteService service,
  bool cancelOrder = false,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OnlineOrderCorrectionDialog(
      order: order,
      service: service,
      cancelOrder: cancelOrder,
    ),
  );
}

class _OnlineOrderCorrectionDialog extends StatefulWidget {
  const _OnlineOrderCorrectionDialog({
    required this.order,
    required this.service,
    required this.cancelOrder,
  });

  final OnlineOrder order;
  final WebsiteService service;
  final bool cancelOrder;

  @override
  State<_OnlineOrderCorrectionDialog> createState() =>
      _OnlineOrderCorrectionDialogState();
}

class _OnlineOrderCorrectionDialogState
    extends State<_OnlineOrderCorrectionDialog> {
  final _reasonController = TextEditingController();
  final _manualReferenceController = TextEditingController();
  final _operationKey = const Uuid().v4();
  late Future<_CorrectionDialogData> _dataFuture;
  final Map<int, int> _quantities = {};
  final Map<int, String> _dispositions = {};
  final Set<int> _selected = {};
  bool _initializedLines = false;
  bool _saving = false;
  DateTime _manualRefundedAt = DateTime.now();
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _dataFuture = Future.wait([
      widget.service.loadOnlineOrderCorrectionPreview(widget.order.id),
      widget.service.loadLatestOnlineOrderCorrection(widget.order.id),
    ]).then(
      (values) => _CorrectionDialogData(
        preview: values[0] as OnlineOrderCorrectionPreview,
        existing: values[1] as OnlineOrderCorrectionRecord?,
      ),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _manualReferenceController.dispose();
    super.dispose();
  }

  void _initializeLines(OnlineOrderCorrectionPreview preview) {
    if (_initializedLines) return;
    _initializedLines = true;
    for (final line in preview.lines) {
      _selected.add(line.lineIndex);
      _quantities[line.lineIndex] = line.remainingQuantity;
      _dispositions[line.lineIndex] =
          line.physicalReturnAllowed ? 'restock' : 'financial_only';
    }
  }

  double _selectedAmount(OnlineOrderCorrectionPreview preview) {
    var total = 0.0;
    for (final line in preview.lines) {
      if (!_selected.contains(line.lineIndex) || line.remainingQuantity <= 0) {
        continue;
      }
      total += line.amountForQuantity(_quantities[line.lineIndex] ?? 0);
    }
    return total;
  }

  Future<void> _pickManualRefundDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _manualRefundedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (selected == null || !mounted) return;
    final current = DateTime.now();
    setState(() {
      _manualRefundedAt = DateTime(
        selected.year,
        selected.month,
        selected.day,
        current.hour,
        current.minute,
      );
    });
  }

  Future<void> _submit(
    OnlineOrderCorrectionPreview preview,
    OnlineOrderCorrectionRecord? existing,
  ) async {
    if (_saving) return;
    final selectedLines = preview.lines
        .where((line) => _selected.contains(line.lineIndex))
        .map(
          (line) => OnlineOrderCorrectionLineRequest(
            lineIndex: line.lineIndex,
            quantity: _quantities[line.lineIndex] ?? 0,
            disposition: _dispositions[line.lineIndex] ?? 'financial_only',
          ),
        )
        .where((line) => line.quantity > 0)
        .toList(growable: false);
    if (existing == null &&
        (selectedLines.isEmpty || _reasonController.text.trim().length < 4)) {
      setState(() {
        _error = selectedLines.isEmpty
            ? 'Selecciona al menos una línea.'
            : 'Escribe un motivo verificable.';
      });
      return;
    }
    if ((existing?.needsManualEvidence ?? !preview.isMercadoPago) &&
        _manualReferenceController.text.trim().isEmpty) {
      setState(() => _error =
          'Confirma la referencia del dinero devuelto antes de continuar.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final correction = existing ??
          await widget.service.requestOnlineOrderCorrection(
            orderId: widget.order.id,
            expectedVersion: preview.orderVersion,
            lines: selectedLines,
            reason: _reasonController.text.trim(),
            operationKey: _operationKey,
            correctionIntent:
                widget.cancelOrder ? 'cancel_before_fulfillment' : 'return',
          );
      await widget.service.executeOnlineOrderCorrection(
        correction,
        manualReference: correction.needsManualEvidence
            ? _manualReferenceController.text.trim()
            : null,
        manualRefundedAt:
            correction.needsManualEvidence ? _manualRefundedAt : null,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
        _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: FutureBuilder<_CorrectionDialogData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || snapshot.data == null) {
              return _LoadFailure(
                message: snapshot.error.toString(),
                onRetry: () => setState(_load),
              );
            }
            final data = snapshot.data!;
            _initializeLines(data.preview);
            final existing = data.existing;
            final unresolved = existing != null && !existing.isApplied;
            final activeExisting = unresolved ? existing : null;
            final cancelIntent = widget.cancelOrder ||
                activeExisting?.correctionIntent == 'cancel_before_fulfillment';
            final selectedAmount =
                unresolved ? existing.amount : _selectedAmount(data.preview);
            return Column(
              children: [
                Container(
                  width: double.infinity,
                  color: theme.colorScheme.inverseSurface,
                  padding: const EdgeInsets.fromLTRB(22, 17, 14, 17),
                  child: Row(
                    children: [
                      Icon(
                        Icons.assignment_return_outlined,
                        color: theme.colorScheme.onInverseSurface,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Corrección · ${widget.order.orderNumber}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onInverseSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Dinero, stock y contabilidad con evidencia separada',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onInverseSurface
                                    .withValues(alpha: .72),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        color: theme.colorScheme.onInverseSurface,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!data.preview.controlsReady)
                          const _AttentionStrip(
                            text:
                                'Los controles contables de devoluciones aún no están activos. '
                                'No se moverá dinero ni stock hasta completar esa habilitación.',
                            error: true,
                          )
                        else if (unresolved)
                          _AttentionStrip(
                            text: existing.processingState == 'action_required'
                                ? existing.lastErrorMessage ??
                                    'La corrección requiere reintento o conciliación.'
                                : 'Ya existe una solicitud. Se reanudará sin crear otro reembolso.',
                            error:
                                existing.processingState == 'action_required',
                          )
                        else
                          _AttentionStrip(
                            text: data.preview.isMercadoPago
                                ? 'Mercado Pago se reembolsa primero con una clave idempotente. '
                                    'Después se aplican los efectos internos.'
                                : 'Ejecuta la devolución bancaria fuera del ERP y registra aquí '
                                    'su referencia verificable.',
                          ),
                        const SizedBox(height: 20),
                        if (!unresolved) ...[
                          Text(
                            'Líneas a corregir',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 7),
                          for (final line in data.preview.lines)
                            _CorrectionLineRow(
                              line: line,
                              selected: _selected.contains(line.lineIndex),
                              quantity: _quantities[line.lineIndex] ?? 0,
                              disposition: _dispositions[line.lineIndex] ??
                                  'financial_only',
                              onSelected: (value) => setState(() {
                                value
                                    ? _selected.add(line.lineIndex)
                                    : _selected.remove(line.lineIndex);
                              }),
                              onQuantityChanged: (value) => setState(
                                () => _quantities[line.lineIndex] = value,
                              ),
                              onDispositionChanged: (value) => setState(
                                () => _dispositions[line.lineIndex] = value,
                              ),
                            ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _reasonController,
                            maxLines: 2,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Motivo obligatorio',
                              hintText:
                                  'Ej.: cliente devolvió el producto sin uso',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _saving ? null : _pickManualRefundDate,
                              icon: const Icon(Icons.calendar_today_outlined,
                                  size: 17),
                              label: Text(
                                'Fecha efectiva · ${MaterialLocalizations.of(context).formatShortDate(_manualRefundedAt)}',
                              ),
                            ),
                          ),
                        ],
                        if ((activeExisting?.needsManualEvidence ??
                            !data.preview.isMercadoPago)) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: _manualReferenceController,
                            decoration: const InputDecoration(
                              labelText: 'Referencia de devolución verificada',
                              hintText: 'Ej.: transferencia BCI 483921',
                              prefixIcon: Icon(Icons.verified_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    border: Border(
                      top: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Monto a devolver',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            ChileanUtils.formatCurrency(selectedAmount),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        child: const Text('Volver'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _saving || !data.preview.controlsReady
                            ? null
                            : () => _submit(
                                  data.preview,
                                  activeExisting,
                                ),
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(unresolved
                                ? Icons.refresh_rounded
                                : Icons.assignment_return_outlined),
                        label: Text(unresolved
                            ? 'Reanudar corrección'
                            : cancelIntent
                                ? 'Reembolsar y cancelar'
                                : 'Solicitar devolución'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CorrectionLineRow extends StatelessWidget {
  const _CorrectionLineRow({
    required this.line,
    required this.selected,
    required this.quantity,
    required this.disposition,
    required this.onSelected,
    required this.onQuantityChanged,
    required this.onDispositionChanged,
  });

  final OnlineOrderCorrectionLinePreview line;
  final bool selected;
  final int quantity;
  final String disposition;
  final ValueChanged<bool> onSelected;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<String> onDispositionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Checkbox(value: selected, onChanged: (v) => onSelected(v ?? false)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.productName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  [
                    if (line.productSku?.trim().isNotEmpty == true)
                      line.productSku!,
                    line.isService ? 'Servicio' : 'Producto',
                    ChileanUtils.formatCurrency(line.remainingTotal),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 112,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: selected && quantity > 1
                      ? () => onQuantityChanged(quantity - 1)
                      : null,
                  icon: const Icon(Icons.remove_rounded, size: 17),
                ),
                Text('$quantity',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: selected && quantity < line.remainingQuantity
                      ? () => onQuantityChanged(quantity + 1)
                      : null,
                  icon: const Icon(Icons.add_rounded, size: 17),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 166,
            child: DropdownButtonFormField<String>(
              initialValue: disposition,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Tratamiento',
                border: OutlineInputBorder(),
              ),
              items: line.physicalReturnAllowed
                  ? const [
                      DropdownMenuItem(
                          value: 'restock', child: Text('Reponer')),
                      DropdownMenuItem(
                          value: 'quarantine', child: Text('Cuarentena')),
                      DropdownMenuItem(
                          value: 'scrap', child: Text('Dar de baja')),
                      DropdownMenuItem(
                          value: 'financial_only',
                          child: Text('Solo financiero')),
                    ]
                  : const [
                      DropdownMenuItem(
                        value: 'financial_only',
                        child: Text('Solo financiero'),
                      ),
                    ],
              onChanged: selected
                  ? (value) {
                      if (value != null) onDispositionChanged(value);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionStrip extends StatelessWidget {
  const _AttentionStrip({required this.text, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFF9A3412) : const Color(0xFF315C78);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Text(text, style: TextStyle(color: color, height: 1.35)),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 28),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

class _CorrectionDialogData {
  const _CorrectionDialogData({required this.preview, required this.existing});
  final OnlineOrderCorrectionPreview preview;
  final OnlineOrderCorrectionRecord? existing;
}
