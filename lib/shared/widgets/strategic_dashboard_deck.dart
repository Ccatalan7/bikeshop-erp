import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../modules/accounting/widgets/accounting_dashboard_section.dart';
import '../models/strategic_dashboard_metrics.dart';
import '../services/database_service.dart';
import '../services/strategic_dashboard_service.dart';

class StrategicDashboardDeck extends StatefulWidget {
  const StrategicDashboardDeck({super.key});

  @override
  State<StrategicDashboardDeck> createState() => _StrategicDashboardDeckState();
}

class _StrategicDashboardDeckState extends State<StrategicDashboardDeck> {
  static const _titles = <String>[
    'Panorama financiero',
    'Flujo del taller',
    'Capacidad y servicio',
    'Productos y rotación',
  ];

  static const _subtitles = <String>[
    'Ingresos, gastos y principales salidas de caja',
    'Desde la recepción hasta la entrega, con la muestra visible',
    'Horario, asistencia, horas imputadas y contribución de mano de obra',
    'Entrada por productos versus servicios y movimiento de inventario',
  ];

  final PageController _controller = PageController();
  int _page = 0;
  StrategicDashboardPeriodPreset _periodPreset =
      StrategicDashboardPeriodPreset.last90Days;
  late StrategicDashboardDateWindow _dateWindow;
  StrategicDashboardMetrics? _metrics;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _dateWindow = StrategicDashboardDateWindow.forPreset(
      _periodPreset,
      today: StrategicDashboardService.businessToday(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMetrics());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMetrics() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = StrategicDashboardService(
        context.read<DatabaseService>(),
      );
      final metrics = await service.load(window: _dateWindow);
      if (!mounted) return;
      setState(() {
        _metrics = metrics;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  String get _periodLabel {
    switch (_periodPreset) {
      case StrategicDashboardPeriodPreset.thisMonth:
        return 'Este mes';
      case StrategicDashboardPeriodPreset.previousMonth:
        return 'Mes anterior';
      case StrategicDashboardPeriodPreset.last30Days:
        return 'Últimos 30 días';
      case StrategicDashboardPeriodPreset.last90Days:
        return 'Últimos 90 días';
      case StrategicDashboardPeriodPreset.last12Months:
        return 'Últimos 12 meses';
      case StrategicDashboardPeriodPreset.custom:
        final start = DateFormat('d MMM', 'es').format(_dateWindow.startDate);
        final end = DateFormat('d MMM', 'es').format(_dateWindow.endDate);
        return '$start – $end';
    }
  }

  Future<void> _selectPeriod(
    StrategicDashboardPeriodPreset preset,
  ) async {
    StrategicDashboardDateWindow window;
    if (preset == StrategicDashboardPeriodPreset.custom) {
      final today = StrategicDashboardService.businessToday();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(today.year - 5),
        lastDate: today,
        initialDateRange: DateTimeRange(
          start: _dateWindow.startDate,
          end: _dateWindow.endDate,
        ),
        initialEntryMode: DatePickerEntryMode.calendarOnly,
        locale: const Locale('es'),
        helpText: 'Selecciona el período',
        cancelText: 'Cancelar',
        saveText: 'Aplicar',
        builder: (context, child) {
          final theme = Theme.of(context);
          return Theme(
            data: theme.copyWith(
              datePickerTheme: theme.datePickerTheme.copyWith(
                headerBackgroundColor: theme.colorScheme.primary,
                headerForegroundColor: theme.colorScheme.onPrimary,
                rangeSelectionBackgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.14),
                rangePickerElevation: 14,
                rangePickerShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked == null || !mounted) return;
      window = StrategicDashboardDateWindow.custom(
        picked.start,
        picked.end,
      );
    } else {
      window = StrategicDashboardDateWindow.forPreset(
        preset,
        today: StrategicDashboardService.businessToday(),
      );
    }

    if (!mounted) return;
    setState(() {
      _periodPreset = preset;
      _dateWindow = window;
    });
    await _loadMetrics();
  }

  void _goTo(int page) {
    if (page < 0 || page >= _titles.length || page == _page) return;
    setState(() => _page = page);
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1080;
        final viewportHeight = wide ? 650.0 : 1230.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DeckHeader(
              page: _page,
              pageCount: _titles.length,
              title: _titles[_page],
              subtitle: _subtitles[_page],
              periodLabel: _periodLabel,
              periodPreset: _periodPreset,
              showPeriod: _page > 0,
              onPeriodSelected: _selectPeriod,
              onPrevious: _page == 0 ? null : () => _goTo(_page - 1),
              onNext:
                  _page == _titles.length - 1 ? null : () => _goTo(_page + 1),
              onSelectPage: _goTo,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: viewportHeight,
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) {
                  if (_page != page) setState(() => _page = page);
                },
                children: [
                  const SingleChildScrollView(
                    physics: NeverScrollableScrollPhysics(),
                    child: AccountingDashboardSection(),
                  ),
                  _OperationalPageState(
                    loading: _loading,
                    error: _error,
                    onRetry: _loadMetrics,
                    child: _metrics == null
                        ? null
                        : _WorkshopFlowPage(
                            metrics: _metrics!,
                            wide: wide,
                          ),
                  ),
                  _OperationalPageState(
                    loading: _loading,
                    error: _error,
                    onRetry: _loadMetrics,
                    child: _metrics == null
                        ? null
                        : _CapacityAndServicePage(
                            metrics: _metrics!,
                            wide: wide,
                          ),
                  ),
                  _OperationalPageState(
                    loading: _loading,
                    error: _error,
                    onRetry: _loadMetrics,
                    child: _metrics == null
                        ? null
                        : _ProductsAndRotationPage(
                            metrics: _metrics!,
                            wide: wide,
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DeckHeader extends StatelessWidget {
  const _DeckHeader({
    required this.page,
    required this.pageCount,
    required this.title,
    required this.subtitle,
    required this.periodLabel,
    required this.periodPreset,
    required this.showPeriod,
    required this.onPeriodSelected,
    required this.onPrevious,
    required this.onNext,
    required this.onSelectPage,
  });

  final int page;
  final int pageCount;
  final String title;
  final String subtitle;
  final String periodLabel;
  final StrategicDashboardPeriodPreset periodPreset;
  final bool showPeriod;
  final ValueChanged<StrategicDashboardPeriodPreset> onPeriodSelected;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onSelectPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final navigation = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showPeriod) ...[
              _PeriodMenu(
                label: periodLabel,
                selected: periodPreset,
                onSelected: onPeriodSelected,
              ),
              const SizedBox(width: 12),
            ],
            _DeckArrow(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Panel anterior',
              onPressed: onPrevious,
            ),
            const SizedBox(width: 6),
            _DeckArrow(
              icon: Icons.arrow_forward_rounded,
              tooltip: 'Panel siguiente',
              onPressed: onNext,
            ),
          ],
        );

        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${(page + 1).toString().padLeft(2, '0')} / ${pageCount.toString().padLeft(2, '0')}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (compact) ...[
              heading,
              const SizedBox(height: 12),
              navigation,
            ] else
              Row(
                children: [
                  Expanded(child: heading),
                  navigation,
                ],
              ),
            const SizedBox(height: 13),
            Row(
              children: List.generate(pageCount, (index) {
                final selected = index == page;
                return Padding(
                  padding:
                      EdgeInsets.only(right: index == pageCount - 1 ? 0 : 6),
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: 'Panel ${index + 1}',
                    child: InkWell(
                      onTap: () => onSelectPage(index),
                      borderRadius: BorderRadius.circular(4),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: selected ? 42 : 24,
                        height: 3,
                        decoration: BoxDecoration(
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.dividerColor.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}

class _PeriodMenu extends StatelessWidget {
  const _PeriodMenu({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final StrategicDashboardPeriodPreset selected;
  final ValueChanged<StrategicDashboardPeriodPreset> onSelected;

  static const _presets = <StrategicDashboardPeriodPreset>[
    StrategicDashboardPeriodPreset.thisMonth,
    StrategicDashboardPeriodPreset.previousMonth,
    StrategicDashboardPeriodPreset.last30Days,
    StrategicDashboardPeriodPreset.last90Days,
    StrategicDashboardPeriodPreset.last12Months,
  ];

  String _labelFor(StrategicDashboardPeriodPreset preset) {
    switch (preset) {
      case StrategicDashboardPeriodPreset.thisMonth:
        return 'Este mes';
      case StrategicDashboardPeriodPreset.previousMonth:
        return 'Mes anterior';
      case StrategicDashboardPeriodPreset.last30Days:
        return 'Últimos 30 días';
      case StrategicDashboardPeriodPreset.last90Days:
        return 'Últimos 90 días';
      case StrategicDashboardPeriodPreset.last12Months:
        return 'Últimos 12 meses';
      case StrategicDashboardPeriodPreset.custom:
        return 'Rango personalizado';
    }
  }

  IconData _iconFor(StrategicDashboardPeriodPreset preset) {
    switch (preset) {
      case StrategicDashboardPeriodPreset.thisMonth:
        return Icons.calendar_today_outlined;
      case StrategicDashboardPeriodPreset.previousMonth:
        return Icons.history_rounded;
      case StrategicDashboardPeriodPreset.last30Days:
        return Icons.view_week_outlined;
      case StrategicDashboardPeriodPreset.last90Days:
        return Icons.date_range_outlined;
      case StrategicDashboardPeriodPreset.last12Months:
        return Icons.calendar_view_month_outlined;
      case StrategicDashboardPeriodPreset.custom:
        return Icons.edit_calendar_outlined;
    }
  }

  PopupMenuItem<StrategicDashboardPeriodPreset> _item(
    BuildContext context,
    StrategicDashboardPeriodPreset preset,
  ) {
    final theme = Theme.of(context);
    final isSelected = selected == preset;
    return PopupMenuItem<StrategicDashboardPeriodPreset>(
      value: preset,
      height: 48,
      child: Row(
        children: [
          Icon(
            _iconFor(preset),
            size: 18,
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _labelFor(preset),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: isSelected ? 1 : 0,
            child: Icon(
              Icons.check_rounded,
              size: 17,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<StrategicDashboardPeriodPreset>(
      tooltip: 'Cambiar período',
      initialValue: selected,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      elevation: 12,
      color: theme.colorScheme.surfaceContainerLowest,
      surfaceTintColor: theme.colorScheme.surfaceTint,
      constraints: const BoxConstraints(minWidth: 232, maxWidth: 260),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      clipBehavior: Clip.antiAlias,
      onSelected: onSelected,
      itemBuilder: (context) => [
        ..._presets.map((preset) => _item(context, preset)),
        const PopupMenuDivider(height: 9),
        _item(context, StrategicDashboardPeriodPreset.custom),
      ],
      child: Container(
        height: 38,
        constraints: const BoxConstraints(minWidth: 146, maxWidth: 210),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_outlined,
              size: 17,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.expand_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _DeckArrow extends StatelessWidget {
  const _DeckArrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 19),
      style: IconButton.styleFrom(
        minimumSize: const Size(38, 38),
        maximumSize: const Size(38, 38),
        padding: EdgeInsets.zero,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        disabledBackgroundColor:
            Theme.of(context).colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }
}

class _OperationalPageState extends StatelessWidget {
  const _OperationalPageState({
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.child,
  });

  final bool loading;
  final Object? error;
  final VoidCallback onRetry;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (loading && child == null) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 18),
              Text(
                'Calculando indicadores con datos operacionales…',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }
    if (error != null && child == null) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Row(
            children: [
              Icon(
                Icons.sync_problem_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'No se pudieron cargar los indicadores estratégicos.',
                ),
              ),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        if (child != null) child!,
        if (loading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class _WorkshopFlowPage extends StatelessWidget {
  const _WorkshopFlowPage({required this.metrics, required this.wide});

  final StrategicDashboardMetrics metrics;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[
      Expanded(
        flex: 7,
        child: _FlowCycleCard(metrics: metrics),
      ),
      if (wide) const SizedBox(width: 16) else const SizedBox(height: 16),
      Expanded(
        flex: 4,
        child: _CurrentLoadCard(metrics: metrics),
      ),
    ];

    return wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: content)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: content);
  }
}

class _FlowCycleCard extends StatelessWidget {
  const _FlowCycleCard({required this.metrics});

  final StrategicDashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final flow = metrics.flow;
    final theme = Theme.of(context);
    final steps = [
      (
        label: 'Aprobación',
        value: _duration(flow.approvalMedianHours),
        sample: flow.approvalSamples,
        icon: Icons.fact_check_outlined,
      ),
      (
        label: 'Espera a taller',
        value: _duration(flow.startMedianHours),
        sample: flow.startSamples,
        icon: Icons.schedule_outlined,
      ),
      (
        label: 'Ejecución',
        value: _duration(flow.executionMedianHours),
        sample: flow.executionSamples,
        icon: Icons.build_outlined,
      ),
      (
        label: 'Ciclo total',
        value: _duration(flow.totalMedianHours),
        sample: flow.totalSamples,
        icon: Icons.outbox_outlined,
      ),
    ];

    return _DashboardCard(
      title: 'Ciclo del trabajo',
      subtitle: 'Mediana del período · los tiempos de espera sí cuentan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(steps.length, (index) {
              final step = steps[index];
              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (index > 0)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.22),
                            ),
                          ),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.10),
                          ),
                          child: Icon(
                            step.icon,
                            size: 17,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        if (index < steps.length - 1)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.22),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Text(
                      step.value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      step.label,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.sample == 0 ? 'sin muestra aún' : 'n=${step.sample}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 30),
          Divider(color: theme.dividerColor.withValues(alpha: 0.45)),
          const SizedBox(height: 14),
          Text(
            'Entregas por semana',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _WeeklyDeliveryChart(points: metrics.weekly)),
        ],
      ),
    );
  }
}

class _WeeklyDeliveryChart extends StatelessWidget {
  const _WeeklyDeliveryChart({required this.points});

  final List<StrategicWeeklyPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxY = math
        .max(
          2,
          points.fold<int>(0,
                  (maxValue, point) => math.max(maxValue, point.deliveries)) +
              1,
        )
        .toDouble();

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: math.max(1, (maxY / 3).ceilToDouble()),
          getDrawingHorizontalLine: (_) => FlLine(
            color: theme.dividerColor.withValues(alpha: 0.28),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                final date = points[index].start;
                return Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    date == null
                        ? ''
                        : DateFormat('d MMM', 'es_CL').format(date),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: theme.colorScheme.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${rod.toY.round()} entregas',
                TextStyle(color: theme.colorScheme.onInverseSurface),
              );
            },
          ),
        ),
        barGroups: List.generate(points.length, (index) {
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: points[index].deliveries.toDouble(),
                width: 18,
                color: theme.colorScheme.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(5)),
              ),
            ],
          );
        }),
      ),
      swapAnimationDuration: const Duration(milliseconds: 650),
      swapAnimationCurve: Curves.easeOutCubic,
    );
  }
}

class _CurrentLoadCard extends StatelessWidget {
  const _CurrentLoadCard({required this.metrics});

  final StrategicDashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final load = metrics.load;
    final maxBucket = math.max(
      1,
      load.ageBuckets
          .fold<int>(0, (value, bucket) => math.max(value, bucket.count)),
    );

    return _DashboardCard(
      title: 'Carga actual',
      subtitle: 'Trabajos abiertos a esta hora',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${load.activeCount}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('activos', style: theme.textTheme.bodyMedium),
              ),
              const Spacer(),
              if (load.overdueCount > 0)
                Text(
                  '${load.overdueCount} fuera de fecha',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          ...load.ageBuckets.map((bucket) {
            final ratio = bucket.count / maxBucket;
            return Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(bucket.label)),
                      Text(
                        '${bucket.count}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 5,
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
            );
          }),
          const Spacer(),
          Divider(color: theme.dividerColor.withValues(alpha: 0.45)),
          const SizedBox(height: 12),
          _RateLine(
            label: 'Entregas a tiempo',
            value: metrics.flow.onTimeRate,
            sample: metrics.flow.onTimeSamples,
          ),
          const SizedBox(height: 12),
          _RateLine(
            label: 'Presupuestos aprobados',
            value: metrics.flow.approvalRate,
            sample: metrics.flow.decisionSamples,
          ),
        ],
      ),
    );
  }
}

class _RateLine extends StatelessWidget {
  const _RateLine(
      {required this.label, required this.value, required this.sample});

