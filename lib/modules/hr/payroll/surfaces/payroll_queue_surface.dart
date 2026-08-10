import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/widgets/vb_notice.dart';
import '../theme/payroll_tokens.dart';
import 'payroll_accent_action.dart';
import 'payroll_person_avatar.dart';

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
    required this.personId,
    required this.name,
    required this.initials,
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
    this.blockedReason = '',
    this.blockedReasonIsPersonal = false,
    this.destination,
    this.shortcuts = const <PayrollRowShortcutVM>[],
  });
  final String personId;
  final String name;
  final String initials;
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

  /// Por qué esta fila no ofrece acción, en una frase.
  ///
  /// `5c`: «Inhabilitado ≠ oculto: aparece cuando falta permiso o la semana
  /// está cerrada, y **siempre acompañado del motivo**». Sin esto, la forma
  /// pasiva dice que no se puede y calla lo único que el operador necesita —
  /// qué destrabaría la fila—, y el estado se vuelve un muro sin puerta.
  final String blockedReason;

  /// Si el motivo habla de **esta persona** o del estado de la semana.
  ///
  /// En escritorio da lo mismo: el motivo vive en un tooltip y no cuesta
  /// espacio. En el teléfono sí importa — un motivo de la semana es idéntico
  /// en todas las tarjetas, y repetirlo cuatro veces se comió los «cuatro
  /// registros completos en el primer viewport» que pide `5l`, para decir algo
  /// que la barra ya dice con `Confirmar semana`. El motivo de la semana lo
  /// explica el marco; la tarjeta explica lo que es cierto de su persona.
  final bool blockedReasonIsPersonal;
  final String hours; // "38,5 h"
  final String rate; // "$4.490 / h"
  final String paymentsSummary;

  /// A dónde llega la transferencia. Sólo vive en la fila abierta, y es nula
  /// cuando el método es efectivo: ahí no hay cuenta que nombrar.
  final PayrollRowDestinationVM? destination;

  /// Salidas de la fila abierta. Son atajos, no decisiones: ninguna de ellas
  /// paga ni confirma nada.
  final List<PayrollRowShortcutVM> shortcuts;
  final bool expanded;
  final VoidCallback onToggle;
  final FutureOr<void> Function() onAction;

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
/// La cuenta **destino** de una transferencia, o la ausencia declarada de una.
///
/// Es un tipo y no un `String?` porque «no la sé» y «no aplica» son hechos
/// distintos, y la pantalla los pinta distinto: uno es una glosa neutra y el
/// otro un pendiente accionable que ya tiene su atajo en la misma fila.
@immutable
class PayrollRowDestinationVM {
  /// `Banco Estado · Cuenta Vista · •••• 4821`, ya enmascarada por el host.
  const PayrollRowDestinationVM.known(String this.label) : missing = false;

  /// La persona se paga por transferencia y no tiene cuenta registrada.
  const PayrollRowDestinationVM.missing()
      : label = null,
        missing = true;

