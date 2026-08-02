import 'package:flutter/material.dart';

import '../theme/payroll_tokens.dart';

/// Anchos de las seis pistas de 7b, leídos del archivo de Design:
/// `minmax(200px,1fr) 160px 108px 104px 112px 132px`, gap 10, padding 16.
const double _colPerson = 200;
const double _colMethod = 160;
const double _colTotal = 108;
const double _colAdvances = 104;
const double _colPaid = 112;
const double _colAction = 132;
const double _colGap = 10;
const double _ledgerPadH = 16;

/// Historial de semanas pagadas o anuladas.
///
/// Aspecto: Design `Nóminas - Rediseño`, frame **`7b-historial-{pacific,
/// aubergine}`** (carpeta `handoff-t9`, turno 7), con `5i` del turno 5 como
/// referencia clara. Los dos frames dibujan la misma pantalla y **no coinciden
/// en la composición del libro de personas**: 5i dibuja tarjetas por persona y
/// 7b una tabla de seis pistas con `MÉTODO Y FECHA`. Gana 7b por ser el turno
/// posterior, y porque su tabla dice de dónde salió cada pago, que es la
/// pregunta que sigue a «¿está pagada?».
///
/// Es deliberadamente de solo lectura. La página dueña hidrata el comprobante
/// seleccionado antes de entregar [detail], de modo que ninguna cifra de pago
/// se presenta como autoritativa mientras esa lectura siga pendiente.
class PayrollHistorySurface extends StatefulWidget {
  const PayrollHistorySurface({
    super.key,
    required this.weeks,
    required this.detail,
    required this.compact,
    required this.isHydrating,
    required this.authoritativeReady,
    required this.error,
    required this.onSelect,
    required this.onRetry,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.paginationError,
    this.onLoadMore,
  });

  final List<PayrollHistoryWeekVM> weeks;
  final PayrollHistoryDetailVM? detail;
  final bool compact;
  final bool isHydrating;
  final bool authoritativeReady;
  final String? error;
  final ValueChanged<String> onSelect;
  final VoidCallback onRetry;
  final bool hasMore;
  final bool isLoadingMore;
  final String? paginationError;
  final VoidCallback? onLoadMore;

  /// Suma de las seis pistas de 7b más sus cinco gaps y el padding de la
  /// tarjeta.
  ///
  /// Bajo este ancho la pista `MÉTODO Y FECHA` no cabe **como columna** y baja
  /// a subtítulo de la persona. El número se deriva de los anchos leídos del
  /// archivo de Design, no de tantear en pantalla: el frame se dibujó sobre un
  /// canvas de 1340 y el workspace real de una ventana de 1360 es más angosto
  /// porque el rail y el cromo se lo comen antes.
  static const double methodColumnMinWidth = _colPerson +
      _colMethod +
      _colTotal +
      _colAdvances +
      _colPaid +
      _colAction +
      5 * _colGap +
      2 * _ledgerPadH;

  @override
  State<PayrollHistorySurface> createState() => _PayrollHistorySurfaceState();
}

class _PayrollHistorySurfaceState extends State<PayrollHistorySurface> {
  /// En compacto la superficie es un disclosure de dos pasos: primero **qué
  /// semana**, después **qué pasó en ella**.
  ///
  /// Design no publicó Historial compacto —5l y 5m son la cola—, así que la
  /// composición la aporta esta capa siguiendo `GUI_MOBILE_DESIGN_PRINCIPLES`:
  /// un objetivo por pantalla y retorno explícito. Lo que **no** se hace es
  /// meter 30 semanas paginadas en un select: `S-05` topa en ~7 opciones y
  /// `S-06 · VbSearchableSelect` todavía no existe en este repositorio.
  bool _compactShowsWeek = false;

  void _selectFromCompactIndex(String id) {
    setState(() => _compactShowsWeek = true);
    widget.onSelect(id);
  }

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final weeks = widget.weeks;
    final detail = widget.detail;
    if (weeks.isEmpty || detail == null) {
      return Center(
        child: Text(
          'Todavía no hay semanas pagadas o anuladas.',
          style: visual.bodyS,
        ),
      );
    }

