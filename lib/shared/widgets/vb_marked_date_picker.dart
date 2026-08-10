import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';
import '../utils/responsive_breakpoints.dart';
import 'vb_status_badge.dart';

/// The two operational states that `D-01` can expose on a calendar day.
///
/// The enum deliberately owns meaning rather than colour. The resolved
/// [VinabikeThemeRoles] decide how each state looks in every preset and
/// brightness.
enum VbMarkedDateStatus { pending, invoiced }

/// One visible and announced marker in [showVbMarkedDatePicker].
@immutable
class VbMarkedDateMarker {
  const VbMarkedDateMarker({required this.status, required this.label})
      : assert(label.length > 0, 'A date marker must name its state.');

  final VbMarkedDateStatus status;

  /// Human wording used by both the legend and the date cell semantics.
  ///
  /// Requiring this text prevents the semantic tone from becoming the only
  /// channel for the state.
  final String label;
}

/// `D-01` — canonical date picker with state markers inside calendar cells.
///
/// This is intentionally a composition of the already-published Material and
/// Viñabike owners rather than a new visual family:
///
/// * calendar surfaces, day states and typography come from
///   [DatePickerThemeData];
/// * every target is one [kMinInteractiveDimension] cell;
/// * marker geometry comes from Material [Badge];
/// * the visible, textual legend is `E-01` [VbStatusBadge]; and
/// * pending/invoiced colours come from the warning/success semantic roles.
///
/// No feature-local colour, radius, shadow, spacing or type value enters this
/// owner. On phone it recomposes as a full-screen task; tablet and desktop use
/// the theme-owned dialog.
Future<DateTime?> showVbMarkedDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required Map<DateTime, VbMarkedDateMarker> markers,
  DateTime? currentDate,
  SelectableDayPredicate? selectableDayPredicate,
  String? helpText,
  String? cancelText,
  String? confirmText,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final normalizedInitialDate = DateUtils.dateOnly(initialDate);
  final normalizedFirstDate = DateUtils.dateOnly(firstDate);
  final normalizedLastDate = DateUtils.dateOnly(lastDate);
  final normalizedCurrentDate =
      DateUtils.dateOnly(currentDate ?? DateTime.now());

  assert(
    !normalizedLastDate.isBefore(normalizedFirstDate),
    'lastDate must be on or after firstDate.',
  );
  assert(
    !normalizedInitialDate.isBefore(normalizedFirstDate) &&
        !normalizedInitialDate.isAfter(normalizedLastDate),
    'initialDate must be inside the selectable range.',
  );
  assert(
    selectableDayPredicate == null ||
        selectableDayPredicate(normalizedInitialDate),
    'initialDate must satisfy selectableDayPredicate.',
  );

  final normalizedMarkers = <DateTime, VbMarkedDateMarker>{
    for (final entry in markers.entries)
      DateUtils.dateOnly(entry.key): entry.value,
  };

  return showDialog<DateTime>(
    context: context,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    builder: (dialogContext) => _VbMarkedDatePickerDialog(
      initialDate: normalizedInitialDate,
      firstDate: normalizedFirstDate,
      lastDate: normalizedLastDate,
      currentDate: normalizedCurrentDate,
      markers: normalizedMarkers,
      selectableDayPredicate: selectableDayPredicate,
      helpText: helpText,
      cancelText: cancelText,
      confirmText: confirmText,
    ),
  );
}

enum _CalendarMode { day, year }

class _VbMarkedDatePickerDialog extends StatefulWidget {
  const _VbMarkedDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.markers,
    required this.selectableDayPredicate,
    required this.helpText,
    required this.cancelText,
    required this.confirmText,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;
  final Map<DateTime, VbMarkedDateMarker> markers;
  final SelectableDayPredicate? selectableDayPredicate;
  final String? helpText;
  final String? cancelText;
  final String? confirmText;

  @override
  State<_VbMarkedDatePickerDialog> createState() =>
      _VbMarkedDatePickerDialogState();
}

class _VbMarkedDatePickerDialogState extends State<_VbMarkedDatePickerDialog> {
  static const int _daysPerWeek = DateTime.daysPerWeek;
  static const int _visibleWeekRows = 6;

