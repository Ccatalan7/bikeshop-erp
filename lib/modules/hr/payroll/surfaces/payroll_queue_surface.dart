import 'package:flutter/material.dart';

import '../theme/payroll_tokens.dart';
import 'payroll_accent_action.dart';

/// 2a / 3a — Cola de nóminas: banda de semanas + tabla de decisión +
/// franja de Asistencias + barra monetaria. Construida desde cero.
/// NO envuelve payroll_week_queue.dart ni payroll_week_worksheet.dart.
///
/// El shell entrega el ancho útil real después de reservar navegación y toolbar.
/// La banda conserva cuatro slots visibles cuando caben; cuando existen más
/// semanas, sólo ese selector usa desplazamiento horizontal acotado y la tabla
/// nunca inventa ni descuenta geometría global.

// ── Modelos de vista (se alimentan de los servicios existentes) ─────────────
enum PayrollRowStatus {
  paid,
  paidWithinTolerance,
  pendingTransfer,
  pendingCash,
  openWeek,

  /// La línea no debe dinero porque su total es CERO, no porque se haya
  /// pagado. Son casos distintos y confundirlos afirma un pago que no
  /// existió: pasa cuando alguien entra a la semana sin horas cerradas.
  nothingToPay,

  /// La semana terminó pero sigue en borrador: las horas todavía no están
  /// fijas, así que no se puede pagar a nadie. La fila lo dice en vez de
  /// ofrecer un botón que en realidad abre otra cosa.
  weekNotConfirmed,
}

/// Cómo se presenta la única decisión visible de una fila.
///
/// Estado y acción no se componen como dos controles vecinos: cada fila
/// expone una sola pieza escaneable que puede ser pasiva, abrir el respaldo de
/// un pago, ejecutar la siguiente acción o desplegar una opción contextual.
enum PayrollRowActionMode {
  none,
  direct,
  paidDetails,
  menu,
}

class PayrollWeekCardVM {
  const PayrollWeekCardVM({
    required this.name,
    required this.range,
    required this.amountLabel,
    required this.amountCaption,
    required this.statusLabel,
    required this.tone,
    required this.selected,
    required this.onTap,
    this.settledFraction,
    this.footnote,
  });
  final String name; // "Semana 28"
  final String range; // "07 – 13 jul"
  final String amountLabel; // "$267.875"
  final String amountCaption; // "por pagar" | "acumulado"
  final String statusLabel; // "ABIERTA" | "EN COLA" | "EN CURSO"

  /// Cuánto de la semana ya está saldado, 0..1. El monto solo dice cuánto
  /// falta; la barra dice si eso es el final de un tramo o el principio.
  final double? settledFraction;

  /// Qué falta o qué pasó, en una línea: "3 por resolver", "confirmada 08/07",
  /// "se cierra el lunes". Sin esto la tarjeta obliga a entrar para saber si
  /// hay trabajo.
  final String? footnote;

  /// Temporary constructor compatibility for the page-level VM builder. The
  /// mounted Queue resolves the canonical state family through [toneFor].
  final PayrollStateTone tone;
  final bool selected;
  final VoidCallback onTap;

  PayrollStateTone toneFor(PayrollVisualTokens visual) {
    return statusLabel == 'ABIERTA' ? visual.warning : visual.neutral;
  }
}

class PayrollPersonRowVM {
  const PayrollPersonRowVM({
    required this.name,
    required this.initials,
    required this.avatarColor,
    required this.method,
    required this.methodIsCash,
    required this.earned,
    required this.advances,
    required this.newMoney,
    required this.paid,
    required this.status,
    required this.statusLabel,
    required this.statusMeta,
    required this.actionLabel,
    required this.actionMode,
    required this.hours,
    required this.rate,
    required this.paymentsSummary,
    required this.expanded,
    required this.onToggle,
    required this.onAction,
    this.bankAccountCaption,
    this.shortcuts = const <PayrollRowShortcutVM>[],
  });
  final String name;
  final String initials;
  final Color avatarColor;
  final String method; // "Transferencia" | "Efectivo"
  final bool methodIsCash;
  final String earned; // "$172.875"
  final String advances; // "−$40.000" | "—"

  /// Lo que la semana debe en dinero **después** de consumir anticipos, no el
  /// saldo pendiente: 5a la lee junto a `paid`, y `total − anticipos − pagado`
  /// es exactamente la cifra de la barra monetaria.
  final String newMoney; // "$179.375"

  /// Dinero que efectivamente se movió por esta fila. `—` mientras no haya
  /// ninguno: un `$0` afirmaría un pago de cero.
  final String paid; // "$179.375" | "—"
  final PayrollRowStatus status;
  final String statusLabel;

  /// Segunda línea del chip de decisión: cómo y cuándo se pagó
  /// (`transf 14/07`). Vacía cuando no hay un hecho que contar.
  final String statusMeta;

  /// Empty when the row is intentionally read-only.
  final String actionLabel; // "Pagar" | "Ver pago" | "Configurar método"
  final PayrollRowActionMode actionMode;
  final String hours; // "38,5 h"
  final String rate; // "$4.490 / h"
  final String paymentsSummary;

  /// Cuenta desde la que se paga, tal como la muestra el banco
  /// (`Banco de Chile ****9082`). Sólo vive en la fila abierta.
  final String? bankAccountCaption;

  /// Salidas de la fila abierta. Son atajos, no decisiones: ninguna de ellas
  /// paga ni confirma nada.
  final List<PayrollRowShortcutVM> shortcuts;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAction;

  bool get isPending =>
      status == PayrollRowStatus.pendingTransfer ||
      status == PayrollRowStatus.pendingCash;