    return LayoutBuilder(
      key: const ValueKey('payroll-history-surface'),
      builder: (context, constraints) {
        final useCompactComposition =
            widget.compact || constraints.maxWidth < 820;
        if (useCompactComposition) {
          return _compactShowsWeek
              ? _CompactWeekView(
                  detail: detail,
                  isHydrating: widget.isHydrating,
                  authoritativeReady: widget.authoritativeReady,
                  error: widget.error,
                  onRetry: widget.onRetry,
                  onBack: () => setState(() => _compactShowsWeek = false),
                )
              : _HistoryIndex(
                  key: const ValueKey('payroll-history-index-compact'),
                  weeks: weeks,
                  compact: true,
                  onSelect: _selectFromCompactIndex,
                  hasMore: widget.hasMore,
                  isLoadingMore: widget.isLoadingMore,
                  paginationError: widget.paginationError,
                  onLoadMore: widget.onLoadMore,
                );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 7b: la lista es un panel de 300 pegado al borde, separado por un
            // `divider`. No es una tarjeta flotante con su propio margen.
            SizedBox(
              width: 300,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: visual.surface,
                  border: Border(right: BorderSide(color: visual.border)),
                ),
                child: _HistoryIndex(
                  weeks: weeks,
                  compact: false,
                  onSelect: widget.onSelect,
                  hasMore: widget.hasMore,
                  isLoadingMore: widget.isLoadingMore,
                  paginationError: widget.paginationError,
                  onLoadMore: widget.onLoadMore,
                ),
              ),
            ),
            Expanded(
              child: _HistoryDetail(
                detail: detail,
                isHydrating: widget.isHydrating,
                authoritativeReady: widget.authoritativeReady,
                error: widget.error,
                onRetry: widget.onRetry,
              ),
            ),
          ],
        );
      },
    );
  }
}

@immutable
class PayrollHistoryWeekVM {
  const PayrollHistoryWeekVM({
    required this.id,
    required this.title,
    required this.range,
    required this.amount,
    required this.status,
    required this.voided,
    required this.selected,
    this.monthLabel,
    this.people,
    this.balance,
    this.settled = true,
  });

  final String id;
  final String title;
  final String range;
  final String amount;
  final String status;
  final bool voided;
  final bool selected;

  /// `julio 2026`. Encabeza el bloque de semanas de ese mes.
  ///
  /// Es lo que queda en pie del selector de mes de 5i: el RPC
  /// `get_payroll_history_page_v1` pagina por keyset sobre `period_end` y no
  /// acepta un mes, así que un selector filtraría sólo lo ya cargado y
  /// afirmaría que antes no hay nada. Agrupar sí es derivable del dato.
  final String? monthLabel;

  /// `4 personas`. Nulo cuando la semana todavía no hidrató sus líneas.
  final String? people;

  /// Saldo pendiente ya formateado, o nulo si aún no se conoce.
  final String? balance;
  final bool settled;
}

@immutable
class PayrollHistoryDetailVM {
  const PayrollHistoryDetailVM({
    required this.id,
    required this.title,
    required this.range,
    required this.voucherNumber,
    required this.status,
    required this.voided,
    required this.weekTotal,
    required this.payable,
    required this.paid,
    required this.advances,
    required this.pending,
    required this.settled,
    required this.lines,
    this.peopleLabel,
    this.closedNote,
    this.originNote,
    this.manualPayments = 0,
    this.statementPayments = 0,
  });

  final String id;
  final String title;
  final String range;
  final String voucherNumber;
  final String status;
  final bool voided;
  final String weekTotal;

  /// `total − anticipos`: lo que la semana debía en dinero. Sin esta cifra la
  /// banda obligaba a restar de cabeza para saber si la semana cerró bien.
  final String payable;
  final String paid;
  final String advances;
  final String pending;

  /// El saldo quedó en cero. Se decide en el modelo y no comparando strings.
  final bool settled;
  final List<PayrollHistoryLineVM> lines;

  /// `3 personas`.
  final String? peopleLabel;