  final String? label;
  final bool missing;
}

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
    this.onEditDraft,
    this.dense = false,
    this.excludedNote,
    this.blockedNote,
  });

  final List<PayrollWeekCardVM> weeks;
  final List<PayrollPersonRowVM> rows;
  final PayrollWeekTotalsVM totals;
  final VoidCallback onOpenAttendance;
  final VoidCallback onConfirmWeek;
  final VoidCallback onNextAction;
  final VoidCallback? onEditDraft;

  /// Quién quedó fuera del cálculo y por qué. Nulo cuando no hay nadie: una
  /// franja de advertencia vacía enseña a ignorar las advertencias.
  final String? excludedNote;

  /// Por qué **todas** las filas bloqueadas lo están, cuando comparten motivo.
  ///
  /// `5c` exige que un estado inhabilitado nunca aparezca sin su razón, y esa
  /// razón tiene que verse **con el puntero**, no sólo con lector de pantalla.
  /// El vehículo NO puede ser un `Tooltip`: se comprobó en un proceso limpio
  /// que un `OverlayPortal` visible dentro del `LayoutBuilder` de esta tabla
  /// revienta al cambiar de banda (§4.24). El que sí sirve lo dibuja el propio
  /// `7a`: «la franja del pie manda a Asistencias» — una nota en línea, del
  /// dueño canónico `E-04 · VbNotice`, que no monta nada sobre el overlay.
  ///
  /// Nulo cuando no hay filas bloqueadas **o cuando no comparten motivo**: una
  /// sola franja no puede hablar por dos razones distintas sin mentirle a una.
  /// Ese caso lo cubre la fila abierta, que siempre lleva el suyo.
  final String? blockedNote;

  /// true cuando el ancho útil es 1116 (sidebar expandido) o menor: el método
  /// baja como segunda línea de la persona y se abrevian los headers.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // `5n` · «`LayoutBuilder` **en la superficie**, no en la fila». Éste es
    // ese LayoutBuilder, y su `constraints.maxWidth` es el ancho lógico
    // ANTES de cualquier padding o borde interior: el único eje honesto para
    // decidir el tramo. La tabla ya no lo deduce del ancho que le toca.
    return LayoutBuilder(
      builder: (context, surfaceConstraints) {
        final surfaceWidth = surfaceConstraints.maxWidth;
        return _buildSurface(context, surfaceWidth);
      },
    );
  }

  Widget _buildSurface(BuildContext context, double surfaceWidth) {
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
                _DecisionTable(
                  surfaceWidth: surfaceWidth,
                  rows: rows,
                  totals: totals,
                  dense: dense,
                  footerReason: blockedNote,
                ),
                if (blockedNote != null) ...<Widget>[
                  SizedBox(height: dense ? 11 : 12),
                  KeyedSubtree(
                    key: const ValueKey<String>('payroll-blocked-note'),
                    child: VbNotice(
                      tone: VbNoticeTone.warning,
                      title: 'Esta semana todavía no se puede pagar',
                      body: blockedNote,
                    ),
                  ),
                ],
                if (excludedNote != null) ...<Widget>[
                  SizedBox(height: dense ? 11 : 12),
                  _ExcludedStrip(
                    note: excludedNote!,
                    onOpen: onOpenAttendance,
                    dense: dense,
                  ),
                ],
                // `5b`: a 1116 la **franja de Asistencias se oculta**. No es
                // una pérdida: lo que esa franja recuerda —que las horas se
                // editan en Asistencias— ya lo dice la nota de personas fuera
                // del cálculo cuando hay alguna, y la salida real vive en la
                // fila abierta (`Abrir en Asistencias ↗`). Con el sidebar
                // expandido el canvas no sobra, y una franja permanente que
                // sólo recuerda una regla es lo primero que se retira.
                if (!dense) ...<Widget>[
                  SizedBox(height: dense ? 11 : 12),
                  _AttendanceStrip(onOpen: onOpenAttendance, dense: dense),
                ],
              ],
            ),
          ),
        ),
        _MoneyBar(
          totals: totals,
          dense: dense,
          onConfirmWeek: onConfirmWeek,
          onNextAction: onNextAction,
          onEditDraft: onEditDraft,
        ),
      ],
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
  const _DecisionTable({
    required this.surfaceWidth,
    required this.rows,
    required this.totals,
    required this.dense,
    required this.footerReason,
  });
  final List<PayrollPersonRowVM> rows;
  final PayrollWeekTotalsVM totals;
  final bool dense;

  /// El motivo que YA dice la franja del pie, si dice alguno. La fila abierta
  /// no lo repite: `7a` dibuja **tres** paneles, y un cuarto que copia palabra
  /// por palabra un aviso visible cinco centímetros más abajo es ruido.
  final String? footerReason;

  /// Ancho lógico de la SUPERFICIE, no el que le toca a esta tarjeta. Decide
  /// el tramo; el reparto de columnas sigue usando el interior real.
  final double surfaceWidth;

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
        // `5n` · «Layout por ancho lógico, con `LayoutBuilder` en la
        // superficie, no en la fila». El tramo lo decide `surfaceWidth`, que
        // baja del `LayoutBuilder` EXTERIOR; `tableWidth` sólo reparte
        // columnas. Entre ambos se pierden el padding lateral de la superficie
        // (32/36 según tier) y los 2 px del `Border`, así que resolver el
        // tramo acá dejaba 1200 de viewport siempre por debajo de 1200.
        final layout = _QueueGridLayout.resolve(
          width: tableWidth,
          logicalWidth: surfaceWidth,
          denseHint: dense,
        );
        final body = SizedBox(
          width: tableWidth,
          child: _DecisionTableBody(
            footerReason: footerReason,
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
    required this.footerReason,
  });

  final List<PayrollPersonRowVM> rows;
  final PayrollWeekTotalsVM totals;
  final _QueueGridLayout layout;
  final String? footerReason;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          // Las dos franjas de cabecera llevan identidad porque son dos owners
          // distintos con dos tokens distintos, y el esqueleto de carga tiene
          // que reservar LAS DOS (revisión de Codex, 2026-08-01).
          key: const ValueKey<String>('payroll-table-title'),
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
          key: const ValueKey<String>('payroll-table-columns'),
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
        _PersonRows(
          rows: rows,
          layout: layout,
          footerReason: footerReason,
        ),
      ],
    );
  }
}

/// Las filas y su navegación por teclado.
///
/// 7a lo dice en su propio frame —«Solo una fila abierta a la vez ↑↓ → ↵»— y
/// hasta acá era sólo un rótulo: la conducta no existía. El scope la
/// implementa, y es **determinista**: `↑`/`↓` mueven el foco a la fila
/// anterior o siguiente, no a los controles de adentro, porque la travesía
/// direccional por defecto entra al caret y al botón de decisión y el operador
/// pierde el hilo de la tabla.
///
/// «Una sola abierta a la vez» ya lo garantiza el host, que guarda **un** id
/// expandido; acá se conserva esa propiedad al abrir con el teclado.
/// Mover el foco una fila arriba o abajo.
@immutable
class _MoveRowIntent extends Intent {
  const _MoveRowIntent(this.delta);
  final int delta;
}

class _PersonRows extends StatefulWidget {
  const _PersonRows({
    required this.rows,
    required this.layout,
    required this.footerReason,
  });
  final String? footerReason;

  final List<PayrollPersonRowVM> rows;
  final _QueueGridLayout layout;

  @override
  State<_PersonRows> createState() => _PersonRowsState();
}

class _PersonRowsState extends State<_PersonRows> {
  final List<FocusNode> _nodes = <FocusNode>[];

  void _sync(int length) {
    while (_nodes.length < length) {
      _nodes.add(FocusNode(debugLabel: 'payroll-row-${_nodes.length}'));
    }
    while (_nodes.length > length) {
      _nodes.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _move(int from, int delta) {
    final next = from + delta;
    if (next < 0 || next >= _nodes.length) return;
    _nodes[next].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    _sync(widget.rows.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < widget.rows.length; index++)
          _PersonRow(
            footerReason: widget.footerReason,
            vm: widget.rows[index],
            layout: widget.layout,
            focusNode: _nodes[index],
            onMove: (delta) => _move(index, delta),
          ),
      ],
    );
  }
}

/// `5m`, leído del frame publicado por Design (turno 5, `5m-p1`): en la banda
/// de tablet la fila mide **60** y el control de decisión **44 × 200**. El 44
/// ya tiene dueño —`PayrollTokens.touchMin`—, así que sólo viajan acá los dos
/// que no lo tienen.
const double tabletRowHeight = 60;

