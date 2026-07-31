import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/payroll_voucher.dart';
import 'payroll_format.dart';
import 'payroll_money_bar.dart';

/// What the operator decided for one worker's balance.
///
/// The intent carries a `pay_payroll_voucher` splits payload scoped to a single
/// line. Lines that are absent from the map are skipped by the command, so a
/// manual payment never settles a colleague by accident, and no
/// `PayrollVoucherLine` is pre-updated before the money command succeeds.
@immutable
class PayrollManualPaymentIntent {
  const PayrollManualPaymentIntent({
    required this.voucherId,
    required this.lineId,
    required this.splits,
    required this.totalAmount,
    required this.operationKey,
    required this.expectedReconciliationVersion,
  });

  final String voucherId;
  final String lineId;
  final Map<String, dynamic> splits;
  final double totalAmount;
  final String operationKey;
  final int expectedReconciliationVersion;
}

/// Groups digits with Chilean thousands separators while the operator types.
class ClpAmountInputFormatter extends TextInputFormatter {
  const ClpAmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Parses an amount field formatted by [ClpAmountInputFormatter].
double parsePayrollAmount(String text) =>
    double.tryParse(text.replaceAll('.', '').trim()) ?? 0;

/// Opens the payment composer for one worker.
///
/// Compact widths get a bottom sheet reachable with the thumb; wide widths get
/// a deliberately narrow surface: paying one person is not a spreadsheet task.
Future<PayrollManualPaymentIntent?> showPayrollPaymentSheet({
  required BuildContext context,
  required PayrollVoucher voucher,
  required PayrollVoucherLine line,
  required List<Map<String, dynamic>> paymentMethods,
  required List<EmployeeAdvance> openAdvances,
}) {
  final isCompact = MediaQuery.sizeOf(context).width < 600;
  final content = PayrollPaymentSheet(
    voucher: voucher,
    line: line,
    paymentMethods: paymentMethods,
    openAdvances: openAdvances,
  );

  if (isCompact) {
    return showModalBottomSheet<PayrollManualPaymentIntent>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: content,
      ),
    );
  }

  return showDialog<PayrollManualPaymentIntent>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: content,
      ),
    ),
  );
}

/// Payment composer: advances first, then the compact equation, then the
/// payment record block. The persistent bar always shows the new money about
/// to be registered; finishing never auto-advances anywhere.
class PayrollPaymentSheet extends StatefulWidget {
  const PayrollPaymentSheet({
    super.key,
    required this.voucher,
    required this.line,
    required this.paymentMethods,
    required this.openAdvances,
  });

  final PayrollVoucher voucher;
  final PayrollVoucherLine line;
  final List<Map<String, dynamic>> paymentMethods;
  final List<EmployeeAdvance> openAdvances;

  @override
  State<PayrollPaymentSheet> createState() => _PayrollPaymentSheetState();
}

class _PayrollPaymentSheetState extends State<PayrollPaymentSheet> {
  late final TextEditingController _amountController;
  final TextEditingController _referenceController = TextEditingController();

  String? _methodId;
  DateTime _paymentDate = DateTime.now();

  /// Advance ids selected for allocation, in selection order.
  final Set<String> _selectedAdvanceIds = <String>{};
  String? _validationError;
  bool _isDirty = false;
  bool _allowPop = false;
  final String _operationKey = const Uuid().v4();

  /// Open advances belonging to this worker that may legally cover this week:
  /// handed over on or before the week's close, with money still available.
  List<EmployeeAdvance> get _compatibleAdvances {
    final periodEnd = DateTime(
      widget.voucher.periodEnd.year,
      widget.voucher.periodEnd.month,
      widget.voucher.periodEnd.day,
      23,
      59,
      59,
    );
    return widget.openAdvances
        .where((advance) =>
            advance.employeeId == widget.line.employeeId &&
            advance.availableAmount > 0.01 &&
            !advance.paidCivilDate.isAfter(periodEnd))
        .toList(growable: false)
      ..sort((a, b) => a.paidCivilDate.compareTo(b.paidCivilDate));
  }

  double get _balance => widget.line.balance;

  /// Amount covered by the selected advances, chronological, capped by the
  /// remaining balance.
  List<(EmployeeAdvance, double)> get _advanceAllocations {
    final allocations = <(EmployeeAdvance, double)>[];
    var remaining = _balance;
    for (final advance in _compatibleAdvances) {
      if (!_selectedAdvanceIds.contains(advance.id)) continue;
      if (remaining <= 0.01) break;
      final applied = advance.availableAmount > remaining
          ? remaining
          : advance.availableAmount;
      allocations.add((advance, applied));
      remaining -= applied;
    }
    return allocations;
  }

  double get _advanceAmount => _advanceAllocations.fold<double>(
        0,
        (sum, allocation) => sum + allocation.$2,
      );

  double get _paymentAmount => parsePayrollAmount(_amountController.text);

  double get _total => _paymentAmount + _advanceAmount;