  PayrollStateTone toneFor(PayrollVisualTokens visual) {
    switch (status) {
      case PayrollRowStatus.paid:
      case PayrollRowStatus.paidWithinTolerance:
        return visual.success;
      case PayrollRowStatus.pendingTransfer:
      case PayrollRowStatus.pendingCash:
        return visual.warning;
      case PayrollRowStatus.openWeek:
      // Sin horas no es un éxito ni una alerta: es una fila que no debería
      // estar ahí. Neutro, para que no compita con el trabajo real.
      case PayrollRowStatus.nothingToPay:
        return visual.neutral;
      // Falta confirmar SÍ es un bloqueo: es lo único que impide pagar.
      case PayrollRowStatus.weekNotConfirmed:
        return visual.warning;
    }
  }
}

/// Una salida de la fila abierta: nombre y a dónde lleva. Nunca ejecuta un
/// movimiento de dinero — para eso está la decisión de la fila.
class PayrollRowShortcutVM {
  const PayrollRowShortcutVM({
    required this.label,
    required this.onTap,
    this.external = false,
  });

  final String label;
  final VoidCallback onTap;

  /// Sale del módulo (Asistencias). Se marca para que nadie espere volver al
  /// mismo lugar.
  final bool external;
}

class PayrollWeekTotalsVM {
  const PayrollWeekTotalsVM({
    required this.title,
    required this.equation,
    required this.remaining,
    required this.showCommitAction,
    required this.canConfirm,
    required this.blockedReason,
    required this.nextActionLabel,
  });
  final String title; // "Semana 28 · 07 – 13 jul"
  final String
      equation; // "total $487.250 − anticipos $40.000 − pagado $179.375"
  final String remaining; // "$267.875"
  final bool showCommitAction;
  final bool canConfirm;
  final String blockedReason;
  final String nextActionLabel; // "Pagar a Lucas"
}

// ── Superficie ──────────────────────────────────────────────────────────────
class PayrollQueueSurface extends StatelessWidget {
  const PayrollQueueSurface({
    super.key,
    required this.weeks,
    required this.rows,
    required this.totals,
    required this.onOpenAttendance,
    required this.onConfirmWeek,
    required this.onNextAction,
    this.dense = false,
    this.excludedNote,
  });

  final List<PayrollWeekCardVM> weeks;
  final List<PayrollPersonRowVM> rows;
  final PayrollWeekTotalsVM totals;
  final VoidCallback onOpenAttendance;
  final VoidCallback onConfirmWeek;
  final VoidCallback onNextAction;

  /// Quién quedó fuera del cálculo y por qué. Nulo cuando no hay nadie: una
  /// franja de advertencia vacía enseña a ignorar las advertencias.
  final String? excludedNote;

  /// true cuando el ancho útil es 1116 (sidebar expandido) o menor: el método
  /// baja como segunda línea de la persona y se abrevian los headers.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _WeekQueueStrip(weeks: weeks, dense: dense),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                dense ? 16 : 18, dense ? 14 : 16, dense ? 16 : 18, 0),
            child: ListView(
              key: const ValueKey('payroll-queue-vertical-scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(bottom: dense ? 11 : 12),
              children: <Widget>[
                _DecisionTable(rows: rows, totals: totals, dense: dense),
                if (excludedNote != null) ...<Widget>[
                  SizedBox(height: dense ? 11 : 12),
                  _ExcludedStrip(
                    note: excludedNote!,
                    onOpen: onOpenAttendance,
                    dense: dense,
                  ),
                ],
                SizedBox(height: dense ? 11 : 12),
                _AttendanceStrip(onOpen: onOpenAttendance, dense: dense),
              ],
            ),
          ),
        ),
        _MoneyBar(
          totals: totals,
          dense: dense,
          onConfirmWeek: onConfirmWeek,
          onNextAction: onNextAction,
        ),
      ],
    );
  }
}

/// Ficha de persona con contraste GARANTIZADO.
///
/// Antes el color salía de una paleta fija por hash y las iniciales iban con un
/// color fijo encima: en los tonos oscuros de esa paleta (café, morado) las
/// letras quedaban ilegibles. Eso no era una decisión de tema — nadie había
/// comprobado el par.
///
/// El color de la persona sigue siendo estable (la misma persona, el mismo
/// tono, que es para lo que sirve), pero se usa como TINTE de un fondo suave y
/// las iniciales se pintan con ese mismo tono saturado. Así el par nace del
/// mismo color y no puede quedar sin contraste, en claro o en oscuro.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.color, required this.initials});
  final Color color;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hsl = HSLColor.fromColor(color);
    final fill = hsl
        .withSaturation(hsl.saturation.clamp(0.18, 0.55))
        .withLightness(dark ? 0.24 : 0.91)
        .toColor();
    final ink = hsl
        .withSaturation(hsl.saturation.clamp(0.35, 0.85))
        .withLightness(dark ? 0.78 : 0.32)
        .toColor();
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: visual.avatarInitials(10).copyWith(color: ink),
      ),
    );
  }
}

