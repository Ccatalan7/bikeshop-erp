import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../themes/vinabike_theme_roles.dart';
import 'vb_button.dart';
import 'vb_overlay_surfaces.dart';

/// Un atajo del selector de período: «Hoy», «Este mes»…
@immutable
class VbDateRangePreset {
  const VbDateRangePreset({required this.label, required this.range});

  final String label;
  final DateTimeRange range;
}

/// Atajos de un informe que mira hacia atrás: nada termina después de hoy.
List<VbDateRangePreset> vbReportDateRangePresets(DateTime today) {
  final day = DateUtils.dateOnly(today);
  final weekStart = day.subtract(Duration(days: day.weekday - 1));
  DateTimeRange range(DateTime start, DateTime end) =>
      DateTimeRange(start: start, end: end);

  return [
    VbDateRangePreset(label: 'Hoy', range: range(day, day)),
    VbDateRangePreset(
      label: 'Ayer',
      range: range(
        day.subtract(const Duration(days: 1)),
        day.subtract(const Duration(days: 1)),
      ),
    ),
    VbDateRangePreset(label: 'Esta semana', range: range(weekStart, day)),
    VbDateRangePreset(
      label: 'Semana pasada',
      range: range(
        weekStart.subtract(const Duration(days: 7)),
        weekStart.subtract(const Duration(days: 1)),
      ),
    ),
    VbDateRangePreset(
      label: 'Este mes',
      range: range(DateTime(day.year, day.month), day),
    ),
    VbDateRangePreset(
      label: 'Mes anterior',
      range: range(
        DateTime(day.year, day.month - 1),
        DateTime(day.year, day.month, 0),
      ),
    ),
    VbDateRangePreset(
      label: 'Últimos 30 días',
      range: range(day.subtract(const Duration(days: 29)), day),
    ),
  ];
}

/// Selector de período del ERP: un día o un rango, con atajos.
///
/// Lo que lo separa del `showDateRangePicker` de Material, que el resto de la
/// app usaba como modal centrado:
///
/// * **hoy siempre se ve**: anillo y negrita, como cualquier calendario;
/// * **un clic elige un día** y ya se puede aplicar; el segundo clic, más
///   adelante, lo vuelve rango (antes había que tocar dos veces el mismo día);
/// * los **atajos** («Hoy», «Este mes»…) aplican de una;
/// * en escritorio es un popover anclado al botón y en compacto la hoja de
///   abajo, por el host dual [showVbSurface].
Future<DateTimeRange?> showVbDateRangePicker({
  required BuildContext anchorContext,
  required DateTimeRange initialRange,
  required DateTime firstDate,
  required DateTime lastDate,
  List<VbDateRangePreset> presets = const [],
  DateTime? today,
  String title = 'Elegir período',
}) {
  return showVbSurface<DateTimeRange>(
    anchorContext: anchorContext,
    title: title,
    minWidth: 300,
    maxWidth: presets.isEmpty ? 340 : 492,
    builder: (surfaceContext) => VbDateRangePanel(
      initialRange: initialRange,
      firstDate: firstDate,
      lastDate: lastDate,
      presets: presets,
      today: today,
      compact: vbSurfaceIsTouchHost(surfaceContext),
      onApply: (range) => Navigator.of(surfaceContext).pop(range),
      onCancel: () => Navigator.of(surfaceContext).pop(),
    ),
  );
}

/// El contenido del selector, sin superficie: calendario, atajos y acciones.
class VbDateRangePanel extends StatefulWidget {
  const VbDateRangePanel({
    super.key,
    required this.initialRange,
    required this.firstDate,
    required this.lastDate,
    required this.onApply,
    required this.onCancel,
    this.presets = const [],
    this.today,
    this.compact = false,
  });

  final DateTimeRange initialRange;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTimeRange> onApply;
  final VoidCallback onCancel;
  final List<VbDateRangePreset> presets;
  final DateTime? today;

  /// Hoja táctil: atajos en una fila de chips arriba y celdas de 44 px.
  final bool compact;

  @override
  State<VbDateRangePanel> createState() => _VbDateRangePanelState();
}

