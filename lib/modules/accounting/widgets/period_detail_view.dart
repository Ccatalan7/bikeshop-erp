import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_money_text.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_segmented.dart';
import '../../../shared/widgets/vb_skeleton.dart';
import '../models/dashboard_metrics.dart';
import '../models/period_detail_breakdown.dart';

/// Cómo se leen los movimientos del período.
enum PeriodDetailMode { movements, days }

/// Detalle de una barra del panorama financiero.
///
/// La jerarquía es la de la pregunta que trae al operador: primero **cuánto**
/// (el total, grande), después **cómo** (el desglose, que también filtra) y
/// recién abajo **cuáles** (los movimientos, por día). Un solo acento —el
/// primario del tema— marca lo elegido; el resto es tinta y gris. El verde y
/// el rojo quedan como un punto junto al título: dicen ingreso o gasto, no
/// pintan cada cifra.
///
/// La vista no guarda estado: el dueño (`_IncomeExpenseCardState`) decide el
/// período, el modo, el filtro y qué está abierto.
class PeriodDetailView extends StatelessWidget {
  const PeriodDetailView({
    super.key,
    required this.kind,
    required this.range,
    required this.today,
    required this.items,
    required this.isLoading,
    required this.hasError,
    required this.mode,
    required this.selectedBucketKey,
    required this.expandedDays,
    required this.onBack,
    required this.onPickRange,
    required this.onStepRange,
    required this.onModeChanged,
    required this.onBucketSelected,
    required this.onToggleDay,
    required this.onRetry,
    required this.canOpenItem,
    required this.onOpenItem,
    required this.openItemKey,
    required this.loadingItemKey,
    required this.expandedItemBuilder,
  });

  final PeriodDetailKind kind;
  final DateTimeRange range;
  final DateTime today;

  /// Todos los movimientos del período; null mientras llega la primera carga.
  final List<PeriodDetailItem>? items;
  final bool isLoading;
  final bool hasError;
  final PeriodDetailMode mode;
  final String? selectedBucketKey;
  final Set<DateTime> expandedDays;
  final VoidCallback onBack;
  final ValueChanged<BuildContext> onPickRange;

  /// −1 / +1. Null en una dirección = no hay hacia dónde ir.
  final ValueChanged<int> onStepRange;
  final ValueChanged<PeriodDetailMode> onModeChanged;
  final ValueChanged<String?> onBucketSelected;
  final ValueChanged<DateTime> onToggleDay;
  final VoidCallback onRetry;
  final bool Function(PeriodDetailItem item) canOpenItem;
  final ValueChanged<PeriodDetailItem> onOpenItem;
  final String? openItemKey;
  final String? loadingItemKey;

  /// Lo que se despliega bajo un movimiento abierto (la factura en línea).
  final Widget? Function(PeriodDetailItem item) expandedItemBuilder;

  static String itemKey(PeriodDetailItem item) =>
      '${item.sourceType}:${item.id}';