class _WeekQueueStrip extends StatelessWidget {
  const _WeekQueueStrip({required this.weeks, required this.dense});
  final List<PayrollWeekCardVM> weeks;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: visual.surface,
        border: Border(bottom: BorderSide(color: visual.border)),
      ),
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 16 : 18, vertical: dense ? 10 : 11),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gap = dense ? 8.0 : 9.0;
          if (weeks.length <= 4) {
            return Row(
              children: <Widget>[
                for (int i = 0; i < weeks.length; i++) ...<Widget>[
                  Expanded(child: _WeekCard(vm: weeks[i], dense: dense)),
                  if (i != weeks.length - 1) SizedBox(width: gap),
                ],
              ],
            );
          }
          final fourSlotWidth = (constraints.maxWidth - gap * 3) / 4;
          final cardWidth = fourSlotWidth < 210 ? 210.0 : fourSlotWidth;
          return SingleChildScrollView(
            key: const ValueKey('payroll-desktop-week-strip-scroll'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < weeks.length; i++) ...<Widget>[
                  SizedBox(
                    width: cardWidth,
                    child: _WeekCard(vm: weeks[i], dense: dense),
                  ),
                  if (i != weeks.length - 1) SizedBox(width: gap),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.vm, required this.dense});
  final PayrollWeekCardVM vm;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final tone = vm.toneFor(visual);
    final borderRadius = BorderRadius.circular(9);
    return Semantics(
      button: true,
      selected: vm.selected,
      label:
          '${vm.name}, ${vm.range}, ${vm.amountLabel} ${vm.amountCaption}, ${vm.statusLabel}',
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            color: vm.selected ? visual.surface : visual.surfaceSunken,
            borderRadius: borderRadius,
            border: Border.all(
              color: vm.selected ? visual.accent : visual.border,
            ),
            boxShadow: vm.selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: visual.accent.withValues(alpha: 0.12),
                      spreadRadius: 3,
                      blurRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            key: ValueKey('payroll-week-card-${vm.name}'),
            onTap: vm.onTap,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: borderRadius,
            hoverColor: visual.accentSoft.withValues(alpha: 0.7),
            focusColor: visual.accentSoft,
            splashColor: visual.accent.withValues(alpha: 0.10),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: dense ? 10 : 11,
                vertical: dense ? 8 : 9,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(vm.name,
                          style: visual.cardTitle.copyWith(
                              fontSize: dense ? 11 : 11.5,
                              color:
                                  vm.selected ? visual.ink : visual.inkMuted)),
                      const SizedBox(width: 7),
                      if (!dense)
                        Expanded(
                          child: Text(vm.range,
                              style: visual.monoS.copyWith(fontSize: 9.5),
                              overflow: TextOverflow.ellipsis),
                        )
                      else
                        const Spacer(),
                      if (dense)
                        Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                color: tone.fg, shape: BoxShape.circle))
                      else
                        _StatusPill(
                            label: vm.statusLabel, tone: tone, fontSize: 8.5),
                    ],
                  ),
                  SizedBox(height: dense ? 5 : 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Text(vm.amountLabel,
                          style: visual.numCard.copyWith(
                              fontSize: vm.selected ? 19 : 15,
                              color:
                                  vm.selected ? visual.ink : visual.inkFaint)),
                      const SizedBox(width: 6),
                      if (!dense)
                        Text(vm.amountCaption,
                            style: visual.bodyS.copyWith(
                                fontSize: 10, color: visual.inkFaint)),
                    ],
                  ),
                  if (dense)
                    Text(vm.range, style: visual.monoS.copyWith(fontSize: 9)),
                  // La barra y la línea de estado son lo que convierte la tira
                  // en un panorama: sin ellas el monto no dice si la semana va
                  // empezando o le falta un pago, y hay que entrar a cada una
                  // para saber dónde está el trabajo.
                  if (!dense && vm.settledFraction != null) ...[
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: vm.settledFraction!.clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: visual.border,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          vm.settledFraction! >= 1
                              ? visual.success.fg
                              : tone.fg,
                        ),
                      ),
                    ),
                  ],
                  if (!dense && vm.footnote != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      vm.footnote!,
                      style: visual.bodyS.copyWith(
                        fontSize: 9.5,
                        color: vm.selected ? tone.fg : visual.inkFaint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DecisionTable extends StatelessWidget {
  const _DecisionTable(
      {required this.rows, required this.totals, required this.dense});
  final List<PayrollPersonRowVM> rows;
  final PayrollWeekTotalsVM totals;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Compression order:
        // 1. El método pasa debajo de la persona.
        // 2. Gaps y gutters se compactan.
        // 3. Cada fila conserva una sola decisión intrínseca, sin escalar texto.
        // 4. Solo si el host entrega menos de 648 px útiles aparece un
        //    desplazamiento horizontal acotado para no ocultar cifras.
        const minimumReadableWidth = 648.0;
        final effectiveWidth = constraints.maxWidth < minimumReadableWidth
            ? minimumReadableWidth
            : constraints.maxWidth;
        // El borde consume un píxel por lado; cabecera y filas calculan sobre
        // el ancho interior real para no acumular un overflow subpíxel.
        final tableWidth = effectiveWidth - 2;
        final layout = _QueueGridLayout.resolve(
          width: tableWidth,
          denseHint: dense,
        );
        final body = SizedBox(
          width: tableWidth,
          child: _DecisionTableBody(
            rows: rows,
            totals: totals,
            layout: layout,
          ),
        );

        return Container(
          decoration: BoxDecoration(
            color: visual.surface,
            borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
            border: Border.all(color: visual.borderStrong),
            boxShadow: visual.raised,
          ),
          clipBehavior: Clip.antiAlias,
          child: constraints.maxWidth < minimumReadableWidth
              ? SingleChildScrollView(
                  key: const ValueKey('payroll-queue-last-resort-scroll'),
                  scrollDirection: Axis.horizontal,
                  child: body,
                )
              : body,
        );
      },
    );
  }
}

class _DecisionTableBody extends StatelessWidget {
  const _DecisionTableBody({
    required this.rows,
    required this.totals,
    required this.layout,
  });

