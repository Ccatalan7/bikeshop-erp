import 'package:flutter/material.dart';

/// Chilean peso amounts, always integral and grouped with a period.
///
/// Payroll money is compared across a bank statement, a voucher line and a
/// receipt. Rendering it with tabular figures keeps digits aligned so an
/// operator can scan a column and see that two amounts differ.
String formatPayrollClp(num amount) {
  final rounded = amount.round();
  final isNegative = rounded < 0;
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
    buffer.write(digits[index]);
  }
  return '${isNegative ? '-' : ''}\$$buffer';
}

/// Signed amount used for a difference. Zero renders without a sign.
String formatPayrollClpSigned(num amount) {
  final rounded = amount.round();
  if (rounded == 0) return formatPayrollClp(0);
  final formatted = formatPayrollClp(rounded.abs());
  return rounded > 0 ? '+$formatted' : '-$formatted';
}

/// Hours with Chilean decimal separator. Whole values drop the decimal.
String formatPayrollHours(double hours) {
  if (hours == hours.roundToDouble()) return '${hours.round()} h';
  return '${hours.toStringAsFixed(1).replaceAll('.', ',')} h';
}

/// The text style every monetary figure uses.
TextStyle payrollMoneyTextStyle(BuildContext context, {bool emphasis = false}) {
  final theme = Theme.of(context);
  final base =
      emphasis ? theme.textTheme.titleMedium : theme.textTheme.bodyLarge;
  return (base ?? const TextStyle()).copyWith(
    fontWeight: emphasis ? FontWeight.w800 : FontWeight.w700,
    fontFeatures: const [FontFeature.tabularFigures()],
    letterSpacing: -0.2,
  );
}

/// One labelled amount in the money bar.
@immutable
class PayrollMoneyFigure {
  const PayrollMoneyFigure({
    required this.label,
    required this.amount,
    this.emphasis = false,
    this.isPrimary = false,
  });

  final String label;
  final num amount;

  /// Draws the amount in the heavier style. Reserved for the number the
  /// operator is acting on.
  final bool emphasis;

  /// Survives compact widths. Exactly one figure should set this.
  final bool isPrimary;
}

/// Persistent single-line money and call-to-action bar.
///
/// It stays one line at every width: the primary figure and the call to action
/// never wrap. Secondary figures appear only when the bar has room for them,
/// so a phone never trades the action away for a column of numbers.
class PayrollMoneyBar extends StatelessWidget {
  const PayrollMoneyBar({
    super.key,
    required this.figures,
    this.primaryAction,
    this.secondaryAction,
    this.note,
  });

  static const double minimumTouchTarget = 48;
  static const double _secondaryFiguresWidth = 600;

  /// Below this the actions move under the figures.
  ///
  /// The bar stays one persistent unit; only its internal arrangement changes.
  /// Squeezing two touch-sized buttons and an amount onto one line at 384 px or
  /// inside a 480 px sheet either clips the action or shrinks the label below a
  /// readable size, and the action is the point of the bar.
  static const double _stackedActionsWidth = 520;

  final List<PayrollMoneyFigure> figures;
  final Widget? primaryAction;
  final Widget? secondaryAction;

  /// One short sentence under the bar. Use it for a real constraint, never for
  /// a congratulation.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = figures.firstWhere(
      (figure) => figure.isPrimary,
      orElse: () => figures.isEmpty
          ? const PayrollMoneyFigure(label: 'Total', amount: 0)
          : figures.first,
    );
    final secondary =
        figures.where((figure) => !identical(figure, primary)).toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final showSecondary =
                    constraints.maxWidth >= _secondaryFiguresWidth &&
                        secondary.isNotEmpty;
                final stackActions =
                    constraints.maxWidth < _stackedActionsWidth;

                final figuresRow = Row(
                  children: [
                    Flexible(child: _Figure(figure: primary)),
                    if (showSecondary) ...[
                      const SizedBox(width: 22),
                      for (final figure in secondary) ...[
                        Flexible(child: _Figure(figure: figure)),
                        const SizedBox(width: 22),
                      ],
                    ],
                  ],
                );

                final actions = <Widget>[
                  if (secondaryAction != null) secondaryAction!,
                  if (primaryAction != null) primaryAction!,
                ];
                if (actions.isEmpty) return figuresRow;

                if (stackActions) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      figuresRow,
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (var index = 0;
                              index < actions.length;
                              index++) ...[
                            Expanded(child: actions[index]),
                            if (index < actions.length - 1)
                              const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Flexible(child: figuresRow),
                    const Spacer(),
                    // A long primary label (e.g. «Comprometer N semanas y
                    // aplicar conciliación») must truncate at medium widths
                    // instead of overflowing the bar.
                    for (var index = 0; index < actions.length; index++) ...[
                      Flexible(child: actions[index]),
                      if (index < actions.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                );
              },
            ),
            if (note != null && note!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.figure});

  final PayrollMoneyFigure figure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '${figure.label}: ${formatPayrollClp(figure.amount)}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            figure.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            formatPayrollClp(figure.amount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: payrollMoneyTextStyle(context, emphasis: figure.emphasis),
          ),
        ],
      ),
    );
  }
}

/// Filled action sized for touch. Used as the bar's primary call to action.
class PayrollPrimaryAction extends StatelessWidget {
  const PayrollPrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon ?? Icons.arrow_forward_rounded, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, PayrollMoneyBar.minimumTouchTarget),
      ),
    );
  }
}

/// Outlined companion action sized for touch.
class PayrollSecondaryAction extends StatelessWidget {
  const PayrollSecondaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.more_horiz_rounded, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, PayrollMoneyBar.minimumTouchTarget),
      ),
    );
  }
}