  List<Map<String, dynamic>> get _activePaymentMethods => widget.paymentMethods
      .where(
        (method) =>
            method['is_active'] != false &&
            (method['id']?.toString().trim().isNotEmpty ?? false),
      )
      .toList(growable: false);

  Map<String, dynamic>? get _selectedMethod {
    final methodId = _methodId;
    if (methodId == null) return null;
    for (final method in _activePaymentMethods) {
      if (method['id']?.toString() == methodId) return method;
    }
    return null;
  }

  bool get _selectedMethodRequiresReference =>
      _selectedMethod?['requires_reference'] == true;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _balance <= 0 ? '0' : _formatDigits(_balance.round()),
    );
    final preferredMethodId = widget.line.paymentMethodId?.trim();
    _methodId = _activePaymentMethods.any(
      (method) => method['id']?.toString() == preferredMethodId,
    )
        ? preferredMethodId
        : null;
  }

  String _formatDigits(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  void _toggleAdvance(EmployeeAdvance advance, bool selected) {
    setState(() {
      _isDirty = true;
      _validationError = null;
      if (selected) {
        _selectedAdvanceIds.add(advance.id);
      } else {
        _selectedAdvanceIds.remove(advance.id);
      }
      final remaining = (_balance - _advanceAmount).clamp(0, _balance);
      _amountController.text = _formatDigits(remaining.round());
    });
  }

  Future<void> _pickDate() async {
    final firstDate = DateTime(
      widget.voucher.periodEnd.year,
      widget.voucher.periodEnd.month,
      widget.voucher.periodEnd.day,
    );
    final lastDate = DateTime.now();
    if (firstDate.isAfter(lastDate)) {
      setState(() {
        _validationError =
            'La semana todavía no termina. Usa un anticipo si entregaste '
            'dinero antes del cierre.';
      });
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate.isBefore(firstDate) ? firstDate : _paymentDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _paymentDate = picked;
        _isDirty = true;
      });
    }
  }

  Future<void> _requestClose() async {
    if (!_isDirty) {
      _pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Descartar este pago?'),
        content: const Text(
          'El monto, la fecha y el método todavía no se han registrado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) _pop();
  }

  void _pop([PayrollManualPaymentIntent? result]) {
    _allowPop = true;
    Navigator.of(context).pop(result);
  }

  void _submit() {
    final lineId = widget.line.id;
    if (lineId == null) {
      setState(() => _validationError = 'Esta línea todavía no está guardada.');
      return;
    }
    if (_total <= 0) {
      setState(() => _validationError = 'Ingresa un monto mayor que cero.');
      return;
    }
    if (_total > _balance + 0.01) {
      setState(() {
        _validationError =
            'El total supera el saldo de ${formatPayrollClp(_balance)}. Si el '
            'banco transfirió de más (redondeo), registra aquí solo el saldo; '
            'la diferencia se resuelve en Conciliar cartola con su propia '
            'disposición.';
      });
      return;
    }
    final periodEnd = DateTime(
      widget.voucher.periodEnd.year,
      widget.voucher.periodEnd.month,
      widget.voucher.periodEnd.day,
    );
    final today = DateTime.now();
    final todayCivil = DateTime(today.year, today.month, today.day);
    final paymentCivil =
        DateTime(_paymentDate.year, _paymentDate.month, _paymentDate.day);
    if (_paymentAmount > 0 &&
        (paymentCivil.isBefore(periodEnd) ||
            paymentCivil.isAfter(todayCivil))) {
      setState(() {
        _validationError =
            'Un pago de nómina debe fecharse entre el cierre de la semana y '
            'hoy. Para una entrega anterior usa Anticipo.';
      });
      return;
    }
    if (_paymentAmount > 0 && (_methodId ?? '').isEmpty) {
      setState(() {
        _validationError = 'Elige el método de pago. No se asume ninguno.';
      });
      return;
    }
    final paymentAccountId =
        _selectedMethod?['account_id']?.toString().trim() ?? '';
    if (_paymentAmount > 0 && paymentAccountId.isEmpty) {
      setState(() {
        _validationError =
            'El método elegido no tiene una cuenta contable activa.';
      });
      return;
    }
    if (_paymentAmount > 0 &&
        _selectedMethodRequiresReference &&
        _referenceController.text.trim().isEmpty) {
      setState(() {
        _validationError =
            'Este método exige una referencia antes de registrar el pago.';
      });
      return;
    }

    final splits = <Map<String, dynamic>>[
      for (final (advance, applied) in _advanceAllocations)
        {
          'kind': 'advance',
          'advance_id': advance.id,
          'amount': applied,
        },
      if (_paymentAmount > 0)
        {
          'kind': 'payment',
          'payment_method_id': _methodId,
          'payment_account_id': paymentAccountId,
          'amount': _paymentAmount,
          // The picker represents a tenant civil date, not a device-local
          // instant. Noon UTC preserves that calendar date in Chile and the
          // SQL boundary performs the authoritative tenant-timezone check.
          'payment_date': DateTime.utc(
            _paymentDate.year,
            _paymentDate.month,
            _paymentDate.day,
            12,
          ).toIso8601String(),
          'reference': _referenceController.text.trim().isEmpty
              ? null
              : _referenceController.text.trim(),
        },
    ];

    _pop(
      PayrollManualPaymentIntent(
        voucherId: widget.voucher.id ?? '',
        lineId: lineId,
        splits: <String, dynamic>{lineId: splits},
        totalAmount: _total,
        operationKey: _operationKey,
        expectedReconciliationVersion: widget.voucher.reconciliationVersion,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final advances = _compatibleAdvances;
    final remaining = _balance - _total;
    final newMoney = _paymentAmount;

    return PopScope(
      canPop: _allowPop || !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _requestClose();
      },
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pagar a ${widget.line.employeeName}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Saldo pendiente ${formatPayrollClp(_balance)} · '
                      '${formatPayrollWeekRange(widget.voucher.periodStart, widget.voucher.periodEnd)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (advances.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const _SectionLabel(label: '1 · Anticipos de la persona'),
                      const SizedBox(height: 4),
                      Text(
                        'Impútalos antes de registrar dinero nuevo para no '
                        'entregar dos veces el mismo dinero.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final advance in advances)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _selectedAdvanceIds.contains(advance.id),
                          onChanged: (selected) =>
                              _toggleAdvance(advance, selected ?? false),
                          title: Text(
                            'Anticipo del '
                            '${formatPayrollDate(advance.paidCivilDate)}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            'Disponible '
                            '${formatPayrollClp(advance.availableAmount)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 14),
                    _EquationBand(
                      balance: _balance,
                      advances: _advanceAmount,
                      newMoney: newMoney,
                    ),
                    const SizedBox(height: 16),
                    _SectionLabel(
                      label: advances.isEmpty
                          ? 'Registro del pago'
                          : '2 · Registro del pago',
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.fromLTRB(13, 6, 13, 13),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _amountController,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [ClpAmountInputFormatter()],
                            onChanged: (_) => setState(() {
                              _validationError = null;
                              _isDirty = true;
                            }),
                            decoration: const InputDecoration(
                              labelText: 'Dinero nuevo',
                              prefixText: r'$ ',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _methodId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Método de pago',
                            ),
                            items: [
                              for (final method in _activePaymentMethods)
                                DropdownMenuItem<String>(
                                  value: method['id']?.toString(),
                                  child: Text(
                                    method['name']?.toString() ?? 'Sin nombre',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) => setState(() {
                              _methodId = value;
                              _validationError = null;
                              _isDirty = true;
                            }),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _pickDate,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InputDecorator(
                                    decoration: const InputDecoration(
                                      labelText: 'Fecha del pago',
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            formatPayrollDate(_paymentDate),
                                          ),
                                        ),
                                        Icon(
                                          Icons.calendar_today_rounded,
                                          size: 17,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _referenceController,
                            onChanged: (_) => setState(() {
                              _validationError = null;
                              _isDirty = true;
                            }),
                            decoration: InputDecoration(
                              labelText: _selectedMethodRequiresReference
                                  ? 'Referencia (obligatoria)'
                                  : 'Referencia (opcional)',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_validationError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _validationError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (remaining > 0.01) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Quedará un saldo de ${formatPayrollClp(remaining)} en '
                        'esta persona. Podrás resolverlo después; nada avanza '
                        'solo.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            PayrollMoneyBar(
              figures: [
                PayrollMoneyFigure(
                  label: 'Dinero nuevo',
                  amount: newMoney,
                  emphasis: true,
                  isPrimary: true,
                ),
                PayrollMoneyFigure(label: 'Anticipos', amount: _advanceAmount),
                PayrollMoneyFigure(label: 'Saldo actual', amount: _balance),
              ],
              primaryAction: PayrollPrimaryAction(
                label: 'Registrar',
                icon: Icons.check_rounded,
                onPressed: _submit,
              ),
              secondaryAction: PayrollSecondaryAction(
                label: 'Cancelar',
                icon: Icons.close_rounded,
                onPressed: _requestClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The compact settlement equation: saldo − anticipos = dinero nuevo.
class _EquationBand extends StatelessWidget {
  const _EquationBand({
    required this.balance,
    required this.advances,
    required this.newMoney,
  });

  final double balance;
  final double advances;
  final double newMoney;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget term(String label, double amount, {bool emphasis = false}) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            formatPayrollClp(amount),
            style: payrollMoneyTextStyle(context, emphasis: emphasis)
                .copyWith(fontSize: emphasis ? 16 : 14),
          ),
        ],
      );
    }

    Widget operator(String symbol) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          symbol,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Semantics(
      label: 'Saldo ${formatPayrollClp(balance)} menos anticipos '
          '${formatPayrollClp(advances)} igual dinero nuevo '
          '${formatPayrollClp(newMoney)}',
      container: true,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            term('Saldo', balance),
            operator('−'),
            term('Anticipos', advances),
            operator('='),
            term('Dinero nuevo', newMoney, emphasis: true),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