  final List<PayrollPersonRowVM> rows;
  final PayrollWeekTotalsVM totals;
  final _QueueGridLayout layout;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          constraints: BoxConstraints(
            minHeight: layout.dense ? 42 : PayrollTokens.tableHeaderH,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: layout.horizontalPadding,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: visual.border)),
          ),
          child: Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  totals.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: visual.sectionTitle.copyWith(
                    fontSize: layout.dense ? 13 : 13.5,
                  ),
                ),
              ),
              if (!layout.dense) ...<Widget>[
                const SizedBox(width: 11),
                Flexible(
                  child: Text(
                    'horas cerradas en Asistencias',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: visual.bodyS.copyWith(
                      fontSize: 11,
                      color: visual.inkFaint,
                    ),
                  ),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
        Container(
          height: PayrollTokens.tableColsH,
          padding: EdgeInsets.symmetric(
            horizontal: layout.horizontalPadding,
          ),
          decoration: BoxDecoration(
            color: visual.surfaceSunken,
            border: Border(bottom: BorderSide(color: visual.border)),
          ),
          child: _RowGrid(
            layout: layout,
            children: <Widget>[
              const SizedBox(),
              const _ColLabel('PERSONA'),
              if (layout.showMethod) const _ColLabel('MÉTODO'),
              const _ColLabel('TOTAL', right: true),
              if (layout.showAdvances)
                _ColLabel(
                  layout.showMethod ? 'ANTICIPOS' : 'ANTIC.',
                  right: true,
                ),
              const _ColLabel('A PAGAR', right: true, accent: true),
              if (layout.showPaid) const _ColLabel('PAGADO', right: true),
              const _ColLabel('DECISIÓN', right: true),
            ],
          ),
        ),
        for (final PayrollPersonRowVM row in rows)
          _PersonRow(vm: row, layout: layout),
      ],
    );
  }
}

/// Reparte el espacio desde reglas `min / max / flex`. Las columnas monetarias
/// y de decisión nunca dependen de un ancho fijo de un mockup.
class _QueueGridLayout {
  const _QueueGridLayout({
    required this.dense,
    required this.showMethod,
    required this.showAdvances,
    required this.horizontalPadding,
    required this.leadingWidth,
    required this.gap,
    required this.widths,
  });

  final bool dense;
  final bool showMethod;

  /// `ANTICIPOS` sobrevive hasta 1116 (5b) y desaparece en tablet (5m), donde
  /// la aritmética completa vive en la fila abierta y en el chip.
  final bool showAdvances;
  final double horizontalPadding;
  final double leadingWidth;
  final double gap;
  final List<double> widths;

  /// `PAGADO` acompaña a `MÉTODO`: las dos se retiran juntas al bajar de 1240,
  /// y lo que decían pasa a la segunda línea de la persona y al chip (5b).
  bool get showPaid => showMethod;

  static _QueueGridLayout resolve({
    required double width,
    required bool denseHint,
  }) {
    final showMethod = !denseHint && width >= 1240;
    final dense = denseHint || !showMethod;
    // 5m: a 834 la tabla queda en persona / total / a pagar / decisión. El
    // umbral es 900 porque bajo ese ancho el chrome ya es el header único.
    final showAdvances = width >= 900;
    final horizontalPadding = width < 720 ? 12.0 : (dense ? 15.0 : 16.0);
    // The disclosure is a real focusable control, not a decorative glyph.
    // Reserve its full desktop target so keyboard and pointer users receive
    // the same affordance without stealing space from the decision column.
    const leadingWidth = 36.0;
    final gap = width < 720 ? 7.0 : (dense ? 9.0 : 10.0);

    final rules = showMethod
        ? const <_AdaptiveColumnRule>[
            _AdaptiveColumnRule(min: 220, max: 470, flex: 3.2),
            _AdaptiveColumnRule(min: 110, max: 210, flex: 1.35),
            _AdaptiveColumnRule(min: 88, max: 145, flex: 1),
            _AdaptiveColumnRule(min: 88, max: 145, flex: 1),
            _AdaptiveColumnRule(min: 116, max: 190, flex: 1.35),
            // PAGADO carga la misma clase de cifra que ANTICIPOS, así que
            // comparte su regla en vez de heredar un ancho literal del mock.
            _AdaptiveColumnRule(min: 88, max: 145, flex: 1),
            _AdaptiveColumnRule(min: 210, max: 360, flex: 2.2),
          ]
        : <_AdaptiveColumnRule>[
            const _AdaptiveColumnRule(min: 130, max: 430, flex: 2.4),
            const _AdaptiveColumnRule(min: 62, max: 140, flex: 1),
            if (showAdvances)
              const _AdaptiveColumnRule(min: 58, max: 140, flex: 0.95),
            const _AdaptiveColumnRule(min: 82, max: 180, flex: 1.35),
            // La columna de decisión recibe prioridad antes que identidad y
            // conserva un único control intrínseco al ancho real de 1116 px.
            const _AdaptiveColumnRule(min: 130, max: 280, flex: 2.65),
          ];
    final contentWidth =
        width - horizontalPadding * 2 - leadingWidth - gap * rules.length;

    return _QueueGridLayout(
      dense: dense,
      showMethod: showMethod,
      showAdvances: showAdvances,
      horizontalPadding: horizontalPadding,
      leadingWidth: leadingWidth,
      gap: gap,
      widths: _resolveAdaptiveWidths(
        available: contentWidth,
        rules: rules,
      ),
    );
  }

  static List<double> _resolveAdaptiveWidths({
    required double available,
    required List<_AdaptiveColumnRule> rules,
  }) {
    final widths = <double>[for (final rule in rules) rule.min];
    var remaining =
        (available - widths.fold<double>(0, (sum, width) => sum + width))
            .clamp(0.0, double.infinity);
    var active = <int>[
      for (var index = 0; index < rules.length; index++) index,
    ];

    while (remaining > 0.01 && active.isNotEmpty) {
      final totalFlex = active.fold<double>(
        0,
        (sum, index) => sum + rules[index].flex,
      );
      var distributed = 0.0;
      final saturated = <int>[];
      for (final index in active) {
        final capacity = rules[index].max - widths[index];
        final share = remaining * rules[index].flex / totalFlex;
        final addition = share < capacity ? share : capacity;
        widths[index] += addition;
        distributed += addition;
        if (capacity - addition <= 0.01) saturated.add(index);
      }
      if (distributed <= 0.01) break;
      remaining -= distributed;
      active = active.where((index) => !saturated.contains(index)).toList();
    }

    if (remaining > 0.01) {
      // Un host extremadamente ancho conserva la alineación ocupando el
      // remanente en identidad, la columna más segura para texto largo.
      widths[0] += remaining;
    }
    return widths;
  }
}

