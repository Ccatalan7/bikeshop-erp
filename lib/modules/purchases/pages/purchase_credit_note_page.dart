import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/credit_balance_refund_dialog.dart';
import '../models/purchase_credit_note.dart';
import '../models/purchase_invoice.dart';
import '../services/purchase_credit_note_service.dart';

class PurchaseCreditNotePage extends StatefulWidget {
  const PurchaseCreditNotePage({
    super.key,
    required this.invoice,
    this.service,
    this.initialReceiptResolutionCaseId,
    this.initialSourceLineIndex,
    this.initialResolutionQuantity,
    this.initialResolutionLabel,
    this.initialReceiptId,
    this.initialReceiptNumber,
    this.focusCreditNoteId,
    this.focusRefundId,
    this.embedded = false,
    this.onClose,
  });

  final PurchaseInvoice invoice;
  final PurchaseCreditNoteService? service;
  final String? initialReceiptResolutionCaseId;
  final int? initialSourceLineIndex;
  final int? initialResolutionQuantity;
  final String? initialResolutionLabel;
  final String? initialReceiptId;
  final String? initialReceiptNumber;
  final String? focusCreditNoteId;
  final String? focusRefundId;
  final bool embedded;
  final VoidCallback? onClose;

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
  List<PurchaseCreditNoteLineRecord> _focusedLines = const [];
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
    if (widget.initialReceiptResolutionCaseId != null) {
      _reasonCode = 'invoice_correction';
      _reason.text =
          'Resolución de diferencia de recepción ${widget.initialResolutionLabel ?? ''}'
              .trim();
    }
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
        widget.focusCreditNoteId == null
            ? Future<List<PurchaseCreditNoteLineRecord>>.value(const [])
            : _service.getLines(widget.focusCreditNoteId!),
      ]);
      if (!mounted) return;
      final balances = results[0] as List<PurchaseCreditNoteLineBalance>;
      setState(() {
        _lines = balances
            .where(
          (line) =>
              line.remainingNet + line.remainingTax > 0 &&
              (widget.initialReceiptResolutionCaseId == null ||
                  line.lineIndex == widget.initialSourceLineIndex),
        )
            .map((line) {
          var draft = PurchaseCreditNoteLineDraft(balance: line);
          if (widget.initialReceiptResolutionCaseId != null &&
              line.lineIndex == widget.initialSourceLineIndex) {
            final requested = widget.initialResolutionQuantity ?? 0;
            final maximum = requested.clamp(0, line.remainingQuantity).toInt();
            draft = draft.withQuantity(maximum).copyWith(
                  receiptResolutionCaseId:
                      widget.initialReceiptResolutionCaseId,
                  receiptResolutionMaximum: maximum,
                );
          }
          return draft;
        }).toList(growable: false);
        _returnOptions = results[1] as List<PurchaseCreditReturnOption>;
        final history = List<PurchaseCreditNoteRecord>.from(
          results[2] as List<PurchaseCreditNoteRecord>,
        );
        final focusedId = widget.focusCreditNoteId;
        if (focusedId != null) {
          history.sort((a, b) {
            if (a.id == focusedId) return -1;
            if (b.id == focusedId) return 1;
            return b.issueDate.compareTo(a.issueDate);
          });
        }
        _history = history;
        _refunds = results[3] as List<PurchaseSupplierRefundRecord>;
        _refundMethods = results[4] as List<PurchaseRefundPaymentMethod>;
        _refundEnabled = results[5] as bool;
        _focusedLines = results[6] as List<PurchaseCreditNoteLineRecord>;
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
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text('Anular ${record.number}'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Se creará un asiento inverso y se restaurarán cuentas por '
                'pagar, inventario contable e IVA. No se modificará stock '
                'físico.',
              ),
              if (widget.focusCreditNoteId == record.id &&
                  widget.initialReceiptId?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                const Text(
                  'Esta nota resuelve una diferencia de recepción. Al '
                  'anularla, esa cantidad volverá a quedar abierta y podrá '
                  'recibirse o resolverse mediante otro documento.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Los reembolsos vinculados deben anularse primero. Una nota '
                'tributaria ya emitida requiere su documento oficial de '
                'reversa y no puede anularse aquí.',
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
    final reason = await _askVoidReason(
      'Anular reembolso ${refund.number}',
      consequence:
          'Se revertirá el asiento y se restaurará el saldo financiero. '
          'Esta acción en el ERP no revierte ni recupera una transferencia '
          'real ya ejecutada en el banco; esa operación debe gestionarse por '
          'separado.',
    );
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

  Future<String?> _askVoidReason(
    String title, {
    String? consequence,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: consequence == null
            ? null
            : const Icon(Icons.warning_amber_rounded),
        title: Text(title),
        content: SizedBox(
          width: consequence == null ? null : 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (consequence != null) ...[
                Text(consequence),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                decoration:
                    const InputDecoration(labelText: 'Motivo obligatorio'),
              ),
            ],
          ),
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
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(_error!, textAlign: TextAlign.center))
            : widget.focusCreditNoteId != null
                ? _buildFocusedDocument()
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
                                      if (widget
                                              .initialReceiptResolutionCaseId !=
                                          null) ...[
                                        const SizedBox(height: 12),
                                        _buildReceiptResolutionNotice(),
                                      ],
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
                                                          option
                                                              .sourceLineKey ==
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
                  );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Nota de crédito de compra')),
      body: body,
    );
  }

  Widget _buildFocusedDocument() {
    final record = _history
        .where((item) => item.id == widget.focusCreditNoteId)
        .firstOrNull;
    if (record == null) {
      return const Center(
        child: Text('No se encontró la nota de crédito vinculada.'),
      );
    }
    final refunds = _refunds
        .where((refund) => refund.purchaseCreditNoteId == record.id)
        .toList(growable: false);
    if (widget.focusRefundId != null) {
      refunds.sort((a, b) {
        if (a.id == widget.focusRefundId) return -1;
        if (b.id == widget.focusRefundId) return 1;
        return b.refundedAt.compareTo(a.refundedAt);
      });
    }
    final statusColor = record.status == 'posted'
        ? const Color(0xFF2F6F62)
        : const Color(0xFF874B4E);

    return ColoredBox(
      color: const Color(0xFFF6F8FA),
      child: Column(
        children: [
          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFD8DEE3)),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onClose ??
                      () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                  tooltip: 'Volver a la recepción',
                  icon: const Icon(Icons.arrow_back, size: 20),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nota de crédito ${record.number}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF20262C),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Factura ${widget.invoice.invoiceNumber} · '
                        '${widget.invoice.supplierName ?? 'Proveedor'}',
                        style: const TextStyle(
                          color: Color(0xFF68747D),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.42),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    record.status == 'posted' ? 'VIGENTE' : 'ANULADA',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Container(
                    color: Colors.white,
                    foregroundDecoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFD8DEE3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'NOTA DE CRÉDITO DE COMPRA',
                                      style: TextStyle(
                                        color: Color(0xFF20262C),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Documento financiero vinculado',
                                      style: TextStyle(
                                        color: Color(0xFF68747D),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    ChileanUtils.formatDate(
                                      record.issueDate.toLocal(),
                                    ),
                                    style: const TextStyle(
                                      color: Color(0xFF37434B),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (record.supplierNumber?.isNotEmpty == true)
                                    Text(
                                      'Proveedor: ${record.supplierNumber}',
                                      style: const TextStyle(
                                        color: Color(0xFF68747D),
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (widget.initialReceiptId?.isNotEmpty == true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 26,
                              vertical: 11,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEAF1F4),
                              border: Border.symmetric(
                                horizontal: BorderSide(
                                  color: Color(0xFFB8CBD3),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.link,
                                  size: 18,
                                  color: Color(0xFF235466),
                                ),
                                const SizedBox(width: 9),
                                const Expanded(
                                  child: Text(
                                    'Esta nota resuelve una diferencia exacta '
                                    'de recepción y no mueve stock físico.',
                                    style: TextStyle(
                                      color: Color(0xFF304B56),
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: widget.onClose ??
                                      () => context.push(
                                            '/purchases/receipts/'
                                            '${Uri.encodeComponent(widget.initialReceiptId!)}',
                                          ),
                                  child: Text(
                                    'Abrir '
                                    '${widget.initialReceiptNumber ?? 'recepción'}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(26, 18, 26, 14),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Motivo: ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(text: record.reason),
                              ],
                            ),
                            style: const TextStyle(
                              color: Color(0xFF37434B),
                              fontSize: 13,
                            ),
                          ),
                        ),
                        _buildFocusedLineTable(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(26, 18, 26, 18),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'EFECTO',
                                  style: TextStyle(
                                    color: Color(0xFF68747D),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.35,
                                  ),
                                ),
                              ),
                              Text(
                                'Total acreditado  '
                                '${ChileanUtils.formatCurrency(record.totalAmount.toDouble())}',
                                style: const TextStyle(
                                  color: Color(0xFF20262C),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (refunds.isNotEmpty) _buildFocusedRefunds(refunds),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 14,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF7F9FA),
                            border: Border(
                              top: BorderSide(color: Color(0xFFD8DEE3)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'DTE ${record.officialStatus} · '
                                  'Reembolsado '
                                  '${ChileanUtils.formatCurrency(record.refundedAmount.toDouble())}',
                                  style: const TextStyle(
                                    color: Color(0xFF52606A),
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              if (record.canRefund && _refundEnabled)
                                FilledButton.tonalIcon(
                                  onPressed: _submitting
                                      ? null
                                      : () => _recordRefund(record),
                                  icon: const Icon(
                                    Icons.payments_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Registrar reembolso'),
                                ),
                              if (record.canVoid) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed:
                                      _submitting ? null : () => _void(record),
                                  icon: const Icon(Icons.undo, size: 18),
                                  label: const Text('Anular nota'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusedLineTable() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth < 760 ? 760 : constraints.maxWidth,
          child: Column(
            children: [
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 26),
                color: const Color(0xFFF1F4F6),
                child: const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'PRODUCTO',
                        style: TextStyle(
                          color: Color(0xFF235466),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(width: 80, child: Text('CANT.')),
                    SizedBox(width: 120, child: Text('NETO')),
                    SizedBox(width: 110, child: Text('IVA')),
                    SizedBox(width: 120, child: Text('TOTAL')),
                  ],
                ),
              ),
              for (final line in _focusedLines)
                Container(
                  constraints: const BoxConstraints(minHeight: 54),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE3E8EC)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.productName,
                              style: const TextStyle(
                                color: Color(0xFF20262C),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (line.productSku?.isNotEmpty == true)
                              Text(
                                'SKU ${line.productSku}',
                                style: const TextStyle(
                                  color: Color(0xFF68747D),
                                  fontSize: 11.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text('${line.quantity}'),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          ChileanUtils.formatCurrency(
                            line.netAmount.toDouble(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          ChileanUtils.formatCurrency(
                            line.taxAmount.toDouble(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          ChileanUtils.formatCurrency(
                            line.totalAmount.toDouble(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFocusedRefunds(List<PurchaseSupplierRefundRecord> refunds) {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 14, 26, 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFD8DEE3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'REEMBOLSOS VINCULADOS',
            style: TextStyle(
              color: Color(0xFF52606A),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.35,
            ),
          ),
          for (final refund in refunds)
            Container(
              margin: const EdgeInsets.only(top: 9),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: refund.id == widget.focusRefundId
                    ? const Color(0xFFEAF1F4)
                    : null,
                border: refund.id == widget.focusRefundId
                    ? Border.all(color: const Color(0xFF8FAEB9))
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${refund.number} · ${refund.paymentMethodName} · '
                      '${ChileanUtils.formatCurrency(refund.amount.toDouble())}',
                      style: const TextStyle(
                        color: Color(0xFF37434B),
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  Text(refund.status == 'posted' ? 'Vigente' : 'Anulado'),
                  if (refund.canVoid) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _submitting ? null : () => _voidRefund(refund),
                      child: const Text('Anular'),
                    ),
                  ],
                ],
              ),
            ),
        ],
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

  Widget _buildReceiptResolutionNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFEAF1F4),
        border: Border.fromBorderSide(
          BorderSide(color: Color(0xFFB8CBD3)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.link, size: 19, color: Color(0xFF235466)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Esta nota quedará vinculada a la diferencia exacta de la '
              'recepción. Reducirá cuentas por pagar, inventario contable e '
              'IVA según la línea; no moverá stock físico.',
              style: TextStyle(
                color: Color(0xFF304B56),
                fontSize: 13,
              ),
            ),
          ),
          if (widget.initialReceiptId?.isNotEmpty == true)
            TextButton(
              onPressed: () => context.push(
                '/purchases/receipts/'
                '${Uri.encodeComponent(widget.initialReceiptId!)}',
              ),
              child: Text(
                'Abrir ${widget.initialReceiptNumber ?? 'recepción'}',
              ),
            ),
        ],
      ),
    );
  }

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
    final focused = widget.focusCreditNoteId == record.id;
    return Card(
      color: focused ? const Color(0xFFEAF1F4) : null,
      shape: focused
          ? const RoundedRectangleBorder(
              side: BorderSide(color: Color(0xFF235466), width: 1.5),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            )
          : null,
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
            _number(
              line.receiptResolutionMaximum == null
                  ? 'Cantidad'
                  : 'Cantidad (máx. ${line.receiptResolutionMaximum})',
              line.quantity,
              (value) => onChanged(line.withQuantity(value)),
            ),
            _number(
              'Neto crédito',
              line.netAmount,
              line.receiptResolutionCaseId == null
                  ? (value) => onChanged(line.copyWith(netAmount: value))
                  : null,
            ),
            _number(
              'IVA crédito',
              line.taxAmount,
              line.receiptResolutionCaseId == null
                  ? (value) => onChanged(line.copyWith(taxAmount: value))
                  : null,
            ),
            if (line.receiptResolutionCaseId != null)
              const SizedBox(
                width: 210,
                child: InputDecorator(
                  decoration:
                      InputDecoration(labelText: 'Origen de la corrección'),
                  child: Text('Diferencia de recepción'),
                ),
              )
            else
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<PurchaseCreditDisposition>(
                  initialValue: line.disposition,
                  decoration:
                      const InputDecoration(labelText: 'Respaldo físico'),
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

  Widget _number(String label, int value, ValueChanged<int>? changed) =>
      SizedBox(
        width: 145,
        child: TextFormField(
          key: ValueKey('$label-$value'),
          initialValue: value.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
          enabled: changed != null,
          onChanged:
              changed == null ? null : (raw) => changed(int.tryParse(raw) ?? 0),
        ),
      );
}