/// `5n` · escalera de tramos, y **único owner del tier en todo el módulo**.
/// «≥1200 tabla de 8 columnas · 1000–1199 seis columnas · 900–999 cinco ·
/// <900 cuatro con fila de 60 · <600 tarjetas».
const double payrollQueueEightColMin = 1200;
const double payrollQueueSixColMin = 1000;

/// El host tenía su propio `< 1240` y competía con esta escalera. Un tier con
/// dos dueños es un tier que se contradice en los bordes, así que el host
/// pregunta acá en vez de repetir el número.
bool payrollQueueDenseHint(double logicalWidth) =>
    logicalWidth < payrollQueueEightColMin;

/// `5n` · `maxWidth 186/168/200` del control de decisión: 186 en la tabla
/// ancha, **168 en los tramos compactos de escritorio**, 200 en táctil.
const double tabletDecisionWidth = 200;

/// Reparte el espacio desde reglas `min / max / flex`. Las columnas monetarias
/// y de decisión nunca dependen de un ancho fijo de un mockup.
class _QueueGridLayout {
  const _QueueGridLayout({
    required this.dense,
    required this.showMethod,
    required this.tablet,
    required this.showAdvances,
    required this.horizontalPadding,
    required this.leadingWidth,
    required this.gap,
    required this.widths,
  });

  final bool dense;
  final bool showMethod;

  /// La banda de tablet de `5m` (834): cuatro columnas, fila de **60** y el
  /// control de decisión a **44 × 200**.
  ///
  /// «El mismo control de decisión crece a 44 de alto y 200 de ancho, **sin
  /// cambiar de forma ni de verbo**» — anotación literal del frame. No es un
  /// control distinto: es el mismo, táctil.
  final bool tablet;

  /// `ANTICIPOS` sobrevive hasta 1116 (5b) y desaparece en tablet (5m), donde
  /// la aritmética completa vive en la fila abierta y en el chip.
  final bool showAdvances;
  final double horizontalPadding;
  final double leadingWidth;
  final double gap;
  final List<double> widths;

  /// `5n` · el tope del control por tramo. Lo resuelve el layout una vez y
  /// viaja a las CUATRO formas; que cada forma lo dedujera de `tablet` fue lo
  /// que dejó el compacto de escritorio en 186 y el táctil sin tope.
  double get decisionMaxWidth => tablet
      ? tabletDecisionWidth
      : (showMethod ? decisionCellMaxWidth : decisionCellMaxWidthDense);

  /// `PAGADO` acompaña a `MÉTODO`: las dos se retiran juntas al bajar de
  /// `payrollQueueEightColMin` (**1200**),
  /// y lo que decían pasa a la segunda línea de la persona y al chip (5b).
  bool get showPaid => showMethod;

  /// Dos anchos, y la distinción es el defecto que esto corrige.
  ///
  /// [logicalWidth] es el de la SUPERFICIE y decide el **tramo** —`5n` lo pide
  /// así—. [width] es el interior de la tarjeta y sólo reparte columnas.
  ///
  /// Entre uno y otro hay **dos descuentos, no uno**: el padding lateral de la
  /// superficie (**32 px**, o **36** según el tier) y además los **2 px** del
  /// `Border` de la tarjeta. Por eso un viewport de 1200 nunca llegaba a 1200
  /// aquí. Usar un solo ancho para las dos cosas daba, según cuál se eligiera,
  /// un tramo corrido decenas de píxeles o un overflow de dos.
  static _QueueGridLayout resolve({
    required double width,
    required double logicalWidth,
    required bool denseHint,
  }) {
    // `5n` · «Layout por ancho lógico» declara la escalera: **≥1200 ocho
    // columnas · 1000–1199 seis · 900–999 cinco · <900 cuatro con fila de 60 ·
    // <600 tarjetas».
    //
    final showMethod = !denseHint && logicalWidth >= payrollQueueEightColMin;
    final dense = denseHint || !showMethod;
    final showAdvances = logicalWidth >= payrollQueueSixColMin;
    // 834 es el ancho declarado de 5m; 720 es el piso desde el que la tabla
    // sigue siendo tabla. Bajo eso la superficie ya se compone en tarjetas.
    final tablet = !showMethod && logicalWidth >= 720 && logicalWidth < 900;
    final horizontalPadding = logicalWidth < 720 ? 12.0 : (dense ? 15.0 : 16.0);
    // The disclosure is a real focusable control, not a decorative glyph.
    // Reserve its full desktop target so keyboard and pointer users receive
    // the same affordance without stealing space from the decision column.
    const leadingWidth = 36.0;
    final gap = logicalWidth < 720 ? 7.0 : (dense ? 9.0 : 10.0);

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
            // `5m`: en tablet la decisión pide **200** de ancho, no 130.
            _AdaptiveColumnRule(
              min: tablet ? tabletDecisionWidth : 130,
              max: 280,
              flex: 2.65,
            ),
          ];
    final contentWidth =
        width - horizontalPadding * 2 - leadingWidth - gap * rules.length;