  final String label;
  final double? value;
  final int sample;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value == null ? '—' : _percent(value),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(width: 8),
        Text(
          sample == 0 ? 'sin muestra' : 'n=$sample',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _CapacityAndServicePage extends StatelessWidget {
  const _CapacityAndServicePage({required this.metrics, required this.wide});

  final StrategicDashboardMetrics metrics;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Expanded(flex: 6, child: _CapacityCard(metrics: metrics)),
      if (wide) const SizedBox(width: 16) else const SizedBox(height: 16),
      Expanded(flex: 5, child: _ServiceEconomicsCard(metrics: metrics)),
    ];
    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _CapacityCard extends StatelessWidget {
  const _CapacityCard({required this.metrics});

  final StrategicDashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final value = metrics.value;
    final theme = Theme.of(context);
    final maxHours = math.max(
      1.0,
      math.max(value.businessOpenHours, value.mechanicAttendanceHours),
    );
    final actualCoverage = value.laborHourCoverageRate ?? 0;

    return _DashboardCard(
      title: 'Capacidad del taller',
      subtitle: 'Horas de reloj y horas-persona no son lo mismo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 22),
          _CapacityBar(
            icon: Icons.storefront_outlined,
            label: 'Negocio abierto',
            value: value.businessOpenHours,
            max: maxHours,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 20),
          _CapacityBar(
            icon: Icons.badge_outlined,
            label: 'Asistencia mecánicos',
            value: value.mechanicAttendanceHours,
            max: maxHours,
            color: const Color(0xFF00897B),
          ),
          const SizedBox(height: 20),
          _CapacityBar(
            icon: Icons.handyman_outlined,
            label: 'Imputadas a trabajos',
            value: value.actualHours,
            max: maxHours,
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 28),
          Divider(color: theme.dividerColor.withValues(alpha: 0.45)),
          const SizedBox(height: 14),
          _MetricSentence(
            leading: value.mechanicEquivalentCoverage == null
                ? '—'
                : '${value.mechanicEquivalentCoverage!.toStringAsFixed(1)}×',
            title: 'cobertura mecánica equivalente',
            detail:
                '${value.mechanicCount} mecánicos activos · presencia / horario abierto',
          ),
          const SizedBox(height: 16),
          _MetricSentence(
            leading: value.productiveUtilizationRate == null
                ? '—'
                : _percent(value.productiveUtilizationRate),
            title: 'utilización productiva registrada',
            detail: actualCoverage == 0
                ? 'Comienza al guardar horas reales en cada trabajo.'
                : 'Cobertura de horas en ${_percent(actualCoverage)} de las facturas de taller.',
          ),
          const Spacer(),
          _QuietNotice(
            icon: Icons.info_outline,
            text: (value.jobAssignmentCoverageRate ?? 0) == 0
                ? 'La lectura es del equipo completo: los trabajos históricos no tienen mecánico asignado.'
                : 'Asignación a mecánico en ${_percent(value.jobAssignmentCoverageRate)} de los trabajos nuevos.',
          ),
        ],
      ),
    );
  }
}