  /// `registró Claudio Catalán · 29 jun 17:00`.
  ///
  /// 7b escribe «confirmó Rocío». Acá *confirmar* es el paso que deja la semana
  /// en `confirmed`, y estas semanas están `paid`: quien figura es quien
  /// **registró el pago** (`paid_by` / `paid_at`). Se conserva el hecho que el
  /// frame quería comunicar y se corrige el verbo.
  final String? closedNote;

  /// De dónde salieron los pagos de esta semana. Cierra la pregunta que sigue a
  /// «¿está pagada?»: si la plata la registró alguien a mano o la trajo una
  /// cartola.
  final String? originNote;
  final int manualPayments;
  final int statementPayments;
}

@immutable
class PayrollHistoryLineVM {
  const PayrollHistoryLineVM({
    required this.name,
    required this.weekTotal,
    required this.paid,
    required this.advances,
    required this.pending,
    this.settled = true,
    this.hasEvidence = false,
    this.onOpenEvidence,
    this.initials,
    this.avatarColor,
    this.methodAndDate,
  });

  final String name;
  final String weekTotal;
  final String paid;
  final String advances;
  final String pending;

  /// La línea quedó en cero. Se decide en el modelo, no comparando strings.
  final bool settled;
  final bool hasEvidence;
  final VoidCallback? onOpenEvidence;

  /// Identity of the person, so a historical week reads like the rest of the
  /// module instead of a bare table.
  final String? initials;
  final Color? avatarColor;

  /// `Transferencia · 07/07`, la pista `MÉTODO Y FECHA` de 7b. Nula cuando no
  /// se movió dinero: una fila sin pago no tiene método que declarar.
  final String? methodAndDate;
}

// ─────────────────────────────────────────────────────────────────────────────
// Índice de semanas
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryIndex extends StatelessWidget {
  const _HistoryIndex({
    super.key,
    required this.weeks,
    required this.compact,
    required this.onSelect,
    required this.hasMore,
    required this.isLoadingMore,
    required this.paginationError,
    required this.onLoadMore,
  });

  final List<PayrollHistoryWeekVM> weeks;
  final bool compact;
  final ValueChanged<String> onSelect;
  final bool hasMore;
  final bool isLoadingMore;
  final String? paginationError;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final showsTail = hasMore || isLoadingMore || paginationError != null;
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: weeks.length + (showsTail ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == weeks.length) {
          return _HistoryLoadMore(
            compact: compact,
            loading: isLoadingMore,
            error: paginationError,
            onPressed: hasMore || paginationError != null ? onLoadMore : null,
          );
        }
        final week = weeks[index];
        final previous = index == 0 ? null : weeks[index - 1];
        final month = week.monthLabel;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (month != null && month != previous?.monthLabel)
              _HistoryMonthHeader(label: month),
            _HistoryIndexRow(
              week: week,
              compact: compact,
              onTap: () => onSelect(week.id),
            ),
          ],
        );
      },
    );
  }
}

/// El residuo honesto del selector de mes de 5i.
class _HistoryMonthHeader extends StatelessWidget {
  const _HistoryMonthHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      key: ValueKey<String>('payroll-history-month-$label'),
      color: visual.surfaceSunken,
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
      child: Text(label.toUpperCase(), style: visual.overline),
    );
  }
}

class _HistoryLoadMore extends StatelessWidget {
  const _HistoryLoadMore({
    required this.compact,
    required this.loading,
    this.error,
    required this.onPressed,
  });