    return _QueueGridLayout(
      dense: dense,
      showMethod: showMethod,
      tablet: tablet,
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

class _PersonRow extends StatefulWidget {
  const _PersonRow({
    required this.footerReason,
    required this.vm,
    required this.layout,
    required this.focusNode,
    required this.onMove,
  });
  final PayrollPersonRowVM vm;
  final _QueueGridLayout layout;
  final FocusNode focusNode;
  final ValueChanged<int> onMove;
  final String? footerReason;

  @override
  State<_PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends State<_PersonRow> {
  bool _focused = false;

  PayrollPersonRowVM get vm => widget.vm;
  _QueueGridLayout get layout => widget.layout;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onShowFocusHighlight: (value) {
        if (value != _focused) setState(() => _focused = value);
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveRowIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveRowIntent(-1),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        _MoveRowIntent: CallbackAction<_MoveRowIntent>(
          onInvoke: (intent) {
            widget.onMove(intent.delta);
            return null;
          },
        ),
        // Enter abre y cierra la misma fila: es el mismo verbo del caret, y el
        // host sigue siendo el dueño de que haya una sola abierta.
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            vm.onToggle();
            return null;
          },
        ),
      },
      child: Semantics(
        container: true,
        selected: _focused,
        child: _buildRow(context, visual),
      ),
    );
  }

  Widget _buildRow(BuildContext context, PayrollVisualTokens visual) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          constraints: BoxConstraints(
            minHeight: layout.tablet ? tabletRowHeight : PayrollTokens.rowH,
          ),
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
          // El foco de teclado tiene que verse: sin anillo, `↑`/`↓` mueven
          // algo que el operador no puede ubicar.
          foregroundDecoration: _focused
              ? BoxDecoration(
                  border: Border.all(color: visual.accent, width: 2),
                )
              : (vm.expanded
                  ? BoxDecoration(
                      border: Border(
                        left: BorderSide(color: visual.accent, width: 3),
                      ),
                    )
                  : null),
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
                  // **Sin `tooltip:`, y no por gusto.** `IconButton.tooltip`
                  // construye un `Tooltip`, que es un `OverlayPortal`; con uno
                  // visible dentro del `LayoutBuilder` de esta tabla, cambiar
                  // de banda tumba el módulo. Reproducido en proceso limpio
                  // (`84436`, sin hot reload): hover real sobre el caret,
                  // `1360 → 834`, y cae con `A _RenderLayoutBuilder was
                  // mutated in _RenderLayoutBuilder.performLayout`. **Este
                  // defecto es ANTERIOR a `5c`** —el caret siempre tuvo su
                  // tooltip— y lo único que hizo `5c` fue encontrarlo.
                  // No se pierde nada: el `Semantics` de arriba ya dice
                  // «Mostrar/Ocultar detalle de <persona>» palabra por
                  // palabra, y el estado se ve en el propio glifo (▸ / ▾).
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
                  PayrollPersonAvatar(
                    personId: vm.personId,
                    initials: vm.initials,
                    size: 26,
                    fontSize: 10,
                  ),
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
              _RowStateActions(
                vm: vm,
                tablet: layout.tablet,
                decisionMaxWidth: layout.decisionMaxWidth,
              ),
            ],
          ),
        ),
        if (vm.expanded)
          _RowDisclosure(
            vm: vm,
            dense: layout.dense,
            footerReason: widget.footerReason,
          ),
      ],
    );
  }
}

// ── `5c` · gramática de decisión ────────────────────────────────────────────
//
// El tablero `5c` es **el contrato del control de decisión**: cinco formas por
// cinco estados. Cualquier fila futura —vacaciones, licencia, finiquito— cae
// en una de las cinco, o se declara una sexta en Design antes de dibujarla.
//
//   1. pagada          → el chip ES el botón: abre el respaldo   (`_PaidStatusAction`)
//   2. falta método    → tonal con caret: opciones               (`_StatusActionMenu`)
//   3. transferencia   → acción directa, estado implícito        (`_DirectRowAction`)
//   4. efectivo        → misma jerarquía, otra tesorería         (`_DirectRowAction`)
//   5. bloqueo         → texto pasivo, sin falsa acción          (`_PassiveDecision`)
//
// Medidas **leídas literales del turno 7** (`7a`, canvas «Nóminas - Rediseño»),
// no estimadas de una captura: `height:28 · max-width:186 · padding:0 10 ·
// border-radius:8 · gap:6 · border:1`, rótulo `500 11px` (`600` en el
// primario), meta mono `9.5px` al 75 %, `›` de 12 al 60 % y `▾` de 9 detrás de
// un divisor de 1 con 7 de separación. La forma pasiva es
// `font:400 11px · color inkFaint`, sin fondo, sin borde y sin radio.
const double decisionCellHeight = 28;
const double decisionCellMaxWidth = 186;
const double decisionCellMaxWidthDense = 168;
const double decisionCellPadH = 10;
const double decisionCellGap = 6;
const double decisionLabelSize = 11;
const double decisionMetaSize = 9.5;

/// `5c` · FOCO: **anillo de 3 px por fuera del borde, nunca reemplazándolo**, y
/// **visible con teclado, no con clic**.
///
/// Las dos mitades de esa regla salen gratis si el anillo no pide el foco por
/// su cuenta: este `Focus` sólo se entera de que lo tomó el control de adentro
/// (`hasFocus` incluye a los descendientes), y en Material un `InkWell` **no
/// mueve el foco al tocarlo con el puntero** — se comprobó en el SDK montado,
/// no se supuso—, así que el anillo aparece con `Tab`/`↑`/`↓` y no con el clic.
///
/// Se dibuja con un hijo posicionado a −3 y `Clip.none`: queda literalmente por
/// fuera de los límites del control, no ocupa layout y no toca su borde.
class _DecisionFocusRing extends StatefulWidget {
  const _DecisionFocusRing({required this.child, this.focusable = false});

  final Widget child;

  /// La forma pasiva sí es un destino de teclado: es la única manera de que
  /// quien no usa puntero alcance el motivo. Las activas ya traen el suyo
  /// dentro del `InkWell`.
  final bool focusable;

  @override
  State<_DecisionFocusRing> createState() => _DecisionFocusRingState();
}

