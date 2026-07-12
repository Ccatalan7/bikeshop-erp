import 'package:flutter/material.dart';

import '../utils/chilean_utils.dart';

class CreditRefundMethodOption {
  const CreditRefundMethodOption({
    required this.id,
    required this.name,
    required this.requiresReference,
  });

  final String id;
  final String name;
  final bool requiresReference;
}

class CreditBalanceRefundInput {
  const CreditBalanceRefundInput({
    required this.refundedAt,
    required this.paymentMethodId,
    required this.amount,
    required this.reference,
    required this.reason,
  });

  final DateTime refundedAt;
  final String paymentMethodId;
  final int amount;
  final String reference;
  final String reason;
}

Future<CreditBalanceRefundInput?> showCreditBalanceRefundDialog({
  required BuildContext context,
  required String title,
  required String counterpartyLabel,
  required int availableAmount,
  required List<CreditRefundMethodOption> paymentMethods,
}) =>
    showDialog<CreditBalanceRefundInput>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreditBalanceRefundDialog(
        title: title,
        counterpartyLabel: counterpartyLabel,
        availableAmount: availableAmount,
        paymentMethods: paymentMethods,
      ),
    );

class _CreditBalanceRefundDialog extends StatefulWidget {
  const _CreditBalanceRefundDialog({
    required this.title,
    required this.counterpartyLabel,
    required this.availableAmount,
    required this.paymentMethods,
  });

  final String title;
  final String counterpartyLabel;
  final int availableAmount;
  final List<CreditRefundMethodOption> paymentMethods;

  @override
  State<_CreditBalanceRefundDialog> createState() =>
      _CreditBalanceRefundDialogState();
}

class _CreditBalanceRefundDialogState
    extends State<_CreditBalanceRefundDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  late DateTime _refundedAt;
  String? _methodId;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.availableAmount.toString());
    _refundedAt = DateTime.now();
    _methodId = widget.paymentMethods.firstOrNull?.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.paymentMethods
        .where((method) => method.id == _methodId)
        .firstOrNull;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Registra este movimiento solo después de verificar '
                    'que el dinero fue efectivamente '
                    '${widget.counterpartyLabel}. El ERP contabiliza y deja '
                    'la trazabilidad, pero no ejecuta la transferencia bancaria.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Saldo máximo: ${ChileanUtils.formatCurrency(widget.availableAmount.toDouble())}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 180,
                      child: TextFormField(
                        controller: _amount,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Monto CLP *'),
                        validator: (raw) {
                          final value = int.tryParse(raw?.trim() ?? '');
                          if (value == null || value <= 0) {
                            return 'Monto entero obligatorio.';
                          }
                          if (value > widget.availableAmount) {
                            return 'Supera el saldo disponible.';
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(
                      width: 270,
                      child: DropdownButtonFormField<String>(
                        initialValue: _methodId,
                        decoration:
                            const InputDecoration(labelText: 'Medio de pago *'),
                        items: widget.paymentMethods
                            .map((method) => DropdownMenuItem(
                                  value: method.id,
                                  child: Text(method.name),
                                ))
                            .toList(growable: false),
                        onChanged: (value) => setState(() => _methodId = value),
                        validator: (value) => value == null
                            ? 'Selecciona un medio de pago.'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reference,
                  decoration: InputDecoration(
                    labelText: selected?.requiresReference == true
                        ? 'Comprobante / referencia *'
                        : 'Comprobante, recibo o referencia *',
                  ),
                  validator: (value) => value?.trim().isEmpty ?? true
                      ? 'La referencia es obligatoria para auditar.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Motivo *'),
                  validator: (value) => value?.trim().isEmpty ?? true
                      ? 'Explica el motivo del movimiento.'
                      : null,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                        'Fecha ${_refundedAt.day.toString().padLeft(2, '0')}/'
                        '${_refundedAt.month.toString().padLeft(2, '0')}/'
                        '${_refundedAt.year}'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Registrar movimiento'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _refundedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _refundedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _refundedAt.hour,
        _refundedAt.minute,
      );
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      CreditBalanceRefundInput(
        refundedAt: _refundedAt,
        paymentMethodId: _methodId!,
        amount: int.parse(_amount.text.trim()),
        reference: _reference.text.trim(),
        reason: _reason.text.trim(),
      ),
    );
  }
}
