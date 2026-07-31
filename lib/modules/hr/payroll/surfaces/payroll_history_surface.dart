import 'package:flutter/material.dart';

import '../theme/payroll_tokens.dart';

/// Historial moderno de nóminas pagadas/anuladas.
///
/// Es deliberadamente de solo lectura. La página dueña hidrata el comprobante
/// seleccionado antes de entregar [detail], de modo que ninguna cifra de pago
/// se presenta como autoritativa mientras esa lectura siga pendiente.
class PayrollHistorySurface extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
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
        final useCompactComposition = compact || constraints.maxWidth < 820;
        if (useCompactComposition) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CompactHistorySelector(
                weeks: weeks,
                selectedId: detail!.id,
                onSelect: onSelect,
              ),
              if (hasMore || isLoadingMore || paginationError != null)
                _HistoryLoadMore(
                  compact: true,
                  loading: isLoadingMore,
                  error: paginationError,
                  onPressed:
                      hasMore || paginationError != null ? onLoadMore : null,
                ),
              Expanded(
                child: _HistoryDetail(
                  detail: detail!,
                  compact: true,
                  isHydrating: isHydrating,
                  authoritativeReady: authoritativeReady,
                  error: error,
                  onRetry: onRetry,
                ),
              ),
            ],
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 286,
                child: _HistoryIndex(
                  weeks: weeks,
                  onSelect: onSelect,
                  hasMore: hasMore,
                  isLoadingMore: isLoadingMore,
                  paginationError: paginationError,
                  onLoadMore: onLoadMore,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HistoryDetail(
                  detail: detail!,
                  compact: false,
                  isHydrating: isHydrating,
                  authoritativeReady: authoritativeReady,
                  error: error,
                  onRetry: onRetry,
                ),
              ),
            ],
          ),
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

  /// De dónde salieron los pagos de esta semana. 5i lo pone al pie porque es
  /// la pregunta que sigue a «¿está pagada?»: quién y cómo la registró.
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
    this.hasEvidence = false,
    this.onOpenEvidence,
    this.initials,
    this.avatarColor,
    this.paymentCaption,
  });

  final String name;
  final String weekTotal;
  final String paid;
  final String advances;
  final String pending;
  final bool hasEvidence;
  final VoidCallback? onOpenEvidence;

  /// Identity of the person, so a historical week reads like the rest of the
  /// module instead of a bare table.
  final String? initials;
  final Color? avatarColor;

  /// How the money moved, in the bank's own words ("transf 14/07",
  /// "efectivo 12/07"). Absent when nothing was paid.
  final String? paymentCaption;
}

class _HistoryIndex extends StatelessWidget {
  const _HistoryIndex({
    required this.weeks,
    required this.onSelect,
    required this.hasMore,
    required this.isLoadingMore,
    required this.paginationError,
    required this.onLoadMore,
  });

  final List<PayrollHistoryWeekVM> weeks;
  final ValueChanged<String> onSelect;
  final bool hasMore;
  final bool isLoadingMore;
  final String? paginationError;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
            child: Row(
              children: [
                Text('HISTORIAL', style: visual.overline),
                const Spacer(),
                Text(
                  hasMore ? '${weeks.length}+' : '${weeks.length}',
                  style: visual.monoS,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: visual.border),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: weeks.length +
                  ((hasMore || isLoadingMore || paginationError != null)
                      ? 1
                      : 0),
              separatorBuilder: (_, __) => const SizedBox.shrink(),
              itemBuilder: (context, index) {
                if (index == weeks.length) {
                  return _HistoryLoadMore(
                    compact: false,
                    loading: isLoadingMore,
                    error: paginationError,
                    onPressed:
                        hasMore || paginationError != null ? onLoadMore : null,
                  );
                }
                final week = weeks[index];
                return _HistoryIndexRow(
                  week: week,
                  onTap: () => onSelect(week.id),
                );
              },
            ),
          ),
        ],
      ),
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
      padding: EdgeInsets.fromLTRB(
        compact ? 13 : 10,
        compact ? 0 : 10,
        compact ? 13 : 10,
        10,
      ),
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

class _CompactHistorySelector extends StatelessWidget {
  const _CompactHistorySelector({
    required this.weeks,
    required this.selectedId,
    required this.onSelect,
  });

  final List<PayrollHistoryWeekVM> weeks;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      color: visual.surface,
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
      child: DropdownButtonFormField<String>(
        key: const ValueKey('payroll-history-selector'),
        initialValue: selectedId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Semana histórica',
          labelStyle: visual.label,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          constraints:
              const BoxConstraints(minHeight: PayrollTokens.touchMobile),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PayrollTokens.rField),
            borderSide: BorderSide(color: visual.borderStrong),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PayrollTokens.rField),
            borderSide: BorderSide(color: visual.borderStrong),
          ),
        ),
        style: visual.bodyM,
        items: [
          for (final week in weeks)
            DropdownMenuItem<String>(
              value: week.id,
              child: Text(
                '${week.title} · ${week.range} · ${week.status}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (id) {
          if (id != null) onSelect(id);
        },
      ),
    );
  }
}