class _AdaptiveColumnRule {
  const _AdaptiveColumnRule({
    required this.min,
    required this.max,
    required this.flex,
  });

  final double min;
  final double max;
  final double flex;
}

/// Grid de una fila con una única distribución adaptativa compartida por
/// cabecera y registros.
class _RowGrid extends StatelessWidget {
  const _RowGrid({
    required this.layout,
    required this.children,
  });
  final _QueueGridLayout layout;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    assert(children.length == layout.widths.length + 1);
    final out = <Widget>[
      SizedBox(width: layout.leadingWidth, child: children.first),
    ];
    for (var index = 1; index < children.length; index++) {
      out
        ..add(SizedBox(width: layout.gap))
        ..add(
          SizedBox(
            width: layout.widths[index - 1],
            child: children[index],
          ),
        );
    }
    return Row(children: out);
  }
}

class _ColLabel extends StatelessWidget {
  const _ColLabel(this.text, {this.right = false, this.accent = false});
  final String text;
  final bool right;
  final bool accent;
  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Align(
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        text,
        style: visual.overline.copyWith(
          color: accent ? visual.accent : visual.inkFaint,
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.vm, required this.layout});
  final PayrollPersonRowVM vm;
  final _QueueGridLayout layout;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          constraints: const BoxConstraints(minHeight: PayrollTokens.rowH),
          padding: EdgeInsets.symmetric(
            horizontal: layout.horizontalPadding,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            // Expanded disclosure is a depth change (sunken step + the
            // accent anchor border below), never the selection tint: the
            // selected-week/History fill keeps `surfaceSelected` for itself.
            color: vm.expanded ? visual.surfaceSunken : visual.surface,
            border: Border(bottom: BorderSide(color: visual.border)),
          ),
          foregroundDecoration: vm.expanded
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(color: visual.accent, width: 3),
                  ),
                )
              : null,
          child: _RowGrid(
            layout: layout,
            children: <Widget>[
              Semantics(
                button: true,
                expanded: vm.expanded,
                label: vm.expanded
                    ? 'Ocultar detalle de ${vm.name}'
                    : 'Mostrar detalle de ${vm.name}',
                excludeSemantics: true,
                child: IconButton(
                  onPressed: vm.onToggle,
                  tooltip: vm.expanded ? 'Ocultar detalle' : 'Mostrar detalle',
                  mouseCursor: SystemMouseCursors.click,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  style: IconButton.styleFrom(
                    foregroundColor: visual.inkFaint,
                    hoverColor: visual.accent.withValues(alpha: 0.08),
                    focusColor: visual.accent.withValues(alpha: 0.14),
                  ),
                  icon: Icon(
                    vm.expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                    size: 18,
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  _Avatar(color: vm.avatarColor, initials: vm.initials),
                  const SizedBox(width: 9),
                  Expanded(
                    child: !layout.showMethod
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(vm.name,
                                  style: visual.bodyM.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis),
                              Row(children: <Widget>[
                                Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                        // accent-fill: indicator (method dot)
                                        color: vm.methodIsCash
                                            ? visual.warningFg
                                            : visual.accent,
                                        shape: BoxShape.circle)),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    vm.method,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: visual.monoS.copyWith(fontSize: 9.5),
                                  ),
                                ),
                              ]),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: <Widget>[
                              Flexible(
                                child: Text(vm.name,
                                    style: visual.bodyM
                                        .copyWith(fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              // Las horas viajan con el nombre porque son la
                              // BASE del monto de esa fila: sin ellas el total
                              // hay que creerlo, y la única forma de auditarlo
                              // es salir a Asistencias.
                              if (vm.hours.isNotEmpty) ...[
                                const SizedBox(width: 7),
                                Text(vm.hours,
                                    style: visual.monoS.copyWith(
                                        fontSize: 9.5, color: visual.inkFaint)),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
              if (layout.showMethod)
                Row(children: <Widget>[
                  Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          // accent-fill: indicator (method dot)
                          color: vm.methodIsCash
                              ? visual.warningFg
                              : visual.accent,
                          shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(vm.method,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.bodyS.copyWith(fontSize: 11.5)),
                  ),
                ]),
              Align(
                alignment: Alignment.centerRight,
                child: Text(vm.earned,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: visual.monoM
                        .copyWith(fontSize: layout.dense ? 11 : 12)),
              ),
              if (layout.showAdvances)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(vm.advances,
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: visual.monoM.copyWith(
                          fontSize: layout.dense ? 11 : 12,
                          color: vm.advances == '—'
                              ? visual.inkDisabled
                              : visual.successFg)),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(vm.newMoney,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: visual.numRow.copyWith(
                        fontSize: layout.dense ? 12.5 : 14,
                        color: vm.newMoney == '—'
                            ? visual.inkDisabled
                            : visual.ink)),
              ),
              if (layout.showPaid)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(vm.paid,
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: visual.monoM.copyWith(
                          fontSize: layout.dense ? 11 : 12,
                          color: vm.paid == '—'
                              ? visual.inkDisabled
                              : visual.ink)),
                ),
              _RowStateActions(vm: vm, dense: layout.dense),
            ],
          ),
        ),
        if (vm.expanded) _RowDisclosure(vm: vm, dense: layout.dense),
      ],
    );
  }
}

class _RowStateActions extends StatelessWidget {
  const _RowStateActions({required this.vm, required this.dense});

