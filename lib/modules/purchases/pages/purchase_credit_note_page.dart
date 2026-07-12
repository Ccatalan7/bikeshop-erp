import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/credit_balance_refund_dialog.dart';
import '../models/purchase_credit_note.dart';
import '../models/purchase_invoice.dart';
import '../services/purchase_credit_note_service.dart';

class PurchaseCreditNotePage extends StatefulWidget {
  const PurchaseCreditNotePage(
      {super.key, required this.invoice, this.service});
  final PurchaseInvoice invoice;
  final PurchaseCreditNoteService? service;

  @override
  State<PurchaseCreditNotePage> createState() => _PurchaseCreditNotePageState();
}

class _PurchaseCreditNotePageState extends State<PurchaseCreditNotePage> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _supplierNumber = TextEditingController();
  late final PurchaseCreditNoteService _service;
  late final String _idempotencyKey;
  List<PurchaseCreditNoteLineDraft> _lines = const [];
  List<PurchaseCreditReturnOption> _returnOptions = const [];
  List<PurchaseCreditNoteRecord> _history = const [];
  List<PurchaseSupplierRefundRecord> _refunds = const [];
  List<PurchaseRefundPaymentMethod> _refundMethods = const [];
  final DateTime _issueDate = DateTime.now();
  String _reasonCode = 'goods_return';
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _refundEnabled = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PurchaseCreditNoteService();
    _idempotencyKey = const Uuid().v4();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _supplierNumber.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final id = widget.invoice.id;
      if (id == null) throw StateError('La factura aún no está guardada.');
      final results = await Future.wait([
        _service.getLineBalances(id),
        _service.getReturnOptions(id),
        _service.getHistory(id),
        _service.getRefunds(id),
        _service.getRefundPaymentMethods(),
        _service.isRefundEnabled(),
      ]);
      if (!mounted) return;
      final balances = results[0] as List<PurchaseCreditNoteLineBalance>;
      setState(() {
        _lines = balances
            .where((line) => line.remainingNet + line.remainingTax > 0)
            .map((line) => PurchaseCreditNoteLineDraft(balance: line))
            .toList(growable: false);
        _returnOptions = results[1] as List<PurchaseCreditReturnOption>;
        _history = results[2] as List<PurchaseCreditNoteRecord>;
        _refunds = results[3] as List<PurchaseSupplierRefundRecord>;
        _refundMethods = results[4] as List<PurchaseRefundPaymentMethod>;
        _refundEnabled = results[5] as bool;
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

  void _replace(int index, PurchaseCreditNoteLineDraft line) {
    setState(() {
      final updated = List<PurchaseCreditNoteLineDraft>.from(_lines);
      updated[index] = line;
      _lines = updated;
    });
  }

  int get _net => _lines.fold(0, (sum, line) => sum + line.netAmount);
  int get _tax => _lines.fold(0, (sum, line) => sum + line.taxAmount);
  int get _total => _net + _tax;

  PurchaseCreditReturnOption? _optionFor(PurchaseCreditNoteLineDraft line) {
    return _returnOptions
        .where((option) => option.id == line.supplierReturnLineId)
        .firstOrNull;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final selected = _lines.where((line) => line.isSelected).toList();
    if (selected.isEmpty) {
      return _showError('Selecciona al menos un monto a acreditar.');
    }
    for (final line in selected) {
      final error = line.validate(returnOption: _optionFor(line));
      if (error != null) return _showError(error);
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar nota de crédito interna'),
        content: Text(
          'Neto: ${ChileanUtils.formatCurrency(_net.toDouble())}\n'
          'IVA crédito: ${ChileanUtils.formatCurrency(_tax.toDouble())}\n'
          'Total: ${ChileanUtils.formatCurrency(_total.toDouble())}\n\n'
          'Se reducirá la cuenta por pagar. No habrá movimiento de stock. '
          'Este documento no se presentará como DTE emitido.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Revisar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Registrar nota')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      final result = await _service.create(
        invoiceId: widget.invoice.id!,
        lines: selected,
        issueDate: _issueDate,
        reasonCode: _reasonCode,
        reason: _reason.text,
        supplierNumber: _supplierNumber.text,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 44),
          title: Text('${result.number} registrada'),
          content: Text(result.replayed
              ? 'La solicitud ya existía; no se duplicó el asiento.'
              : 'El ajuste financiero y su asiento balanceado quedaron trazados. Estado DTE: interno.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Listo'))
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

  Future<void> _void(PurchaseCreditNoteRecord record) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Anular ${record.number}'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration:
                const InputDecoration(labelText: 'Motivo de anulación')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Anular con reversión')),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await _service.voidNote(record.id, reason, const Uuid().v4());
      if (!mounted) return;
      setState(() => _loading = true);
      await _load();
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _recordRefund(PurchaseCreditNoteRecord record) async {
    if (_refundMethods.isEmpty) {
      return _showError(
          'Configura al menos un medio de pago activo antes de registrar el reembolso.');
    }
    final input = await showCreditBalanceRefundDialog(
      context: context,
      title: 'Registrar reembolso de ${record.number}',
      counterpartyLabel: 'recibido del proveedor',
      availableAmount: record.availableToRefund,
      paymentMethods: _refundMethods
          .map((method) => CreditRefundMethodOption(
                id: method.id,
                name: method.name,
                requiresReference: method.requiresReference,
              ))
          .toList(growable: false),
    );
    if (input == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      final result = await _service.createRefund(
        creditNoteId: record.id,
        refundedAt: input.refundedAt,
        paymentMethodId: input.paymentMethodId,
        amount: input.amount,
        reference: input.reference,
        reason: input.reason,
        idempotencyKey: const Uuid().v4(),
      );
      if (!mounted) return;
      _showSuccess(result.replayed
          ? 'El reembolso ya estaba registrado; no se duplicó.'
          : '${result.number} registrado y contabilizado.');
      setState(() => _loading = true);
      await _load();
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _voidRefund(PurchaseSupplierRefundRecord refund) async {
    final reason = await _askVoidReason('Anular reembolso ${refund.number}');
    if (reason == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await _service.voidRefund(refund.id, reason, const Uuid().v4());
      if (!mounted) return;
      _showSuccess('Reembolso anulado con asiento de reversión.');
      setState(() => _loading = true);
      await _load();
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String?> _askVoidReason(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
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
              child: const Text('Anular con reversión')),
        ],
      ),
    );
    controller.dispose();
    return value == null || value.isEmpty ? null : value;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red.shade700));
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), backgroundColor: Colors.green.shade700));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nota de crédito de compra')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
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
                                    _buildHeader(),
                                    const SizedBox(height: 16),
                                    _buildFields(),
                                    const SizedBox(height: 20),
                                    Text('Líneas acreditables',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(height: 8),
                                    if (_lines.isEmpty)
                                      const Card(
                                          child: Padding(
                                              padding: EdgeInsets.all(20),
                                              child: Text(
                                                  'No quedan montos acreditables.'))),
                                    ..._lines
                                        .asMap()
                                        .entries
                                        .map((entry) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 12),
                                              child: _CreditLineCard(
                                                line: entry.value,
                                                returnOptions: _returnOptions
                                                    .where((option) =>
                                                        option.sourceLineKey ==
                                                        entry.value.balance
                                                            .sourceLineKey)
                                                    .toList(),
                                                onChanged: (line) =>
                                                    _replace(entry.key, line),
                                              ),
                                            )),
                                    if (_history.isNotEmpty) ...[
                                      const SizedBox(height: 20),
                                      Text('Historial',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      const SizedBox(height: 8),
                                      ..._history.map(_historyCard),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _footer(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(spacing: 28, runSpacing: 10, children: [
            Text('Factura ${widget.invoice.invoiceNumber}',
                style: Theme.of(context).textTheme.titleMedium),
            Text(widget.invoice.supplierName ?? 'Sin proveedor'),
            Text(
                'Saldo: ${ChileanUtils.formatCurrency(widget.invoice.balance)}'),
            const Chip(
                avatar: Icon(Icons.verified_user_outlined, size: 18),
                label: Text('DTE interno, no emitido')),
          ]),
        ),
      );

  Widget _buildFields() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(spacing: 16, runSpacing: 16, children: [
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                initialValue: _reasonCode,
                decoration:
                    const InputDecoration(labelText: 'Tipo de corrección'),
                items: const [
                  DropdownMenuItem(
                      value: 'goods_return',
                      child: Text('Devolución de mercadería')),
                  DropdownMenuItem(
                      value: 'price_adjustment',
                      child: Text('Ajuste de precio')),
                  DropdownMenuItem(
                      value: 'invoice_correction',
                      child: Text('Corrección de factura')),
                  DropdownMenuItem(value: 'other', child: Text('Otro')),
                ],
                onChanged: (value) =>
                    setState(() => _reasonCode = value ?? 'other'),
              ),
            ),
            SizedBox(
              width: 320,
              child: TextFormField(
                controller: _reason,
                decoration:
                    const InputDecoration(labelText: 'Motivo detallado'),
                validator: (value) => value?.trim().isEmpty ?? true
                    ? 'Explica la corrección.'
                    : null,
              ),
            ),
            SizedBox(
                width: 240,
                child: TextFormField(
                    controller: _supplierNumber,
                    decoration: const InputDecoration(
                        labelText: 'Nº nota proveedor (opcional)'))),
          ]),
        ),
      );

  Widget _historyCard(PurchaseCreditNoteRecord record) {
    final refunds = _refunds
        .where((refund) => refund.purchaseCreditNoteId == record.id)
        .toList(growable: false);
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(
                '${record.number} · ${ChileanUtils.formatCurrency(record.totalAmount.toDouble())}'),
            subtitle: Text(
              '${record.reason} · DTE ${record.officialStatus}\n'
              'Reembolsado ${ChileanUtils.formatCurrency(record.refundedAmount.toDouble())} · '
              'Disponible ${ChileanUtils.formatCurrency(record.availableToRefund.toDouble())}'
              '${record.voidReason == null ? '' : ' · Anulada: ${record.voidReason}'}',
            ),
            isThreeLine: true,
            trailing: Wrap(
              spacing: 8,
              children: [
                if (record.canRefund && _refundEnabled)
                  FilledButton.tonalIcon(
                    onPressed: _submitting ? null : () => _recordRefund(record),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Registrar reembolso'),
                  ),
                if (record.canVoid)
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : () => _void(record),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Anular nota'),
                  )
                else if (!record.canRefund || !_refundEnabled)
                  Chip(label: Text(_noteStatusLabel(record))),
              ],
            ),
          ),
          ...refunds.map((refund) => Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${refund.number} · ${refund.paymentMethodName} · '
                        '${ChileanUtils.formatCurrency(refund.amount.toDouble())}\n'
                        'Ref. ${refund.reference} · ${refund.reason}'
                        '${refund.voidReason == null ? '' : ' · Anulado: ${refund.voidReason}'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (refund.canVoid)
                      TextButton(
                        onPressed:
                            _submitting ? null : () => _voidRefund(refund),
                        child: const Text('Anular reembolso'),
                      )
                    else
                      const Chip(label: Text('Anulado')),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  String _noteStatusLabel(PurchaseCreditNoteRecord record) {
    if (record.status == 'voided') return 'Anulada';
    if (!_refundEnabled && record.canRefund) {
      return 'Reembolsos en habilitación';
    }
    if (record.refundedAmount > 0) return 'Reembolso registrado';
    if (record.officialStatus == 'issued') return 'Requiere reversión DTE';
    return 'Sin saldo por reembolsar';
  }

  Widget _footer() => Material(
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(children: [
              Expanded(
                  child: Text(
                      'Neto ${ChileanUtils.formatCurrency(_net.toDouble())} · IVA ${ChileanUtils.formatCurrency(_tax.toDouble())} · Total ${ChileanUtils.formatCurrency(_total.toDouble())} · Stock sin cambios')),
              TextButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              const SizedBox(width: 8),
              FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Revisar y registrar')),
            ]),
          ),
        ),
      );
}