class _HistoryIndexRow extends StatelessWidget {
  const _HistoryIndexRow({required this.week, required this.onTap});

  final PayrollHistoryWeekVM week;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final tone = week.voided ? visual.danger : visual.success;
    return Semantics(
      button: true,
      selected: week.selected,
      label: '${week.title}, ${week.range}, ${week.amount}, ${week.status}',
      child: Material(
        key: ValueKey('payroll-history-week-${week.id}'),
        color: week.selected ? visual.surfaceSelected : visual.surface,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          hoverColor: visual.accentSoft.withValues(alpha: 0.55),
          focusColor: visual.accentSoft,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 11, 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: week.selected ? visual.accent : Colors.transparent,
                  width: 3,
                ),
                bottom: BorderSide(color: visual.border),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(week.title, style: visual.cardTitle),
                    ),
                    _HistoryStatus(label: week.status, tone: tone),
                  ],
                ),
                const SizedBox(height: 4),
                // 5i: rango Y personas en la misma línea. Sin el conteo, dos
                // semanas del mismo monto son indistinguibles en la lista.
                Text(
                  week.people == null
                      ? week.range
                      : '${week.range} · ${week.people}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: visual.monoS,
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        week.amount,
                        maxLines: 1,
                        style: visual.numRow,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text('total', style: visual.monoS.copyWith(fontSize: 9.5)),
                    const Spacer(),
                    // El saldo es lo único que distingue una semana cerrada de
                    // una que quedó a medias. Va a la derecha, y sólo grita
                    // cuando de verdad falta plata.
                    if (week.balance != null)
                      Text(
                        'saldo ${week.balance}',
                        maxLines: 1,
                        style: visual.monoS.copyWith(
                          fontSize: 10,
                          color:
                              week.settled ? visual.inkFaint : visual.warningFg,
                        ),
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

class _HistoryDetail extends StatelessWidget {
  const _HistoryDetail({
    required this.detail,
    required this.compact,
    required this.isHydrating,
    required this.authoritativeReady,
    required this.error,
    required this.onRetry,
  });

  final PayrollHistoryDetailVM detail;
  final bool compact;
  final bool isHydrating;
  final bool authoritativeReady;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final tone = detail.voided ? visual.danger : visual.success;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: compact
            ? BorderRadius.zero
            : BorderRadius.circular(PayrollTokens.rPanel),
        border: compact ? null : Border.all(color: visual.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 13 : 16,
              compact ? 12 : 14,
              compact ? 13 : 16,
              12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.title, style: visual.sectionTitle),
                      const SizedBox(height: 3),
                      Text(
                        '${detail.range} · ${detail.voucherNumber} · solo lectura',
                        style: visual.monoS,
                      ),
                    ],
                  ),
                ),
                _HistoryStatus(label: detail.status, tone: tone),
              ],
            ),
          ),
          Divider(height: 1, color: visual.border),
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
                    padding: EdgeInsets.all(compact ? 13 : 16),
                    children: compact
                        ? [
                            _HistoryTotals(detail: detail, compact: true),
                            const SizedBox(height: 12),
                            Text('PERSONAS', style: visual.overline),
                            const SizedBox(height: 7),
                            _CompactHistoryLedger(lines: detail.lines),
                          ]
                        : [
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

class _HistoryTotals extends StatelessWidget {
  const _HistoryTotals({required this.detail, required this.compact});

  final PayrollHistoryDetailVM detail;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    // 5i: la banda es la aritmética completa EN ORDEN — total, menos
    // anticipos, da a pagar; menos pagado, queda saldo. Antes eran cuatro
    // cifras sueltas en otro orden, y faltaba `A PAGAR`: había que hacer la
    // resta de cabeza para saber si la semana cerró bien.
    final children = [
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
      _HistoryFigure(label: 'PAGADO', value: detail.paid),
      _HistoryFigure(
        label: 'SALDO',
        value: detail.pending,
        // Un saldo abierto en una semana cerrada es lo único accionable de
        // esta pantalla; en cero no tiene por qué gritar.
        tone: detail.settled ? _FigureTone.plain : _FigureTone.warning,
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: visual.surfaceSunken,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.border),
      ),
      child: compact
          ? Wrap(
              spacing: 18,
              runSpacing: 12,
              children: [
                for (final child in children)
                  SizedBox(width: 132, child: child),
              ],
            )
          : Row(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  Expanded(child: children[index]),
                  if (index != children.length - 1) const SizedBox(width: 12),
                ],
              ],
            ),
    );
  }
}

