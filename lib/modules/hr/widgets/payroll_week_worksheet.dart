import 'package:flutter/material.dart';

import '../models/payroll_voucher.dart';
import 'payroll_format.dart';
import 'payroll_money_bar.dart';

/// Width at which the decision table collapses into stacked person rows.
const double kPayrollTableWidth = 720;

/// The selected week as a per-person decision table.
///
/// Columns: Persona · Método · Ganado · Anticipos · Dinero nuevo · acción.
/// Hours, rate and recorded payments live on the second line and inside the
/// labelled per-person disclosure. The worksheet is strictly read-only about
/// money: hours, rate and totals come from attendance and are corrected
/// there, never here.
class PayrollWeekWorksheet extends StatefulWidget {
  const PayrollWeekWorksheet({
    super.key,
    required this.voucher,
    required this.onPayLine,
    required this.onRegisterAdvance,
    this.onEdit,
    this.onDelete,
    this.onOpenAttendances,
    this.commandsEnabled = true,
    this.busyLineId,
    this.scrollController,
    this.leading,
    this.banner,
    this.paymentMethodNamesById = const <String, String>{},
    this.advanceAvailableByEmployee = const <String, double>{},
  });

  final PayrollVoucher voucher;
  final ValueChanged<PayrollVoucherLine> onPayLine;
  final ValueChanged<PayrollVoucherLine> onRegisterAdvance;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Hour corrections belong to attendance; this returns the operator there.
  final VoidCallback? onOpenAttendances;
  final bool commandsEnabled;
  final String? busyLineId;
  final ScrollController? scrollController;

  /// Compact-only back affordance injected by the host.
  final Widget? leading;

  /// Optional host banner (e.g. "week settled" with explicit next steps).
  final Widget? banner;

  /// Canonical payment-method names, keyed by method id.
  final Map<String, String> paymentMethodNamesById;

  /// Open advance money still available per employee, restricted by the host
  /// to advances handed over on or before this week's close.
  final Map<String, double> advanceAvailableByEmployee;

  @override
  State<PayrollWeekWorksheet> createState() => _PayrollWeekWorksheetState();
}

class _PayrollWeekWorksheetState extends State<PayrollWeekWorksheet> {
  final Set<String> _expandedLineIds = <String>{};

  List<PayrollVoucherLine> get _includedLines => widget.voucher.lines
      .where((line) => line.isIncluded)
      .toList(growable: false);

  bool _isExpanded(PayrollVoucherLine line) =>
      line.id != null && _expandedLineIds.contains(line.id);