class _VbDateRangePanelState extends State<VbDateRangePanel> {
  late DateTime _start;
  late DateTime _end;
  late DateTime _visibleMonth;
  DateTime? _hovered;

  DateTime get _today => DateUtils.dateOnly(widget.today ?? DateTime.now());
  DateTime get _first => DateUtils.dateOnly(widget.firstDate);
  DateTime get _last => DateUtils.dateOnly(widget.lastDate);

  @override
  void initState() {
    super.initState();
    _start = _clamp(DateUtils.dateOnly(widget.initialRange.start));
    _end = _clamp(DateUtils.dateOnly(widget.initialRange.end));
    if (_end.isBefore(_start)) _end = _start;
    // Se abre en el mes donde termina lo elegido: para «octubre» es octubre,
    // con hoy a la vista.
    _visibleMonth = DateTime(_end.year, _end.month);
  }

  DateTime _clamp(DateTime day) {
    if (day.isBefore(_first)) return _first;
    if (day.isAfter(_last)) return _last;
    return day;
  }

  bool get _isSingleDay => DateUtils.isSameDay(_start, _end);

  void _selectDay(DateTime day) {
    setState(() {
      // Un rango completo o un día anterior al inicio empiezan de nuevo con
      // ese día solo; un día posterior a un día suelto cierra el rango.
      if (!_isSingleDay || day.isBefore(_start)) {
        _start = day;
        _end = day;
      } else {
        _end = day;
      }
    });
  }