/// De dónde salieron los pagos de la semana.
///
/// Cierra la pregunta que sigue a «¿está pagada?»: si la plata la registró
/// alguien a mano o la trajo una cartola. Es lectura, no un control.
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
/// lo que entra (anticipos), lo que se debe (a pagar) y lo que falta (saldo).
enum _FigureTone { plain, credit, accent, warning }

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
      _FigureTone.plain => visual.ink,
      _FigureTone.credit => visual.successFg,
      _FigureTone.accent => visual.accent,
      _FigureTone.warning => visual.warningFg,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: visual.overline.copyWith(
            color: tone == _FigureTone.accent ? visual.accent : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: visual.numRow.copyWith(color: color),
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
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.border),
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
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: '${line.name}, total ${line.weekTotal}, pagos ${line.paid}, '
          'anticipos ${line.advances}, saldo ${line.pending}',
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
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              border: divider
                  ? Border(
                      bottom: BorderSide(color: visual.border),
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: visual.cardTitle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      line.pending,
                      style: visual.numRow,
                    ),
                    if (onTap != null) ...<Widget>[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        size: 17,
                        color: visual.accent,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${line.weekTotal} total − ${line.paid} pagos − '
                  '${line.advances} anticipos',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: visual.monoS,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopHistoryLedger extends StatelessWidget {
  const _DesktopHistoryLedger({required this.lines});

  final List<PayrollHistoryLineVM> lines;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      key: const ValueKey('payroll-history-ledger'),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(13, 8, 13, 8),
            color: visual.surfaceSunken,
            child: Row(
              children: [
                Text('PERSONA Y PAGO', style: visual.overline),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _ledgerSummary(lines),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: visual.monoS.copyWith(fontSize: 9.5),
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < lines.length; index++)
            _HistoryPersonRow(
              line: lines[index],
              isFirst: index == 0,
            ),
        ],
      ),
    );
  }
}

/// Reads the ledger and states what the operator would otherwise count by
/// hand: how many people the week has and how many of them actually got paid.
String _ledgerSummary(List<PayrollHistoryLineVM> lines) {
  final withPayment = lines.where((line) => line.hasEvidence).length;
  final people = lines.length;
  if (people == 0) return 'sin personas en esta semana';
  final peopleLabel = people == 1 ? '1 persona' : '$people personas';
  if (withPayment == 0) return '$peopleLabel · ningún pago registrado';
  if (withPayment == people) return '$peopleLabel · todas con pago';
  return '$peopleLabel · $withPayment con pago';
}

/// Design t5 · frame 5i — one dominant figure per row.
///
/// The eye lands on what was actually paid; the arithmetic that explains it
/// (week total minus advances) drops to a monospaced subtitle, and the
/// remaining balance stays small at the right. A settled row offers its
/// evidence through a quiet chip instead of a competing action.
class _HistoryPersonRow extends StatelessWidget {
  const _HistoryPersonRow({required this.line, required this.isFirst});

  final PayrollHistoryLineVM line;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final onTap = line.hasEvidence ? line.onOpenEvidence : null;
    final settled = line.pending == r'$0';
    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: '${line.name}, pagado ${line.paid}, total ${line.weekTotal}, '
          'anticipos ${line.advances}, saldo ${line.pending}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: isFirst ? BorderSide.none : BorderSide(color: visual.border),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        child: Row(
          children: [
            Container(
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
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    line.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: visual.cardTitle.copyWith(fontSize: 12.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'total ${line.weekTotal} · anticipos ${line.advances}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: visual.monoS.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  line.paid,
                  style: visual.numRow.copyWith(
                    fontSize: 15,
                    color: onTap == null ? visual.inkMuted : visual.ink,
                  ),
                ),
                if (line.paymentCaption != null)
                  Text(
                    line.paymentCaption!,
                    style: visual.monoS.copyWith(fontSize: 9.5),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 92,
              child: Text(
                'saldo ${line.pending}',
                textAlign: TextAlign.right,
                style: visual.monoS.copyWith(
                  fontSize: 11,
                  color: settled ? visual.inkFaint : visual.warningFg,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // La columna de evidencia se dimensiona por su contenido más ancho
            // —el chip «Ver pago ›» con su padding e ícono—, no por un número
            // heredado: con 104 el chip se recortaba 19 px en cada fila pagada.
            SizedBox(
              width: 124,
              child: Align(
                alignment: Alignment.centerRight,
                child: onTap == null
                    ? Text(
                        'sin pago',
                        style: visual.monoS.copyWith(fontSize: 10),
                      )
                    : _HistoryEvidenceChip(
                        name: line.name,
                        onTap: onTap,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet success chip that opens the payment evidence popover.
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
        borderRadius: BorderRadius.circular(PayrollTokens.rPill),
        side: BorderSide(color: visual.successBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 28,
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
              const SizedBox(width: 3),
              Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: visual.successFg,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryStatus extends StatelessWidget {
  const _HistoryStatus({required this.label, required this.tone});

  final String label;
  final PayrollStateTone tone;

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
          fontSize: 9,
          color: tone.fg,
        ),
      ),
    );
  }
}