class _CapacityBar extends StatelessWidget {
  const _CapacityBar({
    required this.icon,
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });

  final IconData icon;
  final String label;
  final double value;
  final double max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 10),
        SizedBox(width: 154, child: Text(label)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: (value / max).clamp(0, 1),
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.10),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 68,
          child: Text(
            '${value.toStringAsFixed(1)} h',
            textAlign: TextAlign.end,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceEconomicsCard extends StatelessWidget {
  const _ServiceEconomicsCard({required this.metrics});

  final StrategicDashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final value = metrics.value;
    final theme = Theme.of(context);
    final contributionPositive = value.laborContribution >= 0;
    final sourceLabel = switch (value.mechanicCostSource) {
      'paid_and_pending_payroll' => 'nómina pagada + período pendiente',
      'pending_payroll' => 'nómina pendiente',
      'paid_payroll' => 'nómina pagada',
      _ => 'asistencia × tarifa configurada',
    };

    return _DashboardCard(
      title: 'Economía del servicio',
      subtitle: 'Sólo mano de obra del taller',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'Contribución de mano de obra',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _clp(value.laborContribution),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: contributionPositive
                  ? const Color(0xFF2E7D32)
                  : theme.colorScheme.error,
            ),
          ),
          Text(
            value.laborContributionRate == null
                ? 'Sin ventas de servicio en el período'
                : '${_percent(value.laborContributionRate)} sobre la venta de servicios',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 26),
          _MoneyComparison(
            serviceSales: value.workshopServiceSales,
            mechanicCost: value.mechanicCostUsed,
          ),
          const SizedBox(height: 24),
          Divider(color: theme.dividerColor.withValues(alpha: 0.45)),
          const SizedBox(height: 14),
          _MetricSentence(
            leading: value.serviceSalesPerAttendanceHour == null
                ? '—'
                : _clp(value.serviceSalesPerAttendanceHour!),
            title: 'servicio vendido por hora asistida',
            detail:
                '${value.mechanicAttendanceHours.toStringAsFixed(1)} h de asistencia mecánica',
          ),
          const SizedBox(height: 15),
          _MetricSentence(
            leading: value.netSalesPerLaborHour == null
                ? '—'
                : _clp(value.netSalesPerLaborHour!),
            title: 'ticket de taller por hora imputada',
            detail: value.actualHoursJobs == 0
                ? 'Aún no hay trabajos con horas reales.'
                : '${value.actualHoursJobs} trabajos con registro de horas',
          ),
          const Spacer(),
          _QuietNotice(
            icon: Icons.receipt_long_outlined,
            text:
                'Costo usado: $sourceLabel. No incluye repuestos, IVA ni gastos generales.',
          ),
        ],
      ),
    );
  }
}

