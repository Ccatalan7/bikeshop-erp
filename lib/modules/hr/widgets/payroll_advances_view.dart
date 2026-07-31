import 'package:flutter/material.dart';

import '../models/payroll_voucher.dart';
import 'payroll_format.dart';
import 'payroll_money_bar.dart';

/// Employee-first advances surface, sister of the weekly payroll queue.
///
/// The overview is a per-person summary; the individual ledger and the rules
/// appear only for the selected person. Weekly worksheets never show this
/// ledger — they only surface the balance applicable to their own week.
class PayrollAdvancesView extends StatefulWidget {
  const PayrollAdvancesView({
    super.key,
    required this.advances,
    required this.employees,
    required this.onRegister,
  });

  final List<EmployeeAdvance> advances;
  final List<Map<String, dynamic>> employees;
  final VoidCallback? onRegister;

  @override
  State<PayrollAdvancesView> createState() => _PayrollAdvancesViewState();
}

class _PersonAdvances {
  _PersonAdvances(this.employeeId, this.name);

  final String employeeId;
  final String name;
  final List<EmployeeAdvance> advances = [];

  double get delivered =>
      advances.fold<double>(0, (sum, advance) => sum + advance.amount);
  double get applied =>
      advances.fold<double>(0, (sum, advance) => sum + advance.amountApplied);
  double get available =>
      advances.fold<double>(0, (sum, advance) => sum + advance.availableAmount);
}

class _PayrollAdvancesViewState extends State<PayrollAdvancesView> {
  String? _selectedEmployeeId;

  String _employeeName(String employeeId) {
    for (final employee in widget.employees) {
      if (employee['id']?.toString() != employeeId) continue;
      final first = employee['first_name']?.toString().trim() ?? '';
      final last = employee['last_name']?.toString().trim() ?? '';
      final name = '$first $last'.trim();
      if (name.isNotEmpty) return name;
    }
    return 'Persona sin ficha';
  }

  List<_PersonAdvances> get _people {
    final byEmployee = <String, _PersonAdvances>{};
    for (final advance in widget.advances) {
      byEmployee
          .putIfAbsent(
            advance.employeeId,
            () => _PersonAdvances(
              advance.employeeId,
              _employeeName(advance.employeeId),
            ),
          )
          .advances
          .add(advance);
    }
    final people = byEmployee.values.toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    return people;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = _people;
    final selected = people
        .where((person) => person.employeeId == _selectedEmployeeId)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rule = Text(
                'El anticipo pertenece a la persona, no a una semana. Se '
                'se aplica después en una nómina compatible y nunca cambia '
                'horas ni totales.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              );
              final register = widget.onRegister == null || people.isEmpty
                  ? null
                  : PayrollPrimaryAction(
                      label: 'Registrar anticipo',
                      icon: Icons.add_rounded,
                      onPressed: widget.onRegister,
                    );
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    rule,
                    if (register != null) ...[
                      const SizedBox(height: 10),
                      register,
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: rule),
                  if (register != null) ...[
                    const SizedBox(width: 12),
                    register,
                  ],
                ],
              );
            },
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: people.isEmpty
              ? _buildEmptyState(theme)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 720;
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 320,
                            child: _buildPersonList(people, selected),
                          ),
                          Container(
                            width: 1,
                            color: theme.colorScheme.outlineVariant,
                          ),
                          Expanded(
                            child: selected == null
                                ? _buildNoSelection(theme)
                                : _buildLedger(selected, showBack: false),
                          ),
                        ],
                      );
                    }
                    if (selected != null) {
                      return _buildLedger(selected, showBack: true);
                    }
                    return _buildPersonList(people, selected);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.savings_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No hay anticipos abiertos.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Registra aquí el dinero entregado antes de cerrar una '
                'nómina. Quedará en el libro del trabajador hasta que decidas '
                'aplicarlo a una semana compatible.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (widget.onRegister != null) ...[
                const SizedBox(height: 18),
                PayrollPrimaryAction(
                  key: const Key('payroll-advances-empty-register'),
                  label: 'Registrar primer anticipo',
                  icon: Icons.add_rounded,
                  onPressed: widget.onRegister,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoSelection(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Text(
          'Elige una persona para ver su libro de anticipos.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  Widget _buildPersonList(
    List<_PersonAdvances> people,
    _PersonAdvances? selected,
  ) {
    final theme = Theme.of(context);
    return ListView.separated(
      itemCount: people.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
      itemBuilder: (context, index) {
        final person = people[index];
        final isSelected = person.employeeId == selected?.employeeId;
        return Semantics(
          button: true,
          selected: isSelected,
          label: '${person.name}. '
              'Disponible ${formatPayrollClp(person.available)}.',
          excludeSemantics: true,
          child: Material(
            color: isSelected
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.transparent,
            child: InkWell(
              onTap: () => setState(
                () => _selectedEmployeeId = person.employeeId,
              ),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: PayrollMoneyBar.minimumTouchTarget + 8,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            person.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${person.advances.length} '
                            '${person.advances.length == 1 ? 'anticipo abierto' : 'anticipos abiertos'}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          formatPayrollClp(person.available),
                          style: payrollMoneyTextStyle(
                            context,
                            emphasis: true,
                          ).copyWith(fontSize: 14.5),
                        ),
                        Text(
                          'disponible',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLedger(_PersonAdvances person, {required bool showBack}) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        if (showBack)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _selectedEmployeeId = null),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Volver a personas'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, PayrollMoneyBar.minimumTouchTarget),
              ),
            ),
          ),
        Text(
          person.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 22,
          runSpacing: 8,
          children: [
            _LedgerFigure(label: 'Entregado', amount: person.delivered),
            _LedgerFigure(label: 'Aplicado', amount: person.applied),
            _LedgerFigure(
              label: 'Disponible',
              amount: person.available,
              emphasis: true,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < person.advances.length; index++)
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: index == 0
                          ? BorderSide.none
                          : BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatPayrollDate(
                                person.advances[index].paidCivilDate,
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (person.advances[index].reference
                                    ?.trim()
                                    .isNotEmpty ==
                                true)
                              Text(
                                person.advances[index].reference!.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _LedgerFigure(
                        label: 'Entregado',
                        amount: person.advances[index].amount,
                      ),
                      const SizedBox(width: 18),
                      _LedgerFigure(
                        label: 'Disponible',
                        amount: person.advances[index].availableAmount,
                        emphasis: true,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Regla: un anticipo solo puede aplicarse a una semana cuyo cierre '
          'sea igual o posterior a la fecha de entrega. La aplicación se '
          'decide al registrar el pago o al conciliar la cartola.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _LedgerFigure extends StatelessWidget {
  const _LedgerFigure({
    required this.label,
    required this.amount,
    this.emphasis = false,
  });

  final String label;
  final double amount;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
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
              .copyWith(fontSize: 13.5),
        ),
      ],
    );
  }
}