  @override
  Widget build(BuildContext context) {
    final allItems = items;
    final breakdown =
        allItems == null ? null : PeriodDetailBreakdown.of(allItems, kind);
    final selected = breakdown?.bucket(selectedBucketKey);
    final visibleItems = allItems == null || breakdown == null
        ? null
        : breakdown.filter(allItems, selected?.key);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 620;
        final roles = VinabikeThemeRoles.of(context);
        final tones = breakdown == null
            ? const <String, _Tone>{}
            : _bucketTones(roles, breakdown);
        final selectedTopKey = selected == null
            ? null
            : (breakdown!.parentOf(selected.key)?.key ?? selected.key);

        Widget body;
        if (hasError && allItems == null) {
          body = _ErrorState(onRetry: onRetry);
        } else if (allItems == null || breakdown == null) {
          body = const _ListSkeleton();
        } else if (allItems.isEmpty) {
          body = _EmptyState(kind: kind);
        } else if (mode == PeriodDetailMode.days) {
          body = _DaysTable(
            kind: kind,
            breakdown: breakdown,
            items: visibleItems!,
            selected: selected,
            expandedDays: expandedDays,
            narrow: narrow,
            tones: tones,
            onToggleDay: onToggleDay,
            rowBuilder: (item) =>
                _buildItemRow(context, breakdown, tones, item),
          );
        } else {
          body = _MovementsList(
            kind: kind,
            days: PeriodDetailBreakdown.groupByDay(visibleItems!),
            rowBuilder: (item) =>
                _buildItemRow(context, breakdown, tones, item),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              kind: kind,
              range: range,
              today: today,
              mode: mode,
              narrow: narrow,
              showModeToggle: allItems != null && allItems.isNotEmpty,
              onBack: onBack,
              onPickRange: onPickRange,
              onStepRange: onStepRange,
              onModeChanged: onModeChanged,
            ),
            const SizedBox(height: 8),
            if (breakdown != null && allItems!.isNotEmpty)
              _SummaryTabs(
                kind: kind,
                breakdown: breakdown,
                selected: selected,
                tones: tones,
                onSelected: onBucketSelected,
              )
            else if (allItems == null && !hasError)
              const _TabsSkeleton(),
            // La base de las pestañas es la mezcla del período en sus
            // colores; mientras carga, la misma línea es el progreso.
            SizedBox(
              height: 4,
              child: isLoading && allItems != null
                  ? const LinearProgressIndicator(minHeight: 4)
                  : breakdown != null && !breakdown.isEmpty
                      ? _MixBar(
                          breakdown: breakdown,
                          tones: tones,
                          selectedTopKey: selectedTopKey,
                        )
                      : Align(
                          alignment: Alignment.bottomCenter,
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: roles.hairline,
                          ),
                        ),
            ),
            Expanded(
              child: AnimatedOpacity(
                opacity: isLoading && allItems != null ? 0.55 : 1,
                duration: const Duration(milliseconds: 160),
                child: body,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildItemRow(
    BuildContext context,
    PeriodDetailBreakdown breakdown,
    Map<String, _Tone> tones,
    PeriodDetailItem item,
  ) {
    final key = itemKey(item);
    final isOpen = openItemKey == key;
    final expanded = isOpen ? expandedItemBuilder(item) : null;
    final openable = canOpenItem(item);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PeriodDetailItemRow(
          kind: kind,
          item: item,
          methodLabel: _methodLabel(breakdown, item),
          accent: tones[breakdown.topKeyOf(item)]?.ink,
          accentSoft: tones[breakdown.topKeyOf(item)]?.soft,
          isOpen: isOpen,
          isLoading: loadingItemKey == key,
          onTap: openable ? () => onOpenItem(item) : null,
        ),
        if (expanded != null) expanded,
      ],
    );
  }

  String? _methodLabel(PeriodDetailBreakdown breakdown, PeriodDetailItem item) {
    if (kind != PeriodDetailKind.incomeCash) return null;
    final child = breakdown.bucket(breakdown.childKeyOf(item));
    if (child != null) {
      return child.key == 'card:unknown' ? 'Tarjeta' : child.label;
    }
    final name = item.description.trim();
    return name.isEmpty ? null : name;
  }
}

// ---------------------------------------------------------------------------
// Período: etiqueta y paso
// ---------------------------------------------------------------------------

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isFirstOfMonth(DateTime day) => day.day == 1;

bool _isLastOfMonth(DateTime day) =>
    day.day == DateUtils.getDaysInMonth(day.year, day.month);

/// Un mes entero, o el mes en curso hasta hoy.
bool _isMonthShaped(DateTimeRange range, DateTime today) {
  final start = _dateOnly(range.start);
  final end = _dateOnly(range.end);
  if (!_isFirstOfMonth(start) ||
      start.year != end.year ||
      start.month != end.month) {
    return false;
  }
  return _isLastOfMonth(end) || DateUtils.isSameDay(end, today);
}

/// De lunes a domingo, o la semana en curso de lunes a hoy.
bool _isWeekShaped(DateTimeRange range, DateTime today) {
  final start = _dateOnly(range.start);
  final end = _dateOnly(range.end);
  if (start.weekday != DateTime.monday) return false;
  final days = end.difference(start).inDays;
  // Un lunes solo es un día, no «la semana hasta hoy».
  if (days == 0) return false;
  if (days == 6) return true;
  return days < 6 && DateUtils.isSameDay(end, today);
}

String _capitalize(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

String _shortDay(DateTime day, DateTime today, {bool withWeekday = true}) {
  final sameYear = day.year == today.year;
  final pattern = withWeekday
      ? (sameYear ? 'EEE d MMM' : 'EEE d MMM y')
      : (sameYear ? 'd MMM' : 'd MMM y');
  return _capitalize(
    DateFormat(pattern, 'es_CL').format(day).replaceAll('.', ''),
  );
}

/// «Hoy», «Ayer», «Sáb 10 oct», «Octubre 2026», «Semana del 6 oct»,
/// «28 sep – 3 oct».
String periodDetailRangeLabel(DateTimeRange range, DateTime today) {
  final day = _dateOnly(today);
  final start = _dateOnly(range.start);
  final end = _dateOnly(range.end);
  if (DateUtils.isSameDay(start, end)) {
    if (DateUtils.isSameDay(start, day)) return 'Hoy';
    if (DateUtils.isSameDay(start, day.subtract(const Duration(days: 1)))) {
      return 'Ayer';
    }
    return _shortDay(start, day);
  }
  if (_isMonthShaped(range, day)) {
    return _capitalize(DateFormat('MMMM y', 'es_CL').format(start));
  }
  if (_isWeekShaped(range, day)) {
    return 'Semana del ${_shortDay(start, day, withWeekday: false)}';
  }
  if (start.month == 1 &&
      start.day == 1 &&
      start.year == end.year &&
      ((end.month == 12 && end.day == 31) || DateUtils.isSameDay(end, day))) {
    return '${start.year}';
  }
  return '${_shortDay(start, day, withWeekday: false)} – '
      '${_shortDay(end, day, withWeekday: false)}';
}

/// El período vecino con la misma forma: el día, la semana o el mes anterior
/// o siguiente. Null si el siguiente empezaría después de hoy.
DateTimeRange? periodDetailStep(
  DateTimeRange range,
  int direction,
  DateTime today,
) {
  final day = _dateOnly(today);
  final start = _dateOnly(range.start);
  final end = _dateOnly(range.end);
  DateTimeRange next;
  if (_isMonthShaped(range, day)) {
    final first = DateTime(start.year, start.month + direction);
    next = DateTimeRange(
      start: first,
      end: DateTime(first.year, first.month + 1, 0),
    );
  } else if (_isWeekShaped(range, day)) {
    final monday = start.add(Duration(days: 7 * direction));
    next = DateTimeRange(
      start: monday,
      end: monday.add(const Duration(days: 6)),
    );
  } else {
    final length = end.difference(start).inDays + 1;
    final shifted = start.add(Duration(days: length * direction));
    next = DateTimeRange(
      start: shifted,
      end: shifted.add(Duration(days: length - 1)),
    );
  }
  if (next.start.isAfter(day)) return null;
  if (next.end.isAfter(day)) {
    next = DateTimeRange(start: next.start, end: day);
  }
  return next;
}

// ---------------------------------------------------------------------------
// Encabezado
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.kind,
    required this.range,
    required this.today,
    required this.mode,
    required this.narrow,
    required this.showModeToggle,
    required this.onBack,
    required this.onPickRange,
    required this.onStepRange,
    required this.onModeChanged,
  });

  final PeriodDetailKind kind;
  final DateTimeRange range;
  final DateTime today;
  final PeriodDetailMode mode;
  final bool narrow;
  final bool showModeToggle;
  final VoidCallback onBack;
  final ValueChanged<BuildContext> onPickRange;
  final ValueChanged<int> onStepRange;
  final ValueChanged<PeriodDetailMode> onModeChanged;

  String get _caption => switch (kind) {
        PeriodDetailKind.incomeCash => 'Cobros recibidos',
        PeriodDetailKind.incomeAccrual => 'Ventas emitidas · neto sin IVA',
        PeriodDetailKind.expenseCash => 'Pagos realizados',
        PeriodDetailKind.expenseAccrual => 'Gastos devengados',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final tone = kind.isIncome ? roles.success.accent : roles.danger.accent;

    final title = Row(
      children: [
        IconButton(
          onPressed: onBack,
          tooltip: 'Volver al gráfico',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 4),
        ExcludeSemantics(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Semantics(
            header: true,
            label: '${kind.isIncome ? 'Ingresos' : 'Gastos'}, $_caption',
            excludeSemantics: true,
            child: Text(
              kind.isIncome ? 'Ingresos' : 'Gastos',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        if (!narrow) ...[
          const SizedBox(width: 10),
          Flexible(
            child: ExcludeSemantics(
              child: Text(
                _caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: roles.neutral.accent,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    final stepper = _RangeStepper(
      label: periodDetailRangeLabel(range, today),
      canGoBack: periodDetailStep(range, -1, today) != null,
      canGoForward: periodDetailStep(range, 1, today) != null,
      expand: narrow,
      onPick: onPickRange,
      onStep: onStepRange,
    );

    final toggle = showModeToggle
        ? SizedBox(
            width: narrow
                ? (MediaQuery.sizeOf(context).width * 0.5).clamp(168.0, 216.0)
                : 196,
            child: VbSegmented<PeriodDetailMode>(
              groupLabel: 'Ver movimientos',
              value: mode,
              onChanged: onModeChanged,
              options: const [
                VbSegmentedOption(
                  value: PeriodDetailMode.movements,
                  label: 'Movimientos',
                ),
                VbSegmentedOption(
                  value: PeriodDetailMode.days,
                  label: 'Por día',
                ),
              ],
            ),
          )
        : null;

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: title),
              if (toggle != null) toggle,
            ],
          ),
          const SizedBox(height: 10),
          stepper,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 12),
        stepper,
        if (toggle != null) ...[
          const SizedBox(width: 12),
          toggle,
        ],
      ],
    );
  }
}

class _RangeStepper extends StatelessWidget {
  const _RangeStepper({
    required this.label,
    required this.canGoBack,
    required this.canGoForward,
    required this.expand,
    required this.onPick,
    required this.onStep,
  });

  final String label;
  final bool canGoBack;
  final bool canGoForward;
  final bool expand;
  final ValueChanged<BuildContext> onPick;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final touch = MediaQuery.sizeOf(context).width < 900;
    final height = touch ? 44.0 : 34.0;

    Widget arrow(IconData icon, String tooltip, bool enabled, int direction) {
      return SizedBox(
        width: touch ? 44 : 32,
        height: height,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          iconSize: 18,
          onPressed: enabled ? () => onStep(direction) : null,
          icon: Icon(icon),
        ),
      );
    }

    final picker = Builder(
      builder: (anchorContext) => Semantics(
        button: true,
        label: 'Período: $label. Cambiar período',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onPick(anchorContext),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: roles.neutral.accent,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: roles.neutral.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            arrow(
                Icons.chevron_left_rounded, 'Período anterior', canGoBack, -1),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            if (expand) Expanded(child: picker) else picker,
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            arrow(
              Icons.chevron_right_rounded,
              'Período siguiente',
              canGoForward,
              1,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Resumen: total y desglose
// ---------------------------------------------------------------------------

TextStyle _moneyStyle(double size, Color color, {FontWeight? weight}) {
  return GoogleFonts.ibmPlexMono(
    fontSize: size,
    fontWeight: weight ?? FontWeight.w700,
    height: 1.1,
    color: color,
    letterSpacing: size > 20 ? -0.8 : 0,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

String _percent(double part, double whole) {
  if (whole <= 0) return '0 %';
  final value = part / whole * 100;
  if (value > 0 && value < 1) return '<1 %';
  return '${value.round()} %';
}

/// Tono de un grupo: la tinta (punto, ícono, barra) y su fondo suave.
@immutable
class _Tone {
  const _Tone(this.ink, this.soft);

  final Color ink;
  final Color soft;
}

/// Cada grupo con su color de identidad del tema (azul, ciruela, verde,
/// ámbar). En ingresos el color es del método y no cambia de un período a
/// otro: tarjetas azul, transferencia ciruela, efectivo verde. «Otros» y «Sin
/// método» van en gris: no son una identidad.
Map<String, _Tone> _bucketTones(
  VinabikeThemeRoles roles,
  PeriodDetailBreakdown breakdown,
) {
  final palette = [
    _Tone(roles.avatarA, roles.avatarSoftA),
    _Tone(roles.avatarB, roles.avatarSoftB),
    _Tone(roles.avatarC, roles.avatarSoftC),
    _Tone(roles.avatarD, roles.avatarSoftD),
  ];
  final neutral = _Tone(roles.neutral.accent, roles.neutral.container);
  const preferred = {
    PeriodDetailBreakdown.cardKey: 0,
    'method:transfer': 1,
    'method:cash': 2,
  };
  final tones = <String, _Tone>{};
  final used = <int>{};
  if (breakdown.kind.isIncome) {
    for (final bucket in breakdown.buckets) {
      final index = preferred[bucket.key];
      if (index != null) {
        tones[bucket.key] = palette[index];
        used.add(index);
      }
    }
  }
  for (final bucket in breakdown.buckets) {
    if (tones.containsKey(bucket.key)) continue;
    if (bucket.key == PeriodDetailBreakdown.othersKey ||
        bucket.key == 'method:none') {
      tones[bucket.key] = neutral;
      continue;
    }
    final free = [
      for (var i = 0; i < palette.length; i++)
        if (!used.contains(i)) i,
    ];
    if (free.isEmpty) {
      tones[bucket.key] = neutral;
    } else {
      used.add(free.first);
      tones[bucket.key] = palette[free.first];
    }
  }
  return tones;
}

class _MixBar extends StatelessWidget {
  const _MixBar({
    required this.breakdown,
    required this.tones,
    required this.selectedTopKey,
  });

  final PeriodDetailBreakdown breakdown;
  final Map<String, _Tone> tones;
  final String? selectedTopKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = breakdown.buckets
        .fold<double>(0, (sum, bucket) => sum + bucket.amount.abs());
    if (total <= 0) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Row(
          children: [
            for (var i = 0; i < breakdown.buckets.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: (breakdown.buckets[i].amount.abs() / total * 1000)
                    .round()
                    .clamp(1, 1000),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  color: selectedTopKey == null ||
                          selectedTopKey == breakdown.buckets[i].key
                      ? tones[breakdown.buckets[i].key]?.ink ?? scheme.outline
                      : scheme.outlineVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// El resumen en una sola franja: el total y cada grupo del desglose como
/// pestañas que también filtran. Antes eran un bloque de cifra grande más una
/// tabla (≈190 px) que le dejaba cuatro filas a la lista; el dueño lo pidió
/// de vuelta chico («lo importante es la lista»). Débito y crédito aparecen
/// al elegir «Tarjetas», y también están en su tooltip.
class _SummaryTabs extends StatelessWidget {
  const _SummaryTabs({
    required this.kind,
    required this.breakdown,
    required this.selected,
    required this.tones,
    required this.onSelected,
  });

  final PeriodDetailKind kind;
  final PeriodDetailBreakdown breakdown;
  final PeriodDetailBucket? selected;
  final Map<String, _Tone> tones;
  final ValueChanged<String?> onSelected;

  String _countLabel(int count) {
    final noun = switch (kind) {
      PeriodDetailKind.incomeCash => count == 1 ? 'cobro' : 'cobros',
      PeriodDetailKind.incomeAccrual => count == 1 ? 'venta' : 'ventas',
      _ => count == 1 ? 'pago' : 'pagos',
    };
    return '$count $noun';
  }

  @override
  Widget build(BuildContext context) {
    final current = selected;
    final parent = current == null ? null : breakdown.parentOf(current.key);
    final selectedTop = parent ?? current;
    final children = selectedTop != null && selectedTop.children.length > 1
        ? selectedTop.children
        : const <PeriodDetailBucket>[];
    final average =
        breakdown.count == 0 ? 0.0 : breakdown.total / breakdown.count;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _SummaryTab(
                label: 'Total · ${_countLabel(breakdown.count)}',
                amount: breakdown.total,
                emphasis: true,
                selected: selectedTop == null,
                tooltip: breakdown.count > 1
                    ? 'Promedio ${VbMoneyText.formatClp(average)}'
                    : null,
                onTap: breakdown.isEmpty ? null : () => onSelected(null),
              ),
              for (final bucket in breakdown.buckets)
                _SummaryTab(
                  label: '${bucket.label} · '
                      '${_percent(bucket.amount, breakdown.total)}',
                  amount: bucket.amount,
                  tone: tones[bucket.key],
                  selected: selectedTop?.key == bucket.key,
                  tooltip: bucket.children.length > 1
                      ? [
                          for (final child in bucket.children)
                            '${child.label} ${VbMoneyText.formatClp(child.amount)}',
                        ].join(' · ')
                      : _countLabel(bucket.count),
                  onTap: () => onSelected(
                    selectedTop?.key == bucket.key ? null : bucket.key,
                  ),
                ),
            ],
          ),
        ),
        if (children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: children.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final child = children[index];
                  final isSelected = current?.key == child.key;
                  return _ChildChip(
                    bucket: child,
                    tone: tones[selectedTop!.key],
                    selected: isSelected,
                    onTap: () => onSelected(
                      isSelected ? selectedTop.key : child.key,
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({
    required this.label,
    required this.amount,
    required this.selected,
    required this.onTap,
    this.tone,
    this.emphasis = false,
    this.tooltip,
  });

  final String label;
  final double amount;
  final bool selected;
  final bool emphasis;
  final _Tone? tone;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final active = selected && onTap != null;
    final dot = tone?.ink;
    final fill =
        active ? (tone?.soft ?? roles.selectionContainer) : Colors.transparent;

    Widget tab = Semantics(
      button: onTap != null,
      selected: active,
      label: '$label, ${VbMoneyText.formatClp(amount)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 6),
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (dot != null) ...[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: dot,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        label,
                        maxLines: 1,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              active ? scheme.onSurface : roles.neutral.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    VbMoneyText.formatClp(amount),
                    style: _moneyStyle(
                      emphasis ? 19 : 15,
                      emphasis || active
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      weight: emphasis || active
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final message = tooltip;
    if (message != null) {
      tab = Tooltip(
        message: message,
        waitDuration: const Duration(milliseconds: 400),
        child: tab,
      );
    }
    return tab;
  }
}

class _ChildChip extends StatelessWidget {
  const _ChildChip({
    required this.bucket,
    required this.selected,
    required this.onTap,
    this.tone,
  });

  final PeriodDetailBucket bucket;
  final _Tone? tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final ink = scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: '${bucket.label}, ${VbMoneyText.formatClp(bucket.amount)}',
      excludeSemantics: true,
      child: Material(
        color: selected
            ? (tone?.soft ?? roles.selectionContainer)
            : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? (tone?.ink ?? roles.accentBorder)
                : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  bucket.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  VbMoneyText.formatClp(bucket.amount),
                  style: _moneyStyle(12, ink, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabsSkeleton extends StatelessWidget {
  const _TabsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const VbSkeletonGroup(
      child: Padding(
        padding: EdgeInsets.fromLTRB(4, 6, 0, 9),
        child: Row(
          children: [
            VbSkeleton.bar(width: 110, height: 28),
            SizedBox(width: 20),
            VbSkeleton.bar(width: 96, height: 28),
            SizedBox(width: 20),
            VbSkeleton.bar(width: 96, height: 28),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Movimientos
// ---------------------------------------------------------------------------

class _MovementsList extends StatelessWidget {
  const _MovementsList({
    required this.kind,
    required this.days,
    required this.rowBuilder,
  });

  final PeriodDetailKind kind;
  final List<PeriodDetailDay> days;
  final Widget Function(PeriodDetailItem item) rowBuilder;

  @override
  Widget build(BuildContext context) {
    // Una lista plana de encabezados de día y filas: el builder sólo arma lo
    // que se ve aunque el período tenga cientos de movimientos.
    final entries = <Object>[];
    for (final day in days) {
      entries.add(day);
      entries.addAll(day.items);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is PeriodDetailDay) {
          return _DayHeader(kind: kind, day: entry, first: index == 0);
        }
        return rowBuilder(entry as PeriodDetailItem);
      },
    );
  }
}

String _dayTitle(DateTime day) {
  final today = _dateOnly(DateTime.now());
  final label = _shortDay(day, today);
  if (DateUtils.isSameDay(day, today)) return 'Hoy · $label';
  if (DateUtils.isSameDay(day, today.subtract(const Duration(days: 1)))) {
    return 'Ayer · $label';
  }
  return label;
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.kind,
    required this.day,
    required this.first,
  });

  final PeriodDetailKind kind;
  final PeriodDetailDay day;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final count = day.items.length;
    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, first ? 12 : 18, 8, 6),
        child: Row(
          children: [
            Text(
              _dayTitle(day.date).toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count ${kind.isIncome ? (count == 1 ? 'cobro' : 'cobros') : (count == 1 ? 'pago' : 'pagos')}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: roles.neutral.accent,
              ),
            ),
            const Spacer(),
            Text(
              VbMoneyText.formatClp(day.total),
              style: _moneyStyle(12, roles.neutral.accent,
                  weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _itemIcon(PeriodDetailKind kind, PeriodDetailItem item) {
  if (kind == PeriodDetailKind.incomeCash) {
    final code = (item.paymentMethodCode ?? '').toLowerCase();
    final name = item.description.toLowerCase();
    if (code.startsWith('card') ||
        item.paymentInstrument != null && item.paymentInstrument != 'unknown') {
      return Icons.credit_card_rounded;
    }
    if (code == 'cash' || name.contains('efectivo')) {
      return Icons.payments_outlined;
    }
    if (code == 'transfer' || name.contains('transfer')) {
      return Icons.account_balance_outlined;
    }
    if (code == 'mercadopago' || name.contains('mercado')) {
      return Icons.account_balance_wallet_outlined;
    }
    if (code == 'check' || name.contains('cheque')) {
      return Icons.receipt_long_outlined;
    }
    return Icons.attach_money_rounded;
  }
  return switch (item.sourceType) {
    'sales_invoice' => Icons.receipt_long_outlined,
    'purchase_payment' => Icons.local_shipping_outlined,
    'employee_advance' => Icons.person_outline_rounded,
    'journal_entry' => Icons.menu_book_outlined,
    _ => Icons.receipt_outlined,
  };
}

/// Un movimiento: quién, qué documento y a qué hora, con qué método y
/// cuánto. La cifra es [VbMoneyText]; el método va como etiqueta neutra.
class PeriodDetailItemRow extends StatelessWidget {
  const PeriodDetailItemRow({
    super.key,
    required this.kind,
    required this.item,
    this.methodLabel,
    this.accent,
    this.accentSoft,
    this.isOpen = false,
    this.isLoading = false,
    this.onTap,
  });

  final PeriodDetailKind kind;
  final PeriodDetailItem item;
  final String? methodLabel;

  /// Color de identidad del grupo del movimiento (ícono teñido y etiqueta).
  /// Sin él la fila va en gris.
  final Color? accent;
  final Color? accentSoft;
  final bool isOpen;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);

    final title = switch (kind) {
      PeriodDetailKind.incomeCash ||
      PeriodDetailKind.incomeAccrual =>
        item.secondaryText.trim().isEmpty ? 'Cliente' : item.secondaryText,
      _ => item.description.trim().isNotEmpty
          ? item.description
          : item.documentNumber,
    };

    final at = item.occurredAt;
    final time = at == null || (at.hour == 0 && at.minute == 0)
        ? null
        : DateFormat('HH:mm').format(at);
    final subtitle = <String>[
      if (kind.isIncome && item.documentNumber.trim().isNotEmpty)
        item.documentNumber.trim(),
      if (!kind.isIncome && item.secondaryText.trim().isNotEmpty)
        item.secondaryText.trim(),
      if (!kind.isIncome && item.documentNumber.trim().isNotEmpty)
        item.documentNumber.trim(),
      if (time != null) time,
    ].join(' · ');

    return LayoutBuilder(
      builder: (context, constraints) {
        final showTag = methodLabel != null && constraints.maxWidth >= 460;
        final subtitleText = !showTag && methodLabel != null
            ? [methodLabel!, if (subtitle.isNotEmpty) subtitle].join(' · ')
            : subtitle;

        return Semantics(
          button: onTap != null,
          label: [
            title,
            if (methodLabel != null) methodLabel!,
            VbMoneyText.formatClp(item.amount),
            if (subtitle.isNotEmpty) subtitle,
          ].join(', '),
          excludeSemantics: true,
          child: Material(
            color: isOpen ? roles.selectionContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: accentSoft ?? scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          _itemIcon(kind, item),
                          size: 17,
                          color: accent ?? scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isOpen
                                    ? roles.onSelectionContainer
                                    : scheme.onSurface,
                              ),
                            ),
                            if (subtitleText.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitleText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: roles.neutral.accent,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (showTag) ...[
                        const SizedBox(width: 12),
                        _MethodTag(
                          label: methodLabel!,
                          fill: accentSoft,
                        ),
                      ],
                      const SizedBox(width: 14),
                      VbMoneyText(item.amount),
                      SizedBox(
                        width: 24,
                        child: onTap == null
                            ? null
                            : isLoading
                                ? const Center(
                                    child: SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.6,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    isOpen
                                        ? Icons.expand_less_rounded
                                        : Icons.chevron_right_rounded,
                                    size: 18,
                                    color: roles.neutral.accent,
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

class _MethodTag extends StatelessWidget {
  const _MethodTag({required this.label, this.fill});

  final String label;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill ?? scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Por día: el cuadre de caja
// ---------------------------------------------------------------------------

/// Una columna de la tabla por día.
class _DayColumn {
  const _DayColumn(this.label, this.matches, {this.tone});

  final String label;
  final bool Function(PeriodDetailItem item) matches;
  final Color? tone;
}

class _DaysTable extends StatelessWidget {
  const _DaysTable({
    required this.kind,
    required this.breakdown,
    required this.items,
    required this.selected,
    required this.expandedDays,
    required this.narrow,
    required this.tones,
    required this.onToggleDay,
    required this.rowBuilder,
  });

  final PeriodDetailKind kind;
  final PeriodDetailBreakdown breakdown;
  final List<PeriodDetailItem> items;
  final PeriodDetailBucket? selected;
  final Set<DateTime> expandedDays;
  final bool narrow;
  final Map<String, _Tone> tones;
  final ValueChanged<DateTime> onToggleDay;
  final Widget Function(PeriodDetailItem item) rowBuilder;

  /// Sin filtro, una columna por grupo (las tres más grandes y «Resto»); con
  /// «Tarjetas», una por débito y crédito; con un grupo hoja, sólo el total.
  List<_DayColumn> _columns() {
    final current = selected;
    if (current == null) {
      final buckets = breakdown.buckets;
      if (buckets.length <= 1) return const [];
      final shown = buckets.length > 4 ? buckets.take(3).toList() : buckets;
      final shownKeys = shown.map((bucket) => bucket.key).toSet();
      return [
        for (final bucket in shown)
          _DayColumn(
            bucket.label,
            (item) => breakdown.topKeyOf(item) == bucket.key,
            tone: tones[bucket.key]?.ink,
          ),
        if (buckets.length > 4)
          _DayColumn(
            'Resto',
            (item) => !shownKeys.contains(breakdown.topKeyOf(item)),
          ),
      ];
    }
    if (current.children.length > 1) {
      return [
        for (final child in current.children)
          _DayColumn(
            child.label,
            (item) => breakdown.childKeyOf(item) == child.key,
            tone: tones[current.key]?.ink,
          ),
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final days = PeriodDetailBreakdown.groupByDay(items);
    final columns = narrow ? const <_DayColumn>[] : _columns();
    final entries = <Object>[
      _DaysTableHeader(columns: columns),
    ];
    for (final day in days) {
      entries.add(day);
      if (expandedDays.contains(day.date)) entries.addAll(day.items);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              if (entry is Widget) return entry;
              if (entry is PeriodDetailDay) {
                return _DayTotalsRow(
                  kind: kind,
                  breakdown: breakdown,
                  day: entry,
                  columns: columns,
                  narrow: narrow,
                  expanded: expandedDays.contains(entry.date),
                  onTap: () => onToggleDay(entry.date),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(left: 22),
                child: rowBuilder(entry as PeriodDetailItem),
              );
            },
          ),
        ),
        _DaysTableFooter(columns: columns, items: items),
      ],
    );
  }
}

const double _dayColumnWidth = 116;

class _DaysTableHeader extends StatelessWidget {
  const _DaysTableHeader({required this.columns});

  final List<_DayColumn> columns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: roles.neutral.accent,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
    );
    return ExcludeSemantics(
      child: Container(
        height: 34,
        padding: const EdgeInsets.fromLTRB(30, 0, 8, 0),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: roles.hairline)),
        ),
        child: Row(
          children: [
            Expanded(child: Text('DÍA', style: style)),
            for (final column in columns)
              Container(
                width: _dayColumnWidth,
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (column.tone != null) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: column.tone,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        column.label.toUpperCase(),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style?.copyWith(letterSpacing: 0.3),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: _dayColumnWidth,
              child: Text('TOTAL', textAlign: TextAlign.right, style: style),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTotalsRow extends StatelessWidget {
  const _DayTotalsRow({
    required this.kind,
    required this.breakdown,
    required this.day,
    required this.columns,
    required this.narrow,
    required this.expanded,
    required this.onTap,
  });

  final PeriodDetailKind kind;
  final PeriodDetailBreakdown breakdown;
  final PeriodDetailDay day;
  final List<_DayColumn> columns;
  final bool narrow;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final count = day.items.length;
    final noun = kind.isIncome
        ? (count == 1 ? 'cobro' : 'cobros')
        : (count == 1 ? 'pago' : 'pagos');

    // En compacto no hay columnas: el reparto va como una línea bajo el día.
    String? split;
    if (narrow && !breakdown.isEmpty) {
      final parts = <String>[];
      for (final bucket in breakdown.buckets) {
        final amount = day.items
            .where((item) => breakdown.topKeyOf(item) == bucket.key)
            .fold<double>(0, (sum, item) => sum + item.amount);
        if (amount != 0) {
          parts.add('${bucket.label} ${VbMoneyText.formatClp(amount)}');
        }
      }
      if (parts.length > 1) split = parts.join(' · ');
    }

    return Semantics(
      button: true,
      expanded: expanded,
      label: '${_dayTitle(day.date)}, $count $noun, '
          '${VbMoneyText.formatClp(day.total)}',
      excludeSemantics: true,
      child: Material(
        color: expanded ? scheme.surfaceContainerLow : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: roles.hairline)),
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: roles.neutral.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _dayTitle(day.date),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: '   $count $noun',
                              style: TextStyle(color: roles.neutral.accent),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      if (split != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          split,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: roles.neutral.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                for (final column in columns)
                  SizedBox(
                    width: _dayColumnWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _SmallMoney(
                        day.items
                            .where(column.matches)
                            .fold<double>(0, (sum, item) => sum + item.amount),
                      ),
                    ),
                  ),
                SizedBox(
                  width: _dayColumnWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: VbMoneyText(day.total),
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

class _DaysTableFooter extends StatelessWidget {
  const _DaysTableFooter({required this.columns, required this.items});

  final List<_DayColumn> columns;
  final List<PeriodDetailItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = items.fold<double>(0, (sum, item) => sum + item.amount);
    return Container(
      height: 40,
      padding: const EdgeInsets.fromLTRB(30, 0, 8, 0),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'TOTAL DEL PERÍODO',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
          ),
          for (final column in columns)
            SizedBox(
              width: _dayColumnWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: _SmallMoney(
                  items
                      .where(column.matches)
                      .fold<double>(0, (sum, item) => sum + item.amount),
                  strong: true,
                ),
              ),
            ),
          SizedBox(
            width: _dayColumnWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: VbMoneyText(total),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cifra de una columna intermedia: la misma tipografía que [VbMoneyText],
/// un punto más chica y sin negrita, para que el total de la fila mande.
class _SmallMoney extends StatelessWidget {
  const _SmallMoney(this.amount, {this.strong = false});

  final double amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final scheme = Theme.of(context).colorScheme;
    final zero = amount.round() == 0;
    return Text(
      zero ? '—' : VbMoneyText.formatClp(amount),
      textAlign: TextAlign.right,
      softWrap: false,
      style: _moneyStyle(
        12.5,
        zero ? roles.neutral.accent : scheme.onSurface,
        weight: strong ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estados
// ---------------------------------------------------------------------------

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return VbSkeletonGroup(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 16, 8, 0),
        children: [
          for (var i = 0; i < 5; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: Row(
                children: [
                  VbSkeleton.block(size: 34),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        VbSkeleton.bar(width: 160),
                        SizedBox(height: 6),
                        VbSkeleton.bar(width: 96),
                      ],
                    ),
                  ),
                  VbSkeleton.bar(width: 72),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.kind});

  final PeriodDetailKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final text = switch (kind) {
      PeriodDetailKind.incomeCash => 'Sin cobros en este período',
      PeriodDetailKind.incomeAccrual => 'Sin ventas en este período',
      _ => 'Sin pagos en este período',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 28,
              color: roles.neutral.accent,
            ),
            const SizedBox(height: 10),
            Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Usa las flechas o el calendario para mirar otro.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: roles.neutral.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: VbNotice(
          tone: VbNoticeTone.danger,
          title: 'No se pudo cargar el detalle',
          body: 'Puede ser la conexión. Los datos no cambiaron.',
          action: VbButton(
            label: 'Reintentar',
            variant: VbButtonVariant.secondary,
            onPressed: onRetry,
          ),
        ),
      ),
    );
  }
}