  void _toggleExpanded(PayrollVoucherLine line) {
    final id = line.id;
    if (id == null) return;
    setState(() {
      if (!_expandedLineIds.remove(id)) _expandedLineIds.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voucher = widget.voucher;
    final stage = payrollStageFor(voucher.status);
    final lines = _includedLines;
    final missingMethod = lines
        .where((line) => (line.paymentMethodId ?? '').trim().isEmpty)
        .toList(growable: false);
    final canPayLines = widget.commandsEnabled &&
        (voucher.status == PayrollVoucherStatus.confirmed ||
            voucher.status == PayrollVoucherStatus.partial);
    final isDraft = voucher.status == PayrollVoucherStatus.draft;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        if (widget.leading != null) ...[
          Align(alignment: Alignment.centerLeft, child: widget.leading),
          const SizedBox(height: 8),
        ],
        if (widget.banner != null) ...[
          widget.banner!,
          const SizedBox(height: 12),
        ],
        _CommitmentBand(voucher: voucher),
        const SizedBox(height: 12),
        _StageBand(
          stage: stage,
          voucher: voucher,
          onEdit: widget.onEdit,
          onDelete: widget.onDelete,
        ),
        if (missingMethod.isNotEmpty) ...[
          const SizedBox(height: 12),
          _MethodExceptionBand(lines: missingMethod),
        ],
        const SizedBox(height: 16),
        Text(
          'Personas de la semana',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Las horas y el total vienen de asistencia. Aquí solo decides cómo '
          'se resuelve cada saldo.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        if (lines.isEmpty)
          const _EmptyLines()
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final isTable = constraints.maxWidth >= kPayrollTableWidth;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    if (isTable) const _TableHeader(),
                    for (var index = 0; index < lines.length; index++)
                      _PersonRow(
                        line: lines[index],
                        isTable: isTable,
                        isFirst: index == 0 && !isTable,
                        isDraftWeek: isDraft,
                        isBusy: lines[index].id != null &&
                            lines[index].id == widget.busyLineId,
                        canPay: canPayLines,
                        canAdvance: widget.commandsEnabled &&
                            voucher.status != PayrollVoucherStatus.paid &&
                            voucher.status != PayrollVoucherStatus.voided,
                        methodName: _methodNameFor(lines[index]),
                        advanceAvailable: widget.advanceAvailableByEmployee[
                                lines[index].employeeId] ??
                            0,
                        expanded: _isExpanded(lines[index]),
                        onToggleExpanded: () => _toggleExpanded(lines[index]),
                        onPay: () => widget.onPayLine(lines[index]),
                        onRegisterAdvance: () =>
                            widget.onRegisterAdvance(lines[index]),
                        onOpenAttendances: widget.onOpenAttendances,
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  String? _methodNameFor(PayrollVoucherLine line) {
    final id = line.paymentMethodId?.trim();
    if (id == null || id.isEmpty) return null;
    return widget.paymentMethodNamesById[id] ?? 'Método sin nombre';
  }
}

class _CommitmentBand extends StatelessWidget {
  const _CommitmentBand({required this.voucher});

  final PayrollVoucher voucher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          payrollPeriodLabel(voucher),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${voucher.employeeCount} '
          '${voucher.employeeCount == 1 ? 'persona' : 'personas'} · '
          '${formatPayrollHours(voucher.totalHours)} · '
          'Documento ${voucher.voucherNumber}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StageBand extends StatelessWidget {
  const _StageBand({
    required this.stage,
    required this.voucher,
    required this.onEdit,
    required this.onDelete,
  });

  final PayrollStageDescriptor stage;
  final PayrollVoucher voucher;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDraft = voucher.status == PayrollVoucherStatus.draft;

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(stage.icon, size: 17, color: theme.colorScheme.onSurface),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${stage.label} · ${stage.meaning}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.35,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (voucher.paidAt != null) ...[
                const SizedBox(width: 8),
                Text(
                  formatPayrollDate(voucher.paidAt!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          if (isDraft && (onEdit != null || onDelete != null)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onEdit != null)
                  PayrollSecondaryAction(
                    label: 'Editar borrador',
                    icon: Icons.edit_outlined,
                    onPressed: onEdit,
                  ),
                if (onDelete != null)
                  PayrollSecondaryAction(
                    label: 'Eliminar borrador',
                    icon: Icons.delete_outline_rounded,
                    onPressed: onDelete,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MethodExceptionBand extends StatelessWidget {
  const _MethodExceptionBand({required this.lines});

  final List<PayrollVoucherLine> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = lines.map((line) => line.employeeName).join(', ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.report_problem_outlined,
            size: 18,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sin método de pago canónico: $names. Elige el método al '
              'registrar el pago; no se asume ninguno por defecto.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLines extends StatelessWidget {
  const _EmptyLines();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Center(
        child: Text(
          'Esta semana no incluye personas.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

const double _kAmountColWidth = 96;
const double _kNewMoneyColWidth = 110;
const double _kActionColWidth = 132;

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 8, 13, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('PERSONA', style: labelStyle)),
          Expanded(flex: 3, child: Text('MÉTODO', style: labelStyle)),
          SizedBox(
            width: _kAmountColWidth,
            child: Text('GANADO', style: labelStyle, textAlign: TextAlign.end),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: _kAmountColWidth,
            child:
                Text('ANTICIPOS', style: labelStyle, textAlign: TextAlign.end),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: _kNewMoneyColWidth,
            child: Text(
              'DINERO NUEVO',
              style: labelStyle,
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 12),
          const SizedBox(width: _kActionColWidth),
        ],
      ),
    );
  }
}

/// One worker of the selected week: a single decision row plus a labelled
/// disclosure with hours, rate and recorded payments.
///
/// Zero hours renders in the calm secondary tone: a person who did not work
/// is a normal fact, not an exception, and must not dominate the row.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.line,
    required this.isTable,
    required this.isFirst,
    required this.isDraftWeek,
    required this.isBusy,
    required this.canPay,
    required this.canAdvance,
    required this.methodName,
    required this.advanceAvailable,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onPay,
    required this.onRegisterAdvance,
    required this.onOpenAttendances,
  });

  final PayrollVoucherLine line;
  final bool isTable;
  final bool isFirst;
  final bool isDraftWeek;
  final bool isBusy;
  final bool canPay;
  final bool canAdvance;
  final String? methodName;
  final double advanceAvailable;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onPay;
  final VoidCallback onRegisterAdvance;
  final VoidCallback? onOpenAttendances;

  bool get _hasNoHours => line.totalHours <= 0;

  bool get _isSettled => line.balance <= 0.01;

  double get _newMoney {
    if (_isSettled) return 0;
    final covered =
        advanceAvailable > line.balance ? line.balance : advanceAvailable;
    return line.balance - covered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      label: '${line.employeeName}. '
          '${_isSettled ? 'Sin saldo.' : 'Saldo ${formatPayrollClp(line.balance)}.'}',
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: isFirst
                ? BorderSide.none
                : BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
                child:
                    isTable ? _buildTableRow(context) : _buildStacked(context),
              ),
            ),
            if (expanded) _RowDisclosure(line: line, this_: this),
          ],
        ),
      ),
    );
  }