class _DecisionFocusRingState extends State<_DecisionFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Focus(
      canRequestFocus: widget.focusable,
      skipTraversal: !widget.focusable,
      onFocusChange: (bool value) {
        if (value != _focused) setState(() => _focused = value);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          widget.child,
          if (_focused)
            Positioned(
              left: -3,
              top: -3,
              right: -3,
              bottom: -3,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey<String>('payroll-decision-focus-ring'),
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(PayrollTokens.rField + 3),
                    // accent-fill: focus ring. `5c` lo fija en el acento al
                    // 35 %; en oscuro ese acento es el del preset, que es
                    // exactamente lo que publica `interaction.focusRing`.
                    border: Border.all(
                      color: visual.accent.withValues(alpha: 0.35),
                      width: 3,
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

/// El envoltorio común de las tres formas tonales de `5c`. Una sola pieza para
/// que «cambiar de estado» no signifique cambiar de tamaño ni de forma.
class _DecisionShell extends StatelessWidget {
  const _DecisionShell({
    required this.tone,
    required this.tablet,
    required this.maxWidth,
    required this.children,
  });

  final PayrollStateTone tone;

  /// `5m`: en tablet el MISMO control crece a 44 × 200, sin cambiar de forma.
  final bool tablet;

  /// `5n` · `maxWidth 186/168/200`, ya resuelto por el layout.
  final double maxWidth;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: tablet ? PayrollTokens.touchMin : decisionCellHeight,
        minWidth: tablet ? tabletDecisionWidth : 0,
        // `5n`: `maxWidth 186/168/200`. Es TOPE, no piso: sin él la regla de
        // columna dejaba crecer el control hasta 280 en táctil.
        maxWidth: maxWidth,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: decisionCellPadH),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }
}

/// `5c` · forma 5: **texto pasivo, sin falsa acción**.
///
/// No es una píldora atenuada: una píldora con relleno y borde es la misma
/// figura que las cuatro formas activas, y con producción en borrador **todas**
/// las filas del módulo caen aquí — la tabla entera parecía accionable y no lo
/// era. Va el hecho en texto, con el motivo al alcance del puntero y del
/// lector de pantalla, y sin cursor de mano.
class _PassiveDecision extends StatelessWidget {
  const _PassiveDecision({
    required this.label,
    required this.reason,
    required this.name,
    this.decisionMaxWidth = decisionCellMaxWidth,
  });

  final String label;
  final String reason;
  final String name;

  /// `5n` · la forma pasiva no lleva píldora, pero **sí lleva el mismo tope**:
  /// si su texto se estira más que las cuatro formas activas, el ojo lee dos
  /// anchos de columna distintos en la misma tabla.
  final double decisionMaxWidth;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final Widget text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: visual.bodyS.copyWith(
        fontSize: decisionLabelSize,
        fontWeight: FontWeight.w400,
        color: visual.inkFaint,
      ),
    );
    return _DecisionFocusRing(
      focusable: true,
      child: Semantics(
        key: ValueKey<String>('payroll-row-blocked-$name'),
        // `aria-disabled` + `aria-describedby` de `5c`: se anuncia que hay un
        // estado y que no está habilitado, y el motivo viaja con él.
        //
        // `container: true` no es decoración: sin él la anotación se funde en
        // el nodo de la FILA, que sí trae el botón del caret — y el lector
        // terminaba anunciando la fila entera como un botón deshabilitado,
        // cuando el caret se puede abrir perfectamente. Lo bloqueado es la
        // decisión, no la fila.
        container: true,
        enabled: false,
        label: reason.isEmpty ? '$label. $name' : '$label. $name. $reason',
        // Acá el motivo viaja como PROPIEDAD semántica, no como `Tooltip`.
        //
        // `5c` pide «el motivo en tooltip» y se implementó así primero, pero un
        // `Tooltip` es un `OverlayPortal` y **uno VISIBLE** dentro del
        // `LayoutBuilder` de esta tabla se reactiva en el reparenting del
        // cambio de banda y muta un `_RenderLayoutBuilder` desde dentro del
        // `performLayout` de otro: el módulo se cae. Medido en proceso limpio,
        // sin hot reload. Montado y **sin mostrar** no falla — lo que importa
        // es que esté visible, no cuántos haya—, y el `tooltip:` del caret,
        // anterior a `5c`, lo producía igual: el defecto no era de esta celda.
        // La prueba de widget NO lo reproduce; necesita el relayout real de la
        // ventana, por eso el contrato es estructural.
        //
        // **El motivo visible NO se pierde:** vive donde lo dibuja el propio
        // `7a` —la franja del pie—, en el aviso en línea canónico
        // `E-04 · VbNotice`, que no monta nada sobre el overlay. Se dice una
        // vez cuando todas las filas comparten motivo, y si no lo comparten la
        // franja calla y cada fila abierta lleva el suyo. Esta propiedad es el
        // canal para lectores de pantalla, no el sustituto de aquello.
        tooltip: reason,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: decisionMaxWidth),
          child: text,
        ),
      ),
    );
  }
}

class _RowStateActions extends StatelessWidget {
  const _RowStateActions({
    required this.vm,
    this.tablet = false,
    this.decisionMaxWidth = decisionCellMaxWidth,
  });

  final PayrollPersonRowVM vm;

  /// Banda de tablet de `5m`: el control crece a 44 sin cambiar de forma.
  final bool tablet;

  /// `5n` · tope del control en este tramo (186 / 168 / 200).
  final double decisionMaxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: KeyedSubtree(
        key: ValueKey<String>('payroll-row-actions-${vm.name}'),
        child: switch (vm.actionMode) {
          PayrollRowActionMode.none => _PassiveDecision(
              label: vm.statusLabel,
              reason: vm.blockedReason,
              name: vm.name,
              decisionMaxWidth: decisionMaxWidth,
            ),
          PayrollRowActionMode.direct => _DirectRowAction(
              vm: vm,
              tablet: tablet,
              decisionMaxWidth: decisionMaxWidth,
            ),
          PayrollRowActionMode.paidDetails => _PaidStatusAction(
              vm: vm,
              tablet: tablet,
              decisionMaxWidth: decisionMaxWidth,
            ),
          PayrollRowActionMode.menu => _StatusActionMenu(
              vm: vm,
              tablet: tablet,
              decisionMaxWidth: decisionMaxWidth,
            ),
        },
      ),
    );
  }
}

