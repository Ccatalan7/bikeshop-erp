import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/credit_balance_refund_dialog.dart';
import '../models/sales_credit_note.dart';
import '../models/sales_models.dart';
import '../services/sales_credit_note_service.dart';

class SalesCreditNotePage extends StatefulWidget {
  const SalesCreditNotePage({
    super.key,
    required this.invoice,
    this.service,
  });
  final Invoice invoice;
  final SalesCreditNoteService? service;

  @override
  State<SalesCreditNotePage> createState() => _SalesCreditNotePageState();
}

class _SalesCreditNotePageState extends State<SalesCreditNotePage> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final SalesCreditNoteService _service;
  late String _idempotencyKey;
  List<SalesCreditNoteLineDraft> _lines = const [];
  List<SalesCreditReturnOption> _returnOptions = const [];
  List<SalesCreditNoteRecord> _history = const [];
  List<SalesCustomerRefundRecord> _refunds = const [];
  List<SalesRefundPaymentMethod> _refundMethods = const [];
  String _reasonCode = 'goods_return';
  bool _loading = true;
  bool _submitting = false;
  bool _refundEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SalesCreditNoteService();
    _idempotencyKey = const Uuid().v4();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
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
      setState(() {
        _lines = (results[0] as List<SalesCreditNoteLineBalance>)
            .where((line) => line.remainingNet + line.remainingTax > 0)
            .map((line) => SalesCreditNoteLineDraft(balance: line))
            .toList(growable: false);
        _returnOptions = results[1] as List<SalesCreditReturnOption>;
        _history = results[2] as List<SalesCreditNoteRecord>;
        _refunds = results[3] as List<SalesCustomerRefundRecord>;
        _refundMethods = results[4] as List<SalesRefundPaymentMethod>;
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

  void _replace(int index, SalesCreditNoteLineDraft line) {
    setState(() {
      final updated = List<SalesCreditNoteLineDraft>.from(_lines);
      updated[index] = line;
      _lines = updated;
    });
  }

  SalesCreditReturnOption? _optionFor(SalesCreditNoteLineDraft line) {
    for (final option in _returnOptions) {
      if (option.id == line.salesReturnLineId) return option;
    }
    return null;
  }

  int get _net => _lines.fold(0, (sum, line) => sum + line.netAmount);
  int get _tax => _lines.fold(0, (sum, line) => sum + line.taxAmount);
  int get _total => _net + _tax;

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
          'IVA: ${ChileanUtils.formatCurrency(_tax.toDouble())}\n'
          'Total: ${ChileanUtils.formatCurrency(_total.toDouble())}\n\n'
          'Se reducirá la cuenta por cobrar y se recalculará el saldo sin '
          'alterar pagos. La nota no moverá stock: toda devolución física '
          'debe estar registrada por separado. Estado DTE: interno.',
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
        issueDate: DateTime.now(),
        reasonCode: _reasonCode,
        reason: _reason.text,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      _showSuccess(result.replayed
          ? 'La solicitud ya existía; no se duplicó el asiento.'
          : '${result.number} registrada con asiento balanceado.');
      _reason.clear();
      _idempotencyKey = const Uuid().v4();
      setState(() => _loading = true);
      await _load();
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _void(SalesCreditNoteRecord record) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Anular ${record.number}'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Motivo obligatorio')),
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

  Future<void> _recordRefund(SalesCreditNoteRecord record) async {
    if (_refundMethods.isEmpty) {
      return _showError(
          'Configura al menos un medio de pago activo antes de registrar el reembolso.');
    }
    final input = await showCreditBalanceRefundDialog(
      context: context,
      title: 'Registrar reembolso de ${record.number}',
      counterpartyLabel: 'devuelto al cliente',
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

  Future<void> _voidRefund(SalesCustomerRefundRecord refund) async {
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

  void _showError(String text) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.red.shade700));
  void _showSuccess(String text) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.green.shade700));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nota de crédito de venta')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : Form(
                  key: _formKey,
                  child: Column(children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1100),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _header(),
                                    const SizedBox(height: 16),
                                    _fields(),
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
                                    ..._lines.asMap().entries.map((entry) =>
                                        _lineCard(entry.key, entry.value)),
                                    if (_history.isNotEmpty) ...[
                                      const SizedBox(height: 20),
                                      Text('Historial',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      const SizedBox(height: 8),
                                      ..._history.map(_historyCard),
                                    ],
                                  ]),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _footer(),
                  ]),
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
            Text(
                'Saldo actual: ${ChileanUtils.formatCurrency(widget.invoice.balance)}'),
            const Chip(
                avatar: Icon(Icons.verified_user_outlined, size: 18),
                label: Text('DTE interno, no emitido')),
          ]),
        ),
      );

  Widget _fields() => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Wrap(spacing: 16, runSpacing: 12, children: [
            SizedBox(
              width: 240,
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
              width: 420,
              child: TextFormField(
                controller: _reason,
                decoration:
                    const InputDecoration(labelText: 'Motivo detallado'),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'Explica la corrección.'
                    : null,
              ),
            ),
          ]),
        ),
      );

  Widget _lineCard(int index, SalesCreditNoteLineDraft draft) {
    final options = _returnOptions
        .where((option) => option.sourceLineKey == draft.balance.sourceLineKey)
        .toList(growable: false);
    return Card(
      key: ValueKey('credit-${draft.balance.lineIndex}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(draft.balance.productName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
              '${draft.balance.productSku ?? 'Sin SKU'} · Cantidad pendiente ${draft.balance.remainingQuantity} · Neto pendiente ${ChileanUtils.formatCurrency(draft.balance.remainingNet.toDouble())}'),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(
                width: 115,
                child: TextFormField(
                  initialValue: draft.quantity.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                  onChanged: (value) => _replace(
                      index, draft.withQuantity(int.tryParse(value) ?? 0)),
                )),
            SizedBox(
                width: 150,
                child: TextFormField(
                  initialValue: draft.netAmount.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Neto CLP'),
                  onChanged: (value) => _replace(index,
                      draft.copyWith(netAmount: int.tryParse(value) ?? 0)),
                )),
            SizedBox(
                width: 140,
                child: TextFormField(
                  initialValue: draft.taxAmount.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'IVA CLP'),
                  onChanged: (value) => _replace(index,
                      draft.copyWith(taxAmount: int.tryParse(value) ?? 0)),
                )),
            SizedBox(
                width: 225,
                child: DropdownButtonFormField<SalesCreditDisposition>(
                  initialValue: draft.disposition,
                  decoration: const InputDecoration(labelText: 'Respaldo'),
                  items: const [
                    DropdownMenuItem(
                        value: SalesCreditDisposition.financialOnly,
                        child: Text('Corrección financiera')),
                    DropdownMenuItem(
                        value: SalesCreditDisposition.salesReturn,
                        child: Text('Devolución física')),
                  ],
                  onChanged: (value) => _replace(
                      index,
                      draft.copyWith(
                        disposition: value,
                        clearSalesReturn:
                            value == SalesCreditDisposition.financialOnly,
                      )),
                )),
            if (draft.disposition == SalesCreditDisposition.salesReturn)
              SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<String>(
                    initialValue: draft.salesReturnLineId,
                    decoration: const InputDecoration(
                        labelText: 'Devolución vinculada'),
                    items: options
                        .map((option) => DropdownMenuItem(
                            value: option.id,
                            child: Text(
                                '${option.returnNumber} · ${option.remainingQuantity} u.')))
                        .toList(),
                    onChanged: (value) => _replace(
                        index, draft.copyWith(salesReturnLineId: value)),
                  )),
          ]),
        ]),
      ),
    );
  }

  Widget _historyCard(SalesCreditNoteRecord record) {
    final refunds = _refunds
        .where((refund) => refund.salesCreditNoteId == record.id)
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

  String _noteStatusLabel(SalesCreditNoteRecord record) {
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
                  child: const Text('Cerrar')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _submitting || _lines.isEmpty ? null : _submit,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.receipt_long_outlined),
                label: const Text('Registrar nota'),
              ),
            ]),
          ),
        ),
      );
}