  void _moveMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  VbDateRangePreset? get _matchingPreset {
    for (final preset in widget.presets) {
      if (DateUtils.isSameDay(preset.range.start, _start) &&
          DateUtils.isSameDay(preset.range.end, _end)) {
        return preset;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final calendar = _buildCalendar(context);
    final footer = _buildFooter(context);
    final presets = widget.presets
        .where((preset) => !preset.range.start.isAfter(_last))
        .toList(growable: false);

    if (widget.compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(13, 4, 13, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (presets.isNotEmpty) ...[
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: presets.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) => _PresetChip(
                    preset: presets[index],
                    selected: identical(_matchingPreset, presets[index]),
                    onTap: () => widget.onApply(presets[index].range),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            calendar,
            const SizedBox(height: 12),
            footer,
          ],
        ),
      );
    }

    final roles = VinabikeThemeRoles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (presets.isNotEmpty) ...[
                  SizedBox(
                    width: 136,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final preset in presets)
                          _PresetRow(
                            preset: preset,
                            selected: identical(_matchingPreset, preset),
                            onTap: () => widget.onApply(preset.range),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  VerticalDivider(width: 1, color: roles.hairline),
                  const SizedBox(width: 14),
                ],
                Expanded(child: calendar),
              ],
            ),
          ),
          const SizedBox(height: 12),
          footer,
        ],
      ),
    );
  }

  Widget _buildCalendar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final monthLabel = DateFormat('MMMM yyyy', 'es_CL').format(_visibleMonth);
    final canGoBack = DateTime(_visibleMonth.year, _visibleMonth.month).isAfter(
      DateTime(_first.year, _first.month),
    );
    final canGoForward =
        DateTime(_visibleMonth.year, _visibleMonth.month).isBefore(
      DateTime(_last.year, _last.month),
    );
    final cellHeight = widget.compact ? 44.0 : 36.0;
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month);
    final leading = firstOfMonth.weekday - 1;
    final daysInMonth =
        DateUtils.getDaysInMonth(_visibleMonth.year, _visibleMonth.month);
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '${monthLabel[0].toUpperCase()}${monthLabel.substring(1)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Mes anterior',
              visualDensity: VisualDensity.compact,
              onPressed: canGoBack ? () => _moveMonth(-1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              tooltip: 'Mes siguiente',
              visualDensity: VisualDensity.compact,
              onPressed: canGoForward ? () => _moveMonth(1) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final label in const ['L', 'M', 'X', 'J', 'V', 'S', 'D'])
              Expanded(
                child: ExcludeSemantics(
                  child: Center(
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: roles.neutral.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var row = 0; row < cellCount ~/ 7; row++)
          SizedBox(
            height: cellHeight,
            child: Row(
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: _buildCell(
                      context,
                      row * 7 + column - leading + 1,
                      daysInMonth,
                      scheme,
                      roles,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCell(
    BuildContext context,
    int dayNumber,
    int daysInMonth,
    ColorScheme scheme,
    VinabikeThemeRoles roles,
  ) {
    if (dayNumber < 1 || dayNumber > daysInMonth) return const SizedBox();
    final theme = Theme.of(context);
    final day = DateTime(_visibleMonth.year, _visibleMonth.month, dayNumber);
    final enabled = !day.isBefore(_first) && !day.isAfter(_last);
    final isStart = DateUtils.isSameDay(day, _start);
    final isEnd = DateUtils.isSameDay(day, _end);
    final isEdge = isStart || isEnd;
    final inRange = day.isAfter(_start) && day.isBefore(_end);
    final isToday = DateUtils.isSameDay(day, _today);
    final hovered = _hovered != null && DateUtils.isSameDay(day, _hovered);

    // La banda del rango va de borde a borde de la celda; el inicio y el fin
    // la cortan por la mitad para que el círculo quede encima.
    final band = !_isSingleDay && (inRange || isEdge);
    final bandColor = roles.selectionContainer;

    final textColor = !enabled
        ? roles.disabledForeground
        : isEdge
            ? scheme.onPrimary
            : inRange
                ? roles.onSelectionContainer
                : scheme.onSurface;

    final label = DateFormat("EEEE d 'de' MMMM", 'es_CL').format(day);

    return Semantics(
      button: true,
      enabled: enabled,
      selected: isEdge || inRange,
      label: isToday ? '$label, hoy' : label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: enabled ? (_) => setState(() => _hovered = day) : null,
        onExit: enabled ? (_) => setState(() => _hovered = null) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => _selectDay(day) : null,
          // La celda entera es el Stack: la banda del rango cruza de borde a
          // borde y el círculo va centrado encima. Sin `expand` y sin
          // `stretch`, las cajas de color medían cero de alto y la banda no
          // se veía.
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (band)
                Positioned.fill(
                  top: 3,
                  bottom: 3,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ColoredBox(
                          color:
                              inRange || isEnd ? bandColor : Colors.transparent,
                        ),
                      ),
                      Expanded(
                        child: ColoredBox(
                          color: inRange || isStart
                              ? bandColor
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isEdge
                            ? scheme.primary
                            : hovered && !inRange
                                ? scheme.surfaceContainerHigh
                                : null,
                        border: isToday && !isEdge
                            ? Border.all(color: scheme.primary, width: 1.5)
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '$dayNumber',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isToday && !isEdge && enabled
                                ? scheme.primary
                                : textColor,
                            fontWeight: isEdge || isToday
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final days = _end.difference(_start).inDays + 1;
    final summary = _isSingleDay
        ? _dayLabel(_start)
        : '${_dayLabel(_start)} – ${_dayLabel(_end)} · $days días';

    return Row(
      children: [
        Expanded(
          child: Text(
            summary,
            maxLines: 2,
            style: theme.textTheme.bodySmall?.copyWith(
              color: roles.neutral.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        VbButton(
          label: 'Cancelar',
          variant: VbButtonVariant.text,
          onPressed: widget.onCancel,
        ),
        const SizedBox(width: 6),
        VbButton(
          label: 'Aplicar',
          onPressed: () => widget.onApply(
            DateTimeRange(start: _start, end: _end),
          ),
        ),
      ],
    );
  }

  String _dayLabel(DateTime day) {
    if (DateUtils.isSameDay(day, _today)) return 'Hoy';
    final pattern = day.year == _today.year ? 'EEE d MMM' : 'EEE d MMM y';
    final text = DateFormat(pattern, 'es_CL').format(day).replaceAll('.', '');
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final VbDateRangePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? roles.selectionContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              preset.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected
                    ? roles.onSelectionContainer
                    : theme.colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final VbDateRangePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? roles.selectionContainer : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? roles.accentBorder : theme.colorScheme.outline,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                preset.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: selected
                      ? roles.onSelectionContainer
                      : theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