class _DirectRowAction extends StatelessWidget {
  const _DirectRowAction({
    required this.vm,
    this.tablet = false,
    this.decisionMaxWidth = decisionCellMaxWidth,
  });
  final PayrollPersonRowVM vm;

  /// `5m`: en la banda de tablet el mismo control crece a 44.
  final bool tablet;

  /// `5n` · tope del control en este tramo (186 / 168 / 200).
  final double decisionMaxWidth;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final bool primary = vm.status == PayrollRowStatus.pendingTransfer;
    final bool outline = vm.status == PayrollRowStatus.pendingCash;

    if (primary) {
      // Accent-filled interaction is owned by the canonical action so fill,
      // foreground and overlays stay one contract.
      return _DecisionFocusRing(
        child: ConstrainedBox(
          // `5m`: en tablet el control mide **200** de ancho. Fuera de esa
          // banda sigue siendo intrínseco al verbo, que es lo que pide 5a.
          constraints: BoxConstraints(
            minWidth: tablet ? tabletDecisionWidth : 0,
            // `5n`: `maxWidth 186/168/200`. Es TOPE, no piso.
            maxWidth: decisionMaxWidth,
          ),
          child: IntrinsicWidth(
            child: Semantics(
              label: '${vm.statusLabel}.',
              child: KeyedSubtree(
                key: ValueKey<String>('payroll-row-action-${vm.name}'),
                child: PayrollAccentAction(
                  actionKey:
                      ValueKey<String>('payroll-row-action-tap-${vm.name}'),
                  label: vm.actionLabel,
                  onTap: vm.onAction,
                  // `5m`: en tablet el MISMO control crece a 44 —el objetivo
                  // táctil que ya publica `PayrollTokens.touchMin`— sin cambiar
                  // de forma ni de verbo. Fuera de ahí, el 28 de `7a`.
                  minHeight:
                      tablet ? PayrollTokens.touchMin : decisionCellHeight,
                  // `5b` es explícito: a 1116 «las etiquetas largas se truncan
                  // con elipsis», no se encogen. El rótulo no cambia de tamaño
                  // entre bandas; lo que cambia es cuánto cabe.
                  fontSize: decisionLabelSize,
                  horizontalPadding: tablet ? 14 : decisionCellPadH,
                  verticalPadding: 5,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final fill = outline ? visual.surface : Colors.transparent;
    final border = outline ? visual.borderStrong : Colors.transparent;
    final foreground = vm.isPending ? visual.inkMuted : visual.inkFaint;

    return _DecisionFocusRing(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: tablet ? tabletDecisionWidth : 0,
          // `5n`: `maxWidth 186/168/200`. Es TOPE, no piso.
          maxWidth: decisionMaxWidth,
        ),
        child: IntrinsicWidth(
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
                  constraints: BoxConstraints(
                    minHeight:
                        tablet ? PayrollTokens.touchMin : decisionCellHeight,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: tablet ? 14 : decisionCellPadH,
                      vertical: 5,
                    ),
                    child: Text(
                      vm.actionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: visual.labelStrong.copyWith(
                        fontSize: decisionLabelSize,
                        color: foreground,
                      ),
                    ),
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
  const _PaidStatusAction({
    required this.vm,
    this.tablet = false,
    this.decisionMaxWidth = decisionCellMaxWidth,
  });

  final PayrollPersonRowVM vm;
  final bool tablet;

  /// `5n` · tope del control en este tramo (186 / 168 / 200).
  final double decisionMaxWidth;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final tone = vm.toneFor(visual);
    // El chip no dice sólo «Pagado»: dice cómo y cuándo. Es la única forma de
    // distinguir dos filas pagadas sin abrir el respaldo de cada una, y en
    // 1116 es donde vive la columna PAGADO que ahí se retira.
    final meta = vm.statusMeta.trim();
    return _DecisionFocusRing(
      // Sin `Tooltip`: repetía palabra por palabra la etiqueta semántica que
      // está justo abajo, y cada `Tooltip` es un `OverlayPortal` que se monta
      // DENTRO del `LayoutBuilder` de esta tabla. Con uno por fila, un cambio
      // de ancho revienta en `overlay.dart:1258 · '!_skipMarkNeedsLayout'` —
      // medido en la app viva, no supuesto—. Lo que decía ya lo dicen el
      // rótulo visible y la semántica.
      child: Semantics(
        button: true,
        label: meta.isEmpty
            ? '${vm.statusLabel}. Ver pago de ${vm.name}'
            : '${vm.statusLabel} $meta. Ver pago de ${vm.name}',
        tooltip: 'Ver pago de ${vm.name}',
        excludeSemantics: true,
        child: Material(
          key: ValueKey<String>('payroll-paid-status-${vm.name}'),
          color: tone.soft,
          // `7a` la dibuja con radio 8, no de cápsula: las cinco formas de
          // `5c` comparten envoltura y sólo cambian de contenido.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PayrollTokens.rField),
            side: BorderSide(color: tone.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: vm.onAction,
            mouseCursor: SystemMouseCursors.click,
            hoverColor: tone.fg.withValues(alpha: 0.08),
            focusColor: tone.fg.withValues(alpha: 0.12),
            child: _DecisionShell(
              maxWidth: decisionMaxWidth,
              tone: tone,
              tablet: tablet,
              children: <Widget>[
                Flexible(
                  child: Text(
                    vm.statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: visual.labelStrong.copyWith(
                      fontSize: decisionLabelSize,
                      fontWeight: FontWeight.w500,
                      color: tone.fg,
                    ),
                  ),
                ),
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(width: decisionCellGap),
                  Flexible(
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: visual.monoS.copyWith(
                        fontSize: decisionMetaSize,
                        color: tone.fg.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: decisionCellGap),
                Text(
                  '›',
                  style: visual.bodyS.copyWith(
                    fontSize: 12,
                    color: tone.fg.withValues(alpha: 0.6),
                  ),
                ),
              ],
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
class _StatusActionMenu extends StatefulWidget {
  const _StatusActionMenu({
    required this.vm,
    this.tablet = false,
    this.decisionMaxWidth = decisionCellMaxWidth,
  });

  final PayrollPersonRowVM vm;
  final bool tablet;

  /// `5n` · tope del control en este tramo (186 / 168 / 200).
  final double decisionMaxWidth;

  @override
  State<_StatusActionMenu> createState() => _StatusActionMenuState();
}

class _StatusActionMenuState extends State<_StatusActionMenu> {
  late final FocusNode _triggerFocus = FocusNode(
    debugLabel: 'Método de pago · ${widget.vm.name}',
  );

  @override
  void dispose() {
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final vm = widget.vm;
    final tablet = widget.tablet;
    final decisionMaxWidth = widget.decisionMaxWidth;
    // La forma con caret existe hoy para un único caso —«Sin método»—, y ése
    // no es una advertencia sino un **bloqueo**: sin método no se le puede
    // pagar a esa persona por ninguna vía. Heredar el tono del estado de la
    // fila pintaba de ámbar lo mismo que «falta confirmar», que sí se puede
    // pagar. `7a` lo dibuja en `danger` —`#33191A` / `#6E332F` / `#F08C82`,
    // leídos del canvas— y el mapa de uso del turno 9 lo dice con todas sus
    // letras: «danger: chip Sin método». Si algún día aparece un segundo caso
    // de menú, declara su tono aquí en vez de tomarlo prestado.
    final tone = visual.danger;
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
          onPressed: () async {
            await vm.onAction();
            if (mounted && _triggerFocus.canRequestFocus) {
              _triggerFocus.requestFocus();
            }
          },
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

        return _DecisionFocusRing(
          // Sin `Tooltip`, por la misma causa medida en `_PaidStatusAction`.
          child: Semantics(
            button: true,
            tooltip: '${vm.statusLabel}: abrir opciones',
            // `5c` pide `aria-haspopup=menu`. Flutter no publica ese flag;
            // lo equivalente y verdadero es anunciar que el control tiene
            // estado abierto/cerrado y en cuál está, que es justo lo que
            // `MenuAnchor` ya sabe.
            expanded: controller.isOpen,
            label: '${vm.statusLabel}. Abrir opciones',
            excludeSemantics: true,
            child: Material(
              key: ValueKey<String>('payroll-method-menu-${vm.name}'),
              color: tone.soft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PayrollTokens.rField),
                side: BorderSide(color: tone.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                focusNode: _triggerFocus,
                onTap: toggleMenu,
                mouseCursor: SystemMouseCursors.click,
                hoverColor: tone.fg.withValues(alpha: 0.08),
                focusColor: tone.fg.withValues(alpha: 0.12),
                child: _DecisionShell(
                  maxWidth: decisionMaxWidth,
                  tone: tone,
                  tablet: tablet,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        vm.statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.labelStrong.copyWith(
                          fontSize: decisionLabelSize,
                          fontWeight: FontWeight.w500,
                          color: tone.fg,
                        ),
                      ),
                    ),
                    // `7a`: el caret va detrás de un divisor de 1 con 7 de
                    // separación, no suelto ni dentro de un botón aparte.
                    const SizedBox(width: decisionCellGap),
                    Container(width: 1, height: 15, color: tone.border),
                    const SizedBox(width: 7),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 14,
                      color: tone.fg,
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
}

/// Disclosure por fila: horas, tarifa y pagos registrados. Payroll no edita
/// asistencia: la salida es "Ver asistencia de la semana ↗".
class _RowDisclosure extends StatelessWidget {
  const _RowDisclosure({
    required this.vm,
    required this.dense,
    this.footerReason,
  });

  /// Cuando la franja del pie ya dice ESTE motivo, el panel no se dibuja.
  final String? footerReason;
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
            // `5c`: el bloqueo nunca aparece sin su motivo, y la fila abierta
            // es donde vive el suyo cuando la franja del pie no puede hablar
            // por él —porque las filas bloqueadas no comparten razón—. Es una
            // nota en línea, sin overlay: la que sí se puede montar acá.
            if (vm.blockedReason.isNotEmpty && vm.blockedReason != footerReason)
              _DiscPanel(
                label: 'POR QUÉ NO SE PUEDE PAGAR',
                child: Text(
                  vm.blockedReason,
                  key:
                      ValueKey<String>('payroll-disclosure-blocked-${vm.name}'),
                  style: visual.bodyS.copyWith(fontSize: 11.5),
                ),
              ),
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
                  if (vm.destination case final destination?) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      destination.missing
                          ? 'Sin cuenta de destino registrada'
                          : destination.label!,
                      key: ValueKey<String>(
                        destination.missing
                            ? 'payroll-row-destination-missing'
                            : 'payroll-row-destination',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: visual.monoS.copyWith(
                        fontSize: 9.5,
                        color: destination.missing ? visual.warningFg : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (vm.shortcuts.isNotEmpty)
              _DiscPanel(
                label: 'ATAJOS',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: <Widget>[
                        for (final shortcut in vm.shortcuts)
                          _DiscShortcut(shortcut: shortcut),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 7a dibuja esta pista. Se escribe **porque la conducta
                    // existe**: `↑`/`↓` mueven el foco de fila y `↵` abre o
                    // cierra la enfocada. Una pista sin conducta es una
                    // promesa falsa, y así estaba antes.
                    Text(
                      'Una sola fila abierta a la vez · ↑↓ mueve · ↵ abre',
                      key: const ValueKey<String>('payroll-row-keyboard-hint'),
                      style: visual.monoS.copyWith(fontSize: 9.5),
                    ),
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
                  TextSpan(
                    text: 'El borrador parte de ',
                  ),
                  TextSpan(
                    text: 'Asistencias',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '. Puedes ajustar horas y tarifa aquí antes de '
                        'confirmar; la asistencia original no cambia.',
                  ),
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
    this.onEditDraft,
  });
  final PayrollWeekTotalsVM totals;
  final bool dense;
  final VoidCallback onConfirmWeek;
  final VoidCallback onNextAction;
  final VoidCallback? onEditDraft;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      // Identidad de producción: la barra de dinero es el owner del control de
      // decisión y hay que poder ubicarla sin adivinar su ancestro. El contrato
      // del esqueleto la buscaba por `ancestor(Container).first`, que se rompe
      // en cuanto alguien envuelve la fila (revisión de Codex, 2026-08-01).
      key: const ValueKey<String>('payroll-money-bar'),
      padding: EdgeInsets.symmetric(horizontal: dense ? 16 : 18),
      decoration: BoxDecoration(
        color: visual.surface,
        border: Border(top: BorderSide(color: visual.borderStrong)),
        boxShadow: visual.moneyBar,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // `5m` nota 04, literal: «A 834 la barra monetaria **se apila**:
          // cifra y razón arriba, botón de 46 abajo. Nada de un botón de 34
          // perdido en una esquina táctil.»
          //
          // **ADAPTADO a 48, y el frame gana igual (2026-08-02).** El `height`
          // de `PayrollAccentAction` dimensiona el `InkWell` entero, así que un
          // 46 es un objetivo táctil de 46 y **`F-06 · TOUCH` pide 48**. El 46
          // se descarta por la MISMA razón por la que `5l` descartó el 50: la
          // altura dibujada no manda sobre la regla táctil. Y acá la adaptación
          // es incluso más fiel que el número, porque lo que la nota persigue
          // es justamente que el botón **no** quede chico de tocar. Se usa el
          // owner canónico `touchMobile` (48); no se crea un estático nuevo —
          // el candado de arquitectura de tema prohíbe inventar valores
          // visuales fuera del pipeline de roles, y tenía razón.
          //
          // Esto estaba implementado… en `PayrollMoneyBar`, que **esta
          // superficie nunca monta** — la cola tiene su propia barra. Por eso
          // el handoff lo daba por hecho «sin confirmar en vivo» y al mirarlo
          // en la app seguía lado a lado. La regla vive ahora donde se pinta.
          //
          // Se cuentan las acciones **visibles**, y son dos estados reales y
          // excluyentes que emite `_totals()`: borrador → sólo `Confirmar`;
          // confirmada → sólo la acción-siguiente. Contar «confirm-only» era
          // apilar la mitad de los casos y dejar el otro en fila por un
          // fixture que el producto no puede producir.
          final visibleActions = <Widget Function()>[
            if (totals.showCommitAction)
              () => PayrollAccentAction(
                    actionKey: const ValueKey<String>('payroll-confirm-week'),
                    label: 'Confirmar semana',
                    semanticLabel: 'Confirmar semana',
                    onTap: onConfirmWeek,
                    enabled: totals.canConfirm,
                    height: PayrollTokens.touchMobile,
                    // El rótulo conserva el tamaño del CTA de la barra en su
                    // rama densa: no hay valor propio leído para el apilado y
                    // no se inventa uno.
                    fontSize: 11.5,
                  ),
            if (totals.nextActionLabel.isNotEmpty)
              () => PayrollAccentAction(
                    actionKey:
                        const ValueKey<String>('payroll-next-week-action'),
                    label: totals.nextActionLabel,
                    onTap: onNextAction,
                    height: PayrollTokens.touchMobile,
                    fontSize: 11.5,
                  ),
          ];
          final showEditDraft = totals.showCommitAction && onEditDraft != null;
          Widget editDraftAction({required double height}) => OutlinedButton(
                key: const ValueKey<String>('payroll-edit-draft'),
                onPressed: onEditDraft,
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, height),
                  foregroundColor: visual.inkMuted,
                  side: BorderSide(color: visual.borderStrong),
                ),
                child: const Text('Editar borrador'),
              );
          final stack = constraints.maxWidth < PayrollTokens.bpDesktop &&
              visibleActions.length == 1;
          if (stack) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text('FALTA',
                          style: visual.overline.copyWith(fontSize: 9)),
                      const SizedBox(width: 8),
                      Text(totals.remaining,
                          style: visual.numBar.copyWith(fontSize: 19)),
                      if (!totals.canConfirm &&
                          totals.blockedReason.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            totals.blockedReason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: visual.bodyS.copyWith(
                              fontSize: 9.5,
                              color: visual.warningFg,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (showEditDraft) ...<Widget>[
                    editDraftAction(height: PayrollTokens.touchMobile),
                    const SizedBox(height: 8),
                  ],
                  visibleActions.single(),
                ],
              ),
            );
          }
          return SizedBox(
            height: dense ? 54 : PayrollTokens.moneyBarH,
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
                if (showEditDraft) ...<Widget>[
                  editDraftAction(height: dense ? 30 : 32),
                  const SizedBox(width: 8),
                ],
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
                    actionKey:
                        const ValueKey<String>('payroll-next-week-action'),
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
        },
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