  late DateTime _selectedDate;
  late DateTime _displayedMonth;
  _CalendarMode _mode = _CalendarMode.day;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _displayedMonth = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
    );
  }

  DateTime _monthStart(DateTime date) => DateTime(date.year, date.month);

  DateTime _monthEnd(DateTime date) =>
      DateTime(date.year, date.month + 1).subtract(const Duration(days: 1));

  bool _monthOverlapsRange(DateTime month) =>
      !_monthEnd(month).isBefore(widget.firstDate) &&
      !_monthStart(month).isAfter(widget.lastDate);

  DateTime _addMonths(DateTime month, int delta) =>
      DateTime(month.year, month.month + delta);

  bool get _canGoToPreviousMonth =>
      _monthOverlapsRange(_addMonths(_displayedMonth, -1));

  bool get _canGoToNextMonth =>
      _monthOverlapsRange(_addMonths(_displayedMonth, 1));

  void _showPreviousMonth() {
    if (!_canGoToPreviousMonth) return;
    setState(() => _displayedMonth = _addMonths(_displayedMonth, -1));
  }

  void _showNextMonth() {
    if (!_canGoToNextMonth) return;
    setState(() => _displayedMonth = _addMonths(_displayedMonth, 1));
  }

  bool _isSelectable(DateTime date) =>
      !date.isBefore(widget.firstDate) &&
      !date.isAfter(widget.lastDate) &&
      (widget.selectableDayPredicate?.call(date) ?? true);

  void _selectDate(DateTime date) {
    if (!_isSelectable(date)) return;
    setState(() => _selectedDate = date);
  }

  DateTime _dateInYear(int year) {
    final month = _displayedMonth.month;
    final day = _selectedDate.day.clamp(
      1,
      DateUtils.getDaysInMonth(year, month),
    );
    final candidate = DateTime(year, month, day);
    if (candidate.isBefore(widget.firstDate)) return widget.firstDate;
    if (candidate.isAfter(widget.lastDate)) return widget.lastDate;
    return candidate;
  }

  void _selectYear(DateTime date) {
    final candidate = _dateInYear(date.year);
    setState(() {
      _displayedMonth = _monthStart(candidate);
      _mode = _CalendarMode.day;
      if (_isSelectable(candidate)) _selectedDate = candidate;
    });
  }

  void _cancel() => Navigator.of(context).pop();

  void _confirm() => Navigator.of(context).pop(_selectedDate);

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final datePickerTheme = theme.datePickerTheme;
    final helpText = widget.helpText ?? localizations.datePickerHelpText;
    final cancelText = widget.cancelText ?? localizations.cancelButtonLabel;
    final confirmText = widget.confirmText ?? localizations.okButtonLabel;
    final isPhone = MediaQuery.sizeOf(context).width <
        ResponsiveBreakpoints.phoneMaxExclusive;

    final calendar = SizedBox(
      width: kMinInteractiveDimension * _daysPerWeek,
      child: _CalendarPanel(
        selectedDate: _selectedDate,
        displayedMonth: _displayedMonth,
        firstDate: widget.firstDate,
        lastDate: widget.lastDate,
        currentDate: widget.currentDate,
        markers: widget.markers,
        selectableDayPredicate: widget.selectableDayPredicate,
        mode: _mode,
        canGoToPreviousMonth: _canGoToPreviousMonth,
        canGoToNextMonth: _canGoToNextMonth,
        onPreviousMonth: _showPreviousMonth,
        onNextMonth: _showNextMonth,
        onToggleMode: () => setState(() {
          _mode = _mode == _CalendarMode.day
              ? _CalendarMode.year
              : _CalendarMode.day;
        }),
        onSelectDate: _selectDate,
        onSelectYear: _selectYear,
      ),
    );

    if (isPhone) {
      return Dialog.fullscreen(
        child: Scaffold(
          backgroundColor:
              datePickerTheme.backgroundColor ?? theme.colorScheme.surface,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: datePickerTheme.headerBackgroundColor,
            foregroundColor: datePickerTheme.headerForegroundColor,
            title: Text(helpText),
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(child: calendar),
            ),
          ),
          persistentFooterButtons: [
            TextButton(onPressed: _cancel, child: Text(cancelText)),
            FilledButton(onPressed: _confirm, child: Text(confirmText)),
          ],
        ),
      );
    }

    return AlertDialog(
      backgroundColor: datePickerTheme.backgroundColor,
      surfaceTintColor: datePickerTheme.surfaceTintColor,
      shadowColor: datePickerTheme.shadowColor,
      elevation: datePickerTheme.elevation,
      shape: datePickerTheme.shape,
      title: Text(helpText),
      content: SingleChildScrollView(child: calendar),
      actions: [
        TextButton(onPressed: _cancel, child: Text(cancelText)),
        FilledButton(onPressed: _confirm, child: Text(confirmText)),
      ],
    );
  }
}

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({
    required this.selectedDate,
    required this.displayedMonth,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.markers,
    required this.selectableDayPredicate,
    required this.mode,
    required this.canGoToPreviousMonth,
    required this.canGoToNextMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToggleMode,
    required this.onSelectDate,
    required this.onSelectYear,
  });

  final DateTime selectedDate;
  final DateTime displayedMonth;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;
  final Map<DateTime, VbMarkedDateMarker> markers;
  final SelectableDayPredicate? selectableDayPredicate;
  final _CalendarMode mode;
  final bool canGoToPreviousMonth;
  final bool canGoToNextMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToggleMode;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<DateTime> onSelectYear;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final monthLabel = localizations.formatMonthYear(displayedMonth);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: kMinInteractiveDimension,
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  identifier: 'vb-marked-date-month-year',
                  button: true,
                  label: monthLabel,
                  onTap: onToggleMode,
                  child: ExcludeSemantics(
                    child: TextButton(
                      key: const ValueKey('vb-marked-date-month-year'),
                      onPressed: onToggleMode,
                      child: Text(monthLabel),
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('vb-marked-date-previous-month'),
                tooltip: localizations.previousMonthTooltip,
                onPressed: canGoToPreviousMonth ? onPreviousMonth : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                key: const ValueKey('vb-marked-date-next-month'),
                tooltip: localizations.nextMonthTooltip,
                onPressed: canGoToNextMonth ? onNextMonth : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        if (mode == _CalendarMode.year)
          SizedBox(
            height: kMinInteractiveDimension *
                _VbMarkedDatePickerDialogState._visibleWeekRows,
            child: YearPicker(
              key: const ValueKey('vb-marked-date-year-picker'),
              firstDate: firstDate,
              lastDate: lastDate,
              selectedDate: selectedDate,
              currentDate: currentDate,
              onChanged: onSelectYear,
            ),
          )
        else
          _MonthGrid(
            selectedDate: selectedDate,
            displayedMonth: displayedMonth,
            firstDate: firstDate,
            lastDate: lastDate,
            currentDate: currentDate,
            markers: markers,
            selectableDayPredicate: selectableDayPredicate,
            onSelectDate: onSelectDate,
          ),
        _MarkerLegend(markers: markers.values),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.selectedDate,
    required this.displayedMonth,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.markers,
    required this.selectableDayPredicate,
    required this.onSelectDate,
  });

  final DateTime selectedDate;
  final DateTime displayedMonth;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;
  final Map<DateTime, VbMarkedDateMarker> markers;
  final SelectableDayPredicate? selectableDayPredicate;
  final ValueChanged<DateTime> onSelectDate;

  bool _isSelectable(DateTime date) =>
      !date.isBefore(firstDate) &&
      !date.isAfter(lastDate) &&
      (selectableDayPredicate?.call(date) ?? true);

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final firstDayOffset = DateUtils.firstDayOffset(
      displayedMonth.year,
      displayedMonth.month,
      localizations,
    );
    final daysInMonth = DateUtils.getDaysInMonth(
      displayedMonth.year,
      displayedMonth.month,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: kMinInteractiveDimension,
          child: Row(
            children: List.generate(DateTime.daysPerWeek, (index) {
              final weekday = (localizations.firstDayOfWeekIndex + index) %
                  DateTime.daysPerWeek;
              return Expanded(
                child: Center(
                  child: Text(
                    localizations.narrowWeekdays[weekday],
                    style: Theme.of(context).datePickerTheme.weekdayStyle,
                  ),
                ),
              );
            }),
          ),
        ),
        SizedBox(
          height: kMinInteractiveDimension *
              _VbMarkedDatePickerDialogState._visibleWeekRows,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: DateTime.daysPerWeek,
              mainAxisExtent: kMinInteractiveDimension,
            ),
            itemCount: DateTime.daysPerWeek *
                _VbMarkedDatePickerDialogState._visibleWeekRows,
            itemBuilder: (context, index) {
              final day = index - firstDayOffset + 1;
              if (day < 1 || day > daysInMonth) {
                return const SizedBox.shrink();
              }
              final date = DateTime(
                displayedMonth.year,
                displayedMonth.month,
                day,
              );
              return _DayCell(
                date: date,
                selected: DateUtils.isSameDay(date, selectedDate),
                today: DateUtils.isSameDay(date, currentDate),
                enabled: _isSelectable(date),
                marker: markers[date],
                onPressed: () => onSelectDate(date),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.selected,
    required this.today,
    required this.enabled,
    required this.marker,
    required this.onPressed,
  });

  final DateTime date;
  final bool selected;
  final bool today;
  final bool enabled;
  final VbMarkedDateMarker? marker;
  final VoidCallback onPressed;

  String get _dateKey => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Set<WidgetState> _states(Set<WidgetState> interactiveStates) => {
        ...interactiveStates,
        if (selected) WidgetState.selected,
        if (!enabled) WidgetState.disabled,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pickerTheme = theme.datePickerTheme;
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final localizations = MaterialLocalizations.of(context);
    final semanticParts = <String>[
      localizations.formatFullDate(date),
      if (today) localizations.currentDateLabel,
      if (marker != null) marker!.label,
    ];

    final foreground = WidgetStateProperty.resolveWith<Color?>((states) {
      final resolvedStates = _states(states);
      final property = today
          ? pickerTheme.todayForegroundColor
          : pickerTheme.dayForegroundColor;
      return property?.resolve(resolvedStates) ??
          (resolvedStates.contains(WidgetState.selected)
              ? scheme.onPrimary
              : resolvedStates.contains(WidgetState.disabled)
                  ? roles.disabledForeground
                  : scheme.onSurface);
    });
    final background = WidgetStateProperty.resolveWith<Color?>((states) {
      final resolvedStates = _states(states);
      final property = today
          ? pickerTheme.todayBackgroundColor
          : pickerTheme.dayBackgroundColor;
      return property?.resolve(resolvedStates) ??
          (resolvedStates.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent);
    });
    final overlay = WidgetStateProperty.resolveWith<Color?>(
        (states) => pickerTheme.dayOverlayColor?.resolve(_states(states)));
    final shape = WidgetStateProperty.resolveWith<OutlinedBorder?>((states) =>
        pickerTheme.dayShape?.resolve(_states(states)) ?? const CircleBorder());
    final side = WidgetStateProperty.resolveWith<BorderSide?>(
        (states) => today ? pickerTheme.todayBorder : BorderSide.none);

    Widget label = Text(
      localizations.formatDecimal(date.day),
      style: pickerTheme.dayStyle,
    );
    if (marker != null) {
      final tone = marker!.status == VbMarkedDateStatus.pending
          ? roles.warning
          : roles.success;
      label = Badge(
        key: ValueKey('vb-marked-date-marker-$_dateKey'),
        backgroundColor: tone.accent,
        child: label,
      );
    }

    return Semantics(
      key: ValueKey('vb-marked-date-day-$_dateKey'),
      identifier: 'vb-marked-date-day-$_dateKey',
      button: true,
      enabled: enabled,
      selected: selected,
      label: semanticParts.join(', '),
      onTap: enabled ? onPressed : null,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: enabled ? onPressed : null,
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(
              Size.square(kMinInteractiveDimension),
            ),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: WidgetStatePropertyAll(pickerTheme.dayStyle),
            foregroundColor: foreground,
            backgroundColor: background,
            overlayColor: overlay,
            shape: shape,
            side: side,
          ),
          child: label,
        ),
      ),
    );
  }
}

class _MarkerLegend extends StatelessWidget {
  const _MarkerLegend({required this.markers});

  final Iterable<VbMarkedDateMarker> markers;

  @override
  Widget build(BuildContext context) {
    final byStatus = <VbMarkedDateStatus, VbMarkedDateMarker>{};
    for (final marker in markers) {
      byStatus.putIfAbsent(marker.status, () => marker);
    }
    if (byStatus.isEmpty) return const SizedBox.shrink();

    return Semantics(
      container: true,
      label: 'Leyenda del calendario',
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        runAlignment: WrapAlignment.center,
        children: [
          if (byStatus[VbMarkedDateStatus.pending] case final pending?)
            VbStatusBadge(
              key: const ValueKey('vb-marked-date-legend-pending'),
              label: pending.label,
              tone: VbStatusTone.warning,
            ),
          if (byStatus[VbMarkedDateStatus.invoiced] case final invoiced?)
            VbStatusBadge(
              key: const ValueKey('vb-marked-date-legend-invoiced'),
              label: invoiced.label,
              tone: VbStatusTone.success,
            ),
        ],
      ),
    );
  }
}