  final PayrollPersonRowVM vm;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final tone = vm.toneFor(visual);
    return Align(
      alignment: Alignment.centerRight,
      child: KeyedSubtree(
        key: ValueKey<String>('payroll-row-actions-${vm.name}'),
        child: switch (vm.actionMode) {
          PayrollRowActionMode.none => _StatusPill(
              label: vm.statusLabel,
              tone: tone,
              fontSize: dense ? 8.5 : 9,
            ),
          PayrollRowActionMode.direct => _DirectRowAction(
              vm: vm,
              dense: dense,
            ),
          PayrollRowActionMode.paidDetails => _PaidStatusAction(
              vm: vm,
              dense: dense,
            ),
          PayrollRowActionMode.menu => _StatusActionMenu(
              vm: vm,
              dense: dense,
            ),
        },
      ),
    );
  }
}

class _DirectRowAction extends StatelessWidget {
  const _DirectRowAction({required this.vm, required this.dense});
  final PayrollPersonRowVM vm;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final bool primary = vm.status == PayrollRowStatus.pendingTransfer;
    final bool outline = vm.status == PayrollRowStatus.pendingCash;

    if (primary) {
      // Accent-filled interaction is owned by the canonical action so fill,
      // foreground and overlays stay one contract.
      return IntrinsicWidth(
        child: Semantics(
          label: '${vm.statusLabel}.',
          child: KeyedSubtree(
            key: ValueKey<String>('payroll-row-action-${vm.name}'),
            child: PayrollAccentAction(
              actionKey: ValueKey<String>('payroll-row-action-tap-${vm.name}'),
              label: vm.actionLabel,
              onTap: vm.onAction,
              minHeight: dense ? 27 : 28,
              fontSize: dense ? 10.5 : 11,
              horizontalPadding: dense ? 9 : 10,
              verticalPadding: 5,
            ),
          ),
        ),
      );
    }

    final fill = outline ? visual.surface : Colors.transparent;
    final border = outline ? visual.borderStrong : Colors.transparent;
    final foreground = vm.isPending ? visual.inkMuted : visual.inkFaint;