  final bool compact;
  final bool loading;
  final String? error;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      key: ValueKey<String>(
        compact
            ? 'payroll-history-load-more-compact'
            : 'payroll-history-load-more',
      ),
      color: visual.surface,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Semantics(
        liveRegion: error != null,
        label: error,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null) ...[
              Text(
                error!,
                key: const ValueKey<String>(
                  'payroll-history-pagination-error',
                ),
                style: visual.bodyS.copyWith(color: visual.dangerFg),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              height: PayrollTokens.touchMobile,
              child: OutlinedButton.icon(
                onPressed: loading ? null : onPressed,
                icon: loading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: visual.accent,
                        ),
                      )
                    : Icon(
                        error == null
                            ? Icons.expand_more
                            : Icons.refresh_rounded,
                        size: 18,
                      ),
                label: Text(
                  loading
                      ? 'Cargando semanas…'
                      : error == null
                          ? 'Cargar semanas anteriores'
                          : 'Reintentar cargar historial',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de semana de 7b: `min-height 62`, dos datos a la izquierda, la cifra y
/// el estado a la derecha, y la selección por barra de acento incrustada.
class _HistoryIndexRow extends StatelessWidget {
  const _HistoryIndexRow({
    required this.week,
    required this.compact,
    required this.onTap,
  });

  final PayrollHistoryWeekVM week;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final tone = _weekTone(visual, week);
    final balance = week.balance;
    return Semantics(
      button: true,
      selected: week.selected,
      label: '${week.title}, ${week.range}, ${week.amount}, ${week.status}',
      child: Material(
        key: ValueKey('payroll-history-week-${week.id}'),
        color:
            week.selected && !compact ? visual.surfaceSelected : visual.surface,
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          hoverColor: visual.accentSoft.withValues(alpha: 0.55),
          focusColor: visual.accentSoft,
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: week.selected && !compact
                      ? visual.accent
                      : Colors.transparent,
                  width: 3,
                ),
                bottom: BorderSide(color: visual.border),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        week.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.cardTitle,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        week.people == null
                            ? week.range
                            : '${week.range} · ${week.people}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.monoS,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(week.amount, maxLines: 1, style: visual.numRow),
                    const SizedBox(height: 3),
                    _HistoryStatusDot(label: week.status, tone: tone),
                    // El saldo es lo único que distingue una semana cerrada de
                    // una que quedó a medias, y sólo grita cuando falta plata.
                    if (balance != null && !week.settled) ...[
                      const SizedBox(height: 3),
                      Text(
                        'saldo $balance',
                        maxLines: 1,
                        style: visual.monoS.copyWith(color: visual.warningFg),
                      ),
                    ],
                  ],
                ),
                if (compact) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
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

PayrollStateTone _weekTone(
        PayrollVisualTokens visual, PayrollHistoryWeekVM w) =>
    w.voided ? visual.danger : (w.settled ? visual.success : visual.warning);

/// 7b: el estado se lee por **punto + rótulo**, no por píldora rellena. Su
/// razón está escrita en el propio frame: en una lista de cuatro filas, cuatro
/// píldoras rellenas pelean con las cifras.
class _HistoryStatusDot extends StatelessWidget {
  const _HistoryStatusDot({required this.label, required this.tone});

  final String label;
  final PayrollStateTone tone;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: tone.fg, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: visual.monoS.copyWith(
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: tone.fg,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detalle de la semana
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryDetail extends StatelessWidget {
  const _HistoryDetail({
    required this.detail,
    required this.isHydrating,
    required this.authoritativeReady,
    required this.error,
    required this.onRetry,
  });

  final PayrollHistoryDetailVM detail;
  final bool isHydrating;
  final bool authoritativeReady;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      color: visual.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isHydrating)
            LinearProgressIndicator(
              minHeight: 2,
              color: visual.accent,
              backgroundColor: visual.accentSoft,
            ),
          Expanded(
            child: !authoritativeReady
                ? _HistoryLoadingState(
                    loading: isHydrating,
                    error: error,
                    onRetry: onRetry,
                  )
                : ListView(
                    padding: const EdgeInsets.all(18),
                    children: <Widget>[
                      _HistoryHeader(detail: detail, compact: false),
                      const SizedBox(height: 14),
                      _HistoryTotals(detail: detail, compact: false),
                      const SizedBox(height: 12),
                      _DesktopHistoryLedger(lines: detail.lines),
                      if (detail.originNote != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _PaymentOriginNote(detail: detail),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// El encabezado de 7b: título con rango, la cifra dominante, y quién y cuándo.
///
/// El hueco superior derecho del frame lo ocupa `Reabrir semana`. Acá **no hay
/// botón**: `revert_payroll_to_draft` exige `status = 'confirmed'` y el
/// Historial sólo muestra `paid`/`voided`, así que ese botón fallaría en todas
/// las filas que esta pantalla puede mostrar. En su lugar va lo que el
/// encabezado necesitaba igual: el estado y el número de comprobante.
class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.detail, required this.compact});

  final PayrollHistoryDetailVM detail;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final tone = detail.voided
        ? visual.danger
        : (detail.settled ? visual.success : visual.warning);
    final subtitle = <String>[
      if (detail.peopleLabel != null) detail.peopleLabel!,
      if (detail.closedNote != null) detail.closedNote!,
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${detail.title} · ${detail.range}',
                style: visual.sectionTitle,
              ),
              const SizedBox(height: 4),
              Text(
                detail.weekTotal,
                key: const ValueKey<String>('payroll-history-week-total'),
                style: visual.numBar,
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: visual.monoS.copyWith(fontSize: 10.5),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _HistoryStatusDot(label: detail.status, tone: tone),
            const SizedBox(height: 4),
            Text(
              '${detail.voucherNumber} · solo lectura',
              textAlign: TextAlign.right,
              style: visual.monoS,
            ),
          ],
        ),
      ],
    );
  }
}

class _HistoryLoadingState extends StatelessWidget {
  const _HistoryLoadingState({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              CircularProgressIndicator(color: visual.accent)
            else
              Icon(
                Icons.error_outline,
                color: visual.dangerFg,
              ),
            const SizedBox(height: 12),
            Text(
              error ?? 'Cargando pagos registrados…',
              style: visual.bodyS,
              textAlign: TextAlign.center,
            ),
            if (!loading && error != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: PayrollTokens.touchMobile,
                child: OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('Reintentar'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// La banda de aritmética de 7b: **cinco celdas de igual peso** separadas por
/// `divider`, con `A PAGAR` en el acento a 16 y el resto a 14. `SALDO $0` va en
/// `inkFaint`: un cero resuelto no necesita color.
class _HistoryTotals extends StatelessWidget {
  const _HistoryTotals({required this.detail, required this.compact});

  final PayrollHistoryDetailVM detail;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final children = <_HistoryFigure>[
      _HistoryFigure(label: 'TOTAL', value: detail.weekTotal),
      _HistoryFigure(
        label: 'ANTICIPOS',
        value: detail.advances,
        tone: _FigureTone.credit,
      ),
      _HistoryFigure(
        label: 'A PAGAR',
        value: detail.payable,
        tone: _FigureTone.accent,
      ),
      _HistoryFigure(
        label: 'PAGADO',
        value: detail.paid,
        tone: _FigureTone.credit,
      ),
      _HistoryFigure(
        label: 'SALDO',
        value: detail.pending,
        // Un saldo abierto en una semana cerrada es lo único accionable de
        // esta pantalla; en cero no tiene por qué gritar.
        tone: detail.settled ? _FigureTone.faint : _FigureTone.warning,
      ),
    ];
    return Container(
      key: const ValueKey<String>('payroll-history-totals'),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: compact
          ? Column(
              children: [
                for (var i = 0; i < children.length; i += 2)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _cell(
                            visual,
                            children[i],
                            right: true,
                            bottom: i + 2 < children.length,
                          ),
                        ),
                        if (i + 1 < children.length)
                          Expanded(
                            child: _cell(
                              visual,
                              children[i + 1],
                              bottom: i + 2 < children.length,
                            ),
                          )
                        else
                          const Expanded(child: SizedBox.shrink()),
                      ],
                    ),
                  ),
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++)
                    Expanded(
                      child: _cell(
                        visual,
                        children[i],
                        right: i != children.length - 1,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _cell(
    PayrollVisualTokens visual,
    _HistoryFigure figure, {
    bool right = false,
    bool bottom = false,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        border: Border(
          right: right ? BorderSide(color: visual.border) : BorderSide.none,
          bottom: bottom ? BorderSide(color: visual.border) : BorderSide.none,
        ),
      ),
      child: figure,
    );
  }
}

/// De dónde salieron los pagos de la semana. Es lectura, no un control.
class _PaymentOriginNote extends StatelessWidget {
  const _PaymentOriginNote({required this.detail});

  final PayrollHistoryDetailVM detail;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    Widget chip(String label, {required bool statement}) {
      final tone = statement ? visual.accent : visual.inkMuted;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: statement ? visual.accentSoft : visual.surfaceSunken,
          borderRadius: BorderRadius.circular(PayrollTokens.rPill),
          border: Border.all(
            color: statement ? visual.accentBorder : visual.border,
          ),
        ),
        child: Text(
          label,
          style: visual.labelStrong.copyWith(fontSize: 10, color: tone),
        ),
      );
    }

    return Container(
      key: const ValueKey<String>('payroll-history-payment-origin'),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.border),
      ),
      child: Wrap(
        spacing: 9,
        runSpacing: 7,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            'Origen de los pagos de esta semana:',
            style: visual.bodyS.copyWith(fontSize: 11.5),
          ),
          if (detail.manualPayments > 0)
            chip(
              '${detail.manualPayments} '
              '${detail.manualPayments == 1 ? 'manual' : 'manuales'}',
              statement: false,
            ),
          if (detail.statementPayments > 0)
            chip(
              '${detail.statementPayments} por cartola',
              statement: true,
            ),
          Text(
            'Cada pago guarda quién y cómo lo registró',
            style: visual.monoS.copyWith(fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

/// Qué papel cumple una cifra de la banda. No es decoración: el color separa
/// lo que entra (anticipos y pagos), lo que se debe (a pagar) y lo que falta.
enum _FigureTone { plain, credit, accent, warning, faint }

class _HistoryFigure extends StatelessWidget {
  const _HistoryFigure({
    required this.label,
    required this.value,
    this.tone = _FigureTone.plain,
  });

  final String label;
  final String value;
  final _FigureTone tone;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final color = switch (tone) {
      _FigureTone.plain => visual.inkMuted,
      _FigureTone.credit => visual.successFg,
      _FigureTone.accent => visual.accent,
      _FigureTone.warning => visual.warningFg,
      _FigureTone.faint => visual.inkFaint,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: visual.overline.copyWith(fontSize: 9),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: visual.numRow.copyWith(
            fontSize: tone == _FigureTone.accent ? 16 : 14,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Libro de personas · 7b
// ─────────────────────────────────────────────────────────────────────────────

/// El chip `Ver pago` mide 26 de alto y **radio 7** en el archivo de Design.
/// Ese 7 no tiene token propio en `PayrollTokens` (la escalera salta de
/// `rControl 6` a `rField 8`); se implementa el valor leído y queda anotado
/// como hueco de la guía de componentes, no como preferencia local.
const double _rEvidenceChip = 7;
const double _hEvidenceChip = 26;

class _DesktopHistoryLedger extends StatelessWidget {
  const _DesktopHistoryLedger({required this.lines});

  final List<PayrollHistoryLineVM> lines;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final showMethodColumn =
            constraints.maxWidth >= PayrollHistorySurface.methodColumnMinWidth;
        return Container(
          key: const ValueKey('payroll-history-ledger'),
          decoration: BoxDecoration(
            color: visual.surface,
            borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
            border: Border.all(color: visual.borderStrong),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: BoxDecoration(
                  color: visual.surfaceSunken,
                  border: Border(bottom: BorderSide(color: visual.border)),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text('PERSONA', style: visual.overline)),
                    if (showMethodColumn) ...<Widget>[
                      const SizedBox(width: _colGap),
                      SizedBox(
                        width: _colMethod,
                        child: Text('MÉTODO Y FECHA', style: visual.overline),
                      ),
                    ],
                    const SizedBox(width: _colGap),
                    const _HeaderCell(width: _colTotal, label: 'TOTAL'),
                    const SizedBox(width: _colGap),
                    const _HeaderCell(
                      width: _colAdvances,
                      label: 'ANTICIPOS',
                    ),
                    const SizedBox(width: _colGap),
                    const _HeaderCell(width: _colPaid, label: 'PAGADO'),
                    const SizedBox(width: _colGap),
                    const SizedBox(width: _colAction),
                  ],
                ),
              ),
              for (var index = 0; index < lines.length; index++)
                _HistoryPersonRow(
                  line: lines[index],
                  isLast: index == lines.length - 1,
                  showMethodColumn: showMethodColumn,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.width, required this.label});

  final double width;
  final String label;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: visual.overline,
      ),
    );
  }
}

/// Design t9 · frame 7b — una fila de tabla por persona.
///
/// La pregunta que responde el historial es «¿de dónde salió esta plata?», así
/// que la fila declara método y fecha además de las tres cifras. El saldo
/// aparece **sólo cuando la fila quedó debiendo**: 7b dibuja una semana
/// cuadrada y por eso no tiene columna de saldo, pero esconder plata pendiente
/// sería una pantalla mintiendo sobre dinero.
class _HistoryPersonRow extends StatelessWidget {
  const _HistoryPersonRow({
    required this.line,
    required this.isLast,
    required this.showMethodColumn,
  });

  final PayrollHistoryLineVM line;
  final bool isLast;
  final bool showMethodColumn;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final onTap = line.hasEvidence ? line.onOpenEvidence : null;
    final method = line.methodAndDate;
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: '${line.name}, ${method ?? 'sin pago'}, '
          'total ${line.weekTotal}, anticipos ${line.advances}, '
          'pagado ${line.paid}, saldo ${line.pending}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: isLast ? BorderSide.none : BorderSide(color: visual.border),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  _HistoryAvatar(line: line),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          line.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: visual.bodyM.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        // Bajo el ancho de las seis pistas, MÉTODO Y FECHA baja
                        // a subtítulo en vez de desaparecer.
                        if (!showMethodColumn)
                          Text(
                            method ?? 'sin pago',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: visual.monoS.copyWith(
                              color: method == null
                                  ? visual.inkFaint
                                  : visual.inkMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showMethodColumn) ...<Widget>[
              const SizedBox(width: _colGap),
              SizedBox(
                width: _colMethod,
                child: Text(
                  method ?? 'sin pago',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: visual.monoS.copyWith(
                    fontSize: 11,
                    color: method == null ? visual.inkFaint : visual.inkMuted,
                  ),
                ),
              ),
            ],
            const SizedBox(width: _colGap),
            _NumberCell(
              width: _colTotal,
              value: line.weekTotal,
              style: visual.monoS.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: visual.inkMuted,
              ),
            ),
            const SizedBox(width: _colGap),
            _NumberCell(
              width: _colAdvances,
              value: line.advances,
              style: visual.monoS.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color:
                    line.advances == '—' ? visual.inkFaint : visual.successFg,
              ),
            ),
            const SizedBox(width: _colGap),
            SizedBox(
              width: _colPaid,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    line.paid,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: visual.numRow.copyWith(
                      fontSize: 13,
                      color:
                          line.hasEvidence ? visual.successFg : visual.inkFaint,
                    ),
                  ),
                  if (!line.settled)
                    Text(
                      'saldo ${line.pending}',
                      key: ValueKey<String>(
                        'payroll-history-open-balance-${line.name}',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: visual.monoS.copyWith(color: visual.warningFg),
                    ),
                ],
              ),
            ),
            const SizedBox(width: _colGap),
            SizedBox(
              width: _colAction,
              child: Align(
                alignment: Alignment.centerRight,
                // Sin pago no hay chip, y tampoco un rótulo que repita lo que
                // la pista de método ya dijo: en la app viva «sin pago» salía
                // dos veces en la misma fila.
                child: onTap == null
                    ? const SizedBox.shrink()
                    : _HistoryEvidenceChip(name: line.name, onTap: onTap),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberCell extends StatelessWidget {
  const _NumberCell({
    required this.width,
    required this.value,
    required this.style,
  });

  final double width;
  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _HistoryAvatar extends StatelessWidget {
  const _HistoryAvatar({required this.line});

  final PayrollHistoryLineVM line;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: line.avatarColor ?? visual.accentSoft,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        line.initials ?? '·',
        style: visual.bodyM.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: visual.shell,
        ),
      ),
    );
  }
}

/// Chip verde que abre la evidencia del pago. Su tríada es la misma en claro y
/// oscuro: `success.soft` de fondo, `success.border` de borde y `success.fg` de
/// texto, movida sólo por brightness.
class _HistoryEvidenceChip extends StatelessWidget {
  const _HistoryEvidenceChip({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Material(
      key: ValueKey<String>('payroll-history-evidence-$name'),
      color: visual.successSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_rEvidenceChip),
        side: BorderSide(color: visual.successBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: _hEvidenceChip,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ver pago',
                style: visual.labelStrong.copyWith(
                  fontSize: 10.5,
                  color: visual.successFg,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: visual.successFg.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compacto · sin frame de Design, compuesto acá
// ─────────────────────────────────────────────────────────────────────────────

/// Segundo paso del disclosure compacto: qué pasó en la semana elegida.
class _CompactWeekView extends StatelessWidget {
  const _CompactWeekView({
    required this.detail,
    required this.isHydrating,
    required this.authoritativeReady,
    required this.error,
    required this.onRetry,
    required this.onBack,
  });

  final PayrollHistoryDetailVM detail;
  final bool isHydrating;
  final bool authoritativeReady;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: visual.surface,
          child: InkWell(
            key: const ValueKey<String>('payroll-history-back-to-index'),
            onTap: onBack,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: PayrollTokens.touchMobile,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: visual.border)),
              ),
              child: Row(
                children: [
                  Icon(Icons.arrow_back, size: 18, color: visual.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Todas las semanas',
                    style: visual.labelStrong.copyWith(color: visual.accent),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isHydrating)
          LinearProgressIndicator(
            minHeight: 2,
            color: visual.accent,
            backgroundColor: visual.accentSoft,
          ),
        Expanded(
          child: !authoritativeReady
              ? _HistoryLoadingState(
                  loading: isHydrating,
                  error: error,
                  onRetry: onRetry,
                )
              : Container(
                  color: visual.canvas,
                  child: ListView(
                    padding: const EdgeInsets.all(13),
                    children: <Widget>[
                      _HistoryHeader(detail: detail, compact: true),
                      const SizedBox(height: 12),
                      _HistoryTotals(detail: detail, compact: true),
                      const SizedBox(height: 12),
                      Text('PERSONAS', style: visual.overline),
                      const SizedBox(height: 7),
                      _CompactHistoryLedger(lines: detail.lines),
                      if (detail.originNote != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _PaymentOriginNote(detail: detail),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _CompactHistoryLedger extends StatelessWidget {
  const _CompactHistoryLedger({required this.lines});

  final List<PayrollHistoryLineVM> lines;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      key: const ValueKey<String>('payroll-history-compact-ledger'),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (var index = 0; index < lines.length; index++)
            _CompactHistoryLine(
              line: lines[index],
              divider: index != lines.length - 1,
            ),
        ],
      ),
    );
  }
}

class _CompactHistoryLine extends StatelessWidget {
  const _CompactHistoryLine({
    required this.line,
    required this.divider,
  });

  final PayrollHistoryLineVM line;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final onTap = line.hasEvidence ? line.onOpenEvidence : null;
    final method = line.methodAndDate;
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: '${line.name}, ${method ?? 'sin pago'}, total ${line.weekTotal}, '
          'anticipos ${line.advances}, pagado ${line.paid}, '
          'saldo ${line.pending}',
      excludeSemantics: true,
      child: Material(
        color: visual.surface,
        child: InkWell(
          key: ValueKey<String>('payroll-history-evidence-${line.name}'),
          onTap: onTap,
          mouseCursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          hoverColor: visual.accentSoft.withValues(alpha: 0.55),
          focusColor: visual.accentSoft,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: PayrollTokens.touchMobile,
            ),
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
            decoration: BoxDecoration(
              border: divider
                  ? Border(bottom: BorderSide(color: visual.border))
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _HistoryAvatar(line: line),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        line.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.bodyM.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      line.paid,
                      style: visual.numRow.copyWith(
                        fontSize: 13,
                        color: line.hasEvidence
                            ? visual.successFg
                            : visual.inkFaint,
                      ),
                    ),
                    if (onTap != null) ...<Widget>[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        size: 17,
                        color: visual.successFg,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  method ?? 'sin pago',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: visual.monoS.copyWith(
                    color: method == null ? visual.inkFaint : visual.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'total ${line.weekTotal} · anticipos ${line.advances}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.monoS,
                      ),
                    ),
                    if (!line.settled)
                      Text(
                        'saldo ${line.pending}',
                        key: ValueKey<String>(
                          'payroll-history-open-balance-compact-${line.name}',
                        ),
                        style: visual.monoS.copyWith(color: visual.warningFg),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