  Widget _identity(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          line.employeeName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _hasNoHours
              ? 'Sin horas esta semana'
              : '${formatPayrollHours(line.totalHours)} · '
                  '${formatPayrollClp(line.hourlyRate)}/h',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _methodCell(ThemeData theme) {
    if (methodName == null) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: _ExceptionChip(label: 'Sin método'),
      );
    }
    return Text(
      methodName!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
    );
  }

  Widget _amount(
    BuildContext context,
    double value, {
    bool emphasis = false,
    bool quietDashWhenZero = false,
  }) {
    final theme = Theme.of(context);
    if (quietDashWhenZero && value <= 0.01) {
      return Text(
        '—',
        textAlign: TextAlign.end,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Text(
      formatPayrollClp(value),
      textAlign: TextAlign.end,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: payrollMoneyTextStyle(context, emphasis: emphasis)
          .copyWith(fontSize: emphasis ? 14.5 : 13.5),
    );
  }

  Widget _action(ThemeData theme) {
    if (isBusy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_isSettled) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_rounded,
            size: 15,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            'Pagada',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    final payButton = Semantics(
      button: true,
      enabled: canPay,
      label: canPay
          ? 'Pagar a ${line.employeeName}'
          : 'Pagar a ${line.employeeName}, deshabilitado: comprometé la semana primero',
      child: ExcludeSemantics(
        child: OutlinedButton(
          onPressed: canPay ? onPay : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, PayrollMoneyBar.minimumTouchTarget),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text('Pagar'),
        ),
      ),
    );
    if (canPay) return payButton;
    return Tooltip(
      message: isDraftWeek
          ? 'Compromete la semana para registrar pagos.'
          : 'Los pagos están bloqueados hasta recargar la vista.',
      child: payButton,
    );
  }

  Widget _disclosureIcon(ThemeData theme) {
    return Semantics(
      button: true,
      label: expanded
          ? 'Ocultar detalle de ${line.employeeName}'
          : 'Ver detalle de ${line.employeeName}',
      child: ExcludeSemantics(
        child: Icon(
          expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildTableRow(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(flex: 5, child: _identity(theme)),
        Expanded(flex: 3, child: _methodCell(theme)),
        SizedBox(
          width: _kAmountColWidth,
          child: _amount(context, line.totalAmount),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: _kAmountColWidth,
          child: _amount(context, advanceAvailable, quietDashWhenZero: true),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: _kNewMoneyColWidth,
          child: _isSettled
              ? Text(
                  'Sin saldo',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : _amount(context, _newMoney, emphasis: true),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: _kActionColWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _action(theme),
              const SizedBox(width: 6),
              _disclosureIcon(theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStacked(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _identity(theme)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _isSettled
                    ? Text(
                        'Sin saldo',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : _amount(context, _newMoney, emphasis: true),
                Text(
                  'dinero nuevo',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (methodName == null)
                    const _ExceptionChip(label: 'Sin método')
                  else
                    Text(
                      methodName!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (advanceAvailable > 0.01)
                    Text(
                      'Anticipo ${formatPayrollClp(advanceAvailable)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            _action(theme),
            const SizedBox(width: 4),
            _disclosureIcon(theme),
          ],
        ),
      ],
    );
  }
}

class _RowDisclosure extends StatelessWidget {
  const _RowDisclosure({required this.line, required this.this_});

  final PayrollVoucherLine line;
  final _PersonRow this_;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 4, 13, 11),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 22,
            runSpacing: 8,
            children: [
              _Fact(label: 'Horas', value: formatPayrollHours(line.totalHours)),
              _Fact(
                label: 'Tarifa',
                value: '${formatPayrollClp(line.hourlyRate)}/h',
              ),
              _Fact(label: 'Ganado', value: formatPayrollClp(line.totalAmount)),
              _Fact(
                label: 'Registrado',
                value: formatPayrollClp(line.settledAmount),
              ),
              _Fact(label: 'Saldo', value: formatPayrollClp(line.balance)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            children: [
              if (this_.canAdvance)
                TextButton.icon(
                  onPressed: this_.onRegisterAdvance,
                  icon: const Icon(Icons.savings_outlined, size: 16),
                  label: const Text('Registrar anticipo…'),
                  style: TextButton.styleFrom(
                    minimumSize:
                        const Size(0, PayrollMoneyBar.minimumTouchTarget),
                  ),
                ),
              if (this_.onOpenAttendances != null)
                TextButton.icon(
                  onPressed: this_.onOpenAttendances,
                  icon: const Icon(Icons.access_time_outlined, size: 16),
                  label: const Text('Corregir horas en Asistencias'),
                  style: TextButton.styleFrom(
                    minimumSize:
                        const Size(0, PayrollMoneyBar.minimumTouchTarget),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: payrollMoneyTextStyle(context).copyWith(fontSize: 13.5),
        ),
      ],
    );
  }
}

class _ExceptionChip extends StatelessWidget {
  const _ExceptionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.report_problem_outlined,
            size: 13,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
