import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/utils/responsive_viewport.dart';
import '../models/payroll_voucher.dart';
import 'payroll_format.dart';
import 'payroll_money_bar.dart';
import 'payroll_payment_sheet.dart' show ClpAmountInputFormatter;

/// A request to register money handed to a worker outside a voucher payment.
@immutable
class PayrollAdvanceIntent {
  const PayrollAdvanceIntent({
    required this.employeeId,
    required this.employeeName,
    required this.amount,
    required this.paymentMethodId,
    required this.paymentAccountId,
    required this.paidAt,
    required this.operationKey,
    this.reference,
    this.notes,
  });

  final String employeeId;
  final String employeeName;
  final double amount;
  final String paymentMethodId;
  final String paymentAccountId;
  final DateTime paidAt;
  final String operationKey;
  final String? reference;
  final String? notes;
}

/// Opens advance entry either from a worker/week shortcut or from the global
/// payroll command, where choosing the worker is mandatory.
Future<PayrollAdvanceIntent?> showPayrollAdvanceEntry({
  required BuildContext context,
  required List<Map<String, dynamic>> paymentMethods,
  PayrollVoucher? voucher,
  PayrollVoucherLine? line,
  List<Map<String, dynamic>> employees = const [],
  String? initialEmployeeId,
}) {
  assert(
    (voucher == null && line == null) || (voucher != null && line != null),
  );
  final isCompact = ResponsiveViewport.widthOf(context) <
      ResponsiveViewport.phoneMaxExclusive;
  final content = PayrollAdvanceEntry(
    voucher: voucher,
    line: line,
    paymentMethods: paymentMethods,
    employees: employees,
    initialEmployeeId: initialEmployeeId,
  );

  if (isCompact) {
    return showModalBottomSheet<PayrollAdvanceIntent>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      showDragHandle: false,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: content,
      ),
    );
  }

  return showDialog<PayrollAdvanceIntent>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 580),
        child: content,
      ),
    ),
  );
}

class PayrollAdvanceEntry extends StatefulWidget {
  const PayrollAdvanceEntry({
    super.key,
    required this.paymentMethods,
    this.voucher,
    this.line,
    this.employees = const [],
    this.initialEmployeeId,
  });

  final PayrollVoucher? voucher;
  final PayrollVoucherLine? line;
  final List<Map<String, dynamic>> paymentMethods;
  final List<Map<String, dynamic>> employees;
  final String? initialEmployeeId;

  @override
  State<PayrollAdvanceEntry> createState() => _PayrollAdvanceEntryState();
}

