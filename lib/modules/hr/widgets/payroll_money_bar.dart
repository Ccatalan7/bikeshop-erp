import 'package:flutter/material.dart';

import '../../../shared/utils/responsive_viewport.dart';

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

  /// Las cifras secundarias necesitan su propio ancho: por debajo de esto
  /// «Monto reconocido» no cabe junto a la principal sin recortarse.
  static const double _secondaryFiguresWidth = 520;

  /// Below this the actions move under the figures.
  ///
  /// The bar stays one persistent unit; only its internal arrangement changes.
  /// Squeezing two touch-sized buttons and an amount onto one line at 384 px or
  /// inside a 480 px sheet either clips the action or shrinks the label below a
  /// readable size, and the action is the point of the bar.
  /// **Bajo el compacto canónico las acciones se apilan a ancho completo.**
  ///
  /// Con 520 la barra mantenía figuras y botón en la misma fila hasta muy
  /// abajo, y el rótulo largo del primario —«Confirmar N semanas y aplicar
  /// conciliación»— se recortaba a «Confirmar 4 sema…», junto con «Monto
  /// reco…». Un botón que no dice qué hace no es una acción: es una adivinanza
  /// sobre dinero. Apilando, el primario ocupa la fila entera y el texto entra
  /// completo en tablet y teléfono.
  static const double _stackedActionsWidth = ResponsiveViewport.desktopMin;

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
                  // **Bajo teléfono las acciones se apilan; en tablet siguen
                  // en fila.** Repartir la fila por proporción falla en los
                  // dos sentidos: mitad y mitad cortaba «Confirmar N semanas y
                  // aplicar conciliación», y darle 3 de 4 dejaba a «Cancelar»
                  // sin espacio. A 430 no hay reparto que salve una frase y
                  // una palabra a la vez, así que cada una toma la fila
                  // entera. A 834 sí caben lado a lado.
                  // `5m` nota 04: «A 834 la barra monetaria se apila: cifra y
                  // razón arriba, botón de 46 abajo. Nada de un botón de 34
                  // perdido en una esquina táctil.» Eso vale para la barra de
                  // **una sola acción** —la semana—; el caso de dos acciones
                  // del OCR conserva su fila, que es la decisión del párrafo
                  // de arriba y no se deshace.
                  final stackVertically = constraints.maxWidth <
                          ResponsiveViewport.phoneMaxExclusive ||
                      actions.length == 1;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      figuresRow,
                      const SizedBox(height: 10),
                      if (stackVertically)
                        for (var index = actions.length - 1;
                            index >= 0;
                            index--) ...[
                          // El primario arriba: es lo que la etapa pide.
                          actions[index],
                          if (index > 0) const SizedBox(height: 8),
                        ]
                      else
                        Row(
                          children: [
                            for (var index = 0;
                                index < actions.length - 1;
                                index++) ...[
                              actions[index],
                              const SizedBox(width: 8),
                            ],
                            Expanded(child: actions.last),
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
      // **Dos líneas, no puntos suspensivos.** Este botón mueve dinero: en la
      // app viva a 834 y 430 decía «Confirmar 4 sema…» y «Ir a apli…», que no
      // es una acción sino una adivinanza. Un rótulo que envuelve sigue
      // diciendo entero lo que va a pasar; el alto mínimo táctil se conserva y
      // el botón crece si hace falta.
      label: Text(
        label,
        maxLines: 3,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
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
      label: Text(
        label,
        maxLines: 3,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, PayrollMoneyBar.minimumTouchTarget),
      ),
    );
  }
}