    return IntrinsicWidth(
      child: Semantics(
        button: true,
        label: '${vm.statusLabel}. ${vm.actionLabel}',
        child: Material(
          key: ValueKey<String>('payroll-row-action-${vm.name}'),
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PayrollTokens.rField),
            side: BorderSide(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: vm.onAction,
            mouseCursor: SystemMouseCursors.click,
            hoverColor: visual.accentSoft,
            focusColor: visual.accentSoft,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: dense ? 27 : 28),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? 9 : 10,
                  vertical: 5,
                ),
                child: Text(
                  vm.actionLabel,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: visual.labelStrong.copyWith(
                    fontSize: dense ? 10.5 : 11,
                    color: foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un pago confirmado no necesita un enlace adyacente: el propio estado abre
/// su respaldo. Hover, foco, cursor y tooltip comunican que es interactivo sin
/// agregar otra etiqueta dentro de la tabla.
class _PaidStatusAction extends StatelessWidget {
  const _PaidStatusAction({required this.vm, required this.dense});

  final PayrollPersonRowVM vm;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final tone = vm.toneFor(visual);
    // El chip no dice sólo «Pagado»: dice cómo y cuándo. Es la única forma de
    // distinguir dos filas pagadas sin abrir el respaldo de cada una, y en
    // 1116 es donde vive la columna PAGADO que ahí se retira.
    final meta = vm.statusMeta.trim();
    return Tooltip(
      message: 'Ver pago de ${vm.name}',
      child: Semantics(
        button: true,
        label: meta.isEmpty
            ? '${vm.statusLabel}. Ver pago de ${vm.name}'
            : '${vm.statusLabel} $meta. Ver pago de ${vm.name}',
        excludeSemantics: true,
        child: Material(
          key: ValueKey<String>('payroll-paid-status-${vm.name}'),
          color: tone.soft,
          shape: StadiumBorder(side: BorderSide(color: tone.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: vm.onAction,
            mouseCursor: SystemMouseCursors.click,
            hoverColor: tone.fg.withValues(alpha: 0.08),
            focusColor: tone.fg.withValues(alpha: 0.12),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: dense ? 8 : 9,
                vertical: dense ? 3 : 4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    vm.statusLabel,
                    maxLines: 1,
                    style: visual.labelStrong.copyWith(
                      fontSize: dense ? 8.5 : 9,
                      color: tone.fg,
                    ),
                  ),
                  if (meta.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.monoS.copyWith(
                          fontSize: dense ? 8.5 : 9,
                          color: tone.fg,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 3),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: dense ? 11 : 12,
                    color: tone.fg,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Variante compacta para un estado que necesita una acción contextual.
/// El chevron forma parte de la misma píldora y abre un menú anclado; el menú
/// mantiene la acción fuera de la línea hasta que el usuario la solicita.
class _StatusActionMenu extends StatelessWidget {
  const _StatusActionMenu({required this.vm, required this.dense});

  final PayrollPersonRowVM vm;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final tone = vm.toneFor(visual);
    return MenuAnchor(
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(visual.surface),
        surfaceTintColor:
            const WidgetStatePropertyAll<Color>(Colors.transparent),
        elevation: const WidgetStatePropertyAll<double>(5),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(vertical: 4),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PayrollTokens.rField),
            side: BorderSide(color: visual.borderStrong),
          ),
        ),
      ),
      menuChildren: <Widget>[
        MenuItemButton(
          key: ValueKey<String>('payroll-configure-method-${vm.name}'),
          onPressed: vm.onAction,
          leadingIcon: Icon(
            Icons.tune_rounded,
            size: 17,
            color: visual.accent,
          ),
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll<Size>(Size(190, 38)),
            foregroundColor: WidgetStatePropertyAll<Color>(visual.ink),
            textStyle: WidgetStatePropertyAll<TextStyle>(
              visual.labelStrong.copyWith(fontSize: 11),
            ),
          ),
          child: Text(vm.actionLabel),
        ),
      ],
      builder: (context, controller, child) {
        void toggleMenu() =>
            controller.isOpen ? controller.close() : controller.open();

        return Tooltip(
          message: '${vm.statusLabel}: abrir opciones',
          child: Semantics(
            button: true,
            label: '${vm.statusLabel}. Abrir opciones',
            excludeSemantics: true,
            child: Material(
              key: ValueKey<String>('payroll-method-menu-${vm.name}'),
              color: tone.soft,
              shape: StadiumBorder(side: BorderSide(color: tone.border)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: toggleMenu,
                mouseCursor: SystemMouseCursors.click,
                hoverColor: tone.fg.withValues(alpha: 0.08),
                focusColor: tone.fg.withValues(alpha: 0.12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: dense ? 24 : 26),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.only(
                          left: dense ? 8 : 9,
                          right: dense ? 6 : 7,
                        ),
                        child: Text(
                          vm.statusLabel,
                          maxLines: 1,
                          style: visual.labelStrong.copyWith(
                            fontSize: dense ? 8.5 : 9,
                            color: tone.fg,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: dense ? 14 : 15,
                        color: tone.border,
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: dense ? 4 : 5,
                        ),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: dense ? 15 : 16,
                          color: tone.fg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Disclosure por fila: horas, tarifa y pagos registrados. Payroll no edita
/// asistencia: la salida es "Ver asistencia de la semana ↗".
class _RowDisclosure extends StatelessWidget {
  const _RowDisclosure({required this.vm, required this.dense});
  final PayrollPersonRowVM vm;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(dense ? 46 : 51, 12, dense ? 15 : 17, 14),
      decoration: BoxDecoration(
        color: visual.surfaceSunken,
        border: Border(bottom: BorderSide(color: visual.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panels = <Widget>[
            _DiscPanel(
              label: 'CÓMO SE CALCULÓ',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _DiscLine(label: 'Horas cerradas', value: vm.hours),
                  _DiscLine(label: 'Tarifa', value: vm.rate),
                  _DiscLine(label: 'Total de la semana', value: vm.earned),
                  _DiscLine(label: 'Anticipos aplicados', value: vm.advances),
                  // La última línea es la que la tabla muestra arriba: cierra
                  // la aritmética en vez de repetir un dato suelto.
                  _DiscLine(
                    label: 'A pagar',
                    value: vm.newMoney,
                    emphasis: true,
                  ),
                ],
              ),
            ),
            _DiscPanel(
              label: 'PAGOS DE ESTA SEMANA',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: visual.surface,
                      borderRadius: BorderRadius.circular(PayrollTokens.rField),
                      border: Border.all(color: visual.border),
                    ),
                    child: Text(
                      vm.paymentsSummary,
                      style: visual.bodyS.copyWith(fontSize: 11.5),
                    ),
                  ),
                  if (vm.bankAccountCaption != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      vm.bankAccountCaption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: visual.monoS.copyWith(fontSize: 9.5),
                    ),
                  ],
                ],
              ),
            ),
            if (vm.shortcuts.isNotEmpty)
              _DiscPanel(
                label: 'ATAJOS',
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: <Widget>[
                    for (final shortcut in vm.shortcuts)
                      _DiscShortcut(shortcut: shortcut),
                  ],
                ),
              ),
          ];
          // Tres paneles piden ~840 px para no quedar en una columna de texto
          // ilegible; bajo eso se apilan, que es como los lee 5l.
          if (constraints.maxWidth < 840) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < panels.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(height: 12),
                  panels[i],
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var i = 0; i < panels.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 26),
                Expanded(child: panels[i]),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Un bloque rotulado de la fila abierta. Los tres comparten rótulo y ritmo
/// para que se lean como una sola explicación, no como tres widgets sueltos.
class _DiscPanel extends StatelessWidget {
  const _DiscPanel({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: visual.overline.copyWith(fontSize: 9)),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

/// Una línea `concepto … cifra` de la aritmética.
class _DiscLine extends StatelessWidget {
  const _DiscLine({
    required this.label,
    required this.value,
    this.emphasis = false,
  });
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Container(
        decoration: emphasis
            ? BoxDecoration(
                border: Border(top: BorderSide(color: visual.border)),
              )
            : null,
        padding: EdgeInsets.only(top: emphasis ? 5 : 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: visual.bodyS.copyWith(
                  fontSize: 11.5,
                  color: emphasis ? visual.ink : visual.inkMuted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              value,
              maxLines: 1,
              style: visual.monoM.copyWith(
                fontSize: emphasis ? 12.5 : 11.5,
                color: emphasis ? visual.accent : visual.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscShortcut extends StatelessWidget {
  const _DiscShortcut({required this.shortcut});
  final PayrollRowShortcutVM shortcut;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Material(
      key: ValueKey<String>('payroll-row-shortcut-${shortcut.label}'),
      color: visual.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        side: BorderSide(color: visual.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: shortcut.onTap,
        mouseCursor: SystemMouseCursors.click,
        hoverColor: visual.accentSoft,
        focusColor: visual.accentSoft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  shortcut.label,
                  maxLines: 1,
                  style: visual.labelStrong.copyWith(
                    fontSize: 11,
                    color: visual.inkMuted,
                  ),
                ),
                if (shortcut.external) ...<Widget>[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.north_east_rounded,
                    size: 11,
                    color: visual.inkFaint,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quién quedó fuera de la aritmética de la semana y qué lo destraba.
///
/// La fila de esa persona ya lo dice, pero sólo si alguien la mira; el pie
/// suma sin ella y nadie sabría por qué. La salida es cerrar sus horas en
/// Asistencias: Nóminas no las inventa ni la borra de la semana.
class _ExcludedStrip extends StatelessWidget {
  const _ExcludedStrip({
    required this.note,
    required this.onOpen,
    required this.dense,
  });
  final String note;
  final VoidCallback onOpen;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      key: const ValueKey('payroll-excluded-strip'),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 11 : 13,
        vertical: dense ? 9 : 11,
      ),
      decoration: BoxDecoration(
        color: visual.warning.soft,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.warning.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: visual.warning.soft,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: visual.warning.border),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.priority_high_rounded,
              size: 13,
              color: visual.warning.fg,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              note,
              style: visual.bodyS.copyWith(
                fontSize: 11.5,
                color: visual.warning.fg,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Cerrar horas en Asistencias',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(PayrollTokens.rField),
              child: InkWell(
                key: const ValueKey('payroll-close-hours-action'),
                onTap: onOpen,
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(PayrollTokens.rField),
                hoverColor: visual.warning.fg.withValues(alpha: 0.08),
                focusColor: visual.warning.fg.withValues(alpha: 0.12),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(PayrollTokens.rField),
                    border: Border.all(color: visual.warning.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Cerrar horas en Asistencias ↗',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: visual.labelStrong.copyWith(
                      fontSize: 11,
                      color: visual.warning.fg,
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
}

class _AttendanceStrip extends StatelessWidget {
  const _AttendanceStrip({required this.onOpen, required this.dense});
  final VoidCallback onOpen;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      key: const ValueKey('payroll-attendance-strip'),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 11 : 13,
        vertical: dense ? 9 : 11,
      ),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: visual.accentSoft,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: visual.accentBorder),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.schedule, size: 14, color: visual.accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: visual.bodyS.copyWith(fontSize: 11.5),
                children: const <InlineSpan>[
                  TextSpan(text: 'Las horas se editan en '),
                  TextSpan(
                      text: 'Asistencias',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(
                      text: '. Nóminas solo liquida lo que Asistencias cerró.'),
                ],
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Abrir Asistencias',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(PayrollTokens.rField),
              child: InkWell(
                key: const ValueKey('payroll-open-attendance-action'),
                onTap: onOpen,
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(PayrollTokens.rField),
                hoverColor: visual.accentSoft,
                focusColor: visual.accentSoft,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(PayrollTokens.rField),
                    border: Border.all(color: visual.borderStrong),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Abrir Asistencias ↗',
                    style: visual.labelStrong.copyWith(
                      fontSize: 11,
                      color: visual.inkMuted,
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
}

/// Barra monetaria: se ancla al canvas del módulo, no a la ventana, para no
/// quedar por debajo del toolbar derecho.
class _MoneyBar extends StatelessWidget {
  const _MoneyBar({
    required this.totals,
    required this.dense,
    required this.onConfirmWeek,
    required this.onNextAction,
  });
  final PayrollWeekTotalsVM totals;
  final bool dense;
  final VoidCallback onConfirmWeek;
  final VoidCallback onNextAction;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      height: dense ? 54 : PayrollTokens.moneyBarH,
      padding: EdgeInsets.symmetric(horizontal: dense ? 16 : 18),
      decoration: BoxDecoration(
        color: visual.surface,
        border: Border(top: BorderSide(color: visual.borderStrong)),
        boxShadow: visual.moneyBar,
      ),
      child: Row(
        children: <Widget>[
          Text(dense ? 'FALTA' : 'FALTA PAGAR',
              style: visual.overline.copyWith(fontSize: dense ? 9 : 9.5)),
          const SizedBox(width: 8),
          Text(totals.remaining,
              style: visual.numBar.copyWith(fontSize: dense ? 19 : 20)),
          if (!dense) ...<Widget>[
            const SizedBox(width: 14),
            Expanded(
              child: Text(totals.equation,
                  style: visual.monoS.copyWith(fontSize: 10.5),
                  overflow: TextOverflow.ellipsis),
            ),
          ] else ...<Widget>[
            const SizedBox(width: 12),
            if (totals.canConfirm) const Spacer(),
          ],
          if (!totals.canConfirm) ...<Widget>[
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: dense ? 220 : 300),
                child: Text(
                  totals.blockedReason,
                  maxLines: dense ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: visual.bodyS.copyWith(
                    fontSize: dense ? 9.5 : 10.5,
                    color: visual.warningFg,
                  ),
                ),
              ),
            ),
            SizedBox(width: dense ? 8 : 12),
          ],
          // Deshabilitado que explica: inerte + razón visible al lado.
          if (totals.showCommitAction)
            PayrollAccentAction(
              actionKey: const ValueKey<String>('payroll-confirm-week'),
              label: dense ? 'Confirmar' : 'Confirmar semana',
              semanticLabel: 'Confirmar semana',
              onTap: onConfirmWeek,
              enabled: totals.canConfirm,
              height: dense ? 30 : 32,
              fontSize: dense ? 11 : 11.5,
              horizontalPadding: dense ? 11 : 12,
            ),
          // Acción-siguiente solo cuando existe y es distinta del CTA de
          // confirmación: jamás dos botones primarios idénticos.
          if (totals.nextActionLabel.isNotEmpty) ...<Widget>[
            const SizedBox(width: 8),
            PayrollAccentAction(
              actionKey: const ValueKey<String>('payroll-next-week-action'),
              label: totals.nextActionLabel,
              onTap: onNextAction,
              height: dense ? 32 : PayrollTokens.ctaH,
              fontSize: dense ? 11.5 : 12,
              horizontalPadding: dense ? 12 : 14,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(
      {required this.label, required this.tone, this.fontSize = 9.5});
  final String label;
  final PayrollStateTone tone;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.soft,
        borderRadius: BorderRadius.circular(PayrollTokens.rPill),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        label,
        style: visual.labelStrong.copyWith(
          fontSize: fontSize,
          color: tone.fg,
        ),
      ),
    );
  }
}