class _PayrollAdvanceEntryState extends State<PayrollAdvanceEntry> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();

  String? _employeeId;
  String? _methodId;
  DateTime _paidAt = DateTime.now();
  String? _validationError;
  bool _isDirty = false;
  bool _allowPop = false;
  final String _operationKey = const Uuid().v4();

  double get _amount =>
      double.tryParse(_amountController.text.replaceAll('.', '').trim()) ?? 0;

  List<Map<String, dynamic>> get _eligiblePaymentMethods =>
      widget.paymentMethods
          .where(
            (method) =>
                method['is_active'] == true &&
                (method['id']?.toString().trim().isNotEmpty ?? false) &&
                (method['account_id']?.toString().trim().isNotEmpty ?? false),
          )
          .toList(growable: false);

  List<Map<String, dynamic>> get _activePaymentMethods {
    final methods = _eligiblePaymentMethods;
    methods.sort(
      (a, b) => _paymentMethodOptionLabel(a, methods)
          .toLowerCase()
          .compareTo(_paymentMethodOptionLabel(b, methods).toLowerCase()),
    );
    return methods;
  }

  String _paymentMethodName(Map<String, dynamic> method) {
    final name = method['name']?.toString().trim();
    return name == null || name.isEmpty ? 'Sin nombre' : name;
  }

  String _paymentMethodOptionLabel(
    Map<String, dynamic> method,
    List<Map<String, dynamic>> candidates,
  ) {
    final name = _paymentMethodName(method);
    final accountCode = method['account_code']?.toString().trim();
    final accountName = method['account_name']?.toString().trim();
    final accountParts = <String>[
      if (accountCode != null && accountCode.isNotEmpty) accountCode,
      if (accountName != null &&
          accountName.isNotEmpty &&
          accountName.toLowerCase() != accountCode?.toLowerCase())
        accountName,
    ];
    if (accountParts.isNotEmpty) {
      return '$name · ${accountParts.join(' · ')}';
    }

    final sameName = candidates
        .where(
          (candidate) =>
              _paymentMethodName(candidate).toLowerCase() == name.toLowerCase(),
        )
        .toList(growable: false);
    if (sameName.length <= 1) return name;

    sameName.sort(
      (a, b) => (a['account_id']?.toString() ?? '')
          .compareTo(b['account_id']?.toString() ?? ''),
    );
    final position = sameName.indexWhere(
      (candidate) => candidate['id']?.toString() == method['id']?.toString(),
    );
    return '$name · cuenta contable ${position < 0 ? 1 : position + 1}';
  }

  List<Map<String, dynamic>> get _selectableEmployees {
    final byId = <String, Map<String, dynamic>>{};
    for (final employee in widget.employees) {
      final id = employee['id']?.toString().trim();
      if (id == null || id.isEmpty) continue;
      final status = employee['status']?.toString().trim().toLowerCase();
      if (status != null && status.isNotEmpty && status != 'active') continue;
      if (employee['is_active'] == false) continue;
      byId.putIfAbsent(id, () => employee);
    }
    final employees = byId.values.toList(growable: false);
    employees.sort(
      (a, b) => _employeeOptionLabel(a)
          .toLowerCase()
          .compareTo(_employeeOptionLabel(b).toLowerCase()),
    );
    return employees;
  }

  Map<String, dynamic>? get _selectedMethod {
    for (final method in _activePaymentMethods) {
      if (method['id']?.toString() == _methodId) return method;
    }
    return null;
  }

  bool get _selectedMethodRequiresReference =>
      _selectedMethod?['requires_reference'] == true;

  Map<String, dynamic>? get _selectedEmployee {
    final employeeId = _employeeId;
    if (employeeId == null) return null;
    for (final employee in _selectableEmployees) {
      if (employee['id']?.toString() == employeeId) return employee;
    }
    return null;
  }

  String _employeeDisplayName(Map<String, dynamic> employee) {
    final displayName = employee['display_name']?.toString().trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final name = [
      employee['first_name']?.toString().trim() ?? '',
      employee['last_name']?.toString().trim() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
    return name.isEmpty ? 'Persona sin nombre' : name;
  }

  String _employeeOptionLabel(Map<String, dynamic> employee) {
    final rut = employee['rut']?.toString().trim();
    return [
      _employeeDisplayName(employee),
      if (rut != null && rut.isNotEmpty) rut,
    ].join(' · ');
  }

  String get _employeeName {
    final line = widget.line;
    if (line != null) return line.employeeName;
    final row = _selectedEmployee;
    if (row == null) return 'una persona';
    return _employeeDisplayName(row);
  }

  String? _preferredMethodIdFor(Map<String, dynamic>? employee) {
    final preferred =
        employee?['preferred_payment_method_id']?.toString().trim();
    if (preferred == null || preferred.isEmpty) return null;
    return _activePaymentMethods.any(
      (method) => method['id']?.toString() == preferred,
    )
        ? preferred
        : null;
  }

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    final requestedEmployeeId =
        line?.employeeId ?? widget.initialEmployeeId?.trim();
    _employeeId = line != null
        ? line.employeeId
        : _selectableEmployees.any(
            (employee) => employee['id']?.toString() == requestedEmployeeId,
          )
            ? requestedEmployeeId
            : null;
    final lineMethodId = line?.paymentMethodId?.trim();
    _methodId = _activePaymentMethods.any(
      (method) => method['id']?.toString() == lineMethodId,
    )
        ? lineMethodId
        : _preferredMethodIdFor(_selectedEmployee);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(_paidAt.year - 1),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _paidAt = picked;
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
        title: const Text('¿Descartar este anticipo?'),
        content: const Text(
          'El dinero todavía no se ha registrado en el libro de anticipos.',
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

  void _pop([PayrollAdvanceIntent? result]) {
    _allowPop = true;
    Navigator.of(context).pop(result);
  }

  void _selectEmployee(String? value) {
    setState(() {
      _employeeId = value;
      _methodId = _preferredMethodIdFor(_selectedEmployee);
      _validationError = null;
      _isDirty = true;
    });
  }

  void _submit() {
    final employeeId = widget.line?.employeeId ?? _employeeId;
    if (employeeId == null || employeeId.isEmpty) {
      setState(() => _validationError = 'Elige quién recibe el anticipo.');
      return;
    }
    if (_amount <= 0) {
      setState(() => _validationError = 'Ingresa un monto mayor que cero.');
      return;
    }
    final method = _selectedMethod;
    final methodId = method?['id']?.toString().trim();
    if (methodId == null || methodId.isEmpty) {
      setState(() {
        _validationError = _activePaymentMethods.isEmpty
            ? 'No hay métodos de pago activos con una cuenta contable '
                'disponible.'
            : 'Elige con qué método entregaste el anticipo.';
      });
      return;
    }
    final paymentAccountId = method?['account_id']?.toString().trim() ?? '';
    if (paymentAccountId.isEmpty) {
      setState(() {
        _validationError =
            'El método elegido no tiene una cuenta contable activa.';
      });
      return;
    }
    if (_selectedMethodRequiresReference &&
        _referenceController.text.trim().isEmpty) {
      setState(() {
        _validationError =
            'Este método exige una referencia antes de registrar el anticipo.';
      });
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final paidAt = DateTime(_paidAt.year, _paidAt.month, _paidAt.day);
    if (paidAt.isAfter(today)) {
      setState(
          () => _validationError = 'La fecha no puede estar en el futuro.');
      return;
    }
    final voucher = widget.voucher;
    _pop(
      PayrollAdvanceIntent(
        employeeId: employeeId,
        employeeName: _employeeName,
        amount: _amount,
        paymentMethodId: methodId,
        paymentAccountId: paymentAccountId,
        paidAt: _paidAt,
        operationKey: _operationKey,
        reference: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        notes: voucher == null
            ? 'Anticipo registrado desde el centro de nóminas.'
            : 'Anticipo registrado desde la semana '
                '${formatPayrollWeekRange(voucher.periodStart, voucher.periodEnd)}.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                      widget.line == null
                          ? 'Registrar anticipo'
                          : 'Anticipo para $_employeeName',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.voucher == null
                          ? _employeeId == null
                              ? 'Elige una persona y registra dinero entregado '
                                  'antes de liquidar una semana.'
                              : 'Registra dinero entregado a $_employeeName '
                                  'antes de liquidar una semana.'
                          : 'Semana '
                              '${formatPayrollWeekRange(widget.voucher!.periodStart, widget.voucher!.periodEnd)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'El anticipo queda en el registro de la persona y podrá '
                        'aplicarse a una nómina posterior. No cambia horas, '
                        'tarifas ni totales para hacerlos cuadrar.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (widget.line == null) ...[
                      const SizedBox(height: 18),
                      _buildEmployeeSelector(),
                    ],
                    const SizedBox(height: 18),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      autofocus: widget.line != null || _employeeId != null,
                      inputFormatters: const [ClpAmountInputFormatter()],
                      onChanged: (_) => setState(() {
                        _validationError = null;
                        _isDirty = true;
                      }),
                      decoration: const InputDecoration(
                        labelText: 'Monto entregado',
                        prefixText: '\$ ',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey<String>(
                        'payroll-advance-method-${_methodId ?? 'none'}',
                      ),
                      initialValue: _methodId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Método y cuenta de entrega',
                      ),
                      items: [
                        for (final method in _activePaymentMethods)
                          DropdownMenuItem<String>(
                            value: method['id']?.toString(),
                            child: Text(
                              _paymentMethodOptionLabel(
                                method,
                                _activePaymentMethods,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _activePaymentMethods.isEmpty
                          ? null
                          : (value) => setState(() {
                                _methodId = value;
                                _validationError = null;
                                _isDirty = true;
                              }),
                    ),
                    if (_activePaymentMethods.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'No hay métodos de pago activos con una cuenta '
                        'contable disponible. Configura uno antes de registrar '
                        'el anticipo.',
                        key: const Key(
                          'payroll-advance-no-valid-payment-method',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de entrega',
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text(formatPayrollDate(_paidAt))),
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 17,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
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
                    if (_validationError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _validationError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
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
                  label: 'Anticipo',
                  amount: _amount,
                  emphasis: true,
                  isPrimary: true,
                ),
              ],
              primaryAction: PayrollPrimaryAction(
                label: 'Registrar anticipo',
                icon: Icons.savings_outlined,
                onPressed: _activePaymentMethods.isEmpty ? null : _submit,
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

  Widget _buildEmployeeSelector() {
    final employees = _selectableEmployees;
    if (employees.length <= 7) {
      return DropdownButtonFormField<String>(
        key: const Key('payroll-advance-employee-select'),
        initialValue: _employeeId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Persona',
          helperText: employees.isEmpty
              ? 'No hay trabajadores activos disponibles.'
              : null,
        ),
        items: [
          for (final employee in employees)
            DropdownMenuItem<String>(
              value: employee['id']?.toString(),
              child: Text(
                _employeeOptionLabel(employee),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: employees.isEmpty ? null : _selectEmployee,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return DropdownMenu<String>(
          key: const Key('payroll-advance-employee-search'),
          width: constraints.maxWidth,
          menuHeight: 320,
          initialSelection: _employeeId,
          label: const Text('Persona'),
          hintText: 'Buscar por nombre o RUT',
          enableFilter: true,
          enableSearch: true,
          requestFocusOnTap: true,
          dropdownMenuEntries: [
            for (final employee in employees)
              DropdownMenuEntry<String>(
                value: employee['id']!.toString(),
                label: _employeeOptionLabel(employee),
              ),
          ],
          onSelected: _selectEmployee,
        );
      },
    );
  }
}