class _MoneyComparison extends StatelessWidget {
  const _MoneyComparison(
      {required this.serviceSales, required this.mechanicCost});

  final double serviceSales;
  final double mechanicCost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxValue = math.max(1.0, math.max(serviceSales, mechanicCost));
    return Column(
      children: [
        _MoneyBar(
          label: 'Servicios vendidos',
          amount: serviceSales,
          ratio: serviceSales / maxValue,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 14),
        _MoneyBar(
          label: 'Costo mecánicos',
          amount: mechanicCost,
          ratio: mechanicCost / maxValue,
          color: const Color(0xFFF59E0B),
        ),
      ],
    );
  }
}

class _MoneyBar extends StatelessWidget {
  const _MoneyBar({
    required this.label,
    required this.amount,
    required this.ratio,
    required this.color,
  });

  final String label;
  final double amount;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              _clp(amount),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1),
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: 0.10),
          ),
        ),
      ],
    );
  }
}

class _ProductsAndRotationPage extends StatelessWidget {
  const _ProductsAndRotationPage({required this.metrics, required this.wide});

  final StrategicDashboardMetrics metrics;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Expanded(flex: 5, child: _SalesMixCard(metrics: metrics)),
      if (wide) const SizedBox(width: 16) else const SizedBox(height: 16),
      Expanded(flex: 6, child: _InventoryRotationCard(metrics: metrics)),
    ];
    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _SalesMixCard extends StatelessWidget {
  const _SalesMixCard({required this.metrics});

  final StrategicDashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final value = metrics.value;
    final theme = Theme.of(context);
    final total =
        value.productSales + value.serviceSales + value.unclassifiedSales;
    const productColor = Color(0xFF1976D2);
    const serviceColor = Color(0xFF00897B);
    const unclassifiedColor = Color(0xFF90A4AE);

    return _DashboardCard(
      title: 'Entrada por tipo',
      subtitle:
          'Venta neta · ${_percent(value.classificationCoverageRate)} clasificada',
      child: Column(
        children: [
          const SizedBox(height: 18),
          SizedBox(
            height: 210,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    centerSpaceRadius: 67,
                    sectionsSpace: 3,
                    startDegreeOffset: -90,
                    sections: total <= 0
                        ? [
                            PieChartSectionData(
                              value: 1,
                              color: theme.dividerColor.withValues(alpha: 0.25),
                              radius: 28,
                              showTitle: false,
                            ),
                          ]
                        : [
                            PieChartSectionData(
                              value: value.productSales,
                              color: productColor,
                              radius: 28,
                              showTitle: false,
                            ),
                            PieChartSectionData(
                              value: value.serviceSales,
                              color: serviceColor,
                              radius: 28,
                              showTitle: false,
                            ),
                            if (value.unclassifiedSales > 0)
                              PieChartSectionData(
                                value: value.unclassifiedSales,
                                color: unclassifiedColor,
                                radius: 28,
                                showTitle: false,
                              ),
                          ],
                  ),
                  swapAnimationDuration: const Duration(milliseconds: 650),
                  swapAnimationCurve: Curves.easeOutCubic,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('VENTA NETA', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 3),
                    Text(
                      _clp(total),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _LegendAmount(
            color: productColor,
            label: 'Productos, repuestos y accesorios',
            amount: value.productSales,
            share: value.productSalesShare,
          ),
          const SizedBox(height: 13),
          _LegendAmount(
            color: serviceColor,
            label: 'Servicios',
            amount: value.serviceSales,
            share: value.serviceSalesShare,
          ),
          if (value.unclassifiedSales > 0) ...[
            const SizedBox(height: 13),
            _LegendAmount(
              color: unclassifiedColor,
              label: 'Sin clasificar',
              amount: value.unclassifiedSales,
              share: value.unclassifiedSalesShare,
            ),
          ],
          const SizedBox(height: 16),
          Divider(color: theme.dividerColor.withValues(alpha: 0.45)),
          const SizedBox(height: 13),
          _MetricSentence(
            leading: value.productGrossMarginRate == null
                ? '—'
                : _percent(value.productGrossMarginRate),
            title: 'margen bruto conocido de productos',
            detail:
                '${_clp(value.productGrossContribution)} · costo respaldado en ${_percent(value.productCostCoverageRate)} de la venta',
          ),
          const Spacer(),
          const _QuietNotice(
            icon: Icons.inventory_2_outlined,
            text:
                'El margen usa el costo histórico de cada producto. Las líneas ambiguas permanecen visibles y no se atribuyen a productos ni servicios.',
          ),
        ],
      ),
    );
  }
}