class _CreditLineCard extends StatelessWidget {
  const _CreditLineCard(
      {required this.line,
      required this.returnOptions,
      required this.onChanged});
  final PurchaseCreditNoteLineDraft line;
  final List<PurchaseCreditReturnOption> returnOptions;
  final ValueChanged<PurchaseCreditNoteLineDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(line.balance.productName,
              style: Theme.of(context).textTheme.titleMedium),
          Text(
              'Disponible: ${line.balance.remainingQuantity} un. · Neto ${ChileanUtils.formatCurrency(line.balance.remainingNet.toDouble())} · IVA ${ChileanUtils.formatCurrency(line.balance.remainingTax.toDouble())}'),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _number('Cantidad', line.quantity,
                (value) => onChanged(line.withQuantity(value))),
            _number('Neto crédito', line.netAmount,
                (value) => onChanged(line.copyWith(netAmount: value))),
            _number('IVA crédito', line.taxAmount,
                (value) => onChanged(line.copyWith(taxAmount: value))),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<PurchaseCreditDisposition>(
                initialValue: line.disposition,
                decoration: const InputDecoration(labelText: 'Respaldo físico'),
                items: const [
                  DropdownMenuItem(
                      value: PurchaseCreditDisposition.financialOnly,
                      child: Text('Solo financiero')),
                  DropdownMenuItem(
                      value: PurchaseCreditDisposition.supplierReturn,
                      child: Text('Devolución registrada')),
                ],
                onChanged: (value) => onChanged(line.copyWith(
                    disposition: value,
                    clearSupplierReturn:
                        value == PurchaseCreditDisposition.financialOnly)),
              ),
            ),
            if (line.disposition == PurchaseCreditDisposition.supplierReturn)
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  initialValue: line.supplierReturnLineId,
                  decoration:
                      const InputDecoration(labelText: 'Devolución de origen'),
                  items: returnOptions
                      .map((option) => DropdownMenuItem(
                          value: option.id,
                          child: Text(
                              '${option.returnNumber} · ${option.remainingQuantity} un.')))
                      .toList(),
                  onChanged: (value) =>
                      onChanged(line.copyWith(supplierReturnLineId: value)),
                ),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _number(String label, int value, ValueChanged<int> changed) =>
      SizedBox(
        width: 145,
        child: TextFormField(
          key: ValueKey('$label-$value'),
          initialValue: value.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
          onChanged: (raw) => changed(int.tryParse(raw) ?? 0),
        ),
      );
}