class _LegendAmount extends StatelessWidget {
  const _LegendAmount({
    required this.color,
    required this.label,
    required this.amount,
    required this.share,
  });

  final Color color;
  final String label;
  final double amount;
  final double? share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(label)),
        Text(
          _clp(amount),
          style:
              theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 42,
          child: Text(
            share == null ? '—' : _percent(share),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _InventoryRotationCard extends StatelessWidget {
  const _InventoryRotationCard({required this.metrics});

  final StrategicDashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final inventory = metrics.inventory;
    final theme = Theme.of(context);
    final maxUnits = math.max(
      1.0,
      inventory.topProducts.fold<double>(
        0,
        (value, product) => math.max(value, product.units),
      ),
    );

    return _DashboardCard(
      title: 'Rotación de inventario',
      subtitle: 'Salida real en facturas del período',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MetricSentence(
                  leading: inventory.stockCoverDays == null
                      ? '—'
                      : '${inventory.stockCoverDays!.round()} d',
                  title: 'cobertura del stock que sí rota',
                  detail:
                      '${inventory.unitsSold.toStringAsFixed(0)} unidades vendidas',
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _MetricSentence(
                  leading: _clp(inventory.stagnantStockValue),
                  title: 'stock sin salida',
                  detail:
                      '${inventory.stagnantProductCount} productos en el período',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: theme.dividerColor.withValues(alpha: 0.45)),
          const SizedBox(height: 14),
          Text(
            'Mayor movimiento',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 13),
          if (inventory.topProducts.isEmpty)
            Text(
              'No hay productos vendidos en este período.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...inventory.topProducts.map((product) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${product.units.toStringAsFixed(0)} u',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 88,
                          child: Text(
                            _clp(product.sales),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (product.units / maxUnits).clamp(0, 1),
                        minHeight: 6,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
              );
            }),
          const Spacer(),
          const _QuietNotice(
            icon: Icons.query_stats_outlined,
            text:
                'Cobertura = stock actual / ritmo diario del período. No se presenta como rotación contable porque aún no hay inventario promedio histórico.',
          ),
        ],
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _MetricSentence extends StatelessWidget {
  const _MetricSentence({
    required this.leading,
    required this.title,
    required this.detail,
  });

  final String leading;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          leading,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.labelLarge),
              const SizedBox(height: 2),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuietNotice extends StatelessWidget {
  const _QuietNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _duration(double? hours) {
  if (hours == null || hours.isNaN || hours.isInfinite) return '—';
  if (hours < 1) return '${math.max(1, (hours * 60).round())} min';
  if (hours < 24) return '${hours.toStringAsFixed(hours < 10 ? 1 : 0)} h';
  final days = hours / 24;
  return '${days.toStringAsFixed(days < 10 ? 1 : 0)} d';
}

String _clp(double value) {
  return NumberFormat.currency(
    locale: 'es_CL',
    symbol: r'$',
    decimalDigits: 0,
  ).format(value.round());
}

String _percent(double? value) {
  if (value == null || value.isNaN || value.isInfinite) return '—';
  return '${(value * 100).round()}%';
}
